"""Command-line entry point, used by the GitHub Actions PR-review bot.

    python -m app.cli review --path . --base origin/main --out review.md

Runs the same static analysis as the web app, keeps only findings on lines changed in the PR,
and (if a free LLM key is set) adds an AI explanation. Exits 1 if new high-severity issues exist
and --fail-on-high is given.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

from . import llm
from .analysis import run_analysis


def _snippet(root: Path, rel: str, line: int, radius: int = 6) -> str:
    # Local copy (not engines._snippet) so the CI bot doesn't need ChromaDB installed.
    try:
        lines = (root / rel).read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return ""
    lo, hi = max(1, line - radius), min(len(lines), line + radius)
    return "\n".join(f"{n:>5} | {lines[n - 1]}" for n in range(lo, hi + 1))


def changed_lines(root: Path, base: str) -> dict:
    """{file: set(line numbers)} for lines added/modified relative to base."""
    diff = subprocess.run(["git", "diff", "--unified=0", f"{base}...HEAD"], cwd=root,
                          capture_output=True, text=True, check=True).stdout
    out, current = {}, None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            current = None if line.endswith("/dev/null") else line[6:]
            out.setdefault(current, set())
        elif line.startswith("@@") and current:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            start, count = int(m.group(1)), int(m.group(2) or 1)
            out[current].update(range(start, start + count))
    return {k: v for k, v in out.items() if k}


def review(root: Path, base: str | None) -> tuple[str, int]:
    analysis = run_analysis(root)
    findings = analysis["findings"]
    if base:
        changed = changed_lines(root, base)
        findings = [f for f in findings if f["line"] in changed.get(f["file"], ())]
    high = sum(1 for f in findings if f["severity"] == "high")

    icon = {"high": "🔴", "medium": "🟠", "low": "🟡"}
    lines = [
        "## 🤖 DevMate AI review", "",
        f"Repository health: **{analysis['health_score']}/100 ({analysis['grade']})** · "
        f"{'new issues in this PR' if base else 'issues'}: **{len(findings)}** ({high} high)", "",
    ]
    if not findings:
        lines.append("No issues found in the changed lines. ✅")
        return "\n".join(lines), 0

    lines += ["| | Location | Rule | Message |", "|---|---|---|---|"]
    for f in findings[:30]:
        msg = f["message"].replace("|", "\\|")[:140]
        lines.append(f"| {icon.get(f['severity'], '')} | `{f['file']}:{f['line']}` | {f['rule']} | {msg} |")

    top = [f for f in findings if f["severity"] in ("high", "medium")][:8]
    if top and llm.available():
        blocks = "\n\n".join(f"{f['rule']} at {f['file']}:{f['line']} — {f['message']}\n```\n{_snippet(root, f['file'], f['line'])}\n```"
                             for f in top)
        try:
            ai = llm.ask("These issues were introduced in a pull request. For each one give a one-paragraph "
                         "explanation and a short corrected snippet. Be concise.\n\n" + blocks)
            lines += ["", "<details><summary>💡 AI explanations and fixes</summary>", "", ai, "", "</details>"]
        except llm.NoLLMAvailable as e:
            lines += ["", f"_AI explanations unavailable: {e}_"]
    return "\n".join(lines), high


def main(argv=None):
    ap = argparse.ArgumentParser(prog="devmate")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("review", help="Analyse a repository (optionally only the lines changed since --base)")
    r.add_argument("--path", default=".")
    r.add_argument("--base", help="git ref to diff against, e.g. origin/main")
    r.add_argument("--out", help="write Markdown here instead of stdout")
    r.add_argument("--fail-on-high", action="store_true")
    args = ap.parse_args(argv)

    md, high = review(Path(args.path).resolve(), args.base)
    if args.out:
        Path(args.out).write_text(md, encoding="utf-8")
    else:
        print(md)
    sys.exit(1 if args.fail_on_high and high else 0)


if __name__ == "__main__":
    main()
