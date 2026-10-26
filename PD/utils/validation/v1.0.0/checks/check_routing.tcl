#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Routing Check Script
# Parses routing check reports (check_routes / check_routes.final) and verifies
# zero opens and zero shorts.
#
# Usage:
#   tclsh check_routing.tcl --report <path> --result-dir <path> --test-mode
#
# Defaults:
#   --result-dir .
#
# PASS criteria: opens == 0 AND shorts == 0
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse arguments ──────────────────────────────────────────────────────────
set report_file ""
set result_dir  "."
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        "--report"     { incr i; set report_file [lindex $argv $i] }
        "--result-dir" { incr i; set result_dir  [lindex $argv $i] }
        "--test-mode"  { set test_mode 1 }
        default {
            puts "ERROR: Unknown argument: $arg"
            puts "Usage: tclsh check_routing.tcl --report <path> --result-dir <path> --test-mode"
            exit 1
        }
    }
}

set check_name "check_routing"

# ── Test mode ────────────────────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir $check_name "routing_violations"
    exit 0
}

# ── Validate arguments ──────────────────────────────────────────────────────
if {$report_file eq ""} {
    puts "ERROR: --report is required"
    exit 1
}

# ── Read report ──────────────────────────────────────────────────────────────
set content [read_report $report_file]
if {$content eq ""} {
    write_check_result $result_dir $check_name "FAIL" \
        -metric "routing_violations" -detail "Report file not found: $report_file" \
        -report_file $report_file
    exit 1
}

# ── Extract opens count ─────────────────────────────────────────────────────
# Patterns:
#   "Number of opens: 0"
#   "Opens: 0"
#   "open nets: 0"
set opens ""

# Pattern 1: "Number of opens: <N>"
set opens [extract_metric $content {(?i)Number\s+of\s+opens?\s*[:\s]+\s*(\d+)}]

# Pattern 2: "Opens: <N>" or "Open Nets: <N>"
if {$opens eq ""} {
    set opens [extract_metric $content {(?i)Opens?\s*(?:Nets?)?\s*[:\s]+\s*(\d+)}]
}

# ── Extract shorts count ────────────────────────────────────────────────────
# Patterns:
#   "Number of shorts: 0"
#   "Shorts: 0"
set shorts ""

# Pattern 1: "Number of shorts: <N>"
set shorts [extract_metric $content {(?i)Number\s+of\s+shorts?\s*[:\s]+\s*(\d+)}]

# Pattern 2: "Shorts: <N>"
if {$shorts eq ""} {
    set shorts [extract_metric $content {(?i)Shorts?\s*[:\s]+\s*(\d+)}]
}

# ── Fallback: total violations ───────────────────────────────────────────────
# If neither opens nor shorts found, look for "total violations: <N>"
set total_violations ""
if {$opens eq "" && $shorts eq ""} {
    set total_violations [extract_metric $content {(?i)total\s+violations?\s*[:\s]+\s*(\d+)}]
}

# ── Determine pass/fail ─────────────────────────────────────────────────────
if {$total_violations ne ""} {
    # Used total violations as single metric
    set total_count [expr {int($total_violations)}]

    if {$total_count == 0} {
        set status "PASS"
        set detail "No routing violations found (total violations = 0)"
    } else {
        set status "FAIL"
        set detail "Found $total_count total routing violation(s)"
    }

    write_check_result $result_dir $check_name $status \
        -metric "routing_violations" -value $total_count -threshold "0" -operator "==" \
        -report_file $report_file -detail $detail

} elseif {$opens eq "" && $shorts eq ""} {
    # Could not extract any routing metrics
    write_check_result $result_dir $check_name "FAIL" \
        -metric "routing_violations" \
        -detail "Could not extract opens/shorts/violations count from report" \
        -report_file $report_file
    exit 1

} else {
    # Have opens and/or shorts individually
    set opens_count  [expr {$opens  ne "" ? int($opens)  : 0}]
    set shorts_count [expr {$shorts ne "" ? int($shorts) : 0}]
    set total_count  [expr {$opens_count + $shorts_count}]

    if {$opens_count == 0 && $shorts_count == 0} {
        set status "PASS"
        set detail "No routing violations (opens = 0, shorts = 0)"
    } else {
        set status "FAIL"
        set parts [list]
        if {$opens_count > 0} {
            lappend parts "$opens_count open(s)"
        }
        if {$shorts_count > 0} {
            lappend parts "$shorts_count short(s)"
        }
        set detail "Found routing violations: [join $parts ", "]"
    }

    write_check_result $result_dir $check_name $status \
        -metric "routing_violations" -value $total_count -threshold "0" -operator "==" \
        -report_file $report_file -detail $detail
}

exit [expr {$status eq "PASS" ? 0 : 1}]
