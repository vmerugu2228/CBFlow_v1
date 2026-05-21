#!/usr/bin/env tclsh
# CBFlow ECO export_db - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ECO"
set STAGE_NAME "export_db"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
    if {[info exists eco(export,pg_netlist)] && $eco(export,pg_netlist) eq "true"} {
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
    if {[info exists eco(export,incremental_def)] && $eco(export,incremental_def) eq "true"} {
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
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
