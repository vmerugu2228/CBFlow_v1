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
set utils_path "$FLOW_DIR/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set FLOW_TYPE "FCFP"
set STAGE_NAME "fc_powerplan"
set NODE_NAME [cbflow_node_name]

# Generated per-node config (project + tech + flow + node + user cascade).
set config_file "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
if {![file exists $config_file]} { puts stderr "ERROR: node config not found: $config_file (run the $NODE_NAME setup subnode)"; exit 1 }
source $config_file
global fcfp project tech flow
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set WORK_DIR [cbflow_node_dir $NODE_NAME]
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

handle_info "Starting FCFP fc_powerplan stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CREATE POWER RINGS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc resolve_power_config {
    global fcfp project tech flow
    handle_info "Resolving power-plan configuration..."

    # PG nets: fcfp(power,vdd_net/vss_net) override, else the project's PG
    # definition project(power,vdd_net/vss_net). Error if neither.
    set ::PG(vdd) [expr {[info exists fcfp(power,vdd_net)] && $fcfp(power,vdd_net) ne "" ? $fcfp(power,vdd_net) : [cbflow_require project power,vdd_net]}]
    set ::PG(vss) [expr {[info exists fcfp(power,vss_net)] && $fcfp(power,vss_net) ne "" ? $fcfp(power,vss_net) : [cbflow_require project power,vss_net]}]

    # Layers: fcfp(power,*_layer_h/v) override, else the PG ring layers of the
    # project's metal stack — tech(<project(metal_stack)>,pg_ring_layer_h/v).
    set _ms [cbflow_require project metal_stack]
    foreach {_k _tk} {ring_layer_h pg_ring_layer_h ring_layer_v pg_ring_layer_v
                      strap_layer_h pg_ring_layer_h strap_layer_v pg_ring_layer_v} {
        set ::PG($_k) [expr {[info exists fcfp(power,$_k)] && $fcfp(power,$_k) ne "" ? $fcfp(power,$_k) : [cbflow_require tech "$_ms,$_tk"]}]
    }
    # sroute layer range: bottom metal of the stack up to the highest ring layer.
    set _ml [cbflow_require tech "$_ms,metal_layers"]
    set _i [expr {max([lsearch -exact $_ml $::PG(ring_layer_h)], [lsearch -exact $_ml $::PG(ring_layer_v)])}]
    if {$_i < 0} {
        handle_error "PG ring layers $::PG(ring_layer_h)/$::PG(ring_layer_v) are not in tech($_ms,metal_layers)"
        return
    }
    set ::PG(sroute_range) [list [lindex $_ml 0] [lindex $_ml $_i]]

    # Ring / strap geometry — FCFP_innovus_config power,* (no built-in values)
    foreach _k {ring_width ring_spacing ring_offset strap_width strap_spacing strap_pitch} {
        set ::PG($_k) [cbflow_require fcfp power,$_k]
    }

    puts "VDD net: $::PG(vdd), VSS net: $::PG(vss)"
    puts "Ring layers: $::PG(ring_layer_h) (H), $::PG(ring_layer_v) (V); straps $::PG(strap_layer_h)/$::PG(strap_layer_v); sroute $::PG(sroute_range)"
}

flow_proc create_power_rings {
    global fcfp project tech flow
    handle_info "Creating power rings..."

    file mkdir "$::REPORTS_DIR"

    set vdd_net      $::PG(vdd)
    set vss_net      $::PG(vss)
    set ring_width   $::PG(ring_width)
    set ring_spacing $::PG(ring_spacing)
    set ring_offset  $::PG(ring_offset)
    set ring_layer_h $::PG(ring_layer_h)
    set ring_layer_v $::PG(ring_layer_v)

    puts "Ring width: $ring_width, spacing: $ring_spacing"

    # Create core power rings
    addRing -nets [list $vdd_net $vss_net] \
        -type core_rings \
        -follow core \
        -layer [list top $ring_layer_h bottom $ring_layer_h left $ring_layer_v right $ring_layer_v] \
        -width $ring_width \
        -spacing $ring_spacing \
        -offset $ring_offset

    # Create block rings around macros if configured
    if {[info exists fcfp(power,create_block_rings)] && $fcfp(power,create_block_rings) eq "true"} {
        puts "   Creating block power rings..."
        set block_ring_width [cbflow_require fcfp power,block_ring_width]
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

    set vdd_net       $::PG(vdd)
    set vss_net       $::PG(vss)
    set strap_width   $::PG(strap_width)
    set strap_spacing $::PG(strap_spacing)
    set strap_pitch   $::PG(strap_pitch)

    # Horizontal straps
    set strap_layer_h $::PG(strap_layer_h)
    puts "Adding horizontal power straps on $strap_layer_h..."
    addStripe -nets [list $vdd_net $vss_net] \
        -layer $strap_layer_h \
        -direction horizontal \
        -width $strap_width \
        -spacing $strap_spacing \
        -set_to_set_distance $strap_pitch

    # Vertical straps
    set strap_layer_v $::PG(strap_layer_v)
    puts "Adding vertical power straps on $strap_layer_v..."
    addStripe -nets [list $vdd_net $vss_net] \
        -layer $strap_layer_v \
        -direction vertical \
        -width $strap_width \
        -spacing $strap_spacing \
        -set_to_set_distance $strap_pitch

    # Additional fine-pitch straps on lower layers if configured
    if {[info exists fcfp(power,fine_strap_layer)] && $fcfp(power,fine_strap_layer) ne "" && \
        [info exists fcfp(power,fine_strap_width)] && $fcfp(power,fine_strap_width) ne ""} {
        puts "Adding fine-pitch straps on $fcfp(power,fine_strap_layer)..."
        addStripe -nets [list $vdd_net $vss_net] \
            -layer $fcfp(power,fine_strap_layer) \
            -direction vertical \
            -width $fcfp(power,fine_strap_width) \
            -spacing $strap_spacing \
            -set_to_set_distance [cbflow_require fcfp power,fine_strap_pitch]
    }

    puts " Power straps created"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CONNECT POWER                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc connect_power {
    global fcfp project tech flow
    handle_info "Connecting power/ground nets..."

    set vdd_net $::PG(vdd)
    set vss_net $::PG(vss)

    # Connect VDD
    globalNetConnect $vdd_net -type pgpin -pin $vdd_net -inst * -override
    puts "   Connected $vdd_net to all instances"

    # Connect VSS
    globalNetConnect $vss_net -type pgpin -pin $vss_net -inst * -override
    puts "   Connected $vss_net to all instances"

    # Connect tie-high/tie-low cells if configured
    if {[info exists fcfp(power,tie_high_net)] && $fcfp(power,tie_high_net) ne ""} {
        globalNetConnect $fcfp(power,tie_high_net) -type tiehi -inst * -override
        puts "   Connected tie-high: $fcfp(power,tie_high_net)"
    }
    if {[info exists fcfp(power,tie_low_net)] && $fcfp(power,tie_low_net) ne ""} {
        globalNetConnect $fcfp(power,tie_low_net) -type tielo -inst * -override
        puts "   Connected tie-low: $fcfp(power,tie_low_net)"
    }

    # Special route for power connections
    sroute -connect {blockPin padPin padRing corePin floatingStripe} \
        -layerChangeRange $::PG(sroute_range) \
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
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Tool: Cadence Innovus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp ""
    puts $fp "Power Nets:"
    puts $fp "  VDD: $::PG(vdd)"
    puts $fp "  VSS: $::PG(vss)"
    puts $fp ""
    puts $fp "Configuration:"
    puts $fp "  Ring width: $::PG(ring_width)"
    puts $fp "  Strap width: $::PG(strap_width)"
    puts $fp "  Strap pitch: $::PG(strap_pitch)"
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
    flow_exec resolve_power_config
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
