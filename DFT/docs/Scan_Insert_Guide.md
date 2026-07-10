# SCAN_INSERT Guide

Stitch flops into scan chains, produce scan-inserted netlist + scandef.

## Stages

```
netlist1 ┐
sdc1     ├→ init_scan1 → scan_stitch1 → scan_check1 → scan_export1 → release_data1
lib1     ┘
```

## Supported tools

| Vendor    | Tool          | `tool,name` value |
|-----------|---------------|-------------------|
| Mentor    | Tessent       | `tessent`         |
| Synopsys  | DFT Compiler  | `dft_compiler`    |

## Minimal user config

```tcl
set project(name) "bumblebee"
set project(phase) "P0"
set project(track_variant) "9T"
set flow(type) "SCAN_INSERT"
set flow(design_name) "cpu_core"
set flow(run_name) "v1"
set flow(run_type) "hier"

set scan_insert(tool,name) "tessent"
set scan_insert(input,netlist) "/path/to/synth_output.v"
set scan_insert(input,sdc)     "/path/to/cpu_core.sdc"
```

## Knobs

```tcl
# Tessent
set scan_insert(scan,chain_count)            16
set scan_insert(scan,clock_domain_aware)     true

# DFT Compiler
set scan_insert(scan,style) "multiplexed_flip_flop"
```

## Run

```bash
cd workarea/cpu_core/P0_run_SCAN_INSERT_v1
cbflow run all
```

## Outputs

- `outputs/cpu_core.scan.v` — scan-stitched netlist
- `outputs/scan.scandef` — scan chain definition (consumed by PNR and ATPG)
- `reports/scan_insert/scan_chains.rpt` — chain count, avg/max length
- `reports/scan_insert/scan_drc.rpt` — scan shift/capture DRC results
