# Timing ECO — reference

## ECO flow (open-source)
`eco(tool,name) "openroad"` → `PD/config/flow/v1.0.0/node_configs/ECO_openroad_config.tcl`,
command files `PD/cmds/ECO/opensource/openroad/v1.0.0/`.

| Node | What it does | Look at |
|---|---|---|
| odb1 / sdc1 | stage the release's `db/<design>.odb` + SDC (`eco(input,release_tag)`) | `work/ECO/odb1/odb/` |
| eco1 | parse + cap-check the change file (or guided `repair_timing`), apply, list changes, legalize (`eco(oss,place,max_displacement)` µm), strip signal wiring, global + detailed re-route, DRC gate | `reports/eco_changes.rpt`, `eco_check_placement.rpt`, `eco_route_drc.rpt`, `eco_qor.tcl` (global-route parasitics) |
| signoff1 | fillers, `global_connect`, deliverables (before OpenRCX), per-corner SPEF, timing / DRV / power, timing models | `reports/signoff_qor.tcl`, `signoff_drv.rpt` |
| export_data1 | GDS (KLayout, same recipe as PNR) | `outputs/final.gds` |
| release_data1 | `<release,path>/<phase>/<block>/ECO/<EXIT>_ECO<n>` — PNR-compatible names (`netlist/<d>.v .pt.v .lvs.v .cdl`, `def`, `db`, `sdc`, `spef/<d>_<rc>.spef`, `lib`) + `reports/eco_changes.rpt` | release dir |

The ECO re-routes the whole block (signal + clock wiring removed, power kept):
a database saved after OpenRCX has re-encoded wires the router rejects. Large
blocks take as long as their PNR route stage.

## Change-file commands (`eco(oss,changes,allowed)`)
One command per line, `#` comments. Anything else fails eco1 before a change is applied.

| Command | Use | Counts as |
|---|---|---|
| `replace_cell <inst> <lib_cell>` | upsize / downsize within a family (same pins), Vt swap | resize, or vt_swap when the Vt flavour (`tech(vt_pattern,*)`) differs |
| `eco_insert_buffer <buffer_cell> <net> [<inst>/<pin> ...]` | buffer a net (all loads, or the listed load pins move behind the buffer); hold delay cell before a capture pin | buffer |
| `remove_buffers <inst> ...` | remove buffers | removals (per instance) |

`insert_buffer` (OpenROAD's own) is **not** allowed: it crashes / corrupts the
parasitics state on a routed database in the current OpenROAD build.
`eco_insert_buffer` edits the database directly (OpenDB), checks every
connection, and eco1 fails if the ECO leaves any signal input unconnected.
Rules checked: instance exists, lib cell exists, different master, not dont_use
(`tech(<track>,dont_use_pnr)` + Vts outside `project(vt_flavors)`).

## Caps per ECO run (`eco(oss,limit,*)`, ECO Agent safety rails)
buffers 50 · resizes 50 · vt_swaps 20 · removals 20. Raise them in the run's uc
only when the user agrees.

## sky130 hd (opensky)
- Cells `sky130_fd_sc_hd__<func>_<drive>`; drives typically 1/2/4 (some 0, 6, 8, 12, 16).
  Flops `dfxtp`, `dfrtp`, scan `sdfxtp`, `sdfrbp` (_1/_2 only — no bigger drive:
  buffer the Q net instead).
- Buffers `buf_1 … buf_16`; clock cells `clkbuf_*` / `clkinv*` belong to CTS — never in a data-path ECO.
- Hold / delay cells: `tech(hd,delay_cells)` `dlygate4sd1_1 dlygate4sd2_1 dlygate4sd3_1`, `tech(hd,hold_buffers)`.
- One Vt (`tech(vt_variants_available) {svt}`) — no Vt swaps on opensky.
- post-route dont_use: `sky130_fd_sc_hd__lpflow_*`, `sky130_fd_sc_hd__probe*`.

## uc templates (copy project / phase / lib tag from the STA run's user_config)
```tcl
# uc_ECO_<phase>_<exit>_ECO<n>.tcl
set project(name)              "opensky"
set flow(type)                 "ECO"
set flow(design_name)          "<block>"
set flow(run_name)             "<phase>_eco<n>"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "<phase>"
set project(release,phase)     "<phase>"
set project(lib_config_tag)    "<lib tag>"
set eco(tool,name)             "openroad"
set eco(input,release_tag)     "<STA's release tag | last accepted EXIT_ECO<k>>"
set eco(oss,mode)              "changes"
set eco(input,change_file)     "<abs path>/eco<n>_changes.tcl"
set project(release,tag)       "<EXIT>_ECO<n>"
```
STA on the ECO: the STA run's user_config with a new `flow(run_name)`,
`set sta(input,release_tag) "<EXIT>_ECO<n>"`, `flow(use_xterm) "false"`.
LEC: the block's LEC uc (`uc_LEC_signoff_<phase>_<exit>.tcl`) with a new run name and
`set lec(input,netlist_revised_release_tag) "<EXIT>_ECO<n>"` (golden stays the SYNTH tag).

Guided repair instead of a change file: `set eco(oss,mode) "repair"` plus
`eco(oss,repair,setup|hold|setup_margin|hold_margin|max_buffer_percent|max_utilization|sequence|skip)`.
It is less predictable (OpenROAD chooses the moves) — use it only when the user asks or
the candidate list is far beyond the caps, and still gate it with STA + LEC.

## SmartGrid
`<EXIT>_ECO<n>` shows on the releases page as a variant of `<EXIT>`; it does not
replace the exit release. Promotion (`cbflow run release --from-run <eco run> --tag <EXIT> --override`)
and publishing are the user's call.
