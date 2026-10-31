#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — DRC Violation Check
# Parses signoff_check_drc.rpt and extracts total DRC violation count.
# PASS if violations == 0 (signoff/P3) or <= threshold (earlier phases).
#
# Usage:
#   tclsh check_drc.tcl --report <path> --result-dir <path> \
#                        [--threshold <value>] [--test-mode]
#
# Report formats supported:
#   FC:  "Total Violations: 0"  or  "Total.*violation.*: 0"
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse arguments ──────────────────────────────────────────────────────────
set report_file ""
set result_dir  "."
set threshold   0
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --report     { incr i; set report_file [lindex $argv $i] }
        --result-dir { incr i; set result_dir  [lindex $argv $i] }
        --threshold  { incr i; set threshold   [lindex $argv $i] }
        --test-mode  { set test_mode 1 }
    }
}

# ── Test mode — dummy PASS ───────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir "check_drc" "drc_violations"
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
    write_check_result $result_dir "check_drc" "FAIL" \
        -metric "drc_violations" -value "" -threshold $threshold -operator "<=" \
        -report_file $report_file \
        -detail "Report file not found: $report_file"
    exit 1
}

# ── Extract DRC violation count ──────────────────────────────────────────────
# Try FC format: "Total Violations: <N>"
set drc_violations [extract_metric $content {Total\s+Violations\s*:\s*(\d+)}]

# Fallback: broader pattern "Total.*violation.*: <N>"
if {$drc_violations eq ""} {
    set drc_violations [extract_metric $content {Total\s+.*[Vv]iolation.*:\s*(\d+)}]
}

# Fallback: "DRC violations: <N>" or "DRC errors: <N>"
if {$drc_violations eq ""} {
    set drc_violations [extract_metric $content {(?:DRC)\s+(?:violations?|errors?)\s*:\s*(\d+)}]
}

# If still not found, report as FAIL with detail
if {$drc_violations eq ""} {
    write_check_result $result_dir "check_drc" "FAIL" \
        -metric "drc_violations" -value "" -threshold $threshold -operator "<=" \
        -report_file $report_file \
        -detail "Could not extract DRC violation count from report"
    exit 1
}

# ── Compare against threshold ───────────────────────────────────────────────
set status [expr {[compare_threshold $drc_violations $threshold "<="] ? "PASS" : "FAIL"}]

if {$status eq "PASS"} {
    set detail "DRC violations ($drc_violations) within threshold ($threshold)"
} else {
    set detail "DRC violations ($drc_violations) exceed threshold ($threshold)"
}

write_check_result $result_dir "check_drc" $status \
    -metric "drc_violations" -value $drc_violations -threshold $threshold -operator "<=" \
    -report_file $report_file \
    -detail $detail

exit [expr {$status eq "PASS" ? 0 : 1}]
