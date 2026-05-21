#!/usr/bin/env tclsh
# CBFlow PV ERC - Mentor Calibre

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "erc"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc run_erc_checks {
    handle_info "Running ERC checks..."
    file mkdir "results/erc" ; file mkdir "reports/phyv/erc"
    puts "Running power connectivity checks..."; calibre -erc -power > "$::REPORTS_DIR/power.rpt"
    puts "Running ground connectivity checks..."; calibre -erc -ground > "$::REPORTS_DIR/ground.rpt"
    puts "Running floating net checks..."; calibre -erc -floating > "$::REPORTS_DIR/floating.rpt"
    puts " ERC checks completed"
}

flow_proc generate_erc_report {
    global phyv project tech
    handle_info "Generating ERC report..."
    set rpt "$::REPORTS_DIR/erc_results.rpt"
    set fp [open $rpt w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - ERC Results"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp "Tool: Mentor Calibre\n"
    puts $fp "Reports: reports/phyv/erc/power.rpt, ground.rpt, floating.rpt"
    close $fp
    puts " ERC report: $rpt"
}

flow_proc erc_flow {
    handle_info "Executing ERC flow..."
    flow_exec run_erc_checks
    flow_exec generate_erc_report
    handle_info " ERC Complete! Results: results/erc/erc_results.rpt"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec erc_flow } else { puts " PV ERC procedures loaded" }

# Exit tool after stage completion
exit
