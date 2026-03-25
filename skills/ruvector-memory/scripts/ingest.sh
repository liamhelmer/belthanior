#!/usr/bin/env bash
# Ingest memory files into the vector index
# Usage: ingest.sh <file-or-directory>
set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
AGENTDB_DIR="$WORKSPACE/agentdb"
TARGET="${1:?Usage: ingest.sh <file-or-directory>}"

ingest_file() {
  local file="$1"
  local filename
  filename=$(basename "$file")

  # Skip non-markdown and hidden files
  [[ "$filename" == .* ]] && return
  [[ "$filename" != *.md ]] && return

  echo "Ingesting: $file"

  # Split file into paragraphs and index each
  python3 - "$file" "$AGENTDB_DIR" <<'PYEOF'
import sys, subprocess, json, re

filepath = sys.argv[1]
agentdb_dir = sys.argv[2]
source = filepath

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Split on double newlines, filter short chunks
chunks = [c.strip() for c in re.split(r'\n\n+', content) if len(c.strip()) > 60]

for chunk in chunks:
    meta = json.dumps({"source": source, "tags": "ingested", "timestamp": "auto"})
    subprocess.run([
        "npx", "agentdb", "store",
        "--dir", agentdb_dir,
        "--text", chunk,
        "--metadata", meta
    ], capture_output=True, cwd=agentdb_dir)

print(f"  → {len(chunks)} chunks indexed from {filepath}")
PYEOF
}

if [ -f "$TARGET" ]; then
  ingest_file "$TARGET"
elif [ -d "$TARGET" ]; then
  find "$TARGET" -maxdepth 2 -name "*.md" | sort | while read -r f; do
    ingest_file "$f"
  done
else
  echo "ERROR: $TARGET is not a file or directory"
  exit 1
fi

echo "Ingest complete."
