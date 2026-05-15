#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - EMIR Power/Rail Analysis Command File
# Description: IR-drop, EM, and effective resistance analysis using RedHawk in-design
# Tool: Synopsys RedHawk (in-design within Fusion Compiler)
# Based on: FC-RM Y-2026.03 redhawk_in_design_pnr.tcl
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/EMIR/power_analysis/run/config.tcl"
if {[file exists $config_file]} { source $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
global emir project tech flow
# Source REDHAWK tool config
set _tool_config "[file dirname [info script]]/redhawk_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting EMIR power/rail analysis with Synopsys RedHawk in-design..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/EMIR/power_analysis"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# ==============================================================================
# flow_proc: configure_redhawk
# Description: Set app_options for RedHawk binary, tech files, layer maps, lib files
# FC-RM: rail.enable_redhawk, rail.redhawk_path, rail.layer_map_file,
#         rail.tech_file, rail.em_only_tech_file, rail.lib_files, rail.apl_files
# ==============================================================================
flow_proc configure_redhawk {
    global emir project tech
    handle_info "Configuring RedHawk in-design environment..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$::REPORTS_DIR"
    file mkdir "$::OUTPUTS_DIR/emir"

    # Enable RedHawk
    set_app_options -name rail.enable_redhawk -value true

    # ── RedHawk binary path ──
    if {[info exists emir(tool,redhawk_path)] && $emir(tool,redhawk_path) ne ""} {
        handle_info "Setting RedHawk path: $emir(tool,redhawk_path)"
        set_app_options -name rail.redhawk_path -value $emir(tool,redhawk_path)
    } elseif {![catch {set rh_dir [file dirname [exec which redhawk]]}]} {
        handle_info "Auto-detected RedHawk path: $rh_dir"
        set_app_options -name rail.redhawk_path -value $rh_dir
    } else {
        handle_error "Unable to find RedHawk binary. Set emir(tool,redhawk_path)."
    }

    # ── Host / grid options ──
    if {[info exists emir(tool,grid_farm)] && $emir(tool,grid_farm) ne ""} {
        handle_info "Submitting RedHawk jobs to grid: $emir(tool,grid_farm)"
        set_host_options -submit_command $emir(tool,grid_farm)
    } else {
        handle_info "Running RedHawk on local machine"
        remove_host_options -all
        set max_cores 8
        if {[info exists emir(tool,max_cores)] && $emir(tool,max_cores) ne ""} {
            set max_cores $emir(tool,max_cores)
        }
        set_host_options -submit_command {local} -max_cores $max_cores
    }

    # ── Layer map file ──
    if {[info exists emir(input,layer_map_file)] && [file exists [which $emir(input,layer_map_file)]]} {
        handle_info "Setting layer map file: $emir(input,layer_map_file)"
        set_app_options -name rail.layer_map_file -value $emir(input,layer_map_file)
    }

    # ── RedHawk tech file ──
    if {[info exists emir(input,tech_file)] && $emir(input,tech_file) ne ""} {
        if {[which $emir(input,tech_file)] ne ""} {
            handle_info "Setting RedHawk tech file: $emir(input,tech_file)"
            set_app_options -name rail.tech_file -value $emir(input,tech_file)
        } else {
            handle_error "RedHawk tech file not found: $emir(input,tech_file)"
        }
    }

    # ── EM tech file (for electromigration analysis) ──
    if {[info exists redhawk(em,enable)] && $redhawk(em,enable)} {
        if {[info exists emir(input,em_tech_file)] && [file exists [which $emir(input,em_tech_file)]]} {
            handle_info "Setting EM tech file: $emir(input,em_tech_file)"
            set_app_options -name rail.em_only_tech_file -value $emir(input,em_tech_file)
        } elseif {[info exists emir(input,em_tech_file)] && $emir(input,em_tech_file) ne ""} {
            handle_error "EM tech file not found: $emir(input,em_tech_file)"
        }
    }

    # ── Lib files ──
    if {[info exists emir(input,lib_files)] && $emir(input,lib_files) ne ""} {
        set lib_files ""
        foreach fl $emir(input,lib_files) {
            set lib_files "$lib_files \n$fl"
        }
        handle_info "Setting rail.lib_files"
        set_app_options -name rail.lib_files -value $lib_files
    }

    # ── APL files (for dynamic analysis) ──
    if {[info exists emir(input,apl_files)] && $emir(input,apl_files) ne ""} {
        handle_info "Setting APL files for dynamic analysis"
        set_app_options -name rail.apl_files -value $emir(input,apl_files)
    }

    # ── Extra GSR option file ──
    if {[info exists emir(input,extra_gsr)] && $emir(input,extra_gsr) ne ""} {
        handle_info "Setting extra GSR: $emir(input,extra_gsr)"
        set_app_options -name rail.extra_gsr_option_file -value $emir(input,extra_gsr)
        set ::emir_extra_gsr $emir(input,extra_gsr)
    } else {
        exec touch extra.gsr
        set ::emir_extra_gsr "extra.gsr"
    }

    # ── Rail database name ──
    if {[info exists emir(input,rail_database)] && $emir(input,rail_database) ne ""} {
        set_app_options -name rail.database -value $emir(input,rail_database)
    }

    # ── Missing via threshold ──
    set_missing_via_check_options -exclude_stack_via -threshold -1
    if {[info exists redhawk(ir_drop,missing_via_threshold)] && $redhawk(ir_drop,missing_via_threshold) ne ""} {
        set_missing_via_check_options -exclude_stack_via -threshold $redhawk(ir_drop,missing_via_threshold)
    }

    # ── Switch model files ──
    if {[info exists emir(input,switch_model_files)] && $emir(input,switch_model_files) ne ""} {
        set_app_options -name rail.switch_model_files -value $emir(input,switch_model_files)
    }

    handle_info "RedHawk configuration completed"
}

# ==============================================================================
# flow_proc: setup_taps
# Description: Create pad taps for RedHawk analysis
# FC-RM: create_taps -import / -top_pg / pad_files
# ==============================================================================
flow_proc setup_taps {
    global emir project tech
    handle_info "Setting up power taps..."

    if {[info exists emir(input,pad_file_ndm)] && [file exists [which $emir(input,pad_file_ndm)]]} {
        handle_info "Importing taps from NDM pad file: $emir(input,pad_file_ndm)"
        create_taps -import $emir(input,pad_file_ndm)
    } elseif {[info exists emir(input,pad_file_ploc)] && [file exists [which $emir(input,pad_file_ploc)]]} {
        handle_info "Setting pad file (ploc): $emir(input,pad_file_ploc)"
        set_app_options -name rail.pad_files -value $emir(input,pad_file_ploc)
    } else {
        handle_info "Creating taps from top-level PG pins"
        create_taps -top_pg
    }

    handle_info "Tap setup completed"
}

# ==============================================================================
# flow_proc: configure_analysis
# Description: Set frequency, temperature, scenario, macro models
# FC-RM: rail.frequency, rail.temperature, rail.scenario_name, rail.macro_models
# ==============================================================================
flow_proc configure_analysis {
    global emir project tech
    handle_info "Configuring rail analysis parameters..."

    # ── Frequency ──
    if {[info exists redhawk(power,frequency)] && $redhawk(power,frequency) ne ""} {
        handle_info "Setting frequency: $redhawk(power,frequency)"
        set_app_options -name rail.frequency -value $redhawk(power,frequency)
    }

    # ── Temperature ──
    if {[info exists redhawk(thermal,temperature)] && $redhawk(thermal,temperature) ne ""} {
        handle_info "Setting temperature: $redhawk(thermal,temperature)"
        set_app_options -name rail.temperature -value $redhawk(thermal,temperature)
    }

    # ── Scenario ──
    if {[info exists redhawk(power,scenario)] && $redhawk(power,scenario) ne ""} {
        handle_info "Setting rail scenario: $redhawk(power,scenario)"
        set_scenario_status $redhawk(power,scenario) -active true -setup true
        set_app_options -name rail.scenario_name -value $redhawk(power,scenario)
    } else {
        set current_scn [get_object_name [get_scenario [current_scenario]]]
        handle_info "Using current scenario: $current_scn"
        set_app_options -name rail.scenario_name -value $current_scn
    }

    # ── Macro models ──
    if {[info exists emir(input,macro_models)] && $emir(input,macro_models) ne ""} {
        handle_info "Setting macro models"
        set_app_options -name rail.macro_models -value $emir(input,macro_models)
    }

    # ── Switching activity file ──
    if {[info exists redhawk(power,switching_activity_file)] && $redhawk(power,switching_activity_file) ne ""} {
        set ::emir_saif $redhawk(power,switching_activity_file)
    } else {
        set ::emir_saif ""
    }

    # ── Use FC power ──
    if {[info exists redhawk(power,use_fc_power)] && $redhawk(power,use_fc_power)} {
        set ::emir_use_fc_power 1
    } else {
        set ::emir_use_fc_power 0
    }

    handle_info "Rail analysis parameters configured"
}

# ==============================================================================
# flow_proc: run_rail_analysis
# Description: Run analyze_rail for voltage_drop, EM, effective_resistance, etc.
# FC-RM: analyze_rail with -voltage_drop / -electromigration / -effective_resistance /
#         -min_path_resistance / -check_missing_via
# ==============================================================================
flow_proc run_rail_analysis {
    global emir project tech
    handle_info "Running rail analysis..."

    set run_dir $::env(CBFLOW_RUN_DIR)

    # Determine analysis mode
    set analysis_mode "static"
    if {[info exists redhawk(power,analysis_mode)] && $redhawk(power,analysis_mode) ne ""} {
        set analysis_mode $redhawk(power,analysis_mode)
    }

    # Determine analysis nets
    set analysis_nets ""
    if {[info exists redhawk(power,analysis_nets)] && $redhawk(power,analysis_nets) ne ""} {
        set analysis_nets $redhawk(power,analysis_nets)
    }

    # EM analysis flag
    set em_analysis 0
    if {[info exists redhawk(em,enable)] && $redhawk(em,enable)} {
        set em_analysis 1
    }

    set extra_gsr $::emir_extra_gsr

    # ── Change abstract blocks to design view for analysis ──
    set block_refs [filter_collection [get_designs -filter "view_name==abstract"] "name!=$project(top_module)"]
    set ::emir_block_ref_list [list]
    if {[sizeof_collection $block_refs] > 0} {
        foreach_in_collection block $block_refs {
            lappend ::emir_block_ref_list [get_object_name $block]
        }
        change_abstract -view design -references $::emir_block_ref_list
    }

    # ── Build and run analyze_rail command ──
    if {$analysis_mode eq "static" || $analysis_mode eq "dynamic_vcd" || $analysis_mode eq "dynamic_vectorless" || $analysis_mode eq "dynamic"} {
        set rail_cmd "analyze_rail -nets $analysis_nets -voltage_drop $analysis_mode"
        if {$em_analysis} {
            lappend rail_cmd -electromigration
        }
        lappend rail_cmd -extra_gsr_option $extra_gsr
        if {$::emir_use_fc_power} {
            lappend rail_cmd -power_analysis icc2
        }
        if {$::emir_saif ne ""} {
            lappend rail_cmd -switching_activity $::emir_saif
        }
    } elseif {$analysis_mode eq "effective_resistance"} {
        set rail_cmd "analyze_rail -nets $analysis_nets -effective_resistance -extra_gsr_option $extra_gsr"
    } elseif {$analysis_mode eq "min_path_resistance"} {
        set rail_cmd "analyze_rail -nets $analysis_nets -min_path_resistance -extra_gsr_option $extra_gsr"
    } elseif {$analysis_mode eq "check_missing_via"} {
        set rail_cmd "analyze_rail -nets $analysis_nets -check_missing_via -extra_gsr_option $extra_gsr"
        if {[info exists redhawk(ir_drop,missing_via_threshold)] && $redhawk(ir_drop,missing_via_threshold) ne ""} {
            set rail_cmd "analyze_rail -nets $analysis_nets -voltage_drop static -check_missing_via -extra_gsr_option $extra_gsr"
        }
    } else {
        handle_error "Unknown analysis mode: $analysis_mode. Use static/dynamic/effective_resistance/min_path_resistance/check_missing_via."
        return
    }

    handle_info "Running: $rail_cmd"
    eval $rail_cmd

    # ── Restore abstract views ──
    if {[llength $::emir_block_ref_list] > 0} {
        change_abstract -view abstract -references $::emir_block_ref_list
    }

    handle_info "Rail analysis completed"
}

# ==============================================================================
# flow_proc: fix_missing_vias
# Description: Fix PG missing vias from DRC error data
# FC-RM: fix_pg_missing_vias from DRC error data
# ==============================================================================
flow_proc fix_missing_vias {
    global emir project tech
    handle_info "Checking for missing via fixes..."

    set fix_vias 0
    if {[info exists redhawk(ir_drop,fix_missing_vias)] && $redhawk(ir_drop,fix_missing_vias)} {
        set fix_vias 1
    }

    if {!$fix_vias} {
        handle_info "Missing via fix not enabled -- skipping"
        return
    }

    handle_info "Fixing PG missing vias from DRC error data"
    foreach_in_collection err_file [get_drc_error_data -all *miss_via*] {
        set errdm [open_drc_error_data $err_file]
        set errs [get_drc_errors -error_data $errdm]
        fix_pg_missing_vias -error_data $errdm $errs
    }

    handle_info "Missing via fix completed"
}

# ==============================================================================
# flow_proc: generate_reports
# Description: Report rail results for voltage, EM, resistance, missing vias
# FC-RM: report_rail_result -type effective_voltage / minimum_path_resistance /
#         effective_resistance / missing_vias
# ==============================================================================
flow_proc generate_reports {
    global emir project tech
    handle_info "Generating EMIR reports..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set rpt_dir "$::REPORTS_DIR"
    set res_dir "$::OUTPUTS_DIR/emir"

    file mkdir $rpt_dir
    file mkdir $res_dir

    set analysis_mode "static"
    if {[info exists redhawk(power,analysis_mode)] && $redhawk(power,analysis_mode) ne ""} {
        set analysis_mode $redhawk(power,analysis_mode)
    }
    set analysis_nets ""
    if {[info exists redhawk(power,analysis_nets)] && $redhawk(power,analysis_nets) ne ""} {
        set analysis_nets $redhawk(power,analysis_nets)
    }

    set output_report ""
    if {[info exists redhawk(output,report_file)] && $redhawk(output,report_file) ne ""} {
        set output_report $redhawk(output,report_file)
    }

    # ── Voltage drop report ──
    if {$analysis_mode eq "static" || $analysis_mode eq "dynamic_vcd" || $analysis_mode eq "dynamic_vectorless" || $analysis_mode eq "dynamic"} {
        handle_info "Generating effective voltage report"
        report_rail_result -type effective_voltage -supply_nets $analysis_nets $output_report
    }

    # ── EM report ──
    if {[info exists redhawk(em,enable)] && $redhawk(em,enable)} {
        if {[info exists redhawk(output,em_report)] && $redhawk(output,em_report) ne ""} {
            handle_info "Generating EM report: $redhawk(output,em_report)"
            set fd [open $redhawk(output,em_report) w]
            foreach_in_collection em_err_file [get_drc_error_data -all *em*] {
                set dm [open_drc_error_data $em_err_file]
                set all_errs [get_drc_errors -error_data $dm *]
                foreach_in_collection err $all_errs {
                    set info [get_attribute $err error_info]
                    puts $fd $info
                }
            }
            close $fd
        }
    }

    # ── Min path resistance report ──
    if {$analysis_mode eq "min_path_resistance"} {
        handle_info "Generating minimum path resistance report"
        report_rail_result -type minimum_path_resistance -supply_nets $analysis_nets $output_report
    }

    # ── Effective resistance report ──
    if {$analysis_mode eq "effective_resistance"} {
        handle_info "Generating effective resistance report"
        report_rail_result -type effective_resistance -supply_nets $analysis_nets $output_report
    }

    # ── Missing vias report ──
    if {$analysis_mode eq "check_missing_via"} {
        handle_info "Generating missing vias report"
        report_rail_result -type missing_vias -supply_nets $analysis_nets $output_report
    }

    # ── Summary results file ──
    set rpt "${res_dir}/power_analysis.rpt"
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow EMIR - Rail Analysis Results (Synopsys RedHawk in-design)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design:     $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool:       Synopsys RedHawk (in-design)"
    puts $fp ""
    puts $fp "Analysis Mode: $analysis_mode"
    puts $fp "Analysis Nets: $analysis_nets"
    if {[info exists redhawk(ir_drop,threshold)] && $redhawk(ir_drop,threshold) ne ""} {
        puts $fp "IR-Drop Threshold: $redhawk(ir_drop,threshold)"
    }
    if {[info exists redhawk(thermal,enable)] && $redhawk(thermal,enable)} {
        puts $fp "Thermal Analysis: enabled"
    }
    puts $fp ""
    puts $fp "Detailed Reports: $rpt_dir/"
    close $fp

    handle_info "EMIR reports generated in $rpt_dir"
}

# ==============================================================================
# flow_proc: save_design_block
# Description: Save block and library after analysis
# FC-RM: save_block, save_lib
# ==============================================================================
flow_proc save_design_block {
    global emir project tech
    handle_info "Saving design block..."

    save_block
    save_lib

    handle_info "Design block saved"
}

# ==============================================================================
# Top-level flow execution
# ==============================================================================
flow_exec_all configure_redhawk setup_taps configure_analysis run_rail_analysis fix_missing_vias generate_reports save_design_block

# Exit tool after stage completion
exit
