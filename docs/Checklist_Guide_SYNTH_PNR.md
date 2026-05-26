# CBflow SYNTH_PNR Checklist System Guide

**CBflow v2.0.0** | **Flow: SYNTH_PNR** | **170 Library Checks Across 8 Categories**

This guide covers the complete checklist system for the SYNTH_PNR flow, including CLI usage, custom check creation, waivers, milestone progression, and the full 170-check reference library.

---

## Table of Contents

1. [How to Use Checklists (CLI Commands)](#1-how-to-use-checklists-cli-commands)
2. [How to Add Custom Checks](#2-how-to-add-custom-checks)
3. [How to Remove Checks](#3-how-to-remove-checks)
4. [How to Waive Checks](#4-how-to-waive-checks)
5. [Milestone Progression](#5-milestone-progression)
6. [Complete Check Reference](#6-complete-check-reference)
7. [Phase-Aware Check Activation Matrix](#7-phase-aware-check-activation-matrix)
8. [Threshold Override System](#8-threshold-override-system)

---

## 1. How to Use Checklists (CLI Commands)

All checklist commands are run from the **run directory** (e.g., `P0_run_SYNTH_PNR_test1/`).

### 1.1 List All Milestones

```bash
cbflow flow checklist list
```

Output:

```
SYNTH_PNR Flow Milestones
==========================
  FP_EXIT      Floorplan Exit - Design ready for placement          Stage: init_design1
  PLACE_EXIT   Placement Exit - Design ready for Clock Tree Synthesis  Stage: place1
  CTS_EXIT     Clock Tree Synthesis Exit - Design ready for Routing    Stage: cts_opt1
  PRO_EXIT     Post Route Optimization Exit - Design ready for PV      Stage: pro1
  BTO          Backend Tape Out - Design ready for mask generation     Stage: signoff1
  MTO          Mask Tape Out - Final delivery for mask generation      Stage: signoff1
```

### 1.2 List All Checks for a Milestone

```bash
cbflow flow checklist list-checks --milestone FP_EXIT
```

Shows all mandatory, optional, and library checks activated for `FP_EXIT`, including check packs (timing, placement, clock, power) and the phase at which each check becomes active.

```bash
# Filter by phase to see only checks active at a specific phase
cbflow flow checklist list-checks --milestone FP_EXIT --phase P0

# Filter by category
cbflow flow checklist list-checks --milestone BTO --category timing

# Filter by severity
cbflow flow checklist list-checks --milestone PRO_EXIT --severity critical
```

### 1.3 Generate a Checklist

```bash
cbflow flow checklist generate --milestone PRO_EXIT --phase P2 --format text
```

Generates a formatted checklist for PRO_EXIT at P2, showing all checks that must pass, their thresholds, and report file locations.

```bash
# Generate in different formats
cbflow flow checklist generate --milestone BTO --phase P3 --format text
cbflow flow checklist generate --milestone BTO --phase P3 --format html
cbflow flow checklist generate --milestone BTO --phase P3 --format json

# Generate for a specific project (applies project threshold overrides)
cbflow flow checklist generate --milestone PLACE_EXIT --phase P1 --project ravendrive
```

### 1.4 Evaluate Checklist Status

```bash
cbflow flow checklist status --milestone PRO_EXIT --run-dir . --phase P2
```

Evaluates all checks against actual report data in the run directory. Output includes PASS/FAIL/WAIVED/SKIP status for each check.

```bash
# Detailed output with actual vs. threshold values
cbflow flow checklist status --milestone BTO --run-dir . --phase P3 --details

# Status for a specific project (applies project-level thresholds)
cbflow flow checklist status --milestone CTS_EXIT --run-dir . --phase P1 --project ravendrive

# Quiet mode -- exit code only (0 = all pass, 1 = failures exist)
cbflow flow checklist status --milestone PLACE_EXIT --run-dir . --phase P0 --quiet
```

### 1.5 Sign Off a Milestone

```bash
cbflow flow checklist sign-off --milestone BTO --run-dir . --approver chip_lead --phase P3
```

Signs off a milestone after all mandatory checks pass. Records the approver, timestamp, and check results in `releases/<milestone>/signoff_record.json`.

```bash
# Dry-run to see what would be signed off
cbflow flow checklist sign-off --milestone PRO_EXIT --run-dir . --approver timing_lead --phase P2 --dry-run

# Sign off with a comment
cbflow flow checklist sign-off --milestone CTS_EXIT --run-dir . --approver cts_lead --phase P1 \
    --comment "Clock skew within target. Hold fixing deferred to route opt."
```

**Sign-off requirements:**
- All mandatory checks for the milestone at the given phase must PASS or be WAIVED
- BTO and MTO milestones do not allow waivers (policy enforced)
- Sign-off creates an immutable record under `releases/<milestone>/`

---

## 2. How to Add Custom Checks

CBflow supports three modes of custom check creation: **script-based**, **grep-based**, and **file-based**.

### 2.1 Script-Based Checks

Execute a TCL script that returns PASS/FAIL based on custom criteria.

```bash
cbflow flow checklist add-check \
    --milestone PRO_EXIT \
    --name custom_timing \
    --type mandatory \
    --description "Custom timing check" \
    --script check_timing.tcl \
    --criteria "wns >= 0"
```

The script `check_timing.tcl` must be placed in the run directory or a path accessible to the checklist engine. The script receives the run directory and node name as arguments and must exit with code 0 (pass) or 1 (fail).

```bash
# Add a custom power check at P2+
cbflow flow checklist add-check \
    --milestone BTO \
    --name custom_power_budget \
    --type mandatory \
    --description "Total power under 500mW budget" \
    --script check_power_budget.tcl \
    --criteria "total_power <= 500" \
    --min-phase P2
```

### 2.2 Grep-Based Checks

Search a report file for a specific pattern. Pass or fail based on whether the pattern is found.

```bash
cbflow flow checklist add-check \
    --milestone BTO \
    --name drc_zero \
    --type mandatory \
    --description "DRC must be zero" \
    --grep-file "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt" \
    --grep-pattern "Total.*0.*violation" \
    --grep-pass-if found
```

```bash
# Check that no critical warnings exist in the log
cbflow flow checklist add-check \
    --milestone PRO_EXIT \
    --name no_critical_warnings \
    --type mandatory \
    --description "No critical warnings in optimization log" \
    --grep-file "work/SYNTH_PNR/pro1/run/pro1.log" \
    --grep-pattern "CRITICAL WARNING" \
    --grep-pass-if not-found \
    --min-phase P2

# Check for LVS clean status
cbflow flow checklist add-check \
    --milestone BTO \
    --name lvs_clean \
    --type mandatory \
    --description "LVS comparison matches" \
    --grep-file "work/SYNTH_PNR/signoff1/reports/lvs_summary.rpt" \
    --grep-pattern "MATCH" \
    --grep-pass-if found
```

### 2.3 File-Based Checks

Verify that a required output file exists (and optionally is non-empty).

```bash
cbflow flow checklist add-check \
    --milestone BTO \
    --name gds_exists \
    --type file \
    --file-path "outputs/${design_name}.gds"
```

```bash
# Check that multiple deliverables exist
cbflow flow checklist add-check \
    --milestone MTO \
    --name pt_netlist_exists \
    --type file \
    --file-path "outputs/${design_name}.pt.v" \
    --min-phase P2

cbflow flow checklist add-check \
    --milestone MTO \
    --name fm_netlist_exists \
    --type file \
    --file-path "outputs/${design_name}.fm.v" \
    --min-phase P2

# Check with non-empty requirement
cbflow flow checklist add-check \
    --milestone BTO \
    --name spef_exists \
    --type file \
    --file-path "outputs/${design_name}.spef" \
    --require-non-empty
```

**Common options for all check types:**

| Option | Description | Default |
|--------|-------------|---------|
| `--min-phase` | Earliest phase where check is active (P0/P1/P2/P3) | P0 |
| `--type` | `mandatory` or `optional` | mandatory |
| `--category` | Custom category name for grouping | custom |
| `--severity` | `critical`, `major`, or `minor` | major |

---

## 3. How to Remove Checks

Remove a previously added custom check from a milestone.

```bash
cbflow flow checklist remove-check --milestone PRO_EXIT --name custom_timing
```

```bash
# Remove with confirmation prompt (default)
cbflow flow checklist remove-check --milestone BTO --name drc_zero

# Force remove without confirmation
cbflow flow checklist remove-check --milestone BTO --name drc_zero --force

# List custom checks before removing
cbflow flow checklist list-checks --milestone PRO_EXIT --custom-only
```

**Restrictions:**
- Only custom checks (user-added) can be removed. Library checks (TMG, PLC, CLK, PWR, RTG, PHY, SI, MFG) are defined in the check library and cannot be removed -- use waivers instead.
- Removing a check from a signed-off milestone invalidates the sign-off record.

---

## 4. How to Waive Checks

Waivers are approved exceptions that allow a check to be bypassed at a specific milestone.

### 4.1 List Active Waivers

```bash
cbflow flow checklist waiver --action list
```

```bash
# Filter by milestone
cbflow flow checklist waiver --action list --milestone FP_EXIT

# Filter by project
cbflow flow checklist waiver --action list --project ravendrive

# Show expired and revoked waivers too
cbflow flow checklist waiver --action list --all
```

### 4.2 Add a Waiver

```bash
cbflow flow checklist waiver \
    --action add \
    --milestone FP_EXIT \
    --check congestion_analysis \
    --reason "Acceptable at P0" \
    --approver chip_lead \
    --expiry 2026-08-01
```

```bash
# Waiver scoped to a specific project
cbflow flow checklist waiver \
    --action add \
    --milestone PLACE_EXIT \
    --check hold_timing \
    --reason "Hold fixing deferred to CTS stage per methodology" \
    --approver timing_lead \
    --expiry 2026-06-30 \
    --project ravendrive \
    --risk-level low \
    --conditions "Hold WNS must be >= -50ps"

# Waiver scoped to a specific block
cbflow flow checklist waiver \
    --action add \
    --milestone CTS_EXIT \
    --check clock_power \
    --reason "Clock mesh required for performance, power budget adjusted" \
    --approver clock_lead \
    --expiry 2026-09-15 \
    --project ravendrive \
    --block cpu_core \
    --risk-level medium
```

### 4.3 Revoke a Waiver

```bash
cbflow flow checklist waiver --action revoke --waiver-id W001
```

```bash
# Revoke with reason
cbflow flow checklist waiver --action revoke --waiver-id W002 \
    --reason "Congestion issue resolved after floorplan revision"
```

### 4.4 Waiver Policy

The waiver system enforces the following policies (defined in `PD/config/exit/v1.0.0/waiver_config.tcl`):

| Policy | Value | Description |
|--------|-------|-------------|
| `require_approval` | true | Every waiver must have a named approver |
| `require_expiry_date` | true | Every waiver must have an expiration date |
| `max_waiver_duration_days` | 90 | Maximum waiver lifetime is 90 days |
| `allow_bto_waivers` | **false** | BTO milestone waivers are **NOT** allowed |
| `allow_mto_waivers` | **false** | MTO milestone waivers are **NOT** allowed |
| `notify_on_waiver_use` | true | Notifications sent when a waiver is exercised |
| `audit_log_path` | `logs/waiver_audit.log` | All waiver activity is audited |

**Key restrictions:**
- BTO and MTO waivers are **never** allowed. All checks must pass cleanly at tapeout milestones.
- Maximum waiver duration is 90 days. Waivers must be renewed if the issue persists.
- Waivers require a named approver (chip_lead, timing_lead, etc.) and a business justification.
- All waiver usage is logged to the audit trail for compliance tracking.
- Risk levels (`low`, `medium`, `high`) must be assigned and are tracked in reporting.

---

## 5. Milestone Progression

The SYNTH_PNR flow defines six milestones in sequential order. Each milestone gates the next and activates progressively more check categories.

```
FP_EXIT --> PLACE_EXIT --> CTS_EXIT --> PRO_EXIT --> BTO --> MTO
init_design1   place1      cts_opt1      pro1      signoff1  signoff1
```

### 5.1 Milestone Summary

| Milestone | Stage Node | Description | Check Packs | Mandatory | Optional | Library Categories |
|-----------|------------|-------------|-------------|-----------|----------|--------------------|
| **FP_EXIT** | `init_design1` | Floorplan Exit -- Design ready for placement | timing, placement, clock, power | 4 | 3 | 4 |
| **PLACE_EXIT** | `place1` | Placement Exit -- Design ready for CTS | timing, placement, clock, power, physical | 6 | 5 | 5 |
| **CTS_EXIT** | `cts_opt1` | CTS Exit -- Design ready for routing | timing, placement, clock, power, physical | 5 | 5 | 5 |
| **PRO_EXIT** | `pro1` | Post-Route Opt Exit -- Design ready for PV | timing, placement, clock, power, routing, physical, si | 5 | 7 | 7 |
| **BTO** | `signoff1` | Backend Tape Out -- Design ready for mask generation | timing, placement, clock, power, routing, physical, si, manufacturing | 9 | 3 | 8 |
| **MTO** | `signoff1` | Mask Tape Out -- Final delivery for mask shop | timing, placement, clock, power, routing, physical, si, manufacturing | 10 | 6 | 8 |

### 5.2 Milestone Details

#### FP_EXIT -- Floorplan Exit

- **Stage node:** `init_design1`
- **Report directory:** `work/SYNTH_PNR/init_design1/reports/`
- **Check packs activated:** timing (P0), placement (P0), clock (P1), power (P1)
- **Mandatory checks:** 4 (fp_qor, fp_utilization, fp_design_summary, fp_clock_definitions)
- **Optional checks:** 3 (fp_timing_estimate, fp_constraint_check, fp_floorplan_rules)
- **Library checks by phase:**
  - P0: timing (2), placement (4) = **6 checks**
  - P1: +clock (2), +power (1), +timing (4), +placement (6) = **19 checks**
  - P2: +timing (0), +placement (1), +clock (0), +power (0) = **20 checks**
  - P3: +timing (0) = **20 checks**
- **Deliverables:** floorplan_db (.nlib), qor_report, utilization_report

#### PLACE_EXIT -- Placement Exit

- **Stage node:** `place1`
- **Report directory:** `work/SYNTH_PNR/place1/reports/`
- **Check packs activated:** timing (P0), placement (P0), clock (P1), power (P1), physical (P1)
- **Mandatory checks:** 6 (place_legality, place_setup_timing, place_qor, place_congestion, place_hold_timing, place_power)
- **Optional checks:** 5 (place_utilization, place_qor_summary, place_vt_group, place_constraint_check, place_signoff_drc)
- **Deliverables:** placement_db (.nlib), qor_report, timing_report, congestion_report, power_report

#### CTS_EXIT -- Clock Tree Synthesis Exit

- **Stage node:** `cts_opt1`
- **Report directory:** `work/SYNTH_PNR/cts_opt1/reports/` (clock reports from `cts1`)
- **Check packs activated:** timing (P0), placement (P0), clock (P0), power (P1), physical (P1)
- **Mandatory checks:** 5 (cts_clock_qor, cts_opt_qor, cts_setup_timing, cts_clock_timing, cts_hold_timing)
- **Optional checks:** 5 (cts_power, cts_congestion, cts_vt_group, cts_legality, cts_constraint_check)
- **Deliverables:** cts_db (.nlib), qor_report, clock_qor_report, timing_report, power_report

#### PRO_EXIT -- Post-Route Optimization Exit

- **Stage node:** `pro1`
- **Report directory:** `work/SYNTH_PNR/pro1/reports/`
- **Check packs activated:** timing (P0), placement (P0), clock (P0), power (P1), routing (P0), physical (P1), si (P2)
- **Mandatory checks:** 5 (pro_routing, pro_setup_timing, pro_qor, pro_hold_timing, pro_power)
- **Optional checks:** 7 (pro_congestion, pro_signal_integrity, pro_qor_summary, pro_vt_group, pro_legality, pro_constraint_check, pro_signoff_drc, pro_routes_final)
- **Deliverables:** pro_db (.nlib), netlist (.v), DEF, qor_report, timing_setup_report, timing_hold_report, power_report

#### BTO -- Backend Tape Out

- **Stage node:** `signoff1`
- **Report directory:** `work/SYNTH_PNR/signoff1/reports/`
- **Check packs activated:** timing (P0), placement (P0), clock (P0), power (P1), routing (P0), physical (P1), si (P2), manufacturing (P2)
- **Mandatory checks:** 9 (bto_setup_timing, bto_qor, bto_routing, bto_hold_timing, bto_signoff_drc, bto_power, bto_si, bto_legality, bto_constraint_check)
- **Optional checks:** 3 (bto_qor_summary, bto_vt_group, bto_utilization)
- **Cross-flow requirements:** STA, LEC, CLP, PV, EMIR, ECO must all pass
- **Waivers NOT allowed**
- **Deliverables:** signoff_db, GDS, netlist (.v, .pt.v, .fm.v), DEF, LEF, qor_report, drc_report, timing_report, power_report

#### MTO -- Mask Tape Out

- **Stage node:** `signoff1`
- **Report directory:** `work/SYNTH_PNR/signoff1/reports/`
- **Check packs activated:** All 8 categories (same as BTO)
- **Mandatory checks:** 10 (mto_gds_complete, mto_netlist_complete, mto_def_complete, mto_lef_complete, mto_upf_complete, mto_pt_netlist, mto_fm_netlist, mto_lvs_netlist, mto_vclp_netlist, mto_dc_netlist)
- **Optional checks:** 6 (mto_floorplan, mto_wscript, mto_wscript_pt, mto_routing_constraints, mto_design_db_nlib, mto_design_db_enc)
- **Prerequisite:** All BTO checks must pass first
- **Cross-flow requirements:** All BTO flows + POPT
- **Waivers NOT allowed**
- **Deliverables:** Complete delivery package (GDS, netlist, DEF, LEF, PT netlist, FM netlist, LVS netlist, UPF)

---

## 6. Complete Check Reference

The check library contains **170 checks** across 8 categories. Each check has a unique ID, is activated at a specific phase, and applies to one or more milestones.

**Severity levels:**
- **critical** -- Must pass. Blocks sign-off. Cannot be deferred.
- **major** -- Should pass. Requires justification if failing.
- **minor** -- Advisory. Does not block sign-off but tracked for quality.

**Milestone shorthand:**
- `FP+` = FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO
- `PLACE+` = PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO
- `CTS+` = CTS_EXIT, PRO_EXIT, BTO
- `PRO+` = PRO_EXIT, BTO
- `BTO` = BTO only
- `BTO/MTO` = BTO and MTO

### 6.1 Timing Checks (TMG-001 to TMG-030)

| ID | Check Name | Description | Severity | Phase | Milestones | Threshold | Operator |
|------|-----------|-------------|----------|-------|------------|-----------|----------|
| TMG-001 | setup_wns | Worst negative slack (setup) must meet threshold | critical | P0 | PLACE+ | 0.0 | >= |
| TMG-002 | setup_tns | Total negative slack (setup) must meet threshold | critical | P0 | PLACE+ | 0.0 | >= |
| TMG-003 | hold_wns | Worst negative slack (hold) must meet threshold | critical | P1 | CTS+ | 0.0 | >= |
| TMG-004 | hold_tns | Total negative slack (hold) must meet threshold | critical | P1 | CTS+ | 0.0 | >= |
| TMG-005 | setup_nvp | Number of violating paths (setup) within limit | major | P1 | CTS+ | 0 | <= |
| TMG-006 | hold_nvp | Number of violating paths (hold) within limit | major | P2 | PRO+ | 0 | <= |
| TMG-007 | max_cap_violations | Max capacitance violations count within limit | major | P1 | CTS+ | 0 | <= |
| TMG-008 | max_tran_violations | Max transition violations count within limit | major | P1 | CTS+ | 0 | <= |
| TMG-009 | max_fanout_violations | Max fanout violations count within limit | major | P1 | CTS+ | 0 | <= |
| TMG-010 | net_length_violations | Nets exceeding max length threshold | minor | P2 | PRO+ | 0 | <= |
| TMG-011 | setup_wns_per_group | Worst WNS per timing path group must meet threshold | major | P2 | PRO+ | 0.0 | >= |
| TMG-012 | hold_wns_per_group | Worst hold WNS per timing path group must meet threshold | major | P2 | PRO+ | 0.0 | >= |
| TMG-013 | recovery_violations | Recovery timing violations count within limit | major | P2 | PRO+ | 0 | <= |
| TMG-014 | removal_violations | Removal timing violations count within limit | major | P2 | PRO+ | 0 | <= |
| TMG-015 | pulse_width_violations | Min pulse width violations count within limit | major | P2 | PRO+ | 0 | <= |
| TMG-016 | clock_gating_check | Clock gating timing violations count within limit | major | P2 | PRO+ | 0 | <= |
| TMG-017 | multicycle_path_check | Multicycle path constraint coverage percentage | minor | P2 | PRO+ | 1 | >= |
| TMG-018 | false_path_coverage | False path constraint validation count | minor | P2 | PRO+ | 0 | >= |
| TMG-019 | case_analysis_coverage | Case analysis constraint count validated | minor | P2 | PRO+ | 0 | >= |
| TMG-020 | timing_exception_coverage | Timing exception coverage ratio must meet threshold | minor | P3 | BTO | 95.0% | >= |
| TMG-021 | setup_slack_histogram | Setup slack distribution -- paths with slack below threshold | minor | P2 | PRO+ | 0 | <= |
| TMG-022 | hold_slack_histogram | Hold slack distribution -- paths with slack below threshold | minor | P2 | PRO+ | 0 | <= |
| TMG-023 | cross_corner_wns | Worst WNS across all MMMC corners must meet threshold | critical | P2 | PRO+ | 0.0 | >= |
| TMG-024 | cross_corner_tns | Worst TNS across all MMMC corners must meet threshold | critical | P2 | PRO+ | 0.0 | >= |
| TMG-025 | interface_timing | I/O timing constraint compliance -- interface WNS | major | P1 | PLACE+ | 0.0 | >= |
| TMG-026 | reg2reg_wns | Register-to-register worst setup slack | major | P1 | PLACE+ | 0.0 | >= |
| TMG-027 | io2reg_wns | IO-to-register worst setup slack | major | P2 | PRO+ | 0.0 | >= |
| TMG-028 | reg2io_wns | Register-to-IO worst setup slack | major | P2 | PRO+ | 0.0 | >= |
| TMG-029 | memory_timing | Memory interface timing slack must meet threshold | major | P2 | PRO+ | 0.0 | >= |
| TMG-030 | signoff_vs_implementation | Signoff/implementation WNS correlation delta within limit | major | P3 | BTO | 0.050 ns | <= |

### 6.2 Placement Checks (PLC-001 to PLC-020)

| ID | Check Name | Description | Severity | Phase | Milestones | Threshold | Operator |
|------|-----------|-------------|----------|-------|------------|-----------|----------|
| PLC-001 | illegal_cells | Zero illegal cell placement violations required | critical | P0 | PLACE+ | 0 | == |
| PLC-002 | cell_density | Overall cell density percentage within target range | major | P0 | PLACE+ | 80.0% | <= |
| PLC-003 | brickwall_density | Local density hotspots must not exceed threshold | critical | P1 | PLACE+ | 90.0% | <= |
| PLC-004 | displacement_quality | Cell displacement from optimal placement position | minor | P1 | PLACE+ | 5.0 um | <= |
| PLC-005 | pin_accessibility | Pin access violations for routing must be zero | major | P1 | PLACE+ | 0 | <= |
| PLC-006 | macro_spacing | Macro-to-macro minimum spacing compliance | major | P0 | FP+ | 0 | == |
| PLC-007 | macro_orientation | Macro orientation legality -- all macros correctly oriented | major | P0 | FP+ | 0 | == |
| PLC-008 | macro_channel_width | Routing channel width between macros meets minimum | major | P1 | FP+ | 2.0 um | >= |
| PLC-009 | halo_violations | Halo/keepout region violations count | major | P1 | PLACE+ | 0 | == |
| PLC-010 | blockage_overlap | Cell-in-blockage placement violations | major | P1 | PLACE+ | 0 | == |
| PLC-011 | cell_orientation | Standard cell orientation violations | minor | P1 | PLACE+ | 0 | == |
| PLC-012 | well_tap_spacing | Well tap proximity compliance -- max spacing within limit | major | P2 | PRO+ | 0 | == |
| PLC-013 | endcap_placement | Endcap cell placement completeness | major | P2 | PRO+ | 0 | == |
| PLC-014 | filler_coverage | Filler cell coverage ratio percentage | major | P2 | PRO+ | 100.0% | >= |
| PLC-015 | power_domain_boundary | Power domain boundary cell placement violations | major | P1 | PLACE+ | 0 | == |
| PLC-016 | io_placement_legality | IO pad placement legality violations | major | P0 | FP+ | 0 | == |
| PLC-017 | utilization_uniformity | Utilization variance across placement regions | minor | P2 | PRO+ | 10.0% | <= |
| PLC-018 | congestion_hotspot | Local congestion hotspot overflow percentage | major | P1 | PLACE+ | 5.0% | <= |
| PLC-019 | placement_wirelength | Total estimated wirelength within budget | minor | P1 | PLACE+ | 1000000 | <= |
| PLC-020 | scan_chain_reorder | Scan chain physical order quality -- reorder distance | minor | P2 | PRO+ | 100.0 | <= |

### 6.3 Clock Checks (CLK-001 to CLK-025)

| ID | Check Name | Description | Severity | Phase | Milestones | Threshold | Operator |
|------|-----------|-------------|----------|-------|------------|-----------|----------|
| CLK-001 | clock_skew | Global clock skew across all sequential elements | critical | P0 | CTS+ | 100 ps | <= |
| CLK-002 | clock_insertion_delay | Maximum clock insertion delay from source to sink | major | P0 | CTS+ | 500 ps | <= |
| CLK-003 | clock_coverage | Percentage of sequential elements covered by clock tree | critical | P1 | CTS+ | 100.0% | >= |
| CLK-004 | clock_latency_balance | Latency balance across clock domains | major | P1 | CTS+ | 50 ps | <= |
| CLK-005 | clock_transition | Maximum clock transition time at sink pins | major | P1 | CTS+ | 150 ps | <= |
| CLK-006 | clock_power | Total clock network dynamic power consumption | major | P1 | CTS+ | 50.0 mW | <= |
| CLK-007 | clock_fanout | Maximum fanout of any clock buffer in the tree | minor | P1 | CTS+ | 32 | <= |
| CLK-008 | useful_skew | Timing benefit gained from useful skew optimization | minor | P1 | CTS+ | 0 ps | >= |
| CLK-009 | non_clock_cells_in_clock | Non-clock cells (non-buffer/inverter) found in clock tree | critical | P1 | CTS+ | 0 | == |
| CLK-010 | undefined_cells_in_clock | Cells in clock tree not in the allowed clock cell list | critical | P1 | CTS+ | 0 | == |
| CLK-011 | clock_reconvergence | Clock reconvergence pessimism removal analysis | major | P2 | PRO+ | 50 ps | <= |
| CLK-012 | clock_mesh_drc | DRC violations on clock mesh routing | major | P2 | PRO+ | 0 | == |
| CLK-013 | icg_usage | ICG cell utilization ratio across the design | minor | P1 | CTS+ | 50.0% | >= |
| CLK-014 | clock_buffer_ratio | Ratio of clock buffers to clock inverters in tree | minor | P2 | PRO+ | 3.0 | <= |
| CLK-015 | clock_ndr_compliance | Clock net compliance with non-default routing rules | major | P2 | PRO+ | 0 | == |
| CLK-016 | clock_tree_depth | Maximum clock tree depth measured in logic levels | minor | P1 | CTS+ | 20 | <= |
| CLK-017 | clock_duty_cycle | Clock duty cycle distortion at worst sink | major | P2 | PRO+ | 5.0% | <= |
| CLK-018 | clock_jitter_margin | Remaining jitter and uncertainty margin | major | P2 | PRO+ | 10 ps | >= |
| CLK-019 | inter_clock_skew | Skew between different clock domains at crossing points | major | P2 | PRO+ | 200 ps | <= |
| CLK-020 | clock_gating_efficiency | Percentage of gated clocks in the design | minor | P2 | PRO+ | 70.0% | >= |
| CLK-021 | clock_occ_timing | On-chip clock controller timing closure | minor | P3 | BTO | 0 | >= |
| CLK-022 | clock_dft_coverage | DFT clock controllability and observability coverage | minor | P3 | BTO | 95.0% | >= |
| CLK-023 | clock_latency_max | Absolute maximum clock latency limit across all sinks | major | P1 | CTS+ | 1000 ps | <= |
| CLK-024 | clock_hold_margin | CTS hold timing margin across all clock paths | critical | P2 | PRO+ | 0 ps | >= |
| CLK-025 | clock_power_vs_budget | Clock power consumption relative to allocated power budget | major | P2 | PRO+ | 100.0% | <= |

### 6.4 Power/Low-Power Checks (PWR-001 to PWR-020)

| ID | Check Name | Description | Severity | Phase | Milestones | Threshold | Operator |
|------|-----------|-------------|----------|-------|------------|-----------|----------|
| PWR-001 | missing_isolation | Missing isolation cells at power domain crossings | critical | P1 | PLACE+ | 0 | == |
| PWR-002 | missing_level_shifters | Missing level shifter cells at voltage domain crossings | critical | P1 | PLACE+ | 0 | == |
| PWR-003 | power_switch_distance | Maximum distance from power switch to controlled logic | major | P2 | PLACE+ | 50.0 um | <= |
| PWR-004 | always_on_violations | Always-on path violations in power-gated domains | critical | P2 | PLACE+ | 0 | == |
| PWR-005 | retention_check | Retention register save and restore path verification | critical | P2 | PLACE+ | 0 | == |
| PWR-006 | upf_implementation_match | Mismatch count between UPF intent and implementation | critical | P2 | PLACE+ | 0 | == |
| PWR-007 | power_domain_crossing | Unprotected signals crossing power domain boundaries | critical | P1 | PLACE+ | 0 | == |
| PWR-008 | supply_net_connectivity | VDD and VSS supply net connectivity integrity | critical | P2 | PLACE+ | 0 | == |
| PWR-009 | power_switch_chain | Power switch daisy-chain connectivity and ordering integrity | major | P2 | PLACE+ | 0 | == |
| PWR-010 | isolation_enable_timing | Isolation cell enable signal timing verification | major | P2 | PLACE+ | 0 | == |
| PWR-011 | level_shifter_placement | Level shifter placement location compliance | major | P2 | PLACE+ | 0 | == |
| PWR-012 | power_state_coverage | Percentage of defined power states exercised in verification | minor | P3 | PLACE+ | 100.0% | >= |
| PWR-013 | corruption_analysis | State corruption risk analysis during power transitions | major | P3 | PLACE+ | 0 | == |
| PWR-014 | sleep_wakeup_sequence | Sleep and wakeup power sequence verification | major | P3 | PLACE+ | 0 | == |
| PWR-015 | power_intent_lint | UPF power intent lint and syntax check violations | major | P0 | FP+ | 0 | == |
| PWR-016 | voltage_area_overlap | Overlapping voltage area boundary violations | critical | P1 | PLACE+ | 0 | == |
| PWR-017 | ao_buffer_usage | Always-on buffer insertion and usage verification | major | P2 | PLACE+ | 0 | == |
| PWR-018 | power_domain_boundary_cells | Completeness of boundary cells at power domain edges | major | P2 | PLACE+ | 0 | == |
| PWR-019 | esd_path_check | ESD discharge path integrity through power domains | major | P3 | PLACE+ | 0 | == |
| PWR-020 | power_gating_leakage | Residual leakage current in power-gated domains | minor | P3 | PLACE+ | 1.0 uA | <= |

### 6.5 Routing Checks (RTG-001 to RTG-025)

| ID | Check Name | Description | Severity | Phase | Milestones | Threshold | Operator |
|------|-----------|-------------|----------|-------|------------|-----------|----------|
| RTG-001 | routing_completion | Routing 100% complete -- all nets fully routed | critical | P0 | PRO+ | 100% | == |
| RTG-002 | opens | Zero open nets -- no incomplete routing | critical | P0 | PRO+ | 0 | == |
| RTG-003 | shorts | Zero short violations -- no shorted nets | critical | P0 | PRO+ | 0 | == |
| RTG-004 | drc_total | Total DRC violations within threshold | critical | P1 | PRO+ | 0 | <= |
| RTG-005 | drc_spacing | Metal spacing violations within threshold | critical | P1 | PRO+ | 0 | <= |
| RTG-006 | drc_width | Minimum width violations within threshold | critical | P1 | PRO+ | 0 | <= |
| RTG-007 | drc_via | Via enclosure violations within threshold | major | P2 | PRO+ | 0 | <= |
| RTG-008 | drc_area | Minimum area violations within threshold | major | P2 | PRO+ | 0 | <= |
| RTG-009 | congestion_h | Horizontal routing congestion overflow percentage | major | P0 | PLACE+ | 0.5% | <= |
| RTG-010 | congestion_v | Vertical routing congestion overflow percentage | major | P0 | PLACE+ | 0.5% | <= |
| RTG-011 | antenna_violations | Antenna rule violations count | major | P2 | PRO+ | 0 | <= |
| RTG-012 | antenna_ratio | Worst antenna ratio within allowed limit | major | P2 | PRO+ | 1.0 | <= |
| RTG-013 | net_length_threshold | Number of nets exceeding maximum length threshold | minor | P2 | PRO+ | 0 | <= |
| RTG-014 | detour_routing | Routing detour percentage -- ratio of actual to ideal length | minor | P2 | PRO+ | 5.0% | <= |
| RTG-015 | via_count_optimization | Via count per net optimization -- excess via percentage | minor | P3 | PRO+ | 10.0% | <= |
| RTG-016 | ndr_compliance | Non-default rule compliance -- all NDR nets meet rules | major | P2 | PRO+ | 0 | == |
| RTG-017 | shielding_coverage | Critical net shielding coverage percentage | major | P2 | PRO+ | 100.0% | >= |
| RTG-018 | metal_density_min | Minimum metal density per layer meets foundry requirement | major | P2 | PRO+ | 20.0% | >= |
| RTG-019 | metal_density_max | Maximum metal density per layer within foundry limit | major | P2 | PRO+ | 80.0% | <= |
| RTG-020 | via_density | Via density uniformity across design | minor | P3 | PRO+ | 15.0% | <= |
| RTG-021 | power_shorts | Power-to-signal short violations -- zero allowed | critical | P1 | PRO+ | 0 | == |
| RTG-022 | power_opens | Power mesh open connections -- zero allowed | critical | P1 | PRO+ | 0 | == |
| RTG-023 | critical_net_routing | Critical net routing quality -- DRC-clean critical nets | major | P2 | PRO+ | 0 | == |
| RTG-024 | clock_route_drc | Clock routing specific DRC violations | major | P2 | PRO+ | 0 | == |
| RTG-025 | multi_cut_via_ratio | Multi-cut via usage ratio for reliability | minor | P3 | PRO+ | 90.0% | >= |

### 6.6 Physical Design Checks (PHY-001 to PHY-020)

| ID | Check Name | Description | Severity | Phase | Milestones | Threshold | Operator |
|------|-----------|-------------|----------|-------|------------|-----------|----------|
| PHY-001 | unconnected_cells | Cells with unconnected pins -- no dangling connections | critical | P1 | PLACE+ | 0 | == |
| PHY-002 | floating_pins | Floating input pins -- no undriven inputs | critical | P1 | PLACE+ | 0 | == |
| PHY-003 | open_nets | Physically open signal nets -- no broken connections | critical | P1 | PLACE+ | 0 | == |
| PHY-004 | missing_vias_power | Missing vias in power mesh -- all junctions connected | critical | P2 | PRO+ | 0 | == |
| PHY-005 | power_strap_coverage | VDD/VSS strap coverage per layer meets requirement | major | P1 | PLACE+ | 95.0% | >= |
| PHY-006 | power_strap_width | Power strap width compliance with design rules | major | P2 | PRO+ | 0 | == |
| PHY-007 | power_mesh_ir_drop | IR drop at worst case within voltage margin | critical | P2 | PRO+ | 30.0 mV | <= |
| PHY-008 | em_violations | Electromigration current density violations | critical | P2 | PRO+ | 0 | == |
| PHY-009 | well_tap_coverage | N-well/P-well tap coverage ratio meets latch-up rules | major | P2 | PLACE+ | 100.0% | >= |
| PHY-010 | endcap_completeness | Row-end endcap cells present at all row boundaries | major | P2 | PLACE+ | 0 | == |
| PHY-011 | filler_completeness | Filler cell coverage -- no gaps in cell rows | major | P2 | PRO+ | 0 | == |
| PHY-012 | decap_placement | Decap cell distribution for power integrity | minor | P2 | PRO+ | 85.0% | >= |
| PHY-013 | boundary_cell_check | Voltage area boundary cells properly placed | major | P2 | PLACE+ | 0 | == |
| PHY-014 | pin_density_check | Pin density within routability threshold | minor | P1 | PLACE+ | 0 | <= |
| PHY-015 | io_ring_continuity | IO power ring continuity -- no breaks in ring | critical | P1 | FP+ | 0 | == |
| PHY-016 | pg_connection_check | All standard cells PG connected -- no floating power/ground | critical | P2 | PLACE+ | 0 | == |
| PHY-017 | spare_cell_placement | Spare cell distribution across design area | minor | P2 | PLACE+ | 90.0% | >= |
| PHY-018 | tie_cell_connection | Tie-high/tie-low cell completeness -- no direct VDD/VSS ties | major | P2 | PLACE+ | 0 | == |
| PHY-019 | blockage_coverage | Hard/soft blockage proper coverage in floorplan | minor | P1 | PLACE+ | 0 | == |
| PHY-020 | cell_padding_check | Cell-to-cell spacing padding meets requirements | minor | P2 | PLACE+ | 0 | == |

### 6.7 Signal Integrity Checks (SI-001 to SI-015)

| ID | Check Name | Description | Severity | Phase | Milestones | Threshold | Operator |
|------|-----------|-------------|----------|-------|------------|-----------|----------|
| SI-001 | crosstalk_delay | Crosstalk-induced delay violations | critical | P2 | PRO+ | 0 | == |
| SI-002 | crosstalk_noise | Crosstalk noise violations (DC) | critical | P2 | PRO+ | 0 | == |
| SI-003 | glitch_violations | Glitch propagation violations | critical | P2 | PRO+ | 0 | == |
| SI-004 | coupling_cap_ratio | Max coupling cap to total cap ratio | major | P2 | PRO+ | 0.35 | <= |
| SI-005 | aggressor_count | Nets with excessive aggressors | major | P2 | PRO+ | 0 | == |
| SI-006 | victim_slack_degradation | Timing degradation from SI effects | major | P2 | PRO+ | 0.050 ns | <= |
| SI-007 | si_hold_violations | SI-induced hold timing violations | critical | P3 | PRO+ | 0 | == |
| SI-008 | si_setup_violations | SI-induced setup timing violations | critical | P3 | PRO+ | 0 | == |
| SI-009 | noise_margin | Worst noise margin remaining | major | P2 | PRO+ | 0.10 V | >= |
| SI-010 | shielding_effectiveness | Shield net effectiveness percentage | minor | P3 | PRO+ | 90.0% | >= |
| SI-011 | si_aware_timing_delta | SI vs non-SI timing delta | minor | P2 | PRO+ | 0.100 ns | <= |
| SI-012 | bus_crosstalk | Bus self-coupling analysis violations | major | P3 | PRO+ | 0 | == |
| SI-013 | clock_si_impact | SI impact on clock network | critical | P2 | PRO+ | 0 | == |
| SI-014 | power_rail_noise | Power rail noise coupling violations | major | P3 | PRO+ | 0 | == |
| SI-015 | simultaneous_switching | SSO/SSN simultaneous switching analysis | major | P3 | PRO+ | 0 | == |

### 6.8 Manufacturing Checks (MFG-001 to MFG-015)

| ID | Check Name | Description | Severity | Phase | Milestones | Threshold | Operator |
|------|-----------|-------------|----------|-------|------------|-----------|----------|
| MFG-001 | metal_density_m1 | Metal 1 density within foundry limits | critical | P2 | BTO/MTO | 20.0% | >= |
| MFG-002 | metal_density_m2 | Metal 2 density within foundry limits | critical | P2 | BTO/MTO | 20.0% | >= |
| MFG-003 | metal_density_upper | Upper metal density compliance | critical | P2 | BTO/MTO | 0 | == |
| MFG-004 | metal_density_uniformity | Density window uniformity within limits | major | P3 | BTO/MTO | 0 | == |
| MFG-005 | via_density_check | Via density per layer within limits | major | P3 | BTO/MTO | 0 | == |
| MFG-006 | critical_area_analysis | Random defect critical area analysis | minor | P3 | BTO/MTO | 1.0 | <= |
| MFG-007 | antenna_per_layer | Per-layer antenna ratio check | major | P2 | PRO+/MTO | 0 | == |
| MFG-008 | double_patterning | Double patterning compliance (advanced nodes) | major | P2 | BTO/MTO | 0 | == |
| MFG-009 | minimum_density_fill | Post-fill minimum density check | major | P3 | BTO/MTO | 0 | == |
| MFG-010 | filler_metal_check | Dummy metal fill coverage | major | P3 | BTO/MTO | 80.0% | >= |
| MFG-011 | opc_friendly_check | OPC-friendly routing patterns | minor | P3 | BTO/MTO | 0 | == |
| MFG-012 | lithography_hotspot | Lithography hotspot detection | minor | P3 | BTO/MTO | 0 | == |
| MFG-013 | etch_proximity | Etch proximity effect violations | minor | P3 | BTO/MTO | 0 | == |
| MFG-014 | cmp_uniformity | CMP planarity and uniformity analysis | minor | P3 | BTO/MTO | 0 | == |
| MFG-015 | esd_protection | ESD structure completeness check | major | P3 | BTO/MTO | 0 | == |

---

## 7. Phase-Aware Check Activation Matrix

Checks are activated progressively as the design advances through phases. The table below shows how many **library checks** are active at each milestone and phase combination.

### 7.1 Checks Active Per Milestone Per Phase

| Milestone | P0 | P1 | P2 | P3 | Total Library Checks |
|-----------|----|----|----|----|---------------------|
| **FP_EXIT** | 6 | 13 | 1 | 0 | 20 |
| **PLACE_EXIT** | 10 | 30 | 33 | 6 | 79 |
| **CTS_EXIT** | 12 | 34 | 33 | 6 | 85 |
| **PRO_EXIT** | 15 | 34 | 55 | 14 | 118 |
| **BTO** | 15 | 34 | 58 | 23 | 130 |
| **MTO** | 15 | 34 | 58 | 23 | 130 |

### 7.2 Checks Active Per Category Per Milestone

| Category | FP_EXIT | PLACE_EXIT | CTS_EXIT | PRO_EXIT | BTO | MTO |
|----------|---------|------------|----------|----------|-----|-----|
| Timing (30) | 2 | 6 | 9 | 26 | 30 | 30 |
| Placement (20) | 4 | 16 | 16 | 20 | 20 | 20 |
| Clock (25) | 0 | 0 | 16 | 25 | 25 | 25 |
| Power (20) | 1 | 16 | 16 | 20 | 20 | 20 |
| Routing (25) | 0 | 2 | 2 | 25 | 25 | 25 |
| Physical (20) | 1 | 13 | 13 | 20 | 20 | 20 |
| SI (15) | 0 | 0 | 0 | 15 | 15 | 15 |
| Manufacturing (15) | 0 | 0 | 0 | 2 | 15 | 15 |
| **Total** | **8** | **53** | **72** | **153** | **170** | **170** |

### 7.3 Severity Distribution Per Milestone

| Milestone | Critical | Major | Minor |
|-----------|----------|-------|-------|
| FP_EXIT | 0 | 5 | 3 |
| PLACE_EXIT | 11 | 30 | 12 |
| CTS_EXIT | 17 | 36 | 19 |
| PRO_EXIT | 28 | 73 | 52 |
| BTO | 33 | 82 | 55 |
| MTO | 33 | 82 | 55 |

### 7.4 Phase Descriptions

| Phase | Name | Purpose | Threshold Posture |
|-------|------|---------|-------------------|
| **P0** | Trial/Exploration | Initial bring-up, feasibility assessment | Relaxed -- large negative slack allowed, high congestion tolerated |
| **P1** | Implementation | Convergence toward targets, iterative optimization | Moderate -- tighter timing, DRC acknowledged but non-zero allowed |
| **P2** | Pre-Signoff | All metrics converging to zero, signoff tools engaged | Tight -- timing clean, DRC near-zero, SI analysis active |
| **P3** | Signoff/Tapeout | Final verification, zero tolerance on all critical checks | Strict -- zero violations on all critical metrics, full delivery package |

---

## 8. Threshold Override System

The checklist system supports a layered threshold override mechanism that allows project-specific and phase-specific customization of check pass/fail criteria.

### 8.1 Override Resolution Order

Thresholds are resolved in priority order (highest priority first):

```
1. Phase-level project override   phase_override(<project>,<phase>,<milestone>,<metric>)
2. Project-level override         threshold_override(<project>,<milestone>,<metric>)
3. Phase-progressive defaults     phase_defaults(<phase>,<milestone>,<metric>)
4. Default thresholds             default_thresholds(<milestone>,<metric>)
5. Check library default          (from checks/*.tcl default_threshold)
```

If no override is found at any level, the check library's `default_threshold` is used.

### 8.2 Default Thresholds

These are the baseline thresholds when no project or phase overrides are specified:

| Milestone | Metric | Default Threshold |
|-----------|--------|-------------------|
| FP_EXIT | utilization_min | 0.55 (55%) |
| FP_EXIT | utilization_max | 0.85 (85%) |
| FP_EXIT | setup_wns | -200 ps |
| PLACE_EXIT | setup_wns | -100 ps |
| PLACE_EXIT | setup_tns | -1000 ps |
| PLACE_EXIT | hold_wns | -50 ps |
| PLACE_EXIT | max_congestion | 0.90 (90%) |
| PLACE_EXIT | density_min | 0.65 (65%) |
| PLACE_EXIT | density_max | 0.88 (88%) |
| CTS_EXIT | clock_skew | 60 ps |
| CTS_EXIT | max_insertion_delay | 500 ps |
| CTS_EXIT | clock_coverage | 99.0% |
| CTS_EXIT | setup_wns | -50 ps |
| CTS_EXIT | hold_wns | -20 ps |
| PRO_EXIT | setup_wns | -20 ps |
| PRO_EXIT | setup_tns | -200 ps |
| PRO_EXIT | hold_wns | -10 ps |
| PRO_EXIT | hold_tns | -100 ps |
| PRO_EXIT | max_congestion | 0.85 (85%) |
| PRO_EXIT | max_ir_drop | 40 mV |
| BTO | setup_wns | 0 ps |
| BTO | setup_tns | 0 ps |
| BTO | hold_wns | 0 ps |
| BTO | hold_tns | 0 ps |
| BTO | drc_violations | 0 |
| BTO | max_ir_drop | 30 mV |

### 8.3 Phase-Progressive Defaults

Thresholds that automatically relax at early phases and tighten toward signoff. These apply to **all projects** unless overridden at the project level.

#### P0 -- Trial/Exploration (relaxed)

| Milestone | Metric | P0 Threshold |
|-----------|--------|-------------|
| FP_EXIT | utilization_min | 0.45 |
| FP_EXIT | setup_wns | -500 ps |
| PLACE_EXIT | setup_wns | -200 ps |
| PLACE_EXIT | setup_tns | -5000 ps |
| PLACE_EXIT | hold_wns | -100 ps |
| PLACE_EXIT | max_congestion | 0.95 |
| CTS_EXIT | clock_skew | 100 ps |
| CTS_EXIT | setup_wns | -100 ps |
| CTS_EXIT | hold_wns | -50 ps |
| PRO_EXIT | setup_wns | -100 ps |
| PRO_EXIT | hold_wns | -50 ps |
| PRO_EXIT | max_ir_drop | 60 mV |
| BTO | setup_wns | -50 ps |
| BTO | hold_wns | -20 ps |

#### P1 -- Implementation (convergence)

| Milestone | Metric | P1 Threshold |
|-----------|--------|-------------|
| PLACE_EXIT | setup_wns | -80 ps |
| PLACE_EXIT | setup_tns | -2000 ps |
| PLACE_EXIT | hold_wns | -30 ps |
| CTS_EXIT | clock_skew | 60 ps |
| CTS_EXIT | setup_wns | -50 ps |
| CTS_EXIT | hold_wns | -20 ps |
| PRO_EXIT | setup_wns | -30 ps |
| PRO_EXIT | hold_wns | -20 ps |
| BTO | setup_wns | -20 ps |
| BTO | hold_wns | -10 ps |

#### P2 -- Pre-Signoff (tight)

| Milestone | Metric | P2 Threshold |
|-----------|--------|-------------|
| PLACE_EXIT | setup_wns | -20 ps |
| PLACE_EXIT | setup_tns | -500 ps |
| CTS_EXIT | clock_skew | 40 ps |
| CTS_EXIT | setup_wns | -10 ps |
| PRO_EXIT | setup_wns | 0 ps |
| PRO_EXIT | hold_wns | 0 ps |
| PRO_EXIT | setup_tns | 0 ps |
| BTO | setup_wns | 0 ps |
| BTO | hold_wns | 0 ps |
| BTO | drc_violations | 0 |

#### P3 -- Signoff/Tapeout (strict, zero tolerance)

| Milestone | Metric | P3 Threshold |
|-----------|--------|-------------|
| PLACE_EXIT | setup_wns | 0 ps |
| PLACE_EXIT | setup_tns | 0 ps |
| CTS_EXIT | clock_skew | 30 ps |
| CTS_EXIT | setup_wns | 0 ps |
| CTS_EXIT | hold_wns | 0 ps |
| PRO_EXIT | setup_wns | 0 ps |
| PRO_EXIT | hold_wns | 0 ps |
| PRO_EXIT | setup_tns | 0 ps |
| PRO_EXIT | hold_tns | 0 ps |
| BTO | setup_wns | 0 ps |
| BTO | hold_wns | 0 ps |
| BTO | setup_tns | 0 ps |
| BTO | hold_tns | 0 ps |
| BTO | drc_violations | 0 |

### 8.4 Project-Level Overrides

Override thresholds for a specific project. Place in `PD/config/exit/v1.0.0/threshold_overrides.tcl`.

**Example: ravendrive (22nm, relaxed early milestones)**

```tcl
array set threshold_override {
    ravendrive,FP_EXIT,utilization_min           0.55
    ravendrive,FP_EXIT,utilization_max           0.82
    ravendrive,FP_EXIT,setup_wns                 -300

    ravendrive,PLACE_EXIT,setup_wns              -80
    ravendrive,PLACE_EXIT,setup_tns              -800
    ravendrive,PLACE_EXIT,max_congestion         0.88

    ravendrive,CTS_EXIT,clock_skew               60
    ravendrive,CTS_EXIT,max_insertion_delay       600
    ravendrive,CTS_EXIT,clock_coverage            99.0

    ravendrive,PRO_EXIT,max_ir_drop              40
}
```

**Example: india (5nm, tighter thresholds)**

```tcl
array set threshold_override {
    india,FP_EXIT,utilization_min                0.65
    india,FP_EXIT,utilization_max                0.78

    india,PLACE_EXIT,setup_wns                   -30
    india,PLACE_EXIT,setup_tns                   -300
    india,PLACE_EXIT,max_congestion              0.80

    india,CTS_EXIT,clock_skew                    35
    india,CTS_EXIT,max_insertion_delay            350
    india,CTS_EXIT,clock_coverage                 99.8

    india,PRO_EXIT,max_ir_drop                   20
    india,PRO_EXIT,setup_wns                     0
    india,PRO_EXIT,hold_wns                      0
}
```

### 8.5 Phase-Level Project Overrides

The most specific override: per-project, per-phase thresholds that take the highest priority.

```tcl
array set phase_override {
    ravendrive,P0,FP_EXIT,utilization_min        0.50
    ravendrive,P0,PLACE_EXIT,setup_wns           -150
    ravendrive,P0,PLACE_EXIT,setup_tns           -2000
    ravendrive,P0,CTS_EXIT,clock_skew            80

    ravendrive,P1,PLACE_EXIT,setup_wns           -80
    ravendrive,P1,PLACE_EXIT,setup_tns           -800

    ravendrive,P2,PLACE_EXIT,setup_wns           -20
    ravendrive,P2,PRO_EXIT,setup_wns             0
    ravendrive,P2,PRO_EXIT,hold_wns              0
}
```

### 8.6 How to Customize Thresholds

**Step 1:** Edit (or create) the threshold overrides file:

```
PD/config/exit/v1.0.0/threshold_overrides.tcl
```

**Step 2:** Add entries using the appropriate array format:

```tcl
# Project-level override (applies to all phases unless phase override exists)
set threshold_override(<project>,<milestone>,<metric>) <value>

# Phase-level project override (highest priority)
set phase_override(<project>,<phase>,<milestone>,<metric>) <value>
```

**Step 3:** Verify the resolved threshold:

```bash
# Check what threshold will be used for a specific project/milestone/phase
cbflow flow checklist generate --milestone PLACE_EXIT --phase P1 --project ravendrive
```

### 8.7 Override Policy

| Policy | Setting | Description |
|--------|---------|-------------|
| `allow_relaxation` | true | Projects may relax thresholds from defaults |
| `allow_tightening` | true | Projects may tighten thresholds from defaults |
| `require_justification` | true | All overrides should be documented with rationale |
| `log_override_usage` | true | Override usage is logged for audit trail |

---

## Configuration File Reference

| File | Purpose |
|------|---------|
| `PD/config/exit/v1.0.0/FP_EXIT_config.tcl` | FP_EXIT milestone: checks, deliverables, mandatory files |
| `PD/config/exit/v1.0.0/PLACE_EXIT_config.tcl` | PLACE_EXIT milestone configuration |
| `PD/config/exit/v1.0.0/CTS_EXIT_config.tcl` | CTS_EXIT milestone configuration |
| `PD/config/exit/v1.0.0/PRO_EXIT_config.tcl` | PRO_EXIT milestone configuration |
| `PD/config/exit/v1.0.0/BTO_config.tcl` | BTO milestone configuration |
| `PD/config/exit/v1.0.0/MTO_config.tcl` | MTO milestone configuration |
| `PD/config/exit/v1.0.0/checks/timing_checks.tcl` | 30 timing library checks |
| `PD/config/exit/v1.0.0/checks/placement_checks.tcl` | 20 placement library checks |
| `PD/config/exit/v1.0.0/checks/clock_checks.tcl` | 25 clock library checks |
| `PD/config/exit/v1.0.0/checks/power_checks.tcl` | 20 power/UPF library checks |
| `PD/config/exit/v1.0.0/checks/routing_checks.tcl` | 25 routing library checks |
| `PD/config/exit/v1.0.0/checks/physical_checks.tcl` | 20 physical design library checks |
| `PD/config/exit/v1.0.0/checks/si_checks.tcl` | 15 signal integrity library checks |
| `PD/config/exit/v1.0.0/checks/manufacturing_checks.tcl` | 15 manufacturing/DFM library checks |
| `PD/config/exit/v1.0.0/threshold_overrides.tcl` | Default, phase, and project threshold overrides |
| `PD/config/exit/v1.0.0/waiver_config.tcl` | Waiver policy, database, and procedures |
| `PD/config/exit/v1.0.0/remediation_config.tcl` | Fix suggestions for common check failures |
| `PD/config/flow/v1.0.0/release_config.tcl` | Release exit files, phase criteria, cross-flow mapping |
