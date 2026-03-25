#!/usr/bin/env bash
# vector_search.sh — Treatment: AgentDB vector search over memory
# Usage: vector_search.sh "query" [limit]
# Returns JSON array of {text, score, source} results
#
# Uses `agentdb reflexion retrieve` which outputs rich text.
# We parse the ANSI-colored output to extract Task and Similarity fields.

set -euo pipefail

QUERY="${1:?Usage: vector_search.sh \"query\" [limit]}"
LIMIT="${2:-5}"
DB="/home/openclaw/.openclaw/workspace/agentdb/memory.db"

# Run reflexion retrieve and strip ANSI codes
RAW=$(agentdb reflexion retrieve "$QUERY" --k "$LIMIT" --db "$DB" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

# Parse the text output into JSON
echo "$RAW" | python3 -c "
import sys, json, re

raw = sys.stdin.read()
results = []

# Split into episode blocks (delimited by horizontal rules)
# Each episode starts with '#N: Episode M' and contains Task:, Similarity: fields
blocks = re.split(r'[─═]{10,}', raw)

for block in blocks:
    block = block.strip()
    if not block:
        continue

    # Only process blocks that contain an Episode marker
    if not re.search(r'#\d+:\s*Episode\s+\d+', block):
        continue

    # Extract task text (everything after 'Task:' until next field)
    task_match = re.search(r'Task:\s*(.*?)(?=\n\s*(?:Reward|Success|Similarity|Critique):|\Z)', block, re.DOTALL)
    if not task_match:
        continue

    task_text = task_match.group(1).strip()
    if not task_text:
        continue

    # Extract similarity score
    sim_match = re.search(r'Similarity:\s*([\d.]+)', block)
    similarity = float(sim_match.group(1)) if sim_match else 0.0

    results.append({
        'text': task_text,
        'score': similarity,
        'source': 'vector'
    })

print(json.dumps(results))
"
