#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Constraint Violations Check Script
# Parses constraint violation reports (report_qor.rpt or check_timing.rpt) to
# extract max_cap, max_tran, and max_fanout violation counts.
# PASS if all violation counts are zero.
#
# Usage: tclsh check_constraints.tcl --report <path> --result-dir <path>
#                                    [--test-mode]
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse Arguments ──────────────────────────────────────────────────────────
set report_file ""
set result_dir  "."
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --report     { incr i; set report_file [lindex $argv $i] }
        --result-dir { incr i; set result_dir  [lindex $argv $i] }
        --test-mode  { set test_mode 1 }
        default {
            puts "WARNING: Unknown argument: $arg"
        }
    }
}

# ── Test Mode ────────────────────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir "check_constraints" "constraint_violations"
    exit 0
}

# ── Validate Inputs ──────────────────────────────────────────────────────────
if {$report_file eq ""} {
    puts "ERROR: --report argument is required"
    write_check_result $result_dir "check_constraints" "FAIL" \
        -detail "No report file specified (--report)"
    exit 1
}

# ── Read Report ──────────────────────────────────────────────────────────────
set content [read_report $report_file]
if {$content eq ""} {
    write_check_result $result_dir "check_constraints" "FAIL" \
        -metric "constraint_violations" \
        -report_file $report_file \
        -detail "Report file not found: $report_file"
    exit 1
}

# ── Extract Constraint Violation Counts ──────────────────────────────────────
# FC format:
#   "max_capacitance violations: 5"
#   "max_transition violations: 3"
#   "max_fanout violations: 0"
# Also handle:
#   "Max Cap violations: 5"
#   "max_capacitance violation count: 5"

# max_capacitance violations
set max_cap_violations ""
set val [extract_metric $content {(?:max_capacitance|Max\s+Cap)\s+(?:violations?|violation\s+count)\s*[=:]\s*(\d+)}]
if {$val ne ""} {
    set max_cap_violations $val
}

# max_transition violations
set max_tran_violations ""
set val [extract_metric $content {(?:max_transition|Max\s+Tran)\s+(?:violations?|violation\s+count)\s*[=:]\s*(\d+)}]
if {$val ne ""} {
    set max_tran_violations $val
}

# max_fanout violations
set max_fanout_violations ""
set val [extract_metric $content {(?:max_fanout|Max\s+Fanout)\s+(?:violations?|violation\s+count)\s*[=:]\s*(\d+)}]
if {$val ne ""} {
    set max_fanout_violations $val
}

# ── Report Extracted Values ──────────────────────────────────────────────────
puts "INFO: Constraint violation counts from $report_file:"
if {$max_cap_violations ne ""}    { puts "INFO:   max_capacitance violations: $max_cap_violations" }
if {$max_tran_violations ne ""}   { puts "INFO:   max_transition violations:  $max_tran_violations" }
if {$max_fanout_violations ne ""} { puts "INFO:   max_fanout violations:      $max_fanout_violations" }

# ── Evaluate Result ──────────────────────────────────────────────────────────
# Check if we found at least one metric
set found_any 0
if {$max_cap_violations ne ""}    { set found_any 1 }
if {$max_tran_violations ne ""}   { set found_any 1 }
if {$max_fanout_violations ne ""} { set found_any 1 }

if {!$found_any} {
    write_check_result $result_dir "check_constraints" "FAIL" \
        -metric "constraint_violations" \
        -report_file $report_file \
        -detail "Could not extract any constraint violation counts from report"
    exit 1
}

# PASS only if ALL found violation counts are zero
set total_violations 0
set detail_parts [list]

if {$max_cap_violations ne ""} {
    set total_violations [expr {$total_violations + int($max_cap_violations)}]
    lappend detail_parts "max_cap=$max_cap_violations"
}
if {$max_tran_violations ne ""} {
    set total_violations [expr {$total_violations + int($max_tran_violations)}]
    lappend detail_parts "max_tran=$max_tran_violations"
}
if {$max_fanout_violations ne ""} {
    set total_violations [expr {$total_violations + int($max_fanout_violations)}]
    lappend detail_parts "max_fanout=$max_fanout_violations"
}

set pass [expr {$total_violations == 0}]
set status [expr {$pass ? "PASS" : "FAIL"}]

set detail_str [join $detail_parts ", "]
append detail_str "; total_violations=$total_violations"

puts "INFO: Total constraint violations = $total_violations, Result = $status"

write_check_result $result_dir "check_constraints" $status \
    -metric "constraint_violations" \
    -value $total_violations \
    -threshold 0 \
    -operator "==" \
    -report_file $report_file \
    -detail $detail_str

exit [expr {$status eq "PASS" ? 0 : 1}]
