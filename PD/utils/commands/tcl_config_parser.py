#!/usr/bin/env python3
"""CBflow flow/node config accessors — resolver-backed.

Every read goes through `cbflow_config.load_resolved_config()`, which spawns
`config_resolver.tcl` and returns the cascade-resolved key→value dict. There
is no regex parsing of `.tcl` files in this module — `static_checks.py`
enforces that property.

Most public functions accept an optional `run_dir`:
    run_dir=None     → project baseline (no user_config / runtime override)
    run_dir=<path>   → full cascade, honors user_config overrides

Callers that operate inside a run (`cbflow run report`, `cbflow run show-graph`,
the dashboard) should pass `run_dir`; pre-run queries (`cbflow flow types`,
`cbflow workspace template`) leave it as None.

Merged-flow helpers (`is_merged_flow`, `parse_merged_flow`,
`get_merged_flow_stages`) operate on flow-type strings and require no config
read beyond `get_flow_types()` — they're pure Python.

Plugin support (`_load_plugin_config`) currently raises NotImplementedError.
JSON-registry plugins aren't on the production critical path; restoring this
will require the resolver to walk `plugins/*/flow_registry.json` and emit the
same CBFLOW_CFG keys.
"""

import os
import re
from typing import Any, Dict, List, Optional

import cbflow_config as _cfg


# ─── Helpers ──────────────────────────────────────────────────────────────


def _get_config_root() -> Optional[str]:
    """PD core dir, for non-config path computations (e.g., tool-shell binary
    location lookups). Does not read any .tcl file."""
    core_dir = os.environ.get('CBFLOW_CORE_DIR')
    if not core_dir:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        core_dir = os.path.dirname(os.path.dirname(script_dir))
    return core_dir


def _get_flow_config_version() -> str:
    """Flow config version from env (or `v1.0.0`)."""
    return os.environ.get('FLOW_CONFIG_VERSION', '') or 'v1.0.0'


def _parse_tcl_list(value: str) -> List[str]:
    """Split a whitespace-separated Tcl list. Resolver pre-flattens multi-line
    values to single lines, so a simple split is sufficient — no need to walk
    brace nesting."""
    if value is None:
        return []
    value = value.strip()
    if value.startswith('{') and value.endswith('}'):
        value = value[1:-1].strip()
    return value.split()


def _parse_tcl_string(value: str) -> str:
    """Strip surrounding quotes/braces from a Tcl atom."""
    if value is None:
        return ''
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or \
       (value.startswith('{') and value.endswith('}')):
        value = value[1:-1]
    return value.strip()


def _resolved(flow_type: str, run_dir: Optional[str] = None) -> Dict[str, str]:
    """Call the cascade resolver and return its dict. Cached per
    (flow_type, run_dir) by cbflow_config."""
    return _cfg.load_resolved_config(flow_type, run_dir=run_dir)


# ─── Flow-level accessors (read from `flow_config.tcl` + descriptions) ────


def get_flow_types() -> List[str]:
    """Every flow type the framework knows about (from `flow(types)`)."""
    # SYNTH is the canonical baseline flow — every install ships it. Using it
    # as the resolver vehicle is arbitrary; only flow(*) keys matter here.
    cfg = _resolved('SYNTH', run_dir=None)
    return _parse_tcl_list(_cfg.optional(cfg, 'flow(types)') or '')


def get_flow_descriptions() -> Dict[str, str]:
    cfg = _resolved('SYNTH', run_dir=None)
    out: Dict[str, str] = {}
    prefix = 'flow_descriptions('
    for key, val in cfg.items():
        if key.startswith(prefix) and key.endswith(')'):
            name = key[len(prefix):-1]
            out[name] = _parse_tcl_string(val)
    return out


def get_phases() -> List[str]:
    cfg = _resolved('SYNTH', run_dir=None)
    return _parse_tcl_list(_cfg.optional(cfg, 'flow(phases)') or '')


def get_phase_descriptions() -> Dict[str, str]:
    cfg = _resolved('SYNTH', run_dir=None)
    out: Dict[str, str] = {}
    prefix = 'phase_descriptions('
    for key, val in cfg.items():
        if key.startswith(prefix) and key.endswith(')'):
            out[key[len(prefix):-1]] = _parse_tcl_string(val)
    return out


def get_exit_milestones() -> List[str]:
    cfg = _resolved('SYNTH', run_dir=None)
    return _parse_tcl_list(_cfg.optional(cfg, 'flow(exit_milestones)') or '')


def get_milestone_stage_mapping() -> Dict[str, str]:
    cfg = _resolved('SYNTH', run_dir=None)
    out: Dict[str, str] = {}
    prefix = 'MILESTONE_STAGE_MAPPING('
    for key, val in cfg.items():
        if key.startswith(prefix) and key.endswith(')'):
            out[key[len(prefix):-1]] = _parse_tcl_string(val)
    return out


# ─── Per-flow accessors (read from `<FLOW>_config.tcl` via cascade) ───────


def _load_node_config(flow_type: str,
                      run_dir: Optional[str] = None) -> Dict[str, str]:
    """The resolved cascade dict for a flow.

    Callers that previously held the regex-parsed array as a dict can keep
    treating this as one — same shape, just sourced through the resolver.
    """
    return _resolved(flow_type, run_dir=run_dir)


def get_flow_stages(flow_type: str,
                    run_dir: Optional[str] = None) -> List[str]:
    cfg = _resolved(flow_type, run_dir=run_dir)
    return _parse_tcl_list(_cfg.require(cfg, 'stages'))


def get_flow_stages_with_suffix(flow_type: str, suffix: str = "1") -> List[str]:
    """Suffix each stage name (some call sites want `inputs1` form even when
    the resolver returns `inputs1` already). Idempotent — only appends if the
    suffix isn't already present."""
    out = []
    for s in get_flow_stages(flow_type):
        out.append(s if s.endswith(suffix) else f"{s}{suffix}")
    return out


def get_tool_info(flow_type: str,
                  run_dir: Optional[str] = None) -> Dict[str, str]:
    """Tool {vendor, name, version, args} for a flow.

    Tool selection cascades: node_config default → user_config override. The
    resolver applies the override automatically when run_dir is provided.
    """
    cfg = _resolved(flow_type, run_dir=run_dir)
    return {
        'vendor': _parse_tcl_string(_cfg.optional(cfg, 'tool,vendor') or ''),
        'name':   _parse_tcl_string(_cfg.optional(cfg, 'tool,name') or ''),
        'version': _parse_tcl_string(_cfg.optional(cfg, 'tool,version') or ''),
        'args':   _parse_tcl_string(_cfg.optional(cfg, 'tool,args') or ''),
    }


def get_supported_tools(flow_type: str,
                        run_dir: Optional[str] = None) -> List[str]:
    cfg = _resolved(flow_type, run_dir=run_dir)
    return _parse_tcl_list(_cfg.optional(cfg, 'supported_tools') or '')


def get_default_tool(flow_type: str,
                     run_dir: Optional[str] = None) -> str:
    cfg = _resolved(flow_type, run_dir=run_dir)
    return _parse_tcl_string(_cfg.optional(cfg, 'default_tool') or '')


def get_flow_info(flow_type: str) -> Dict[str, Any]:
    descriptions = get_flow_descriptions()
    return {
        'description': descriptions.get(flow_type, flow_type),
        'stages': get_flow_stages(flow_type),
        'tool': get_tool_info(flow_type),
        'supported_tools': get_supported_tools(flow_type),
        'default_tool': get_default_tool(flow_type),
    }


def get_all_flow_info() -> Dict[str, Dict[str, Any]]:
    return {ft: get_flow_info(ft) for ft in get_flow_types()}


def get_subnodes(flow_type: str, stage: str,
                 run_dir: Optional[str] = None) -> List[str]:
    """Subnodes for a stage. Honors both `inputs1` and `inputs` naming."""
    cfg = _resolved(flow_type, run_dir=run_dir)
    for key in (f'subnodes,{stage}', f'subnodes,{stage}1',
                f'subnodes,{re.sub(r"[0-9]+$", "", stage)}'):
        val = _cfg.optional(cfg, key)
        if val:
            return _parse_tcl_list(val)
    return []


def get_tool_path(flow_type: str,
                  run_dir: Optional[str] = None) -> str:
    info = get_tool_info(flow_type, run_dir=run_dir)
    if info['vendor'] and info['name']:
        return f"{info['vendor']}/{info['name']}"
    return ''


def clear_cache() -> None:
    """Drop the cbflow_config resolved-config cache."""
    _cfg.clear_cache()


# ─── Merge metadata accessors ─────────────────────────────────────────────


def get_entry_stage(flow_type: str,
                    run_dir: Optional[str] = None) -> str:
    cfg = _resolved(flow_type, run_dir=run_dir)
    val = _cfg.optional(cfg, 'merge_entry_stage')
    if val:
        return _parse_tcl_string(val)
    # Fallback: first stage of the flow. Not a "missing key default" — it's
    # the documented semantic when merge_entry_stage isn't set, used by
    # non-mergeable flows.
    stages = get_flow_stages(flow_type, run_dir=run_dir)
    return stages[0] if stages else ''


def get_handoff_stage(flow_type: str,
                      run_dir: Optional[str] = None) -> str:
    cfg = _resolved(flow_type, run_dir=run_dir)
    val = _cfg.optional(cfg, 'merge_handoff_stage')
    if val:
        return _parse_tcl_string(val)
    # Documented semantic: if not set, the export_data stage is the handoff;
    # if neither exists, the last stage of the flow takes over.
    stages = get_flow_stages(flow_type, run_dir=run_dir)
    for s in stages:
        if re.sub(r'\d+$', '', s) == 'export_data':
            return s
    return stages[-1] if stages else ''


def get_parallel_stages(flow_type: str,
                        run_dir: Optional[str] = None) -> List[str]:
    """Stages that branch off the linear flow (e.g., `release_data1` runs in
    parallel with the next flow's entry). `merge_parallel_stages` is the
    authoritative key — if not set, fall back to scanning for release_data
    stages by name."""
    cfg = _resolved(flow_type, run_dir=run_dir)
    val = _cfg.optional(cfg, 'merge_parallel_stages')
    if val:
        return _parse_tcl_list(val)
    out = []
    for s in get_flow_stages(flow_type, run_dir=run_dir):
        if re.sub(r'\d+$', '', s) == 'release_data':
            out.append(s)
    return out


# ─── Merged-flow support (pure Python, no config reads) ───────────────────


def is_merged_flow(flow_spec: str) -> bool:
    parts = parse_merged_flow(flow_spec)
    return parts is not None and len(parts) > 1


def parse_merged_flow(flow_spec: str) -> Optional[List[str]]:
    flow_spec = flow_spec.upper()
    known_flows = set(get_flow_types())

    if flow_spec in known_flows:
        return None

    parts = flow_spec.split('_')

    # 2-flow merge
    for i in range(1, len(parts)):
        left = '_'.join(parts[:i])
        right = '_'.join(parts[i:])
        if left in known_flows and right in known_flows:
            return [left, right]

    # 3-flow merge
    for i in range(1, len(parts)):
        for j in range(i + 1, len(parts)):
            f1 = '_'.join(parts[:i])
            f2 = '_'.join(parts[i:j])
            f3 = '_'.join(parts[j:])
            if f1 in known_flows and f2 in known_flows and f3 in known_flows:
                return [f1, f2, f3]

    return None


def get_merged_flow_stages(flow_spec: str) -> List[Dict[str, Any]]:
    """Combined stage list for a merged flow.

    Each element is {name, original_stage, flow, prefix, dependency, tool,
    is_parallel, is_handoff}. Cross-flow edges: first stage of flow N+1
    depends on flow N's handoff stage.
    """
    sub_flows = parse_merged_flow(flow_spec)
    if not sub_flows:
        return []

    merged_stages: List[Dict[str, Any]] = []
    prev_handoff_merged_name: Optional[str] = None

    for flow_idx, flow in enumerate(sub_flows):
        prefix = flow.lower()
        stages = get_flow_stages(flow)
        tool_info = get_tool_info(flow)
        is_last_flow = (flow_idx == len(sub_flows) - 1)

        entry_stage = get_entry_stage(flow)
        handoff_stage = get_handoff_stage(flow)
        parallel_stages = set(get_parallel_stages(flow))

        handoff_base = re.sub(r'\d+$', '', handoff_stage)
        handoff_merged_name = f"{prefix}_{handoff_base}"

        for i, stage in enumerate(stages):
            base_name = re.sub(r'\d+$', '', stage)
            merged_name = f"{prefix}_{base_name}"

            if stage == entry_stage and prev_handoff_merged_name:
                dependency = prev_handoff_merged_name
            elif i == 0:
                dependency = ''
            elif stage in parallel_stages and not is_last_flow:
                dependency = handoff_merged_name
            else:
                prev_stage_base = re.sub(r'\d+$', '', stages[i - 1])
                dependency = f"{prefix}_{prev_stage_base}"

            merged_stages.append({
                'name': merged_name,
                'original_stage': stage,
                'flow': flow,
                'prefix': prefix,
                'dependency': dependency,
                'tool': tool_info,
                'is_parallel': stage in parallel_stages and not is_last_flow,
                'is_handoff': stage == handoff_stage,
            })

        prev_handoff_merged_name = handoff_merged_name

    return merged_stages


def get_merged_flow_stage_names(flow_spec: str) -> List[str]:
    return [s['name'] for s in get_merged_flow_stages(flow_spec)]


# ─── Plugin support — disabled in v2 schema ──────────────────────────────


def _load_plugin_config(flow_type: str) -> Dict[str, str]:
    """JSON-registry plugin flows are not yet resolver-aware. The fix is to
    teach `config_resolver.tcl` to walk `plugins/*/flow_registry.json` and
    emit the same CBFLOW_CFG keys; until then this is intentionally a hard
    error rather than a quiet fallback to a stale regex path."""
    raise NotImplementedError(
        "Plugin flow configs are not supported through the v2 resolver. "
        f"To register flow {flow_type!r}, define it in "
        "config/flow/v1.0.0/node_configs/ instead."
    )


def _discover_plugin_flows() -> List[Dict[str, Any]]:
    """Likewise — plugin discovery is disabled in v2."""
    return []
