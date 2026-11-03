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

set CBFLOW_CFG_SCHEMA_VERSION 4

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
} elseif {[info exists ::env(CBFLOW_CORE_DIR)]} {
    # Post cbflow_global utils-refactor FLOW_DIR = umbrella root, so
    # $FLOW_DIR/config no longer resolves to the PD-overlay. CBFLOW_CORE_DIR
    # = PD root which still owns PD-overlay project+flow configs.
    set config_root "$::env(CBFLOW_CORE_DIR)/config"
} elseif {[info exists ::env(FLOW_DIR)]} {
    # FLOW_DIR = umbrella after refactor; PD-overlay is at FLOW_DIR/PD/config.
    if {[file isdirectory "$::env(FLOW_DIR)/PD/config"]} {
        set config_root "$::env(FLOW_DIR)/PD/config"
    } else {
        set config_root "$::env(FLOW_DIR)/config"
    }
} else {
    puts stderr "ERROR: config root not resolvable — set CONFIG_ROOT, FLOW_DIR, or CBFLOW_CORE_DIR"
    exit 1
}
set flow_ver    [expr {[info exists ::env(FLOW_CONFIG_VERSION)] ? $::env(FLOW_CONFIG_VERSION) : "v1.0.0"}]

# ── 1b. Global config root (cbflow_global refactor) ──
# Global sources are sourced BEFORE flow_config so flow_registry.tcl pre-
# populates flow(types) / flow(discipline,*) / flow(disciplines) before
# any discipline's flow_config appends its mandatory_vars.
set global_root ""
if {[info exists ::env(CBFLOW_GLOBAL_DIR)] && [file isdirectory "$::env(CBFLOW_GLOBAL_DIR)/config"]} {
    set global_root "$::env(CBFLOW_GLOBAL_DIR)/config"
} elseif {[info exists ::env(CBFLOW_ROOT)] && [file isdirectory "$::env(CBFLOW_ROOT)/global/config"]} {
    set global_root "$::env(CBFLOW_ROOT)/global/config"
}
if {$global_root eq ""} {
    puts stderr "ERROR: CBFLOW_GLOBAL_DIR / CBFLOW_ROOT/global not set — cannot resolve global config root"
    exit 1
}
set _global_sources [list]
set _fr "$global_root/flow/$flow_ver/flow_registry.tcl"
if {![file exists $_fr]} {
    puts stderr "ERROR: global flow_registry.tcl missing: $_fr"
    exit 1
}
source $_fr
lappend _global_sources "global_registry:$_fr"

# ── 2. flow_config.tcl — routed by discipline ────────────────────────────────
# The global registry set flow(discipline,<flow>) → one of {PD, DFT, DV}. Route
# the flow_config.tcl source to that discipline's tree so DFT / DV flows load
# their own mandatory_vars + node_config, not PD's.
#
# The CBFLOW_<DISC>_DIR env var (exported by bin/cbflow when the discipline
# directory exists) locates the discipline root. Falls back to a sibling of
# CBFLOW_CORE_DIR to survive test contexts that don't fully invoke the
# launcher.
set _disc "PD"
if {[info exists ::flow(discipline,$flow_type)]} {
    set _disc $::flow(discipline,$flow_type)
}
set _disc_upper [string toupper $_disc]
set _disc_dir ""
set _disc_env_var "CBFLOW_${_disc_upper}_DIR"
if {[info exists ::env($_disc_env_var)] && [file isdirectory $::env($_disc_env_var)]} {
    set _disc_dir $::env($_disc_env_var)
} elseif {[info exists ::env(CBFLOW_ROOT)] && [file isdirectory "$::env(CBFLOW_ROOT)/$_disc"]} {
    set _disc_dir "$::env(CBFLOW_ROOT)/$_disc"
} elseif {$_disc eq "PD"} {
    # Backwards compat: pre-Phase-5 workareas only export CBFLOW_CORE_DIR.
    set _disc_dir [file dirname $config_root]
}
if {$_disc_dir eq ""} {
    puts stderr "ERROR: cannot resolve discipline root for '$_disc' (flow $flow_type)"
    puts stderr "       set $_disc_env_var or CBFLOW_ROOT."
    exit 1
}

set flow_config "$_disc_dir/config/flow/$flow_ver/flow_config.tcl"
if {![file exists $flow_config]} {
    puts stderr "ERROR: flow_config.tcl not found: $flow_config"
    puts stderr "       (discipline=$_disc for flow=$flow_type)"
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
    # release_config.tcl uses ::operating_modes — the dynamic STA-mode block
    # at the bottom gates on `[array exists operating_modes]` so --no-run
    # mode is handled naturally. Capture any REAL parse error (previously
    # silently swallowed) and surface it to stderr so a syntax error in
    # release_config.tcl doesn't turn into empty release(base_dir) +
    # release_tag resolutions returning 0 all over the codebase.
    if {[catch { source $_release_cfg } _rc_err]} {
        puts stderr "WARNING: release_config.tcl parse error: $_rc_err"
        puts stderr "         Release-tag input resolution will fall back to empty."
    }
}

# ── 3a. project configs — global (identity) + per-discipline overlays ──
# Sourced BEFORE tech because tech configs reference $project(lib_root) etc.
# The identity half (global) provides project(technology|top_module|...);
# each discipline overlay provides project(lib_root|workarea_path|...)
# — the discipline overlay files are symmetric siblings. In a full-tree
# clone all three attach (PD last → wins on conflicts); in a sparse clone
# (DFT or DV only), only the owner's overlay is on disk and is the
# authoritative source for cross-discipline keys like workarea_path.
set _proj_srcs [list]
if {!$_no_run} {
    set _proj_name [expr {[info exists ::env(CBFLOW_PROJECT_NAME)] ? $::env(CBFLOW_PROJECT_NAME) : ""}]
    set _proj_ver  [expr {[info exists ::env(FLOW_CONFIG_VERSION)] ? $::env(FLOW_CONFIG_VERSION) : "v1.0.0"}]
    if {$_proj_name ne ""} {
        if {$global_root ne ""} {
            # Post 2026-11-01 rename: identity file is <project>_config.tcl.
            set _gp "$global_root/project/$_proj_name/$_proj_ver/${_proj_name}_config.tcl"
            if {[file exists $_gp]} {
                source $_gp
                lappend _proj_srcs "global_project:$_gp"
            }
        }
        # Walk every discipline root for its project overlay. _cbflow_paths.sh
        # exports CBFLOW_<DISC>_DIR only when the directory exists, so each
        # overlay only attaches when its tree is on disk. Basename is
        # <project>_<disc>_config.tcl.
        foreach {_env_var _disc_short} {
                CBFLOW_DFT_DIR  dft
                CBFLOW_DV_DIR   dv
                CBFLOW_CORE_DIR pd
        } {
            if {![info exists ::env($_env_var)]} { continue }
            set _root $::env($_env_var)
            if {![file isdirectory $_root]} { continue }
            set _overlay_name "${_proj_name}_${_disc_short}_config.tcl"
            set _ovl "$_root/config/project/$_proj_name/$_proj_ver/$_overlay_name"
            if {[file exists $_ovl]} {
                source $_ovl
                lappend _proj_srcs "disc_project:$_ovl"
            }
        }
    }
}

# ── 3b. tech configs — global (foundry) + PD overlay (metal/cells) ──
# Sourced AFTER project so $project(lib_root) resolves inside tech(*,lef_tech)
# / tech(rcx,*) path values. Both files additively populate tech(...).
set _tech_srcs [list]
if {!$_no_run} {
    set _tech_node [expr {[info exists ::env(CBFLOW_TECH_NODE)] ? $::env(CBFLOW_TECH_NODE) :
                           [expr {[info exists ::env(TECH_NAME)] ? $::env(TECH_NAME) : ""}]}]
    set _tech_ver  [expr {[info exists ::env(TECH_CONFIG_VERSION)] ? $::env(TECH_CONFIG_VERSION) : "v1.0.0"}]
    if {$_tech_node ne ""} {
        # Post 2026-10-11: tech is a SINGLE file in global. The former
        # PD-side tech_pd_config.tcl was merged into tech_config.tcl.
        if {$global_root ne ""} {
            set _gt "$global_root/tech/$_tech_node/$_tech_ver/tech_config.tcl"
            if {[file exists $_gt]} {
                source $_gt
                lappend _tech_srcs "global_tech:$_gt"
            }
        }
    }
}

# ── 3c. mmmc_config.tcl + mmmc_node_scenarios.tcl (from global) ──
# mmmc_config.tcl:         PVT building blocks + auto-gen views/scenarios
# mmmc_node_scenarios.tcl: per-node (setup/hold) scenario assignments.
# Both moved to global/ in Phase 3 — they are project-scoped identity data,
# not PD-specific.
if {!$_no_run} {
    if {$_proj_name ne "" && $global_root ne ""} {
        set _mmmc_cfg_path "$global_root/project/$_proj_name/$_proj_ver/mmmc_config.tcl"
        if {[file exists $_mmmc_cfg_path]} {
            source $_mmmc_cfg_path
        }
        set _mmmc_ns_path "$global_root/project/$_proj_name/$_proj_ver/mmmc_node_scenarios.tcl"
        if {[file exists $_mmmc_ns_path]} {
            source $_mmmc_ns_path
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
# `cbflow run add-node --resource-tier <T>` writes stages,<name>,resource_tier
# via node_manager. Without this emission, the resolver silently drops the
# tier → race_engine falls back to the base-stage default queue; next node
# mutation rewrites runtime_flow_config.tcl without the tier line and the
# user's setting is lost from disk.
_emit_array_glob $flow_array "stages,*,resource_tier"

# ── branch metadata (cbflow run create-branch) ──
_emit_array_glob $flow_array "branch_keys,*"

# ── tool info ──
foreach key {tool,vendor tool,name tool,version tool,args supported_tools default_tool} {
    _emit_array_key $flow_array $key
}

# ── project(*) — identity (name, phases, technology, top_module, …) +
# discipline overlay keys (workarea_path, lib_root, release,*, dft,* …).
# Pre 2026-11-03 the resolver sourced the project configs but never
# serialized `project(*)` back to Python, so helpers like get_phases()
# couldn't see project(phases) even when it was correctly set in the
# project config. The project cascade is already sourced upstream (lines
# 165-198); here we just emit every key for Python callers.
if {[info exists ::project]} {
    foreach key [lsort [array names ::project]] {
        puts "CBFLOW_CFG:project($key)=[_flatten $::project($key)]"
    }
}

# ── flow(*) — runtime/dispatch booleans, defaults set in flow_config.tcl,
# overridable in user_config.tcl. Every key here MUST be set somewhere in the
# cascade — race_engine.py asserts via require(). ──
foreach key {types disciplines use_lsf use_xterm test_mode dispatcher cbflow_version
             mode merged,flows merged,fp_independent merged,pnr_depends_fp
             dashboard,default_port mmmc,enabled
             race,db_max_sessions phases exit_milestones run_types
             run_name design_name type run_type} {
    if {[info exists ::flow($key)]} {
        puts "CBFLOW_CFG:flow($key)=[_flatten $::flow($key)]"
    }
}

# ── flow(mandatory_vars,*) — pre-flight validation contract. Consumed by
# config_validator.validate_mandatory_vars() to fail-fast before DAG build. ──
foreach key [lsort [array names ::flow "mandatory_vars,*"]] {
    puts "CBFLOW_CFG:flow($key)=[_flatten $::flow($key)]"
}

# ── flow(discipline,<FLOW>) — discipline map. Consumed by:
#   - flow_cmd.py to group + filter by discipline
#   - race_engine._build_command() for discipline-aware handler lookup ──
foreach key [lsort [array names ::flow "discipline,*"]] {
    puts "CBFLOW_CFG:flow($key)=[_flatten $::flow($key)]"
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
set _sources [list]
# Global registry (flow_registry.tcl loaded before flow_config)
foreach _gs $_global_sources { lappend _sources $_gs }
# Global + PD tech overlays (Phase 3 split)
foreach _ts $_tech_srcs { lappend _sources $_ts }
# Global + PD project overlays (Phase 3 split)
foreach _ps $_proj_srcs { lappend _sources $_ps }
lappend _sources "flow_config:$flow_config"
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
puts "CBFLOW_CFG:_global_root=$global_root"

puts "CBFLOW_CFG:_done=true"
