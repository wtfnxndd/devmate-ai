"""LLM access, local-first.

Providers (all OpenAI-compatible, so one client library covers them):
  * local  — Ollama on this machine (free, private: code never leaves the computer)
  * cloud  — Groq, then Gemini free tiers (fast fallback)

The AI mode decides the order:  "local" (local only), "local-first" (default), "cloud-first".
Answers are cached in the database, and can be streamed token-by-token to the UI (see `streaming`).
"""
import contextvars
import hashlib
import logging
import queue
import re
import time

import httpx
from openai import OpenAI

from .config import settings
from .db import AppSetting, LLMCache, SessionLocal

log = logging.getLogger("devmate.llm")

SYSTEM_PROMPT = (
    "You are DevMate AI, a senior software engineer who reviews code, explains bugs, writes documentation "
    "and tests. Be precise, reference file names and line numbers when available, prefer concrete fixes "
    "with code, and answer in GitHub-flavoured Markdown."
)

MODES = ("local", "local-first", "cloud-first")
# Small local models have small context windows and run on CPU: keep prompts short.
LOCAL_PROMPT_CHARS = 9000


class NoLLMAvailable(RuntimeError):
    pass


# ---------------------------------------------------------------- runtime settings (editable from the UI)
def get_setting(key: str, default: str) -> str:
    with SessionLocal() as db:
        row = db.get(AppSetting, key)
        return row.value if row else default


def set_setting(key: str, value: str):
    with SessionLocal() as db:
        db.merge(AppSetting(key=key, value=value))
        db.commit()


def ai_mode() -> str:
    m = get_setting("ai_mode", settings.ai_mode)
    return m if m in MODES else "local-first"


def local_model() -> str:
    return get_setting("ollama_model", settings.ollama_model)


# ---------------------------------------------------------------- Ollama detection
_ollama_cache = {"at": 0.0, "models": None}


def ollama_models(force: bool = False) -> list | None:
    """Installed Ollama models, or None if Ollama isn't running. Cached for 15 seconds."""
    if not settings.ollama_url:
        return None
    if not force and time.time() - _ollama_cache["at"] < 15:
        return _ollama_cache["models"]
    try:
        r = httpx.get(settings.ollama_url.rstrip("/") + "/api/tags", timeout=2)
        r.raise_for_status()
        models = [{"name": m["name"], "size": m.get("size", 0), "family": m.get("details", {}).get("family", ""),
                   "parameters": m.get("details", {}).get("parameter_size", "")} for m in r.json().get("models", [])]
    except Exception:
        models = None
    _ollama_cache.update(at=time.time(), models=models)
    return models


def _pick_local_model(installed: list) -> str | None:
    names = [m["name"] for m in installed]
    wanted = local_model()
    if wanted in names or f"{wanted}:latest" in names:
        return wanted
    return names[0] if names else None


# ---------------------------------------------------------------- providers
_cooldown: dict[str, float] = {}


def _retry_after(err: Exception) -> float:
    m = re.search(r"retry in (?:(\d+)h)?(?:(\d+)m)?([\d.]+)s", str(err))
    if m:
        h, mnt, sec = (float(x) if x else 0 for x in m.groups())
        return h * 3600 + mnt * 60 + sec
    return 60


def _local():
    installed = ollama_models()
    model = _pick_local_model(installed) if installed else None
    if not model:
        return []
    client = OpenAI(base_url=settings.ollama_url.rstrip("/") + "/v1", api_key="ollama", max_retries=0, timeout=600)
    return [(f"local:{model}", model, client)]


def _cloud():
    p = []
    if settings.groq_api_key:
        groq = OpenAI(base_url="https://api.groq.com/openai/v1", api_key=settings.groq_api_key, max_retries=0, timeout=90)
        p += [(f"groq:{m.strip()}", m.strip(), groq) for m in settings.groq_model.split(",") if m.strip()]
    if settings.gemini_api_key:
        gemini = OpenAI(base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
                        api_key=settings.gemini_api_key, max_retries=0, timeout=30)
        p += [(f"gemini:{m.strip()}", m.strip(), gemini) for m in settings.gemini_model.split(",") if m.strip()]
    return p


def _providers():
    mode = ai_mode()
    if mode == "local":
        return _local()
    if mode == "cloud-first":
        return _cloud() + _local()
    return _local() + _cloud()


def available() -> list:
    return sorted({name.split(":")[0] for name, _, _ in _providers()})


def status() -> dict:
    installed = ollama_models(force=True)
    return {
        "mode": ai_mode(),
        "modes": list(MODES),
        "ollama_running": installed is not None,
        "ollama_url": settings.ollama_url,
        "local_model": local_model(),
        "active_local_model": _pick_local_model(installed) if installed else None,
        "installed": installed or [],
        "cloud": sorted({n.split(":")[0] for n, _, _ in _cloud()}),
        "order": [n for n, _, _ in _providers()],
    }


# ---------------------------------------------------------------- streaming sink
# When set (by a streaming endpoint), ask() streams tokens into this queue as they arrive.
_sink: contextvars.ContextVar[queue.Queue | None] = contextvars.ContextVar("llm_sink", default=None)


def streaming(q: queue.Queue):
    return _sink.set(q)


def _emit(kind: str, data):
    q = _sink.get()
    if q is not None:
        q.put((kind, data))


def _shrink(prompt: str) -> str:
    if len(prompt) <= LOCAL_PROMPT_CHARS:
        return prompt
    half = LOCAL_PROMPT_CHARS // 2
    return prompt[:half] + "\n\n[... trimmed for the local model ...]\n\n" + prompt[-half:]


def ask(prompt: str, system: str = SYSTEM_PROMPT, use_cache: bool = True, history: list | None = None) -> str:
    key = hashlib.sha256((system + "\x00" + prompt + str(history or "")).encode()).hexdigest()
    if use_cache:
        with SessionLocal() as db:
            hit = db.get(LLMCache, key)
            if hit:
                _emit("provider", f"{hit.provider} (cached)")
                return hit.response
    providers = _providers()
    if not providers:
        if ai_mode() == "local":
            raise NoLLMAvailable("Local AI is not running. Start Ollama and download a model in AI settings.")
        raise NoLLMAvailable("No AI available. Start Ollama for local AI, or add a free GROQ_API_KEY / GEMINI_API_KEY.")

    errors = []
    for name, model, client in providers:
        if _cooldown.get(name, 0) > time.time():
            errors.append(f"{name}: rate-limited, skipped")
            continue
        local = name.startswith("local:")
        user = _shrink(prompt) if local else prompt
        hist = (history or [])[-4:] if local else (history or [])
        messages = [{"role": "system", "content": system}, *hist, {"role": "user", "content": user}]
        started = False
        try:
            _emit("provider", name)
            if _sink.get() is None:
                resp = client.chat.completions.create(model=model, messages=messages, temperature=0.2)
                text = resp.choices[0].message.content or ""
            else:
                parts = []
                for chunk in client.chat.completions.create(model=model, messages=messages, temperature=0.2, stream=True):
                    delta = chunk.choices[0].delta.content if chunk.choices else None
                    if delta:
                        started = True
                        parts.append(delta)
                        _emit("delta", delta)
                text = "".join(parts)
            # Reasoning models may wrap their thinking in <think> tags; keep only the answer.
            text = re.sub(r"<think>.*?</think>\s*", "", text, flags=re.S).strip()
            with SessionLocal() as db:
                db.merge(LLMCache(key=key, provider=name, response=text))
                db.commit()
            return text
        except Exception as e:
            if started:  # can't silently switch provider mid-answer
                raise NoLLMAvailable(f"{name} stopped mid-answer: {str(e)[:160]}") from e
            if "429" in str(e) or "RESOURCE_EXHAUSTED" in str(e):
                _cooldown[name] = time.time() + _retry_after(e)
            elif "timed out" in str(e).lower() or "404" in str(e):
                _cooldown[name] = time.time() + 600
            log.warning("LLM provider %s failed: %s", name, str(e)[:200])
            errors.append(f"{name}: {str(e)[:160]}")
            _emit("reset", None)
    raise NoLLMAvailable("All AI providers failed — " + " | ".join(errors))
