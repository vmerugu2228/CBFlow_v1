#!/usr/bin/env tclsh
# CBFlow FCFP placement - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "placement"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for placement..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(placement,from_label)] ? $fcfp(placement,from_label) : "shaping"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/placement
    current_block ${design_name}/placement
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: create_placement
# FC-RM: create_placement -congestion -timing_driven
# ==============================================================================
flow_proc create_placement {
    handle_info "Running placement..."
    global fcfp

    set place_cmd "create_placement -congestion -timing_driven"

    # Effort level
    if {[info exists fcfp(placement,effort)] && $fcfp(placement,effort) ne ""} {
        lappend place_cmd -effort $fcfp(placement,effort)
    }

    # Congestion-driven options
    if {[info exists fcfp(placement,congestion_effort)] && $fcfp(placement,congestion_effort) ne ""} {
        set_app_option -name place.coarse.congestion_layer_aware -value $fcfp(placement,congestion_effort)
    }

    # Source placement constraints
    if {[info exists fcfp(placement,constraint_script)] && [file exists $fcfp(placement,constraint_script)]} {
        source -e $fcfp(placement,constraint_script)
    }

    handle_info "Running: $place_cmd"
    eval $place_cmd

    # Report placement
    redirect -file $::REPORTS_DIR/report_placement.rpt {
        report_placement -physical_hierarchy_violations all -wirelength all
    }

    connect_pg_net
    handle_info "Placement completed"
}

# ==============================================================================
# flow_proc: push_down_objects
# FC-RM: Push site rows and other objects down to sub-blocks
# ==============================================================================
flow_proc push_down_objects {
    handle_info "Pushing objects to sub-blocks..."
    global fcfp

    # Push down site rows
    if {[info exists fcfp(placement,push_down_site_rows)] && $fcfp(placement,push_down_site_rows)} {
        push_down_objects -site_rows
        handle_info "Site rows pushed down"
    }

    # Push down blockages
    if {[info exists fcfp(placement,push_down_blockages)] && $fcfp(placement,push_down_blockages)} {
        push_down_objects -blockages
        handle_info "Blockages pushed down"
    }

    # Push down PG
    if {[info exists fcfp(placement,push_down_pg)] && $fcfp(placement,push_down_pg)} {
        push_down_objects -pg
        handle_info "PG pushed down"
    }

    handle_info "Push-down completed"
}

# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract -estimate_timing
# ==============================================================================
flow_proc create_abstracts {
    handle_info "Creating abstracts with timing estimation..."
    global fcfp

    if {[info exists fcfp(placement,abstract_timing)] && $fcfp(placement,abstract_timing)} {
        create_abstract -estimate_timing
        handle_info "Abstracts created with timing estimation"
    } else {
        create_abstract
        handle_info "Abstracts created"
    }
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving placement block..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/placement
    handle_info "Block saved: ${design_name}/placement"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating placement reports..."
    global fcfp

    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths $max_paths -delay_type min
    }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/report_congestion.rpt { report_congestion }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Placement reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
