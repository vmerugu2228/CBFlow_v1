#!/usr/bin/env tclsh
# CBFlow PV DRC - Mentor Calibre

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "drc"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc run_drc_checks {
    handle_info "Running DRC checks..."
    file mkdir "results/drc" ; file mkdir "reports/phyv/drc"
    puts "Running spacing checks..."; calibre -drc -spacing > "$::REPORTS_DIR/spacing.rpt"
    puts "Running width checks...";   calibre -drc -width > "$::REPORTS_DIR/width.rpt"
    puts "Running density checks..."; calibre -drc -density > "$::REPORTS_DIR/density.rpt"
    puts "Running via checks...";     calibre -drc -via > "$::REPORTS_DIR/via.rpt"
    puts " DRC checks completed"
}

flow_proc generate_drc_report {
    global phyv project tech
    handle_info "Generating DRC report..."
    set rpt "$::REPORTS_DIR/drc_results.rpt"
    set fp [open $rpt w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow PV - DRC Results"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool: Mentor Calibre\n"
    puts $fp "Reports: reports/phyv/drc/spacing.rpt, width.rpt, density.rpt, via.rpt"
    close $fp
    puts " DRC report: $rpt"
}

flow_proc drc_flow {
    handle_info "Executing DRC flow..."
    flow_exec run_drc_checks
    flow_exec generate_drc_report
    handle_info " DRC Complete! Results: results/drc/drc_results.rpt"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec drc_flow } else { puts " PV DRC procedures loaded" }

# Exit tool after stage completion
exit
