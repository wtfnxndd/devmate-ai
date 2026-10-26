// DevMate AI for VS Code — a thin client over the DevMate FastAPI backend.
const vscode = require("vscode");
const path = require("path");

const SEVERITY = {
  high: vscode.DiagnosticSeverity.Error,
  medium: vscode.DiagnosticSeverity.Warning,
  low: vscode.DiagnosticSeverity.Information,
};
const RANK = { low: 0, medium: 1, high: 2 };

let diagnostics;
let status;
// workspace folder path -> DevMate project id
const projects = new Map();

function apiUrl() {
  return vscode.workspace.getConfiguration("devmate").get("apiUrl").replace(/\/$/, "");
}

async function api(method, route, body) {
  let res;
  try {
    res = await fetch(`${apiUrl()}/api${route}`, {
      method,
      headers: { "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new Error(`Cannot reach the DevMate backend at ${apiUrl()}. Start it with start.sh.`);
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || `HTTP ${res.status}`);
  return data;
}

function workspaceRoot() {
  const doc = vscode.window.activeTextEditor?.document;
  const folder = (doc && vscode.workspace.getWorkspaceFolder(doc.uri)) || vscode.workspace.workspaceFolders?.[0];
  if (!folder) throw new Error("Open a folder first.");
  return folder.uri.fsPath;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Imports the workspace into DevMate (once per session) and waits until analysis is ready. */
async function ensureProject(root, { force = false } = {}) {
  let id = projects.get(root);
  if (id && !force) return id;
  return vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: "DevMate", cancellable: false },
    async (progress) => {
      if (id) await api("POST", `/projects/${id}/reanalyze`);
      else {
        id = (await api("POST", "/projects/local", { path: root })).id;
        projects.set(root, id);
      }
      for (let i = 0; i < 300; i++) {
        const p = await api("GET", `/projects/${id}`);
        progress.report({ message: `${p.status}…` });
        if (p.status === "ready") return id;
        if (p.status.startsWith("error")) throw new Error(p.error || p.status);
        await sleep(2000);
      }
      throw new Error("Analysis timed out.");
    }
  );
}

async function analyze() {
  const root = workspaceRoot();
  const id = await ensureProject(root, { force: projects.has(root) });
  const analysis = await api("GET", `/projects/${id}/analysis`);
  const min = RANK[vscode.workspace.getConfiguration("devmate").get("minSeverity")] ?? 0;

  diagnostics.clear();
  const byFile = new Map();
  for (const f of analysis.findings) {
    if ((RANK[f.severity] ?? 0) < min) continue;
    const line = Math.max(0, f.line - 1);
    const d = new vscode.Diagnostic(new vscode.Range(line, 0, line, 1000), `${f.rule}: ${f.message}`, SEVERITY[f.severity]);
    d.source = `DevMate (${f.tool})`;
    const file = path.join(root, f.file);
    if (!byFile.has(file)) byFile.set(file, []);
    byFile.get(file).push(d);
  }
  for (const [file, list] of byFile) diagnostics.set(vscode.Uri.file(file), list);

  status.text = `$(shield) DevMate ${analysis.health_score}/100 (${analysis.grade})`;
  status.tooltip = `High ${analysis.counts.high} · Medium ${analysis.counts.medium} · Low ${analysis.counts.low}`;
  status.show();
  vscode.window.showInformationMessage(
    `DevMate: health ${analysis.health_score}/100 — ${analysis.findings.length} findings in the Problems panel.`
  );
}

/** Shows Markdown returned by an engine in a side preview. */
async function showMarkdown(title, result) {
  const header = result.ai ? "" : "> Static-only output (no LLM key configured on the backend).\n\n";
  const doc = await vscode.workspace.openTextDocument({ language: "markdown", content: `# ${title}\n\n${header}${result.markdown}` });
  await vscode.window.showTextDocument(doc, vscode.ViewColumn.Beside, true);
  await vscode.commands.executeCommand("markdown.showPreview", doc.uri);
}

async function explainError() {
  const editor = vscode.window.activeTextEditor;
  let error = editor && !editor.selection.isEmpty ? editor.document.getText(editor.selection) : "";
  if (!error) error = await vscode.window.showInputBox({ prompt: "Paste the error message or stack trace" });
  if (!error) return;
  const id = await ensureProject(workspaceRoot());
  const result = await withSpinner("Debugging…", () => api("POST", `/projects/${id}/debug`, { error }));
  await showMarkdown("Error explanation", result);
}

async function generateTests() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) throw new Error("Open a source file first.");
  const root = workspaceRoot();
  const rel = path.relative(root, editor.document.uri.fsPath).split(path.sep).join("/");
  const id = await ensureProject(root);
  const result = await withSpinner(`Generating tests for ${rel}…`, () => api("POST", `/projects/${id}/tests`, { file: rel }));
  await showMarkdown(`Tests for ${rel}`, result);
}

async function ask() {
  const message = await vscode.window.showInputBox({ prompt: "Ask DevMate about this codebase" });
  if (!message) return;
  const id = await ensureProject(workspaceRoot());
  const result = await withSpinner("Thinking…", () => api("POST", `/projects/${id}/chat`, { message }));
  const sources = (result.sources || []).map((s) => `- \`${s.file}:${s.start}-${s.end}\``).join("\n");
  await showMarkdown(message, { ...result, markdown: `${result.markdown}\n\n---\n**Sources**\n${sources}` });
}

async function engine(route, title) {
  const id = await ensureProject(workspaceRoot());
  const result = await withSpinner(`${title}…`, () => api("POST", `/projects/${id}/${route}`));
  await showMarkdown(title, result);
}

function withSpinner(title, fn) {
  return vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: `DevMate: ${title}` }, fn);
}

function command(fn) {
  return async (...args) => {
    try {
      await fn(...args);
    } catch (e) {
      vscode.window.showErrorMessage(`DevMate: ${e.message}`);
    }
  };
}

function activate(context) {
  diagnostics = vscode.languages.createDiagnosticCollection("devmate");
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  status.command = "devmate.analyze";
  status.text = "$(shield) DevMate";
  status.show();
  context.subscriptions.push(
    diagnostics,
    status,
    vscode.commands.registerCommand("devmate.analyze", command(analyze)),
    vscode.commands.registerCommand("devmate.explainError", command(explainError)),
    vscode.commands.registerCommand("devmate.generateTests", command(generateTests)),
    vscode.commands.registerCommand("devmate.ask", command(ask)),
    vscode.commands.registerCommand("devmate.review", command(() => engine("review", "AI code review"))),
    vscode.commands.registerCommand("devmate.readme", command(() => engine("readme", "README")))
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
