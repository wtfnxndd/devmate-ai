"""Per-file quality metrics and hotspots.

Hotspot = code that is complex, has issues, and changes often: the files most likely to contain the
next bug (Adam Tornhill, "Your Code as a Crime Scene"). Churn comes from git history when available.
"""
import math
import subprocess
from collections import Counter
from pathlib import Path

import lizard

from .ingest import iter_source_files

SEV_W = {"high": 10, "medium": 3, "low": 1}


def maintainability_index(loc: int, avg_cc: float, comment_ratio: float) -> float:
    """Microsoft's 0-100 Maintainability Index without Halstead volume (not available for all languages).

    >= 20 is maintainable, 10-19 moderate, < 10 hard to maintain. Comments add up to +10.
    """
    if loc <= 0:
        return 100.0
    mi = (171 - 0.23 * avg_cc * 10 - 16.2 * math.log(loc)) * 100 / 171
    mi += 10 * min(1.0, comment_ratio * 4)
    return round(max(0.0, min(100.0, mi)), 1)


def git_churn(root: Path, commits: int = 300) -> dict:
    """{file: number of the last N commits touching it} if the project is a git repo."""
    if not (root / ".git").exists():
        return {}
    try:
        out = subprocess.run(["git", "log", f"--max-count={commits}", "--name-only", "--pretty=format:"],
                             cwd=root, capture_output=True, text=True, timeout=60).stdout
    except Exception:
        return {}
    return dict(Counter(line.strip() for line in out.splitlines() if line.strip()))


COMMENT_PREFIX = ("#", "//", "/*", "*", "--", '"""', "'''")


def file_metrics(root: Path, findings: list) -> dict:
    issues = {}
    for f in findings:
        d = issues.setdefault(f["file"], {"high": 0, "medium": 0, "low": 0})
        d[f["severity"]] = d.get(f["severity"], 0) + 1
    churn = git_churn(root)

    files = []
    for rel, _lang, text in iter_source_files(root):
        lines = text.splitlines()
        code = [l for l in lines if l.strip()]
        comments = sum(1 for l in code if l.strip().startswith(COMMENT_PREFIX))
        try:
            fns = lizard.analyze_file.analyze_source_code(rel, text).function_list
        except Exception:
            fns = []
        ccs = [f.cyclomatic_complexity for f in fns] or [1]
        iss = issues.get(rel, {"high": 0, "medium": 0, "low": 0})
        files.append({
            "file": rel, "loc": len(code), "functions": len(fns),
            "cc_total": sum(ccs), "cc_max": max(ccs), "cc_avg": round(sum(ccs) / len(ccs), 2),
            "comment_ratio": round(comments / len(code), 3) if code else 0,
            "mi": maintainability_index(len(code), sum(ccs) / len(ccs), comments / len(code) if code else 0),
            "issues": iss, "issue_weight": sum(SEV_W[k] * v for k, v in iss.items()),
            "churn": churn.get(rel, 0),
        })

    # Risk 0-100: complexity (40%), issues (40%), churn (20%; redistributed if no git history).
    def norm(key):
        top = max((f[key] for f in files), default=0) or 1
        return {f["file"]: f[key] / top for f in files}
    cc, iw, ch = norm("cc_total"), norm("issue_weight"), norm("churn")
    has_churn = any(f["churn"] for f in files)
    for f in files:
        r = 0.4 * cc[f["file"]] + 0.4 * iw[f["file"]] + (0.2 * ch[f["file"]] if has_churn else 0)
        f["risk"] = round(100 * (r if has_churn else r / 0.8))
        f["mi_band"] = "good" if f["mi"] >= 20 else "moderate" if f["mi"] >= 10 else "poor"
    files.sort(key=lambda f: -f["risk"])
    avg_mi = round(sum(f["mi"] * f["loc"] for f in files) / max(1, sum(f["loc"] for f in files)), 1)
    return {"files": files, "has_churn": has_churn, "avg_mi": avg_mi,
            "hotspots": [f["file"] for f in files if f["risk"] >= 50][:10]}
