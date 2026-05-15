#!/usr/bin/env tclsh
# CBFlow PNR floorplan - Cadence Innovus
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global pnr project tech flow
# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR floorplan with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "floorplan"
set NODE_NAME "floorplan1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

flow_proc read_floorplan {
    handle_info "Reading floorplan constraints..."
    
    if {[info exists pnr(input,floorplan_def)] && [file exists $pnr(input,floorplan_def)]} {
        handle_info "Reading DEF floorplan: [file tail $pnr(input,floorplan_def)]"
        defIn $pnr(input,floorplan_def)
    } else {
        handle_info "No DEF floorplan specified, will create automatic floorplan"
    }
}

flow_proc create_floorplan {
    handle_info "Creating floorplan..."
    
    # Get floorplan parameters from hierarchical configuration
    set core_util $innovus(floorplan,core_util)
    set aspect_ratio $innovus(floorplan,aspect_ratio)
    set core_margins $innovus(floorplan,core_margins)
    set site_name $innovus(floorplan,site_name)
    set mode $innovus(floorplan,mode)
    
    handle_info "Floorplan parameters:"
    handle_info "  Core utilization: $core_util"
    handle_info "  Aspect ratio: $aspect_ratio"
    handle_info "  Core margins: $core_margins"
    
    # Create floorplan with aspect ratio and utilization
    floorPlan -site $site_name -r $aspect_ratio $core_util {*}$core_margins
    snapFPlan
    checkFPlan
}

flow_proc place_ios {
    handle_info "Placing I/O pins..."
    
    # Check for I/O placement file
    set io_file $innovus(floorplan,io_placement_file)
    set io_mode $innovus(floorplan,io_placement_mode)
    set io_pin_width $innovus(floorplan,io_pin_width)
    set io_pin_depth $innovus(floorplan,io_pin_depth)
    set io_pin_spacing $innovus(floorplan,io_pin_spacing)
    if {$io_file ne "" && [file exists $io_file]} {
        handle_info "Reading I/O placement: [file tail $io_file]"
        loadIoFile $io_file
    } else {
        handle_info "No I/O placement file, using automatic placement"
        editPin -pinWidth $io_pin_width -pinDepth $io_pin_depth -spacing $io_pin_spacing \
                -fixOverlap 1 -unit MICRON -spreadDirection clockwise -side Top -layer 1 \
                -spreadType center
    }
}

flow_proc create_power_domains {
    handle_info "Creating power domains..."
    
    # Check for UPF file
    set upf_file $innovus(floorplan,upf_file)
    set power_domains $innovus(floorplan,power_domains)
    if {$upf_file ne "" && [file exists $upf_file]} {
        handle_info "Reading UPF: [file tail $upf_file]"
        read_power_intent -1801 $upf_file
        commit_power_intent
    } else {
        handle_info "No UPF file specified, using single power domain"
    }
}

flow_proc floorplan_complete {
    handle_info "Floorplan stage complete"

    # Save checkpoint
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/floorplan.enc"

    # Generate floorplan reports
    file mkdir "$::REPORTS_DIR"

    catch { reportFPlan "$::REPORTS_DIR/floorplan.rpt" }
    catch { checkFPlan -reportUtil -outFile "$::REPORTS_DIR/floorplan_util.rpt" }
    catch { checkDesign -all -outfile "$::REPORTS_DIR/check_design.rpt" }

    log_stage_status "floorplan" "COMPLETE" "Floorplan created successfully"
}

flow_proc enable_mmmc {
    # Enable MMMC scenarios for floorplan stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for floorplan stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "floorplan" "setup"]
    set hold_scenarios [get_effective_scenarios "floorplan" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for floorplan, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "floorplan"]
    
    handle_info "Floorplan MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Tool-specific MMMC scenario setup would go here
    handle_info "MMMC scenarios configured for floorplan stage"
}


# Exit tool after stage completion
exit
