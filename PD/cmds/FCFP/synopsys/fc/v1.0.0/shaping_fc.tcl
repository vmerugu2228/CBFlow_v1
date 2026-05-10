#!/usr/bin/env tclsh
# CBFlow FCFP shaping - Synopsys Fusion Compiler
# FC-RM: shaping.tcl -- Block shaping with channel/non-channel styles,
#         shaping rule checks, and abstract creation
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FCFP/shaping/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
handle_info "Starting FCFP shaping..."
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

set WORK_DIR "$run_dir/work/FCFP/shaping1"
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
    handle_info "Loading design for shaping..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(design_name)] ? $fcfp(design_name) : $flow(design_name)}]

    if {[info exists fcfp(open_lib)] && $fcfp(open_lib) ne ""} {
        open_lib $fcfp(open_lib)
    }

    set from_label [expr {[info exists fcfp(shaping,from_label)] ? $fcfp(shaping,from_label) : "create_floorplan"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/shaping
    current_block ${design_name}/shaping
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: shape_blocks
# FC-RM: shape_blocks with channel/non-channel style
# ==============================================================================
flow_proc shape_blocks {
    handle_info "Shaping blocks..."
    global fcfp

    # Source pre-shaping constraints
    if {[info exists fcfp(shaping,constraint_script)] && [file exists $fcfp(shaping,constraint_script)]} {
        source -e $fcfp(shaping,constraint_script)
        handle_info "Shaping constraints loaded"
    }

    # Determine shaping style: channel (default) or non-channel
    set shaping_style "channel"
    if {[info exists fcfp(shaping,style)] && $fcfp(shaping,style) ne ""} {
        set shaping_style $fcfp(shaping,style)
    }

    set shape_cmd "shape_blocks"

    if {$shaping_style eq "non-channel"} {
        lappend shape_cmd -channels false
    }

    # Target utilization for shaping
    if {[info exists fcfp(shaping,target_utilization)] && $fcfp(shaping,target_utilization) ne ""} {
        lappend shape_cmd -core_utilization $fcfp(shaping,target_utilization)
    }

    # Min/max size constraints
    if {[info exists fcfp(shaping,min_width)] && $fcfp(shaping,min_width) ne ""} {
        lappend shape_cmd -min_width $fcfp(shaping,min_width)
    }
    if {[info exists fcfp(shaping,min_height)] && $fcfp(shaping,min_height) ne ""} {
        lappend shape_cmd -min_height $fcfp(shaping,min_height)
    }

    handle_info "Running: $shape_cmd (style=$shaping_style)"
    eval $shape_cmd

    handle_info "Block shaping completed"
}

# ==============================================================================
# flow_proc: check_shaping
# FC-RM: check_floorplan_rules after shaping
# ==============================================================================
flow_proc check_shaping {
    handle_info "Checking shaping results..."
    global fcfp

    redirect -file $::REPORTS_DIR/check_floorplan_rules.shaping {
        check_floorplan_rules
    }

    redirect -file $::REPORTS_DIR/report_placement.shaping {
        report_placement -physical_hierarchy_violations all -wirelength all
    }

    redirect -file $::REPORTS_DIR/report_utilization.shaping {
        report_utilization
    }

    handle_info "Shaping checks completed"
}

# ==============================================================================
# flow_proc: create_abstracts
# FC-RM: create_abstract for sub-blocks after shaping
# ==============================================================================
flow_proc create_abstracts {
    handle_info "Creating abstracts after shaping..."
    global fcfp

    create_abstract
    handle_info "Abstracts created"
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving shaping block..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(design_name)] ? $fcfp(design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/shaping
    handle_info "Block saved: ${design_name}/shaping"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating shaping reports..."
    global fcfp

    set max_paths [expr {[info exists fcfp(analysis,max_paths)] ? $fcfp(analysis,max_paths) : 100}]

    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor }
    redirect -file $::REPORTS_DIR/report_timing.rpt {
        report_timing -max_paths $max_paths -delay_type max
    }
    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Shaping reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FCFP/shaping/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.shaping.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
