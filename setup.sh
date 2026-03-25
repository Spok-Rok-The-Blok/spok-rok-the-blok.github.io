#!/usr/bin/env bash
# setup.sh — Run this once after installing Hugo to initialize the site
# Prerequisites: sudo apt-get install -y hugo

set -e
BLOG_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BLOG_DIR"

echo "Setting up Hugo site..."

# Init Hugo site (in current dir, force overwrite of existing files)
hugo new site . --force

# Install a clean, fast theme (Ananke is well-supported and SEO-friendly)
git init 2>/dev/null || true
git submodule add https://github.com/theNewDynamic/gohugo-theme-ananke.git themes/ananke 2>/dev/null || \
  echo "Theme already exists, skipping"

# Write config
cat > hugo.toml << 'CONFIG'
baseURL = "https://YOUR-DOMAIN.github.io/"
languageCode = "en-us"
title = "AI Tools for Small Business"
theme = "ananke"

[params]
  description = "Honest reviews and comparisons of AI tools for small business owners and solopreneurs."
  author = "Spok HQ Research Team"
  featured_image = ""
  recent_posts_number = 5

[markup]
  [markup.goldmark]
    [markup.goldmark.renderer]
      unsafe = true

[taxonomies]
  category = "categories"
  tag = "tags"
CONFIG

echo "Hugo site initialized."
echo ""
echo "Next steps:"
echo "  1. Edit hugo.toml and set your baseURL to your GitHub Pages domain"
echo "  2. Run: ./generate.sh  (generates first article)"
echo "  3. Run: hugo server -D  (preview locally)"
echo "  4. Set up GitHub repo + Pages (see README)"
echo "  5. Add cron job: crontab -e"
echo "     0 2 * * * cd $BLOG_DIR && ./generate.sh >> ./generate.log 2>&1"
echo "     30 2 * * * cd $BLOG_DIR && hugo && git add -A && git commit -m 'nightly build' && git push"
