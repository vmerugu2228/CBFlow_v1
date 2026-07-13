#!/usr/bin/env tclsh
# CBFlow PV PERC - Synopsys ICV

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "perc"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# --------------------------------------------------------------------------
flow_proc configure_perc {
    global pv tech project
    handle_info "Configuring PERC run..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # PERC rule deck
    if {[info exists pv(perc,rule_deck)]} {
        set ::perc_rules $pv(perc,rule_deck)
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
    if {[info exists pv(common,top_cell)]} {
        set ::perc_top_cell $pv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::perc_top_cell $project(top_module)
    } else {
        handle_error "Top cell not defined — set pv(common,top_cell) or project(top_module)"
    }

    # PERC-specific options
    set ::perc_options ""
    if {[info exists pv(perc,threads)]} {
        append ::perc_options " -dp $pv(perc,threads)"
    } else {
        append ::perc_options " -dp 4"
    }
    if {[info exists pv(perc,esd_check)]} {
        append ::perc_options " -esd_check $pv(perc,esd_check)"
    }
    if {[info exists pv(perc,latchup_check)]} {
        append ::perc_options " -latchup_check $pv(perc,latchup_check)"
    }
    if {[info exists pv(perc,voltage_aware)]} {
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

    # Write to $::REPORTS_DIR (= work/PV/perc1/reports/) so the release
    # verifier finds `work/PV/perc1/reports/perc_results.rpt` per
    # release_config.tcl. The historical results/perc/ path is also written
    # for backwards compatibility with any script that hardcoded it.
    set rpt "$::REPORTS_DIR/perc_results.rpt"
    set legacy_rpt "$run_dir/results/perc/perc_results.rpt"
    file mkdir $::REPORTS_DIR
    file mkdir [file dirname $legacy_rpt]
    set fp [open $rpt w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow PV - PERC Results (Synopsys ICV)"
    puts $fp "==============================================================================="
    puts $fp "Generated: [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
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
    # Mirror to the historical results/perc/ path.
    catch {file copy -force $rpt $legacy_rpt}

    handle_info "PERC report: $rpt"
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all configure_perc run_perc parse_perc_results generate_perc_report
exit
