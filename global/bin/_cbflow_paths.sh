#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Launcher — Shared path resolution
#
# Sourced by every cbflow-* launcher in global/bin/ and every discipline
# launcher <disc>/bin/cbflow-<disc>. Sets:
#   CBFLOW_ROOT        — repo root (parent of global/, PD/, DFT/, DV/)
#   CBFLOW_GLOBAL_DIR  — <root>/global
#   CBFLOW_CORE_DIR    — <root>/PD  (PD discipline root)
#   CBFLOW_DFT_DIR     — <root>/DFT (only if directory exists)
#   CBFLOW_DV_DIR      — <root>/DV  (only if directory exists)
#
# Works from either invocation home (global/bin/ or <disc>/bin/) and survives
# any symlink chain.
#
# The caller must pass BASH_SOURCE of the invoking launcher as the first
# argument so the resolver sees the outer script's path, not this file's.
# Usage in caller:
#     source "$(dirname "${BASH_SOURCE[0]}")/_cbflow_paths.sh" "${BASH_SOURCE[0]}"
# ═══════════════════════════════════════════════════════════════════════════════

_cbflow_resolve_paths() {
    local _src="${1:-${BASH_SOURCE[0]}}"
    # Walk the symlink chain manually (readlink -f isn't portable on macOS).
    while [ -L "$_src" ]; do
        local _srcdir="$(cd "$(dirname "$_src")" && pwd)"
        _src="$(readlink "$_src")"
        [[ "$_src" != /* ]] && _src="$_srcdir/$_src"
    done

    local _script_dir="$(cd "$(dirname "$_src")" && pwd)"       # <...>/bin
    local _parent_dir="$(dirname "$_script_dir")"                # <...>/<disc-or-global>
    local _parent_name="$(basename "$_parent_dir")"

    if [[ "$_parent_name" == "global" ]]; then
        # Main launcher stack — global/bin/
        CBFLOW_GLOBAL_DIR="$_parent_dir"
        CBFLOW_ROOT="$(dirname "$_parent_dir")"
    else
        # Discipline launcher — <disc>/bin/
        CBFLOW_ROOT="$(dirname "$_parent_dir")"
        CBFLOW_GLOBAL_DIR="$CBFLOW_ROOT/global"
    fi

    # PD is the canonical "core" discipline — most cross-cutting Python code
    # (race_engine, workspace_cmd, etc.) lives under PD/utils/commands/.
    CBFLOW_CORE_DIR="$CBFLOW_ROOT/PD"

    # Discipline roots — only exported when directory actually exists.
    [[ -d "$CBFLOW_ROOT/DFT" ]] && CBFLOW_DFT_DIR="$CBFLOW_ROOT/DFT"
    [[ -d "$CBFLOW_ROOT/DV"  ]] && CBFLOW_DV_DIR="$CBFLOW_ROOT/DV"

    # Config schema versions. Every config tree in the repo is on v1.0.0.
    # Previously each individual caller (Python + TCL) had its own default
    # fallback, meaning any typo'd env override silently loaded v1.0.0
    # anyway. Set them centrally so individual sites can read env strictly
    # and fail if the targeted version dir is missing.
    #
    # When a repo adds a v1.1.0 or v2.0.0 schema, bump these to point at
    # the new tree. Multi-version repos should override these via the
    # calling script or a local shell wrapper, not via silent defaults.
    : "${FLOW_CONFIG_VERSION:=v1.0.0}"
    : "${UTILITIES_VERSION:=v1.0.0}"
    : "${TECH_CONFIG_VERSION:=v1.0.0}"
    : "${PROJECT_CONFIG_VERSION:=v1.0.0}"

    export CBFLOW_ROOT CBFLOW_GLOBAL_DIR CBFLOW_CORE_DIR
    export FLOW_CONFIG_VERSION UTILITIES_VERSION TECH_CONFIG_VERSION PROJECT_CONFIG_VERSION
    [[ -n "${CBFLOW_DFT_DIR:-}" ]] && export CBFLOW_DFT_DIR
    [[ -n "${CBFLOW_DV_DIR:-}"  ]] && export CBFLOW_DV_DIR
    # Explicit success — otherwise the function returns the exit status
    # of the last conditional, which is 1 when the corresponding
    # discipline directory doesn't exist. Under `set -euo pipefail` in
    # the calling launcher, that would silently abort every cbflow
    # command on installs without a DV/ (or DFT/) subdirectory.
    return 0
}

_cbflow_resolve_paths "${1:-}"
unset -f _cbflow_resolve_paths
