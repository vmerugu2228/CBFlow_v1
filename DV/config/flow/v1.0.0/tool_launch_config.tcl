#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow DV Tool Launch Configuration
#
# Tool shells for the DV flows (SPEC_RAMP … DV_SIGNOFF). Sourced by the DV
# subnode handlers ($CONFIG_ROOT = DV/config) and by the config resolver.
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Tool Shell Commands ────────────────────────────────────────────────────┐
# Review gates (vendor generic, tool review) run on the host tclsh.
set lsf(tool_shell,review)       "tclsh"
set lsf(tool_flags,review)       [list "" ""]

# Open-source (vendor "opensource"): verilator (SV-UVM simulation, coverage),
# rtlcheck (sby formal), vplan (verification plan) in the CBflow tool
# container — shared with PD / DFT (global/config/flow/<ver>/oss_launch_config.tcl).
set _flow_cfg_dir [file dirname [file normalize [info script]]]   ;# <root>/DV/config/flow/<ver>
source [file join [file dirname [file dirname [file dirname [file dirname $_flow_cfg_dir]]]] \
    global config flow [file tail $_flow_cfg_dir] oss_launch_config.tcl]
unset _flow_cfg_dir

# ┌─ Tool Short Names (dashboard DAG node labels) ───────────────────────────┐
set lsf(tool_short,review)       "REV"
set lsf(tool_short,verilator)    "VLT"
set lsf(tool_short,vplan)        "PLAN"

# ┌─ Wrapper Shell ──────────────────────────────────────────────────────────┐
set lsf(tool_wrapper_shell)     "/bin/csh -f"
