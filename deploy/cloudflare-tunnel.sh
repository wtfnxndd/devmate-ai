#!/bin/bash
# Exposes the DevMate backend on the internet through a free Cloudflare quick tunnel.
# The API is locked with a random access token and local-folder import is disabled,
# so nobody can read files from this computer through the public URL.
set -e
cd "$(dirname "$0")/../backend"
CLOUDFLARED="${CLOUDFLARED:-$HOME/development/bin/cloudflared}"
PAGES_URL="${PAGES_URL:-https://devmate-ai.rn4263313.workers.dev}"

TOKEN_FILE=.api_token
[ -f "$TOKEN_FILE" ] || python3 -c "import secrets; print(secrets.token_urlsafe(24))" > "$TOKEN_FILE"
TOKEN=$(cat "$TOKEN_FILE")

# Stop anything already on the port, then start the locked-down backend.
pids=$(lsof -ti tcp:8000 || true); [ -n "$pids" ] && kill $pids && sleep 1
API_TOKEN="$TOKEN" ALLOW_LOCAL_IMPORT=false .venv/bin/uvicorn app.main:app --port 8000 > /tmp/devmate-backend.log 2>&1 &
BACKEND=$!
trap 'kill $BACKEND 2>/dev/null' EXIT

LOG=/tmp/devmate-tunnel.log
"$CLOUDFLARED" tunnel --no-autoupdate --url http://localhost:8000 > "$LOG" 2>&1 &
TUNNEL=$!
trap 'kill $BACKEND $TUNNEL 2>/dev/null' EXIT

for _ in $(seq 1 30); do
  URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1)
  [ -n "$URL" ] && break
  sleep 1
done
[ -z "$URL" ] && { echo "Tunnel failed to start, see $LOG"; exit 1; }

echo
echo "Backend is public at: $URL"
echo
echo "Open DevMate (keep this link private, it contains the access token):"
echo "  $PAGES_URL/?api=$URL&token=$TOKEN"
echo
echo "Press Ctrl+C to stop."
wait $TUNNEL
