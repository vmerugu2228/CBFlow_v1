#!/usr/bin/env tclsh
# CBFlow SYNTH export_data1 - Synopsys Fusion Compiler | SYNTH export_data1
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
global synth project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting SYNTH export_data1 with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/SYNTH/export_data1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# ==============================================================================
# flow_proc: export_netlist
# Description: Export synthesized gate-level Verilog netlist
# ==============================================================================
flow_proc export_netlist {
    handle_info "Exporting synthesized netlist..."
    global synth

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR/netlist"

    # Write gate-level Verilog netlist
    if {[info exists fc(common,design_name)]} {
        set netlist_file "$::OUTPUTS_DIR/netlist/$fc(common,design_name).v"
    } else {
        set netlist_file "$::OUTPUTS_DIR/netlist/synth.v"
    }

    handle_info "Writing Verilog netlist: $netlist_file"
    write_verilog $netlist_file \
        -hierarchy all \
        -no_physical_only_cells

    # Verify netlist was created
    if {[file exists $netlist_file]} {
        set fsize [file size $netlist_file]
        handle_info "Netlist written successfully ($fsize bytes)"
    } else {
        handle_error "Netlist file was not created: $netlist_file"
    }

    # Also write a version without pg for functional sim
    set netlist_nopg "$::OUTPUTS_DIR/netlist/synth_func.v"
    handle_info "Writing functional netlist: $netlist_nopg"
    write_verilog $netlist_nopg \
        -hierarchy all \
        -no_physical_only_cells \
        -exclude_pg_ports

    handle_info "Netlist export completed"
}

# ==============================================================================
# flow_proc: export_constraints
# Description: Export SDC timing constraints from post-synthesis design state
# ==============================================================================
flow_proc export_constraints {
    handle_info "Exporting SDC constraints..."
    global synth

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR/sdc"

    if {[info exists fc(common,design_name)]} {
        set sdc_file "$::OUTPUTS_DIR/sdc/$fc(common,design_name).sdc"
    } else {
        set sdc_file "$::OUTPUTS_DIR/sdc/synth.sdc"
    }

    handle_info "Writing SDC: $sdc_file"
    write_sdc $sdc_file \
        -significant_digits [expr {[info exists fc(analysis,significant_digits)] ? $fc(analysis,significant_digits) : 4}] \
        -nosplit

    # Verify SDC was created
    if {[file exists $sdc_file]} {
        handle_info "SDC written successfully ([file size $sdc_file] bytes)"
    } else {
        handle_error "SDC file was not created: $sdc_file"
    }

    handle_info "Constraints export completed"
}

# ==============================================================================
# flow_proc: export_reports
# Description: Copy synthesis reports to results directory for downstream use
# ==============================================================================
flow_proc export_reports {
    handle_info "Exporting synthesis reports..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR/reports"

    # Copy all synthesis reports
    set rpt_src_dir "$run_dir/work/SYNTH/synthesis1/reports"
    if {[file isdirectory $rpt_src_dir]} {
        set rpt_files [glob -nocomplain -directory $rpt_src_dir *.rpt]
        foreach rpt $rpt_files {
            set rpt_name [file tail $rpt]
            file copy -force $rpt "$::OUTPUTS_DIR/reports/$rpt_name"
            handle_info "Copied report: $rpt_name"
        }
        handle_info "Exported [llength $rpt_files] report files"
    } else {
        handle_warning "No synthesis reports directory found at $rpt_src_dir"
    }

    # Save the design block (NDM format)
    file mkdir "$::OUTPUTS_DIR/db"
    handle_info "Saving design block..."
    save_block -as "$::OUTPUTS_DIR/db/synth.nlib"

    handle_info "Report export completed"
}

# ==============================================================================
# flow_proc: validate_exports
# Description: Validate all exported files exist and are non-empty
# ==============================================================================
flow_proc validate_exports {
    handle_info "Validating exported data..."
    global synth

    set run_dir $::env(CBFLOW_RUN_DIR)
    set export_pass true

    # Determine design name for file paths
    if {[info exists fc(common,design_name)]} {
        set dname $fc(common,design_name)
    } else {
        set dname "synth"
    }

    # Define expected export files
    set expected_files [list \
        "$::OUTPUTS_DIR/netlist/${dname}.v" \
        "$::OUTPUTS_DIR/sdc/${dname}.sdc" \
    ]

    foreach full_path $expected_files {
        set rel_path [file tail $full_path]
        if {[file exists $full_path]} {
            set fsize [file size $full_path]
            if {$fsize == 0} {
                handle_warning "Export file is empty: $rel_path"
                set export_pass false
            } else {
                handle_info "Verified: $rel_path ($fsize bytes)"
            }
        } else {
            handle_warning "Missing export file: $rel_path"
            set export_pass false
        }
    }

    # Verify reports were copied
    set rpt_dir "$::OUTPUTS_DIR/reports"
    if {[file isdirectory $rpt_dir]} {
        set rpt_count [llength [glob -nocomplain -directory $rpt_dir *.rpt]]
        handle_info "Found $rpt_count report files in export"
    }

    if {$export_pass} {
        handle_info "All export files validated successfully"
    } else {
        handle_warning "Some export files are missing or empty -- review warnings above"
    }

    handle_info "Export validation completed"
}

# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
