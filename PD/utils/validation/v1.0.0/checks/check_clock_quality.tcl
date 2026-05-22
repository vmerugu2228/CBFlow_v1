#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Clock Quality Check Script
# Parses clock QoR reports to extract clock skew, insertion delay, and coverage.
# Compares skew against a maximum threshold.
#
# Usage: tclsh check_clock_quality.tcl --report <path> --result-dir <path>
#                                      [--max-skew <ps>] [--test-mode]
#
# Max skew default: <= 60 ps
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse Arguments ──────────────────────────────────────────────────────────
set report_file ""
set result_dir  "."
set max_skew    60.0
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --report     { incr i; set report_file [lindex $argv $i] }
        --result-dir { incr i; set result_dir  [lindex $argv $i] }
        --max-skew   { incr i; set max_skew    [lindex $argv $i] }
        --test-mode  { set test_mode 1 }
        default {
            puts "WARNING: Unknown argument: $arg"
        }
    }
}

# ── Test Mode ────────────────────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir "check_clock_quality" "global_skew_ps"
    exit 0
}

# ── Validate Inputs ──────────────────────────────────────────────────────────
if {$report_file eq ""} {
    puts "ERROR: --report argument is required"
    write_check_result $result_dir "check_clock_quality" "FAIL" \
        -detail "No report file specified (--report)"
    exit 1
}

# ── Read Report ──────────────────────────────────────────────────────────────
set content [read_report $report_file]
if {$content eq ""} {
    write_check_result $result_dir "check_clock_quality" "FAIL" \
        -metric "global_skew_ps" \
        -report_file $report_file \
        -detail "Report file not found: $report_file"
    exit 1
}

# ── Extract Clock QoR Metrics ───────────────────────────────────────────────
# FC format: "Global Skew: 45ps"  "Max Insertion Delay: 350ps"  "Coverage: 99.5%"

# Global Skew — try multiple patterns
set global_skew ""

# "Global Skew: 45ps" or "Global Skew: 45 ps" or "Global Skew = 45ps"
set val [extract_metric $content {Global\s+Skew\s*[=:]\s*([\d.]+)\s*ps}]
if {$val ne ""} {
    set global_skew $val
}

# "Clock Skew: 45ps" (alternate label)
if {$global_skew eq ""} {
    set val [extract_metric $content {Clock\s+Skew\s*[=:]\s*([\d.]+)\s*ps}]
    if {$val ne ""} {
        set global_skew $val
    }
}

# "Max Skew: 45ps" (alternate label)
if {$global_skew eq ""} {
    set val [extract_metric $content {Max\s+Skew\s*[=:]\s*([\d.]+)\s*ps}]
    if {$val ne ""} {
        set global_skew $val
    }
}

# Max Insertion Delay
set insertion_delay ""
set val [extract_metric $content {(?:Max\s+)?Insertion\s+Delay\s*[=:]\s*([\d.]+)\s*ps}]
if {$val ne ""} {
    set insertion_delay $val
}

# Coverage
set coverage ""
set val [extract_metric $content {Coverage\s*[=:]\s*([\d.]+)\s*%}]
if {$val ne ""} {
    set coverage $val
}

# ── Report Extracted Values ──────────────────────────────────────────────────
puts "INFO: Clock QoR metrics extracted from $report_file:"
if {$global_skew ne ""}     { puts "INFO:   Global Skew:         ${global_skew} ps" }
if {$insertion_delay ne ""} { puts "INFO:   Max Insertion Delay:  ${insertion_delay} ps" }
if {$coverage ne ""}        { puts "INFO:   Coverage:             ${coverage}%" }

# ── Build Detail String ─────────────────────────────────────────────────────
set detail_parts [list]
if {$global_skew ne ""}     { lappend detail_parts "skew=${global_skew}ps" }
if {$insertion_delay ne ""} { lappend detail_parts "insertion_delay=${insertion_delay}ps" }
if {$coverage ne ""}        { lappend detail_parts "coverage=${coverage}%" }

# ── Evaluate Result ──────────────────────────────────────────────────────────
if {$global_skew eq ""} {
    write_check_result $result_dir "check_clock_quality" "FAIL" \
        -metric "global_skew_ps" \
        -report_file $report_file \
        -detail "Could not extract clock skew from report"
    exit 1
}

set skew_val [expr {double($global_skew)}]
set pass [compare_threshold $skew_val $max_skew "<="]
set status [expr {$pass ? "PASS" : "FAIL"}]

set detail_str [join $detail_parts ", "]
if {$pass} { set cmp_word "within" } else { set cmp_word "exceeds" }
append detail_str "; skew ${global_skew}ps ${cmp_word} threshold ${max_skew}ps"

puts "INFO: Global Skew = ${global_skew} ps, Max Skew = ${max_skew} ps, Result = $status"

write_check_result $result_dir "check_clock_quality" $status \
    -metric "global_skew_ps" \
    -value $global_skew \
    -threshold $max_skew \
    -operator "<=" \
    -report_file $report_file \
    -detail $detail_str

exit [expr {$status eq "PASS" ? 0 : 1}]
