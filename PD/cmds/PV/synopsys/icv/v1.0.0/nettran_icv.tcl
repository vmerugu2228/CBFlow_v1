#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV nettran — Synopsys ICV
# Translates the source netlist into an LVS-ready format (SPICE / hierarchical
# CDL) that feeds into lvs1. Sits between netlist1 (raw input) and lvs1.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$::env(CBFLOW_RUN_DIR)/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "nettran"
set NODE_NAME "${STAGE_NAME}1"

source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$::env(CBFLOW_RUN_DIR)/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $::env(CBFLOW_RUN_DIR) $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc configure_nettran {
    global pv project tech
    handle_info "Configuring netlist translation..."

    # Source netlist (raw Verilog gate-level from netlist1 stage)
    if {[info exists pv(input,netlist)] && $pv(input,netlist) ne ""} {
        set ::nettran_source $pv(input,netlist)
    } else {
        handle_error "No source netlist — set pv(input,netlist) in user_config"
        return
    }

    # Output format: default is SPICE for LVS
    set ::nettran_output_format [expr {[info exists pv(nettran,output_format)] ? \
                                       $pv(nettran,output_format) : "spice"}]

    # Include library models (for cell-level LVS)
    set ::nettran_lib_models [expr {[info exists pv(nettran,lib_models)] ? \
                                    $pv(nettran,lib_models) : ""}]

    set ::nettran_out "$::WORK_DIR/results/lvs_source.${::nettran_output_format}"

    handle_info "Netlist translation configuration:"
    handle_info "  Source:      $::nettran_source"
    handle_info "  Output fmt:  $::nettran_output_format"
    handle_info "  Output file: $::nettran_out"
}

# ---------------------------------------------------------------------------
flow_proc run_nettran {
    set ::nettran_status "PASS"
    handle_info "Running netlist translation with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::WORK_DIR/results"
    file mkdir "$::REPORTS_DIR"

    set icv_cmd "icv -nettran -i $::nettran_source -o $::nettran_out"
    append icv_cmd " -format $::nettran_output_format"
    if {$::nettran_lib_models ne ""} {
        append icv_cmd " -lib $::nettran_lib_models"
    }
    append icv_cmd " -log $::env(CBFLOW_RUN_DIR)/logs/pv/nettran_icv.log"

    handle_info "ICV command: $icv_cmd"
    if {[catch {eval exec $icv_cmd} _result]} {
        handle_warning "ICV nettran failed: $_result"
        set ::nettran_status "FAIL"
    } else {
        set ::nettran_status "PASS"
        handle_info "Netlist translation completed"
    }
}

# ---------------------------------------------------------------------------
flow_proc report_nettran {
    set rpt_dir "$::REPORTS_DIR"
    file mkdir $rpt_dir

    set fp [open "$rpt_dir/nettran_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "Netlist Translation Summary — Synopsys ICV"
    puts $fp "================================================================"
    puts $fp "Source netlist: $::nettran_source"
    puts $fp "Output file:    $::nettran_out"
    puts $fp "Output format:  $::nettran_output_format"
    puts $fp "Status:         $::nettran_status"
    puts $fp "================================================================"
    close $fp
    handle_info "Netlist translation report written: $rpt_dir/nettran_summary.rpt"
}

# ---------------------------------------------------------------------------
flow_proc nettran_flow {
    handle_info "Executing PV netlist translation flow..."
    flow_exec configure_nettran
    flow_exec run_nettran
    flow_exec report_nettran
    handle_info "PV netlist translation completed"
    # Propagate failure to RACE: run_nettran uses handle_warning so the
    # report step still runs, but we must exit non-zero here or RACE marks
    # the job PASS while ICV actually crashed.
    if {[info exists ::nettran_status] && $::nettran_status eq "FAIL"} {
        handle_error "nettran failed — see $::REPORTS_DIR/nettran_summary.rpt"
    }
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec nettran_flow } else { puts " PV nettran procedures loaded" }
exit
