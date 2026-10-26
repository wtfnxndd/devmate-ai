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
trap 'kill $BACKEND $TUNNEL 2>/dev/null; (cd ../frontend && npx --yes wrangler@4 kv key delete --binding DEVMATE_CONFIG --remote api_url >/dev/null 2>&1)' EXIT

for _ in $(seq 1 30); do
  URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1)
  [ -n "$URL" ] && break
  sleep 1
done
[ -z "$URL" ] && { echo "Tunnel failed to start, see $LOG"; exit 1; }

# Publish the new address so the permanent site link finds this backend automatically.
(cd ../frontend && npx --yes wrangler@4 kv key put --binding DEVMATE_CONFIG --remote api_url "$URL" >/dev/null 2>&1) \
  && PUBLISHED=1 || echo "(Could not publish the URL to Cloudflare; use the full link below.)"

echo
echo "DevMate backend is online."
echo
if [ -n "$PUBLISHED" ]; then
  echo "Open:  $PAGES_URL"
  echo
  echo "First time on a new browser/device? Open this once to save the access token (keep it private):"
fi
echo "  $PAGES_URL/?api=$URL&token=$TOKEN"
echo
echo "Keep this window open. Press Ctrl+C to stop."
wait $TUNNEL
