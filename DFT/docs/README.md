# CBflow DFT Discipline

The DFT (Design for Test) discipline is parallel to PD (Physical Design). It
shares the same RACE engine, dashboard, test suite, and `cbflow` CLI — only the
per-flow cmd handlers, tool configs, and documentation live separately under
`DFT/`.

```
CBflow_clone/
├── PD/            ← Physical Design (SYNTH, FP, PNR, STA, ...)
└── DFT/           ← Design for Test (this tree)
    ├── cmds/      ← per-flow cmd handlers (Tcl)
    └── docs/      ← this directory
```

## Supported DFT Flows

| Flow              | Purpose                                              | Tools                       |
|-------------------|------------------------------------------------------|-----------------------------|
| `DFT_INSERT_PASS1`| Core DFT: MBIST + BSCAN                              | Tessent, DFT Compiler       |
| `DFT_INSERT_PASS2`| Top DFT: TDR / DFT signals / SRI                     | Tessent, DFT Compiler       |
| `DFT_INSERT_PASS3`| EDT + OCC                                            | Tessent, DFT Compiler       |
| `SCAN_INSERT`     | Logical netlist → scan-stitched netlist + scandef    | Tessent, DFT Compiler       |
| `ATPG`            | Pattern generation + fault simulation + coverage     | Tessent, TestMAX            |
| `GLS_FUNC`        | Gate-level functional simulation (ZD or SDF)         | VCS, Questa                 |
| `GLS_SCAN_MBIST`  | Gate-level scan/MBIST/BSCAN pattern simulation       | VCS, Questa                 |

Mode knobs (not separate flows):
- `<flow>(mode)` — `zd` (zero-delay) or `sdf` (timing-aware)
- `gls_scan_mbist(verify_type)` — `scan`, `mbist`, or `bscan`

## Discipline Routing

The framework resolves cmd handlers by trying `$FLOW_DIR/cmds/<FLOW>/...` first
(PD), then `$CBFLOW_DFT_DIR/cmds/<FLOW>/...` (DFT). The DFT root is exported by
`PD/bin/cbflow` when the sibling `DFT/` directory exists.

Node configs (stages, dependencies, tool settings) for the DFT flows live in
`DFT/config/flow/v1.0.0/node_configs/` (`<FLOW>_config.tcl` + per-tool
`<FLOW>_<tool>_config.tcl`), dispatched by `DFT/config/flow/v1.0.0/flow_config.tcl`.

## Scan insertion in the open-source SYNTH flow

The open-source PD flow (vendor `opensource`, project `opensky`) inserts scan
chains inside **SYNTH** (Yosys + OpenROAD DFT). It does not use a separate DFT flow. The project keys are:

```tcl
set project(dft,enable)              true
set project(dft,max_chain_length)    100
set project(dft,clock_mixing)        no_mix          ;# no_mix | clock_mix
set project(dft,scan_enable_pattern) scan_enable_*
```

SYNTH writes `reports/dft_plan.rpt` and releases a scan-mode SDC
`<design>.scan.sdc`. With DFT on, clock gating uses the scan ICG
(`tech(<trk>,icg_scan_cell)`). See
`PD/docs/02-user-guide/opensource-flow-guide.md` §5.

## See also

- `DFT_Flow_Reference.md` — full mapping of the 11-activity DFT diagram to the DFT flows
- `DFT_Insert_Guide.md` — `DFT_INSERT_PASS1/2/3` user guide
- `Scan_Insert_Guide.md` — `SCAN_INSERT` user guide
- `ATPG_Guide.md` — `ATPG` user guide
- `GLS_Verification_Guide.md` — `GLS_FUNC` / `GLS_SCAN_MBIST` user guide
