# AgentDB Reference

AgentDB (`npm install agentdb@alpha`) is the agent-memory layer built on RuVector. It provides persistent, self-learning vector memory — search quality improves with every query.

## Core Concepts

- **Chunks**: Text snippets stored with metadata. Each call to `store.sh` creates one chunk.
- **Embeddings**: AgentDB generates local embeddings (no API call, no cost).
- **GNN layer**: After enough queries, the GNN re-ranks results based on what was actually useful.
- **EWC++**: Prevents catastrophic forgetting — new learning doesn't erase old patterns.

## CLI Reference

```bash
# Init a new index
npx agentdb init --dir <path>

# Store a memory
npx agentdb store --dir <path> --text "text" --metadata '{"source":"file","tags":"tag"}'

# Search
npx agentdb search --dir <path> --query "natural language" --limit 5

# Stats
npx agentdb stats --dir <path>

# Export index (for backup/migration)
npx agentdb export --dir <path> --out dump.json

# Import
npx agentdb import --dir <path> --in dump.json
```

## MCP Server

```bash
# HTTP transport (Claude Code / OpenClaw tool integration)
npx @ruvector/rvf-mcp-server --transport http --port 7700

# stdio transport (for local MCP clients)
npx @ruvector/rvf-mcp-server --transport stdio
```

### MCP Tools exposed

| Tool | Description |
|------|-------------|
| `memory_store` | Store text + metadata |
| `memory_search` | Semantic search, returns ranked results |
| `memory_stats` | Index stats |
| `memory_ingest_file` | Ingest a markdown file |

## Metadata Schema

```json
{
  "source": "MEMORY.md",        // file or origin
  "tags": "liam,preferences",   // comma-separated
  "timestamp": "2026-03-25T..."  // ISO8601
}
```

## Integration Pattern

**On every memory write:**
1. Write to flat file (MEMORY.md or daily file) — source of truth
2. Call `store.sh` with the same text — keeps index in sync

**On memory recall:**
1. Try `query.sh` first — semantic results
2. Fall back to `memory_search` tool (existing OpenClaw built-in) for exact matches
3. Combine results

## Chunking Strategy

- Minimum chunk size: 60 chars (smaller chunks generate noise)
- Split on double newlines (paragraph boundaries)
- For MEMORY.md sections, each `##` section is a natural chunk boundary
- Avoid chunking code blocks across boundaries

## Known Limitations (alpha)

- `agentdb stats` may not be available in all alpha builds
- Index is not crash-safe — run `agentdb export` periodically for backup
- GNN improvements require ~1K+ queries to become noticeable
- No built-in deduplication — re-ingesting a file creates duplicate chunks; use `agentdb export`, deduplicate, `agentdb import` if needed

## Troubleshooting

**"npx agentdb: command not found"**
→ Run `npm install -g agentdb@alpha`

**"ENOENT: .agentdb/config.json"**
→ Run `npx agentdb init --dir $WORKSPACE/agentdb`

**MCP server won't start**
→ Check port 7700 isn't in use: `lsof -i :7700`
→ Try stdio transport instead
