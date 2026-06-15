# ATPG Guide

Automatic test pattern generation, fault simulation, and coverage reporting.

## Stages

```
netlist1 ┐
scandef1 ├→ init_atpg1 → pattern_gen1 → fault_sim1 → coverage_report1 → export_patterns1 → release_data1
sdf1     ┤   (sdf mode only)
lib1     ┘
```

## Supported tools

| Vendor    | Tool      | `tool,name` value |
|-----------|-----------|-------------------|
| Mentor    | Tessent   | `tessent`         |
| Synopsys  | TestMAX   | `testmax`         |

## Minimal user config

```tcl
set project(name) "ravendrive"
set project(phase) "P0"
set project(track_variant) "9T"
set flow(type) "ATPG"
set flow(design_name) "cpu_core"
set flow(run_name) "v1"
set flow(run_type) "hier"

set atpg(tool,name) "tessent"
set atpg(mode) "zd"   ;# "zd" (zero-delay) or "sdf" (timing-aware)

set atpg(input,netlist) "/path/to/cpu_core.scan.v"
set atpg(input,scandef) "/path/to/scan.scandef"
# sdf mode only:
set atpg(input,sdf)     "/path/to/cpu_core.sdf"
```

## Mode knob

- `atpg(mode) "zd"` — zero-delay (no SDF, fastest pattern generation)
- `atpg(mode) "sdf"` — timing-aware (consumes SDF, catches transition / path-delay faults)

## Other knobs

```tcl
# Pattern types (Tessent supports stuck_at + transition + path_delay; TestMAX stuck_at + transition)
set atpg(atpg,pattern_type) "stuck_at transition path_delay"
set atpg(atpg,max_patterns) 100000
```

## Run

```bash
cd workarea/cpu_core/P0_run_ATPG_v1
cbflow run all
```

## Outputs

- `outputs/cpu_core.patterns.stil` — ATPG patterns (STIL format)
- `reports/atpg/pattern_gen.rpt` — pattern count, type breakdown
- `reports/atpg/fault_coverage.rpt` — fault coverage, test coverage
- `reports/atpg/coverage_summary.txt` — summary for sign-off

## Handoff to GLS

Pattern files produced here feed `GLS_SCAN_MBIST`:

```tcl
# In uc_GLS_SCAN_MBIST_*.tcl
set gls_scan_mbist(input,patterns) "/path/to/cpu_core.patterns.stil"
# Or read from the upstream ATPG run:
set gls_scan_mbist(input,from_run) "/path/to/P0_run_ATPG_v1"
```
