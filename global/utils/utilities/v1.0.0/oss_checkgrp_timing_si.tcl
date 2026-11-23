# ═══════════════════════════════════════════════════════════════════════════════
# Checklist group: timing + signal integrity (PLACE_EXIT, CTS_EXIT, PRO_EXIT,
# BTO) — runs at every PNR stage's report step (oss_checks_run <stage>) with
# the stage's design, MMMC corners, SDC (propagated clocks from cts on) and,
# at pro / signoff, the extracted SPEF loaded.
#
#   report_qor.rpt         setup/hold NVP, per-path-group WNS, slack histograms,
#                          cross-corner WNS/TNS, reg2reg / in2reg / reg2out WNS,
#                          signoff vs implementation delta (signoff)
#   report_timing.max.rpt  interface (in2reg / reg2out / in2out) and memory
#                          (mem2reg / reg2mem) group WNS
#   check_timing.rpt       recovery / removal / min pulse width / clock gating
#                          violations, multicycle / false path / case analysis
#                          counts (from write_sdc of the loaded constraints)
#   report_crosstalk.rpt   max coupling-cap / total-cap ratio (SPEF, pro on)
#
# Slacks are in library time units (ns). Values that cannot be measured at a
# stage (no constrained path, no SPEF yet) are left out — the check reads NA.
# Not produced (no OpenSTA engine for them): crosstalk delta delay, noise /
# glitch / noise margin, SI-aware setup/hold, clock SI, rail noise, SSO, bus
# coupling, shielding; and checks whose limit is not configured (aggressor
# count, net length) or that the tool checklist map already serves from
# checklist_metrics.rpt (hold WNS/TNS, max cap/tran/fanout).
# ═══════════════════════════════════════════════════════════════════════════════

proc oss_checkgrp_timing_si {stage} {
    set _views [oss_node_views $::NODE_NAME]
    oss_tsichk_nvp_hist
    oss_tsichk_groups
    oss_tsichk_io_groups
    oss_tsichk_cross_corner $_views
    oss_tsichk_check_types
    oss_tsichk_exceptions
    if {$stage in {pro signoff}} { oss_tsichk_coupling $stage $_views }
    if {$stage eq "signoff"} { oss_tsichk_signoff_delta }
}

# A slack OpenSTA reports for an unconstrained / empty set is ~1e30: not a value.
proc oss_tsichk_ok {v} {
    return [expr {[string is double -strict $v] && abs($v) < 1e20}]
}

# Worst slack of the paths -from / -to (all corners), "" when there is none.
proc oss_tsichk_wns {from to min_max} {
    set _w ""
    foreach _pe [find_timing_paths -from $from -to $to -path_delay $min_max \
                     -group_path_count 1 -endpoint_path_count 1 -sort_by_slack] {
        set _s [get_property $_pe slack]
        if {[oss_tsichk_ok $_s] && ($_w eq "" || $_s < $_w)} { set _w $_s }
    }
    return $_w
}

# Endpoints with slack below a limit (all corners), max = setup, min = hold.
proc oss_tsichk_count_below {min_max limit} {
    return [llength [find_timing_paths -path_delay $min_max -slack_max $limit \
                         -group_path_count 1000000 -endpoint_path_count 1]]
}

# Command output as text (OpenSTA redirection into a temp file).
proc oss_tsichk_capture {args} {
    set _tmp "$::REPORTS_DIR/.oss_tsichk.tmp"
    set _rc [catch {oss_report $_tmp {*}$args} _e]
    set _t ""
    if {[file exists $_tmp]} {
        set _fh [open $_tmp]; set _t [read $_fh]; close $_fh
        file delete $_tmp
    }
    if {$_rc} { error $_e }
    return $_t
}

# TIMING_0005 setup_nvp / TIMING_0006 hold_nvp: endpoints with negative slack.
# TIMING_0021 / TIMING_0022: endpoints below the histogram margins the checks
# name (-0.100 setup, -0.050 hold).
proc oss_tsichk_nvp_hist {} {
    oss_check_line report_qor.rpt "No. of Violating Paths : [oss_nvp max]"
    oss_check_line report_qor.rpt "No. of Hold Violating Paths : [oss_nvp min]"
    oss_check_line report_qor.rpt "Paths with Slack < -0.100 : [oss_tsichk_count_below max -0.100]"
    oss_check_line report_qor.rpt "Hold Paths with Slack < -0.050 : [oss_tsichk_count_below min -0.050]"
}

# TIMING_0011 setup_wns_per_group / TIMING_0012 hold_wns_per_group: worst
# slack per configured path group (<flow>(oss,path_groups)), all corners;
# worst group first (the checks read the first line).
proc oss_tsichk_groups {} {
    set _groups [oss_get [oss_flow_arr] oss,path_groups]
    foreach {_mm _tag} {max "WNS" min "Hold WNS"} {
        set _rows {}
        foreach {_g _ft} $_groups {
            lassign $_ft _from _to
            set _w [oss_tsichk_wns [$_from] [$_to] $_mm]
            if {$_w ne ""} { lappend _rows [list $_g $_w] }
        }
        foreach _r [lsort -real -index 1 $_rows] {
            oss_check_line report_qor.rpt \
                "Timing Path Group [lindex $_r 0] $_tag [cbflow_fmt_slack [lindex $_r 1]]"
        }
    }
}

# TIMING_0026 reg2reg_wns / TIMING_0027 io2reg_wns / TIMING_0028 reg2io_wns
# (report_qor.rpt) and TIMING_0025 interface_timing (report_timing.max.rpt,
# worst interface group first); TIMING_0029 memory_timing: paths to / from
# the memory macros (designs with memories only). Setup slack, all corners.
proc oss_tsichk_io_groups {} {
    set _regs [all_registers]
    set _in   [all_inputs -no_clocks]
    set _out  [all_outputs]
    set _wns [dict create]
    foreach {_g _from _to} [list reg2reg $_regs $_regs in2reg $_in $_regs \
                                reg2out $_regs $_out in2out $_in $_out] {
        if {[llength $_from] == 0 || [llength $_to] == 0} continue
        set _w [oss_tsichk_wns $_from $_to max]
        if {$_w ne ""} { dict set _wns $_g $_w }
    }
    foreach _g {reg2reg in2reg reg2out} {
        if {[dict exists $_wns $_g]} {
            oss_check_line report_qor.rpt "Group '$_g' WNS [cbflow_fmt_slack [dict get $_wns $_g]]"
        }
    }
    set _rows {}
    foreach _g {in2reg reg2out in2out} {
        if {[dict exists $_wns $_g]} { lappend _rows [list $_g [dict get $_wns $_g]] }
    }
    foreach _r [lsort -real -index 1 $_rows] {
        oss_check_line report_timing.max.rpt "Group '[lindex $_r 0]' WNS [cbflow_fmt_slack [lindex $_r 1]]"
    }

    if {![oss_has_memories]} return
    set _mems {}
    foreach _i [oss_memory_insts [hier_children [oss_get flow design_name]]] {
        lappend _mems [get_cells $_i]
    }
    if {[llength $_mems] == 0} return
    set _rows {}
    foreach {_g _from _to} [list mem2reg $_mems $_regs reg2mem $_regs $_mems] {
        set _w [oss_tsichk_wns $_from $_to max]
        if {$_w ne ""} { lappend _rows [list $_g $_w] }
    }
    foreach _r [lsort -real -index 1 $_rows] {
        oss_check_line report_timing.max.rpt "Group '[lindex $_r 0]' WNS [cbflow_fmt_slack [lindex $_r 1]]"
    }
}

# Per-corner analysis option of an sta:: slack command (-scene / -corner by
# OpenSTA version).
proc oss_tsichk_corner_value {cmd min_max view} {
    set _opt [oss_corner_opt $cmd]
    if {[catch {$cmd $min_max $_opt $view} _v]} {
        set _alt [expr {$_opt eq "-scene" ? "-corner" : "-scene"}]
        if {[catch {$cmd $min_max $_alt $view} _v]} { return "" }
    }
    return $_v
}

# TIMING_0023 cross_corner_wns / TIMING_0024 cross_corner_tns: worst setup
# WNS and worst setup TNS over the node's MMMC views.
proc oss_tsichk_cross_corner {views} {
    set _wns ""; set _tns ""; set _wv ""; set _tv ""
    foreach _v $views {
        set _w [oss_tsichk_corner_value sta::worst_slack -max $_v]
        if {[oss_tsichk_ok $_w] && ($_wns eq "" || $_w < $_wns)} { set _wns $_w; set _wv $_v }
        set _t [oss_tsichk_corner_value sta::total_negative_slack -max $_v]
        if {[oss_tsichk_ok $_t] && ($_tns eq "" || $_t < $_tns)} { set _tns $_t; set _tv $_v }
    }
    if {$_wns ne ""} {
        oss_check_line report_qor.rpt "Cross-Corner WNS : [cbflow_fmt_slack $_wns] ($_wv)"
    }
    if {$_tns ne ""} {
        oss_check_line report_qor.rpt "Cross-Corner TNS : [cbflow_fmt_slack $_tns] ($_tv)"
    }
}

# TIMING_0013 recovery / TIMING_0014 removal / TIMING_0015 min pulse width /
# TIMING_0016 clock gating (setup + hold): violating checks reported by
# report_check_types -violators (one "(VIOLATED)" row per check), all corners.
proc oss_tsichk_check_types {} {
    foreach {_k _flags} {
        "Recovery Violations"             {-recovery}
        "Removal Violations"              {-removal}
        "Min Pulse Width Violations"      {-min_pulse_width}
        "Clock Gating Check Violations"   {-clock_gating_setup -clock_gating_hold}
    } {
        set _n 0
        foreach _f $_flags {
            set _t [oss_tsichk_capture report_check_types $_f -violators -format end]
            incr _n [regexp -all {\(VIOLATED\)} $_t]
        }
        oss_check_line check_timing.rpt "$_k : $_n"
    }
}

# TIMING_0017 multicycle_path_check / TIMING_0018 false_path_coverage /
# TIMING_0019 case_analysis_coverage: exception and case-analysis commands in
# the constraints as loaded (write_sdc of the design's timing state).
proc oss_tsichk_exceptions {} {
    set _tmp "$::REPORTS_DIR/.oss_tsichk_sdc.tmp"
    write_sdc $_tmp
    set _fh [open $_tmp]; set _t [read $_fh]; close $_fh
    file delete $_tmp
    oss_check_line check_timing.rpt "Multicycle Paths : [regexp -all -line {^\s*set_multicycle_path\M} $_t]"
    oss_check_line check_timing.rpt "False Paths : [regexp -all -line {^\s*set_false_path\M} $_t]"
    oss_check_line check_timing.rpt "Case Analysis Constants : [regexp -all -line {^\s*set_case_analysis\M} $_t]"
}

# SI_0004 coupling_cap_ratio: per net, coupling cap / total cap (*D_NET total)
# from the extracted SPEF of each RC corner the node's views use; the worst
# net over all corners, as a ratio (0..1, the check's 0.35 limit). Only when
# the SPEF carries coupling caps: an extraction that grounds every coupling
# cap (all *CAP pair entries 0) has no coupling to measure.
proc oss_tsichk_coupling {stage views} {
    set _pro [expr {$stage eq "signoff" ? [oss_upstream_node] : $::NODE_NAME}]
    set _rcs {}
    foreach _v $views {
        set _rc [oss_view_attr $_v rc_corner]
        if {$_rc ni $_rcs} { lappend _rcs $_rc }
    }
    set _max ""; set _where ""; set _anycc 0
    foreach _rc $_rcs {
        set _f "[cbflow_node_dir $_pro]/outputs/final_${_rc}.spef"
        if {![file exists $_f]} continue
        set _fh [open $_f]
        set _net ""; set _tot 0.0; set _cc 0.0; set _incap 0
        while {[gets $_fh _ln] >= 0} {
            set _w [regexp -all -inline {\S+} $_ln]
            set _k [lindex $_w 0]
            if {$_k eq "*D_NET"} {
                set _net [lindex $_w 1]; set _tot [lindex $_w 2]; set _cc 0.0; set _incap 0
            } elseif {$_k eq "*CAP"} {
                set _incap 1
            } elseif {$_k in {*RES *INDUC *END}} {
                set _incap 0
                if {$_k eq "*END" && $_net ne "" && [string is double -strict $_tot] && $_tot > 0} {
                    set _r [expr {$_cc / $_tot}]
                    if {$_max eq "" || $_r > $_max} { set _max $_r; set _where "$_net $_rc" }
                    set _net ""
                }
            } elseif {$_incap && [llength $_w] == 4} {
                set _c [lindex $_w 3]
                set _cc [expr {$_cc + $_c}]
                if {$_c > 0} { set _anycc 1 }
            }
        }
        close $_fh
    }
    if {$_anycc && $_max ne ""} {
        oss_check_line report_crosstalk.rpt "Max coupling ratio : [format %.3f $_max] ($_where)"
    }
}

# TIMING_0030 signoff_vs_implementation: |signoff setup WNS - implementation
# (pro) setup WNS|, the pro node's WNS read from its checklist_metrics.rpt.
proc oss_tsichk_signoff_delta {} {
    set _pro [oss_upstream_node]
    set _f "[cbflow_node_dir $_pro]/reports/checklist_metrics.rpt"
    if {![file exists $_f]} return
    set _fh [open $_f]; set _t [read $_fh]; close $_fh
    if {![regexp -line {^Setup WNS\s*:\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)} $_t -> _impl]} return
    set _so [sta::worst_slack -max]
    if {![oss_tsichk_ok $_so]} return
    oss_check_line report_qor.rpt \
        "Signoff Correlation Delta : [cbflow_fmt_slack [expr {abs($_so - $_impl)}]] (signoff [cbflow_fmt_slack $_so], $_pro [cbflow_fmt_slack $_impl])"
}
