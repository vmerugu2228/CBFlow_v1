# CBflow MMMC Manager User Guide

## Overview

The MMMC (Multi-Mode Multi-Corner) Manager generates and manages analysis view configurations for timing signoff. It creates `mmmc_config.tcl` from a user-defined PVT matrix, validates each scenario against a library tag's `lib_config.tcl`, and skips scenarios with missing libraries.

Project MMMC files live in `global/config/project/<proj>/v1.0.0/`:

| File | Holds |
|------|-------|
| `mmmc_config.tcl` | PVT building blocks, modes, RC corners, scenario sets (cascade step 7) |
| `mmmc_node_scenarios.tcl` | per-node setup / hold scenario assignments (`array set mmmc {cts {setup {...} hold {...}} ...}`) |
| `mmmc_view_definition.tcl` | generated MMMC library sets + views for the Cadence flows (`generate-view-def --style flow`) |

Every subcommand accepts `--project <p>` (resolves those files) and `--tech <t>` (tech config); `--config <path>`
points at an explicit `mmmc_config.tcl`. Outside a run shell pass `--tech` (inside one, `CBFLOW_TECH_NODE` is set).
The commands are PD-owned and auto-dispatched from `cbflow flow mmmc-manager …`.

## Quick Start

```bash
# Generate MMMC config (interactive)
cbflow flow mmmc-manager generate

# Generate MMMC config (non-interactive)
cbflow flow mmmc-manager generate --tech gf_22nm \
    --corners "ss tt ff" \
    --voltages "0p76v 0p80v 0p84v" \
    --temperatures "150c 25c m40c"

# View / check a project's config
cbflow flow mmmc-manager show     --project opensky --tech skywater_130nm
cbflow flow mmmc-manager validate --project opensky --tech skywater_130nm
```

## Architecture

```
User defines PVT matrix             Validate against lib_config      Write mmmc_config.tcl
─────────────────────────   ──>   ──────────────────────────   ──>  ─────────────────────
corners:  ss tt ff                   ss_0p76v_150c  ok               Only valid scenarios
voltages: 0p76v 0p80v 0p84v        ss_0p76v_25c   ok               are included
temps:    150c 25c m40c             ff_0p76v_150c  SKIP (no libs)
                                    tt_0p80v_25c   ok
= 27 combos                        ...                              mmmc_config.tcl
                                    12 valid, 15 skipped             (views, scenario sets)

                                                                     mmmc_node_scenarios.tcl
                                                                     (node assignments)
```

## Commands

### generate — Primary command

Interactive CLI that prompts for missing inputs:

```bash
$ cbflow flow mmmc-manager generate

  ============================================================
    CBflow MMMC Config Generator
  ============================================================

  Available technologies:
    1. gf_22nm
    2. tsmc_5nm
    3. tsmc_7nm
  Select technology [1-3]: 1
  Selected: gf_22nm
  Process corners [ss tt ff]: ss tt ff
  Voltages (e.g., 0p76v 0p80v 0p84v): 0p76v 0p80v 0p84v
  Temperatures (e.g., 150c 25c m40c): 150c 25c m40c
```

**Non-interactive (all args on CLI):**

```bash
cbflow flow mmmc-manager generate --tech gf_22nm \
    --corners "ss tt ff" \
    --voltages "0p76v 0p80v 0p84v" \
    --temperatures "150c 25c m40c" \
    --modes "func test" \
    --vts "svt lvt hvt" \
    --track 9T \
    --lib-tag P0 \
    --project bumblebee
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--tech` | Technology name | Prompted interactively |
| `--corners` | Process corners | `ss tt ff` |
| `--voltages` | Voltage points | Prompted (required) |
| `--temperatures` | Temperature points | Prompted (required) |
| `--modes` | Operating modes | From existing config or `func test` |
| `--vts` | VT filter for lib validation | All VTs |
| `--track` | Track to validate against | Auto-detected |
| `--lib-tag` | Library tag (reads `<lib_tag_root>/<tech>/<TAG>/lib_config.tcl`) | Auto-detected |
| `--lib-config` | Explicit `lib_config.tcl` (bypasses tag resolution) | — |
| `--tech-config` | Explicit `tech_config.tcl` | — |
| `--project` | Also mirror the output to `global/config/project/<p>/v1.0.0/mmmc_config.tcl` | — |
| `--sdc-pattern` | SDC naming convention | `${design_name}_{mode}.sdc` |
| `--allow-missing` | Keep PVT combos with no matching `lib_set_ref` (bootstrapping) | fail-fast |

**What it does:**

1. Builds Cartesian product: corners x voltages x temperatures
2. Resolves the library tag's `lib_config.tcl` (see "Library tag resolution")
3. Validates each `lib_set_ref` (e.g., `ss_0p76v_150c`) against lib_config
4. **Skips** scenarios with no matching libraries
5. Generates analysis views only for valid PVT combos
6. Creates backup with timestamp before overwriting
7. Writes a `mmmc_node_scenarios.tcl` template
8. Reports everything clearly

**Output example:**

```
  MMMC Generation Report — gf_22nm
  ============================================================
  Validated against: lib_config.tcl

  Requested PVT matrix:
    Corners:      ss tt ff
    Voltages:     0p76v 0p80v 0p84v
    Temperatures: 150c 25c m40c
    Total combos: 27

  Library Set Validation (track=9T):
     ss_0p76v_150c                  ok
     ss_0p76v_25c                   ok
   ! ff_0p76v_150c                  SKIPPED (no libs)
   ! ff_0p76v_25c                   SKIPPED (no libs)
     tt_0p80v_25c                   ok
     ...

  Valid:   12 / 27  |  Skipped: 15

  Generated:
    Process corners: ff ss tt
      ff: 4 PVT points
      ss: 5 PVT points
      tt: 3 PVT points
    Modes: func test
    Analysis views: 24

  Output: <lib_tag_root>/gf_22nm/P0/mmmc_config.tcl
          (+ global/config/project/bumblebee/v1.0.0/mmmc_config.tcl with --project)
```

The primary output is written **next to the tag's `lib_config.tcl`**, so one tag directory ships both configs;
`--project` mirrors it into the project config directory the run cascade reads.

### show — Display current MMMC config

```bash
cbflow flow mmmc-manager show --project opensky --tech skywater_130nm
```

Real output (excerpt):

```
  Process Corners: ff ss tt
  Operating Modes:
    func — ${design_name}_func.sdc
  PVT Points:
    ff: {1p95v 100c} {1p95v m40c}
    ss: {1p60v 100c} {1p60v m40c}
    tt: {1p80v 100c} {1p80v 25c}
  RC Corners:
    rc_max:            temp=125   cap=1.10  res=1.15
    rc_min:            temp=-40   cap=0.90  res=0.85
    rc_typ:            temp=25    cap=1.00  res=1.00
  Analysis Views: 18 (1 modes x 6 PVT combos x 3 RC corners)
  Scenario Sets:
    setup:       2 views
    hold:        2 views
    signoff:     4 views
    ...
  Node Scenario Assignments:  (mmmc_node_scenarios.tcl)
    cts:            2 setup, 2 hold
    synthesis:      1 setup, 1 hold
    timing:         2 setup, 2 hold
    init_scan:      1 setup, 1 hold
    ...
```

### validate — Check config consistency

```bash
cbflow flow mmmc-manager validate --project opensky --tech skywater_130nm
```

Runs 6 validation checks:
1. PVT coverage — every corner has PVT points
2. RC pair mapping — every corner has an RC pair
3. RC pair references — every RC pair name exists in rc_corners
4. Operating mode completeness — every mode has a constraint file
5. TCL execution — mmmc_config.tcl executes without errors
6. Node scenario validity — every scenario in node assignments exists in analysis_views

### list-views — List all analysis views

```bash
cbflow flow mmmc-manager list-views
```

### list-scenarios — List scenarios in a set

```bash
cbflow flow mmmc-manager list-scenarios --project opensky --tech skywater_130nm --set signoff
#   1. func_ss_1p60v_rc_max_100c
#   2. func_ss_1p60v_rc_max_m40c
#   3. func_ff_1p95v_rc_min_m40c
#   4. func_ff_1p95v_rc_min_100c
```

Available sets: `setup`, `hold`, `power`, `signoff`, `all`, `sta_setup`, `sta_hold`, `sta_signoff`

### generate-view-def — Cadence view_definition.tcl

```bash
cbflow flow mmmc-manager generate-view-def --project bumblebee --tech gf_22nm --output view_definition.tcl
cbflow flow mmmc-manager generate-view-def --project bumblebee --tech gf_22nm --style flow \
    --output global/config/project/bumblebee/v1.0.0/mmmc_view_definition.tcl
```

`--style standalone` (default) writes a self-contained file with every view and library paths via `::lib_dir`;
`--style flow` writes the `mmmc_view_definition.tcl` the Cadence flows read (views from the setup + hold + signoff
scenario sets, libraries / QRC via `$::tech(...)`). Either way it emits Cadence MMMC TCL with `create_library_set`, `create_rc_corner`, `create_constraint_mode`, `create_delay_corner`, `create_analysis_view`, and `set_analysis_view` commands.

### Manual edit commands

After generation, fine-tune with:

```bash
# Add operating mode
cbflow flow mmmc-manager add-mode --name scan --sdc '${design_name}_scan.sdc'

# Remove operating mode
cbflow flow mmmc-manager remove-mode --name scan

# Add PVT point
cbflow flow mmmc-manager add-pvt --corner ss --voltage 0p72v --temperature 175c

# Remove PVT point
cbflow flow mmmc-manager remove-pvt --corner ss --voltage 0p80v --temperature 25c

# Add RC corner
cbflow flow mmmc-manager add-rc --name rc_max_cworst --temperature 125 \
    --cap_mult 1.15 --res_mult 1.25 --metal_mult 1.15 --via_mult 1.25

# Override node scenarios (writes mmmc_node_scenarios.tcl)
cbflow flow mmmc-manager set-node --project opensky --tech skywater_130nm --node cts \
    --setup "func_ss_1p60v_rc_max_100c func_ss_1p60v_rc_max_m40c" --hold "func_ff_1p95v_rc_min_m40c"
```

Every mutation re-runs the validation checks and refuses to write an inconsistent config.

## Generated mmmc_config.tcl Structure

```tcl
# AUTO-GENERATED by: cbflow flow mmmc-manager generate
# Tech: gf_22nm | Corners: 12 | Views: 24

# ── Voltage & Temperature ──
set mmmc(voltage,nom)     0.80
set mmmc(voltage,low)     0.76
set mmmc(voltage,high)    0.84
set mmmc(temperature,hot) 150
set mmmc(temperature,nom) 25
set mmmc(temperature,cold) -40

# ── Process Corners ──
set mmmc(process_corners) {ff ss tt}

# ── Operating Modes ──
array set operating_modes {
    func { constraint_file "${design_name}_func.sdc" }
    test { constraint_file "${design_name}_test.sdc" }
}

# ── PVT Points (only validated combos) ──
set mmmc(pvt,ss) {{0p76v 150c} {0p76v 25c} {0p76v m40c} ...}
set mmmc(pvt,tt) {{0p80v 25c} {0p80v 150c} {0p80v m40c}}
set mmmc(pvt,ff) {{0p84v m40c} {0p84v 25c} {0p84v 150c} {0p80v m40c}}

# ── RC Pairing ──
set mmmc(rc_pair,ss) "rc_max"   ;# ss → worst parasitics
set mmmc(rc_pair,tt) "rc_typ"   ;# tt → typical
set mmmc(rc_pair,ff) "rc_min"   ;# ff → best parasitics

# ── Auto-generate analysis views ──
# Views = modes x corners x PVT (Cartesian product)
# Format: <mode>_<corner>_<voltage>_<rc>_<temperature>
# Example: func_ss_0p76v_rc_max_150c

# ── Scenario Sets ──
# setup:   all ss views
# hold:    all ff views
# signoff: setup + hold + nominal tt
# power:   tt + ss with rctyp

# ── RC Corners ──
# rc_max: cap=1.10 res=1.15 (worst case)
# rc_typ: cap=1.00 res=1.00 (typical)
# rc_min: cap=0.90 res=0.85 (best case)
```

## Node Scenario Assignments (mmmc_node_scenarios.tcl)

Node assignments are **not** in mmmc_config — they are project-level decisions in
`global/config/project/<proj>/v1.0.0/mmmc_node_scenarios.tcl`, keyed by node type:

```tcl
array set mmmc {
    init_design {
        setup {func_tt_0p80v_rc_typ_25c}       ;# 1 scenario (speed)
        hold  {func_tt_0p80v_rc_typ_25c}
    }
    cts {
        setup {
            func_ss_0p80v_rc_max_125c
            func_ss_0p80v_rc_max_m40c
        }
        hold {
            func_ff_1p10v_rc_min_125c
            func_ff_1p10v_rc_min_m40c
        }
    }
    signoff { setup { ... } hold { ... } }
}
```

Per run, one node's scenarios can be narrowed in `setup/override_config.<node>.tcl`
(`set mmmc(timing1,setup_scenarios) "..."` / `hold_scenarios`), which the run GUI writes from
right-click -> MMMC Scenarios.

**Strategy:** Early stages use fewer scenarios (faster iteration), late stages use more (comprehensive signoff).

The `generate` command writes a `mmmc_node_scenarios.tcl` template; `set-node` edits the project file.

## Library Tag Resolution

The MMMC manager resolves which `lib_config.tcl` to validate against:

1. **`--lib-config <path>`** → that file
2. **`--lib-tag P0`** → `<lib_tag_root>/<tech>/P0/lib_config.tcl` (`lib_tag_root`: `CBFLOW_LIB_TAG_ROOT` >
   `project(lib_tag_root)` > `tech(lib_tag_root)`)
3. **No tag, one tag available** → auto-selects it
4. **No tag, several tags** → lists them and asks (or errors: "Please specify --lib-tag")

## Backup and Overwrite Protection

When overwriting an existing mmmc_config.tcl:

```
  WARNING: mmmc_config.tcl already exists
  Overwrite? (y/n) [y]: y
  Backup: mmmc_config.tcl.bak_20260603_094512
```

Backups are timestamped — easy to revert.

## Complete Workflow

```bash
# 1. Generate library config
cbflow flow library-manager generate --lib-root /libs/gf_22nm --tech gf_22nm --tag P0

# 2. Generate MMMC config (validates against the tag, mirrors into the project)
cbflow flow mmmc-manager generate --tech gf_22nm \
    --corners "ss tt ff" \
    --voltages "0p76v 0p80v 0p84v" \
    --temperatures "150c 25c m40c" \
    --lib-tag P0 --project bumblebee

# 3. Adjust node assignments (mmmc_node_scenarios.tcl)
cbflow flow mmmc-manager set-node --project bumblebee --tech gf_22nm --node cts \
    --setup "func_ss_0p76v_rc_max_150c" --hold "func_ff_0p84v_rc_min_m40c"

# 4. Verify
cbflow flow mmmc-manager show     --project bumblebee --tech gf_22nm
cbflow flow mmmc-manager validate --project bumblebee --tech gf_22nm

# 5. Generate the Cadence view definition the flows read (Innovus/Tempus)
cbflow flow mmmc-manager generate-view-def --project bumblebee --tech gf_22nm --style flow \
    --output global/config/project/bumblebee/v1.0.0/mmmc_view_definition.tcl

# 6. Run flows
cbflow workspace create --config uc_SYNTH_PNR.tcl
cbflow run all
```

## Analysis View Naming Convention

```
<mode>_<corner>_<voltage>_<rc_corner>_<temperature>
```

| Component | Values | Example |
|-----------|--------|---------|
| mode | func, test, scan | `func` |
| corner | ss, tt, ff | `ss` |
| voltage | 0p76v, 0p80v, 0p84v | `0p76v` |
| rc_corner | rc_max, rc_typ, rc_min | `rc_max` |
| temperature | 150c, 25c, m40c | `150c` |

**Full example:** `func_ss_0p76v_rc_max_150c` (opensky: `func_ss_1p60v_rc_max_100c`)

**lib_set_ref** (derived): `ss_0p76v_150c` — maps to `tech(<track>,lib,ss_0p76v_150c,timing)` in lib_config
