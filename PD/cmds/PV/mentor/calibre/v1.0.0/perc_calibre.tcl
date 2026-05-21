#!/usr/bin/env tclsh
# CBFlow PV PERC - Mentor Calibre

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "perc"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc run_perc_checks {
    handle_info "Running PERC checks..."
    file mkdir "results/perc" ; file mkdir "reports/phyv/perc"
    puts "Running reliability checks..."; calibre -perc -reliability > "$::REPORTS_DIR/reliability.rpt"
    puts "Running ESD protection checks..."; calibre -perc -esd > "$::REPORTS_DIR/esd.rpt"
    puts "Running latch-up checks..."; calibre -perc -latchup > "$::REPORTS_DIR/latchup.rpt"
    puts " PERC checks completed"
}

flow_proc generate_perc_report {
    global phyv project tech
    handle_info "Generating PERC report..."
    set rpt "$::REPORTS_DIR/perc_results.rpt"
    set fp [open $rpt w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - PERC Results"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp "Tool: Mentor Calibre\n"
    puts $fp "Reports: reports/phyv/perc/reliability.rpt, esd.rpt, latchup.rpt"
    close $fp
    puts " PERC report: $rpt"
}

flow_proc perc_flow {
    handle_info "Executing PERC flow..."
    flow_exec run_perc_checks
    flow_exec generate_perc_report
    handle_info " PERC Complete! Results: results/perc/perc_results.rpt"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec perc_flow } else { puts " PV PERC procedures loaded" }

# Exit tool after stage completion
exit
