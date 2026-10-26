"""Phase 2: static analysis — bugs, OWASP security issues, code smells and complexity.

Free rule-based tools find the issues; the LLM is only used afterwards to explain/fix them.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import lizard

from .ingest import IGNORED_DIRS, iter_source_files

BIN = Path(sys.executable).parent
SEVERITY_WEIGHT = {"high": 10, "medium": 4, "low": 1}

# OWASP-style regex rules that work for every language.
SECRET_RULES = [
    ("hardcoded-secret", "high", "A02 Cryptographic Failures",
     re.compile(r"""(?i)(password|passwd|secret|api_?key|token)\s*[:=]\s*['"][^'"\s]{6,}['"]""")),
    ("aws-access-key", "high", "A02 Cryptographic Failures", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("private-key", "high", "A02 Cryptographic Failures", re.compile(r"-----BEGIN (RSA |EC )?PRIVATE KEY-----")),
    ("sql-string-concat", "medium", "A03 Injection",
     re.compile(r"""(?i)(execute|query)\s*\(\s*['"`](select|insert|update|delete)[^'"`]*['"`]\s*(\+|%|\.format|\$\{)""")),
    ("eval-usage", "high", "A03 Injection", re.compile(r"\beval\s*\(")),
    ("innerhtml-assignment", "medium", "A03 Injection (XSS)", re.compile(r"\.innerHTML\s*=")),
    ("insecure-http", "low", "A02 Cryptographic Failures", re.compile(r"""['"]http://(?!localhost|127\.0\.0\.1)""")),
    ("weak-hash", "medium", "A02 Cryptographic Failures", re.compile(r"(?i)\b(md5|sha1)\s*\(")),
]


def _run(cmd, cwd):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=300)
        return r.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def _bandit(root: Path):
    out = _run([str(BIN / "bandit"), "-r", ".", "-f", "json", "-q", "-s", "B101", "-x", ",".join(IGNORED_DIRS)], root)
    try:
        data = json.loads(out or "{}")
    except json.JSONDecodeError:
        return []
    return [{
        "tool": "bandit", "rule": f"{r['test_id']} {r['test_name']}", "severity": r["issue_severity"].lower(),
        "category": "security", "owasp": (r.get("issue_cwe") or {}).get("link", ""),
        "file": r["filename"].lstrip("./"), "line": r["line_number"], "message": r["issue_text"],
    } for r in data.get("results", [])]


def _ruff(root: Path):
    out = _run([str(BIN / "ruff"), "check", ".", "--output-format", "json", "--exit-zero",
                "--select", "E9,F,B,S,SIM,C4,PL", "--ignore", "PLR2004,S101,PLC0414"], root)
    try:
        data = json.loads(out or "[]")
    except json.JSONDecodeError:
        return []
    findings = []
    for r in data:
        code = r.get("code") or "syntax"
        # SIM/C4/PL are style hints; check them before "S" (security), which they would otherwise match.
        style = code.startswith(("SIM", "C4", "PL"))
        security = code.startswith("S") and not style
        sev = ("high" if code.startswith(("E9", "F82", "F63", "syntax")) else "low" if style
               else "medium" if code.startswith(("B", "S", "F")) else "low")
        findings.append({
            "tool": "ruff", "rule": code, "severity": sev,
            "category": "security" if security else "bug" if code.startswith(("B", "F", "E9")) else "smell",
            "file": str(Path(r["filename"]).relative_to(root)) if Path(r["filename"]).is_absolute() else r["filename"],
            "line": r["location"]["row"], "message": r["message"],
        })
    return findings


def _semgrep(root: Path):
    """Optional: runs only if the free Semgrep CLI is installed (pip install semgrep)."""
    exe = shutil.which("semgrep")
    if not exe:
        return []
    out = _run([exe, "--config", "p/owasp-top-ten", "--json", "--quiet", "--metrics=off"], root)
    try:
        data = json.loads(out or "{}")
    except json.JSONDecodeError:
        return []
    return [{
        "tool": "semgrep", "rule": r["check_id"].split(".")[-1],
        "severity": {"ERROR": "high", "WARNING": "medium"}.get(r["extra"]["severity"], "low"),
        "category": "security", "file": r["path"], "line": r["start"]["line"], "message": r["extra"]["message"],
    } for r in data.get("results", [])]


def _regex_rules(files):
    findings = []
    for rel, _lang, text in files:
        for i, line in enumerate(text.splitlines(), 1):
            for rule, sev, owasp, rx in SECRET_RULES:
                if rx.search(line):
                    findings.append({"tool": "devmate-rules", "rule": rule, "severity": sev, "category": "security",
                                     "owasp": owasp, "file": rel, "line": i, "message": line.strip()[:160]})
    return findings


def _complexity(files):
    """Cyclomatic complexity for all languages via lizard."""
    funcs = []
    for rel, _lang, text in files:
        try:
            info = lizard.analyze_file.analyze_source_code(rel, text)
        except Exception:
            continue
        for f in info.function_list:
            funcs.append({"file": rel, "function": f.name, "line": f.start_line,
                          "complexity": f.cyclomatic_complexity, "nloc": f.nloc, "params": len(f.parameters)})
    funcs.sort(key=lambda f: -f["complexity"])
    smells = []
    for f in funcs:
        if f["complexity"] > 10:
            smells.append({"tool": "lizard", "rule": "high-complexity",
                           "severity": "medium" if f["complexity"] <= 20 else "high", "category": "smell",
                           "file": f["file"], "line": f["line"],
                           "message": f"{f['function']} has cyclomatic complexity {f['complexity']} (keep ≤ 10)"})
        if f["nloc"] > 60:
            smells.append({"tool": "lizard", "rule": "long-function", "severity": "low", "category": "smell",
                           "file": f["file"], "line": f["line"], "message": f"{f['function']} is {f['nloc']} lines long"})
        if f["params"] > 5:
            smells.append({"tool": "lizard", "rule": "too-many-params", "severity": "low", "category": "smell",
                           "file": f["file"], "line": f["line"], "message": f"{f['function']} takes {f['params']} parameters"})
    avg = round(sum(f["complexity"] for f in funcs) / len(funcs), 2) if funcs else 0
    return funcs, smells, avg


def grade(score: int) -> str:
    return "A" if score >= 85 else "B" if score >= 70 else "C" if score >= 55 else "D" if score >= 40 else "F"


def _is_test(rel: str) -> bool:
    p = rel.replace("\\", "/").lower()
    name = p.rsplit("/", 1)[-1]
    return ("/tests/" in f"/{p}" or "/test/" in f"/{p}" or "/__tests__/" in f"/{p}"
            or name.startswith("test_") or name.endswith(("_test.py", ".test.js", ".test.ts", ".spec.ts", ".spec.js", "_test.go")))


def _dedupe(findings):
    """Several tools often flag the same line; keep only the most severe finding per file/line/category."""
    seen, out = set(), []
    for f in findings:
        k = (f["file"], f["line"], f["category"])
        if k not in seen:
            seen.add(k)
            out.append(f)
    return out


def run_analysis(root: Path) -> dict:
    files = list(iter_source_files(root))
    has_python = any(lang == "python" for _, lang, _ in files)
    funcs, smells, avg_cc = _complexity(files)
    findings = _regex_rules(files) + smells + _semgrep(root)
    if has_python:
        findings += _bandit(root) + _ruff(root)
    # Test code legitimately uses fake secrets, asserts and weak hashes; don't report those as vulnerabilities.
    findings = [f for f in findings if not (f["category"] == "security" and _is_test(f["file"]))]
    order = {"high": 0, "medium": 1, "low": 2}
    findings.sort(key=lambda f: (order.get(f["severity"], 3), f["file"], f["line"]))
    findings = _dedupe(findings)

    # Floor of 500 lines so tiny projects are not scored to zero by a handful of issues.
    total_lines = max(500, sum(len(t.splitlines()) for _, _, t in files))
    penalty = sum(SEVERITY_WEIGHT.get(f["severity"], 1) for f in findings)
    # Penalty normalised per 1000 lines so big projects are not punished for size alone.
    score = max(0, round(100 - penalty * 1000 / total_lines / 2 - max(0, avg_cc - 5) * 2))
    counts = {s: sum(1 for f in findings if f["severity"] == s) for s in ("high", "medium", "low")}
    by_cat = {c: sum(1 for f in findings if f["category"] == c) for c in ("security", "bug", "smell")}
    return {
        "health_score": score,
        "grade": grade(score),
        "counts": counts, "by_category": by_cat, "avg_complexity": avg_cc,
        "complex_functions": funcs[:15], "findings": findings[:500],
        "tools": ["lizard", "devmate-rules"] + (["bandit", "ruff"] if has_python else [])
                 + (["semgrep"] if shutil.which("semgrep") else []),
    }
