# DFT Flow Reference

The DFT diagram describes 11 fine-grained activities. CBflow consolidates them
into 5 flows because the framework's units of work are configurable runs, not
single tool invocations. Variants are knobs on the run, not separate flows.

## Diagram-to-flow mapping

| #  | Activity in diagram                                | Flow              | Stage(s)                                        |
|----|----------------------------------------------------|-------------------|-------------------------------------------------|
| 1  | RTL (input)                                        | `DFT_INSERT`      | `rtl1`                                          |
| 2  | DFT Insertion of MBIST                             | `DFT_INSERT`      | `insert_mbist1`                                 |
| 3  | DFT Insertion of OCC                               | `DFT_INSERT`      | `insert_occ1`                                   |
| 4  | DFT Insertion of EDT/SSN                           | `DFT_INSERT`      | `insert_edt1`                                   |
| 5  | DFT Verification                                   | `DFT_INSERT`      | `dft_verify1`                                   |
| 6  | Logical Synthesis                                  | `SYNTH` (PD)      | (handed off via `from_run` or `release_tag`)    |
| 7  | Logical Netlist (handoff)                          | `SCAN_INSERT`     | `netlist1`                                      |
| 8  | Scan Insertion                                     | `SCAN_INSERT`     | `scan_stitch1`, `scan_check1`, `scan_export1`   |
| 9  | ATPG (patterns + fault sim)                        | `ATPG`            | `pattern_gen1`, `fault_sim1`, `coverage_report1`|
| 10 | Physical Implementation                            | `PNR` (PD)        | (handed off via `from_run` or `release_tag`)    |
| 11 | GLS — Scan ZD / SDF, Functional, MBIST, BSCAN      | `GLS_FUNC` + `GLS_SCAN_MBIST` (with mode/verify_type knobs) | `run_sim1` |

## Knobs (consolidating variants into single flows)

```tcl
# ATPG — Zero-Delay vs SDF
set atpg(mode) "zd"     ;# or "sdf"

# GLS_FUNC — Zero-Delay vs SDF
set gls_func(mode) "zd"     ;# or "sdf"

# GLS_SCAN_MBIST — which test type to simulate
set gls_scan_mbist(mode)        "zd"     ;# or "sdf"
set gls_scan_mbist(verify_type) "scan"   ;# or "mbist", "bscan"
```

## Cross-discipline handoff

DFT runs consume PD outputs (synthesized netlists, scandef, SDF) via the
standard CBflow handshake:

```tcl
# Read SYNTH output by absolute path
set scan_insert(input,netlist) "/path/to/cpu_core.synth.v"

# Read from an upstream PD run directory
set scan_insert(input,from_run) "/path/to/P0_run_SYNTH_test1"

# Read from a released PD milestone
set scan_insert(input,netlist_release_tag) "P0_PRO_EXIT"
```

The same three mechanisms work in reverse for PD runs consuming DFT outputs
(e.g. `pnr(input,netlist)` ← `DFT_INSERT` or `SCAN_INSERT` output).

## Why 5 flows, not 11?

| Reason | Detail |
|---|---|
| Knobs over flows | "ATPG with SDF" is the same engine as "ATPG with ZD" — just a different input set. Splitting them creates two flows that share 95% of their stage list. |
| Single signoff per discipline action | A user runs "ATPG" once and gets all pattern types (stuck-at + transition + path-delay). Three flows would force three separate sign-offs for one logical milestone. |
| Stage parallelism | MBIST / OCC / EDT/SSN insertion run in parallel inside `DFT_INSERT` (RACE handles the DAG), so there's no execution win from splitting them. |
| Reuse the handoff system | `SYNTH` ↔ `SCAN_INSERT` ↔ `PNR` chaining works today via `from_run` and `release_tag` — no new mechanism needed. |
