#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — File Existence Check
# Verifies that a given file exists and is non-empty.
# PASS if file exists and size > 0.
#
# Usage:
#   tclsh check_file_exists.tcl --file <path> --result-dir <path> \
#                                --check-name <name> [--test-mode]
#
# --report is accepted as an alias for --file (for compatibility).
# ═══════════════════════════════════════════════════════════════════════════════

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir check_common.tcl]

# ── Parse arguments ──────────────────────────────────────────────────────────
set target_file ""
set result_dir  "."
set check_name  "check_file_exists"
set test_mode   0

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --file       { incr i; set target_file [lindex $argv $i] }
        --report     { incr i; set target_file [lindex $argv $i] }
        --result-dir { incr i; set result_dir  [lindex $argv $i] }
        --check-name { incr i; set check_name  [lindex $argv $i] }
        --test-mode  { set test_mode 1 }
    }
}

# ── Test mode — dummy PASS ───────────────────────────────────────────────────
if {$test_mode} {
    test_mode_pass $result_dir $check_name "file_exists"
    exit 0
}

# ── Validate arguments ──────────────────────────────────────────────────────
if {$target_file eq ""} {
    puts "ERROR: --file (or --report) is required"
    exit 1
}

# ── Check file existence ────────────────────────────────────────────────────
if {![file exists $target_file]} {
    write_check_result $result_dir $check_name "FAIL" \
        -metric "file_exists" -value "0" -threshold "1" -operator "==" \
        -report_file $target_file \
        -detail "File does not exist: $target_file"
    exit 1
}

# ── Check file is non-empty ─────────────────────────────────────────────────
set file_size [file size $target_file]

if {$file_size == 0} {
    write_check_result $result_dir $check_name "FAIL" \
        -metric "file_size" -value "0" -threshold "1" -operator ">=" \
        -report_file $target_file \
        -detail "File exists but is empty (0 bytes): $target_file"
    exit 1
}

# ── PASS — file exists and is non-empty ──────────────────────────────────────
write_check_result $result_dir $check_name "PASS" \
    -metric "file_size" -value $file_size -threshold "1" -operator ">=" \
    -report_file $target_file \
    -detail "File exists and is non-empty ($file_size bytes): $target_file"

exit 0
