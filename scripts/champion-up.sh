#!/bin/bash
# champion-up.sh - start the champion (Qwen3.6-35B-A3B UD-IQ3_S) llama-server
#
# Usage: ~/dev/llm-silicon/champion-up.sh [ctx]
#   ctx: context length (default 131072, the model's native max)
#
# Serves OpenAI-compatible API on http://127.0.0.1:12346/v1
# Logs to /tmp/champion_server.log
#
# Wire-ups that depend on it:
#   - opencode:  ~/.config/opencode/config.json  -> provider "champion"
#   - pi:        ~/.pi/agent/models.json          -> provider "champion"
#   - raw API:   curl http://127.0.0.1:12346/v1/chat/completions
#
# FIX 2026-08-14: added -np 1. The 4-slot default over-allocated KV
# (4 x 131K slots ~= 16GB KV + 15.35GB model on a 24GB box) -> deep swap,
# decode 27 -> 17 t/s, prefill 308 -> 145 t/s. One slot is all Hermes/pi
# uses. See local-llm-benchmarking skill: server-throughput-swap-vs-overhead.
#
# EXPERIMENT KNOB (2026-08-14): THINK_ARGS overrides the reasoning control.
# DEFAULT (mission outcome): --reasoning-budget 256 - thinking preserved for
# hard reasoning turns (proxy gates prove quality: all 3 hard tasks pass),
# runaway thinking on mechanical/planning turns capped at 256 tokens
# (measured: 600+ token runaways with ZERO content -> 255 reasoning + real
# answer). Overrides: THINK_ARGS="--reasoning off" for pure mechanical
# sessions (18x token reduction on trivial turns), THINK_ARGS="--reasoning
# on" for unlimited thinking. Per-request opt-in still works: clients
# sending chat_template_kwargs.enable_thinking=true get thinking regardless.

set -euo pipefail

MODEL="$HOME/.lmstudio/models/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/Qwen3.6-35B-A3B-UD-IQ3_S.gguf"
CTX="${1:-131072}"
PORT="${PORT:-12346}"
BIN="$HOME/dev/llama.cpp/build/bin/llama-server"
LOG=/tmp/champion_server.log

# Already running?
if pgrep -f "llama-server.*$MODEL" > /dev/null; then
  echo "champion server already running (port check: $(curl -s -m 2 http://127.0.0.1:$PORT/health 2>/dev/null || echo 'unreachable'))"
  exit 0
fi

if [ ! -f "$MODEL" ]; then
  echo "ERROR: model not found at $MODEL" >&2
  exit 1
fi

if [ ! -x "$BIN" ]; then
  echo "ERROR: llama-server not found at $BIN (build llama.cpp master first)" >&2
  exit 1
fi

echo "Starting champion server (ctx=$CTX, port=$PORT)..."
echo "  model: $MODEL"
echo "  think args: ${THINK_ARGS:---reasoning-budget 256 (mission default; overridable via THINK_ARGS)}"
nohup "$BIN" -m "$MODEL" -c "$CTX" -t 8 -fa on --jinja -np 1 ${THINK_ARGS:---reasoning-budget 256} --port "$PORT" --host 127.0.0.1 > "$LOG" 2>&1 &
SERVER_PID=$!

# Wait for health (up to 60s)
for i in $(seq 1 60); do
  if curl -s -m 2 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"ok"'; then
    echo "READY after ${i}s (pid $SERVER_PID)"
    echo "  API: http://127.0.0.1:$PORT/v1"
    echo "  log: $LOG"
    exit 0
  fi
  sleep 1
done

echo "ERROR: server did not become healthy in 60s - check $LOG" >&2
exit 1
