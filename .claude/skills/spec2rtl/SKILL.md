---
name: spec2rtl
description: Generate synthesizable SystemVerilog RTL for a CBflow block from its specification (CBflow block spec YAML + SystemRDL / XLS registers, or a natural-language spec turned into one) — clarify the spec, write a micro-architecture, build an independent reference model and self-checking testbench, scaffold the top (exact spec ports, generated register block, memory macros, protocol assertions), implement the logic and iterate against gates (verilator + slang lint, yosys latch / driver / synthesis check, RTL-vs-spec ports, simulation, SymbiYosys formal) until clean, then hand the RTL to the CBflow RTL_SPEC / RTL_LINT / RTL_CDC / UPF_CHECK flows and DV. Use when the user asks to write / generate RTL from a spec, implement a block, spec-to-RTL, or turn a design document into Verilog.
---

# Spec to RTL

You write the RTL; `scripts/s2r.py` does everything deterministic around it
(brief, scaffold, gates). Read [reference.md](reference.md) first: the RTL
rules, gate meanings, debug method and iteration limits. The pipeline follows
the published agentic systems (`RTL/docs/research/spec2rtl-research.md`): spec
and micro-architecture before code, an independent test oracle, and tool
feedback in a bounded loop.

Variables:
- `$K` = `python3 .claude/skills/spec2rtl/scripts/s2r.py`;
- `<work>` = a scratch dir per block;
- `<rtl>` = the RTL dir being written;
- `<lc>` = the library tag's `lib_config.tcl` (memory macro models);
- `export CBFLOW_OSS_TOOLS=<lsf(oss,tools_dir)>` (e.g. `~/eda/tools/oss`).

## S0. Spec — clarify before anything else
- **With a spec YAML** (`inputs/<proj>/<block>/<phase>/spec/<block>.spec.yaml`):
  `$K ctx --spec <yaml> --work <work> --lib-config <lc>` validates it (spec_tool
  check), generates the register block, and writes `<work>/ctx.md`. Read the brief.
- **Without one** (only a document or description): write the YAML in the CBflow
  schema (copy the structure of `inputs/opensky/gcd/P3/spec/`):
  - block, clocks, resets, ports, interfaces (protocols);
  - registers (SystemRDL; `littleendian = true;`);
  - memories, features with test names and milestones.

  Then run `ctx`.
- **Ambiguities:** list them in `<work>/questions.md`, then ask the user once, in
  one batch. Typical ones:
  - reset polarity and sync / async;
  - latency and throughput;
  - back-pressure;
  - widths, overflow and wrap behaviour;
  - register side effects (W1C, single-pulse);
  - memory port use and read latency;
  - error responses;
  - what happens on simultaneous events.

  Record the answers in the spec, not only in chat. **Never invent behaviour
  the spec doesn't give.**

## S1. Micro-architecture (`<work>/uarch.md`) — the user approves it
Write it before any RTL. It covers:
- module tree;
- per-interface cycle contracts;
- datapath widths;
- FSM state / transition table;
- latency per operation;
- reset values;
- a table of which logic drives or reads each `hwif_in` / `hwif_out` field;
- the cycle-by-cycle use of each memory port;
- arbitration / priority;
- the assertions to add.

Check it against `ctx.md`: every port and feature must be covered. Show it to the
user and get approval, or their changes, before S3.

## S2. Independent reference model + tests (separate agent)
Spawn a subagent that gets **only** the spec, `ctx.md` and `uarch.md`, never your
RTL. It writes the test oracle:
- a Python (or SV) reference model;
- a self-checking testbench, either an SV file (`module tb`, Verilator `--timing`)
  or a cocotb directory with a Makefile;
- one test per spec feature (the feature's `tests` names), with random plus
  corner cases;
- `PASS` when everything passes, `FAIL <test> <cycle> <signal> exp=<> got=<>` per
  mismatch.

Keep its testbench separate from `<rtl>`. When the RTL and the tests disagree
later, **the spec decides** who is wrong. If the spec can't decide, ask the user.

## S3. Scaffold
```bash
$K scaffold --spec <yaml> --work <work> --rtl <rtl> --lib-config <lc>
```
It writes `<rtl>/<top>.sv` with:
- the exact spec ports;
- the generated register block instance and `hwif` structs;
- memory macro instances with their pins.

It also writes `<rtl>/<top>_sva.sv` (valid / ready + APB protocol checks: asserts
on outputs, assumes on inputs; bound for simulation), plus `<work>/<top>_ftop.sv`
and `<work>/<top>.sby` for formal. It never overwrites a file. Keep the port list
exactly as generated. Add properties from `uarch.md` to `<top>_sva.sv`
(immediate assertions with `$past` only — see reference.md).

## S4. Implement + gate loop
Implement bottom-up, following the RTL rules (reference.md). After each
meaningful change, run:
```bash
$K gate --spec <yaml> --work <work> --rtl <rtl> --lib-config <lc> --tb <tb.sv|cocotb dir> --sby <work>/<top>.sby
```
The stages run in order: lint → synth → ports → sim → formal. `--only` narrows
them while debugging. On FAIL:
- **Read the first error**, not the whole log: `<work>/gate.json` and the stage
  log.
- **Simulation:** take the first mismatching cycle and trace the failing output
  back through its drivers to the cause.
- **Formal:** read `<work>/<top>_run/engine_0/trace.vcd` (the counterexample).

Fix the cause, not the symptom. Limits per module: 5 lint / synth fix rounds and
10 functional debug rounds. Escalate to the user right away when:
- the same failure repeats 3 times;
- the fix needs a spec or uarch change;
- a test and the RTL disagree and the spec can't decide;
- a waiver is needed;
- clock-domain crossing appears.

Done = all stages PASS, and every spec feature has a passing test.

## S5. Hand to CBflow
Ask the user before writing into `inputs/` (repo files):
1. Copy `<rtl>/*.sv` to `inputs/<proj>/<block>/<phase>/rtl/`, and set the spec's
   `rtl.sources`.
2. Put the testbench under `.../tb/`.
3. Run the CBflow RTL flows, either `workarea/run_spec2gds.sh <block> <phase>
   UNTIL=2` (if the phase has a signoff chain) or workspace create + `run all`
   for RTL_SPEC, then RTL_LINT, RTL_CDC and UPF_CHECK. The exits are SPEC_EXIT,
   LINT_SIGNOFF, CDC_SIGNOFF and UPF_SIGNOFF.
4. Fix what they report: those flows are the signoff, and the gates are the inner
   loop. Propose waivers (YAML with reason, owner, expiry); the user approves
   them.
5. Optionally go on to DV: TB_SETUP (uvmgen) and M1.

## S6. Report
Report:
- the files;
- `gate.json` (every stage PASS);
- feature → test → result;
- the formal property list and its result;
- the CBflow flow exits reached;
- open questions or waivers;
- anything the spec left to an assumption (state each one).
