#!/usr/bin/env tclsh
# CBFlow SYNTH release_data1 - Synopsys Fusion Compiler | SYNTH release_data1
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME



# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }
# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }
# ==============================================================================
# flow_proc: init_release
# Initialize release and validate mandatory variables
# ==============================================================================
flow_proc init_release {
    handle_info "Initializing release..."
    global synth project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists synth(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (synth(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists synth(common,design_name)] ? $synth(common,design_name) : [expr {[info exists flow(design_name)] ? $flow(design_name) : "synth"}]}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists synth(common,release_phase)]} { set release_phase $synth(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "SYNTH" $design_name $run_dir $release_phase
    } else {
        set ::release_dir "$run_dir/release/SYNTH"
        foreach subdir {reports data netlist sdc db} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    set _release_tag [expr {[info exists project(release,tag)] ? $project(release,tag) : "(unset)"}]
    handle_info "Release tag: $_release_tag"
}

# ==============================================================================
# flow_proc: prepare_release
# Description: Prepare release directory structure and copy deliverables
# ==============================================================================
flow_proc prepare_release {
    handle_info "Preparing synthesis release data..."
    global synth project

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Create release directory structure
    set release_dir "$run_dir/results/release"
    foreach subdir {
        "netlist"
        "sdc"
        "db"
        "reports"
        "reports/timing"
        "reports/area"
        "reports/power"
        "reports/qor"
    } {
        file mkdir "$release_dir/$subdir"
    }

    handle_info "Release directory structure created at $release_dir"

    # Determine design name
    if {[info exists synth(common,design_name)]} {
        set dname $synth(common,design_name)
    } else {
        set dname "synth"
    }

    # Copy netlist
    set nl_src "$run_dir/results/synth/netlist/${dname}.v"
    if {[file exists $nl_src]} {
        file copy -force $nl_src "$release_dir/netlist/${dname}.v"
        handle_info "Copied netlist to release"
    } else {
        handle_warning "Netlist not found: $nl_src"
    }

    # Copy functional netlist
    set nl_func_src "$run_dir/results/synth/netlist/synth_func.v"
    if {[file exists $nl_func_src]} {
        file copy -force $nl_func_src "$release_dir/netlist/synth_func.v"
        handle_info "Copied functional netlist to release"
    }

    # Copy SDC
    set sdc_src "$run_dir/results/synth/sdc/${dname}.sdc"
    if {[file exists $sdc_src]} {
        file copy -force $sdc_src "$release_dir/sdc/${dname}.sdc"
        handle_info "Copied SDC to release"
    } else {
        handle_warning "SDC not found: $sdc_src"
    }

    # Copy design database (NDM)
    set db_src "$run_dir/results/synth/db/synth.nlib"
    if {[file exists $db_src]} {
        file copy -force $db_src "$release_dir/db/synth.nlib"
        handle_info "Copied design database to release"
    }

    # Copy synthesis reports categorized into subdirectories
    set rpt_src "$run_dir/results/synth/reports"
    if {[file isdirectory $rpt_src]} {
        set rpt_files [glob -nocomplain -directory $rpt_src *.rpt]
        foreach rpt $rpt_files {
            set rpt_name [file tail $rpt]
            if {[string match "*timing*" $rpt_name]} {
                file copy -force $rpt "$release_dir/reports/timing/$rpt_name"
            } elseif {[string match "*area*" $rpt_name] || [string match "*utilization*" $rpt_name]} {
                file copy -force $rpt "$release_dir/reports/area/$rpt_name"
            } elseif {[string match "*power*" $rpt_name]} {
                file copy -force $rpt "$release_dir/reports/power/$rpt_name"
            } else {
                file copy -force $rpt "$release_dir/reports/qor/$rpt_name"
            }
        }
        handle_info "Copied [llength $rpt_files] reports to release"
    }

    handle_info "Release data preparation completed"
}

# ==============================================================================
# flow_proc: validate_release
# Description: Validate release completeness and integrity
# ==============================================================================
flow_proc validate_release {
    handle_info "Validating release data..."
    global synth

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
    if {[info exists synth(common,design_name)]} {
        set dname $synth(common,design_name)
    } else {
        set dname "synth"
    }

    # Define required deliverables
    set required_files [list \
        "netlist/${dname}.v" \
        "sdc/${dname}.sdc" \
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

    # Final release status
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
    global synth project

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
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
