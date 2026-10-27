import json
import logging
import queue
import threading
import re
import shutil
from pathlib import Path

import secrets

from fastapi import BackgroundTasks, Body, FastAPI, File, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse, Response, StreamingResponse
from pydantic import BaseModel
from sqlalchemy import select

from datetime import datetime

from . import deps as depscan
from . import engines, fixer, ingest, llm, pdf, rag
from .analysis import grade, run_analysis
from .config import settings
from .db import ChatMessage, Project, SessionLocal, init_db
from .parser import analyze_structure

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("devmate")

app = FastAPI(title="DevMate AI", version="1.0.0",
              description="Intelligent Software Review, Debugging & Documentation Assistant")


@app.middleware("http")
async def require_token(request: Request, call_next):
    if (settings.api_token and request.url.path.startswith("/api/") and request.url.path != "/api/health"
            and request.method != "OPTIONS"):
        sent = request.headers.get("x-devmate-token", "")
        if not secrets.compare_digest(sent, settings.api_token):
            return JSONResponse({"detail": "Missing or wrong access token"}, status_code=401)
    return await call_next(request)


# Added after the token check so CORS headers also wrap 401 responses.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
init_db()


class GithubIn(BaseModel):
    url: str


class LocalIn(BaseModel):
    path: str


class TestsIn(BaseModel):
    file: str


class DebugIn(BaseModel):
    error: str


class ChatIn(BaseModel):
    message: str


class FixIn(BaseModel):
    file: str
    line: int
    rule: str = ""
    message: str = ""


class ApplyFixIn(BaseModel):
    file: str
    start: int
    original: str
    fixed: str


class FileTaskIn(BaseModel):
    file: str
    task: str  # explain | refactor | docstrings


# ---------------------------------------------------------------- helpers
def _get(pid: int) -> Project:
    with SessionLocal() as db:
        p = db.get(Project, pid)
    if not p:
        raise HTTPException(404, "Project not found")
    return p


def _save(pid: int, **fields):
    with SessionLocal() as db:
        p = db.get(Project, pid)
        for k, v in fields.items():
            if k == "results":
                p.results = {**(p.results or {}), **v}
            else:
                setattr(p, k, v)
        db.commit()


def _require(p: Project, key: str):
    if p.status != "ready" or key not in (p.results or {}):
        raise HTTPException(409, f"Project is '{p.status}'. Wait until analysis is ready.")
    return p.results[key]


def _fingerprint(f: dict) -> str:
    # Numbers in messages are usually line numbers / counts that shift when code above changes.
    msg = re.sub(r"\b\d+\b", "#", f["message"][:100])
    return f"{f['severity']}|{f['file']}|{f['rule']}|{msg}"


def _pipeline(pid: int):
    """Phase 1 + 2: parse → static analysis → embed for RAG."""
    p = _get(pid)
    root = Path(p.path)
    try:
        _save(pid, status="parsing")
        structure = analyze_structure(root)
        chunks = structure.pop("chunks")
        _save(pid, status="analyzing", results={"structure": structure})
        analysis = run_analysis(root)
        _save(pid, status="scanning dependencies")
        deps = depscan.scan(root)
        # Known-vulnerable packages lower the health score (max 15 points).
        analysis["code_score"] = analysis["health_score"]
        analysis["health_score"] = max(0, analysis["health_score"] - min(15, deps["vulnerable"] * 3))
        analysis["grade"] = grade(analysis["health_score"])
        history = (_get(pid).results or {}).get("history", [])[-19:] + [{
            "at": datetime.utcnow().isoformat(timespec="seconds"), "score": analysis["health_score"],
            "counts": analysis["counts"], "vulnerable_deps": deps["vulnerable"],
            "duplication": analysis["duplication"]["percentage"],
            # Line-independent identity of each finding, used to diff analyses (fixed vs new issues).
            "fingerprints": sorted({_fingerprint(f) for f in analysis["findings"]}),
        }]
        # Engine outputs depend on the old code, so drop them on re-analysis.
        stale = {k: None for k in ("review", "readme", "api_docs", "report")}
        _save(pid, status="indexing", results={"analysis": analysis, "dependencies": deps, "history": history, **stale})
        rag.index_chunks(pid, chunks)
        _save(pid, status="ready", results={"endpoints": engines.find_endpoints(root, structure)})
        log.info("Project %s ready: %s", pid, structure["summary"])
    except Exception as e:
        log.exception("Pipeline failed")
        _save(pid, status=f"error: {e}"[:30], results={"error": str(e)})


def _create(name: str, source: str, root: Path, bg: BackgroundTasks):
    with SessionLocal() as db:
        p = Project(name=name, source=source, path=str(root), results={})
        db.add(p)
        db.commit()
        pid = p.id
    bg.add_task(_pipeline, pid)
    return _summary(_get(pid))


def _summary(p: Project) -> dict:
    r = p.results or {}
    a = r.get("analysis", {})
    return {
        "id": p.id, "name": p.name, "source": p.source, "status": p.status,
        "created_at": p.created_at.isoformat(), "summary": r.get("structure", {}).get("summary"),
        "health_score": a.get("health_score"), "grade": a.get("grade"), "counts": a.get("counts"),
        "vulnerable_deps": r.get("dependencies", {}).get("vulnerable"),
        "error": r.get("error"),
    }


# ---------------------------------------------------------------- routes
@app.get("/api/health")
def health():
    return {"status": "ok", "llm_providers": llm.available(), "ai_mode": llm.ai_mode(),
            "auth_required": bool(settings.api_token), "local_import": settings.allow_local_import}


@app.post("/api/projects/upload")
async def upload(bg: BackgroundTasks, file: UploadFile = File(...)):
    if not file.filename.lower().endswith(".zip"):
        raise HTTPException(400, "Upload a .zip file")
    try:
        root = ingest.from_zip(await file.read())
    except Exception as e:
        raise HTTPException(400, f"Invalid zip: {e}") from e
    return _create(Path(file.filename).stem, f"zip:{file.filename}", root, bg)


@app.post("/api/projects/github")
def github(body: GithubIn, bg: BackgroundTasks):
    try:
        root = ingest.from_github(body.url)
    except Exception as e:
        raise HTTPException(400, f"Could not download repository: {e}") from e
    return _create(body.url.rstrip("/").split("/")[-1].removesuffix(".git"), body.url, root, bg)


@app.post("/api/projects/local")
def local(body: LocalIn, bg: BackgroundTasks):
    if not settings.allow_local_import:
        raise HTTPException(403, "Importing local folders is disabled on this server")
    try:
        root = ingest.from_local(body.path)
    except Exception as e:
        raise HTTPException(400, str(e)) from e
    return _create(root.name, f"local:{body.path}", root, bg)


@app.get("/api/projects")
def list_projects():
    with SessionLocal() as db:
        return [_summary(p) for p in db.scalars(select(Project).order_by(Project.id.desc()))]


@app.get("/api/projects/{pid}")
def get_project(pid: int):
    return _summary(_get(pid))


@app.delete("/api/projects/{pid}")
def delete_project(pid: int):
    p = _get(pid)
    rag.delete(pid)
    fixer.forget(pid)
    shutil.rmtree(Path(p.path), ignore_errors=True)
    with SessionLocal() as db:
        db.query(ChatMessage).filter_by(project_id=pid).delete()
        db.delete(db.get(Project, pid))
        db.commit()
    return {"deleted": pid}


@app.post("/api/projects/{pid}/reanalyze")
def reanalyze(pid: int, bg: BackgroundTasks):
    p = _get(pid)
    # Keep the analysed copy if DevMate fixes were applied to it; otherwise refresh it from disk.
    if p.source.startswith("local:") and settings.allow_local_import and not fixer.changed_files(pid):
        # Re-copy the folder so edits made since the import are analysed.
        try:
            root = ingest.from_local(p.source[len("local:"):])
        except ValueError as e:
            raise HTTPException(400, str(e)) from e
        shutil.rmtree(Path(p.path), ignore_errors=True)
        _save(pid, path=str(root))
    _save(pid, status="queued")
    bg.add_task(_pipeline, pid)
    return {"status": "queued"}


@app.get("/api/projects/{pid}/structure")
def structure(pid: int):
    return _require(_get(pid), "structure")


@app.get("/api/projects/{pid}/analysis")
def analysis(pid: int):
    return _require(_get(pid), "analysis")


@app.get("/api/projects/{pid}/architecture")
def architecture(pid: int):
    s = _require(_get(pid), "structure")
    return {"mermaid": s["mermaid"], "tree": s["tree"], "dependencies": s["dependencies"]}


@app.get("/api/projects/{pid}/file", response_class=PlainTextResponse)
def read_file(pid: int, path: str):
    root = Path(_get(pid).path).resolve()
    target = (root / path).resolve()
    if not str(target).startswith(str(root)) or not target.is_file():
        raise HTTPException(404, "File not found")
    return target.read_text(encoding="utf-8", errors="replace")


def _cached(pid: int, key: str, fn, refresh: bool):
    p = _get(pid)
    _require(p, "analysis")
    if not refresh and (p.results or {}).get(key) and p.results[key].get("ai"):
        return p.results[key]
    out = fn(p)
    _save(pid, results={key: out})
    return out


@app.post("/api/projects/{pid}/review")
def review(pid: int, refresh: bool = False):
    return _cached(pid, "review", lambda p: engines.review(Path(p.path), p.results["analysis"]), refresh)


@app.post("/api/projects/{pid}/readme")
def readme(pid: int, refresh: bool = False):
    return _cached(pid, "readme", lambda p: engines.readme(
        Path(p.path), p.name, p.results["structure"], p.results.get("endpoints", [])), refresh)


@app.post("/api/projects/{pid}/api-docs")
def api_docs(pid: int, refresh: bool = False):
    return _cached(pid, "api_docs", lambda p: engines.api_docs(Path(p.path), p.results.get("endpoints", [])), refresh)


@app.post("/api/projects/{pid}/report")
def report(pid: int, refresh: bool = False):
    return _cached(pid, "report", lambda p: engines.health_report(
        p.name, p.results["structure"], p.results["analysis"], p.results.get("dependencies")), refresh)


@app.get("/api/projects/{pid}/dependencies")
def dependencies(pid: int):
    return _require(_get(pid), "dependencies")


@app.get("/api/projects/{pid}/history")
def history(pid: int):
    return (_get(pid).results or {}).get("history", [])


@app.get("/api/projects/{pid}/files")
def files(pid: int):
    """Per-file metrics for the file explorer."""
    p = _get(pid)
    s, a = _require(p, "structure"), _require(p, "analysis")
    cc = {}
    for f in a["complex_functions"]:
        cc[f["file"]] = max(cc.get(f["file"], 0), f["complexity"])
    issues = {}
    for f in a["findings"]:
        sev = issues.setdefault(f["file"], {"high": 0, "medium": 0, "low": 0})
        sev[f["severity"]] = sev.get(f["severity"], 0) + 1
    return [{
        "file": rel, "language": info["language"], "lines": info["lines"],
        "classes": len(info["classes"]), "functions": len(info["functions"]),
        "max_complexity": cc.get(rel), "issues": issues.get(rel, {"high": 0, "medium": 0, "low": 0}),
    } for rel, info in sorted(s["files"].items())]


@app.post("/api/projects/{pid}/fix")
def fix(pid: int, body: FixIn):
    p = _get(pid)
    _require(p, "analysis")
    try:
        return engines.fix_finding(Path(p.path), body.model_dump())
    except ValueError as e:
        raise HTTPException(400, str(e)) from e


@app.post("/api/projects/{pid}/file-assist")
def file_assist(pid: int, body: FileTaskIn):
    p = _get(pid)
    try:
        return engines.file_assist(Path(p.path), _require(p, "structure"), body.file, body.task)
    except ValueError as e:
        raise HTTPException(400, str(e)) from e


@app.post("/api/projects/{pid}/tests")
def tests(pid: int, body: TestsIn):
    p = _get(pid)
    try:
        return engines.generate_tests(Path(p.path), _require(p, "structure"), body.file)
    except ValueError as e:
        raise HTTPException(400, str(e)) from e


@app.post("/api/projects/{pid}/debug")
def debug(pid: int, body: DebugIn):
    p = _get(pid)
    return engines.debug(pid, Path(p.path), _require(p, "structure"), body.error)


# ---------------------------------------------------------------- fixing the project
@app.post("/api/projects/{pid}/fix/apply")
def apply_fix(pid: int, body: ApplyFixIn):
    p = _get(pid)
    try:
        res = fixer.apply_fix(pid, Path(p.path), body.file, body.start, body.original, body.fixed)
    except ValueError as e:
        raise HTTPException(409, str(e)) from e
    _save(pid, results={"applied_fixes": (p.results or {}).get("applied_fixes", []) + [res]})
    return res


@app.post("/api/projects/{pid}/fix-all")
def fix_all(pid: int, limit: int = 8):
    p = _get(pid)
    if not llm.available():
        raise HTTPException(400, "Fix all needs a free LLM key (GEMINI_API_KEY or GROQ_API_KEY)")
    out = fixer.fix_all(pid, Path(p.path), _require(p, "analysis")["findings"], limit=min(limit, 20))
    _save(pid, results={"applied_fixes": (p.results or {}).get("applied_fixes", []) + out["applied"]})
    return out


@app.get("/api/projects/{pid}/changes")
def changes(pid: int):
    p = _get(pid)
    return {"files": fixer.changed_files(pid), "applied": (p.results or {}).get("applied_fixes", []),
            "patch": fixer.patch(pid, Path(p.path))}


@app.post("/api/projects/{pid}/fix/revert")
def revert(pid: int):
    p = _get(pid)
    n = fixer.revert(pid, Path(p.path))
    _save(pid, results={"applied_fixes": []})
    return {"reverted_files": n}


@app.get("/api/projects/{pid}/export/patch", response_class=PlainTextResponse)
def export_patch(pid: int):
    return fixer.patch(pid, Path(_get(pid).path))


@app.get("/api/projects/{pid}/export/zip")
def export_zip(pid: int):
    p = _get(pid)
    data = fixer.export_zip(Path(p.path), p.name)
    return Response(data, media_type="application/zip",
                    headers={"Content-Disposition": f'attachment; filename="{p.name}-devmate.zip"'})


PDF_KINDS = {"report": "Health Report", "review": "AI Code Review", "readme": "README", "api_docs": "API Reference"}


@app.get("/api/projects/{pid}/export/pdf")
def export_pdf(pid: int, kind: str = "report"):
    if kind not in PDF_KINDS:
        raise HTTPException(400, f"kind must be one of {list(PDF_KINDS)}")
    generate = {"report": report, "review": review, "readme": readme, "api_docs": api_docs}[kind]
    md = generate(pid)["markdown"]
    p = _get(pid)
    a = (p.results or {}).get("analysis", {})
    data = pdf.render(md, PDF_KINDS[kind], p.name, a.get("health_score"), a.get("grade"))
    return Response(data, media_type="application/pdf",
                    headers={"Content-Disposition": f'attachment; filename="{p.name}-{kind}.pdf"'})


# ---------------------------------------------------------------- duplication
@app.get("/api/projects/{pid}/duplicates")
def duplicates(pid: int):
    return _require(_get(pid), "analysis").get("duplication", {"blocks": [], "percentage": 0})


@app.post("/api/projects/{pid}/duplicates/{index}/refactor")
def refactor_duplicate(pid: int, index: int):
    p = _get(pid)
    blocks = _require(p, "analysis").get("duplication", {}).get("blocks", [])
    if not 0 <= index < len(blocks):
        raise HTTPException(404, "No such duplicate block")
    return engines.refactor_duplicate(Path(p.path), blocks[index])


# ---------------------------------------------------------------- compare
@app.get("/api/projects/{pid}/compare")
def compare(pid: int, a: int = -2, b: int = -1):
    """Diff two analyses of the same project (indexes into history; default: previous vs latest)."""
    hist = (_get(pid).results or {}).get("history", [])
    if len(hist) < 2:
        raise HTTPException(409, "Re-analyze the project at least once to compare analyses")
    try:
        old, new = hist[a], hist[b]
    except IndexError as e:
        raise HTTPException(400, "Invalid analysis index") from e
    comparable = "fingerprints" in old and "fingerprints" in new
    fo, fn = set(old.get("fingerprints", [])), set(new.get("fingerprints", []))

    def parse(fp):
        sev, file, rule, msg = fp.split("|", 3)
        return {"severity": sev, "file": file, "rule": rule, "message": msg}

    return {
        "from": {k: old.get(k) for k in ("at", "score", "counts", "vulnerable_deps", "duplication")},
        "to": {k: new.get(k) for k in ("at", "score", "counts", "vulnerable_deps", "duplication")},
        # Analyses recorded before issue tracking existed only have totals.
        "comparable": comparable,
        "fixed": [parse(x) for x in sorted(fo - fn)] if comparable else [],
        "new": [parse(x) for x in sorted(fn - fo)] if comparable else [],
        "unchanged": len(fo & fn),
        "history": [{k: h.get(k) for k in ("at", "score", "counts", "vulnerable_deps", "duplication")} for h in hist],
    }


@app.get("/api/compare-projects")
def compare_projects(a: int, b: int):
    out = []
    for pid in (a, b):
        p = _get(pid)
        r = p.results or {}
        s, an, d = r.get("structure", {}).get("summary", {}), r.get("analysis", {}), r.get("dependencies", {})
        out.append({
            "id": pid, "name": p.name, "score": an.get("health_score"), "grade": an.get("grade"),
            "files": s.get("files"), "lines": s.get("lines"), "functions": s.get("functions"),
            "languages": s.get("languages"), "counts": an.get("counts"), "by_category": an.get("by_category"),
            "avg_complexity": an.get("avg_complexity"), "duplication": an.get("duplication", {}).get("percentage"),
            "vulnerable_deps": d.get("vulnerable"), "total_vulns": d.get("total_vulns"),
        })
    return out


@app.post("/api/projects/{pid}/commit-message")
def commit_message(pid: int):
    p = _get(pid)
    return engines.commit_message(p.name, fixer.patch(pid, Path(p.path)), (p.results or {}).get("applied_fixes", []))


# ---------------------------------------------------------------- streaming
def _sse(q: queue.Queue):
    while True:
        item = q.get()
        if item is None:
            break
        kind, data = item
        yield f"data: {json.dumps({'type': kind, 'data': data})}\n\n"


@app.post("/api/projects/{pid}/stream/{kind}")
def stream(pid: int, kind: str, body: dict = Body(default={}), refresh: bool = False):
    """Runs any AI feature and streams the answer token by token (Server-Sent Events).

    Events: provider (which model), delta (text chunk), reset (provider failed, restart), done (final result), error.
    """
    handlers = {
        "review": lambda: review(pid, refresh),
        "readme": lambda: readme(pid, refresh),
        "api-docs": lambda: api_docs(pid, refresh),
        "report": lambda: report(pid, refresh),
        "tests": lambda: tests(pid, TestsIn(**body)),
        "debug": lambda: debug(pid, DebugIn(**body)),
        "chat": lambda: chat(pid, ChatIn(**body)),
        "fix": lambda: fix(pid, FixIn(**body)),
        "file-assist": lambda: file_assist(pid, FileTaskIn(**body)),
        "duplicate-refactor": lambda: refactor_duplicate(pid, int(body.get("index", 0))),
        "commit-message": lambda: commit_message(pid),
    }
    if kind not in handlers:
        raise HTTPException(404, f"Unknown AI feature: {kind}")
    q: queue.Queue = queue.Queue()

    def work():
        llm.streaming(q)
        try:
            q.put(("done", handlers[kind]()))
        except HTTPException as e:
            q.put(("error", e.detail))
        except Exception as e:  # surface the reason to the UI instead of a broken stream
            log.exception("stream %s failed", kind)
            q.put(("error", str(e)))
        finally:
            q.put(None)

    threading.Thread(target=work, daemon=True).start()
    return StreamingResponse(_sse(q), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


# ---------------------------------------------------------------- AI settings & local models
RECOMMENDED_MODELS = [
    {"name": "qwen2.5-coder:1.5b", "size_gb": 1.0, "note": "Fastest. Good for chat and quick explanations."},
    {"name": "qwen2.5-coder:3b", "size_gb": 1.9, "note": "Recommended balance of speed and quality on a laptop CPU."},
    {"name": "qwen2.5-coder:7b", "size_gb": 4.7, "note": "Best code quality; slower without a GPU."},
    {"name": "deepseek-coder:6.7b", "size_gb": 3.8, "note": "DeepSeek Coder (named in the synopsis)."},
    {"name": "llama3.2:3b", "size_gb": 2.0, "note": "General-purpose writing (README, reports)."},
]


class AiSettingsIn(BaseModel):
    mode: str | None = None
    local_model: str | None = None


class PullIn(BaseModel):
    name: str


@app.get("/api/ai/status")
def ai_status():
    return {**llm.status(), "recommended": RECOMMENDED_MODELS}


@app.put("/api/ai/settings")
def ai_settings(body: AiSettingsIn):
    if body.mode is not None:
        if body.mode not in llm.MODES:
            raise HTTPException(400, f"mode must be one of {llm.MODES}")
        llm.set_setting("ai_mode", body.mode)
    if body.local_model:
        llm.set_setting("ollama_model", body.local_model)
    return ai_status()


def _ollama(path: str) -> str:
    if not settings.ollama_url:
        raise HTTPException(400, "OLLAMA_URL is not set")
    return settings.ollama_url.rstrip("/") + path


@app.post("/api/ai/models/pull")
def pull_model(body: PullIn):
    """Downloads a model into Ollama, streaming progress as Server-Sent Events."""
    if llm.ollama_models(force=True) is None:
        raise HTTPException(503, "Ollama is not running on the DevMate server")

    def gen():
        import httpx
        try:
            with httpx.stream("POST", _ollama("/api/pull"), json={"name": body.name, "stream": True}, timeout=None) as r:
                for line in r.iter_lines():
                    if line:
                        yield f"data: {line}\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
        llm.ollama_models(force=True)

    return StreamingResponse(gen(), media_type="text/event-stream", headers={"Cache-Control": "no-cache"})


@app.delete("/api/ai/models/{name:path}")
def delete_model(name: str):
    import httpx
    r = httpx.request("DELETE", _ollama("/api/delete"), json={"name": name}, timeout=30)
    if r.status_code >= 400:
        raise HTTPException(r.status_code, r.text)
    llm.ollama_models(force=True)
    return {"deleted": name}


@app.get("/api/projects/{pid}/chat")
def chat_history(pid: int):
    with SessionLocal() as db:
        msgs = db.scalars(select(ChatMessage).filter_by(project_id=pid).order_by(ChatMessage.id))
        return [{"role": m.role, "content": m.content} for m in msgs]


@app.post("/api/projects/{pid}/chat")
def chat(pid: int, body: ChatIn):
    _require(_get(pid), "structure")
    history = chat_history(pid)
    out = engines.chat(pid, body.message, history)
    with SessionLocal() as db:
        db.add_all([ChatMessage(project_id=pid, role="user", content=body.message),
                    ChatMessage(project_id=pid, role="assistant", content=out["markdown"])])
        db.commit()
    return out


@app.get("/")
def root():
    return {"app": "DevMate AI", "docs": "/docs", "data_dir": str(settings.data_dir)}
