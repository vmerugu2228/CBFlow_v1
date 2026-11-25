#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow UPF_CHECK — compile (opensource / container tclsh)
# The RTL elaborated from the top by yosys-slang -> design.json (instances the
# UPF elements are checked against).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "UPF_CHECK"
set STAGE_NAME "compile"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_RTL_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_rtl_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc elaborate {
    oss_run "$::REPORTS_DIR/elaborate.log" yosys -q -p "plugin -i slang; read_slang --top [rtl_top] [rtl_init_out stubs.v] [join [rtl_init_sources]]; hierarchy -top [rtl_top]; proc; write_json [oss_stage_out design.json]; stat"
    oss_write_file [oss_stage_out compile.status] "PASS\n"
    handle_info "RTL elaborated (yosys-slang) -> design.json"
}

oss_exec_all
exit
