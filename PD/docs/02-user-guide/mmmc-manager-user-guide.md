# CBflow MMMC Manager User Guide

## Overview

The MMMC (Multi-Mode Multi-Corner) Manager generates and manages analysis view configurations for timing signoff. It creates `mmmc_config.tcl` from a user-defined PVT matrix, validates each scenario against lib_config, and skips scenarios with missing libraries.

## Quick Start

```bash
# Generate MMMC config (interactive)
cbflow flow mmmc-manager generate

# Generate MMMC config (non-interactive)
cbflow flow mmmc-manager generate --tech gf_22nm \
    --corners "ss tt ff" \
    --voltages "0p76v 0p80v 0p84v" \
    --temperatures "150c 25c m40c"

# View what was generated
cbflow flow mmmc-manager show
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

                                                                     project_config.tcl
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
    --lib-tag P0
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
| `--lib-tag` | lib_config tag (e.g., P0) | Auto-detected |
| `--sdc-pattern` | SDC naming convention | `${design_name}_{mode}.sdc` |

**What it does:**

1. Builds Cartesian product: corners x voltages x temperatures
2. Resolves lib_config (auto-detects tagged versions)
3. Validates each `lib_set_ref` (e.g., `ss_0p76v_150c`) against lib_config
4. **Skips** scenarios with no matching libraries
5. Generates analysis views only for valid PVT combos
6. Creates backup with timestamp before overwriting
7. Writes `mmmc_node_scenarios.tcl` template for project_config
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

  Output: config/flow/v1.0.0/mmmc_config.tcl
```

### show — Display current MMMC config

```bash
cbflow flow mmmc-manager show
```

Shows process corners, operating modes, PVT points, RC pairing, analysis view count, scenario sets, and node assignments.

### validate — Check config consistency

```bash
cbflow flow mmmc-manager validate
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
cbflow flow mmmc-manager list-scenarios --set setup
cbflow flow mmmc-manager list-scenarios --set signoff
```

Available sets: `setup`, `hold`, `power`, `signoff`, `all`, `sta_setup`, `sta_hold`, `sta_signoff`

### generate-view-def — Cadence view_definition.tcl

```bash
cbflow flow mmmc-manager generate-view-def --output view_definition.tcl
```

Generates Cadence MMMC TCL with `create_library_set`, `create_rc_corner`, `create_constraint_mode`, `create_delay_corner`, `create_analysis_view`, and `set_analysis_view` commands.

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

# Override node scenarios
cbflow flow mmmc-manager set-node --node cts --setup "scen1 scen2" --hold "scen3"
```

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
set mmmc(rc_pair,ss) "rcmax"    ;# ss → worst parasitics
set mmmc(rc_pair,tt) "rctyp"    ;# tt → typical
set mmmc(rc_pair,ff) "rcmin"    ;# ff → best parasitics

# ── Auto-generate analysis views ──
# Views = modes x corners x PVT (Cartesian product)
# Format: <mode>_<corner>_<voltage>_<rc>_<temperature>
# Example: func_ss_0p76v_rcmax_150c

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

## Node Scenario Assignments (project_config.tcl)

Node assignments are **NOT** in mmmc_config — they're in project_config because they're project-level decisions:

```tcl
# In project_config.tcl:
array set mmmc {
    init_design {
        setup {func_tt_0p80v_rctyp_25c}      ;# 1 scenario (speed)
        hold  {func_tt_0p80v_rctyp_25c}
    }
    placement {
        setup {                                 ;# 2 scenarios (balance)
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
        }
    }
    signoff {
        setup {                                 ;# all ss scenarios (accuracy)
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
            test_ss_0p76v_rcmax_150c
        }
        hold { ... }
    }
}
```

**Strategy:** Early stages use fewer scenarios (faster iteration), late stages use more (comprehensive signoff).

The `generate` command writes a `mmmc_node_scenarios.tcl` template that you can copy into project_config.

## lib_config Tag Resolution

The MMMC manager auto-resolves which lib_config to validate against:

1. **`--lib-tag P0`** → reads `lib_config_P0.tcl`
2. **No tag, default exists** → reads `lib_config.tcl`
3. **No tag, only one tagged config** → auto-selects it
4. **No tag, multiple tagged configs** → lists them, asks user to specify

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

# 2. Generate MMMC config (validates against lib_config)
cbflow flow mmmc-manager generate --tech gf_22nm \
    --corners "ss tt ff" \
    --voltages "0p76v 0p80v 0p84v" \
    --temperatures "150c 25c m40c" \
    --lib-tag P0

# 3. Edit node assignments in project_config.tcl

# 4. Verify
cbflow flow mmmc-manager show
cbflow flow mmmc-manager validate

# 5. Generate Cadence view_definition.tcl (for Innovus/Tempus)
cbflow flow mmmc-manager generate-view-def --output view_definition.tcl

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
| rc_corner | rcmax, rctyp, rcmin | `rcmax` |
| temperature | 150c, 25c, m40c | `150c` |

**Full example:** `func_ss_0p76v_rcmax_150c`

**lib_set_ref** (derived): `ss_0p76v_150c` — maps to `tech(<track>,lib,ss_0p76v_150c,timing)` in lib_config
