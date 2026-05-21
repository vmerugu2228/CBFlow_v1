#!/usr/bin/env tclsh
# CBFlow FCFP export_data - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "export_data"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for export_data..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(export_data,from_label)] ? $fcfp(export_data,from_label) : "timing_budget"}]
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
    if {[info exists fcfp(common,sub_blocks)] && [llength $fcfp(common,sub_blocks)] > 0} {
        file mkdir "$res_dir/def/partitions"
        foreach block $fcfp(common,sub_blocks) {
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

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

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
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
