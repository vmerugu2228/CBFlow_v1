#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - ECO Export DB Command File
# Description: Export ECO-modified design data
# Tool: Synopsys Fusion Compiler
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/ECO/export_db/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global eco project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting ECO export_db with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ── Directories ──────────────────────────────────────────────────────────────
set WORK_DIR "$run_dir/work/ECO/export_db1"
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
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# --------------------------------------------------------------------------
# Procedure: export_netlist
#   Write post-ECO Verilog netlist
# --------------------------------------------------------------------------
flow_proc export_netlist {
    global eco project
    handle_info "Exporting post-ECO netlist..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::OUTPUTS_DIR"

    set netlist_file "$::OUTPUTS_DIR/eco_netlist.v"

    # Write Verilog with ECO changes
    write_verilog -hierarchy all $netlist_file
    handle_info "Netlist exported: $netlist_file"

    # Write PG netlist if requested
    if {[info exists fc(export,pg_netlist)] && $fc(export,pg_netlist) eq "true"} {
        set pg_netlist "$::OUTPUTS_DIR/eco_netlist_pg.v"
        write_verilog -hierarchy all -pg $pg_netlist
        handle_info "PG netlist exported: $pg_netlist"
    }
}

# --------------------------------------------------------------------------
# Procedure: export_def
#   Write post-ECO DEF
# --------------------------------------------------------------------------
flow_proc export_def {
    global eco project
    handle_info "Exporting post-ECO DEF..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set def_file "$::OUTPUTS_DIR/eco_modified.def"
    write_def -include {cells nets special_nets vias} $def_file
    handle_info "DEF exported: $def_file"

    # Write incremental DEF showing only ECO changes
    if {[info exists fc(export,incremental_def)] && $fc(export,incremental_def) eq "true"} {
        set inc_def "$::OUTPUTS_DIR/eco_incremental.def"
        write_def -eco_changed_cells $inc_def
        handle_info "Incremental DEF exported: $inc_def"
    }
}

# --------------------------------------------------------------------------
# Procedure: export_gds
#   Write post-ECO GDS stream
# --------------------------------------------------------------------------
flow_proc export_gds {
    global eco project tech
    handle_info "Exporting post-ECO GDS..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set gds_file "$::OUTPUTS_DIR/eco_modified.gds"

    # Set GDS map file if available
    if {[info exists tech(gds_map_file)]} {
        set_write_stream_options -map_layer $tech(gds_map_file)
    }

    write_gds -hierarchy all $gds_file
    handle_info "GDS exported: $gds_file ([expr {[file size $gds_file] / 1048576}] MB)"

    # Save the design block
    set nlib_file "$::OUTPUTS_DIR/db/eco.nlib"
    file mkdir [file dirname $nlib_file]
    save_block -as $nlib_file
    handle_info "Design block saved: $nlib_file"
}

# --------------------------------------------------------------------------
# Procedure: validate_exports
#   Validate exported files exist and are non-empty
# --------------------------------------------------------------------------
flow_proc validate_exports {
    handle_info "Validating exported ECO data..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors {}

    foreach {label fname} {
        "Netlist" "eco_netlist.v"
        "DEF"     "eco_modified.def"
        "GDS"     "eco_modified.gds"
    } {
        set full "$::OUTPUTS_DIR/$fname"
        set path $fname
        if {![file exists $full]} {
            lappend errors "$label not exported: $path"
        } elseif {[file size $full] == 0} {
            lappend errors "$label is empty: $path"
        } else {
            handle_info "  $label: $path ([file size $full] bytes)"
        }
    }

    # Write export summary
    set rpt "$::OUTPUTS_DIR/export_summary.rpt"
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow ECO - Export Summary (Synopsys FC)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists ::project(top_module)]} { puts $fp "Design: $::project(top_module)" }
    puts $fp ""
    puts $fp "Exported Files:"
    puts $fp "  Netlist: results/eco/eco_netlist.v"
    puts $fp "  DEF:     results/eco/eco_modified.def"
    puts $fp "  GDS:     results/eco/eco_modified.gds"
    puts $fp "  NDM:     results/db/eco.nlib"
    puts $fp ""
    if {[llength $errors] > 0} {
        puts $fp "EXPORT STATUS: FAIL"
        foreach e $errors { puts $fp "  - $e" }
    } else {
        puts $fp "EXPORT STATUS: PASS"
    }
    close $fp

    if {[llength $errors] > 0} {
        foreach e $errors { handle_error "Export: $e" }
    } else {
        handle_info "ECO export validation PASSED"
    }
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/ECO/export_db1/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.export_db.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
