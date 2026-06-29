#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow shared redhawk_fc.tcl — Synopsys Fusion Compiler ↔ RedHawk-SC integration
# Standalone recipe sourced by gated flow_procs in cts_opt_fc.tcl, pro_fc.tcl,
# signoff_fc.tcl. Single canonical copy lives under cmds/PNR/synopsys/fc/<ver>/;
# the synth_pnr copies of those cmd files are symlinks, so the same recipe is
# reachable from both PNR and SYNTH_PNR runs.
#
# FC-RM source of truth: Y-2026.03 RedHawk-SC integration in clock_opt_opto.tcl,
# route_opt.tcl, and chip_finish.tcl.
#
# Caller protocol: the flow_proc that sources this recipe MUST set these globals
# first. Missing required inputs → return -code error (aborts the stage).
#
# Required:
#   ::REDHAWK_STAGE              "cts_opt" | "pro" | "signoff"
#   ::REDHAWK_GAD_FILE           Geometry-aware data file from foundry/PDK
#   ::REDHAWK_TECH_FILE          RedHawk tech file
#   ::REDHAWK_POWER_NET          Top-level power net name (e.g. VDD)
#   ::REDHAWK_GROUND_NET         Top-level ground net name (e.g. VSS)
#
# Optional (sensible defaults):
#   ::REDHAWK_SCENARIO           ""     — analysis scenario; "" → current_scenario
#   ::REDHAWK_IR_THRESHOLD       "0.05" — IR drop violation threshold (V)
#   ::REDHAWK_SWITCHING_ACTIVITY ""     — SAIF/VCD file for dynamic IR
#   ::REDHAWK_STATIC             "true" — run static IR analysis
#   ::REDHAWK_DYNAMIC            "true" — run dynamic IR analysis
#   ::REDHAWK_EM                 "false"— run EM (electromigration) analysis
#   ::REDHAWK_FIX_VIOLATORS      "true" — feed IR violators back to opt as
#                                          fix points (cts_opt + pro only)
#   ::REDHAWK_NUM_CPUS           "8"    — RedHawk parallelism
#   ::REDHAWK_REPORTS_DIR        ""     — output dir; "" → ::REPORTS_DIR/redhawk
#
# Behavior by stage:
#   cts_opt / pro  — pre-opto IR baseline + post-opto IR re-analysis;
#                    optionally feed violators back as fix points.
#   signoff        — one-shot static + dynamic IR signoff; no fix-point feedback.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Input validation ─────────────────────────────────────────────────────────
foreach _req {REDHAWK_STAGE REDHAWK_GAD_FILE REDHAWK_TECH_FILE REDHAWK_POWER_NET REDHAWK_GROUND_NET} {
    if {![info exists ::$_req] || [set ::$_req] eq ""} {
        return -code error "redhawk_fc.tcl: required global ::$_req is not set"
    }
}
foreach _file {REDHAWK_GAD_FILE REDHAWK_TECH_FILE} {
    if {![file exists [set ::$_file]]} {
        return -code error "redhawk_fc.tcl: ::$_file points at non-existent file: [set ::$_file]"
    }
}
if {[lsearch -exact {cts_opt pro signoff} $::REDHAWK_STAGE] < 0} {
    return -code error "redhawk_fc.tcl: ::REDHAWK_STAGE must be one of {cts_opt pro signoff}, got '$::REDHAWK_STAGE'"
}

# ── Defaults for optional knobs ──────────────────────────────────────────────
foreach {_var _default} {
    REDHAWK_SCENARIO            ""
    REDHAWK_IR_THRESHOLD        "0.05"
    REDHAWK_SWITCHING_ACTIVITY  ""
    REDHAWK_STATIC              "true"
    REDHAWK_DYNAMIC             "true"
    REDHAWK_EM                  "false"
    REDHAWK_FIX_VIOLATORS       "true"
    REDHAWK_NUM_CPUS            "8"
    REDHAWK_REPORTS_DIR         ""
} {
    if {![info exists ::$_var] || [set ::$_var] eq ""} {
        set ::$_var $_default
    }
}

if {$::REDHAWK_REPORTS_DIR eq ""} {
    set ::REDHAWK_REPORTS_DIR "$::REPORTS_DIR/redhawk"
}
file mkdir $::REDHAWK_REPORTS_DIR

handle_info "─── RedHawk-SC rail analysis: stage=$::REDHAWK_STAGE ───"
handle_info "  GAD file:           $::REDHAWK_GAD_FILE"
handle_info "  Tech file:          $::REDHAWK_TECH_FILE"
handle_info "  Power / Ground:     $::REDHAWK_POWER_NET / $::REDHAWK_GROUND_NET"
handle_info "  IR threshold:       $::REDHAWK_IR_THRESHOLD V"
handle_info "  Static / Dynamic:   $::REDHAWK_STATIC / $::REDHAWK_DYNAMIC"
handle_info "  EM analysis:        $::REDHAWK_EM"
handle_info "  Fix violators:      $::REDHAWK_FIX_VIOLATORS (cts_opt/pro only)"
handle_info "  CPUs:               $::REDHAWK_NUM_CPUS"
handle_info "  Reports dir:        $::REDHAWK_REPORTS_DIR"

# ── FC-RM: configure RedHawk-SC link ─────────────────────────────────────────
set _rh_opts [list \
    -gad_file       $::REDHAWK_GAD_FILE \
    -tech_file      $::REDHAWK_TECH_FILE \
    -power_supply   $::REDHAWK_POWER_NET \
    -ground_supply  $::REDHAWK_GROUND_NET \
    -num_cpus       $::REDHAWK_NUM_CPUS \
    -ir_threshold   $::REDHAWK_IR_THRESHOLD]

if {$::REDHAWK_SCENARIO ne ""} {
    lappend _rh_opts -scenario $::REDHAWK_SCENARIO
}
if {$::REDHAWK_SWITCHING_ACTIVITY ne "" && [file exists $::REDHAWK_SWITCHING_ACTIVITY]} {
    lappend _rh_opts -switching_activity_file $::REDHAWK_SWITCHING_ACTIVITY
}

handle_info "Configuring RedHawk-SC interface"
handle_info "Running: set_redhawk_sc_options $_rh_opts"
eval set_redhawk_sc_options $_rh_opts

# Enable RedHawk-SC in the opto loop (cts_opt / pro only — opto runs ARE the
# loop). For signoff this knob is irrelevant; signoff is one-shot.
if {$::REDHAWK_STAGE in {cts_opt pro}} {
    set_app_options -name opt.flow.enable_redhawk_sc -value true
    if {[string is true -strict $::REDHAWK_FIX_VIOLATORS]} {
        set_app_options -name opt.flow.redhawk_sc_fix_violators -value true
    }
}

# Pre-flight: setup check
redirect -file $::REDHAWK_REPORTS_DIR/check_setup.${::REDHAWK_STAGE}.rpt {
    redhawk_sc_check_setup
}

# ── Static IR analysis ───────────────────────────────────────────────────────
if {[string is true -strict $::REDHAWK_STATIC]} {
    handle_info "RedHawk-SC: running static IR analysis"
    redirect -file $::REDHAWK_REPORTS_DIR/static_ir.${::REDHAWK_STAGE}.rpt {
        redhawk_sc_static_analysis \
            -output_dir $::REDHAWK_REPORTS_DIR/static_${::REDHAWK_STAGE}
    }
}

# ── Dynamic IR analysis ──────────────────────────────────────────────────────
if {[string is true -strict $::REDHAWK_DYNAMIC]} {
    handle_info "RedHawk-SC: running dynamic IR analysis"
    set _dyn_opts [list -output_dir $::REDHAWK_REPORTS_DIR/dynamic_${::REDHAWK_STAGE}]
    if {$::REDHAWK_SWITCHING_ACTIVITY ne "" && [file exists $::REDHAWK_SWITCHING_ACTIVITY]} {
        lappend _dyn_opts -switching_activity_file $::REDHAWK_SWITCHING_ACTIVITY
        handle_info "  Using switching activity: $::REDHAWK_SWITCHING_ACTIVITY"
    } else {
        lappend _dyn_opts -vectorless
        handle_info "  Vectorless mode (no switching activity file provided)"
    }
    redirect -file $::REDHAWK_REPORTS_DIR/dynamic_ir.${::REDHAWK_STAGE}.rpt {
        eval redhawk_sc_dynamic_analysis $_dyn_opts
    }
}

# ── EM analysis (optional, off by default) ───────────────────────────────────
if {[string is true -strict $::REDHAWK_EM]} {
    handle_info "RedHawk-SC: running EM analysis"
    redirect -file $::REDHAWK_REPORTS_DIR/em.${::REDHAWK_STAGE}.rpt {
        redhawk_sc_em_analysis \
            -output_dir $::REDHAWK_REPORTS_DIR/em_${::REDHAWK_STAGE}
    }
}

# ── Apply violators as fix points (cts_opt + pro only) ───────────────────────
if {$::REDHAWK_STAGE in {cts_opt pro} && [string is true -strict $::REDHAWK_FIX_VIOLATORS]} {
    handle_info "RedHawk-SC: applying IR violators as fix points for next opto pass"
    redirect -file $::REDHAWK_REPORTS_DIR/apply_results.${::REDHAWK_STAGE}.rpt {
        redhawk_sc_apply_results -fix_points
    }
}

# ── Summary report ───────────────────────────────────────────────────────────
redirect -file $::REDHAWK_REPORTS_DIR/summary.${::REDHAWK_STAGE}.rpt {
    report_redhawk_sc_results
}

handle_info "─── RedHawk-SC rail analysis completed: stage=$::REDHAWK_STAGE ───"
handle_info "  Reports written to: $::REDHAWK_REPORTS_DIR"
