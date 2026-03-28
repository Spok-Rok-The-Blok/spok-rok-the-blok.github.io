#!/usr/bin/env bash
# trend-queue.sh — Trending topic scanner + queue prioritizer
# Checks GitHub trending, Reddit, and news for topics matching our product articles
# Bumps matching articles to the front of the publish queue
# Runs daily at 5:50 AM (before morning brief at 6 AM)

set -e

BLOG_DIR="/home/charlie/.openclaw/workspace/blog"
QUEUE_DIR="$BLOG_DIR/product-articles"
STATE_FILE="$QUEUE_DIR/queue-state.json"
TREND_LOG="$BLOG_DIR/trend.log"
TREND_STATE="$QUEUE_DIR/trend-state.json"

source /home/charlie/.openclaw/secrets.env

echo "[$(date)] === Trend scanner starting ===" | tee -a "$TREND_LOG"

# ── 1. Fetch trending topics ──────────────────────────────────────────────

# GitHub trending (scrape text from trending page)
GH_TRENDING=$(curl -s "https://github.com/trending" \
  -H "User-Agent: Mozilla/5.0" \
  | python3 -c "
import sys, re
html = sys.stdin.read()
# Extract repo names and descriptions
repos = re.findall(r'<h2[^>]*>.*?<a[^>]*>([^<]+)</a>', html, re.DOTALL)
descs = re.findall(r'<p[^>]*class=\"col-9[^\"]*\"[^>]*>\s*([^<]+)\s*</p>', html)
for r in repos[:10]:
    print(r.strip().replace('\n','').replace('  ',''))
for d in descs[:10]:
    print(d.strip())
" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')

# Reddit RSS feeds — top posts from relevant subs
REDDIT_TOPICS=""
for sub in "entrepreneur" "artificial" "ChatGPT" "freelance" "sidehustle"; do
  FEED=$(curl -s "https://www.reddit.com/r/$sub/hot.json?limit=5" \
    -H "User-Agent: Mozilla/5.0" \
    | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    posts=d['data']['children']
    for p in posts:
        print(p['data']['title'].lower())
except:
    pass
" 2>/dev/null)
  REDDIT_TOPICS="$REDDIT_TOPICS $FEED"
done

# Combine all trending text
ALL_TRENDS="$GH_TRENDING $REDDIT_TOPICS"
echo "[$(date)] Trend corpus: $(echo $ALL_TRENDS | wc -w) words" | tee -a "$TREND_LOG"

# ── 2. Score each queued article against trends ───────────────────────────

SCORED=$(python3 << PYEOF
import os, re, json

queue_dir = "$QUEUE_DIR"
trends = """$ALL_TRENDS""".lower()

# Keywords for each product (maps to article filename patterns)
product_keywords = {
    "chatgpt":       ["chatgpt", "gpt", "openai", "prompt", "prompts"],
    "email":         ["email", "newsletter", "outreach", "cold email"],
    "ai-tools":      ["ai tools", "artificial intelligence", "automation"],
    "workflows":     ["workflow", "automation", "agent", "productivity"],
    "blueprint":     ["solopreneur", "one person", "solo", "build in public"],
    "openclaw":      ["ai agent", "personal assistant", "openclaw"],
    "freelancer":    ["freelance", "freelancer", "proposal", "rate", "client"],
    "content":       ["content", "social media", "calendar", "posting"],
    "customer":      ["customer service", "support", "ecommerce", "shopify"],
    "legal":         ["legal", "contract", "nda", "freelancer"],
    "etsy":          ["etsy", "digital product", "seller", "shop"],
    "outreach":      ["cold outreach", "linkedin", "dm", "sales"],
    "coaches":       ["coach", "coaching", "consultant", "consulting"],
    "youtube":       ["youtube", "video", "creator", "channel"],
    "real-estate":   ["real estate", "realtor", "property", "listing"],
    "notion":        ["notion", "template", "productivity", "freelance"],
    "repurposing":   ["repurpose", "content repurposing", "reuse content"],
    "instagram":     ["instagram", "reels", "caption", "social"],
    "seo":           ["seo", "search engine", "google", "keywords", "blog"],
    "course":        ["course", "online course", "creator", "teach"],
    "onboarding":    ["onboarding", "client", "freelance"],
    "productivity":  ["productivity", "system", "workflow", "solopreneur"],
    "newsletter":    ["newsletter", "email list", "substack"],
    "side-hustle":   ["side hustle", "passive income", "extra income"],
    "linkedin":      ["linkedin", "b2b", "professional"],
    "podcast":       ["podcast", "launch", "audio"],
    "pricing":       ["pricing", "rates", "freelance", "charge"],
    "launch":        ["launch", "digital product", "gumroad"],
    "pinterest":     ["pinterest", "pin", "visual"],
    "therapists":    ["therapist", "coach", "mental health", "therapy"],
}

# Get queued articles
articles = sorted([f for f in os.listdir(queue_dir) if f.endswith('.md') and 'published' not in f])

scores = []
for article in articles:
    best_score = 0
    best_match = ""
    for key, kws in product_keywords.items():
        if any(k in article for k in key.split('-')):
            score = sum(trends.count(kw) for kw in kws)
            if score > best_score:
                best_score = score
                best_match = ", ".join([kw for kw in kws if trends.count(kw) > 0])
    scores.append((best_score, article, best_match))

scores.sort(reverse=True)
result = {"ranked": [], "topMatch": None}
for score, article, match in scores:
    result["ranked"].append({"file": article, "score": score, "matchedOn": match})

if scores and scores[0][0] > 0:
    result["topMatch"] = scores[0][1]
    result["topMatchScore"] = scores[0][0]
    result["topMatchKeywords"] = scores[0][2]

print(json.dumps(result, indent=2))
PYEOF
)

echo "$SCORED" > "$TREND_STATE"
echo "[$(date)] Scoring complete" | tee -a "$TREND_LOG"

# ── 3. Reorder queue — move top trending article to front ─────────────────
TOP_MATCH=$(echo "$SCORED" | python3 -c "
import sys,json
d=json.load(sys.stdin)
tm=d.get('topMatch')
score=d.get('topMatchScore',0)
kws=d.get('topMatchKeywords','')
if tm and score > 0:
    print(f'{tm}||{score}||{kws}')
" 2>/dev/null || echo "")

if [ -n "$TOP_MATCH" ]; then
    TOP_FILE=$(echo "$TOP_MATCH" | cut -d'|' -f1)
    TOP_SCORE=$(echo "$TOP_MATCH" | cut -d'|' -f3)
    TOP_KWS=$(echo "$TOP_MATCH" | cut -d'|' -f5)

    # Rename to sort first (prefix with 000-)
    if [ -f "$QUEUE_DIR/$TOP_FILE" ] && [[ "$TOP_FILE" != 000-* ]]; then
        # Remove any previous priority prefix
        for f in "$QUEUE_DIR"/000-*.md; do
            [ -f "$f" ] && mv "$f" "$QUEUE_DIR/$(basename $f | sed 's/^000-//')"
        done
        mv "$QUEUE_DIR/$TOP_FILE" "$QUEUE_DIR/000-$TOP_FILE"
        echo "[$(date)] TRENDING: Promoted '$TOP_FILE' (score: $TOP_SCORE, keywords: $TOP_KWS)" | tee -a "$TREND_LOG"
    fi
else
    echo "[$(date)] No strong trend match — queue unchanged" | tee -a "$TREND_LOG"
fi

echo "[$(date)] === Trend scanner done ===" | tee -a "$TREND_LOG"
