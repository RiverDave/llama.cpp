#!/bin/bash
# proxy.sh - hard-task proxy runner for the champion-speedup mission.
#
#   proxy.sh run --label NAME [--task t1|t2|t3] [--model-pattern PAT] [--timeout S]
#       Runs each task with the champion via pi (thinking: default level),
#       timeboxed, then independently verifies the gate (agent self-report
#       never counts - proxy.sh runs verify.sh itself).
#       Output: scripts/proxy/reports/NAME.json + per-task pi debug logs.
#
#   proxy.sh compare BASELINE CANDIDATE
#       Per-task wall ratio table + gate verdict:
#       mean ratio >= 1.20 across >=2 tasks with both gates green, and no
#       degraded-memory run (free < 20% or swap > 8GB) -> GATE ACHIEVED.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASKS_DIR="$ROOT/scripts/proxy/tasks"
REPORTS_DIR="$ROOT/scripts/proxy/reports"
mkdir -p "$REPORTS_DIR"

MODE=""
LABEL=""
TASKS="t1 t2 t3"
MODEL_PATTERN="qwen3.6-35b-a3b"
TIMEOUT_S=1200
BASELINE=""
CANDIDATE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        run) MODE=run; shift ;;
        compare) MODE=compare; BASELINE="$2"; CANDIDATE="$3"; shift 3 ;;
        --label) LABEL="$2"; shift 2 ;;
        --task) TASKS="$2"; shift 2 ;;
        --model-pattern) MODEL_PATTERN="$2"; shift 2 ;;
        --timeout) TIMEOUT_S="$2"; shift 2 ;;
        *) echo "unknown arg: $1"; exit 2 ;;
    esac
done

memory_snapshot() {
    local swap_mb free_pct
    swap_mb=$(sysctl -n vm.swapusage | sed 's/.*used = \([0-9.]*\)M.*/\1/' | cut -d. -f1)
    free_pct=$(memory_pressure -Q 2>/dev/null | grep -oE '[0-9]+%' | tr -d '%')
    echo "{\"swap_mb\": ${swap_mb:-0}, \"free_pct\": ${free_pct:-0}}"
}

now_monotonic() { python3 -c 'import time; print(time.monotonic())'; }

if [[ "$MODE" == "run" ]]; then
    [[ -n "$LABEL" ]] || { echo "run needs --label"; exit 2; }
    MEM_BEFORE=$(memory_snapshot)
    RESULTS="{}"
    for t in $TASKS; do
        SRCDIR="$TASKS_DIR/$t"
        [[ -d "$SRCDIR" ]] || { echo "no such task dir: $SRCDIR"; continue; }
        WORK="/tmp/proxy_${LABEL}_${t}"
        rm -rf "$WORK"; mkdir -p "$WORK"
        cp -R "$SRCDIR"/. "$WORK"/

        # fresh pi debug log for this run
        : > ~/.pi/agent/debug.log 2>/dev/null || true

        cd "$WORK"
        PROMPT="$(cat task.md)"
        START=$(now_monotonic)
        nohup pi --provider champion --model "$MODEL_PATTERN" --no-session \
            --print "$PROMPT" > pi_stdout.log 2>&1 &
        PID=$!
        TIMED_OUT=0
        while kill -0 "$PID" 2>/dev/null; do
            sleep 5
            NOW=$(now_monotonic)
            if python3 -c "import sys; sys.exit(0 if $NOW - $START > $TIMEOUT_S else 1)"; then
                kill -9 "$PID" 2>/dev/null || true
                TIMED_OUT=1
                break
            fi
        done
        wait "$PID" 2>/dev/null
        PI_EXIT=$?
        END=$(now_monotonic)
        WALL=$(python3 -c "print(round($END - $START, 1))")

        cp ~/.pi/agent/debug.log "$REPORTS_DIR/${LABEL}_${t}_debug.log" 2>/dev/null || true

        # independent gate check
        GATE=0; GATE_TIME=0
        if [[ -f "$WORK/verify.sh" ]]; then
            GATE_START=$(now_monotonic)
            if ( cd "$WORK" && bash verify.sh > gate.log 2>&1 ); then GATE=1; else GATE=0; fi
            GATE_END=$(now_monotonic)
            GATE_TIME=$(python3 -c "print(round($GATE_END - $GATE_START, 1))")
        fi
        echo "task $t: pi_exit=$PI_EXIT wall=${WALL}s gate=$GATE gate_time=${GATE_TIME}s timed_out=$TIMED_OUT"

        RESULTS=$(python3 - "$RESULTS" "$t" "$GATE" "$WALL" "$PI_EXIT" "$TIMED_OUT" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
r[sys.argv[2]] = {"gate": int(sys.argv[3]) == 1, "wall_s": float(sys.argv[4]),
                  "pi_exit": int(sys.argv[5]), "timed_out": int(sys.argv[6]) == 1}
print(json.dumps(r))
PY
)
    done
    MEM_AFTER=$(memory_snapshot)
    python3 - "$REPORTS_DIR/$LABEL.json" "$LABEL" "$MEM_BEFORE" "$MEM_AFTER" "$RESULTS" <<'PY'
import json, sys, datetime
path, label, mb, ma, res = (sys.argv[1], sys.argv[2],
                            json.loads(sys.argv[3]), json.loads(sys.argv[4]),
                            json.loads(sys.argv[5]))
doc = {"label": label, "date": datetime.datetime.now().isoformat(timespec="seconds"),
       "memory_before": mb, "memory_after": ma, "tasks": res}
json.dump(doc, open(path, "w"), indent=2)
print("wrote", path)
PY
    exit 0
fi

if [[ "$MODE" == "compare" ]]; then
    python3 - "$REPORTS_DIR/$BASELINE.json" "$REPORTS_DIR/$CANDIDATE.json" <<'PY'
import json, sys
b = json.load(open(sys.argv[1])); c = json.load(open(sys.argv[2]))

def degraded(m):
    return m.get("free_pct", 0) < 20 or m.get("swap_mb", 0) > 8000

bd = degraded(b["memory_before"]) or degraded(b["memory_after"])
cd = degraded(c["memory_before"]) or degraded(c["memory_after"])
print(f"baseline  {b['label']}: {b['date']}  degraded={bd}  swap={b['memory_before'].get('swap_mb')}MB free={b['memory_before'].get('free_pct')}%")
print(f"candidate {c['label']}: {c['date']}  degraded={cd}  swap={c['memory_before'].get('swap_mb')}MB free={c['memory_before'].get('free_pct')}%")

print(f"{'task':5} {'base_s':>8} {'cand_s':>8} {'ratio':>7}  gates")
ratios = []; ok = 0; total = 0
for t in b["tasks"]:
    if t not in c["tasks"]:
        continue
    bt, ct = b["tasks"][t], c["tasks"][t]
    ratio = bt["wall_s"] / ct["wall_s"] if ct["wall_s"] > 0 else 0.0
    g = "OK" if (bt["gate"] and ct["gate"]) else "MISS"
    print(f"{t:5} {bt['wall_s']:8.1f} {ct['wall_s']:8.1f} {ratio:7.2f}  {g}")
    if bt["gate"] and ct["gate"]:
        ratios.append(ratio); ok += 1
    total += 1

if not ratios:
    print("VERDICT: no task passed both gates"); sys.exit(1)
mean = sum(ratios) / len(ratios)
print(f"mean ratio over gated tasks: {mean:.3f} ({ok}/{total} tasks)")
if bd or cd:
    print("VERDICT: DEGRADED MEMORY - run does not count")
elif ok >= 2 and mean >= 1.20:
    print("VERDICT: GATE ACHIEVED (>=20% on >=2 tasks, all gates green)")
else:
    print("VERDICT: NOT ACHIEVED")
sys.exit(0 if (ok >= 2 and mean >= 1.20 and not (bd or cd)) else 1)
PY
    exit 0
fi

echo "usage: proxy.sh run --label NAME [--task ...] | proxy.sh compare BASE CAND"
exit 2
