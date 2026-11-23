# CBflow Library Manager User Guide

## Overview

The Library Manager automates discovery, organization, and validation of EDA libraries (NDM, DB, LEF, Liberty timing) across tracks, VT flavors, and PVT corners. It generates a `lib_config.tcl` that tech_config sources — eliminating manual library path entry.

## Quick Start

```bash
# Generate lib_config from your library directory
cbflow flow library-manager generate \
    --lib-root /libs/gf_22nm \
    --tech gf_22nm

# Verify coverage
cbflow flow library-manager coverage --tech gf_22nm
```

## Architecture

```
lib_root/                          tech_config.tcl
  Back_End/ndm/*.ndm       ──>      source lib_config.tcl
  Back_End/lef/*.lef       ──>        (fully resolved paths)
  Front_End/timing/
    stdcell/*.lib,*.db     ──>    lib_config.tcl (auto-generated)
    memory/*.lib           ──>      tech(9T,svt,ndm)
    io/*.lib               ──>      tech(9T,lib,ss_0p76v_150c,timing)
                                     tech(corners) {ss_0p76v_150c ...}
```

## Commands

### generate — Primary command

Scans library directories, discovers all libs by track/VT/corner, writes fully resolved `lib_config.tcl`.

```bash
cbflow flow library-manager generate \
    --lib-root /libs/gf_22nm \         # Library root directory
    --tech gf_22nm                      # Technology name (auto-reads tracks/VTs from tech_config)
```

**What it does:**
1. Reads `tech(tracks_available)` and `tech(vt_variants_available)` from tech_config
2. Scans NDM, LEF, DB, Liberty files — extracts track, VT, corner from filenames
3. Validates PVT by reading `.lib` file headers (nom_voltage, nom_temperature)
4. Writes `lib_config.tcl` with fully resolved absolute paths — no variables, no loops
5. Reports missing memory/IO corners and any PVT mismatches

**Options:**

| Option | Description | Example |
|--------|-------------|---------|
| `--lib-root` | Primary library root | `/libs/gf_22nm` |
| `--tech` | Technology name | `gf_22nm` |
| `--stdcell-path` | Additional stdcell lib roots (multiple) | `--stdcell-path /libs/eco /libs/channel` |
| `--memory-path` | Override memory lib dirs (multiple) | `--memory-path /libs/sram_v2` |
| `--io-path` | Override IO lib dirs (multiple) | `--io-path /libs/gpio_v3` |
| `--exclude` | Glob patterns to exclude (path or filename) | `--exclude "*ulvt*" "*/eco/*"` |
| `--tag` | Named output: `lib_config_<tag>.tcl` | `--tag P0` |
| `--tracks` | Override tracks (auto-detected) | `--tracks "9T 7.5T"` |
| `--vts` | Override VT list (auto-detected) | `--vts "svt lvt hvt"` |
| `--incremental` | Merge new libs into existing config | `--incremental` |

**Output example:**
```
============================================================
  Library Discovery Report — gf_22nm
============================================================
  Tracks:    9T 7.5T 8T
  VTs:       svt lvt ulvt hvt
  Corners:   12
  NDM:       12 stdcell + 1 memory + 1 io
  DB:        12 stdcell
  LEF:       12 stdcell + 1 memory + 1 io
  Timing:    144 stdcell sets

  Memory corners: 12/12 ok
  IO corners:     12/12 ok

  PVT Verification (filename vs .lib header):
    Verified: 144  Skipped: 0
    All verified libs match — PVT consistent

  Output: config/tech/gf_22nm/v1.0.0/lib_config.tcl
============================================================
```

### add — Add a category to a library tag

`add` scans one category and merges it into an existing **tag directory**,
`<lib_tag_root>/<tech>/<tag>/`. Other categories are preserved.

```bash
cbflow flow library-manager add --tech <tech> --tag <TAG> --category <cat> --path <dir> [<dir>...]
```

| Option | Description |
|--------|-------------|
| `--tag` | Existing tag to extend (required) |
| `--category` | `analog`, `ip`, `memory`, `io`, `stdcell` or `block` (required) |
| `--path` | Source directories (for `block`: the block's PNR release dir) |
| `--tech` / `--tech-config` | Technology name, or an explicit `tech_config.tcl` |
| `--tracks`, `--vts` | `stdcell` only. Auto-detected if omitted. |
| `--exclude` | Glob patterns to skip |
| `--allow-missing` | Proceed if source paths are missing (bootstrapping) |
| `--pv-pending` | `block` only. See below. |
| `--lib-tag-root` | Override the tag root. Precedence: flag > `CBFLOW_LIB_TAG_ROOT` > `project(lib_tag_root)` > `tech(lib_tag_root)`. |
| `--project` | Project whose `project(lib_tag_root)` locates the tag (default `$CBFLOW_PROJECT_NAME`) |
| `--version` | Config version (default `v1.0.0`) |

**Shared categories** (`memory`, `io`, `analog`, `ip`): every view is bundled.
Files are symlinked into `<tag>/<cat>/{lef,gds,cdl,verilog,...}`, and `lib_config.tcl` gets these keys:

```tcl
set tech(lef,memory)     [list .../sky130_sram_1kbyte_1rw1r_32x256_8.lef]
set tech(gds,memory)     [list .../sky130_sram_1kbyte_1rw1r_32x256_8.gds]
set tech(cdl,memory)     [list .../sky130_sram_1kbyte_1rw1r_32x256_8.spice]   ;# .cdl / .spice / .sp
set tech(verilog,memory) [list .../sky130_sram_1kbyte_1rw1r_32x256_8.v]
set tech(lib,<corner>,timing,memory) [list ...]
```

Empty categories are written as `[list ]`. When you add a non-stdcell category,
the existing `tech(corners)` list is kept and is not replaced by the added
library's corners.

**Blocks** (`--category block`): this adds a released hierarchical block (DL3 or DL2) as a hard macro for its parent.

```bash
cbflow flow library-manager add --tech skywater_130nm --tag OSS1 --category block \
    --project opensky --path <release,path>/P1/mac_array/PNR/PRO_EXIT
```

| View | From |
|---|---|
| `lef/<b>.lef`, `netlist/<b>.v`, `netlist/<b>.lvs.v` (opt), `def/<b>.def` (opt), `sdc/<b>.sdc` (opt), `lib/<b>__<lib_set>.lib` | PNR release (`--path`) |
| `gds/<b>.gds`, `netlist/<b>.cdl` | Sibling **PV** release `<phase>/<block>/PV/<exit>`, which must be `RELEASE_COMPLETE` with `STATUS=PASS` |
| `spef/<b>_<rc>.spef` | PNR release `spef/` (symlinked) |

`--pv-pending` takes the GDS / CDL from the PNR release while PV has not
released yet. The block is then recorded as pending. Re-run `add` without the flag once PV
releases. Without the flag there is no fallback, and a missing or failed PV release is an error.

`add` regenerates `<tag>/blocks_config.tcl` (sourced from `lib_config.tcl`) on every run:

```tcl
set tech(blocks)                    [list ai_subsys ctrl_subsys gcd mac_array]
set tech(block,mac_array,release)   ".../P1/mac_array/PNR/PRO_EXIT"
set tech(block,mac_array,pv_release) ".../P1/mac_array/PV/PRO_EXIT"   ;# or "PENDING"
set tech(block,mac_array,lef)       "$_lib_tag_dir/block/mac_array/lef/mac_array.lef"
set tech(block,mac_array,lib_sets)  {...}
set tech(block,mac_array,lib,<lib_set>) "..."
set tech(block,mac_array,spef_corners) [list rc_max rc_min rc_typ]
set tech(block,mac_array,spef,rc_max) "$_lib_tag_dir/block/mac_array/spef/mac_array_rc_max.spef"
```

Flat STA (`sta(oss,sta,mode) flat`) reads `tech(block,<b>,netlist)` and `tech(block,<b>,spef,<rc>)` for every descendant.

### Selecting a tag per run

```tcl
# setup/user_config.tcl
set project(lib_config_tag) "OSS2"
```

The run's user_config value wins over the project's value. The workarea scripts set it from `LIB_TAG`.

### coverage — Show library coverage matrix

```bash
cbflow flow library-manager coverage --tech gf_22nm
```

Shows a track x corner matrix indicating which VTs are available for each combination.

### check — Validate library paths exist on disk

```bash
cbflow flow library-manager check              # auto-reads tech(lib_root)
cbflow flow library-manager check --verbose     # show every file
```

### scan — Discover .lib files in a directory

```bash
cbflow flow library-manager scan --path /libs/gf_22nm --recursive
cbflow flow library-manager scan --format json
```

### list — List configured library sets

```bash
cbflow flow library-manager list --corner ss --voltage 0.80
```

## Generated lib_config.tcl

The output is **pure data** — no code, no variables, no loops. Every path is fully resolved.

```tcl
# AUTO-GENERATED by: cbflow flow library-manager generate
# Tech: gf_22nm | Generated: 2026-06-03

# ── NDM per track per VT ──
set tech(9T,svt,ndm) [list "/libs/gf_22nm/Back_End/ndm/tcbn22cllbwp9tsvt.ndm"]
set tech(9T,lvt,ndm) [list "/libs/gf_22nm/Back_End/ndm/tcbn22cllbwp9tlvt.ndm"]

# ── NDM combined per track ──
set tech(9T,ndm) [list "/libs/.../tcbn22cllbwp9tsvt.ndm" "/libs/.../memory.ndm" ...]

# ── Timing libs per track per VT per corner ──
set tech(9T,svt,lib,ss_0p76v_150c,timing) [list "/libs/.../tcbn22cllbwp9tsvtss0p76v150c_ccs.lib"]

# ── Timing combined per track per corner ──
set tech(9T,lib,ss_0p76v_150c,timing) [list ... all VTs + memory + io ...]

# ── Corners discovered ──
set tech(corners) {ff_0p84v_m40c ss_0p76v_150c ss_0p76v_25c tt_0p80v_25c ...}
```

## Tagged Configs (lib_config versioning)

Generate multiple lib configs for different scenarios:

```bash
# Full config with all VTs
cbflow flow library-manager generate --tech gf_22nm --tag full

# SVT+LVT only for timing closure
cbflow flow library-manager generate --tech gf_22nm --tag svt_lvt --exclude "*ulvt*" "*hvt*"

# Phase-specific
cbflow flow library-manager generate --tech gf_22nm --tag P0
```

Select in project_config:
```tcl
set project(lib_config_version) "P0"   ;# sources lib_config_P0.tcl
```

If not set, defaults to `lib_config.tcl`.

## Exclude Patterns

Exclude matches against **full absolute path** (not just filename):

```bash
--exclude "*ulvt*"              # filename: skip all ULVT libs
--exclude "*/eco/*"             # path: skip libs under eco/ directory
--exclude "*channel*"           # filename: skip channel cell libs
--exclude "*/old_release/*"     # path: skip old releases
```

## Multiple Library Roots

```bash
# Base + ECO + channel cells
cbflow flow library-manager generate --tech gf_22nm \
    --stdcell-path /libs/eco_cells /libs/channel_cells

# Multiple memory sources
cbflow flow library-manager generate --tech gf_22nm \
    --memory-path /libs/sram_v2/timing /libs/rom_v1/timing
```

Additional paths are scanned recursively — no specific directory structure required.

## Incremental Updates

Add new libraries without regenerating everything:

```bash
cbflow flow library-manager generate --tech gf_22nm --tag P0 --incremental
```

Existing entries not found in the current scan are retained.

## tech_config Integration

tech_config.tcl sources lib_config automatically:

```tcl
# In tech_config.tcl:
if {[info exists project(lib_config_version)] && $project(lib_config_version) ne ""} {
    set _lib_config "$_tech_dir/lib_config_$project(lib_config_version).tcl"
} else {
    set _lib_config "$_tech_dir/lib_config.tcl"
}
source $_lib_config
```

Variables available in tech_config:
```tcl
tech(lib_paths,stdcell)  ;# additional stdcell roots (list)
tech(lib_paths,memory)   ;# additional memory paths (list)
tech(lib_paths,io)       ;# additional IO paths (list)
```

## PVT Verification

The generate command performs a two-pass verification:
1. **Pass 1 (filename)** — Extracts corner/voltage/temperature from filename pattern
2. **Pass 2 (header)** — Reads `.lib` file header (`nom_voltage`, `nom_temperature`) and cross-checks

Mismatches are reported:
```
  PVT Verification (filename vs .lib header):
    Verified: 168  Skipped: 0
    MISMATCHES: 1
      tcbn22cllbwp9tsvtss0p76v25c_ccs.lib — temp: file=25C header=150C
```

## Filename Conventions

The scanner auto-detects from standard foundry naming:

| Component | Pattern in filename | Example |
|-----------|-------------------|---------|
| Track | `\d+p?\d*t` | `9t`, `7p5t`, `5t` |
| VT | `svt`, `lvt`, `ulvt`, `hvt` | `tcbn22cllbwp9t**svt**` |
| Corner | `(ss\|tt\|ff)(0p\d+v)(m?\d+c)` | `ss0p76v150c` |
| Format | `.ndm`, `.db`, `_ccs.lib`, `.lef` | `*_ccs.lib` |
