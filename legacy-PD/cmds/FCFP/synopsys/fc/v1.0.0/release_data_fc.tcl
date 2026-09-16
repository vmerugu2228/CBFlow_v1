#!/usr/bin/env tclsh
# CBFlow FCFP release_data - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "release_data"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME



# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }
# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global fcfp project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists fcfp(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (fcfp(common,design_name) or flow(design_name))"
    }
    if {![info exists project(release,tag)] || $project(release,tag) eq ""} {
        lappend missing_vars "project(release,tag) in project_config.tcl"
    }
    if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
        lappend missing_vars "FLOW_DIR"
    }
    if {![info exists ::env(CONFIG_ROOT)] || $::env(CONFIG_ROOT) eq ""} {
        lappend missing_vars "CONFIG_ROOT"
    }

    if {[llength $missing_vars] > 0} {
        handle_warning "Missing mandatory variables for release:"
        foreach v $missing_vars { handle_warning "  - $v" }
        handle_warning "Release may be incomplete"
    }

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "fcfp"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists fcfp(common,release_phase)]} { set release_phase $fcfp(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "FCFP" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/FCFP"
        foreach subdir {reports data def netlist sdc budgets} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    set _release_tag [expr {[info exists project(release,tag)] ? $project(release,tag) : "(unset)"}]
    handle_info "Release tag: $_release_tag"
}

# ==============================================================================
# flow_proc: prepare_release
# Stage FCFP deliverables into release directory
# ==============================================================================
flow_proc prepare_release {
    handle_info "Preparing FCFP release..."
    global fcfp project

    set run_dir $::env(CBFLOW_RUN_DIR)
    set rd "$run_dir/results/release"

    foreach d {"def" "def/partitions" "reports" "reports/fcfp" "netlist" "sdc" "budgets"} {
        file mkdir "$rd/$d"
    }

    # Release DEF files
    foreach def [glob -nocomplain "$run_dir/results/fcfp/def/*.def"] {
        catch {file copy -force $def "$rd/def/[file tail $def]"}
        handle_info "Released: [file tail $def]"
    }

    # Release partition DEFs
    foreach def [glob -nocomplain "$run_dir/results/fcfp/def/partitions/*.def"] {
        catch {file copy -force $def "$rd/def/partitions/[file tail $def]"}
    }

    # Release netlist
    if {[file exists "$run_dir/results/fcfp/fcfp_floorplan.v"]} {
        catch {file copy -force "$run_dir/results/fcfp/fcfp_floorplan.v" "$rd/netlist/"}
    }

    # Release SDC
    if {[file exists "$run_dir/results/fcfp/fcfp_floorplan.sdc"]} {
        catch {file copy -force "$run_dir/results/fcfp/fcfp_floorplan.sdc" "$rd/sdc/"}
    }

    # Release timing budgets
    foreach sdc [glob -nocomplain "$run_dir/results/fcfp/timing_budgets/*/*.sdc" "$run_dir/results/fcfp/timing_budgets/*.sdc"] {
        catch {file copy -force $sdc "$rd/budgets/[file tail $sdc]"}
    }

    # Release reports
    foreach subdir {"create_floorplan" "shaping" "placement" "create_power" "place_pins" "top_compile" "timing_budget"} {
        set src "$run_dir/results/fcfp/reports/$subdir"
        if {[file isdirectory $src]} {
            file mkdir "$rd/reports/fcfp/$subdir"
            foreach rpt [glob -nocomplain "$src/*.rpt"] {
                catch {file copy -force $rpt "$rd/reports/fcfp/$subdir/[file tail $rpt]"}
            }
        }
    }

    handle_info "FCFP release prepared"
}

# ==============================================================================
# flow_proc: validate_release
# Validate release deliverables are complete
# ==============================================================================
flow_proc validate_release {
    handle_info "Validating FCFP release..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set rd "$run_dir/results/release"
    set errors 0

    # Validate using release_config mandatory file lists
    if {[namespace exists ::CBFlow::Release]} {
        set valid [::CBFlow::Release::validate_mandatory_files]
        if {!$valid} {
            handle_warning "Some mandatory files are missing — check release phase requirements"
        }
    }

    if {![file exists "$rd/def/fcfp_floorplan.def"]} {
        handle_error "Missing floorplan DEF in release"
        incr errors
    }

    # Validate file sizes
    foreach f [glob -nocomplain "$rd/def/*.def"] {
        if {[file size $f] == 0} {
            handle_warning "Empty DEF file: [file tail $f]"
        }
    }

    set released_rpts [glob -nocomplain "$rd/reports/fcfp/*.rpt" "$rd/reports/fcfp/*/*.rpt"]
    handle_info "Released [llength $released_rpts] FCFP reports"

    if {$errors > 0} {
        handle_error "FCFP release validation failed with $errors errors"
        return -code error "Release validation failed"
    }

    handle_info "FCFP release validation passed"
}

# ==============================================================================
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ==============================================================================
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global fcfp project

    set notes ""
    if {[info exists project(release_notes)]} { set notes $project(release_notes) }

    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::generate_manifest
        ::CBFlow::Release::generate_release_notes $notes
        ::CBFlow::Release::stamp_complete
        ::CBFlow::Release::summary
    } else {
        handle_info "Release utilities not loaded — skipping output generation"
    }

    handle_info "Release output generated"
}

# ==============================================================================
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
