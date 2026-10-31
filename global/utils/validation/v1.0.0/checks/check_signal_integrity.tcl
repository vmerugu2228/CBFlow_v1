#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Signal Integrity (SI) Violation Check
# Parses report_si.rpt and extracts crosstalk/SI/noise violation counts.
# PASS if all SI-related violation counts == 0.
#
# Usage:
#   tclsh check_signal_integrity.tcl --report <path> --result-dir <path> \
#                                     [--test-mode]
#
# Report formats supported:
#   FC:  "SI Violations: 0"
#        "Crosstalk Violations: 0"
#        "Noise Violations: 0"
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
        --report     { incr i; set report_file [lindex $argv $i] }
        --result-dir { incr i; set result_dir  [lindex $argv $i] }
        --test-mode  { set test_mode 1 }
    }
}

# ── Test mode — dummy PASS ───────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir "check_signal_integrity" "si_violations"
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
    write_check_result $result_dir "check_signal_integrity" "FAIL" \
        -metric "si_violations" -value "" -threshold "0" -operator "==" \
        -report_file $report_file \
        -detail "Report file not found: $report_file"
    exit 1
}

# ── Extract SI violation counts ──────────────────────────────────────────────
# FC format: "SI Violations: <N>"
set si_violations [extract_metric $content {SI\s+Violations?\s*:\s*(\d+)}]

# FC format: "Crosstalk Violations: <N>"
set xtalk_violations [extract_metric $content {Crosstalk\s+Violations?\s*:\s*(\d+)}]

# FC format: "Noise Violations: <N>"
set noise_violations [extract_metric $content {Noise\s+Violations?\s*:\s*(\d+)}]

# If none of the patterns matched, try a generic SI/crosstalk pattern
if {$si_violations eq "" && $xtalk_violations eq "" && $noise_violations eq ""} {
    # Try generic: "Total SI violations: <N>" or "Signal Integrity violations: <N>"
    set si_violations [extract_metric $content {(?:Total\s+)?(?:SI|Signal\s+Integrity)\s+[Vv]iolations?\s*:\s*(\d+)}]
}

# If still nothing found, report FAIL
if {$si_violations eq "" && $xtalk_violations eq "" && $noise_violations eq ""} {
    write_check_result $result_dir "check_signal_integrity" "FAIL" \
        -metric "si_violations" -value "" -threshold "0" -operator "==" \
        -report_file $report_file \
        -detail "Could not extract any SI/crosstalk/noise violation counts from report"
    exit 1
}

# ── Compute total violations ────────────────────────────────────────────────
set total 0
set detail_parts [list]

if {$si_violations ne ""} {
    set total [expr {$total + $si_violations}]
    lappend detail_parts "SI=$si_violations"
}
if {$xtalk_violations ne ""} {
    set total [expr {$total + $xtalk_violations}]
    lappend detail_parts "Crosstalk=$xtalk_violations"
}
if {$noise_violations ne ""} {
    set total [expr {$total + $noise_violations}]
    lappend detail_parts "Noise=$noise_violations"
}

# ── Compare: PASS only if total == 0 ────────────────────────────────────────
set status [expr {[compare_threshold $total 0 "=="] ? "PASS" : "FAIL"}]

set breakdown [join $detail_parts ", "]
if {$status eq "PASS"} {
    set detail "No SI violations found ($breakdown)"
} else {
    set detail "SI violations detected: total=$total ($breakdown)"
}

write_check_result $result_dir "check_signal_integrity" $status \
    -metric "si_violations" -value $total -threshold "0" -operator "==" \
    -report_file $report_file \
    -detail $detail

exit [expr {$status eq "PASS" ? 0 : 1}]
