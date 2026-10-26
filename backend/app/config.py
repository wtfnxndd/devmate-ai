from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BASE_DIR / ".env", extra="ignore")

    # Free LLM providers (both OpenAI-compatible). Leave blank to run in static-only mode.
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.8-flash,gemini-3.7-flash,gemini-flash-lite-latest"
    groq_api_key: str = ""
    groq_model: str = "llama-3.3-70b-versatile"
    # Optional: local Ollama (future "privacy mode"); empty = disabled.
    ollama_url: str = ""
    ollama_model: str = "qwen2.5-coder:7b"

    # SQLite by default; set to a free Supabase/Neon Postgres URL to deploy.
    database_url: str = f"sqlite:///{BASE_DIR / 'data' / 'devmate.db'}"
    data_dir: Path = BASE_DIR / "data"
    github_token: str = ""

    max_file_bytes: int = 200_000
    rag_top_k: int = 5


settings = Settings()
settings.data_dir.mkdir(parents=True, exist_ok=True)
(settings.data_dir / "projects").mkdir(exist_ok=True)
