#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - EMIR IR Drop Analysis Command File (Voltus)
# Description: Power grid IR drop analysis with hotspot detection and reporting
# Tool: Cadence Voltus
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/EMIR/ir_drop/run/config.tcl"
if {[file exists $config_file]} { source $config_file }
global emir project tech flow

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

# Source VOLTUS tool config
set _tool_config "[file dirname [info script]]/voltus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting EMIR ir_drop stage with Voltus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/ir_drop"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     CONFIGURE IR DROP                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc configure_ir {
    global emir project tech flow
    handle_info "Configuring IR drop analysis settings..."

    file mkdir "$::REPORTS_DIR/ir_drop"
    file mkdir "$::OUTPUTS_DIR/emir/ir_drop"

    # Set PG analysis mode
    if {[info exists voltus(ir_drop,analysis_mode)]} {
        puts "PG analysis mode: $voltus(ir_drop,analysis_mode)"
        set_pg_analysis_mode -power_grid_mode $voltus(ir_drop,analysis_mode)
    } else {
        puts "PG analysis mode: static (default)"
        set_pg_analysis_mode -power_grid_mode static
    }

    # Set IR drop threshold from config
    if {[info exists voltus(ir_drop,threshold)]} {
        puts "IR drop threshold: $voltus(ir_drop,threshold)V"
        set_pg_analysis_mode -ir_drop_limit $voltus(ir_drop,threshold)
    }

    # Set EM threshold from config
    if {[info exists voltus(em,threshold)]} {
        puts "EM current density threshold: $voltus(em,threshold)"
        set_pg_analysis_mode -em_limit $voltus(em,threshold)
    }

    # Configure power net names
    if {[info exists voltus(power,vdd_net)]} {
        puts "VDD net: $voltus(power,vdd_net)"
    }
    if {[info exists voltus(power,vss_net)]} {
        puts "VSS net: $voltus(power,vss_net)"
    }

    # Set analysis precision
    if {[info exists voltus(ir_drop,mesh_density)]} {
        set_pg_analysis_mode -mesh_density $voltus(ir_drop,mesh_density)
        puts "Mesh density: $voltus(ir_drop,mesh_density)"
    }

    # Configure voltage source locations
    if {[info exists voltus(ir_drop,pad_location_file)]} {
        if {[file exists $voltus(ir_drop,pad_location_file)]} {
            read_pg_pad_location $voltus(ir_drop,pad_location_file)
            puts "Pad locations loaded: $voltus(ir_drop,pad_location_file)"
        }
    }

    puts " IR drop configuration completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     RUN IR DROP ANALYSIS                                   │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_ir_drop {
    global emir project tech flow
    handle_info "Running power grid IR drop analysis..."

    # Run static IR drop analysis
    puts "Analyzing static IR drop..."
    analyze_power_grid -type ir_drop

    # Write static IR drop results
    set static_rpt "$::REPORTS_DIR/ir_drop/static_ir_drop.rpt"
    report_pg_ir_drop \
        -out_file $static_rpt
    handle_info "  Static IR drop report: $static_rpt"

    # Generate IR drop voltage map
    set ir_map "$::OUTPUTS_DIR/emir/ir_drop/ir_drop_map.rptdb"
    report_pg_ir_drop -map \
        -out_file $ir_map
    handle_info "  IR drop map: $ir_map"

    # Run dynamic IR drop if configured
    if {[info exists voltus(ir_drop,run_dynamic)] && $voltus(ir_drop,run_dynamic) eq "true"} {
        puts "Analyzing dynamic IR drop..."
        set_pg_analysis_mode -power_grid_mode dynamic
        analyze_power_grid -type ir_drop

        set dynamic_rpt "$::REPORTS_DIR/ir_drop/dynamic_ir_drop.rpt"
        report_pg_ir_drop \
            -out_file $dynamic_rpt
        handle_info "  Dynamic IR drop report: $dynamic_rpt"
    }

    # Run EM analysis
    if {![info exists voltus(em,skip)] || $voltus(em,skip) ne "true"} {
        puts "Analyzing electromigration..."
        analyze_power_grid -type em

        set em_rpt "$::REPORTS_DIR/ir_drop/em_analysis.rpt"
        report_pg_em \
            -out_file $em_rpt
        handle_info "  EM analysis report: $em_rpt"
    }

    puts " IR drop analysis completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     IDENTIFY HOTSPOTS                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc identify_hotspots {
    global emir project tech flow
    handle_info "Identifying IR drop and EM hotspots..."

    # Report PG hotspots based on threshold
    set hotspot_rpt "$::REPORTS_DIR/ir_drop/pg_hotspots.rpt"

    if {[info exists voltus(ir_drop,threshold)]} {
        report_pg_hotspot \
            -ir_drop_threshold $voltus(ir_drop,threshold) \
            -out_file $hotspot_rpt
    } else {
        report_pg_hotspot \
            -out_file $hotspot_rpt
    }
    handle_info "  Hotspot report: $hotspot_rpt"

    # Report worst-case IR drop instances
    set worst_rpt "$::REPORTS_DIR/ir_drop/worst_ir_instances.rpt"
    if {[info exists voltus(ir_drop,max_violations)]} {
        set max_violations $voltus(ir_drop,max_violations)
    } else {
        set max_violations 100
    }

    report_pg_ir_drop -worst_case $max_violations \
        -out_file $worst_rpt
    handle_info "  Worst IR drop instances ($max_violations): $worst_rpt"

    # EM hotspot detection
    if {![info exists voltus(em,skip)] || $voltus(em,skip) ne "true"} {
        set em_hotspot_rpt "$::REPORTS_DIR/ir_drop/em_hotspots.rpt"
        if {[info exists voltus(em,threshold)]} {
            report_pg_hotspot \
                -em_threshold $voltus(em,threshold) \
                -out_file $em_hotspot_rpt
        } else {
            report_pg_hotspot -type em \
                -out_file $em_hotspot_rpt
        }
        handle_info "  EM hotspot report: $em_hotspot_rpt"
    }

    puts " Hotspot identification completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     GENERATE REPORT                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_report {
    global emir project tech flow
    handle_info "Generating IR drop analysis summary..."

    set summary_file "$::REPORTS_DIR/ir_drop/ir_drop_summary.rpt"
    file mkdir [file dirname $summary_file]
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow EMIR IR Drop Analysis Summary - Voltus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp "Tool: Cadence Voltus"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    puts $fp ""
    puts $fp "Configuration:"
    if {[info exists voltus(ir_drop,analysis_mode)]} { puts $fp "  Analysis mode: $voltus(ir_drop,analysis_mode)" }
    if {[info exists voltus(ir_drop,threshold)]} { puts $fp "  IR drop threshold: $voltus(ir_drop,threshold)V" }
    if {[info exists voltus(em,threshold)]} { puts $fp "  EM threshold: $voltus(em,threshold)" }
    if {[info exists voltus(power,vdd_net)]} { puts $fp "  VDD net: $voltus(power,vdd_net)" }
    if {[info exists voltus(power,vss_net)]} { puts $fp "  VSS net: $voltus(power,vss_net)" }
    puts $fp ""
    puts $fp "Reports Generated:"
    puts $fp "  Static IR drop:    reports/emir/ir_drop/static_ir_drop.rpt"
    puts $fp "  PG hotspots:       reports/emir/ir_drop/pg_hotspots.rpt"
    puts $fp "  Worst instances:   reports/emir/ir_drop/worst_ir_instances.rpt"
    puts $fp "  IR drop map:       results/emir/ir_drop/ir_drop_map.rptdb"
    if {[info exists voltus(ir_drop,run_dynamic)] && $voltus(ir_drop,run_dynamic) eq "true"} {
        puts $fp "  Dynamic IR drop:   reports/emir/ir_drop/dynamic_ir_drop.rpt"
    }
    if {![info exists voltus(em,skip)] || $voltus(em,skip) ne "true"} {
        puts $fp "  EM analysis:       reports/emir/ir_drop/em_analysis.rpt"
        puts $fp "  EM hotspots:       reports/emir/ir_drop/em_hotspots.rpt"
    }
    close $fp

    handle_info "  Summary: $summary_file"
    puts " IR drop reporting completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow EMIR ir_drop with Voltus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc ir_drop_flow {
    handle_info "Executing EMIR ir_drop flow..."
    flow_exec configure_ir
    flow_exec run_ir_drop
    flow_exec identify_hotspots
    flow_exec generate_report
    handle_info "EMIR ir_drop completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec ir_drop_flow } else { puts " EMIR ir_drop procedures loaded" }

# Exit tool after stage completion
exit
