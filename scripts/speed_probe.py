#!/usr/bin/env python3
"""Decode-speed probe for llama-server spec-dec configs.

Measures TTFT, decode tok/s, and total wall time for a LONG generation
(where MTP/spec-dec payoffs live). Uses streaming and counts tokens from
the SSE stream's usage field when present, else whitespace-token proxy.

Usage: python3 speed_probe.py <port> [label] [n_requests]
"""
import json, sys, time, urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "12346"
LABEL = sys.argv[2] if len(sys.argv) > 2 else f"port {PORT}"
N = int(sys.argv[3]) if len(sys.argv) > 3 else 2

URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"

# ~450-500 token target output. Long enough that decode dominates prefill.
PROMPT = ("Write a detailed technical explanation of how speculative "
          "decoding works in modern LLM inference engines. Cover the draft "
          "model, verification pass, acceptance rate, and how it interacts "
          "with memory bandwidth limits on Apple Silicon. Be thorough and "
          "specific, with concrete numbers where possible.")

def one():
    body = {"model": "x", "messages": [{"role": "user", "content": PROMPT}],
            "temperature": 0.4, "max_tokens": 700, "stream": True,
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.monotonic(); ttft = None; n_toks = 0; words = 0
    with urllib.request.urlopen(req, timeout=300) as r:
        for line in r:
            line = line.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            if ttft is None:
                ttft = time.monotonic() - t0
            d = line[5:].strip()
            if d == "[DONE]":
                break
            try:
                chunk = json.loads(d)
                delta = chunk["choices"][0].get("delta", {})
                for k in ("content", "reasoning_content"):
                    t = delta.get(k)
                    if t:
                        n_toks += 1  # one token per SSE chunk in llama.cpp
                        words += len(t.split())
                if chunk.get("usage") and chunk["usage"].get("completion_tokens"):
                    n_toks = chunk["usage"]["completion_tokens"]
            except Exception:
                pass
    total = time.monotonic() - t0
    dec = total - (ttft or 0.0)
    return {"ttft": ttft, "total": total, "toks": n_toks,
            "tok_s": n_toks / max(dec, 0.01)}

def main():
    res = [one() for _ in range(N)]
    print(f"== {LABEL} ==")
    for i, r in enumerate(res):
        print(f"  run{i+1}: ttft={r['ttft']:.2f}s total={r['total']:.2f}s "
              f"toks={r['toks']} decode={r['tok_s']:.1f} tok/s")
    if N > 1:
        avg = sum(r["tok_s"] for r in res) / len(res)
        print(f"  avg decode: {avg:.1f} tok/s")

if __name__ == "__main__":
    main()
