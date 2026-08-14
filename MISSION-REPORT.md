# champion-speedup mission

Goal: make the champion (Qwen3.6-35B-A3B UD-IQ3_S, M4 Mini 24GB, llama.cpp) faster on GENERAL-PURPOSE, genuinely hard coding tasks (user clarification 2026-08-14: not LLVM-specific — long context reads, reasoning turns, multi-file edits, verification loops). Target: 20-30% wall-time on a realistic agent-loop proxy. Hard stop ~5h. Verdict report at the end.

Proxy design (hard-task session through pi + champion, thinking adaptive: ON for reasoning turns, OFF for tool/mechanical turns):
- 2-3 fixed tasks from a hard-task set (algorithm implementation with tests, bug fix with repro, constrained refactor), each with a deterministic verify gate
- Metrics per task: wall time, tokens in/out, decode tok/s, TTFT, KV-reuse hits (server log)
- Baseline = current server config under clean memory; every candidate change re-runs the same set

## Baseline (all measured Aug 9-11, clean memory)

| Metric | Value |
|---|---|
| llama-bench tg128 | 25.9-26.4 t/s |
| llama-bench pp128 | 204-224 t/s |
| llama-server SSE decode (thinking OFF, clean mem) | 27.1 t/s |
| llama-server prefill (clean mem) | 302-308 t/s |
| swap-degraded server decode | 16.9-19.3 t/s (memory decides the number!) |
| agent-loop proxy (pi, file-write+exec) | 12.3s (opencode 18.0s) |
| bandwidth ceiling used | ~29% (120 GB/s; dense models hit 77-88%) |

Root cause of the decode wall: kernel-dispatch-bound small-batch mul_mat. IQ3_S is in NO fast Metal path; MoE expert mul_mat_id only uses the fast mm kernel at batch >= 32. Single-stream decode always runs the slow per-expert mat-vec.

## Dead ends (measured, DO NOT repeat)

- spec-dec MTP on this stack: 0.94x (verify pass ~3x cost of plain decode, unbatched on Metal)
- spec-dec with same-vocab Qwen3.5-0.8B draft: 0.5x (acceptance 0.36, bandwidth stolen)
- KV cache quant (-ctk/-ctv q8_0): neutral
- thinking-length caps: ignored; only binary enable_thinking works
- quant swap Q3_K_S vs IQ3_S: IQ3_S wins (19.6 vs 16.8 server t/s)
- MLX: no sub-4-bit quant exists; MTP stripped; tools broken; server OOMs
- ANE: impossible (decode CPU-only, static shapes, 32MB SRAM)
- CPU+GPU split (-ot/-cmoe): breaks MoE decode on Metal (#24413)
- multi-stream aggregate: ~2x ceiling, ZERO single-stream gain
- PR #25377/#25453 + nr8-for-IQ3_S surgery: NEUTRAL (doesn't touch mul_mat_id)
- -bs/--backend-sampling: ~5%, marginal
- upstream since Aug 10: nothing touches the Metal small-batch dispatch gap

## Plan

- Phase 0 (0-1h): clean-memory baseline on proxy + components. Fix champion-up.sh (-np 1 - the 4-slot KV over-allocation trap is still live). Verify adaptive-thinking + KV-prefix-reuse discipline in a real pi session.
- Phase 1 (1-2.5h): the decode shot -- MTP lookahead-batched verify on Metal (draft N tokens, verify in ONE batched graph). MTP head drafts well (accept 0.61, len 2.83); the loss is the unbatched verify pass. This is the one patch with plausible 1.2-1.4x. Fallback: ngram-simple spec-dec (never measured), IQ3_XXS quant A/B.
- Phase 2 (2.5-4.5h): iterate; logit-verify every change vs baseline; re-measure proxy.
- Phase 3 (4.5-5h): verdict report. Keep only changes >=10% verified.

## Rules

- Branch `champion-speedup` only; NO upstream commits; no history rewrites after push (user watches the remote).
- Every change: rebuild + llama-bench/llama-server smoke + logit verification vs baseline.
- Zombie-server check before any benchmark (`pgrep -f llama-server`).
- Only clean-memory numbers count; judge every number with free pages + swapusage.
- Sol (opencode run, openai/gpt-5.6-sol via user subscription) for design review + adversarial validation.
- Timeboxed: any experiment that doesn't show >=10% after its budget dies.

## Progress log

- 2026-08-14 09:00: mission scaffold. Branch created from master 62bf73d (matches all prior measured data). Rebuild from clean master started -- build/bin was stale (Aug 10 19:15, possibly fork-surgery binary). Machine state: 17.4GB swap in use (legacy pressure), server DOWN.
- 2026-08-14 ~10:00: proxy gate infrastructure built + validated (commit 81f7de39c, corrective 734b08e25). 3 hard tasks, all RED-on-starting-code / GREEN-on-reference. proxy.sh runner with independent gate verification + clean-memory contract; agentload_probe.py (agent-loop simulation).
- 2026-08-14 ~10:15: BASELINE (clean memory, server -np 1 @131K, master 62bf73d):
  - speed_probe (700-token gen, thinking off): decode 27.8 / 28.0 t/s (avg 27.9) -- best clean server number ever recorded (old: 27.1)
  - TTFT cold 0.67s, warm 0.18s
  - agentload probe (5K-token stable prefix, 6 turns): cold TTFT 16.8s -> warm 1.81-1.91s (9.4x KV prefix reuse working); per-turn warm total 6.2-6.4s (120 tok @ ~27 t/s); decode stable 26.8-27.3 t/s
  - /slots field for cache hits: n_prompt_tokens_cache (not cached_tokens) in this build
  - proxy baseline run launched (3 hard tasks through pi, thinking high, 20 min timebox each)
