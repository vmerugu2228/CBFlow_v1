#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow LSF Configuration — RTL
# Queue tiers, bsub, xterm and module settings are site-wide and live in one
# file, PD/config/flow/<ver>/lsf_config.tcl (read as text by run_cmd.py and
# the static checks there) — the RTL flows source it.
# ═══════════════════════════════════════════════════════════════════════════════
set _flow_cfg_dir [file dirname [file normalize [info script]]]   ;# <root>/RTL/config/flow/<ver>
source [file join [file dirname [file dirname [file dirname [file dirname $_flow_cfg_dir]]]] \
    PD config flow [file tail $_flow_cfg_dir] lsf_config.tcl]
unset _flow_cfg_dir
