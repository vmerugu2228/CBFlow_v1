#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Run Command Handler
# Description: Handles flow execution within a run directory
# Usage: cbflow run <subcommand> [options]
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import glob
import os
import re as _re_mod
import sys
import subprocess
import logging
from datetime import datetime
from pathlib import Path

# Shape of a CBflow run directory. Keep in sync with
# workspace_cmd._RUN_DIR_RE, dashboard/router._RUN_DIR_RE, and
# dashboard/app._RUN_DIR_RE. Previously bare `'_run_' in name` matched
# stray dirs (old_run_notes, backup_run_sim) with destructive consequences.
# Phase token: any project-defined phase name (project(phases)) — not a
# fixed list of phase schemes.
_PHASE_PREFIX_RE = r'(?:[A-Za-z0-9]+(?:_[0-9]+)?)'
_FLOW_TOKEN_RE   = r'[A-Z][A-Z0-9_]*'
_RUN_DIR_RE = _re_mod.compile(
    r'^' + _PHASE_PREFIX_RE + r'_run_' + _FLOW_TOKEN_RE + r'(?:_|$)')


def _is_run_dir_name(name: str) -> bool:
    return bool(_RUN_DIR_RE.match(name))

# Configure unified logging
from logging_config import configure_logging, get_logger

import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir, CBFLOW_VERSION as VERSION
from core import release_exits
from core import registry

# PD-only commands (metrics, graph_renderer, node_manager, log_viewer, lsf,
# email, autoppt, checklist, library/mmmc/qor managers) stayed under
# PD/utils/commands/ after the cbflow_global utils-refactor. run_cmd lives
# under global/utils/commands/ now, so it must put PD-commands on sys.path
# before any `from <pd_module> import ...` fires. Silently skipped when the
# PD/ tree is absent (sparse-checkout on a discipline-only branch) — the
# imports below are each try/except guarded.
try:
    _pd_cmds_bootstrap = os.path.join(get_cbflow_core_dir(), 'utils', 'commands')
    if os.path.isdir(_pd_cmds_bootstrap) and _pd_cmds_bootstrap not in _sys.path:
        _sys.path.insert(0, _pd_cmds_bootstrap)
except Exception:
    pass

logger = configure_logging('cbflow.run')


def _tcl_values(files, keys) -> dict:
    """Source `files` in a tclsh and return {key: value} for each of `keys`
    (Tcl variable names such as `project(block_list)`) that the files set.
    Values are returned verbatim (multi-line safe). Raises RuntimeError when
    tclsh fails — a config that does not source is an error, not a default."""
    _files = ' '.join('{' + f + '}' for f in files)
    _keys = ' '.join('{' + k + '}' for k in keys)
    script = (f'foreach _cbf_f [list {_files}] {{ source $_cbf_f }}\n'
              f'foreach _cbf_k [list {_keys}] {{\n'
              f'    if {{[info exists $_cbf_k]}} {{\n'
              f'        puts "@@CBFLOW_KEY@@$_cbf_k"; puts [set $_cbf_k]; puts "@@CBFLOW_END@@"\n'
              f'    }}\n'
              f'}}\n')
    try:
        proc = subprocess.run(['tclsh'], input=script, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise RuntimeError(f'tclsh failed sourcing {" ".join(files)}: {e}')
    if proc.returncode != 0:
        raise RuntimeError(f'tclsh failed sourcing {" ".join(files)}: {proc.stderr.strip()}')
    out, key, buf = {}, None, []
    for line in proc.stdout.splitlines():
        if line.startswith('@@CBFLOW_KEY@@'):
            key, buf = line[len('@@CBFLOW_KEY@@'):], []
        elif line == '@@CBFLOW_END@@' and key is not None:
            out[key] = '\n'.join(buf)
            key = None
        elif key is not None:
            buf.append(line)
    return out


def _pd_flow_config_file(name: str) -> str:
    """<CBFLOW_CORE_DIR>/config/flow/<FLOW_CONFIG_VERSION>/<name> — the PD
    flow-config files the resolver sources (tool_launch/lsf/release/validation)."""
    path = os.path.join(get_cbflow_core_dir(), 'config', 'flow',
                        registry.config_version('FLOW_CONFIG_VERSION'), name)
    if not os.path.isfile(path):
        raise registry.RegistryError(f'{name} not found: {path}')
    return path


def _node_dir(flow_type: str, node: str, run_dir: str = '') -> str:
    """work/<FLOW>/<node> — mirrors utils.tcl cbflow_node_dir."""
    return os.path.join(run_dir, 'work', flow_type, node) if run_dir else \
        os.path.join('work', flow_type, node)


def _log_error_patterns() -> list:
    """validation(log_error_patterns) from validation_config.tcl — substrings
    that mark a log line as an error in `cbflow run report`."""
    path = _pd_flow_config_file('validation_config.tcl')
    with open(path, encoding='utf-8', errors='replace') as f:
        m = _re_mod.search(r'^\s*set\s+validation\(log_error_patterns\)\s+\{([^}]*)\}',
                           f.read(), _re_mod.M)
    if not m or not m.group(1).split():
        raise registry.RegistryError(f'validation(log_error_patterns) is not set in {path}')
    return m.group(1).split()


def _lsf_tiers() -> list:
    """LSF resource tiers: lsf(available_queues) in lsf_config.tcl."""
    path = _pd_flow_config_file('lsf_config.tcl')
    with open(path, encoding='utf-8', errors='replace') as f:
        m = _re_mod.search(r'^\s*set\s+lsf\(available_queues\)\s+(?:"([^"]*)"|\{([^}]*)\})',
                           f.read(), _re_mod.M)
    tiers = (m.group(1) if m and m.group(1) is not None else (m.group(2) if m else '')).split()
    if not tiers:
        raise registry.RegistryError(f'lsf(available_queues) is not set in {path}')
    return tiers


def _tool_vendor_from_overlay(flow_type: str, tool: str) -> str:
    """tool,vendor from <disc>/config/flow/<ver>/node_configs/<FLOW>_<tool>_config.tcl,
    or '' when the overlay does not exist / declare it."""
    tool_cfg = os.path.join(registry.discipline_dir(registry.flow_discipline(flow_type)),
                            'config', 'flow', registry.config_version('FLOW_CONFIG_VERSION'),
                            'node_configs', f'{flow_type}_{tool}_config.tcl')
    if os.path.isfile(tool_cfg):
        with open(tool_cfg, 'r') as _tcf:
            for _line in _tcf:
                _m = _re_mod.search(r'tool,vendor["\s]+["\s]*([^"}\s]+)', _line)
                if _m:
                    return _m.group(1)
    return ''


def _flow_node_of_type(flow_type: str, node_type: str, run_dir: str) -> str:
    """The node of `flow_type` whose node_types,<node> is `node_type` (from
    the resolved node config of `run_dir`). Raises when there is none."""
    import cbflow_config as _cc
    cfg = _cc.load_resolved_config(flow_type, run_dir=run_dir)
    stages = (_cc.optional(cfg, 'stages') or '').split()
    hits = [s for s in stages if (cfg.get(f'node_types,{s}', '') or '').strip('"') == node_type]
    if not hits:
        raise registry.RegistryError(
            f'{flow_type}: no node with node_types,<node> "{node_type}" in its node config')
    return hits[-1]




def is_run_directory() -> bool:
    """Check if current directory is a valid run directory."""
    # Check for run environment file or Makefile
    return (os.path.exists('.run.cbflow.env') or
            os.path.exists('.run.cbflow.tcl') or
            any(Path('.').glob('.race_*.db')) or
            _is_run_dir_name(os.path.basename(os.getcwd())))


def load_run_env() -> dict:
    """Load .run.cbflow.env as dictionary."""
    env_file = os.path.join(os.getcwd(), '.run.cbflow.env')
    env_vars = {}
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    if line.startswith('export '):
                        line = line[7:]
                    key, value = line.split('=', 1)
                    env_vars[key] = value.strip('"').strip("'")
    return env_vars


def _ensure_run_env_loaded():
    """Load ALL run env vars into os.environ."""
    env_vars = load_run_env()
    for key, val in env_vars.items():
        if val:
            os.environ[key] = val
    # Clear config parser cache since env changed
    from tcl_config_parser import clear_cache
    clear_cache()


def get_flow_type() -> str:
    """Detect flow type from environment or run directory name."""
    _ensure_run_env_loaded()

    # Priority 1: from .run.cbflow.env (most reliable)
    env_vars = load_run_env()
    flow_type = env_vars.get('CBFLOW_FLOW_TYPE', '')
    if flow_type:
        return flow_type.upper()

    # Priority 2: from directory name (P0_run_PNR_run1 -> PNR, P0_run_SYNTH_FP_PNR_run1 -> SYNTH_FP_PNR)
    dirname = os.path.basename(os.getcwd())
    if _is_run_dir_name(dirname):
        parts = dirname.split('_run_', 1)
        if len(parts) > 1:
            # The flow type is everything between _run_ and the last _runname
            # e.g., P0_run_SYNTH_FP_PNR_run1 -> SYNTH_FP_PNR_run1 -> need to strip _run1
            rest = parts[1]
            # Find the run name (last _word segment that looks like a run name)
            # Run names are typically: run1, run2, test, etc.
            # Split from right and try to identify the run name
            segments = rest.rsplit('_', 1)
            if len(segments) == 2 and (segments[1].startswith('run') or segments[1] in ('test',)):
                return segments[0].upper()
            return rest.upper()

    return env_vars.get('FLOW_TYPE', 'UNKNOWN')


def get_flow_stages(flow_type: str, run_dir=None) -> list:
    """Ordered stages for a flow type. `run_dir=None` uses the current run
    dir when invoked from one (so user_config selections — e.g. a tool
    overlay with its own stage list — apply), else the project baseline.
    """
    from tcl_config_parser import is_merged_flow, get_merged_flow_stage_names
    from tcl_config_parser import get_flow_stages as _get_stages

    if is_merged_flow(flow_type):
        return get_merged_flow_stage_names(flow_type)
    if run_dir is None and os.path.exists('.run.cbflow.tcl'):
        run_dir = os.getcwd()
    return _get_stages(flow_type, run_dir=run_dir)


def get_all_stages(flow_type: str) -> list:
    """Get base stages + custom nodes from runtime config (full stage list)."""
    stages = list(get_flow_stages(flow_type))
    custom_data = load_custom_nodes_from_runtime_config()
    for name, info in custom_data.get('nodes', {}).items():
        if name not in stages:
            dep = info.get('dependencies', [''])
            dep_name = dep[0] if isinstance(dep, list) and dep else dep
            if dep_name and dep_name in stages:
                idx = stages.index(dep_name) + 1
                stages.insert(idx, name)
            else:
                stages.append(name)
    return stages


def _get_completed_from_db() -> set:
    """Get completed job names from RACE DB (replaces .stamps/ queries)."""
    try:
        from status_provider import StatusProvider
        provider = StatusProvider(os.getcwd())
        all_status = provider.get_all_status()
        from core.db import COMPLETED_STATES
        return {s for s, v in all_status.items()
                if v.get('status') in COMPLETED_STATES}
    except Exception:
        return set()


def load_custom_nodes_from_runtime_config() -> dict:
    """Load custom nodes from setup/runtime_flow_config.tcl.

    Returns a dict with:
        - 'nodes': dict of {node_name: {'type': str, 'dependencies': list, 'branch_key': str}}
        - 'branches': dict of {branch_key: {'name': str, 'created_by': str, 'created_date': str}}
    """
    runtime_config = os.path.join(os.getcwd(), 'setup', 'runtime_flow_config.tcl')

    result = {
        'nodes': {},
        'branches': {}
    }

    if not os.path.exists(runtime_config):
        return result

    try:
        with open(runtime_config, 'r') as f:
            content = f.read()

        # Parse TCL array set format
        # Look for: array set pnr { ... }
        import re

        # Find array content between braces - handle nested braces properly
        match = re.search(r'array\s+set\s+\w+\s*\{', content)
        if not match:
            return result

        # Find the matching closing brace via the shared word-boundary
        # tokenizer (skips Tcl comments and `"..."` string bodies). Owning
        # the walker in _tcl_utils rather than reaching into
        # checklist_cmd's private symbol means a rename is caught at
        # import time by both consumers, not silently reverted to the
        # buggy naive counter via a swallowed ImportError.
        from _tcl_utils import find_balanced_close as _tclbal
        end_pos_1based = _tclbal(content, match.end(), open_depth=1)
        if end_pos_1based < 0:
            return result
        end_pos = end_pos_1based + 1
        array_content = content[match.end():end_pos-1]

        # Parse key-value pairs from TCL array. Format: key value pairs
        # separated by whitespace; values may be braced `{...}` or
        # double-quoted `"..."` (both can contain whitespace/braces/
        # newlines) or plain barewords. The inner tokenizer used to be a
        # naive brace counter — same class of bug the outer walker was
        # migrated away from — so a legit value like `"a}b"` mis-
        # terminated on the inner `}` and mis-aligned every subsequent
        # token. Now it delegates the `{...}` skip to the shared
        # word-boundary walker and correctly handles `"..."` strings.
        tokens = []
        i = 0
        n_ac = len(array_content)
        while i < n_ac:
            # Skip whitespace
            while i < n_ac and array_content[i] in ' \t\n\r':
                i += 1
            if i >= n_ac:
                break
            c = array_content[i]
            # Comment (`#` at word start — after our whitespace skip we ARE at word start)
            if c == '#':
                while i < n_ac and array_content[i] not in ('\n', '\r'):
                    i += 1
                continue
            # Braced value: use the shared walker so `}` inside a `"..."`
            # inside a `{...}` block doesn't decrement depth prematurely.
            if c == '{':
                start = i + 1
                close = _tclbal(array_content, start, open_depth=1)
                if close < 0:
                    # Unbalanced — bail out rather than emit garbage
                    break
                tokens.append(array_content[start:close])
                i = close + 1
                continue
            # Double-quoted value: skip to matching `"`, honoring `\`
            # escapes. `}` inside is literal — must NOT decrement anything.
            if c == '"':
                i += 1
                start = i
                while i < n_ac and array_content[i] != '"':
                    if array_content[i] == '\\' and i + 1 < n_ac:
                        i += 2
                        continue
                    i += 1
                tokens.append(array_content[start:i])
                if i < n_ac:
                    i += 1  # consume closing `"`
                continue
            # Bareword: stop at whitespace or brace/quote
            start = i
            while i < n_ac and array_content[i] not in ' \t\n\r{}"':
                i += 1
            if start < i:
                tokens.append(array_content[start:i])

        # Process key-value pairs (every two tokens form a key-value pair)
        idx = 0
        while idx < len(tokens) - 1:
            key = tokens[idx]
            value = tokens[idx + 1]
            idx += 2

            # Parse stages,<node_name>,<attribute>
            stage_match = re.match(r'stages,([^,]+),(\w+)', key)
            if stage_match:
                node_name = stage_match.group(1)
                attribute = stage_match.group(2)

                if node_name not in result['nodes']:
                    result['nodes'][node_name] = {}

                if attribute == 'type':
                    result['nodes'][node_name]['type'] = value
                elif attribute == 'dependencies':
                    result['nodes'][node_name]['dependencies'] = value.split() if value else []
                elif attribute == 'branch_key':
                    result['nodes'][node_name]['branch_key'] = value
                elif attribute == 'resource_tier':
                    # Kept in sync with race_engine._load_runtime_custom_nodes
                    # and node_manager._load_runtime_config, both of which
                    # already surface this key.
                    result['nodes'][node_name]['resource_tier'] = value
                continue

            # Parse branch_keys,<branch_key>,<attribute>
            branch_match = re.match(r'branch_keys,([^,]+),(\w+)', key)
            if branch_match:
                branch_key = branch_match.group(1)
                attribute = branch_match.group(2)

                if branch_key not in result['branches']:
                    result['branches'][branch_key] = {}

                result['branches'][branch_key][attribute] = value

    except Exception as e:
        logger.debug(f"Error parsing runtime config: {e}")

    # Filter out incomplete node entries (nodes must have a 'type' to be valid)
    valid_nodes = {}
    for node_name, node_info in result['nodes'].items():
        if 'type' in node_info:
            valid_nodes[node_name] = node_info
    result['nodes'] = valid_nodes

    return result


def get_branch_name_for_node(node_name: str, custom_data: dict) -> str:
    """Get branch name for a node if it belongs to a branch."""
    if node_name not in custom_data['nodes']:
        return None

    node_info = custom_data['nodes'][node_name]
    branch_key = node_info.get('branch_key')

    if not branch_key:
        return None

    branch_info = custom_data['branches'].get(branch_key, {})
    return branch_info.get('name', branch_key)



def run_target(target: str, env_vars: dict = None) -> int:
    """Run a target using RACE (Python-native DAG executor).

    LSF/xterm controlled by flow(use_lsf) and flow(use_xterm) in flow_config.tcl.
    """
    run_dir = os.getcwd()

    # Load run environment
    run_env = load_run_env()
    if env_vars:
        run_env.update(env_vars)

    from race_engine import RaceEngine

    # Add file logging to $run_dir/logs/
    logs_dir = os.path.join(run_dir, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    from logging_config import add_file_handler
    add_file_handler(logger, logs_dir, 'cbflow_run.log')

    flow_type = run_env.get('CBFLOW_FLOW_TYPE', '')
    engine = RaceEngine(run_dir, flow_type, run_env)
    if engine.initialize():
        logger.info(f"RACE: {len(engine.jobs)} jobs, "
                     f"{len(engine.stage_order)} stages")
        result = engine.execute(target)
        logger.info(f"Run completed: target={target} result={'PASS' if result == 0 else 'FAIL'}")
        return result
    else:
        logger.error("RACE initialization failed")
        return 1


# ─────────────────────────────────────────────────────────────────────────────────
# Run Commands
# ─────────────────────────────────────────────────────────────────────────────────

def _dashboard_autoregister(run_dir: str, flow_type: str) -> None:
    """Show this run in its discipline dashboard (if that daemon is running).

    Runs in a short subprocess: the run dashboard and SmartGrid packages both
    ship modules named lifecycle / daemon / state_paths, so importing one
    here would shadow the other later in this process (release publish)."""
    utils_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    code = ("import sys; sys.path[:0] = [%r, %r, %r]; import lifecycle; "
            "r = lifecycle.autoregister(%r, %r); print('ok' if r and r.get('ok') else '')"
            % (os.path.join(utils_dir, 'dashboard'), os.path.join(utils_dir, 'commands'),
               utils_dir, run_dir, flow_type))
    try:
        out = subprocess.run([sys.executable, '-c', code], capture_output=True,
                             text=True, timeout=10).stdout.strip()
        if out == 'ok':
            logger.info(f"  Dashboard: run registered ({flow_type})")
    except Exception:
        pass


def _logical_release_dir(path: str) -> str:
    """<FLOW>/.versions/<tag>/v<n> (where a release node writes) -> <FLOW>/<tag>
    (the current-version link every reader uses)."""
    import re as _re
    m = _re.match(r'^(.*)/\.versions/([^/]+)/v\d+/?$', path or '')
    return os.path.join(m.group(1), m.group(2)) if m else path


def _new_release_version(logical: str) -> str:
    """Next version dir <FLOW>/.versions/<tag>/v<n> of a release (a legacy
    unversioned <FLOW>/<tag> dir becomes v1 first)."""
    import re as _re
    vroot = os.path.join(os.path.dirname(logical), '.versions', os.path.basename(logical))
    if os.path.isdir(logical) and not os.path.islink(logical):
        os.makedirs(vroot, exist_ok=True)
        os.rename(logical, os.path.join(vroot, 'v1'))
    n = max([int(m.group(1)) for d in (os.listdir(vroot) if os.path.isdir(vroot) else [])
             for m in [_re.match(r'^v(\d+)$', d)] if m] or [0]) + 1
    return os.path.join(vroot, f'v{n}')


def _set_current_version(logical: str, vdir: str):
    """<FLOW>/<tag> -> .versions/<tag>/v<n>, replaced atomically."""
    tmp = f'{logical}.tmp{os.getpid()}'
    os.symlink(os.path.relpath(vdir, os.path.dirname(logical)), tmp)
    os.replace(tmp, logical)


def _flow_release_manifest(run_dir: str, node: str = ''):
    """{release_dir, milestone, ...} from a run whose own release_data stage
    released it (work/<FLOW>/<node>/outputs/release.manifest — node: a given
    release node, e.g. release_data2 added under an export of place; default
    the flow's release_data node), else {}."""
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    flow_type = ''
    if os.path.exists(env_file):
        with open(env_file) as fh:
            for line in fh:
                if line.startswith('export CBFLOW_FLOW_TYPE='):
                    flow_type = line.split('=', 1)[1].strip().strip('"')
    info = {}
    if not flow_type:
        return info
    try:
        release_node = node or _flow_node_of_type(flow_type, 'release_data', run_dir)
    except registry.RegistryError:
        return info            # flow has no release_data stage → no flow release
    manifest = os.path.join(_node_dir(flow_type, release_node, run_dir),
                            'outputs', 'release.manifest')
    if os.path.isfile(manifest):
        with open(manifest) as fh:
            for line in fh:
                parts = line.strip().split(None, 1)
                if len(parts) == 2:
                    info[parts[0]] = parts[1]
        if info.get('release_dir'):
            info['release_dir'] = _logical_release_dir(info['release_dir'])
        info['flow_type'] = flow_type
    return info


def _publish_signoff_release(run_dir: str, info: dict, strict: bool) -> int:
    """Publish a signoff run (STA / PV / LEC …) as its own SmartGrid run,
    attached to the exit it verified — that exit must already be published."""
    env_vars = {}
    with open(os.path.join(run_dir, '.run.cbflow.env')) as fh:
        for line in fh:
            line = line.strip()
            if line.startswith('export ') and '=' in line:
                k, v = line[7:].split('=', 1)
                env_vars[k] = v.strip('"')
    project = env_vars.get('CBFLOW_PROJECT_NAME', '')
    block = env_vars.get('CBFLOW_DESIGN_NAME', '')
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')
    exit_tag = info['attach_to']
    pd_pkg = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          'project_dashboard')
    if pd_pkg not in sys.path:
        sys.path.insert(0, pd_pkg)
    import importlib.util as _ilu
    import tracker_db as _tdb
    spec = _ilu.spec_from_file_location('_pd_state_paths', os.path.join(pd_pkg, 'state_paths.py'))
    sp = _ilu.module_from_spec(spec); spec.loader.exec_module(sp)
    rows = [r for r in _tdb.list_published(sp.tracker_db(project), project)
            if r['block'] == block and r['phase'] == phase and r['milestone'] == exit_tag]
    if not rows or not rows[0].get('run_dir') or not os.path.isdir(rows[0]['run_dir']):
        logger.error(f"  Not published: {block} / {phase} has no {exit_tag} entry to attach "
                     f"{info.get('flow_type')} to — publish the {exit_tag} release first.")
        return 1
    logger.info(f"  {info.get('flow_type')} run verifies {block} / {phase} / {exit_tag} "
                f"({os.path.basename(rows[0]['run_dir'])})")
    return _publish_flow_release(run_dir, exit_tag, strict=strict, override=True,
                                 attach_to=exit_tag)


def _clone_release(run_dir: str, src_tag: str, new_tag: str, node: str = '',
                   publish=None, override: bool = False) -> int:
    """Copy a flow release to another exit tag — e.g. BTO to MTO when the
    data does not change. Same block / phase / flow (the run's), the source
    must be complete, the two exits must map to the same stage
    (MILESTONE_STAGE_MAPPING), and every earlier exit of the phase must be
    released (exit order). The copy records CLONED_FROM; --publish publishes
    it to the new milestone."""
    import json
    import shutil
    if not new_tag:
        logger.error("  --clone-from needs --tag <new exit>, e.g. --clone-from BTO --tag MTO")
        return 1
    info = _flow_release_manifest(run_dir, node)
    rel_dir = info.get('release_dir', '')
    if not rel_dir:
        logger.error(f"  {run_dir}: no flow release (release_data stage not complete?)")
        return 1
    flow_dir = os.path.dirname(rel_dir)                 # <base>/<phase>/<block>/<FLOW>
    block_dir = os.path.dirname(flow_dir)
    phase_dir = os.path.dirname(block_dir)
    phase, block = os.path.basename(phase_dir), os.path.basename(block_dir)
    src, dst = os.path.join(flow_dir, src_tag), os.path.join(flow_dir, new_tag)
    stamp = os.path.join(src, 'RELEASE_COMPLETE')
    if not os.path.isfile(stamp) or 'STATUS=PASS' not in open(stamp).read():
        logger.error(f"  source release not complete: {src}")
        return 1
    env_vars = {}
    with open(os.path.join(run_dir, '.run.cbflow.env')) as fh:
        for line in fh:
            line = line.strip()
            if line.startswith('export ') and '=' in line:
                k, v = line[7:].split('=', 1)
                env_vars[k] = v.strip('"')
    project = env_vars.get('CBFLOW_PROJECT_NAME', '')
    try:
        exits = release_exits.exits_for_phase(project, phase)
        stage_of = release_exits.milestone_stage_mapping()
    except release_exits.PhaseExitsError as e:
        logger.error(f"  {e}")
        return 1
    if new_tag in exits:
        if src_tag in stage_of and stage_of.get(new_tag) != stage_of.get(src_tag):
            logger.error(f"  {new_tag} is the {stage_of.get(new_tag)} exit, {src_tag} the "
                         f"{stage_of.get(src_tag)} exit — a clone keeps the data, so the "
                         f"exits must map to the same stage")
            return 1
        missing = [e for e in exits[:exits.index(new_tag)]
                   if not glob.glob(os.path.join(block_dir, '*', e, 'RELEASE_COMPLETE'))]
        if missing:
            logger.error(f"  exit order — {block} {phase} cannot release {new_tag} before "
                         f"{', '.join(missing)} (release in order: {' -> '.join(exits)})")
            return 1
    # a locked exit (cbflow flow release lock) takes no clone
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import candidate_cmd as _cand
    _lk = _cand.locked({'release': os.path.dirname(phase_dir)}, phase, block, info['flow_type'], new_tag)
    if _lk:
        logger.error(f"  clone into {new_tag} refused — exit {_lk['exit']} is LOCKED by {_lk['user']} "
                     f"({_lk['at']}): {_lk['reason']}")
        return 1
    # a new version of the destination tag; current moves to it below
    vdst = _new_release_version(dst)
    shutil.copytree(os.path.realpath(src), vdst, symlinks=True)
    mpath = os.path.join(vdst, 'MANIFEST.json')
    if os.path.isfile(mpath):
        with open(mpath) as fh:
            m = json.load(fh)
        m['release_tag'] = new_tag
        m['cloned_from'] = src_tag
        m['cloned_from_version'] = os.path.basename(os.path.realpath(src))
        m['version'] = os.path.basename(vdst)
        m['storage'] = os.path.realpath(vdst)
        m['timestamp'] = datetime.now().isoformat(timespec='seconds')
        with open(mpath, 'w') as fh:
            json.dump(m, fh, indent=2)
    with open(os.path.join(vdst, 'RELEASE_COMPLETE')) as fh:
        st = fh.read()
    st = _re_mod.sub(r'^TAG=.*$', f'TAG={new_tag}', st, flags=_re_mod.M)
    with open(os.path.join(vdst, 'RELEASE_COMPLETE'), 'w') as fh:
        fh.write(st)
    with open(os.path.join(vdst, 'CLONED_FROM'), 'w') as fh:
        fh.write(f"{os.path.realpath(src)}\n")
    _set_current_version(dst, vdst)
    logger.info(f"  Cloned {src_tag} -> {new_tag}: {dst}")
    if not publish:
        logger.info("  Not published to SmartGrid (publish not requested — use --publish).")
        return 0
    try:
        milestone_stage_map = release_exits.milestone_stage_mapping()
    except release_exits.PhaseExitsError as e:
        logger.error(f"  {e}")
        return 1
    return _publish_to_project_dashboard(
        project=project, block=env_vars.get('CBFLOW_DESIGN_NAME', block), phase=phase,
        milestone=new_tag, release_dir=dst,
        workspace=os.path.dirname(os.path.abspath(run_dir)),
        runs={info['flow_type']: os.path.basename(os.path.abspath(run_dir))},
        milestone_stage_map=milestone_stage_map, override=override, strict=True,
        flow=info['flow_type'])


def _publish_flow_release(run_dir: str, milestone: str, strict: bool, override: bool,
                          attach_to: str = '', node: str = '') -> int:
    """Publish the release a flow's own release_data stage wrote (no
    repackaging) into the SmartGrid cell (project, block, phase, milestone).
    Used by `cbflow run release --from-run <run> --publish` and the run GUI's
    Release form (publish checkbox)."""
    info = _flow_release_manifest(run_dir, node)
    release_dir = info.get('release_dir', '')
    if not release_dir or not os.path.isdir(release_dir):
        logger.error(f"  {run_dir}: no flow release found (release_data stage not complete?)")
        return 1
    env_vars = {}
    with open(os.path.join(run_dir, '.run.cbflow.env')) as fh:
        for line in fh:
            line = line.strip()
            if line.startswith('export ') and '=' in line:
                k, v = line[7:].split('=', 1)
                env_vars[k] = v.strip('"')
    project_name = env_vars.get('CBFLOW_PROJECT_NAME', env_vars.get('PROJECT_NAME', ''))
    design_name = env_vars.get('CBFLOW_DESIGN_NAME', '')
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')
    try:
        milestone_stage_map = release_exits.milestone_stage_mapping()
    except release_exits.PhaseExitsError as e:
        logger.error(f"  {e}")
        return 1
    return _publish_to_project_dashboard(
        project=project_name, block=design_name, phase=phase,
        milestone=milestone, release_dir=release_dir,
        workspace=os.path.dirname(os.path.abspath(run_dir)),
        runs={info['flow_type']: os.path.basename(os.path.abspath(run_dir))},
        milestone_stage_map=milestone_stage_map, override=override, strict=strict,
        flow=info['flow_type'], attach_to=attach_to)


def cmd_all(args: argparse.Namespace) -> int:
    """Run complete flow (all stages)."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    flow_type = get_flow_type()
    _dashboard_autoregister(os.getcwd(), flow_type)
    validate = getattr(args, 'validate', False)
    use_lsf = getattr(args, 'lsf', False)
    lsf_queue = getattr(args, 'queue', None)
    collect_metrics = getattr(args, 'collect_metrics', False)

    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  Running Complete {flow_type} Flow")
    if validate:
        logger.info(f"  Validation:   ENABLED")
    if use_lsf:
        logger.info(f"  LSF:            ENABLED (queue: {lsf_queue or 'auto'})")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info("")

    # Pre-run validation
    if validate:
        from validation_cmd import ValidationRunner
        runner = ValidationRunner(run_dir=os.getcwd(), flow_type=flow_type)
        pre_result = runner.run_pre_stage('all')
        if not pre_result['passed']:
            logger.error("Pre-run validation failed. Fix issues before running.")
            runner.print_report()
            return 1
        logger.info("Pre-run validation passed")

    result = run_target('all', load_run_env())

    # Post-run validation
    if validate and result == 0:
        from validation_cmd import ValidationRunner
        runner = ValidationRunner(run_dir=os.getcwd(), flow_type=flow_type)
        stages = get_flow_stages(flow_type)
        if stages:
            last_stage = stages[-1]
            runner.run_post_stage(last_stage)
            runner.check_exit_criteria(last_stage)
            runner.print_report()

    # Collect metrics if requested
    if collect_metrics or os.environ.get('CBFLOW_COLLECT_METRICS', '').lower() in ('1', 'true', 'yes'):
        try:
            from metrics_cmd import MetricsCollector
            collector = MetricsCollector()
            collector.collect_run_metrics(os.getcwd())
            collector.db.close()
        except Exception as e:
            # Was logged at DEBUG, which hid metric collection failures
            # (full-disk, DB lock) from operators. Promote to WARNING so
            # the message is visible in normal runs without changing log
            # verbosity. Metrics are non-blocking (run already finished)
            # so we don't propagate.
            logger.warning(f"Metrics collection skipped: {e}", exc_info=True)

    return result


def cmd_stage(args: argparse.Namespace) -> int:
    """Run a specific stage."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    stage = args.stage
    subnode = getattr(args, 'subnode', None)
    flow_type = get_flow_type()
    _dashboard_autoregister(os.getcwd(), flow_type)
    valid_stages = get_all_stages(flow_type)
    validate = getattr(args, 'validate', False)
    use_lsf = getattr(args, 'lsf', False)
    lsf_queue = getattr(args, 'queue', None)

    if stage not in valid_stages and stage != 'all':
        logger.error(f"Invalid stage: {stage}")
        logger.info(f"Valid stages for {flow_type}: {', '.join(valid_stages)}")
        return 1

    # Single subnode execution
    if subnode:
        _ensure_run_env_loaded()
        run_dir = os.getcwd()
        target = f"{stage}_{subnode}"
        logger.info(f"")
        logger.info(f"  Running {flow_type} Subnode: {stage} / {subnode}")
        logger.info(f"  ───────────────────────────────────────────────────────")
        logger.info(f"")
        result = run_target(target, load_run_env())
        return result

    # Pre-stage validation
    if validate:
        from validation_cmd import ValidationRunner
        runner = ValidationRunner(run_dir=os.getcwd(), flow_type=flow_type)
        pre_result = runner.run_pre_stage(stage)
        if not pre_result['passed']:
            logger.error(f"Pre-stage validation failed for {stage}")
            runner.print_report()
            return 1

    logger.info(f"")
    logger.info(f"  Running {flow_type} Stage: {stage}")
    logger.info(f"  ───────────────────────────────────────────────────────")
    logger.info(f"")
    result = run_target(stage, load_run_env())

    # Post-stage validation
    if validate and result == 0:
        from validation_cmd import ValidationRunner
        runner = ValidationRunner(run_dir=os.getcwd(), flow_type=flow_type)
        runner.run_post_stage(stage)
        runner.check_exit_criteria(stage)
        runner.print_report()

    return result


def _split_targets(names, valid_stages, engine):
    """(stages, jobs) from bypass / force / forcevalidate targets: a stage
    (timing1), a scenario subnode as <stage>:<scenario>
    (timing1:func_ss_1p60v_rc_max_100c) or its job name
    (timing1_func_ss_1p60v_rc_max_100c). Raises ValueError listing the
    stage's scenarios when a target matches nothing."""
    stages, jobs = [], []
    for n in names:
        if n in valid_stages:
            stages.append(n)
            continue
        job = n.replace(':', '_', 1) if ':' in n else n
        j = engine.jobs.get(job)
        if j is not None and getattr(j, 'job_type', 'subnode') != 'stage':
            jobs.append(job)
            continue
        stage = n.split(':', 1)[0] if ':' in n else next(
            (st for st in valid_stages if n.startswith(st + '_')), '')
        if stage in valid_stages:
            subs = sorted(x.split(stage + '_', 1)[1] for x, jj in engine.jobs.items()
                          if jj.stage == stage and x.startswith(stage + '_')
                          and x.split(stage + '_', 1)[1] not in ('setup', 'run', 'validate', 'finish'))
            raise ValueError(f"{n}: no such subnode of {stage}"
                             + (f" — scenarios: {', '.join(subs)}" if subs else ' (it has no scenario subnodes)'))
        raise ValueError(f"Invalid stage: {n}. Valid: {', '.join(valid_stages)} "
                         "(a scenario subnode as <stage>:<scenario>)")
    return stages, jobs


def cmd_bypass(args: argparse.Namespace) -> int:
    """Bypass (skip) stages — mark as DONE without executing."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    names = [s.strip() for s in args.stages.split(',') if s.strip()]
    flow_type = get_flow_type()
    valid = get_all_stages(flow_type)

    from race_engine import RaceEngine
    run_env = load_run_env()
    engine = RaceEngine(os.getcwd(), flow_type, run_env)
    if not engine.initialize():
        return 1
    try:
        stages, jobs = _split_targets(names, valid, engine)
    except ValueError as e:
        logger.error(str(e))
        return 1
    rc = 0
    if stages:
        logger.info(f"Bypassing stages: {', '.join(stages)}")
        rc = engine.bypass(stages)
    if jobs and rc == 0:
        logger.info(f"Bypassing subnodes: {', '.join(jobs)}")
        rc = engine.bypass_jobs(jobs)
    return rc


def cmd_forcevalidate(args: argparse.Namespace) -> int:
    """Mark stages as already completed (ran outside CBflow)."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    flow_type = get_flow_type()
    all_stages = get_all_stages(flow_type)

    # Resolve which stages to forcevalidate
    stages = []
    if getattr(args, 'node', None):
        # Single node
        stages = [args.node]
    elif getattr(args, 'from_stage', None) and getattr(args, 'to_stage', None):
        # Range: --from X --to Y
        from_idx = all_stages.index(args.from_stage) if args.from_stage in all_stages else -1
        to_idx = all_stages.index(args.to_stage) if args.to_stage in all_stages else -1
        if from_idx < 0:
            logger.error(f"Invalid --from stage: {args.from_stage}")
            return 1
        if to_idx < 0:
            logger.error(f"Invalid --to stage: {args.to_stage}")
            return 1
        stages = all_stages[from_idx:to_idx + 1]
    elif getattr(args, 'from_stage', None):
        # From X to end
        from_idx = all_stages.index(args.from_stage) if args.from_stage in all_stages else -1
        if from_idx < 0:
            logger.error(f"Invalid --from stage: {args.from_stage}")
            return 1
        stages = all_stages[from_idx:]
    elif getattr(args, 'to_stage', None):
        # From start to Y
        to_idx = all_stages.index(args.to_stage) if args.to_stage in all_stages else -1
        if to_idx < 0:
            logger.error(f"Invalid --to stage: {args.to_stage}")
            return 1
        stages = all_stages[:to_idx + 1]
    elif getattr(args, 'stages', None):
        # Comma-separated list (backward compat)
        stages = [s.strip() for s in args.stages.split(',')]
    else:
        logger.error("Specify --node, --from/--to, or --stages")
        return 1

    from race_engine import RaceEngine
    run_env = load_run_env()
    engine = RaceEngine(os.getcwd(), flow_type, run_env)
    if not engine.initialize():
        return 1
    try:
        stages, jobs = _split_targets(stages, all_stages, engine)
    except ValueError as e:
        logger.error(str(e))
        return 1
    rc = 0
    if stages:
        logger.info(f"Force-validating: {', '.join(stages)}")
        rc = engine.forcevalidate(stages)
    if jobs and rc == 0:
        logger.info(f"Force-validating subnodes: {', '.join(jobs)}")
        rc = engine.forcevalidate_jobs(jobs)
    return rc


def cmd_force(args: argparse.Namespace) -> int:
    """Force re-run specific stages only (no downstream invalidation)."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    names = [s.strip() for s in args.stages.split(',') if s.strip()]
    flow_type = get_flow_type()
    valid = get_all_stages(flow_type)

    from race_engine import RaceEngine
    run_env = load_run_env()
    engine = RaceEngine(os.getcwd(), flow_type, run_env)
    if not engine.initialize():
        return 1
    try:
        stages, jobs = _split_targets(names, valid, engine)
    except ValueError as e:
        logger.error(str(e))
        return 1
    rc = 0
    if stages:
        logger.info(f"Force re-running stages: {', '.join(stages)}")
        rc = engine.force(stages)
    if jobs and rc == 0:
        logger.info(f"Force re-running subnodes: {', '.join(jobs)}")
        rc = engine.force_jobs(jobs)
    return rc


def cmd_debug(args: argparse.Namespace) -> int:
    """Inspect the engine-visible config cascade.

    --dump-resolved-cfg → every key the engine sees, sorted, one per line.
    --key 'flow(use_lsf)' → single key, value + cascade source files.
    """
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    flow_type = get_flow_type()
    run_dir = os.getcwd()
    env = load_run_env()

    import cbflow_config as _cbc
    try:
        cfg = _cbc.load_resolved_config(flow_type, run_dir, env=env)
    except Exception as e:
        logger.error(f"resolver failed: {e}")
        return 2

    sources = cfg.get('_sources', '')
    schema = cfg.get('_schema_version', '?')

    if args.key:
        key = args.key
        if key in cfg:
            print(f"{key}={cfg[key]}")
            if sources:
                print(f"  contributing sources: {sources}")
            return 0
        print(f"# key not in resolved cascade: {key}")
        print(f"# contributing sources: {sources or '<unknown>'}")
        return 3

    if not args.dump_resolved_cfg:
        logger.error("Pass --dump-resolved-cfg (full dump) or --key <name> "
                     "(single key + sources)")
        return 1

    print(f"# CBflow resolved-config dump (schema v{schema})")
    print(f"# flow={flow_type} run_dir={run_dir}")
    print(f"# sources: {sources}")
    print(f"# {len(cfg)} keys")
    print()
    for key in sorted(cfg.keys()):
        print(f"{key}={cfg[key]}")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    """Show run status."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    # Set up file output if requested
    output_file = getattr(args, 'output', None)
    file_handler = None
    if output_file:
        file_handler = logging.FileHandler(output_file, mode='w')
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(logging.Formatter('%(message)s'))
        logger.addHandler(file_handler)

    flow_type = get_flow_type()
    base_stages = get_flow_stages(flow_type)

    # Load custom nodes from runtime config
    custom_data = load_custom_nodes_from_runtime_config()
    custom_nodes = custom_data['nodes']
    branches = custom_data['branches']

    logger.info("")
    logger.info(f"  {flow_type} Run Status")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info("")
    logger.info(f"  Run Directory:  {os.getcwd()}")
    logger.info(f"  Flow Type:      {flow_type}")
    logger.info("")

    # ── Get status from engine DB ──────────────────────────────────────────
    from status_provider import get_status_provider
    status_prov = get_status_provider(os.getcwd())
    using_db = status_prov.db_exists()

    logger.info(f"  Dispatcher:     RACE")
    if using_db:
        logger.info(f"  Status DB:      {status_prov.db_path}")
    else:
        logger.info(f"  Status DB:      (not yet created — run a stage first)")

    all_status = status_prov.get_all_status()
    completed = [s for s, info in all_status.items() if info.get('status') == 'DONE']

    def show_stage_status(stage, label_suffix=""):
        """Helper to display stage status from DB or stamps."""
        label = f"{stage}{label_suffix}"
        info = all_status.get(stage, {})
        status = info.get('status', '')
        ts = info.get('timestamp', '')

        if status == 'DONE':
            runtime = ''
            if using_db:
                rt = status_prov.get_stage_runtime(stage)
                if rt > 0:
                    runtime = f" ({rt:.1f}s)"
            logger.info(f"  [DONE] {label:<30} {ts}{runtime}")
        elif status == 'RUNNING':
            logger.info(f"  [RUN ] {label:<30} running")
        elif status == 'PENDING':
            logger.info(f"  [PEND] {label:<30} waiting for deps")
        elif status == 'FAIL':
            logger.info(f"  [FAIL] {label:<30} {ts}")
        elif status == 'INVALIDATED':
            logger.info(f"  [INVD] {label:<30} needs rerun")
        else:
            logger.info(f"  [RDY ] {label:<30}")

    # Show status for base stages
    show_details = getattr(args, 'details', False)
    logger.info(f"  Stage Progress: {len([s for s in base_stages if s in completed])}/{len(base_stages)}")
    logger.info(f"  ─────────────────────────────────────────────────────────")
    for stage in base_stages:
        show_stage_status(stage)
        if show_details:
            # Show subnode status from DB or stamps
            from tcl_config_parser import get_subnodes
            subnodes = get_subnodes(flow_type, stage)

            if subnodes == ['dynamic']:
                # Dynamic stage — discover subnodes from DB or stamps
                stage_base = stage.rstrip('0123456789')
                dynamic_subs = [s for s in completed if s.startswith(f'{stage_base}_')]
                if dynamic_subs:
                    for ss in sorted(dynamic_subs):
                        scenario = ss.replace(f'{stage_base}_', '', 1)
                        sub_info = status_prov.get_subnode_status(stage, scenario)
                        ts = sub_info.get('timestamp', '')
                        logger.info(f"      [DONE] {scenario:<40} {ts}")
                else:
                    logger.info(f"      [    ] (no scenarios executed yet)")
            else:
                for subnode in subnodes:
                    sub_info = status_prov.get_subnode_status(stage, subnode)
                    sub_status = sub_info.get('status', '')
                    ts = sub_info.get('timestamp', '')
                    if sub_status == 'DONE':
                        logger.info(f"      [DONE] {subnode:<24} {ts}")
                    elif sub_status == 'FAIL':
                        logger.info(f"      [FAIL] {subnode:<24} {ts}")
                    else:
                        logger.info(f"      [    ] {subnode:<24}")

    # Show status for branch nodes (custom nodes)
    if custom_nodes:
        # Group nodes by branch
        branch_nodes = {}  # branch_key -> list of nodes
        unbranched_nodes = []

        for node_name, node_info in custom_nodes.items():
            branch_key = node_info.get('branch_key')
            if branch_key:
                if branch_key not in branch_nodes:
                    branch_nodes[branch_key] = []
                branch_nodes[branch_key].append((node_name, node_info))
            else:
                unbranched_nodes.append((node_name, node_info))

        # Show branch nodes grouped by branch
        if branch_nodes:
            logger.info("")
            logger.info("Branch Stage Status:")
            for branch_key in sorted(branch_nodes.keys()):
                branch_info = branches.get(branch_key, {})
                branch_name = branch_info.get('name', branch_key)
                logger.info(f"  [{branch_name}]")

                # Sort nodes by dependency order (topological sort)
                nodes = branch_nodes[branch_key]
                node_names = {n[0] for n in nodes}
                sorted_nodes = []
                remaining = list(nodes)
                # Build a simple dependency-based sort
                added = set()
                max_iterations = len(remaining) * len(remaining)
                iterations = 0
                while remaining and iterations < max_iterations:
                    iterations += 1
                    for item in remaining:
                        deps = item[1].get('dependencies', [])
                        # A node is ready if all its deps in this branch are already added
                        branch_deps = [d for d in deps if d in node_names]
                        if all(d in added for d in branch_deps):
                            sorted_nodes.append(item)
                            added.add(item[0])
                            remaining.remove(item)
                            break
                # Add any remaining nodes that couldn't be sorted
                sorted_nodes.extend(remaining)
                nodes = sorted_nodes

                for node_name, node_info in nodes:
                    node_type = node_info.get('type', 'unknown')
                    show_stage_status(node_name, f" [{node_type}]")
                    if show_details:
                        from tcl_config_parser import get_subnodes
                        # Use the base type (without suffix) to look up subnodes
                        import re
                        base_type = re.sub(r'[0-9]+$', '', node_type)
                        subnodes = get_subnodes(flow_type, base_type)
                        for subnode in subnodes:
                            subnode_stamp = f"{node_name}_{subnode}"
                            if subnode_stamp in completed:
                                logger.info(f"      [DONE] {subnode:<24}")
                            else:
                                logger.info(f"      [    ] {subnode:<24}")

        # Show unbranched custom nodes
        if unbranched_nodes:
            logger.info("")
            logger.info("Custom Nodes:")
            for node_name, node_info in unbranched_nodes:
                node_type = node_info.get('type', 'unknown')
                show_stage_status(node_name, f" [{node_type}]")

    logger.info("")
    total_stages = len(base_stages) + len(custom_nodes)
    completed_count = len(completed)
    logger.info(f"  Progress: {completed_count}/{total_stages} stages completed")

    # Show branch summary
    if branches:
        logger.info("")
        logger.info(f"Branches: {len(branches)}")
        for branch_key, branch_info in branches.items():
            branch_name = branch_info.get('name', branch_key)
            created_date = branch_info.get('created_date', 'unknown')
            logger.info(f"  - {branch_name} (created: {created_date})")

    # Show run result from DB
    if using_db and getattr(args, 'details', False):
        logger.info("")
        try:
            from race_engine import StatusDB
            import hashlib
            uid = hashlib.md5(os.path.abspath(os.getcwd()).encode()).hexdigest()[:6]
            db = StatusDB.__new__(StatusDB)
            db.db_path = status_prov.db_path
            result = db.get_run_info('result')
            started = db.get_run_info('started')
            completed_at = db.get_run_info('completed')
            if result:
                logger.info(f"  Run Result:  {result}")
            if started:
                logger.info(f"  Started:     {started}")
            if completed_at:
                logger.info(f"  Completed:   {completed_at}")
        except Exception:
            pass

    logger.info("")

    # Clean up file handler
    if file_handler:
        logger.removeHandler(file_handler)
        file_handler.close()
        logger.info(f"Status dumped to: {output_file}")

    return 0


def cmd_retrace(args: argparse.Namespace) -> int:
    """Remove stamps to force rerun."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    from_stage = getattr(args, 'from_stage', None)
    flow_type = get_flow_type()
    all_stages = get_all_stages(flow_type)

    if from_stage and from_stage not in all_stages:
        logger.error(f"Invalid stage: {from_stage}")
        logger.info(f"Valid stages: {', '.join(all_stages)}")
        return 1

    # ── Determine stages to clear ────────────────────────────────────────
    if from_stage:
        stage_idx = all_stages.index(from_stage)
        stages_to_clear = all_stages[stage_idx:]
    else:
        stages_to_clear = list(all_stages)

    # ── Show what will be cleared ─────────────────────────────────────────
    logger.info("")
    logger.info(f"  Retrace {'from ' + from_stage if from_stage else '(complete)'}")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info("")
    logger.info(f"  Stages to invalidate ({len(stages_to_clear)}):")
    for stage in stages_to_clear:
        logger.info(f"    [CLEAR] {stage}")
    logger.info("")

    # ── Progress bar while clearing ───────────────────────────────────────
    import time as _time
    import sys as _sys

    bar_width = 40
    total = len(stages_to_clear)

    from race_engine import RaceEngine
    run_env = load_run_env()
    engine = RaceEngine(os.getcwd(), flow_type, run_env)
    if not engine.initialize():
        logger.error("RACE initialization failed — cannot retrace")
        return 1

    for i, stage in enumerate(stages_to_clear):
        # Progress bar
        pct = int((i + 1) / total * 100)
        filled = int(bar_width * (i + 1) / total)
        bar = '\033[32m' + '#' * filled + '\033[0m' + '-' * (bar_width - filled)
        _sys.stderr.write(f'\r  [{bar}] {pct:3d}%  Invalidating {stage}...')
        _sys.stderr.flush()

        # Invalidate this stage in engine (any status except already INVALIDATED)
        for name, job in engine.jobs.items():
            if job.stage == stage and job.status != 'INVALIDATED':
                job.status = 'INVALIDATED'

        # Pace the progress bar (~0.5s per stage)
        _time.sleep(0.5)

    # Update DB
    invalidated = [n for n, j in engine.jobs.items() if j.stage in stages_to_clear]
    engine.db.invalidate(invalidated)

    _sys.stderr.write(f'\r  [\033[32m{"#" * bar_width}\033[0m] 100%  Complete.{" " * 30}\n')
    _sys.stderr.flush()

    # ── Summary ───────────────────────────────────────────────────────────
    logger.info("")
    logger.info(f"  Retrace Summary")
    logger.info(f"  ─────────────────────────────────")
    logger.info(f"  Stages cleared:  {len(stages_to_clear)}")
    logger.info(f"  Jobs invalidated: {len(invalidated)}")
    if from_stage:
        logger.info(f"  From stage:      {from_stage}")
    else:
        logger.info(f"  Scope:           all stages")
    logger.info(f"  Status:          Ready to rerun")
    logger.info("")

    # Run if --run flag is set
    if getattr(args, 'run', False):
        logger.info("  Re-running flow...")
        return run_target('all', load_run_env())

    logger.info(f"  To rerun: cbflow run all")
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    """Generate detailed per-node report with setup, outputs, errors."""
    if not is_run_directory():
        logger.error("Not in a valid run directory")
        return 1

    flow_type = get_flow_type()
    run_dir = os.getcwd()
    stages = get_flow_stages(flow_type, run_dir=run_dir)

    from tcl_config_parser import get_subnodes, _load_node_config, _parse_tcl_list
    node_config = _load_node_config(flow_type, run_dir=run_dir)

    completed = _get_completed_from_db()

    # Resolve tool info for cmd_file path - read from config, fallback to run env
    import re as _re
    env_vars = load_run_env()
    vendor = (node_config.get('tool,vendor', '').strip('"')
              or env_vars.get('CBFLOW_TOOL_VENDOR', '')
              or os.environ.get('CBFLOW_TOOL_VENDOR', ''))
    tool = (node_config.get('tool,name', '').strip('"')
            or env_vars.get('CBFLOW_TOOL_NAME', '')
            or os.environ.get('CBFLOW_TOOL_NAME', ''))
    version = (node_config.get('tool,version', '').strip('"')
               or env_vars.get('CBFLOW_TOOL_VERSION', '')
               or os.environ.get('CBFLOW_TOOL_VERSION', ''))
    # Command files live under the flow's discipline root (flow_registry.tcl).
    try:
        core_dir = registry.discipline_dir(registry.flow_discipline(flow_type))
        # Auto-resolve vendor from tool-specific config: <FLOW>_<tool>_config.tcl
        if not vendor and tool:
            vendor = _tool_vendor_from_overlay(flow_type, tool)
        log_error_patterns = _log_error_patterns()
    except registry.RegistryError as e:
        logger.error(str(e))
        return 1

    dump_setup = getattr(args, 'dump_setup', True)
    filter_node = getattr(args, 'node', None)

    # Filter stages if --node specified
    if filter_node:
        matching = [s for s in stages if s == filter_node]
        if not matching:
            logger.error(f"Node '{filter_node}' not found. Available: {', '.join(stages)}")
            return 1
        stages = matching

    sep = '=' * 72
    thin = '-' * 72

    logger.info('')
    logger.info(f'  {sep}')
    logger.info(f'  {flow_type} DETAILED NODE REPORT')
    logger.info(f'  {sep}')
    logger.info(f'  Run Dir: {os.getcwd()}')
    logger.info(f'  Tool:    {vendor}/{tool}/{version}')
    logger.info('')

    for stage in stages:
        subnodes = get_subnodes(flow_type, stage)
        stage_done = stage in completed
        status = 'DONE' if stage_done else 'READY'
        cmd_base = _re.sub(r'\d+$', '', stage)

        logger.info(f'  {thin}')
        logger.info(f'  [{status}]  {stage}')
        logger.info(f'  {thin}')

        # --- Subnodes ---
        logger.info(f'    Subnodes: {", ".join(subnodes)}')
        for sn in subnodes:
            sn_key = f'{stage}_{sn}'
            sn_done = sn_key in completed
            icon = '[done]' if sn_done else '[    ]'
            ts = ''
            logger.info(f'      {icon} {sn:<20} {ts}')

        # --- Setup files ---
        # Node files live in work/<FLOW>/<node>/run/ (cbflow_node_dir layout).
        node_dir = _node_dir(flow_type, stage)
        setup_paths = [os.path.join(node_dir, 'run', 'setup.tcl')]
        config_paths = [os.path.join(node_dir, 'run', 'config.tcl')]

        logger.info(f'')
        logger.info(f'    Setup Files:')

        setup_found = None
        for sp in setup_paths:
            if os.path.exists(sp):
                setup_found = sp
                break
        if setup_found:
            size = os.path.getsize(setup_found)
            logger.info(f'      [found] setup.tcl  ({size} bytes) -> {setup_found}')
            if dump_setup and size > 0:
                logger.info(f'      --- setup.tcl contents ---')
                with open(setup_found, 'r') as f:
                    lines = f.readlines()
                for i, line in enumerate(lines[:50]):
                    logger.info(f'        {i+1:>3}| {line.rstrip()}')
                if len(lines) > 50:
                    logger.info(f'        ... ({len(lines) - 50} more lines)')
                logger.info(f'      --- end setup.tcl ---')
        else:
            logger.info(f'      [miss] setup.tcl  NOT FOUND')
            logger.info(f'             Searched: {", ".join(setup_paths[:2])}')

        config_found = None
        for cp in config_paths:
            if os.path.exists(cp):
                config_found = cp
                break
        if config_found:
            size = os.path.getsize(config_found)
            logger.info(f'      [found] config.tcl ({size} bytes) -> {config_found}')
            if dump_setup and size > 0:
                logger.info(f'      --- config.tcl contents ---')
                with open(config_found, 'r') as f:
                    lines = f.readlines()
                for i, line in enumerate(lines[:50]):
                    logger.info(f'        {i+1:>3}| {line.rstrip()}')
                if len(lines) > 50:
                    logger.info(f'        ... ({len(lines) - 50} more lines)')
                logger.info(f'      --- end config.tcl ---')
        else:
            logger.info(f'      [miss] config.tcl NOT FOUND')
            logger.info(f'             Searched: {", ".join(config_paths[:2])}')

        # --- Command file ---
        cmd_file = os.path.join(core_dir, 'cmds', flow_type, vendor, tool,
                                version, f'{cmd_base}_{tool}.tcl') if core_dir else ''
        logger.info(f'')
        logger.info(f'    Command File:')
        if cmd_file and os.path.exists(cmd_file):
            size = os.path.getsize(cmd_file)
            with open(cmd_file, 'r') as f:
                content = f.read()
            proc_count = content.count('flow_proc ')
            proc_names = _re.findall(r'flow_proc\s+"?(\w+)"?', content)
            logger.info(f'      [found] {cmd_base}_{tool}.tcl ({size} bytes, {proc_count} flow_procs)')
            if proc_names:
                logger.info(f'      flow_procs: {", ".join(proc_names)}')
        elif cmd_file:
            logger.info(f'      [miss] {cmd_base}_{tool}.tcl NOT FOUND')
            logger.info(f'             Expected: {cmd_file}')
        else:
            logger.info(f'      [??] FLOW_DIR not set, cannot locate command file')

        # --- Subnode handler file ---
        handler_file = os.path.join(core_dir, 'cmds', flow_type, vendor, tool,
                                    version, f'{cmd_base}_subnode_handler.tcl') if core_dir else ''
        if handler_file:
            logger.info(f'')
            logger.info(f'    Subnode Handler:')
            if os.path.exists(handler_file):
                size = os.path.getsize(handler_file)
                logger.info(f'      [found] {cmd_base}_subnode_handler.tcl ({size} bytes)')
            else:
                logger.info(f'      [miss] {cmd_base}_subnode_handler.tcl NOT FOUND')

        # --- Required inputs (from config) ---
        critical_key = f'critical_files,{stage}'
        critical_files = node_config.get(critical_key, '')
        if critical_files:
            inputs_list = _parse_tcl_list(critical_files)
            logger.info(f'')
            logger.info(f'    Required Inputs:')
            for inp in inputs_list:
                exists = os.path.exists(inp)
                icon = '[found]' if exists else '[miss]'
                logger.info(f'      {icon} {inp}')

        # --- Expected outputs (from config) ---
        output_key = f'mandatory_outputs,{stage}'
        outputs_raw = node_config.get(output_key, '')
        if outputs_raw:
            outputs_list = _parse_tcl_list(outputs_raw)
            logger.info(f'')
            logger.info(f'    Expected Outputs:')
            for out in outputs_list:
                exists = os.path.exists(out)
                icon = '[found]' if exists else '[miss]'
                extra = ''
                if exists:
                    sz = os.path.getsize(out)
                    extra = f' ({sz} bytes)'
                logger.info(f'      {icon} {out}{extra}')

        # --- Work directory contents ---
        work_dir = node_dir
        if os.path.exists(work_dir):
            logger.info(f'')
            logger.info(f'    Work Directory: {work_dir}')
            for root, dirs, files in os.walk(work_dir):
                rel = os.path.relpath(root, work_dir)
                indent = '      '
                if rel != '.':
                    indent = '        '
                    logger.info(f'      {rel}/')
                for fn in sorted(files):
                    fpath = os.path.join(root, fn)
                    sz = os.path.getsize(fpath)
                    logger.info(f'{indent}  {fn} ({sz} bytes)')

        # --- Errors (check logs) ---
        log_dir = 'logs'
        stage_errors = []
        if os.path.exists(log_dir):
            for lf in sorted(os.listdir(log_dir)):
                if cmd_base in lf and lf.endswith('.log'):
                    log_path = os.path.join(log_dir, lf)
                    try:
                        with open(log_path, 'r') as f:
                            for line_num, line in enumerate(f, 1):
                                if any(p in line for p in log_error_patterns):
                                    stage_errors.append(f'{lf}:{line_num}: {line.strip()[:100]}')
                    except Exception:
                        pass

        if stage_errors:
            logger.info(f'')
            logger.info(f'    Errors Found ({len(stage_errors)}):')
            for err in stage_errors[:10]:
                logger.info(f'      [ERR] {err}')
            if len(stage_errors) > 10:
                logger.info(f'      ... and {len(stage_errors) - 10} more')
        else:
            logger.info(f'')
            logger.info(f'    Errors: None')

        # --- Finish timestamp ---
        # handler_common.tcl writes finish/finish_info.tcl and
        # run/<stage>_finish.timestamp under the node dir.
        finish_info_paths = ([os.path.join(node_dir, 'finish', 'finish_info.tcl')]
                             + sorted(glob.glob(os.path.join(node_dir, 'run', '*_finish.timestamp'))))
        for ts_file in finish_info_paths:
            if os.path.exists(ts_file):
                with open(ts_file, 'r') as f:
                    ts = f.read().strip()
                logger.info(f'')
                logger.info(f'    Finish Info: {ts_file}')
                logger.info(f'      {ts}')
                break

        logger.info('')

    # Summary
    all_stages = get_flow_stages(flow_type)
    done_count = sum(1 for s in all_stages if s in completed)
    logger.info(f'  {sep}')
    logger.info(f'  Summary: {done_count}/{len(all_stages)} stages completed')
    logger.info(f'  {sep}')
    logger.info('')
    return 0


def cmd_clean(args: argparse.Namespace) -> int:
    """Clean run directory."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    dirs_to_clean = ['work', 'logs']
    files_to_clean = ['.run.status']

    if not getattr(args, 'confirm', False):
        logger.warning("")
        logger.warning("  WARNING: This will delete all work files!")
        logger.warning("")
        logger.info("  Directories to remove:")
        for d in dirs_to_clean:
            if os.path.exists(d):
                logger.info(f"    {d}/")
        for f in files_to_clean:
            if os.path.exists(f):
                logger.info(f"    {f}")
        logger.info("")
        logger.info("  Use --confirm to proceed")
        return 1

    # Best-effort: drop this run from the dashboard daemon's registry.
    # Silent if daemon isn't running or the run was never registered.
    _deregister_from_dashboard(os.getcwd())

    import shutil
    for d in dirs_to_clean:
        if os.path.exists(d):
            shutil.rmtree(d)
            logger.info(f"Removed: {d}/")

    for f in files_to_clean:
        if os.path.exists(f):
            os.remove(f)
            logger.info(f"Removed: {f}")

    logger.info("[DONE] Clean completed")
    return 0


def _deregister_from_dashboard(run_dir):
    """Best-effort deregister of run_dir from the dashboard daemon.
    Never raises — clean must proceed even if the daemon is unreachable."""
    try:
        import sys as _sys
        dashboard_dir = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'dashboard')
        if dashboard_dir not in _sys.path:
            _sys.path.insert(0, dashboard_dir)
        import lifecycle  # noqa: E402
        if lifecycle.status()['state'] != 'running':
            return
        reply = lifecycle.send_deregister(run_dir)
        if reply.get('ok'):
            logger.info(f"Dashboard: deregistered run from daemon")
    except Exception:
        pass


def cmd_list_nodes(args: argparse.Namespace) -> int:
    """List all flow nodes."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    flow_type = get_flow_type()
    stages = get_flow_stages(flow_type)

    # Check stamps for completion status
    completed = _get_completed_from_db()

    # Load custom nodes from runtime config
    custom_data = load_custom_nodes_from_runtime_config()
    custom_nodes = custom_data.get('nodes', {}) if custom_data else {}

    logger.info("")
    logger.info(f"  {flow_type} Flow Nodes")
    logger.info(f"  {'═'*55}")
    logger.info("")

    # Discover dynamic fan-out subnodes from the engine DB. Flows like STA
    # expand a stage declared `subnodes {dynamic}` (timing1, extraction1)
    # into per-scenario / per-RC-corner subnodes at runtime; those exist
    # only as job rows. Static wrappers (setup/run/validate/finish) are
    # also job_type='subnode', so only stages configured as dynamic are
    # expanded here, and the engine's setup/validate/finish bookends are
    # dropped. Parentage comes from the DB `stage` column, never from a
    # job_name prefix (`timing1_fix_*` is not a child of `timing1`).
    from tcl_config_parser import get_subnodes
    _DYN_BOOKENDS = ('setup', 'validate', 'finish')

    def _is_dynamic(cfg_key):
        try:
            return get_subnodes(flow_type, cfg_key) == ['dynamic']
        except Exception:
            return False

    # node name -> config key that decides whether it is dynamic. Custom
    # and branch nodes inherit from their node type (timing2 -> timing).
    _dyn_candidates = {s: s for s in stages}
    for _name, _info in custom_nodes.items():
        _dyn_candidates[_name] = _info.get('type', '') or _name

    dyn_subnodes = {}        # node -> list of (subnode_job_name, done)
    try:
        from status_provider import get_status_provider
        _sp = get_status_provider(os.getcwd())
        if _sp.db_exists():
            _by_stage = {}
            for _job, _row in _sp.get_all_subnodes().items():
                _by_stage.setdefault(_row.get('stage', ''), []).append(
                    (_job, _row))
            for _node, _cfg_key in _dyn_candidates.items():
                if _node not in _by_stage or not _is_dynamic(_cfg_key):
                    continue
                _fan = sorted(
                    (_job, _row.get('status') in _sp.COMPLETED_STATES)
                    for _job, _row in _by_stage[_node]
                    if _row.get('subnode') not in _DYN_BOOKENDS)
                if _fan:
                    dyn_subnodes[_node] = _fan
    except Exception as _e:
        logger.debug(f"dynamic-subnode discovery skipped: {_e}")

    # Base flow - show as a chain
    logger.info(f"  Base Flow:")
    logger.info(f"  {'─'*55}")
    for i, stage in enumerate(stages):
        done = stage in completed          # stages are node names (config)
        icon = "[DONE]" if done else "[    ]"
        arrow = "  -> " if i < len(stages) - 1 else ""
        suffix = ""
        if stage in dyn_subnodes:
            n = len(dyn_subnodes[stage])
            d = sum(1 for _, sub_done in dyn_subnodes[stage] if sub_done)
            suffix = f"  [{d}/{n} dynamic subnodes]"
        logger.info(f"  {icon} {i+1:>2}. {stage:<25}{arrow}{suffix}")

    # Dynamic subnodes — one block per fanned-out stage.
    if dyn_subnodes:
        logger.info("")
        logger.info(f"  Dynamic Subnodes (per-scenario / per-RC-corner fan-out):")
        logger.info(f"  {'─'*55}")
        for stage, subs in dyn_subnodes.items():
            logger.info(f"  {stage}:")
            for sub_name, done in subs:
                icon = "[DONE]" if done else "[    ]"
                logger.info(f"    {icon} {sub_name}")

    # Custom nodes
    if custom_nodes:
        logger.info("")
        logger.info(f"  Custom Nodes:")
        logger.info(f"  {'─'*55}")
        for name, info in custom_nodes.items():
            node_type = info.get('type', '?')
            deps = info.get('dependencies', [])
            dep_str = ', '.join(deps) if deps else 'none'
            done = name in completed
            icon = "[DONE]" if done else "[    ]"
            logger.info(f"  {icon} {name:<20} type={node_type:<15} after={dep_str}")

    logger.info("")
    total = len(stages) + len(custom_nodes)
    done_count = sum(1 for s in stages if s in completed)
    done_count += sum(1 for n in custom_nodes if n in completed)
    dyn_total = sum(len(v) for v in dyn_subnodes.values())
    dyn_done = sum(sum(1 for _, d in v if d) for v in dyn_subnodes.values())
    if dyn_total:
        logger.info(f"  Total: {total} nodes ({done_count} completed) "
                    f"+ {dyn_total} dynamic subnodes ({dyn_done} completed)")
    else:
        logger.info(f"  Total: {total} nodes ({done_count} completed)")
    logger.info("")
    return 0


def cmd_show_graph(args: argparse.Namespace) -> int:
    """Show flow dependency graph as box-and-arrow diagram."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    from tcl_config_parser import is_merged_flow, get_merged_flow_stages
    from graph_renderer import render_graph

    flow_type = get_flow_type()

    # Build stage list with dependency and is_parallel metadata
    if is_merged_flow(flow_type):
        merged = get_merged_flow_stages(flow_type)
        stages_data = [
            {
                'name': s['name'],
                'dependency': s.get('dependency', ''),
                'is_parallel': s.get('is_parallel', False),
            }
            for s in merged
        ]
    else:
        # Single flow: build from node config.
        # merge_parallel_stages declares stages that run in parallel with the
        # NEXT flow's entry in a merged sequence. For a standalone flow run
        # there is no next flow, so those stages are linear (terminal). The
        # parallel_set is therefore intentionally left empty here — see the
        # is_merged_flow branch above for the merged-flow rendering.
        import re as _re
        from tcl_config_parser import _load_node_config, _parse_tcl_list
        _rd = os.getcwd() if is_run_directory() else None
        stages = get_flow_stages(flow_type, run_dir=_rd)
        node_config = _load_node_config(flow_type, run_dir=_rd)
        stages_data = []
        for i, stage in enumerate(stages):
            # Look up dependency
            dep_key = f'dependencies,{stage}'
            raw = node_config.get(dep_key, '')
            if not raw:
                base = _re.sub(r'\d+$', '', stage)
                if base != stage:
                    raw = node_config.get(f'dependencies,{base}', '')
            dep = ''
            if raw:
                dep_list = _parse_tcl_list(raw)
                if dep_list:
                    dep = dep_list[0]
                    if dep and dep not in stages:
                        for s in stages:
                            if _re.sub(r'\d+$', '', s) == dep:
                                dep = s
                                break
            stages_data.append({
                'name': stage,
                'dependency': dep,
                'is_parallel': False,
            })

    completed = _get_completed_from_db()

    # Get subnodes per stage if detail mode
    detail = getattr(args, 'detail', False)
    subnodes_map = {}
    if detail:
        from tcl_config_parser import _load_node_config, _parse_tcl_list
        _rd2 = os.getcwd() if is_run_directory() else None
        node_config = _load_node_config(flow_type, run_dir=_rd2)
        for sd in stages_data:
            stage = sd['name']
            key = f'subnodes,{stage}'
            raw = node_config.get(key, '')
            if raw:
                subnodes_map[stage] = _parse_tcl_list(raw)

    # Render
    output = render_graph(
        stages_data,
        completed=completed,
        title=f"{flow_type} Flow Dependency Graph",
        detail=detail,
        subnodes=subnodes_map,
    )
    print(output)
    return 0


def _get_node_manager():
    """Create a NodeManager for the current run directory."""
    from node_manager import NodeManager
    env_vars = load_run_env()
    # Also load TCL env
    from start_run import load_tcl_env_vars
    tcl_file = os.path.join(os.getcwd(), '.run.cbflow.tcl')
    if os.path.exists(tcl_file):
        tcl_vars = load_tcl_env_vars(tcl_file)
        for k, v in tcl_vars.items():
            if k not in env_vars:
                env_vars[k] = v
    return NodeManager(run_dir=os.getcwd(), flow_type=get_flow_type(), env_vars=env_vars)


def cmd_add_node(args: argparse.Namespace) -> int:
    """Add a custom node to the flow."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    node_type = args.type
    node_name = getattr(args, 'node', None)
    dependency = getattr(args, 'dep', None)

    flow_type = get_flow_type()
    valid_stages = get_flow_stages(flow_type)

    # Pre-validate node type
    import re
    base_types = sorted(set(re.sub(r'\d+$', '', s) for s in valid_stages)) if valid_stages else []

    if valid_stages and node_type not in valid_stages and node_type not in base_types:
        logger.error("")
        logger.error(f"  Invalid node type '{node_type}' for {flow_type} flow")
        logger.error("")
        logger.error(f"  Valid node types for {flow_type}:")
        for s in base_types:
            logger.error(f"    - {s}")
        logger.error("")
        logger.error(f"  Example:")
        # Guard the example — if base_types is empty (every stage is purely
        # numeric, no base type), skip the example rather than IndexError.
        if base_types and valid_stages:
            logger.error(f"    cbflow run add-node --type {base_types[0]} --dep {valid_stages[-1]}")
        logger.error("")
        return 1

    # Auto-generate node name if not provided
    if not node_name:
        mgr = _get_node_manager()
        # Find the next available suffix for this type
        all_existing = list(mgr.base_stages) + list(mgr.custom_nodes.keys())
        # Find highest existing number for this type
        max_num = 0
        for existing in all_existing:
            base = re.sub(r'\d+$', '', existing)
            if base == node_type:
                suffix_match = re.search(r'(\d+)$', existing)
                if suffix_match:
                    max_num = max(max_num, int(suffix_match.group(1)))
        next_num = max_num + 1
        node_name = f"{node_type}{next_num}"
        logger.info(f"  Auto-generated node name: {node_name}")
    else:
        mgr = _get_node_manager()

    if not dependency:
        logger.error("")
        logger.error(f"  Missing --dep (dependency node)")
        logger.error("")
        logger.error(f"  The new node needs a dependency to connect it in the flow.")
        logger.error(f"  Current {flow_type} stages: {' -> '.join(valid_stages)}")
        logger.error("")
        if valid_stages:
            last = valid_stages[-1]
            logger.error(f"  Example:")
            logger.error(f"    cbflow run add-node --type {node_type} --dep {last}")
        else:
            # No stages loaded — the config cascade failed. Don't suggest
            # a fake stage name (prior `'signoff1'` fallback would mislead
            # the user into typing an invalid --dep on DFT/DV runs).
            logger.error(f"  (Could not enumerate stages for {flow_type} — "
                         f"check flow_config.tcl and node_configs/.)")
        logger.error("")
        return 1

    resource_tier = getattr(args, 'resource_tier', '') or ''
    success = mgr.add_node(node_name, node_type, dependency,
                           resource_tier=resource_tier)
    return 0 if success else 1


def cmd_set_dep(args: argparse.Namespace) -> int:
    """Rewire a node's dependencies (e.g. export_data1 onto place1 so its
    release carries place data); --reset restores the node config's."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1
    mgr = _get_node_manager()
    deps = (getattr(args, 'deps', '') or '').replace(',', ' ').split()
    ok = mgr.set_deps(args.node, deps, reset=getattr(args, 'reset', False))
    return 0 if ok else 1


def cmd_delete_node(args: argparse.Namespace) -> int:
    """Delete a custom node from the flow."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    mgr = _get_node_manager()
    success = mgr.delete_node(args.node)
    return 0 if success else 1


def cmd_create_branch(args: argparse.Namespace) -> int:
    """Create a flow branch."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    _ensure_run_env_loaded()
    mgr = _get_node_manager()
    success = mgr.create_branch(args.branch, args.from_stage)
    return 0 if success else 1


def cmd_list_branches(args: argparse.Namespace) -> int:
    """List all flow branches."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    mgr = _get_node_manager()
    branches = mgr.list_branches()

    if not branches:
        logger.info("  No branches defined")
        return 0

    logger.info("")
    logger.info(f"  Branches ({len(branches)}):")
    logger.info(f"  ───────────────────────────────────────────────────────")
    for b in branches:
        logger.info(f"  {b['name']}")
        logger.info(f"    Created: {b.get('created_date', 'N/A')} by {b.get('created_by', 'N/A')}")
        logger.info(f"    Nodes:   {', '.join(b['nodes'])}")
    logger.info("")
    return 0


def cmd_delete_branch(args: argparse.Namespace) -> int:
    """Delete a flow branch and all its nodes."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    branch_name = getattr(args, 'branch', None)
    from_node = getattr(args, 'from_node', None)

    mgr = _get_node_manager()

    if not branch_name and not from_node:
        # Interactive: enumerate branches and prompt. Batch: hard-error.
        if sys.stdin.isatty():
            try:
                branches = sorted(mgr.list_branches() or [])
            except Exception:
                branches = []
            if branches:
                print('  Available branches:')
                for i, b in enumerate(branches, 1):
                    print(f'    {i}. {b}')
                choice = input(f'  Select branch to delete [1-{len(branches)}] or name: ').strip()
                try:
                    idx = int(choice) - 1
                    if 0 <= idx < len(branches):
                        branch_name = branches[idx]
                except ValueError:
                    if choice in branches:
                        branch_name = choice
            if not branch_name:
                logger.error("  No branch selected.")
                return 1
        else:
            logger.error("  Error: Either --branch or --from is required")
            return 1

    if branch_name:
        success = mgr.delete_branch(branch_name)
    elif from_node:
        # Delete the node and its dependents
        success = mgr.delete_node(from_node)

    return 0 if success else 1


def cmd_update(args: argparse.Namespace) -> int:
    """Update run to workspace release version or specified release."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    import json
    import shutil
    from start_run import load_tcl_env_vars, _generate_run_tcl_env, _generate_run_shell_env

    env_vars = load_run_env()
    flow_dir = env_vars.get('FLOW_DIR', get_cbflow_core_dir())
    current_release = env_vars.get('CBFLOW_RELEASE_VERSION', 'unknown')
    flow_type = get_flow_type()

    # Determine target release
    target_release = getattr(args, 'release', None)
    if not target_release:
        # Get from workspace
        workspace_dir = os.path.dirname(os.getcwd())
        ws_env_file = os.path.join(workspace_dir, '.cbflow.env')
        if os.path.exists(ws_env_file):
            with open(ws_env_file, 'r') as f:
                for line in f:
                    if 'CBFLOW_RELEASE_VERSION' in line:
                        target_release = line.split('=', 1)[-1].strip().strip('"')
                        break
        if not target_release:
            logger.error("  Error: No target release specified and no workspace found")
            logger.error("  Usage: cbflow run update --release v1.0.1")
            return 1

    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  Updating Run")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info("")
    logger.info(f"  Current release:  {current_release}")
    logger.info(f"  Target release:   {target_release}")

    if current_release == target_release:
        logger.info(f"  Already at target release. No changes needed.")
        return 0

    # Load target release manifest. Releases moved to global/releases/
    # on 2026-11-01 — prefer the global location, fall back to legacy
    # <core>/releases/ for pre-migration installs.
    from core.paths import get_cbflow_releases_dir
    _r = get_cbflow_releases_dir()
    releases_dir = os.path.join(_r, target_release) if _r \
                   else os.path.join(flow_dir, 'releases', target_release)
    manifest_file = os.path.join(releases_dir, 'MANIFEST.json')
    if not os.path.exists(manifest_file):
        logger.error(f"  Error: Release '{target_release}' not found")
        return 1

    with open(manifest_file, 'r', encoding='utf-8') as f:
        manifest = json.load(f)

    # Backup current env files
    if not getattr(args, 'no_backup', False):
        backup_dir = os.path.join(os.getcwd(), '.backup')
        os.makedirs(backup_dir, exist_ok=True)
        from datetime import datetime
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        for ef in ['.run.cbflow.env', '.run.cbflow.tcl']:
            src = os.path.join(os.getcwd(), ef)
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(backup_dir, f"{ef}.{ts}"))
        logger.info(f"  Backup created in .backup/")

    # Update env vars with new component versions
    components = manifest.get('components', {})
    version_map = {}
    for comp_name, comp_info in components.items():
        version = comp_info.get('version', '')
        # Map component paths to version var names
        if 'config.flow' in comp_name:
            version_map['FLOW_CONFIG_VERSION'] = version
        elif 'utils.generation' in comp_name:
            version_map['GENERATION_VERSION'] = version
        elif 'utils.utilities' in comp_name:
            version_map['UTILITIES_VERSION'] = version
        elif 'utils.node_management' in comp_name:
            version_map['NODE_MANAGEMENT_VERSION'] = version
        elif 'utils.validation' in comp_name:
            version_map['VALIDATION_VERSION'] = version
        elif 'utils.makefile' in comp_name:
            version_map['MAKEFILE_COMMANDS_VERSION'] = version

    env_vars['CBFLOW_RELEASE_VERSION'] = target_release
    env_vars.update(version_map)

    # Also load TCL env vars
    tcl_env_file = os.path.join(os.getcwd(), '.run.cbflow.tcl')
    if os.path.exists(tcl_env_file):
        tcl_vars = load_tcl_env_vars(tcl_env_file)
        for k, v in tcl_vars.items():
            if k not in env_vars:
                env_vars[k] = v
    env_vars.update(version_map)
    env_vars['CBFLOW_RELEASE_VERSION'] = target_release

    # Regenerate env files
    design = env_vars.get('CBFLOW_DESIGN_NAME', '')
    run_name = env_vars.get('CBFLOW_RUN_NAME', '')
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')

    _generate_run_tcl_env(os.getcwd(), env_vars, flow_type, design, run_name, phase)
    _generate_run_shell_env(os.getcwd(), env_vars, flow_type, design, run_name, phase)

    logger.info(f"  [DONE] Environment updated to {target_release}")

    # Verify engine DAG after update
    from race_engine import DagBuilder
    try:
        builder = DagBuilder(os.getcwd(), flow_type, env_vars)
        jobs, stages = builder.build()
        logger.info(f"  [DONE] Engine DAG verified: {len(jobs)} jobs, {len(stages)} stages")
    except Exception as e:
        logger.warning(f"  Engine DAG verification failed: {e}")

    logger.info("")
    return 0


def cmd_gen_makefile(args: argparse.Namespace) -> int:
    """Verify engine DAG for the run directory."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    env_vars = load_run_env()
    flow_type = get_flow_type()

    logger.info("")
    logger.info(f"  Verifying RACE DAG")
    logger.info(f"  ═══════════════════════════════════════════════════════════")

    from race_engine import RaceEngine
    engine = RaceEngine(os.getcwd(), flow_type, env_vars)
    if engine.initialize():
        logger.info(f"  Flow:   {flow_type}")
        logger.info(f"  Jobs:   {len(engine.jobs)}")
        logger.info(f"  Stages: {' → '.join(engine.stage_order)}")
        logger.info(f"  DB:     {engine.db.db_path}")
        logger.info(f"  [DONE] Engine DAG verified")
        return 0
    else:
        logger.error("  Engine initialization failed")
        return 1


def cmd_release_info(args: argparse.Namespace) -> int:
    """Show release information for this run."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  CBFlow Release Information")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info("")
    logger.info(f"Run Directory: {os.getcwd()}")
    logger.info("")

    env_vars = load_run_env()
    release_version = env_vars.get('CBFLOW_RELEASE_VERSION', 'unknown')
    logger.info(f"Release Version: {release_version}")
    logger.info("")
    logger.info("Component Versions:")
    for key, value in sorted(env_vars.items()):
        if '_VERSION' in key and key != 'CBFLOW_RELEASE_VERSION':
            logger.info(f"  {key}: {value}")

    logger.info("")
    return 0


def cmd_release(args: argparse.Namespace) -> int:
    """Milestone-gated release: validates all required flows passed, then packages deliverables."""
    import re as _re
    import json
    import shutil
    from datetime import datetime

    dry_run = getattr(args, 'dry_run', False)
    tag_override = getattr(args, 'tag', None)

    # A run that released itself (open-source flows: release_data stage)
    # is not repackaged — the release is on disk; only publish on request.
    from_run = getattr(args, 'from_run', None)
    if from_run and getattr(args, 'clone_from', None):
        return _clone_release(os.path.abspath(from_run), args.clone_from, tag_override,
                              node=getattr(args, 'node', None) or '',
                              publish=getattr(args, 'publish', None),
                              override=getattr(args, 'override', False))
    if from_run:
        run_dir = os.path.abspath(from_run)
        rel_node = getattr(args, 'node', None) or ''
        info = _flow_release_manifest(run_dir, rel_node)
        if not info.get('release_dir'):
            logger.error(f"--from-run {from_run}: run has no release from its release_data stage")
            return 1
        milestone = tag_override or info.get('milestone', '')
        logger.info(f"  Release (from run): {info['release_dir']}")
        # A signoff flow's release (STA/PV/LEC …) belongs to the exit it
        # verified (attach_to): re-publish that exit's entry, which gathers
        # every flow's release of the exit, from the run it was published from.
        if not info.get('milestone') and info.get('attach_to'):
            if not getattr(args, 'publish', None):
                logger.info("  Not published to SmartGrid (publish not requested — use --publish).")
                return 0
            return _publish_signoff_release(run_dir, info, strict=True)
        if not getattr(args, 'publish', None):
            logger.info("  Not published to SmartGrid (publish not requested — use --publish).")
            return 0
        if not milestone:
            logger.error("  --publish needs a milestone: pass --tag <MILESTONE> (e.g. BTO)")
            return 1
        return _publish_flow_release(run_dir, milestone, strict=True,
                                     override=getattr(args, 'override', False),
                                     node=rel_node)

    # Must run from a workspace (not a run dir — we need to see all runs)
    workspace = os.getcwd()
    runs = sorted([d for d in os.listdir(workspace)
                   if os.path.isdir(d) and _is_run_dir_name(d)])
    if not runs:
        logger.error("No runs found in workspace. Run from a workarea directory.")
        return 1

    # Load project config to get release settings
    env_vars = {}
    for run in runs:
        env_file = os.path.join(workspace, run, '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('export ') and '=' in line:
                        k, v = line[7:].split('=', 1)
                        env_vars[k] = v.strip('"')
            break

    project_name = env_vars.get('CBFLOW_PROJECT_NAME', env_vars.get('PROJECT_NAME', ''))
    design_name = env_vars.get('CBFLOW_DESIGN_NAME', '')
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')

    # Predefined tags, milestone→stage map: release_config.tcl
    # (release_tags(*), MILESTONE_STAGE_MAPPING(*)) via core.release_exits.
    try:
        release_tags = release_exits.release_tags()
        milestone_stage_map = release_exits.milestone_stage_mapping()
    except release_exits.PhaseExitsError as e:
        logger.error(str(e))
        return 1

    # Release settings: project(release,*) across the project config cascade.
    try:
        active_tag  = registry.project_value(project_name, 'release,active_tag') or ''
        expiry_date = registry.project_value(project_name, 'release,expiry_date') or ''
        release_path = registry.require_project_value(project_name, 'release,path')
    except registry.RegistryError as e:
        logger.error(str(e))
        return 1

    tag = tag_override or active_tag
    if not tag:
        logger.error("No release tag set. Set project(release,active_tag) in project config.")
        logger.error(f"Available tags: {', '.join(sorted(release_tags.keys()))}")
        return 1

    # Validate tag is predefined
    if tag not in release_tags:
        logger.error(f"Release tag '{tag}' is not predefined.")
        logger.error(f"Available tags: {', '.join(sorted(release_tags.keys()))}")
        return 1

    tag_info = release_tags[tag]

    try:
        phase_exits = _milestone_order(project_name, phase)
    except release_exits.PhaseExitsError as e:
        logger.error(str(e))
        return 1
    if tag not in phase_exits:
        logger.error(f"Phase {phase} has no {tag} exit (exits in {phase}: "
                     f"{', '.join(phase_exits)}) — project(phase_exits) in the project config")
        return 1

    # Validate expiry
    if expiry_date:
        try:
            exp = datetime.strptime(expiry_date, '%Y-%m-%d')
        except ValueError:
            logger.error(f"project(release,expiry_date) '{expiry_date}' is not a YYYY-MM-DD date")
            return 1
        if datetime.now() > exp:
            logger.error(f"Release tag '{tag}' expired on {expiry_date}")
            return 1

    # Release tag name = the exit name (default); --name overrides it.
    release_tag_name = getattr(args, 'name', None) or tag

    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  CBflow Milestone Release: {release_tag_name}")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  Tag:         {tag} ({tag_info['description']})")
    logger.info(f"  Phase:       {phase}")
    logger.info(f"  Project:     {project_name}")
    logger.info(f"  Design:      {design_name}")
    logger.info(f"  Release to:  {release_path}")
    if expiry_date:
        logger.info(f"  Expiry:      {expiry_date}")
    required_stage = milestone_stage_map.get(tag, '')
    logger.info(f"  Required stage: {required_stage}")
    logger.info(f"  Required flows: {' '.join(tag_info['required_flows'])}")
    logger.info(f"  ─────────────────────────────────────────────────────────")
    logger.info("")

    # Gate check: the tag's required flows (release_tags(<tag>) required_flows)
    # that have a run in this workspace — only those are packaged.
    required_flows = tag_info['required_flows']
    found_runs = {}
    for run in runs:
        env_file = os.path.join(workspace, run, '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if 'CBFLOW_FLOW_TYPE' in line:
                        m = _re.search(r'"([^"]+)"', line)
                        if m and m.group(1) in required_flows:
                            found_runs[m.group(1)] = run
    logger.info(f"  Found runs: {len(found_runs)}")
    for flow, run_name in sorted(found_runs.items()):
        logger.info(f"    {flow:<15} → {run_name}")
    logger.info("")

    if not found_runs:
        logger.error(f"  No runs of the {tag} required flows ({' '.join(required_flows)}) "
                     f"found in workspace")
        return 1

    # What each flow releases: release_deliverables(<FLOW>,<category>) suffixes.
    try:
        deliverables = {f: release_exits.release_deliverables(f) for f in found_runs}
    except release_exits.PhaseExitsError as e:
        logger.error(str(e))
        return 1

    if dry_run:
        logger.info(f"  DRY RUN: {len(found_runs)} flows found. Release would proceed.")
        return 0

    # Create release directory
    # Same layout as the flows' release_data: <release,path>/<phase>/<block>/<FLOW>/<tag>
    try:
        flow_dirs = {f: registry.release_dir(release_path, phase, design_name, f, release_tag_name)
                     for f in found_runs}
    except registry.RegistryError as e:
        logger.error(str(e))
        return 1
    block_dir = os.path.join(release_path, phase, design_name)
    release_dir = next(iter(flow_dirs.values()))          # primary flow's release
    for _d in flow_dirs.values():
        os.makedirs(_d, exist_ok=True)
    logger.info(f"  Release directories: {block_dir}/<FLOW>/{release_tag_name}")
    logger.info("")

    def _category(fname, flow_deliv):
        """Category whose release_deliverables suffix matches fname (longest
        suffix wins), or None when fname is not a deliverable of the flow."""
        best, best_len = None, 0
        for cat, sufs in flow_deliv.items():
            for suf in sufs:
                if fname.endswith(suf) and len(suf) > best_len:
                    best, best_len = cat, len(suf)
        return best

    # Copy deliverables from each flow
    total_files = 0
    for flow, run_dir_name in found_runs.items():
        run_path = os.path.join(workspace, run_dir_name)
        flow_release_dir = flow_dirs[flow]
        flow_deliv = deliverables[flow]
        flow_files = 0

        # Scan for output manifest first
        manifests = []
        for root, dirs, files in os.walk(os.path.join(run_path, 'work')):
            for fname in files:
                if fname == 'output_manifest.tcl':
                    manifests.append(os.path.join(root, fname))

        sources = []
        if manifests:
            # Use manifest to find files (supports both 'set manifest(key) "val"' and 'array set manifest { key "val" }')
            manifest_path = sorted(manifests)[-1]
            with open(manifest_path) as mf:
                for line in mf:
                    # Format 1: set manifest(key) "value"
                    m = _re.match(r'set\s+manifest\((\S+)\)\s+"([^"]*)"', line.strip())
                    # Format 2: key "value" (inside array set block)
                    if not m:
                        m = _re.match(r'(\w+)\s+"([^"]+)"', line.strip())
                    if m and m.group(1) not in ('flow', 'node', 'design', 'run_dir', 'timestamp', 'file_count'):
                        if os.path.exists(m.group(2)):
                            sources.append(m.group(2))
        else:
            # No manifest: scan all outputs/ and reports/ directories (top-level + per-node)
            scan_dirs = [os.path.join(run_path, 'outputs'), os.path.join(run_path, 'results')]
            work_path = os.path.join(run_path, 'work')
            if os.path.isdir(work_path):
                for _flow_dir in os.listdir(work_path):
                    _flow_path = os.path.join(work_path, _flow_dir)
                    if os.path.isdir(_flow_path):
                        for _node_dir in os.listdir(_flow_path):
                            for _sub in ('outputs', 'reports'):
                                _sd = os.path.join(_flow_path, _node_dir, _sub)
                                if os.path.isdir(_sd):
                                    scan_dirs.append(_sd)
            for scan_dir in scan_dirs:
                for root, dirs, files in os.walk(scan_dir):
                    sources += [os.path.join(root, fname) for fname in files]

        for src in sources:
            subdir = _category(os.path.basename(src), flow_deliv)
            if subdir is None:
                continue                  # not a release_deliverables file of this flow
            dest_dir = os.path.join(flow_release_dir, subdir)
            os.makedirs(dest_dir, exist_ok=True)
            shutil.copy2(src, dest_dir)
            flow_files += 1

        total_files += flow_files
        logger.info(f"  {flow:<12} → {flow_files} files released")

    # Generate MANIFEST.json
    manifest = {
        'release_tag': release_tag_name,
        'milestone': tag,
        'description': tag_info['description'],
        'phase': phase,
        'project': project_name,
        'design': design_name,
        'timestamp': datetime.now().isoformat(),
        'user': os.environ.get('USER', 'unknown'),
        'total_files': total_files,
        'flows': {flow: run for flow, run in found_runs.items()},
        'expiry_date': expiry_date,
    }
    for _flow, _d in flow_dirs.items():
        with open(os.path.join(_d, 'MANIFEST.json'), 'w', encoding='utf-8') as f:
            json.dump(dict(manifest, flow=_flow), f, indent=2)
    for _flow, _d in flow_dirs.items():
        with open(os.path.join(_d, 'RELEASE_COMPLETE'), 'w', encoding='utf-8') as f:
            f.write(f"TAG={release_tag_name}\n")
            f.write(f"MILESTONE={tag}\n")
            f.write(f"PHASE={phase}\n")
            f.write(f"PROJECT={project_name}\n")
            f.write(f"DESIGN={design_name}\n")
            f.write(f"FILES={total_files}\n")
            f.write(f"FLOWS={' '.join(found_runs.keys())}\n")
            f.write(f"STATUS=PASS\n")
            f.write(f"TIMESTAMP={datetime.now().isoformat()}\n")
            f.write(f"USER={os.environ.get('USER', 'unknown')}\n")

    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  Release Complete: {release_tag_name}")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  Directory:   {release_dir}")
    logger.info(f"  Total files: {total_files}")
    logger.info(f"  Flows:       {len(found_runs)}")
    logger.info(f"  Status:      PASS")
    logger.info(f"  MANIFEST:    {release_dir}/MANIFEST.json")
    logger.info("")

    # ── Snapshot to CBflow-ProjectDashboard ──
    # args.publish is tri-state:
    #   None  — flag not given: publish best-effort. Only an ALREADY RUNNING
    #           SmartGrid daemon is used (a release never spawns one), and
    #           any publish problem is a note, not a failed release — the
    #           release is already on disk with STATUS=PASS.
    #   True  — explicit --publish: start the daemon if needed; a publish
    #           failure fails the command.
    #   False — --no-publish, or a programmatic Namespace that never
    #           declared the attribute: skip.
    # Publishing is opt-in: only an explicit --publish (or the GUI Release
    # form's publish checkbox) snapshots the release into SmartGrid, so runs
    # nobody chose to report never reach the grid.
    publish = getattr(args, 'publish', False)
    if publish:
        strict = True
        rc = _publish_to_project_dashboard(
            project=project_name, block=design_name, phase=phase,
            milestone=tag, release_dir=release_dir,
            workspace=workspace, runs=found_runs,
            milestone_stage_map=milestone_stage_map,
            override=getattr(args, 'override', False),
            strict=strict)
        if rc != 0 and strict:
            return rc
    return 0


def _run_milestone_checklist(workspace: str, runs: dict, milestone: str) -> None:
    """`cbflow flow checklist status --milestone <M> --run-dir <run>` for each
    published run (subprocess: a BLOCKED verdict exits 1 — that is data, not
    a publish failure). Writes checklist_results into the run's RACE DB."""
    cbflow = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))))), 'bin', 'cbflow')
    if not os.path.exists(cbflow):
        cbflow = 'cbflow'
    for flow, run in (runs or {}).items():
        run_dir = run if os.path.isabs(run) else os.path.join(workspace, run)
        if not os.path.isdir(run_dir):
            continue
        logger.info(f"  Checklist {milestone} on {os.path.basename(run_dir)} ({flow})...")
        try:
            proc = subprocess.run([cbflow, 'flow', 'checklist', 'status',
                                   '--milestone', milestone, '--run-dir', run_dir],
                                  capture_output=True, text=True, timeout=600)
            verdict = next((l.split(':', 1)[1].strip() for l in proc.stdout.splitlines()
                            if l.strip().lower().startswith('verdict')), '')
            logger.info(f"    checklist done{(' — ' + verdict) if verdict else ''}")
        except Exception as e:
            logger.warning(f"    checklist could not run: {e}")


def _milestone_order(project=None, phase=None) -> list:
    """MILESTONE_ORDER from PD release_config.tcl; with project + phase, only
    the exits that phase has (project(phase_exits)). Raises
    release_exits.PhaseExitsError when the config does not declare them."""
    if project and phase:
        return release_exits.exits_for_phase(project, phase)
    return release_exits.milestone_order()


def _missing_earlier_milestones(project, block, phase, milestone, pd_pkg) -> list:
    """Milestones ordered before `milestone` that are not yet published for
    (project, block, phase) — only exits the phase has count. Milestones
    outside MILESTONE_ORDER are ungated."""
    order = _milestone_order(project, phase)
    if milestone not in order:
        return []
    import importlib.util as _ilu
    import tracker_db as _pd_tracker
    # project_dashboard/state_paths.py by path: dashboard/ has a module of the
    # same name, so a plain import can resolve to the wrong one.
    spec = _ilu.spec_from_file_location('_pd_state_paths',
                                        os.path.join(pd_pkg, 'state_paths.py'))
    sp = _ilu.module_from_spec(spec)
    spec.loader.exec_module(sp)
    db_path = sp.tracker_db(project)
    published = set()
    if os.path.exists(db_path):
        published = {r['milestone'] for r in _pd_tracker.list_published(db_path, project)
                     if r['block'] == block and r['phase'] == phase}
    return [m for m in order[:order.index(milestone)] if m not in published]


def _publish_to_project_dashboard(project, block, phase, milestone, release_dir,
                                   workspace, runs, milestone_stage_map, override,
                                   strict=True, flow='', attach_to=''):
    """Snapshot the just-completed release into the project dashboard.

    strict=True  (explicit --publish): start the SmartGrid daemon if it is
                 not running; any failure is logged as an error.
    strict=False (default best-effort publish): never start a daemon — if
                 none is running the publish is skipped — and problems are
                 logged as warnings.
    A failed publish never rolls back the release itself. Returns 0 when
    published, non-zero otherwise (the caller decides whether that fails
    the command).
    """
    _problem = logger.error if strict else logger.warning
    # the published data is the current VERSION (<FLOW>/.versions/<tag>/v<n>,
    # or its disk copy): SmartGrid keeps it even if current moves later, and
    # cleanup never removes a published version
    release_dir = os.path.realpath(release_dir) if release_dir else release_dir
    import sys as _sys
    pd_pkg = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          'project_dashboard')
    if pd_pkg not in _sys.path:
        _sys.path.insert(0, pd_pkg)
    try:
        import client as _pd_client
        import tracker_db as _pd_tracker
    except ImportError as e:
        _problem(f"  Publish failed: could not import project_dashboard ({e})")
        return 1

    # Best-effort mode never starts a daemon, so check for one BEFORE
    # building the payload (RACE DB reads, hashing, DEF/LEF parsing).
    if not strict:
        try:
            import lifecycle as _pd_lifecycle
            _running = _pd_lifecycle.is_running(project)
        except Exception as e:
            logger.warning(f"  Publish skipped: cannot query SmartGrid daemon ({e})")
            return 1
        if not _running:
            logger.info(f"  Not published: no SmartGrid daemon is running for "
                        f"project {project} (the release itself is complete).")
            logger.info(f"  To publish: `cbflow smartgrid start --project {project}`, "
                        f"then re-run this release — or re-run it with --publish.")
            return 1

    # The phase must have this exit (release_tags(<exit>) phases), and exits
    # publish in MILESTONE_ORDER: every earlier exit of the phase must
    # already be on SmartGrid for this block/phase.
    try:
        phase_exits = _milestone_order(project, phase)
    except release_exits.PhaseExitsError as e:
        logger.error(f"  Not published: {e}")
        return 1
    if milestone in _milestone_order() and milestone not in phase_exits:
        logger.error(f"  Not published: phase {phase} has no {milestone} exit "
                     f"(exits in {phase}: {', '.join(phase_exits)}).")
        return 1
    missing = _missing_earlier_milestones(project, block, phase, milestone, pd_pkg)
    if missing:
        logger.error(f"  Not published: {milestone} cannot release before "
                     f"{', '.join(missing)} for {block} / {phase}.")
        logger.error(f"  Release in order: {' -> '.join(phase_exits)} "
                     f"(next: {missing[0]}).")
        return 1

    # Every published release carries the milestone's complete checklist:
    # evaluate it on each published run now (status from the run's data,
    # NA where a check has no data) so SmartGrid snapshots checklist_results.
    # A signoff run (attach_to) is checked against its flow's own checklist,
    # <FLOW>_SIGNOFF (global/config/exit/<ver>/<FLOW>_SIGNOFF_config.tcl),
    # when the flow declares one; its verdict stays the release Status.
    checklist_milestone = milestone
    if attach_to:
        checklist_milestone = f'{flow}_SIGNOFF'
        _exit_cfg = os.path.join(registry.root(), 'global', 'config', 'exit',
                                 registry.config_version('FLOW_CONFIG_VERSION'),
                                 f'{checklist_milestone}_config.tcl')
        if os.path.isfile(_exit_cfg):
            _run_milestone_checklist(workspace, runs, checklist_milestone)
        else:
            checklist_milestone = ''
    else:
        _run_milestone_checklist(workspace, runs, milestone)

    published_by = os.environ.get('USER', 'unknown')
    logger.info("  ─────────────────────────────────────────────────────────")
    logger.info(f"  Publishing to CBflow-ProjectDashboard "
                f"(project={project}, block={block}, phase={phase}, milestone={milestone})...")
    try:
        payload = _pd_client.build_payload(
            project=project, block=block, phase=phase, milestone=milestone,
            release_dir=release_dir, workspace=workspace,
            runs=runs, milestone_stage_map=milestone_stage_map,
            published_by=published_by, override=override,
            flow=flow, attach_to=attach_to, checklist_milestone=checklist_milestone)
        reply = _pd_client.publish(project, payload, start_daemon=strict)
    except Exception as e:
        _problem(f"  Publish failed: {e}")
        return 1

    if not reply.get('ok'):
        if reply.get('no_daemon'):
            logger.info(f"  Not published: no SmartGrid daemon is running for "
                        f"project {project} (the release itself is complete).")
            logger.info(f"  To publish: `cbflow smartgrid start --project {project}`, "
                        f"then re-run this release — or re-run it with --publish.")
        elif reply.get('conflict'):
            if strict:
                logger.error(f"  Publish conflict: {reply.get('error')}")
                logger.error("  Re-run with --override to replace the existing entry.")
            else:
                logger.info(f"  Not re-published: this (project, block, phase, "
                            f"milestone) cell is already on SmartGrid.")
                logger.info("  Re-run the release with --override to replace it.")
        else:
            _problem(f"  Publish failed: {reply.get('error')}")
        return 1
    logger.info(f"  Published: {reply.get('url', '(no url)')}")
    return 0


def cmd_release_lock(args: argparse.Namespace) -> int:
    """Set production permissions (lock) or development permissions (unlock)."""
    import stat

    unlock = getattr(args, 'unlock', False)
    # Framework trees: bin/, global/ and every discipline directory
    # (flow(discipline_dir,*)); workarea / inputs / releases stay writable.
    from core import registry as _flow_registry
    try:
        _root = _flow_registry.root()
        trees = [os.path.join(_root, 'bin'), os.path.join(_root, 'global')] + [
            _flow_registry.discipline_dir(d) for d in _flow_registry.flow_disciplines()]
    except _flow_registry.RegistryError as e:
        logger.error(f"Cannot resolve the CBflow trees: {e}")
        return 1
    trees = [t for t in trees if os.path.isdir(t)]
    if not trees:
        logger.error(f"No CBflow framework directory found under {_root}")
        return 1
    core_dir = ', '.join(trees)

    mode_label = "UNLOCK (777)" if unlock else "LOCK (production)"
    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  CBflow Permission {mode_label}")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  Directory: {core_dir}")
    logger.info("")

    file_count = 0
    dir_count = 0

    # Script/binary extensions
    exec_exts = {'.sh', '.csh', '.bash', '.zsh'}
    exec_names = set()

    for root, dirs, files in (w for t in trees for w in os.walk(t)):
        # Skip hidden dirs
        dirs[:] = [d for d in dirs if not d.startswith('.')]

        for d in dirs:
            dpath = os.path.join(root, d)
            if unlock:
                os.chmod(dpath, 0o777)
            else:
                os.chmod(dpath, 0o755)
            dir_count += 1

        for f in files:
            fpath = os.path.join(root, f)
            if os.path.islink(fpath) or not os.path.exists(fpath):
                continue  # skip symlinks and broken links
            try:
                if unlock:
                    os.chmod(fpath, 0o777)
                else:
                    _, ext = os.path.splitext(f)
                    is_bin = '/bin' in root or root.endswith('bin')
                    is_exec = ext in exec_exts or (is_bin and ext == '')
                    is_python = ext == '.py'

                    if is_bin or is_exec:
                        os.chmod(fpath, 0o555)
                    elif is_python:
                        os.chmod(fpath, 0o555)
                    else:
                        os.chmod(fpath, 0o444)
                file_count += 1
            except (OSError, PermissionError):
                pass

    logger.info(f"  Files:       {file_count}")
    logger.info(f"  Directories: {dir_count}")
    logger.info(f"  Mode:        {mode_label}")
    logger.info("")
    if not unlock:
        logger.info(f"  Permissions set:")
        logger.info(f"    Directories:     755 (rwxr-xr-x)")
        logger.info(f"    Scripts/Python:  555 (r-xr-xr-x)")
        logger.info(f"    Config/TCL/Docs: 444 (r--r--r--)")
        logger.info("")
        logger.info(f"  To unlock for development: cbflow run release-lock --unlock")
    logger.info("")
    return 0


def cmd_release_check(args: argparse.Namespace) -> int:
    """Check chip-level release readiness: all blocks × all flows for a milestone."""
    import re as _re
    import json

    tag = args.tag
    project_name = args.project
    # Phase must come from --phase or CBFLOW_PROJECT_PHASE (set inside a run
    # shell) — picking the project's first phase silently checked the wrong one.
    phase = getattr(args, 'phase', '') or os.environ.get('CBFLOW_PROJECT_PHASE', '')
    if not phase:
        logger.error('--phase required for release-check (or run from a run shell where '
                     'CBFLOW_PROJECT_PHASE is set).')
        return 1
    block_filter = getattr(args, 'block', None)

    # Load release_tags from release_config
    release_tags = release_exits.release_tags()

    if tag not in release_tags:
        logger.error(f"Unknown tag '{tag}'. Available: {', '.join(sorted(release_tags.keys()))}")
        return 1

    tag_info = release_tags[tag]
    release_tag_name = getattr(args, 'name', None) or tag

    # Release path + block list from the project config cascade. block_list
    # is derived in Tcl (from design_hierarchy), so it is evaluated, not regexed.
    try:
        release_path = registry.require_project_value(project_name, 'release,path')
        _bl = _tcl_values(registry.project_config_paths(project_name),
                          ['project(block_list)']).get('project(block_list)', '')
    except (registry.RegistryError, RuntimeError) as e:
        logger.error(str(e))
        return 1
    block_list = _bl.split()
    if not block_list:
        logger.error(f"project(block_list) is not set for {project_name} in the project config.")
        return 1

    blocks = [block_filter] if block_filter else block_list
    required_flows = tag_info['required_flows']

    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════════════════")
    logger.info(f"  Chip-Level Release Check: {release_tag_name}")
    logger.info(f"  ═══════════════════════════════════════════════════════════════════")
    logger.info(f"  Tag:         {tag} ({tag_info['description']})")
    logger.info(f"  Phase:       {phase}")
    logger.info(f"  Project:     {project_name}")
    logger.info(f"  Blocks:      {', '.join(blocks)}")
    logger.info(f"  Flows:       {', '.join(required_flows)}")
    logger.info(f"  Release dir: {release_path}")
    logger.info(f"  ─────────────────────────────────────────────────────────────────")
    logger.info("")

    # Header
    flow_hdr = ''.join(f'{fl:<14}' for fl in required_flows)
    logger.info(f"  {'Block':<20} {flow_hdr}{'Status'}")
    logger.info(f"  {'─' * (20 + 14 * len(required_flows) + 10)}")

    all_pass = True
    total_blocks = len(blocks)
    complete_blocks = 0

    for block in blocks:
        row = f"  {block:<20} "
        block_ok = True
        stub_detected = False

        for flow in required_flows:
            release_dir = registry.release_dir(release_path, phase, block, flow, release_tag_name)
            rc_file = os.path.join(release_dir, 'RELEASE_COMPLETE')

            if os.path.isdir(release_dir) and len(os.listdir(release_dir)) > 0:
                # test_mode stub marker — refuse to count as PASS. The
                # stub pipeline writes `.TEST_MODE_STUB` next to the
                # artifacts; a release-check for BTO/MTO sign-off MUST
                # NOT accept a stub as a real release.
                #
                # Pre-fix: we only checked the two top-level locations
                # (<flow>/.TEST_MODE_STUB and <flow>/outputs/.TEST_MODE_STUB).
                # But `cbflow run release` copies node outputs into
                # <flow>/data/ (or output-manifest-chosen subdirs), so
                # the marker landed where this check never looked.
                # Walk the whole release_dir subtree so a stub artifact
                # ANYWHERE under <flow>/ is caught.
                _stub_found = False
                for _root, _dirs, _files in os.walk(release_dir):
                    if '.TEST_MODE_STUB' in _files:
                        _stub_found = True
                        break
                if _stub_found:
                    row += f'{"STUB":<14}'
                    block_ok = False
                    stub_detected = True
                else:
                    fcount = sum(1 for _, _, files in os.walk(release_dir) for f in files)
                    row += f'{"PASS("+str(fcount)+")":<14}'
            else:
                row += f'{"MISS":<14}'
                block_ok = False

        # Check overall RELEASE_COMPLETE
        # Per-flow layout: every flow dir carries its own RELEASE_COMPLETE
        _rcs = sorted(glob.glob(os.path.join(release_path, phase, block, '*',
                                             release_tag_name, 'RELEASE_COMPLETE')))
        rc_path_full = _rcs[0] if _rcs else os.path.join(
            release_path, phase, block, release_tag_name, 'RELEASE_COMPLETE')
        if block_ok and os.path.exists(rc_path_full):
            # Also check the summary RELEASE_COMPLETE text for a stub tag.
            try:
                with open(rc_path_full) as _f:
                    _rc_body = _f.read()
                if 'TEST_MODE_STUB' in _rc_body:
                    row += '[STUB — NOT A REAL RELEASE]'
                    all_pass = False
                else:
                    row += '[COMPLETE]'
                    complete_blocks += 1
            except OSError:
                row += '[COMPLETE]'
                complete_blocks += 1
        elif block_ok:
            row += '[NO STAMP]'
        elif stub_detected:
            row += '[STUB — NOT A REAL RELEASE]'
            all_pass = False
        else:
            row += '[INCOMPLETE]'
            all_pass = False

        logger.info(row)

    logger.info(f"  {'─' * (20 + 14 * len(required_flows) + 10)}")
    logger.info(f"  {'TOTAL':<20} {complete_blocks}/{total_blocks} blocks complete")
    logger.info("")

    if all_pass and complete_blocks == total_blocks:
        logger.info(f"  CHIP-LEVEL RELEASE: READY for {release_tag_name}")
    else:
        logger.info(f"  CHIP-LEVEL RELEASE: NOT READY — {total_blocks - complete_blocks} block(s) incomplete")

    logger.info("")
    return 0 if (all_pass and complete_blocks == total_blocks) else 1


def cmd_targets(args: argparse.Namespace) -> int:
    """List available stages/targets."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    flow_type = get_flow_type()
    stages = get_flow_stages(flow_type)

    logger.info(f"\n  {flow_type} Available Targets")
    logger.info(f"  {'=' * 50}")
    logger.info(f"  cbflow run all                Run complete flow")
    for stage in stages:
        logger.info(f"  cbflow run stage --name {stage:<15s}")
    logger.info(f"  cbflow run retrace            Retrace all stages")
    logger.info(f"  cbflow run retrace --from X   Retrace from stage X")
    logger.info(f"  {'=' * 50}\n")
    return 0


def _per_tool_key(resolved: dict, prefix: str, tool_name: str) -> str:
    """Value of `<prefix>,<tool>` or, when the tool has no entry,
    `<prefix>,default` from the resolved config (both declared in
    tool_launch_config.tcl). Raises when neither is declared."""
    for key in (f'{prefix},{tool_name})', f'{prefix},default)'):
        if key in resolved:
            return resolved[key]
    raise registry.RegistryError(f'{prefix},{tool_name}) / {prefix},default) not set '
                                 f'(PD/config/flow/<ver>/tool_launch_config.tcl)')


def cmd_interactive(args: argparse.Namespace) -> int:
    """Launch interactive EDA tool session in xterm."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    import subprocess
    import shutil
    from datetime import datetime

    env_vars = load_run_env()
    flow_type = get_flow_type()
    run_dir = os.getcwd()
    load_node = getattr(args, 'node', None)
    notiming = getattr(args, 'notiming', False)

    # Determine tool from run env → user_config override → flow config default
    _ensure_run_env_loaded()

    # Read tool info: user_config override > node config default
    vendor = ''
    tool_name = ''

    # Priority 1: user_config (has the actual tool selection)
    flow_lower = flow_type.lower()
    user_config = os.path.join(run_dir, 'setup', 'user_config.tcl')
    if os.path.exists(user_config):
        import re as _re2
        with open(user_config) as _uc:
            for _line in _uc:
                m = _re2.search(rf'{flow_lower}\(tool,name\)\s+"([^"]+)"', _line)
                if m: tool_name = m.group(1)
                m = _re2.search(rf'{flow_lower}\(tool,vendor\)\s+"([^"]+)"', _line)
                if m: vendor = m.group(1)

    # Priority 2: project(default_tools) — {<FLOW> "<tool>" ...} pairs
    if not tool_name:
        proj_name = env_vars.get('CBFLOW_PROJECT_NAME', '')
        if proj_name:
            try:
                _dt = registry.project_value(proj_name, 'default_tools') or ''
            except registry.RegistryError as e:
                logger.error(f"  {e}")
                return 1
            pairs = _dt.split()
            for i in range(0, len(pairs) - 1, 2):
                if pairs[i] == flow_type:
                    tool_name = pairs[i + 1].strip('"')
                    break

    # Priority 3: node config default
    if not tool_name:
        try:
            from tcl_config_parser import get_tool_info
            tool_info = get_tool_info(flow_type)
            if not vendor: vendor = tool_info.get('vendor', '')
            if not tool_name: tool_name = tool_info.get('name', '')
        except Exception:
            pass

    # Auto-resolve vendor from tool-specific node config if missing
    if tool_name and not vendor:
        try:
            vendor = _tool_vendor_from_overlay(flow_type, tool_name)
        except registry.RegistryError as e:
            logger.error(f"  {e}")
            return 1

    if not vendor or not tool_name:
        logger.error("Tool vendor/name not configured. Check user_config or project default_tools.")
        return 1

    # Launch settings: tool_launch_config.tcl + lsf_config.tcl (+ user_config
    # overrides) through the resolver — no raw .tcl reads, no defaults here.
    import cbflow_config as _cbflow_cfg
    resolved = _cbflow_cfg.load_resolved_config(flow_type, run_dir, env=env_vars)
    try:
        tool_shell = _cbflow_cfg.require(resolved, f'lsf(tool_shell,{tool_name})')
        # a tool whose batch shell is not interactive (the open-source
        # container wrapper) declares its interactive shell
        tool_shell = _cbflow_cfg.optional(resolved, f'lsf(interactive,shell,{tool_name})') or tool_shell
        use_lsf = (_cbflow_cfg.require(resolved, 'flow(use_lsf)') == 'true')
        lsf_queue = _cbflow_cfg.require(resolved, 'lsf(interactive,queue)')
        lsf_runtime = _cbflow_cfg.require(resolved, 'lsf(interactive,runtime_limit)')
        _mem = _cbflow_cfg.require(resolved, 'lsf(interactive,memory)')
        xterm_cmd = _cbflow_cfg.require(resolved, 'lsf(xterm,command)')
        xterm_geom = _cbflow_cfg.require(resolved, 'lsf(xterm,geometry)')
        load_flags = _per_tool_key(resolved, 'lsf(interactive,load_flags', tool_name)
        empty_flags = _per_tool_key(resolved, 'lsf(interactive,empty_flags', tool_name)
    except (_cbflow_cfg.ConfigError, registry.RegistryError) as e:
        logger.error(f"  {e}")
        return 1
    lsf_memory = (str(int(_mem[:-2]) * 1000) if _mem.upper().endswith('GB') else _mem)
    # Module load — lsf(module,<tool>) in lsf_config.tcl (full command). Tools
    # without an entry run from PATH (e.g. the open-source container tools).
    module_cmd = _cbflow_cfg.optional(resolved, f'lsf(module,{tool_name})') or ''
    # GUI binary that replaces the tool shell for an empty session (icv -vue …).
    gui_shell = _cbflow_cfg.optional(resolved, f'lsf(tool_gui_shell,{tool_name})') or ''

    # Create INTERACTIVE directory
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    if load_node:
        session_name = f"{load_node}_{ts}"
    else:
        session_name = f"session_{ts}"

    interactive_dir = os.path.join(run_dir, 'INTERACTIVE', session_name)
    os.makedirs(interactive_dir, exist_ok=True)

    # ── Generate TCL load script for the node ──────────────────────────────
    load_tcl_path = None
    if load_node:
        load_tcl_path = os.path.join(interactive_dir, f'interactive.{load_node}.{tool_name}.tcl')
        node_base = load_node.rstrip('0123456789')

        # Resolve parent stage + scenario from load_node.
        #   - If load_node IS a stage (e.g. timing1) → parent=load_node, scenario=None
        #   - If load_node is a per-scenario subnode (e.g. timing1_func_ss_0p80v_rcmax_125c)
        #     → parent=timing1, scenario=func_ss_0p80v_rcmax_125c
        # This is needed for STA: a PT/Tempus session per scenario lives under
        # work/STA/<parent_stage>/run/<load_node>.session, not under work/STA/<load_node>/.
        parent_stage = load_node
        scenario = None
        try:
            _flow_stages = get_flow_stages(flow_type, run_dir=run_dir)
        except Exception:
            _flow_stages = []
        if load_node not in _flow_stages:
            # Longest-match: prefer the most specific stage prefix.
            for _s in sorted(_flow_stages, key=len, reverse=True):
                if load_node.startswith(_s + '_'):
                    parent_stage = _s
                    scenario = load_node[len(_s) + 1:]
                    break
        if scenario:
            logger.info(f"  Resolved subnode: {load_node} → stage={parent_stage}, scenario={scenario}")

        work_dir = _node_dir(flow_type, parent_stage, run_dir)

        # Per-tool restore script: lsf(interactive,restore,<tool>) (or ,default)
        # in tool_launch_config.tcl, read verbatim (multi-line Tcl).
        _rk = [f'lsf(interactive,restore,{tool_name})', 'lsf(interactive,restore,default)']
        try:
            _rv = _tcl_values([_pd_flow_config_file('tool_launch_config.tcl')], _rk)
        except (RuntimeError, registry.RegistryError) as e:
            logger.error(f"  {e}")
            return 1
        restore_tcl = _rv.get(_rk[0], _rv.get(_rk[1]))
        if restore_tcl is None:
            logger.error(f"  {_rk[0]} / {_rk[1]} not set (tool_launch_config.tcl)")
            return 1

        with open(load_tcl_path, 'w') as tf:
            tf.write(f"# CBflow Interactive — Load {load_node}\n")
            tf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            tf.write(f"# Flow: {flow_type} / Tool: {tool_name}\n\n")

            # Source run environment + config + utilities (all tools)
            tf.write(f"# Source run environment\n")
            tf.write(f'set ::env(CBFLOW_RUN_DIR) "{run_dir}"\n')
            run_tcl = os.path.join(run_dir, '.run.cbflow.tcl')
            if os.path.exists(run_tcl):
                tf.write(f'source "{run_tcl}"\n')
            # utilities before the node setup (it registers flow_proc hooks) —
            # the same order the stage command files use
            tf.write(f'source "$::env(CBFLOW_GLOBAL_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"\n')

            # Source node config + setup (tech/project/flow arrays + flow_proc hooks)
            config_tcl = os.path.join(work_dir, 'run', 'config.tcl')
            setup_tcl = os.path.join(work_dir, 'run', 'setup.tcl')
            if os.path.exists(config_tcl):
                tf.write(f'source "{config_tcl}"\n')
            if os.path.exists(setup_tcl):
                tf.write(f'source "{setup_tcl}"\n')
            tf.write("\n")

            # Session context consumed by the restore script
            tf.write("# Session context (used by lsf(interactive,restore,<tool>))\n")
            for _var, _val in (('cbflow_flow_type', flow_type), ('cbflow_tool', tool_name),
                               ('cbflow_run_dir', run_dir), ('cbflow_load_node', load_node),
                               ('cbflow_parent_stage', parent_stage),
                               ('cbflow_scenario', scenario or ''),
                               ('cbflow_node_base', node_base), ('cbflow_work_dir', work_dir),
                               ('cbflow_session_name', session_name),
                               ('cbflow_design_name', env_vars.get('CBFLOW_DESIGN_NAME', '')),
                               ('cbflow_notiming', '1' if notiming else '0')):
                tf.write(f'set {_var} "{_val}"\n')
            tf.write("\n")
            tf.write(restore_tcl.strip('\n') + "\n")

        logger.info(f"  Load TCL:  {load_tcl_path}")

    # ── Generate wrapper script ──────────────────────────────────────────
    wrapper_path = os.path.join(interactive_dir, 'launch_interactive.sh')
    with open(wrapper_path, 'w') as wf:
        wf.write("#!/bin/bash\n")
        wf.write(f"# CBflow Interactive Session — {flow_type} / {tool_name}\n")
        wf.write(f"# Session: {session_name}\n")
        wf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        wf.write(f"cd {interactive_dir}\n")
        if module_cmd:
            wf.write(f"{module_cmd}\n")
        wf.write(f"source {run_dir}/.run.cbflow.env\n")
        # the node's tool settings from its launch wrapper (container mounts,
        # image, PDK … for the open-source tools)
        if load_node:
            _lw = sorted(glob.glob(os.path.join(work_dir, 'run', 'launch_*.csh')))
            if _lw:
                with open(_lw[0]) as _lf:
                    for _ln in _lf:
                        _m = _re_mod.match(r'^setenv\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.*)$', _ln.strip())
                        if _m and _m.group(1) not in ('CBFLOW_NODE_NAME', 'CBFLOW_STAGE_NAME'):
                            wf.write(f"export {_m.group(1)}={_m.group(2)}\n")
        wf.write("\n")

        # Build tool invocation: lsf(interactive,load_flags|empty_flags,<tool>)
        if load_tcl_path:
            wf.write(' '.join(p for p in (tool_shell, load_flags, f'"{load_tcl_path}"') if p) + "\n")
        elif gui_shell:
            wf.write(f"{gui_shell}\n")
        else:
            wf.write(' '.join(p for p in (tool_shell, empty_flags) if p) + "\n")
        # a failed session (tool missing, license, load error) keeps its
        # window until Enter so the message can be read
        wf.write('_rc=$?\n'
                 'if [ $_rc -ne 0 ]; then\n'
                 '    echo; echo "Session ended with exit code $_rc — press Enter to close."; read -r _\n'
                 'fi\n')
    os.chmod(wrapper_path, 0o755)

    # ── Print summary ────────────────────────────────────────────────────
    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════")
    logger.info(f"  CBflow Interactive Session")
    logger.info(f"  ═══════════════════════════════════════════════════════")
    logger.info(f"  Flow:      {flow_type}")
    logger.info(f"  Tool:      {tool_name} ({vendor})")
    logger.info(f"  Shell:     {tool_shell}")
    if load_node:
        logger.info(f"  Load:      {load_node}")
        logger.info(f"  Load TCL:  {load_tcl_path}")
    logger.info(f"  Session:   INTERACTIVE/{session_name}")
    logger.info(f"  Wrapper:   {wrapper_path}")
    logger.info(f"  LSF:       {'Enabled' if use_lsf else 'Disabled (local)'}")
    logger.info("")

    # ── Launch ───────────────────────────────────────────────────────────
    title = f"CBflow {flow_type} {tool_name}"
    if load_node:
        title += f" [{load_node}]"

    if use_lsf:
        # Submit via LSF with interactive xterm. bsub binary: $CBFLOW_BSUB_CMD
        # (same override launch_utils.tcl honours), else lsf(bsub,command).
        import shlex as _shlex
        _bsub = os.environ.get('CBFLOW_BSUB_CMD', '').strip()
        if not _bsub:
            try:
                _bsub = _cbflow_cfg.require(resolved, 'lsf(bsub,command)')
            except _cbflow_cfg.ConfigError as e:
                logger.error(f"  {e}")
                return 1
        bsub_cmd = _shlex.split(_bsub) + [
            '-Is', '-q', lsf_queue,
            '-W', lsf_runtime, '-R',
            f'rusage[mem={lsf_memory}]',
            xterm_cmd, '-geometry', xterm_geom,
            '-title', title, '-e', wrapper_path
        ]
        logger.info(f"  Launch: LSF ({lsf_queue}) + xterm")
        logger.info(f"  Command: {' '.join(bsub_cmd)}")
        logger.info("")
        try:
            subprocess.Popen(bsub_cmd)
            logger.info(f"  Submitted to LSF queue '{lsf_queue}'")
        except FileNotFoundError:
            logger.error(f"  bsub not found. Run the wrapper manually:")
            logger.error(f"    {wrapper_path}")
            return 1
    else:
        # Local xterm — preflight before Popen so silent failures are caught.
        logger.info(f"  Launch: xterm (local)")
        # (a) xterm binary present?
        if not shutil.which(xterm_cmd):
            logger.error(f"  '{xterm_cmd}' not found in PATH.")
            logger.error(f"  Options:")
            logger.error(f"    1. Install xterm  (apt/yum install xterm)")
            logger.error(f"    2. Run the wrapper directly in this terminal:")
            logger.error(f"       bash {wrapper_path}")
            logger.error(f"    3. Set lsf(xterm,command) to another terminal")
            return 1
        # (b) DISPLAY set? (SSH without -X gives no DISPLAY → xterm exits silently)
        if not os.environ.get('DISPLAY'):
            logger.error(f"  DISPLAY is not set — xterm needs an X display.")
            logger.error(f"  If you're on SSH, reconnect with `ssh -X <host>` or `ssh -Y <host>`.")
            logger.error(f"  Or run the wrapper directly (no GUI): bash {wrapper_path}")
            return 1
        logger.info(f"  Opening: {xterm_cmd} -geometry {xterm_geom} -title \"{title}\"")
        # No -hold: a held window outlives its session and cannot be closed;
        # the wrapper pauses on a failed exit so the error stays readable.
        try:
            proc = subprocess.Popen([
                xterm_cmd, '-geometry', xterm_geom,
                '-title', title, '-e', wrapper_path
            ])
        except FileNotFoundError:
            logger.error(f"  Failed to launch {xterm_cmd}.")
            logger.error(f"  Run the wrapper manually: bash {wrapper_path}")
            return 1
        # Give xterm ~1s to fail. If it exits immediately, something went wrong
        # (missing tool binary, bad DISPLAY, wrapper error) — surface it.
        import time as _t
        _t.sleep(1.0)
        rc = proc.poll()
        if rc is not None and rc != 0:
            logger.error(f"  xterm exited immediately (rc={rc}).")
            logger.error(f"  Most likely: the EDA tool ('{tool_shell}') isn't in PATH")
            logger.error(f"  or its module wasn't loaded. Test in this terminal:")
            logger.error(f"    bash {wrapper_path}")
            return 1
        logger.info(f"  Interactive session launched (pid={proc.pid}).")

    logger.info(f"  Working directory: {interactive_dir}")
    return 0


def cmd_logs(args: argparse.Namespace) -> int:
    """View run logs."""
    from log_viewer import cmd_logs as view_logs
    return view_logs(args)


def cmd_help(args: argparse.Namespace) -> int:
    """Show detailed help."""
    flow_type = get_flow_type() if is_run_directory() else 'PNR'
    stages = get_flow_stages(flow_type)

    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info(f"  CBFlow Run Commands - Detailed Help")
    logger.info(f"  ═══════════════════════════════════════════════════════════")
    logger.info("")

    logger.info(f"FLOW EXECUTION:")
    logger.info("  cbflow run all                        Run complete flow")
    logger.info("  cbflow run all --validate              Run with pre/post validation")
    logger.info("  cbflow run all --lsf                   Submit stages via LSF")
    logger.info("  cbflow run all --lsf --queue XL        Submit with specific LSF queue")
    logger.info("  cbflow run all --collect-metrics        Collect timing metrics after run")
    logger.info("  cbflow run stage --name place1          Run a single stage")
    logger.info("  cbflow run stage --name cts1 --validate Run stage with validation")
    logger.info("  cbflow run stage --name route1 --lsf    Submit single stage to LSF")
    logger.info("")

    logger.info(f"STATUS & MONITORING:")
    logger.info("  cbflow run status                 Show stage completion status")
    logger.info("  cbflow run status --details       Show all subnodes per stage")
    logger.info("  cbflow run status --output s.txt  Dump status to file")
    logger.info("  cbflow run report                 Detailed per-node report (setup, config, errors)")
    logger.info("  cbflow run report --node place1   Report for a specific node only")
    logger.info("  cbflow run report --no-dump       Report without dumping setup file contents")
    logger.info("  cbflow run targets                List runnable stages")
    logger.info("  cbflow run lsf-status             Show LSF job queue status")
    logger.info("")

    logger.info(f"VALIDATION:")
    logger.info("  cbflow run validate                    Validate config + inputs + outputs")
    logger.info("  cbflow run validate --type config      Validate configuration only")
    logger.info("  cbflow run validate --type inputs      Validate netlist, SDC, DEF")
    logger.info("  cbflow run validate --stage place1     Validate outputs for 'place1'")
    logger.info("  cbflow run validate --type exit --stage cts1  Check CTS exit criteria")
    logger.info("")

    logger.info(f"LOG VIEWER:")
    logger.info("  cbflow run logs                   View latest log file")
    logger.info("  cbflow run logs --list            List all log files with sizes")
    logger.info("  cbflow run logs --tail 50         Show last 50 lines of latest log")
    logger.info("  cbflow run logs --level ERROR     Filter for errors only")
    logger.info("  cbflow run logs --search 'slack'  Search logs for pattern")
    logger.info("  cbflow run logs --file run.log    View specific log file")
    logger.info("")

    logger.info(f"RETRACE & FLOW CONTROL:")
    logger.info("  cbflow run retrace                Invalidate all jobs (rerun everything)")
    logger.info("  cbflow run retrace --from cts1    Invalidate from cts1 onwards")
    logger.info("  cbflow run bypass --stages X,Y    Skip stages (mark done without running)")
    logger.info("  cbflow run force --stages X       Re-run only X (no downstream invalidation)")
    logger.info("  cbflow run forcevalidate --node X       Mark single stage as already done")
    logger.info("  cbflow run forcevalidate --to place1    Mark start→place1 as done")
    logger.info("  cbflow run forcevalidate --from X --to Y  Mark range as done")
    logger.info("")

    logger.info(f"NODE MANAGEMENT:")
    logger.info("  cbflow run list-nodes             List all flow nodes")
    logger.info("  cbflow run show-graph             Show dependency graph with status")
    logger.info("  cbflow run show-graph --detail    Show graph with subnode details")
    logger.info("  cbflow run add-node --node place2 --type place --dep place1")
    logger.info("                                    Add custom node after place1")
    logger.info("  cbflow run set-dep --node export_data1 --deps place1")
    logger.info("                                    Rewire a node (--reset restores)")
    logger.info("  cbflow run delete-node --node place2")
    logger.info("                                    Remove custom node")
    logger.info("")

    logger.info(f"BRANCH MANAGEMENT:")
    logger.info("  cbflow run create-branch --branch fix_timing --from place1")
    logger.info("                                    Branch from place1")
    logger.info("  cbflow run list-branches          List all branches")
    logger.info("  cbflow run delete-branch --branch fix_timing")
    logger.info("")

    logger.info(f"RELEASE & UPDATE:")
    logger.info("  cbflow run release-info           Show current release version")
    logger.info("  cbflow run update                 Update to latest workspace release")
    logger.info("  cbflow run update --release v1.0.1  Update to specific version")
    logger.info("  cbflow run gen-makefile           Verify engine DAG structure")
    logger.info("  cbflow run release --tag PLACE_EXIT          Release (from workarea)")
    logger.info("  cbflow run release --tag BTO --publish       Release + publish to SmartGrid")
    logger.info("  cbflow run release --from-run . --publish    Publish a run's own release")
    logger.info("  cbflow run release --from-run . --clone-from BTO --tag MTO")
    logger.info("                                    Copy the BTO release to MTO")
    logger.info("")

    logger.info(f"EMAIL & REPORTING:")
    logger.info("  cbflow run email --to user@co.com --template run-status")
    logger.info("  cbflow run email --to user@co.com --template run-summary --preview")
    logger.info("  cbflow run email --to user@co.com --template checklist")
    logger.info("  cbflow run autoppt                Generate PD run summary (HTML)")
    logger.info("  cbflow run autoppt --format pptx  Generate PowerPoint summary")
    logger.info("")

    logger.info(f"EXIT CHECKLIST:")
    logger.info("  cbflow run checklist --milestone PRO_EXIT --phase P2")
    logger.info("  cbflow run checklist --milestone BTO --phase P3 --format html")
    logger.info("  cbflow run checklist --milestone BTO --sign-off --approver chip_lead")
    logger.info("  cbflow run checklist --list       List available milestones")
    logger.info("")

    logger.info(f"INTERACTIVE SESSION:")
    logger.info("  cbflow run interactive --node place1          Load place1 design")
    logger.info("  cbflow run interactive --node signoff1        Load signoff checkpoint")
    logger.info("")

    logger.info(f"CLEANUP:")
    logger.info("  cbflow run clean --confirm        Delete work/, logs/")
    logger.info("")

    if stages:
        logger.info(f"AVAILABLE STAGES ({flow_type}):")
        stage_list = ' -> '.join(stages)
        logger.info(f"  {stage_list}")
        logger.info("")

    return 0


def cmd_validate_run(args: argparse.Namespace) -> int:
    """Run validation on current run directory."""
    from validation_cmd import cmd_validate
    return cmd_validate(args)


def cmd_lsf_status_run(args: argparse.Namespace) -> int:
    """Show LSF job status."""
    _ensure_run_env_loaded()
    from lsf_cmd import cmd_lsf_status
    return cmd_lsf_status(args)


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow run',
        description='CBFlow - Flow Execution',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Quick Reference:
  cbflow run all                                 Run complete flow
  cbflow run all --validate                      Run with validation checks
  cbflow run all --lsf --queue XL                Submit to LSF cluster
  cbflow run stage --name place1                 Run single stage
  cbflow run status --details                    Show detailed progress
  cbflow run validate --stage cts1               Validate stage outputs
  cbflow run logs --tail 50 --level ERROR        View recent errors
  cbflow run show-graph --detail                 Visualize flow graph
  cbflow run add-node --node place2 --type place --dep place1
  cbflow run set-dep --node export_data1 --deps place1   Rewire a node
  cbflow run bypass --stages cts1,route1         Mark stages done without running
  cbflow run retrace --from cts1                 Reset cts1 onwards (--run reruns)
  cbflow run report                              Detailed node report with setup dumps
  cbflow run report --node place1                Report for specific node
  cbflow run lsf-status                          Check LSF job queue
  cbflow run checklist --milestone BTO --phase P3  Run exit milestone checklist
  cbflow run release --tag PLACE_EXIT --publish  Release (from workspace) + publish
  cbflow run release --from-run . --publish      Publish a run's own release (open-source)
  cbflow run email --to user@co.com --template run-status   Send email report
  cbflow run autoppt                             Generate run summary PPT/HTML

  Run 'cbflow run help' for full documentation with examples.
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    _fmt = argparse.RawDescriptionHelpFormatter

    # all command
    all_parser = subparsers.add_parser('all', help='Run complete flow',
        formatter_class=_fmt, description="""Run the complete flow (all stages sequentially).

Examples:
  cbflow run all                     Run all stages
  cbflow run all --validate          Validate before and after each stage
  cbflow run all --lsf               Submit each stage to LSF cluster
  cbflow run all --lsf --queue XL    Use XL queue (64GB, 32 CPU)
  cbflow run all --collect-metrics   Save timing data to metrics database""")
    all_parser.add_argument('--validate', action='store_true', help='Enable pre/post validation')
    all_parser.add_argument('--lsf', action='store_true', help='Submit stages via LSF')
    all_parser.add_argument('--queue', help='LSF queue override (S, M, L, XL, ultra)')
    all_parser.add_argument('--collect-metrics', action='store_true',
                           help='Collect run metrics after completion')

    # stage command
    stage_parser = subparsers.add_parser('stage', help='Run a specific stage',
        formatter_class=_fmt, description="""Run a single stage or subnode of the flow.

Examples:
  cbflow run stage --name place1             Run full placement stage (all subnodes)
  cbflow run stage -n cts1                   Short form
  cbflow run stage --name init_design1 --subnode run    Run only the 'run' subnode
  cbflow run stage -n cts1 -s setup          Run only CTS setup subnode
  cbflow run stage --name route1 --validate  Run with validation
  cbflow run stage --name signoff1 --lsf     Submit to LSF""")
    stage_parser.add_argument('--name', '-n', dest='stage', required=True, help='Stage name')
    stage_parser.add_argument('--subnode', '-s', default=None,
                             help='Run a specific subnode only (e.g., setup, run, validate, finish)')
    stage_parser.add_argument('--validate', action='store_true', help='Enable pre/post validation')
    stage_parser.add_argument('--lsf', action='store_true', help='Submit via LSF')
    stage_parser.add_argument('--queue', help='LSF queue override')

    # status command
    status_parser = subparsers.add_parser('status', help='Show run status',
        formatter_class=_fmt, description="""Show completion status for all stages.

Examples:
  cbflow run status                  Show stage completion
  cbflow run status --details        Show all subnodes per stage
  cbflow run status --output s.txt   Save status to file""")
    status_parser.add_argument('--details', '-d', action='store_true', help='Show detailed status with subnodes')
    status_parser.add_argument('--output', '-o', help='Dump status to a text file')

    # retrace command
    retrace_parser = subparsers.add_parser('retrace', help='Invalidate stages so they rerun',
        formatter_class=_fmt, description="""Invalidate stages in the RACE DB so they rerun.

Does NOT automatically rerun - only invalidates. Use --run to also execute.

Examples:
  cbflow run retrace                    Invalidate all stages
  cbflow run retrace --from cts1        Invalidate cts1 and every later stage
  cbflow run retrace --run              Invalidate all stages and rerun
  cbflow run retrace --from cts1 --run  Invalidate from cts1 and rerun""")
    retrace_parser.add_argument('--from', dest='from_stage', help='Retrace from this stage onwards')
    retrace_parser.add_argument('--run', action='store_true', help='Rerun the flow after invalidating')

    # bypass command
    bypass_parser = subparsers.add_parser('bypass', help='Skip stages (mark as done without running)',
        formatter_class=_fmt, description="""Mark stages as DONE without executing.
Useful for skipping stages not needed in this run (e.g., skip export_data).
A fully bypassed stage gets work/<FLOW>/<node>/BYPASSED.

Examples:
  cbflow run bypass --stages export_data1,release_data1
  cbflow run bypass --stages init_design1        Skip just init_design
  cbflow run bypass --stages cts1,cts_opt1,route1,pro1,signoff1
                                                 Release place1 as PLACE_EXIT:
                                                 then cbflow run stage --name release_data1
  cbflow run bypass --stages timing1:func_ff_1p95v_rc_min_m40c
                                                 Skip one STA scenario

A target is a stage (timing1) or one scenario subnode of a dynamic MMMC
stage — <stage>:<scenario> (timing1:func_ss_1p60v_rc_max_100c) or its job
name (timing1_func_ss_1p60v_rc_max_100c); an unknown scenario lists the
stage's scenarios.""")
    bypass_parser.add_argument('--stages', '-s', required=True,
                               help='Comma-separated stages and/or <stage>:<scenario> subnodes to bypass')

    # force command
    force_parser = subparsers.add_parser('force', help='Force re-run specific stages only',
        formatter_class=_fmt, description="""Force re-execute specific stages (or scenario subnodes) now.
The named targets re-run; completed jobs that depend on them are invalidated
(re-run them with cbflow run all). For a scenario subnode only that scenario
re-runs — its sibling scenarios keep their results. Dependencies must already be DONE.

Examples:
  cbflow run force --stages place1               Re-run place
  cbflow run force --stages cts1,cts_opt1        Re-run CTS stages
  cbflow run force --stages timing1:func_ss_1p60v_rc_max_100c
                                                 Re-run one STA scenario

A target is a stage (timing1) or one scenario subnode of a dynamic MMMC
stage — <stage>:<scenario> (timing1:func_ss_1p60v_rc_max_100c) or its job
name (timing1_func_ss_1p60v_rc_max_100c); an unknown scenario lists the
stage's scenarios.""")
    force_parser.add_argument('--stages', '-s', required=True,
                              help='Comma-separated stages and/or <stage>:<scenario> subnodes to force re-run')

    # forcevalidate command
    fv_parser = subparsers.add_parser('forcevalidate', help='Mark stages as already completed',
        formatter_class=_fmt, description="""Mark stages as DONE as if they ran successfully.
Use when a stage was run outside CBflow (manual tool run, data from another run, etc.).

Three modes:
  --node X              Mark single node as done
  --from X --to Y       Mark range of stages as done
  --from X              Mark from X to end as done
  --to Y                Mark from start to Y as done

Examples:
  cbflow run forcevalidate --node place1
  cbflow run forcevalidate --from inputs1 --to synthesis1
  cbflow run forcevalidate --to place1     Mark everything up to place as done
  cbflow run forcevalidate --from route1   Mark route onwards as done
  cbflow run forcevalidate --node timing1:func_ff_1p95v_rc_min_100c
                                           Mark one STA scenario as done

--node / --stages also take a scenario subnode: <stage>:<scenario> or its
job name (a stage's scenarios are listed when the name is unknown).""")
    fv_parser.add_argument('--node', '-n', help='Single stage (or <stage>:<scenario>) to mark as completed')
    fv_parser.add_argument('--from', dest='from_stage', help='Start of range (inclusive)')
    fv_parser.add_argument('--to', dest='to_stage', help='End of range (inclusive)')
    fv_parser.add_argument('--stages', '-s', help='Comma-separated list (backward compat)')

    # clean command
    clean_parser = subparsers.add_parser('clean', help='Clean run directory',
        formatter_class=_fmt, description="""Delete all work files and logs (and deregister the run from the dashboard).

Examples:
  cbflow run clean --confirm         Delete work/, logs/""")
    clean_parser.add_argument('--confirm', action='store_true', help='Confirm cleanup')

    # list-nodes command
    subparsers.add_parser('list-nodes', help='List flow nodes',
        formatter_class=_fmt, description="""Show all base flow nodes and custom nodes with status.

Examples:
  cbflow run list-nodes              Show nodes with completion status""")

    # show-graph command
    graph_parser = subparsers.add_parser('show-graph', help='Show flow dependency graph',
        formatter_class=_fmt, description="""Display the flow dependency graph visually.

Examples:
  cbflow run show-graph              Show graph with completion status
  cbflow run show-graph --detail     Include subnodes inside each stage""")
    graph_parser.add_argument('--detail', '-d', action='store_true', help='Show subnodes in graph')

    # add-node command
    add_node_parser = subparsers.add_parser('add-node', help='Add custom node',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="""Add a custom node to the flow.

Usage:
  cbflow run add-node --type <stage_type> --dep <after_node> [--node <name>]

Arguments:
  --type, -t    Node type - must match a valid stage type in current flow (required)
  --dep,  -d    Dependency - the new node runs after this node (required)
  --node, -n    Node name (optional - auto-generated as type+next_number if omitted)

Examples:
  cbflow run add-node --type place --dep place1         # auto-names as place2
  cbflow run add-node --node export_data2 --type export_data --dep place1
  cbflow run add-node --node release_data2 --type release_data --dep export_data2

  Added nodes inherit runtime,timeout from their base stage.

  Use 'cbflow run list-nodes' to see existing nodes
  Use 'cbflow run show-graph' to see the dependency graph""")
    add_node_parser.add_argument('--node', '-n', required=False, default=None,
                                help='Node name (optional - auto-generated from type if omitted)')
    add_node_parser.add_argument('--type', '-t', required=True,
                                help='Node type - must be a valid stage type for current flow')
    add_node_parser.add_argument('--dep', '-d',
                                help='Dependency node - the new node runs after this one')
    add_node_parser.add_argument('--resource-tier', '-r', default='',
                                choices=[''] + _lsf_tiers(),
                                help=('Override LSF resource tier for this node '
                                      '(XS/S/M/L/XL/ultra). Omit to inherit from '
                                      'the base stage or lsf(default_queue_type).'))

    # set-dep command
    set_dep_parser = subparsers.add_parser('set-dep', help='Rewire a node\'s dependencies',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="""Rewire a node's dependencies (base or custom node).

Usage:
  cbflow run set-dep --node <node> --deps <node>[,<node>...]
  cbflow run set-dep --node <node> --reset

Releasing an intermediate stage — three ways, any of them:
  1. bypass the stages after it, then run export + release:
       cbflow run bypass --stages cts1,cts_opt1,route1,pro1,signoff1
       cbflow run stage --name release_data1
  2. rewire export onto it:
       cbflow run set-dep --node export_data1 --deps place1
       cbflow run stage --name release_data1
  3. add an export + release pair under it:
       cbflow run add-node --node export_data2 --type export_data --dep place1
       cbflow run add-node --node release_data2 --type release_data --dep export_data2
       cbflow run stage --name release_data2
  The release takes the source stage's exit (place -> PLACE_EXIT, cts_opt ->
  CTS_EXIT, pro -> PRO_EXIT, signoff -> BTO).""")
    set_dep_parser.add_argument('--node', '-n', required=True, help='Node to rewire')
    set_dep_parser.add_argument('--deps', '-d', default='',
                                help='New dependency node(s), comma- or space-separated')
    set_dep_parser.add_argument('--reset', action='store_true',
                                help='Drop the override: back to the node config\'s dependencies')

    # delete-node command
    del_node_parser = subparsers.add_parser('delete-node', help='Delete custom node',
        formatter_class=_fmt, description="""Remove a custom node from the flow.

Examples:
  cbflow run delete-node --node place2
  cbflow run delete-node -n eco1""")
    del_node_parser.add_argument('--node', '-n', required=True, help='Node name to remove')

    # create-branch command
    branch_parser = subparsers.add_parser('create-branch', help='Create flow branch',
        formatter_class=_fmt, description="""Create a branch in the flow from an existing stage.

Examples:
  cbflow run create-branch --branch fix_timing --from place1
  cbflow run create-branch -b experiment --from cts1""")
    branch_parser.add_argument('--branch', '-b', required=True, help='Branch name')
    branch_parser.add_argument('--from', dest='from_stage', required=True, help='Source stage to branch from')

    # list-branches command
    subparsers.add_parser('list-branches', help='List flow branches',
        formatter_class=_fmt, description="""Show all branches in the current flow.

Examples:
  cbflow run list-branches""")

    # delete-branch command
    del_branch_parser = subparsers.add_parser('delete-branch', help='Delete flow branch',
        formatter_class=_fmt, description="""Delete a branch from the flow.

Examples:
  cbflow run delete-branch --branch fix_timing
  cbflow run delete-branch --from place2""")
    del_branch_group = del_branch_parser.add_mutually_exclusive_group(required=True)
    del_branch_group.add_argument('--branch', '-b', help='Branch name to delete')
    del_branch_group.add_argument('--from', dest='from_node', help='Delete branch starting from this node')

    # update command
    update_parser = subparsers.add_parser('update', help='Update to workspace release or specific version',
        formatter_class=_fmt, description="""Update the run to a new release version.

Examples:
  cbflow run update                      Update to latest workspace release
  cbflow run update --release v1.0.1     Update to specific version
  cbflow run update --release v2.0.0 --no-backup  Skip backup""")
    update_parser.add_argument('--release', '-r', help='Target release version (e.g., v2.0.0)')
    update_parser.add_argument('--no-backup', action='store_true', help='Skip backup of environment files')

    # gen-makefile command
    subparsers.add_parser('gen-makefile', help='Verify the RACE DAG (legacy name)',
        formatter_class=_fmt, description="""Verify the RACE DAG for the current run.

Examples:
  cbflow run gen-makefile                Verify engine DAG structure""")

    # release-info command
    subparsers.add_parser('release-info', help='Show release information',
        formatter_class=_fmt, description="""Show the release version used by this run.

Examples:
  cbflow run release-info""")

    # release command (milestone-gated)
    release_parser = subparsers.add_parser('release', help='Milestone-gated release to shared path',
        formatter_class=_fmt, description="""Package deliverables from ALL required flows into a release directory.

Run from the workarea (default) or point --from-run at a run that released itself.
Release is milestone-gated: all required flows for the tag must have completed runs,
and earlier exits of the phase (project(phase_exits)) must already be released.
Layout: <project(release,path)>/<phase>/<block>/<FLOW>/<tag>
Tags are predefined in release_config.tcl; default tag = project(release,active_tag).
Publishing to SmartGrid is opt-in (--publish).

Examples:
  cbflow run release                    Release using the active tag
  cbflow run release --tag BTO          Override with explicit tag
  cbflow run release --tag BTO --publish  Release + publish to SmartGrid
  cbflow run release --dry-run          Validate only, don't copy files
  cbflow run release --from-run . --node release_data1 --publish
                                        Publish an open-source run's own release
  cbflow run release --from-run <run> --clone-from BTO --tag MTO --publish
                                        Copy the BTO release to MTO and publish it""")
    release_parser.add_argument('--tag', '-t', help='Exit milestone to release (default: project active_tag)')
    release_parser.add_argument('--name', default=None,
                                help='Release tag name (default: the exit name)')
    release_parser.add_argument('--dry-run', action='store_true', help='Validate only, no file copy')
    # Publish is opt-in. default=None (not False) so cmd_release can tell
    # "flag not given" from an explicit --no-publish.
    # Tri-state publish (None = flag not given). Two store_const options on
    # one dest, not the boolean-optional argparse action: that needs Python 3.9+
    # and this parser is built for every `cbflow run` invocation.
    release_parser.add_argument('--publish', dest='publish', action='store_const',
                                const=True, default=None,
                                help='After release, snapshot metrics+checklist into '
                                     'SmartGrid (the project dashboard). Opt-in: without '
                                     '--publish nothing is published. Starts the SmartGrid '
                                     'daemon if needed and fails on a publish error.')
    release_parser.add_argument('--from-run', dest='from_run', default=None,
                                help='Run directory that released itself (open-source '
                                     'flows: release_data stage) — no repackaging; with '
                                     '--publish, publish that release to the --tag milestone.')
    release_parser.add_argument('--clone-from', dest='clone_from', default=None,
                                help='With --from-run and --tag: copy the run flow\'s release '
                                     'of this exit to the --tag exit (e.g. --clone-from BTO '
                                     '--tag MTO when nothing changed); same stage, exit order '
                                     'enforced; --publish publishes the copy.')
    release_parser.add_argument('--node', dest='node', default=None,
                                help='With --from-run: the release node whose release to '
                                     'publish (e.g. release_data2 added under an export of '
                                     'place); default the flow\'s release_data node.')
    release_parser.add_argument('--no-publish', dest='publish', action='store_const',
                                const=False,
                                help='Skip the SmartGrid publish (the default; kept for scripts).')
    release_parser.add_argument('--override', action='store_true',
                                help='On publish: replace an existing published entry '
                                     'for this (project, block, phase, milestone) cell')

    # release-lock command (permissions)
    lock_parser = subparsers.add_parser('release-lock', help='Set production permissions',
        formatter_class=_fmt, description="""Lock CBflow to production permissions or unlock for development.

Examples:
  cbflow run release-lock              Set read-only/executable permissions
  cbflow run release-lock --unlock     Set 777 permissions (development mode)""")
    lock_parser.add_argument('--unlock', action='store_true', help='Set 777 permissions instead of locking')

    # release-check command (chip-level)
    rc_parser = subparsers.add_parser('release-check', help='Check chip-level release readiness',
        formatter_class=_fmt, description="""Check that all blocks have released for a milestone tag.

Scans all blocks in project(block_list) and verifies each has complete releases for all required flows.

Examples:
  cbflow run release-check --tag BTO --project opensky --phase P2
  cbflow run release-check --tag PLACE_EXIT --project bumblebee --phase LC2
  cbflow run release-check --tag BTO --project bumblebee --phase LC3 --block cpu_core""")
    rc_parser.add_argument('--tag', '-t', required=True, help='Release tag to check')
    rc_parser.add_argument('--project', '-p', required=True, help='Project name')
    # No default: --phase must be explicit. Pre-fix the P0 default silently
    # mis-tagged release-check runs on non-P0 projects (bumblebee uses LC1-LC5).
    rc_parser.add_argument('--phase',
                           help='Design phase from project(phases) (e.g. opensky P0-P3, '
                                'bumblebee LC1-LC5); default $CBFLOW_PROJECT_PHASE')
    rc_parser.add_argument('--block', '-b', help='Check specific block only (default: all blocks)')

    # targets command
    subparsers.add_parser('targets', help='List runnable stages',
        formatter_class=_fmt, description="""List the stages of this run as 'cbflow run stage' commands.

Examples:
  cbflow run targets""")

    # logs command
    logs_parser = subparsers.add_parser('logs', help='View run logs',
        formatter_class=_fmt, description="""View, search, and filter log files from the run.

Examples:
  cbflow run logs                        Show latest log
  cbflow run logs --list                 List all log files with sizes
  cbflow run logs --tail 50              Show last 50 lines
  cbflow run logs --level ERROR          Show only errors
  cbflow run logs --search 'slack'       Search for pattern
  cbflow run logs --file place.log       View specific file""")
    logs_parser.add_argument('--list', '-l', dest='list_logs', action='store_true',
                            help='List all log files')
    logs_parser.add_argument('--tail', '-t', type=int, default=None,
                            help='Show last N lines')
    logs_parser.add_argument('--search', '-s', help='Search pattern (regex supported)')
    logs_parser.add_argument('--level', choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                            help='Filter by log level')
    logs_parser.add_argument('--file', '-f', dest='log_file', help='Specific log file to view')

    # validate command
    validate_parser = subparsers.add_parser('validate', help='Validate run',
        formatter_class=_fmt, description="""Run validation checks on the current run.

Examples:
  cbflow run validate                    Full validation (config + inputs + outputs)
  cbflow run validate --type config      Validate configuration files only
  cbflow run validate --type inputs      Validate netlist, SDC, DEF files
  cbflow run validate --stage place1     Validate stage outputs + exit criteria
  cbflow run validate --type exit --stage cts1  Check CTS exit criteria""")
    validate_parser.add_argument('--type', choices=['all', 'config', 'inputs', 'exit'],
                                default='all', help='Validation type')
    validate_parser.add_argument('--stage', help='Stage to validate')

    # report command
    report_parser = subparsers.add_parser('report', help='Detailed per-node report',
        formatter_class=_fmt, description="""Generate a detailed report for each node showing subnodes,
setup files (with contents), command files, outputs, and errors.

Examples:
  cbflow run report                        Full report for all stages
  cbflow run report --node place1          Report for a specific node
  cbflow run report --dump-setup           Dump setup.tcl and config.tcl contents
  cbflow run report --node inputs1 --dump-setup  Dump setup files for inputs""")
    report_parser.add_argument('--node', '-n', help='Report for a specific node only')
    report_parser.add_argument('--dump-setup', action='store_true', default=True,
                               help='Dump setup.tcl and config.tcl contents (default: on)')
    report_parser.add_argument('--no-dump', dest='dump_setup', action='store_false',
                               help='Skip dumping setup file contents')

    # lsf-status command
    lsf_parser = subparsers.add_parser('lsf-status', help='Show LSF job status',
        formatter_class=_fmt, description="""Show the LSF jobs of this run.

Examples:
  cbflow run lsf-status
  cbflow run lsf-status --flow PNR""")
    lsf_parser.add_argument('--flow', help='Filter by flow type')

    # debug command — print the resolved cascade dict for this run.
    debug_parser = subparsers.add_parser(
        'debug',
        help='Inspect resolved config / engine internals',
        description="""Inspect the cascade-resolved config dict the engine uses.

Useful when production reports "use_lsf=true was ignored" or any config-shaped
bug — one invocation shows exactly which key the engine sees and which file
contributed it.

Examples:
  cbflow run debug --dump-resolved-cfg
  cbflow run debug --dump-resolved-cfg --key 'flow(use_lsf)'""",
        formatter_class=_fmt)
    debug_parser.add_argument('--dump-resolved-cfg', action='store_true',
                              help='Print every resolved config key=value, '
                                   'one per line, plus contributing source files')
    debug_parser.add_argument('--key',
                              help='Print only this key (with cascade sources)')

    # help command
    # interactive command
    interactive_parser = subparsers.add_parser('interactive', help='Launch interactive EDA tool session',
        formatter_class=_fmt, description="""Open an interactive EDA tool session in xterm.

Restores a node's saved design and opens the tool in GUI mode.
Creates a working directory under INTERACTIVE/<node>_<timestamp>.
Open-source runs (openroad / sta / yosys) open via cbflow-oss interactive.

For STA (PT/Tempus), --node may name either the stage (e.g. timing1) or a
per-scenario subnode (e.g. timing1_func_ss_0p80v_rcmax_125c). The subnode form
loads the exact scenario session AND sources the scenario context so
CORNER/MODE/VOLTAGE/TEMPERATURE/RC_CORNER/SDC_FILE/SPEF_FILE match the batch run.

Examples:
  cbflow run interactive --node place1                            Load place1 (PNR)
  cbflow run interactive --node signoff1                          Load signoff1 checkpoint
  cbflow run interactive --node timing1                           STA — pick any session
  cbflow run interactive --node timing1_func_ss_0p80v_rcmax_125c  STA — exact scenario""")
    interactive_parser.add_argument('--node', '-n', required=True,
                                   help='Node or subnode to restore (stage names or STA per-scenario subnodes)')
    interactive_parser.add_argument('--notiming', action='store_true', default=False,
                                   help='Launch without timing libraries (faster startup; Innovus)')

    # email command
    try:
        from email_cmd import create_parser as email_create_parser
        email_create_parser(subparsers)
    except ImportError:
        subparsers.add_parser('email', help='Send email notifications (email_cmd.py not found)')

    # autoppt command (optional — disabled by default, enable via project(autoppt,enabled) "true")
    try:
        from autoppt_cmd import create_parser as autoppt_create_parser
        autoppt_create_parser(subparsers)
    except Exception:
        pass

    # checklist command — run-level only: status, generate, sign-off
    ck = subparsers.add_parser('checklist', help='Run exit milestone checklist',
        formatter_class=_fmt, description="""Run exit milestone checklist against the current run directory.

Validates mandatory checks, files, and deliverables for a given milestone and phase.
If run has completed stages (in RACE DB), shows PASS/FAIL status per check.
Otherwise generates the checklist template.

To manage checks (add/remove/edit), use:  cbflow flow checklist add-check ...

Examples:
  cbflow run checklist --milestone PRO_EXIT --phase P2
  cbflow run checklist --milestone BTO --phase P3 --format html
  cbflow run checklist --milestone FP_EXIT --sign-off --approver chip_lead
  cbflow run checklist --list
""")
    try:
        _ms_help = ', '.join(release_exits.milestone_order())
    except release_exits.PhaseExitsError:
        _ms_help = 'MILESTONE_ORDER in release_config.tcl'
    ck.add_argument('--milestone', '-m', help=f'Exit milestone ({_ms_help})')
    ck.add_argument('--phase', '-p', help='Design phase from project(phases) (e.g. P0-P3, LC1-LC5)')
    ck.add_argument('--format', '-f', choices=['text', 'json', 'html'], default='text', help='Output format')
    ck.add_argument('--project', default='', help='Project name for threshold overrides')
    ck.add_argument('--sign-off', action='store_true', dest='sign_off', help='Record sign-off')
    ck.add_argument('--approver', help='Approver name (required with --sign-off)')
    ck.add_argument('--list', action='store_true', dest='list_milestones', help='List available milestones')

    # dashboard command
    dash_parser = subparsers.add_parser('gui', help='Open RACE GUI',
        formatter_class=_fmt, description="""Open the run in the CBflow dashboard.

Default: registers this run with the per-user dashboard daemon
(starts the daemon if not running) and opens the browser to the
run's deep-link. The daemon's port is deterministic per user and
discipline: flow(dashboard,port_base,<DISC>) + uid % flow(dashboard,port_width)
(PD 9000, DFT 9300, DV 9600, RTL 9900; width 300) — pass --port to
'cbflow run dashboard start', not here.

Examples:
  cbflow run gui                  Register + open in daemon (default)
  cbflow run gui --no-browser     Register but don't open browser
  cbflow run gui --public         Bind daemon to LAN (http://<host>:<port>/)
                                  — needed for remote browsers in production
  cbflow run gui --foreground     Legacy: per-run foreground server
  cbflow run gui --foreground --port 9090
                                  Legacy server on a specific port""")
    dash_parser.add_argument('--port', '-p', type=int, default=0,
                             help='Port for --foreground mode only (default: auto). '
                                  'In daemon mode use: cbflow run dashboard start --port N')
    dash_parser.add_argument('--no-browser', action='store_true', dest='no_browser', help='Don\'t open browser')
    dash_parser.add_argument('--foreground', action='store_true',
                             help='Run a per-run foreground server (legacy). Skips the daemon.')
    dash_parser.add_argument('--daemon', action='store_true',
                             help='Explicitly use daemon mode (now the default; flag kept for clarity)')
    dash_parser.add_argument(
        '--public', action='store_true',
        help='Bind the daemon to 0.0.0.0 so remote browsers on the LAN can '
             'reach the dashboard at http://<hostname>:<port>/. Default is '
             'localhost-only (reach via SSH tunnel). Env: '
             'CBFLOW_DASHBOARD_BIND_ADDR.')
    dash_parser.add_argument(
        '--bind-addr', dest='bind_addr', default=None,
        help='Explicit bind interface — overrides --public when both given.')

    db_parser = subparsers.add_parser('db-manage', help='Manage RACE database sessions',
        formatter_class=_fmt, description="""Manage RACE SQLite database sessions.

Lists all existing RACE databases for the current user, shows disk usage,
and provides options to delete old/unwanted sessions.

The maximum number of DB sessions is controlled by flow(race,db_max_sessions).
A warning is issued when the threshold is reached.

Examples:
  cbflow run db-manage                  Check session count vs limit
  cbflow run db-manage --list           List all DBs (owner, flow, result, size)
  cbflow run db-manage --cleanup        Interactive delete (owner only)
  cbflow run db-manage --delete <run>   Delete one run's DB (owner only)""")
    db_parser.add_argument('--list', '-l', action='store_true', dest='db_list', help='List all databases')
    db_parser.add_argument('--delete', '-d', metavar='RUN', help='Delete DB for a specific run')
    db_parser.add_argument('--cleanup', action='store_true', help='Interactive cleanup of old databases')
    db_parser.add_argument('--check', action='store_true', help='Check session count against limit')

    subparsers.add_parser('help', help='Show detailed help')

    return parser


def cmd_gui(args):
    """Open the run in the CBflow dashboard.

    Default: per-user daemon (Phase 2). Legacy foreground server via
    --foreground. Passing --port without --foreground is an error — the
    daemon's port is set at daemon start.
    """
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    use_foreground = getattr(args, 'foreground', False)
    explicit_daemon = getattr(args, 'daemon', False)
    no_browser = getattr(args, 'no_browser', False)
    port = getattr(args, 'port', 0) or 0

    if use_foreground and explicit_daemon:
        logger.error("--foreground and --daemon are mutually exclusive")
        return 2

    # Default = daemon. Foreground only if user opted out.
    if not use_foreground:
        if port:
            logger.error(
                "--port is not used in daemon mode (the daemon owns a single "
                "deterministic port).")
            logger.error("To change the daemon's port:")
            logger.error("  cbflow dashboard stop")
            logger.error(f"  cbflow dashboard start --port {port}")
            return 2
        return _cmd_gui_daemon(no_browser,
                               public=getattr(args, 'public', False),
                               bind_addr=getattr(args, 'bind_addr', None))

    # --foreground: legacy per-run server (unchanged).
    import sys
    sys.path.insert(0, os.path.join(os.environ.get('FLOW_DIR', ''), 'utils', 'dashboard'))
    try:
        from race_dashboard import start_dashboard
    except ImportError:
        dashboard_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'dashboard')
        sys.path.insert(0, dashboard_dir)
        from race_dashboard import start_dashboard
    return start_dashboard(os.getcwd(), port=port,
                           open_browser=not no_browser,
                           public=getattr(args, 'public', False)) or 0


def _cmd_gui_daemon(no_browser, public=False, bind_addr=None):
    """Register the current run with the per-user dashboard daemon.

    One daemon per discipline (PD, DFT, DV) — the current run's flow type
    determines which daemon this call targets. A DV run won't accidentally
    register with the PD daemon, so each discipline's dashboard shows only
    its own runs.

    `public` / `bind_addr` are forwarded to ensure_daemon if the daemon
    isn't already running. If the daemon is already up with a different
    bind, the user must `cbflow dashboard restart --public` (or stop and
    restart) — we don't transparently rebind a running daemon.
    """
    import sys
    dashboard_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'dashboard')
    if dashboard_dir not in sys.path:
        sys.path.insert(0, dashboard_dir)
    import lifecycle  # noqa: E402

    # Resolve the current run's discipline so each discipline gets its
    # own daemon. The launcher doesn't source .run.cbflow.env, so
    # CBFLOW_FLOW_TYPE isn't in os.environ — read the file directly from
    # the run dir. A flow without flow(discipline,<FLOW>) is an error.
    discipline = None
    flow_type = os.environ.get('CBFLOW_FLOW_TYPE', '').strip().upper()
    if not flow_type:
        env_file = os.path.join(os.getcwd(), '.run.cbflow.env')
        if os.path.exists(env_file):
            try:
                with open(env_file) as _f:
                    for _line in _f:
                        _line = _line.strip()
                        if _line.startswith('export CBFLOW_FLOW_TYPE='):
                            flow_type = _line.split('=', 1)[1].strip().strip('"').upper()
                            break
            except OSError:
                pass
    if flow_type:
        # flow(discipline,<FLOW>) in flow_registry.tcl — required, no PD default.
        try:
            discipline = registry.flow_discipline(flow_type).upper()
        except registry.RegistryError as _e:
            logger.error(f'run_cmd: {_e} — cannot pick the dashboard daemon for this run.')
            return 1

    try:
        lifecycle.ensure_daemon(public=public, bind_addr=bind_addr,
                                discipline=discipline)
        reply = lifecycle.send_register(os.getcwd())
    except (RuntimeError, OSError) as e:
        logger.error(f'dashboard daemon error: {e}')
        return 1

    if not reply.get('ok'):
        logger.error(f'register failed: {reply.get("error", "unknown")}')
        return 1

    url = reply['url']
    logger.info(f'Dashboard URL: {url}')

    if no_browser:
        return 0

    if lifecycle.is_ssh_session():
        import socket
        port = lifecycle.status()['port']
        host = socket.gethostname()
        logger.info('SSH session detected — not opening browser.')
        logger.info(f'  Tunnel:    ssh -L {port}:localhost:{port} $USER@{host}')
        logger.info(f'  Then open: {url}')
        return 0

    if lifecycle.open_browser(url):
        return 0
    logger.info(f'Browser launch failed; open manually: {url}')
    return 0


def cmd_db_manage(args):
    """Manage RACE database sessions."""
    import sqlite3
    import hashlib
    import re as _re

    # Session limits: flow(race,db_max_sessions) / flow(race,db_warn_ratio)
    # in global/config/flow/<ver>/flow_registry.tcl.
    _lim_keys = ['flow(race,db_max_sessions)', 'flow(race,db_warn_ratio)']
    try:
        _lim = _tcl_values([registry.flow_registry_path()], _lim_keys)
        for _k in _lim_keys:
            if not _lim.get(_k, '').strip():
                raise registry.RegistryError(f'{_k} is not set in flow_registry.tcl')
        max_sessions = int(_lim[_lim_keys[0]])
        warn_threshold = int(max_sessions * float(_lim[_lim_keys[1]]))
    except (registry.RegistryError, RuntimeError, ValueError) as e:
        logger.error(f"db-manage: {e}")
        return 1

    # Find all RACE DBs — search race area first, then local workarea fallback
    user = os.environ.get('USER', 'unknown')
    dbs = []

    def _scan_db(db_file, run_dir_name=''):
        """Read DB metadata and append to dbs list."""
        try:
            conn = sqlite3.connect(str(db_file))
            info = {}
            try:
                for k, v in conn.execute('SELECT key, value FROM run_info'):
                    info[k] = v
            except Exception:
                pass
            job_count = 0
            try:
                job_count = conn.execute('SELECT COUNT(DISTINCT job_name) FROM jobs').fetchone()[0]
            except Exception:
                pass
            conn.close()

            size = db_file.stat().st_size
            mtime = datetime.fromtimestamp(db_file.stat().st_mtime)

            # Determine status: ACTIVE (run_dir exists) or ORPHANED (run_dir deleted)
            actual_run_dir = info.get('run_dir', '')
            if actual_run_dir and os.path.isdir(actual_run_dir):
                run_status = 'ACTIVE'
            else:
                run_status = 'ORPHANED'

            dbs.append({
                'path': str(db_file),
                'run_dir': run_dir_name or info.get('run_dir', str(db_file.stem)),
                'run_dir_abs': actual_run_dir,
                'flow_type': info.get('flow_type', '?'),
                'result': info.get('result', '?'),
                'owner': info.get('owner', info.get('user', '?')),
                'owner_uid': info.get('owner_uid', ''),
                'initialized': info.get('initialized', '?'),
                'size': size,
                'mtime': mtime,
                'jobs': job_count,
                'status': run_status,
            })
        except Exception:
            pass

    # Search race area (primary location): project(race,db_path)
    race_area = ''
    project_name = (os.environ.get('CBFLOW_PROJECT_NAME', '')
                    or load_run_env().get('CBFLOW_PROJECT_NAME', ''))
    if project_name:
        try:
            race_area = registry.project_value(project_name, 'race,db_path') or ''
        except registry.RegistryError as e:
            logger.error(f"db-manage: {e}")
            return 1

    if race_area and os.path.isdir(race_area):
        # Scan all .db files in race area for this user
        for db_file in Path(race_area).rglob('*.db'):
            _scan_db(db_file, db_file.stem)
    else:
        # Fallback: search local workarea
        workarea = os.path.dirname(os.getcwd()) if is_run_directory() else os.getcwd()
        try:
            from core.db import find_race_db_from_run_dir
        except ImportError:
            _utils_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            if _utils_dir not in sys.path:
                sys.path.insert(0, _utils_dir)
            from core.db import find_race_db_from_run_dir
        for run_dir in Path(workarea).iterdir():
            if not run_dir.is_dir():
                continue
            db_path = find_race_db_from_run_dir(str(run_dir))
            if db_path:
                _scan_db(Path(db_path), str(run_dir.name))

    # Sort by modification time (newest first)
    dbs.sort(key=lambda d: d['mtime'], reverse=True)

    # Filter: only show current user's databases
    current_uid = str(os.getuid())
    dbs = [d for d in dbs if not d.get('owner_uid') or d['owner_uid'] == current_uid]

    # --check: just check count against limit
    if getattr(args, 'check', False) or (not getattr(args, 'db_list', False) and not getattr(args, 'delete', None) and not getattr(args, 'cleanup', False)):
        count = len(dbs)
        logger.info(f"")
        logger.info(f"  RACE Database Session Check")
        logger.info(f"  {'='*50}")
        logger.info(f"  Sessions found:  {count}")
        logger.info(f"  Warn threshold:  {warn_threshold}")
        logger.info(f"  Max sessions:    {max_sessions}")
        logger.info(f"")
        if count >= max_sessions:
            logger.warning(f"  WARNING: Session limit reached ({count}/{max_sessions})!")
            logger.warning(f"  Please delete old databases using: cbflow run db-manage --cleanup")
        elif count >= warn_threshold:
            logger.warning(f"  WARNING: Approaching session limit ({count}/{max_sessions})")
            logger.warning(f"  Consider cleaning up old databases: cbflow run db-manage --cleanup")
        else:
            logger.info(f"  Status: OK ({count}/{max_sessions})")
        logger.info(f"")
        return 0

    # --list: show all databases (only current user's)
    if getattr(args, 'db_list', False):
        orphaned = sum(1 for d in dbs if d['status'] == 'ORPHANED')
        logger.info(f"")
        logger.info(f"  RACE Database Sessions ({len(dbs)} found, {orphaned} orphaned, limit={max_sessions})")
        logger.info(f"  {'='*95}")
        logger.info(f"  {'#':>3s}  {'Status':8s} {'Run Directory':30s} {'Flow':10s} {'Result':8s} {'Jobs':5s} {'Size':8s} {'Modified':16s}")
        logger.info(f"  {'─'*95}")
        for i, d in enumerate(dbs):
            size_str = f"{d['size'] / 1024:.0f}KB" if d['size'] < 1048576 else f"{d['size'] / 1048576:.1f}MB"
            mtime_str = d['mtime'].strftime('%Y-%m-%d %H:%M')
            logger.info(f"  {i+1:3d}  {d['status']:8s} {d['run_dir'][:30]:30s} {d['flow_type']:10s} {d['result']:8s} {d['jobs']:5d} {size_str:8s} {mtime_str}")
        logger.info(f"")
        if orphaned:
            logger.info(f"  TIP: {orphaned} ORPHANED database(s) can be safely deleted (run directory no longer exists)")
            logger.info(f"       Use: cbflow run db-manage --cleanup  then type 'orphaned'")
        if len(dbs) >= warn_threshold:
            logger.warning(f"  WARNING: {len(dbs)}/{max_sessions} sessions used. Consider: cbflow run db-manage --cleanup")
        return 0

    # --delete: delete specific run's DB (ownership check)
    if getattr(args, 'delete', None):
        target = args.delete
        found = [d for d in dbs if target in d['run_dir']]
        if not found:
            logger.error(f"  No database found matching '{target}'")
            return 1
        current_uid = str(os.getuid())
        for d in found:
            if d.get('owner_uid') and d['owner_uid'] != current_uid:
                logger.error(f"  Cannot delete: owned by '{d['owner']}' — only the owner can delete")
                return 1
            os.remove(d['path'])
            logger.info(f"  Deleted: {d['path']}")
        logger.info(f"  Removed {len(found)} database(s)")
        return 0

    # --cleanup: interactive cleanup (only shows your own DBs)
    if getattr(args, 'cleanup', False):
        if not dbs:
            logger.info("  No RACE databases found.")
            return 0

        orphaned = sum(1 for d in dbs if d['status'] == 'ORPHANED')
        logger.info(f"")
        logger.info(f"  RACE Database Cleanup ({len(dbs)} sessions, {orphaned} orphaned, limit={max_sessions})")
        logger.info(f"  {'='*95}")
        logger.info(f"  {'#':>3s}  {'Status':8s} {'Run Directory':30s} {'Flow':10s} {'Result':8s} {'Jobs':5s} {'Size':8s} {'Modified':16s}")
        logger.info(f"  {'─'*95}")
        for i, d in enumerate(dbs):
            size_str = f"{d['size'] / 1024:.0f}KB" if d['size'] < 1048576 else f"{d['size'] / 1048576:.1f}MB"
            mtime_str = d['mtime'].strftime('%Y-%m-%d %H:%M')
            logger.info(f"  [{i+1:2d}] {d['status']:8s} {d['run_dir'][:30]:30s} {d['flow_type']:10s} {d['result']:8s} {d['jobs']:5d} {size_str:8s} {mtime_str}")
        logger.info(f"")
        logger.info(f"  ORPHANED = run directory deleted (safe to remove)")
        logger.info(f"  Enter numbers to delete (comma-separated), 'orphaned' to delete all orphaned, 'old' to delete oldest, or 'q' to quit:")

        try:
            choice = input("  > ").strip()
        except (EOFError, KeyboardInterrupt):
            logger.info("  Cancelled.")
            return 0

        if choice.lower() == 'q':
            return 0

        to_delete = []
        if choice.lower() == 'orphaned':
            # Delete all orphaned DBs (list is already filtered to current user)
            to_delete = [d for d in dbs if d['status'] == 'ORPHANED']
        elif choice.lower() == 'old':
            # Delete oldest half (keep newest)
            keep = max(len(dbs) // 2, 1)
            to_delete = dbs[keep:]
        else:
            for part in choice.split(','):
                part = part.strip()
                if part.isdigit():
                    idx = int(part) - 1
                    if 0 <= idx < len(dbs):
                        to_delete.append(dbs[idx])

        if not to_delete:
            logger.info("  Nothing to delete.")
            return 0

        deleted = 0
        for d in to_delete:
            try:
                os.remove(d['path'])
                logger.info(f"  Deleted: {d['run_dir'][:40]} ({os.path.basename(d['path'])})")
                # Also remove pointer file if run_dir still exists
                run_dir_path = d.get('run_dir_abs', '')
                if run_dir_path and os.path.isdir(run_dir_path):
                    pointer = os.path.join(run_dir_path, '.race_db_pointer')
                    if os.path.exists(pointer):
                        os.remove(pointer)
                deleted += 1
            except OSError as e:
                logger.error(f"  Failed to delete {d['path']}: {e}")

        logger.info(f"  Removed {deleted} database(s). Remaining: {len(dbs) - deleted}")
        return 0

    return 0


def _cmd_email_dispatch(args):
    """Dispatch to email command."""
    try:
        from email_cmd import cmd_email
        return cmd_email(args)
    except ImportError:
        print("ERROR: email_cmd module not found")
        return 1


def _cmd_autoppt_dispatch(args):
    """Dispatch to autoppt command."""
    # Enabled by: user_config override, project(autoppt,enabled) in the
    # project config, or CBFLOW_AUTOPPT_ENABLED=true.
    _enabled = False
    _uc = os.path.join(os.getcwd(), 'setup', 'user_config.tcl')
    if os.path.exists(_uc):
        with open(_uc, 'r') as _f:
            for _line in _f:
                if 'autoppt,enabled' in _line and '"true"' in _line:
                    _enabled = True
                    break
    if not _enabled:
        _proj = (os.environ.get('CBFLOW_PROJECT_NAME', '')
                 or load_run_env().get('CBFLOW_PROJECT_NAME', ''))
        if _proj:
            try:
                _enabled = (registry.project_value(_proj, 'autoppt,enabled') or '').lower() == 'true'
            except registry.RegistryError as e:
                print(f"ERROR: {e}")
                return 1
    if not _enabled:
        _enabled = os.environ.get('CBFLOW_AUTOPPT_ENABLED', 'false').lower() == 'true'

    if not _enabled:
        print("AutoPPT is disabled. Enable in project_config:")
        print('  set project(autoppt,enabled) "true"')
        return 1

    try:
        from autoppt_cmd import cmd_autoppt
        return cmd_autoppt(args)
    except Exception as e:
        print("ERROR: autoppt unavailable — {}".format(e))
        print("  HTML mode works without python-pptx: cbflow run autoppt --format html")
        return 1


def _cmd_checklist_dispatch(args):
    """Run checklist against current run directory. Status/generate/sign-off only."""
    try:
        import checklist_cmd
    except ImportError:
        print("ERROR: checklist_cmd module not found")
        return 1

    run_dir = os.getcwd()

    # List milestones
    if getattr(args, 'list_milestones', False):
        return checklist_cmd.cmd_list(args)

    # Sign-off
    if getattr(args, 'sign_off', False):
        if not args.milestone:
            print("ERROR: --milestone required with --sign-off")
            return 1
        if not args.approver:
            print("ERROR: --approver required with --sign-off")
            return 1
        args.run_dir = run_dir
        return checklist_cmd.cmd_signoff(args)

    # Default: run status/generate
    if not args.milestone:
        print("ERROR: --milestone required. Use --list to see available milestones.")
        return 1

    args.run_dir = run_dir

    # If run has completed stages in DB, run status check; otherwise generate template
    from pathlib import Path as _Path
    has_db = any(_Path(run_dir).glob('.race_*.db'))
    if has_db:
        return checklist_cmd.cmd_status(args)
    else:
        return checklist_cmd.cmd_generate(args)


def main() -> int:
    """Main entry point."""
    from logging_config import print_logo
    print_logo()

    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    # Command dispatch
    commands = {
        'all': cmd_all,
        'stage': cmd_stage,
        'status': cmd_status,
        'report': cmd_report,
        'retrace': cmd_retrace,
        'clean': cmd_clean,
        'list-nodes': cmd_list_nodes,
        'show-graph': cmd_show_graph,
        'add-node': cmd_add_node,
        'set-dep': cmd_set_dep,
        'delete-node': cmd_delete_node,
        'create-branch': cmd_create_branch,
        'list-branches': cmd_list_branches,
        'delete-branch': cmd_delete_branch,
        'update': cmd_update,
        'gen-makefile': cmd_gen_makefile,
        'release-info': cmd_release_info,
        'release': cmd_release,
        'release-check': cmd_release_check,
        'release-lock': cmd_release_lock,
        'targets': cmd_targets,
        'logs': cmd_logs,
        'validate': cmd_validate_run,
        'lsf-status': cmd_lsf_status_run,
        'bypass': cmd_bypass,
        'force': cmd_force,
        'forcevalidate': cmd_forcevalidate,
        'interactive': cmd_interactive,
        'email': _cmd_email_dispatch,
        'autoppt': _cmd_autoppt_dispatch,
        'checklist': _cmd_checklist_dispatch,
        'gui': cmd_gui,
        'db-manage': cmd_db_manage,
        'help': cmd_help,
        'debug': cmd_debug,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
