#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — pattern_gen (opensource / container tclsh)
# Stuck-at pattern generation. The ATPG model: macros replaced by their stubs
# (outputs held 0) and flattened (yosys), scan flops cut into pseudo inputs /
# outputs (`fault cut`), library cells turned into gates from their liberty
# functions (nl2bench), the bench cleaned for Atalanta (constants, held ports,
# logic left unobservable / uncontrollable by the cut — counted, not tested),
# then Atalanta: random-pattern session, FAN deterministic ATPG, compaction.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
set STAGE_NAME "pattern_gen"
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
    set ::init "[cbflow_node_dir [oss_chain_node init_atpg]]"
    set ::netlist [dft_input netlist]
    set ::libs [dft_libs init_atpg]
    set ::w "$::WORK_DIR/run"
    set ::holds {}
    foreach _h [dft_holds atpg] { lappend ::holds --hold $_h }
}

flow_proc flatten {
    global design_name
    set _ys "$::w/flatten.ys"
    set _t ""
    foreach _l $::libs { append _t "read_liberty -lib $_l\n" }
    append _t "read_verilog $::netlist\nread_verilog $::init/outputs/macro_stubs.v\n"
    append _t "hierarchy -top $design_name\nflatten\nopt_clean -purge\nwrite_verilog -noattr $::w/atpg_flat.v\n"
    dft_write $_ys $_t
    dft_run "$::REPORTS_DIR/flatten.log" yosys -q -s $_ys
}

flow_proc cut {
    set _types [dft_report_list "$::init/reports/census.rpt" "Sequential types"]
    set _clk [dft_scan_clock "$::init/reports/scan_chains.rpt"]
    # pyverilog writes its parser tables into the working directory
    cd $::w
    dft_run "$::REPORTS_DIR/cut.log" fault cut --dff [join $_types ,] --clock $_clk -o "$::w/atpg_cut.v" "$::w/atpg_flat.v"
}

flow_proc bench {
    cd $::w
    dft_run "$::REPORTS_DIR/nl2bench.log" nl2bench -o "$::w/atpg_raw.bench" {*}[concat {*}[lmap _l $::libs {list -l $_l}]] "$::w/atpg_cut.v"
    dft_py "$::REPORTS_DIR/bench_clean.log" bench-clean --bench "$::w/atpg_raw.bench" -o [oss_stage_out atpg.bench] \
        --map [oss_stage_out bench_map.json] {*}$::holds
}

flow_proc atpg {
    set _fill [oss_get atpg oss,atalanta,fill]
    if {$_fill ni {R 0 1}} { error "atpg(oss,atalanta,fill) must be R, 0 or 1, got '$_fill'" }
    set _args [list -b [oss_get atpg oss,atalanta,backtrack] -B [oss_get atpg oss,atalanta,phase2_backtrack] \
                    -r [oss_get atpg oss,atalanta,random_packets] -c [oss_get atpg oss,atalanta,compaction] \
                    -s [oss_get atpg oss,atalanta,seed] -$_fill \
                    -t [oss_stage_out atpg.test] -U [oss_stage_out atpg.ufaults] -v]
    cd [file dirname [oss_stage_out atpg.bench]]
    dft_run "$::REPORTS_DIR/atalanta.log" atalanta {*}$_args [oss_stage_out atpg.bench]
    set _fh [open "$::REPORTS_DIR/atalanta.log"]; set _t [read $_fh]; close $_fh
    if {[regexp {Fatal error|Error:} $_t]} { error "Atalanta failed — $::REPORTS_DIR/atalanta.log" }
    if {![regexp {after compaction\s*:\s*(\d+)} $_t -> _n] || $_n == 0} {
        error "Atalanta produced no patterns — $::REPORTS_DIR/atalanta.log"
    }
    regexp {Fault coverage\s*:\s*([\d.]+)} $_t -> _fc
    handle_info "Atalanta: $_n patterns, fault coverage $_fc %"
}

dft_exec_all
exit
