#!/usr/bin/env tclsh
# CBFlow FP export_data - Synopsys Fusion Compiler | FP export_data

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "export_data"
set NODE_NAME "export_data1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: export_def
# Description: Export floorplan DEF for downstream PNR consumption
# ==============================================================================
flow_proc export_def {
    handle_info "Exporting DEF data..."
    global fp

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/fp/def"

    if {[info exists fp(common,design_name)]} {
        set def_file "$run_dir/results/fp/def/$fp(common,design_name).def"
    } else {
        set def_file "$run_dir/results/fp/def/floorplan.def"
    }

    handle_info "Writing DEF: $def_file"
    write_def $def_file \
        -include_tech_via_definitions \
        -vias \
        -floorplan

    # Verify DEF was created
    if {[file exists $def_file]} {
        set def_size [file size $def_file]
        handle_info "DEF written successfully ($def_size bytes)"
    } else {
        handle_error "DEF file was not created: $def_file"
    }

    handle_info "DEF export completed"
}

# ==============================================================================
# flow_proc: export_design
# Description: Save design library (NDM) for downstream consumption
# ==============================================================================
flow_proc export_design {
    handle_info "Exporting design library..."
    global fp

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/fp/db"

    # Save the design block
    if {[info exists fp(common,design_lib_name)] && [info exists fp(common,design_name)]} {
        set save_name "$fp(common,design_lib_name):$fp(common,design_name)/fp_done"
        handle_info "Saving design block as: $save_name"
        save_block -as $save_name
    } else {
        handle_info "Saving design block..."
        save_block
    }

    # Also save a standalone copy
    set db_file "$run_dir/results/fp/db/fp.nlib"
    handle_info "Saving library copy: $db_file"
    save_lib -as $db_file

    # Verify library was saved
    if {[file exists $db_file]} {
        handle_info "Design library saved successfully"
    } else {
        handle_warning "Design library file not verified at: $db_file"
    }

    handle_info "Design export completed"
}

# ==============================================================================
# flow_proc: export_reports
# Description: Copy all FP reports to the results directory
# ==============================================================================
flow_proc export_reports {
    handle_info "Exporting FP reports..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/fp/reports"

    # Copy all FP reports
    set rpt_src_dir "$run_dir/reports/fp"
    if {[file isdirectory $rpt_src_dir]} {
        # Copy reports from each subdirectory
        foreach rpt_subdir {floorplan powerplan post_floorplan} {
            set sub_src "$rpt_src_dir/$rpt_subdir"
            if {[file isdirectory $sub_src]} {
                file mkdir "$run_dir/results/fp/reports/$rpt_subdir"
                set rpt_files [glob -nocomplain -directory $sub_src *.rpt]
                foreach rpt $rpt_files {
                    set rpt_name [file tail $rpt]
                    file copy -force $rpt "$run_dir/results/fp/reports/$rpt_subdir/$rpt_name"
                }
                handle_info "Copied [llength $rpt_files] reports from $rpt_subdir"
            }
        }

        # Copy top-level reports
        set top_rpts [glob -nocomplain -directory $rpt_src_dir *.rpt]
        foreach rpt $top_rpts {
            file copy -force $rpt "$run_dir/results/fp/reports/[file tail $rpt]"
        }
        handle_info "Copied [llength $top_rpts] top-level reports"
    } else {
        handle_warning "No FP reports directory found"
    }

    handle_info "Report export completed"
}

# ==============================================================================
# flow_proc: validate_exports
# Description: Validate all exported files exist and are non-empty
# ==============================================================================
flow_proc validate_exports {
    handle_info "Validating exported data..."
    global fp

    set run_dir $::env(CBFLOW_RUN_DIR)
    set export_pass true

    # Determine file names
    if {[info exists fp(common,design_name)]} {
        set dname $fp(common,design_name)
    } else {
        set dname "floorplan"
    }

    # Check DEF
    set def_path "$run_dir/results/fp/def/${dname}.def"
    if {[file exists $def_path]} {
        set fsize [file size $def_path]
        if {$fsize == 0} {
            handle_warning "DEF file is empty"
            set export_pass false
        } else {
            handle_info "Verified DEF: $fsize bytes"
        }
    } else {
        handle_warning "Missing DEF export: $def_path"
        set export_pass false
    }

    # Check design library
    set db_path "$run_dir/results/fp/db/fp.nlib"
    if {[file exists $db_path]} {
        handle_info "Verified design library: $db_path"
    } else {
        handle_warning "Missing design library: $db_path"
        set export_pass false
    }

    # Check reports
    set rpt_dir "$run_dir/results/fp/reports"
    if {[file isdirectory $rpt_dir]} {
        set rpt_count [llength [glob -nocomplain -directory $rpt_dir -type f *.rpt]]
        handle_info "Found $rpt_count top-level report files in export"
    }

    if {$export_pass} {
        handle_info "All export files validated successfully"
    } else {
        handle_warning "Some export files are missing or empty -- review warnings above"
    }

    handle_info "Export validation completed"
}

# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
