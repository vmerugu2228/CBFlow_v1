#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow dispatch smoke harness — directly exercises launch_utils::submit_job
# with stubbed bsub + xterm. Catches the class of bugs `test_mode=true` masks
# in the regular test suite (missing or corrupt lsf/flow config keys that
# submit_job reads but `handler_run` short-circuits past).
#
# Args: <flow_type> <stage_name>
# Env:  CBFLOW_CORE_DIR must point at PD/ root.
#       PATH must include the stubs/ dir so `bsub` and `xterm` resolve.
#       CBFLOW_STUB_LOG (optional) directs stub captures somewhere readable.
#
# Exit: 0 on success, non-zero on dispatch failure.
# ═══════════════════════════════════════════════════════════════════════════════

if {$argc < 2} {
    puts stderr "Usage: dispatch_smoke.tcl <flow_type> <stage_name>"
    exit 2
}

set flow_type  [lindex $argv 0]
set stage_name [lindex $argv 1]

if {![info exists ::env(CBFLOW_CORE_DIR)] || $::env(CBFLOW_CORE_DIR) eq ""} {
    puts stderr "ERROR: CBFLOW_CORE_DIR not set"
    exit 2
}
set pd_dir $::env(CBFLOW_CORE_DIR)

# Synthesize the env the cascade expects (mirrors what .run.cbflow.tcl sets
# inside a real workspace). Use --no-run mode style: no project-level
# mmmc_config, no user_config — just the project baseline. That's the
# minimum a real LSF dispatch would see if the user hadn't overridden
# anything in user_config.
set ::env(CBFLOW_FLOW_TYPE)    $flow_type
set ::env(FLOW_DIR)            $pd_dir
set ::env(CONFIG_ROOT)         "$pd_dir/config"
set ::env(SCRIPTS_ROOT)        "$pd_dir/utils"
set ::env(FLOW_CONFIG_VERSION) v1.0.0
set ::env(UTILITIES_VERSION)   v1.0.0

source "$pd_dir/config/flow/v1.0.0/flow_config.tcl"
source "$pd_dir/config/flow/v1.0.0/tool_launch_config.tcl"
source "$pd_dir/config/flow/v1.0.0/lsf_config.tcl"

# Pretend the user wrote `set flow(use_lsf) "true"` and `set flow(use_xterm)
# "true"` in user_config. submit_job reads these via determine_launch_mode.
set ::flow(use_lsf)   "true"
set ::flow(use_xterm) "true"

# Source the dispatcher last so its `proc` definitions are bound to the
# `lsf` array we just populated.
source "$pd_dir/utils/utilities/v1.0.0/launch_utils.tcl"

# Build a throwaway wrapper script that submit_job would hand to bsub.
set tmp [pwd]
set wrapper "$tmp/_dispatch_smoke_wrapper.csh"
set work_dir $tmp
set node_name "${stage_name}1"

set fh [open $wrapper "w"]
puts $fh "#!/bin/csh -f"
puts $fh "# dispatch smoke wrapper — never actually runs"
puts $fh "echo 'wrapper invoked (this is a stub)'"
close $fh
file attributes $wrapper -permissions rwxr-xr-x

# Now exercise the real dispatch path. submit_job will:
#   (1) read $::flow(use_lsf) / use_xterm via determine_launch_mode
#   (2) resolve qtype from $::lsf(flow_mapping,$flow_type,$stage_name)
#   (3) read $::lsf(queue_types,$qtype,{memory,cpu,runtime_limit})
#   (4) read $::lsf(bsub,{command,queue,project,affinity})
#   (5) read $::lsf(xterm,{command,geometry}) since use_xterm=true
#   (6) exec the stubbed bsub
# Any missing key from steps 2-5 errors here with "no such element" or the
# explicit `puts ERROR` + exit branches inside submit_job.
puts "── invoking submit_job for ${flow_type}/${stage_name} ──"
if {[catch {submit_job $wrapper $flow_type $stage_name $node_name $work_dir} err]} {
    puts stderr "DISPATCH_SMOKE_FAIL: $err"
    exit 1
}
puts "── submit_job returned cleanly ──"
exit 0
