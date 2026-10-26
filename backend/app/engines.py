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
def health_report(name: str, structure: dict, analysis: dict) -> dict:
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
    ]
    static_md = "\n".join(lines)
    prompt = ("Below is a static-analysis health report. Add an 'Executive summary' at the top (3-4 sentences) and a "
              "'Recommended improvements' section at the end with prioritised, concrete refactoring and architecture "
              "advice. Keep all existing tables.\n\n" + static_md)
    md, ai = _try_llm(prompt, static_md)
    return {"markdown": md, "ai": ai}
