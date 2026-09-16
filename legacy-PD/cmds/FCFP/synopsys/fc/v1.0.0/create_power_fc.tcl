#!/usr/bin/env tclsh
# CBFlow FCFP create_power - Synopsys Fusion Compiler

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FCFP"
set STAGE_NAME "create_power"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ==============================================================================
# flow_proc: load_design
# ==============================================================================
flow_proc load_design {
    handle_info "Loading design for create_power..."
    global fcfp flow

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

    if {[info exists fcfp(common,open_lib)] && $fcfp(common,open_lib) ne ""} {
        open_lib $fcfp(common,open_lib)
    }

    set from_label [expr {[info exists fcfp(create_power,from_label)] ? $fcfp(create_power,from_label) : "placement"}]
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

    if {[info exists fcfp(power,pns_script)] && [file exists $fcfp(power,pns_script)]} {
        handle_info "Sourcing PNS script: $fcfp(power,pns_script)"
        source $fcfp(power,pns_script)
    } else {
        # Build from config variables
        set vdd_net [expr {[info exists fcfp(power,vdd_net)] ? $fcfp(power,vdd_net) : "VDD"}]
        set vss_net [expr {[info exists fcfp(power,vss_net)] ? $fcfp(power,vss_net) : "VSS"}]

        # PG rings
        if {[info exists fcfp(power,ring_config)] && [file exists $fcfp(power,ring_config)]} {
            source $fcfp(power,ring_config)
        }

        # PG mesh
        if {[info exists fcfp(power,mesh_config)] && [file exists $fcfp(power,mesh_config)]} {
            source $fcfp(power,mesh_config)
        }

        # PG straps / std cell rails
        if {[info exists fcfp(power,strap_config)] && [file exists $fcfp(power,strap_config)]} {
            source $fcfp(power,strap_config)
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

    if {[info exists fcfp(power,place_stdcells)] && $fcfp(power,place_stdcells) ne "" && [string is true -strict $fcfp(power,place_stdcells)]} {
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

    if {[info exists fcfp(common,connect_pg_net_script)] && [file exists $fcfp(common,connect_pg_net_script)]} {
        source $fcfp(common,connect_pg_net_script)
    } else {
        connect_pg_net
    }

    # Handle special power domains
    if {[info exists fcfp(power,special_pg_nets)] && $fcfp(power,special_pg_nets) ne ""} {
        foreach {net pin_pat} $fcfp(power,special_pg_nets) {
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

    set design_name [expr {[info exists fcfp(common,design_name)] ? $fcfp(common,design_name) : $flow(design_name)}]

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
# ==============================================================================

flow_exec_all

# Exit tool after stage completion
exit
