#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — timing (opensource / sta)
# OpenSTA timing for one MMMC scenario (::SCENARIO / ::LIB_SET / ::RC_CORNER /
# ::SDC_FILE / ::SPEF_FILE from the timing subnode handler): netlist + libs
# (+ child timing models) + SDC + SPEF, setup/hold/DRV reports and QoR.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "STA"
set STAGE_NAME "timing"
# Dynamic subnodes (per RC corner / per scenario) pass their node in the
# context script (::OSS_NODE); otherwise the launch wrapper's node.
set NODE_NAME [expr {[info exists ::OSS_NODE] ? $::OSS_NODE : [cbflow_node_name]}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: scenario libs, netlist(s), SDC, SPEF(s). sta(oss,sta,mode) flat: every
# descendant block's gate netlist + its SPEF stitched per instance; hier: the
# children as timing models.
flow_proc load_design {
    global design_name blocks
    set _mode [oss_get sta oss,sta,mode]
    if {$_mode ni {flat hier}} { error "sta(oss,sta,mode) must be flat or hier, got '$_mode'" }
    set _flat [expr {$_mode eq "flat" && [llength $blocks] > 0}]
    set _desc [expr {$_flat ? [hier_descendants $design_name] : {}}]
    foreach _l [oss_lib_set_files $::LIB_SET] { read_liberty $_l }
    foreach _l [oss_memory_libs $::LIB_SET] { read_liberty $_l }
    if {[oss_has_memories]} {
        handle_warning "memory macros timed at [dict get [oss_get tech memory,lib_set_map] $::LIB_SET] (scenario lib set $::LIB_SET; tech(memory,lib_set_map)) — PVT mismatch"
    }
    if {$_flat} {
        foreach _b $_desc { read_verilog [oss_get tech block,$_b,netlist] }
        handle_info "flat STA: netlists of [join $_desc {, }]"
    } else {
        foreach _b $blocks { read_liberty [hier_block_lib [hier_block_views $_b] $_b $::LIB_SET] }
    }
    set _nl [lindex [glob -nocomplain "$::NETLIST_DIR/${design_name}.pt.v" "$::NETLIST_DIR/${design_name}.v"] 0]
    if {$_nl eq ""} { error "netlist not staged in $::NETLIST_DIR (expected ${design_name}.pt.v or ${design_name}.v)" }
    read_verilog $_nl
    link_design $design_name
    read_sdc $::SDC_FILE
    set_propagated_clock [all_clocks]
    if {$::SPEF_FILE ne "" && [file exists $::SPEF_FILE]} {
        read_spef $::SPEF_FILE
    } elseif {[is_true [oss_get sta oss,allow_no_spef]]} {
        handle_warning "no SPEF for $::RC_CORNER — timing with wire-load estimates only (sta(oss,allow_no_spef) true)"
    } else {
        error "no SPEF for $::RC_CORNER ($::SPEF_FILE) — set sta(oss,allow_no_spef) true to time without parasitics"
    }
    # flat: each descendant's SPEF (scenario RC corner) onto every instance of it
    foreach _b $_desc {
        set _k "block,$_b,spef,$::RC_CORNER"
        if {![info exists ::tech($_k)]} {
            error "flat STA: no SPEF tech($_k) in the library tag (block $_b has: [oss_get tech block,$_b,spef_corners]) — re-release $_b with $::RC_CORNER extraction, then library-manager add"
        }
        foreach _c [get_cells -hierarchical -filter "ref_name == $_b"] {
            read_spef -path [get_full_name $_c] $::tech($_k)
            handle_info "flat STA: [get_full_name $_c] <- [file tail $::tech($_k)]"
        }
    }
}

# No operation step: OpenSTA times on demand — the reports below are the analysis.

# Reports: setup / hold, DRV, don't-use / don't-touch, path groups, power,
# scenario QoR (read by merge_reports)
flow_proc report {
    file mkdir $::SCEN_REPORTS
    set _n [oss_get sta oss,report,group_path_count]
    report_checks -path_delay max -group_path_count $_n -format full_clock_expanded > "$::SCEN_REPORTS/setup.rpt"
    report_checks -path_delay min -group_path_count $_n -format full_clock_expanded > "$::SCEN_REPORTS/hold.rpt"
    # Electrical rules: tran / cap limits from the libraries, fanout limit
    # from sta(oss,drv,max_fanout). drv.rpt = worst pin per check (limit,
    # value, slack) then every violator.
    set_max_fanout [oss_get sta oss,drv,max_fanout] [current_design]
    report_check_types -max_slew -max_capacitance -max_fanout > "$::SCEN_REPORTS/drv.rpt"
    report_check_types -max_slew -max_capacitance -max_fanout -violators >> "$::SCEN_REPORTS/drv.rpt"
    # Netlist rules: don't-use cells (tech(<track>,<sta(oss,dont_use,tech_key)>))
    # and don't-touch instances (sta(oss,dont_touch,instances) patterns that
    # must still match) -> dont_use.rpt / dont_touch.rpt
    set _du [oss_trk [oss_get sta oss,dont_use,tech_key]]
    set _du_hits {}
    foreach _c [get_cells -hierarchical *] {
        set _ref [get_property $_c ref_name]
        foreach _p $_du { if {[string match $_p $_ref]} { lappend _du_hits [list [get_full_name $_c] $_ref]; break } }
    }
    set _fh [open "$::SCEN_REPORTS/dont_use.rpt" w]
    puts $_fh "Don't-use cells (tech([oss_track],[oss_get sta oss,dont_use,tech_key])): $_du"
    puts $_fh "Instances using a don't-use cell: [llength $_du_hits]"
    foreach _h $_du_hits { puts $_fh [format "  %-50s %s" {*}$_h] }
    close $_fh
    set _dt [expr {[info exists ::sta(oss,dont_touch,instances)] ? $::sta(oss,dont_touch,instances) : [oss_get sta oss,dont_touch,instances]}]
    set _dt_missing {}; set _dt_n 0
    set _fh [open "$::SCEN_REPORTS/dont_touch.rpt" w]
    puts $_fh "Don't-touch instance patterns (sta(oss,dont_touch,instances)): [expr {[llength $_dt] ? $_dt : {none}}]"
    foreach _p $_dt {
        set _m [get_cells -hierarchical -quiet $_p]
        if {![llength $_m]} { lappend _dt_missing $_p; puts $_fh "  MISSING  $_p"; continue }
        foreach _c $_m { incr _dt_n; puts $_fh [format "  OK       %-50s %s" [get_full_name $_c] [get_property $_c ref_name]] }
    }
    puts $_fh "Patterns missing: [llength $_dt_missing]   Instances kept: $_dt_n"
    close $_fh
    # Parasitic annotation: every driven net must carry SPEF parasitics (flat
    # STA: the stitched block SPEFs too) -> parasitic_annotation.rpt. Drivers
    # of load-less nets (CTS dummy loads) are listed, not counted.
    sta::redirect_string_begin
    report_parasitic_annotation -report_unannotated
    set _pa [sta::redirect_string_end]
    set _pa_un {}; set _pa_part {}; set _pa_float {}; set _sec ""
    foreach _ln [split $_pa \n] {
        if {[regexp {Found \d+ unannotated drivers} $_ln]} { set _sec un; continue }
        if {[regexp {Found \d+ partially unannotated drivers} $_ln]} { set _sec part; continue }
        set _p [string trim $_ln]
        if {$_p eq "" || $_sec eq ""} continue
        set _net [get_nets -quiet -of_objects [get_pins -quiet $_p]]
        set _loads [expr {$_net eq "" ? {} : [get_pins -quiet -of_objects $_net -filter "direction == input"]}]
        if {$_net ne "" && [llength $_loads] == 0 && [llength [get_ports -quiet -of_objects $_net]] == 0} {
            lappend _pa_float $_p
        } elseif {$_sec eq "un"} { lappend _pa_un $_p } else { lappend _pa_part $_p }
    }
    set _fh [open "$::SCEN_REPORTS/parasitic_annotation.rpt" w]
    puts $_fh "Parasitic annotation ($::SCENARIO, RC corner $::RC_CORNER)"
    puts $_fh "Unannotated nets : [llength $_pa_un]"
    puts $_fh "Partially annotated nets : [llength $_pa_part]"
    puts $_fh "Load-less nets (not counted) : [llength $_pa_float]"
    foreach {_t _l} [list UNANNOTATED $_pa_un PARTIAL $_pa_part LOADLESS $_pa_float] {
        foreach _p $_l { puts $_fh [format "  %-11s %s" $_t $_p] }
    }
    puts $_fh "\n# report_parasitic_annotation -report_unannotated\n$_pa"
    close $_fh
    # Path-group timing (R2R / I2R / R2O / I2O ...): timing_<setup|hold>_<group>.rpt
    set _grp [lindex [oss_group_timing {} "$::SCEN_REPORTS/timing"] 1]
    set _fh [open "$::SCEN_REPORTS/[oss_get sta oss,scenario_qor_file]" w]
    puts $_fh "set qor(scenario) \"$::SCENARIO\""
    puts $_fh "set qor(wns_setup) [sta::worst_slack -max]"
    puts $_fh "set qor(wns_hold) [sta::worst_slack -min]"
    puts $_fh "set qor(tns_setup) [sta::total_negative_slack -max]"
    puts $_fh "set qor(tns_hold) [sta::total_negative_slack -min]"
    puts $_fh "set qor(nvp_setup) [oss_nvp max]"
    puts $_fh "set qor(nvp_hold) [oss_nvp min]"
    puts $_fh "set qor(max_tran_violations) [sta::max_slew_violation_count]"
    puts $_fh "set qor(max_cap_violations) [sta::max_capacitance_violation_count]"
    puts $_fh "set qor(max_fanout_violations) [sta::max_fanout_violation_count]"
    puts $_fh "set qor(dont_use_cells) [llength $_du_hits]"
    puts $_fh "set qor(dont_touch_missing) [llength $_dt_missing]"
    puts $_fh "set qor(dont_touch_instances) $_dt_n"
    puts $_fh "set qor(parasitic_unannotated) [llength $_pa_un]"
    puts $_fh "set qor(parasitic_partial) [llength $_pa_part]"
    puts $_fh [list set qor(path_groups) $_grp]
    # Worst margin per check (limit - value; negative = violation)
    foreach {_k _c} {tran_slack max_slew_check_slack cap_slack max_capacitance_check_slack
                     fanout_slack max_fanout_check_slack} {
        if {[catch {sta::$_c} _v] || ![string is double -strict $_v] || abs($_v) > 1e20} { set _v "N/A" }
        puts $_fh "set qor($_k) \"$_v\""
    }
    # Power (sta(oss,report_power)): report_power on this scenario's corner;
    # the Total row (internal switching leakage total, W) goes into the QoR.
    if {[is_true [oss_get sta oss,report_power]]} {
        report_power > "$::SCEN_REPORTS/power.rpt"
        set _pfh [open "$::SCEN_REPORTS/power.rpt"]; set _pt [read $_pfh]; close $_pfh
        if {![regexp -line {^Total\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $_pt -> _int _sw _lk _tot]} {
            error "no Total row in $::SCEN_REPORTS/power.rpt"
        }
        puts $_fh "set qor(power_internal) $_int\nset qor(power_switching) $_sw\nset qor(power_leakage) $_lk\nset qor(power_total) $_tot"
    }
    close $_fh
    puts "QOR $::SCENARIO: wns_setup=[sta::worst_slack -max] wns_hold=[sta::worst_slack -min]"
}

# No save step: a timing scenario writes no design data (merge_reports
# publishes the summary to outputs/).

flow_exec_all
exit
