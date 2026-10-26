#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — denali
# GLOBAL layer (cross-discipline: PD + DFT + DV all read this)
# Auto-split from legacy PD/config/project/denali/v1.0.0/denali_config.tcl
# =============================================================================

#!/usr/bin/env tclsh
# ============================================================================
# CBflow - Denali Project Configuration
# Description: Denali project-specific parameters
# ============================================================================

# Project identification
set project(name) "denali"

# Phase timeline for this project (project-specific — flow(phases) is deprecated).
set project(phases)          {P0 P1 P2 P3}
set project(current_phase)   "P0"
set project(version) "1.0"
set project(cbflow_release) "v1.0.0"   ;# CBflow release version for this project
set project(description) "Denali chip design project"
set project(owner) "Denali Design Team"
set project(contact) "denali@smartsoc.com"

;# Project root directory for relative path resolution
set project(technology) "gf_28nm"
set project(vt_flavors) "rvt lvt hvt"
set project(top_module) "denali_top"

;
;# SDC Mode Definitions (used for file naming: <design_name>.<mode>.sdc)
set project(sdc_modes) {func scan test}
set project(default_sdc_mode) "func"

;# Power & Ground Nets (consumed by init_design/PNR — top-level SoC-wide)
set project(power,vdd_net) "VDD"
set project(power,vss_net) "VSS"
set project(power,vdd_pin) "VDD"
set project(power,vss_pin) "VSS"

;# Block-level specs (clock uncertainty, target frequency/power/area, reset
# ports, I/O voltage, power domains, design-size estimates) used to live
# here as `project(target,*)`, `project(estimated_*)`, `project(io,*)`,
# `project(reset,*)`, `project(power,domains|states|switches|isolation|
# retention)`. They were unread by any cmd handler and removed in the
# cleanup commit. Block-shaped specs belong in user_config or a per-block
# `<block_name>_floorplan.tcl`, not in this project-wide config.

# Test and verification
set project(dft,scan_chains) "4"
set project(dft,coverage_target) "98"
set project(dft,compression) "true"
set project(verification,formal) "true"
set project(verification,simulation) "true"

;# Feature toggles
set project(tapeout_date) "2026-09-30"          ;# ISO date — drives "Weeks to tapeout" on dashboard

;
;# ---------------------------------------------------------------------------
# LSF RESOURCE MANAGEMENT
# ---------------------------------------------------------------------------

set project(analog_blocks) ""        ;# Analog block list (project-specific; empty if none)
set project(design_hierarchy) {
    denali_top                    {
    description                   "Full chip top level (DL1)"
    level                         "DL1"
    parent                        ""
    children                      {tom}
    }                             tom
    {                             description
    "TOM processing block (DL2)"  level
    "DL2"                         parent
    "denali_top"                  children
    {}                            }
}

# Default Cadence tools
set project(valid_design_names) [dict keys $project(design_hierarchy)]

# ─────────────────────────────────────────────────────────────────────────────
# Derived: project(block_list) — the DL2 subsystems of design_hierarchy.
# Consumed by FCFP/FP init_design_fc.tcl for hierarchical NDM loading.
# ─────────────────────────────────────────────────────────────────────────────
set _blk_list {}
dict for {_blk _spec} $project(design_hierarchy) {
    if {[dict exists $_spec level] && [dict get $_spec level] eq "DL2"} {
        lappend _blk_list $_blk
    }
}
set project(block_list) $_blk_list
unset _blk_list _blk _spec
