#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — signoff (opensource / openroad)
# Final timing on extracted parasitics, deliverables: DEF, netlists
# (logical + power-aware for LVS), abstract LEF + per-lib-set timing models
# (consumed by the parent block), CDL, database.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "signoff"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load {
    oss_load_stage [oss_upstream_node]
    set_propagated_clock [all_clocks]
    foreach _v [oss_node_views $::NODE_NAME] {
        read_spef -corner $_v [oss_node_output [oss_upstream_node] final_[oss_view_attr $_v rc_corner].spef]
    }
}

flow_proc timing {
    global oss_upf design_name
    set _upf "$::UPF_DIR/${design_name}.upf"
    if {![file exists $_upf]} { error "UPF not staged: $_upf (pnr(input,upf_file))" }
    oss_upf_parse $_upf
    oss_check_power
    oss_write_qor signoff
    oss_report "$::REPORTS_DIR/signoff_drv.rpt" report_check_types -max_slew -max_capacitance -max_fanout -violators
    # One power report per MMMC view (multi-corner STA needs the corner).
    set _copt [oss_corner_opt report_power]
    foreach _v [oss_node_views $::NODE_NAME] {
        oss_report "$::REPORTS_DIR/signoff_power_${_v}.rpt" report_power $_copt $_v
    }
    oss_power_metrics [oss_node_views $::NODE_NAME]
}

# Append "# category: power" to this node's checklist metrics (published as
# the release metrics.rpt): total/internal/switching/leakage per view in mW
# from the report_power "Total" row, plus the worst view's total.
proc oss_power_metrics {views} {
    set _rpt "$::REPORTS_DIR/[file tail [oss_get pnr checklist,report]]"
    if {![file exists $_rpt]} { error "checklist metrics not written: $_rpt" }
    set L [list "# category: power"]
    set _worst ""; set _worst_v ""
    foreach _v $views {
        set _fh [open "$::REPORTS_DIR/signoff_power_${_v}.rpt"]; set _t [read $_fh]; close $_fh
        if {![regexp -line {^Total\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $_t -> _int _sw _lk _tot]} {
            error "no Total row in signoff_power_${_v}.rpt"
        }
        foreach {_k _w} [list Total $_tot Internal $_int Switching $_sw Leakage $_lk] {
            lappend L "$_k power mW $_v : [format %.4g [expr {$_w * 1e3}]]"
        }
        if {$_worst eq "" || $_tot > $_worst} { set _worst $_tot; set _worst_v $_v }
    }
    lappend L "Total power mW : [format %.4g [expr {$_worst * 1e3}]]" "Worst power view : $_worst_v"
    set _fh [open $_rpt a]; puts $_fh [join $L \n]; close $_fh
}

flow_proc deliverables {
    global design_name blocks
    write_def                 [oss_stage_out final.def]
    write_verilog             [oss_stage_out final.v]
    # LVS netlist: power-aware, without physical-only cells (fillers, well
    # taps) — they hold no devices, so extraction has nothing to match.
    write_verilog -include_pwr_gnd -remove_cells [concat [oss_trk fillers] [oss_trk well_tap]] \
        [oss_stage_out final.lvs.v]
    write_abstract_lef -bloat_occupied_layers [oss_stage_out final.lef]
    # CDL masters: standard cells + every child block's released CDL.
    set _cdl [list [oss_trk cdl_stdcell]]
    foreach _b $blocks { lappend _cdl [oss_get tech block,$_b,cdl] }
    write_cdl -masters $_cdl [oss_stage_out final.cdl]
    file copy -force [oss_sdc_file] [oss_stage_out final.sdc]
    write_db [oss_stage_out final.odb]
}

# Timing model per lib set — the parent reads <design>__<lib_set>.lib per corner.
flow_proc timing_models {
    global design_name
    foreach _v [oss_node_views $::NODE_NAME] {
        set _ls [oss_view_attr $_v lib_set_ref]
        write_timing_model [oss_corner_opt write_timing_model] $_v -library_name ${design_name}__${_ls} \
            [oss_stage_out final__${_ls}.lib]
    }
}

flow_exec_all
exit
