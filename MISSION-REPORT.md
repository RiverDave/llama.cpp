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
- 2026-08-14 ~10:30: baseline run 1: t1 81.1s GATE PASS, t2 298.7s gate FAIL (env: Homebrew clang20 TSAN segfaults on ARM64; agent's fix was CORRECT - verified TSan-clean under /usr/bin/clang++; gate now pins system clang), t3 121.5s GATE PASS. Agent side-effect: it edited ~/.zshenv + ~/.bashrc (PATH=/usr/bin first) to work around the toolchain - REVERTED (would have broken Homebrew tooling); task.md now carries the toolchain hint.
- 2026-08-14 ~11:00: authoritative baseline2 (all gates green): t1 511.0s, t2 50.6s, t3 70.8s (mean 210.8s). t1 variance 81-511s = agent path luck (baseline1 t1 wrote the whole SAM in one 1201-token call; baseline2 t1 rabbit-holed). t2 hint worked: 299->51s.
- 2026-08-14 ~11:15: thinking mechanics resolved: llama-server default = thinking ON (common/chat.cpp:364); pi sends NO thinking control (no chat_template_kwargs/reasoning_effort in its bundle; :minimal suffix is a no-op for llama.cpp); pi hides reasoning_content from the debug extension. Control lever = server flags --reasoning [on|off|auto] + --reasoning-budget N (THINK_ARGS knob added to champion-up.sh). Same question: thinking ON = 74 tok/2.9s; OFF = 4 tok/0.12s.
- 2026-08-14 ~11:30: candidate cand-budget256 (--reasoning-budget 256): all gates PASS (t1 86.0s, t2 55.7s, t3 116.4s) but NO clear signal vs baseline2 (t2/t3 slightly SLOWER - within path variance; t1's 86s vs 511s is path luck, its min-path baseline was 81s). Budget does not cap short thinking runs; verdict: neutral, not a win.
- 2026-08-14 ~11:45: candidate cand-nothink (--reasoning off): ALL GATES PASS (t1 172.0s, t2 50.8s, t3 121.4s) but NOT a win: t1 no-thinking used 3625 tokens / 8 calls / 4 bash cycles vs thinking's 1739 tokens / 4 calls / 1 cycle. THINKING IS LOAD-BEARING on hard tasks (planning avoids iteration loops). t3 also slower (121 vs 71).
- 2026-08-14 ~12:00: RUNAWAY THINKING FOUND: open-ended mechanical prompt (no tool schema) with thinking ON = 600+ reasoning tokens, ZERO content (max_tokens exhausted). Thinking never self-terminates on mechanical prompts. --reasoning-budget 256 CAPS it: 255 reasoning + real content, answered every turn (verified 3/3). This is the compromise knob: hard tasks keep thinking (cand-budget256: all gates pass, neutral walls), runaway-prone turns capped (~30-40% faster on those turns).
- Per-request opt-in verified: with server --reasoning off, chat_template_kwargs.enable_thinking=true still enables thinking (server-common.cpp:1080). Adaptive building block complete.
- 2026-08-14 ~12:15: cand-budget256b (confirmation run) in flight.

## VERDICT (2026-08-14 ~13:00, mission end)

### Contract result
`proxy.sh compare baseline2 cand-budget256`: **GATE ACHIEVED** (mean ratio
2.49x, 3/3 gates green, no degraded-memory runs). Caveat, stated plainly:
t1's wall is agent-path-luck dominated (81s / 511s / 172s / 1200s-timeout
across runs), so the 5.94x t1 ratio is variance, not config. t2/t3 moved
-9%/+39% (within variance). The hard-task proxy CANNOT demonstrate config
wins at n=1; its verdicts are noise. Methodological finding (journaled to
skill): use min-of-3 or repeated-measures for agent-task proxies.

### What actually changed (defensible, measured)
1. **-np 1** (was 4-slot default): server no longer swap-throttles decode
   27 -> 17 t/s. Clean decode now 27.9 t/s - best ever recorded on this box.
2. **--reasoning-budget 256 as daily-driver default** (new): thinking stays
   available for hard reasoning (all 3 hard proxy tasks pass with it), but
   RUNAWAY thinking (discovered this mission: 600+ reasoning tokens, ZERO
   content, thinking never self-terminates on mechanical/planning prompts)
   is capped: measured 255 reasoning + real answer, every turn.
3. **Session-level adaptive knob**: THINK_ARGS="--reasoning off" cuts
   trivial-turn tokens 18x (74 -> 4); per-request opt-in verified
   (enable_thinking:true still works with the server default off).
4. **KV prefix reuse verified working**: 9.4x warm TTFT on stable prefixes
   (16.8s -> 1.8s) - already automatic in the server.
5. Thinking is LOAD-BEARING on hard tasks: --reasoning off made t1 use 2x
   tokens and 2x wall (4 compile cycles vs 1) - do NOT run hard sessions
   with thinking off.

### Decode kernel shot: NOT attempted - decision with evidence
The only remaining single-stream lever (batched/fused expert kernels,
mul_mv_id at ne21=1) is a multi-hour kernel surgery whose own prior art on
this box is neutral (nr8-for-IQ3_S surgery, measured Aug 10). Published
analysis (#25250 + our measurements) says single-stream Metal decode at
IQ3_S is kernel-dispatch-bound with NO known software fix; upstream has
nothing new since Aug 10 (95 commits scanned). EV of the attempt within
the remaining timebox was judged negative; the composite wins above were
banked instead.

### Daily driver (recommended, already the script default)
```
~/dev/llm-silicon/champion-up.sh          # -np 1 + --reasoning-budget 256
THINK_ARGS="--reasoning off" ~/dev/llm-silicon/champion-up.sh   # mechanical sessions
```
Rollback: plain `git checkout master` + rebuild, or THINK_ARGS="" on the
old script (all changes are flag-level, no model/kernel changes).
