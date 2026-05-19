#!/usr/bin/env tclsh
# CBFlow FCFP export_data - Synopsys Fusion Compiler
# Hierarchical DP data export -- DEF, floorplan, netlist, design library
# Aligned with FC-RM Y-2026.03
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
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP export_data..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

set WORK_DIR "$run_dir/work/FCFP/export_data1"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for export_data..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fc(common,open_lib)] && $fc(common,open_lib) ne ""} {
        open_lib $fc(common,open_lib)
    }

    set from_label [expr {[info exists fc(export_data,from_label)] ? $fc(export_data,from_label) : "timing_budget"}]
    open_block ${design_name}/${from_label}
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: write_def_output
# Export DEF files (full + floorplan-only + per-partition)
# ==============================================================================
flow_proc write_def_output {
    handle_info "Exporting DEF files..."
    global fcfp

    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"
    file mkdir "$res_dir/def"

    write_def "$res_dir/def/fcfp_floorplan.def"
    handle_info "Exported: fcfp_floorplan.def"

    write_def -floorplan_only "$res_dir/def/fcfp_floorplan_only.def"
    handle_info "Exported: fcfp_floorplan_only.def"

    # Per-partition DEFs
    if {[info exists fc(common,sub_blocks)] && [llength $fc(common,sub_blocks)] > 0} {
        file mkdir "$res_dir/def/partitions"
        foreach block $fc(common,sub_blocks) {
            catch {
                write_def -cell $block "$res_dir/def/partitions/${block}.def"
                handle_info "Exported partition DEF: ${block}.def"
            }
        }
    }

    handle_info "DEF export completed"
}

# ==============================================================================
# flow_proc: write_floorplan
# Export floorplan TCL for reload
# ==============================================================================
flow_proc write_floorplan {
    handle_info "Exporting floorplan data..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"
    file mkdir $res_dir

    catch {
        write_floorplan -output "$res_dir/fcfp_floorplan.tcl" -force
        handle_info "Floorplan TCL exported"
    }

    handle_info "Floorplan export completed"
}

# ==============================================================================
# flow_proc: write_netlist
# Export Verilog netlist and SDC
# ==============================================================================
flow_proc write_netlist {
    handle_info "Exporting netlist and constraints..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"
    file mkdir $res_dir

    write_verilog "$res_dir/fcfp_floorplan.v"
    handle_info "Exported Verilog: fcfp_floorplan.v"

    write_sdc "$res_dir/fcfp_floorplan.sdc"
    handle_info "Exported SDC: fcfp_floorplan.sdc"

    handle_info "Netlist/constraint export completed"
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving export_data block..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block -as ${design_name}/export_data
    handle_info "Block saved: ${design_name}/export_data"
}

# ==============================================================================
# flow_proc: generate_reports
# Export manifest and copy reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating export_data reports..."
    global fcfp

    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"
    file mkdir "$res_dir/reports"

    # Copy stage reports to export area
    set copied 0
    foreach subdir {"create_floorplan" "shaping" "placement" "create_power" "place_pins" "top_compile" "timing_budget"} {
        set src_dir "$run_dir/reports/fcfp/$subdir"
        if {[file isdirectory $src_dir]} {
            file mkdir "$res_dir/reports/$subdir"
            foreach rpt [glob -nocomplain "$src_dir/*.rpt"] {
                catch {file copy -force $rpt "$res_dir/reports/$subdir/[file tail $rpt]"}
                incr copied
            }
        }
    }
    handle_info "Exported $copied report files"

    # Generate manifest
    set mf [open "$res_dir/export_manifest.txt" w]
    puts $mf "FCFP Export Manifest - [clock format [clock seconds]]"
    puts $mf "======================================================="
    puts $mf "Files exported:"
    foreach f [glob -nocomplain "$res_dir/def/*.def" "$res_dir/def/partitions/*.def" "$res_dir/*.v" "$res_dir/*.sdc" "$res_dir/*.tcl"] {
        puts $mf "  [string map [list $res_dir/ ""] $f]"
    }
    close $mf

    handle_info "Export_data reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.export_data.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
