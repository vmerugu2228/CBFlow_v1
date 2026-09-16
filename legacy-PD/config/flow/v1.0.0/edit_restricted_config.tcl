#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Edit Restricted Configuration
# Variables that users should NOT modify — controlled by leads/CAD team
#
# Each entry is a glob pattern matched against the variable name on `set` lines
# in user_config.tcl. `*` matches any single key segment so per-metal-stack /
# per-track / per-RC-corner schemas need just one rule.
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Flow Infrastructure (do not change) ───────────────────────────────────────┐
set restricted_flow_variables {
    "flow(types)"
    "flow(run_types)"
    "project(phases)"
    "flow(exit_milestones)"
    "flow(valid_status)"
    "flow(status_file)"
    "flow(mandatory_vars,all)"
    "flow(mmmc,enabled)"
}

# ┌─ Technology Identity (foundry-defined, do not change) ──────────────────────┐
set restricted_tech_variables {
    "tech(node)"
    "tech(process)"
    "tech(foundry)"
    "project(metal_stack)"
    "tech(tracks_available)"
    "tech(metal_stacks_available)"
    "tech(*,tluplus_map)"
    "tech(*,*,lef_tech)"
}

# ┌─ Tool Selection (controlled by CAD team) ──────────────────────────────────┐
# Each per-flow array also declares supported_tools internally; the rules below
# block users from overriding the selection via user_config.tcl.
set restricted_tool_variables {
    "synth_pnr(supported_tools)"
    "synth(supported_tools)"
    "pnr(supported_tools)"
    "fp(supported_tools)"
    "fcfp(supported_tools)"
    "sta(supported_tools)"
    "pv(supported_tools)"
    "lec(supported_tools)"
    "clp(supported_tools)"
    "emir(supported_tools)"
    "eco(supported_tools)"
    "popt(supported_tools)"
}

# ┌─ RC Corner Parasitics (signoff-critical) ──────────────────────────────────┐
# Schema is tech(rcx,<metal_stack>,<rc_corner>,<format>) — glob covers all stacks.
set restricted_rc_variables {
    "tech(rcx,*,rc_max,tluplus)"
    "tech(rcx,*,rc_max,qrc)"
    "tech(rcx,*,rc_max,nxtgrd)"
    "tech(rcx,*,rc_typ,tluplus)"
    "tech(rcx,*,rc_typ,qrc)"
    "tech(rcx,*,rc_typ,nxtgrd)"
    "tech(rcx,*,rc_min,tluplus)"
    "tech(rcx,*,rc_min,qrc)"
    "tech(rcx,*,rc_min,nxtgrd)"
}

# ┌─ MMMC Corners & PVT Building Blocks (signoff-critical) ────────────────────┐
# PVT is set per process corner as {voltage temperature} pairs; rc_pair maps
# each process corner to its parasitic corner.
set restricted_mmmc_variables {
    "mmmc(process_corners)"
    "mmmc(pvt,ss)"
    "mmmc(pvt,tt)"
    "mmmc(pvt,ff)"
    "mmmc(rc_pair,ss)"
    "mmmc(rc_pair,tt)"
    "mmmc(rc_pair,ff)"
}

# ┌─ Release Milestones (controlled by leads) ─────────────────────────────────┐
set restricted_release_variables {
    "MILESTONE_STAGE_MAPPING(FP_EXIT)"
    "MILESTONE_STAGE_MAPPING(PLACE_EXIT)"
    "MILESTONE_STAGE_MAPPING(CTS_EXIT)"
    "MILESTONE_STAGE_MAPPING(PRO_EXIT)"
    "MILESTONE_STAGE_MAPPING(BTO)"
    "MILESTONE_STAGE_MAPPING(MTO)"
}

# Combine all restricted patterns
set all_restricted_variables [concat \
    $restricted_flow_variables \
    $restricted_tech_variables \
    $restricted_tool_variables \
    $restricted_rc_variables \
    $restricted_mmmc_variables \
    $restricted_release_variables \
]

# ┌─ Validation ────────────────────────────────────────────────────────────────┐

proc _matches_restricted {var_name patterns} {
    foreach pat $patterns {
        if {[string match $pat $var_name]} { return 1 }
    }
    return 0
}

proc check_file_for_restrictions {filename} {
    global all_restricted_variables
    set violations {}
    if {![file exists $filename]} { return $violations }
    set fd [open $filename "r"]
    set line_num 0
    while {[gets $fd line] >= 0} {
        incr line_num
        set line [string trim $line]
        if {[string match "#*" $line] || $line eq ""} { continue }
        if {[regexp {^\s*set\s+([^\s]+)\s+} $line -> var_name]} {
            if {[_matches_restricted $var_name $all_restricted_variables]} {
                lappend violations "$filename:$line_num — $var_name"
            }
        }
    }
    close $fd
    return $violations
}

proc validate_variable_restrictions {} {
    global all_restricted_variables
    set violations {}
    foreach config_file {"user_config.tcl" "setup/user_config.tcl"} {
        if {[file exists $config_file]} {
            set violations [concat $violations [check_file_for_restrictions $config_file]]
        }
    }
    if {[llength $violations] > 0} {
        puts "ERROR: Restricted variables modified without authorization:"
        foreach v $violations { puts "       $v" }
        puts "       Contact CAD team or project lead for approval."
        return false
    }
    return true
}
