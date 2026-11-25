#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — Open-source tool container launch settings (cross-discipline)
#
# Sourced by each discipline's tool_launch_config.tcl (PD, DFT). Every
# open-source tool runs inside the CBflow tool container through
# global/bin/cbflow-oss, which takes `<tool> <cmd_file> <log_file>` and
# returns the tool's exit status.
# ═══════════════════════════════════════════════════════════════════════════════

set _cbflow_oss [expr {[info exists ::env(FLOW_DIR)] && [file exists "$::env(FLOW_DIR)/global/bin/cbflow-oss"]
                      ? "$::env(FLOW_DIR)/global/bin/cbflow-oss" : "cbflow-oss"}]
# PD: yosys openroad sta magic netgen klayout. DFT: fault (Fault suite +
# Atalanta + nl2bench) and iverilog (iverilog / vvp) — both run a Tcl driver
# under the container's tclsh, which execs the tools.
foreach _oss_tool {yosys openroad sta magic netgen klayout fault iverilog} {
    set lsf(tool_shell,$_oss_tool) "$_cbflow_oss $_oss_tool"
    set lsf(tool_flags,$_oss_tool) [list "" ""]
}
# Interactive sessions (cbflow run interactive): the container's interactive
# shell, the load script as its argument (no -f)
foreach _oss_tool {yosys openroad sta oss_tclsh} {
    set lsf(interactive,shell,$_oss_tool) "$_cbflow_oss interactive $_oss_tool"
    set lsf(interactive,load_flags,$_oss_tool) ""
}
# oss_tclsh: Tcl driver stages (GDS stream-out, release) run by the
# container's tclsh, so they can exec klayout/magic/netgen directly.
set lsf(tool_shell,oss_tclsh) "$_cbflow_oss tclsh"
set lsf(tool_flags,oss_tclsh) [list "" ""]
unset _oss_tool _cbflow_oss
# Container image (pinned by digest; IIC-OSIC-TOOLS, arm64 + amd64).
set lsf(oss,image) "hpretl/iic-osic-tools@sha256:306585de35d198e70ea58950f77147c86f56c698726a19afea9f1c83009557be"
# Tools built for the image that it does not ship (bin/ is mounted and put on
# the container PATH): atalanta (global/utils/oss/install_atalanta.sh).
set lsf(oss,tools_dir) "$::env(HOME)/eda/tools/oss"
