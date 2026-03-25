#!/usr/bin/env bash
# Check AgentDB index status
set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
AGENTDB_DIR="$WORKSPACE/agentdb"

echo "=== RuVector Memory Status ==="
echo "Index dir: $AGENTDB_DIR"

if [ ! -d "$AGENTDB_DIR/.agentdb" ]; then
  echo "STATUS: NOT INITIALIZED — run scripts/setup.sh"
  exit 1
fi

# Count indexed items
cd "$AGENTDB_DIR"
npx agentdb stats --dir "$AGENTDB_DIR" 2>&1 || echo "(stats not available in this agentdb version)"

# Check MCP server
if curl -s --max-time 1 http://localhost:7700/health &>/dev/null; then
  echo "MCP server: RUNNING (port 7700)"
else
  echo "MCP server: NOT RUNNING (start with: npx @ruvector/rvf-mcp-server --transport http --port 7700)"
fi
