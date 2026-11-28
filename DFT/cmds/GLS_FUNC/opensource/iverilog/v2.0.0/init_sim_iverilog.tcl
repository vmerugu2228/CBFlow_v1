#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow GLS_FUNC — init_sim (opensource / container tclsh)
# Prepare the gate-level simulation: the released netlist, the testbench
# (gls_func(oss,tb_input) input node), the cell models (FUNCTIONAL), and the
# macros — models: the memory models of the library tag (memory declarations
# moved first for iverilog) + child-block netlists; stubs: every blackboxed
# macro with outputs held 0 (the ATPG model). Writes the file list
# (sim_files.txt) and, with toggle coverage on, the VCD dump module.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "GLS_FUNC"
set STAGE_NAME "init_sim"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load_design {
    set ::arr [oss_flow_arr]
    if {[info exists ::${::arr}(oss,verify)] && [oss_get $::arr oss,verify] ne "scan"} {
        error "${::arr}(oss,verify) [oss_get $::arr oss,verify]: only scan pattern simulation is supported by the open-source flow (mbist / bscan are not)"
    }
    set ::netlist [dft_input netlist]
    set ::tb [dft_input [oss_get $::arr oss,tb_input]]
    set ::libs [dft_libs init_sim]
    set ::tb_top [oss_get $::arr oss,tb_top]
    handle_info "netlist $::netlist, testbench $::tb (top $::tb_top)"
}

flow_proc macros {
    global design_name
    set _files [dft_cell_models]
    set _mode [oss_get $::arr oss,macros]
    switch -- $_mode {
        stubs {
            dft_py "$::REPORTS_DIR/cells.log" cells {*}[concat {*}[lmap _l $::libs {list --lib $_l}]] -o [oss_stage_out cells.json]
            dft_netlist_json $::netlist $design_name $::libs [oss_stage_out netlist.json] "$::REPORTS_DIR/netlist_json.log"
            dft_py "$::REPORTS_DIR/stubs.log" stubs --json [oss_stage_out netlist.json] --top $design_name \
                --cells [oss_stage_out cells.json] -o [oss_stage_out macro_stubs.v]
            lappend _files [oss_stage_out macro_stubs.v]
        }
        models {
            file mkdir [oss_stage_out models]
            foreach _m [oss_memory_files verilog] {
                set _o [oss_stage_out models/[file tail $_m]]
                dft_py "$::REPORTS_DIR/model_fix.log" model-fix --model $_m -o $_o
                lappend _files $_o
            }
            foreach _b [hier_children $design_name] { lappend _files [dict get [hier_block_views $_b] netlist] }
        }
        default { error "${::arr}(oss,macros) must be models or stubs, got '$_mode'" }
    }
    lappend _files $::netlist $::tb
    set ::tops [list $::tb_top]
    if {[is_true [oss_get $::arr oss,toggle,enable]]} {
        set _scope [oss_get $::arr oss,dump_scope]
        # the VCD path comes from run_sim (+cbflow_vcd=<its outputs>/sim.vcd);
        # depth 1: the nets of the dumped netlist module, not the cell internals
        dft_write [oss_stage_out cbflow_dump.v] "// CBflow GLS — VCD of $_scope for toggle coverage\nmodule cbflow_dump;\n  reg \[8*1024-1:0\] vcd;\n  initial begin\n    if (!\$value\$plusargs(\"cbflow_vcd=%s\", vcd)) vcd = \"sim.vcd\";\n    \$dumpfile(vcd);\n    \$dumpvars(1, $_scope);\n  end\nendmodule\n"
        lappend _files [oss_stage_out cbflow_dump.v]
        lappend ::tops cbflow_dump
    }
    dft_write [oss_stage_out sim_files.txt] "[join $_files \n]\n"
    dft_write [oss_stage_out sim_tops.txt] "[join $::tops \n]\n"
}

dft_exec_all
exit
