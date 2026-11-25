#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow RTL Tool Launch Configuration
#
# Tool shells for the RTL flows (RTL_SPEC, RTL_LINT, RTL_CDC, RTL_RDC,
# UPF_CHECK). Sourced by the RTL subnode handlers ($CONFIG_ROOT = RTL/config)
# and by the config resolver.
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Tool Shell Commands ────────────────────────────────────────────────────┐
# Commercial (Synopsys Spyglass / VC-LP, Cadence Jaspergold / Conformal LP)
set lsf(tool_shell,spyglass)     "spyglass"
set lsf(tool_shell,jaspergold)   "jg"
set lsf(tool_shell,vc_lp)        "vc_lp_shell"
set lsf(tool_shell,conformal_lp) "conformal_lp"

# Open-source (vendor "opensource"): verilator / rtlcheck run in the CBflow
# tool container — shell, image and tools dir shared with PD / DFT
# (global/config/flow/<ver>/oss_launch_config.tcl).
set _flow_cfg_dir [file dirname [file normalize [info script]]]   ;# <root>/RTL/config/flow/<ver>
source [file join [file dirname [file dirname [file dirname [file dirname $_flow_cfg_dir]]]] \
    global config flow [file tail $_flow_cfg_dir] oss_launch_config.tcl]
unset _flow_cfg_dir

# ┌─ Tool Short Names (dashboard DAG node labels) ───────────────────────────┐
set lsf(tool_short,spyglass)     "SG"
set lsf(tool_short,jaspergold)   "JG"
set lsf(tool_short,verilator)    "VLT"
set lsf(tool_short,rtlcheck)     "RTLC"

# ┌─ Wrapper Shell ──────────────────────────────────────────────────────────┐
set lsf(tool_wrapper_shell)     "/bin/csh -f"
