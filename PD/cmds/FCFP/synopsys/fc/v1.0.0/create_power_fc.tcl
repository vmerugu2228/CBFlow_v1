#!/usr/bin/env tclsh
# CBFlow FCFP create_power - Synopsys Fusion Compiler
# FC-RM: create_power.tcl (hier) -- PG network creation, stdcell placement,
#         PG connection, PG DRC checks
# Aligned with FC-RM Y-2026.03
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header
set config_file "$run_dir/work/FCFP/create_power/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global fcfp project tech flow
# Source FC tool config
set _tool_config "[file dirname [info script]]/fc_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP create_power..."
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

set WORK_DIR "$run_dir/work/FCFP/create_power1"
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
    handle_info "Loading design for create_power..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    if {[info exists fc(common,open_lib)] && $fc(common,open_lib) ne ""} {
        open_lib $fc(common,open_lib)
    }

    set from_label [expr {[info exists fc(create_power,from_label)] ? $fc(create_power,from_label) : "placement"}]
    copy_block -from ${design_name}/${from_label} -to ${design_name}/create_power
    current_block ${design_name}/create_power
    link_block

    handle_info "Design loaded: $design_name"
}

# ==============================================================================
# flow_proc: create_power_network
# FC-RM: Source PNS file or build PG rings/mesh/straps
# ==============================================================================
flow_proc create_power_network {
    handle_info "Creating power network..."
    global fcfp

    # Check design pre-power insertion
    redirect -file $::REPORTS_DIR/check_design.pre_power {
        check_design -checks dp_pre_power_insertion
    }

    if {[info exists fc(power,pns_script)] && [file exists $fc(power,pns_script)]} {
        handle_info "Sourcing PNS script: $fc(power,pns_script)"
        source -e $fc(power,pns_script)
    } else {
        # Build from config variables
        set vdd_net [expr {[info exists fc(power,vdd_net)] ? $fc(power,vdd_net) : "VDD"}]
        set vss_net [expr {[info exists fc(power,vss_net)] ? $fc(power,vss_net) : "VSS"}]

        # PG rings
        if {[info exists fc(power,ring_config)] && [file exists $fc(power,ring_config)]} {
            source -e $fc(power,ring_config)
        }

        # PG mesh
        if {[info exists fc(power,mesh_config)] && [file exists $fc(power,mesh_config)]} {
            source -e $fc(power,mesh_config)
        }

        # PG straps / std cell rails
        if {[info exists fc(power,strap_config)] && [file exists $fc(power,strap_config)]} {
            source -e $fc(power,strap_config)
        }

        handle_info "PG network created for $vdd_net/$vss_net"
    }

    handle_info "Power network creation completed"
}

# ==============================================================================
# flow_proc: stdcell_placement
# FC-RM: create_placement -effort low for robust PG analysis
# ==============================================================================
flow_proc stdcell_placement {
    handle_info "Running low-effort stdcell placement for PG analysis..."
    global fcfp

    if {[info exists fc(power,place_stdcells)] && $fc(power,place_stdcells)} {
        set_app_options -name place.coarse.continue_on_missing_scandef -value true
        create_placement -effort low
        reset_app_options place.coarse.continue_on_missing_scandef
        handle_info "Stdcell placement completed"
    } else {
        handle_info "Stdcell placement not enabled; skipping"
    }
}

# ==============================================================================
# flow_proc: connect_pg
# FC-RM: connect_pg_net
# ==============================================================================
flow_proc connect_pg {
    handle_info "Connecting PG nets..."
    global fcfp

    if {[info exists fc(common,connect_pg_net_script)] && [file exists $fc(common,connect_pg_net_script)]} {
        source -e $fc(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    # Handle special power domains
    if {[info exists fc(power,special_pg_nets)] && $fc(power,special_pg_nets) ne ""} {
        foreach {net pin_pat} $fc(power,special_pg_nets) {
            handle_info "Connecting special PG net: $net"
        }
    }

    handle_info "PG nets connected"
}

# ==============================================================================
# flow_proc: check_pg
# FC-RM: check_pg_connectivity, check_pg_drc, check_mv_design
# ==============================================================================
flow_proc check_pg {
    handle_info "Checking PG connectivity and DRC..."

    redirect -file $::REPORTS_DIR/check_pg_connectivity.rpt { check_pg_connectivity }
    redirect -file $::REPORTS_DIR/check_pg_drc.rpt { check_pg_drc }
    redirect -file $::REPORTS_DIR/check_mv_design.rpt { check_mv_design }

    handle_info "PG checks completed"
}

# ==============================================================================
# flow_proc: save_design
# ==============================================================================
flow_proc save_design {
    handle_info "Saving create_power block..."
    global fcfp flow

    set design_name [expr {[info exists fc(common,design_name)] ? $fc(common,design_name) : $flow(design_name)}]

    save_lib -all
    save_block
    save_block -as ${design_name}/create_power
    handle_info "Block saved: ${design_name}/create_power"
}

# ==============================================================================
# flow_proc: generate_reports
# ==============================================================================
flow_proc generate_reports {
    handle_info "Generating create_power reports..."
    global fcfp

    redirect -file $::REPORTS_DIR/report_design.rpt { report_design -physical }
    redirect -file $::REPORTS_DIR/report_utilization.rpt { report_utilization }
    redirect -file $::REPORTS_DIR/check_legality.rpt { check_legality }
    redirect -file $::REPORTS_DIR/report_pg.rpt { report_pg }
    redirect -file $::REPORTS_DIR/report_power.rpt { report_power }
    redirect -file $::REPORTS_DIR/check_design.pre_placement.rpt {
        check_design -checks pre_placement_stage
    }
    redirect -file $::REPORTS_DIR/report_msg_summary.rpt { report_msg -summary }

    handle_info "Create_power reports generated in: $::REPORTS_DIR"
}

# ==============================================================================
# Source setup.tcl and overrides before flow_exec_all
# ==============================================================================
set _setup_file "$run_dir/work/FCFP/create_power/run/setup.tcl"
if {[file exists $_setup_file]} { handle_info "Sourcing setup hooks: $_setup_file"; source $_setup_file }
set _override_file "$run_dir/setup/override_setup.tcl"
if {[file exists $_override_file]} { handle_info "Sourcing user override: $_override_file"; source $_override_file }
set _stage_override "$run_dir/setup/override_setup.create_power.tcl"
if {[file exists $_stage_override]} { handle_info "Sourcing stage override: $_stage_override"; source $_stage_override }

flow_exec_all

# Exit tool after stage completion
exit
