# GLS Verification Guide

Gate-level simulation across functional and test (scan/MBIST/BSCAN) patterns,
in zero-delay or SDF-annotated modes.

## Two flows

| Flow              | Pattern source                          | Use case                                  |
|-------------------|-----------------------------------------|-------------------------------------------|
| `GLS_FUNC`        | Functional testbench (user-written)     | Verify gate-level functional behavior     |
| `GLS_SCAN_MBIST`  | ATPG patterns (STIL) or MBIST sequences | Verify scan/MBIST/BSCAN test patterns     |

## Stages (both flows)

```
GLS_FUNC:
  netlist1 ┐
  sdf1     ├→ init_sim1 → compile1 → run_sim1 → coverage1 → release_data1
  testbench1 ┤
  lib1     ┘

GLS_SCAN_MBIST:
  netlist1 ┐
  sdf1     ├→ init_sim1 → compile1 → run_sim1 → coverage1 → release_data1
  patterns1 ┤
  lib1     ┘
```

## Supported tools

| Vendor    | Tool    | `tool,name` value |
|-----------|---------|-------------------|
| Synopsys  | VCS     | `vcs`             |
| Mentor    | Questa  | `questa`          |

## Minimal user config

```tcl
# GLS_FUNC
set flow(type) "GLS_FUNC"
set gls_func(tool,name) "vcs"
set gls_func(mode) "zd"
set gls_func(input,netlist)   "/path/to/cpu_core.synth.v"
set gls_func(input,testbench) "/path/to/cpu_core_tb.sv"
# sdf mode only:
set gls_func(input,sdf) "/path/to/cpu_core.sdf"

# GLS_SCAN_MBIST
set flow(type) "GLS_SCAN_MBIST"
set gls_scan_mbist(tool,name) "vcs"
set gls_scan_mbist(mode) "zd"
set gls_scan_mbist(verify_type) "scan"   ;# scan | mbist | bscan
set gls_scan_mbist(input,netlist)  "/path/to/cpu_core.scan.v"
set gls_scan_mbist(input,patterns) "/path/to/cpu_core.patterns.stil"
```

## Mode and verify_type knobs

```tcl
# Delay mode (both flows)
set gls_func(mode)        "zd"   ;# zero-delay — fast
set gls_func(mode)        "sdf"  ;# annotated — catches timing issues

# Which test type (GLS_SCAN_MBIST only)
set gls_scan_mbist(verify_type) "scan"   ;# stuck-at, transition scan patterns
set gls_scan_mbist(verify_type) "mbist"  ;# MBIST BIST sequences
set gls_scan_mbist(verify_type) "bscan"  ;# boundary scan / JTAG
```

## Other knobs

```tcl
set gls_func(sim,timescale) "1ns/1ps"
```

## Run

```bash
cd workarea/cpu_core/P0_run_GLS_FUNC_v1
cbflow run all
```

## Outputs

- `outputs/sim.log` — simulator log (errors, warnings, $finish reason)
- `outputs/coverage.ucdb` — coverage database (UCDB for Questa, VDB for VCS)
- `reports/gls_func/coverage_summary.txt` — coverage roll-up
