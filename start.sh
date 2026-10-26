#!/bin/bash
# Runs DevMate locally: backend on :8000, web app on :5173.
cd "$(dirname "$0")"

# Stop any copies already running on our ports.
for port in 8000 5173; do
  pids=$(lsof -ti tcp:$port)
  [ -n "$pids" ] && kill $pids && sleep 1
done

[ -d web/dist ] || (cd web && npm install --silent && npm run build)

(cd backend && .venv/bin/uvicorn app.main:app --port 8000) &
(cd web && npx vite preview --port 5173 --strictPort) &
sleep 3
open "http://localhost:5173/?api=http://localhost:8000&token="
wait
