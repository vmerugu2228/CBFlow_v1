#!/usr/bin/env tclsh
# CBFlow PV merge_data - Mentor Calibre

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "merge_data"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc merge_verification_results {
    global phyv project tech flow
    handle_info "Merging all verification results..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/phyv"

    set summary_file "$run_dir/results/phyv/phyv_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - Physical Verification Summary"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
    puts $fp "\nTool: Mentor Calibre\n"

    # Check each verification stage
    foreach {stage dir label} {
        drc "results/drc/drc_results.rpt" "DRC (Design Rule Check)"
        lvs "results/lvs/lvs_results.rpt" "LVS (Layout vs Schematic)"
        erc "results/erc/erc_results.rpt" "ERC (Electrical Rule Check)"
        perc "results/perc/perc_results.rpt" "PERC (Parasitic Extraction Rule Check)"
    } {
        set full_path "$run_dir/$dir"
        if {[file exists $full_path]} {
            puts $fp "  $label: COMPLETED - $dir"
        } else {
            puts $fp "  $label: PENDING - $dir"
        }
    }

    puts $fp "\nDetailed Reports:"
    foreach rpt [glob -nocomplain "$run_dir/reports/phyv/*/*.rpt" "$run_dir/reports/phyv/*.rpt"] {
        set rel [string range $rpt [expr {[string length $run_dir] + 1}] end]
        puts $fp "  $rel"
    }
    close $fp

    puts " Merged summary: $summary_file"
}

flow_proc merge_data_flow {
    handle_info "Executing merge data flow..."
    flow_exec merge_verification_results
    handle_info "PV merge data completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec merge_data_flow } else { puts " PV merge data procedures loaded" }

# Exit tool after stage completion
exit
