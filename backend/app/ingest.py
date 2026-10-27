"""Phase 1: project ingestion from ZIP upload, GitHub URL or local directory."""
import io
import os
import re
import shutil
import subprocess
import uuid
import zipfile
from pathlib import Path

import httpx

from .config import settings

IGNORED_DIRS = {
    ".git", "node_modules", "__pycache__", ".venv", "venv", "env", "build", "dist",
    ".dart_tool", ".idea", ".vscode", "target", ".next", "coverage", ".gradle", "Pods",
}

LANG_BY_EXT = {
    ".py": "python", ".js": "javascript", ".jsx": "javascript", ".ts": "typescript",
    ".tsx": "tsx", ".java": "java", ".go": "go", ".rs": "rust", ".c": "c", ".h": "c",
    ".cpp": "cpp", ".cc": "cpp", ".hpp": "cpp", ".cs": "c_sharp", ".rb": "ruby",
    ".php": "php", ".dart": "dart", ".kt": "kotlin", ".swift": "swift",
}


def _new_dir() -> Path:
    d = settings.data_dir / "projects" / uuid.uuid4().hex[:12]
    d.mkdir(parents=True)
    return d


def _safe_extract(zf: zipfile.ZipFile, dest: Path):
    dest = dest.resolve()
    for member in zf.infolist():
        target = (dest / member.filename).resolve()
        if not str(target).startswith(str(dest)):
            raise ValueError(f"Unsafe path in zip: {member.filename}")
    zf.extractall(dest)


def _unwrap_single_dir(d: Path) -> Path:
    children = [c for c in d.iterdir() if not c.name.startswith("__MACOSX")]
    return children[0] if len(children) == 1 and children[0].is_dir() else d


def from_zip(data: bytes) -> Path:
    d = _new_dir()
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        _safe_extract(zf, d)
    return _unwrap_single_dir(d)


def _git_clone(owner: str, repo: str, branch: str | None) -> Path | None:
    """Shallow clone with recent history (for churn / hotspots). Returns None if git isn't usable."""
    d = _new_dir() / repo
    url = f"https://github.com/{owner}/{repo}.git"
    if settings.github_token:
        url = f"https://x-access-token:{settings.github_token}@github.com/{owner}/{repo}.git"
    cmd = ["git", "clone", "--quiet", "--depth", "300", "--single-branch", "--no-tags", url, str(d)]
    if branch:
        cmd[2:2] = ["--branch", branch]
    try:
        subprocess.run(cmd, check=True, timeout=180, capture_output=True,
                       env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
        return d
    except Exception:
        shutil.rmtree(d.parent, ignore_errors=True)
        return None


def from_github(url: str) -> Path:
    m = re.match(r"https?://github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?(?:/tree/([^/]+))?/?$", url.strip())
    if not m:
        raise ValueError("Expected a URL like https://github.com/owner/repo")
    owner, repo, branch = m.groups()
    cloned = _git_clone(owner, repo, branch)
    if cloned:
        return cloned
    headers = {"Authorization": f"Bearer {settings.github_token}"} if settings.github_token else {}
    api = f"https://api.github.com/repos/{owner}/{repo}/zipball" + (f"/{branch}" if branch else "")
    r = httpx.get(api, headers=headers, follow_redirects=True, timeout=120)
    r.raise_for_status()
    return from_zip(r.content)


def from_local(path: str) -> Path:
    src = Path(path).expanduser().resolve()
    if not src.is_dir():
        raise ValueError(f"Not a directory: {src}")
    d = _new_dir() / src.name
    shutil.copytree(src, d, ignore=shutil.ignore_patterns(*IGNORED_DIRS))
    return d


def iter_source_files(root: Path):
    """Yields (relative_path, language, text) for every supported source file."""
    for p in sorted(root.rglob("*")):
        if not p.is_file() or any(part in IGNORED_DIRS for part in p.relative_to(root).parts):
            continue
        lang = LANG_BY_EXT.get(p.suffix.lower())
        if not lang or p.stat().st_size > settings.max_file_bytes:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        yield str(p.relative_to(root)), lang, text
