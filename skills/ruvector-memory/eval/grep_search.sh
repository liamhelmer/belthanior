#!/usr/bin/env bash
# grep_search.sh — Baseline: grep/ripgrep over workspace memory files
# Usage: grep_search.sh "query" [limit]
# Returns JSON array of {text, score} chunks ranked by keyword match count

set -euo pipefail

QUERY="${1:?Usage: grep_search.sh \"query\" [limit]}"
LIMIT="${2:-5}"
WORKSPACE="/home/openclaw/.openclaw/workspace"
MEMORY_FILES=("$WORKSPACE/MEMORY.md")

# Add all memory/*.md files
for f in "$WORKSPACE"/memory/*.md; do
    [[ -f "$f" ]] && MEMORY_FILES+=("$f")
done

# Step 1: Extract keywords from query (lowercase, remove stopwords, min 3 chars)
STOPWORDS="what|which|where|when|how|does|did|the|a|an|is|are|was|were|has|have|had|do|for|of|in|on|to|and|or|not|that|this|with|from|its|it|be|been|being|but|by|can|could|if|into|may|than|then|them|they|will|would|about|between|each|other|some|such|there|these|also|just|any|all"

KEYWORDS=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | grep -vwE "^($STOPWORDS)$" | awk 'length >= 3' | sort -u)

if [[ -z "$KEYWORDS" ]]; then
    echo "[]"
    exit 0
fi

# Step 2: Split each memory file into chunks (by ## headings or blank-line-separated paragraphs)
# Each chunk is ~5-20 lines for meaningful context
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

chunk_id=0
for file in "${MEMORY_FILES[@]}"; do
    [[ -f "$file" ]] || continue
    basename=$(basename "$file")

    # Split on ## headings, keeping heading with content
    awk -v prefix="$TMPDIR/chunk_${basename}_" -v cid="$chunk_id" '
    BEGIN { current_chunk = ""; chunk_num = cid }
    /^##[^#]/ {
        if (current_chunk != "") {
            fname = prefix chunk_num ".txt"
            print current_chunk > fname
            close(fname)
            chunk_num++
        }
        current_chunk = $0 "\n"
        next
    }
    {
        if (current_chunk == "" && NF > 0) {
            current_chunk = $0 "\n"
        } else {
            current_chunk = current_chunk $0 "\n"
        }
    }
    END {
        if (current_chunk != "") {
            fname = prefix chunk_num ".txt"
            print current_chunk > fname
            close(fname)
            chunk_num++
        }
        print chunk_num > "/dev/stderr"
    }
    ' "$file" 2>"$TMPDIR/last_cid_${basename}.txt"

    last_cid=$(cat "$TMPDIR/last_cid_${basename}.txt" 2>/dev/null || echo "$chunk_id")
    chunk_id=$last_cid
done

# Step 3: Score each chunk by counting keyword matches
declare -A CHUNK_SCORES

for chunk_file in "$TMPDIR"/chunk_*.txt; do
    [[ -f "$chunk_file" ]] || continue
    score=0
    chunk_text=$(cat "$chunk_file")
    chunk_lower=$(echo "$chunk_text" | tr '[:upper:]' '[:lower:]')

    while IFS= read -r keyword; do
        [[ -z "$keyword" ]] && continue
        # Count occurrences of keyword in chunk (case-insensitive)
        count=$(echo "$chunk_lower" | grep -oc "$keyword" 2>/dev/null || true)
        score=$((score + count))
    done <<< "$KEYWORDS"

    if [[ $score -gt 0 ]]; then
        CHUNK_SCORES["$chunk_file"]=$score
    fi
done

# Step 4: Sort by score descending, take top N, output as JSON
results="["
first=true
count=0

# Sort chunks by score
for chunk_file in $(for k in "${!CHUNK_SCORES[@]}"; do echo "${CHUNK_SCORES[$k]} $k"; done | sort -rn | head -n "$LIMIT" | awk '{print $2}'); do
    score=${CHUNK_SCORES[$chunk_file]}
    text=$(cat "$chunk_file" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")

    if [[ "$first" == "true" ]]; then
        first=false
    else
        results+=","
    fi

    results+="{\"text\":$text,\"score\":$score,\"source\":\"grep\"}"
    count=$((count + 1))
done

results+="]"
echo "$results"
