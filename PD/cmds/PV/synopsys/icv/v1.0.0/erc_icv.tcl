#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - PV ERC Command File
# Description: Electrical Rule Check using Synopsys ICV
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

set config_file "$run_dir/work/PV/erc/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global pv project tech flow
handle_info "Starting PV ERC stage with Synopsys ICV..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/erc"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# --------------------------------------------------------------------------
# Procedure: configure_erc
#   Set up ERC rule deck and options
# --------------------------------------------------------------------------
flow_proc configure_erc {
    global pv tech project
    handle_info "Configuring ERC run..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # ERC rule deck (may be standalone or embedded in LVS deck)
    if {[info exists pv(erc,rule_deck)]} {
        set ::erc_rules $pv(erc,rule_deck)
    } elseif {[info exists tech(rules,erc)]} {
        set ::erc_rules $tech(rules,erc)
    } elseif {[info exists ::pv_erc_rules]} {
        set ::erc_rules $::pv_erc_rules
    } elseif {[info exists tech(rules,lvs)]} {
        set ::erc_rules $tech(rules,lvs)
        handle_info "Using LVS rule deck for ERC (embedded ERC rules)"
    } else {
        handle_error "No ERC rule deck specified"
        return
    }

    # GDS input
    if {[info exists pv(input,gds)]} {
        set ::erc_gds $pv(input,gds)
    } elseif {[info exists ::pv_gds_file]} {
        set ::erc_gds $::pv_gds_file
    } else {
        set gds_candidates [glob -nocomplain "$run_dir/work/PV/inputs/gds/*.gds"]
        if {[llength $gds_candidates] > 0} {
            set ::erc_gds [lindex $gds_candidates 0]
        } else {
            handle_error "No GDS file found for ERC"
            return
        }
    }

    # Top cell
    if {[info exists pv(top_cell)]} {
        set ::erc_top_cell $pv(top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::erc_top_cell $project(top_module)
    } else {
        handle_error "Top cell not defined — set pv(top_cell) or project(top_module)"
    }

    # ERC-specific options
    set ::erc_options ""
    if {[info exists pv(erc,threads)]} {
        append ::erc_options " -dp $pv(erc,threads)"
    } else {
        append ::erc_options " -dp 4"
    }
    if {[info exists pv(erc,power_nets)]} {
        append ::erc_options " -power_nets $pv(erc,power_nets)"
    }
    if {[info exists pv(erc,ground_nets)]} {
        append ::erc_options " -ground_nets $pv(erc,ground_nets)"
    }

    handle_info "ERC configuration:"
    handle_info "  Rule deck: $::erc_rules"
    handle_info "  GDS input: $::erc_gds"
    handle_info "  Top cell:  $::erc_top_cell"
}

# --------------------------------------------------------------------------
# Procedure: run_erc
#   Execute ICV ERC checks (connectivity, shorts, opens, floating nets)
# --------------------------------------------------------------------------
flow_proc run_erc {
    handle_info "Running ERC with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pv/erc"
    file mkdir "$::REPORTS_DIR"

    set erc_start [clock seconds]

    # Build ICV ERC command
    set icv_cmd "icv -erc -i $::erc_gds -c $::erc_rules -f $run_dir/results/pv/erc"
    append icv_cmd " -top $::erc_top_cell"
    append icv_cmd " -run_dir $run_dir/work/PV/erc/run"
    append icv_cmd " -log $run_dir/logs/pv/erc_icv.log"
    append icv_cmd " $::erc_options"

    handle_info "ICV command: $icv_cmd"

    if {[catch {eval exec $icv_cmd} result]} {
        handle_error "ICV ERC execution failed: $result"
        set ::erc_status "FAIL"
    } else {
        set ::erc_status "PASS"
        handle_info "ICV ERC execution completed"
    }

    set erc_end [clock seconds]
    set ::erc_runtime [expr {$erc_end - $erc_start}]
    handle_info "ERC runtime: ${::erc_runtime} seconds"
}

# --------------------------------------------------------------------------
# Procedure: parse_erc_results
#   Parse ERC output and count violations by type
# --------------------------------------------------------------------------
flow_proc parse_erc_results {
    handle_info "Parsing ERC results..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set ::erc_violations {}
    set ::erc_total_violations 0

    # Parse ICV ERC results
    set results_files [glob -nocomplain "$run_dir/results/pv/erc/*.RESULTS" "$run_dir/results/pv/erc/*.sum"]

    foreach rf $results_files {
        if {[file exists $rf]} {
            set fp [open $rf r]
            set content [read $fp]
            close $fp

            foreach line [split $content "\n"] {
                if {[regexp {^(\S+)\s*:\s*(\d+)\s*violations?} $line -> rule_name count]} {
                    dict set ::erc_violations $rule_name $count
                    incr ::erc_total_violations $count
                }
            }
        }
    }

    # Categorize ERC violations
    set ::erc_power_errors 0
    set ::erc_ground_errors 0
    set ::erc_floating_errors 0
    set ::erc_short_errors 0
    set ::erc_open_errors 0

    dict for {rule count} $::erc_violations {
        if {[regexp -nocase {power|vdd|vcc} $rule]}     { incr ::erc_power_errors $count }
        if {[regexp -nocase {ground|gnd|vss} $rule]}     { incr ::erc_ground_errors $count }
        if {[regexp -nocase {float} $rule]}              { incr ::erc_floating_errors $count }
        if {[regexp -nocase {short} $rule]}              { incr ::erc_short_errors $count }
        if {[regexp -nocase {open} $rule]}               { incr ::erc_open_errors $count }
    }

    handle_info "ERC total violations: $::erc_total_violations"
    handle_info "  Power errors:    $::erc_power_errors"
    handle_info "  Ground errors:   $::erc_ground_errors"
    handle_info "  Floating nets:   $::erc_floating_errors"
    handle_info "  Short circuits:  $::erc_short_errors"
    handle_info "  Open circuits:   $::erc_open_errors"
}

# --------------------------------------------------------------------------
# Procedure: generate_erc_report
#   Generate ERC summary report
# --------------------------------------------------------------------------
flow_proc generate_erc_report {
    global pv project tech
    handle_info "Generating ERC report..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set rpt "$run_dir/results/erc/erc_results.rpt"
    file mkdir [file dirname $rpt]
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow PV - ERC Results (Synopsys ICV)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design:     $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool:       Synopsys ICV"
    if {[info exists ::erc_rules]}         { puts $fp "Rule Deck:  $::erc_rules" }
    if {[info exists ::erc_runtime]}       { puts $fp "Runtime:    ${::erc_runtime} seconds" }
    puts $fp ""
    puts $fp "ERC Status: [expr {[info exists ::erc_status] ? $::erc_status : \"UNKNOWN\"}]"
    puts $fp "Total Violations: $::erc_total_violations"
    puts $fp ""
    puts $fp "Violations by Type:"
    puts $fp "-----------------------------------------------------------------------"
    puts $fp [format "  %-25s %8d" "Power Connectivity:" $::erc_power_errors]
    puts $fp [format "  %-25s %8d" "Ground Connectivity:" $::erc_ground_errors]
    puts $fp [format "  %-25s %8d" "Floating Nets:" $::erc_floating_errors]
    puts $fp [format "  %-25s %8d" "Short Circuits:" $::erc_short_errors]
    puts $fp [format "  %-25s %8d" "Open Circuits:" $::erc_open_errors]
    puts $fp ""

    if {[info exists ::erc_violations]} {
        puts $fp "Violations by Rule:"
        puts $fp "-----------------------------------------------------------------------"
        dict for {rule cnt} $::erc_violations {
            puts $fp [format "  %-40s %8d" $rule $cnt]
        }
    }

    puts $fp ""
    puts $fp "Result Files: $run_dir/results/pv/erc/"
    puts $fp "Log File:     $run_dir/logs/pv/erc_icv.log"
    close $fp

    handle_info "ERC report: $rpt"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all configure_erc run_erc parse_erc_results generate_erc_report
exit
