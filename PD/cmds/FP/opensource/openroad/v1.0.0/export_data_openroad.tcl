#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FP — export_data (opensource / openroad)
# Floorplan deliverables for PNR: DEF (die, rows, tracks, placed macros,
# pins, taps, power grid), database, netlist (with physical cells), SDC, UPF.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "export_data"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: previous stage's database, liberty from the init_design node's MMMC
# views, SDC (timing estimate for the FP_EXIT checklist)
flow_proc load_design {
    global blocks
    set_thread_count [oss_get fp oss,threads]
    oss_read_corners [oss_chain_node init_design] $blocks
    read_db [oss_prev_odb [oss_upstream_node]]
    read_sdc [oss_sdc_file]
}

# No operation step: export_data only writes the floorplan deliverables.

# Reports: design area + FP_EXIT checklist metrics
flow_proc report {
    oss_report "$::REPORTS_DIR/design_area.rpt" report_design_area
    oss_checklist_safe fp
}

# Save the deliverables: DEF, database, netlists, GDS, SDC, UPF
flow_proc save_design {
    global design_name
    write_def     [oss_stage_out final.def]
    write_db      [oss_stage_out final.odb]
    write_verilog [oss_stage_out final.v]
    # PV inputs at floorplan: power-aware LVS netlist (no physical-only cells)
    # and the floorplan streamed to GDS
    write_verilog -include_pwr_gnd -remove_cells [concat [oss_trk fillers] [oss_trk well_tap]] \
        [oss_stage_out final.lvs.v]
    # min_area_layers may be {} (repair off) — oss_get rejects empty values
    if {![info exists ::fp(oss,export,min_area_layers)]} { error "fp(oss,export,min_area_layers) is not set" }
    oss_def2gds [oss_stage_out final.def] [oss_stage_out final.gds] \
        $::fp(oss,export,min_area_layers) [oss_get fp oss,export,klayout_batch]
    file copy -force [oss_sdc_file] [oss_stage_out final.sdc]
    # UPF: required when fp(mandatory_outputs,<this node>) lists final.upf.
    set _upf "$::UPF_DIR/${design_name}.upf"
    if {[file exists $_upf]} {
        file copy -force $_upf [oss_stage_out final.upf]
    } elseif {"final.upf" in [oss_get fp mandatory_outputs,$::NODE_NAME]} {
        error "UPF not staged: $_upf (fp(mandatory_outputs,$::NODE_NAME) requires final.upf)"
    }
}

flow_exec_all
exit
