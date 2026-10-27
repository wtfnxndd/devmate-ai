"""Applies AI fixes to the analysed copy of a project and exports the result.

The original version of every touched file is backed up on first change, so fixes can be
reverted and a unified-diff patch can be produced for the user's real repository.
"""
import difflib
import io
import shutil
import zipfile
from pathlib import Path

from . import engines
from .config import settings
from .ingest import IGNORED_DIRS

# Findings an automatic patch should not attempt (they need human design decisions).
SKIP_RULES = {"duplicate-code", "high-complexity", "long-function", "too-many-params"}


def _backup_dir(pid: int) -> Path:
    return settings.data_dir / "originals" / str(pid)


def _backup(pid: int, root: Path, rel: str):
    dest = _backup_dir(pid) / rel
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / rel, dest)


def _safe(root: Path, rel: str) -> Path:
    p = (root / rel).resolve()
    if not str(p).startswith(str(root.resolve())) or not p.is_file():
        raise ValueError(f"Unknown file: {rel}")
    return p


def apply_fix(pid: int, root: Path, rel: str, start: int, original: str, fixed: str) -> dict:
    """Replaces the `original` block (expected at line `start`) with `fixed`."""
    path = _safe(root, rel)
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    orig = original.split("\n")
    idx = start - 1
    if lines[idx : idx + len(orig)] != orig:
        # The file changed since the fix was generated: look for the block elsewhere.
        idx = next((i for i in range(len(lines) - len(orig) + 1) if lines[i : i + len(orig)] == orig), -1)
        if idx < 0:
            raise ValueError("The code changed since this fix was generated. Regenerate the fix.")
    _backup(pid, root, rel)
    lines[idx : idx + len(orig)] = fixed.split("\n")
    path.write_text("\n".join(lines), encoding="utf-8")
    return {"file": rel, "line": idx + 1, "removed": len(orig), "added": len(fixed.split("\n"))}


def fix_all(pid: int, root: Path, findings: list, limit: int = 8, on_event=None) -> dict:
    """Generates and applies fixes for the most severe findings, bottom-up per file so line numbers stay valid."""
    targets = [f for f in findings if f["severity"] in ("high", "medium") and f["rule"] not in SKIP_RULES][:limit]
    targets.sort(key=lambda f: (f["file"], -f["line"]))
    applied, failed = [], []
    for f in targets:
        if on_event:
            on_event("fixing", _brief(f))
        try:
            fix = engines.fix_finding(root, f)
            if not fix.get("fixed") or fix["fixed"].strip() == fix["original"].strip():
                failed.append({**_brief(f), "reason": fix.get("explanation", "No change suggested")[:200]})
                continue
            res = apply_fix(pid, root, f["file"], fix["start"], fix["original"], fix["fixed"])
            applied.append({**_brief(f), **res})
            if on_event:
                on_event("fixed", {**_brief(f), **res, "original": fix["original"][:4000], "fixed": fix["fixed"][:4000]})
        except Exception as e:  # keep going: one bad fix must not stop the batch
            failed.append({**_brief(f), "reason": str(e)[:200]})
            if on_event:
                on_event("skipped", failed[-1])
    return {"applied": applied, "failed": failed}


def _brief(f: dict) -> dict:
    return {"file": f["file"], "line": f["line"], "rule": f["rule"], "severity": f["severity"]}


def changed_files(pid: int) -> list:
    base = _backup_dir(pid)
    return sorted(str(p.relative_to(base)) for p in base.rglob("*") if p.is_file()) if base.exists() else []


def patch(pid: int, root: Path) -> str:
    """Unified diff (git apply / patch -p1 compatible) of every changed file."""
    out = []
    for rel in changed_files(pid):
        before = (_backup_dir(pid) / rel).read_text(encoding="utf-8").splitlines(keepends=True)
        after = (root / rel).read_text(encoding="utf-8").splitlines(keepends=True)
        out.extend(difflib.unified_diff(before, after, f"a/{rel}", f"b/{rel}"))
    return "".join(out)


def revert(pid: int, root: Path) -> int:
    files = changed_files(pid)
    for rel in files:
        shutil.copy2(_backup_dir(pid) / rel, root / rel)
    shutil.rmtree(_backup_dir(pid), ignore_errors=True)
    return len(files)


def forget(pid: int):
    shutil.rmtree(_backup_dir(pid), ignore_errors=True)


def export_zip(root: Path, name: str) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in sorted(root.rglob("*")):
            rel = p.relative_to(root)
            if p.is_file() and not any(part in IGNORED_DIRS for part in rel.parts):
                zf.write(p, f"{name}/{rel}")
    return buf.getvalue()
