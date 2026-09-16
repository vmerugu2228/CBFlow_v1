#!/usr/bin/env tclsh
# CBFlow shared (PNR + SYNTH_PNR) — synopsys/fc — release_data1 - Synopsys Fusion Compiler | PNR release_data1
# Sources release_config.tcl for phase-wise mandatory file validation
# Generates: release directory, manifest, release notes, completion stamp

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

if {![info exists ::flow_type] || $::flow_type eq ""} { set ::flow_type $::env(CBFLOW_FLOW_TYPE) }
set FLOW_TYPE $::flow_type
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# Active flow config array — pnr() or synth_pnr() depending on the run.
# Use $cfg(...) / [info exists cfg(...)] throughout the file body.
upvar #0 [string tolower $::flow_type] cfg



# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }
# Source release utilities for ::CBFlow::Release namespace
set _ru "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_ru]} { source $_ru }
# ==============================================================================
# flow_proc: prepare_release
# Description: Prepare release directory structure and copy deliverables
# ==============================================================================
flow_proc prepare_release {
    handle_info "Preparing release data..."
    global cfg project flow

    set run_dir $::env(CBFLOW_RUN_DIR)

    # ── Validate mandatory variables ─────────────────────────────────────────
    set missing_vars {}
    if {![info exists cfg(common,design_name)] && ![info exists flow(design_name)]} {
        lappend missing_vars "design_name (pnr(common,design_name) or flow(design_name))"
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

    set design_name [expr {[info exists cfg(common,design_name)] ? $cfg(common,design_name) : $flow(design_name)}]

    # ── Determine release phase ──────────────────────────────────────────────
    set release_phase "P0"
    if {[info exists project(release_phase)]} { set release_phase $project(release_phase) }
    if {[info exists cfg(common,release_phase)]} { set release_phase $cfg(common,release_phase) }
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
    set _release_tag [expr {[info exists project(release,tag)] ? $project(release,tag) : "(unset)"}]
    handle_info "Release tag: $_release_tag"
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
    set gds_src "$run_dir/results/pnr/gds/$cfg(common,design_name).gds"
    if {[file exists $gds_src]} {
        file copy -force $gds_src "$release_dir/gds/$cfg(common,design_name).gds"
        handle_info "Copied GDS to release"
    } else {
        handle_warning "GDS source not found: $gds_src"
    }

    # Copy netlists
    foreach suffix [list "" "_pg"] {
        set nl_src "$run_dir/results/pnr/netlist/$cfg(common,design_name)${suffix}.v"
        if {$suffix eq "_pg"} {
            set nl_dst "$release_dir/netlist/pg/$cfg(common,design_name)_pg.v"
        } else {
            set nl_dst "$release_dir/netlist/$cfg(common,design_name).v"
        }
        if {[file exists $nl_src]} {
            file copy -force $nl_src $nl_dst
            handle_info "Copied netlist${suffix} to release"
        }
    }

    # Copy SDF
    set sdf_src "$run_dir/results/pnr/netlist/$cfg(common,design_name).sdf"
    if {[file exists $sdf_src]} {
        file copy -force $sdf_src "$release_dir/sdf/$cfg(common,design_name).sdf"
        handle_info "Copied SDF to release"
    }

    # Copy DEF
    set def_src "$run_dir/results/pnr/def/$cfg(common,design_name).def"
    if {[file exists $def_src]} {
        file copy -force $def_src "$release_dir/def/$cfg(common,design_name).def"
        handle_info "Copied DEF to release"
    }

    # Copy SDC
    set sdc_src "$run_dir/results/pnr/sdc/$cfg(common,design_name).sdc"
    if {[file exists $sdc_src]} {
        file copy -force $sdc_src "$release_dir/sdc/$cfg(common,design_name).sdc"
        handle_info "Copied SDC to release"
    }

    # Copy SPEF files (all corners)
    foreach corner {max min nom} {
        set spef_src "$run_dir/results/pnr/spef/$cfg(common,design_name)_${corner}.spef"
        if {[file exists $spef_src]} {
            file copy -force $spef_src "$release_dir/spef/$cfg(common,design_name)_${corner}.spef"
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
    global cfg project

    set run_dir $::env(CBFLOW_RUN_DIR)
    set release_dir "$run_dir/results/release"
    set manifest_file "$release_dir/MANIFEST.txt"

    # Open manifest for writing
    set fh [open $manifest_file w]
    puts $fh "# CBFlow shared (PNR + SYNTH_PNR) — synopsys/fc — Release Manifest"
    puts $fh "# Design: $cfg(common,design_name)"
    puts $fh "# Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
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
    global cfg

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
        "gds/$cfg(common,design_name).gds" \
        "netlist/$cfg(common,design_name).v" \
        "netlist/pg/$cfg(common,design_name)_pg.v" \
        "def/$cfg(common,design_name).def" \
        "sdc/$cfg(common,design_name).sdc" \
        "spef/$cfg(common,design_name)_max.spef" \
        "spef/$cfg(common,design_name)_min.spef" \
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
        puts $stamp_fh "Release completed: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
        puts $stamp_fh "Design: $cfg(common,design_name)"
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
    global cfg project

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
