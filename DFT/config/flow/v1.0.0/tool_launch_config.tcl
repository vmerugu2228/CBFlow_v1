#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow DFT Tool Launch Configuration
#
# Tool shells for the DFT flows (SCAN_INSERT, ATPG, GLS_FUNC, GLS_SCAN_MBIST,
# DFT_INSERT_PASS1/2/3). Sourced by the DFT subnode handlers
# ($CONFIG_ROOT = DFT/config) and by the config resolver.
# ═══════════════════════════════════════════════════════════════════════════════

# ┌─ Tool Shell Commands ────────────────────────────────────────────────────┐
# Commercial (Mentor Tessent, Synopsys DFT Compiler / TestMAX / VCS, Questa)
set lsf(tool_shell,tessent)      "tessent"
set lsf(tool_shell,dft_compiler) "dc_shell"
set lsf(tool_shell,testmax)      "tmax"
set lsf(tool_shell,vcs)          "vcs"
set lsf(tool_shell,questa)       "vsim"

# Open-source (vendor "opensource"): fault (SCAN_INSERT / ATPG) and iverilog
# (GLS) run in the CBflow tool container — shell, image and tools dir are
# shared with PD (global/config/flow/<ver>/oss_launch_config.tcl).
set _flow_cfg_dir [file dirname [file normalize [info script]]]   ;# <root>/DFT/config/flow/<ver>
source [file join [file dirname [file dirname [file dirname [file dirname $_flow_cfg_dir]]]] \
    global config flow [file tail $_flow_cfg_dir] oss_launch_config.tcl]
unset _flow_cfg_dir

# ┌─ Tool Short Names (dashboard DAG node labels "<node> [TSS]") ────────────┐
set lsf(tool_short,tessent)      "TSS"
set lsf(tool_short,dft_compiler) "DFTC"
set lsf(tool_short,testmax)      "TMAX"
set lsf(tool_short,fault)        "FAULT"
set lsf(tool_short,iverilog)     "IVL"

# ┌─ Wrapper Shell ──────────────────────────────────────────────────────────┐
set lsf(tool_wrapper_shell)     "/bin/csh -f"
