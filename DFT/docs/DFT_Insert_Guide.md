# DFT_INSERT Guide

Insert MBIST, OCC, and EDT/SSN test logic into RTL.

## Stages

```
rtl1 → init_dft1 → insert_mbist1 ┐
spec1 ─────┘                      ├→ insert_edt1 → dft_verify1 → dft_inserted_export1 → release_data1
lib1 ──────┘  insert_occ1 ────────┘
```

Insertion of MBIST, OCC, and EDT each run as separate stages so they can be
debugged and re-run independently. MBIST and OCC run in parallel; EDT depends
on both.

## Supported tools

| Vendor    | Tool          | `tool,name` value |
|-----------|---------------|-------------------|
| Mentor    | Tessent       | `tessent`         |
| Synopsys  | DFT Compiler  | `dft_compiler`    |

## Minimal user config

```tcl
set project(name) "ravendrive"
set project(phase) "P0"
set project(track_variant) "9T"
set flow(type) "DFT_INSERT"
set flow(design_name) "cpu_core"
set flow(run_name) "v1"
set flow(run_type) "hier"

set dft_insert(tool,name) "tessent"
set dft_insert(input,rtl)      "/path/to/cpu_core.v"
set dft_insert(input,dft_spec) "/path/to/dft_spec.tcl"
```

## Knobs

```tcl
# MBIST
set dft_insert(mbist,controller_type)   "smart_serial"  ;# or "static_distributed"
set dft_insert(mbist,wrap_memories)     true
set dft_insert(mbist,bist_clock_domain) "tessent_clk"

# OCC
set dft_insert(occ,scan_enable_pin) "scan_en"
set dft_insert(occ,test_clock_pin)  "test_clk"
set dft_insert(occ,at_speed)        true

# EDT / SSN
set dft_insert(edt,compression_ratio) 100
set dft_insert(edt,input_channels)    8
set dft_insert(edt,output_channels)   8
set dft_insert(edt,ssn,enable)        true

# Verify
set dft_insert(verify,drc_level)          "strict"
set dft_insert(verify,coverage_threshold) 98.0
```

## Run

```bash
cd workarea/cpu_core/P0_run_DFT_INSERT_v1
cbflow run all
cbflow run status
```

## Outputs

- `outputs/cpu_core.mbist.v` — MBIST-wrapped netlist
- `outputs/cpu_core.occ.v` — OCC-instrumented netlist
- `outputs/cpu_core.edt.v` — EDT/SSN-compressed netlist
- `outputs/cpu_core.dft.v` — final DFT-inserted RTL (passed to SYNTH)
- `outputs/dft_manifest.tcl` — manifest of all DFT outputs
- `reports/dft_insert/*.rpt` — MBIST / OCC / EDT / verify insertion reports
