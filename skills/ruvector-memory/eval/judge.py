#!/usr/bin/env python3
"""
judge.py — LLM-as-judge for relevance scoring using local Qwen LLM.

Scores (query, result_text) pairs on a 0-3 relevance scale:
  0 = irrelevant — no connection to the query
  1 = tangential — loosely related but doesn't answer the query
  2 = relevant — contains useful information that addresses the query
  3 = highly relevant — directly and fully answers the query

Usage:
  python3 judge.py --query "..." --text "..." [--cache-file cache.json]
  python3 judge.py --batch input.jsonl --output output.jsonl [--cache-file cache.json]

The judge is blind to which system produced the result.
"""

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.request
import urllib.error

LLM_BASE_URL = "http://localhost:8000/v1"
MODEL = "Qwen/Qwen3.5-27B"
DEFAULT_CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", ".judge_cache.json")

JUDGE_PROMPT = """You are an impartial relevance judge. Given a QUERY and a TEXT passage retrieved from a memory system, rate how relevant the TEXT is to answering the QUERY.

Score on this scale:
0 = IRRELEVANT — The text has no meaningful connection to the query.
1 = TANGENTIAL — The text is loosely related but does not directly answer the query.
2 = RELEVANT — The text contains useful information that partially or indirectly answers the query.
3 = HIGHLY RELEVANT — The text directly and substantially answers the query.

Rules:
- Judge ONLY the text's relevance to the query. Do not consider formatting, style, or source.
- A text that contains the exact answer deserves a 3.
- A text about the same topic but not answering the specific question deserves a 1 or 2.
- Be strict: only give 3 if the text clearly contains the answer.

QUERY: {query}

TEXT: {text}

Respond with ONLY a JSON object: {{"score": <0-3>, "reasoning": "<one sentence>"}}"""


def cache_key(query: str, text: str) -> str:
    """Deterministic hash for (query, text) pair."""
    content = f"{query.strip()}|||{text.strip()}"
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def load_cache(cache_file: str) -> dict:
    """Load judge result cache from disk."""
    if os.path.exists(cache_file):
        try:
            with open(cache_file, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            return {}
    return {}


def save_cache(cache: dict, cache_file: str):
    """Save judge result cache to disk."""
    os.makedirs(os.path.dirname(cache_file) or ".", exist_ok=True)
    with open(cache_file, "w") as f:
        json.dump(cache, f, indent=2)


def call_llm(prompt: str, max_retries: int = 3) -> str:
    """Call local Qwen LLM via OpenAI-compatible API."""
    payload = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.0,
        "max_tokens": 200,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()

    headers = {
        "Content-Type": "application/json",
    }

    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(
                f"{LLM_BASE_URL}/chat/completions",
                data=payload,
                headers=headers,
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode())
                return data["choices"][0]["message"]["content"]
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, KeyError) as e:
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
            else:
                raise RuntimeError(f"LLM call failed after {max_retries} attempts: {e}")


def judge_relevance(query: str, text: str, cache: dict, cache_file: str) -> dict:
    """Judge relevance of text to query, using cache."""
    key = cache_key(query, text)

    if key in cache:
        return cache[key]

    # Truncate very long texts to avoid overwhelming the judge
    truncated = text[:3000] if len(text) > 3000 else text

    prompt = JUDGE_PROMPT.format(query=query, text=truncated)

    try:
        response = call_llm(prompt)
        # Parse the JSON response — robust extraction
        # The LLM may include thinking preamble, markdown fences, etc.
        cleaned = response.strip()

        # Strip markdown code fences if present
        if "```" in cleaned:
            # Extract content between first ``` and last ```
            parts = cleaned.split("```")
            for part in parts:
                part = part.strip()
                if part.startswith("json"):
                    part = part[4:].strip()
                if part.startswith("{"):
                    cleaned = part
                    break

        # Find the outermost JSON object by locating first { and last }
        first_brace = cleaned.find("{")
        last_brace = cleaned.rfind("}")
        if first_brace != -1 and last_brace != -1 and last_brace > first_brace:
            cleaned = cleaned[first_brace:last_brace + 1]

        result = json.loads(cleaned)
        score = int(result.get("score", 0))
        score = max(0, min(3, score))  # Clamp to 0-3
        reasoning = result.get("reasoning", "")

        judgment = {
            "score": score,
            "reasoning": reasoning,
            "query": query,
            "text_preview": text[:200],
        }
    except (json.JSONDecodeError, ValueError, RuntimeError) as e:
        judgment = {
            "score": 0,
            "reasoning": f"Judge error: {str(e)}",
            "query": query,
            "text_preview": text[:200],
        }

    # Cache the result
    cache[key] = judgment
    save_cache(cache, cache_file)

    return judgment


def judge_batch(input_file: str, output_file: str, cache_file: str):
    """Process a batch of (query, text) pairs from JSONL."""
    cache = load_cache(cache_file)
    results = []

    with open(input_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    total = len(lines)
    for i, line in enumerate(lines, 1):
        item = json.loads(line)
        query = item["query"]
        text = item["text"]
        system = item.get("system", "unknown")
        tc_id = item.get("id", f"item_{i}")

        judgment = judge_relevance(query, text, cache, cache_file)
        judgment["system"] = system
        judgment["id"] = tc_id
        results.append(judgment)

        print(f"  [{i}/{total}] {tc_id} ({system}): score={judgment['score']}", file=sys.stderr)

    with open(output_file, "w") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")

    return results


def main():
    parser = argparse.ArgumentParser(description="LLM relevance judge")
    parser.add_argument("--query", help="Single query to judge")
    parser.add_argument("--text", help="Single text to judge")
    parser.add_argument("--batch", help="Input JSONL file for batch judging")
    parser.add_argument("--output", help="Output JSONL file for batch results")
    parser.add_argument("--cache-file", default=DEFAULT_CACHE, help="Cache file path")

    args = parser.parse_args()

    if args.batch:
        if not args.output:
            print("Error: --output required with --batch", file=sys.stderr)
            sys.exit(1)
        judge_batch(args.batch, args.output, args.cache_file)
    elif args.query and args.text:
        cache = load_cache(args.cache_file)
        result = judge_relevance(args.query, args.text, cache, args.cache_file)
        print(json.dumps(result, indent=2))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
