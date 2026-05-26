# CBflow MMMC Setup Guide

Complete guide on how MMMC (Multi-Mode Multi-Corner) is configured, enabled, and executed in the SYNTH_PNR flow.

---

## 1. Architecture Overview

```
mmmc_config.tcl          ← Defines PVT building blocks, auto-generates views
       ↓
SYNTH_PNR_config.tcl     ← Enables MMMC, assigns scenario sets per stage
       ↓
SYNTH_PNR_fc_config.tcl  ← Tool-specific MMMC app vars (FC/Innovus)
       ↓
user_config.tcl          ← User overrides (scenario selection per node)
       ↓
init_design_fc.tcl       ← Command file: creates modes → corners → scenarios in FC
```

---

## 2. Defining PVT Building Blocks

**File:** `PD/config/flow/v1.0.0/mmmc_config.tcl`

### 2.1 Process Corners
```tcl
set mmmc(process_corners) {ss tt ff}
```

### 2.2 Operating Modes
```tcl
array set operating_modes {
    func { constraint_file "${design_name}_func.sdc" }
    test { constraint_file "${design_name}_test.sdc" }
}
```
Each mode has its own SDC. Add new modes here — the system auto-propagates everywhere.

### 2.3 PVT Combinations (Voltage × Temperature per Corner)
```tcl
set mmmc(pvt,ss) {{0p76v 150c} {0p76v 25c} {0p76v m40c} {0p80v 150c} {0p80v 25c}}
set mmmc(pvt,tt) {{0p80v 25c} {0p80v 150c} {0p80v m40c}}
set mmmc(pvt,ff) {{0p84v m40c} {0p84v 25c} {0p84v 150c} {0p80v m40c}}
```

### 2.4 RC Pairing (Corner → Parasitic Corner)
```tcl
set mmmc(rc_pair,ss) "rcmax"    ;# Slow process = worst RC delay
set mmmc(rc_pair,tt) "rctyp"    ;# Typical
set mmmc(rc_pair,ff) "rcmin"    ;# Fast process = best RC
```

---

## 3. How Views Are Auto-Generated

The system generates analysis views from the Cartesian product:

```
views = modes × corners × PVT_points
```

**Naming:** `${mode}_${corner}_${voltage}_${rc}_${temperature}`

**Example:** `func_ss_0p76v_rcmax_150c`

```tcl
foreach _mode [array names operating_modes] {
    foreach _corner $mmmc(process_corners) {
        set _rc $mmmc(rc_pair,$_corner)
        foreach _pvt $mmmc(pvt,$_corner) {
            set _v [lindex $_pvt 0]
            set _t [lindex $_pvt 1]
            set _name "${_mode}_${_corner}_${_v}_${_rc}_${_t}"
            # Store: corner, mode, voltage, temp, analysis_type, sdc, lib_set, rc_corner
        }
    }
}
```

**Result:** 24 views (2 modes × 12 PVT combos)

---

## 4. Scenario Sets (Pre-Computed Groups)

```tcl
mmmc_scenario_sets(setup)    = all *_ss_* views     (10 scenarios)
mmmc_scenario_sets(hold)     = all *_ff_* views     (8 scenarios)
mmmc_scenario_sets(signoff)  = ss + ff + tt nominal (19 scenarios)
mmmc_scenario_sets(all)      = every view           (24 scenarios)
```

---

## 5. Node-Specific Scenario Assignments

Each stage gets only the scenarios it needs (performance vs accuracy trade-off):

```tcl
array set mmmc {
    init_design {
        setup {func_tt_0p80v_rctyp_25c}
        hold  {}
    }
    synthesis {
        setup {func_ss_0p76v_rcmax_150c func_ss_0p76v_rcmax_m40c}
        hold  {func_ff_0p84v_rcmin_m40c}
    }
    placement {
        setup {func_ss_0p76v_rcmax_150c func_ss_0p80v_rcmax_25c test_ss_0p76v_rcmax_150c}
        hold  {func_ff_0p84v_rcmin_m40c test_ff_0p84v_rcmin_m40c}
    }
    cts {
        setup {func_ss_0p76v_rcmax_150c func_ss_0p76v_rcmax_m40c test_ss_0p76v_rcmax_150c}
        hold  {func_ff_0p84v_rcmin_m40c func_ff_0p80v_rcmin_m40c test_ff_0p84v_rcmin_m40c}
    }
    signoff {
        setup {func_ss_0p76v_rcmax_150c func_ss_0p76v_rcmax_25c func_ss_0p76v_rcmax_m40c
               test_ss_0p76v_rcmax_150c test_ss_0p76v_rcmax_25c test_ss_0p80v_rcmax_150c}
        hold  {func_ff_0p84v_rcmin_m40c func_ff_0p84v_rcmin_25c func_ff_0p80v_rcmin_m40c
               test_ff_0p84v_rcmin_m40c test_ff_0p84v_rcmin_25c test_ff_0p80v_rcmin_m40c}
    }
}
```

**Progression:** Fewer scenarios early (speed) → more at signoff (accuracy).

---

## 6. Enabling MMMC in SYNTH_PNR Flow

**File:** `PD/config/flow/v1.0.0/node_configs/SYNTH_PNR_config.tcl`

```tcl
array set synth_pnr {
    mmmc,enabled                true
    mmmc,default_scenario_set   "signoff"
    mmmc,scenario_set           "signoff"
    mmmc,multi_corner_compile   true
}
```

| Variable | Purpose |
|----------|---------|
| `mmmc,enabled` | Master switch — `true` to activate MMMC |
| `mmmc,default_scenario_set` | Fallback if node has no specific assignment |
| `mmmc,scenario_set` | Active set for this flow instance |
| `mmmc,multi_corner_compile` | Compile against multiple corners simultaneously |

---

## 7. Tool-Specific MMMC Settings (Fusion Compiler)

**File:** `PD/config/flow/v1.0.0/node_configs/SYNTH_PNR_fc_config.tcl`

```tcl
array set synth_pnr {
    compile,high_effort_timing      true
    cts,clock_opt_cts,enable_aocv   true
    cts_primary_corner              ""       ;# Empty = use all active scenarios
}
```

Per-stage scenario overrides (tool app vars):
```tcl
    synthesis,compile,active_scenarios      ""    ;# Empty = use node assignment
    cts,clock_opt_cts,active_scenarios      ""
    route_auto,active_scenarios             ""
    pro,opt_active_scenarios                ""
    signoff,active_scenarios                ""
```

---

## 8. How Command Files Execute MMMC

**File:** `PD/cmds/SYNTH_PNR/synopsys/fc/v1.0.0/init_design_fc.tcl`

The `setup_mcmm` flow_proc executes in this order:

### Step 1: Load UPF
```tcl
load_upf $synth_pnr(input,upf_file)
commit_upf
```

### Step 2: Create Modes (from operating_modes)
```tcl
foreach _mode [array names operating_modes] {
    set _sdc [dict get $operating_modes($_mode) constraint_file]
    create_mode $_mode
    current_mode $_mode
    read_sdc "$SDC_DIR/$_sdc"
}
```
Result: `func` and `test` modes created with their SDC files.

### Step 3: Create Corners (from analysis_views)
```tcl
foreach scenario [array names analysis_views] {
    array set _v $analysis_views($scenario)
    set _corner_name "${_v(corner)}_${_v(lib_set_ref)}"

    # Read timing libraries for this PVT point
    set _timing_libs $tech(${track},lib,${_v(lib_set_ref)},timing)

    # Read parasitic tech for RC corner
    set _tlu $tech(rcx,${_v(rc_corner)},tluplus)

    create_corner $_corner_name
    set_parasitic_parameters -corner $_corner_name -library_cell_late_spec $_timing_libs
    read_parasitic_tech -tlup $_tlu -name $_corner_name
}
```
Result: Unique corners like `ss_0p76v_150c`, `ff_0p84v_m40c`, etc.

### Step 4: Create Scenarios (mode × corner)
```tcl
foreach scenario [array names analysis_views] {
    array set _v $analysis_views($scenario)
    set _corner_name "${_v(corner)}_${_v(lib_set_ref)}"

    create_scenario -name $scenario -mode $_v(mode) -corner $_corner_name

    # Set analysis type
    switch $_v(analysis_type) {
        "setup"      { set_scenario_status $scenario -setup true -hold false }
        "hold"       { set_scenario_status $scenario -setup false -hold true }
        "setup_hold" { set_scenario_status $scenario -setup true -hold true }
    }
}
```

### Step 5: Activate Node-Specific Scenarios
```tcl
set _node_scenarios [get_node_scenarios $NODE_NAME "all"]
set_scenario_status -active false [get_scenarios -filter active]
set_scenario_status -active true $_node_scenarios
```
Only scenarios assigned to this node are activated. Others exist but are inactive.

---

## 9. How to Override MMMC in user_config.tcl

### Override scenario set for entire flow:
```tcl
set synth_pnr(mmmc,scenario_set) "setup"    ;# Only setup corners
```

### Override scenarios for a specific stage:
```tcl
# In setup/override_config.place1.tcl (or user_config.tcl):
set synth_pnr(synthesis,compile,active_scenarios) {func_ss_0p76v_rcmax_150c func_ff_0p84v_rcmin_m40c}
set synth_pnr(cts,clock_opt_cts,active_scenarios) {func_ss_0p76v_rcmax_150c func_ff_0p84v_rcmin_m40c func_tt_0p80v_rctyp_25c}
```

### Add a new operating mode:
```tcl
# In user_config.tcl:
set operating_modes(scan) { constraint_file "${design_name}_scan.sdc" }
```
The system auto-generates `scan_ss_*`, `scan_tt_*`, `scan_ff_*` views.

### Add a new PVT point:
```tcl
# In user_config.tcl:
lappend mmmc(pvt,ss) {0p72v 150c}    ;# Add ultra-low voltage corner
```
New views auto-generated: `func_ss_0p72v_rcmax_150c`, `test_ss_0p72v_rcmax_150c`

### Reduce corners for faster iteration (P0):
```tcl
set mmmc(pvt,ss) {{0p76v 150c}}       ;# Only worst-case
set mmmc(pvt,tt) {{0p80v 25c}}        ;# Only nominal
set mmmc(pvt,ff) {{0p84v m40c}}       ;# Only best-case
# Result: 6 views instead of 24 (2 modes × 3 corners × 1 PVT each)
```

---

## 10. How to Select Scenarios in GUI

1. Open dashboard: `cbflow run gui`
2. Right-click a timing-sensitive stage (e.g., `place1`)
3. Click **MMMC Scenarios**
4. Check/uncheck scenarios for setup and hold
5. Click **Save** — writes `setup/override_config.place1.tcl`
6. Retrace from that stage to apply

---

## 11. STA Dynamic Scenarios

For STA flow, each scenario runs as a **separate parallel job**:

```
timing1/
  ├── setup/                              (config setup)
  ├── func_ss_0p76v_rcmax_150c/          (parallel job)
  ├── func_ss_0p76v_rcmax_25c/           (parallel job)
  ├── func_ff_0p84v_rcmin_m40c/          (parallel job)
  ├── ...                                 (one per active scenario)
  ├── validate/                           (aggregate results)
  └── finish/                             (mark complete)
```

Each scenario subnode gets a **context file** with:
```tcl
set ::CORNER      "ss"
set ::MODE        "func"
set ::VOLTAGE     "0p76v"
set ::TEMPERATURE "150c"
set ::RC_CORNER   "rcmax"
set ::LIB_SET     "ss_0p76v_150c"
set ::SDC_FILE    "/path/to/func.sdc"
set ::SPEF_FILE   "/path/to/rcmax.spef"
```

---

## 12. RC Corners (Parasitic Extraction)

```tcl
array set rc_corners {
    rcmax {
        temperature     125
        cap_multiplier  1.10
        res_multiplier  1.15
        metal_fill      1.15
        via_res         1.25
    }
    rctyp {
        temperature     25
        cap_multiplier  1.00
        res_multiplier  1.00
        metal_fill      1.00
        via_res         1.00
    }
    rcmin {
        temperature     -40
        cap_multiplier  0.90
        res_multiplier  0.85
        metal_fill      0.85
        via_res         0.75
    }
}
```

Tech config maps RC corners to actual parasitic files:
```tcl
set tech(rcx,rcmax,tluplus)  "/path/to/rcmax.tluplus"
set tech(rcx,rctyp,tluplus)  "/path/to/rctyp.tluplus"
set tech(rcx,rcmin,tluplus)  "/path/to/rcmin.tluplus"
```

---

## 13. Summary: What You Need to Set Up MMMC

| What | Where | Required? |
|------|-------|-----------|
| Process corners | `mmmc_config.tcl` | Yes (ss/tt/ff) |
| Operating modes + SDC | `mmmc_config.tcl` | Yes (func at minimum) |
| PVT points per corner | `mmmc_config.tcl` | Yes (voltage × temp combos) |
| RC corner pairing | `mmmc_config.tcl` | Yes (corner → RC mapping) |
| Enable MMMC | `SYNTH_PNR_config.tcl` | Yes (`mmmc,enabled true`) |
| Timing libs per PVT | `tech_config.tcl` | Yes (`tech(<track>,lib,<libset>,timing)`) |
| TLU+ per RC corner | `tech_config.tcl` | Yes (`tech(rcx,<rc>,tluplus)`) |
| SDC files | Input files | Yes (one per mode) |
| Node scenario assignments | `mmmc_config.tcl` | Optional (defaults to signoff set) |
| Per-stage overrides | `user_config.tcl` | Optional (tune for speed/accuracy) |

---

## 14. Quick Start: Minimal MMMC for P0

For fast iteration during exploration (P0), reduce to 6 corners:

```tcl
# user_config.tcl — minimal MMMC for P0
set mmmc(pvt,ss) {{0p76v 150c}}
set mmmc(pvt,tt) {{0p80v 25c}}
set mmmc(pvt,ff) {{0p84v m40c}}
# Result: 2 modes × 3 corners = 6 scenarios (fast)
```

For signoff (P3), use full mmmc_config.tcl defaults (24 scenarios).
