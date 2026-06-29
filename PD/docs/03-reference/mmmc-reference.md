# CBflow MMMC Reference Guide

Complete reference for Multi-Mode Multi-Corner (MMMC) configuration and management in CBflow v2.0.0.

## Overview

CBflow's MMMC system provides automated multi-corner timing analysis across the complete PD flow. It covers:

- **Process corners**: SS (slow), TT (typical), FF (fast)
- **Voltage variation**: Nominal +-5% (e.g., 0.76V / 0.80V / 0.84V)
- **Temperature range**: -40C / 25C / 150C
- **Operating modes**: Functional, Test (user-configurable)
- **RC corners**: rcmax, rctyp, rcmin

---

## PVT Corner Definitions

### Process Corners
| Corner | Description | Setup Critical | Hold Critical |
|--------|-------------|:-:|:-:|
| **SS** | Slow NMOS, Slow PMOS | Yes | No |
| **TT** | Typical NMOS, Typical PMOS | No | No |
| **FF** | Fast NMOS, Fast PMOS | No | Yes |

### Voltage Corners (+-5% tolerance)
| Corner | Value | Usage |
|--------|------:|-------|
| Low (-5%) | 0.76V | Worst setup timing |
| Nominal | 0.80V | Typical operation |
| High (+5%) | 0.84V | Worst hold timing |

### Temperature Corners
| Corner | Value | Usage |
|--------|------:|-------|
| Cold | -40C | Hold critical (with FF) |
| Nominal | 25C | Typical operation |
| Hot | 150C | Setup critical (with SS), leakage |

### RC Corners
| Corner | Description | Multipliers | Usage |
|--------|-------------|:-----------:|-------|
| **rc_max** | Maximum parasitics | 1.15x R, 1.15x C | Setup critical |
| **rc_typ** | Typical parasitics | 1.0x R, 1.0x C | Nominal |
| **rc_min** | Minimum parasitics | 0.85x R, 0.85x C | Hold critical |

---

## Scenario Naming Convention

```
<mode>_<corner>_<voltage>_<rc_corner>_<temperature>
```

### Examples
| Scenario Name | Meaning |
|---------------|---------|
| `func_ss_0p76v_rcmax_150c` | Functional, slow, 0.76V, max RC, 150C -- **worst setup** |
| `func_ff_0p84v_rcmin_m40c` | Functional, fast, 0.84V, min RC, -40C -- **worst hold** |
| `func_tt_0p80v_rctyp_25c` | Functional, typical, 0.80V, typ RC, 25C -- **nominal** |
| `test_ss_0p76v_rcmax_150c` | Test mode, slow, 0.76V, max RC, 150C |

---

## Operating Modes

| Mode | Description | Voltage | Clock | Constraint File |
|------|-------------|--------:|------:|-----------------|
| **func** | Normal functional operation | 0.80V nom | 1000MHz | ravendrive_func.sdc |
| **test** | DFT scan test mode | 0.80V nom | 100MHz | ravendrive_test.sdc |

Modes are user-configurable via `cbflow flow mmmc-manager add-mode` or `mmmc_config.tcl`.

---

## Predefined Scenario Sets

| Set | Count | Purpose | Scenarios |
|-----|:-----:|---------|-----------|
| **setup** | 4 | Setup-critical analysis | SS + low voltage + hot + rcmax |
| **hold** | 4 | Hold-critical analysis | FF + high voltage + cold + rcmin |
| **power** | 3 | Power analysis (leakage + dynamic) | Mix of corners |
| **signoff** | 10 | Complete sign-off | Setup + hold + nominal |
| **sta_setup** | 4 | STA setup-only | SS corners for STA |
| **sta_hold** | 4 | STA hold-only | FF corners for STA |
| **sta_signoff** | 10 | STA comprehensive | Full STA coverage |
| **all** | 17 | All available | Every defined view |

### Signoff Scenarios (10)
```
func_ss_0p76v_rcmax_150c      # Worst setup
func_ss_0p76v_rcmax_m40c      # Setup cold
func_ss_0p80v_rcmax_150c      # Setup nom-V
func_tt_0p80v_rctyp_25c       # Nominal
func_ff_0p84v_rcmin_m40c      # Worst hold
func_ff_0p84v_rcmin_25c       # Hold nominal temp
func_ff_0p80v_rcmin_m40c      # Hold nom-V
test_ss_0p76v_rcmax_150c      # Test worst setup
test_tt_0p80v_rctyp_25c       # Test nominal
test_ff_0p84v_rcmin_m40c      # Test worst hold
```

---

## Per-Node Scenario Assignments

Scenarios increase progressively as the flow matures:

| Node | Setup | Hold | Total | Rationale |
|------|:-----:|:----:|:-----:|-----------|
| init_design | 1 | 1 | 2 | Quick sanity check |
| floorplan | 1 | 1 | 2 | Coarse estimation |
| placement | 2 | 2 | 4 | Placement optimization |
| cts | 3 | 3 | 6 | Clock tree balancing |
| route | 3 | 3 | 6 | Routing optimization |
| post_route | 4 | 4 | 8 | Post-route closure |
| signoff | 6 | 6 | 12 | Full sign-off coverage |
| synthesis | 4 | 3 | 7 | Multi-corner compile |

---

## MMMC in Each Flow

### SYNTH (Multi-Corner Compile)
```
inputs1 -> mmmc_setup1 -> synthesis1 -> export_data1 -> release_data1
```
- `mmmc_setup1` resolves synthesis scenarios (7 corners)
- `synthesis1` loads all corner libraries via `set_app_var target_library`
- FC `compile_fusion` optimizes across all loaded corners
- Per-corner timing reports generated

### PNR (Per-Stage Scenarios)
```
inputs -> place -> cts -> route -> pro -> signoff -> export -> release
```
- Each stage calls `create_mmmc_scenarios_for_node "<stage>"`
- Creates Innovus/FC analysis views per scenario
- Progressive scenario count: 4 at placement -> 12 at signoff
- Config-driven via `pnr(mmmc,enabled_stages)`

### STA (Dynamic Per-Scenario Subnodes)
```
inputs1 -> extraction1 -> timing1 (per-scenario subnodes) -> reporting1 -> release_data1
```
- RACE generates dynamic subnodes within timing1 from user-specified MMMC scenarios
- Each MMMC scenario appears as an individual subnode (e.g., `timing1_func_ss_0p76v_rcmax_150c`)
- Each scenario runs both setup + hold analysis independently
- RACE executes scenario subnodes in parallel when resources allow
- 10 scenarios (signoff set) = 10 parallel timing jobs
- Per-scenario status is tracked individually in the RACE SQLite DB
- `cbflow run status --details` shows completion status for each scenario subnode

### STA Dynamic Subnode Execution
```
RACE generates subnodes at runtime from user_config scenarios:
  timing1_func_ss_0p76v_rcmax_150c    (independent subnode)
  timing1_func_ff_0p84v_rcmin_m40c    (independent subnode)
  timing1_func_tt_0p80v_rctyp_25c     (independent subnode)
  ... (10 total for signoff set)

Each subnode invokes: timing_scenario_handler.tcl <scenario_name>
Status tracked in RACE DB -- no stamp files.
```

### Individual Scenario Control

Because each MMMC scenario is an independent subnode, you can control them individually:

```bash
# Check status of all scenario subnodes
cbflow run status --details

# Force re-run a single scenario
cbflow run force --node timing1_func_ss_0p76v_rcmax_150c

# Bypass a specific scenario
cbflow run bypass --node timing1_func_ff_0p84v_rcmin_m40c

# Force validate a scenario without re-running
cbflow run forcevalidate --node timing1_func_tt_0p80v_rctyp_25c
```

These commands can be issued while the engine is running (active engine sync).

---

## User Controls

### Select Scenario Set
```tcl
# In user_config.tcl or project config:
set sta(mmmc,scenario_set) "signoff"    # 10 scenarios
set sta(mmmc,scenario_set) "setup"      # 4 setup-only (quick)
set sta(mmmc,scenario_set) "all"        # 17 comprehensive

set pnr(mmmc,scenario_set) "signoff"
set synth(mmmc,scenario_set) "setup"
```

### Override Per-Stage
```tcl
# Use a different set for a specific stage
set pnr(mmmc,override,placement,setup) {func_ss_0p76v_rcmax_150c}
set pnr(mmmc,override,signoff,hold) {func_ff_0p84v_rcmin_m40c func_ff_0p80v_rcmin_m40c}
```

---

## MMMC Manager CLI

### Create New Config (Interactive)
```bash
cbflow flow mmmc-manager create --interactive --output mmmc_config.tcl
```
Walks through:
1. Process corners (ss,tt,ff)
2. Nominal voltage + tolerance % -> derives low/nom/high
3. Temperatures (-40,25,150)
4. Operating modes (name, description, clock, SDC file)
5. RC corners
6. Reviews generated scenarios
7. Auto-generates scenario sets and node mappings

### Create Non-Interactive
```bash
cbflow flow mmmc-manager create \
  --corners ss,tt,ff \
  --voltages 0.80,5 \
  --temps -40,25,150 \
  --modes "func:Functional:1000MHz:func.sdc,test:DFT Test:100MHz:test.sdc" \
  --output mmmc_config.tcl
```

### Show Current Config
```bash
cbflow flow mmmc-manager show
cbflow flow mmmc-manager show --config path/to/mmmc_config.tcl
```

### Validate Config
```bash
cbflow flow mmmc-manager validate
```
Checks:
- All scenarios in sets exist in analysis_views
- All scenarios in node mappings exist in analysis_views
- lib_set_ref values are consistent
- Detects orphan scenarios

### Generate Cadence View Definition
```bash
cbflow flow mmmc-manager generate-view-def --output view_definition.tcl
```
Generates Cadence Innovus/Tempus native format:
```tcl
create_library_set -name ss_076v_150c -timing [list ...] -si [list ...]
create_rc_corner -name rc_max -T 150 -preRoute_res 1.15 ...
create_constraint_mode -name func_mode -sdc_files [list func.sdc]
create_delay_corner -name func_ss_0p76v_rcmax_150c_dc ...
create_analysis_view -name func_ss_0p76v_rcmax_150c ...
set_analysis_view -setup [list ...] -hold [list ...]
```

### Add/Remove Operating Modes
```bash
cbflow flow mmmc-manager add-mode --name scan --desc "Scan mode" --freq 200MHz --sdc scan.sdc
cbflow flow mmmc-manager remove-mode --name scan
```

---

## Block awareness: how a project-level view definition serves many blocks

`mmmc_view_definition.tcl` is **deliberately project-level**, not per-block:
it lives at `config/project/<name>/v1.0.0/mmmc_view_definition.tcl` and is
referenced by every cmd handler that needs MMMC (init_design, synthesis,
timing, etc.) via the project-relative path.

This is correct because **library sets, RC corners, delay corners, and
analysis-view definitions are shared across all blocks in a project** —
they describe the foundry PVT setup, which is the same regardless of which
block is being implemented. Duplicating them per block would just produce
N identical files.

The **block-specific piece** is the SDC. The view definition handles this
without needing per-block files:

```tcl
# Inside mmmc_view_definition.tcl
create_constraint_mode -name func_cm \
    -sdc_files [list [subst $::operating_modes(func,constraint_file)]]
```

The `[subst ...]` happens at `source` time, inside the running cmd file.
`operating_modes(func,constraint_file)` is set in `mmmc_config.tcl` to
`"${design_name}_func.sdc"`. When the view definition is sourced during a
run, `${design_name}` resolves to the current run's `flow(design_name)` —
so block A's run loads `<blockA>_func.sdc`, block B's run loads
`<blockB>_func.sdc`. **Same view_definition.tcl, different SDC per block.**

This means the SDC files must follow the convention. For a flow
`flow(design_name) "cpu_core"`, the user_config must point at:

```tcl
set sta(input,sdc,func) "/path/to/cpu_core_func.sdc"
set sta(input,sdc,test) "/path/to/cpu_core_test.sdc"
```

### When a block needs its own MMMC setup (different corners)

If one block needs corners the project-level view definition doesn't cover,
override per-run by setting `<flow>(input,mmmc_file)` in user_config:

```tcl
# Use a custom view definition for THIS run only
set fp(input,mmmc_file) "/path/to/my_block_view_definition.tcl"
```

The `init_design_innovus.tcl` handler (line 150-156) checks for this
override before falling back to the project-level file. No code changes
needed; this hook already exists.

This is rare in practice — projects normally standardize PVT corners so
all blocks share the same view definition.

---

## Utility Procedures (TCL)

Available after sourcing `mmmc_config.tcl`:

| Procedure | Purpose |
|-----------|---------|
| `get_scenario_set "signoff"` | Get list of scenarios in a set |
| `get_analysis_view "func_ss_0p76v_rcmax_150c"` | Get view details (corner, voltage, temp, libs) |
| `get_node_scenarios "placement" "all"` | Get all scenarios for a PNR stage |
| `get_node_setup_scenarios "cts"` | Get setup-only scenarios for a stage |
| `get_node_hold_scenarios "route"` | Get hold-only scenarios for a stage |
| `create_mmmc_scenarios_for_node "signoff"` | Create FC/Innovus analysis views |
| `is_mmmc_enabled` | Check if MMMC is active |
| `list_scenario_sets` | Show all predefined sets with counts |
| `list_mmmc_nodes` | Show all node-scenario assignments |
| `list_all_scenarios` | Show all 17 analysis views |

---

## Analysis View Structure

Each analysis view contains:

```tcl
"func_ss_0p76v_rcmax_150c" {
    corner          "ss"
    mode            "func"
    voltage         0.76
    temperature     150
    analysis_type   "setup"              # setup | hold | setup_hold
    constraint_file "ravendrive_func.sdc"
    lib_set_ref     "ss_0760v_150c"      # Maps to library_sets in tech_config
    rc_corner       "rc_max"
    description     "Func worst setup: SS, 0.76V, 150C, max RC"
}
```

### Analysis Type Mapping
| Corner + Voltage + Temp | Analysis Type |
|-------------------------|:------------:|
| SS + low V + hot | setup |
| FF + high V + cold | hold |
| TT + nom V + nom T | setup_hold |

---

## Configuration File

**Location**: `PD/config/flow/v1.0.0/mmmc_config.tcl`

Key arrays:
- `mmmc_config` -- global settings (enabled, derating, uncertainty)
- `process_corners` -- SS/TT/FF definitions with voltage/temp ranges
- `operating_modes` -- func/test with SDC files
- `rc_corners` -- rcmax/rctyp/rcmin with multipliers
- `mmmc_scenario_sets` -- predefined sets (setup/hold/signoff/all/sta_*)
- `analysis_views` -- 17 views with full PVT + RC + mode attributes
- `mmmc` -- per-node scenario assignments (init_design through signoff + synthesis)

---

**Documentation Version**: 2.0.0
