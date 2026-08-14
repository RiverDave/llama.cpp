# KERNEL-PROJECT: metal-moe-kernel (pet project - max silicon utilization)

Goal: maximize M4 Mini (24GB, 120 GB/s) silicon utilization for the champion
(Qwen3.6-35B-A3B UD-IQ3_S). The one remaining hardware-level lever: the MoE
expert matmul dispatch gap (mul_mat_id uses the slow per-expert mat-vec below
batch 32, the fast mm GEMM above).

## Measured context (all prior campaign data)

- Single-stream decode: 27.9 t/s server (clean), ~29% of the 120 GB/s ceiling
- Per-token wall ~38ms vs ~11ms ideal; mul_mat_id is the dominant cost
- ne21_mm_id_min = 32 (ggml-metal-ops.cpp:2593) gates the mm path
- kernel_mul_mm_id_iq3_s_f32 ALREADY EXISTS (instantiations verified) and is
  battle-tested in production prefill (batches >= 32) - no correctness worry
- has_simdgroup_mm = TRUE on M4 (MTLGPUFamilyApple7, device.m:734)
- Aug 10 aggregate sweep (npl 1..32): ~2x ceiling, no cliff at ne21=32 -
  mm@32 was engaged at npl=32 but memory pressure (KV) swamped it
- The mm kernel uses a 64x32 tile (NR0=64, NR1=32, NK=32); at batch < 32 it
  zero-pads the token dimension (utilization = batch/32). PR #25377's 64x8
  skinny tile fixed the same problem for plain mul_mat (2.02x at bs=8, Q4_0).

## Milestones (each: build + benchmark + logit-verify)

- M0 [DONE 2026-08-14]: source archaeology. mm kernel exists for IQ3_S;
  dispatch threshold is the gate; simdgroup mm enabled on M4.
- E0 (5 min): lower ne21_mm_id_min 32 -> 2, llama-batched-bench -b sweep
  1/2/4/8/16/32/64, baseline vs patched. DECISION:
    * mm@small-batch wins  -> dispatch-only fix (tiny, low risk)
    * mm@small-batch loses -> E1 skinny-tile variant (64x8 mul_mm_id)
- E1: skinny-tile kernel_mul_mm_id (NR1=8, copy kernel, instantiate IQ3_S
  + Q4_0/Q8_0 as validation quants), dispatch for ne21 2..16.
- E2: multi-slot server aggregate with new dispatch (ne21 = active slots;
  target: beat the ~2x aggregate ceiling).
- E3: speculative decode (--spec-type draft-mtp): verify batch (1+n_draft
  ~= 3-6 tokens) routes to the fast path -> single-stream 1.2-1.4x target.
  Requires server spec wiring at this commit (verified present).

## Acceptance criteria (every milestone)

1. Logit-identical: same prompt through baseline + patched builds,
   llama-eval-callback logit dump, max-abs-diff < 1e-4.
2. >= 10% on the milestone's target metric (batched-bench S_TG at the
   batch size, or aggregate server t/s, or spec-dec single-stream).
3. No regression at batch 1 (the mv path must stay untouched for ne21=1).
4. Proxy gates (scripts/proxy.sh t1-t3) still pass for the server config.

## Method

- Branch metal-moe-kernel off champion-speedup (infra inherited).
- Experiments as small commits; keep ne21=1 path bit-identical.
- Memory discipline: stop the champion server before llama-batched-bench
  (two 15GB model loads never fit 24GB); same memory state for A/B pairs.
- Benchmark: llama-batched-bench -npp 32 -ntg 128 -b N sweep, S_TG column.
- Journal every step here + MISSION-REPORT.md.

## Progress log

- 2026-08-14: M0 done. E0 dispatched: baseline sweep running.
- 2026-08-14 E0 RESULT: DISPATCH-ONLY IS DEAD. Threshold 32->2 routes
  everything to the existing 64x32 mm kernel; measured REGRESSION at every
  batch (throttle-noise-corrected, interleaved pairs recommended for E1):
    baseline (mv<32 / mm@32): b=2 29.67, b=8 29.79, b=32 30.13 t/s decode
    patched (mm everywhere):  b=1 24.92, b=2 24.38, b=4 25.84, b=8 24.88,
    b=16 25.78, b=32 26.42
  The 64x32 tile zero-pads below 32 tokens (~1/32 utilization at b=1).
  Prefill also regressed at small batches (S_PP b=8: 61.6 -> 39.9).
  REVERTED (ops.cpp restored to threshold 32, rebuilt).
  NOTE: consecutive bench runs throttle (~10-15% drift, power governor) -
  E1 A/Bs MUST be interleaved pairs, not sequential sweeps.
  Bench gotcha: llama-batched-bench needs -npl explicitly (empty n_pl =
  zero combos, header-only, exit 0).

## E1 design (skinny-tile kernel_mul_mm_id, NR1=8) - the mission spec

### Hypothesis
A 64x8-tile variant of kernel_mul_mm_id instantiated for IQ3_S (plus
Q4_0/Q8_0 as plumbing validation) beats the per-expert mul_mv_id path at
decode batches 2..16 on M4/Metal, because the weight tile is amortized
across 8 tokens instead of 1 (PR #25377 evidence on plain mul_mat:
2.02x at bs=8, Q4_0).

### Surgery plan
1. COPY kernel_mul_mm_id (ggml-metal.metal:10452) as
   kernel_mul_mm_id_nr8 with NR1: 32 -> 8:
   - NR0=64, NR1=8, NK=32, NL0=NK/16=2, NL1=NK/8=4
   - threadgroup = 1 simdgroup (64 threads); accumulators: 8x
     simdgroup_float8x8 (64x8 tile)
   - sb shmem shrinks to NR1*NK*sizeof(S1); sa stays NR0*NK*sizeof(S0)
   - grid: tgpig.x = ceil(neh1/8), tgpig.y = ceil(ne0/64), tgpig.z = expert
   - careful with lr0/lr1 clamping + id lookup (ids_i32[im*ne21 + r1 + lr1])
2. Instantiate for block_iq3_s (QK_NL, dequantize_iq3_s) + block_q4_0 +
   block_q8_0 (validation quants). Register host_name in the template
   block; wire pipeline lookup in ggml-metal-device.cpp (mirror
   ggml_metal_library_get_pipeline_mul_mm_id at ggml-metal-device.cpp:1009
   - corrected 2026-08-14 per Sol review; the .metal file is the shader
   source, the registry lives in ggml-metal-device.cpp).
3. Dispatch (ggml-metal-ops.cpp MUL_MAT_ID case): new branch
   (ne21 >= 2 && ne21 <= 16 && quant in {iq3_s, q4_0, q8_0}) ->
   nr8 pipeline; keep mv at ne21==1; keep existing mm at ne21>=32.
4. Build, then INTERLEAVED A/B: baseline vs patched, llama-batched-bench
   -b 2,4,8,16,32 pairs (order A B A B), -c 2048 -npp 32 -ntg 64 -npl 1.
5. Logit verification: llama-eval-callback dump (same prompt, baseline vs
   patched build) max-abs-diff < 1e-4. The mm path is already used in
   prefill >= 32 tokens in production, so numerical parity is expected.
6. If nr8 wins at 2..16: extend dispatch, then E2 (multi-slot server
   aggregate: ne21 = active slots) and E3 (spec-verify batch -> single-
   stream 1.2-1.4x via --spec-type draft-mtp).

### Kill criteria (per variant)
- Interleaved A/B shows < 5% gain at b=8 -> variant dead, try next
  (NR1=4? 16? different NK? Q4_0-first validation).
- Logit diff > 1e-4 -> correctness bug, revert variant.
- Batch-1 decode regresses > 2% -> revert immediately (mv path must stay
  for ne21=1; the nr8 branch is gated on ne21>=2 anyway).
- 3 consecutive variants < 5% -> E1 dead, report PARTIAL, keep threshold
  at 32 (current behavior is the safe state).
