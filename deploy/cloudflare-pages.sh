#!/bin/bash
# Builds the React web app and deploys it to Cloudflare (Workers static assets, free tier).
# Config: web/wrangler.jsonc. First run opens a browser so you can log in to Cloudflare.
set -e
cd "$(dirname "$0")/../web"
npm install --silent
npm run build
npx --yes wrangler@4 whoami >/dev/null 2>&1 || npx --yes wrangler@4 login
npx --yes wrangler@4 deploy
