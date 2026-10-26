#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Utilization Check Script
# Parses utilization reports (report_utilization.rpt) and checks cell density
# against min/max thresholds.
#
# Usage:
#   tclsh check_utilization.tcl --report <path> --result-dir <path> \
#       --min <value> --max <value> --test-mode
#
# Defaults:
#   --min        0.0    (utilization must be >= min)
#   --max        100.0  (utilization must be <= max)
#   --result-dir .
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse arguments ──────────────────────────────────────────────────────────
set report_file ""
set result_dir  "."
set min_util    0.0
set max_util    100.0
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        "--report"     { incr i; set report_file [lindex $argv $i] }
        "--result-dir" { incr i; set result_dir  [lindex $argv $i] }
        "--min"        { incr i; set min_util    [lindex $argv $i] }
        "--max"        { incr i; set max_util    [lindex $argv $i] }
        "--test-mode"  { set test_mode 1 }
        default {
            puts "ERROR: Unknown argument: $arg"
            puts "Usage: tclsh check_utilization.tcl --report <path> --result-dir <path> --min <value> --max <value> --test-mode"
            exit 1
        }
    }
}

set check_name "check_utilization"

# ── Test mode ────────────────────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir $check_name "utilization"
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
        -metric "utilization" -detail "Report file not found: $report_file" \
        -report_file $report_file
    exit 1
}

# ── Extract utilization percentage ───────────────────────────────────────────
# Try multiple patterns:
#   "Cell Density: 0.72"        (FC — fractional form, multiply by 100)
#   "Utilization: 72.3%"        (percentage form)
#   "Utilization: 72.3"         (numeric without %)
set util ""
set is_fractional 0

# Pattern 1: Cell Density (FC fractional format, e.g. "Cell Density: 0.72")
set util [extract_metric $content {(?i)Cell\s+Density\s*[:\s]+\s*(\d+\.?\d*)}]
if {$util ne ""} {
    # Check if value is fractional (0.0 - 1.0 range) and convert to percentage
    if {[expr {double($util)}] <= 1.0} {
        set util [expr {double($util) * 100.0}]
        set is_fractional 1
    }
}

# Pattern 2: Utilization with optional % sign
if {$util eq ""} {
    set util [extract_metric $content {(?i)Utilization\s*[:\s]+\s*(\d+\.?\d*)\s*%?}]
}

# Pattern 3: Cell Area / Total Area based calculation (last resort)
if {$util eq ""} {
    set cell_area [extract_metric $content {(?i)Cell\s+Area\s*[:\s]+\s*(\d+\.?\d*)}]
    set total_area [extract_metric $content {(?i)(?:Total|Design)\s+Area\s*[:\s]+\s*(\d+\.?\d*)}]
    if {$cell_area ne "" && $total_area ne "" && [expr {double($total_area)}] > 0} {
        set util [expr {double($cell_area) / double($total_area) * 100.0}]
    }
}

if {$util eq ""} {
    write_check_result $result_dir $check_name "FAIL" \
        -metric "utilization" -detail "Could not extract utilization from report" \
        -report_file $report_file
    exit 1
}

set util_val [expr {double($util)}]

# ── Compare against min and max thresholds ───────────────────────────────────
set pass_min [compare_threshold $util_val $min_util ">="]
set pass_max [compare_threshold $util_val $max_util "<="]

if {$pass_min && $pass_max} {
    set status "PASS"
    set detail [format "Utilization = %.2f%% is within range \[%.2f%%, %.2f%%\]" $util_val $min_util $max_util]
} elseif {!$pass_min} {
    set status "FAIL"
    set detail [format "Utilization = %.2f%% is below minimum %.2f%%" $util_val $min_util]
} else {
    set status "FAIL"
    set detail [format "Utilization = %.2f%% exceeds maximum %.2f%%" $util_val $max_util]
}

write_check_result $result_dir $check_name $status \
    -metric "utilization" -value [format "%.2f" $util_val] \
    -threshold "${min_util}-${max_util}" -operator "range" \
    -report_file $report_file -detail $detail

exit [expr {$status eq "PASS" ? 0 : 1}]
