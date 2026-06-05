#!/usr/bin/env tclsh
# CBFlow SYNTH_PNR export_data (write_data) - Synopsys Fusion Compiler
# FC-RM: write_data.tcl -- Export all design deliverables: netlists, GDS/OASIS,
#         DEF, parasitics, UPF, SDC, floorplan, routing constraints
# Aligned with FC-RM Y-2026.03

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH_PNR"
set STAGE_NAME "export_data"
set NODE_NAME "export_data1"

# ── Config (full cascade: project → tech → flow → node → mmmc → tool → user) ─
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"

# ── Directories ──────────────────────────────────────────────────────────────
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# FC-RM: open_lib, copy_block from signoff, link_block
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for write_data..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set lib_name [expr {$synth_pnr(common,design_lib_name) ne "" ? $synth_pnr(common,design_lib_name) : "${design_name}.nlib"}]

    open_lib $lib_name
    copy_block -from ${design_name}/signoff -to ${design_name}/write_data
    current_block ${design_name}/write_data
    link_block

    # FC-RM: Non-persistent settings
    if {$synth_pnr(common,non_persistent_script) ne "" && [file exists $synth_pnr(common,non_persistent_script)]} {
        source -e $synth_pnr(common,non_persistent_script)
    }

    # FC-RM: User pre-write_data script
    if {[info exists synth_pnr(export_data,pre_script)] && [file exists $synth_pnr(export_data,pre_script)]} {
        source -e $synth_pnr(export_data,pre_script)
    }

    handle_info "Design loaded: ${design_name}/write_data"
# ==============================================================================
# flow_proc: change_names
# FC-RM: define_name_rules, change_names -rules verilog -hierarchy
# ==============================================================================
flow_proc change_names {
    handle_info "Applying verilog naming rules..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    # FC-RM: Define name rules
    if {[info exists synth_pnr(export_data,name_rules)] && $synth_pnr(export_data,name_rules) ne ""} {
        eval define_name_rules verilog $synth_pnr(export_data,name_rules)
    }

    redirect -file $::REPORTS_DIR/report_name_rules.log { report_name_rules }
    redirect -file $::REPORTS_DIR/report_names.log { report_names -rules verilog }

    # FC-RM: change_names
    change_names -rules verilog -hierarchy

    save_block
    handle_info "Verilog naming rules applied"
# ==============================================================================
# flow_proc: write_netlist
# FC-RM: Multiple write_verilog variants (logic_only, PT, FM, LVS, VC_LP)
# ==============================================================================
flow_proc write_netlist {
    handle_info "Writing netlists..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set out $::OUTPUTS_DIR

    # FC-RM: Logic-only netlist (no pg, no physical-only cells)
    set exclude_base "scalar_wire_declarations leaf_module_declarations pg_objects end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells"
    handle_info "Writing logic-only netlist"
    write_verilog -compress gzip -exclude "$exclude_base" -hierarchy all ${out}/${design_name}.v

    # FC-RM: DC comparison netlist (no diodes)
    handle_info "Writing DC comparison netlist"
    write_verilog -compress gzip -exclude "$exclude_base diode_cells" -hierarchy all ${out}/${design_name}.dc.v

    # FC-RM: PrimeTime netlist (with diodes/DCAP for leakage power)
    handle_info "Writing PT netlist"
    write_verilog -compress gzip -only_master_variant \
        -exclude "scalar_wire_declarations leaf_module_declarations pg_objects end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells flip_chip_pad_cells" \
        -hierarchy all ${out}/${design_name}.pt.v

    # FC-RM: Formality netlist (with pg, no supply statements)
    handle_info "Writing FM netlist"
    write_verilog -compress gzip -only_master_variant \
        -exclude "scalar_wire_declarations leaf_module_declarations end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells supply_statements" \
        -hierarchy all ${out}/${design_name}.fm.v

    # FC-RM: LVS netlist (with pg and physical-only cells)
    handle_info "Writing LVS netlist"
    write_verilog -compress gzip -exclude "scalar_wire_declarations leaf_module_declarations empty_modules" \
        -hierarchy all ${out}/${design_name}.lvs.v

    # FC-RM: VC LP netlist (no diodes, no supply statements)
    handle_info "Writing VC LP netlist"
    write_verilog -compress gzip \
        -exclude "scalar_wire_declarations leaf_module_declarations end_cap_cells well_tap_cells filler_cells pad_spacer_cells physical_only_cells cover_cells diode_cells supply_statements" \
        -hierarchy all ${out}/${design_name}.vc_lp.v

    handle_info "All netlists written"
# ==============================================================================
# flow_proc: write_gds_output
# FC-RM: write_gds with layer map, compression
# ==============================================================================
flow_proc write_gds_output {
    handle_info "Writing GDS..."
    global synth_pnr tech flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set out $::OUTPUTS_DIR

    if {[info exists synth_pnr(export_data,write_gds)] && $synth_pnr(export_data,write_gds)} {
        set cmd "write_gds -compress -hierarchy all -long_names -keep_data_type"
        if {$tech(gds_layer_map_file) ne "" && [file exists $tech(gds_layer_map_file)]} {
            lappend cmd -layer_map $tech(gds_layer_map_file)
        }
        lappend cmd ${out}/${design_name}.gds
        handle_info "Running: $cmd"
        eval $cmd
    }

    # FC-RM: write_oasis (optional)
    if {[info exists synth_pnr(export_data,write_oasis)] && $synth_pnr(export_data,write_oasis)} {
        set cmd "write_oasis -compress 6 -hierarchy all -keep_data_type"
        if {$tech(oasis_layer_map_file) ne "" && [file exists $tech(oasis_layer_map_file)]} {
            lappend cmd -layer_map $tech(oasis_layer_map_file)
        }
        lappend cmd ${out}/${design_name}.oasis
        handle_info "Running: $cmd"
        eval $cmd
    }

    # FC-RM: write_lef
    handle_info "Writing LEF"
    write_lef -design ${design_name}/write_data.design -slice_polygon ${out}/${design_name}.lef

    handle_info "GDS/OASIS/LEF output completed"
# ==============================================================================
# flow_proc: write_def_output
# FC-RM: write_def, write_floorplan
# ==============================================================================
flow_proc write_def_output {
    handle_info "Writing DEF and floorplan..."
    global synth_pnr flow tech

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set out $::OUTPUTS_DIR

    # FC-RM: write_def
    set def_cmd "write_def -compress gzip -version 5.8 -include_tech_via_definitions"
    if {[info exists synth_pnr(export_data,def_convert_sites)] && $synth_pnr(export_data,def_convert_sites) ne ""} {
        lappend def_cmd -convert_sites $synth_pnr(export_data,def_convert_sites)
    }
    lappend def_cmd ${out}/${design_name}.def
    handle_info "Running: $def_cmd"
    eval $def_cmd

    # FC-RM: write_floorplan
    handle_info "Writing floorplan"
    write_floorplan -format icc2 -def_version 5.8 -force \
        -read_def_options {-add_def_only_objects {all} -skip_pg_net_connections} \
        -exclude {scan_chains fills pg_metal_fills routing_rules} \
        -net_types {power ground} \
        -include_physical_status {fixed locked} \
        -output ${out}/${design_name}_floorplan

    handle_info "DEF and floorplan written"
# ==============================================================================
# flow_proc: write_parasitics_output
# FC-RM: update_timing, write_parasitics (SPEF)
# ==============================================================================
flow_proc write_parasitics_output {
    handle_info "Writing parasitics..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set out $::OUTPUTS_DIR

    # FC-RM: update_timing before parasitic extraction
    update_timing

    # FC-RM: write_parasitics (SPEF)
    handle_info "Writing SPEF"
    write_parasitics -compress -output ${out}/${design_name}

    handle_info "Parasitics written"
# ==============================================================================
# flow_proc: write_sdc_output
# FC-RM: write_script (SDC per scenario), write_routing_constraints
# ==============================================================================
flow_proc write_sdc_output {
    handle_info "Writing SDC and routing constraints..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set out $::OUTPUTS_DIR

    # FC-RM: write_script (FC format and PT format)
    handle_info "Writing FC scripts"
    write_script -force -compress gzip -output ${out}/${design_name}_wscript
    handle_info "Writing PT scripts"
    write_script -force -compress gzip -format pt -output ${out}/${design_name}_wscript_for_pt

    # FC-RM: write_routing_constraints
    handle_info "Writing routing constraints"
    write_routing_constraints ${out}/${design_name}_routing_constraints

    # FC-RM: write_sdc per scenario
    handle_info "Writing SDC per scenario"
    foreach_in_collection scn [all_scenarios] {
        current_scenario $scn
        set scn_name [get_object_name $scn]
        write_sdc -compress gzip -output ${out}/${design_name}_${scn_name}.sdc
    }

    handle_info "SDC and routing constraints written"
# ==============================================================================
# flow_proc: write_upf_output
# FC-RM: save_upf (prime or golden mode)
# ==============================================================================
flow_proc write_upf_output {
    handle_info "Writing UPF..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]
    set out $::OUTPUTS_DIR

    set upf_mode [expr {$synth_pnr(common,upf_mode) ne "" ? $synth_pnr(common,upf_mode) : "none"}]

    if {$upf_mode eq "prime"} {
        save_upf ${out}/${design_name}.upf
        handle_info "UPF saved (prime mode)"
    } elseif {$upf_mode eq "golden"} {
        save_upf ${out}/${design_name}.supplemental.pg.upf
        set_app_options -name mv.upf.save_upf_include_supply_exceptions -value false
        save_upf ${out}/${design_name}.supplemental.upf
        reset_app_options mv.upf.save_upf_include_supply_exceptions
        handle_info "UPF saved (golden mode — with and without supply exceptions)"
    } else {
        handle_info "UPF mode is 'none', skipping UPF export"
    }

    # FC-RM: SAIF map
    saif_map -type ptpx -write_map ${out}/${design_name}.saif.ptpx.map
    saif_map -write_map ${out}/${design_name}.saif.fc.map

    # FC-RM: FUSA SSF
    if {$synth_pnr(common,enable_fusa) ne "" && $synth_pnr(common,enable_fusa)} {
        save_ssf ${out}/${design_name}.ssf
    }

    handle_info "UPF/SAIF/FUSA export completed"
# ==============================================================================
# flow_proc: save_design
# FC-RM: save_block
# ==============================================================================
flow_proc save_design {
    handle_info "Saving export_data design..."
    global synth_pnr flow

    set design_name [expr {$synth_pnr(common,design_name) ne "" ? $synth_pnr(common,design_name) : $flow(design_name)}]

    save_block
    if {[info exists synth_pnr(export_data,block_labeling)] && $synth_pnr(export_data,block_labeling)} {
        save_block -as ${design_name}/write_data
        handle_info "Block saved: ${design_name}/write_data"
    }

    # FC-RM: User post-write_data script
    if {[info exists synth_pnr(export_data,post_script)] && [file exists $synth_pnr(export_data,post_script)]} {
        source -e $synth_pnr(export_data,post_script)
    }

    handle_info "Export data saved"
# ==============================================================================
# flow_proc: generate_reports
# FC-RM: run_end, report_msg
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

    # run_end removed (not a valid FC command)
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Export data reports generated"
# ==============================================================================
# Source setup.tcl (flow_proc hooks: prepend, append, replace)
# ==============================================================================
set _setup_file "$run_dir/work/$::env(CBFLOW_FLOW_TYPE)/$::env(CBFLOW_NODE_NAME)/run/setup.tcl"
if {[file exists $_setup_file]} {
    handle_info "Sourcing setup hooks: $_setup_file"
    source -e $_setup_file
}
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} {
    handle_info "Sourcing user override: $_override_file"
    source -e $_override_file
}
set _stage_override "$run_dir/setup/override_setup.export_data.tcl"
if {[file exists $_stage_override]} {
    handle_info "Sourcing stage override: $_stage_override"
    source -e $_stage_override
flow_exec_all

# BUG FIX #7: Exit tool after stage completion
exit
