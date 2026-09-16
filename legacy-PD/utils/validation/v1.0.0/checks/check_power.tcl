#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Power Check Script
# Parses power reports to extract total power, leakage, dynamic, and clock power.
# Reports all extracted values; PASS if total power is within budget.
#
# Usage: tclsh check_power.tcl --report <path> --result-dir <path>
#                               [--budget <mW>] [--test-mode]
#
# Budget default: none (if not specified, reports values but always PASS)
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse Arguments ──────────────────────────────────────────────────────────
set report_file ""
set result_dir  "."
set budget      ""
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --report     { incr i; set report_file [lindex $argv $i] }
        --result-dir { incr i; set result_dir  [lindex $argv $i] }
        --budget     { incr i; set budget      [lindex $argv $i] }
        --test-mode  { set test_mode 1 }
        default {
            puts "WARNING: Unknown argument: $arg"
        }
    }
}

# ── Test Mode ────────────────────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir "check_power" "total_power_mW"
    exit 0
}

# ── Validate Inputs ──────────────────────────────────────────────────────────
if {$report_file eq ""} {
    puts "ERROR: --report argument is required"
    write_check_result $result_dir "check_power" "FAIL" \
        -detail "No report file specified (--report)"
    exit 1
}

# ── Read Report ──────────────────────────────────────────────────────────────
set content [read_report $report_file]
if {$content eq ""} {
    write_check_result $result_dir "check_power" "FAIL" \
        -metric "total_power_mW" \
        -report_file $report_file \
        -detail "Report file not found: $report_file"
    exit 1
}

# ── Extract Power Metrics ───────────────────────────────────────────────────
# FC format: "Total Power: 125.3 mW"
# Also handle: "Total Power  =  125.3 mW", scientific notation, uW/W units

# Helper: extract power value and normalize to mW
proc extract_power {content label} {
    # Match: <label> <sep> <number> <unit>
    set pattern "(?:${label})\\s*\[=:\]\\s*(\[\\d.eE+-\]+)\\s*(mW|uW|W|nW)"
    if {[regexp -nocase $pattern $content _match value unit]} {
        set value [expr {double($value)}]
        switch -nocase -- $unit {
            "W"  { return [expr {$value * 1000.0}] }
            "mW" { return $value }
            "uW" { return [expr {$value / 1000.0}] }
            "nW" { return [expr {$value / 1000000.0}] }
        }
    }
    return ""
}

set total_power   [extract_power $content "Total\\s+Power"]
set leakage_power [extract_power $content "Leakage\\s+Power"]
set dynamic_power [extract_power $content "Dynamic\\s+Power"]
set clock_power   [extract_power $content "Clock\\s+Power"]

# Also try "Internal Power" + "Switching Power" as alternate dynamic breakdown
set internal_power  [extract_power $content "Internal\\s+Power"]
set switching_power [extract_power $content "Switching\\s+Power"]

# ── Report Extracted Values ──────────────────────────────────────────────────
puts "INFO: Power metrics extracted from $report_file:"
if {$total_power ne ""}     { puts "INFO:   Total Power:     ${total_power} mW" }
if {$leakage_power ne ""}   { puts "INFO:   Leakage Power:   ${leakage_power} mW" }
if {$dynamic_power ne ""}   { puts "INFO:   Dynamic Power:   ${dynamic_power} mW" }
if {$clock_power ne ""}     { puts "INFO:   Clock Power:     ${clock_power} mW" }
if {$internal_power ne ""}  { puts "INFO:   Internal Power:  ${internal_power} mW" }
if {$switching_power ne ""} { puts "INFO:   Switching Power: ${switching_power} mW" }

# ── Build Detail String ─────────────────────────────────────────────────────
set detail_parts [list]
if {$total_power ne ""}     { lappend detail_parts "total=${total_power}mW" }
if {$leakage_power ne ""}   { lappend detail_parts "leakage=${leakage_power}mW" }
if {$dynamic_power ne ""}   { lappend detail_parts "dynamic=${dynamic_power}mW" }
if {$clock_power ne ""}     { lappend detail_parts "clock=${clock_power}mW" }
if {$internal_power ne ""}  { lappend detail_parts "internal=${internal_power}mW" }
if {$switching_power ne ""} { lappend detail_parts "switching=${switching_power}mW" }

# ── Evaluate Result ──────────────────────────────────────────────────────────
if {$total_power eq ""} {
    write_check_result $result_dir "check_power" "FAIL" \
        -metric "total_power_mW" \
        -report_file $report_file \
        -detail "Could not extract total power from report"
    exit 1
}

set status "PASS"
set detail_str [join $detail_parts ", "]

if {$budget ne ""} {
    set pass [compare_threshold $total_power $budget "<="]
    set status [expr {$pass ? "PASS" : "FAIL"}]
    if {$pass} { set cmp_word "met" } else { set cmp_word "exceeded" }
    append detail_str "; budget=${budget}mW ${cmp_word}"
    puts "INFO: Total Power = ${total_power} mW, Budget = ${budget} mW, Result = $status"
} else {
    puts "INFO: No budget specified — reporting values only (PASS)"
    append detail_str "; no budget specified"
}

write_check_result $result_dir "check_power" $status \
    -metric "total_power_mW" \
    -value $total_power \
    -threshold $budget \
    -operator "<=" \
    -report_file $report_file \
    -detail $detail_str

exit [expr {$status eq "PASS" ? 0 : 1}]
