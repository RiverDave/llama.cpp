#!/usr/bin/env python3
"""Agent-loop simulation probe: stable prefix + varying tail per turn.

Simulates what an agent loop sends to the server: the same big context
(system prompt + accumulated history) followed by a fresh instruction each
turn. Measures cold->warm TTFT, decode t/s, and KV prefix reuse
(cached_tokens via /slots) -- the fast iteration metric for prefill /
KV-reuse experiments. NOT a correctness proxy; use proxy.sh for that.

Usage: agentload_probe.py <port> [turns=6] [prefix_blocks=60]
"""
import json
import sys
import time
import urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "12346"
TURNS = int(sys.argv[2]) if len(sys.argv) > 2 else 6
BLOCKS = int(sys.argv[3]) if len(sys.argv) > 3 else 60

BASE = f"http://127.0.0.1:{PORT}"

# One "file" of fake codebase context, ~55-60 tokens per block.
BLOCK = """namespace cir { struct KernelInfo { unsigned block_x, block_y, block_z;
unsigned grid_x, grid_y, grid_z; constexpr bool valid() const { return block_x > 0
&& block_y > 0 && block_z > 0; } }; inline unsigned flat_id(const KernelInfo& k) {
return k.grid_x * k.grid_y * k.grid_z; } } // namespace cir
"""
PREFIX = BLOCK * BLOCKS


def chat(tail: str):
    body = {
        "model": "x",
        "messages": [
            {"role": "system",
             "content": "You are an expert C++ compiler engineer. Answer with code only."},
            {"role": "user", "content": PREFIX + "\n\nTASK: " + tail},
        ],
        "temperature": 0.3,
        "max_tokens": 120,
        "stream": True,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        f"{BASE}/v1/chat/completions", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.monotonic(); ttft = None; toks = 0
    with urllib.request.urlopen(req, timeout=300) as r:
        for line in r:
            line = line.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            if ttft is None:
                ttft = time.monotonic() - t0
            if line[5:].strip() == "[DONE]":
                break
            try:
                d = json.loads(line[5:])
                delta = d["choices"][0].get("delta", {})
                if delta.get("content"):
                    toks += 1
            except Exception:
                pass
    total = time.monotonic() - t0
    return ttft, total, toks


def slot_cached():
    try:
        with urllib.request.urlopen(f"{BASE}/slots", timeout=5) as r:
            slots = json.load(r)
        return sum(s.get("cached_tokens", 0) for s in slots)
    except Exception:
        return -1


print(f"== agentload probe (port {PORT}, {TURNS} turns, "
      f"prefix {BLOCKS}x{len(BLOCK)} chars) ==")
for i in range(TURNS):
    tail = (f"Implement function f{i} that computes the kernel launch geometry "
            f"for device {i}.")
    ttft, total, toks = chat(tail)
    cached = slot_cached()
    dec = total - (ttft or 0.0)
    tps = toks / max(dec, 0.01)
    print(f"  turn{i+1}: ttft={ttft:6.2f}s total={total:6.2f}s "
          f"toks={toks:3d} decode={tps:5.1f} cached={cached}")
