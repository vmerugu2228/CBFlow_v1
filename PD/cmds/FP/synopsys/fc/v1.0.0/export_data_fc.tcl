#!/usr/bin/env tclsh
# CBFlow FP export_data - Synopsys Fusion Compiler | FP export_data
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
global fp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FP export_data with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

set WORK_DIR "$run_dir/work/FP/export_data"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: export_def
# Description: Export floorplan DEF for downstream PNR consumption
# ==============================================================================
flow_proc export_def {
    handle_info "Exporting DEF data..."
    global fp

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/fp/def"

    if {[info exists fc(common,design_name)]} {
        set def_file "$run_dir/results/fp/def/$fc(common,design_name).def"
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
    if {[info exists fc(common,design_lib_name)] && [info exists fc(common,design_name)]} {
        set save_name "$fc(common,design_lib_name):$fc(common,design_name)/fp_done"
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
    if {[info exists fc(common,design_name)]} {
        set dname $fc(common,design_name)
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

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.export_data.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
