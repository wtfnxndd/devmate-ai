#!/bin/bash
# Builds the Flutter web app and deploys it to Cloudflare Pages (free).
# First run opens a browser so you can log in to your Cloudflare account.
set -e
cd "$(dirname "$0")/../frontend"
export PATH="$HOME/development/flutter/bin:$PATH"
PROJECT="${PROJECT:-devmate-ai}"

flutter build web --release
npx --yes wrangler@4 whoami >/dev/null 2>&1 || npx --yes wrangler@4 login
npx --yes wrangler@4 pages project create "$PROJECT" --production-branch main 2>/dev/null || true
npx --yes wrangler@4 pages deploy build/web --project-name "$PROJECT" --branch main --commit-dirty=true
