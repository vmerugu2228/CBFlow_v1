#!/usr/bin/env tclsh
# ==============================================================================
# FP floorplan — Cadence Innovus
# Description: Load design, load floorplan (.fp or .def), optional pin placement,
#              save to outputs/
# User provides floorplan/pin files in override_setup.floorplan.tcl or user_config
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
# Description: Restore design from init_design stage
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
# flow_proc: load_floorplan
# Description: Load floorplan from .fp file or .def file
#   Config: fp(input,floorplan_file) — Innovus .fp file (loadFPlan)
#           fp(input,def_file)       — DEF file (defIn)
# ==============================================================================
flow_proc load_floorplan {
    global fp

    if {[info exists fp(input,floorplan_file)] && $fp(input,floorplan_file) ne ""} {
        if {![file exists $fp(input,floorplan_file)]} {
            handle_error "Floorplan file not found: $fp(input,floorplan_file)"
            exit 1
        }
        handle_info "Loading floorplan: [file tail $fp(input,floorplan_file)]"
        loadFPlan $fp(input,floorplan_file)
    } elseif {[info exists fp(input,def_file)] && $fp(input,def_file) ne ""} {
        if {![file exists $fp(input,def_file)]} {
            handle_error "DEF file not found: $fp(input,def_file)"
            exit 1
        }
        handle_info "Loading DEF: [file tail $fp(input,def_file)]"
        defIn $fp(input,def_file)
    } else {
        handle_info "No floorplan or DEF file provided — starting with empty floorplan"
        handle_info "  Set fp(input,floorplan_file) or fp(input,def_file) in user_config"
    }

    handle_info "Floorplan loaded"
}

# ==============================================================================
# flow_proc: place_pins
# Description: Optional pin placement from user-provided file
#   Config: fp(input,pin_placement_file) — TCL script with pin commands
# ==============================================================================
flow_proc place_pins {
    global fp

    if {[info exists fp(input,pin_placement_file)] && $fp(input,pin_placement_file) ne ""} {
        if {[file exists $fp(input,pin_placement_file)]} {
            handle_info "Loading pin placement: [file tail $fp(input,pin_placement_file)]"
            source $fp(input,pin_placement_file)
        } else {
            handle_error "Pin placement file not found: $fp(input,pin_placement_file)"
            exit 1
        }
    } else {
        handle_info "No pin placement file — skipping (set fp(input,pin_placement_file) to enable)"
    }
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
# Source setup hooks (user overrides — applied AFTER flow_proc defs)
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
    load_floorplan
    place_pins
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
