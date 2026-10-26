#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Congestion Check Script
# Parses congestion reports to extract overflow percentage and compare against
# a maximum threshold. Supports FC format ("Overall Overflow:", "Max Congestion:",
# "H/V overflow") and Innovus format.
#
# Usage: tclsh check_congestion.tcl --report <path> --result-dir <path>
#                                   [--threshold <value>] [--test-mode]
#
# Threshold default: <= 0.90 (90% overflow)
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse Arguments ──────────────────────────────────────────────────────────
set report_file ""
set result_dir  "."
set threshold   0.90
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --report     { incr i; set report_file [lindex $argv $i] }
        --result-dir { incr i; set result_dir  [lindex $argv $i] }
        --threshold  { incr i; set threshold   [lindex $argv $i] }
        --test-mode  { set test_mode 1 }
        default {
            puts "WARNING: Unknown argument: $arg"
        }
    }
}

# ── Test Mode ────────────────────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir "check_congestion" "overflow_pct"
    exit 0
}

# ── Validate Inputs ──────────────────────────────────────────────────────────
if {$report_file eq ""} {
    puts "ERROR: --report argument is required"
    write_check_result $result_dir "check_congestion" "FAIL" \
        -detail "No report file specified (--report)"
    exit 1
}

# ── Read Report ──────────────────────────────────────────────────────────────
set content [read_report $report_file]
if {$content eq ""} {
    write_check_result $result_dir "check_congestion" "FAIL" \
        -metric "overflow_pct" \
        -report_file $report_file \
        -detail "Report file not found: $report_file"
    exit 1
}

# ── Extract Congestion Metrics ───────────────────────────────────────────────
# Try multiple FC/Innovus congestion report formats

set overflow_pct ""

# Format 1: "Overall Overflow: 0.12" (fractional)
set val [extract_metric $content {Overall\s+Overflow\s*:\s*([\d.]+)}]
if {$val ne ""} {
    set overflow_pct $val
}

# Format 2: "Max Congestion: 85%" (percentage — convert to fraction)
if {$overflow_pct eq ""} {
    set val [extract_metric $content {Max\s+Congestion\s*:\s*([\d.]+)\s*%}]
    if {$val ne ""} {
        set overflow_pct [expr {double($val) / 100.0}]
    }
}

# Format 3: H/V overflow lines — take the max
#   "Horizontal Overflow: 0.05"  /  "Vertical Overflow: 0.08"
if {$overflow_pct eq ""} {
    set h_val [extract_metric $content {(?:Horizontal|H)\s+[Oo]verflow\s*:\s*([\d.]+)}]
    set v_val [extract_metric $content {(?:Vertical|V)\s+[Oo]verflow\s*:\s*([\d.]+)}]
    if {$h_val ne "" || $v_val ne ""} {
        set h [expr {$h_val ne "" ? double($h_val) : 0.0}]
        set v [expr {$v_val ne "" ? double($v_val) : 0.0}]
        set overflow_pct [expr {$h > $v ? $h : $v}]
        puts "INFO: H overflow = $h_val, V overflow = $v_val (using max = $overflow_pct)"
    }
}

# Format 4: "Total Overflow: 0.15" (generic)
if {$overflow_pct eq ""} {
    set val [extract_metric $content {Total\s+Overflow\s*:\s*([\d.]+)}]
    if {$val ne ""} {
        set overflow_pct $val
    }
}

# ── Evaluate Result ──────────────────────────────────────────────────────────
if {$overflow_pct eq ""} {
    write_check_result $result_dir "check_congestion" "FAIL" \
        -metric "overflow_pct" \
        -report_file $report_file \
        -detail "Could not extract overflow metric from report"
    exit 1
}

set overflow_pct [expr {double($overflow_pct)}]
set pass [compare_threshold $overflow_pct $threshold "<="]
set status [expr {$pass ? "PASS" : "FAIL"}]

puts "INFO: Overflow = $overflow_pct, Threshold = $threshold, Result = $status"

if {$pass} { set cmp_word "within" } else { set cmp_word "exceeds" }

write_check_result $result_dir "check_congestion" $status \
    -metric "overflow_pct" \
    -value $overflow_pct \
    -threshold $threshold \
    -operator "<=" \
    -report_file $report_file \
    -detail "Overflow ${overflow_pct} ${cmp_word} threshold ${threshold}"

exit [expr {$status eq "PASS" ? 0 : 1}]
