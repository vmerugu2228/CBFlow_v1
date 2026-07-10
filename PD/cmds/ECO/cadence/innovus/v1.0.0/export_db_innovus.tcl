#!/usr/bin/env tclsh
# CBFlow ECO export_db - Cadence Innovus

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

    # Innovus: write_netlist (hierarchical) — drops PG by default
    handle_info "saveNetlist $netlist_file"
    saveNetlist $netlist_file
    handle_info "Netlist exported: $netlist_file"

    if {[info exists eco(export,pg_netlist)] && $eco(export,pg_netlist) eq "true"} {
        set pg_netlist "$::OUTPUTS_DIR/eco_netlist_pg.v"
        handle_info "saveNetlist -includePowerGround $pg_netlist"
        saveNetlist -includePowerGround $pg_netlist
        handle_info "PG netlist exported: $pg_netlist"
    }
}

# --------------------------------------------------------------------------
flow_proc export_def {
    global eco project
    handle_info "Exporting post-ECO DEF..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set def_file "$::OUTPUTS_DIR/eco_modified.def"
    handle_info "defOut -floorplan -netlist -routing $def_file"
    defOut -floorplan -netlist -routing $def_file
    handle_info "DEF exported: $def_file"

    if {[info exists eco(export,incremental_def)] && $eco(export,incremental_def) eq "true"} {
        set inc_def "$::OUTPUTS_DIR/eco_incremental.def"
        # Innovus has no direct -eco_changed_cells switch; use defOut -ecoOnly
        # if the build supports it, else fall back to full DEF and a manual diff.
        if {[catch {defOut -ecoOnly $inc_def} _err]} {
            handle_warning "defOut -ecoOnly unsupported by this Innovus build ($_err); writing full DEF as incremental"
            defOut -floorplan -netlist -routing $inc_def
        }
        handle_info "Incremental DEF exported: $inc_def"
    }
}

# --------------------------------------------------------------------------
flow_proc export_gds {
    global eco project tech
    handle_info "Exporting post-ECO GDS..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set gds_file "$::OUTPUTS_DIR/eco_modified.gds"

    set _cmd "streamOut $gds_file -mode ALL -merge"
    if {[info exists tech($project(metal_stack),gds_layer_map_file)] && $tech($project(metal_stack),gds_layer_map_file) ne ""} {
        append _cmd " -mapFile $tech($project(metal_stack),gds_layer_map_file)"
    }
    if {[info exists tech($project(metal_stack),stream_files_for_merge)] && $tech($project(metal_stack),stream_files_for_merge) ne ""} {
        append _cmd " -merge \{$tech($project(metal_stack),stream_files_for_merge)\}"
    }
    handle_info "Running: $_cmd"
    eval $_cmd

    if {[file exists $gds_file]} {
        handle_info "GDS exported: $gds_file ([expr {[file size $gds_file] / 1048576}] MB)"
    }

    # Save the Innovus design db too
    set _db "$::OUTPUTS_DIR/db/eco.innovus.dat"
    file mkdir [file dirname $_db]
    handle_info "saveDesign $_db"
    saveDesign $_db
    handle_info "Design db saved: $_db"
}

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

    set rpt "$::OUTPUTS_DIR/export_summary.rpt"
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow ECO - Export Summary (Cadence Innovus)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists ::project(top_module)]} { puts $fp "Design: $::project(top_module)" }
    puts $fp ""
    puts $fp "Exported Files:"
    puts $fp "  Netlist: results/eco/eco_netlist.v"
    puts $fp "  DEF:     results/eco/eco_modified.def"
    puts $fp "  GDS:     results/eco/eco_modified.gds"
    puts $fp "  DB:      results/db/eco.innovus.dat"
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

exit
