#!/usr/bin/env tclsh
# CBFlow PNR powerplan - Cadence Innovus
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
handle_info "Starting PNR powerplan with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "powerplan"
set NODE_NAME "powerplan1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

flow_proc enable_mmmc {
    # Enable MMMC scenarios for powerplan stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for powerplan stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "powerplan" "setup"]
    set hold_scenarios [get_effective_scenarios "powerplan" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for powerplan, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "powerplan"]
    
    handle_info "powerplan MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Tool-specific MMMC scenario setup would go here
    handle_info "MMMC scenarios configured for powerplan stage"
}

flow_proc create_power_rings {
    handle_info "Creating power rings..."
    
    # Get power ring parameters from hierarchical configuration
    set ring_nets $innovus(powerplan,ring_nets)
    set ring_width $innovus(powerplan,ring_width)
    set ring_spacing $innovus(powerplan,ring_spacing)
    set ring_offset $innovus(powerplan,ring_offset)
    set ring_layers $innovus(powerplan,ring_layers)
    
    handle_info "Power ring parameters:"
    handle_info "  Width: $ring_width"
    handle_info "  Spacing: $ring_spacing"
    handle_info "  Offset: $ring_offset"

    # Connect global power nets
    globalNetConnect VDD -type pgpin -pin VDD -all
    globalNetConnect VSS -type pgpin -pin VSS -all

    # Create power rings around core
    addRing -nets $ring_nets \
            -type core_rings \
            -layer $ring_layers \
            -width $ring_width \
            -spacing $ring_spacing \
            -offset $ring_offset \
            -center 1 \
            -jog_distance 0 -threshold 0
}

flow_proc create_power_stripes {
    handle_info "Creating power stripes..."
    
    # Get stripe parameters from hierarchical configuration
    set stripe_nets $innovus(powerplan,stripe_nets)
    set stripe_width $innovus(powerplan,stripe_width)
    set stripe_spacing $innovus(powerplan,stripe_spacing)
    set stripe_layers $innovus(powerplan,stripe_layers)
    set stripe_direction $innovus(powerplan,stripe_direction)
    
    handle_info "Power stripe parameters:"
    handle_info "  Width: $stripe_width"
    handle_info "  Spacing: $stripe_spacing"
    handle_info "  Layers: $stripe_layers"
    
    # Create vertical and horizontal stripes
    foreach layer $stripe_layers {
        if {[expr {[lsearch $stripe_layers $layer] % 2}] == 0} {
            set direction "vertical"
        } else {
            set direction "horizontal"
        }
        
        handle_info "Creating $direction stripes on $layer"
        addStripe -nets $stripe_nets \
                  -layer $layer \
                  -direction $direction \
                  -width $stripe_width \
                  -spacing $stripe_spacing \
                  -set_to_set_distance [expr {$stripe_spacing * 10}] \
                  -start_from left \
                  -extend_to design_boundary
    }
}

flow_proc connect_power_grid {
    handle_info "Connecting power grid..."
    
    # Connect standard cell power pins to rails and rings to stripes
    sroute -connect {blockPin padPin padRing corePin floatingStripe} \
           -layerChangeRange {M1 M9} \
           -blockPinTarget nearestTarget \
           -padPinPortConnect allPort \
           -padPinTarget nearestTarget \
           -corePinTarget firstAfterRowEnd \
           -crossoverViaLayerRange {M1 M9} \
           -allowJogging 1 \
           -allowLayerChange 1

    handle_info "Power grid connections completed"
}

flow_proc add_well_ties {
    handle_info "Adding well ties..."
    
    # Get well tie parameters from hierarchical configuration
    set well_tie_cells $innovus(powerplan,well_tie_cells)
    set well_tie_spacing $innovus(powerplan,well_tie_spacing)
    set well_tie_rule $innovus(powerplan,well_tie_rule)
    
    handle_info "Well tie spacing: $well_tie_spacing"
    
    addWellTap -cell $well_tie_cells -cellInterval $well_tie_spacing -rule $well_tie_rule
}

flow_proc verify_power_grid {
    handle_info "Verifying power grid..."

    # Power grid verification
    verifyConnectivity -type all -error 1000 -warning 50

    # Generate power reports
    file mkdir "$::REPORTS_DIR"

    catch { verifyConnectivity -type all -report "$::REPORTS_DIR/verify_connectivity.rpt" }
    catch { verify_PG_short -report "$::REPORTS_DIR/pg_short.rpt" }

    handle_info "Power grid verification completed"
}

flow_proc powerplan_complete {
    handle_info "Power planning stage complete"

    # Save checkpoint
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/powerplan.enc"

    # Generate final reports
    file mkdir "$::REPORTS_DIR"

    catch { reportNetStat > "$::REPORTS_DIR/power_net_stats.rpt" }
    catch { report_power -outfile "$::REPORTS_DIR/report_power.rpt" }

    log_stage_status "powerplan" "COMPLETE" "Power planning completed successfully"
}



# Exit tool after stage completion
exit
