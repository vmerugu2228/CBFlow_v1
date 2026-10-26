#!/usr/bin/env tclsh
# CBFlow EMIR power/rail analysis - Synopsys RedHawk (FC-RM Y-2026.03)

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "EMIR"
set STAGE_NAME "power_analysis"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

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
    if {[info exists emir(em,enable)] && $emir(em,enable) ne "" && [string is true -strict $emir(em,enable)]} {
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
    if {[info exists emir(ir_drop,missing_via_threshold)] && $emir(ir_drop,missing_via_threshold) ne ""} {
        set_missing_via_check_options -exclude_stack_via -threshold $emir(ir_drop,missing_via_threshold)
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
    if {[info exists emir(power,frequency)] && $emir(power,frequency) ne ""} {
        handle_info "Setting frequency: $emir(power,frequency)"
        set_app_options -name rail.frequency -value $emir(power,frequency)
    }

    # ── Temperature ──
    if {[info exists emir(thermal,temperature)] && $emir(thermal,temperature) ne ""} {
        handle_info "Setting temperature: $emir(thermal,temperature)"
        set_app_options -name rail.temperature -value $emir(thermal,temperature)
    }

    # ── Scenario ──
    if {[info exists emir(power,scenario)] && $emir(power,scenario) ne ""} {
        handle_info "Setting rail scenario: $emir(power,scenario)"
        set_scenario_status $emir(power,scenario) -active true -setup true
        set_app_options -name rail.scenario_name -value $emir(power,scenario)
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
    if {[info exists emir(power,switching_activity_file)] && $emir(power,switching_activity_file) ne ""} {
        set ::emir_saif $emir(power,switching_activity_file)
    } else {
        set ::emir_saif ""
    }

    # ── Use FC power ──
    if {[info exists emir(power,use_fc_power)] && $emir(power,use_fc_power) ne "" && [string is true -strict $emir(power,use_fc_power)]} {
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
    if {[info exists emir(power,analysis_mode)] && $emir(power,analysis_mode) ne ""} {
        set analysis_mode $emir(power,analysis_mode)
    }

    # Determine analysis nets
    set analysis_nets ""
    if {[info exists emir(power,analysis_nets)] && $emir(power,analysis_nets) ne ""} {
        set analysis_nets $emir(power,analysis_nets)
    }

    # EM analysis flag
    set em_analysis 0
    if {[info exists emir(em,enable)] && $emir(em,enable) ne "" && [string is true -strict $emir(em,enable)]} {
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
        if {[info exists emir(ir_drop,missing_via_threshold)] && $emir(ir_drop,missing_via_threshold) ne ""} {
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
    if {[info exists emir(ir_drop,fix_missing_vias)] && $emir(ir_drop,fix_missing_vias) ne "" && [string is true -strict $emir(ir_drop,fix_missing_vias)]} {
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
    if {[info exists emir(power,analysis_mode)] && $emir(power,analysis_mode) ne ""} {
        set analysis_mode $emir(power,analysis_mode)
    }
    set analysis_nets ""
    if {[info exists emir(power,analysis_nets)] && $emir(power,analysis_nets) ne ""} {
        set analysis_nets $emir(power,analysis_nets)
    }

    set output_report ""
    if {[info exists emir(output,report_file)] && $emir(output,report_file) ne ""} {
        set output_report $emir(output,report_file)
    }

    # ── Voltage drop report ──
    if {$analysis_mode eq "static" || $analysis_mode eq "dynamic_vcd" || $analysis_mode eq "dynamic_vectorless" || $analysis_mode eq "dynamic"} {
        handle_info "Generating effective voltage report"
        report_rail_result -type effective_voltage -supply_nets $analysis_nets $output_report
    }

    # ── EM report ──
    if {[info exists emir(em,enable)] && $emir(em,enable) ne "" && [string is true -strict $emir(em,enable)]} {
        if {[info exists emir(output,em_report)] && $emir(output,em_report) ne ""} {
            handle_info "Generating EM report: $emir(output,em_report)"
            set fd [open $emir(output,em_report) w]
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
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
    if {[info exists project(top_module)]} { puts $fp "Design:     $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool:       Synopsys RedHawk (in-design)"
    puts $fp ""
    puts $fp "Analysis Mode: $analysis_mode"
    puts $fp "Analysis Nets: $analysis_nets"
    if {[info exists emir(ir_drop,threshold)] && $emir(ir_drop,threshold) ne ""} {
        puts $fp "IR-Drop Threshold: $emir(ir_drop,threshold)"
    }
    if {[info exists emir(thermal,enable)] && $emir(thermal,enable) ne "" && [string is true -strict $emir(thermal,enable)]} {
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
