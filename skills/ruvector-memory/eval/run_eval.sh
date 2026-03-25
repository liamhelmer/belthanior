#!/usr/bin/env bash
# run_eval.sh — Orchestrator for vector search vs grep eval
# Runs both systems on all test cases, judges results, computes metrics.
#
# Usage: ./run_eval.sh [--skip-ingest] [--skip-judge] [--limit N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="/home/openclaw/.openclaw/workspace/agentdb/memory.db"
WORKSPACE="/home/openclaw/.openclaw/workspace"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d_%H%M%S)
RESULT_FILE="$RESULTS_DIR/${DATE}.json"
JUDGE_INPUT="$RESULTS_DIR/.judge_input_${DATE}.jsonl"
JUDGE_OUTPUT="$RESULTS_DIR/.judge_output_${DATE}.jsonl"
RAW_RESULTS="$RESULTS_DIR/.raw_${DATE}.jsonl"
SEARCH_LIMIT=5

# Parse args
SKIP_INGEST=false
SKIP_JUDGE=false
LIMIT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-ingest) SKIP_INGEST=true; shift ;;
        --skip-judge) SKIP_JUDGE=true; shift ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

mkdir -p "$RESULTS_DIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        RuVector Memory Eval — grep vs. vector search        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Date:     $(date -Iseconds)"
echo "DB:       $DB"
echo "Limit:    $SEARCH_LIMIT results per query"
echo ""

# ─── Step 0: Check DB has content ───────────────────────────────────────────
echo "▸ Checking AgentDB status..."
EPISODE_COUNT=$(agentdb status --db "$DB" 2>&1 | grep -oP 'Total Records\s+\K\d+' || echo "0")

if [[ "$SKIP_INGEST" == "false" && "$EPISODE_COUNT" -lt 10 ]]; then
    echo "  ⚠ Only $EPISODE_COUNT episodes in DB. Ingesting MEMORY.md chunks..."

    # Split MEMORY.md into chunks and ingest
    chunk_num=0
    current_chunk=""
    current_heading=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[^#] ]]; then
            # New heading — flush previous chunk
            if [[ -n "$current_chunk" ]]; then
                chunk_num=$((chunk_num + 1))
                session_id="ingest-memory-eval-${chunk_num}"
                task_text="${current_heading}\n${current_chunk}"
                agentdb reflexion store "$session_id" "$task_text" 0.8 true "source:MEMORY.md chunk:$chunk_num" --db "$DB" 2>/dev/null || true
            fi
            current_heading="$line"
            current_chunk=""
        else
            current_chunk="${current_chunk}${line}\n"
        fi
    done < "$WORKSPACE/MEMORY.md"

    # Flush last chunk
    if [[ -n "$current_chunk" ]]; then
        chunk_num=$((chunk_num + 1))
        session_id="ingest-memory-eval-${chunk_num}"
        task_text="${current_heading}\n${current_chunk}"
        agentdb reflexion store "$session_id" "$task_text" 0.8 true "source:MEMORY.md chunk:$chunk_num" --db "$DB" 2>/dev/null || true
    fi

    # Also ingest daily memory files
    for memfile in "$WORKSPACE"/memory/*.md; do
        [[ -f "$memfile" ]] || continue
        basename=$(basename "$memfile")
        [[ "$basename" == *.json ]] && continue
        [[ "$basename" == *AUDIT* ]] && continue
        [[ "$basename" == *state* ]] && continue

        chunk_num=$((chunk_num + 1))
        content=$(head -c 4000 "$memfile")
        session_id="ingest-memfile-${basename}-${chunk_num}"
        agentdb reflexion store "$session_id" "$content" 0.8 true "source:$basename" --db "$DB" 2>/dev/null || true
    done

    echo "  ✅ Ingested $chunk_num chunks"
else
    echo "  ✅ DB has $EPISODE_COUNT episodes (skipping ingest)"
fi
echo ""

# ─── Step 1: Run searches ──────────────────────────────────────────────────
echo "▸ Running searches on test cases..."

test_count=0
total_grep_time=0
total_vector_time=0

# Clear raw results
> "$RAW_RESULTS"
> "$JUDGE_INPUT"

while IFS= read -r line; do
    tc_id=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])")
    query=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['query'])")
    difficulty=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['difficulty'])")
    expected=$(echo "$line" | python3 -c "import sys,json; print(json.dumps(json.loads(sys.stdin.read())['expected_contains']))")

    test_count=$((test_count + 1))
    if [[ -n "$LIMIT" && $test_count -gt $LIMIT ]]; then
        break
    fi

    printf "  [%02d] %-6s %-50s " "$test_count" "$difficulty" "${query:0:50}"

    # --- Grep search ---
    grep_start=$(date +%s%N)
    grep_results=$("$SCRIPT_DIR/grep_search.sh" "$query" "$SEARCH_LIMIT" 2>/dev/null || echo "[]")
    grep_end=$(date +%s%N)
    grep_ms=$(( (grep_end - grep_start) / 1000000 ))
    total_grep_time=$((total_grep_time + grep_ms))

    # --- Vector search ---
    vec_start=$(date +%s%N)
    vec_results=$("$SCRIPT_DIR/vector_search.sh" "$query" "$SEARCH_LIMIT" 2>/dev/null || echo "[]")
    vec_end=$(date +%s%N)
    vec_ms=$(( (vec_end - vec_start) / 1000000 ))
    total_vector_time=$((total_vector_time + vec_ms))

    printf "grep=%dms vec=%dms\n" "$grep_ms" "$vec_ms"

    # Save raw results and prepare judge input using Python for safe JSON handling
    python3 -c "
import json, sys

tc_id = sys.argv[1]
difficulty = sys.argv[2]
query = sys.argv[3]
expected = json.loads(sys.argv[4])
grep_results = json.loads(sys.argv[5])
vec_results = json.loads(sys.argv[6])
grep_ms = int(sys.argv[7])
vec_ms = int(sys.argv[8])
raw_file = sys.argv[9]
judge_file = sys.argv[10]

# Save raw results
raw = {
    'id': tc_id, 'difficulty': difficulty, 'query': query,
    'expected': expected, 'grep_results': grep_results,
    'vector_results': vec_results, 'grep_ms': grep_ms, 'vector_ms': vec_ms
}
with open(raw_file, 'a') as f:
    f.write(json.dumps(raw) + '\n')

# Prepare judge input
with open(judge_file, 'a') as f:
    for rank, r in enumerate(grep_results):
        f.write(json.dumps({
            'id': tc_id, 'query': query, 'text': r['text'],
            'system': 'grep', 'rank': rank, 'difficulty': difficulty
        }) + '\n')
    for rank, r in enumerate(vec_results):
        f.write(json.dumps({
            'id': tc_id, 'query': query, 'text': r['text'],
            'system': 'vector', 'rank': rank, 'difficulty': difficulty
        }) + '\n')
" "$tc_id" "$difficulty" "$query" "$expected" "$grep_results" "$vec_results" "$grep_ms" "$vec_ms" "$RAW_RESULTS" "$JUDGE_INPUT"

done < "$SCRIPT_DIR/test_cases.jsonl"

echo ""
echo "  Total: $test_count test cases"
echo "  Avg grep latency:   $((total_grep_time / test_count))ms"
echo "  Avg vector latency: $((total_vector_time / test_count))ms"
echo ""

# ─── Step 2: Judge results ─────────────────────────────────────────────────
if [[ "$SKIP_JUDGE" == "true" ]]; then
    echo "▸ Skipping judge (--skip-judge)"
    echo ""
else
    judge_count=$(wc -l < "$JUDGE_INPUT")
    echo "▸ Judging $judge_count results with Qwen2.5-32B..."
    python3 "$SCRIPT_DIR/judge.py" --batch "$JUDGE_INPUT" --output "$JUDGE_OUTPUT" --workers 4
    echo "  ✅ Judging complete"
    echo ""
fi

# ─── Step 3: Compute metrics ──────────────────────────────────────────────
echo "▸ Computing metrics..."
echo ""

python3 - "$RAW_RESULTS" "$JUDGE_OUTPUT" "$RESULT_FILE" "$total_grep_time" "$total_vector_time" "$test_count" << 'PYTHON_SCRIPT'
import json
import sys
import os
from collections import defaultdict

raw_file = sys.argv[1]
judge_file = sys.argv[2]
result_file = sys.argv[3]
total_grep_ms = int(sys.argv[4])
total_vector_ms = int(sys.argv[5])
test_count = int(sys.argv[6])

# Load judge results into lookup: (tc_id, system, rank) -> score
judge_scores = {}
if os.path.exists(judge_file):
    with open(judge_file) as f:
        for line in f:
            if not line.strip():
                continue
            j = json.loads(line)
            # Re-read the judge input to get rank
            key = (j.get("id", ""), j.get("system", ""))
            if key not in judge_scores:
                judge_scores[key] = []
            judge_scores[key].append(j.get("score", 0))

# Also load judge output with rank info from the input file
judge_by_rank = {}
judge_input_file = judge_file.replace("judge_output", "judge_input")
if os.path.exists(judge_input_file) and os.path.exists(judge_file):
    inputs = []
    with open(judge_input_file) as f:
        for line in f:
            if line.strip():
                inputs.append(json.loads(line))
    outputs = []
    with open(judge_file) as f:
        for line in f:
            if line.strip():
                outputs.append(json.loads(line))

    for inp, out in zip(inputs, outputs):
        key = (inp["id"], inp["system"], inp["rank"])
        judge_by_rank[key] = out.get("score", 0)

# Load raw results
raw_results = []
with open(raw_file) as f:
    for line in f:
        if line.strip():
            raw_results.append(json.loads(line))

# Compute metrics per difficulty tier
tiers = ["easy", "medium", "hard"]
metrics = {tier: {"grep": {}, "vector": {}} for tier in tiers}
metrics["overall"] = {"grep": {}, "vector": {}}

def compute_recall_and_mrr(results_by_tier):
    """Compute Recall@K and MRR for each tier and system."""
    for tier in tiers + ["overall"]:
        for system in ["grep", "vector"]:
            cases = results_by_tier[tier][system]
            if not cases:
                metrics[tier][system] = {
                    "recall_at_1": 0, "recall_at_3": 0, "recall_at_5": 0,
                    "mrr": 0, "avg_score": 0, "count": 0
                }
                continue

            n = len(cases)
            recall_1 = sum(1 for c in cases if c["best_rank_relevant"] <= 0) / n
            recall_3 = sum(1 for c in cases if c["best_rank_relevant"] <= 2) / n
            recall_5 = sum(1 for c in cases if c["best_rank_relevant"] <= 4) / n

            mrr_sum = 0
            for c in cases:
                if c["best_rank_relevant"] < 999:
                    mrr_sum += 1.0 / (c["best_rank_relevant"] + 1)
            mrr = mrr_sum / n

            avg_score = sum(c["max_score"] for c in cases) / n

            metrics[tier][system] = {
                "recall_at_1": round(recall_1 * 100, 1),
                "recall_at_3": round(recall_3 * 100, 1),
                "recall_at_5": round(recall_5 * 100, 1),
                "mrr": round(mrr, 3),
                "avg_score": round(avg_score, 2),
                "count": n,
            }

# Organize results by tier
results_by_tier = {tier: {"grep": [], "vector": []} for tier in tiers}
results_by_tier["overall"] = {"grep": [], "vector": []}

RELEVANT_THRESHOLD = 2  # score >= 2 counts as "relevant"

for r in raw_results:
    tc_id = r["id"]
    difficulty = r["difficulty"]

    for system in ["grep", "vector"]:
        # Get ranked scores for this (tc_id, system)
        ranked_scores = []
        for rank in range(5):
            score = judge_by_rank.get((tc_id, system, rank), 0)
            ranked_scores.append(score)

        # Find best rank where result is relevant
        best_rank = 999
        max_score = 0
        for rank, score in enumerate(ranked_scores):
            max_score = max(max_score, score)
            if score >= RELEVANT_THRESHOLD and rank < best_rank:
                best_rank = rank

        case_info = {
            "tc_id": tc_id,
            "best_rank_relevant": best_rank,
            "max_score": max_score,
            "scores": ranked_scores,
        }

        results_by_tier[difficulty][system].append(case_info)
        results_by_tier["overall"][system].append(case_info)

compute_recall_and_mrr(results_by_tier)

# Latency
avg_grep_ms = total_grep_ms / test_count if test_count else 0
avg_vector_ms = total_vector_ms / test_count if test_count else 0
latency_ratio = avg_vector_ms / avg_grep_ms if avg_grep_ms > 0 else float('inf')

# ─── Print comparison table ──────────────────────────────────────────────
print("╔═══════════════════════════════════════════════════════════════════════════╗")
print("║                         EVALUATION RESULTS                              ║")
print("╠═════════════╦═════════╦═══════════╦═══════════╦═══════════╦═════════════╣")
print("║ Tier        ║ System  ║ Recall@1  ║ Recall@3  ║ Recall@5  ║ MRR         ║")
print("╠═════════════╬═════════╬═══════════╬═══════════╬═══════════╬═════════════╣")

for tier in tiers + ["overall"]:
    for system in ["grep", "vector"]:
        m = metrics[tier][system]
        if not m:
            continue
        label = f"{tier:11s}" if system == "grep" else "           "
        sys_label = f"{system:7s}"
        print(f"║ {label} ║ {sys_label} ║ {m['recall_at_1']:7.1f}%  ║ {m['recall_at_3']:7.1f}%  ║ {m['recall_at_5']:7.1f}%  ║ {m['mrr']:8.3f}    ║")
    if tier != "overall":
        print("╠═════════════╬═════════╬═══════════╬═══════════╬═══════════╬═════════════╣")

print("╚═════════════╩═════════╩═══════════╩═══════════╩═══════════╩═════════════╝")
print()

# Latency
print(f"  Avg latency — grep: {avg_grep_ms:.0f}ms | vector: {avg_vector_ms:.0f}ms | ratio: {latency_ratio:.1f}x")
print()

# ─── Success Criteria Evaluation ─────────────────────────────────────────
print("╔═══════════════════════════════════════════════════════════════════════════╗")
print("║                       PRE-COMMITTED SUCCESS CRITERIA                    ║")
print("╠═══════════════════════════════════════════════════════════════════════════╣")

hard_grep_r3 = metrics["hard"]["grep"].get("recall_at_3", 0)
hard_vec_r3 = metrics["hard"]["vector"].get("recall_at_3", 0)
hard_diff = hard_vec_r3 - hard_grep_r3

overall_grep_mrr = metrics["overall"]["grep"].get("mrr", 0)
overall_vec_mrr = metrics["overall"]["vector"].get("mrr", 0)

# Criterion 1: Vector Recall@3 on hard queries beats grep by ≥15pp
if hard_diff >= 15:
    c1 = f"✅ PASS: Vector Recall@3 on hard beats grep by {hard_diff:.1f}pp (≥15pp)"
elif hard_diff >= 5:
    c1 = f"⚠️  MARGINAL: Vector Recall@3 on hard beats grep by {hard_diff:.1f}pp (5-15pp)"
else:
    c1 = f"❌ FAIL: Vector Recall@3 on hard vs grep diff = {hard_diff:.1f}pp (<5pp)"
print(f"║ {c1:<73s} ║")

# Criterion 2: Overall vector MRR > grep MRR
if overall_vec_mrr > overall_grep_mrr:
    c2 = f"✅ PASS: Vector MRR ({overall_vec_mrr:.3f}) > grep MRR ({overall_grep_mrr:.3f})"
else:
    c2 = f"❌ FAIL: Vector MRR ({overall_vec_mrr:.3f}) ≤ grep MRR ({overall_grep_mrr:.3f})"
print(f"║ {c2:<73s} ║")

# Criterion 3: Latency check
if latency_ratio > 10 and hard_diff < 5:
    c3 = f"❌ FAIL: Vector {latency_ratio:.1f}x slower with <5pp accuracy gain"
elif latency_ratio > 10:
    c3 = f"⚠️  WARNING: Vector {latency_ratio:.1f}x slower (but accuracy gain justifies)"
else:
    c3 = f"✅ PASS: Vector latency ratio {latency_ratio:.1f}x (acceptable)"
print(f"║ {c3:<73s} ║")

# Criterion 4: Inconclusive check
if abs(hard_diff) < 5:
    c4 = f"⚠️  INCONCLUSIVE: Hard tier diff = {hard_diff:.1f}pp (<5pp, not enough signal)"
else:
    c4 = f"✅ CONCLUSIVE: Hard tier diff = {hard_diff:.1f}pp (sufficient signal)"
print(f"║ {c4:<73s} ║")

print("╚═══════════════════════════════════════════════════════════════════════════╝")

# ─── Save full results ───────────────────────────────────────────────────
full_results = {
    "date": os.popen("date -Iseconds").read().strip(),
    "test_count": test_count,
    "search_limit": 5,
    "metrics": metrics,
    "latency": {
        "avg_grep_ms": round(avg_grep_ms, 1),
        "avg_vector_ms": round(avg_vector_ms, 1),
        "ratio": round(latency_ratio, 2),
    },
    "success_criteria": {
        "hard_recall3_diff_pp": round(hard_diff, 1),
        "overall_mrr_vector": overall_vec_mrr,
        "overall_mrr_grep": overall_grep_mrr,
        "latency_ratio": round(latency_ratio, 2),
    },
    "per_case": [],
}

for r in raw_results:
    tc_id = r["id"]
    case_detail = {
        "id": tc_id,
        "difficulty": r["difficulty"],
        "query": r["query"],
        "grep_ms": r.get("grep_ms", 0),
        "vector_ms": r.get("vector_ms", 0),
        "grep_scores": [],
        "vector_scores": [],
    }
    for rank in range(5):
        case_detail["grep_scores"].append(judge_by_rank.get((tc_id, "grep", rank), 0))
        case_detail["vector_scores"].append(judge_by_rank.get((tc_id, "vector", rank), 0))
    full_results["per_case"].append(case_detail)

with open(result_file, "w") as f:
    json.dump(full_results, f, indent=2)

print(f"\n  📄 Full results saved to: {result_file}")

# ─── Generate summary.md ─────────────────────────────────────────────
summary_path = os.path.join(os.path.dirname(result_file), "summary.md")
lines = []
lines.append("# RuVector Memory Eval — Summary")
lines.append("")
lines.append(f"**Date:** {full_results['date']}")
lines.append(f"**Test cases:** {test_count} | **Results per query:** 5")
lines.append("")
lines.append("## Metrics")
lines.append("")
lines.append("| Tier | System | Recall@1 | Recall@3 | Recall@5 | MRR | Avg Score |")
lines.append("|------|--------|----------|----------|----------|-----|-----------|")
for tier in tiers + ["overall"]:
    for system in ["grep", "vector"]:
        m = metrics[tier][system]
        if not m:
            continue
        lines.append(
            f"| {tier} | {system} | {m['recall_at_1']:.1f}% | {m['recall_at_3']:.1f}% "
            f"| {m['recall_at_5']:.1f}% | {m['mrr']:.3f} | {m['avg_score']:.2f} |"
        )
lines.append("")
lines.append("## Latency")
lines.append("")
lines.append(f"| System | Avg Latency |")
lines.append(f"|--------|-------------|")
lines.append(f"| grep   | {avg_grep_ms:.0f}ms       |")
lines.append(f"| vector | {avg_vector_ms:.0f}ms       |")
lines.append(f"| ratio  | {latency_ratio:.1f}x        |")
lines.append("")
lines.append("## Success Criteria")
lines.append("")
lines.append(f"1. {c1}")
lines.append(f"2. {c2}")
lines.append(f"3. {c3}")
lines.append(f"4. {c4}")
lines.append("")
lines.append("## Interpretation")
lines.append("")

# Generate a verdict line
pass_count = sum(1 for c in [c1, c2, c3, c4] if c.startswith("✅"))
fail_count = sum(1 for c in [c1, c2, c3, c4] if c.startswith("❌"))
if pass_count >= 3 and fail_count == 0:
    verdict = "**PASS** — Vector search meets all pre-committed criteria."
elif fail_count >= 2:
    verdict = "**FAIL** — Vector search does not meet key criteria."
else:
    verdict = "**INCONCLUSIVE** — Mixed results; further tuning or more test cases needed."

lines.append(f"**Verdict:** {verdict}")
lines.append("")
lines.append(
    f"Vector search achieved {metrics['overall']['vector'].get('recall_at_3', 0):.1f}% Recall@3 overall "
    f"vs grep's {metrics['overall']['grep'].get('recall_at_3', 0):.1f}%. "
    f"On hard queries, the gap was {hard_diff:.1f}pp. "
    f"Vector latency averaged {avg_vector_ms:.0f}ms ({latency_ratio:.1f}x grep), "
    f"which {'is acceptable' if latency_ratio <= 10 else 'is high but may be justified by accuracy gains'}."
)
lines.append("")

summary_text = "\n".join(lines)
with open(summary_path, "w") as f:
    f.write(summary_text)

print(f"  📄 Summary saved to: {summary_path}")
print()
print(summary_text)
PYTHON_SCRIPT

echo ""
echo "Done."
