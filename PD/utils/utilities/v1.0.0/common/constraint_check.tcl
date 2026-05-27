#!/usr/bin/env tclsh
###############################################################################
# constraint_check.tcl — Tool-Independent SDC Constraint Validator
#
# Parses check_timing.rpt to detect constraint issues:
#   - Unconstrained endpoints
#   - Missing input/output delays
#   - Unclocked registers
#   - Unconstrained clock groups
#   - Multiple clocks on endpoints
#   - Other constraint warnings
#
# Counts violations by type and provides a summary.
# Works with plain tclsh — no EDA tool required.
#
# Usage:
#   tclsh constraint_check.tcl -report check_timing.rpt
#   tclsh constraint_check.tcl -report check_timing.rpt -out results.txt
#
# No fallbacks. Errors if report not found.
###############################################################################

namespace eval ::constraint_check {
    variable version "1.0.0"

    # Violation categories with their detection patterns
    variable categories [list \
        unconstrained_endpoints    {[Uu]nconstrained\s+[Ee]ndpoint}        \
        missing_input_delay        {[Nn]o\s+input\s+delay|input_delay.*missing|[Mm]issing.*input.delay}  \
        missing_output_delay       {[Nn]o\s+output\s+delay|output_delay.*missing|[Mm]issing.*output.delay}  \
        unclocked_registers        {[Uu]nclocked\s+[Rr]egister|no\s+clock\s+reaching}  \
        unconstrained_clock_groups {[Uu]nconstrained\s+clock.*group|clock.*group.*not\s+set}  \
        multiple_clocks            {[Mm]ultiple\s+clock|more\s+than\s+one\s+clock}  \
        no_clock_defined           {[Nn]o\s+clock\s+defined|clock\s+not\s+defined}  \
        ideal_clock_nets           {[Ii]deal\s+clock|clock.*ideal}  \
        generated_clock_issues     {[Gg]enerated\s+clock.*(?:error|warning|issue|problem)}  \
    ]
}

# Parse the check_timing report
proc ::constraint_check::parse_report {rpt_file} {
    if {![file exists $rpt_file]} {
        error "ERROR: Check timing report not found: $rpt_file"
    }
    set fh [open $rpt_file r]
    set content [read $fh]
    close $fh

    if {[string trim $content] eq ""} {
        error "ERROR: Report file is empty: $rpt_file"
    }

    variable categories
    set results [dict create]
    set detail_lines [dict create]

    # Initialize all categories
    foreach {cat pattern} $categories {
        dict set results $cat 0
        dict set detail_lines $cat [list]
    }

    # Parse line by line for section-based counting
    set current_section ""
    set section_count 0
    set lines [split $content "\n"]

    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        set trimmed [string trim $line]

        # Skip empty lines and separators
        if {$trimmed eq "" || [regexp {^[-=*]+$} $trimmed]} continue

        # Check if this line matches a category header
        set matched_cat ""
        foreach {cat pattern} $categories {
            if {[regexp -nocase $pattern $trimmed]} {
                set matched_cat $cat
                break
            }
        }

        if {$matched_cat ne ""} {
            set current_section $matched_cat

            # Try to extract count from the same line or next line
            # Patterns: "... (42)", "... : 42", "Count: 42", "42 endpoints"
            if {[regexp {[\(:]\s*(\d+)\s*[\)]} $trimmed -> cnt]} {
                dict set results $matched_cat [expr {[dict get $results $matched_cat] + $cnt}]
            } elseif {[regexp {:\s*(\d+)\s*$} $trimmed -> cnt]} {
                dict set results $matched_cat [expr {[dict get $results $matched_cat] + $cnt}]
            } elseif {[regexp {(\d+)\s+(?:endpoint|register|pin|port|object|clock)} $trimmed -> cnt]} {
                dict set results $matched_cat [expr {[dict get $results $matched_cat] + $cnt}]
            }
            continue
        }

        # If in a known section, count listed items (lines starting with instance paths)
        if {$current_section ne "" && [regexp {^\s+\S+} $line]} {
            # Lines indented with instance names are individual violations
            if {[regexp {^\s+(\S+/\S+|\S+)} $trimmed -> instance]} {
                set cur [dict get $results $current_section]
                # Only count if we haven't found a numeric count yet
                if {$cur == 0} {
                    dict lappend detail_lines $current_section $instance
                }
            }
        }

        # Detect section end (blank line or new section)
        if {$trimmed eq ""} {
            # If we were counting individual items, finalize
            if {$current_section ne "" && [dict get $results $current_section] == 0} {
                dict set results $current_section [llength [dict get $detail_lines $current_section]]
            }
            set current_section ""
        }
    }

    # Finalize any remaining section
    if {$current_section ne "" && [dict get $results $current_section] == 0} {
        dict set results $current_section [llength [dict get $detail_lines $current_section]]
    }

    return [list results $results details $detail_lines]
}

# Category display names
proc ::constraint_check::display_name {cat} {
    set names [dict create \
        unconstrained_endpoints     "Unconstrained Endpoints" \
        missing_input_delay         "Missing Input Delays" \
        missing_output_delay        "Missing Output Delays" \
        unclocked_registers         "Unclocked Registers" \
        unconstrained_clock_groups  "Unconstrained Clock Groups" \
        multiple_clocks             "Multiple Clocks on Endpoints" \
        no_clock_defined            "No Clock Defined" \
        ideal_clock_nets            "Ideal Clock Nets" \
        generated_clock_issues      "Generated Clock Issues" \
    ]
    if {[dict exists $names $cat]} {
        return [dict get $names $cat]
    }
    return $cat
}

# Generate report
proc ::constraint_check::report {rpt_file args} {
    set out_file ""
    foreach {key val} $args {
        if {$key eq "-out"} { set out_file $val }
    }

    set parsed [parse_report $rpt_file]
    set results [dict get $parsed results]

    variable categories

    set lines [list]
    lappend lines "===== SDC Constraint Check Report ====="
    lappend lines "Source: $rpt_file"
    lappend lines ""
    lappend lines [format "%-36s %10s  %s" "Violation Type" "Count" "Status"]
    lappend lines [string repeat "-" 60]

    set total_violations 0
    set violation_types 0

    foreach {cat pattern} $categories {
        set cnt [dict get $results $cat]
        set total_violations [expr {$total_violations + $cnt}]
        set status "CLEAN"
        if {$cnt > 0} {
            set status "VIOLATION"
            incr violation_types
        }
        lappend lines [format "%-36s %10d  %s" [display_name $cat] $cnt $status]
    }

    lappend lines [string repeat "-" 60]
    lappend lines [format "%-36s %10d" "TOTAL VIOLATIONS" $total_violations]
    lappend lines ""

    if {$total_violations == 0} {
        lappend lines "Result: ALL CLEAN -- No constraint issues detected."
    } else {
        lappend lines "Result: $violation_types violation type(s) found, $total_violations total issues."
        lappend lines "Action: Review and fix SDC constraints before signoff."
    }
    lappend lines ""

    set text [join $lines "\n"]
    if {$out_file ne ""} {
        set fh [open $out_file w]
        puts $fh $text
        close $fh
        puts "INFO: Output written to $out_file"
    } else {
        puts $text
    }
}

# CLI entry point
proc ::constraint_check::main {args} {
    set rpt_file ""
    set out_file ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            -report {
                incr i
                set rpt_file [lindex $args $i]
            }
            -out {
                incr i
                set out_file [lindex $args $i]
            }
            default {
                error "ERROR: Unknown argument: $arg\nUsage: tclsh constraint_check.tcl -report check_timing.rpt \[-out file\]"
            }
        }
    }

    if {$rpt_file eq ""} {
        error "ERROR: -report argument is required.\nUsage: tclsh constraint_check.tcl -report check_timing.rpt \[-out file\]"
    }

    set extra_args [list]
    if {$out_file ne ""} { lappend extra_args -out $out_file }

    report $rpt_file {*}$extra_args
}

# Execute when run from command line
if {[info exists ::argv] && [llength $::argv] > 0} {
    ::constraint_check::main {*}$::argv
}
