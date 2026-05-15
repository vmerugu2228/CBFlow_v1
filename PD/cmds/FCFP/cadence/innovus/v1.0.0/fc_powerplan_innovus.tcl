#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FCFP Power Plan Command File (Innovus)
# Description: Create power rings, power straps, connect PG nets, verify power
#              grid, and generate power plan reports
# Tool: Cadence Innovus
# ═══════════════════════════════════════════════════════════════════════════════

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

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
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

# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting FCFP fc_powerplan stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CREATE POWER RINGS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc create_power_rings {
    global fcfp project tech flow
    handle_info "Creating power rings..."

    file mkdir "$::REPORTS_DIR"

    # Get power net names from config
    if {[info exists innovus(power,vdd_net)]} {
        set vdd_net $innovus(power,vdd_net)
    } else {
        set vdd_net "VDD"
    }
    if {[info exists innovus(power,vss_net)]} {
        set vss_net $innovus(power,vss_net)
    } else {
        set vss_net "VSS"
    }

    # Get ring parameters from config
    if {[info exists innovus(power,ring_width)]} {
        set ring_width $innovus(power,ring_width)
    } else {
        set ring_width 2.0
    }
    if {[info exists innovus(power,ring_spacing)]} {
        set ring_spacing $innovus(power,ring_spacing)
    } else {
        set ring_spacing 1.0
    }
    if {[info exists innovus(power,ring_offset)]} {
        set ring_offset $innovus(power,ring_offset)
    } else {
        set ring_offset 2.0
    }

    # Get ring layers from config
    if {[info exists innovus(power,ring_layer_h)]} {
        set ring_layer_h $innovus(power,ring_layer_h)
    } else {
        set ring_layer_h "metal5"
    }
    if {[info exists innovus(power,ring_layer_v)]} {
        set ring_layer_v $innovus(power,ring_layer_v)
    } else {
        set ring_layer_v "metal6"
    }

    puts "VDD net: $vdd_net, VSS net: $vss_net"
    puts "Ring width: $ring_width, spacing: $ring_spacing"
    puts "Ring layers: $ring_layer_h (H), $ring_layer_v (V)"

    # Create core power rings
    addRing -nets [list $vdd_net $vss_net] \
        -type core_rings \
        -follow core \
        -layer [list top $ring_layer_h bottom $ring_layer_h left $ring_layer_v right $ring_layer_v] \
        -width $ring_width \
        -spacing $ring_spacing \
        -offset $ring_offset

    # Create block rings around macros if configured
    if {[info exists innovus(power,create_block_rings)] && $innovus(power,create_block_rings) eq "true"} {
        puts "   Creating block power rings..."
        if {[info exists innovus(power,block_ring_width)]} {
            set block_ring_width $innovus(power,block_ring_width)
        } else {
            set block_ring_width 1.0
        }
        addRing -nets [list $vdd_net $vss_net] \
            -type block_rings \
            -around each_block \
            -layer [list top $ring_layer_h bottom $ring_layer_h left $ring_layer_v right $ring_layer_v] \
            -width $block_ring_width \
            -spacing $ring_spacing \
            -offset $ring_offset
    }

    puts " Power rings created"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CREATE POWER STRAPS                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc create_power_straps {
    global fcfp project tech flow
    handle_info "Creating power straps..."

    # Get power net names
    if {[info exists innovus(power,vdd_net)]} { set vdd_net $innovus(power,vdd_net) } else { set vdd_net "VDD" }
    if {[info exists innovus(power,vss_net)]} { set vss_net $innovus(power,vss_net) } else { set vss_net "VSS" }

    # Get strap parameters from config
    if {[info exists innovus(power,strap_width)]} {
        set strap_width $innovus(power,strap_width)
    } else {
        set strap_width 1.0
    }
    if {[info exists innovus(power,strap_spacing)]} {
        set strap_spacing $innovus(power,strap_spacing)
    } else {
        set strap_spacing 1.0
    }
    if {[info exists innovus(power,strap_pitch)]} {
        set strap_pitch $innovus(power,strap_pitch)
    } else {
        set strap_pitch 20.0
    }

    # Horizontal straps
    if {[info exists innovus(power,strap_layer_h)]} {
        set strap_layer_h $innovus(power,strap_layer_h)
    } else {
        set strap_layer_h "metal5"
    }

    puts "Adding horizontal power straps on $strap_layer_h..."
    addStripe -nets [list $vdd_net $vss_net] \
        -layer $strap_layer_h \
        -direction horizontal \
        -width $strap_width \
        -spacing $strap_spacing \
        -set_to_set_distance $strap_pitch

    # Vertical straps
    if {[info exists innovus(power,strap_layer_v)]} {
        set strap_layer_v $innovus(power,strap_layer_v)
    } else {
        set strap_layer_v "metal6"
    }

    puts "Adding vertical power straps on $strap_layer_v..."
    addStripe -nets [list $vdd_net $vss_net] \
        -layer $strap_layer_v \
        -direction vertical \
        -width $strap_width \
        -spacing $strap_spacing \
        -set_to_set_distance $strap_pitch

    # Additional fine-pitch straps on lower layers if configured
    if {[info exists innovus(power,fine_strap_layer)] && [info exists innovus(power,fine_strap_width)]} {
        puts "Adding fine-pitch straps on $innovus(power,fine_strap_layer)..."
        addStripe -nets [list $vdd_net $vss_net] \
            -layer $innovus(power,fine_strap_layer) \
            -direction vertical \
            -width $innovus(power,fine_strap_width) \
            -spacing $strap_spacing \
            -set_to_set_distance $innovus(power,fine_strap_pitch)
    }

    puts " Power straps created"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CONNECT POWER                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc connect_power {
    global fcfp project tech flow
    handle_info "Connecting power/ground nets..."

    # Get power net names
    if {[info exists innovus(power,vdd_net)]} { set vdd_net $innovus(power,vdd_net) } else { set vdd_net "VDD" }
    if {[info exists innovus(power,vss_net)]} { set vss_net $innovus(power,vss_net) } else { set vss_net "VSS" }

    # Connect VDD
    globalNetConnect $vdd_net -type pgpin -pin $vdd_net -inst * -override
    puts "   Connected $vdd_net to all instances"

    # Connect VSS
    globalNetConnect $vss_net -type pgpin -pin $vss_net -inst * -override
    puts "   Connected $vss_net to all instances"

    # Connect tie-high/tie-low cells if configured
    if {[info exists innovus(power,tie_high_net)]} {
        globalNetConnect $innovus(power,tie_high_net) -type tiehi -inst * -override
        puts "   Connected tie-high: $innovus(power,tie_high_net)"
    }
    if {[info exists innovus(power,tie_low_net)]} {
        globalNetConnect $innovus(power,tie_low_net) -type tielo -inst * -override
        puts "   Connected tie-low: $innovus(power,tie_low_net)"
    }

    # Special route for power connections
    sroute -connect {blockPin padPin padRing corePin floatingStripe} \
        -layerChangeRange {metal1 metal6} \
        -blockPinTarget {nearestTarget} \
        -corePinTarget {firstAfterRowEnd} \
        -allowJogging 1 \
        -allowLayerChange 1 \
        -nets [list $vdd_net $vss_net]

    puts " Power connections completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     VERIFY POWER GRID                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc verify {
    global fcfp project tech flow
    handle_info "Verifying power grid connectivity..."

    file mkdir "$::REPORTS_DIR"

    # Verify PG connectivity
    set pg_verify_rpt "$::REPORTS_DIR/pg_verify.rpt"
    verifyConnectivity -type all -report $pg_verify_rpt
    handle_info "  PG connectivity: $pg_verify_rpt"

    # Check PG via generation
    set via_rpt "$::REPORTS_DIR/pg_via_check.rpt"
    verify_pg -report $via_rpt
    handle_info "  PG verification: $via_rpt"

    # Check for floating metals
    set drc_rpt "$::REPORTS_DIR/pg_drc.rpt"
    verifyGeometry -report $drc_rpt
    handle_info "  PG geometry: $drc_rpt"

    puts " Power grid verification completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE REPORT                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_report {
    global fcfp project tech flow
    handle_info "Generating power plan reports..."

    # Power grid summary
    report_power_grid > "$::REPORTS_DIR/power_grid_summary.rpt"

    # Summary file
    set summary_file "$::REPORTS_DIR/fc_powerplan_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow FCFP Power Plan Summary - Innovus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp "Tool: Cadence Innovus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp ""
    puts $fp "Power Nets:"
    if {[info exists innovus(power,vdd_net)]} { puts $fp "  VDD: $innovus(power,vdd_net)" }
    if {[info exists innovus(power,vss_net)]} { puts $fp "  VSS: $innovus(power,vss_net)" }
    puts $fp ""
    puts $fp "Configuration:"
    if {[info exists innovus(power,ring_width)]} { puts $fp "  Ring width: $innovus(power,ring_width)" }
    if {[info exists innovus(power,strap_width)]} { puts $fp "  Strap width: $innovus(power,strap_width)" }
    if {[info exists innovus(power,strap_pitch)]} { puts $fp "  Strap pitch: $innovus(power,strap_pitch)" }
    puts $fp ""
    puts $fp "Reports:"
    puts $fp "  Power grid:    reports/fcfp/powerplan/power_grid_summary.rpt"
    puts $fp "  PG verify:     reports/fcfp/powerplan/pg_verify.rpt"
    puts $fp "  PG DRC:        reports/fcfp/powerplan/pg_drc.rpt"
    close $fp

    handle_info "  Summary: $summary_file"
    puts " Power plan reports generated"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow FCFP fc_powerplan with Innovus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc fc_powerplan_flow {
    handle_info "Executing FCFP fc_powerplan flow..."
    flow_exec create_power_rings
    flow_exec create_power_straps
    flow_exec connect_power
    flow_exec verify
    flow_exec generate_report
    handle_info "FCFP fc_powerplan completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec fc_powerplan_flow } else { puts " FCFP fc_powerplan procedures loaded" }

# Exit tool after stage completion
exit
