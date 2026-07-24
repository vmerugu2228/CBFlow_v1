#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          CBflow Flow Configuration                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Resolve config directory (handles symlinks) ──
set script_path [info script]
if {[file type $script_path] eq "link"} {
    set script_path [file readlink $script_path]
    if {[file pathtype $script_path] ne "absolute"} {
        set script_path [file join [file dirname [info script]] $script_path]
    }
}
set config_dir [file dirname $script_path]

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SECTION 1: FLOW SETTINGS                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Flow Types ────────────────────────────────────────────────────────────────┐
set flow(type)      ""                                                    ;# Mandatory — set in user_config
set flow(types)     {SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR DFT_INSERT SCAN_INSERT ATPG GLS_FUNC GLS_SCAN_MBIST}

# ┌─ Flow Runtime ──────────────────────────────────────────────────────────────┐
set flow(run_name)      ""                                                ;# Mandatory — set in user_config
set flow(design_name)   ""                                                ;# Mandatory — set in user_config
set flow(run_type)      ""                                                ;# Mandatory — "hier" or "flat"
set flow(run_types)     {hier flat}
set flow(test_mode)     "false"                                           ;# Bypass EDA tools, show commands only
set flow(mandatory_vars,all) {flow(run_name) flow(type) flow(design_name)}

# Per-flow mandatory keys. Validated pre-flight by config_validator.py after
# the cascade resolves — a missing/empty key here fails `cbflow run` and
# `cbflow workspace validate` before any work/ directory is created.
# Keep this list to genuine cross-cutting invariants (tool selection). Stage-
# specific inputs are validated by resolve_inputs / enhanced_validate_run.
#
# Naming convention: the resolver emits keys of the *current flow's* array
# WITHOUT the array-name prefix (e.g. `default_tool=pt`, not `sta(default_tool)=pt`).
# List them here in the emission form, i.e. bare `default_tool`, not
# `sta(default_tool)`. Cross-flow keys (`flow(...)`) keep their prefix.
set flow(mandatory_vars,SYNTH)      {default_tool}
set flow(mandatory_vars,PNR)        {default_tool}
set flow(mandatory_vars,SYNTH_PNR)  {default_tool}
set flow(mandatory_vars,STA)        {default_tool}
set flow(mandatory_vars,FP)         {default_tool}
set flow(mandatory_vars,FCFP)       {default_tool}
set flow(mandatory_vars,LEC)        {default_tool}
set flow(mandatory_vars,CLP)        {default_tool}
set flow(mandatory_vars,PV)         {default_tool}
set flow(mandatory_vars,EMIR)       {default_tool}
set flow(mandatory_vars,ECO)        {default_tool}
set flow(mandatory_vars,POPT)       {default_tool}

# ┌─ Dispatcher ────────────────────────────────────────────────────────────────┐
set flow(dispatcher)    "race"                                            ;# "race" (RACE) or "make" (GNU Make)
set flow(use_lsf)       false                                             ;# Enable LSF job submission (set true in user_config when bsub available)
set flow(use_xterm)     true                                              ;# Launch EDA tools in xterm (set false for direct terminal execution)
set flow(cbflow_version) "2.0.0"                                          ;# Framework version — single source of truth
set flow(dashboard,default_port) 0                                        ;# 0 = auto-select free port (avoids multi-user conflicts)

# ┌─ Flow Mode ─────────────────────────────────────────────────────────────────┐
set flow(mode)                  "default"                                 ;# default | merged
set flow(merged,flows)          "SYNTH_PNR"
set flow(merged,fp_independent) true
set flow(merged,pnr_depends_fp) true

# ┌─ RACE Database ──────────────────────────────────────────────────────────────┐
set flow(race,db_max_sessions)  10                                        ;# Warning at 80%, error at 100%

# ┌─ MMMC ────────────────────────────────────────────────────────────────────┐
set flow(mmmc,enabled)        true
set flow(mmmc,enabled_stages) {place cts cts_opt route pro signoff}

# ┌─ Phases & Milestones ────────────────────────────────────────────────────┐
# Phases are project-specific — each project declares its own list via
# `project(phases)` and current phase via `project(current_phase)`. The old
# global `flow(phases)` has been removed. Exit milestones remain global.
set flow(exit_milestones) {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SECTION 2: VALIDATION RULES                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

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

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SECTION 3: FLOW TYPE RESOLUTION                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set current_flow_type ""
set _valid_flow_types $flow(types)

if {[info exists ::env(CBFLOW_FLOW_TYPE)]} {
    set current_flow_type $::env(CBFLOW_FLOW_TYPE)
}
if {$current_flow_type eq ""} {
    global argc argv
    if {[info exists argc] && [info exists argv] && $argc > 0} {
        foreach arg $argv {
            set _arg_upper [string toupper $arg]
            if {$_arg_upper in $_valid_flow_types} { set current_flow_type $_arg_upper; break }
        }
    }
}
if {$current_flow_type eq ""} {
    puts "ERROR: Flow type not defined. Set CBFLOW_FLOW_TYPE or pass as argument."
    puts "       Available: $_valid_flow_types"
    exit 1
}

set flow_config_file "$config_dir/node_configs/${current_flow_type}_config.tcl"
if {[file exists $flow_config_file]} {
    source $flow_config_file
} else {
    puts "ERROR: Flow config not found: $flow_config_file"
    puts "       Available: $_valid_flow_types"
    exit 1
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SECTION 4: DESCRIPTIONS                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

source "$config_dir/descriptions_config.tcl"
