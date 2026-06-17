#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Config Resolver — single source of truth for the cascade
#
# Sources the project → tech → flow → node_config → mmmc → user_config →
# runtime_flow_config cascade in a tclsh subprocess and dumps every variable
# any Python consumer reads as one CBFLOW_CFG:key=value line on stdout.
#
# Two modes:
#   tclsh config_resolver.tcl <flow_type> <run_dir>     # full cascade
#   tclsh config_resolver.tcl <flow_type> --no-run      # project baseline only,
#                                                       # no user_config / runtime override
# In --no-run mode FLOW_DIR / CONFIG_ROOT / FLOW_CONFIG_VERSION must be set in
# the env (the bin/cbflow wrapper sets them). The .run.cbflow.tcl sourcing is
# skipped.
#
# Every consumer goes through cbflow_config.py (Python) which validates the
# CBFLOW_CFG:_schema_version line emitted below. Bump the version any time
# the emission schema changes — Python errors loudly on mismatch.
# ═══════════════════════════════════════════════════════════════════════════════

set CBFLOW_CFG_SCHEMA_VERSION 2

if {$argc < 2} {
    puts stderr "Usage: config_resolver.tcl <flow_type> <run_dir|--no-run>"
    exit 1
}

set flow_type [lindex $argv 0]
set run_dir   [lindex $argv 1]

set _no_run [expr {$run_dir eq "--no-run" || $run_dir eq ""}]

# ── 1. .run.cbflow.tcl (full cascade only) ──
if {!$_no_run} {
    set env_file "$run_dir/.run.cbflow.tcl"
    if {[file exists $env_file]} {
        source $env_file
    } else {
        puts stderr "ERROR: .run.cbflow.tcl not found in $run_dir"
        exit 1
    }
}

# ── 2. flow_config.tcl (always — defines flow array + sources node_config) ──
# Path lookup cascades env → derived from CBFLOW_CORE_DIR so this script works
# both inside a run (where .run.cbflow.tcl set FLOW_DIR) and out of it
# (e.g. `cbflow flow types` before any workspace has been created).
if {[info exists ::env(CONFIG_ROOT)]} {
    set config_root $::env(CONFIG_ROOT)
} elseif {[info exists ::env(FLOW_DIR)]} {
    set config_root "$::env(FLOW_DIR)/config"
} elseif {[info exists ::env(CBFLOW_CORE_DIR)]} {
    set config_root "$::env(CBFLOW_CORE_DIR)/config"
} else {
    puts stderr "ERROR: config root not resolvable — set CONFIG_ROOT, FLOW_DIR, or CBFLOW_CORE_DIR"
    exit 1
}
set flow_ver    [expr {[info exists ::env(FLOW_CONFIG_VERSION)] ? $::env(FLOW_CONFIG_VERSION) : "v1.0.0"}]
set flow_config "$config_root/flow/$flow_ver/flow_config.tcl"

if {![file exists $flow_config]} {
    puts stderr "ERROR: flow_config.tcl not found: $flow_config"
    exit 1
}
# CBFLOW_FLOW_TYPE drives flow_config.tcl's node_config dispatch.
if {![info exists ::env(CBFLOW_FLOW_TYPE)] || $::env(CBFLOW_FLOW_TYPE) eq ""} {
    set ::env(CBFLOW_FLOW_TYPE) $flow_type
}
source $flow_config

# ── tool_launch_config.tcl (defines lsf(flow_mapping,*) tiers + tool_shell) ──
set _tlc "$config_root/flow/$flow_ver/tool_launch_config.tcl"
if {[file exists $_tlc]} { source $_tlc }

# ── lsf_config.tcl (queue tier definitions: memory/cpu/runtime per tier) ──
set _lsf_cfg "$config_root/flow/$flow_ver/lsf_config.tcl"
if {[file exists $_lsf_cfg]} { source $_lsf_cfg }

# ── release_config.tcl (defines MILESTONE_STAGE_MAPPING for exit checklists) ──
set _release_cfg "$config_root/flow/$flow_ver/release_config.tcl"
if {[file exists $_release_cfg]} {
    # release_config.tcl uses ::operating_modes — guard against eval errors when
    # the resolver is invoked in --no-run mode and operating_modes hasn't been
    # populated yet. The dynamic STA-mode block at the bottom of the file is
    # gated on `[array exists operating_modes]` so it skips naturally.
    catch { source $_release_cfg }
}

# ── 3. mmmc_config.tcl (full cascade only — needs project context) ──
if {!$_no_run} {
    set _proj_name [expr {[info exists ::env(CBFLOW_PROJECT_NAME)] ? $::env(CBFLOW_PROJECT_NAME) : ""}]
    set _proj_ver  [expr {[info exists ::env(FLOW_CONFIG_VERSION)] ? $::env(FLOW_CONFIG_VERSION) : "v1.0.0"}]
    if {$_proj_name ne ""} {
        set _mmmc_cfg_path "$config_root/project/$_proj_name/$_proj_ver/mmmc_config.tcl"
        if {[file exists $_mmmc_cfg_path]} {
            source $_mmmc_cfg_path
        }
    }

    # ── 4. user_config.tcl — last writer wins for overridable keys ──
    set user_config "$run_dir/setup/user_config.tcl"
    if {[file exists $user_config]} {
        source $user_config
    }

    # ── 5. runtime_flow_config.tcl — `cbflow run add-node` custom node defs ──
    # Currently regex-scanned inside race_engine.py:189/462/469. Sourcing it
    # here makes those regex paths obsolete: any stages,<name>,type the user
    # added at runtime lives on the flow array exactly like a built-in stage.
    set runtime_flow "$run_dir/setup/runtime_flow_config.tcl"
    if {[file exists $runtime_flow]} {
        source $runtime_flow
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Emission — every CBFLOW_CFG:key=value line a Python consumer is allowed to
# read. Adding a new caller means adding a new emission here, NOT a new direct
# .tcl read on the Python side. cbflow_config.require() errors if the key isn't
# emitted; the static_checks guard fails CI if any caller bypasses the resolver.
# ═══════════════════════════════════════════════════════════════════════════════

puts "CBFLOW_CFG:_schema_version=$CBFLOW_CFG_SCHEMA_VERSION"

# Per-flow array — every node_config key lives under here.
set flow_array [string tolower $flow_type]

# Flatten whitespace (newlines, tabs, runs of spaces) to single spaces. Values
# come from `array set ... { ... }` blocks that can span multiple lines in the
# source .tcl, but the Python parser reads one CBFLOW_CFG: line at a time, so
# any embedded newline would truncate the value silently.
proc _flatten {value} {
    regsub -all {\s+} [string trim $value] { } out
    return $out
}

# Helper — emit only if the variable exists on the flow array.
# `upvar #0 $arr a` aliases the global array named by `$arr` into the proc's
# local scope as `a`; without this the proc body's `$arr(...)` refs would look
# in proc-local scope and silently find nothing.
proc _emit_array_key {arr key} {
    upvar #0 $arr a
    if {[info exists a($key)]} {
        puts "CBFLOW_CFG:$key=[_flatten $a($key)]"
    }
}

# Helper — emit every key matching a glob on the flow array.
proc _emit_array_glob {arr glob} {
    upvar #0 $arr a
    foreach key [array names a $glob] {
        puts "CBFLOW_CFG:$key=[_flatten $a($key)]"
    }
}

# ── stages ──
_emit_array_key $flow_array stages

# ── dependencies, subnodes, subnode_dependencies, subnode_work_dirs ──
_emit_array_glob $flow_array "dependencies,*"
_emit_array_glob $flow_array "subnodes,*"
_emit_array_glob $flow_array "subnode_dependencies,*"
_emit_array_glob $flow_array "subnode_work_dirs,*"

# ── stage_types, node_types, stages,<name>,type ──
# stages,<name>,type is set by `cbflow run add-node` via runtime_flow_config.tcl
# — emit it so race_engine.py reads it cleanly with no rstrip guess.
_emit_array_glob $flow_array "stage_types,*"
_emit_array_glob $flow_array "node_types,*"
_emit_array_glob $flow_array "stages,*,type"
_emit_array_glob $flow_array "stages,*,dependencies"
_emit_array_glob $flow_array "stages,*,branch_key"

# ── branch metadata (cbflow run create-branch) ──
_emit_array_glob $flow_array "branch_keys,*"

# ── tool info ──
foreach key {tool,vendor tool,name tool,version tool,args supported_tools default_tool} {
    _emit_array_key $flow_array $key
}

# ── flow(*) — runtime/dispatch booleans, defaults set in flow_config.tcl,
# overridable in user_config.tcl. Every key here MUST be set somewhere in the
# cascade — race_engine.py asserts via require(). ──
foreach key {types use_lsf use_xterm test_mode dispatcher cbflow_version
             mode merged,flows merged,fp_independent merged,pnr_depends_fp
             dashboard,default_port mmmc,enabled
             race,db_max_sessions phases exit_milestones run_types} {
    if {[info exists ::flow($key)]} {
        puts "CBFLOW_CFG:flow($key)=[_flatten $::flow($key)]"
    }
}

# ── lsf(*) — flow_mapping for resource-tier dispatch + queue defs.
# Sourced from tool_launch_config.tcl / lsf_config.tcl. race_engine._parse_resource_map
# used to regex-scan these files directly; consumers now read through the
# resolver instead.
if {[array exists ::lsf]} {
    foreach key [array names ::lsf] {
        puts "CBFLOW_CFG:lsf($key)=[_flatten $::lsf($key)]"
    }
}

# ── MMMC (flow-array prefixed and bare scenario-set state) ──
_emit_array_glob $flow_array "mmmc,*"

# ── runtime timeouts ──
_emit_array_glob $flow_array "runtime,timeout,*"

# ── critical_files, mandatory_outputs — consumed by `cbflow run report` and
# the pre-flight validator. These were regex-parsed off the static .tcl file
# until this commit; reading them through the cascade means user_config
# overrides actually take effect on display. ──
_emit_array_glob $flow_array "critical_files,*"
_emit_array_glob $flow_array "mandatory_outputs,*"

# ── required_inputs and the mandatory-input contract ──
_emit_array_glob $flow_array "required_inputs,*"
_emit_array_key $flow_array mandatory_user_inputs
_emit_array_key $flow_array mandatory_input_groups
_emit_array_key $flow_array subnode_input_types

# ── merge metadata (multi-flow chaining) ──
foreach key {merge_entry_stage merge_handoff_stage merge_parallel_stages parallel_stages chip_type} {
    _emit_array_key $flow_array $key
}

# ── output paths ──
_emit_array_glob $flow_array "output,*"

# ── release types ──
_emit_array_glob $flow_array "release_types,*"

# ── operating_modes (project-level array — overridable in user_config) ──
if {[array exists ::operating_modes]} {
    foreach _mode [array names ::operating_modes] {
        # operating_modes value is itself a dict { constraint_file "..." }
        puts "CBFLOW_CFG:operating_modes($_mode)=[_flatten $::operating_modes($_mode)]"
    }
}

# ── RC corner list (derived by mmmc_config from PVT building blocks) ──
if {[info exists rc_corner_list]} {
    puts "CBFLOW_CFG:rc_corner_list=[_flatten $rc_corner_list]"
}

# ── MMMC scenario sets (auto-generated from mmmc_config) ──
if {[array exists mmmc_scenario_sets]} {
    foreach key [array names mmmc_scenario_sets] {
        puts "CBFLOW_CFG:mmmc_scenario_set,$key=[_flatten $mmmc_scenario_sets($key)]"
    }
}

# ── Analysis views (for dynamic timing scenarios) ──
if {[array exists analysis_views]} {
    puts "CBFLOW_CFG:analysis_view_names=[lsort [array names analysis_views]]"
}

# ── Descriptions & milestone mapping (sourced via descriptions_config.tcl /
# release_config.tcl). Consumers: cbflow flow types display, exit-checklist
# generator, run-report titles. ──
foreach _arr {flow_descriptions phase_descriptions run_type_descriptions
              MILESTONE_DESCRIPTIONS MILESTONE_STAGE_MAPPING} {
    if {[array exists ::$_arr]} {
        # `[set _arr]` substitutes the scalar value as plain text — using
        # `$_arr($_k)` here would be parsed as an array reference instead.
        # `upvar #0 ::name local` aliases the global array to a local handle.
        upvar #0 ::$_arr _a
        foreach _k [array names _a] {
            puts "CBFLOW_CFG:[set _arr]($_k)=[_flatten $_a($_k)]"
        }
        unset _a
    }
}

# ── Sourced-files manifest (diagnostic: which files contributed to this run) ──
set _sources [list "flow_config:$flow_config"]
if {!$_no_run} {
    if {[info exists _mmmc_cfg_path] && [file exists $_mmmc_cfg_path]} {
        lappend _sources "mmmc_config:$_mmmc_cfg_path"
    }
    if {[file exists $user_config]} {
        lappend _sources "user_config:$user_config"
    }
    if {[file exists $runtime_flow]} {
        lappend _sources "runtime_flow_config:$runtime_flow"
    }
}
puts "CBFLOW_CFG:_sources=[join $_sources { }]"

puts "CBFLOW_CFG:_done=true"
