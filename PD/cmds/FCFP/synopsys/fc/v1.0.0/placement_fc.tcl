#!/usr/bin/env tclsh
# CBFlow FCFP placement - Synopsys Fusion Compiler
# FC-RM: placement.tcl -- Congestion/timing-driven placement,
#         push-down objects, abstract creation
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FCFP/placement/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
handle_info "Starting FCFP placement..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FCFP/placement1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for placement..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(design_name)] ? $fcfp(design_name) : $flow(design_name)}]

    if {[info exists fcfp(open_lib)] && $fcfp(open_lib) ne ""} {
        open_lib $fcfp(open_lib)
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

    set design_name [expr {[info exists fcfp(design_name)] ? $fcfp(design_name) : $flow(design_name)}]

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
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FCFP/placement/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.placement.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
