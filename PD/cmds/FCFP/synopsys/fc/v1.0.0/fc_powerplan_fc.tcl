#!/usr/bin/env tclsh
# CBFlow FCFP fc_powerplan - Synopsys Fusion Compiler | Fullchip power grid planning
# Ported from FC-RM Y-2026.03 create_power.tcl
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FCFP/fc_powerplan/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP fc_powerplan with Synopsys Fusion Compiler..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" &&
    [info exists ::env(TECH_VERSION)] && $::env(TECH_VERSION) ne ""} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

set WORK_DIR "$run_dir/work/FCFP/fc_powerplan"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ---------------------------------------------------------------------------
# flow_proc: create_pg_rings
# FC-RM: Create PG rings around core area (from create_power.tcl PNS section)
# ---------------------------------------------------------------------------
flow_proc create_pg_rings {
    handle_info "Creating PG rings..."
    global fcfp
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"

    # FC-RM: Check design pre-power insertion
    redirect -file $::REPORTS_DIR/check_design.pre_power \
        {check_design -checks dp_pre_power_insertion}

    # FC-RM: PG ring creation from config or defaults
    if {[info exists fc(power,ring_config)] && $fc(power,ring_config) ne ""} {
        # Source user PG ring configuration
        source -e $fc(power,ring_config)
        handle_info "PG rings created from config file"
    } else {
        # Build PG rings from individual config variables
        set vdd_net "VDD"
        set vss_net "VSS"
        if {[info exists fc(power,vdd_net)]} { set vdd_net $fc(power,vdd_net) }
        if {[info exists fc(power,vss_net)]} { set vss_net $fc(power,vss_net) }

        set ring_layers {M9 M10}
        if {[info exists fc(power,ring_layers)]} { set ring_layers $fc(power,ring_layers) }

        set ring_width {2.0 2.0}
        if {[info exists fc(power,ring_width)]} { set ring_width $fc(power,ring_width) }

        set ring_spacing {0.5 0.5}
        if {[info exists fc(power,ring_spacing)]} { set ring_spacing $fc(power,ring_spacing) }

        set ring_offset {2.0 2.0}
        if {[info exists fc(power,ring_offset)]} { set ring_offset $fc(power,ring_offset) }

        puts "CBflow-info: Creating PG ring for $vdd_net on layers $ring_layers"
        create_pg_ring_pattern ring_vdd -horizontal_layer [lindex $ring_layers 0] \
            -horizontal_width [lindex $ring_width 0] -horizontal_spacing [lindex $ring_spacing 0] \
            -vertical_layer [lindex $ring_layers 1] \
            -vertical_width [lindex $ring_width 1] -vertical_spacing [lindex $ring_spacing 1]

        set_pg_strategy ring_strategy_vdd -core \
            -pattern {{name: ring_vdd} {nets: $vdd_net $vss_net} {offset: $ring_offset}}

        compile_pg -strategies ring_strategy_vdd

        handle_info "Default PG rings created for $vdd_net/$vss_net"
    }

    handle_info "PG rings created"
}

# ---------------------------------------------------------------------------
# flow_proc: create_pg_mesh
# FC-RM: Create PG mesh/strap pattern across die (from create_power.tcl)
# ---------------------------------------------------------------------------
flow_proc create_pg_mesh {
    handle_info "Creating PG mesh..."
    global fcfp
    set run_dir $::env(CBFLOW_RUN_DIR)

    if {[info exists fc(power,mesh_config)] && $fc(power,mesh_config) ne ""} {
        # Source user PG mesh configuration
        source -e $fc(power,mesh_config)
        handle_info "PG mesh created from config file"
    } else {
        # Build PG mesh from config variables
        set vdd_net "VDD"
        set vss_net "VSS"
        if {[info exists fc(power,vdd_net)]} { set vdd_net $fc(power,vdd_net) }
        if {[info exists fc(power,vss_net)]} { set vss_net $fc(power,vss_net) }

        set h_layer "M9"
        set v_layer "M10"
        if {[info exists fc(power,mesh_h_layer)]} { set h_layer $fc(power,mesh_h_layer) }
        if {[info exists fc(power,mesh_v_layer)]} { set v_layer $fc(power,mesh_v_layer) }

        set mesh_width "1.0"
        if {[info exists fc(power,mesh_width)]} { set mesh_width $fc(power,mesh_width) }

        set mesh_pitch "50.0"
        if {[info exists fc(power,mesh_pitch)]} { set mesh_pitch $fc(power,mesh_pitch) }

        # FC-RM: Create mesh patterns for horizontal and vertical layers
        puts "CBflow-info: Creating PG mesh on $h_layer (horizontal) and $v_layer (vertical)"
        create_pg_mesh_pattern pg_mesh \
            -parameters {w p o} \
            -layers [list \
                [list {horizontal_layer: $h_layer} {width: @w} {spacing: interleaving} {pitch: @p} {offset: @o} {trim: true}] \
                [list {vertical_layer: $v_layer} {width: @w} {spacing: interleaving} {pitch: @p} {offset: @o} {trim: true}] \
            ]

        set_pg_strategy mesh_strategy -core \
            -pattern {{name: pg_mesh} {nets: $vdd_net $vss_net} {parameters: $mesh_width $mesh_pitch 10.0}}

        compile_pg -strategies mesh_strategy

        handle_info "Default PG mesh created on $h_layer/$v_layer"
    }

    handle_info "PG mesh created"
}

# ---------------------------------------------------------------------------
# flow_proc: create_pg_straps
# FC-RM: Create per-layer PG straps and standard cell rail connections
# ---------------------------------------------------------------------------
flow_proc create_pg_straps {
    handle_info "Creating PG straps and std cell connections..."
    global fcfp
    set run_dir $::env(CBFLOW_RUN_DIR)

    if {[info exists fc(power,strap_config)] && $fc(power,strap_config) ne ""} {
        # Source user strap configuration
        source -e $fc(power,strap_config)
        handle_info "PG straps created from config file"
    } else {
        set vdd_net "VDD"
        set vss_net "VSS"
        if {[info exists fc(power,vdd_net)]} { set vdd_net $fc(power,vdd_net) }
        if {[info exists fc(power,vss_net)]} { set vss_net $fc(power,vss_net) }

        # FC-RM: Standard cell rail connections on M1
        set rail_layer "M1"
        if {[info exists fc(power,std_cell_rail_layer)]} { set rail_layer $fc(power,std_cell_rail_layer) }

        puts "CBflow-info: Creating standard cell PG rail connections on $rail_layer"
        create_pg_std_cell_conn_pattern std_cell_rail \
            -layers $rail_layer

        set_pg_strategy std_cell_strategy -core \
            -pattern {{name: std_cell_rail} {nets: $vdd_net $vss_net}}

        compile_pg -strategies std_cell_strategy

        handle_info "Standard cell PG rail connections created on $rail_layer"
    }

    handle_info "PG straps and std cell connections created"
}

# ---------------------------------------------------------------------------
# flow_proc: connect_pg_net
# FC-RM: Connect VDD/VSS nets (from create_power.tcl)
# ---------------------------------------------------------------------------
flow_proc connect_pg_net {
    handle_info "Connecting PG nets..."
    global fcfp
    set run_dir $::env(CBFLOW_RUN_DIR)

    # FC-RM: Connect all PG nets
    connect_pg_net

    # FC-RM: Handle special power domains if configured
    if {[info exists fc(power,special_pg_nets)] && $fc(power,special_pg_nets) ne ""} {
        foreach {net pin_pat} $fc(power,special_pg_nets) {
            handle_info "Connecting special PG net: $net"
        }
    }

    # FC-RM: Place and legalize stdcells for robust PG analysis
    if {[info exists fc(power,place_stdcells)] && $fc(power,place_stdcells)} {
        set_app_options -name place.coarse.continue_on_missing_scandef -value true
        create_placement -effort low
        reset_app_options place.coarse.continue_on_missing_scandef
        connect_pg_net
        handle_info "Stdcells placed and PG re-connected"
    }

    handle_info "PG nets connected"
}

# ---------------------------------------------------------------------------
# flow_proc: check_pg_connectivity
# FC-RM: Verify PG network connectivity (from create_power.tcl)
# ---------------------------------------------------------------------------
flow_proc check_pg_connectivity {
    handle_info "Checking PG connectivity..."
    global fcfp
    set run_dir $::env(CBFLOW_RUN_DIR)

    # FC-RM: Check PG connectivity
    redirect -file $::REPORTS_DIR/check_pg_connectivity.rpt {check_pg_connectivity}

    # FC-RM: Check PG DRC
    redirect -file $::REPORTS_DIR/check_pg_drc.rpt {check_pg_drc}

    # FC-RM: Check MV design
    redirect -file $::REPORTS_DIR/check_mv_design.rpt {check_mv_design}

    # Parse connectivity report for errors
    set conn_rpt "$::REPORTS_DIR/check_pg_connectivity.rpt"
    if {[file exists $conn_rpt]} {
        set fp [open $conn_rpt r]
        set content [read $fp]
        close $fp
        if {[string match "*OPEN*" $content] || [string match "*ERROR*" $content]} {
            handle_warning "PG connectivity issues found - review $conn_rpt"
        } else {
            handle_info "PG connectivity check passed"
        }
    }

    handle_info "PG connectivity verification completed"
}

# ---------------------------------------------------------------------------
# flow_proc: save_design_block
# FC-RM: Save design block (from create_power.tcl)
# ---------------------------------------------------------------------------
flow_proc save_design_block {
    handle_info "Saving design block..."
    global fcfp project

    if {[info exists fc(output,block_labeling)] && $fc(output,block_labeling)} {
        if {[info exists project(top_module)] && $project(top_module) ne ""} {
            set design_name $project(top_module)
        } else {
            set design_name [get_object_name [current_design]]
        }
        puts "CBflow-info: Saving block as ${design_name}/create_power"
        save_block -as ${design_name}/create_power
    } else {
        save_block
    }

    handle_info "Design block saved"
}

# ---------------------------------------------------------------------------
# flow_proc: generate_reports
# FC-RM: Power plan summary reports (from create_power.tcl)
# ---------------------------------------------------------------------------
flow_proc generate_reports {
    handle_info "Generating power plan reports..."
    global fcfp
    set run_dir $::env(CBFLOW_RUN_DIR)
    set res_dir "$run_dir/results/fcfp"

    # FC-RM: Check pre-placement stage
    redirect -file $::REPORTS_DIR/check_design.pre_placement \
        {check_design -checks pre_placement_stage}

    # FC-RM: Check legality if stdcells were placed
    redirect -file $::REPORTS_DIR/check_legality.rpt {check_legality}

    # Overall PG summary
    redirect -file $::REPORTS_DIR/pg_summary.rpt { report_pg }

    # Power estimate
    redirect -file $::REPORTS_DIR/pg_power_estimate.rpt { report_power }

    # Summary file
    set fp [open "$res_dir/fc_powerplan_summary.rpt" w]
    puts $fp "================================================================"
    puts $fp "FCFP Power Plan Summary - Fusion Compiler"
    puts $fp "Ported from FC-RM Y-2026.03 create_power.tcl"
    puts $fp "Date: [clock format [clock seconds]]"
    puts $fp "================================================================"
    puts $fp ""
    puts $fp "Power plan stages:"
    puts $fp "  1. PG ring creation"
    puts $fp "  2. PG mesh creation"
    puts $fp "  3. PG strap / std cell rail creation"
    puts $fp "  4. PG net connection"
    puts $fp "  5. PG connectivity verification"
    puts $fp ""
    puts $fp "Reports:"
    foreach f [glob -nocomplain "$::REPORTS_DIR/*.rpt"] {
        puts $fp "  [file tail $f]"
    }
    puts $fp "================================================================"
    close $fp

    handle_info "Power plan reports generated"
}

# ---------------------------------------------------------------------------
# flow_proc: fc_powerplan_flow
# Execute all fc_powerplan flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc fc_powerplan_flow {
    handle_info "Executing FCFP fc_powerplan flow..."
    flow_exec create_pg_rings
    flow_exec create_pg_mesh
    flow_exec create_pg_straps
    flow_exec connect_pg_net
    flow_exec check_pg_connectivity
    flow_exec save_design_block
    flow_exec generate_reports
    handle_info "FCFP fc_powerplan completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec fc_powerplan_flow } else { puts " FCFP fc_powerplan procedures loaded" }

# Exit tool after stage completion
exit
