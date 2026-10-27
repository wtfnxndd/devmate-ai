#!/bin/bash
# Puts the DevMate backend online through a free Cloudflare quick tunnel.
# - The API is locked with an access token and local-folder import is disabled.
# - The tunnel address is published to Cloudflare KV, so the site link never changes.
# - Self-healing: if the tunnel dies or expires (e.g. after the Mac sleeps), a new one is started
#   and its address is published again automatically.
cd "$(dirname "$0")/../backend"
CLOUDFLARED="${CLOUDFLARED:-$HOME/development/bin/cloudflared}"
SITE_URL="${SITE_URL:-https://devmate-ai.rn4263313.workers.dev}"
LOG=/tmp/devmate-tunnel.log

TOKEN_FILE=.api_token
[ -f "$TOKEN_FILE" ] || python3 -c "import secrets; print(secrets.token_urlsafe(24))" > "$TOKEN_FILE"
TOKEN=$(cat "$TOKEN_FILE")

publish() { (cd ../web && npx --yes wrangler@4 kv key put --binding DEVMATE_CONFIG --remote api_url "$1" >/dev/null 2>&1); }
unpublish() { (cd ../web && npx --yes wrangler@4 kv key delete --binding DEVMATE_CONFIG --remote api_url >/dev/null 2>&1); }

# Stop anything already on the port, then start the locked-down backend.
pids=$(lsof -ti tcp:8000 || true); [ -n "$pids" ] && kill $pids && sleep 1
start_backend() {
  API_TOKEN="$TOKEN" ALLOW_LOCAL_IMPORT=false .venv/bin/uvicorn app.main:app --port 8000 >> /tmp/devmate-backend.log 2>&1 &
  BACKEND=$!
}
start_backend

TUNNEL=""
cleanup() { kill $BACKEND $TUNNEL 2>/dev/null; unpublish; exit 0; }
trap cleanup INT TERM EXIT

start_tunnel() {
  [ -n "$TUNNEL" ] && kill $TUNNEL 2>/dev/null
  : > "$LOG"
  "$CLOUDFLARED" tunnel --no-autoupdate --url http://localhost:8000 >> "$LOG" 2>&1 &
  TUNNEL=$!
  URL=""
  for _ in $(seq 1 40); do
    URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1)
    [ -n "$URL" ] && break
    sleep 1
  done
  if [ -z "$URL" ]; then echo "$(date +%H:%M) Tunnel failed to start; retrying in 30s"; return 1; fi
  if publish "$URL"; then
    echo "$(date +%H:%M) Online at $SITE_URL  (tunnel: $URL)"
  else
    echo "$(date +%H:%M) Online, but could not publish the address. Use: $SITE_URL/?api=$URL&token=$TOKEN"
  fi
}

start_tunnel
echo
echo "DevMate is online:  $SITE_URL"
echo "First time on a new browser/device? Open this once (keep it private, it has the access token):"
echo "  $SITE_URL/?token=$TOKEN"
echo
echo "Keep this window open. Press Ctrl+C to stop. The tunnel restarts itself if it drops."

# Watchdog: restart the backend or tunnel if either dies or Cloudflare forgets the tunnel.
while true; do
  sleep 30
  if ! kill -0 $BACKEND 2>/dev/null; then echo "$(date +%H:%M) Backend stopped; restarting"; start_backend; fi
  if ! kill -0 $TUNNEL 2>/dev/null || grep -q "Tunnel not found" "$LOG" \
     || ! curl -s -m 10 -o /dev/null "$URL/api/health"; then
    echo "$(date +%H:%M) Tunnel lost; starting a new one"
    start_tunnel || sleep 30
  fi
done
