#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Legality Check Script
# Parses legality reports (check_legality.rpt) and verifies zero illegal cells.
#
# Usage:
#   tclsh check_legality.tcl --report <path> --result-dir <path> --test-mode
#
# Defaults:
#   --result-dir .
#
# PASS criteria: illegal cell count == 0
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
            puts "Usage: tclsh check_legality.tcl --report <path> --result-dir <path> --test-mode"
            exit 1
        }
    }
}

set check_name "check_legality"

# ── Test mode ────────────────────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir $check_name "illegal_cells"
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
        -metric "illegal_cells" -detail "Report file not found: $report_file" \
        -report_file $report_file
    exit 1
}

# ── Extract illegal cell count ───────────────────────────────────────────────
# Try multiple patterns:
#   "Number of illegal cells: 0"
#   "Illegal Cells: 0"
#   "illegal cells : 0"
#   "Illegal cell count: 0"
set illegal_cells ""

# Pattern 1: "Number of illegal cells: <N>"
set illegal_cells [extract_metric $content {(?i)Number\s+of\s+illegal\s+cells?\s*[:\s]+\s*(\d+)}]

# Pattern 2: "Illegal Cells: <N>"
if {$illegal_cells eq ""} {
    set illegal_cells [extract_metric $content {(?i)Illegal\s+Cells?\s*[:\s]+\s*(\d+)}]
}

# Pattern 3: "illegal cell count: <N>"
if {$illegal_cells eq ""} {
    set illegal_cells [extract_metric $content {(?i)illegal\s+cell\s+count\s*[:\s]+\s*(\d+)}]
}

# Pattern 4: "Total illegal: <N>"
if {$illegal_cells eq ""} {
    set illegal_cells [extract_metric $content {(?i)Total\s+illegal\s*[:\s]+\s*(\d+)}]
}

if {$illegal_cells eq ""} {
    write_check_result $result_dir $check_name "FAIL" \
        -metric "illegal_cells" -detail "Could not extract illegal cell count from report" \
        -report_file $report_file
    exit 1
}

# ── Check: PASS only if zero illegal cells ──────────────────────────────────
set illegal_count [expr {int($illegal_cells)}]

if {$illegal_count == 0} {
    set status "PASS"
    set detail "No illegal cells found"
} else {
    set status "FAIL"
    set detail "Found $illegal_count illegal cell(s)"
}

write_check_result $result_dir $check_name $status \
    -metric "illegal_cells" -value $illegal_count -threshold "0" -operator "==" \
    -report_file $report_file -detail $detail

exit [expr {$status eq "PASS" ? 0 : 1}]
