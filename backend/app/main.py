import logging
import shutil
from pathlib import Path

from fastapi import BackgroundTasks, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel
from sqlalchemy import select

from . import engines, ingest, llm, rag
from .analysis import run_analysis
from .config import settings
from .db import ChatMessage, Project, SessionLocal, init_db
from .parser import analyze_structure

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("devmate")

app = FastAPI(title="DevMate AI", version="1.0.0",
              description="Intelligent Software Review, Debugging & Documentation Assistant")
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
        _save(pid, status="indexing", results={"analysis": analysis})
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
        "error": r.get("error"),
    }


# ---------------------------------------------------------------- routes
@app.get("/api/health")
def health():
    return {"status": "ok", "llm_providers": llm.available()}


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
    shutil.rmtree(Path(p.path), ignore_errors=True)
    with SessionLocal() as db:
        db.query(ChatMessage).filter_by(project_id=pid).delete()
        db.delete(db.get(Project, pid))
        db.commit()
    return {"deleted": pid}


@app.post("/api/projects/{pid}/reanalyze")
def reanalyze(pid: int, bg: BackgroundTasks):
    _get(pid)
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
    if not refresh and key in p.results and p.results[key].get("ai"):
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
        p.name, p.results["structure"], p.results["analysis"]), refresh)


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
