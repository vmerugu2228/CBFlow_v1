#!/usr/bin/env tclsh
# CBFlow PV LVS - Synopsys ICV

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "lvs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# --------------------------------------------------------------------------
flow_proc configure_lvs {
    global pv tech project
    handle_info "Configuring LVS run..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # LVS rule deck
    if {[info exists pv(lvs,rule_deck)]} {
        set ::lvs_rules $pv(lvs,rule_deck)
    } elseif {[info exists tech(rules,lvs)]} {
        set ::lvs_rules $tech(rules,lvs)
    } elseif {[info exists ::pv_lvs_rules]} {
        set ::lvs_rules $::pv_lvs_rules
    } else {
        handle_error "No LVS rule deck specified"
        return
    }

    # GDS input (layout)
    if {[info exists pv(input,gds)]} {
        set ::lvs_gds $pv(input,gds)
    } elseif {[info exists ::pv_gds_file]} {
        set ::lvs_gds $::pv_gds_file
    } else {
        set gds_candidates [glob -nocomplain "$run_dir/work/PV/inputs/gds/*.gds"]
        if {[llength $gds_candidates] > 0} {
            set ::lvs_gds [lindex $gds_candidates 0]
        } else {
            handle_error "No GDS file found for LVS"
            return
        }
    }

    # Source netlist (schematic)
    if {[info exists pv(lvs,source_netlist)]} {
        set ::lvs_source $pv(lvs,source_netlist)
    } elseif {[info exists pv(input,netlist)]} {
        set ::lvs_source $pv(input,netlist)
    } else {
        set nl_candidates [glob -nocomplain "$run_dir/work/PV/inputs/netlist/*.v" "$run_dir/work/PV/inputs/spice/*.sp" "$run_dir/work/PV/inputs/spice/*.cdl"]
        if {[llength $nl_candidates] > 0} {
            set ::lvs_source [lindex $nl_candidates 0]
        } else {
            handle_error "No source netlist found for LVS"
            return
        }
    }

    # Top cell
    if {[info exists pv(common,top_cell)]} {
        set ::lvs_top_cell $pv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::lvs_top_cell $project(top_module)
    } else {
        handle_error "Top cell not defined — set pv(common,top_cell) or project(top_module)"
    }

    # LVS options
    set ::lvs_options ""
    if {[info exists pv(lvs,threads)]} {
        append ::lvs_options " -dp $pv(lvs,threads)"
    } else {
        append ::lvs_options " -dp 4"
    }
    if {[info exists pv(lvs,flatten)]} {
        append ::lvs_options " -flat"
    }

    handle_info "LVS configuration:"
    handle_info "  Rule deck:       $::lvs_rules"
    handle_info "  GDS (layout):    $::lvs_gds"
    handle_info "  Source netlist:   $::lvs_source"
    handle_info "  Top cell:        $::lvs_top_cell"
}

# --------------------------------------------------------------------------
# Procedure: run_lvs
#   Execute ICV LVS extraction and comparison
# --------------------------------------------------------------------------
flow_proc run_lvs {
    handle_info "Running LVS with Synopsys ICV..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    file mkdir "$run_dir/results/pv/lvs"
    file mkdir "$::REPORTS_DIR"

    set lvs_start [clock seconds]

    # Build ICV LVS command
    set icv_cmd "icv -lvs -i $::lvs_gds -s $::lvs_source -c $::lvs_rules"
    append icv_cmd " -top $::lvs_top_cell"
    append icv_cmd " -f $run_dir/results/pv/lvs"
    append icv_cmd " -run_dir $run_dir/work/PV/lvs/run"
    append icv_cmd " -log $run_dir/logs/pv/lvs_icv.log"
    append icv_cmd " $::lvs_options"

    handle_info "ICV command: $icv_cmd"

    # Execute LVS
    if {[catch {eval exec $icv_cmd} result]} {
        handle_error "ICV LVS execution failed: $result"
        set ::lvs_status "FAIL"
    } else {
        set ::lvs_status "PASS"
        handle_info "ICV LVS execution completed"
    }

    set lvs_end [clock seconds]
    set ::lvs_runtime [expr {$lvs_end - $lvs_start}]
    handle_info "LVS runtime: ${::lvs_runtime} seconds"
}

# --------------------------------------------------------------------------
# Procedure: parse_lvs_results
#   Parse LVS comparison results - determine MATCH / MISMATCH
# --------------------------------------------------------------------------
flow_proc parse_lvs_results {
    handle_info "Parsing LVS results..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set ::lvs_match "UNKNOWN"
    set ::lvs_device_mismatches 0
    set ::lvs_net_mismatches 0
    set ::lvs_port_mismatches 0
    set ::lvs_property_errors 0

    # Parse ICV LVS output files
    set results_files [glob -nocomplain "$run_dir/results/pv/lvs/*.RESULTS" "$run_dir/results/pv/lvs/*.rep" "$run_dir/work/PV/lvs/run/*.sum"]

    foreach rf $results_files {
        if {[file exists $rf]} {
            set fp [open $rf r]
            set content [read $fp]
            close $fp

            # Check for MATCH/MISMATCH
            if {[regexp -nocase {OVERALL\s+COMPARISON\s+RESULTS?\s*:\s*(\S+)} $content -> match_status]} {
                set ::lvs_match [string toupper $match_status]
            } elseif {[regexp -nocase {LVS\s+(MATCH|CORRECT)} $content]} {
                set ::lvs_match "MATCH"
            } elseif {[regexp -nocase {LVS\s+(MISMATCH|INCORRECT)} $content]} {
                set ::lvs_match "MISMATCH"
            }

            # Count device mismatches
            if {[regexp {Device\s+mismatches?\s*:\s*(\d+)} $content -> cnt]} {
                set ::lvs_device_mismatches $cnt
            }
            # Count net mismatches
            if {[regexp {Net\s+mismatches?\s*:\s*(\d+)} $content -> cnt]} {
                set ::lvs_net_mismatches $cnt
            }
            # Count port mismatches
            if {[regexp {Port\s+mismatches?\s*:\s*(\d+)} $content -> cnt]} {
                set ::lvs_port_mismatches $cnt
            }
            # Count property errors
            if {[regexp {Property\s+errors?\s*:\s*(\d+)} $content -> cnt]} {
                set ::lvs_property_errors $cnt
            }
        }
    }

    handle_info "LVS comparison result: $::lvs_match"
    handle_info "  Device mismatches:  $::lvs_device_mismatches"
    handle_info "  Net mismatches:     $::lvs_net_mismatches"
    handle_info "  Port mismatches:    $::lvs_port_mismatches"
    handle_info "  Property errors:    $::lvs_property_errors"
}

# --------------------------------------------------------------------------
# Procedure: generate_lvs_report
#   Generate comprehensive LVS report
# --------------------------------------------------------------------------
flow_proc generate_lvs_report {
    global pv project tech
    handle_info "Generating LVS report..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    set rpt "$run_dir/results/lvs/lvs_results.rpt"
    file mkdir [file dirname $rpt]
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow PV - LVS Results (Synopsys ICV)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design:          $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology:      $tech(node)" }
    puts $fp "Tool:            Synopsys ICV"
    if {[info exists ::lvs_rules]}         { puts $fp "Rule Deck:       $::lvs_rules" }
    if {[info exists ::lvs_gds]}           { puts $fp "Layout (GDS):    $::lvs_gds" }
    if {[info exists ::lvs_source]}        { puts $fp "Source Netlist:  $::lvs_source" }
    if {[info exists ::lvs_runtime]}       { puts $fp "Runtime:         ${::lvs_runtime} seconds" }
    puts $fp ""
    puts $fp "LVS_STATUS=$::lvs_match"
    puts $fp ""
    puts $fp "Comparison Details:"
    puts $fp "-----------------------------------------------------------------------"
    puts $fp [format "  %-25s %s" "Device Mismatches:" $::lvs_device_mismatches]
    puts $fp [format "  %-25s %s" "Net Mismatches:" $::lvs_net_mismatches]
    puts $fp [format "  %-25s %s" "Port Mismatches:" $::lvs_port_mismatches]
    puts $fp [format "  %-25s %s" "Property Errors:" $::lvs_property_errors]
    puts $fp ""
    puts $fp "Result Files:    $run_dir/results/pv/lvs/"
    puts $fp "Log File:        $run_dir/logs/pv/lvs_icv.log"
    close $fp

    handle_info "LVS report: $rpt"
    if {$::lvs_match eq "MATCH"} {
        handle_info "LVS CLEAN - Layout matches schematic"
    } else {
        handle_warning "LVS $::lvs_match - Review report for details"
    }
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all configure_lvs run_lvs parse_lvs_results generate_lvs_report
exit
