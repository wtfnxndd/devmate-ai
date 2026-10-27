"""Phases 2–4: AI review, documentation, test generation, debugging, chat and health report.

Every engine works without an LLM (static, template-based output) and gets richer when a free
Gemini/Groq key is configured.
"""
import re
from pathlib import Path

from . import llm, rag

NO_LLM_NOTE = "> ℹ️ Static-only output. Add a free `GEMINI_API_KEY` or `GROQ_API_KEY` in `backend/.env` for AI explanations.\n\n"

ENDPOINT_PATTERNS = [
    ("FastAPI/Flask", re.compile(r"""@\w+\.(get|post|put|delete|patch|route)\(\s*['"]([^'"]+)['"]""", re.I)),
    ("Express", re.compile(r"""\b(?:app|router)\.(get|post|put|delete|patch)\(\s*['"`]([^'"`]+)['"`]""")),
    ("Spring", re.compile(r"""@(Get|Post|Put|Delete|Patch|Request)Mapping\(\s*(?:value\s*=\s*)?['"]([^'"]+)['"]""")),
    ("Django", re.compile(r"""\b(?:re_)?path\(\s*r?['"]([^'"]*)['"]\s*,\s*([\w.]+)""")),
]

TEST_FRAMEWORK = {"python": "pytest", "javascript": "Jest", "typescript": "Jest", "tsx": "Jest + React Testing Library",
                  "java": "JUnit 5", "go": "Go testing package", "rust": "Rust #[test]", "dart": "flutter_test",
                  "kotlin": "JUnit 5", "c_sharp": "xUnit", "php": "PHPUnit", "ruby": "RSpec", "cpp": "GoogleTest"}


def _try_llm(prompt, fallback, **kw):
    try:
        return llm.ask(prompt, **kw), True
    except llm.NoLLMAvailable as e:
        return (NO_LLM_NOTE if "No LLM" in str(e) else f"> ⚠️ {e}\n\n") + fallback, False


def _snippet(root: Path, rel: str, line: int, radius: int = 6) -> str:
    try:
        lines = (root / rel).read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return ""
    lo, hi = max(1, line - radius), min(len(lines), line + radius)
    return "\n".join(f"{n:>5} | {lines[n - 1]}" for n in range(lo, hi + 1))


# ---------------------------------------------------------------- Review
def review(root: Path, analysis: dict, limit: int = 12) -> dict:
    top = [f for f in analysis["findings"] if f["severity"] in ("high", "medium")][:limit]
    blocks = [f"### {i}. [{f['severity'].upper()}] {f['rule']} — `{f['file']}:{f['line']}`\n{f['message']}\n"
              f"```\n{_snippet(root, f['file'], f['line'])}\n```" for i, f in enumerate(top, 1)]
    static_md = "\n\n".join(blocks) or "No high or medium severity issues found. 🎉"
    if not top:
        return {"markdown": static_md, "ai": False}
    prompt = (
        "Review these issues found by static analysis in a code project. For EACH issue: explain why it is a "
        "problem (mention the OWASP Top 10 category for security issues), rate if it is a true or likely false "
        "positive, and give a corrected code snippet. Finish with a short 'Top 3 priorities' list.\n\n" + static_md
    )
    md, ai = _try_llm(prompt, static_md)
    return {"markdown": md, "ai": ai, "issues_reviewed": len(top)}


# ---------------------------------------------------------------- Documentation
def find_endpoints(root: Path, structure: dict) -> list:
    eps = []
    for rel in structure["files"]:
        try:
            text = (root / rel).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        seen_lines = set()
        for fw, rx in ENDPOINT_PATTERNS:
            for m in rx.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                if line in seen_lines:  # e.g. "@app.get(" matches both the FastAPI and Express patterns
                    continue
                seen_lines.add(line)
                if fw == "Django":
                    eps.append({"framework": fw, "method": "ANY", "path": "/" + m.group(1), "file": rel, "line": line})
                else:
                    eps.append({"framework": fw, "method": m.group(1).upper().replace("ROUTE", "ANY").replace("REQUEST", "ANY"),
                                "path": m.group(2), "file": rel, "line": line})
    return eps


def _structure_brief(structure: dict, max_files: int = 40) -> str:
    s = structure["summary"]
    out = [f"Files: {s['files']}, lines: {s['lines']}, languages: {s['languages']}",
           "Folder tree:\n" + structure["tree"][:4000], "Key symbols per file:"]
    ranked = sorted(structure["files"].items(), key=lambda kv: -(len(kv[1]["functions"]) + len(kv[1]["classes"])))
    for rel, info in ranked[:max_files]:
        cls = ", ".join(c["name"] for c in info["classes"][:8])
        fns = ", ".join(f["name"] + f["params"][:60] for f in info["functions"][:12])
        out.append(f"- {rel}: classes[{cls}] functions[{fns}]")
    return "\n".join(out)


def _readme_files(root: Path) -> str:
    for name in ("package.json", "pyproject.toml", "requirements.txt", "pubspec.yaml", "pom.xml", "go.mod", "Cargo.toml"):
        p = next(iter(root.rglob(name)), None)
        if p and p.stat().st_size < 20000:
            return f"{name}:\n{p.read_text(errors='replace')[:3000]}"
    return ""


def readme(root: Path, name: str, structure: dict, endpoints: list) -> dict:
    s = structure["summary"]
    ep_table = "\n".join(f"| {e['method']} | `{e['path']}` | `{e['file']}:{e['line']}` |" for e in endpoints[:60])
    fallback = (
        f"# {name}\n\n## Overview\n{s['files']} source files, {s['lines']} lines "
        f"({', '.join(f'{k}: {v}' for k, v in s['languages'].items())}).\n\n"
        f"## Project structure\n```\n{structure['tree'][:5000]}\n```\n\n"
        f"## Architecture\n```mermaid\n{structure['mermaid']}\n```\n\n"
        + (f"## API endpoints\n| Method | Path | Location |\n|---|---|---|\n{ep_table}\n\n" if endpoints else "")
        + "## Getting started\n_TODO: installation and run instructions._\n"
    )
    prompt = (
        f"Write a complete, professional README.md for the project '{name}'. Include: title + one-paragraph "
        "description (infer purpose from the code), features, tech stack, project structure, setup/installation, "
        "usage, API endpoints table (if any), architecture section that embeds the given Mermaid diagram in a "
        "```mermaid block, testing, and contributing.\n\n"
        f"{_structure_brief(structure)}\n\nManifest:\n{_readme_files(root)}\n\n"
        f"Endpoints:\n{ep_table or 'none'}\n\nMermaid dependency diagram:\n{structure['mermaid'][:3000]}"
    )
    md, ai = _try_llm(prompt, fallback)
    return {"markdown": md, "ai": ai}


def api_docs(root: Path, endpoints: list) -> dict:
    if not endpoints:
        return {"markdown": "No HTTP endpoints detected (FastAPI, Flask, Express, Spring and Django are supported).", "ai": False}
    sections = []
    for e in endpoints[:40]:
        sections.append(f"#### {e['method']} {e['path']}  (`{e['file']}:{e['line']}`)\n```\n{_snippet(root, e['file'], e['line'], 12)}\n```")
    static_md = "# API Reference\n\n" + "\n\n".join(sections)
    prompt = ("Generate API reference documentation from these endpoint handlers. For each: purpose, path/query/body "
              "parameters with types, response shape, status codes, and an example curl request.\n\n" + static_md)
    md, ai = _try_llm(prompt, static_md)
    return {"markdown": md, "ai": ai, "endpoints": endpoints}


# ---------------------------------------------------------------- Tests
def generate_tests(root: Path, structure: dict, rel: str) -> dict:
    info = structure["files"].get(rel)
    if not info:
        raise ValueError(f"Unknown file: {rel}")
    code = (root / rel).read_text(encoding="utf-8")
    fw = TEST_FRAMEWORK.get(info["language"], "the standard test framework")
    funcs = [f for f in info["functions"] if not f["name"].split(".")[-1].startswith("_")] or info["functions"]
    if info["language"] == "python":
        mod = rel[:-3].replace("/", ".")
        skel = [f"import pytest\nfrom {mod} import *  # noqa\n"]
        for f in funcs:
            n = f["name"].replace(".", "_")
            skel.append(f"def test_{n}_happy_path():\n    # TODO: call {f['name']}{f['params']} with valid input\n    ...\n\n"
                        f"def test_{n}_edge_cases():\n    # TODO: empty / None / boundary values\n    ...\n")
        fallback = "```python\n" + "\n".join(skel) + "```"
    else:
        fallback = "Functions to cover:\n" + "\n".join(f"- `{f['name']}{f['params']}` — happy path, edge cases, error handling" for f in funcs)
    prompt = (f"Write a complete {fw} unit test file for `{rel}`. Cover every public function/method with a happy path, "
              "edge cases (empty, None/null, boundaries, large input) and error handling; mock I/O, network and DB. "
              "After the code, list additional integration tests worth adding.\n\n"
              f"```{info['language']}\n{code[:24000]}\n```")
    md, ai = _try_llm(prompt, fallback)
    return {"markdown": md, "ai": ai, "framework": fw, "functions": len(funcs)}


# ---------------------------------------------------------------- Debugging
TRACE_PATTERNS = [
    re.compile(r'File "([^"]+)", line (\d+)'),                     # Python
    re.compile(r"at .*?\(?([\w./\\-]+\.(?:js|ts|tsx|jsx|mjs)):(\d+):\d+"),  # Node
    re.compile(r"at [\w.$]+\((\w+\.(?:java|kt)):(\d+)\)"),          # Java/Kotlin
    re.compile(r"([\w./-]+\.(?:go|rs|dart|cpp|c|cs|rb|php|swift)):(\d+)"),
]


def _locate(structure: dict, path: str):
    path = path.replace("\\", "/")
    for rel in structure["files"]:
        if path.endswith(rel) or rel.endswith(path.lstrip("./")) or Path(rel).name == Path(path).name:
            return rel
    return None


def debug(project_id: int, root: Path, structure: dict, error_text: str) -> dict:
    frames = []
    for rx in TRACE_PATTERNS:
        for m in rx.finditer(error_text):
            rel = _locate(structure, m.group(1))
            if rel and (rel, int(m.group(2))) not in [(f["file"], f["line"]) for f in frames]:
                frames.append({"file": rel, "line": int(m.group(2))})
    frames = frames[-5:]  # innermost frames are the most relevant
    snippets = "\n\n".join(f"--- {f['file']}:{f['line']} ---\n{_snippet(root, f['file'], f['line'], 10)}" for f in frames)
    hits = rag.search(project_id, error_text[-1500:], k=4)
    last_line = error_text.strip().splitlines()[-1] if error_text.strip() else ""
    fallback = (f"**Error:** `{last_line}`\n\n" + (f"**Stack frames in your project:**\n```\n{snippets}\n```\n\n" if frames else
                "No stack frames matched project files.\n\n") + "**Related code (RAG):**\n" +
                "\n".join(f"- `{h['file']}:{h['start']}` {h['symbol']} (similarity {h['score']})" for h in hits))
    prompt = ("Debug this error. Explain the root cause in plain language, point to the exact file/line, give the fix "
              "as a code diff, and suggest how to prevent it (test or guard).\n\n"
              f"Error / stack trace:\n```\n{error_text[-6000:]}\n```\n\nCode at stack frames:\n```\n{snippets}\n```\n\n"
              f"Related project code:\n{rag.format_context(hits)[:8000]}")
    md, ai = _try_llm(prompt, fallback, use_cache=False)
    return {"markdown": md, "ai": ai, "frames": frames}


# ---------------------------------------------------------------- Chat
def chat(project_id: int, question: str, history: list) -> dict:
    hits = rag.search(project_id, question)
    context = rag.format_context(hits)
    prompt = f"Project code relevant to the question:\n{context[:12000]}\n\nQuestion: {question}"
    fallback = "**Most relevant code for your question:**\n\n" + "\n\n".join(
        f"`{h['file']}` lines {h['start']}-{h['end']} (similarity {h['score']})\n```\n{h['text'][:800]}\n```" for h in hits)
    md, ai = _try_llm(prompt, fallback, use_cache=False, history=history[-10:])
    return {"markdown": md, "ai": ai, "sources": [{k: h[k] for k in ("file", "start", "end", "score")} for h in hits]}


# ---------------------------------------------------------------- Report
def health_report(name: str, structure: dict, analysis: dict, deps: dict | None = None) -> dict:
    s, a = structure["summary"], analysis
    lines = [
        f"# Project Health Report — {name}", "",
        f"**Health score:** {a['health_score']}/100 (grade **{a['grade']}**)", "",
        "| Metric | Value |", "|---|---|",
        f"| Files | {s['files']} |", f"| Lines of code | {s['lines']} |",
        f"| Classes / Functions | {s['classes']} / {s['functions']} |",
        f"| Avg cyclomatic complexity | {a['avg_complexity']} |",
        f"| Issues (high / medium / low) | {a['counts']['high']} / {a['counts']['medium']} / {a['counts']['low']} |",
        f"| Security / Bugs / Smells | {a['by_category']['security']} / {a['by_category']['bug']} / {a['by_category']['smell']} |",
        f"| Tools used | {', '.join(a['tools'])} |", "",
        "## Most complex functions", "| Function | File | Complexity |", "|---|---|---|",
        *[f"| `{f['function']}` | `{f['file']}:{f['line']}` | {f['complexity']} |" for f in a["complex_functions"][:10]],
        "", "## Top issues",
        *[f"- **[{f['severity']}]** `{f['file']}:{f['line']}` {f['rule']} — {f['message']}" for f in a["findings"][:15]],
        "", "## Vulnerable dependencies (OWASP A06)", dependency_markdown(deps or {}),
    ]
    static_md = "\n".join(lines)
    prompt = ("Below is a static-analysis health report. Add an 'Executive summary' at the top (3-4 sentences) and a "
              "'Recommended improvements' section at the end with prioritised, concrete refactoring and architecture "
              "advice. Keep all existing tables.\n\n" + static_md)
    md, ai = _try_llm(prompt, static_md)
    return {"markdown": md, "ai": ai}


# ---------------------------------------------------------------- Per-finding auto-fix
def fix_finding(root: Path, finding: dict) -> dict:
    """Asks the LLM for a minimal patch for one finding and returns original/fixed code for a diff view."""
    rel, line = finding["file"], int(finding["line"])
    try:
        lines = (root / rel).read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise ValueError(f"Cannot read {rel}") from e
    lo, hi = max(1, line - 8), min(len(lines), line + 8)
    original = "\n".join(lines[lo - 1 : hi])
    prompt = (
        f"Issue: {finding['rule']} — {finding['message']} at {rel}:{line}.\n"
        f"Here are lines {lo}-{hi} of the file:\n```\n{original}\n```\n"
        "Return ONLY the corrected version of exactly these lines inside one ```code block``` (same indentation, "
        "keep unrelated lines unchanged), then one short paragraph starting with 'Why:' explaining the fix."
    )
    try:
        answer = llm.ask(prompt)
    except llm.NoLLMAvailable as e:
        return {"file": rel, "start": lo, "original": original, "fixed": None, "explanation": str(e), "ai": False}
    m = re.search(r"```[\w+-]*\n(.*?)```", answer, re.S)
    fixed = m.group(1).rstrip("\n") if m else None
    if fixed is not None:
        # LLMs tend to drop blank lines at the edges of the snippet; restore them so the patch stays minimal.
        orig_lines, new_lines = original.split("\n"), fixed.split("\n")
        lead = len(orig_lines) - len("\n".join(orig_lines).lstrip("\n").split("\n"))
        trail = len(orig_lines) - len("\n".join(orig_lines).rstrip("\n").split("\n"))
        core = "\n".join(new_lines).strip("\n")
        fixed = "\n" * lead + core + "\n" * trail
    why = answer[m.end():].strip() if m else answer
    return {"file": rel, "start": lo, "original": original, "fixed": fixed, "explanation": why, "ai": True}


# ---------------------------------------------------------------- File-level assistants
FILE_TASKS = {
    "explain": ("Explain this file for a new team member: purpose, how it fits the project, a walkthrough of each "
                "class/function, data flow, and anything surprising. Use headings and bullet points."),
    "refactor": ("Suggest concrete refactorings for this file: code smells, duplication, naming, SOLID / design-pattern "
                 "improvements, performance. For each give before/after code. Finish with the refactored full file "
                 "only if it is under 150 lines."),
    "docstrings": ("Rewrite this file adding complete documentation comments/docstrings in the language's standard "
                   "style (Google-style docstrings for Python, JSDoc, Javadoc, Dartdoc, etc.) for every module, class "
                   "and function. Do not change any logic. Return the full documented file in one code block."),
}


def file_assist(root: Path, structure: dict, rel: str, task: str) -> dict:
    info = structure["files"].get(rel)
    if not info or task not in FILE_TASKS:
        raise ValueError("Unknown file or task")
    code = (root / rel).read_text(encoding="utf-8")
    symbols = "\n".join(f"- {f['name']}{f['params']} (lines {f['start']}-{f['end']})" for f in info["functions"])
    fallback = (f"**{rel}** — {info['language']}, {info['lines']} lines\n\n"
                f"**Classes:** {', '.join(c['name'] for c in info['classes']) or 'none'}\n\n**Functions:**\n{symbols or 'none'}\n\n"
                f"**Imports:**\n" + "\n".join(f"- `{i}`" for i in info["imports"][:30]))
    prompt = f"{FILE_TASKS[task]}\n\nFile `{rel}`:\n```{info['language']}\n{code[:24000]}\n```"
    md, ai = _try_llm(prompt, fallback)
    return {"markdown": md, "ai": ai, "task": task, "file": rel}


def dependency_markdown(deps: dict) -> str:
    if not deps.get("dependencies"):
        return "No pinned dependencies found (requirements.txt, pyproject.toml, package.json, pubspec.yaml, go.mod)."
    rows = []
    for d in deps["dependencies"]:
        if d.get("vulns"):
            v = d["vulns"][0]
            fix = ", ".join(v.get("fixed_in", [])) or "—"
            rows.append(f"| `{d['name']}` {d['version']} | {len(d['vulns'])} | {d['worst']} | "
                        f"{(v.get('aliases') or [v['id']])[0]}: {v.get('summary', '')[:80]} | {fix} |")
    head = f"**{deps['vulnerable']}** of {len(deps['dependencies'])} dependencies have **{deps['total_vulns']}** known vulnerabilities (OSV.dev).\n\n"
    if not rows:
        return head + "No known vulnerabilities. ✅"
    return head + "| Package | Vulns | Worst | Example | Fixed in |\n|---|---|---|---|---|\n" + "\n".join(rows)


def refactor_duplicate(root: Path, block: dict) -> dict:
    """Suggests how to remove one duplicated block (extract function / base class / util module)."""
    parts = []
    for o in block["occurrences"][:4]:
        lines = (root / o["file"]).read_text(encoding="utf-8").splitlines()
        parts.append(f"--- {o['file']} lines {o['start']}-{o['end']} ---\n" + "\n".join(lines[o["start"] - 1 : o["end"]]))
    code = "\n\n".join(parts)
    fallback = ("**Duplicated block** found in:\n" + "\n".join(f"- `{o['file']}:{o['start']}-{o['end']}`" for o in block["occurrences"])
                + "\n\nExtract the shared logic into one function or module and call it from each place.\n\n```\n"
                + block["snippet"] + "\n```")
    prompt = ("The same code appears in several places. Propose a DRY refactoring: name and signature of the shared "
              "function/class, where it should live, the complete extracted code, and the replacement call at each "
              "location. Mention any small differences that need parameters.\n\n" + code)
    md, ai = _try_llm(prompt, fallback)
    return {"markdown": md, "ai": ai}


def commit_message(name: str, patch: str, applied: list) -> dict:
    """Conventional-commit message and a PR description for the fixes DevMate applied."""
    if not patch.strip():
        return {"markdown": "No changes yet. Apply some fixes first.", "ai": False}
    rules = sorted({a.get("rule", "") for a in applied if a.get("rule")})
    files = sorted({a.get("file", "") for a in applied if a.get("file")})
    fallback = (f"```\nfix: resolve {len(applied)} code issue(s) found by DevMate\n\n"
                + "\n".join(f"- {r}" for r in rules) + "\n```\n\n**Files:** " + ", ".join(f"`{f}`" for f in files))
    prompt = (f"These changes were applied to the project '{name}' to fix static-analysis findings ({', '.join(rules)}).\n"
              "Write:\n1. A Conventional Commits message (type(scope): summary, blank line, bullet body) in a ```text block.\n"
              "2. A pull-request description with sections: Summary, Changes (per file), Security impact, How to test.\n\n"
              f"```diff\n{patch[:12000]}\n```")
    md, ai = _try_llm(prompt, fallback)
    return {"markdown": md, "ai": ai}
