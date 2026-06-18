#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         CBFlow Enhanced Validation Configuration             ║
# ║                            Error/Warning Pattern Definitions                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains enhanced validation configuration for CBFlow log validation
# with xterm integration support for critical error display.
#
# Usage: source config/flow/v1.0.0/validation_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     ENHANCED VALIDATION CONFIGURATION                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Critical Error Detection Thresholds ─────────────────────────────────────┐
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(xterm_display_threshold) 1
    set validation(enable_xterm_display) 1
    set validation(xterm_fg_color) "red"
    set validation(xterm_bg_color) "black"
    set validation(xterm_title) "CBFlow Critical Error Viewer"
    set validation(validation_timeout) 300
    set validation(enable_enhanced_patterns) 1

# ┌─ Tool-Specific Critical Error IDs ────────────────────────────────────────┐
# These error IDs trigger immediate xterm display regardless of waiver patterns

# Cadence Genus (SYNTH) Critical Error IDs
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(critical_error_ids,SYNTH,genus) {
        "GENUS-001"    "GENUS-002"    "GENUS-003"    "GENUS-025"
        "GENUS-078"    "GENUS-123"    "GENUS-456"    "GENUS-789"
        "GENUS-999"    "SYNTH_ERROR"  "SYN_FATAL"    "GEN_ABORT"
    }

# Cadence Innovus (FP/PNR) Critical Error IDs
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(critical_error_ids,FP,innovus) {
        "INNOVUS-201"  "INNOVUS-345"  "INNOVUS-456"  "INNOVUS-678"
        "INNOVUS-789"  "INNOVUS-999"  "FP_ERROR"     "FP_FATAL"
        "IMPFP-001"    "IMPFP-025"    "FLP_ABORT"    "PLACE_ERROR"
    }

    set validation(critical_error_ids,PNR,innovus) {
        "INNOVUS-301"  "INNOVUS-456"  "INNOVUS-567"  "INNOVUS-789"
        "INNOVUS-890"  "INNOVUS-999"  "PNR_ERROR"    "PNR_FATAL"
        "IMPPNR-001"   "IMPPNR-025"   "ROUTE_ERROR"  "PNR_ABORT"
    }

# ┌─ Flow-Specific Enhanced Error Patterns ───────────────────────────────────┐
# These patterns supplement the basic error detection with flow-specific rules

# SYNTHESIS Flow Error Patterns
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(error_patterns,SYNTH) {
        ".*synthesis.*failed.*"
        ".*netlist.*generation.*error.*"
        ".*timing.*constraints.*violation.*critical.*"
        ".*library.*loading.*failed.*"
        ".*rtl.*compilation.*error.*"
        ".*elaboration.*failed.*"
        ".*optimization.*aborted.*"
        ".*genus.*crash.*"
        ".*memory.*exhausted.*synthesis.*"
        ".*license.*checkout.*failed.*genus.*"
        ".*design.*has.*no.*ports.*"
        ".*design.*compile.*failed.*"
        ".*critical.*path.*optimization.*failed.*"
    }

    set validation(warning_patterns,SYNTH) {
        ".*timing.*constraint.*missing.*clock.*"
        ".*unresolved.*reference.*"
        ".*latch.*inferred.*"
        ".*combinational.*loop.*detected.*"
        ".*design.*has.*no.*clock.*"
        ".*synthesis.*optimization.*issue.*"
        ".*netlist.*integrity.*warning.*"
        ".*library.*characterization.*incomplete.*"
    }

# FLOORPLAN Flow Error Patterns
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(error_patterns,FP) {
        ".*floorplan.*initialization.*failed.*"
        ".*import.*design.*failed.*"
        ".*lef.*reading.*error.*"
        ".*def.*reading.*error.*"
        ".*technology.*library.*missing.*"
        ".*macro.*placement.*failed.*"
        ".*power.*domain.*setup.*error.*"
        ".*floorplan.*validation.*failed.*"
        ".*innovus.*crash.*fp.*"
        ".*memory.*exhausted.*floorplan.*"
        ".*license.*checkout.*failed.*innovus.*"
        ".*netlist.*import.*error.*"
        ".*constraint.*loading.*failed.*fp.*"
    }

    set validation(warning_patterns,FP) {
        ".*macro.*overlap.*detected.*"
        ".*utilization.*target.*exceeded.*"
        ".*power.*stripe.*spacing.*issue.*"
        ".*floorplan.*aspect.*ratio.*warning.*"
        ".*placement.*density.*warning.*"
        ".*blockage.*overlap.*"
        ".*power.*domain.*warning.*"
        ".*via.*stack.*issue.*fp.*"
    }

# PLACE AND ROUTE Flow Error Patterns
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(error_patterns,PNR) {
        ".*place.*and.*route.*failed.*"
        ".*placement.*failed.*"
        ".*routing.*failed.*"
        ".*cts.*failed.*"
        ".*timing.*optimization.*failed.*"
        ".*drc.*violations.*critical.*"
        ".*antenna.*violations.*critical.*"
        ".*short.*violations.*"
        ".*spacing.*violations.*critical.*"
        ".*innovus.*crash.*pnr.*"
        ".*memory.*exhausted.*pnr.*"
        ".*license.*checkout.*failed.*pnr.*"
        ".*routing.*congestion.*critical.*"
        ".*clock.*tree.*synthesis.*error.*"
        ".*post.*route.*optimization.*failed.*"
    }

    set validation(warning_patterns,PNR) {
        ".*routing.*congestion.*warning.*"
        ".*antenna.*violation.*minor.*"
        ".*via.*pillar.*warning.*"
        ".*timing.*violation.*recoverable.*"
        ".*clock.*skew.*warning.*"
        ".*hold.*time.*violation.*minor.*"
        ".*optimization.*convergence.*issue.*"
        ".*metal.*density.*warning.*"
    }

# ┌─ Critical Warning IDs (require attention but may not trigger xterm) ─────┐
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(critical_warning_ids,SYNTH) {
        "GENUS-W001"   "GENUS-W025"   "GENUS-W078"   "SYN_WARN_CRIT"
    }

    set validation(critical_warning_ids,FP) {
        "INNOVUS-W201" "INNOVUS-W345" "FP_WARN_CRIT" "IMPFP-W001"
    }

    set validation(critical_warning_ids,PNR) {
        "INNOVUS-W301" "INNOVUS-W456" "PNR_WARN_CRIT" "IMPPNR-W001"
    }

# ┌─ Stage-Specific Enhanced Pattern Overrides ───────────────────────────────┐
# Specific stages within flows that have unique validation requirements

# SYNTH Stage-Specific Patterns
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(error_patterns,SYNTH,inputs) {
        ".*rtl.*file.*not.*found.*"
        ".*sdc.*file.*not.*found.*"
        ".*library.*file.*not.*found.*"
        ".*upf.*file.*syntax.*error.*"
    }

    set validation(error_patterns,SYNTH,synthesis) {
        ".*synthesis.*engine.*failure.*"
        ".*design.*rule.*check.*failed.*synthesis.*"
        ".*timing.*driven.*synthesis.*failed.*"
    }

# FP Stage-Specific Patterns
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(error_patterns,FP,import_design) {
        ".*netlist.*import.*failed.*"
        ".*design.*database.*corruption.*"
        ".*technology.*mismatch.*"
    }

    set validation(error_patterns,FP,floorplan) {
        ".*macro.*placement.*conflict.*"
        ".*power.*planning.*error.*"
        ".*io.*placement.*failed.*"
    }

# PNR Stage-Specific Patterns
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(error_patterns,PNR,placement) {
        ".*global.*placement.*failed.*"
        ".*detail.*placement.*failed.*"
        ".*placement.*legalization.*error.*"
    }

    set validation(error_patterns,PNR,cts) {
        ".*clock.*tree.*synthesis.*failure.*"
        ".*clock.*balancing.*error.*"
        ".*useful.*skew.*optimization.*failed.*"
    }

    set validation(error_patterns,PNR,route) {
        ".*global.*routing.*failed.*"
        ".*detail.*routing.*failed.*"
        ".*track.*assignment.*error.*"
        ".*via.*insertion.*failed.*"
    }

# ┌─ Tool Integration Patterns ────────────────────────────────────────────────┐
# Patterns for detecting tool crashes and integration issues

# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(tool_crash_patterns) {
        ".*segmentation.*fault.*"
        ".*core.*dumped.*"
        ".*bus.*error.*"
        ".*floating.*point.*exception.*"
        ".*killed.*signal.*"
        ".*aborted.*signal.*"
        ".*memory.*allocation.*failed.*"
        ".*stack.*overflow.*"
        ".*tool.*terminated.*unexpectedly.*"
    }

    set validation(license_error_patterns) {
        ".*license.*not.*available.*"
        ".*license.*checkout.*failed.*"
        ".*license.*expired.*"
        ".*license.*server.*unreachable.*"
        ".*feature.*not.*licensed.*"
        ".*license.*queue.*timeout.*"
    }

    set validation(environment_error_patterns) {
        ".*environment.*variable.*not.*set.*"
        ".*path.*not.*found.*"
        ".*permission.*denied.*"
        ".*disk.*space.*exhausted.*"
        ".*temporary.*directory.*full.*"
        ".*network.*unreachable.*"
    }

# ┌─ XTerm Display Configuration ──────────────────────────────────────────────┐
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(xterm_command_template) {
        set validation(xterm) -fg ${xterm_fg_color} -bg ${xterm_bg_color}
              -title "${xterm_title}"
              -geometry 120x40
              -e "less +${error_line} ${log_file}"
    }

    # Alternative viewers if xterm not available
    set validation(alternative_viewers) {
        "gnome-terminal --title='CBFlow Error' -- less +${error_line} ${log_file}"
        "konsole --title 'CBFlow Error' -e less +${error_line} ${log_file}"
        "rxvt -fg red -bg black -title 'CBFlow Error' -e less +${error_line} ${log_file}"
    }

    # Error context lines (lines before/after error to show)
    set validation(error_context_lines) 5

# ┌─ Enhanced Reporting Configuration ─────────────────────────────────────────┐
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(enable_enhanced_reports) 1
    set validation(enhanced_report_dir) "logs/validation"
    set validation(error_severity_levels) {CRITICAL HIGH MEDIUM LOW INFO}
    set validation(critical_error_report_format) "CRITICAL_ERRORS_${flow_type}_${stage_name}_${timestamp}.rpt"
    set validation(summary_report_format) "VALIDATION_SUMMARY_${flow_type}_${stage_name}_${timestamp}.rpt"

# ┌─ Integration Hooks ─────────────────────────────────────────────────────────┐
# array set validation { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set validation(pre_validation_hooks) {
        "check_log_file_permissions"
        "validate_environment_setup"
        "initialize_error_tracking"
    }

    # Post-validation hooks (run after validation)
    set validation(post_validation_hooks) {
        "generate_error_summary"
        "update_validation_database"
        "send_critical_error_notifications"
    }

    # Critical error hooks (run when critical errors found)
    set validation(critical_error_hooks) {
        "launch_xterm_viewer"
        "log_critical_error_event"
        "trigger_error_escalation"
    }

puts "INFO: Enhanced validation configuration loaded successfully"
puts "INFO: XTerm integration: [expr {$validation(enable_xterm_display) ? \"enabled\" : \"disabled\"}]"
puts "INFO: Enhanced patterns: [expr {$validation(enable_enhanced_patterns) ? \"enabled\" : \"disabled\"}]"