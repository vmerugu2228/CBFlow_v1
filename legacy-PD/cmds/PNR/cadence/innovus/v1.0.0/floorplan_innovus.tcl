#!/usr/bin/env tclsh
# PNR floorplan - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "floorplan"
set NODE_NAME "floorplan1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME


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
    set core_util $pnr(floorplan,core_util)
    set aspect_ratio $pnr(floorplan,aspect_ratio)
    set core_margins $pnr(floorplan,core_margins)
    set site_name $pnr(floorplan,site_name)
    set mode $pnr(floorplan,mode)
    
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
    set io_file $pnr(floorplan,io_placement_file)
    set io_mode $pnr(floorplan,io_placement_mode)
    set io_pin_width $pnr(floorplan,io_pin_width)
    set io_pin_depth $pnr(floorplan,io_pin_depth)
    set io_pin_spacing $pnr(floorplan,io_pin_spacing)
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
    set upf_file $pnr(floorplan,upf_file)
    set power_domains $pnr(floorplan,power_domains)
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
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs
    saveDesign "$_outputs/floorplan.enc"

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

flow_exec_all
exit
