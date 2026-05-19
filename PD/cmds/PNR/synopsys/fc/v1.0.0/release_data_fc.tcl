#!/usr/bin/env tclsh
# CBFlow PNR release_data1 - Synopsys Fusion Compiler | PNR release_data1
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global pnr project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source release utilities
set release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $release_utils]} { source $release_utils }

# Source release_config for phase/milestone file expectations
set release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $release_config]} { source $release_config }

# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR release_data1 with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set WORK_DIR "$run_dir/work/PNR/release_data1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: prepare_release
# Description: Prepare release directory structure and copy deliverables
# ==============================================================================
flow_proc prepare_release {
    handle_info "Preparing release data..."
    global pnr project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists fc(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (fc(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists fc(common,release_phase)]} { set release_phase $fc(common,release_phase) }
    if {[info exists project(release,phase)] && $project(release,phase) ne ""} { set release_phase $project(release,phase) }

    # ── Initialize release using utilities ───────────────────────────────────
    if {[namespace exists ::CBFlow::Release]} {
        ::CBFlow::Release::init "PNR" $design_name $run_dir $release_phase
    } else {
        # Fallback if release_utils not available
        set ::release_dir "$run_dir/release/PNR"
        foreach subdir {reports data netlist def gds spef sdc upf db} {
            file mkdir "$::release_dir/$subdir"
        }
    }

    handle_info "Release phase: $release_phase"
    handle_info "Release tag: $project(release,tag)"

    # Create legacy release directory structure
    set release_dir "$run_dir/results/release"
    foreach subdir {
        "netlist"
        "netlist/pg"
        "def"
        "gds"
        "spef"
        "sdc"
        "sdf"
        "reports"
        "reports/timing"
        "reports/power"
        "reports/drc"
        "reports/qor"
    } {
        file mkdir "$release_dir/$subdir"
    }

    handle_info "Release directory structure created at $release_dir"

    # Copy GDS
    set gds_src "$run_dir/results/pnr/gds/$fc(common,design_name).gds"
    if {[file exists $gds_src]} {
        file copy -force $gds_src "$release_dir/gds/$fc(common,design_name).gds"
        handle_info "Copied GDS to release"
    } else {
        handle_warning "GDS source not found: $gds_src"
    }

    # Copy netlists
    foreach suffix [list "" "_pg"] {
        set nl_src "$run_dir/results/pnr/netlist/$fc(common,design_name)${suffix}.v"
        if {$suffix eq "_pg"} {
            set nl_dst "$release_dir/netlist/pg/$fc(common,design_name)_pg.v"
        } else {
            set nl_dst "$release_dir/netlist/$fc(common,design_name).v"
        }
        if {[file exists $nl_src]} {
            file copy -force $nl_src $nl_dst
            handle_info "Copied netlist${suffix} to release"
        }
    }

    # Copy SDF
    set sdf_src "$run_dir/results/pnr/netlist/$fc(common,design_name).sdf"
    if {[file exists $sdf_src]} {
        file copy -force $sdf_src "$release_dir/sdf/$fc(common,design_name).sdf"
        handle_info "Copied SDF to release"
    }

    # Copy DEF
    set def_src "$run_dir/results/pnr/def/$fc(common,design_name).def"
    if {[file exists $def_src]} {
        file copy -force $def_src "$release_dir/def/$fc(common,design_name).def"
        handle_info "Copied DEF to release"
    }

    # Copy SDC
    set sdc_src "$run_dir/results/pnr/sdc/$fc(common,design_name).sdc"
    if {[file exists $sdc_src]} {
        file copy -force $sdc_src "$release_dir/sdc/$fc(common,design_name).sdc"
        handle_info "Copied SDC to release"
    }

    # Copy SPEF files (all corners)
    foreach corner {max min nom} {
        set spef_src "$run_dir/results/pnr/spef/$fc(common,design_name)_${corner}.spef"
        if {[file exists $spef_src]} {
            file copy -force $spef_src "$release_dir/spef/$fc(common,design_name)_${corner}.spef"
            handle_info "Copied SPEF ($corner) to release"
        }
    }

    # Copy signoff reports to release
    foreach rpt_pattern {
        "signoff_timing_setup.rpt"
        "signoff_timing_hold.rpt"
        "signoff_qor.rpt"
        "signoff_drc.rpt"
        "signoff_power.rpt"
        "signoff_antenna.rpt"
    } {
        set rpt_src "$run_dir/reports/pnr/$rpt_pattern"
        if {[file exists $rpt_src]} {
            # Categorize reports into subdirectories
            if {[string match "*timing*" $rpt_pattern]} {
                file copy -force $rpt_src "$release_dir/reports/timing/$rpt_pattern"
            } elseif {[string match "*power*" $rpt_pattern]} {
                file copy -force $rpt_src "$release_dir/reports/power/$rpt_pattern"
            } elseif {[string match "*drc*" $rpt_pattern] || [string match "*antenna*" $rpt_pattern]} {
                file copy -force $rpt_src "$release_dir/reports/drc/$rpt_pattern"
            } else {
                file copy -force $rpt_src "$release_dir/reports/qor/$rpt_pattern"
            }
        }
    }

    handle_info "Release data preparation completed"
}

# ==============================================================================
# flow_proc: generate_manifest
# Description: Generate a manifest file listing all release deliverables
# ==============================================================================
flow_proc generate_manifest {
    handle_info "Generating release manifest..."
    global pnr project

    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release"
    set manifest_file "$release_dir/MANIFEST.txt"

    # Open manifest for writing
    set fh [open $manifest_file w]
    puts $fh "# CBFlow PNR Release Manifest"
    puts $fh "# Design: $fc(common,design_name)"
    puts $fh "# Generated: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    if {[info exists project(name)]} {
        puts $fh "# Project: $project(name)"
    }
    puts $fh "# Tool: Synopsys Fusion Compiler"
    puts $fh "#"
    puts $fh "# ============================================================"
    puts $fh ""

    # Walk the release directory and list all files
    set file_count 0
    set total_size 0

    foreach category {gds netlist netlist/pg def sdc sdf spef reports/timing reports/power reports/drc reports/qor} {
        set cat_dir "$release_dir/$category"
        if {[file isdirectory $cat_dir]} {
            set files [glob -nocomplain -directory $cat_dir *]
            if {[llength $files] > 0} {
                puts $fh "\[$category\]"
                foreach f [lsort $files] {
                    set fname [file tail $f]
                    set fsize [file size $f]
                    set fmd5 "N/A"
                    catch {
                        set fmd5 [lindex [exec md5 -q $f] 0]
                    }
                    puts $fh "  $fname  ($fsize bytes)  md5:$fmd5"
                    incr file_count
                    set total_size [expr {$total_size + $fsize}]
                }
                puts $fh ""
            }
        }
    }

    puts $fh "# ============================================================"
    puts $fh "# Total files: $file_count"
    puts $fh "# Total size: $total_size bytes"
    puts $fh "# ============================================================"
    close $fh

    handle_info "Manifest written: $manifest_file ($file_count files, $total_size bytes)"
}

# ==============================================================================
# flow_proc: validate_release
# Description: Validate release completeness and integrity
# ==============================================================================
flow_proc validate_release {
    handle_info "Validating release data..."
    global pnr

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

    # Define required deliverables
    set required_files [list \
        "gds/$fc(common,design_name).gds" \
        "netlist/$fc(common,design_name).v" \
        "netlist/pg/$fc(common,design_name)_pg.v" \
        "def/$fc(common,design_name).def" \
        "sdc/$fc(common,design_name).sdc" \
        "spef/$fc(common,design_name)_max.spef" \
        "spef/$fc(common,design_name)_min.spef" \
        "MANIFEST.txt" \
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

    # Verify signoff reports are present
    set report_count 0
    foreach rpt_dir {reports/timing reports/power reports/drc reports/qor} {
        set rpt_path "$release_dir/$rpt_dir"
        if {[file isdirectory $rpt_path]} {
            set rpts [glob -nocomplain -directory $rpt_path *.rpt]
            set report_count [expr {$report_count + [llength $rpts]}]
        }
    }
    handle_info "Release includes $report_count report files"

    # Final release status
    if {$release_pass} {
        handle_info "RELEASE VALIDATION PASSED: All required deliverables present"
        # Write a release stamp file
        set stamp_fh [open "$release_dir/RELEASE_COMPLETE" w]
        puts $stamp_fh "Release completed: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
        puts $stamp_fh "Design: $fc(common,design_name)"
        puts $stamp_fh "Status: PASS"
        close $stamp_fh
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
    global pnr project

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
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# Must be sourced AFTER flow_proc definitions but BEFORE flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.release_data.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
