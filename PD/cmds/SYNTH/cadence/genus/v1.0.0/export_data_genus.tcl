#!/usr/bin/env tclsh
# SYNTH export_data - Cadence Genus

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "export_data"
set NODE_NAME "export_data1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

handle_info "Starting SYNTH export_data with Cadence Genus..."
# ── Directories ──────────────────────────────────────────────────────────────

flow_proc export_data_database {
    puts "INFO: Exporting synthesis database..."
    
    # Export database for PNR tools
    file mkdir "$::OUTPUTS_DIR/db"
    write_db -to_file "$::OUTPUTS_DIR/db/synth.db"
    puts "INFO: Exported database: $::OUTPUTS_DIR/db/synth.db"

    # Export session for incremental runs
    write_snapshot -outdir "$::OUTPUTS_DIR/db/synth_snapshot"
    puts "INFO: Exported snapshot: $::OUTPUTS_DIR/db/synth_snapshot"
}

# Export liberty libraries
flow_proc export_data_libraries {
    puts "INFO: Exporting timing libraries..."
    
    # Export characterized libraries
    file mkdir "$::OUTPUTS_DIR/lib"
    write_lib -lib_cell_view [get_lib_cells] "$::OUTPUTS_DIR/lib/synth.lib"
    puts "INFO: Exported library: $::OUTPUTS_DIR/lib/synth.lib"

    # Export NLDM libraries for timing analysis
    write_lib -nldm "$::OUTPUTS_DIR/lib/synth_nldm.lib"
    puts "INFO: Exported NLDM library: $::OUTPUTS_DIR/lib/synth_nldm.lib"
}

# Export design constraints
flow_proc export_data_constraints {
    puts "INFO: Exporting design constraints..."
    
    # Export updated SDC for PNR
    file mkdir "$::OUTPUTS_DIR/sdc"
    write_sdc "$::OUTPUTS_DIR/sdc/synth_export.sdc"
    puts "INFO: Exported SDC: $::OUTPUTS_DIR/sdc/synth_export.sdc"

    # Export UPF for power analysis
    if {[get_power_domain -quiet] != ""} {
        file mkdir "$::OUTPUTS_DIR/upf"
        write_upf "$::OUTPUTS_DIR/upf/synth_export.upf"
        puts "INFO: Exported UPF: $::OUTPUTS_DIR/upf/synth_export.upf"
    }
}

# Export design data
flow_proc export_data_design {
    puts "INFO: Exporting design netlist and data..."
    
    # Export final netlist
    file mkdir "$::OUTPUTS_DIR/netlist"
    write_hdl -mapped "$::OUTPUTS_DIR/netlist/synth_export.v"
    puts "INFO: Exported netlist: $::OUTPUTS_DIR/netlist/synth_export.v"

    # Export design exchange format
    file mkdir "$::OUTPUTS_DIR/def"
    write_def "$::OUTPUTS_DIR/def/synth_export.def"
    puts "INFO: Exported DEF: $::OUTPUTS_DIR/def/synth_export.def"
}

# Export characterization data
flow_proc export_data_characterization {
    puts "INFO: Exporting characterization data..."
    
    # Export timing models
    file mkdir "$::OUTPUTS_DIR/tlf"
    write_tlf "$::OUTPUTS_DIR/tlf/synth.tlf"
    puts "INFO: Exported TLF: $::OUTPUTS_DIR/tlf/synth.tlf"

    # Export delay calculation models
    file mkdir "$::OUTPUTS_DIR/sdf"
    write_sdf "$::OUTPUTS_DIR/sdf/synth.sdf"
    puts "INFO: Exported SDF: $::OUTPUTS_DIR/sdf/synth.sdf"
}

# Export verification data
flow_proc export_data_verification {
    puts "INFO: Exporting verification data..."
    
    # Export for LEC verification
    file mkdir "$::OUTPUTS_DIR/lec"
    write_hdl -lec "$::OUTPUTS_DIR/lec/synth_lec.v"
    puts "INFO: Exported LEC netlist: $::OUTPUTS_DIR/lec/synth_lec.v"

    # Export formal verification scripts
    write_lec_script "$::OUTPUTS_DIR/lec/synth_lec.tcl"
    puts "INFO: Exported LEC script: $::OUTPUTS_DIR/lec/synth_lec.tcl"
}

# Export reports and documentation
flow_proc export_data_reports {
    puts "INFO: Exporting final reports..."
    
    # Export comprehensive QoR report
    report_qor -file "$::REPORTS_DIR/export_qor.rpt"
    puts "INFO: Exported QoR report: $::REPORTS_DIR/export_qor.rpt"

    # Export area breakdown
    report_area -hierarchy -file "$::REPORTS_DIR/export_area.rpt"
    puts "INFO: Exported area report: $::REPORTS_DIR/export_area.rpt"

    # Export timing summary
    report_timing -max_paths 100 -file "$::REPORTS_DIR/export_timing.rpt"
    puts "INFO: Exported timing report: $::REPORTS_DIR/export_timing.rpt"

    # Export power analysis
    report_power -file "$::REPORTS_DIR/export_power.rpt"
    puts "INFO: Exported power report: $::REPORTS_DIR/export_power.rpt"
}

# Export metadata and configuration
flow_proc export_data_metadata {
    puts "INFO: Exporting metadata and configuration..."
    
    # Export synthesis configuration
    file mkdir "$::OUTPUTS_DIR/config"
    set config_file "$::OUTPUTS_DIR/config/synth_export.tcl"
    set fp [open $config_file w]
    puts $fp "# Synthesis Export Metadata"
    puts $fp "# Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "set synth(export,version) \"[get_version]\""
    puts $fp "set synth(export,design) \"[get_top_module]\""
    puts $fp "set synth(export,cells) [llength [get_cells -hier]]"
    puts $fp "set synth(export,nets) [llength [get_nets -hier]]"
    close $fp
    puts "INFO: Exported metadata: $config_file"
}

# Validate exported files
flow_proc export_data_validate {
    puts "INFO: Validating exported files..."
    
    set required_files [list \
        "$::OUTPUTS_DIR/db/synth.db" \
        "$::OUTPUTS_DIR/lib/synth.lib" \
        "$::OUTPUTS_DIR/netlist/synth_export.v" \
        "$::OUTPUTS_DIR/sdc/synth_export.sdc" \
    ]
    
    set missing_files {}
    foreach file $required_files {
        if {![file exists $file] || [file size $file] == 0} {
            lappend missing_files $file
        }
    }
    
    if {$missing_files != ""} {
        puts "ERROR: Missing or empty export files:"
        foreach file $missing_files {
            puts "  - $file"
        }
        return false
    }
    
    puts "INFO: All required export files validated successfully"
    return true
}

# Cleanup and finalize
flow_proc export_data_cleanup {
    puts "INFO: Cleaning up export process..."
    
    # Remove temporary files
    file delete -force temp_export
    
    # Create export summary
    set summary_file "$::OUTPUTS_DIR/EXPORT_SUMMARY.txt"
    set fp [open $summary_file w]
    puts $fp "SYNTHESIS EXPORT SUMMARY"
    puts $fp "========================"
    puts $fp "Export Date: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    puts $fp "Design: [get_top_module]"
    puts $fp "Tool Version: [get_version]"
    puts $fp ""
    puts $fp "Exported Files:"
    foreach pattern [list "$::OUTPUTS_DIR/db/*" "$::OUTPUTS_DIR/lib/*" "$::OUTPUTS_DIR/netlist/*" "$::OUTPUTS_DIR/sdc/*"] {
        foreach file [glob -nocomplain $pattern] {
            puts $fp "  - $file ([file size $file] bytes)"
        }
    }
    close $fp
    puts "INFO: Export summary: $summary_file"
}

puts "INFO: SYNTH export_data stage loaded"
# Exit tool after stage completion

flow_exec_all
exit
