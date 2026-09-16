#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow dispatch smoke harness — directly exercises launch_utils::{generate_
# launch_wrapper, submit_job} with stubbed bsub + xterm + every EDA tool shell.
#
# Catches the class of bugs `test_mode=true` masks in the regular test suite:
# missing / corrupt `lsf(...)` config keys that the dispatch path reads but
# `handler_run` short-circuits past.
#
# Two-stage exercise:
#   1. generate_launch_wrapper(work_dir, stage, cmd_file, tool_name)
#        → reads lsf(tool_shell,<tool>), lsf(module,<tool>),
#          lsf(tool_wrapper_shell). Writes a wrapper .csh file.
#   2. submit_job(wrapper, flow, stage, node, work_dir)
#        → reads lsf(bsub,*), lsf(queue_types,<tier>,*), lsf(xterm,*),
#          lsf(flow_mapping,<flow>,<stage>). Execs `bsub … xterm … wrapper`.
#
# Args: <flow_type> <stage_name> <tool_name>
#       (tool_name maps to lsf(tool_shell,<tool_name>))
#
# Env:  CBFLOW_CORE_DIR must point at PD/ root.
#       PATH must include the stubs/ dir so bsub/xterm/tool shells resolve.
#       CBFLOW_STUB_LOG (optional) directs stub captures somewhere readable.
#
# Output (on success):
#   WRAPPER_PATH=<path>     so the Python runner can read+verify content
#   TOOL_SHELL=<binary>     the lsf(tool_shell,<tool>)-resolved binary name
#
# Exit: 0 on success, non-zero on dispatch failure (bsub stub never invoked,
#       wrapper missing, lsf key missing, etc.).
# ═══════════════════════════════════════════════════════════════════════════════

if {$argc < 3} {
    puts stderr "Usage: dispatch_smoke.tcl <flow_type> <stage_name> <tool_name>"
    exit 2
}

set flow_type  [lindex $argv 0]
set stage_name [lindex $argv 1]
set tool_name  [lindex $argv 2]

if {![info exists ::env(CBFLOW_CORE_DIR)] || $::env(CBFLOW_CORE_DIR) eq ""} {
    puts stderr "ERROR: CBFLOW_CORE_DIR not set"
    exit 2
}
set pd_dir $::env(CBFLOW_CORE_DIR)

# Synthesize the env the cascade expects (same as a real .run.cbflow.tcl).
set ::env(CBFLOW_FLOW_TYPE)    $flow_type
set ::env(FLOW_DIR)            $pd_dir
set ::env(CONFIG_ROOT)         "$pd_dir/config"
set ::env(SCRIPTS_ROOT)        "$pd_dir/utils"
set ::env(FLOW_CONFIG_VERSION) v1.0.0
set ::env(UTILITIES_VERSION)   v1.0.0

source "$pd_dir/config/flow/v1.0.0/flow_config.tcl"
source "$pd_dir/config/flow/v1.0.0/tool_launch_config.tcl"
source "$pd_dir/config/flow/v1.0.0/lsf_config.tcl"

set ::flow(use_lsf)   "true"
set ::flow(use_xterm) "true"

source "$pd_dir/utils/utilities/v1.0.0/launch_utils.tcl"

set work_dir [pwd]
set node_name "${stage_name}1"

# Dummy command file. generate_launch_wrapper only uses its name as a tag.
set cmd_file "$work_dir/_cmd_${stage_name}.tcl"
set fh [open $cmd_file w]
puts $fh "# dispatch smoke dummy cmd file for ${stage_name}_${tool_name}.tcl"
close $fh

# ── Stage 1: generate the launch wrapper ─────────────────────────────────────
puts "── generate_launch_wrapper(${stage_name}, ${tool_name}) ──"
if {[catch {
    set wrapper [generate_launch_wrapper $work_dir $stage_name $cmd_file $tool_name]
} err]} {
    puts stderr "DISPATCH_SMOKE_FAIL: generate_launch_wrapper: $err"
    exit 1
}

if {![file exists $wrapper]} {
    puts stderr "DISPATCH_SMOKE_FAIL: wrapper not written: $wrapper"
    exit 1
}
if {![file executable $wrapper]} {
    puts stderr "DISPATCH_SMOKE_FAIL: wrapper not executable: $wrapper"
    exit 1
}

# Resolve what tool_shell launch_utils picked (mirrors its decision).
set tool_shell $tool_name
catch { if {[info exists ::lsf(tool_shell,$tool_name)]} { set tool_shell $::lsf(tool_shell,$tool_name) } }
puts "WRAPPER_PATH=$wrapper"
puts "TOOL_SHELL=$tool_shell"

# ── Stage 2: submit_job (exec bsub-stub → xterm-stub → wrapper → tool-stub) ─
puts "── submit_job(${flow_type}/${stage_name}) ──"
if {[catch {submit_job $wrapper $flow_type $stage_name $node_name $work_dir} err]} {
    puts stderr "DISPATCH_SMOKE_FAIL: submit_job: $err"
    exit 1
}
puts "── submit_job returned cleanly ──"
exit 0
