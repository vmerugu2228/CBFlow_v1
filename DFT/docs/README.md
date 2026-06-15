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
| `DFT_INSERT`      | RTL → DFT-inserted RTL (MBIST + OCC + EDT/SSN)       | Tessent, DFT Compiler       |
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

Node configs (stages, dependencies, tool settings) live in `PD/config/` for all
flows including DFT. This keeps single-source resolution paths from
`config_loader.tcl`, the dashboard, and the test suite.

## See also

- `DFT_Flow_Reference.md` — full mapping of the 11-activity DFT diagram to the 5 flows
- `DFT_Insert_Guide.md` — `DFT_INSERT` user guide
- `Scan_Insert_Guide.md` — `SCAN_INSERT` user guide
- `ATPG_Guide.md` — `ATPG` user guide
- `GLS_Verification_Guide.md` — `GLS_FUNC` / `GLS_SCAN_MBIST` user guide
