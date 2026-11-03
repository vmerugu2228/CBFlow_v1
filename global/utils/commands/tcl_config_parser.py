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


def _baseline_flow() -> str:
    """Pick a flow whose discipline is present on this checkout, for use
    as the resolver vehicle when reading cross-domain keys (flow_registry,
    project, tech — all of which live in global/).

    SYNTH is preferred because every PD install ships it. In a DFT or DV
    sparse-checkout clone where PD/ isn't on disk, SYNTH's flow_config.tcl
    can't be sourced; fall back to the first flow of whichever discipline
    IS available. Only the flow(*) + project(*) + tech(*) keys are read —
    the choice of baseline doesn't affect the result as long as its
    config files are resolvable.
    """
    import os
    preferences = [
        ('CBFLOW_CORE_DIR', 'SYNTH'),       # PD
        ('CBFLOW_DFT_DIR',  'DFT_INSERT'),  # DFT
        ('CBFLOW_DV_DIR',   'SPEC_RAMP'),   # DV
    ]
    for env_var, flow in preferences:
        root = os.environ.get(env_var, '').strip()
        # CBFLOW_CORE_DIR is set unconditionally by _cbflow_paths.sh (even
        # if PD/ isn't on disk), so verify the directory actually exists.
        # Otherwise a DV-only clone picks SYNTH and the resolver blows up
        # on the missing PD/config/flow/flow_config.tcl.
        if root and os.path.isdir(root):
            return flow
    return 'SYNTH'


def get_flow_types() -> List[str]:
    """Every flow type the framework knows about (from `flow(types)`)."""
    # Baseline is any flow whose discipline is on disk — only flow(*) keys
    # matter here, not the specific flow's node_config.
    cfg = _resolved(_baseline_flow(), run_dir=None)
    return _parse_tcl_list(_cfg.optional(cfg, 'flow(types)') or '')


def get_flow_descriptions() -> Dict[str, str]:
    cfg = _resolved(_baseline_flow(), run_dir=None)
    out: Dict[str, str] = {}
    prefix = 'flow_descriptions('
    for key, val in cfg.items():
        if key.startswith(prefix) and key.endswith(')'):
            name = key[len(prefix):-1]
            out[name] = _parse_tcl_string(val)
    return out


def get_disciplines() -> List[str]:
    """List of disciplines the framework knows about (from `flow(disciplines)`).

    Order matches flow_config.tcl's declaration — PD first, then sibling
    disciplines. Empty list if the discipline map isn't declared (pre-refactor
    installs) — callers should treat that as 'PD-only' semantically.
    """
    cfg = _resolved(_baseline_flow(), run_dir=None)
    return _parse_tcl_list(_cfg.optional(cfg, 'flow(disciplines)') or '')


def get_flow_discipline(flow_type: str) -> str:
    """Return the discipline owning `flow_type` (e.g. 'PD', 'DFT', 'DV').

    Returns '' if the map has no entry for this flow (pre-refactor install
    where flow(discipline,*) isn't declared). Callers should default to 'PD'
    in that case for back-compat.
    """
    cfg = _resolved(_baseline_flow(), run_dir=None)
    val = _cfg.optional(cfg, f'flow(discipline,{flow_type})')
    return _parse_tcl_string(val) if val else ''


def get_flows_by_discipline() -> Dict[str, List[str]]:
    """Return {discipline: [flows]}. Undeclared flows fall under '_uncategorized'."""
    out: Dict[str, List[str]] = {}
    for flow in get_flow_types():
        disc = get_flow_discipline(flow) or '_uncategorized'
        out.setdefault(disc, []).append(flow)
    return out


def is_discipline_available(discipline: str) -> bool:
    """True if the discipline directory is present in this checkout.

    Sparse-checkout profiles (cbflow-git-bootstrap) materialize only the
    owner's discipline + global/. _cbflow_paths.sh exports CBFLOW_<DISC>_DIR
    only if the directory exists, so a missing env var signals absence.
    Even PD can be absent in a DV-only or DFT-only sparse clone — don't
    assume it.
    """
    import os
    disc = discipline.upper()
    env_var = 'CBFLOW_CORE_DIR' if disc == 'PD' else f'CBFLOW_{disc}_DIR'
    root = os.environ.get(env_var, '').strip()
    if not root:
        return False
    return os.path.isdir(root)


def get_available_flow_types() -> List[str]:
    """Flows the current checkout can actually resolve. In a full-tree
    install this equals get_flow_types(); in a sparse PD-only clone it
    drops DFT/DV flows whose discipline directory isn't on disk."""
    return [ft for ft in get_flow_types()
            if is_discipline_available(get_flow_discipline(ft) or 'PD')]


# ─── Per-project discipline helpers (reads master_projects.json) ──────────
#
# Projects declare which disciplines they use via
# `enabled_flows_by_discipline` in global/config/master_projects.json. These
# helpers surface that declaration to Python callers (cbflow-git-bootstrap,
# project dashboard discipline cards, workspace create gate).

_CANONICAL_DISCIPLINES = ('PD', 'DFT', 'DV')


def _load_master_projects() -> Dict[str, Any]:
    """Load global/config/master_projects.json. Returns the top-level dict.

    Raises FileNotFoundError if the file isn't present on disk — expected
    only in broken installs.
    """
    import json as _json
    from core.paths import get_master_projects_path
    p = get_master_projects_path()
    if not p:
        raise FileNotFoundError(
            "master_projects.json not found — install is incomplete")
    with open(p, encoding='utf-8') as f:
        return _json.load(f)


def _project_entry(project: str) -> Dict[str, Any]:
    """Return the per-project dict for `project` from master_projects.json.

    Raises KeyError when the project isn't declared — the operator-facing
    error path for `cbflow-git-bootstrap --project <unknown>` etc.
    """
    data = _load_master_projects()
    projects = data.get('projects') or {}
    if project not in projects:
        known = sorted(projects.keys())
        raise KeyError(
            f"project '{project}' not declared in master_projects.json "
            f"(known: {', '.join(known) if known else '<none>'})")
    return projects[project]


def get_project_disciplines(project: str) -> List[str]:
    """Return disciplines this project uses, in canonical PD/DFT/DV order.

    A discipline is "in use" when its flow list under
    `enabled_flows_by_discipline` is non-empty. Projects that pre-date the
    schema v2.0 split (only `enabled_flows` present) are treated as PD-only.
    """
    entry = _project_entry(project)
    by_disc = entry.get('enabled_flows_by_discipline') or {}
    if not by_disc:
        return ['PD'] if entry.get('enabled_flows') else []
    out = []
    for d in _CANONICAL_DISCIPLINES:
        if by_disc.get(d):
            out.append(d)
    return out


def get_project_enabled_flows(project: str, discipline: str) -> List[str]:
    """Return the flow list this project enables for the given discipline."""
    disc = discipline.upper()
    if disc not in _CANONICAL_DISCIPLINES:
        raise ValueError(
            f"unknown discipline '{discipline}' "
            f"(expected one of {', '.join(_CANONICAL_DISCIPLINES)})")
    entry = _project_entry(project)
    by_disc = entry.get('enabled_flows_by_discipline') or {}
    flows = by_disc.get(disc) or []
    # Schema v1 projects stored a flat enabled_flows only — assume PD if
    # the schema v2 map is absent.
    if not by_disc and disc == 'PD':
        flows = entry.get('enabled_flows') or []
    return list(flows)


def is_discipline_enabled_for_project(project: str, discipline: str) -> bool:
    """True when `discipline` is enabled for `project`.

    Operator-facing gate for `cbflow-git-bootstrap --project <name> <disc>`
    and the project dashboard's discipline-card rendering.
    """
    return bool(get_project_enabled_flows(project, discipline))


def _parse_tcl_list_from_dumper(value: str) -> List[str]:
    """Parse a value emitted by _load_dft_overlay_raw's TCL dumper.

    The dumper joins list elements with \\x1E. If no \\x1E is present, the
    value is a single element (scalar or 1-item list) — return as [value].
    """
    if value is None or value == '':
        return []
    if '\x1e' in value:
        return [p for p in value.split('\x1e') if p != '']
    return [value]


def _load_dft_overlay_raw(project: str) -> Dict[str, str]:
    """Source `<CBFLOW_DFT_DIR>/config/project/<project>/v1.0.0/<project>_dft_config.tcl`
    directly via tclsh and return all `project(dft,...)` keys as a flat dict.

    The cascade resolver's --no-run mode skips project overlays by design
    (project context requires a run_dir). This dedicated loader sources only
    the DFT overlay so project-level DFT queries work from any entry point.
    """
    import subprocess
    dft_dir = os.environ.get('CBFLOW_DFT_DIR') or ''
    if not dft_dir:
        core_dir = os.environ.get('CBFLOW_CORE_DIR') or ''
        if core_dir:
            dft_dir = os.path.join(os.path.dirname(core_dir), 'DFT')
    proj_ver = os.environ.get('FLOW_CONFIG_VERSION', '') or 'v1.0.0'
    overlay = os.path.join(dft_dir, 'config', 'project', project, proj_ver,
                           f'{project}_dft_config.tcl')
    if not os.path.exists(overlay):
        return {}

    # Dumper protocol:
    #   `KEY<FS>elem1<RS>elem2<RS>…` per line.
    #   FS = ASCII 0x1F (31), RS = ASCII 0x1E (30) — generated via
    #   `binary format c` because TCL doesn't honor \xNN escapes in
    #   bare words. Python splits on FS once (key vs value) and the
    #   value on RS for list elements. Preserves quoted elements
    #   containing whitespace (e.g. "-f filelist.f").
    script = f'''
array set project {{}}
if {{[catch {{source {overlay}}} err]}} {{ puts stderr "ERROR: $err"; exit 1 }}
set _FS [binary format c 31]
set _RS [binary format c 30]
foreach k [lsort [array names project dft,*]] {{
    set v $project($k)
    if {{[catch {{llength $v}}]}} {{
        puts "project($k)${{_FS}}$v"
    }} else {{
        set _parts [list]
        foreach _e $v {{ lappend _parts $_e }}
        puts "project($k)${{_FS}}[join $_parts $_RS]"
    }}
}}
'''
    try:
        result = subprocess.run(['tclsh'], input=script,
                                capture_output=True, text=True, timeout=10)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return {}
    if result.returncode != 0:
        return {}
    # Use split('\n') not splitlines() — splitlines() treats \x1e as a line
    # terminator, which would strip our list-element separator.
    out: Dict[str, str] = {}
    for line in result.stdout.split('\n'):
        if '\x1f' not in line:
            continue
        k, v = line.split('\x1f', 1)
        out[k] = v
    return out


def get_dft_master_config(project: str, block: str = '') -> Dict[str, Any]:
    """Return the resolved DFT MasterConfig for `project`.

    Reads the DFT project overlay (`<disc>/config/project/<proj>/v1.0.0/
    <proj>_dft_config.tcl`), returning the `project(dft,...)` keyspace as a
    nested dict. When `block` is non-empty, per-block overrides are merged
    into the top-level (e.g. `include_memory_test = ON` when the block has
    an explicit override; falls back to `default` when not).

    Backs the Tessent Pass1 TCL preamble generation (handler reads these
    keys to emit `set_memory_test_config`, `define_memory_module`, etc).

    The schema mirrors the owner spreadsheet
    `DFT_FLOW_Dependencies_Input_Output.xlsx` "MBIST Config Dependencies"
    sheet. See bumblebee_dft_config.tcl for the canonical seed.
    """
    cfg = _load_dft_overlay_raw(project)

    def _get(key: str, default: str = '') -> str:
        if key not in cfg:
            return default
        # Scalar fields may still have a single list wrapper when the TCL
        # dumper detected a 1-element list — strip it.
        parts = _parse_tcl_list_from_dumper(cfg[key])
        return parts[0] if parts else default

    def _get_list(key: str) -> List[str]:
        return _parse_tcl_list_from_dumper(cfg[key]) if key in cfg else []

    out: Dict[str, Any] = {
        'project': project,
        'block': block or None,
        'soc_structure': {
            'top':    _get('project(dft,soc_structure,top)'),
            'blocks': _get_list('project(dft,soc_structure,blocks)'),
        },
        'mbist_tool':                 _get('project(dft,mbist_tool)'),
        'tcd_memory_path':            _get('project(dft,tcd_memory_path)'),
        'mbist_libs': {
            'masis':    _get_list('project(dft,mbist_libs,masis)'),
            'compiler': _get_list('project(dft,mbist_libs,compiler)'),
        },
        'mbist_common_constraints':   _get('project(dft,mbist_common_constraints)'),
        'mbist_def_files':            _get('project(dft,mbist_def_files)'),
        'mbist_static_ports':         _get('project(dft,mbist_static_ports)'),
        'encrypted_rtl':              _get('project(dft,encrypted_rtl)'),
        'encryption_key_file':        _get('project(dft,encryption_key_file)'),
        'write_design_import_script': _get('project(dft,write_design_import_script)'),
        'design_stage_default':       _get('project(dft,design_stage,default)'),
        'design_type_default':        _get('project(dft,design_type,default)'),
        'async_reset_default':        _get('project(dft,async_reset,default)'),
    }

    if not block:
        return out

    def _per_block(key_tmpl: str, default: Any = '',
                   as_list: bool = False) -> Any:
        key = key_tmpl.format(block=block)
        if key not in cfg:
            return default
        parts = _parse_tcl_list_from_dumper(cfg[key])
        if as_list:
            return parts
        return parts[0] if parts else default

    out.update({
        'design_type':         _per_block('project(dft,design_type,{block})',
                                          out['design_type_default']),
        'design_id':           _per_block('project(dft,design_id,{block})'),
        'rtl_files':           _per_block('project(dft,rtl_files,{block})',
                                          [], as_list=True),
        'bbox_models': {
            'instances': _per_block('project(dft,bbox_models,{block},instances)',
                                    [], as_list=True),
            'modules':   _per_block('project(dft,bbox_models,{block},modules)',
                                    [], as_list=True),
        },
        'clocks':              _per_block('project(dft,clocks,{block})',
                                          [], as_list=True),
        'async_reset':         _per_block('project(dft,async_reset,{block})',
                                          out['async_reset_default']),
        'include_memory_test': _per_block('project(dft,include_memory_test,{block})',
                                          'OFF'),
        'mbist_grouping_file': _per_block('project(dft,mbist_grouping_file,{block})'),
    })
    return out


def get_phases(run_dir: Optional[str] = None) -> List[str]:
    """Return the phase list for a project.

    Phases are project-specific — each project sets `project(phases)`
    (e.g. bumblebee uses LC1-LC5, another might use P0-P3). Falls back to
    the legacy global `flow(phases)` only if the project didn't declare
    its own — that fallback keeps older configs working during migration
    and should be removed once every project sets project(phases).
    """
    cfg = _resolved(_baseline_flow(), run_dir=run_dir)
    return _parse_tcl_list(
        _cfg.optional(cfg, 'project(phases)') or
        _cfg.optional(cfg, 'flow(phases)') or ''
    )


def get_phase_descriptions() -> Dict[str, str]:
    cfg = _resolved(_baseline_flow(), run_dir=None)
    out: Dict[str, str] = {}
    prefix = 'phase_descriptions('
    for key, val in cfg.items():
        if key.startswith(prefix) and key.endswith(')'):
            out[key[len(prefix):-1]] = _parse_tcl_string(val)
    return out


def get_exit_milestones() -> List[str]:
    cfg = _resolved(_baseline_flow(), run_dir=None)
    return _parse_tcl_list(_cfg.optional(cfg, 'flow(exit_milestones)') or '')


def get_milestone_stage_mapping() -> Dict[str, str]:
    cfg = _resolved(_baseline_flow(), run_dir=None)
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
    # `stages` is emitted only when a node_config was sourced. Cross-
    # discipline flows registered in flow_registry.tcl (e.g. LINT/CDC under
    # DV) may not yet have their node_config on disk — for discovery
    # commands (`cbflow flow types`) we want an empty list, not a hard
    # error. An actual `cbflow run <flow>` still errors — race_engine
    # validates via require() at DAG build time.
    stages_raw = _cfg.optional(cfg, 'stages')
    if not stages_raw:
        return []
    return _parse_tcl_list(stages_raw)


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
        'discipline': get_flow_discipline(flow_type) or 'PD',
    }


def get_all_flow_info() -> Dict[str, Dict[str, Any]]:
    """Enumerate flows the current checkout can resolve. Skips flows whose
    discipline directory isn't present (sparse-checkout clones)."""
    return {ft: get_flow_info(ft) for ft in get_available_flow_types()}


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
