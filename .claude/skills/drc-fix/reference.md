# DRC fix — reference

## ECO flow in DRC mode
`eco(tool,name) "openroad"`, `eco(oss,mode) "drc"` (PD/config/flow/v1.0.0/node_configs/ECO_openroad_config.tcl).

| Setting | Meaning |
|---|---|
| `eco(input,change_file)` | optional — DRC commands below |
| `eco(oss,route,scope)` | `none` no re-route (export-only fixes) · `nets` re-route only the nets named / touched · `full` every signal + clock net (needed for releases saved after OpenRCX, before 2026-11-25) |
| `eco(oss,export,min_area_layers)` | `{gds_layer gds_datatype min_area_um2 …}` — undersized routing polygons grown to the minimum at stream-out (GDS only) |
| `eco(oss,place,max_displacement)` | µm legalization bound for moved / padded cells |

### Change-file commands (`eco(oss,drc,allowed)`)
| Command | Effect |
|---|---|
| `eco_reroute_nets <net> …` | strip these nets' wiring; they are routed again (scope nets / full) |
| `eco_move_inst <inst> <dx_um> <dy_um>` | move a std cell, legalized; its nets are re-routed |
| `set_placement_padding -global|-masters {…}|-instances {…} -left N -right N` | site padding honoured by the legalization |
| `set_global_routing_layer_adjustment <layer> <0..1>` | reduce that layer's routing capacity (spreads routes out of a dense layer) |
| `repair_antennas_after_grt` | OpenROAD `repair_antennas` after the global route (diodes), then `check_antennas` (`eco_check_antennas.rpt`) |

Caps: `eco(oss,limit,reroute_nets)` 200, `eco(oss,limit,moves)` 20. Power / ground
wiring is never stripped. eco1 fails on router DRC > `eco(oss,route,max_drc)` (0).

## sky130 KLayout deck — rules seen and fixes
| Rule | Meaning | Usual cause in this flow | Fix |
|---|---|---|---|
| `m2.6` | met2 min area 0.0676 µm² | via pad | min_area_layers `69 20 0.0676` |
| `m3.6` | met3 min area 0.24 µm² | M2M3 / M3M4 via-pair pad | min_area_layers `70 20 0.24` |
| `m4.4a` / `m4.4` | met4 min area 0.24 µm² | via pad | min_area_layers `71 20 0.24` |
| `m1.2` `m2.2` `m3.2` `m4.2` `m5.2` | metal spacing | detailed-route leftover / dense area | reroute the hotspot nets; layer adjustment if many |
| `m1.1` `m2.1` … | metal width | patch / jog | reroute nets |
| `via.*` `via2.*` `via3.*` `via4.*` | via enclosure / spacing | via on a narrow wire | reroute nets |
| `m3.6` on a clock net | as m3.6 | NDR clock vias | min area at stream-out (NDR off is the PNR default) |
| `*.ant` / router `Antenna` | antenna ratio | long net on upper metal into a gate | `repair_antennas_after_grt`, reroute |
| `li.*` `licon.*` `poly.*` `difftap.*` `nwell.*` | FEOL | inside std cells / taps / placement | not ECO — check the cell or the placement (PNR) |
| any rule inside a macro / child block cell | — | the child's own layout | fix in the child's release (its own PV) |

Router markers (`route_drc.rpt`): `Short`, `Metal Spacing`, `Min Area`, `Cut Spacing`,
`EOL`, `NS Metal`: reroute the listed nets (`srcs: net:<name>`).
Do not trust `check_drc` run on a database after OpenRCX extraction (false markers);
the ECO's own `eco_route_drc.rpt` comes from the re-route, before extraction.

## GDS layers (sky130 drawing)
met1 68/20 · met2 69/20 · met3 70/20 · met4 71/20 · met5 72/20 · li1 67/20.

## uc templates
```tcl
# uc_ECO_<phase>_<exit>_DRC<n>.tcl
set project(name)              "opensky"
set flow(type)                 "ECO"
set flow(design_name)          "<block>"
set flow(run_name)             "<phase>_drc<n>"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "<phase>"
set project(release,phase)     "<phase>"
set project(lib_config_tag)    "<lib tag>"
set eco(tool,name)             "openroad"
set eco(input,release_tag)     "<the PV run's pv(input,release_tag)>"
set eco(oss,mode)              "drc"
set eco(oss,route,scope)       "none|nets|full"
set eco(oss,export,min_area_layers) {70 20 0.24}      ;# only for min-area rules
set eco(input,change_file)     "<abs path>/drc<n>_changes.tcl"   ;# when there are routing fixes
set project(release,tag)       "<EXIT>_ECO<n>"
```
PV on the repair: the PV run's user_config, new `flow(run_name)`,
`set pv(input,release_tag) "<EXIT>_ECO<n>"`, `flow(use_xterm) "false"`.
