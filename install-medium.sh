#!/usr/bin/env bash
# install-medium.sh — One-time setup for Medium Playwright publisher
set -e

cd /home/charlie/.openclaw/workspace/blog

echo "Installing Playwright..."
npm install

echo "Installing Chromium browser..."
npx playwright install chromium

echo "Done. Test with:"
echo "  node medium-publish.js https://the-age-of-ai.github.io/posts/SOME-POST/ https://the-age-of-ai.github.io/posts/SOME-POST/"
