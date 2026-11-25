#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_SPEC — gen_regs (opensource / container tclsh)
# Register collateral from SystemRDL (PeakRDL): the register block RTL
# (regblock + package, CPU interface rtl_spec(oss,regs,cpuif)), the UVM
# register model, the C header, the IP-XACT memory map and HTML docs. The
# register RTL is converted with sv2v and read by yosys (synthesizable for
# the open-source flow). A spec without registers writes regs.status NONE.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_SPEC"
set STAGE_NAME "gen_regs"
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

flow_proc generate {
    set _rdl "[cbflow_node_dir [oss_chain_node spec_check]]/outputs/regs.rdl"
    if {![file exists $_rdl]} {
        oss_write_file [oss_stage_out regs.status] "NONE\n"
        handle_info "spec has no register interface — no register collateral"
        return
    }
    oss_py "$::REPORTS_DIR/peakrdl.log" $::spec_tool regs --rdl $_rdl --out [oss_stage_out regs] \
        --cpuif [oss_get rtl_spec oss,regs,cpuif]
    # the register RTL must survive SystemVerilog -> Verilog and yosys
    set _sv [lsort [glob [oss_stage_out regs/rtl]/*.sv]]
    set _pk [lsearch -all -inline $_sv *_pkg.sv]
    set _files [concat $_pk [lsearch -all -inline -not $_sv *_pkg.sv]]
    oss_run "$::REPORTS_DIR/sv2v.log" sh -c "sv2v [join $_files] > [oss_stage_out regs/regs_sv2v.v]"
    oss_run "$::REPORTS_DIR/regs_yosys.log" yosys -q -p "read_verilog [oss_stage_out regs/regs_sv2v.v]; hierarchy -check; proc; stat"
    set _fh [open [oss_stage_out regs/regs.json]]; set _j [read $_fh]; close $_fh
    regexp {"registers":\s*(\d+)} $_j -> _n
    oss_write_file [oss_stage_out regs.status] "GENERATED $_n\n"
    handle_info "register block: $_n registers ([join [lmap f $_files {file tail $f}] {, }])"
}

oss_exec_all
exit
