#!/usr/bin/env tclsh
# CBFlow FP powerplan - Synopsys Fusion Compiler | FP powerplan
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FP/powerplan/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FP powerplan with Synopsys Fusion Compiler..."
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

set WORK_DIR "$run_dir/work/FP/powerplan"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: create_power_rings
# Description: Create PG rings around core boundary and macro boundaries
# ==============================================================================
flow_proc create_power_rings {
    handle_info "Creating power rings..."
    global fp tech

    file mkdir "$::REPORTS_DIR"

    # Define ring parameters
    if {[info exists fc(common,ring_horizontal_layer)]} {
        set h_layer $fc(common,ring_horizontal_layer)
    } else {
        set h_layer "M7"
    }
    if {[info exists fc(common,ring_vertical_layer)]} {
        set v_layer $fc(common,ring_vertical_layer)
    } else {
        set v_layer "M8"
    }
    if {[info exists fc(common,ring_width)]} {
        set ring_w $fc(common,ring_width)
    } else {
        set ring_w 3.0
    }
    if {[info exists fc(common,ring_spacing)]} {
        set ring_s $fc(common,ring_spacing)
    } else {
        set ring_s 1.0
    }

    # Create core ring pattern
    handle_info "Creating core PG ring: H=$h_layer V=$v_layer W=$ring_w S=$ring_s"
    create_pg_ring_pattern core_ring_pat \
        -horizontal_layer $h_layer \
        -horizontal_width $ring_w \
        -horizontal_spacing $ring_s \
        -vertical_layer $v_layer \
        -vertical_width $ring_w \
        -vertical_spacing $ring_s

    set_pg_strategy core_ring_strat \
        -core \
        -pattern {{name: core_ring_pat} {nets: {VDD VSS}}}

    compile_pg -strategies core_ring_strat

    # Create macro rings if hard macros exist
    set macros [get_cells -hierarchical -filter "is_hard_macro == true"]
    if {[sizeof_collection $macros] > 0} {
        handle_info "Creating macro rings around [sizeof_collection $macros] macros..."
        create_pg_ring_pattern macro_ring_pat \
            -horizontal_layer $h_layer \
            -horizontal_width [expr {$ring_w * 0.5}] \
            -horizontal_spacing $ring_s \
            -vertical_layer $v_layer \
            -vertical_width [expr {$ring_w * 0.5}] \
            -vertical_spacing $ring_s

        set_pg_strategy macro_ring_strat \
            -macros $macros \
            -pattern {{name: macro_ring_pat} {nets: {VDD VSS}}}

        compile_pg -strategies macro_ring_strat
    }

    handle_info "Power rings created successfully"
}

# ==============================================================================
# flow_proc: create_power_straps
# Description: Create PG straps (mesh) on multiple metal layers
# ==============================================================================
flow_proc create_power_straps {
    handle_info "Creating power straps..."
    global fp tech

    # Define strap configuration per metal layer
    if {[info exists fc(common,pg_strap_config)]} {
        set strap_config $fc(common,pg_strap_config)
    } else {
        # Default strap configuration for typical metal stack
        set strap_config {
            {M3 0.5 10.0 0}
            {M4 0.5 10.0 0}
            {M5 1.0 20.0 0}
            {M6 1.0 20.0 0}
            {M7 2.0 40.0 0}
            {M8 2.0 40.0 0}
        }
    }

    foreach strap_def $strap_config {
        set layer  [lindex $strap_def 0]
        set width  [lindex $strap_def 1]
        set pitch  [lindex $strap_def 2]
        set offset [lindex $strap_def 3]

        handle_info "Creating PG straps on $layer: width=$width pitch=$pitch"

        create_pg_mesh_pattern pg_strap_${layer}_pat \
            -layers [list [list \
                {layer: $layer} \
                {width: $width} \
                {pitch: $pitch} \
                {offset: $offset}]]

        set_pg_strategy pg_strap_${layer}_strat \
            -core \
            -pattern {{name: pg_strap_${layer}_pat} {nets: {VDD VSS}}}

        compile_pg -strategies pg_strap_${layer}_strat
    }

    # Create M1 standard cell rails (followpin)
    handle_info "Creating standard cell follow-pin connections..."
    create_pg_std_cell_conn_pattern std_cell_rail_pat \
        -layers {M1}

    set_pg_strategy std_cell_rail_strat \
        -core \
        -pattern {{name: std_cell_rail_pat} {nets: {VDD VSS}}}

    compile_pg -strategies std_cell_rail_strat

    handle_info "Power straps created on all specified layers"
}

# ==============================================================================
# flow_proc: connect_power
# Description: Connect PG nets to all standard cells and macros
# ==============================================================================
flow_proc connect_power {
    handle_info "Connecting power/ground nets..."
    global fp

    # Connect all PG pins to PG nets
    handle_info "Connecting VDD net..."
    connect_pg_net -net VDD \
        -pin_pattern {VDD} \
        -cells [get_cells -hierarchical]

    handle_info "Connecting VSS net..."
    connect_pg_net -net VSS \
        -pin_pattern {VSS} \
        -cells [get_cells -hierarchical]

    # Connect tie-off cells if present
    connect_pg_net -net VDD -pin_pattern {VPWR}
    connect_pg_net -net VSS -pin_pattern {VGND}

    # Handle additional power domains if UPF is used
    if {[info exists fc(common,power_domains)]} {
        foreach {domain supply_net ground_net} $fc(common,power_domains) {
            handle_info "Connecting power domain $domain: supply=$supply_net ground=$ground_net"
            connect_pg_net -net $supply_net -pin_pattern $supply_net
            connect_pg_net -net $ground_net -pin_pattern $ground_net
        }
    }

    handle_info "Power/ground connections completed"
}

# ==============================================================================
# flow_proc: verify_power
# Description: Verify PG connectivity and integrity
# ==============================================================================
flow_proc verify_power {
    handle_info "Verifying power grid connectivity..."
    global fp

    # Check PG connectivity
    handle_info "Running check_pg_connectivity..."
    redirect -file $::REPORTS_DIR/pg_connectivity.rpt {
        check_pg_connectivity
    }

    # Check for missing PG connections
    redirect -file $::REPORTS_DIR/pg_missing_conn.rpt {
        check_pg_connectivity -check_std_cell_pins
    }

    # Check PG DRC
    handle_info "Running check_pg_drc..."
    redirect -file $::REPORTS_DIR/pg_drc.rpt {
        check_pg_drc
    }

    # Verify voltage area definitions if UPF is used
    if {[info exists fc(common,input_upf)]} {
        redirect -file $::REPORTS_DIR/voltage_area.rpt {
            report_voltage_area
        }
    }

    handle_info "Power grid verification completed"
}

# ==============================================================================
# flow_proc: generate_power_reports
# Description: Generate comprehensive power grid reports
# ==============================================================================
flow_proc generate_power_reports {
    handle_info "Generating power grid reports..."

    # PG summary report
    redirect -file $::REPORTS_DIR/pg_summary.rpt {
        report_pg_strategy
    }

    # Report PG via count
    redirect -file $::REPORTS_DIR/pg_via_count.rpt {
        report_pg_via_count
    }

    # Report IR drop estimate (if available)
    redirect -file $::REPORTS_DIR/ir_drop_estimate.rpt {
        report_power -analysis_effort low
    }

    # Report PG net routing statistics
    redirect -file $::REPORTS_DIR/pg_routing_stats.rpt {
        report_routing_statistics -type pg
    }

    # Save powerplan state
    handle_info "Saving powerplan state..."
    save_block -as $fc(common,design_lib_name):$fc(common,design_name)/powerplan_done

    handle_info "Power grid reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FP/powerplan1/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source -e $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source -e $_override_file }
set _stage_override "$run_dir/setup/override_setup.powerplan.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source -e $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
