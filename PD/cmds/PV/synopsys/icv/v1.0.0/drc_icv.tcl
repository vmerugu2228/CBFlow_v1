#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - PV DRC Command File
# Description: Design Rule Check using Synopsys ICV
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

set config_file "$run_dir/work/PV/drc/run/config.tcl"
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
handle_info "Starting PV DRC stage with Synopsys ICV..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/drc"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# --------------------------------------------------------------------------
# Procedure: configure_drc
#   Set up DRC rule deck, options, and run configuration
# --------------------------------------------------------------------------
flow_proc configure_drc {
    global pv tech project
    handle_info "Configuring DRC run..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Determine rule deck
    if {[info exists icv(drc,rule_deck)]} {
        set ::drc_rules $icv(drc,rule_deck)
    } elseif {[info exists tech(rules,drc)]} {
        set ::drc_rules $tech(rules,drc)
    } elseif {[info exists ::pv_drc_rules]} {
        set ::drc_rules $::pv_drc_rules
    } else {
        handle_error "No DRC rule deck specified"
        return
    }

    # Determine GDS input
    if {[info exists pv(input,gds)]} {
        set ::drc_gds $pv(input,gds)
    } elseif {[info exists ::pv_gds_file]} {
        set ::drc_gds $::pv_gds_file
    } else {
        set gds_candidates [glob -nocomplain "$run_dir/work/PV/inputs/gds/*.gds"]
        if {[llength $gds_candidates] > 0} {
            set ::drc_gds [lindex $gds_candidates 0]
        } else {
            handle_error "No GDS file found for DRC"
            return
        }
    }

    # Top cell
    if {[info exists icv(common,top_cell)]} {
        set ::drc_top_cell $icv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::drc_top_cell $project(top_module)
    } else {
        handle_error "Top cell not defined — set icv(common,top_cell) or project(top_module)"
    }

    # DRC options
    set ::drc_options ""
    if {[info exists icv(drc,max_results)]} {
        append ::drc_options " -max_results $icv(drc,max_results)"
    }
    if {[info exists icv(drc,select_rules)]} {
        append ::drc_options " -select_rules $icv(drc,select_rules)"
    }
    if {[info exists icv(drc,threads)]} {
        append ::drc_options " -dp $icv(drc,threads)"
    } else {
        append ::drc_options " -dp 4"
    }

    handle_info "DRC configuration:"
    handle_info "  Rule deck:  $::drc_rules"
    handle_info "  GDS input:  $::drc_gds"
    handle_info "  Top cell:   $::drc_top_cell"
    handle_info "  Options:    $::drc_options"
}

# --------------------------------------------------------------------------
# Procedure: run_drc
#   Execute ICV DRC with configured rule deck and inputs
# --------------------------------------------------------------------------
flow_proc run_drc {
    handle_info "Running DRC with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pv/drc"
    file mkdir "$::REPORTS_DIR"
    file mkdir "$run_dir/work/PV/drc/run"

    set drc_start [clock seconds]

    # Build ICV DRC command
    set icv_cmd "icv -drc -i $::drc_gds -c $::drc_rules -f $run_dir/results/pv/drc"
    append icv_cmd " -top $::drc_top_cell"
    append icv_cmd " -run_dir $run_dir/work/PV/drc/run"
    append icv_cmd " -log $run_dir/logs/pv/drc_icv.log"
    append icv_cmd " $::drc_options"

    handle_info "ICV command: $icv_cmd"

    # Execute DRC
    if {[catch {eval exec $icv_cmd} result]} {
        handle_error "ICV DRC execution failed: $result"
        set ::drc_status "FAIL"
    } else {
        set ::drc_status "PASS"
        handle_info "ICV DRC execution completed"
    }

    set drc_end [clock seconds]
    set ::drc_runtime [expr {$drc_end - $drc_start}]
    handle_info "DRC runtime: ${::drc_runtime} seconds"
}

# --------------------------------------------------------------------------
# Procedure: parse_drc_results
#   Parse DRC results file and count violations by category
# --------------------------------------------------------------------------
flow_proc parse_drc_results {
    handle_info "Parsing DRC results..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set ::drc_violations {}
    set ::drc_total_violations 0

    # Parse ICV DRC error database
    set results_dir "$run_dir/results/pv/drc"
    set summary_files [glob -nocomplain "$results_dir/*.RESULTS" "$results_dir/*.sum" "$results_dir/drc_errors.ascii"]

    foreach sf $summary_files {
        if {[file exists $sf]} {
            set fp [open $sf r]
            set content [read $fp]
            close $fp

            # Parse violation categories from ICV output format
            foreach line [split $content "\n"] {
                # ICV format: RULE_NAME : count violations
                if {[regexp {^(\S+)\s*:\s*(\d+)\s*violations?} $line -> rule_name count]} {
                    dict set ::drc_violations $rule_name $count
                    incr ::drc_total_violations $count
                }
                # Alternative ICV format: count RULE_NAME
                if {[regexp {^\s*(\d+)\s+(\S+)\s*$} $line -> count rule_name]} {
                    dict set ::drc_violations $rule_name $count
                    incr ::drc_total_violations $count
                }
            }
        }
    }

    # Categorize violations
    set ::drc_categories {}
    dict for {rule count} $::drc_violations {
        set category "other"
        if {[regexp -nocase {spacing|space} $rule]}  { set category "spacing" }
        if {[regexp -nocase {width|min_w} $rule]}    { set category "width" }
        if {[regexp -nocase {density|dens} $rule]}   { set category "density" }
        if {[regexp -nocase {via} $rule]}            { set category "via" }
        if {[regexp -nocase {encl} $rule]}           { set category "enclosure" }
        if {[regexp -nocase {area} $rule]}           { set category "area" }

        if {[dict exists $::drc_categories $category]} {
            dict set ::drc_categories $category [expr {[dict get $::drc_categories $category] + $count}]
        } else {
            dict set ::drc_categories $category $count
        }
    }

    handle_info "DRC total violations: $::drc_total_violations"
    dict for {cat cnt} $::drc_categories {
        handle_info "  $cat: $cnt"
    }
}

# --------------------------------------------------------------------------
# Procedure: generate_drc_report
#   Generate comprehensive DRC report
# --------------------------------------------------------------------------
flow_proc generate_drc_report {
    global pv project tech
    handle_info "Generating DRC report..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set rpt "$run_dir/results/drc/drc_results.rpt"
    file mkdir [file dirname $rpt]
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow PV - DRC Results (Synopsys ICV)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design:     $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp "Tool:       Synopsys ICV"
    if {[info exists ::drc_rules]}         { puts $fp "Rule Deck:  $::drc_rules" }
    if {[info exists ::drc_gds]}           { puts $fp "GDS Input:  $::drc_gds" }
    if {[info exists ::drc_runtime]}       { puts $fp "Runtime:    ${::drc_runtime} seconds" }
    puts $fp ""
    puts $fp "DRC Status: [expr {[info exists ::drc_status] ? $::drc_status : \"UNKNOWN\"}]"
    puts $fp "Total Violations: [expr {[info exists ::drc_total_violations] ? $::drc_total_violations : 0}]"
    puts $fp ""

    if {[info exists ::drc_categories]} {
        puts $fp "Violations by Category:"
        puts $fp "-----------------------------------------------------------------------"
        dict for {cat cnt} $::drc_categories {
            puts $fp [format "  %-25s %8d" $cat $cnt]
        }
    }

    if {[info exists ::drc_violations]} {
        puts $fp ""
        puts $fp "Violations by Rule:"
        puts $fp "-----------------------------------------------------------------------"
        dict for {rule cnt} $::drc_violations {
            puts $fp [format "  %-40s %8d" $rule $cnt]
        }
    }

    puts $fp ""
    puts $fp "Result Files: $run_dir/results/pv/drc/"
    puts $fp "Log File:     $run_dir/logs/pv/drc_icv.log"
    close $fp

    handle_info "DRC report: $rpt"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all configure_drc run_drc parse_drc_results generate_drc_report
exit
