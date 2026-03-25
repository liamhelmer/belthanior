# AgentDB Reference

AgentDB v3.0.0-alpha.10 — Vector intelligence with RuVector backend + GNN self-learning.

## Key Commands

```bash
# Init
agentdb init <db-path> --model Xenova/bge-small-en-v1.5 --dimension 384

# Store a memory (reflexion episode)
agentdb reflexion store <session-id> <text> <reward 0-1> <success true|false> <critique/metadata> <db-path>

# Retrieve by semantic similarity
agentdb reflexion retrieve "<query>" --k 5 --synthesize-context <db-path>

# Structured query (with filters)
agentdb query --query "<query>" --k 5 --format json --synthesize-context --db <db-path>

# Status
agentdb status --db <db-path> --verbose

# DB stats
agentdb db stats --db <db-path>

# Export / import (backup)
agentdb export <db-path> backup.json
agentdb import backup.json <new-db-path>

# GNN training (improves results over time)
agentdb train --domain "memory" --epochs 10 --batch-size 32 --db <db-path>

# Memory optimization / compression
agentdb optimize-memory --compress true --consolidate-patterns true --db <db-path>
```

## Skill / Pattern Commands

```bash
# Create a reusable skill from text
agentdb skill create "skill-name" "description" "content" --db <db-path>

# Search skills
agentdb skill search "<query>" 5 --db <db-path>

# Auto-create skills from high-reward episodes
agentdb skill consolidate 3 0.7 7 true --db <db-path>
```

## Causal Learning

```bash
# Add causal edge (A causes B with 25% uplift, 95% confidence)
agentdb causal add-edge "cause" "effect" 0.25 0.95 100 --db <db-path>

# Retrieve with causal utility
agentdb recall with-certificate "<query>" 10 --db <db-path>

# Auto-discover causal patterns from episodes
agentdb learner run 3 0.6 0.7 --db <db-path>
```

## DB Location

Default: `~/.openclaw/workspace/agentdb/memory.db`
Override: `export AGENTDB_PATH=<path>`

## Embedding Model

Currently using: `Xenova/bge-small-en-v1.5` (384-dim, best quality at 384d)
Upgrade option: `Xenova/bge-base-en-v1.5` (768-dim, production quality — requires re-init)

## Integration Pattern

**On memory write:**
1. Write to flat file (source of truth)
2. `agentdb reflexion store <session> "<text>" 0.8 true "source:<file>" <db>`

**On memory recall:**
1. `agentdb reflexion retrieve "<query>" --k 5 --synthesize-context <db>` — semantic
2. Fall back to `memory_search` (OpenClaw built-in) for exact keyword matches

## Known Quirks (v3 alpha)

- `--db` flag works on most but not all subcommands; positional db path also accepted
- First query downloads transformer model (~90MB, cached after first run)
- `sql.js` WASM backend used (no native build needed on this system)
- GNN improvements kick in after ~1K queries + `agentdb train`
