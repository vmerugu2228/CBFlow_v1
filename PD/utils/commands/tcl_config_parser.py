#!/usr/bin/env python3
"""
CBFlow Tcl Config Parser

Parses existing Tcl configuration files (flow_config.tcl, node_configs/*_config.tcl)
to provide a single source of truth for flow types, stages, tool mappings, phases,
and milestones. Eliminates the need for hardcoded values in Python consumer files.

Usage:
    from tcl_config_parser import get_flow_types, get_flow_stages, get_flow_info
"""

import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Any

# Module-level cache
_cache: Dict[str, Any] = {}


def _get_config_root() -> Optional[str]:
    """Resolve the config root directory from environment or script location."""
    core_dir = os.environ.get('CBFLOW_CORE_DIR')
    if not core_dir:
        # Derive from script location: utils/commands/ -> PD root
        script_dir = os.path.dirname(os.path.abspath(__file__))
        core_dir = os.path.dirname(os.path.dirname(script_dir))
    return core_dir


def _get_flow_config_version() -> str:
    """Get flow config version from environment or resolve from current symlink."""
    ver = os.environ.get('FLOW_CONFIG_VERSION', '')
    if ver:
        return ver
    # Resolve from config/flow/current symlink
    config_root = _get_config_root()
    if config_root:
        current = os.path.join(config_root, 'config', 'flow', 'current')
        if os.path.islink(current):
            return os.path.basename(os.readlink(current))
        elif os.path.isdir(current):
            return 'current'
    return 'v1.0.0'


def _parse_tcl_list(value: str) -> List[str]:
    """Parse a Tcl list string (brace-delimited or space-separated) into a Python list."""
    value = value.strip()
    if value.startswith('{') and value.endswith('}'):
        value = value[1:-1].strip()
    if not value:
        return []
    return value.split()


def _parse_tcl_string(value: str) -> str:
    """Parse a Tcl string value, removing surrounding quotes."""
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or \
       (value.startswith('{') and value.endswith('}')):
        value = value[1:-1]
    return value.strip()


def _parse_array_set_blocks(content: str, array_name: str) -> Dict[str, str]:
    """Parse all 'array set <array_name> { ... }' blocks from Tcl content.

    Returns a dict of key -> raw_value strings.
    Handles multiple array set blocks for the same array (Tcl merges them).
    """
    result = {}
    # Match: array set <name> {  ...  }
    # The closing brace must be at the start of a line (or after whitespace)
    pattern = rf'array\s+set\s+{re.escape(array_name)}\s*\{{(.*?)\n\}}'
    for match in re.finditer(pattern, content, re.DOTALL):
        block = match.group(1)
        # Parse key-value pairs from the block
        # Keys can contain commas and dots (e.g., subnodes,inputs or tool,vendor)
        # Values can be quoted strings, braced lists, or bare words
        kv_pattern = r'^\s*([\w.,]+)\s+(.*?)(?=\n\s*[\w.,]+\s|\n\s*#|\Z)'
        for kv_match in re.finditer(kv_pattern, block, re.MULTILINE | re.DOTALL):
            key = kv_match.group(1).strip()
            val = kv_match.group(2).strip()
            # Remove inline comments (;# ...)
            val = re.sub(r'\s*;\s*#.*$', '', val, flags=re.MULTILINE).strip()
            # Remove trailing line comments
            val = re.sub(r'\s*#[^}]*$', '', val, flags=re.MULTILINE).strip()
            if key and val:
                result[key] = val
    return result


def _parse_set_statements(content: str) -> Dict[str, str]:
    """Parse 'set <var> <value>' statements from Tcl content.

    Returns dict of var_name -> raw_value.
    Handles: set flow(types) {SYNTH FP PNR ...}
             set flow(type) "SYNTH"
    """
    result = {}
    pattern = r'^set\s+([\w().,]+)\s+(.*?)(?:\s*;\s*#.*)?$'
    for match in re.finditer(pattern, content, re.MULTILINE):
        var = match.group(1).strip()
        val = match.group(2).strip()
        result[var] = val
    return result


def _load_flow_config() -> Dict[str, Any]:
    """Load and parse the main flow_config.tcl file."""
    if 'flow_config' in _cache:
        return _cache['flow_config']

    config_root = _get_config_root()
    version = _get_flow_config_version()
    if not config_root:
        _cache['flow_config'] = {}
        return {}

    config_path = os.path.join(config_root, 'config', 'flow', version, 'flow_config.tcl')
    if not os.path.isfile(config_path):
        _cache['flow_config'] = {}
        return {}

    with open(config_path, 'r') as f:
        content = f.read()

    parsed = {}

    # Parse set statements
    set_vars = _parse_set_statements(content)

    # flow(types)
    if 'flow(types)' in set_vars:
        parsed['flow_types'] = _parse_tcl_list(set_vars['flow(types)'])

    # flow(phases)
    if 'flow(phases)' in set_vars:
        parsed['phases'] = _parse_tcl_list(set_vars['flow(phases)'])

    # flow(exit_milestones)
    if 'flow(exit_milestones)' in set_vars:
        parsed['exit_milestones'] = _parse_tcl_list(set_vars['flow(exit_milestones)'])

    # Parse array set blocks
    flow_desc = _parse_array_set_blocks(content, 'flow_descriptions')
    parsed['flow_descriptions'] = {k: _parse_tcl_string(v) for k, v in flow_desc.items()}

    phase_desc = _parse_array_set_blocks(content, 'phase_descriptions')
    parsed['phase_descriptions'] = {k: _parse_tcl_string(v) for k, v in phase_desc.items()}

    milestone_mapping = _parse_array_set_blocks(content, 'MILESTONE_STAGE_MAPPING')
    parsed['milestone_stage_mapping'] = {k: _parse_tcl_string(v) for k, v in milestone_mapping.items()}

    milestone_desc = _parse_array_set_blocks(content, 'MILESTONE_DESCRIPTIONS')
    parsed['milestone_descriptions'] = {k: _parse_tcl_string(v) for k, v in milestone_desc.items()}

    _cache['flow_config'] = parsed
    return parsed


def _load_node_config(flow_type: str) -> Dict[str, str]:
    """Load and parse a specific node config file (e.g., PNR_config.tcl)."""
    cache_key = f'node_config_{flow_type}'
    if cache_key in _cache:
        return _cache[cache_key]

    config_root = _get_config_root()
    version = _get_flow_config_version()
    if not config_root:
        _cache[cache_key] = {}
        return {}

    config_path = os.path.join(
        config_root, 'config', 'flow', version,
        'node_configs', f'{flow_type}_config.tcl'
    )
    if not os.path.isfile(config_path):
        # Try plugin config
        plugin_config = _load_plugin_config(flow_type)
        if plugin_config:
            _cache[cache_key] = plugin_config
            return plugin_config
        _cache[cache_key] = {}
        return {}

    with open(config_path, 'r') as f:
        content = f.read()

    # The array name is the lowercase flow type
    array_name = flow_type.lower()
    parsed = _parse_array_set_blocks(content, array_name)

    _cache[cache_key] = parsed
    return parsed


def _discover_plugin_flows() -> list:
    """Discover plugin flows from the plugins directory."""
    cache_key = 'plugin_flows'
    if cache_key in _cache:
        return _cache[cache_key]

    import json
    plugins = []
    core_dir = _get_config_root()
    if not core_dir:
        _cache[cache_key] = []
        return []

    plugins_dir = os.path.join(core_dir, 'plugins')
    if not os.path.isdir(plugins_dir):
        _cache[cache_key] = []
        return []

    for entry in os.listdir(plugins_dir):
        plugin_dir = os.path.join(plugins_dir, entry)
        registry_file = os.path.join(plugin_dir, 'flow_registry.json')
        if os.path.isdir(plugin_dir) and os.path.isfile(registry_file):
            try:
                with open(registry_file, 'r') as f:
                    registry = json.load(f)
                registry['_plugin_dir'] = plugin_dir
                plugins.append(registry)
            except Exception:
                pass

    _cache[cache_key] = plugins
    return plugins


def _load_plugin_config(flow_type: str) -> Dict[str, str]:
    """Load configuration from a plugin's flow_registry.json as a dict mimicking TCL node config."""
    cache_key = f'plugin_config_{flow_type}'
    if cache_key in _cache:
        return _cache[cache_key]

    import json
    plugins = _discover_plugin_flows()
    for plugin in plugins:
        if plugin.get('flow_type', '').upper() == flow_type.upper():
            # Convert JSON to TCL-like config dict
            config = {}
            stages = plugin.get('stages', [])
            config['stages'] = ' '.join(f'{s}1' for s in stages)
            config['tool,vendor'] = f'"{plugin.get("vendor", "")}"'
            config['tool,name'] = f'"{plugin.get("tool", "")}"'
            config['tool,version'] = f'"{plugin.get("tool_version", "v1.0.0")}"'
            config['tool,args'] = f'"{plugin.get("tool_args", "")}"'
            config['supported_tools'] = f'{{{plugin.get("tool", "")}}}'
            config['default_tool'] = f'"{plugin.get("tool", "")}"'

            # Add subnodes
            for stage, subnodes in plugin.get('subnodes', {}).items():
                config[f'subnodes,{stage}1'] = '{' + ' '.join(subnodes) + '}'

            # Add dependencies
            for stage, deps in plugin.get('dependencies', {}).items():
                dep_str = ' '.join(f'{d}1' for d in deps)
                config[f'dependencies,{stage}1'] = '{' + dep_str + '}'

            _cache[cache_key] = config
            return config

    _cache[cache_key] = {}
    return {}


# ─── Public API ───────────────────────────────────────────────────────────────


def get_flow_types() -> List[str]:
    """Get list of all supported flow types, including plugins.

    Returns: ['SYNTH', 'FP', 'PNR', ..., plus any plugin flows]
    """
    config = _load_flow_config()
    result = config.get('flow_types')
    if not result:
        result = []

    # Merge plugin flows
    plugin_flows = _discover_plugin_flows()
    for plugin in plugin_flows:
        flow_type = plugin.get('flow_type', '').upper()
        if flow_type and flow_type not in result:
            result.append(flow_type)

    return result


def get_flow_stages(flow_type: str) -> List[str]:
    """Get ordered stage list for a flow type from its node config.

    Returns e.g.: ['inputs', 'place', 'cts', 'cts_opt', 'route', 'pro', 'signoff', 'export_data', 'release_data']
    """
    node_config = _load_node_config(flow_type)
    stages_raw = node_config.get('stages', '')
    if stages_raw:
        return _parse_tcl_list(stages_raw)
    return []


def get_flow_stages_with_suffix(flow_type: str, suffix: str = "1") -> List[str]:
    """Get stages with numeric suffix appended (e.g., 'inputs1', 'place1').

    Used by run_cmd.py which needs the suffixed form.
    """
    return [f"{stage}{suffix}" for stage in get_flow_stages(flow_type)]


def get_tool_info(flow_type: str) -> Dict[str, str]:
    """Get tool configuration for a flow type.

    Reads from the tool-specific config (e.g., SYNTH_PNR_fc_config.tcl)
    which has tool,vendor/name/version. Falls back to common config.

    Returns: {'vendor': 'synopsys', 'name': 'fc', 'version': 'v1.0.0', 'args': '-batch -no_gui'}
    """
    node_config = _load_node_config(flow_type)

    # tool,vendor/name may be in the tool-specific config, not the common config
    vendor = _parse_tcl_string(node_config.get('tool,vendor', ''))
    name = _parse_tcl_string(node_config.get('tool,name', ''))

    if not vendor or not name:
        # Load tool-specific config: <FLOW>_<default_tool>_config.tcl
        default_tool = _parse_tcl_string(node_config.get('default_tool', ''))
        if default_tool:
            config_root = _get_config_root()
            version = _get_flow_config_version()
            if config_root:
                tool_config_path = os.path.join(
                    config_root, 'config', 'flow', version,
                    'node_configs', f'{flow_type}_{default_tool}_config.tcl'
                )
                if os.path.isfile(tool_config_path):
                    with open(tool_config_path, 'r') as f:
                        for line in f:
                            line = line.strip()
                            if not line or line.startswith('#'):
                                continue
                            m = re.match(r'["\s]*(tool,\w+)["\s]+["\s]*([^"}\s]+)', line)
                            if m:
                                key, val = m.group(1), m.group(2)
                                if key == 'tool,vendor' and not vendor:
                                    vendor = val
                                elif key == 'tool,name' and not name:
                                    name = val

    return {
        'vendor': vendor,
        'name': name or _parse_tcl_string(node_config.get('default_tool', '')),
        'version': _parse_tcl_string(node_config.get('tool,version', '')),
        'args': _parse_tcl_string(node_config.get('tool,args', '')),
    }


def get_supported_tools(flow_type: str) -> List[str]:
    """Get list of supported tools for a flow type."""
    node_config = _load_node_config(flow_type)
    raw = node_config.get('supported_tools', '')
    if raw:
        return _parse_tcl_list(raw)
    return []


def get_default_tool(flow_type: str) -> str:
    """Get default tool name for a flow type."""
    node_config = _load_node_config(flow_type)
    return _parse_tcl_string(node_config.get('default_tool', ''))


def get_flow_descriptions() -> Dict[str, str]:
    """Get flow type descriptions.

    Returns: {'SYNTH': 'Logic synthesis and optimization', 'FP': 'Floorplanning...', ...}
    """
    config = _load_flow_config()
    result = config.get('flow_descriptions', {})
    if result:
        return result
    # Fallback
    return {ft: ft for ft in get_flow_types()}


def get_flow_info(flow_type: str) -> Dict[str, Any]:
    """Get complete info for a single flow type.

    Returns: {
        'description': '...', 'stages': [...],
        'tool': {'vendor': '...', 'name': '...', ...},
        'supported_tools': [...], 'default_tool': '...'
    }
    """
    descriptions = get_flow_descriptions()
    return {
        'description': descriptions.get(flow_type, flow_type),
        'stages': get_flow_stages(flow_type),
        'tool': get_tool_info(flow_type),
        'supported_tools': get_supported_tools(flow_type),
        'default_tool': get_default_tool(flow_type),
    }


def get_all_flow_info() -> Dict[str, Dict[str, Any]]:
    """Get complete info for all flow types.

    Returns: {'SYNTH': {...}, 'FP': {...}, 'PNR': {...}, ...}
    """
    return {ft: get_flow_info(ft) for ft in get_flow_types()}


def get_phases() -> List[str]:
    """Get list of project phases."""
    config = _load_flow_config()
    result = config.get('phases')
    if result:
        return result
    return ['P0', 'P1', 'P2', 'P3']


def get_phase_descriptions() -> Dict[str, str]:
    """Get phase descriptions.

    Returns: {'P0': 'Initial implementation and prototyping', ...}
    """
    config = _load_flow_config()
    result = config.get('phase_descriptions', {})
    if result:
        return result
    return {p: p for p in get_phases()}


def get_exit_milestones() -> List[str]:
    """Get list of exit milestones."""
    config = _load_flow_config()
    return config.get('exit_milestones', [])


def get_milestone_stage_mapping() -> Dict[str, str]:
    """Get milestone to stage mapping."""
    config = _load_flow_config()
    return config.get('milestone_stage_mapping', {})


def get_subnodes(flow_type: str, stage: str) -> List[str]:
    """Get subnodes for a specific stage of a flow type.

    Handles both suffixed (v1.0.0: subnodes,inputs1) and unsuffixed (v1.0.1: subnodes,inputs) keys.
    Returns e.g.: ['setup', 'netlist', 'sdc', 'def', 'upf', 'library', 'validate', 'finish']
    """
    node_config = _load_node_config(flow_type)
    # Try exact key first
    key = f'subnodes,{stage}'
    raw = node_config.get(key, '')
    if raw:
        return _parse_tcl_list(raw)
    # Try stripping numeric suffix (e.g., inputs1 -> inputs)
    import re
    stripped = re.sub(r'[0-9]+$', '', stage)
    if stripped != stage:
        raw = node_config.get(f'subnodes,{stripped}', '')
        if raw:
            return _parse_tcl_list(raw)
    # Try adding suffix 1 (e.g., inputs -> inputs1)
    raw = node_config.get(f'subnodes,{stage}1', '')
    if raw:
        return _parse_tcl_list(raw)
    return []


def get_tool_path(flow_type: str) -> str:
    """Get the tool path segment for a flow type (e.g., 'cadence/innovus').

    Constructed from the node config's tool vendor and name.
    """
    info = get_tool_info(flow_type)
    vendor = info.get('vendor', '')
    name = info.get('name', '')
    if vendor and name:
        return f"{vendor}/{name}"
    return ''


def clear_cache():
    """Clear the module-level cache. Useful for testing or when configs change."""
    _cache.clear()


# ─── Merge Metadata Accessors ──────────────────────────────────────────────


def get_entry_stage(flow_type: str) -> str:
    """Get the entry stage for a flow (merge metadata).

    Configured via 'merge_entry_stage' in node config.
    """
    node_config = _load_node_config(flow_type)
    raw = node_config.get('merge_entry_stage', '')
    if raw:
        return _parse_tcl_string(raw)
    # Fallback: first stage
    stages = get_flow_stages(flow_type)
    return stages[0] if stages else ''


def get_handoff_stage(flow_type: str) -> str:
    """Get the handoff stage for a flow (merge metadata).

    Configured via 'merge_handoff_stage' in node config.
    """
    node_config = _load_node_config(flow_type)
    raw = node_config.get('merge_handoff_stage', '')
    if raw:
        return _parse_tcl_string(raw)
    # Fallback: find export_data stage
    import re
    stages = get_flow_stages(flow_type)
    for s in stages:
        base = re.sub(r'\d+$', '', s)
        if base == 'export_data':
            return s
    return stages[-1] if stages else ''


def get_parallel_stages(flow_type: str) -> List[str]:
    """Get list of parallel stages - branch off, don't block next flow.

    Configured via 'merge_parallel_stages' in node config.
    """
    node_config = _load_node_config(flow_type)
    raw = node_config.get('merge_parallel_stages', '')
    if raw:
        return _parse_tcl_list(raw)
    # Fallback: find release_data stage
    import re
    result = []
    for s in get_flow_stages(flow_type):
        base = re.sub(r'\d+$', '', s)
        if base == 'release_data':
            result.append(s)
    return result


# ─── Merged Flow Support ────────────────────────────────────────────────────


def is_merged_flow(flow_spec: str) -> bool:
    """Check if flow_spec is a merged flow like SYNTH_FP or SYNTH_FP_PNR.

    A merged flow contains 2-3 valid flow types joined by underscores.
    Single flows like 'PNR' or 'SYNTH' return False.
    """
    parts = parse_merged_flow(flow_spec)
    return parts is not None and len(parts) > 1


def parse_merged_flow(flow_spec: str) -> Optional[List[str]]:
    """Parse a merged flow spec into component flows.

    'SYNTH_FP' → ['SYNTH', 'FP']
    'SYNTH_FP_PNR' → ['SYNTH', 'FP', 'PNR']
    'PNR' → None (single flow, not merged)

    Returns None if it's a single known flow or invalid.
    """
    flow_spec = flow_spec.upper()
    known_flows = set(get_flow_types())

    # If it's a single known flow, not merged
    if flow_spec in known_flows:
        return None

    # Try splitting by underscore and check if ALL parts are valid flows
    # Need to handle multi-word flow names like 'SYNTH' vs compound like 'SYNTH_FP'
    # Strategy: try all possible 2-way and 3-way splits
    parts = flow_spec.split('_')

    # Try 2-flow merge: find split point where left and right are both valid flows
    for i in range(1, len(parts)):
        left = '_'.join(parts[:i])
        right = '_'.join(parts[i:])
        if left in known_flows and right in known_flows:
            return [left, right]

    # Try 3-flow merge: find two split points
    for i in range(1, len(parts)):
        for j in range(i + 1, len(parts)):
            f1 = '_'.join(parts[:i])
            f2 = '_'.join(parts[i:j])
            f3 = '_'.join(parts[j:])
            if f1 in known_flows and f2 in known_flows and f3 in known_flows:
                return [f1, f2, f3]

    return None


def get_merged_flow_stages(flow_spec: str) -> List[dict]:
    """Build combined stage list for a merged flow.

    Returns list of dicts:
    [
        {'name': 'synth_inputs', 'original_stage': 'inputs1', 'flow': 'SYNTH', 'prefix': 'synth'},
        {'name': 'synth_synthesis', 'original_stage': 'synthesis1', 'prefix': 'synth', 'flow': 'SYNTH'},
        ...
        {'name': 'fp_inputs', 'original_stage': 'inputs', 'flow': 'FP', 'prefix': 'fp'},
        ...
    ]

    Cross-flow dependency: first stage of flow N+1 depends on last stage of flow N.
    """
    sub_flows = parse_merged_flow(flow_spec)
    if not sub_flows:
        return []

    merged_stages = []
    prev_handoff_merged_name = None  # Last flow's handoff stage in merged form

    import re

    for flow_idx, flow in enumerate(sub_flows):
        prefix = flow.lower()
        stages = get_flow_stages(flow)
        tool_info = get_tool_info(flow)
        is_last_flow = (flow_idx == len(sub_flows) - 1)

        # Read merge metadata from config
        entry_stage = get_entry_stage(flow)
        handoff_stage = get_handoff_stage(flow)
        parallel_stages = set(get_parallel_stages(flow))

        # Compute the merged name of the handoff stage for this flow
        handoff_base = re.sub(r'\d+$', '', handoff_stage)
        handoff_merged_name = f"{prefix}_{handoff_base}"

        # Helper to convert stage name to merged form
        def to_merged(stage_name):
            return f"{prefix}_{re.sub(r'd+$', '', stage_name) if False else re.sub(r'\\d+$', '', stage_name)}"

        for i, stage in enumerate(stages):
            base_name = re.sub(r'\d+$', '', stage)
            merged_name = f"{prefix}_{base_name}"

            # Determine dependency
            if stage == entry_stage and prev_handoff_merged_name:
                # Entry stage of next flow depends on previous flow's handoff stage
                dependency = prev_handoff_merged_name
            elif i == 0:
                # First stage of first flow - no dependency
                dependency = ''
            elif stage in parallel_stages and not is_last_flow:
                # Parallel stages depend on the handoff stage (not blocking next flow)
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
    """Get just the merged stage names as a flat list.

    'SYNTH_FP' → ['synth_inputs', 'synth_synthesis', ..., 'fp_inputs', ..., 'fp_release_data']
    """
    return [s['name'] for s in get_merged_flow_stages(flow_spec)]
