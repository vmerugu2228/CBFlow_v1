# spec2rtl: state of the art in LLM / agentic specification-to-RTL generation

Research notes to inform a CBflow `spec2rtl` agent skill (Claude Code, open-source tools in
`cbflow-oss` docker). Compiled 2026-11-28 from web sources (arXiv abstracts / HTML, project docs).

**Confidence markers:** numbers are as reported by the paper's own authors unless stated.
`[unverified]` = I could not open the full text to confirm; `[uncertain]` = conflicting or
incomplete sources. No result here was reproduced by me. Benchmark numbers across papers are
**not directly comparable** (different benchmark versions, pass@k, sampling, models).

---

## 0. Executive summary

1. **Tool-in-the-loop beats model choice.** Every strong result couples the LLM with a
   compiler + simulator (almost always Icarus) and feeds structured failure data back. Vanilla
   Claude 3.5 Sonnet scored 72.4% on VerilogEval-v2; the same model inside MAGE's multi-agent
   loop scored 93.6–95.7% (MAGE ablation). VerilogCoder went 66.7% → 94.2% via planning +
   waveform-trace debugging.
2. **The debug signal that matters is "first mismatch + local context".** MAGE: earliest
   mismatching cycle plus a window of inputs / outputs / expected values. VerilogCoder: first
   mismatch time + AST back-trace of the failing output's driving signals with a tabular
   waveform. Raw logs / full VCDs are less useful than a localized, tabular trace.
3. **Planning before code, and a structured intermediate representation.** VerilogCoder's
   task/circuit-relation graph, Spec2RTL-Agent's sub-function decomposition with per-function
   I/O descriptions, the 2026 "Hierarchical IRs" work (architectural sketch + per-module
   operational spec) and Veri-Sure's "design contract" all make the micro-architecture explicit
   before RTL. Single-shot spec-to-RTL on real specs fails (Spec2RTL-Agent single-shot: 0/3).
4. **Toy benchmarks are saturated; realistic ones are not.** VerilogEval/RTLLM are at
   ~90–98% for agentic systems, but NVIDIA's CVDP (783 expert problems, cocotb-scored) tops
   out at ~34% pass@1 for single-turn frontier models (Claude 3.7 Sonnet best), with
   verification tasks (checkers, assertions) far worse (cid13 ~6%).
5. **Most errors are knowledge / spec-ambiguity errors, not reasoning errors** (2508.05266):
   wire-vs-reg, blocking vs non-blocking, bit slicing/widths, misread tables / FSM diagrams /
   waveforms, ambiguous I/O behaviour. Mitigation = rule-injected prompts, spec clarification,
   converting diagrams to truth tables, RAG, and sim-driven localized debug (up to 10 iters).
6. **The testbench is the weak link.** Agents must generate their own checker; CVDP shows LLM
   testbenches/assertions are the least reliable output, and MAGE adds a Judge that may decide
   the *testbench* is wrong. An independent reference model (Python) and spec-derived tests
   are the guard against "RTL and TB agree on the wrong behaviour".
7. **For CBflow:** the backbone already exists (RTL_SPEC → RTL_LINT/CDC/UPF → DV uvmgen /
   Verilator). The skill's job is the missing middle: spec clarification → micro-arch doc →
   reference model + cocotb/SV smoke tests → per-module RTL with a lint/sim/synth/formal inner
   loop → hand-off into the existing flows as the outer gate.

---

## 1. Published systems

### 1.1 Agentic / multi-agent spec-to-RTL

| System | Date / venue | Pipeline | Feedback signals | Decomposition | Reported result |
|---|---|---|---|---|---|
| **Spec2RTL-Agent** (NVIDIA + Georgia Tech + Cadence; Yu et al.) | arXiv 2506.13905, Jun 2025 | (1) Understanding: Summarization agent per spec section → Decomposer → Description agent (I/O, function, refs per sub-function) → Verifier. (2) Progressive coding: pseudocode → Python → C++ per sub-function, Coder + Verifier, Prompt-Optimizer agent rewrites the coder prompt from failure logs. (3) Adaptive reflection: Analysis agent reviews whole trajectory; Reflection agent picks: revise instructions / revise earlier sub-functions / regenerate / **escalate to human**. (4) Code optimizer adapts C++ for **Stratus HLS**, which emits RTL. | Test pass/fail (tests from spec or from higher-level code), self-validation vs spec. RTL is produced by HLS, not written by the LLM. | Sub-functions from the spec document (e.g. AES `AddRoundKey`, cipher). | 3 NIST specs (AES FIPS-197, DSS FIPS-186-5, HMAC FIPS-198-1), GPT-4o + AutoGen: 3/3 correct with 4.33 human interventions avg vs ~20 for human baseline (~75% fewer); single-shot 0/3. AES PPA comparable to modified open-source AES. Note: ablation percentages in the text appear swapped vs the table. |
| **VerilogCoder** (NVIDIA; Ho, Ren, Khailany) | arXiv 2408.08927, Aug 2024; AAAI 2025; code github.com/NVlabs/VerilogCoder | Planner decomposes spec into sub-tasks + plan verifier; signal/transition/example extractor builds a **Task-and-Circuit-Relation Graph (TCRG)**; code agent (engineer + verification assistant); debug agent in ReAct loop. | iverilog syntax errors with line numbers; iverilog sim (mismatch count, first mismatch time, VCD); **AST-based waveform tracing** (Pyverilog: from mismatching output, trace RVALUE drivers to agent-chosen depth; returns code ref + tabular waveform). | Sub-tasks linked to signals, signal transitions and examples (keeps FSM transitions from being dropped). | VerilogEval-Human v2: 94.2% (GPT-4 Turbo). Ablation: baseline 66.7%, TCRG planner 74.4%, AST-WT alone 78.2%, both 94.2%. |
| **MAGE** (UCSD; Zhao et al.) | arXiv 2412.07822, Dec 2024; site stable-lab.github.io/MAGE | Testbench agent (textual-waveform output, state checkpoints) → RTL agent → Judge (simulate, score; may regenerate the **testbench**) → Debug agent. High-temperature candidate sampling + scoring, top-K debug. | Icarus syntax (≤5 fix iterations) and simulation; **state-checkpoint debug**: earliest mismatching cycle t_m and a window [t_m − L, t_m] of inputs / DUT outputs / expected outputs. Candidate score = 1 − mismatches/checks. | Not hierarchical; per-problem. | Claude 3.5 Sonnet: VerilogEval-v2 95.7% (high-T) / 93.6% (low-T); vanilla 72.4%, single-agent 83.9%. T=0.85, n=20 runs. A 2026 paper (2608.30659) re-ran MAGE with GPT-5: 146/156 on VerilogEval v1 and called v2 too ambiguous to use. |
| **AutoChip** (NYU; Thakur, Blocklove et al.) | arXiv 2311.04887 (2023); extended as 2411.11856 (Nov 2024) | Generate → compile → simulate → feed tool output back as new prompt → repeat until both pass. Tree-search over candidates in later version. | Compiler + simulation output only (no human). | None. | 2023: 89.19% of test cases pass on HDLBits (+24.2% over zero-shot). 2024: tool feedback consistently helps only with GPT-4o; mixing small models early + GPT-4o for final iterations matches GPT-4o at 41.9% lower cost. |
| **VeriAssist** (Huang et al.) | arXiv 2406.00115, May 2024 | Generate RTL + testbench; LLM "self-verifies" by stepping through test cases; self-correction from compiler / simulator output. | Icarus compile + sim. | None. | Improved syntax + functional correctness over baselines (GPT-4, GPT-3.5, Claude 3 Sonnet) `[unverified numbers]`. |
| **AIvril / AIVRIL2** (Islam et al.) | arXiv 2409.11411 (Sep 2024); 2412.04485 (Dec 2024) | Two loops: AutoReview (syntax from EDA logs) and AutoDV (functional verification); AIVRIL2 = Code / Review / Verification agents, LLM-agnostic. | EDA tool logs (syntax), functional traces / testbench results. | None. | AIvril: ~2× code quality vs prior work, 88.46% verification-objective success on VerilogEval-Human. AIVRIL2: best functional pass 77% Verilog, 66% VHDL. |
| **VeriMoA** (Ping et al., USC et al.) | arXiv 2510.27617, Oct 2025 (rev. Apr 2026) | Training-free mixture-of-agents; **quality-guided cache** of intermediate HDL ranked across all layers; multi-path generation via **C++ and Python intermediate representations**. | Quality ranking of candidates (details in paper). | Spec → C++/Python → HDL. | +15–30% pass@1 across backbones on VerilogEval 2.0 and RTLLM 2.0; small models match large/fine-tuned ones `[per-model numbers unverified]`. |
| **Veri-Sure** (Liu, Zhou, Jiang) | arXiv 2601.19747, Jan 2026 (NeurIPS 2026 per comments) | Multi-agent with a **design contract** that keeps intent aligned across repair iterations; repairs via **static dependency slicing** (patch, don't regenerate); multi-branch verification with trace-driven temporal analysis + **formal verification**. | Simulation traces, temporal analysis, formal. | Contract-driven. | Claims SOTA "verified-correct" generation; introduces VerilogEval-v2-EXT (+53 industrial-grade tasks) `[no numbers in abstract]`. |
| **Hierarchical IRs + end-to-end multi-agent** (Yin, …, S. Mitra, T. Mitra) | arXiv 2608.30659, Aug 2026 | Two IRs: **Architectural Sketch** (module topology, connections) and **Operational Specification** (per-module function + interfaces); derives per-module test/verification plan; multi-agent debug loop where agents choose which signals to probe. | Simulation with agent-selected probes; lint; synthesis. | Explicit module hierarchy + per-module interface spec. | VerilogEval pass@5 95.5%; only framework producing a functional end-to-end design on processor / DSP case studies; output lint-clean and synthesizable `[qualitative]`. |
| **HORIZON — "Agentic Hardware Design as Repository-Level Code Evolution"** (NVIDIA; Yu, Deng, Pinckney, Khailany) | arXiv 2606.28279, Jun 2026 | Markdown harness compiled into a "project pack" (domain knowledge, executable evaluator, **acceptance predicate**, git/runtime policy); hands-free agent evolves an isolated **git worktree**, using git for state, tracing and replay. | Executable evaluator + acceptance predicate. | Repository-level. | "100% benchmark completion" on ChipBench, RTLLM, VerilogEval and nine CVDP categories; authors caution these are controlled proxies. Closest published analogue to a Claude Code skill. |
| **VeriMaAS** | arXiv 2509.20182, 2025 | Composes agentic workflows per problem. | **Yosys synthesis + OpenSTA logs** as feedback. | — | `[numbers not checked]` |
| **ChipGPT** (Chang et al.) | arXiv 2305.14019, May 2023 (v4 retitled Oct 2025); NeurIPS 2023 ML-for-Systems workshop | 4-stage prompt framework on GPT, no retraining, + **post-LLM search** for PPA. | Synthesis-driven PPA search. | — | Up to 47% area reduction vs plain ChatGPT in area mode; authors are explicit that it only "sheds light". |
| **HDLCoRe** (Ping et al.) | arXiv 2503.16528, Mar 2025 | Training-free: HDL-aware chain-of-thought with task classification and **self-simulation** for error correction + two-stage heterogeneous RAG (component extraction, then example retrieval with filtering / re-ranking). | LLM self-simulation; retrieved examples. | — | Better syntax/functional correctness on RTLLM 2.0, fewer hallucinations `[numbers not verified]`. |
| **Understanding & Mitigating Errors of LLM RTL** (Zhang et al.) | arXiv 2508.05266, v2 Feb 2026 | Error taxonomy from 306 failed designs → rule-based description refinement (10 RTL rules in system prompt), multimodal → truth-table conversion, RAG (~500 circuit entries + 15 syntax-fix entries), two-stage sim debug (localize then fix, ≤10 iterations). | Simulation. | Chunking of long specs. | VerilogEval-v2: GPT-4 Turbo 90.4% (+29.5), DeepSeek-v3.2-Speciale 97.4%, Qwen2.5-Coder-32B 78.1%; beats MAGE by 4.1 pts on v2 (reported). |

### 1.2 Fine-tuned / dataset work (relevant mainly as evidence of failure modes)

| Work | Date | Idea | Reported result |
|---|---|---|---|
| **RTLCoder** | 2023–2024 | Open 7B model trained on synthetic instruction data. | Figures vary across papers: e.g. 61.2 VerilogEval / 32.6 RTLLM-2.0 in one table, 24.5 on RTLLM 1.1 in another `[uncertain]`. |
| **OriGen** (arXiv 2407.16237) | Jul 2024 | Code-to-code augmentation + **self-reflection from compiler feedback**; open source. | Claims +12.8% over prior best open model and above GPT-4 Turbo on VerilogEval-Human pass@1. |
| **CodeV** (arXiv 2407.10424) | Jul 2024 | Multi-level summarization to build Verilog instruction data. | CodeV-Verilog-QC: 80.1% VerilogEval-Machine, 59.2% Human (own eval). |
| **QiMeng-CodeV-R1** (arXiv 2505.24183) | May 2025, NeurIPS 2025 | Distill-then-RL (DAPO) with a rule-based testbench generator checking equivalence vs golden. | 7B: 68.8% VerilogEval v2, 72.9% RTLLM 1.1, 68.0% RTLLM 2 (v4/v5). |
| **PyraNet** (arXiv 2412.06947) | Dec 2024, DAC 2025 | 692k Verilog samples in quality tiers, compile-checked with Icarus; CC BY-NC-SA 4.0. | Up to +32.6% over CodeLlama-7B, +16.7% over prior SOTA on VerilogEval. |
| **RTL++** (arXiv 2505.13479) | May 2025, IEEE LAD '25 | Graph-augmented (code structure graphs: CFG/DFG-style) fine-tuning. | Evaluated on VerilogEval + RTLLM 1.1 `[numbers not verified]`. |

Takeaway for us: we use a frontier model (Opus 5.5), not a fine-tuned 7B. The transferable
ideas are structured context (graphs / contracts / IRs), compile-feedback reflection, and
equivalence-vs-golden as the reward signal.

---

## 2. Benchmarks and failure modes

| Benchmark | What it measures | Status |
|---|---|---|
| **VerilogEval v1** (NVIDIA, 2023) | 156 HDLBits-derived problems, code completion; Machine vs Human descriptions; pass@k by simulation vs reference. | Saturated by agents (~95%+). |
| **VerilogEval v2** (Pinckney et al., arXiv 2408.11053; TODAES 2025; github.com/NVlabs/verilog-eval) | Adds **spec-to-RTL** task format, 0–4 in-context examples, automatic failure classification (compiler/sim). | GPT-4o 63% spec-to-RTL single-shot (v2 paper); prompt-sensitive. Agents ~94–97%. Some problems judged ambiguous (2608.30659). |
| **RTLLM v1 / 2.0** (Lu et al., arXiv 2308.05345; OpenLLM-RTL arXiv 2503.15112) | 30 → 50 designs with description, testbench, reference RTL; syntax, function, and (v1) **PPA quality** via synthesis vs reference. Design sizes 6–2,435 cells. | Mid-size; still useful for PPA sanity. |
| **CVDP** (NVIDIA, arXiv 2506.14074, Jun 2025; github.com/NVlabs/cvdp_benchmark; v1.1.0 via Si2 adds 100 problems from 40+ repos) | 783 expert problems, 13 categories: spec-to-RTL (cid03), spec-to-RTL with module reuse (cid05, agentic), code modification, lint/PPA improvement, TB stimulus, TB checker, assertions, debugging, comprehension. **cocotb** harnesses, Dockerized agent setup (Icarus, Yosys, Verilator; some categories need Xcelium). | Hard: best single-turn 33.6% (Claude 3.7 Sonnet), "agentic" converted-to-single-turn 29%. Verification tasks weakest (checker gen ~6%). |
| **VerilogEval-v2-EXT** (Veri-Sure, 2026) | +53 industrial-grade tasks with difficulty strata. | New; `[not inspected]`. |
| ChipBench, RTL-BenchLS (arXiv 2606.08976) | Larger RTL reasoning/generation benchmarks (2026). | `[not inspected in detail]` |

### Typical failure modes (with sources)

| Failure | Evidence | Detecting gate in an open-source loop |
|---|---|---|
| wire vs reg misuse, assigning wires in always blocks | VerilogEval v2 failure classes; 2508.05266 Type I | slang / Verilator compile |
| Blocking vs non-blocking misuse, mixed assignment semantics | 2508.05266; CVDP case studies | Verilator `BLKSEQ`/`COMBDLY`, Verible lint |
| Bit-width / slicing errors, missing zero-extension | VerilogEval v2; CVDP; RTL-BenchLS "Datapath" | Verilator `WIDTH*` warnings as errors |
| Off-by-one / extra cycle of latency (cycle accuracy) | CVDP brick-sort case (extra cycle per pass) | Cycle-accurate reference model + scoreboard; latency SVA |
| FSM transitions dropped / misread state diagrams, K-maps, waveforms | VerilogCoder (motivating example); 2508.05266 | Spec → explicit transition table; cover each transition |
| Wrong reset polarity / missing reset / init | RTL-BenchLS reset/timing bucket; 2508.05266 "missing initialization" | Spec reset contract + lint rule; X-prop sim; SVA "after reset, outputs = …" |
| Array index without bounds check | CVDP | Verilator runtime / formal assert |
| Missing `endmodule`, unbalanced begin/end, undefined module instantiation | 2403.07039; 2405.02329 | compile |
| Inferred latches (incomplete case/if in comb blocks) | Commonly cited, but **no paper found that quantifies it** `[uncertain]` | Verilator `LATCH`, yosys `proc; check` / `select t:$dlatch` |
| CDC (unsynchronized crossings) | Not measured by any benchmark found — benchmarks are single-clock `[gap]` | opencdc (RTL_CDC) |
| Non-synthesizable constructs (delays, initial blocks in RTL, unsupported SV) | Not quantified in sources found `[uncertain]` | yosys(-slang) synth must pass |
| Ambiguous / underspecified spec → plausible but wrong behaviour | 2508.05266 Type II (dominant); Spec2RTL-Agent reflection escalates to human | Clarification questions before coding |

---

## 3. Best practices for a reliable loop (synthesis of the above)

1. **Clarify the spec first.** The dominant error class is spec ambiguity. Ask targeted questions
   (reset behaviour, latency/throughput, back-pressure semantics, error handling, X handling,
   corner cases), and record answers in the spec, not in chat.
2. **Micro-architecture document before RTL.** Module hierarchy, per-module interface contract
   (ports, widths, protocol, latency, reset values), FSM transition tables, datapath widths,
   memories, clock domains. This is the IR all successful systems introduce (TCRG, sub-function
   descriptions, architectural sketch + operational spec, design contract).
3. **Independent golden model.** Write a Python (or C++) reference model from the spec, *before*
   and *independently of* the RTL (Spec2RTL-Agent / VeriMoA show LLMs are more reliable in
   high-resource languages). Differential test RTL vs model with **cocotb** (CVDP's harness
   choice) — randomized + directed, cycle-accurate where latency is specified.
4. **Bottom-up per module.** Generate and verify leaf modules against their contract with unit
   tests before integrating; patch locally (Veri-Sure slicing) rather than regenerating files.
5. **Gate ladder, cheapest first:** parse/elaborate (slang) → lint-clean (Verilator `-Wall`,
   Verible) → synthesis check (yosys: no latches, no undriven, sane cell count) → unit sim →
   differential sim vs model → formal properties → integration sim → coverage.
6. **Localized debug feedback.** On mismatch, feed the agent: first mismatching cycle, a window
   of inputs/expected/actual (MAGE), and the driver cone of the failing signal with a tabular
   waveform (VerilogCoder AST-WT). Do not paste whole VCDs or logs.
7. **Don't trust the agent's own testbench blindly.** Separate the test author from the RTL
   author (separate subagent / context); when RTL and test disagree, re-check against the spec
   which one is wrong (MAGE Judge). Prefer spec-derived expected values and the reference model.
8. **Formal for control.** Generate SVA for interface protocols (valid/ready hold-until-ready,
   no X on outputs after reset, one-hot state, FIFO no overflow/underflow) and prove / BMC with
   SymbiYosys. Caveat: the open-source Yosys front end supports immediate assertions and
   `$past/$rose/$fell/$stable/$changed`; full concurrent SVA needs the commercial Verific
   front end (Tabby CAD). Write properties in the immediate-assert-in-clocked-block style
   under `` `ifdef FORMAL ``. yosys-slang SVA support: `[unverified]`.
9. **Coverage-driven iteration.** Close functional coverage on the vPlan features and code
   coverage (Verilator `--coverage`); missing bins become new tests, not RTL rewrites.
10. **Bounded iterations + escalation.** Published caps: MAGE 5 syntax-fix iterations;
    2508.05266 10 debug iterations; VerilogCoder 100 auto-replies. Spec2RTL-Agent's reflection
    agent explicitly chooses "escalate to human". Escalate on repeated identical failures.
11. **Sample diversity only when stuck.** High-temperature multi-candidate sampling with a score
    (MAGE) helps but costs tokens; use it as a fallback after the deterministic loop stalls.
12. **Version everything (git worktree), acceptance predicate explicit** (HORIZON). Every
    iteration is a commit; the gate result is the acceptance predicate.

---

## 4. Open-source tools

| Tool | Role in spec2rtl | License (to my knowledge; verify LICENSE files) |
|---|---|---|
| **slang** | Fast SV parse/elaborate, strict diagnostics | MIT |
| **Verilator** | Lint (`--lint-only -Wall`), fast cycle sim, coverage, UVM (5.x `--timing`) | LGPL-3.0 or Artistic-2.0 |
| **Icarus Verilog** | Event sim; used by nearly every paper; cocotb backend | GPL-2.0 (tool; doesn't encumber designs) |
| **Yosys** (+ yosys-slang front end) | Synthesis check: latches (`$dlatch`), undriven, comb loops, area estimate | ISC |
| **SymbiYosys (sby)** | BMC / k-induction / cover with yosys-smtbmc, abc pdr; solvers boolector/yices/bitwuzla | ISC (open SVA subset only; see §3.8) |
| **EQY** | Equivalence checking (e.g. RTL refactor vs previous RTL) | ISC |
| **Verible** | Style lint, formatter, syntax | Apache-2.0 |
| **cocotb** | Python testbenches; differential test vs Python model; CVDP's harness | BSD-3-Clause |
| **sv2v** | SV → Verilog for tools with weak SV (opencdc path already uses it) | BSD-3-Clause |
| **PeakRDL / systemrdl-compiler** | Register RTL / RAL / headers (already in RTL_SPEC) | peakrdl-regblock LGPL-3.0 (generated output is yours); systemrdl-compiler MIT |
| Pyverilog | AST for driver-cone tracing (VerilogCoder AST-WT) | Apache-2.0 |
| Amaranth / Chisel | Python/Scala HDLs. Not recommended as the generation target: CBflow's flows consume SV, and LLM training data is far richer in Verilog/SV. Could be an IR in future. | BSD-2-Clause / Apache-2.0 |

The CBflow container (`hpretl/iic-osic-tools`, pinned in `global/bin/cbflow-oss`) is believed to
ship iverilog, verilator, yosys, sby and cocotb — **confirm with `cbflow-oss check`** before
relying on any of them `[unverified]`.

---

## 5. Recommendation: CBflow `spec2rtl` skill

### 5.1 Principles

- Reuse, don't duplicate: RTL_SPEC owns the spec schema / registers / collateral; RTL_LINT,
  RTL_CDC, UPF_CHECK and the DV flows are the **outer gates and the source of truth for exits**
  (SPEC_EXIT, LINT_SIGNOFF, CDC_SIGNOFF, UPF_SIGNOFF, TB_SETUP_EXIT/M1…). The skill runs a fast
  inner loop directly via `cbflow-oss`, then hands to the real flows.
- Spec-first: the YAML block spec (`<block>.spec.yaml`) + SystemRDL is the contract. The skill
  extends it with a micro-architecture doc, never silently changes it.
- Separate authors: reference model + tests written in a separate subagent context from the RTL.
- Every iteration on a branch/worktree, one commit per gate pass.

### 5.2 Stages, artifacts, gates

| # | Stage | Artifacts (under `inputs/<proj>/<block>/<phase>/`) | Gate | Human checkpoint |
|---|---|---|---|---|
| S0 | **Intake & clarification** | Draft / updated `spec/<b>.spec.yaml`, `spec/<b>_regs.rdl`; `spec/<b>.questions.md` (Q&A log) | `spec_tool.py check` (RTL_SPEC spec_check) passes | **Yes**: answer the open questions (reset, latency, back-pressure, error/illegal-input behaviour, clocks/CDC, power states, memories, performance targets) |
| S1 | **Micro-architecture** | `uarch/<b>.uarch.md` + machine-readable `uarch/<b>.uarch.yaml`: module tree, per-module ports/widths/protocol/latency/reset values, FSM transition tables, datapath widths, pipelines, memory usage, clock domains + synchronizer plan | Consistency check script: uarch top ports == spec ports (`spec_tool.py ports`), every interface/memory/register block mapped to a module, every FSM table complete | **Yes**: approve the micro-architecture (cheapest point to fix design intent) |
| S2 | **Reference model + tests** (separate subagent) | `model/<b>_model.py` (transaction/cycle model from spec+uarch), `tb/cocotb/test_<module>.py` per module + top, directed tests per spec feature (vPlan IDs F1…), `formal/<module>_props.sv` (protocol/reset/one-hot/overflow props, immediate-assert style) | Model self-tests pass; tests reference vPlan feature IDs | Optional review of the model for complex algorithms |
| S3 | **Register / collateral generation** | Run the existing RTL_SPEC flow: PeakRDL regblock, RAL, header, IP-XACT, SDC, UPF, filelist, vPlan | RTL_SPEC run clean | — |
| S4 | **Leaf-module RTL loop** (bottom-up) | `rtl/<module>.sv` | Inner gate ladder per module (below) | Escalate on cap |
| S5 | **Integration** | `rtl/<b>.sv` top, `rtl/<b>.f` | Top-level ladder + differential sim vs model; `spec_tool.py ports` RTL-vs-spec | — |
| S6 | **Outer gates (real CBflow flows)** | RTL_SPEC release (SPEC_EXIT) → RTL_LINT (verilator: slang+Verilator+Verible) → RTL_CDC (opencdc) → UPF_CHECK (rtlcheck) | `violations_final.csv` empty or waived (`<arr>(oss,waivers)` YAML with reason/owner/expires — agent may only **propose** waivers) | **Yes**: waivers, and sign-off of LINT/CDC/UPF exits |
| S7 | **DV hand-off** | `uvmgen.py` env from spec + RAL + vPlan; port the cocotb model's checks into `<b>_ref_model.sv` / `<b>_tests.sv` user files; TB_SETUP / M1 via `dv_tool.py regress` + covmerge | TB_SETUP_EXIT, M1 targets (`project(dv,targets,M1)`) | DV owner owns vPlan from here |
| S8 | **Synthesis smoke** | SYNTH (yosys-slang `read_slang` on the LINT_SIGNOFF filelist), area vs uarch estimate | No latches, no undriven, area within estimate | Optional |

**Inner gate ladder (S4/S5), all via `cbflow-oss`, cheapest first:**

1. `slang` elaborate — zero errors.
2. `verilator --lint-only -Wall` — zero warnings except an explicit allow-list
   (fail on WIDTH*, LATCH, COMBDLY, BLKSEQ, UNDRIVEN, MULTIDRIVEN, CASEINCOMPLETE).
3. `verible-verilog-lint` — style rules from the project.
4. `yosys` (slang front end) `synth; check -assert` + count `$dlatch` = 0, no comb loops, cell count logged.
5. cocotb unit tests (Icarus or Verilator) vs `model/` — all pass.
6. `sby` BMC (depth ~20–40) + cover on the module's properties; k-induction where cheap.
7. Coverage (Verilator `--coverage`) — line/toggle report recorded; gaps → new tests (S2 subagent).

**Debug feedback format** (what the RTL agent sees on failure): gate name; for compile/lint the
first N diagnostics with file:line; for sim the test name, first mismatching cycle, a ±8-cycle
table of inputs/expected/actual, and the driver cone of the failing output (Pyverilog or
slang-based) with the relevant RTL lines; for formal the sby counterexample trace as a table.

### 5.3 Iteration limits and escalation

- Syntax/lint fixes: ≤5 per module per gate (MAGE).
- Functional debug: ≤10 iterations per module (2508.05266), then one attempt with fresh context
  re-reading spec + uarch, then **escalate**.
- Escalate immediately when: the same mismatch repeats 3×; the fix requires changing the spec
  or uarch contract; RTL and test disagree and the spec does not decide which is right; a
  waiver would be needed; CDC structure is involved.
- Hard budget per block (wall-clock / token) set in the skill invocation; report progress per
  module.

### 5.4 What to ask the human (and when)

- S0: ambiguous behaviour list (one consolidated question set, not drip-fed).
- S1: approve micro-architecture (module split, latency, pipelining, memory mapping, CDC plan).
- During S4/S5 only on escalation, with evidence (trace table + candidate interpretations).
- S6: any waiver; exit sign-off.
- Never: auto-edit project config files (CBflow rule) — propose overrides instead.

### 5.5 Reuse map

| Need | Existing CBflow piece |
|---|---|
| Spec schema, checks, port extraction | `RTL/utils/oss/spec_tool.py` (`check`, `ports`, `regs`, `ipxact`, `sdc`, `upf`, `filelist`, `vplan-init`) |
| Lint / CDC / UPF collection + waivers | `RTL/utils/oss/rtl_check.py` (`lint-collect`, `cdc-collect`, `upf-check`, `waive`, `summary`); node configs `RTL_LINT_verilator`, `RTL_CDC_opencdc`, `UPF_CHECK_rtlcheck` |
| UVM env + regress / coverage / signoff | `DV/utils/oss/uvmgen.py`, `DV/utils/oss/dv_tool.py` |
| Chain orchestration | `workarea/run_spec2gds.sh`, `project(signoff_chain,<phase>)` |
| Exit gating | checklist skill / `cbflow flow checklist` (SPEC_EXIT, LINT_SIGNOFF, CDC_SIGNOFF, UPF_SIGNOFF, TB_SETUP_EXIT, M1…) |
| Pilot to validate the skill | gcd P3 (`inputs/opensky/gcd/P3/`): regenerate RTL from its spec and compare against the hand-written RTL / smoke TB |

### 5.6 Gaps to close for the skill

- A cocotb + Python-model harness helper (new, e.g. `RTL/utils/oss/spec2rtl_tool.py`: `sim`,
  `trace` (first-mismatch window + driver cone), `formal` (sby wrapper), `synth-check`).
- uarch YAML schema + checker (extend spec schema or a sibling file).
- Confirm sby / cocotb / Pyverilog availability in the pinned image.
- RDC remains unchecked open-source (existing gap).

### 5.7 Suggested evaluation of the skill itself

Run it on (a) a handful of VerilogEval-v2 spec-to-RTL and RTLLM 2.0 problems (sanity),
(b) a few CVDP cid03/cid05 problems (realistic; cocotb harnesses fit our loop), and (c) the gcd
P3 accelerator end-to-end through LINT_SIGNOFF and M1. Track: gate pass rates, iterations per
module, human escalations, final lint/CDC violations, area vs hand RTL.

---

## Sources

- Spec2RTL-Agent — https://arxiv.org/abs/2506.13905 ; https://arxiv.org/html/2506.13905v2 ; https://research.nvidia.com/publication/2025-06_spec2rtl-agent-automated-hardware-code-generation-complex-specifications-using
- VerilogCoder — https://arxiv.org/abs/2408.08927v2 ; https://arxiv.org/html/2408.08927v2 ; https://ojs.aaai.org/index.php/AAAI/article/view/32007
- MAGE — https://arxiv.org/abs/2412.07822 ; https://arxiv.org/html/2412.07822v1 ; https://stable-lab.github.io/MAGE
- AutoChip — https://arxiv.org/abs/2311.04887v2 ; https://arxiv.org/abs/2411.11856v2
- VeriAssist — https://arxiv.org/abs/2406.00115v1
- AIvril — https://arxiv.org/abs/2409.11411v1 ; AIVRIL2 — https://arxiv.org/html/2412.04485v1
- VeriMoA — https://arxiv.org/abs/2510.27617
- Veri-Sure — https://arxiv.org/abs/2601.19747
- Hierarchical IRs multi-agent — https://arxiv.org/abs/2608.30659
- HORIZON (repository-level evolution) — https://arxiv.org/abs/2606.28279
- VeriMaAS — https://arxiv.org/html/2509.20182v1
- ChipGPT — https://arxiv.org/abs/2305.14019v4
- HDLCoRe — https://arxiv.org/abs/2503.16528
- Errors of LLM-generated RTL — https://arxiv.org/html/2508.05266v2
- RTLCoder/OriGen/CodeV comparisons — https://arxiv.org/pdf/2407.10424 ; https://arxiv.org/html/2407.16237v2 ; https://arxiv.org/pdf/2504.15659
- CodeV-R1 — https://arxiv.org/html/2505.24183v5
- PyraNet — https://arxiv.org/abs/2412.06947v3 ; https://huggingface.co/datasets/bnadimi/PyraNet-Verilog
- RTL++ — https://arxiv.org/abs/2505.13479v1
- VerilogEval v2 — https://arxiv.org/abs/2408.11053v2 ; https://github.com/nvlabs/verilog-eval
- RTLLM — https://arxiv.org/pdf/2308.05345 ; OpenLLM-RTL / RTLLM 2.0 — https://arxiv.org/abs/2503.15112
- CVDP — https://arxiv.org/abs/2506.14074 ; https://arxiv.org/html/2506.14074v1 ; https://si2.org/summary-and-key-improvements-in-cvdp1-1-0/
- RTL-BenchLS taxonomy — https://arxiv.org/pdf/2606.08976 ; other error notes — https://arxiv.org/pdf/2403.07039 ; https://arxiv.org/pdf/2405.02329
- SVA/formal LLM work — ProofLoop https://arxiv.org/pdf/2604.23100 ; HierSVA https://arxiv.org/pdf/2606.13706 ; ChatSVA https://arxiv.org/pdf/2604.02811
- SymbiYosys SVA support — https://yosyshq.readthedocs.io/projects/sby/en/stable/verilog.html ; https://yosyshq.readthedocs.io/projects/sby/en/stable/verific.html
- PeakRDL licensing — https://peakrdl-regblock.readthedocs.io/en/stable/licensing.html ; https://pypi.org/project/systemrdl-compiler/
