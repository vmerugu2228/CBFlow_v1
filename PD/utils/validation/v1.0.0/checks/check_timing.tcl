#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Timing Check Script
# Parses timing reports (report_qor.rpt or report_timing.max/min.rpt) and
# checks WNS/TNS against thresholds.
#
# Usage:
#   tclsh check_timing.tcl --report <path> --result-dir <path> \
#       --type setup|hold --threshold <value> --test-mode
#
# Defaults:
#   --type       setup
#   --threshold  -100   (WNS must be >= threshold to PASS)
#   --result-dir .
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse arguments ──────────────────────────────────────────────────────────
set report_file ""
set result_dir  "."
set timing_type "setup"
set threshold   -100
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        "--report"     { incr i; set report_file [lindex $argv $i] }
        "--result-dir" { incr i; set result_dir  [lindex $argv $i] }
        "--type"       { incr i; set timing_type [lindex $argv $i] }
        "--threshold"  { incr i; set threshold   [lindex $argv $i] }
        "--test-mode"  { set test_mode 1 }
        default {
            puts "ERROR: Unknown argument: $arg"
            puts "Usage: tclsh check_timing.tcl --report <path> --result-dir <path> --type setup|hold --threshold <value> --test-mode"
            exit 1
        }
    }
}

set check_name "check_timing_${timing_type}"

# ── Test mode ────────────────────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir $check_name "wns_${timing_type}"
    exit 0
}

# ── Validate arguments ──────────────────────────────────────────────────────
if {$report_file eq ""} {
    puts "ERROR: --report is required"
    exit 1
}

if {$timing_type ni {setup hold}} {
    puts "ERROR: --type must be 'setup' or 'hold'"
    exit 1
}

# ── Read report ──────────────────────────────────────────────────────────────
set content [read_report $report_file]
if {$content eq ""} {
    write_check_result $result_dir $check_name "FAIL" \
        -metric "wns_${timing_type}" -detail "Report file not found: $report_file" \
        -report_file $report_file
    exit 1
}

# ── Extract WNS ──────────────────────────────────────────────────────────────
# Try multiple patterns found in FC / Innovus QoR reports:
#   "WNS(setup): -45.3"  "WNS(hold): -2.1"
#   "Worst Slack: -45.3"
#   "worst slack: -45.3"
#   "WNS : -45.3"
set wns ""

# Pattern 1: WNS(<type>): <value>
set wns [extract_metric $content "(?i)WNS\\s*\\(\\s*${timing_type}\\s*\\)\\s*\[:\\s\]+\\s*(\\-?\\d+\\.?\\d*)"]

# Pattern 2: Worst Slack (generic, used when type-specific not found)
if {$wns eq ""} {
    set wns [extract_metric $content {(?i)(?:Worst\s+Slack|worst\s+slack)\s*[:\s]+\s*(-?\d+\.?\d*)}]
}

# Pattern 3: Generic WNS without type qualifier
if {$wns eq ""} {
    set wns [extract_metric $content {(?i)WNS\s*[:\s]+\s*(-?\d+\.?\d*)}]
}

if {$wns eq ""} {
    write_check_result $result_dir $check_name "FAIL" \
        -metric "wns_${timing_type}" -detail "Could not extract WNS from report" \
        -report_file $report_file
    exit 1
}

# ── Extract TNS (informational, not used for pass/fail) ─────────────────────
set tns ""
set tns [extract_metric $content "(?i)TNS\\s*\\(\\s*${timing_type}\\s*\\)\\s*\[:\\s\]+\\s*(\\-?\\d+\\.?\\d*)"]
if {$tns eq ""} {
    set tns [extract_metric $content {(?i)(?:TNS|Total\s+Negative\s+Slack|total\s+neg\w*\s+slack)\s*[:\s]+\s*(-?\d+\.?\d*)}]
}

# ── Compare WNS against threshold ───────────────────────────────────────────
set pass [compare_threshold $wns $threshold ">="]

if {$pass} {
    set status "PASS"
    set detail "WNS(${timing_type}) = ${wns} ps >= threshold ${threshold} ps"
} else {
    set status "FAIL"
    set detail "WNS(${timing_type}) = ${wns} ps < threshold ${threshold} ps"
}
if {$tns ne ""} {
    append detail " | TNS(${timing_type}) = ${tns} ps"
}

write_check_result $result_dir $check_name $status \
    -metric "wns_${timing_type}" -value $wns -threshold $threshold -operator ">=" \
    -report_file $report_file -detail $detail

exit [expr {$status eq "PASS" ? 0 : 1}]
