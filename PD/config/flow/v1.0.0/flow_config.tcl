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

# ┌─ Flow Catalog + Discipline Map ─────────────────────────────────────────────┐
# Sourced from the global flow_registry.tcl — cross-discipline catalog and
# discipline mapping live in ONE place (global/config/flow/v1.0.0/) so DFT
# and DV configs don't have to duplicate them.
#
# Sets: flow(types), flow(disciplines), flow(discipline,*), flow(discipline_dir,*).
# Also sources descriptions_config.tcl (arrays flow_descriptions,
# phase_descriptions, run_type_descriptions).
#
# During Phase 1-2 the global path was a symlink to this dir; from Phase 3
# forward it's a real file. Fail-hard if it's missing — the framework needs
# the catalog before anything else runs.
set flow(type) ""                                                         ;# Mandatory — set in user_config
if {[info exists ::env(CBFLOW_GLOBAL_DIR)] && [file isdirectory "$::env(CBFLOW_GLOBAL_DIR)/config"]} {
    set _global_root "$::env(CBFLOW_GLOBAL_DIR)/config"
} elseif {[info exists ::env(CBFLOW_ROOT)] && [file isdirectory "$::env(CBFLOW_ROOT)/global/config"]} {
    set _global_root "$::env(CBFLOW_ROOT)/global/config"
} else {
    set _global_root ""
}
set _flow_ver [expr {[info exists ::env(FLOW_CONFIG_VERSION)] ? $::env(FLOW_CONFIG_VERSION) : "v1.0.0"}]
if {$_global_root ne ""} {
    set _reg "$_global_root/flow/$_flow_ver/flow_registry.tcl"
    if {[file exists $_reg]} {
        source $_reg
    } else {
        puts stderr "ERROR: global flow_registry.tcl not found: $_reg"
        exit 1
    }
} else {
    puts stderr "ERROR: CBFLOW_GLOBAL_DIR / CBFLOW_ROOT/global not set — cannot locate flow_registry.tcl"
    exit 1
}
unset -nocomplain _reg _global_root _flow_ver

# ┌─ PD-specific mandatory_vars ────────────────────────────────────────────────┐
# Cross-domain flow runtime defaults (run_name, run_type, test_mode, dispatcher,
# use_lsf, use_xterm, cbflow_version, mode, merged,*, race,*, mmmc,*,
# exit_milestones, valid_status, status_file, FILE_VALIDATION_RULES) live in
# the global flow_registry.tcl (sourced above). This file only appends what's
# PD-specific: mandatory tool selection per PD flow.
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
    # Missing node_config is legitimate for cross-discipline flows registered
    # in flow_registry.tcl but not yet implemented in PD (e.g. LINT/CDC/SIM
    # under DV, or DFT flows during pre-Phase-5 migration). Emit a diagnostic
    # and continue — the caller will see empty stages, which discovery
    # commands (`cbflow flow types`) handle fine. An actual `cbflow run`
    # against such a flow will fail later at DAG build with a clearer error.
    puts stderr "WARN: node_config not found for flow=$current_flow_type — expected $flow_config_file"
    set _disc "unknown"
    if {[info exists flow(discipline,$current_flow_type)]} {
        set _disc $flow(discipline,$current_flow_type)
    }
    puts stderr "      (discipline=$_disc — file will be added when discipline scaffolding lands)"
    unset -nocomplain _disc
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SECTION 4: DESCRIPTIONS                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# flow_descriptions / phase_descriptions / run_type_descriptions were sourced
# here from a local descriptions_config.tcl. That file moved to global/
# alongside flow_registry.tcl in Phase 3 — the registry sources it at the top
# of this file, so there is nothing to source here.
