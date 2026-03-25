#!/usr/bin/env bash
# Setup RuVector/AgentDB for agent memory
set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
AGENTDB_DIR="$WORKSPACE/agentdb"

echo "=== RuVector Memory Setup ==="

# Check node
if ! command -v node &>/dev/null; then
  echo "ERROR: node not found. Install Node.js first."
  exit 1
fi

# Install agentdb
echo "Installing AgentDB..."
npm install -g agentdb@alpha 2>&1 | tail -3

# Install ruvector MCP server
echo "Installing RuVector MCP server..."
npm install -g @ruvector/rvf-mcp-server 2>&1 | tail -3

# Init agentdb workspace
mkdir -p "$AGENTDB_DIR"
cd "$AGENTDB_DIR"

if [ ! -f ".agentdb/config.json" ]; then
  echo "Initializing AgentDB..."
  npx agentdb init --dir "$AGENTDB_DIR" 2>&1 || echo "(init output above)"
else
  echo "AgentDB already initialized at $AGENTDB_DIR"
fi

# Ingest existing memory files
echo ""
echo "Ingesting existing memory files..."
if [ -f "$WORKSPACE/MEMORY.md" ]; then
  bash "$(dirname "$0")/ingest.sh" "$WORKSPACE/MEMORY.md"
fi
if [ -d "$WORKSPACE/memory" ]; then
  bash "$(dirname "$0")/ingest.sh" "$WORKSPACE/memory/"
fi

echo ""
echo "=== Setup complete ==="
echo "Index location: $AGENTDB_DIR"
echo "Run: bash scripts/status.sh to verify"
