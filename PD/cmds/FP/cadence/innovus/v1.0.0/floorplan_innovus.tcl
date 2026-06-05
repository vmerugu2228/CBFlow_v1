#!/usr/bin/env tclsh
# ==============================================================================
# FP floorplan — Cadence Innovus
# Description: Load design from init_design, create floorplan, place macros,
#              add boundary/tap cells, save to outputs/
# ==============================================================================

# ── Bootstrap ─────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "floorplan"
set NODE_NAME "floorplan1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting CBflow FP floorplan for Innovus"

# ==============================================================================
# flow_proc: load_design
# Description: Restore design database from init_design stage
# ==============================================================================
flow_proc load_design {
    global run_dir flow

    set _db "$run_dir/work/FP/init_design1/outputs/init_design.enc.dat"
    if {![file exists $_db]} {
        handle_error "init_design database not found: $_db"
        exit 1
    }
    handle_info "Restoring design: $_db"
    restoreDesign $_db $flow(design_name)
    handle_info "Design restored: $flow(design_name)"
}

# ==============================================================================
# flow_proc: create_floorplan
# Description: Initialize floorplan — die size or utilization-based
# ==============================================================================
flow_proc create_floorplan {
    global fp project

    handle_info "Creating floorplan..."

    # Floorplan parameters — all from config
    if {![info exists fp(common,site_name)] || $fp(common,site_name) eq ""} {
        handle_error "fp(common,site_name) not set"
        exit 1
    }

    set _site $fp(common,site_name)

    if {[info exists fp(die,width)] && [info exists fp(die,height)]} {
        # Explicit die size
        if {![info exists fp(core,margin_left)]} {
            handle_error "fp(core,margin_left/bottom/right/top) not set"
            exit 1
        }
        handle_info "  Die: $fp(die,width) x $fp(die,height)"
        floorPlan -site $_site \
            -d $fp(die,width) $fp(die,height) \
               $fp(core,margin_left) $fp(core,margin_bottom) \
               $fp(core,margin_right) $fp(core,margin_top)
    } else {
        # Utilization-based
        if {![info exists fp(common,utilization)] || ![info exists fp(common,aspect_ratio)]} {
            handle_error "fp(common,utilization) and fp(common,aspect_ratio) not set"
            exit 1
        }
        handle_info "  Util=$fp(common,utilization) AR=$fp(common,aspect_ratio)"
        floorPlan -site $_site \
            -r $fp(common,aspect_ratio) $fp(common,utilization) \
               $fp(core,margin_left) $fp(core,margin_bottom) \
               $fp(core,margin_right) $fp(core,margin_top)
    }

    handle_info "Floorplan created"
}

# ==============================================================================
# flow_proc: place_macros
# Description: Place macros from placement file or config specs
# ==============================================================================
flow_proc place_macros {
    global fp

    handle_info "Placing macros..."

    # Macro placement file (user provides TCL with placeInstance commands)
    if {[info exists fp(input,macro_placement)] && $fp(input,macro_placement) ne ""} {
        if {[file exists $fp(input,macro_placement)]} {
            handle_info "  Sourcing: [file tail $fp(input,macro_placement)]"
            source $fp(input,macro_placement)
        } else {
            handle_error "Macro placement file not found: $fp(input,macro_placement)"
            exit 1
        }
    }

    # Inline macro specs from config
    if {[info exists fp(common,macros)]} {
        foreach macro_spec $fp(common,macros) {
            array set m $macro_spec
            if {[info exists m(name)] && [info exists m(x)] && [info exists m(y)]} {
                set orient [expr {[info exists m(orient)] ? $m(orient) : "R0"}]
                handle_info "  $m(name) at ($m(x),$m(y)) $orient"
                placeInstance $m(name) $m(x) $m(y) $orient -placed
            }
            array unset m
        }
    }

    # Macro halo
    if {[info exists fp(macro_halo,x)] && [info exists fp(macro_halo,y)]} {
        handle_info "  Halo: $fp(macro_halo,x)um x $fp(macro_halo,y)um"
        addHaloToBlock $fp(macro_halo,x) $fp(macro_halo,y) $fp(macro_halo,x) $fp(macro_halo,y) -allBlock
    }

    handle_info "Macro placement done"
}

# ==============================================================================
# flow_proc: add_endcaps_welltaps
# Description: Insert boundary cells and well taps
# ==============================================================================
flow_proc add_endcaps_welltaps {
    global fp tech

    handle_info "Adding endcaps and well taps..."

    # Endcaps
    if {[info exists tech($::project(track_variant),endcap)] && $tech($::project(track_variant),endcap) ne ""} {
        set _endcap $tech($::project(track_variant),endcap)
        handle_info "  Endcap: $_endcap"
        setEndCap -prefix ENDCAP -cell $_endcap
        addEndCap
    }

    # Well taps
    if {[info exists tech($::project(track_variant),well_tap)] && $tech($::project(track_variant),well_tap) ne ""} {
        set _welltap $tech($::project(track_variant),well_tap)
        if {![info exists fp(welltap,interval)] || $fp(welltap,interval) eq ""} {
            handle_error "fp(welltap,interval) not set — required for well tap insertion"
            exit 1
        }
        handle_info "  Well tap: $_welltap every $fp(welltap,interval)um"
        addWellTap -cell $_welltap -cellInterval $fp(welltap,interval) -prefix WELLTAP
    }

    handle_info "Endcaps and well taps added"
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Floorplan reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating floorplan reports..."
    file mkdir "$::REPORTS_DIR"

    catch { reportFPlan > "$::REPORTS_DIR/floorplan_summary.rpt" }
    catch { report_placement -macro > "$::REPORTS_DIR/macro_placement.rpt" }
    catch { checkPlace > "$::REPORTS_DIR/check_placement.rpt" }
    catch { report_area -outfile "$::REPORTS_DIR/report_area.rpt" }

    handle_info "Reports: $::REPORTS_DIR/"
}

# ==============================================================================
# flow_proc: save_design
# Description: Save database to outputs/ for next stage
# ==============================================================================
flow_proc save_design {
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs

    saveDesign "$_outputs/floorplan.enc"
    handle_info "Design saved: $_outputs/floorplan.enc"
}

# ==============================================================================
# Source setup hooks
# ==============================================================================
foreach _hook [list \
    "$run_dir/setup/override_setup.tcl" \
    "$run_dir/setup/override_setup.floorplan.tcl" \
] {
    if {[file exists $_hook]} {
        handle_info "Sourcing hook: [file tail $_hook]"
        source $_hook
    }
}

# ==============================================================================
# Execute
# ==============================================================================
handle_info "================================================================"
handle_info "CBflow FP floorplan — Innovus"
handle_info "================================================================"

foreach step {
    load_design
    create_floorplan
    place_macros
    add_endcaps_welltaps
    generate_reports
    save_design
} {
    handle_info "── $step ──"
    if {[catch {$step} err]} {
        handle_error "Step '$step' failed: $err"
        exit 1
    }
}

handle_info "FP floorplan completed"
