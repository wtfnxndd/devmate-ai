# DevMate AI

**Intelligent Software Review, Debugging & Documentation Assistant**, built entirely on free tools, with no local LLM or GPU required.

```
[ZIP / GitHub / Local folder]
        │
        ▼
[Tree-sitter parser] ──► classes, functions, imports, dependency graph (Mermaid)
        │
        ▼
[Static analysis] ──► Bandit · Ruff · Lizard (complexity) · OWASP regex rules · Semgrep (optional)
        │
        ▼
[ChromaDB + MiniLM CPU embeddings] ──► RAG context
        │
        ▼
[Free LLM: Gemini API → Groq → (optional) Ollama]   ← cached in DB, falls back automatically
        │
  ┌─────┼─────────┬──────────┬──────────┬────────┐
Review  Docs     Tests     Debug      Chat    Health report
        │
        ▼
[Flutter dashboard (Web / Desktop)]
```

## Features (mapped to the synopsis)

| Synopsis objective | Implementation |
|---|---|
| Project-wide analysis | Upload a ZIP, a GitHub link or a local folder. Tree-sitter parses 20+ languages. |
| Bug & vulnerability detection (OWASP Top 10) | Bandit, Ruff (bug, security and smell rules), OWASP regex rules for every language, and optional Semgrep `p/owasp-top-ten`. The LLM explains each issue and gives a fix. |
| Code complexity | Cyclomatic complexity for every function (Lizard), plus long-function and too-many-parameters smells. |
| Automated documentation | AI-written README, an API reference (FastAPI, Flask, Express, Spring and Django routes detected automatically) and a Mermaid architecture diagram. |
| Intelligent debugging | Paste a stack trace. It finds the project frames (Python, Node, Java, Go, …), pulls in related code with RAG, and explains the root cause with a fix. |
| Test generation | Picks the framework per language (pytest, Jest, JUnit, flutter_test, …). It produces a test skeleton offline and full tests with AI. |
| Architecture mapping | Folder tree, internal dependency edges and a Mermaid graph, with a one-click open in Mermaid Live. |
| Contextual project memory | ChromaDB vector store per project, plus persistent chat history. |
| Health report | Score out of 100 with a grade, metric tables and an AI executive summary with recommendations. Downloadable as Markdown. |
| Dependency CVE scan (OWASP A06) | Reads requirements.txt, pyproject.toml, package.json, pubspec.yaml and go.mod, and checks every version against the free **OSV.dev** database. Shows the CVEs and the safe version to upgrade to. |
| One-click AI fix | Every finding has **Fix with AI**, which shows a before/after diff with an explanation. |
| File assistants | For any file: **Explain**, **Refactor**, **Add docs** (docstrings, JSDoc, Dartdoc…) and **Tests**. |
| Health trend | The score is recorded on every re-analysis and charted on the dashboard. |

Every feature works **without any API key** (static mode). Adding a free key adds AI explanations on top.

## Tech stack (all ₹0)

| Layer | Technology |
|---|---|
| Frontend | Flutter (Web & Desktop) |
| Backend | Python 3.11, FastAPI |
| LLM | Google Gemini API (free tier) with Groq (free tier) as fallback. Ollama is optional. |
| Embeddings | all-MiniLM-L6-v2 via ONNX on the CPU (downloaded once, about 80 MB) |
| Vector DB | ChromaDB (embedded) |
| Database | SQLite locally, or free Supabase/Neon PostgreSQL via `DATABASE_URL` |
| Parsing | Tree-sitter (`tree-sitter-language-pack`) |
| Static analysis | Bandit, Ruff, Lizard, and Semgrep (optional) |
| Docs output | Markdown and Mermaid.js |
| VCS | GitHub API (zipball download) |

**Hardware:** any laptop with 8 GB RAM. No GPU is needed.

## Setup

### 1. Backend

```bash
cd backend
python3.11 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env               # then paste your free keys (optional)
uvicorn app.main:app --reload --port 8000
```

Open http://localhost:8000/docs for interactive Swagger API docs.

**Free keys (no credit card):**
- Gemini: https://aistudio.google.com/apikey → `GEMINI_API_KEY`
- Groq: https://console.groq.com/keys → `GROQ_API_KEY`

> Do **not** enable billing in Google Cloud. Without billing, the API cannot charge you; it just rate-limits, and DevMate then falls back to Groq.

Optional: `pip install semgrep` adds OWASP Top-10 Semgrep rules (macOS and Linux only).

### 2. Frontend

Install the Flutter SDK (https://docs.flutter.dev/get-started/install), then:

```bash
cd frontend
flutter create . --platforms=web,macos,windows,linux   # generates platform folders (first time only)
flutter pub get
flutter run -d chrome                                   # or: -d macos / -d windows
```

To point at a deployed backend: `flutter run -d chrome --dart-define=API_URL=https://your-api.onrender.com`

## API overview

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/projects/upload` | Upload a ZIP |
| POST | `/api/projects/github` | `{ "url": "https://github.com/owner/repo" }` |
| POST | `/api/projects/local` | `{ "path": "/abs/path" }` |
| GET | `/api/projects/{id}` | Status (`parsing → analyzing → indexing → ready`) and health score |
| GET | `/api/projects/{id}/structure` · `/analysis` · `/architecture` | Parsed data, findings, and the Mermaid graph |
| POST | `/api/projects/{id}/review` · `/readme` · `/api-docs` · `/report` | AI engines (results are cached; add `?refresh=true` to regenerate) |
| POST | `/api/projects/{id}/tests` | `{ "file": "src/x.py" }` |
| POST | `/api/projects/{id}/debug` | `{ "error": "<stack trace>" }` |
| POST/GET | `/api/projects/{id}/chat` | RAG chat about the codebase |

## Staying within free limits

1. Static tools find the issues, and the LLM only explains the top ones in **one batched call**.
2. RAG sends only the top 5 relevant code chunks, never the whole repository.
3. Every LLM answer is cached in the database by prompt hash, so repeat requests are free.
4. If Gemini is rate-limited, requests switch to Groq automatically.

## Integrations (future scope, implemented)

### GitHub Actions PR-review bot — `integrations/github-action/`
Comments on every pull request with the issues found **only in the lines changed by that PR**, plus AI explanations and fixes. The check fails if the PR adds a new high-severity issue.

1. Push this project to GitHub (for example `your-user/devmate-ai`).
2. In the repository you want reviewed, copy `integrations/github-action/devmate-review.yml` to `.github/workflows/`.
3. Under Settings → Secrets and variables → Actions, add the variable `DEVMATE_REPO=your-user/devmate-ai` and the secret `GEMINI_API_KEY` (optional).

The same review runs locally:

```bash
cd backend && .venv/bin/python -m app.cli review --path /path/to/repo --base origin/main
```

### VS Code extension — `integrations/vscode/`
Click **DevMate** in the status bar, or open the Command Palette (⇧⌘P) and type "DevMate":
- **Analyze Workspace**: findings appear in the Problems panel, and the health score shows in the status bar.
- **Explain Error / Stack Trace**: select an error, right-click, and choose this.
- **Generate Tests for Current File**, **Ask About This Codebase**, **AI Review of Top Issues** and **Generate README**.

Install: copy `package.json` and `extension.js` into `~/.vscode/extensions/devmate.devmate-ai-1.0.0/` and restart VS Code. You can also package it with `npx @vscode/vsce package`. The backend must be running.

## Deploy with Cloudflare (free)

```
Browser ──► Cloudflare Workers static assets (Flutter web app)
   │
   └──► Cloudflare Tunnel ──► your computer: FastAPI backend (locked with an access token)
```

The backend needs Python tools (Tree-sitter, Bandit, ChromaDB) that can't run on Cloudflare Workers. It runs on your machine, and Cloudflare Tunnel publishes it securely with no port forwarding and no account needed.

1. **Frontend, one time:** `./deploy/cloudflare-pages.sh`. It opens a browser to log in to Cloudflare, then deploys with `wrangler deploy` (config in `frontend/wrangler.jsonc`). Live at **https://devmate-ai.way2fashion-ai.workers.dev**.
2. **Backend, whenever you want it online:** `./deploy/cloudflare-tunnel.sh`. It prints a private link like `https://devmate-ai.way2fashion-ai.workers.dev/?api=https://xxxx.trycloudflare.com&token=…`. Open it, and the app remembers the backend URL and token.

When the backend runs through the tunnel it requires the access token (stored in `backend/.api_token`), and **local-folder import is disabled**, so nobody can read files on your computer.

Requires `cloudflared` (`~/development/bin/cloudflared`) and Node.js for `npx wrangler`.

## Other free deployment options

- **Backend:** Render, Koyeb or Hugging Face Spaces (free tier). Start command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
- **Database:** Supabase or Neon free Postgres. Set `DATABASE_URL`.
- **Frontend:** `flutter build web --dart-define=API_URL=...`, then deploy `build/web` to GitHub Pages, Netlify or Vercel.

## Try it

`sample_project/` is a small shop app with deliberate bugs: SQL injection, a hard-coded password, MD5 hashing, `eval`, a division by zero and unused variables. Import it via **Local folder** to see every engine work.
