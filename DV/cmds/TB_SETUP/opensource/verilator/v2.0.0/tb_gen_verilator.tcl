#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow TB_SETUP — tb_gen (opensource / container tclsh)
# UVM testbench from the spec (DV/utils/oss/uvmgen.py): spec, register model,
# vPlan and RTL filelist staged by the input nodes; the user-owned files of
# tb_setup(oss,tb_dir) replace generated ones; the library tag's memory models
# (fixed for simulation by DFT/utils/oss/oss_dft.py model-fix, quiet) travel
# with the TB -> outputs/tb/ (tb.f, rtl.f), reports/tb_gen.rpt.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "TB_SETUP"
set STAGE_NAME "tb_gen"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_DV_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dv_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"
flow_proc generate {
    if {[llength [hier_children $::design_name]]} {
        error "$::design_name has child blocks ([hier_children $::design_name]) — uvmgen builds block-level testbenches only"
    }
    set _models {}
    foreach _m [oss_memory_files verilog] {
        set _o "$::WORK_DIR/models/[file tail $_m]"
        file mkdir [file dirname $_o]
        oss_py "$::REPORTS_DIR/model_fix.log" "$::env(CBFLOW_DFT_DIR)/utils/oss/oss_dft.py" model-fix --model $_m -o $_o
        set _fh [open $_o]; set _t [read $_fh]; close $_fh
        oss_write_file $_o [regsub -all {parameter\s+VERBOSE\s*=\s*1} $_t {parameter VERBOSE = 0}]
        lappend _models $_o
    }
    set _ud [oss_get_opt tb_setup oss,tb_dir]
    if {$_ud ne "" && ![file isdirectory $_ud]} { error "tb_setup(oss,tb_dir): $_ud not found" }
    uvmgen "$::REPORTS_DIR/uvmgen.log" gen --spec [oss_input spec] --ral [oss_input ral] --rtl-f [oss_input rtl] \
        --vplan [oss_input vplan] {*}[expr {$_ud ne "" ? [list --user-dir $_ud] : {}}] \
        {*}[expr {[llength $_models] ? [list --models {*}$_models] : {}}] \
        -o [oss_stage_out tb] --report "$::REPORTS_DIR/tb_gen.rpt"
    oss_write_file [oss_stage_out tb_gen.status] "DONE\n"
    handle_info "testbench -> [oss_stage_out tb] ([oss_report_value $::REPORTS_DIR/tb_gen.rpt {Test stubs}] test stub(s))"
}

oss_exec_all
exit
