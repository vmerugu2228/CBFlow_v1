#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ECO — signoff (opensource / openroad)
# The ECO'd layout: fillers, supply connections, deliverables (DEF, netlists,
# abstract LEF, CDL, SDC, database) written BEFORE extraction — OpenRCX
# rewrites the wire encoding in the database — then one SPEF per RC corner,
# post-ECO timing / DRV / power per view and a timing model per lib set.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ECO"
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

# Load: the eco node's database + timing views + SDC, propagated clocks
flow_proc load_design {
    global blocks
    set_thread_count [oss_get eco oss,threads]
    oss_read_corners $::NODE_NAME $blocks
    read_db [oss_node_output [oss_upstream_node] eco.odb]
    read_sdc [oss_sdc_file]
    oss_apply_derate
    set_propagated_clock [all_clocks]
}

# Fillers back, supply connections of every new cell, legality
flow_proc fill {
    filler_placement [oss_trk fillers]
    global_connect
    oss_report "$::REPORTS_DIR/signoff_check_placement.rpt" check_placement -verbose
}

# Deliverables before extraction (clean wire encoding in DEF / odb)
flow_proc save_design {
    global blocks
    file copy -force [oss_sdc_file] [oss_stage_out final.sdc]
    foreach _c [oss_deliverable_cmds "$::WORK_DIR/outputs" $blocks] { eval $_c }
}

# One SPEF per RC corner (outputs/final_<rc>.spef); each view reads its own
flow_proc extract {
    set _done {}
    define_process_corner -ext_model_index 0 X
    foreach _v [oss_node_views $::NODE_NAME] {
        set _rc [oss_view_attr $_v rc_corner]
        if {[lsearch -exact $_done $_rc] < 0} {
            oss_rcx_extract $_rc
            write_spef [oss_stage_out final_${_rc}.spef]
            oss_spef_check [oss_stage_out final_${_rc}.spef] $_rc
            lappend _done $_rc
        }
        read_spef -corner $_v [oss_stage_out final_${_rc}.spef]
    }
}

# Post-ECO QoR / timing (extracted), DRV, power per view; timing models
flow_proc report {
    global design_name
    oss_write_qor signoff
    oss_report "$::REPORTS_DIR/signoff_drv.rpt" report_check_types -max_slew -max_capacitance -max_fanout -violators
    set _copt [oss_corner_opt report_power]
    foreach _v [oss_node_views $::NODE_NAME] {
        oss_report "$::REPORTS_DIR/signoff_power_${_v}.rpt" report_power $_copt $_v
        set _ls [oss_view_attr $_v lib_set_ref]
        write_timing_model [oss_corner_opt write_timing_model] $_v -library_name ${design_name}__${_ls} \
            [oss_stage_out final__${_ls}.lib]
    }
}

flow_exec_all
exit
