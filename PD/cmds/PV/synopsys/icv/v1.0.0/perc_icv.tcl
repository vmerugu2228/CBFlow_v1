#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - PV PERC Command File
# Description: Programmable Electrical Rule Check using Synopsys ICV
# Tool: Synopsys ICV
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source -e $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source -e $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/PV/perc/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global pv project tech flow
# Source ICV tool config
set _tool_config "[file dirname [info script]]/icv_config.tcl"
if {[file exists $_tool_config]} { source $_tool_config }
handle_info "Starting PV PERC stage with Synopsys ICV..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/perc"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# --------------------------------------------------------------------------
# Procedure: configure_perc
#   Set up PERC rule deck, reliability checks, and ESD rules
# --------------------------------------------------------------------------
flow_proc configure_perc {
    global pv tech project
    handle_info "Configuring PERC run..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # PERC rule deck
    if {[info exists icv(perc,rule_deck)]} {
        set ::perc_rules $icv(perc,rule_deck)
    } elseif {[info exists tech(rules,perc)]} {
        set ::perc_rules $tech(rules,perc)
    } elseif {[info exists ::pv_perc_rules]} {
        set ::perc_rules $::pv_perc_rules
    } else {
        handle_error "No PERC rule deck specified"
        return
    }

    # GDS input
    if {[info exists pv(input,gds)]} {
        set ::perc_gds $pv(input,gds)
    } elseif {[info exists ::pv_gds_file]} {
        set ::perc_gds $::pv_gds_file
    } else {
        set gds_candidates [glob -nocomplain "$run_dir/work/PV/inputs/gds/*.gds"]
        if {[llength $gds_candidates] > 0} {
            set ::perc_gds [lindex $gds_candidates 0]
        } else {
            handle_error "No GDS file found for PERC"
            return
        }
    }

    # Top cell
    if {[info exists icv(common,top_cell)]} {
        set ::perc_top_cell $icv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::perc_top_cell $project(top_module)
    } else {
        handle_error "Top cell not defined — set icv(common,top_cell) or project(top_module)"
    }

    # PERC-specific options
    set ::perc_options ""
    if {[info exists icv(perc,threads)]} {
        append ::perc_options " -dp $icv(perc,threads)"
    } else {
        append ::perc_options " -dp 4"
    }
    if {[info exists icv(perc,esd_check)]} {
        append ::perc_options " -esd_check $icv(perc,esd_check)"
    }
    if {[info exists icv(perc,latchup_check)]} {
        append ::perc_options " -latchup_check $icv(perc,latchup_check)"
    }
    if {[info exists icv(perc,voltage_aware)]} {
        append ::perc_options " -voltage_aware"
    }

    handle_info "PERC configuration:"
    handle_info "  Rule deck: $::perc_rules"
    handle_info "  GDS input: $::perc_gds"
    handle_info "  Top cell:  $::perc_top_cell"
}

# --------------------------------------------------------------------------
# Procedure: run_perc
#   Execute ICV PERC reliability and ESD checks
# --------------------------------------------------------------------------
flow_proc run_perc {
    handle_info "Running PERC with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pv/perc"
    file mkdir "$::REPORTS_DIR"

    set perc_start [clock seconds]

    set icv_cmd "icv -perc -i $::perc_gds -c $::perc_rules -f $run_dir/results/pv/perc"
    append icv_cmd " -top $::perc_top_cell"
    append icv_cmd " -run_dir $run_dir/work/PV/perc/run"
    append icv_cmd " -log $run_dir/logs/pv/perc_icv.log"
    append icv_cmd " $::perc_options"

    handle_info "ICV command: $icv_cmd"

    if {[catch {eval exec $icv_cmd} result]} {
        handle_error "ICV PERC execution failed: $result"
        set ::perc_status "FAIL"
    } else {
        set ::perc_status "PASS"
        handle_info "ICV PERC execution completed"
    }

    set perc_end [clock seconds]
    set ::perc_runtime [expr {$perc_end - $perc_start}]
    handle_info "PERC runtime: ${::perc_runtime} seconds"
}

# --------------------------------------------------------------------------
# Procedure: parse_perc_results
#   Parse PERC results for reliability, ESD, and latch-up violations
# --------------------------------------------------------------------------
flow_proc parse_perc_results {
    handle_info "Parsing PERC results..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set ::perc_violations {}
    set ::perc_total_violations 0
    set ::perc_reliability_errors 0
    set ::perc_esd_errors 0
    set ::perc_latchup_errors 0
    set ::perc_voltage_errors 0

    set results_files [glob -nocomplain "$run_dir/results/pv/perc/*.RESULTS" "$run_dir/results/pv/perc/*.sum"]

    foreach rf $results_files {
        if {[file exists $rf]} {
            set fp [open $rf r]
            set content [read $fp]
            close $fp

            foreach line [split $content "\n"] {
                if {[regexp {^(\S+)\s*:\s*(\d+)\s*violations?} $line -> rule_name count]} {
                    dict set ::perc_violations $rule_name $count
                    incr ::perc_total_violations $count

                    if {[regexp -nocase {reliab} $rule_name]}     { incr ::perc_reliability_errors $count }
                    if {[regexp -nocase {esd} $rule_name]}        { incr ::perc_esd_errors $count }
                    if {[regexp -nocase {latch} $rule_name]}      { incr ::perc_latchup_errors $count }
                    if {[regexp -nocase {volt|bias} $rule_name]}  { incr ::perc_voltage_errors $count }
                }
            }
        }
    }

    handle_info "PERC total violations: $::perc_total_violations"
    handle_info "  Reliability:  $::perc_reliability_errors"
    handle_info "  ESD:          $::perc_esd_errors"
    handle_info "  Latch-up:     $::perc_latchup_errors"
    handle_info "  Voltage:      $::perc_voltage_errors"
}

# --------------------------------------------------------------------------
# Procedure: generate_perc_report
#   Generate comprehensive PERC report
# --------------------------------------------------------------------------
flow_proc generate_perc_report {
    global pv project tech
    handle_info "Generating PERC report..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set rpt "$run_dir/results/perc/perc_results.rpt"
    file mkdir [file dirname $rpt]
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow PV - PERC Results (Synopsys ICV)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design:     $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool:       Synopsys ICV"
    if {[info exists ::perc_rules]}        { puts $fp "Rule Deck:  $::perc_rules" }
    if {[info exists ::perc_runtime]}      { puts $fp "Runtime:    ${::perc_runtime} seconds" }
    puts $fp ""
    puts $fp "PERC Status: [expr {[info exists ::perc_status] ? $::perc_status : \"UNKNOWN\"}]"
    puts $fp "Total Violations: $::perc_total_violations"
    puts $fp ""
    puts $fp "Violations by Category:"
    puts $fp "-----------------------------------------------------------------------"
    puts $fp [format "  %-25s %8d" "Reliability:" $::perc_reliability_errors]
    puts $fp [format "  %-25s %8d" "ESD Protection:" $::perc_esd_errors]
    puts $fp [format "  %-25s %8d" "Latch-up:" $::perc_latchup_errors]
    puts $fp [format "  %-25s %8d" "Voltage Domain:" $::perc_voltage_errors]
    puts $fp ""

    if {[info exists ::perc_violations]} {
        puts $fp "Violations by Rule:"
        puts $fp "-----------------------------------------------------------------------"
        dict for {rule cnt} $::perc_violations {
            puts $fp [format "  %-40s %8d" $rule $cnt]
        }
    }

    puts $fp ""
    puts $fp "Result Files: $run_dir/results/pv/perc/"
    puts $fp "Log File:     $run_dir/logs/pv/perc_icv.log"
    close $fp

    handle_info "PERC report: $rpt"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all configure_perc run_perc parse_perc_results generate_perc_report
exit
