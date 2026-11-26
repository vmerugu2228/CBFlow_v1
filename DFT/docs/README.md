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
| `SCAN_INSERT`     | Logical netlist → scan-stitched netlist + scandef (oss: scan sign-off of the SYNTH scan netlist) | Tessent, DFT Compiler, fault (oss) |
| `ATPG`            | Pattern generation + fault simulation + coverage     | Tessent, TestMAX, fault (oss) |
| `GLS_FUNC`        | Gate-level functional simulation (ZD or SDF)         | VCS, Questa, iverilog (oss) |
| `GLS_SCAN_MBIST`  | Gate-level scan/MBIST/BSCAN pattern simulation       | VCS, Questa, iverilog (oss) |

Mode knobs (not separate flows; Synopsys / Mentor handlers):
- `atpg(mode)`, `gls_func(mode)`, `gls_scan_mbist(mode)` — `zd` (zero-delay) or `sdf` (timing-aware)
- `gls_scan_mbist(verify_type)` — `scan`, `mbist`, or `bscan`
- `atpg(pd_phase)` — `pre` | `post` (post-PD adds timing_sim1 and the ATPG_POSTPD_EXIT sign-off)

The open-source tools are selected with `<arr>(tool,name)` (`fault`, `iverilog`);
`gls_scan_mbist(oss,verify)` must be `scan` there.

## Discipline Routing

The RACE engine resolves cmd handlers under the flow's own discipline first
(`$CBFLOW_DFT_DIR/cmds/<FLOW>/<vendor>/<tool>/<ver>/`), then the other discipline
trees. `CONFIG_ROOT` of a DFT run is `DFT/config` (tool_launch_config.tcl,
lsf_config.tcl → the PD file); the release config / handshake map and the PD project
overlay come from the PD tree (`$CBFLOW_CORE_DIR`).

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
`sdc/<design>.scan.sdc` and — mandatory with `project(dft,enable)` — the scan
chains as `def/<design>.scandef` (PNR requires and reads it, handshake
`PNR,def_scan`; SCAN_INSERT checks it against its netlist trace). With DFT on,
clock gating uses the scan ICG (`tech(<trk>,icg_scan_cell)`). See
[`PD/docs/02-user-guide/opensource-flow-guide.md` §5](../../PD/docs/02-user-guide/opensource-flow-guide.md#dft-scan-insertion).

## Open-source DFT flows

SCAN_INSERT / ATPG (`fault`) and GLS_FUNC / GLS_SCAN_MBIST (`iverilog`) run on the
open-source stack (Fault cut, nl2bench, Atalanta, Icarus) — scan sign-off of the SYNTH
scan netlist, stuck-at ATPG with independent fault simulation and pattern simulation,
gate-level functional / scan-pattern simulation. See [`opensource-dft-guide.md`](opensource-dft-guide.md);
for gcd P3 they run inside the spec-to-GDS chain
([`spec-to-gds-guide.md`](../../PD/docs/02-user-guide/spec-to-gds-guide.md)).

## See also

- `opensource-dft-guide.md` — open-source SCAN_INSERT / ATPG / GLS (opensky)

- `DFT_Flow_Reference.md` — mapping of the 11-activity DFT diagram to the 7 DFT flows
- `DFT_Insert_Guide.md` — `DFT_INSERT_PASS1/2/3` user guide
- `Scan_Insert_Guide.md` — `SCAN_INSERT` user guide
- `ATPG_Guide.md` — `ATPG` user guide
- `GLS_Verification_Guide.md` — `GLS_FUNC` / `GLS_SCAN_MBIST` user guide
