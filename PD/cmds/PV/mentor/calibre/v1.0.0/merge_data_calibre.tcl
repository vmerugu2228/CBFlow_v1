#!/usr/bin/env tclsh
# CBFlow PV merge_data - Mentor Calibre

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

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
    file mkdir "$run_dir/results/verification"

    # Scan the real per-node work dirs ($run_dir/work/PV/<node>1/results/<x>/)
    # and emit the summary at BOTH the legacy (phyv) and the declared
    # (verification) paths — mandatory_outputs,merge_data1 declares
    # results/verification/verification_summary.rpt.
    set summary_body ""
    append summary_body "═══════════════════════════════════════════════════════════════════════════════\n"
    append summary_body "CBFlow PV - Physical Verification Summary\n"
    append summary_body "═══════════════════════════════════════════════════════════════════════════════\n"
    append summary_body "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\n"
    if {[info exists project(top_module)]} { append summary_body "Design: $project(top_module)\n" }
    if {[info exists project(name)]} { append summary_body "Project: $project(name)\n" }
    if {[info exists tech(node)]} { append summary_body "Technology: $tech(node)\n" }
    append summary_body "\nTool: Mentor Calibre\n\n"

    # Check each verification stage at its real work-dir location.
    foreach {stage node_name file label} {
        drc      drc1      drc.rpt       "DRC (Design Rule Check)"
        lvs      lvs1      lvs.rpt       "LVS (Layout vs Schematic)"
        erc      erc1      erc.rpt       "ERC (Electrical Rule Check)"
        perc     perc1     perc.rpt      "PERC (Parasitic Extraction Rule Check)"
        perc_ldl perc_ldl1 perc_ldl.rpt  "PERC-LDL (Leakage-Driven Layout)"
    } {
        set work_candidate "$run_dir/work/PV/$node_name/results/$stage/$file"
        set run_candidate  "$run_dir/results/$stage/$file"
        set found ""
        if {[file exists $work_candidate]} {
            set found $work_candidate
        } elseif {[file exists $run_candidate]} {
            set found $run_candidate
        }
        if {$found ne ""} {
            append summary_body "  $label: COMPLETED - $found\n"
        } else {
            append summary_body "  $label: PENDING - $stage/$file not found\n"
        }
    }

    append summary_body "\nDetailed Reports:\n"
    foreach rpt [glob -nocomplain "$run_dir/reports/phyv/*/*.rpt" "$run_dir/reports/phyv/*.rpt"] {
        set rel [string range $rpt [expr {[string length $run_dir] + 1}] end]
        append summary_body "  $rel\n"
    }

    # Atomic writes so a crash doesn't leave the merge summary truncated.
    atomic_write "$run_dir/results/phyv/phyv_summary.rpt" $summary_body
    atomic_write "$run_dir/results/verification/verification_summary.rpt" $summary_body

    puts " Merged summary: $run_dir/results/verification/verification_summary.rpt"
}

flow_proc merge_data_flow {
    handle_info "Executing merge data flow..."
    flow_exec merge_verification_results
    handle_info "PV merge data completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec merge_data_flow } else { puts " PV merge data procedures loaded" }

# Exit tool after stage completion
exit
