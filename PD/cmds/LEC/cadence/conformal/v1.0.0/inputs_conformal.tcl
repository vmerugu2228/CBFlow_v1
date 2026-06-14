#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC — Cadence Conformal — Inputs Stage
# Read golden and revised netlists
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "LEC"
set STAGE_NAME "inputs"
set NODE_NAME "inputs1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ── Resolve any release-tag / from_run inputs declared in user_config ─────
# (golden/revised netlists may be supplied directly or via a release tag)
set _release_utils "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} {
    source $_release_utils
    if {[info procs resolve_inputs] ne ""} {
        resolve_inputs LEC
    }
}

# ── Read golden netlist ───────────────────────────────────────────────────
flow_proc read_golden_netlist {
    handle_info "Reading golden reference netlist..."

    set _golden $::lec(input,netlist_golden)
    if {$_golden eq ""} { error "lec(input,netlist_golden) not set" }
    if {![file exists $_golden]} { error "Golden netlist not found: $_golden" }

    read_library -golden -both $::lec(input,netlist_golden)
    read_design -golden $::lec(input,netlist_golden) -file verilog

    handle_info "Golden netlist loaded: $_golden"
}

# ── Read revised netlist ──────────────────────────────────────────────────
flow_proc read_revised_netlist {
    handle_info "Reading revised implementation netlist..."

    set _revised $::lec(input,netlist_revised)
    if {$_revised eq ""} { error "lec(input,netlist_revised) not set" }
    if {![file exists $_revised]} { error "Revised netlist not found: $_revised" }

    read_design -revised $::lec(input,netlist_revised) -file verilog

    handle_info "Revised netlist loaded: $_revised"
}

# ── Validate inputs ───────────────────────────────────────────────────────
flow_proc validate_inputs {
    handle_info "Validating LEC inputs..."

    if {![info exists ::lec(input,netlist_golden)] || $::lec(input,netlist_golden) eq ""} {
        error "Missing: lec(input,netlist_golden)"
    }
    if {![info exists ::lec(input,netlist_revised)] || $::lec(input,netlist_revised) eq ""} {
        error "Missing: lec(input,netlist_revised)"
    }

    handle_info "Inputs validated"
}

flow_exec_all
