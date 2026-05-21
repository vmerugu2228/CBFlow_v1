#!/usr/bin/env tclsh
# CBFlow PV LVS - Mentor Calibre

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "lvs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc run_lvs_comparison {
    handle_info "Running LVS comparison..."
    file mkdir "results/lvs" ; file mkdir "reports/phyv/lvs"
    puts "Extracting layout netlist..."; calibre -lvs -extract > "$::REPORTS_DIR/extract.rpt"
    puts "Comparing layout vs schematic..."; calibre -lvs -compare > "$::REPORTS_DIR/comparison.rpt"
    puts " LVS comparison completed"
}

flow_proc generate_lvs_report {
    global phyv project tech
    handle_info "Generating LVS report..."
    set rpt "$::REPORTS_DIR/lvs_results.rpt"
    set fp [open $rpt w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - LVS Results"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp "Tool: Mentor Calibre\n"
    puts $fp "Reports: reports/phyv/lvs/extract.rpt, comparison.rpt"
    close $fp
    puts " LVS report: $rpt"
}

flow_proc lvs_flow {
    handle_info "Executing LVS flow..."
    flow_exec run_lvs_comparison
    flow_exec generate_lvs_report
    handle_info " LVS Complete! Results: results/lvs/lvs_results.rpt"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec lvs_flow } else { puts " PV LVS procedures loaded" }

# Exit tool after stage completion
exit
