#!/usr/bin/env bash
# Setup RuVector/AgentDB for agent memory
set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
DB="$WORKSPACE/agentdb/memory.db"

echo "=== RuVector Memory Setup ==="

# Install agentdb
echo "Installing AgentDB (latest alpha)..."
npm install -g agentdb@3.0.0-alpha.10 better-sqlite3 2>&1 | tail -3

# Install real ML embeddings
echo "Installing embeddings..."
agentdb install-embeddings --global 2>&1 | tail -3

# Init DB
mkdir -p "$(dirname "$DB")"
if [ ! -f "$DB" ]; then
  echo "Initializing AgentDB at $DB..."
  agentdb init "$DB" --model Xenova/bge-small-en-v1.5 --dimension 384
else
  echo "AgentDB already exists at $DB"
fi

# Ingest existing memory files
echo ""
echo "Ingesting existing memory files..."
bash "$(dirname "$0")/ingest.sh" "$WORKSPACE/MEMORY.md" 2>/dev/null || true
[ -d "$WORKSPACE/memory" ] && bash "$(dirname "$0")/ingest.sh" "$WORKSPACE/memory/" || true

echo ""
agentdb status --db "$DB"
echo "=== Setup complete ==="
