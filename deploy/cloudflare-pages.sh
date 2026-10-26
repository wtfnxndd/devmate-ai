#!/bin/bash
# Builds the Flutter web app and deploys it to Cloudflare (Workers static assets, free tier).
# Config: frontend/wrangler.jsonc. First run opens a browser so you can log in to Cloudflare.
set -e
cd "$(dirname "$0")/../frontend"
export PATH="$HOME/development/flutter/bin:$PATH"

flutter build web --release
npx --yes wrangler@4 whoami >/dev/null 2>&1 || npx --yes wrangler@4 login
npx --yes wrangler@4 deploy
