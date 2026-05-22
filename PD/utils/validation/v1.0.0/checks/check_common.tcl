#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow — Check Script Common Framework
# Shared procedures for all exit milestone check scripts.
#
# Usage: source check_common.tcl   (from individual check scripts)
# ═══════════════════════════════════════════════════════════════════════════════

namespace eval ::CBFlow::Check {

    # ── Extract a numeric metric from report text ─────────────────────────
    # Searches for pattern, returns the first captured group as a number.
    # Returns "" if not found.
    proc extract_metric {report_text pattern} {
        if {[regexp $pattern $report_text _match value]} {
            return [string trim $value]
        }
        return ""
    }

    # ── Extract all matches of a pattern ──────────────────────────────────
    proc extract_all_metrics {report_text pattern} {
        set results [list]
        set start 0
        while {[regexp -start $start $pattern $report_text _match value]} {
            lappend results [string trim $value]
            set start [expr {[string first $_match $report_text $start] + [string length $_match]}]
        }
        return $results
    }

    # ── Compare a value against a threshold ───────────────────────────────
    # Operators: >=  <=  ==  !=  >  <
    # Returns 1 (pass) or 0 (fail)
    proc compare_threshold {value threshold operator} {
        if {$value eq "" || $threshold eq ""} { return 0 }
        set v [expr {double($value)}]
        set t [expr {double($threshold)}]
        switch -- $operator {
            ">="    { return [expr {$v >= $t}] }
            "<="    { return [expr {$v <= $t}] }
            "=="    { return [expr {$v == $t}] }
            "!="    { return [expr {$v != $t}] }
            ">"     { return [expr {$v > $t}] }
            "<"     { return [expr {$v < $t}] }
            default { return 0 }
        }
    }

    # ── Read a report file ────────────────────────────────────────────────
    # Returns file contents or empty string if file doesn't exist.
    proc read_report {filepath} {
        if {![file exists $filepath]} {
            puts "WARNING: Report file not found: $filepath"
            return ""
        }
        set fh [open $filepath "r"]
        set content [read $fh]
        close $fh
        return $content
    }

    # ── Write check result as JSON ────────────────────────────────────────
    # Writes to {result_dir}/{check_name}_result.json
    proc write_check_result {result_dir check_name status args} {
        # args: -metric name -value val -threshold thr -operator op -report_file path -detail msg
        array set opts {
            -metric      ""
            -value       ""
            -threshold   ""
            -operator    ""
            -report_file ""
            -detail      ""
        }
        foreach {k v} $args { set opts($k) $v }

        file mkdir $result_dir
        set result_file [file join $result_dir "${check_name}_result.json"]
        set timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S"]

        set fh [open $result_file "w"]
        puts $fh "\{"
        puts $fh "  \"check\": \"$check_name\","
        puts $fh "  \"status\": \"$status\","
        puts $fh "  \"metric\": \"$opts(-metric)\","
        puts $fh "  \"value\": \"$opts(-value)\","
        puts $fh "  \"threshold\": \"$opts(-threshold)\","
        puts $fh "  \"operator\": \"$opts(-operator)\","
        puts $fh "  \"report_file\": \"$opts(-report_file)\","
        puts $fh "  \"detail\": \"$opts(-detail)\","
        puts $fh "  \"timestamp\": \"$timestamp\""
        puts $fh "\}"
        close $fh

        puts "INFO: Check result: $check_name = $status (written to $result_file)"
        return $status
    }

    # ── Parse FC/Innovus QoR report for key metrics ───────────────────────
    # Returns an array of metric_name → value
    proc parse_qor_report {filepath} {
        set content [read_report $filepath]
        if {$content eq ""} { return [list] }

        set metrics [list]

        # WNS (worst negative slack) — look for "WNS" or "Worst" slack
        set wns [extract_metric $content {(?:WNS|Worst\s+Slack|worst\s+slack)\s*[:\s]+\s*([-\d.]+)}]
        if {$wns ne ""} { lappend metrics "wns" $wns }

        # TNS (total negative slack)
        set tns [extract_metric $content {(?:TNS|Total\s+Negative\s+Slack|total\s+neg\w*\s+slack)\s*[:\s]+\s*([-\d.]+)}]
        if {$tns ne ""} { lappend metrics "tns" $tns }

        # Number of violating paths
        set nvp [extract_metric $content {(?:NVP|Violating\s+Paths?|violating\s+endpoints?)\s*[:\s]+\s*(\d+)}]
        if {$nvp ne ""} { lappend metrics "nvp" $nvp }

        # Area / utilization
        set util [extract_metric $content {(?:Utilization|Cell\s+Density)\s*[:\s]+\s*([\d.]+)\s*%?}]
        if {$util ne ""} { lappend metrics "utilization" $util }

        # Total power
        set power [extract_metric $content {(?:Total\s+Power)\s*[:\s]+\s*([\d.eE+-]+)}]
        if {$power ne ""} { lappend metrics "total_power" $power }

        # DRC violations
        set drc [extract_metric $content {(?:Total|DRC)\s+(?:violations?|errors?)\s*[:\s]+\s*(\d+)}]
        if {$drc ne ""} { lappend metrics "drc_violations" $drc }

        # Max cap violations
        set maxcap [extract_metric $content {(?:max_capacitance|Max\s+Cap)\s+(?:violations?|count)\s*[:\s]+\s*(\d+)}]
        if {$maxcap ne ""} { lappend metrics "max_cap_violations" $maxcap }

        # Max transition violations
        set maxtran [extract_metric $content {(?:max_transition|Max\s+Tran)\s+(?:violations?|count)\s*[:\s]+\s*(\d+)}]
        if {$maxtran ne ""} { lappend metrics "max_tran_violations" $maxtran }

        return $metrics
    }

    # ── Grep-based check ──────────────────────────────────────────────────
    # Searches for pattern in file. Returns PASS/FAIL based on pass_if.
    # pass_if: "found" → PASS if pattern exists, "not_found" → PASS if absent
    proc grep_check {filepath pattern pass_if} {
        set content [read_report $filepath]
        if {$content eq ""} { return "FAIL" }

        set found [regexp $pattern $content]
        if {$pass_if eq "found"} {
            return [expr {$found ? "PASS" : "FAIL"}]
        } else {
            return [expr {$found ? "FAIL" : "PASS"}]
        }
    }

    # ── Test mode: generate dummy PASS result ─────────────────────────────
    proc test_mode_pass {result_dir check_name metric} {
        return [write_check_result $result_dir $check_name "PASS" \
            -metric $metric -value "0" -threshold "0" -operator ">=" \
            -detail "Test mode — dummy PASS"]
    }

    namespace export extract_metric extract_all_metrics compare_threshold \
                     read_report write_check_result parse_qor_report \
                     grep_check test_mode_pass
}

namespace import ::CBFlow::Check::*
