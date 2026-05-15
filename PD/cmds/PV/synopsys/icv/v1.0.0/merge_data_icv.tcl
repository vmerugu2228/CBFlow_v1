#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - PV Merge Data Command File
# Description: Merge all PV results and generate unified summary
# Tool: Synopsys ICV
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source -e $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source -e $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/PV/merge_data/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global pv project tech flow
# Source ICV tool config
set _tool_config "[file dirname [info script]]/icv_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PV merge_data with Synopsys ICV..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/merge_data"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# --------------------------------------------------------------------------
# Procedure: merge_all_results
#   Collect results from all PV stages (DRC, LVS, ERC, PERC)
# --------------------------------------------------------------------------
flow_proc merge_all_results {
    global pv project tech
    handle_info "Merging all PV verification results..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pv"

    set ::pv_stage_status {}

    # --- DRC status ---
    set drc_rpt "$run_dir/results/drc/drc_results.rpt"
    set drc_status "NOT_RUN"
    set drc_violations "N/A"
    if {[file exists $drc_rpt]} {
        set fp [open $drc_rpt r]
        set content [read $fp]
        close $fp
        if {[regexp {DRC Status:\s*(\S+)} $content -> st]} { set drc_status $st }
        if {[regexp {Total Violations:\s*(\d+)} $content -> cnt]} {
            set drc_violations $cnt
            if {$cnt == 0 && $drc_status ne "FAIL"} { set drc_status "CLEAN" }
        }
    }
    dict set ::pv_stage_status drc [list status $drc_status violations $drc_violations]

    # --- LVS status ---
    set lvs_rpt "$run_dir/results/lvs/lvs_results.rpt"
    set lvs_status "NOT_RUN"
    set lvs_match "N/A"
    if {[file exists $lvs_rpt]} {
        set fp [open $lvs_rpt r]
        set content [read $fp]
        close $fp
        if {[regexp {LVS_STATUS=(\S+)} $content -> st]} {
            set lvs_match $st
            set lvs_status [expr {$st eq "MATCH" ? "CLEAN" : "FAIL"}]
        }
    }
    dict set ::pv_stage_status lvs [list status $lvs_status match $lvs_match]

    # --- ERC status ---
    set erc_rpt "$run_dir/results/erc/erc_results.rpt"
    set erc_status "NOT_RUN"
    set erc_violations "N/A"
    if {[file exists $erc_rpt]} {
        set fp [open $erc_rpt r]
        set content [read $fp]
        close $fp
        if {[regexp {ERC Status:\s*(\S+)} $content -> st]} { set erc_status $st }
        if {[regexp {Total Violations:\s*(\d+)} $content -> cnt]} {
            set erc_violations $cnt
            if {$cnt == 0 && $erc_status ne "FAIL"} { set erc_status "CLEAN" }
        }
    }
    dict set ::pv_stage_status erc [list status $erc_status violations $erc_violations]

    # --- PERC status ---
    set perc_rpt "$run_dir/results/perc/perc_results.rpt"
    set perc_status "NOT_RUN"
    set perc_violations "N/A"
    if {[file exists $perc_rpt]} {
        set fp [open $perc_rpt r]
        set content [read $fp]
        close $fp
        if {[regexp {PERC Status:\s*(\S+)} $content -> st]} { set perc_status $st }
        if {[regexp {Total Violations:\s*(\d+)} $content -> cnt]} {
            set perc_violations $cnt
            if {$cnt == 0 && $perc_status ne "FAIL"} { set perc_status "CLEAN" }
        }
    }
    dict set ::pv_stage_status perc [list status $perc_status violations $perc_violations]

    handle_info "Stage results merged:"
    handle_info "  DRC:  $drc_status (violations: $drc_violations)"
    handle_info "  LVS:  $lvs_status (match: $lvs_match)"
    handle_info "  ERC:  $erc_status (violations: $erc_violations)"
    handle_info "  PERC: $perc_status (violations: $perc_violations)"
}

# --------------------------------------------------------------------------
# Procedure: generate_pv_summary
#   Generate overall PV pass/fail summary across DRC/LVS/ERC/PERC
# --------------------------------------------------------------------------
flow_proc generate_pv_summary {
    global pv project tech
    handle_info "Generating PV summary report..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set overall "PASS"
    set stages_run 0
    set stages_clean 0
    set stages_fail 0

    dict for {stage info} $::pv_stage_status {
        set st [dict get $info status]
        if {$st ne "NOT_RUN"} {
            incr stages_run
            if {$st eq "CLEAN"} {
                incr stages_clean
            } else {
                incr stages_fail
                set overall "FAIL"
            }
        }
    }

    if {$stages_run == 0} { set overall "INCOMPLETE" }

    set summary "$run_dir/results/pv/pv_summary.rpt"
    set fp [open $summary w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow PV - Physical Verification Summary"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design:     $project(top_module)" }
    if {[info exists project(name)]}       { puts $fp "Project:    $project(name)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool:       Synopsys ICV"
    puts $fp ""
    puts $fp "OVERALL_STATUS=$overall"
    puts $fp "Stages Run:   $stages_run / 4"
    puts $fp "Stages Clean: $stages_clean"
    puts $fp "Stages Fail:  $stages_fail"
    puts $fp ""
    puts $fp "Stage Details:"
    puts $fp "-----------------------------------------------------------------------"

    set drc_info [dict get $::pv_stage_status drc]
    puts $fp [format "  %-8s %-12s Violations: %s" "DRC" [dict get $drc_info status] [dict get $drc_info violations]]

    set lvs_info [dict get $::pv_stage_status lvs]
    puts $fp [format "  %-8s %-12s Match: %s" "LVS" [dict get $lvs_info status] [dict get $lvs_info match]]

    set erc_info [dict get $::pv_stage_status erc]
    puts $fp [format "  %-8s %-12s Violations: %s" "ERC" [dict get $erc_info status] [dict get $erc_info violations]]

    set perc_info [dict get $::pv_stage_status perc]
    puts $fp [format "  %-8s %-12s Violations: %s" "PERC" [dict get $perc_info status] [dict get $perc_info violations]]

    puts $fp ""
    puts $fp "Detailed Reports:"
    foreach rpt [glob -nocomplain "$run_dir/results/drc/*.rpt" "$run_dir/results/lvs/*.rpt" \
                                  "$run_dir/results/erc/*.rpt" "$run_dir/results/perc/*.rpt" \
                                  "$run_dir/reports/pv/*/*.rpt"] {
        set rel [string range $rpt [expr {[string length $run_dir] + 1}] end]
        puts $fp "  $rel"
    }
    close $fp

    set rpt_copy "$run_dir/reports/pv/pv_merged_summary.rpt"
    file mkdir [file dirname $rpt_copy]
    catch {file copy -force $summary $rpt_copy}

    handle_info "PV summary: $summary"
    handle_info "PV overall status: $overall"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all merge_all_results generate_pv_summary
exit
