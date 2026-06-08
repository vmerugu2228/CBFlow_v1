#!/usr/bin/env tclsh
# CBFlow PNR export_data1 - Synopsys Fusion Compiler | PNR export_data1

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "export_data"
set NODE_NAME "export_data1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: write_netlist
# Description: Write final Verilog netlists (logic-only, PG, PT, FM, LVS)
# ==============================================================================
flow_proc write_netlist {
    handle_info "Writing final netlists..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pnr/netlist"

    # Apply change_names for verilog compliance
    if {[info exists pnr(output,name_rules_options)] && $pnr(output,name_rules_options) ne ""} {
        eval define_name_rules verilog $pnr(output,name_rules_options)
    }
    change_names -rules verilog -hierarchy
    save_block

    # Write logic-only Verilog (no PG, no physical only cells)
    set netlist_logic "$run_dir/results/pnr/netlist/$pnr(common,design_name).v"
    handle_info "Writing logic-only netlist: $netlist_logic"
    write_verilog -compress gzip \
        -exclude {scalar_wire_declarations leaf_module_declarations pg_objects end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells} \
        -hierarchy all \
        ${netlist_logic}

    # Write PG-aware netlist for LVS
    set netlist_lvs "$run_dir/results/pnr/netlist/$pnr(common,design_name).lvs.v"
    handle_info "Writing LVS netlist: $netlist_lvs"
    write_verilog -compress gzip \
        -exclude {scalar_wire_declarations leaf_module_declarations empty_modules} \
        -hierarchy all \
        ${netlist_lvs}

    # Write PT-compatible netlist
    set netlist_pt "$run_dir/results/pnr/netlist/$pnr(common,design_name).pt.v"
    handle_info "Writing PT netlist: $netlist_pt"
    write_verilog -compress gzip \
        -exclude {scalar_wire_declarations leaf_module_declarations pg_objects end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells flip_chip_pad_cells} \
        -hierarchy all \
        ${netlist_pt}

    # Write FM-compatible netlist
    set netlist_fm "$run_dir/results/pnr/netlist/$pnr(common,design_name).fm.v"
    handle_info "Writing FM netlist: $netlist_fm"
    write_verilog -compress gzip \
        -exclude {scalar_wire_declarations leaf_module_declarations end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells supply_statements} \
        -hierarchy all \
        ${netlist_fm}

    handle_info "Netlist export completed"
}

# ==============================================================================
# flow_proc: write_def_output
# Description: Write final DEF file
# ==============================================================================
flow_proc write_def_output {
    handle_info "Writing DEF output..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pnr/def"

    set def_file "$run_dir/results/pnr/def/$pnr(common,design_name).def"
    handle_info "Writing DEF: $def_file"

    set write_def_cmd "write_def -compress gzip -version 5.8 -include_tech_via_definitions"
    if {[info exists pnr(output,def_convert_sites)] && $pnr(output,def_convert_sites) ne ""} {
        lappend write_def_cmd -convert_sites $pnr(output,def_convert_sites)
    }
    lappend write_def_cmd $def_file

    handle_info "Running: $write_def_cmd"
    eval $write_def_cmd

    if {[file exists $def_file]} {
        handle_info "DEF written successfully"
    } else {
        handle_warning "DEF file was not created: $def_file"
    }

    handle_info "DEF export completed"
}

# ==============================================================================
# flow_proc: write_gds_output
# Description: Write GDSII/OASIS layout data
# ==============================================================================
flow_proc write_gds_output {
    handle_info "Checking GDS/OASIS output settings..."
    global pnr tech

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pnr/gds"

    # Write GDS
    if {[info exists pnr(output,write_gds)] && $pnr(output,write_gds)} {
        set gds_file "$run_dir/results/pnr/gds/$pnr(common,design_name).gds"
        handle_info "Writing GDSII: $gds_file"

        set gds_cmd "write_gds -compress -hierarchy all -long_names -keep_data_type"
        if {[info exists tech(gds_layer_map)] && [file exists $tech(gds_layer_map)]} {
            lappend gds_cmd -layer_map $tech(gds_layer_map)
        }
        lappend gds_cmd $gds_file

        handle_info "Running: $gds_cmd"
        eval $gds_cmd

        if {[file exists $gds_file]} {
            handle_info "GDSII written successfully"
        } else {
            handle_warning "GDSII file was not created: $gds_file"
        }
    } else {
        handle_info "GDS output not enabled -- skipping"
    }

    # Write OASIS
    if {[info exists pnr(output,write_oasis)] && $pnr(output,write_oasis)} {
        set oasis_file "$run_dir/results/pnr/gds/$pnr(common,design_name).oasis"
        handle_info "Writing OASIS: $oasis_file"

        set oasis_cmd "write_oasis -compress 6 -hierarchy all -keep_data_type"
        if {[info exists tech(oasis_layer_map)] && [file exists $tech(oasis_layer_map)]} {
            lappend oasis_cmd -layer_map $tech(oasis_layer_map)
        }
        lappend oasis_cmd $oasis_file

        handle_info "Running: $oasis_cmd"
        eval $oasis_cmd

        if {[file exists $oasis_file]} {
            handle_info "OASIS written successfully"
        } else {
            handle_warning "OASIS file was not created: $oasis_file"
        }
    }
}

# ==============================================================================
# flow_proc: write_parasitics_output
# Description: Write SPEF parasitics for signoff timing analysis
# ==============================================================================
flow_proc write_parasitics_output {
    handle_info "Writing parasitics..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pnr/spef"

    # Update timing before writing parasitics
    update_timing

    # Write parasitics (SPEF)
    set spef_output "$run_dir/results/pnr/spef/$pnr(common,design_name)"
    handle_info "Writing SPEF parasitics: $spef_output"
    write_parasitics -compress -output $spef_output

    handle_info "Parasitics export completed"
}

# ==============================================================================
# flow_proc: write_sdc_output
# Description: Write SDC constraints and routing constraints
# ==============================================================================
flow_proc write_sdc_output {
    handle_info "Writing SDC and script outputs..."
    global pnr

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pnr/sdc"

    # Write scripts (mode/corner/scenario scripts for PT)
    write_script -force -compress gzip \
        -output "$run_dir/results/pnr/sdc/${pnr(common,design_name)}_wscript"
    write_script -force -compress gzip -format pt \
        -output "$run_dir/results/pnr/sdc/${pnr(common,design_name)}_wscript_for_pt"

    # Write routing constraints
    write_routing_constraints \
        "$run_dir/results/pnr/sdc/${pnr(common,design_name)}_routing_constraints"

    # Write floorplan
    write_floorplan \
        -format icc2 \
        -def_version 5.8 \
        -force \
        -read_def_options {-add_def_only_objects {all} -skip_pg_net_connections} \
        -exclude {scan_chains fills pg_metal_fills routing_rules} \
        -net_types {power ground} \
        -include_physical_status {fixed locked} \
        -output "$run_dir/results/pnr/sdc/${pnr(common,design_name)}_floorplan"

    # Write UPF if power intent exists
    if {[info exists pnr(output,write_upf)] && $pnr(output,write_upf)} {
        save_upf "$run_dir/results/pnr/sdc/$pnr(common,design_name).upf"
        handle_info "UPF written"
    }

    # Write per-scenario SDC
    foreach_in_collection scn [all_scenarios] {
        current_scenario $scn
        set scnN [get_object_name $scn]
        handle_info "Writing SDC for scenario $scnN"
        write_sdc -compress gzip \
            -output "$run_dir/results/pnr/sdc/${pnr(common,design_name)}_${scnN}.sdc"
    }

    handle_info "SDC and script export completed"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save the final design block
# ==============================================================================
flow_proc save_design_block {
    handle_info "Saving final design block..."
    global pnr

    if {[info exists pnr(output,block_labeling)] && $pnr(output,block_labeling)} {
        save_block -as $pnr(common,design_name)/export_data
        handle_info "Block saved as $pnr(common,design_name)/export_data"
    } else {
        save_block
        handle_info "Block saved"
    }
}

# ==============================================================================
# flow_proc: generate_reports
# FC-RM: Final QoR snapshot, report_msg
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating export_data reports..."

    # FC-RM: Final QoR snapshot before data export
    redirect -file $::REPORTS_DIR/report_qor.rpt { report_qor -nosplit }
    redirect -file $::REPORTS_DIR/report_timing.max.rpt {
        report_timing -max_paths 20 -delay_type max -nosplit
    }
    redirect -file $::REPORTS_DIR/report_timing.min.rpt {
        report_timing -max_paths 20 -delay_type min -nosplit
    }

    # FC-RM: report_msg summary
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Export data reports generated in: $::REPORTS_DIR"
}


# ==============================================================================
# Execute all flow_procs in sequence
# ==============================================================================
flow_exec_all

# Exit tool after stage completion
exit
