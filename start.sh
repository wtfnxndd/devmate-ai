#!/bin/bash
# Starts the DevMate backend (port 8000) and the Flutter web app (port 5173).
cd "$(dirname "$0")"
export PATH="$HOME/development/flutter/bin:$PATH"

# Stop any copies already running on our ports.
for port in 8000 5173; do
  pids=$(lsof -ti tcp:$port)
  [ -n "$pids" ] && kill $pids && sleep 1
done

[ -d frontend/build/web ] || (cd frontend && flutter build web --dart-define=API_URL=http://localhost:8000)

(cd backend && .venv/bin/uvicorn app.main:app --port 8000) &
(cd frontend/build/web && python3 -m http.server 5173) &
sleep 3
open http://localhost:5173
wait
