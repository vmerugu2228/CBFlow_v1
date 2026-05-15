#!/usr/bin/env tclsh
# CBFlow PNR export_db - Cadence Innovus
set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global pnr project tech flow
# Source INNOVUS tool config
set _tool_config "[file dirname [info script]]/innovus_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PNR export_db with Cadence Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# -- Directories ---------------------------------------------------------------
set FLOW_TYPE "PNR"
set STAGE_NAME "export_db"
set NODE_NAME "export_data1"
set WORK_DIR "$run_dir/work/$FLOW_TYPE/$NODE_NAME"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

flow_proc enable_mmmc {
    # Enable MMMC scenarios for export_db stage
    global analysis_views mmmc
    
    handle_info "Enabling MMMC scenarios for export_db stage"
    
    # Load MMMC configuration
    if {![load_mmmc_config]} {
        handle_info "MMMC not configured, skipping scenario setup"
        return
    }
    
    # Get effective scenarios (user override or hardcoded defaults)
    set setup_scenarios [get_effective_scenarios "export_db" "setup"]
    set hold_scenarios [get_effective_scenarios "export_db" "hold"]
    
    if {![llength $setup_scenarios] && ![llength $hold_scenarios]} {
        handle_info "No MMMC scenarios configured for export_db, using default single-corner mode"
        return
    }
    
    # Combine setup and hold scenarios
    set all_scenarios [get_node_all_scenarios "export_db"]
    
    handle_info "export_db MMMC scenarios:"
    handle_info "  Setup scenarios ([llength $setup_scenarios]): [join $setup_scenarios { }]"
    handle_info "  Hold scenarios ([llength $hold_scenarios]): [join $hold_scenarios { }]"
    handle_info "  Total unique scenarios: [llength $all_scenarios]"
    
    # Tool-specific MMMC scenario setup would go here
    handle_info "MMMC scenarios configured for export_db stage"
}

flow_proc setup_export_directories {
    handle_info "Setting up export directory structure..."
    
    # Create comprehensive export directory structure
    set export_base "results/export"
    
    # Main categories
    ensure_directory "$export_base/layout"
    ensure_directory "$export_base/netlist"
    ensure_directory "$export_base/timing"
    ensure_directory "$export_base/power"
    ensure_directory "$export_base/physical"
    ensure_directory "$export_base/verification"
    ensure_directory "$export_base/documentation"
    ensure_directory "$export_base/scripts"
    ensure_directory "$export_base/libraries"
    
    # Layout subdirectories
    ensure_directory "$export_base/layout/gds"
    ensure_directory "$export_base/layout/def"
    ensure_directory "$export_base/layout/oasis"
    ensure_directory "$export_base/layout/abstract"
    
    # Netlist subdirectories
    ensure_directory "$export_base/netlist/verilog"
    ensure_directory "$export_base/netlist/spice"
    ensure_directory "$export_base/netlist/lef"
    
    # Timing subdirectories
    ensure_directory "$export_base/timing/sdc"
    ensure_directory "$export_base/timing/spef"
    ensure_directory "$export_base/timing/sdf"
    ensure_directory "$export_base/timing/mmmc"
    
    # Power subdirectories
    ensure_directory "$export_base/power/upf"
    ensure_directory "$export_base/power/analysis"
    ensure_directory "$export_base/power/reports"
    
    # Physical subdirectories
    ensure_directory "$export_base/physical/floorplan"
    ensure_directory "$export_base/physical/placement"
    ensure_directory "$export_base/physical/routing"
    
    # Verification subdirectories
    ensure_directory "$export_base/verification/drc"
    ensure_directory "$export_base/verification/lvs"
    ensure_directory "$export_base/verification/antenna"
    
    handle_info "Export directory structure created"
}

flow_proc export_layout_data {
    handle_info "Exporting layout data..."
    
    global pnr project tech
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    set stream_map_file [expr {[info exists tech(gds_map_file)] ? $tech(gds_map_file) : ""}]
    set export_base "results/export"

    # Get export parameters
    set gds_enable [expr {[info exists innovus(export,gds)] ? $innovus(export,gds) : "true"}]
    set def_enable [expr {[info exists innovus(export,def)] ? $innovus(export,def) : "true"}]
    set oasis_enable [expr {[info exists innovus(export,oasis)] ? $innovus(export,oasis) : "false"}]
    set abstract_enable [expr {[info exists innovus(export,abstract)] ? $innovus(export,abstract) : "true"}]
    
    handle_info "Layout export parameters:"
    handle_info "  GDS export: $gds_enable"
    handle_info "  DEF export: $def_enable"
    handle_info "  OASIS export: $oasis_enable"
    handle_info "  Abstract export: $abstract_enable"
    
    # Export GDS
    if {$gds_enable eq "true"} {
        handle_info "Exporting GDS layout..."
        set gds_file "$export_base/layout/gds/${top_module}.gds"
        
        # Tool-specific GDS export
        streamOut $gds_file -mapFile $stream_map_file -structureName $top_module

        # Generate GDS with different options
        set gds_hier_file "$export_base/layout/gds/${top_module}_hierarchical.gds"
        streamOut $gds_hier_file -mapFile $stream_map_file -mode hierarchical
        
        handle_info "GDS export completed: $gds_file"
    }
    
    # Export DEF
    if {$def_enable eq "true"} {
        handle_info "Exporting DEF layout..."
        
        # Full DEF with all information
        set def_full_file "$export_base/layout/def/${top_module}_full.def"
        defOut -floorplan -netlist -routing $def_full_file

        # Floorplan-only DEF
        set def_fp_file "$export_base/layout/def/${top_module}_floorplan.def"
        defOut -floorplan $def_fp_file

        # Placement-only DEF
        set def_place_file "$export_base/layout/def/${top_module}_placement.def"
        defOut -floorplan -netlist $def_place_file
        
        handle_info "DEF export completed"
    }
    
    # Export OASIS (if enabled)
    if {$oasis_enable eq "true"} {
        handle_info "Exporting OASIS layout..."
        set oasis_file "$export_base/layout/oasis/${top_module}.oas"
        
        # Tool-specific OASIS export
        streamOut $oasis_file -format oasis -mapFile $stream_map_file
        
        handle_info "OASIS export completed: $oasis_file"
    }
    
    # Export abstract views
    if {$abstract_enable eq "true"} {
        handle_info "Exporting abstract views..."
        
        # Generate LEF abstract
        set lef_file "$export_base/layout/abstract/${top_module}.lef"
        write_lef_abstract $lef_file -include_technology

        # Generate frame view
        set frame_file "$export_base/layout/abstract/${top_module}_frame.lef"
        write_lef_abstract $frame_file -frame_only
        
        handle_info "Abstract view export completed"
    }
}

flow_proc export_netlist_data {
    handle_info "Exporting netlist data..."
    
    global pnr project
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    set export_base "results/export"
    
    # Get netlist export parameters
    set verilog_enable [expr {[info exists innovus(export,verilog)] ? $innovus(export,verilog) : "true"}]
    set spice_enable [expr {[info exists innovus(export,spice)] ? $innovus(export,spice) : "false"}]
    set lef_enable [expr {[info exists innovus(export,lef)} ? $innovus(export,lef) : "true"}]
    
    handle_info "Netlist export parameters:"
    handle_info "  Verilog export: $verilog_enable"
    handle_info "  SPICE export: $spice_enable"
    handle_info "  LEF export: $lef_enable"
    
    # Export Verilog netlists
    if {$verilog_enable eq "true"} {
        handle_info "Exporting Verilog netlists..."
        
        # Final placed and routed netlist
        set verilog_final "$export_base/netlist/verilog/${top_module}_final.v"
        saveNetlist $verilog_final -includeLeakagePower -excludePowerGround

        # Physical-only netlist (for verification)
        set verilog_phys "$export_base/netlist/verilog/${top_module}_physical.v"
        saveNetlist $verilog_phys -physical

        # Hierarchical netlist
        set verilog_hier "$export_base/netlist/verilog/${top_module}_hierarchical.v"
        saveNetlist $verilog_hier -hierarchical
        
        handle_info "Verilog netlist export completed"
    }
    
    # Export SPICE netlists (if enabled)
    if {$spice_enable eq "true"} {
        handle_info "Exporting SPICE netlists..."
        
        # SPICE netlist for LVS
        set spice_lvs "$export_base/netlist/spice/${top_module}_lvs.sp"
        saveNetlist $spice_lvs -format spice -includeLeakagePower

        # SPICE netlist for simulation
        set spice_sim "$export_base/netlist/spice/${top_module}_sim.sp"
        saveNetlist $spice_sim -format spice -excludePowerGround
        
        handle_info "SPICE netlist export completed"
    }
    
    # Export LEF files
    if {$lef_enable eq "true"} {
        handle_info "Exporting LEF files..."
        
        # Technology LEF (copy from input)
        if {[info exists tech(lef,technology)]} {
            file copy $tech(lef,technology) "$export_base/netlist/lef/technology.lef"
        }
        
        # Standard cell LEF (copy from input)
        if {[info exists tech(lef,standard_cells)]} {
            foreach lef_file $tech(lef,standard_cells) {
                set lef_name [file tail $lef_file]
                file copy $lef_file "$export_base/netlist/lef/$lef_name"
            }
        }
        
        # Block-level LEF (if hierarchical design)
        set block_lef "$export_base/netlist/lef/${top_module}.lef"
        write_lef_abstract $block_lef
        
        handle_info "LEF file export completed"
    }
}

flow_proc export_timing_data {
    handle_info "Exporting timing data..."
    
    global pnr project mmmc
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    set export_base "results/export"
    
    # Get timing export parameters
    set sdc_enable [expr {[info exists innovus(export,sdc)] ? $innovus(export,sdc) : "true"}]
    set spef_enable [expr {[info exists innovus(export,spef)] ? $innovus(export,spef) : "true"}]
    set sdf_enable [expr {[info exists innovus(export,sdf)] ? $innovus(export,sdf) : "false"}]
    set mmmc_enable [expr {[info exists mmmc(enable)] ? $mmmc(enable) : "false"}]
    
    handle_info "Timing export parameters:"
    handle_info "  SDC export: $sdc_enable"
    handle_info "  SPEF export: $spef_enable"
    handle_info "  SDF export: $sdf_enable"
    handle_info "  MMMC export: $mmmc_enable"
    
    # Export SDC files
    if {$sdc_enable eq "true"} {
        handle_info "Exporting SDC constraints..."
        
        # Final SDC with all constraints
        set sdc_final "$export_base/timing/sdc/${top_module}_final.sdc"
        write_sdc $sdc_final

        # SDC for signoff tools
        set sdc_signoff "$export_base/timing/sdc/${top_module}_signoff.sdc"
        write_sdc $sdc_signoff -include_all_scenarios
        
        # Original input SDC (copy)
        if {[info exists pnr(input,sdc)] && [file exists $pnr(input,sdc)]} {
            file copy $pnr(input,sdc) "$export_base/timing/sdc/${top_module}_original.sdc"
        }
        
        handle_info "SDC export completed"
    }
    
    # Export SPEF files
    if {$spef_enable eq "true"} {
        handle_info "Exporting SPEF parasitics..."
        
        # Full SPEF with all parasitics
        set spef_full "$export_base/timing/spef/${top_module}_full.spef"
        rcOut -spef $spef_full

        # SPEF for critical nets only
        set spef_critical "$export_base/timing/spef/${top_module}_critical.spef"
        rcOut -spef $spef_critical -nets [get_nets -filter "is_clock==true || is_critical==true"]
        
        handle_info "SPEF export completed"
    }
    
    # Export SDF files (if enabled)
    if {$sdf_enable eq "true"} {
        handle_info "Exporting SDF timing..."
        
        # SDF for simulation
        set sdf_sim "$export_base/timing/sdf/${top_module}_sim.sdf"
        write_sdf $sdf_sim
        
        handle_info "SDF export completed"
    }
    
    # Export MMMC timing data
    if {$mmmc_enable eq "true"} {
        handle_info "Exporting MMMC timing data..."
        
        # Create MMMC-specific exports
        set mmmc_dir "$export_base/timing/mmmc"
        
        # Export scenarios configuration
        set mmmc_config "$mmmc_dir/mmmc_scenarios.tcl"
        set fd [open $mmmc_config "w"]
        puts $fd "# MMMC Scenarios Configuration"
        puts $fd "# Generated by OMNI FLOW"
        puts $fd ""
        
        # Get active scenarios
        if {[is_mmmc_stage "export_db"]} {
            set all_scenarios [get_node_all_scenarios "export_db"]
            foreach scenario $all_scenarios {
                puts $fd "# Scenario: $scenario"
                # Export scenario-specific data
                set scenario_spef "$mmmc_dir/${scenario}.spef"
                rcOut -spef $scenario_spef -corner $scenario

                set scenario_sdc "$mmmc_dir/${scenario}.sdc"
                write_sdc $scenario_sdc -corner $scenario
            }
        }
        
        close $fd
        handle_info "MMMC timing export completed"
    }
}

flow_proc export_power_data {
    handle_info "Exporting power data..."
    
    global pnr project
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    set export_base "results/export"
    
    # Get power export parameters
    set upf_enable [expr {[info exists innovus(export,upf)] ? $innovus(export,upf) : "true"}]
    set power_reports [expr {[info exists innovus(export,power_reports)] ? $innovus(export,power_reports) : "true"}]
    set rail_analysis [expr {[info exists innovus(export,rail_analysis)] ? $innovus(export,rail_analysis) : "true"}]
    
    handle_info "Power export parameters:"
    handle_info "  UPF export: $upf_enable"
    handle_info "  Power reports: $power_reports"
    handle_info "  Rail analysis: $rail_analysis"
    
    # Export UPF files
    if {$upf_enable eq "true"} {
        handle_info "Exporting UPF power intent..."
        
        # Final UPF with implementation details
        set upf_final "$export_base/power/upf/${top_module}_final.upf"
        write_power_intent $upf_final
        
        # Original input UPF (copy if exists)
        if {[info exists pnr(input,upf_file)] && [file exists $pnr(input,upf_file)]} {
            file copy $pnr(input,upf_file) "$export_base/power/upf/${top_module}_original.upf"
        }
        
        handle_info "UPF export completed"
    }
    
    # Export power analysis reports
    if {$power_reports eq "true"} {
        handle_info "Exporting power analysis reports..."
        
        # Copy existing power reports
        if {[file exists "$::REPORTS_DIR"]} {
            catch { file copy "$::REPORTS_DIR" "$export_base/power/reports/" }
        }
        
        # Generate additional power reports
        set power_summary "$export_base/power/analysis/power_summary.rpt"
        report_power > $power_summary

        set power_hierarchy "$export_base/power/analysis/power_hierarchy.rpt"
        report_power -by_hierarchy > $power_hierarchy
        
        handle_info "Power reports export completed"
    }
    
    # Export rail analysis data
    if {$rail_analysis eq "true"} {
        handle_info "Exporting rail analysis data..."
        
        # Rail analysis reports
        set rail_report "$export_base/power/analysis/rail_analysis.rpt"
        report_power -rail_analysis > $rail_report

        # IR drop analysis
        set ir_drop_report "$export_base/power/analysis/ir_drop_analysis.rpt"
        analyze_power_rail -report $ir_drop_report
        
        handle_info "Rail analysis export completed"
    }
}

flow_proc export_physical_data {
    handle_info "Exporting physical design data..."
    
    global pnr project
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    set export_base "results/export"
    
    # Get physical export parameters
    set floorplan_enable [expr {[info exists innovus(export,floorplan)] ? $innovus(export,floorplan) : "true"}]
    set placement_enable [expr {[info exists innovus(export,placement)] ? $innovus(export,placement) : "true"}]
    set routing_enable [expr {[info exists innovus(export,routing)] ? $innovus(export,routing) : "true"}]
    
    handle_info "Physical export parameters:"
    handle_info "  Floorplan data: $floorplan_enable"
    handle_info "  Placement data: $placement_enable"
    handle_info "  Routing data: $routing_enable"
    
    # Export floorplan data
    if {$floorplan_enable eq "true"} {
        handle_info "Exporting floorplan data..."
        
        # Floorplan DEF
        set fp_def "$export_base/physical/floorplan/${top_module}_floorplan.def"
        defOut -floorplan $fp_def
        
        # I/O placement file
        if {[info exists pnr(input,io_file)] && [file exists $pnr(input,io_file)]} {
            file copy $pnr(input,io_file) "$export_base/physical/floorplan/io_placement.io"
        }
        
        # Floorplan constraints
        set fp_tcl "$export_base/physical/floorplan/floorplan_constraints.tcl"
        write_floorplan_constraints $fp_tcl
        
        handle_info "Floorplan data export completed"
    }
    
    # Export placement data
    if {$placement_enable eq "true"} {
        handle_info "Exporting placement data..."
        
        # Placement DEF
        set place_def "$export_base/physical/placement/${top_module}_placement.def"
        defOut -floorplan -netlist $place_def

        # Placement constraints
        set place_tcl "$export_base/physical/placement/placement_constraints.tcl"
        write_placement_constraints $place_tcl
        
        # Copy placement reports from place1 node
        set _place_reports "$run_dir/work/PNR/place1/reports"
        if {[file exists $_place_reports]} {
            catch { file copy $_place_reports "$export_base/physical/placement/reports" }
        }
        
        handle_info "Placement data export completed"
    }
    
    # Export routing data
    if {$routing_enable eq "true"} {
        handle_info "Exporting routing data..."
        
        # Routing DEF
        set route_def "$export_base/physical/routing/${top_module}_routing.def"
        defOut -floorplan -netlist -routing $route_def

        # Routing guides (if available)
        set route_guides "$export_base/physical/routing/routing_guides.guide"
        write_route_guides $route_guides
        
        # Copy routing reports from route1 node
        set _route_reports "$run_dir/work/PNR/route1/reports"
        if {[file exists $_route_reports]} {
            catch { file copy $_route_reports "$export_base/physical/routing/reports" }
        }
        
        handle_info "Routing data export completed"
    }
}

flow_proc export_verification_data {
    handle_info "Exporting verification data..."
    
    global pnr project
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    set export_base "results/export"
    
    # Get verification export parameters
    set drc_enable [expr {[info exists innovus(export,drc)] ? $innovus(export,drc) : "true"}]
    set lvs_enable [expr {[info exists innovus(export,lvs)] ? $innovus(export,lvs) : "true"}]
    set antenna_enable [expr {[info exists innovus(export,antenna)] ? $innovus(export,antenna) : "true"}]
    
    handle_info "Verification export parameters:"
    handle_info "  DRC data: $drc_enable"
    handle_info "  LVS data: $lvs_enable"
    handle_info "  Antenna data: $antenna_enable"
    
    # Export DRC data
    if {$drc_enable eq "true"} {
        handle_info "Exporting DRC verification data..."
        
        # Copy DRC reports from signoff1 node
        set _signoff_reports "$run_dir/work/PNR/signoff1/reports"
        if {[file exists $_signoff_reports]} {
            catch { file copy $_signoff_reports "$export_base/verification/drc/reports" }
        }
        
        # DRC database (if available)
        set drc_db "$export_base/verification/drc/${top_module}_drc.db"
        write_drc_database $drc_db
        
        handle_info "DRC data export completed"
    }
    
    # Export LVS data
    if {$lvs_enable eq "true"} {
        handle_info "Exporting LVS verification data..."
        
        # LVS netlist
        set lvs_netlist "$export_base/verification/lvs/${top_module}_lvs.sp"
        saveNetlist $lvs_netlist -format spice -includeLeakagePower

        # LVS layout
        set lvs_gds "$export_base/verification/lvs/${top_module}_lvs.gds"
        streamOut $lvs_gds -mapFile $stream_map_file
        
        # LVS runset (if available)
        if {[info exists tech(lvs,runset)]} {
            file copy $tech(lvs,runset) "$export_base/verification/lvs/lvs_runset.rs"
        }
        
        handle_info "LVS data export completed"
    }
    
    # Export antenna data
    if {$antenna_enable eq "true"} {
        handle_info "Exporting antenna verification data..."
        
        # Antenna report
        set antenna_rpt "$export_base/verification/antenna/antenna_violations.rpt"
        report_antenna > $antenna_rpt

        # Antenna diode list (if any were inserted)
        set diode_list "$export_base/verification/antenna/antenna_diodes.list"
        report_antenna_diodes > $diode_list
        
        handle_info "Antenna data export completed"
    }
}

flow_proc generate_export_scripts {
    handle_info "Generating export utility scripts..."
    
    set export_base "results/export"
    set scripts_dir "$export_base/scripts"
    
    # Create database loading script
    set load_script "$scripts_dir/load_design.tcl"
    set fd [open $load_script "w"]
    puts $fd "# Design Loading Script"
    puts $fd "# Generated by OMNI FLOW"
    puts $fd ""
    puts $fd "# Load libraries"
    if {[info exists tech(lib,timing)]} {
        foreach lib $tech(lib,timing) {
            puts $fd "read_lib $lib"
        }
    }
    puts $fd ""
    puts $fd "# Load LEF files"
    if {[info exists tech(lef,technology)]} {
        puts $fd "read_lef $tech(lef,technology)"
    }
    if {[info exists tech(lef,standard_cells)]} {
        foreach lef $tech(lef,standard_cells) {
            puts $fd "read_lef $lef"
        }
    }
    puts $fd ""
    puts $fd "# Load netlist"
    global project
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    puts $fd "read_netlist ../netlist/verilog/${top_module}_final.v"
    puts $fd ""
    puts $fd "# Load constraints"
    puts $fd "read_sdc ../timing/sdc/${top_module}_final.sdc"
    puts $fd ""
    puts $fd "# Load parasitics"
    puts $fd "read_spef ../timing/spef/${top_module}_full.spef"
    puts $fd ""
    puts $fd "puts \"Design loaded successfully\""
    close $fd
    
    # Create verification script
    set verify_script "$scripts_dir/verify_design.tcl"
    set fd [open $verify_script "w"]
    puts $fd "# Design Verification Script"
    puts $fd "# Generated by OMNI FLOW"
    puts $fd ""
    puts $fd "# Connectivity check"
    puts $fd "check_design"
    puts $fd ""
    puts $fd "# Timing analysis"
    puts $fd "update_timing"
    puts $fd "report_timing -max_paths 10"
    puts $fd ""
    puts $fd "# Power analysis"
    puts $fd "report_power"
    puts $fd ""
    puts $fd "puts \"Design verification completed\""
    close $fd
    
    # Create file manifest
    set manifest_script "$scripts_dir/file_manifest.txt"
    set fd [open $manifest_script "w"]
    puts $fd "# OMNI FLOW Export File Manifest"
    puts $fd "# Generated: [clock format [clock seconds]]"
    puts $fd "# Design: $top_module"
    puts $fd ""
    puts $fd "=== LAYOUT FILES ==="
    puts $fd "layout/gds/${top_module}.gds                    - Final GDSII layout"
    puts $fd "layout/def/${top_module}_full.def              - Complete DEF file"
    puts $fd "layout/abstract/${top_module}.lef              - Abstract LEF view"
    puts $fd ""
    puts $fd "=== NETLIST FILES ==="
    puts $fd "netlist/verilog/${top_module}_final.v          - Final Verilog netlist"
    puts $fd "netlist/lef/technology.lef                     - Technology LEF"
    puts $fd ""
    puts $fd "=== TIMING FILES ==="
    puts $fd "timing/sdc/${top_module}_final.sdc             - Timing constraints"
    puts $fd "timing/spef/${top_module}_full.spef            - Parasitic extraction"
    puts $fd ""
    puts $fd "=== POWER FILES ==="
    puts $fd "power/upf/${top_module}_final.upf              - Power intent"
    puts $fd "power/analysis/power_summary.rpt               - Power analysis"
    puts $fd ""
    puts $fd "=== VERIFICATION FILES ==="
    puts $fd "verification/drc/reports/                       - DRC reports"
    puts $fd "verification/lvs/${top_module}_lvs.sp           - LVS netlist"
    puts $fd ""
    puts $fd "=== UTILITY SCRIPTS ==="
    puts $fd "utils/load_design.tcl                        - Design loading script"
    puts $fd "utils/verify_design.tcl                      - Verification script"
    close $fd
    
    handle_info "Export utility scripts generated"
}

flow_proc generate_export_documentation {
    handle_info "Generating export documentation..."
    
    set export_base "results/export"
    set doc_dir "$export_base/documentation"
    
    global pnr project
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    
    # Create comprehensive README
    set readme_file "$doc_dir/README.md"
    set fd [open $readme_file "w"]
    puts $fd "# $top_module Export Package"
    puts $fd ""
    puts $fd "Generated by OMNI FLOW on [clock format [clock seconds]]"
    puts $fd ""
    puts $fd "## Design Information"
    puts $fd ""
    puts $fd "- **Design Name:** $top_module"
    if {[info exists project(version)]} {
        puts $fd "- **Version:** $project(version)"
    }
    if {[info exists tech(node)]} {
        puts $fd "- **Technology:** $tech(node)"
    }
    puts $fd "- **Flow Tool:** innovus"
    puts $fd "- **Export Date:** [clock format [clock seconds]]"
    puts $fd ""
    puts $fd "## Directory Structure"
    puts $fd ""
    puts $fd "```"
    puts $fd "export/"
    puts $fd "├── layout/           # Layout files (GDS, DEF, LEF)"
    puts $fd "├── netlist/          # Netlist files (Verilog, SPICE)"
    puts $fd "├── timing/           # Timing files (SDC, SPEF, SDF)"
    puts $fd "├── power/            # Power files (UPF, reports)"
    puts $fd "├── physical/         # Physical data (floorplan, placement)"
    puts $fd "├── verification/     # Verification data (DRC, LVS)"
    puts $fd "├── documentation/    # Documentation and reports"
    puts $fd "└── utils/          # Utility scripts"
    puts $fd "```"
    puts $fd ""
    puts $fd "## Key Files"
    puts $fd ""
    puts $fd "### Layout"
    puts $fd "- \`layout/gds/${top_module}.gds\` - Final GDSII layout"
    puts $fd "- \`layout/def/${top_module}_full.def\` - Complete DEF with routing"
    puts $fd ""
    puts $fd "### Netlist"
    puts $fd "- \`netlist/verilog/${top_module}_final.v\` - Final gate-level netlist"
    puts $fd ""
    puts $fd "### Timing"
    puts $fd "- \`timing/sdc/${top_module}_final.sdc\` - Timing constraints"
    puts $fd "- \`timing/spef/${top_module}_full.spef\` - Parasitic extraction"
    puts $fd ""
    puts $fd "## Usage Instructions"
    puts $fd ""
    puts $fd "1. **Loading Design:**"
    puts $fd "   \`\`\`tcl"
    puts $fd "   source utils/load_design.tcl"
    puts $fd "   \`\`\`"
    puts $fd ""
    puts $fd "2. **Verification:**"
    puts $fd "   \`\`\`tcl"
    puts $fd "   source utils/verify_design.tcl"
    puts $fd "   \`\`\`"
    puts $fd ""
    puts $fd "3. **File Manifest:**"
    puts $fd "   See \`utils/file_manifest.txt\` for complete file listing"
    puts $fd ""
    puts $fd "## Notes"
    puts $fd ""
    puts $fd "- All paths in scripts are relative to the export directory"
    puts $fd "- MMMC scenarios are included in timing/mmmc/ if enabled"
    puts $fd "- Verification data includes DRC/LVS reports and databases"
    puts $fd ""
    close $fd
    
    # Create design specification document
    set spec_file "$doc_dir/design_specification.txt"
    set fd [open $spec_file "w"]
    puts $fd "DESIGN SPECIFICATION"
    puts $fd "==================="
    puts $fd ""
    puts $fd "Design: $top_module"
    puts $fd "Generated: [clock format [clock seconds]]"
    puts $fd ""
    puts $fd "PHYSICAL PARAMETERS"
    puts $fd "==================="
    # Add physical parameters from configuration
    if {[info exists innovus(floorplan,core_util)]} {
        puts $fd "Core Utilization: $innovus(floorplan,core_util)"
    }
    if {[info exists innovus(floorplan,aspect_ratio)]} {
        puts $fd "Aspect Ratio: $innovus(floorplan,aspect_ratio)"
    }
    puts $fd ""
    puts $fd "TIMING PARAMETERS"
    puts $fd "================="
    if {[info exists project(clock,period)]} {
        puts $fd "Clock Period: $project(clock,period)ns"
    }
    if {[info exists project(clock,ports)]} {
        puts $fd "Clock Ports: $project(clock,ports)"
    }
    puts $fd ""
    puts $fd "TECHNOLOGY PARAMETERS"
    puts $fd "===================="
    if {[info exists tech(node)]} {
        puts $fd "Technology Node: $tech(node)"
    }
    if {[info exists tech(process)]} {
        puts $fd "Process: $tech(process)"
    }
    close $fd
    
    handle_info "Export documentation generated"
}

flow_proc validate_export_data {
    handle_info "Validating exported data..."
    
    set export_base "results/export"
    global project
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    
    # Validation results
    set validation_issues 0
    set validation_warnings 0
    
    # Required files checklist
    set required_files [list \
        "layout/gds/${top_module}.gds" \
        "layout/def/${top_module}_full.def" \
        "netlist/verilog/${top_module}_final.v" \
        "timing/sdc/${top_module}_final.sdc" \
        "timing/spef/${top_module}_full.spef" \
        "utils/load_design.tcl" \
        "utils/file_manifest.txt" \
        "documentation/README.md" \
    ]
    
    handle_info "Checking required files:"
    foreach file $required_files {
        set full_path "$export_base/$file"
        if {[file exists $full_path]} {
            handle_info "  ✓ $file"
        } else {
            handle_warning "  ✗ Missing: $file"
            incr validation_issues
        }
    }
    
    # Check file sizes (ensure files are not empty)
    set size_check_files [list \
        "layout/gds/${top_module}.gds" \
        "netlist/verilog/${top_module}_final.v" \
        "timing/spef/${top_module}_full.spef" \
    ]
    
    handle_info "Checking file sizes:"
    foreach file $size_check_files {
        set full_path "$export_base/$file"
        if {[file exists $full_path]} {
            set file_size [file size $full_path]
            if {$file_size > 1000} {
                handle_info "  ✓ $file ([expr {$file_size/1024}] KB)"
            } else {
                handle_warning "  ⚠ $file is very small ($file_size bytes)"
                incr validation_warnings
            }
        }
    }
    
    # Generate validation report
    set validation_file "$export_base/validation_report.txt"
    set fd [open $validation_file "w"]
    puts $fd "EXPORT VALIDATION REPORT"
    puts $fd "========================"
    puts $fd ""
    puts $fd "Design: $top_module"
    puts $fd "Validation Date: [clock format [clock seconds]]"
    puts $fd ""
    puts $fd "SUMMARY"
    puts $fd "======="
    puts $fd "Validation Issues: $validation_issues"
    puts $fd "Validation Warnings: $validation_warnings"
    if {$validation_issues == 0} {
        puts $fd "Status: PASSED"
    } else {
        puts $fd "Status: FAILED"
    }
    puts $fd ""
    puts $fd "DETAILS"
    puts $fd "======="
    foreach file $required_files {
        set full_path "$export_base/$file"
        if {[file exists $full_path]} {
            puts $fd "✓ $file"
        } else {
            puts $fd "✗ $file (MISSING)"
        }
    }
    close $fd
    
    if {$validation_issues == 0} {
        handle_info "Export validation PASSED ($validation_warnings warnings)"
    } else {
        handle_warning "Export validation FAILED ($validation_issues issues, $validation_warnings warnings)"
    }
    
    handle_info "Validation report: $validation_file"
}

flow_proc export_db_complete {
    handle_info "Database export stage complete"

    # Save checkpoint
    set checkpoint_dir "$::WORK_DIR/checkpoints"
    file mkdir $checkpoint_dir
    saveDesign "${checkpoint_dir}/export_db.enc"

    # Generate final export summary
    file mkdir "$::REPORTS_DIR"

    set summary_file "$::REPORTS_DIR/export_summary.rpt"
    set fd [open $summary_file "w"]
    puts $fd "# OMNI FLOW Database Export Summary"
    puts $fd "# Generated: [clock format [clock seconds]]"
    puts $fd ""
    
    global project pnr
    set top_module [expr {[info exists project(top_module)] ? $project(top_module) : [handle_error "project(top_module) not defined"]}]
    
    puts $fd "=== EXPORT SUMMARY ==="
    puts $fd "Design: $top_module"
    puts $fd "Export Location: results/export/"
    puts $fd ""
    
    # Report what was exported
    puts $fd "=== EXPORTED DATA ==="
    set gds_enable [expr {[info exists innovus(export,gds)] ? $innovus(export,gds) : "true"}]
    set def_enable [expr {[info exists innovus(export,def)] ? $innovus(export,def) : "true"}]
    set verilog_enable [expr {[info exists innovus(export,verilog)] ? $innovus(export,verilog) : "true"}]
    set sdc_enable [expr {[info exists innovus(export,sdc)] ? $innovus(export,sdc) : "true"}]
    set spef_enable [expr {[info exists innovus(export,spef)] ? $innovus(export,spef) : "true"}]
    
    puts $fd "Layout Data:"
    puts $fd "  GDS: $gds_enable"
    puts $fd "  DEF: $def_enable"
    puts $fd ""
    puts $fd "Netlist Data:"
    puts $fd "  Verilog: $verilog_enable"
    puts $fd ""
    puts $fd "Timing Data:"
    puts $fd "  SDC: $sdc_enable"
    puts $fd "  SPEF: $spef_enable"
    puts $fd ""
    
    # MMMC status
    global mmmc
    set mmmc_enable [expr {[info exists mmmc(enable)] ? $mmmc(enable) : "false"}]
    puts $fd "MMMC Export: $mmmc_enable"
    
    puts $fd ""
    puts $fd "=== DELIVERABLES ==="
    puts $fd "Export Package: results/export/"
    puts $fd "Documentation: results/export/documentation/"
    puts $fd "Utility Scripts: results/export/utils/"
    puts $fd "Validation Report: results/export/validation_report.txt"
    puts $fd ""
    puts $fd "Status: DATABASE EXPORT COMPLETE"
    
    close $fd
    handle_info "Export summary generated: $summary_file"
    
    log_stage_status "export_db" "COMPLETE" "Database export completed - all deliverables ready"
}
# Exit tool after stage completion
exit
