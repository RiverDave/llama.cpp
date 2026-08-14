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
