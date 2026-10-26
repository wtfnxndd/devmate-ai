"""Free LLM access with automatic fallback: Gemini API -> Groq -> (optional) local Ollama.

All three expose an OpenAI-compatible endpoint, so one client library covers them.
Responses are cached in the database, so re-analysing unchanged code costs no API calls.
"""
import hashlib
import logging
import re
import time

from openai import OpenAI

from .config import settings
from .db import LLMCache, SessionLocal

log = logging.getLogger("devmate.llm")

SYSTEM_PROMPT = (
    "You are DevMate AI, a senior software engineer who reviews code, explains bugs, writes documentation "
    "and tests. Be precise, reference file names and line numbers when available, prefer concrete fixes "
    "with code, and answer in GitHub-flavoured Markdown."
)


class NoLLMAvailable(RuntimeError):
    pass


# provider name -> unix time until which it is skipped (free-tier quota exhausted)
_cooldown: dict[str, float] = {}


def _retry_after(err: Exception) -> float:
    """Seconds to wait after a 429, from the provider's RetryInfo when present."""
    m = re.search(r"retry in (?:(\d+)h)?(?:(\d+)m)?([\d.]+)s", str(err))
    if m:
        h, mnt, sec = (float(x) if x else 0 for x in m.groups())
        return h * 3600 + mnt * 60 + sec
    return 60


def _providers():
    p = []
    if settings.gemini_api_key:
        gemini = OpenAI(base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
                        api_key=settings.gemini_api_key, max_retries=0, timeout=45)
        # Comma-separated list: if one free model is overloaded (503), the next one is tried.
        for model in settings.gemini_model.split(","):
            p.append((f"gemini:{model.strip()}", model.strip(), gemini))
    if settings.groq_api_key:
        groq = OpenAI(base_url="https://api.groq.com/openai/v1", api_key=settings.groq_api_key, max_retries=0, timeout=90)
        for model in settings.groq_model.split(","):
            p.append((f"groq:{model.strip()}", model.strip(), groq))
    if settings.ollama_url:
        p.append(("ollama", settings.ollama_model,
                  OpenAI(base_url=settings.ollama_url.rstrip("/") + "/v1", api_key="ollama", timeout=300)))
    return p


def available() -> list:
    return sorted({name.split(':')[0] for name, _, _ in _providers()})


def ask(prompt: str, system: str = SYSTEM_PROMPT, use_cache: bool = True, history: list | None = None) -> str:
    key = hashlib.sha256((system + "\x00" + prompt + str(history or "")).encode()).hexdigest()
    if use_cache:
        with SessionLocal() as db:
            hit = db.get(LLMCache, key)
            if hit:
                return hit.response
    providers = _providers()
    if not providers:
        raise NoLLMAvailable("No LLM configured. Add a free GEMINI_API_KEY or GROQ_API_KEY to backend/.env")
    messages = [{"role": "system", "content": system}, *(history or []), {"role": "user", "content": prompt}]
    errors = []
    for name, model, client in providers:
        if _cooldown.get(name, 0) > time.time():
            errors.append(f"{name}: rate-limited, skipped")
            continue
        try:
            resp = client.chat.completions.create(model=model, messages=messages, temperature=0.2)
            text = resp.choices[0].message.content or ""
            with SessionLocal() as db:
                db.merge(LLMCache(key=key, provider=name, response=text))
                db.commit()
            return text
        except Exception as e:  # rate limit / outage -> try the next free provider
            if "429" in str(e) or "RESOURCE_EXHAUSTED" in str(e):
                _cooldown[name] = time.time() + _retry_after(e)
            log.warning("LLM provider %s failed: %s", name, str(e)[:200])
            errors.append(f"{name}: {str(e)[:160]}")
    raise NoLLMAvailable("All LLM providers failed — " + " | ".join(errors))
