# Library-manager reference (open-source flow, opensky / sky130)

## Tag layout
```
<lib_tag_root>/<tech>/<TAG>/          project(lib_tag_root) (PD overlay; must be outside CBFLOW_ROOT)
  lib_config.tcl                      tech(...) keys — sourced by the flows (project(lib_config_tag))
  blocks_config.tcl                   tech(blocks), tech(block,<b>,<view>) — sourced by lib_config.tcl
  MANIFEST.tcl  README.md  logs/
  stdcell/{lef,lib}/<trk>/            symlinks into the PDK
  memory|io|ip|analog/{lef,lib,gds,cdl,verilog,db,ndm}/
  block/<b>/{lef,lib,gds,netlist,def,sdc,spef}/  SOURCE (release dir)  PV_SOURCE (PV release | PENDING)
```

## Layers
| Kind | Path | Holds |
|---|---|---|
| base | `<root>/<tech>/<TAG>/` | stdcell / memory / io / ip / analog (shared by projects) |
| project | `<root>/<tech>/projects/<proj>/<TAG>/` | blocks; `lib_config.tcl` = `tech(lib_base_tag)`, `tech(lib_project_tag)`, source `../../../<BASE>/lib_config.tcl`, `_lib_tag_dir` = itself, source `blocks_config.tcl`; `BASE` file |
| combined (legacy) | `<root>/<tech>/<TAG>/` with `blocks_config.tcl` | OSS0-OSS3: cells + blocks |

Markers:
- `FROZEN` (`project-tag freeze`): `add` refuses the tag.

Checks:
- `check` fails a project tag that redefines a base key.
- `project-tag create` refuses a combined base, and a name that is already a base tag.

Runtime (`generate_setup.tcl`) and the Python resolvers look in
`projects/<project(name)>/<TAG>` after the base layouts.

## Keys the flows read
| Key | Meaning |
|---|---|
| `tech(<trk>,lef)` / `tech(<trk>,<vt>,lef)` | cell LEFs (current generator: combined — stdcell + shared macros) |
| `tech(<trk>,lib,<corner>,timing)` | timing libs per corner (stdcell) |
| `tech(<view>,<cat>)` | lef / gds / cdl / verilog of memory / io / ip / analog macros |
| `tech(lib,<corner>,timing,<cat>)` | macro timing libs per corner |
| `tech(memory,lib_set_map)` (tech config) | corner substitution for memories characterized at one corner |
| `tech(<trk>,{gds,cdl,verilog}_stdcell)` (tech config) | stdcell PDK views (not in the tag) |
| `tech(blocks)`, `tech(block,<b>,lef|gds|netlist|lvs_netlist|cdl|def|sdc)`, `tech(block,<b>,lib,<corner>)`, `tech(block,<b>,spef,<rc>)`, `tech(block,<b>,spef_corners)` | hard blocks |
| `tech(required_views,<cat>)` (tech config) | what `check --lib_tag` requires per category |

## Generate recipe (sky130, matches OSS2 / OSS3)
```bash
P=$HOME/eda/pdks/sky130A/libs.ref
bin/cbflow flow library-manager generate --tech skywater_130nm --tag <TAG> --lib-tag-root $HOME/eda/lib_tags \
    --lib-root $P/sky130_fd_sc_hd --tracks hd --vts svt \
    --stdcell-path $P/sky130_fd_sc_hd --memory-path $P/sky130_sram_macros \
    --exclude "*8x1024*" "*32x512*" "sram_1rw1r_32_256_8_sky130*"
```
Known differences from OSS2 (generated 2026-11-22 by an older generator, stdcell
added later with `add --category stdcell`):
- `tech(hd,lef)` also lists the SRAM LEF and `tech(hd,lib,tt_1p8v_25c,timing)` the
  SRAM lib (the combined per-track lists include shared macros); the flows read
  each cell LEF once (`oss_cell_lefs` in `oss_utils.tcl`), and no MMMC lib set
  uses `tt_1p8v_25c`.
- `tech(corners)` includes the memory corner `tt_1p8v_25c`.

## Pitfalls
- `--lib-root` at `libs.ref` (the whole PDK) pulls the IO LEFs (`sky130_ef_io`,
  `sky130_fd_io`) into the tag and into `tech(hd,lef)`. Point it at the stdcell library.
- `generate` without a stdcell match errors ("No tracks matched") — the stdcell
  library must be part of the generate.
- `add` extends an existing tag only; a new tag starts with `generate`.
- A block release without a PV sibling: `add --pv-pending` (gds / cdl from PNR);
  re-add without the flag once PV releases.
- SPEF: a block carries the corners its release extracted; `check` requires the
  RC corners the project's MMMC views use (`-rc_corner` in
  `mmmc_view_definition.tcl`, temperature dropped: rc_max, rc_min).
- Memory timing at one corner only (sky130 SRAM: TT 1.8 V 25 °C): `4/4*` via
  `tech(memory,lib_set_map)` — expected, a library limitation.
- A newer block release can change its interface (gcd P3 = APB + irq) while a
  parent in the same tag was built with the old one: `port_compat.py` ERROR.

## Commands
| Command | Use |
|---|---|
| `library-manager generate --tag <TAG> …` | new base tag (cells) |
| `library-manager project-tag create --project <p> --tag <PT> --base <B> [--from <PT0>]` | new project tag |
| `library-manager project-tag freeze|list|show --project <p> [--tag <PT>]` | freeze / list / show project tags |
| `library-manager add --tag <TAG> --category block [--pv-pending] --path <rel>…` | hard blocks |
| `library-manager add --tag <TAG> --category memory|io|ip|analog|stdcell --path …` | other categories |
| `library-manager check --tech <t> --lib_tag <TAG>` | files + required-view table |
| `library-manager check … --project <p> --design <b> --netlist_tag <T> / --rtl_tag <T> [--phase <P>]` | cells a design instantiates vs the tag |
| `library-manager status --tech <t> --lib_tag <TAG>` | LEF-tech / RCX / timing coverage |
| `scripts/latest_releases.py --project <p>` | latest block releases + add commands |
| `scripts/port_compat.py --project <p> --lib-config <tag>/lib_config.tcl` | block ports vs parents |
