#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_SPEC — gen_collateral (opensource / container tclsh)
# Design collateral from the spec: SDC (clocks, IO delays, load), UPF (power
# domains), the RTL filelist (register block + designer RTL), the initial
# verification plan (XLS, rtl_spec(oss,vplan,generate)), and the RTL top
# checked against the spec's ports and memories (sv2v + yosys; memories /
# child blocks from the library tag as blackboxes; spec memories instantiated
# with their macro, memory macros declared in the spec and in the tag).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "RTL_SPEC"
set STAGE_NAME "gen_collateral"
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
    global design_name
    set _sc "[cbflow_node_dir [oss_chain_node spec_check]]/outputs/spec.json"
    set _rg "[cbflow_node_dir [oss_chain_node gen_regs]]/outputs/regs"
    set _regs [expr {[file isdirectory $_rg] ? [list --regs $_rg] : {}}]
    oss_py "$::REPORTS_DIR/collateral.log" $::spec_tool sdc --spec $_sc -o [oss_stage_out design.sdc]
    set _fh [open $_sc]; set _sj [read $_fh]; close $_fh
    if {[regexp {"power":\s*\{} $_sj]} {
        oss_py "$::REPORTS_DIR/collateral.log" $::spec_tool upf --spec $_sc -o [oss_stage_out design.upf]
    }
    oss_py "$::REPORTS_DIR/collateral.log" $::spec_tool filelist --spec $_sc {*}$_regs -o [oss_stage_out design.f]
    if {[is_true [oss_get rtl_spec oss,vplan,generate]]} {
        oss_py "$::REPORTS_DIR/collateral.log" $::spec_tool vplan-init --spec $_sc -o [oss_stage_out vplan.xlsx]
    }
}

flow_proc check_ports {
    global design_name
    set _sc "[cbflow_node_dir [oss_chain_node spec_check]]/outputs/spec.json"
    set _fh [open [oss_stage_out design.f]]; set _files [split [string trim [read $_fh]] \n]; close $_fh
    set _fh [open $_sc]; set _sj [read $_fh]; close $_fh
    if {![regexp {"top":\s*"([^"]+)"} $_sj -> _top]} { error "rtl.top missing in $_sc" }
    set _v "$::WORK_DIR/run/design_sv2v.v"
    oss_run "$::REPORTS_DIR/sv2v.log" sh -c "sv2v [join $_files] > $_v"
    # memories / child blocks as blackboxes (port directions), then the RTL
    set _cmds {}
    foreach _m [oss_memory_files verilog] { lappend _cmds "read_verilog -lib $_m" }
    foreach _b [hier_children $design_name] { lappend _cmds "read_verilog -lib [dict get [hier_block_views $_b] netlist]" }
    lappend _cmds "read_verilog $_v" "hierarchy -top $_top" "proc" "write_json $::WORK_DIR/run/design.json"
    oss_run "$::REPORTS_DIR/ports_yosys.log" yosys -q -p [join $_cmds "; "]
    oss_py "$::REPORTS_DIR/ports.log" $::spec_tool ports --spec $_sc --json "$::WORK_DIR/run/design.json" \
        --memory-macros {*}[oss_memory_cells] --report "$::REPORTS_DIR/ports.rpt"
}

oss_exec_all
exit
