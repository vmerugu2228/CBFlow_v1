#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FCFP Export Data Command File (Innovus)
# Description: Export DEF, save design database, export reports, and validate
#              exported data for downstream flows
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
set STAGE_NAME "export_data"
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

handle_info "Starting FCFP export_data stage with Innovus..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     EXPORT DEF                                             │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc export_def {
    global fcfp project tech flow
    handle_info "Exporting DEF file..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    file mkdir "$run_dir/results/fcfp/def"

    # DEF filename = project(top_module) (no fallback)
    set def_name [cbflow_require project top_module]

    set def_file "$run_dir/results/fcfp/def/${def_name}.def"

    # Export DEF with all physical data
    defOut $def_file \
        -floorplan \
        -routing

    handle_info "  DEF exported: $def_file"

    # Export floorplan-only DEF if configured
    if {[info exists fcfp(export,floorplan_only_def)] && $fcfp(export,floorplan_only_def) eq "true"} {
        set fp_def "$run_dir/results/fcfp/def/${def_name}_floorplan.def"
        defOut $fp_def -floorplan
        handle_info "  Floorplan DEF: $fp_def"
    }

    puts " DEF export completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     EXPORT DESIGN DATABASE                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc export_design {
    global fcfp project tech flow
    handle_info "Saving design database..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    file mkdir "$run_dir/results/fcfp/db"

    # Design name = project(top_module) (no fallback)
    set design_name [cbflow_require project top_module]

    # Save Innovus design database
    set db_path "$run_dir/results/fcfp/db/${design_name}.enc"
    saveDesign $db_path
    handle_info "  Design database: $db_path"

    # Save netlist
    if {![info exists fcfp(export,skip_netlist)] || $fcfp(export,skip_netlist) ne "true"} {
        file mkdir "$run_dir/results/fcfp/netlist"
        set netlist_file "$run_dir/results/fcfp/netlist/${design_name}.v"
        saveNetlist $netlist_file
        handle_info "  Netlist: $netlist_file"
    }

    # Save SDC constraints
    if {![info exists fcfp(export,skip_sdc)] || $fcfp(export,skip_sdc) ne "true"} {
        file mkdir "$run_dir/results/fcfp/sdc"
        set sdc_file "$run_dir/results/fcfp/sdc/${design_name}.sdc"
        write_sdc $sdc_file
        handle_info "  SDC: $sdc_file"
    }

    puts " Design database export completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     EXPORT REPORTS                                         │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc export_reports {
    global fcfp project tech flow
    handle_info "Collecting and exporting reports..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    file mkdir "$run_dir/results/fcfp/reports"

    # Copy all floorplan-related reports — from the producing nodes'
    # work/FCFP/<node>/reports (node graph: FCFP node_types)
    foreach {rpt_dir node_type} {floorplan fc_floorplan powerplan fc_powerplan post_floorplan fc_post_floorplan} {
        set src_dir "[cbflow_node_dir [cbflow_dep_node $node_type]]/reports"
        set dest_dir "$run_dir/results/fcfp/reports/$rpt_dir"
        if {[file isdirectory $src_dir]} {
            file mkdir $dest_dir
            foreach rpt [glob -nocomplain "$src_dir/*.rpt"] {
                file copy -force $rpt "$dest_dir/[file tail $rpt]"
            }
            handle_info "  Exported $rpt_dir reports"
        }
    }

    puts " Report export completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                     VALIDATE EXPORT                                        │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate {
    global fcfp project tech flow FLOW_DIR
    handle_info "Validating exported data..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors 0

    # Check DEF file exists
    set def_files [glob -nocomplain "$run_dir/results/fcfp/def/*.def"]
    if {[llength $def_files] > 0} {
        foreach def $def_files {
            set fsize [file size $def]
            puts "  DEF: [file tail $def] ($fsize bytes)"
            if {$fsize < 100} {
                handle_warning "DEF file appears too small: [file tail $def]"
                incr errors
            }
        }
    } else {
        handle_warning "No DEF files found in results"
        incr errors
    }

    # Check design database
    set db_files [glob -nocomplain "$run_dir/results/fcfp/db/*"]
    if {[llength $db_files] > 0} {
        puts "  Database files: [llength $db_files]"
    } else {
        handle_warning "No database files found in results"
        incr errors
    }

    # Generate export summary
    set summary_file "$run_dir/results/fcfp/export_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "CBFlow FCFP Export Summary - Innovus"
    puts $fp "═══════════════════════════════════════════════════════════════"
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    puts $fp ""
    puts $fp "Exported Files:"
    puts $fp "  DEF files:      [llength $def_files]"
    puts $fp "  Database files: [llength $db_files]"
    puts $fp "  Netlist:        [llength [glob -nocomplain "$run_dir/results/fcfp/netlist/*"]]"
    puts $fp "  SDC:            [llength [glob -nocomplain "$run_dir/results/fcfp/sdc/*"]]"
    puts $fp ""
    if {$errors > 0} {
        puts $fp "WARNINGS: $errors export issues detected"
    } else {
        puts $fp "STATUS: All exports validated successfully"
    }
    close $fp

    # Run enhanced validation if available
    set validation_flow_dir [expr {[info exists FLOW_DIR] ? $FLOW_DIR : $::env(FLOW_DIR)}]
    set enhanced_validation_script "$validation_flow_dir/utils/validation/[cbflow_version VALIDATION_VERSION]/enhanced_validate_run.tcl"
    if {[file exists $enhanced_validation_script]} {
        if {[catch {exec tclsh $enhanced_validation_script FCFP export_data $run_dir $validation_flow_dir} result]} {
            handle_warning "Validation completed with warnings: $result"
        } else {
            handle_info "Enhanced validation passed"
        }
    }

    handle_info "  Summary: $summary_file"
    puts " Export validation completed ($errors warnings)"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════"
handle_info " CBFlow FCFP export_data with Innovus"
handle_info "═══════════════════════════════════════════════════════════════"

flow_proc export_data_flow {
    handle_info "Executing FCFP export_data flow..."
    flow_exec export_def
    flow_exec export_design
    flow_exec export_reports
    flow_exec validate
    handle_info "FCFP export_data completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} { flow_exec export_data_flow } else { puts " FCFP export_data procedures loaded" }

# Exit tool after stage completion
exit
