# DFT Flow Reference

The DFT diagram describes 11 fine-grained activities. CBflow consolidates them
into 7 flows — three DFT insertion passes (split on 2026-11-03), scan, ATPG and
two gate-level simulation flows — because the framework's units of work are
configurable runs, not single tool invocations. Variants are knobs on the run,
not separate flows.

## Diagram-to-flow mapping

| #  | Activity in diagram                                | Flow              | Stage(s)                                        |
|----|----------------------------------------------------|-------------------|-------------------------------------------------|
| 1  | RTL (input)                                        | `DFT_INSERT_PASS1`| `rtl1`                                          |
| 2  | DFT Insertion of MBIST (+ BSCAN / TAP)             | `DFT_INSERT_PASS1`| `tap_cfg1`, `bscan_cfg1`, `mbist_cfg1`, `*_spec1`, `insert1` |
| —  | Top DFT: TDR, DFT signals, SRI                     | `DFT_INSERT_PASS2`| `tdr_cfg1`, `dft_spec1`, `insert1`              |
| 3  | DFT Insertion of OCC                               | `DFT_INSERT_PASS3`| `occ_spec1`, `insert1`                          |
| 4  | DFT Insertion of EDT/SSN                           | `DFT_INSERT_PASS3`| `edt_spec1`, `insert1`                          |
| 5  | DFT Verification                                   | `DFT_INSERT_PASS1/2/3` | `drc1` / `drc2`, `vgen1`, `sim1`           |
| 6  | Logical Synthesis                                  | `SYNTH` (PD)      | (handed off via `from_run` or `release_tag`)    |
| 7  | Logical Netlist (handoff)                          | `SCAN_INSERT`     | `netlist1`                                      |
| 8  | Scan Insertion                                     | `SCAN_INSERT`     | `scan_stitch1`, `scan_check1`, `scan_export1`   |
| 9  | ATPG (patterns + fault sim)                        | `ATPG`            | `pattern_gen1`, `fault_sim1`, `coverage_report1`, `export_patterns1`, `zd_sim1` / `timing_sim1`, `signoff1` |
| 10 | Physical Implementation                            | `PNR` (PD)        | (handed off via `from_run` or `release_tag`)    |
| 11 | GLS — Scan ZD / SDF, Functional, MBIST, BSCAN      | `GLS_FUNC` + `GLS_SCAN_MBIST` (with mode/verify_type knobs) | `run_sim1` |

Pass chaining: PASS1 release → PASS2 (`dft_insert_pass2(input,netlist)`) →
PASS3 → SCAN_INSERT; PASS3's `<d>.edt_occ.v` is also the `SYNTH,dft_netlist` /
`PNR,dft_netlist` handshake input. Exits: CORE_DFT_EXIT (PASS1), TOP_DFT_EXIT
(PASS2), EDT_OCC_EXIT (PASS3), SCAN_INSERT_EXIT, ATPG_PREPD_EXIT,
ATPG_POSTPD_EXIT.

On the open-source stack (`opensource-dft-guide.md`) scan is inserted inside
SYNTH; SCAN_INSERT signs the structure off and the insertion passes are not
covered yet.

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

# Read from a released SYNTH tag (every SCAN_INSERT,* handshake input)
set scan_insert(input,release_tag) "P0_SYNTH_v1"
```

The same three mechanisms work in reverse for PD runs consuming DFT outputs
(e.g. `pnr(input,netlist)` ← `DFT_INSERT_PASS3` or `SCAN_INSERT` output).

## Why 7 flows, not 11?

| Reason | Detail |
|---|---|
| Knobs over flows | "ATPG with SDF" is the same engine as "ATPG with ZD" — just a different input set. Splitting them creates two flows that share 95% of their stage list. |
| Single signoff per discipline action | A user runs "ATPG" once and gets all pattern types (stuck-at + transition + path-delay). Three flows would force three separate sign-offs for one logical milestone. |
| Pass boundaries | The insertion is split only where the owner spreadsheet hands a release from one team step to the next (core MBIST + BSCAN → top TDR / SRI → EDT + OCC); within a pass RACE runs the stages as one DAG. |
| Reuse the handoff system | `SYNTH` ↔ `SCAN_INSERT` ↔ `PNR` chaining works today via `from_run` and `release_tag` — no new mechanism needed. |
