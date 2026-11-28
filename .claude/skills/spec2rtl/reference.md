# spec2rtl reference

## RTL rules (the failure modes LLM-written RTL shows most — research §2)
- **Nets and blocks:**
  - `` `default_nettype none `` at the top of each file (restore `wire` at the end).
  - `always_ff @(posedge clk)` with non-blocking `<=` only.
  - `always_comb` with blocking `=` only, every output given a default at the
    top of the block, so no latches.
- **Reset:** exactly as the spec says: `resets[].active` (high / low) and
  `synchronous`. Reset every control register; datapath registers only when
  the spec needs a value.
- **Widths:**
  - Explicit widths on every signal; sized constants (`16'd0`, `'0`).
  - No implicit truncation or extension: slice or zero-extend on purpose.
  - Counters wide enough for the maximum count + 1 (e.g. a 256-deep queue
    count needs 9 bits).
- **Registers:** only through the generated register block (`hwif_in.<REG>.<field>.next`
  / `.hwif_out.<REG>.<field>.value`, `.swmod`, `.hwset`). Never hand-write a register
  decoder; change the RDL instead (and re-run `ctx`).
- **FSMs:** `typedef enum logic [n:0]`, a `default` branch, and a state table in
  `uarch.md`.
- **Interfaces:**
  - valid / ready: data is held while `valid && !ready`, and valid never drops
    before the handshake.
  - APB: respond in the access phase (`psel && penable`).
- **Testbench output convention** (the sim gate parses it): one line starting
  with `PASS` (or `TEST PASSED`) when everything passed; each failure on a line
  starting with `FAIL` (or `ERROR:`). Don't print those words elsewhere.
- **SRAM model log volume:** the sky130 SRAM behavioural model prints every access
  (`VERBOSE=1`). Enable the read ports only when reading (it also saves power), and
  keep long tests from logging millions of lines.
- **Memory macros:** connect exactly the pins `ctx.md` lists. sky130 SRAM: `csb` /
  `web` active low; read data one cycle after the address; separate clocks per
  port. Read the macro model in the library tag when unsure.
- **Synthesizable only:** no `initial` (except the generated SVA), no `#` delays,
  no `$display` in RTL, no `real`. Single clock unless the spec defines more
  (CDC → escalate).
- **Ports:** the port list is exactly the spec's (names, directions, widths). The
  scaffold writes it; don't edit it.

## Gates (`s2r.py gate`)
| Stage | Tool | Fails on |
|---|---|---|
| lint | `verilator --lint-only -Wall` + `slang` | errors, and warning classes LATCH, WIDTH*, BLKSEQ, COMBDLY, MULTIDRIVEN, UNDRIVEN, IMPLICIT, SELRANGE, CASEINCOMPLETE, ALWCOMBORDER, MULTITOP, UNOPTFLAT in **your** files (generated register block / PDK models counted apart) |
| synth | `sv2v` + `yosys` (`proc`, latch select-assert, `check`, coarse synth) | inferred latches, multiple / missing drivers, logic loops, elaboration errors; reports the cell count |
| ports | yosys JSON + `spec_tool.py ports` | port name / direction / width vs spec; memory instances vs spec memories / library macros |
| sim | Verilator `--binary --timing --assert` (SV tb, module name read from the file) or cocotb `make` | non-zero exit, a line starting with `FAIL` / `ERROR:` / `%Error`, a failed assertion, or no line starting with `PASS` / `TEST PASSED` |
| formal | SymbiYosys (`smtbmc z3`, prove, depth 12) on `<top>_ftop` | an assertion counterexample (`trace.vcd`) or elaboration error |

Formal details:
- Memory macros become free-output models (`$anyseq`), read with
  `read_verilog -formal`.
- The RTL goes through `read_slang -D FORMAL --extern-modules`.
- The harness starts in reset and leaves inputs free, under the protocol assumes.

Calibration (2026-11-28, gcd P3 hand-written RTL + smoke tb):
- The reference RTL passes all five stages; formal proves by induction.
- Blind regeneration (2026-11-28): an agent following this skill rebuilt gcd P3 from
  the spec alone. It wrote 280 lines of RTL; all 5 gates pass, and the hand-written
  oracle smoke testbench passes first time. Formal caught one real RTL bug (a
  reachable state that dropped `resp_val`).
- Each injected bug was caught by its gate:
  - a latch → synth;
  - a port width → ports;
  - an off-by-one result → sim;
  - valid dropped under back-pressure → formal counterexample.

## Assertions (open-source formal = immediate assertions)
SymbiYosys without Verific has no concurrent SVA (`property … |=>`). Write:
```systemverilog
always @(posedge clk) if (past_ok && !rst && !$past(rst)) begin
    if ($past(v && !r)) assert (v);                 // outputs: assert
    if ($past(in_v && !in_r)) assume (in_v);        // inputs: assume
end
```
`$past`, `$stable` and `$rose` / `$fell` are fine. Assert what the block drives;
assume what it receives.

## Debug method (research §1: first mismatch + local context)
1. Take the **first** failing check (sim log / gate.json), not the last.
2. Name the failing output and its expected / actual value at that cycle.
3. Trace back through the code that drives it: registers, FSM state, control
   conditions. For formal, open the counterexample `trace.vcd`.
4. Find the earliest wrong signal. Compare it with `uarch.md`, then with the
   spec.
5. Fix that cause. Re-run only the failing stage (`--only sim`), then the full
   gate.

## Limits and escalation
- Per module: 5 lint / synth rounds and 10 functional rounds. Then retry once
  from a fresh read of the spec and uarch, then escalate.
- Escalate immediately when:
  - the same failure repeats 3×;
  - a spec / uarch change is needed;
  - a test and the RTL disagree and the spec is ambiguous;
  - a waiver is needed;
  - a CDC or new clock is involved;
  - a register-map change is needed.

## Files
| Path | What |
|---|---|
| `<work>/ctx.md` | design brief (ports per interface, register `hwif` fields, memories + pins, features) |
| `<work>/regs/` | PeakRDL output (rtl / uvm / c / ipxact / html) |
| `<work>/spec.json` | normalized spec (spec_tool check) |
| `<work>/uarch.md`, `questions.md` | micro-architecture, open questions |
| `<rtl>/<top>.sv`, `<rtl>/<top>_sva.sv` | RTL, protocol checks |
| `<work>/<top>_ftop.sv`, `<top>.sby`, `<top>_run/` | formal harness, sby config, run |
| `<work>/gate.json`, `*.log` | gate results and per-stage logs |

## CBflow hand-off
- RTL goes to `inputs/<proj>/<block>/<phase>/rtl/`, with the spec's `rtl.sources`
  updated.
- Run RTL_SPEC (`rtl_spec(tool,name) "rtlcheck"`): register block, RAL, IP-XACT,
  SDC, UPF, filelist, vPlan; SPEC_EXIT.
- Then RTL_LINT (`verilator`) → LINT_SIGNOFF, RTL_CDC (`opencdc`) → CDC_SIGNOFF,
  UPF_CHECK (`rtlcheck`) → UPF_SIGNOFF.
- Then DV: TB_SETUP (uvmgen: RAL + vPlan) and M1-M4.
- Guides: `RTL/docs/opensource-rtl-guide.md`, `DV/docs/opensource-dv-guide.md`.
