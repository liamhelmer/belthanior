---
name: ruvector-memory
description: |
  Vector-powered semantic memory for agents using RuVector/AgentDB. Use when: (1) initializing or upgrading the agent memory system to use vector search, (2) storing a memory/fact with semantic indexing, (3) querying memory by meaning rather than keywords, (4) ingesting existing memory files into the vector index, (5) checking index health or stats. Triggers on "set up ruvector memory", "init agentdb", "ingest memories into vector index", "semantic memory search", or any task requiring better-than-grep memory retrieval.
---

# RuVector Memory Skill

Semantic memory layer for agents using [RuVector/AgentDB](https://github.com/ruvnet/ruvector). Replaces keyword grep with self-learning vector search — retrieval quality improves over time.

## Architecture

```
memory/            ← existing flat files (preserved)
  YYYY-MM-DD.md
  MEMORY.md
agentdb/           ← vector index (new, managed by this skill)
  .agentdb/
```

AgentDB sits alongside the existing memory system. Flat files remain the source of truth; the vector index is a fast-retrieval layer over them.

## Setup

### First-time init

```bash
bash scripts/setup.sh
```

Installs AgentDB, starts the MCP server, ingests existing memory files.

### Check status

```bash
bash scripts/status.sh
```

## Storing Memories

After writing to a flat file (`memory/YYYY-MM-DD.md` or `MEMORY.md`), also index it:

```bash
bash scripts/store.sh "memory text to index" "source-file" "tag1,tag2"
# e.g.
bash scripts/store.sh "Liam prefers Rust for performance-critical work" "MEMORY.md" "liam,preferences"
```

## Querying Memory

```bash
bash scripts/query.sh "your natural language query" [limit]
# e.g.
bash scripts/query.sh "what are liam's coding preferences" 5
```

Returns semantically similar results ranked by relevance. Results improve as more memories are indexed.

## Ingesting Existing Files

To batch-ingest all existing memory files:

```bash
bash scripts/ingest.sh ~/.openclaw/workspace/memory/
bash scripts/ingest.sh ~/.openclaw/workspace/MEMORY.md
```

## MCP Server

RuVector exposes an MCP server for direct tool-call access:

```bash
# Start (runs in background on stdio, used by Claude Code)
npx @ruvector/rvf-mcp-server --transport http --port 7700
```

Once running, use `memory_store` and `memory_search` MCP tools directly.

## Notes

- AgentDB is `@alpha` — index may need periodic rebuilds
- CPU-only mode is fine; belthanior's ROCm is unused here (sublinear solvers don't need GPU)
- See `references/agentdb.md` for API details and advanced config
