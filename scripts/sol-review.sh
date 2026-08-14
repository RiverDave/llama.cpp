#!/bin/bash
# sol-review.sh - overnight Sol review pass for the metal-moe-kernel branch.
# Reviews the diff since the last review with gpt-5.6-sol (via codex review,
# riding the ChatGPT Plus subscription), writes REVIEWS/<date>.md (committed
# to the branch so the fork shows the audit trail), prints a compact digest.
#
# Usage: scripts/sol-review.sh [base-branch]   (default: champion-speedup)
#
# Cron: no_agent watchdog - stdout is delivered verbatim; keep the digest
# short (empty-ish output on no-new-commits would be ideal but a nightly
# review of even 1 commit is the point - this is a review loop, not a
# change-detector).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE="${1:-champion-speedup}"
REVIEWS_DIR="$ROOT/REVIEWS"
MARKER="$REVIEWS_DIR/.last-reviewed"
mkdir -p "$REVIEWS_DIR"

# Locate the base ref (local branch or remote)
if git rev-parse --verify "$BASE" >/dev/null 2>&1; then
    BASE_REF="$BASE"
else
    BASE_REF="origin/$BASE"
fi

LAST="$(cat "$MARKER" 2>/dev/null || echo "$BASE_REF")"

# Number of new commits since last review
NCOMMITS=$(git rev-list --count "$LAST..HEAD" 2>/dev/null || echo "0")
if [ "$NCOMMITS" = "0" ]; then
    # silent tick (watchdog pattern): nothing new, don't wake the user
    exit 0
fi

OUT="$REVIEWS_DIR/$(date +%Y-%m-%d).md"
{
    echo "# Sol review $(date "+%Y-%m-%d %H:%M")"
    echo
    echo "- Range: $LAST..HEAD ($NCOMMITS commits)"
    echo "- Model: gpt-5.6-sol (codex review, ChatGPT plan)"
    echo
    echo '```'
    git log --oneline "$LAST..HEAD" | head -25
    echo '```'
    echo
    echo "## Findings"
    echo
} > "$OUT"

REVIEW_PROMPT="Adversarial code review of the Metal MoE kernel changes (metal-moe-kernel project). Focus: (1) threadgroup/tile math (NR0/NR1/NK, shmem sizing, grid dimensions), (2) dispatch invariants (ne21 gates, quant lists, ne21=1 path must stay on mul_mv_id), (3) logit-correctness risks (dequant, id lookup ids_i32[im*ne21+r1+lr1], barriers), (4) memory hazards (threadgroup races, missing barriers), (5) regression risk to batch-1 decode and to the prefill mm path at >=32. Assume the author is wrong; find the flaw. Quote exact line numbers."

# codex 0.146: --base cannot be combined with a positional [PROMPT]; the
# stdin form ('-') is the workaround. Fall back to the built-in prompt.
if ! codex review --base "$BASE_REF" \
        -c model="gpt-5.6-sol" \
        -c model_reasoning_effort="high" \
        - <<< "$REVIEW_PROMPT" >> "$OUT" 2>&1; then
    echo "(stdin prompt form rejected - retrying with built-in review prompt)" >> "$OUT"
    codex review --base "$BASE_REF" \
        -c model="gpt-5.6-sol" \
        -c model_reasoning_effort="high" \
        >> "$OUT" 2>&1 || echo "(codex review failed)" >> "$OUT"
fi

echo "$(git rev-parse HEAD)" > "$MARKER"

git add REVIEWS/ >/dev/null 2>&1 && git commit -m "review: Sol pass $(date +%Y-%m-%d)" >/dev/null 2>&1 || true

# Digest for delivery
echo "SOL-REVIEW $(date +%Y-%m-%d): $NCOMMITS commits reviewed ($(git rev-parse --short "$LAST")..$(git rev-parse --short HEAD))"
echo "Full review: REVIEWS/$(basename "$OUT") (committed to branch)"
echo "---"
grep -nE "Critical|critical|Warning|warning|Bug|bug|flaw|FAIL|incorrect|race|out.of.bounds" "$OUT" | head -15 || true
echo "---"
tail -30 "$OUT"
