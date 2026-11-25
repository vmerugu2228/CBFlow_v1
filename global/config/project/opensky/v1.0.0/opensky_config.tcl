#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — opensky
# GLOBAL layer (cross-discipline identity)
#
# Open-source RTL-to-GDS proof project: SkyWater SKY130 (sky130A,
# sky130_fd_sc_hd) with the "opensource" vendor tool stack — Yosys,
# OpenROAD, OpenSTA, Magic, Netgen, KLayout — run through global/bin/cbflow-oss.
# =============================================================================

set project(name)            "opensky"
set project(phases)          {P0 P1 P2 P3}
set project(current_phase)   "P0"

# ── Power grid — FP builds the PDN when enabled. false (per block / run in its
# user_config) keeps supplies as logical nets only, no grid shapes, power
# checks skipped — signal-routing bring-up.
set project(pdn,enable)              true

# ── DFT (scan) — SYNTH inserts scan chains when enabled (OpenROAD DFT in the
# open-source flow). A block / run turns it off with project(dft,enable) false
# in its user_config or override_config.tcl.
set project(dft,enable)              true
set project(dft,max_chain_length)    100       ;# scan flops per chain
set project(dft,clock_mixing)        no_mix    ;# no_mix | clock_mix
set project(dft,scan_enable_pattern) scan_enable_*   ;# ports DFT adds (SDC case analysis)
# Exits each phase delivers (order from MILESTONE_ORDER in PD release_config.tcl).
# Drives the schedule, the SmartGrid publish order and the default release tag
# (release tag = exit name unless project(release,tag) is set).
set project(phase_exits) {
    P0 {FP_EXIT PRO_EXIT}
    P1 {FP_EXIT PRO_EXIT}
    P2 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
    P3 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
}
# Per-discipline exit plans: project(phase_exits,<DISC>) — exits of that
# discipline (milestone_info(discipline)) each phase delivers, in release order
# (the exit-order gate checks them within the discipline; the PD plan above is
# not affected). DV: TB setup + M1 / M2 close in P1, M3 / M4 + DV sign-off in
# P2; P3 (the spec-to-GDS pilot) runs the whole DV ladder.
set project(phase_exits,DV) {
    P0 {}
    P1 {TB_SETUP_EXIT M1_EXIT M2_EXIT}
    P2 {M3_EXIT M4_EXIT DV_SIGNOFF_EXIT}
    P3 {TB_SETUP_EXIT M1_EXIT M2_EXIT M3_EXIT M4_EXIT DV_SIGNOFF_EXIT}
}
set project(version)         "1.0"
set project(cbflow_release)  "v1.0.0"
set project(description)     "Open-source RTL-to-GDS proof on SkyWater SKY130"
set project(owner)           "SmartSoC CAD"
set project(contact)         "varun@smartsocs.com"

set project(technology)      "skywater_130nm"
set project(vt_flavors)      "svt"
set project(top_module)      "opensky_chip"

# SDC modes (file naming: <design_name>.<mode>.sdc)
set project(sdc_modes)        {func}
set project(default_sdc_mode) "func"

# Power & ground nets (sky130_fd_sc_hd pins: VPWR/VPB, VGND/VNB)
set project(power,vdd_net) "VPWR"
set project(power,vss_net) "VGND"
set project(power,vdd_pin) "VPWR"
set project(power,vss_pin) "VGND"

# Chip rail cycle for the hierarchical power grid: every block that exports
# horizontal-strap power pins (DL2) carries ALL of these nets in this order,
# so the DL1 straps abut the same net on every DL2 macro. Nets a block does
# not use are feedthrough rails (declared as supply ports in its UPF).
set project(power,rail_nets) {VPWR VGND VPWR_GCD VPWR_MAC}

set project(tapeout_date)  "2027-03-31"
set project(analog_blocks) ""

# Physical hierarchy — built bottom-up: each DL3 block is hardened first
# (GDS + abstract LEF + timing lib), each DL2 integrates its DL3 children as
# hard macros, and the DL1 chip integrates the DL2 subsystems.
set project(design_hierarchy) {
    opensky_chip {
        description "Full chip top level — host bus + reset sync (DL1)"
        level       "DL1"
        parent      ""
        children    {ctrl_subsys ai_subsys}
    }
    ctrl_subsys {
        description "Host-bus front end, registers, IRQ (DL2)"
        level       "DL2"
        parent      "opensky_chip"
        children    {gcd}
    }
    ai_subsys {
        description "AI accelerator subsystem — operand loader + result window (DL2)"
        level       "DL2"
        parent      "opensky_chip"
        children    {mac_array}
    }
    gcd {
        description "16-bit GCD engine (DL3)"
        level       "DL3"
        parent      "ctrl_subsys"
        children    {}
    }
    mac_array {
        description "16x16 int8 systolic MAC array, ~139k cells (DL3)"
        level       "DL3"
        parent      "ai_subsys"
        children    {}
    }
}
set project(valid_design_names) [dict keys $project(design_hierarchy)]

# Derived: DL2 subsystems of design_hierarchy.
set _blk_list {}
dict for {_blk _spec} $project(design_hierarchy) {
    if {[dict exists $_spec level] && [dict get $_spec level] eq "DL2"} {
        lappend _blk_list $_blk
    }
}
set project(block_list) $_blk_list
unset _blk_list _blk _spec
