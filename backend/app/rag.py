"""Codebase RAG: ChromaDB with free local CPU embeddings (all-MiniLM-L6-v2 via ONNX)."""
import chromadb
from chromadb.utils.embedding_functions import ONNXMiniLM_L6_V2

from .config import settings

_client = chromadb.PersistentClient(path=str(settings.data_dir / "chroma"),
                                    settings=chromadb.Settings(anonymized_telemetry=False))


# Force the CPU provider: free, works on any laptop, and avoids CoreML/GPU quirks.
_embed = ONNXMiniLM_L6_V2(preferred_providers=["CPUExecutionProvider"])


def _collection(project_id: int):
    return _client.get_or_create_collection(f"project_{project_id}", embedding_function=_embed,
                                            metadata={"hnsw:space": "cosine"})


def index_chunks(project_id: int, chunks: list):
    try:
        _client.delete_collection(f"project_{project_id}")
    except Exception:
        pass
    col = _collection(project_id)
    for i in range(0, len(chunks), 128):
        batch = chunks[i : i + 128]
        col.add(
            ids=[c["id"] for c in batch],
            documents=[(f"# {c['file']} {c['symbol'] or ''}\n" + c["text"]) for c in batch],
            metadatas=[{"file": c["file"], "symbol": c["symbol"] or "", "start": c["start"], "end": c["end"]} for c in batch],
        )
    return len(chunks)


def search(project_id: int, query: str, k: int | None = None) -> list:
    col = _collection(project_id)
    if col.count() == 0:
        return []
    res = col.query(query_texts=[query], n_results=min(k or settings.rag_top_k, col.count()))
    return [
        {**meta, "text": doc, "score": round(1 - dist, 3)}
        for doc, meta, dist in zip(res["documents"][0], res["metadatas"][0], res["distances"][0])
    ]


def delete(project_id: int):
    try:
        _client.delete_collection(f"project_{project_id}")
    except Exception:
        pass


def format_context(hits: list) -> str:
    return "\n\n".join(f"--- {h['file']} (lines {h['start']}-{h['end']}) ---\n{h['text']}" for h in hits)
