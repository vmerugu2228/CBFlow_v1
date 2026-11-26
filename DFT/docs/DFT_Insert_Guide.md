# DFT_INSERT Guide — DFT_INSERT_PASS1 / PASS2 / PASS3

DFT insertion runs as three flows (split on 2026-11-03), each a normal cbflow
run that releases to the next:

| Flow | Inserts | Input | Exit |
|---|---|---|---|
| `DFT_INSERT_PASS1` | Core DFT — TAP, boundary scan (BSCAN), MBIST, test points | RTL | CORE_DFT_EXIT |
| `DFT_INSERT_PASS2` | Top DFT — TDR, DFT signals, SRI | PASS1 netlist | TOP_DFT_EXIT |
| `DFT_INSERT_PASS3` | EDT / SSN compression + OCC (at-speed clocking), control points | PASS2 netlist | EDT_OCC_EXIT |

PASS3's `<design>.edt_occ.v` feeds SCAN_INSERT and the `SYNTH,dft_netlist` /
`PNR,dft_netlist` handshakes. These flows exist for the Mentor / Synopsys tools
only; the open-source stack inserts scan inside SYNTH
(`opensource-dft-guide.md`).

## Stages

Each pass is a linear chain after its three input nodes:

```
PASS1: rtl1 spec1 lib1 → init1 → tap_cfg1 → bscan_cfg1 → mbist_cfg1 → drc1 → tpi1 → drc2
         → tap_spec1 → bscan_spec1 → mbist_spec1 → insert1 → vgen1 → sim1 → release_data1
PASS2: netlist1 spec1 lib1 → init1 → tdr_cfg1 → drc1 → dft_spec1 → insert1 → vgen1 → sim1 → release_data1
PASS3: netlist1 spec1 lib1 → init1 → constraints1 → ctrl_points1 → drc1 → drc_opt1 → drc2
         → edt_spec1 → occ_spec1 → insert1 → vgen1 → sim1 → release_data1
```

PASS2's `vgen1` / `sim1` are optional at that pass (`dft_insert_pass2(vgen,enabled)`,
`(sim,enabled)`, default `false` with Tessent).

## Supported tools

| Vendor    | Tool          | `tool,name` value |
|-----------|---------------|-------------------|
| Mentor    | Tessent       | `tessent` (default) |
| Synopsys  | DFT Compiler  | `dft_compiler`    |

## Minimal user config

```tcl
set project(name) "bumblebee"
set project(phase) "P0"
set flow(type) "DFT_INSERT_PASS1"
set flow(design_name) "cpu_core"
set flow(run_name) "v1"
set flow(run_type) "hier"

set dft_insert_pass1(tool,name)          "tessent"
set dft_insert_pass1(input,rtl)          "/path/to/cpu_core.f"
set dft_insert_pass1(input,dft_spec)     "/path/to/dft_spec.tcl"
set dft_insert_pass1(input,memory_libs)  "/path/to/memlibs"
set dft_insert_pass1(input,tcelllib)     "/path/to/tessent_cell.lib"

# PASS2 / PASS3: the previous pass's netlist instead of RTL
set dft_insert_pass2(input,netlist)      "/path/to/cpu_core.pass1.v"   ;# or a release tag
set dft_insert_pass2(input,dft_spec)     "/path/to/dft_spec.tcl"
set dft_insert_pass2(input,tcelllib)     "/path/to/tessent_cell.lib"
```

Mandatory inputs: PASS1 `input,rtl`, `input,dft_spec`, `input,memory_libs`,
`input,tcelllib`; PASS2 / PASS3 `input,netlist`, `input,dft_spec`,
`input,tcelllib`.

## Knobs (Tessent overlays)

```tcl
# PASS1 — TAP / BSCAN / MBIST / test points
set dft_insert_pass1(tap,ir_width)              8
set dft_insert_pass1(bscan,enabled)             "auto"
set dft_insert_pass1(mbist,controller_type)     "smart_serial"
set dft_insert_pass1(mbist,wrap_memories)       true
set dft_insert_pass1(mbist,bist_clock_domain)   "tessent_clk"
set dft_insert_pass1(tpi,coverage_target)       99.0
set dft_insert_pass1(drc,level)                 "strict"

# PASS2 — TDR / DFT signals / SRI
set dft_insert_pass2(tdr,data_width)            32
set dft_insert_pass2(dft_signals,test_mode_pin) "test_mode"
set dft_insert_pass2(dft_signals,scan_enable_pin) "scan_en"
set dft_insert_pass2(sri,resource_count)        "auto"

# PASS3 — EDT / SSN / OCC / control points
set dft_insert_pass3(edt,compression_ratio)     100
set dft_insert_pass3(edt,input_channels)        8
set dft_insert_pass3(edt,output_channels)       8
set dft_insert_pass3(edt,ssn_enable)            true
set dft_insert_pass3(occ,scan_enable_pin)       "scan_en"
set dft_insert_pass3(occ,test_clock_pin)        "test_clk"
set dft_insert_pass3(occ,at_speed)              true
set dft_insert_pass3(ctrl_points,mode)          "auto"
```

The full key lists (with defaults) are the overlays
`DFT/config/flow/v1.0.0/node_configs/DFT_INSERT_PASS<n>_<tool>_config.tcl`.

## Run

```bash
cd workarea/cpu_core
cbflow workspace create --config uc_DFT_INSERT_PASS1.tcl
cd P0_run_DFT_INSERT_PASS1_cpu_core_v1
cbflow run all
cbflow run status
```

## Outputs

Each pass releases its DFT-inserted netlist plus the tool collateral
(ICL / PDL / SDC / TCD, MBIST controller / BAP / BSCAN interface files,
pattern files for PASS1; EDT / OCC deliverables for PASS3) — the file lists
are `release_types,dft_pass<n>,files` in each pass's node config.
