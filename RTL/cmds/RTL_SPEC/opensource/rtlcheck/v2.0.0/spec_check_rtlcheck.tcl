#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_SPEC — spec_check (opensource / container tclsh)
# Block spec check: the YAML spec (CBflow spec schema v1) — required fields,
# ports / clocks / resets / interfaces consistent, APB signals present, power
# domains, RTL sources and the register source found, features — written as
# the normalized spec.json; the register source (SystemRDL, or an XLS
# register sheet converted to SystemRDL) as regs.rdl.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_SPEC"
set STAGE_NAME "spec_check"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
set spec_tool "$::env(CBFLOW_RTL_DIR)/utils/oss/spec_tool.py"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc check {
    set ::spec [oss_input spec]
    handle_info "spec $::spec"
    oss_py "$::REPORTS_DIR/spec_check.log" $::spec_tool check --spec $::spec -o [oss_stage_out spec.json] \
        --report "$::REPORTS_DIR/spec_check.rpt" --rdl-out [oss_stage_out regs.rdl]
}

flow_proc report {
    set _r "$::REPORTS_DIR/spec_check.rpt"
    handle_info "spec: [oss_report_value $_r Ports] ports, [oss_report_value $_r Features] features,\
                 [oss_report_value $_r Errors] errors, [oss_report_value $_r Warnings] warnings"
    if {[file exists [oss_stage_out regs.rdl]]} { handle_info "registers: [oss_stage_out regs.rdl]" }
}

oss_exec_all
exit
