#!/usr/bin/env bash
# Ingest memory markdown files into AgentDB as reflexion episodes
# Usage: ingest.sh <file-or-directory>
set -euo pipefail

DB="${AGENTDB_PATH:-$HOME/.openclaw/workspace/agentdb/memory.db}"
TARGET="${1:?Usage: ingest.sh <file-or-directory>}"

ingest_file() {
  local file="$1"
  local filename
  filename=$(basename "$file")
  [[ "$filename" == .* ]] && return
  [[ "$filename" != *.md ]] && return

  echo "Ingesting: $file"

  python3 - "$file" "$DB" <<'PYEOF'
import sys, subprocess, re, os

filepath = sys.argv[1]
db = sys.argv[2]
source = os.path.basename(filepath)

with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Split on double newlines, skip short/empty chunks
chunks = [c.strip() for c in re.split(r'\n\n+', content) if len(c.strip()) > 60]

stored = 0
for i, chunk in enumerate(chunks):
    session_id = f"ingest-{source}-{i}"
    result = subprocess.run([
        "agentdb", "reflexion", "store",
        session_id,       # session-id
        chunk,            # task (text)
        "0.8",            # reward
        "true",           # success
        f"source:{source} ingested:true",  # critique/metadata
        db                # db path (positional if --db not supported)
    ], capture_output=True, text=True)
    # Try --db flag if positional fails
    if result.returncode != 0:
        result = subprocess.run([
            "agentdb", "reflexion", "store",
            session_id, chunk, "0.8", "true",
            f"source:{source} ingested:true",
            "--db", db
        ], capture_output=True, text=True)
    if result.returncode == 0:
        stored += 1

print(f"  → {stored}/{len(chunks)} chunks indexed from {filepath}")
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
