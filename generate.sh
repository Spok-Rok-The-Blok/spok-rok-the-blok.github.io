#!/usr/bin/env bash
# generate.sh — Nightly content generation via Ollama
# Niche: AI Tools for Small Business / Solopreneurs
# Strategy: 1 quality article/night. Structured template. HCU-safe.
# Usage: ./generate.sh [keyword] [count]
# Cron: 0 2 * * * cd /home/charlie/.openclaw/workspace/blog && ./generate.sh >> ./generate.log 2>&1

set -e

MODEL="llama3.2:3b"
CONTENT_DIR="./content/posts"
LOG="./generate.log"
KEYWORDS_FILE="./keywords.txt"
USED_KEYWORDS_FILE="./used-keywords.txt"
COUNT="${2:-1}"

mkdir -p "$CONTENT_DIR"
touch "$USED_KEYWORDS_FILE"

echo "[$(date)] === Starting generation run ===" | tee -a "$LOG"

# Check Ollama is running
if ! curl -sf http://localhost:11434/api/tags > /dev/null; then
  echo "[$(date)] ERROR: Ollama not running. Skipping." | tee -a "$LOG"
  exit 1
fi

# Get next unused keyword
if [ -n "$1" ]; then
  KEYWORD="$1"
else
  KEYWORD=$(grep -vFf "$USED_KEYWORDS_FILE" "$KEYWORDS_FILE" 2>/dev/null | head -1)
fi

if [ -z "$KEYWORD" ]; then
  echo "[$(date)] No unused keywords left. Add more to keywords.txt" | tee -a "$LOG"
  exit 0
fi

echo "[$(date)] Keyword: $KEYWORD" | tee -a "$LOG"

ollama_query() {
  local prompt="$1"
  curl -sf http://localhost:11434/api/generate \
    -d "{\"model\": \"$MODEL\", \"prompt\": $(echo "$prompt" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))"), \"stream\": false}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['response'].strip())"
}

# Step 1: Generate title
echo "[$(date)] Generating title..." | tee -a "$LOG"
TITLE=$(ollama_query "Write ONE SEO-optimized blog post title for this exact keyword: '$KEYWORD'. The title should be specific, practical, and appeal to small business owners. Use 2026 as the year (not 2024 or 2025). Format: 'Best [X] for Small Business in 2026: [Benefit or Comparison]' or similar. Return ONLY the title, no quotes, nothing else.")

if [ -z "$TITLE" ]; then
  echo "[$(date)] ERROR: Empty title. Skipping." | tee -a "$LOG"
  exit 1
fi
echo "[$(date)] Title: $TITLE" | tee -a "$LOG"

# Step 2: Generate structured article (HCU-safe template)
echo "[$(date)] Generating article body..." | tee -a "$LOG"
BODY=$(ollama_query "Write a detailed, helpful blog post titled: '$TITLE'

Use this EXACT structure (required). Do NOT include the title again at the top.

## What Is [Topic]?
(2-3 sentences explaining it plainly for a non-technical small business owner. No jargon.)

## Who Should Use This?
(bullet list: 3-4 specific ideal use cases — mention business types, team sizes, specific pain points)

## Who Should NOT Use This?
(bullet list: 2-3 honest cases where this is a bad fit. Be direct.)

## Top Options Compared
(markdown table with columns: Tool | Price/Month | Best For | Key AI Feature — list 3-4 real tools)

## Our Top Pick: [Tool Name]
(explain why it wins for most small businesses. Mention $AFFILIATE as a runner-up or complementary tool where relevant. Include specific features and real pricing.)

## Pricing Breakdown
(bullet list or table: each plan name, price, and what you actually get. Be specific.)

## Verdict
(2-3 sentence honest bottom line. End with a clear action: 'Try [tool] free for 14 days' or similar.)

Important rules:
- Use 2026 (not 2024 or 2025) for any year references
- Write for small business owners, not developers
- Be specific — name real tools, real prices, real features
- No generic filler like 'In today's fast-paced world...'
- Target 700-900 words
- Format in clean Markdown")

if [ -z "$BODY" ]; then
  echo "[$(date)] ERROR: Empty body. Skipping." | tee -a "$LOG"
  exit 1
fi

# Step 3: Write Hugo post
SLUG=$(echo "$KEYWORD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | cut -c1-60)
DATE=$(date +%Y-%m-%d)
FILENAME="${CONTENT_DIR}/${DATE}-${SLUG}.md"

# Affiliate links
SYSTEME_URL="https://systeme.io/?sa=sa0267131685129e77387d3fa97cf89da7b07af0d7"
FRASE_URL=""       # TODO: add when available
SEMRUSH_URL=""     # TODO: add when available
HUBSPOT_URL=""     # TODO: add when available
GETRESPONSE_URL="" # TODO: add when available

# Pick primary affiliate based on keyword content
AFFILIATE=""
AFFILIATE_URL=""
case "$KEYWORD" in
  *CRM*|*crm*) AFFILIATE="HubSpot" ; AFFILIATE_URL="$HUBSPOT_URL" ;;
  *SEO*|*seo*|*semrush*) AFFILIATE="SEMrush" ; AFFILIATE_URL="$SEMRUSH_URL" ;;
  *email*|*Email*) AFFILIATE="GetResponse" ; AFFILIATE_URL="$GETRESPONSE_URL" ;;
  *accounting*|*bookkeeping*|*invoice*|*payroll*) AFFILIATE="Systeme.io" ; AFFILIATE_URL="$SYSTEME_URL" ;;
  *project*|*manage*) AFFILIATE="Notion" ; AFFILIATE_URL="$SYSTEME_URL" ;;
  *writing*|*content*|*copy*) AFFILIATE="Writesonic" ; AFFILIATE_URL="$FRASE_URL" ;;
  *landing*|*site*|*builder*) AFFILIATE="10Web" ; AFFILIATE_URL="$SYSTEME_URL" ;;
  *) AFFILIATE="Systeme.io" ; AFFILIATE_URL="$SYSTEME_URL" ;;
esac

# Strip any surrounding quotes from title
TITLE="${TITLE#\"}"
TITLE="${TITLE%\"}"
TITLE="${TITLE#\'}"
TITLE="${TITLE%\'}"

cat > "$FILENAME" << FRONTMATTER
---
title: "$TITLE"
date: $DATE
draft: false
description: "Honest review and comparison of ${KEYWORD} options for small business owners in 2026."
categories: ["AI Tools", "Small Business"]
tags: ["small business", "AI tools", "review"]
affiliate: "$AFFILIATE"
affiliateUrl: "$AFFILIATE_URL"
---

$BODY

---
*This post contains affiliate links. We may earn a commission if you purchase through our links, at no extra cost to you.*
FRONTMATTER

echo "[$(date)] Saved: $FILENAME" | tee -a "$LOG"

# Mark keyword as used
echo "$KEYWORD" >> "$USED_KEYWORDS_FILE"
echo "[$(date)] === Run complete ===" | tee -a "$LOG"
