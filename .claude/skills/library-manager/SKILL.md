---
name: library-manager
description: Build, update and check CBflow library tags (the versioned library sets the flows read via project(lib_config_tag)) on the open-source flow (sky130 opensky) — create a new tag, add the standard cells / memory macros / hard blocks from their latest releases, check every category's required views (lib per MMMC corner, lef, gds, cdl, verilog, netlist, def, sdc, spef), check a design's instantiated cells against a tag, check hard blocks' ports against their parents, and switch runs to the tag. Use when the user asks to create or refresh a library tag, add blocks / memories / IPs to a tag, find the latest block releases, check a tag or a netlist / RTL against a tag, or asks why a tag fails a check.
---

# Library tags (CBflow library-manager)

You build and check library tags with **`bin/cbflow flow library-manager`
commands**; the scripts in `scripts/` only read. Read
[reference.md](reference.md) (layout, keys, generate recipe, pitfalls) first.

`$SK` = `.claude/skills/library-manager`, `$CB` = repo root,
`<root>` = `project(lib_tag_root)` (PD overlay), tag dir `<root>/<tech>/<TAG>/`.

**Never modify a tag that runs use** (`project(lib_config_tag)` / user configs /
`grep -l "lib_config_tag" workarea/*/uc_*.tcl`): build a new tag and let the
user switch. Deleting or re-adding into an existing tag needs the user's yes.

## 1. Find the latest releases
```bash
python3 $SK/scripts/latest_releases.py --project <proj>
```
Per block of `project(design_hierarchy)` (the top is not a library block): the
newest phase, then the latest exit, an `<EXIT>_ECO<n>` above its exit; whether a
PV release sits beside it (gds / cdl come from PV; none → `--pv-pending`); the
SPEF corners; the ready `add` commands. Show the table; if the user wants other
releases for some blocks, use those paths.

## 2. Base tag + project tag
Libraries come in two layers (reference.md → Layers):
- **base tag** `<root>/<tech>/<TAG>/`: cells (stdcell, memory, io, ip, analog),
  shared by every project on the tech; built with `generate`.
- **project tag** `<root>/<tech>/projects/<project>/<PTAG>/`: the project's blocks
  over a base; made with `project-tag create --base <B> [--from <previous PTAG>]`.

To refresh blocks, make a new project tag `--from` the previous one. Make a new
base tag only when cells change.

### 2a. Create a base tag (new name, e.g. next OSS<n>; cells only)
Standard cells + memories exactly like the reference tag (see the recipe in
reference.md — `--lib-root` is the **stdcell** library, memories via
`--memory-path`, `--exclude` the macros the tag must not carry):
```bash
bin/cbflow flow library-manager generate --tech <tech> --tag <TAG> --lib-tag-root <root> \
    --lib-root <pdk>/libs.ref/<stdcell_lib> --tracks <trk> --vts <vt> \
    --stdcell-path <pdk>/libs.ref/<stdcell_lib> --memory-path <pdk>/libs.ref/<sram_lib> --exclude '<glob>' …
```
Compare with the reference tag (`diff` of the sorted `lib_config.tcl` with the
tag names masked, and of `find stdcell memory io ip analog -type l`). Explain
every difference before going on (reference.md lists the known ones).

### 2b. Create the project tag
```bash
bin/cbflow flow library-manager project-tag create --tech <tech> --project <proj> --tag <PTAG> \
    --base <BASE> [--from <previous PTAG>]
```

## 3. Add hard blocks (project tag) and other macros (base tag)
Run the `add` commands from step 1 with `--tag <PTAG>`: one call with PV, one
with `--pv-pending`. `add` refuses blocks in a base tag, and refuses any FROZEN
tag. Memories / IP go into the base tag:
`add --category memory|ip|io|analog --path …`.

## 4. Check
```bash
bin/cbflow flow library-manager check --tech <tech> --lib_tag <TAG>          # required-view table
python3 $SK/scripts/port_compat.py --project <proj> --lib-config <root>/<tech>/<TAG>/lib_config.tcl
```
- View table: every MISSING / `n/m` is either a real gap (missing release view)
  or a stale tag; say which (look at the source release dir). `*` (substituted
  memory corner via `tech(memory,lib_set_map)`) and `†` (PDK view from the tech
  config) are expected — note them, not errors.
- Port compatibility: **ERROR** = a block's interface differs from what a parent
  in the tag instantiates (e.g. a newer block release with new ports under an
  older parent) — the parent must be rebuilt against it, or the tag must carry
  the block release the parent was built with; ask the user which. **WARN** =
  unconnected scan inputs (hierarchical scan not stitched) — report.
- For a design that will use the tag:
  `check --tech <tech> --lib_tag <TAG> --project <proj> --design <b> --netlist_tag <T> [--rtl_tag <T>] [--phase <P>]`
  (every instantiated cell / macro / block found in the tag's views).

## 5. Hand over
Report:
- tag path and layers (base + project);
- contents (stdcell, memories, blocks and their source releases);
- check result, port-compatibility result;
- differences from the previous tag.

When runs start using the tag, offer `project-tag freeze`; the user decides.
Switching runs to it is the user's call: `set project(lib_config_tag) "<TAG>"`
in their user configs (or the PD overlay for the project default) — show the
lines, do not edit configs.
