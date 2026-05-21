#!/usr/bin/env tclsh
# CBFlow PV DRC - Synopsys ICV

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PV"
set STAGE_NAME "drc"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# --------------------------------------------------------------------------
flow_proc configure_drc {
    global pv tech project
    handle_info "Configuring DRC run..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Determine rule deck
    if {[info exists pv(drc,rule_deck)]} {
        set ::drc_rules $pv(drc,rule_deck)
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
    if {[info exists pv(common,top_cell)]} {
        set ::drc_top_cell $pv(common,top_cell)
    } elseif {[info exists project(top_module)]} {
        set ::drc_top_cell $project(top_module)
    } else {
        handle_error "Top cell not defined — set pv(common,top_cell) or project(top_module)"
    }

    # DRC options
    set ::drc_options ""
    if {[info exists pv(drc,max_results)]} {
        append ::drc_options " -max_results $pv(drc,max_results)"
    }
    if {[info exists pv(drc,select_rules)]} {
        append ::drc_options " -select_rules $pv(drc,select_rules)"
    }
    if {[info exists pv(drc,threads)]} {
        append ::drc_options " -dp $pv(drc,threads)"
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
