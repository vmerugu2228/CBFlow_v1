#!/usr/bin/env tclsh
# ==============================================================================
# PNR cts — Cadence Innovus
# Description: Clock tree synthesis using CCOpt engine.
#   Follows Cadence Foundation Flow:
#     NDR setup → create_ccopt_clock_tree_spec → clock_opt_design -cts
# ==============================================================================

# ── Bootstrap ─────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "cts"
set NODE_NAME "cts1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting CBflow PNR CTS for Innovus"

# ==============================================================================
# flow_proc: load_design
# Description: Restore design from place stage
# ==============================================================================
flow_proc load_design {
    global run_dir flow

    set _db [cbflow_resolve_head_block "$run_dir/work/$::FLOW_TYPE/place1/outputs/placement.enc.dat" {place init_design}]
    if {![file exists $_db]} {
        handle_warning "place database not found: $_db"
        return
    }
    handle_info "Restoring design: $_db"
    restoreDesign $_db $flow(design_name)
    handle_info "Design restored: $flow(design_name)"
}


# ==============================================================================
# flow_proc: activate_node_scenarios
# Description: Set MMMC scenarios for CTS stage
# ==============================================================================
flow_proc activate_node_scenarios {
    global mmmc STAGE_NAME

    if {![info exists mmmc($STAGE_NAME)]} {
        handle_info "No node-specific scenarios for $STAGE_NAME"
        return
    }

    handle_info "Activating scenarios for: $STAGE_NAME"
    array set _nd $mmmc($STAGE_NAME)
    set _setup [expr {[info exists _nd(setup)] ? $_nd(setup) : {}}]
    set _hold  [expr {[info exists _nd(hold)]  ? $_nd(hold)  : {}}]

    handle_info "  Setup: $_setup"
    handle_info "  Hold:  $_hold"

    set_analysis_view -setup {} -hold {}
    set_analysis_view -setup $_setup -hold $_hold
}

# ==============================================================================
# flow_proc: setup_ndr
# Description: Source NDR script — add_ndr, create_route_type, set_ccopt_property
# ==============================================================================
flow_proc setup_ndr {
    global pnr

    # Source the Cadence NDR script
    set ndr_script "$::env(FLOW_DIR)/cmds/$::FLOW_TYPE/cadence/innovus/v1.0.0/scripts/cts_ndr.tcl"

    # Allow user override
    if {[info exists pnr(cts,ndr_script)] && $pnr(cts,ndr_script) ne ""} {
        set ndr_script $pnr(cts,ndr_script)
    }

    # Only source the NDR script if the user has actually configured NDR
    # knobs. The script's mandatory-knob checks otherwise fire and crash
    # the cts stage for designs that don't need a custom NDR.
    set _ndr_configured [expr {[info exists pnr(cts,ndr_name)] && $pnr(cts,ndr_name) ne ""}]
    if {!$_ndr_configured} {
        handle_info "NDR not configured (pnr(cts,ndr_name) unset) — skipping NDR setup"
    } elseif {[file exists $ndr_script]} {
        handle_info "Sourcing CTS NDR: [file tail $ndr_script]"
        source $ndr_script
    } else {
        handle_warning "CTS NDR script not found: $ndr_script"
        handle_warning "CTS will run without NDR rules"
    }
}

# ==============================================================================
# flow_proc: create_clock_spec
# Description: Generate and source ccopt clock tree specification
#   Reference: create_ccopt_clock_tree_spec -file ccopt.spec
#              source ccopt.spec
# ==============================================================================
flow_proc create_clock_spec {
    global pnr

    handle_info "Creating clock tree specification..."

    set spec_file "$::WORK_DIR/scripts/ccopt.spec"
    file mkdir [file dirname $spec_file]

    create_ccopt_clock_tree_spec -file $spec_file
    handle_info "Clock spec generated: $spec_file"

    source $spec_file
    handle_info "Clock spec sourced"
}

# ==============================================================================
# flow_proc: run_cts
# Description: Run Innovus CTS engine
#   Reference: clock_opt_design -cts
# ==============================================================================
flow_proc run_cts {
    handle_info "Running clock_opt_design -cts..."

    clock_opt_design -cts

    handle_info "CTS completed"
}

# ==============================================================================
# flow_proc: post_cts_timing
# Description: Post-CTS timing analysis
#   Reference: timeDesign -postCTS
# ==============================================================================
flow_proc post_cts_timing {
    handle_info "Running post-CTS timing..."

    timeDesign -postCTS -outDir "$::REPORTS_DIR" -prefix postCTS_setup
    timeDesign -postCTS -hold -outDir "$::REPORTS_DIR" -prefix postCTS_hold

    handle_info "Post-CTS timing done"
}

# ==============================================================================
# flow_proc: generate_reports
# Description: CTS reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating CTS reports..."

    file mkdir "$::REPORTS_DIR"

    catch { report_ccopt_skew_groups > "$::REPORTS_DIR/ccopt_skew_groups.rpt" }
    catch { report_ccopt_clock_trees > "$::REPORTS_DIR/ccopt_clock_trees.rpt" }
    catch { report_clock_timing -type summary > "$::REPORTS_DIR/clock_timing_summary.rpt" }
    catch { report_power -outfile "$::REPORTS_DIR/report_power.rpt" }

    handle_info "Reports: $::REPORTS_DIR/"
}

# ==============================================================================
# flow_proc: save_design
# Description: Save CTS checkpoint
#   Reference: saveDesign DBS/cts.enc
# ==============================================================================
flow_proc save_design {
    set _outputs "$::WORK_DIR/outputs"
    file mkdir $_outputs
    saveDesign "$_outputs/cts.enc"
    cbflow_record_block_state $::STAGE_NAME "$_outputs/cts.enc.dat" $::NODE_NAME
    handle_info "Design saved: $_outputs/cts.enc"
}

# ==============================================================================
# Execute — Cadence Foundation Flow CTS sequence
# ==============================================================================
handle_info "================================================================"
handle_info "CBflow PNR CTS — Innovus"
handle_info "================================================================"

flow_exec_all

handle_info "PNR CTS completed"
