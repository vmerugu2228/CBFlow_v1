#!/usr/bin/env tclsh
# CBFlow FP release_data - Synopsys Fusion Compiler | FP release_data
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: prepare_release
# Description: Prepare release directory and copy all FP deliverables
# ==============================================================================
flow_proc prepare_release {
    handle_info "Preparing FP release data..."
    global fp project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists fp(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (fp(common,design_name) or flow(design_name))"
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

    # Determine design name
    if {[info exists fp(common,design_name)]} {
        set dname $fp(common,design_name)
    } elseif {[info exists flow(design_name)]} {
        set dname $flow(design_name)
    } else {
        set dname "floorplan"
    }

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists fp(common,release_phase)]} { set release_phase $fp(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "FP" $dname $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/FP"
        foreach subdir {reports data def db} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"

    # Create legacy release directory structure
    set release_dir "$run_dir/results/release"
    foreach subdir {
        "def"
        "db"
        "reports"
        "reports/floorplan"
        "reports/powerplan"
        "reports/timing"
        "reports/congestion"
    } {
        file mkdir "$release_dir/$subdir"
    }

    handle_info "Release directory structure created at $release_dir"

    # Copy DEF
    set def_src "$run_dir/results/fp/def/${dname}.def"
    if {[file exists $def_src]} {
        file copy -force $def_src "$release_dir/def/${dname}.def"
        handle_info "Copied DEF to release"
    } else {
        handle_warning "DEF not found: $def_src"
    }

    # Copy design library
    set db_src "$run_dir/results/fp/db/fp.nlib"
    if {[file exists $db_src]} {
        file copy -force $db_src "$release_dir/db/fp.nlib"
        handle_info "Copied design library to release"
    }

    # Copy floorplan reports categorized by type
    set rpt_src "$run_dir/results/fp/reports"
    if {[file isdirectory $rpt_src]} {
        foreach rpt_subdir {floorplan powerplan post_floorplan} {
            set sub_src "$rpt_src/$rpt_subdir"
            if {[file isdirectory $sub_src]} {
                set rpt_files [glob -nocomplain -directory $sub_src *.rpt]
                foreach rpt $rpt_files {
                    set rpt_name [file tail $rpt]
                    if {[string match "*timing*" $rpt_name] || [string match "*clock*" $rpt_name]} {
                        file copy -force $rpt "$release_dir/reports/timing/$rpt_name"
                    } elseif {[string match "*congestion*" $rpt_name] || [string match "*overflow*" $rpt_name]} {
                        file copy -force $rpt "$release_dir/reports/congestion/$rpt_name"
                    } elseif {[string match "*pg*" $rpt_name] || [string match "*power*" $rpt_name]} {
                        file copy -force $rpt "$release_dir/reports/powerplan/$rpt_name"
                    } else {
                        file copy -force $rpt "$release_dir/reports/floorplan/$rpt_name"
                    }
                }
            }
        }
        handle_info "Reports copied to release"
    }

    handle_info "Release data preparation completed"
}

# ==============================================================================
# flow_proc: validate_release
# Description: Validate release completeness
# ==============================================================================
flow_proc validate_release {
    handle_info "Validating release data..."
    global fp flow

    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release"
    set release_pass true

    # Validate using release_config mandatory file lists
    if {[namespace exists ::CBFlow::Release]} {
        set valid [::CBFlow::Release::validate_mandatory_files]
        if {!$valid} {
            handle_warning "Some mandatory files are missing — check release phase requirements"
        }
    }

    # Determine design name
    if {[info exists fp(common,design_name)]} {
        set dname $fp(common,design_name)
    } elseif {[info exists flow(design_name)]} {
        set dname $flow(design_name)
    } else {
        set dname "floorplan"
    }

    # Define required deliverables
    set required_files [list \
        "def/${dname}.def" \
    ]

    # Verify each required file
    foreach rel_path $required_files {
        set full_path "$release_dir/$rel_path"
        if {[file exists $full_path]} {
            set fsize [file size $full_path]
            if {$fsize == 0} {
                handle_warning "Release file is empty: $rel_path"
                set release_pass false
            } else {
                handle_info "Verified: $rel_path ($fsize bytes)"
            }
        } else {
            handle_warning "Missing required release file: $rel_path"
            set release_pass false
        }
    }

    # Check for reports
    set report_count 0
    foreach rpt_dir {reports/floorplan reports/powerplan reports/timing reports/congestion} {
        set rpt_path "$release_dir/$rpt_dir"
        if {[file isdirectory $rpt_path]} {
            set rpts [glob -nocomplain -directory $rpt_path *.rpt]
            set report_count [expr {$report_count + [llength $rpts]}]
        }
    }
    handle_info "Release includes $report_count report files"

    # Final status
    if {$release_pass} {
        handle_info "RELEASE VALIDATION PASSED: All required deliverables present"
    } else {
        handle_warning "RELEASE VALIDATION FAILED: Some deliverables are missing or empty"
    }

    handle_info "Release validation completed"
}

# ==============================================================================
# flow_proc: generate_release_output
# Generate manifest, release notes, and completion stamp via release utilities
# ==============================================================================
flow_proc generate_release_output {
    handle_info "Generating release output..."
    global fp project

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

# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
