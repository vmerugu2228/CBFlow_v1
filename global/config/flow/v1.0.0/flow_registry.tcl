#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Flow Registry — cross-discipline flow catalog
#
# Authoritative source for:
#   · flow(types)        — every flow known to the framework (PD + DFT + DV)
#   · flow(disciplines)  — top-level tree names
#   · flow(discipline,*) — per-flow → discipline mapping
#
# Consumed by:
#   · Every discipline's flow_config.tcl (PD/DFT/DV) at source-time — the
#     discipline appends only its mandatory_vars, not the flow catalog itself
#   · Python-side race_engine._build_command() for handler routing
#   · flow_cmd.py for `cbflow flow types [--domain PD|DFT|DV]` grouping
#   · config_validator to fail-fast on unmapped flows
#
# Every entry in flow(types) MUST also have flow(discipline,<name>) below.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Flow Types (union of every discipline) ────────────────────────────────────
set flow(types) {
    SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR
    DFT_INSERT_PASS1 DFT_INSERT_PASS2 DFT_INSERT_PASS3
    SCAN_INSERT ATPG GLS_FUNC GLS_SCAN_MBIST
    SPEC_RAMP PLANNING TB_SETUP M1_EXEC M2_EXEC M3_EXEC M4_EXEC
    ECO_EXEC DV_SIGNOFF
    RTL_SPEC RTL_LINT RTL_CDC RTL_RDC UPF_CHECK
}

# ── Discipline Roster ─────────────────────────────────────────────────────────
# Names match the top-level directory: $CBFLOW_ROOT/<name>. Each discipline
# owns its cmds/, node_configs/, tool_launch_config, etc. The launcher exports
# CBFLOW_<UPPER>_DIR for each when the directory exists.
set flow(disciplines) {PD DFT DV RTL}

# Directory-name for each discipline (used by paths.get_node_config_path()).
set flow(discipline_dir,PD)  "PD"
set flow(discipline_dir,DFT) "DFT"
set flow(discipline_dir,DV)  "DV"
set flow(discipline_dir,RTL) "RTL"

# ── Per-Flow → Discipline Map ─────────────────────────────────────────────────
# PD — Physical Design (implementation → tapeout)
set flow(discipline,SYNTH)          "PD"
set flow(discipline,FP)             "PD"
set flow(discipline,FCFP)           "PD"
set flow(discipline,PNR)            "PD"
set flow(discipline,SYNTH_PNR)      "PD"
set flow(discipline,STA)            "PD"
set flow(discipline,LEC)            "PD"
set flow(discipline,CLP)            "PD"
set flow(discipline,PV)             "PD"
set flow(discipline,EMIR)           "PD"
set flow(discipline,POPT)           "PD"
set flow(discipline,ECO)            "PD"

# DFT — Design-For-Test (scan, ATPG, GLS)
# DFT_INSERT is split into three sequential passes (per owner spreadsheet
# DFT_FLOW_Dependencies_Input_Output.xlsx): Pass1=Core (MBIST+BSCAN),
# Pass2=Top (TDR/DFT-Signals/SRI), Pass3=EDT+OCC. Each pass is releasable
# and surfaces independently in the dashboard so per-pass owners can
# track their own work.
set flow(discipline,DFT_INSERT_PASS1) "DFT"
set flow(discipline,DFT_INSERT_PASS2) "DFT"
set flow(discipline,DFT_INSERT_PASS3) "DFT"
set flow(discipline,SCAN_INSERT)      "DFT"
set flow(discipline,ATPG)             "DFT"
set flow(discipline,GLS_FUNC)         "DFT"
set flow(discipline,GLS_SCAN_MBIST)   "DFT"

# DV — Verification milestone / review flows
set flow(discipline,SPEC_RAMP)      "DV"
set flow(discipline,PLANNING)       "DV"
set flow(discipline,TB_SETUP)       "DV"
set flow(discipline,M1_EXEC)        "DV"
set flow(discipline,M2_EXEC)        "DV"
set flow(discipline,M3_EXEC)        "DV"
set flow(discipline,M4_EXEC)        "DV"
set flow(discipline,ECO_EXEC)       "DV"
set flow(discipline,DV_SIGNOFF)     "DV"

# RTL — Register-Transfer-Level design-side quality flows
# Static checks on the RTL before synthesis/implementation: lint rules,
# clock-domain crossings, reset-domain crossings, UPF intent. Complements
# DV (dynamic verification) and PD (implementation) with pre-impl gates
# that can block tapeout if left unresolved.
set flow(discipline,RTL_SPEC)       "RTL"
set flow(discipline,RTL_LINT)       "RTL"
set flow(discipline,RTL_CDC)        "RTL"
set flow(discipline,RTL_RDC)        "RTL"
set flow(discipline,UPF_CHECK)      "RTL"

# ── Descriptions — sourced from adjacent descriptions_config.tcl ──────────────
# Kept in a separate file for edit-cadence (descriptions change often; the
# registry is stable). The load path below tolerates the case where the
# registry is sourced standalone (e.g. by a Python test harness) without
# descriptions.
set _desc_path [file join [file dirname [info script]] descriptions_config.tcl]
if {[file exists $_desc_path]} {
    source $_desc_path
}
unset -nocomplain _desc_path

# ══════════════════════════════════════════════════════════════════════════════
#                    CROSS-DOMAIN RUNTIME DEFAULTS
# Every discipline (PD, DFT, DV) inherits these. Each discipline's
# flow_config.tcl is sourced INSTEAD of (not on top of) another discipline's,
# so cross-cutting defaults MUST live here to reach all three.
# ══════════════════════════════════════════════════════════════════════════════

# ── Cross-domain mandatory keys ─────────────────────────────────────────────
# Set by user_config or workspace create; validated pre-flight for every flow.
set flow(mandatory_vars,all) {flow(run_name) flow(type) flow(design_name)}

# ── Runtime defaults ────────────────────────────────────────────────────────
# Guarded sets — if the cascade is ever reordered so user_config /
# flow_config loads BEFORE this registry, the bare `set` form would
# silently clobber the user's values. `info exists` guards keep the
# defaults as defaults — the first writer wins.
proc _registry_default {name value} {
    if {![info exists ::$name]} { set ::$name $value }
}
# Scalar flow(...) defaults — paths with parens need the array-aware
# info exists form.
if {![info exists flow(run_name)]}           { set flow(run_name)      "" }
if {![info exists flow(design_name)]}        { set flow(design_name)   "" }
if {![info exists flow(run_type)]}           { set flow(run_type)      "" }
if {![info exists flow(run_types)]}          { set flow(run_types)     {hier flat} }
if {![info exists flow(test_mode)]}          { set flow(test_mode)     "false" }

# ── Dispatcher ──────────────────────────────────────────────────────────────
if {![info exists flow(dispatcher)]}            { set flow(dispatcher)    "race" }
if {![info exists flow(use_lsf)]}               { set flow(use_lsf)       false }
if {![info exists flow(use_xterm)]}             { set flow(use_xterm)     true }
if {![info exists flow(cbflow_version)]}        { set flow(cbflow_version) "2.0.0" }
if {![info exists flow(dashboard,default_port)]} { set flow(dashboard,default_port) 0 }
# Max jobs the RACE engine runs concurrently when several are ready at once
# (local thread pool). 0 = unlimited (one worker per ready job).
if {![info exists flow(max_parallel_jobs)]}     { set flow(max_parallel_jobs) 0 }

# ── Project setup ───────────────────────────────────────────────────────────
# Flows offered as the "common" selection (and the fallback when nothing is
# selected) by `cbflow flow project` interactive flow selection.
if {![info exists flow(common_flows)]}          { set flow(common_flows) {SYNTH FP PNR STA LEC PV} }

# ── SmartGrid (project dashboard) ───────────────────────────────────────────
# Read by global/utils/project_dashboard/ via core.registry (plain `set`, one
# key per line — no fallbacks in code: a missing key is an error or an
# explicit "not configured" note on the page).
#
# Daemon: per-user × per-project port = port_base + hash(uid:project) % port_span
# (stays clear of the run-dashboard bands 9000-9999 / 20000-24999); default
# bind address (--bind-addr overrides it); per-user state dir (~ expanded).
set flow(smartgrid,port_base)  25000
set flow(smartgrid,port_span)  2500
set flow(smartgrid,bind_addr)  "127.0.0.1"
set flow(smartgrid,state_dir)  "~/.cbflow/project-dashboard"
#
# Discipline accent colours: flow(discipline_color,<DISC>) in the run
# dashboard block below (shared by SmartGrid).
#
# Discipline summary "Top metrics" tiles — metric names as published
# (metrics.rpt / RACE metrics_snapshot), in display order.
set flow(dashboard,top_metrics,PD)  {{Setup WNS} {Setup TNS} {Hold WNS} Utilization {DRC violations} {Clock skew ps}}
set flow(dashboard,top_metrics,DFT) {fault_coverage_pct test_coverage_pct atpg_eff_pct pattern_count mbist_controller_count drc_violation_count}
set flow(dashboard,top_metrics,DV)  {coverage_pct bins_hit bins_total uvm_errors}
#
# Published-run "by stage" tables: {title {metric categories} ...} — the
# categories listed under one title share one Stage x metrics table; a
# category not listed is not shown as a stage table.
set flow(dashboard,stage_tables) {{Design & timing} {design timing clock} Routing {routing} Power {power}}
#
# Metric polarity — which value is the worse QoR point when one publish has
# several rows of the same metric (scenarios / corners). higher_better: the
# smaller value is worse; lower_better: the larger value is worse. Metrics
# without a polarity tie-break on (scenario, corner).
set flow(metric,WNS,polarity)                    "higher_better"
set flow(metric,TNS,polarity)                    "higher_better"
set flow(metric,fault_coverage_pct,polarity)     "higher_better"
set flow(metric,test_coverage_pct,polarity)      "higher_better"
set flow(metric,atpg_eff_pct,polarity)           "higher_better"
set flow(metric,coverage_pct,polarity)           "higher_better"
set flow(metric,mbist_controller_count,polarity) "higher_better"
set flow(metric,drc_count,polarity)              "lower_better"
set flow(metric,lvs_errors,polarity)             "lower_better"
set flow(metric,uvm_errors,polarity)             "lower_better"
set flow(metric,drc_violation_count,polarity)    "lower_better"
#
# Published-run detail page: metric category → tab (routing / timing /
# signoff; anything unmapped lands under "Other metrics"). A category that
# contains a timing-tab category name also goes to timing, as does a metric
# whose upper-cased name contains one of timing_name_tokens.
set flow(dashboard,category_tab,routing)    "routing"
set flow(dashboard,category_tab,congestion) "routing"
set flow(dashboard,category_tab,timing)     "timing"
set flow(dashboard,category_tab,power)      "signoff"
set flow(dashboard,category_tab,em)         "signoff"
set flow(dashboard,category_tab,ir)         "signoff"
set flow(dashboard,category_tab,signoff)    "signoff"
set flow(dashboard,category_tab,drc)        "signoff"
set flow(dashboard,category_tab,lvs)        "signoff"
set flow(dashboard,timing_name_tokens)      {WNS TNS HOLD SETUP SLACK FMAX FREQ}
#
# Floorplan snapshot: LEF paths are swept from the resolved config.tcl of the
# run's node of this node type (node_configs node_types,<node>).
set flow(dashboard,lef_node_type)           "init_design"
# SmartGrid floorplan payload: byte budget for the interactive cell layer
# (JSON). Std cells are sampled down to fit; hard macros are always kept and
# the density overview counts every cell. Bounds the publish message and the
# page download for designs with long hierarchical instance names.
set flow(dashboard,floorplan_cells_max_bytes) 12000000
# Signoff flows: they release the exit they verify (beside the
# implementation flow's release of it). The release page counts them per exit
# against release_tags(<exit>) required_flows; the rest of an exit's
# required_flows are its implementation alternatives (any one releases it).
set flow(release,signoff_flows) {STA PV LEC CLP EMIR ECO POPT}

# ── Flow Mode ───────────────────────────────────────────────────────────────
if {![info exists flow(mode)]}                  { set flow(mode)                  "default" }
if {![info exists flow(merged,flows)]}          { set flow(merged,flows)          "SYNTH_PNR" }
if {![info exists flow(merged,fp_independent)]} { set flow(merged,fp_independent) true }
if {![info exists flow(merged,pnr_depends_fp)]} { set flow(merged,pnr_depends_fp) true }

# ── RACE Database ───────────────────────────────────────────────────────────
if {![info exists flow(race,db_max_sessions)]}  { set flow(race,db_max_sessions)  10 }
# `cbflow run db-manage status` warns at db_max_sessions × db_warn_ratio.
if {![info exists flow(race,db_warn_ratio)]}    { set flow(race,db_warn_ratio)    0.8 }

# ── MMMC ────────────────────────────────────────────────────────────────────
# MMMC is a PD concept (STA/PNR scenarios), but the global default lives here
# so the resolver has something to emit for DFT/DV runs too — they set it to
# false in their own flow_config if it's truly not applicable.
if {![info exists flow(mmmc,enabled)]}         { set flow(mmmc,enabled)        true }
if {![info exists flow(mmmc,enabled_stages)]}  { set flow(mmmc,enabled_stages) {place cts cts_opt route pro signoff} }

# ── Milestones ──────────────────────────────────────────────────────────────
# PD milestones — DFT and DV will declare their own via flow(exit_milestones,DFT)
# / flow(exit_milestones,DV) as those phases mature.
if {![info exists flow(exit_milestones)]} { set flow(exit_milestones) {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO} }

# ── File-Validation Rules ───────────────────────────────────────────────────
# Type → allowed extensions. Consumed by validate_run + inputs handlers.
array set FILE_VALIDATION_RULES {
    RTL     {".v" ".vg" ".sv" ".svh"}
    NETLIST {".v" ".vg" ".sv"}
    SDC     {".sdc"}
    DEF     {".def"}
    SPEF    {".spef"}
    LIB     {".lib"}
    LEF     {".lef"}
    GDS     {".gds" ".gdsii"}
    SDF     {".sdf"}
}

set flow(valid_status) {NOTRUN RUNNING COMPLETE ERROR WARNING SKIPPED RETRACED}
set flow(status_file)  ".run.status"

# ══════════════════════════════════════════════════════════════════════════════
#                    RUN DASHBOARD (global/utils/dashboard)
# Read by dashboard/dash_config.py through core.registry, which parses this file
# (it is not sourced) — keep every entry a plain one-line `set`, with comments
# on their own lines. Values below are the ones the dashboard used to hardcode.
# ══════════════════════════════════════════════════════════════════════════════

# Discipline used by `cbflow dashboard …` commands that name none.
set flow(dashboard,default_discipline) "PD"

# Per-user discipline daemon: port = port_base,<DISC> + (uid % port_width).
set flow(dashboard,port_base,PD)  9000
set flow(dashboard,port_base,DFT) 9300
set flow(dashboard,port_base,DV)  9600
set flow(dashboard,port_base,RTL) 9900
set flow(dashboard,port_width)    300

# Per-project daemon: port = project_port_base,<DISC> + (hash(uid,project) % width).
set flow(dashboard,project_port_base,PD)  20000
set flow(dashboard,project_port_base,DFT) 21000
set flow(dashboard,project_port_base,DV)  22000
set flow(dashboard,project_port_base,RTL) 23000
set flow(dashboard,project_port_width)    1000

# Per-run foreground dashboard (`cbflow run gui` without the daemon):
# port = run_port_min + (hash(run_dir) % span). Kept clear of the daemon
# bands above (9000-10199, 20000-23999) and SmartGrid (25000-27499).
set flow(dashboard,run_port_min) 30000
set flow(dashboard,run_port_max) 59999

# Project/run browser (dashboard/app.py, `cbflow flow dashboard start`).
set flow(dashboard,app_port_min) 8080
set flow(dashboard,app_port_max) 8999

# Browser polling cadence in milliseconds.
#   poll_ms                  fixed interval (daemon index page; fallback when
#                            the adaptive helper is unavailable)
#   poll_active_ms / idle_ms adaptive cadence while a run is active / idle
#   poll_error_ms            back-off after a failed poll
#   poll_active_ms,run_view  active cadence of the main flow view
set flow(dashboard,poll_ms)                 5000
set flow(dashboard,poll_active_ms)          3000
set flow(dashboard,poll_idle_ms)            10000
set flow(dashboard,poll_error_ms)           15000
set flow(dashboard,poll_active_ms,run_view) 2000

# Discipline branding: pill background / pill border / index banner gradient.
# RTL mirrors PD until the RTL team picks its own palette.
set flow(discipline_color,PD)         "#1565c0"
set flow(discipline_color_border,PD)  "#0d47a1"
set flow(discipline_banner,PD)        "linear-gradient(135deg, #4f46e5 0%, #7c3aed 50%, #0ea5e9 100%)"
set flow(discipline_color,DFT)        "#0d9488"
set flow(discipline_color_border,DFT) "#0f766e"
set flow(discipline_banner,DFT)       "linear-gradient(135deg, #0d9488 0%, #0ea5e9 55%, #6366f1 100%)"
set flow(discipline_color,DV)         "#be185d"
set flow(discipline_color_border,DV)  "#9f1239"
set flow(discipline_banner,DV)        "linear-gradient(135deg, #be185d 0%, #a21caf 55%, #6366f1 100%)"
set flow(discipline_color,RTL)        "#1565c0"
set flow(discipline_color_border,RTL) "#0d47a1"
set flow(discipline_banner,RTL)       "linear-gradient(135deg, #4f46e5 0%, #7c3aed 50%, #0ea5e9 100%)"

# Flow badge colour per flow (every entry of flow(types)).
set flow(color,SYNTH)            "#7c3aed"
set flow(color,SYNTH_PNR)        "#6366f1"
set flow(color,PNR)              "#0ea5e9"
set flow(color,FP)               "#06b6d4"
set flow(color,FCFP)             "#0891b2"
set flow(color,STA)              "#10b981"
set flow(color,LEC)              "#f59e0b"
set flow(color,CLP)              "#f97316"
set flow(color,PV)               "#ef4444"
set flow(color,EMIR)             "#dc2626"
set flow(color,POPT)             "#8b5cf6"
set flow(color,ECO)              "#64748b"
set flow(color,DFT_INSERT_PASS1) "#475569"
set flow(color,DFT_INSERT_PASS2) "#475569"
set flow(color,DFT_INSERT_PASS3) "#475569"
set flow(color,SCAN_INSERT)      "#475569"
set flow(color,ATPG)             "#475569"
set flow(color,GLS_FUNC)         "#475569"
set flow(color,GLS_SCAN_MBIST)   "#475569"
set flow(color,SPEC_RAMP)        "#475569"
set flow(color,PLANNING)         "#475569"
set flow(color,TB_SETUP)         "#475569"
set flow(color,M1_EXEC)          "#475569"
set flow(color,M2_EXEC)          "#475569"
set flow(color,M3_EXEC)          "#475569"
set flow(color,M4_EXEC)          "#475569"
set flow(color,ECO_EXEC)         "#475569"
set flow(color,DV_SIGNOFF)       "#475569"
set flow(color,RTL_SPEC)         "#475569"
set flow(color,RTL_LINT)         "#475569"
set flow(color,RTL_CDC)          "#475569"
set flow(color,RTL_RDC)          "#475569"
set flow(color,UPF_CHECK)        "#475569"
# Badge colour for a run whose flow_type is missing or not in flow(types).
set flow(dashboard,unknown_flow_color) "#475569"

# ── Report number format ──────────────────────────────────────────────────────
# Digits after the decimal point for slack (WNS / TNS) in every report the
# flows write and every page SmartGrid renders (cbflow_fmt_slack /
# dash_config.fmt_slack).
set flow(report,slack_digits) 3
