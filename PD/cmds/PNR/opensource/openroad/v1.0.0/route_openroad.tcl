#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — route (opensource / openroad)
# Global + detailed routing. Fails the stage when detailed-route DRC
# violations exceed pnr(oss,route,max_drc).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "route"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: previous stage's database + timing views + SDC, propagated clocks
flow_proc load_design {
    oss_load_stage [oss_upstream_node]
    set_propagated_clock [all_clocks]
}

# Global + detailed routing. The router's own logs land in reports/:
# route_grt.rpt (global route + congestion table), route_congestion.rpt,
# route_drc.rpt (detailed-route DRC).
flow_proc global_detailed_route {
    global design_name blocks pnr
    lassign [oss_signal_layers $design_name $blocks] _min _max
    # Clock layers from the stack, clamped to this block's signal range.
    set _layers [oss_ms metal_layers]
    set _cmin [oss_ms clock_routing_layer_min]
    set _cmax [oss_ms clock_routing_layer_max]
    if {[lsearch -exact $_layers $_cmax] > [lsearch -exact $_layers $_max]} { set _cmax $_max }
    if {[lsearch -exact $_layers $_cmin] > [lsearch -exact $_layers $_cmax]} { set _cmin $_cmax }
    set_routing_layers -signal ${_min}-${_max} -clock ${_cmin}-${_cmax}
    # -verbose prints the final congestion table (overflow per layer + total)
    oss_report "$::REPORTS_DIR/route_grt.rpt" global_route -allow_congestion -verbose \
        -congestion_report_file "$::REPORTS_DIR/route_congestion.rpt"
    # Wire RC from the global route for this stage's timing / clock metrics
    estimate_parasitics -global_routing
    detailed_route -output_drc "$::REPORTS_DIR/route_drc.rpt" -verbose 1
}

# Reports: route checklist metrics (reads route_drc.rpt / route_grt.rpt)
flow_proc report {
    oss_checklist_safe route
}

# Save the routed database
flow_proc save_design {
    write_db [oss_stage_out route.odb]
}

# DRC gate — last, so the routed database and reports exist when it fails
flow_proc check_drc {
    global pnr
    set _n 0
    if {[file exists "$::REPORTS_DIR/route_drc.rpt"]} {
        set _fh [open "$::REPORTS_DIR/route_drc.rpt"]
        foreach _l [split [read $_fh] "\n"] { if {[string match "violation type:*" $_l]} { incr _n } }
        close $_fh
    }
    handle_info "Detailed-route DRC violations: $_n"
    set _max [oss_get pnr oss,route,max_drc]
    if {$_n > $_max} {
        set _msg "detailed route left $_n DRC violations (max $_max) — see $::REPORTS_DIR/route_drc.rpt"
        if {[is_true [oss_get pnr oss,fail_on_violations]]} { error $_msg }
        handle_warning "$_msg — reported, flow continues"
    }
}

flow_exec_all
exit
