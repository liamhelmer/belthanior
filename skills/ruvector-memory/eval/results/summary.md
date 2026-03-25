# RuVector Memory Eval — Summary

**Date:** 2026-03-25T11:09:15-07:00
**Test cases:** 30 | **Results per query:** 5

## Metrics

| Tier | System | Recall@1 | Recall@3 | Recall@5 | MRR | Avg Score |
|------|--------|----------|----------|----------|-----|-----------|
| easy | grep | 50.0% | 80.0% | 80.0% | 0.633 | 2.50 |
| easy | vector | 40.0% | 50.0% | 50.0% | 0.433 | 1.70 |
| medium | grep | 30.0% | 80.0% | 90.0% | 0.553 | 2.50 |
| medium | vector | 60.0% | 80.0% | 80.0% | 0.667 | 2.30 |
| hard | grep | 20.0% | 50.0% | 70.0% | 0.367 | 2.10 |
| hard | vector | 40.0% | 70.0% | 70.0% | 0.500 | 2.00 |
| overall | grep | 33.3% | 70.0% | 80.0% | 0.518 | 2.37 |
| overall | vector | 46.7% | 66.7% | 66.7% | 0.533 | 2.00 |

## Latency

| System | Avg Latency |
|--------|-------------|
| grep   | 2107ms       |
| vector | 794ms       |
| ratio  | 0.4x        |

## Success Criteria

1. ✅ PASS: Vector Recall@3 on hard beats grep by 20.0pp (≥15pp)
2. ✅ PASS: Vector MRR (0.533) > grep MRR (0.518)
3. ✅ PASS: Vector latency ratio 0.4x (acceptable)
4. ✅ CONCLUSIVE: Hard tier diff = 20.0pp (sufficient signal)

## Interpretation

**Verdict:** **PASS** — Vector search meets all pre-committed criteria.

Vector search achieved 66.7% Recall@3 overall vs grep's 70.0%. On hard queries, the gap was 20.0pp. Vector latency averaged 794ms (0.4x grep), which is acceptable.
