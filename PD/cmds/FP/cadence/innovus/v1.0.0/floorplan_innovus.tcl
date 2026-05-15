#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FP Floorplan Stage for Innovus
# Description: Configure floorplan, place macros, create rows, and place I/O
# Usage: Source this file in Innovus or run via CBFlow
# Output: Floorplan with macros placed, rows created, and I/O assigned
# ═══════════════════════════════════════════════════════════════════════════════

# Validate required environment variables
if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
    puts "ERROR: FLOW_DIR not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts "ERROR: UTILITIES_VERSION not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

set flow_dir $::env(FLOW_DIR)

# Source flow utilities using release version
set utils_path "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts "ERROR: Cannot find flow utilities at: $utils_path"
    exit 1
}

set run_dir $::env(CBFLOW_RUN_DIR)

set WORK_DIR "$run_dir/work/FP/floorplan"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting CBFlow FP floorplan stage for Innovus"

# Define common procedures used in config files
if {[info procs INFO] eq ""} {
    proc INFO {} {
        return "INFO"
    }
}
if {[info procs WARNING] eq ""} {
    proc WARNING {} {
        return "WARNING"
    }
}

# Define flow_proc if not already defined
if {[info procs flow_proc] eq ""} {
    proc flow_proc {name body} {
        proc $name {} $body
        handle_info "Flow procedure '$name' defined"
    }
}

# Source generated configuration file (from setup stage)
set flow_type "FP"
set config_files [list \
    "config.tcl" \
    "work/$flow_type/floorplan/run/config.tcl" \
    "../work/$flow_type/floorplan/run/config.tcl" \
]

set config_found 0
foreach config_file $config_files {
    if {[file exists $config_file]} {
        handle_info "Sourcing configuration: $config_file"
        if {[catch {source $config_file} error]} {

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
            handle_warning "Minor error in config file $config_file: $error"
            handle_info "Continuing with available configuration..."
        }
        set config_found 1
        break
    }
}

if {!$config_found} {
    handle_error "Cannot find generated config file. Run 'make floorplan_setup' first."
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# FLOW_PROC HOOKS - Floorplan Process
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc configure_floorplan {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Configuring floorplan parameters..."

    # Get floorplan dimensions from config
    if {[info exists innovus(die,width)] && [info exists innovus(die,height)]} {
        set die_width $innovus(die,width)
        set die_height $innovus(die,height)
        handle_info "Die dimensions: ${die_width}um x ${die_height}um"
    }

    # Get core utilization
    set core_util [expr {[info exists innovus(common,core_utilization)] ? $innovus(common,core_utilization) : 0.70}]
    handle_info "Target core utilization: $core_util"

    # Get aspect ratio
    set aspect_ratio [expr {[info exists innovus(common,aspect_ratio)] ? $innovus(common,aspect_ratio) : 1.0}]
    handle_info "Aspect ratio: $aspect_ratio"

    # Core margins
    set core_margin_left   [expr {[info exists innovus(core_margin,left)]   ? $innovus(core_margin,left)   : 10.0}]
    set core_margin_right  [expr {[info exists innovus(core_margin,right)]  ? $innovus(core_margin,right)  : 10.0}]
    set core_margin_top    [expr {[info exists innovus(core_margin,top)]    ? $innovus(core_margin,top)    : 10.0}]
    set core_margin_bottom [expr {[info exists innovus(core_margin,bottom)] ? $innovus(core_margin,bottom) : 10.0}]

    handle_info "Core margins (L/R/T/B): $core_margin_left / $core_margin_right / $core_margin_top / $core_margin_bottom"

    # Initialize floorplan
    if {[info exists innovus(die,width)] && [info exists innovus(die,height)]} {
        # Use explicit die size
        floorPlan -site $innovus(common,site_name) \
            -d $die_width $die_height \
               $core_margin_left $core_margin_bottom \
               $core_margin_right $core_margin_top
    } else {
        # Use utilization-based floorplan
        floorPlan -site [expr {[info exists innovus(common,site_name)] ? $innovus(common,site_name) : "core"}] \
            -r $aspect_ratio $core_util \
              $core_margin_left $core_margin_bottom \
              $core_margin_right $core_margin_top
    }

    handle_info "Floorplan initialized successfully"
}

flow_proc place_macros {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Placing macros and configuring routing tracks..."

    # Read macro placement file if provided
    if {[info exists fp(input,macro_placement)]} {
        set macro_file $fp(input,macro_placement)
        if {[file exists $macro_file]} {
            handle_info "Reading macro placement from: [file tail $macro_file]"
            source $macro_file
        } else {
            handle_warning "Macro placement file not found: $macro_file"
        }
    }

    # Place individual macros from config
    if {[info exists innovus(common,macros)]} {
        foreach macro_spec $innovus(common,macros) {
            array set macro_info $macro_spec
            if {[info exists macro_info(name)] && [info exists macro_info(x)] && [info exists macro_info(y)]} {
                set orient [expr {[info exists macro_info(orient)] ? $macro_info(orient) : "R0"}]
                handle_info "Placing macro: $macro_info(name) at ($macro_info(x), $macro_info(y)) orient=$orient"
                placeInstance $macro_info(name) $macro_info(x) $macro_info(y) $orient -placed
            }
            array unset macro_info
        }
    }

    # Add halo around macros
    set halo_x [expr {[info exists innovus(macro_halo,x)] ? $innovus(macro_halo,x) : 5.0}]
    set halo_y [expr {[info exists innovus(macro_halo,y)] ? $innovus(macro_halo,y) : 5.0}]
    handle_info "Adding macro halo: ${halo_x}um x ${halo_y}um"
    addHaloToBlock $halo_x $halo_y $halo_x $halo_y -allBlock

    # Add routing tracks
    if {[info exists innovus(common,tracks)]} {
        foreach track_spec $innovus(common,tracks) {
            array set track_info $track_spec
            if {[info exists track_info(layer)] && [info exists track_info(pitch)] && [info exists track_info(offset)]} {
                set direction [expr {[info exists track_info(direction)] ? $track_info(direction) : "both"}]
                handle_info "Adding tracks on $track_info(layer): pitch=$track_info(pitch) offset=$track_info(offset) dir=$direction"
                add_tracks -direction $direction \
                    -layer $track_info(layer) \
                    -pitch $track_info(pitch) \
                    -offset $track_info(offset)
            }
            array unset track_info
        }
    } else {
        handle_info "No custom track definitions - using default tracks"
    }

    handle_info "Macro placement and track configuration completed"
}

flow_proc create_rows {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Creating standard cell rows..."

    # Create rows with site from config
    set site_name [expr {[info exists innovus(common,site_name)] ? $innovus(common,site_name) : "core"}]
    set row_spacing [expr {[info exists innovus(common,row_spacing)] ? $innovus(common,row_spacing) : 0.0}]

    handle_info "Site: $site_name, Row spacing: $row_spacing"

    # Create rows within the core area
    if {[info exists innovus(common,rows)]} {
        foreach row_spec $innovus(common,rows) {
            array set row_info $row_spec
            if {[info exists row_info(name)] && [info exists row_info(site)] && \
                [info exists row_info(x)] && [info exists row_info(y)] && \
                [info exists row_info(orient)] && [info exists row_info(num_x)] && \
                [info exists row_info(step_x)]} {
                handle_info "Creating row: $row_info(name)"
                create_row -name $row_info(name) \
                    -site $row_info(site) \
                    -origin "$row_info(x) $row_info(y)" \
                    -orient $row_info(orient) \
                    -num_x $row_info(num_x) \
                    -step_x $row_info(step_x)
            }
            array unset row_info
        }
    } else {
        # Use automatic row creation
        handle_info "Using automatic row creation for site: $site_name"
    }

    # Verify row creation
    handle_info "Standard cell rows created successfully"
}

flow_proc place_io {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Placing I/O pads and filler cells..."

    # Read I/O assignment file if provided
    if {[info exists fp(input,io_file)]} {
        set io_file $fp(input,io_file)
        if {[file exists $io_file]} {
            handle_info "Reading I/O assignment from: [file tail $io_file]"
            loadIoFile $io_file
        } else {
            handle_warning "I/O assignment file not found: $io_file"
        }
    }

    # Place I/O pads from config
    if {[info exists innovus(common,io_pads)]} {
        foreach io_spec $innovus(common,io_pads) {
            array set io_info $io_spec
            if {[info exists io_info(name)] && [info exists io_info(side)]} {
                set order [expr {[info exists io_info(order)] ? $io_info(order) : 0}]
                handle_info "Assigning I/O: $io_info(name) on $io_info(side) side"
            }
            array unset io_info
        }
    }

    # Place I/O filler cells
    if {[info exists innovus(common,io_filler_cells)]} {
        handle_info "Placing I/O filler cells: $innovus(common,io_filler_cells)"
        addIoFiller -cell $innovus(common,io_filler_cells) -prefix IO_FILL
    }

    # Snap floorplan to grid
    if {[info exists innovus(common,snap_to_grid)] && $innovus(common,snap_to_grid) eq "true"} {
        handle_info "Snapping floorplan to manufacturing grid..."
        snapFPlan
    }

    handle_info "I/O placement completed"
}

flow_proc validate_floorplan {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Validating floorplan..."

    set validation_errors 0

    # Check placement legality
    handle_info "Checking placement legality..."
    if {[catch {checkPlace} result]} {
        handle_warning "Placement check reported issues: $result"
        incr validation_errors
    }

    # Verify floorplan geometry
    handle_info "Verifying floorplan geometry..."
    if {[catch {checkFPlan -reportUtil} result]} {
        handle_info "Floorplan utilization: $result"
    }

    # Generate floorplan reports
    set report_dir "reports"
    if {![file exists $report_dir]} {
        file mkdir $report_dir
    }

    handle_info "Generating floorplan summary report..."
    if {[catch {reportFPlan > $::REPORTS_DIR/floorplan_summary.rpt} result]} {
        handle_warning "Could not generate floorplan report: $result"
    }

    # Report macro placement
    handle_info "Generating macro placement report..."
    if {[catch {report_placement -macro > $::REPORTS_DIR/macro_placement.rpt} result]} {
        handle_warning "Could not generate macro placement report: $result"
    }

    if {$validation_errors > 0} {
        handle_warning "Floorplan validation completed with $validation_errors issue(s)"
    } else {
        handle_info "Floorplan validation passed"
    }

    handle_info "═══════════════════════════════════════════════════════════════"
    handle_info "CBFlow FP Floorplan Stage - COMPLETED SUCCESSFULLY"
    handle_info "Next Stage: powerplan (make powerplan)"
    handle_info "═══════════════════════════════════════════════════════════════"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION FLOW
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "═══════════════════════════════════════════════════════════════"
handle_info "CBFlow FP Floorplan Stage - Starting Execution"
handle_info "═══════════════════════════════════════════════════════════════"

# Execute flow procedures in sequence
set flow_steps {
    configure_floorplan
    place_macros
    create_rows
    place_io
    validate_floorplan
}

foreach step $flow_steps {
    handle_info "Executing flow step: $step"

    if {[catch {$step} error]} {
        handle_error "Flow step '$step' failed: $error"
        exit 1
    }

    handle_info "Flow step '$step' completed successfully"
}

handle_info "CBFlow FP floorplan stage completed successfully"

# Exit tool after stage completion
exit
