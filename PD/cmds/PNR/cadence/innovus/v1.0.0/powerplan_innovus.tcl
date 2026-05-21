#!/usr/bin/env tclsh
# PNR powerplan - Cadence Innovus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "powerplan"
set NODE_NAME "powerplan1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting PNR powerplan with Cadence Innovus..."
set FLOW_TYPE "PNR"
set STAGE_NAME "powerplan"
set NODE_NAME "powerplan1"

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
    set ring_nets $pnr(powerplan,ring_nets)
    set ring_width $pnr(powerplan,ring_width)
    set ring_spacing $pnr(powerplan,ring_spacing)
    set ring_offset $pnr(powerplan,ring_offset)
    set ring_layers $pnr(powerplan,ring_layers)
    
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
    set stripe_nets $pnr(powerplan,stripe_nets)
    set stripe_width $pnr(powerplan,stripe_width)
    set stripe_spacing $pnr(powerplan,stripe_spacing)
    set stripe_layers $pnr(powerplan,stripe_layers)
    set stripe_direction $pnr(powerplan,stripe_direction)
    
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
    set well_tie_cells $pnr(powerplan,well_tie_cells)
    set well_tie_spacing $pnr(powerplan,well_tie_spacing)
    set well_tie_rule $pnr(powerplan,well_tie_rule)
    
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
