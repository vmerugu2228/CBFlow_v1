#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SYNTH — synthesis (opensource / yosys)
# Read the RTL filelist (library cells and child blocks as blackboxes —
# children come from the library tag), elaborate, synthesize and map to the
# active track's cells on the node's first lib set; netlist + area report.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "synthesis"
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "synthesis1"}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc read_design {
    global design_name blocks synth
    set _lib_set [lindex [oss_node_lib_sets $::NODE_NAME] 0]
    set ::oss_libs [oss_lib_set_files $_lib_set]
    handle_info "Mapping library set: $_lib_set"
    # Cell library as blackboxes: RTL may instantiate library cells directly.
    foreach _l $::oss_libs { yosys read_liberty -lib $_l }
    set _fl "$::RTL_DIR/${design_name}.f"
    if {![file exists $_fl]} { error "RTL filelist not staged: $_fl (synth(input,rtl_filelist) must be <design>.f)" }
    set _sv [expr {[oss_get synth input,rtl_format] eq "sverilog" ? "-sv" : ""}]
    set _fh [open $_fl]
    foreach _src [split [read $_fh] "\n"] {
        set _src [string trim $_src]
        if {$_src eq "" || [string match "#*" $_src] || [string match "//*" $_src]} continue
        handle_info "  RTL: $_src"
        yosys read_verilog {*}$_sv -defer $_src
    }
    close $_fh
    # Hard-macro children: interface only, from the library tag.
    foreach _b $blocks {
        set _v [hier_block_views $_b]
        handle_info "  child block $_b ([hier_level $_b]) from [dict get $_v release]"
        yosys read_verilog -lib [dict get $_v netlist]
    }
    yosys hierarchy -check -top $design_name
    yosys tee -o "$::REPORTS_DIR/synthesis_hierarchy.rpt" ls
}

flow_proc synthesize {
    global design_name synth
    set _libs $::oss_libs
    set _flat [expr {[is_true [oss_get synth oss,synth,flatten]] ? "-flatten" : ""}]
    yosys synth -top $design_name {*}$_flat
    yosys opt_clean -purge
    set _dont_use {}
    foreach _c [oss_trk dont_use] { lappend _dont_use -dont_use $_c }
    foreach _l $_libs { yosys dfflibmap -liberty $_l }
    set _abc [list abc -liberty [lindex $_libs 0] {*}$_dont_use]
    set _d [oss_get synth oss,synth,abc_delay_ps]
    if {$_d > 0} { lappend _abc -D $_d }
    yosys {*}$_abc
    lassign [split [oss_trk tie_hi] /] _hi_cell _hi_pin
    lassign [split [oss_trk tie_lo] /] _lo_cell _lo_pin
    yosys hilomap -singleton -hicell $_hi_cell $_hi_pin -locell $_lo_cell $_lo_pin
    yosys setundef -zero
    yosys splitnets
    yosys insbuf -buf [oss_trk buffer_cell] A X
    yosys opt_clean -purge
    yosys check -assert
    yosys tee -o "$::REPORTS_DIR/synthesis_stat.rpt" stat -liberty [lindex $_libs 0]
    yosys write_verilog -noattr -noexpr -nohex -nodec [oss_stage_out synthesis.v]
}

flow_exec_all
exit
