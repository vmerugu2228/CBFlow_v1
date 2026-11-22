#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — init_design (opensource / openroad)
# Load the FP-released floorplan (DEF: die, rows, tracks, placed hard macros,
# IO pins, well taps, power grid) + the SYNTH SDC, re-apply the power intent
# (UPF supplies / global connections). The floorplan itself is built by the
# FP flow (PD/cmds/FP/opensource/openroad/).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "init_design"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: LEF / liberty views, FP-released floorplan DEF, SDC, DRV limits
flow_proc load_design {
    global design_name blocks
    set_thread_count [oss_get pnr oss,threads]
    oss_read_lefs $blocks
    oss_read_corners $::NODE_NAME $blocks
    set _def "$::DEF_DIR/${design_name}.def"
    if {![file exists $_def]} { error "floorplan DEF not staged: $_def (pnr(input,def_file_release_tag) <phase>_FP_v<n>)" }
    handle_info "Floorplan: $_def"
    read_def $_def
    read_sdc [oss_sdc_file]
    oss_drv_limits                   ;# pnr(oss,drv,max_fanout) from overrides
    set_dont_use [oss_pnr_dont_use]
}

# Power intent (UPF supplies / global connections) + connectivity check
flow_proc power_intent {
    global design_name
    oss_apply_upf $design_name
    oss_check_power
}

# Save the database — before report: the checklist's first timing update
# adds resizer properties (limit_sizing_*) to the block, which would land
# in init_design.odb if saved after it
flow_proc save_design {
    write_db [oss_stage_out init_design.odb]
}

# Reports: init_design checklist metrics
flow_proc report {
    oss_checklist_safe init_design
}

flow_exec_all
exit
