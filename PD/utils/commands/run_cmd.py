#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Run Command Handler
# Description: Handles flow execution within a run directory
# Usage: cbflow run <subcommand> [options]
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import os
import sys
import subprocess
import logging
from datetime import datetime
from pathlib import Path

# Configure unified logging
from logging_config import configure_logging, get_logger

import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir, get_flow_config_version, CBFLOW_VERSION as VERSION

logger = configure_logging('cbflow.run')




def is_run_directory() -> bool:
    """Check if current directory is a valid run directory."""
    # Check for run environment file or Makefile
    return (os.path.exists('.run.cbflow.env') or
            os.path.exists('.run.cbflow.tcl') or
            any(Path('.').glob('.race_*.db')) or
            '_run_' in os.path.basename(os.getcwd()))


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
    if '_run_' in dirname:
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
    """Ordered stages for a flow type. `run_dir=None` reads the project
    baseline; pass a run dir to honor user_config overrides.
    """
    from tcl_config_parser import is_merged_flow, get_merged_flow_stage_names
    from tcl_config_parser import get_flow_stages as _get_stages

    if is_merged_flow(flow_type):
        return get_merged_flow_stage_names(flow_type)
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
        return {s for s, v in all_status.items()
                if v.get('status') in ('DONE', 'BYPASSED', 'FORCE_VALIDATED')}
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

        # Find the matching closing brace
        start_pos = match.end()
        brace_count = 1
        end_pos = start_pos
        while end_pos < len(content) and brace_count > 0:
            if content[end_pos] == '{':
                brace_count += 1
            elif content[end_pos] == '}':
                brace_count -= 1
            end_pos += 1

        array_content = content[start_pos:end_pos-1]

        # Parse key-value pairs from TCL array
        # Format: key value (may have braces for values with spaces)
        # TCL array elements are separated by whitespace, with key value pairs

        # Tokenize the array content properly
        tokens = []
        i = 0
        while i < len(array_content):
            # Skip whitespace
            while i < len(array_content) and array_content[i] in ' \t\n\r':
                i += 1
            if i >= len(array_content):
                break

            # Check for braced value
            if array_content[i] == '{':
                # Find matching close brace
                brace_count = 1
                start = i + 1
                i += 1
                while i < len(array_content) and brace_count > 0:
                    if array_content[i] == '{':
                        brace_count += 1
                    elif array_content[i] == '}':
                        brace_count -= 1
                    i += 1
                tokens.append(array_content[start:i-1])
            else:
                # Regular word - stop at whitespace or brace
                start = i
                while i < len(array_content) and array_content[i] not in ' \t\n\r{}':
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

def cmd_all(args: argparse.Namespace) -> int:
    """Run complete flow (all stages)."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    flow_type = get_flow_type()
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
            logger.debug(f"Metrics collection skipped: {e}")

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


def cmd_bypass(args: argparse.Namespace) -> int:
    """Bypass (skip) stages — mark as DONE without executing."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    stages = [s.strip() for s in args.stages.split(',')]
    flow_type = get_flow_type()
    valid = get_all_stages(flow_type)
    for s in stages:
        if s not in valid:
            logger.error(f"Invalid stage: {s}. Valid: {', '.join(valid)}")
            return 1

    from race_engine import RaceEngine
    run_env = load_run_env()
    engine = RaceEngine(os.getcwd(), flow_type, run_env)
    if engine.initialize():
        logger.info(f"Bypassing stages: {', '.join(stages)}")
        return engine.bypass(stages)
    return 1


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

    for s in stages:
        if s not in all_stages:
            logger.error(f"Invalid stage: {s}. Valid: {', '.join(all_stages)}")
            return 1

    from race_engine import RaceEngine
    run_env = load_run_env()
    engine = RaceEngine(os.getcwd(), flow_type, run_env)
    if engine.initialize():
        logger.info(f"Force-validating: {', '.join(stages)}")
        return engine.forcevalidate(stages)
    return 1


def cmd_force(args: argparse.Namespace) -> int:
    """Force re-run specific stages only (no downstream invalidation)."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1

    stages = [s.strip() for s in args.stages.split(',')]
    flow_type = get_flow_type()
    valid = get_all_stages(flow_type)
    for s in stages:
        if s not in valid:
            logger.error(f"Invalid stage: {s}. Valid: {', '.join(valid)}")
            return 1

    from race_engine import RaceEngine
    run_env = load_run_env()
    engine = RaceEngine(os.getcwd(), flow_type, run_env)
    if engine.initialize():
        logger.info(f"Force re-running stages: {', '.join(stages)}")
        return engine.force(stages)
    return 1


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
    # Auto-resolve vendor from tool-specific config: <FLOW>_<tool>_config.tcl
    if not vendor and tool and core_dir:
        flow_type = env_vars.get('CBFLOW_FLOW_TYPE', '') or os.environ.get('CBFLOW_FLOW_TYPE', '')
        cfg_ver = env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
        tool_cfg = os.path.join(core_dir, 'config', 'flow', cfg_ver,
                                'node_configs', '{}_{}_config.tcl'.format(flow_type, tool))
        if os.path.isfile(tool_cfg):
            with open(tool_cfg, 'r') as _tcf:
                for _line in _tcf:
                    _m = _re.search(r'tool,vendor["\s]+["\s]*([^"}\s]+)', _line)
                    if _m:
                        vendor = _m.group(1)
                        break
    core_dir = os.environ.get('FLOW_DIR', '') or env_vars.get('FLOW_DIR', '')

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
        # Check multiple paths where setup files may exist (node name first, then base name)
        setup_paths = [
            os.path.join('work', flow_type, stage, 'run', 'setup.tcl'),
            os.path.join('work', flow_type, cmd_base, 'run', 'setup.tcl'),
            os.path.join('work', flow_type, stage, 'setup', 'setup.tcl'),
            os.path.join('work', flow_type, cmd_base, 'setup', 'setup.tcl'),
        ]
        config_paths = [
            os.path.join('work', flow_type, stage, 'run', 'config.tcl'),
            os.path.join('work', flow_type, cmd_base, 'run', 'config.tcl'),
            os.path.join('work', flow_type, stage, 'setup', 'config.tcl'),
            os.path.join('work', flow_type, cmd_base, 'setup', 'config.tcl'),
        ]

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
        work_dir = os.path.join('work', flow_type, stage)
        if not os.path.exists(work_dir):
            work_dir = os.path.join('work', flow_type, cmd_base)
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
                                if 'ERROR' in line or 'FATAL' in line:
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
        finish_info_paths = [
            os.path.join('work', flow_type, stage, 'run', 'finish.timestamp'),
            os.path.join('work', flow_type, stage, 'finish', 'finish_info.tcl'),
            os.path.join('work', flow_type, cmd_base, 'run', 'finish.timestamp'),
            os.path.join('work', flow_type, cmd_base, 'finish', 'finish_info.tcl'),
        ]
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

    # Base flow - show as a chain
    logger.info(f"  Base Flow:")
    logger.info(f"  {'─'*55}")
    for i, stage in enumerate(stages):
        stage_key = stage if stage in completed else f"{stage}1"
        done = stage in completed or f"{stage}1" in completed
        icon = "[DONE]" if done else "[    ]"
        arrow = "  -> " if i < len(stages) - 1 else ""
        logger.info(f"  {icon} {i+1:>2}. {stage:<25}{arrow}")

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
    done_count = sum(1 for s in stages if s in completed or f"{s}1" in completed)
    done_count += sum(1 for n in custom_nodes if n in completed)
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
        # Single flow: build from node config
        import re as _re
        from tcl_config_parser import (
            _load_node_config, _parse_tcl_list, get_parallel_stages
        )
        _rd = os.getcwd() if is_run_directory() else None
        stages = get_flow_stages(flow_type, run_dir=_rd)
        node_config = _load_node_config(flow_type, run_dir=_rd)
        parallel_set = set(get_parallel_stages(flow_type, run_dir=_rd))
        stages_data = []
        for i, stage in enumerate(stages):
            # Look up dependency
            dep_key = f'dependencies,{stage}'
            raw = node_config.get(dep_key, '')
            if not raw:
                base = _re.sub(r'\d+$', '', stage)
                if base != stage:
                    raw = node_config.get(f'dependencies,{base}', '')
            if raw:
                dep_list = _parse_tcl_list(raw)
                dep = dep_list[0] if dep_list else ''
                if dep and dep not in stages:
                    for s in stages:
                        if _re.sub(r'\d+$', '', s) == dep:
                            dep = s
                            break
            else:
                dep = stages[i - 1] if i > 0 else ''
            stages_data.append({
                'name': stage,
                'dependency': dep,
                'is_parallel': stage in parallel_set,
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
        logger.error(f"  Example:")
        last = valid_stages[-1] if valid_stages else 'signoff1'
        logger.error(f"    cbflow run add-node --type {node_type} --dep {last}")
        logger.error("")
        return 1

    success = mgr.add_node(node_name, node_type, dependency)
    return 0 if success else 1


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

    if not branch_name and not from_node:
        logger.error("  Error: Either --branch or --from is required")
        return 1

    mgr = _get_node_manager()

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

    # Load target release manifest
    releases_dir = os.path.join(flow_dir, 'releases', target_release)
    manifest_file = os.path.join(releases_dir, 'MANIFEST.json')
    if not os.path.exists(manifest_file):
        logger.error(f"  Error: Release '{target_release}' not found")
        return 1

    with open(manifest_file, 'r') as f:
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

    # Must run from a workspace (not a run dir — we need to see all runs)
    workspace = os.getcwd()
    runs = sorted([d for d in os.listdir(workspace) if os.path.isdir(d) and '_run_' in d])
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

    flow_dir = env_vars.get('FLOW_DIR', '')
    project_name = env_vars.get('CBFLOW_PROJECT_NAME', env_vars.get('PROJECT_NAME', ''))
    design_name = env_vars.get('CBFLOW_DESIGN_NAME', '')
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')

    # Load release_config for predefined tags
    release_tags = {}
    release_deliverables = {}
    ver = env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    rc_path = os.path.join(flow_dir, 'config', 'flow', ver, 'release_config.tcl')
    milestone_stage_map = {}
    if os.path.exists(rc_path):
        with open(rc_path) as f:
            content = f.read()
        # Parse MILESTONE_STAGE_MAPPING: FP_EXIT "init_design", BTO "signoff" etc.
        for m in _re.finditer(r'(\w+)\s+"(\w+)"', content[content.find('MILESTONE_STAGE_MAPPING'):content.find('}', content.find('MILESTONE_STAGE_MAPPING'))]):
            milestone_stage_map[m.group(1)] = m.group(2)
            release_tags[m.group(1)] = {
                'description': f'{m.group(1)} milestone (after {m.group(2)})',
                'required_stage': m.group(2),
            }

    # Load project config for active_tag and expiry
    active_tag = ''
    expiry_date = ''
    release_path = ''
    proj_ver = env_vars.get('PROJECT_VERSION', 'v1.0.0')
    proj_config = os.path.join(flow_dir, 'config', 'project', project_name, proj_ver, f'{project_name}_config.tcl')
    if os.path.exists(proj_config):
        with open(proj_config) as f:
            for line in f:
                m = _re.match(r'set\s+project\(release,active_tag\)\s+"([^"]*)"', line.strip())
                if m: active_tag = m.group(1)
                m = _re.match(r'set\s+project\(release,expiry_date\)\s+"([^"]*)"', line.strip())
                if m: expiry_date = m.group(1)
                m = _re.match(r'set\s+project\(release,path\)\s+"([^"]*)"', line.strip())
                if m: release_path = m.group(1)

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

    # Validate expiry
    if expiry_date:
        try:
            exp = datetime.strptime(expiry_date, '%Y-%m-%d')
            if datetime.now() > exp:
                logger.error(f"Release tag '{tag}' expired on {expiry_date}")
                return 1
        except ValueError:
            pass

    release_tag_name = f"{phase}_{tag}"

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
    required_stage = tag_info.get('required_stage', '')
    logger.info(f"  Required stage: {required_stage}")
    logger.info(f"  ─────────────────────────────────────────────────────────")
    logger.info("")

    # Gate check: find all completed runs in workspace
    found_runs = {}
    for run in runs:
        env_file = os.path.join(workspace, run, '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if 'CBFLOW_FLOW_TYPE' in line:
                        m = _re.search(r'"([^"]+)"', line)
                        if m:
                            found_runs[m.group(1)] = run
    logger.info(f"  Found runs: {len(found_runs)}")
    for flow, run_name in sorted(found_runs.items()):
        logger.info(f"    {flow:<15} → {run_name}")
    logger.info("")

    if not found_runs:
        logger.error("  No completed runs found in workspace")
        return 1

    if dry_run:
        logger.info(f"  DRY RUN: {len(found_runs)} flows found. Release would proceed.")
        return 0

    # Create release directory
    release_dir = os.path.join(release_path, project_name, design_name, release_tag_name)
    os.makedirs(release_dir, exist_ok=True)
    logger.info(f"  Release directory: {release_dir}")
    logger.info("")

    # Copy deliverables from each flow
    total_files = 0
    for flow, run_dir_name in found_runs.items():
        run_path = os.path.join(workspace, run_dir_name)
        flow_release_dir = os.path.join(release_dir, flow)
        flow_files = 0

        # Scan for output manifest first
        manifests = []
        for root, dirs, files in os.walk(os.path.join(run_path, 'work')):
            for fname in files:
                if fname == 'output_manifest.tcl':
                    manifests.append(os.path.join(root, fname))

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
                        src = m.group(2)
                        key = m.group(1)
                        # Determine subdirectory from key
                        if 'netlist' in key:
                            subdir = 'netlist'
                        elif key in ('gds', 'def', 'lef', 'sdc', 'upf', 'spef'):
                            subdir = key
                        elif 'report' in key:
                            subdir = 'reports'
                        else:
                            subdir = 'data'
                        dest_dir = os.path.join(flow_release_dir, subdir)
                        os.makedirs(dest_dir, exist_ok=True)
                        if os.path.exists(src):
                            shutil.copy2(src, dest_dir)
                            flow_files += 1
        else:
            # Fallback: scan all outputs/ and reports/ directories (top-level + per-node)
            scan_dirs = [os.path.join(run_path, 'outputs'), os.path.join(run_path, 'results')]
            # Also scan per-node outputs/reports under work/
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
                if os.path.isdir(scan_dir):
                    for root, dirs, files in os.walk(scan_dir):
                        for fname in files:
                            src = os.path.join(root, fname)
                            subdir = 'data'
                            if fname.endswith('.v'):
                                subdir = 'netlist'
                            elif fname.endswith(('.gds', '.oasis')):
                                subdir = 'gds'
                            elif fname.endswith('.def'):
                                subdir = 'def'
                            elif fname.endswith('.spef'):
                                subdir = 'spef'
                            elif fname.endswith('.sdc'):
                                subdir = 'sdc'
                            elif fname.endswith('.upf'):
                                subdir = 'upf'
                            elif fname.endswith('.rpt'):
                                subdir = 'reports'
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
    with open(os.path.join(release_dir, 'MANIFEST.json'), 'w') as f:
        json.dump(manifest, f, indent=2)

    # Generate RELEASE_COMPLETE
    with open(os.path.join(release_dir, 'RELEASE_COMPLETE'), 'w') as f:
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
    return 0


def cmd_release_lock(args: argparse.Namespace) -> int:
    """Set production permissions (lock) or development permissions (unlock)."""
    import stat

    unlock = getattr(args, 'unlock', False)
    core_dir = os.environ.get('CBFLOW_CORE_DIR', '')
    if not core_dir:
        # Try to find from script location
        script_dir = os.path.dirname(os.path.abspath(__file__))
        core_dir = os.path.dirname(os.path.dirname(script_dir))

    if not os.path.isdir(core_dir):
        logger.error(f"Cannot find CBflow core directory: {core_dir}")
        return 1

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

    for root, dirs, files in os.walk(core_dir):
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
        logger.info(f"  To unlock for development: cbflow release lock --unlock")
    logger.info("")
    return 0


def cmd_release_check(args: argparse.Namespace) -> int:
    """Check chip-level release readiness: all blocks × all flows for a milestone."""
    import re as _re
    import json

    tag = args.tag
    project_name = args.project
    phase = getattr(args, 'phase', 'P0') or 'P0'
    block_filter = getattr(args, 'block', None)

    # Find flow_dir from environment or workspace
    flow_dir = os.environ.get('FLOW_DIR', '')
    if not flow_dir:
        # Try to find from any run in current dir
        for d in os.listdir('.'):
            env_f = os.path.join(d, '.run.cbflow.env')
            if os.path.isfile(env_f):
                with open(env_f) as f:
                    for line in f:
                        if 'FLOW_DIR' in line:
                            m = _re.search(r'"([^"]*)"', line)
                            if m: flow_dir = m.group(1)
                break
    if not flow_dir:
        logger.error("Cannot determine FLOW_DIR. Set env or run from workspace.")
        return 1

    ver = get_flow_config_version()

    # Load release_tags from release_config
    release_tags = {}
    rc_path = os.path.join(flow_dir, 'config', 'flow', ver, 'release_config.tcl')
    if os.path.exists(rc_path):
        with open(rc_path) as f:
            content = f.read()
        for m in _re.finditer(r'(\w+)\s+\{description\s+"([^"]+)"\s+phase_min\s+(\w+)\s+required_flows\s+\{([^}]+)\}\}', content):
            release_tags[m.group(1)] = {
                'description': m.group(2),
                'phase_min': m.group(3),
                'required_flows': m.group(4).split(),
            }

    if tag not in release_tags:
        logger.error(f"Unknown tag '{tag}'. Available: {', '.join(sorted(release_tags.keys()))}")
        return 1

    tag_info = release_tags[tag]
    release_tag_name = f"{phase}_{tag}"

    # Load project config for release path and block_list
    release_path = ''
    block_list = []
    proj_ver = os.environ.get('PROJECT_VERSION', 'v1.0.0')
    proj_config = os.path.join(flow_dir, 'config', 'project', project_name, proj_ver, f'{project_name}_config.tcl')
    if os.path.exists(proj_config):
        with open(proj_config) as f:
            for line in f:
                m = _re.match(r'set\s+project\(release,path\)\s+"([^"]*)"', line.strip())
                if m: release_path = m.group(1)
                m = _re.match(r'set\s+project\(block_list\)\s+"([^"]*)"', line.strip())
                if m: block_list = m.group(1).split()

    if not release_path:
        logger.error("project(release,path) not set in project config")
        return 1

    if not block_list:
        # Fallback: scan release dir for existing blocks
        tag_dir = os.path.join(release_path, project_name)
        if os.path.isdir(tag_dir):
            block_list = [d for d in os.listdir(tag_dir) if os.path.isdir(os.path.join(tag_dir, d))]
        if not block_list:
            logger.error("No blocks found. Set project(block_list) in project config.")
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

        for flow in required_flows:
            release_dir = os.path.join(release_path, project_name, block, release_tag_name, flow)
            rc_file = os.path.join(release_path, project_name, block, release_tag_name, 'RELEASE_COMPLETE')

            if os.path.isdir(release_dir) and len(os.listdir(release_dir)) > 0:
                # Check file count
                fcount = sum(1 for _, _, files in os.walk(release_dir) for f in files)
                row += f'{"PASS("+str(fcount)+")":<14}'
            else:
                row += f'{"MISS":<14}'
                block_ok = False

        # Check overall RELEASE_COMPLETE
        rc_path_full = os.path.join(release_path, project_name, block, release_tag_name, 'RELEASE_COMPLETE')
        if block_ok and os.path.exists(rc_path_full):
            row += '[COMPLETE]'
            complete_blocks += 1
        elif block_ok:
            row += '[NO STAMP]'
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


def _load_tool_shell_map(env_vars: dict) -> dict:
    """Load tool→shell mapping from tool_launch_config.tcl."""
    import re
    flow_dir = env_vars.get('FLOW_DIR', os.environ.get('FLOW_DIR', ''))
    version = env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    config_path = os.path.join(flow_dir, 'config', 'flow', version, 'tool_launch_config.tcl')
    shell_map = {}
    if os.path.exists(config_path):
        with open(config_path) as f:
            for line in f:
                m = re.match(r'set\s+tool_shell\((\w+)\)\s+"([^"]+)"', line.strip())
                if m:
                    shell_map[m.group(1)] = m.group(2)
    return shell_map


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

    # Priority 2: project default_tools
    if not tool_name:
        proj_name = env_vars.get('CBFLOW_PROJECT_NAME', '')
        if proj_name:
            flow_dir_val = env_vars.get('FLOW_DIR', '')
            cfg_ver = env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
            proj_cfg = os.path.join(flow_dir_val, 'config', 'project', proj_name, cfg_ver,
                                    '{}_config.tcl'.format(proj_name))
            if os.path.exists(proj_cfg):
                import re as _re3
                with open(proj_cfg) as _pc:
                    content = _pc.read()
                m = _re3.search(r'default_tools\)\s*\{([^}]+)\}', content)
                if m:
                    pairs = m.group(1).split()
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
        flow_dir_val = env_vars.get('FLOW_DIR', '')
        cfg_ver = env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
        import re as _re4
        tool_cfg = os.path.join(flow_dir_val, 'config', 'flow', cfg_ver,
                                'node_configs', '{}_{}_config.tcl'.format(flow_type, tool_name))
        if os.path.exists(tool_cfg):
            with open(tool_cfg) as _tcf:
                for _line in _tcf:
                    m = _re4.search(r'tool,vendor["\s]+["\s]*([^"}\s]+)', _line)
                    if m:
                        vendor = m.group(1)
                        break

    if not vendor or not tool_name:
        logger.error("Tool vendor/name not configured. Check user_config or project default_tools.")
        return 1

    # Resolve tool shell from tool_launch_config.tcl (single source of truth)
    tool_shell_map = _load_tool_shell_map(env_vars)
    if not tool_shell_map:
        logger.warning("Could not load tool_launch_config.tcl; using tool_name as shell command")
    tool_shell = tool_shell_map.get(tool_name, tool_name)

    # Module load — read from flow_config (single source of truth)
    import re as _re
    module_cmd = ''
    flow_dir = env_vars.get('FLOW_DIR', os.environ.get('FLOW_DIR', ''))
    fc_path = os.path.join(flow_dir, 'config', 'flow',
                           env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0'),
                           'flow_config.tcl')
    if os.path.exists(fc_path):
        with open(fc_path) as f:
            for line in f:
                m = _re.search(rf'flow\(tool_module,{_re.escape(tool_name)}\)\s+"([^"]+)"', line)
                if m:
                    module_cmd = f'module load {m.group(1)}'
                    break

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
        work_dir = os.path.join(run_dir, 'work', flow_type, load_node)

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

            # Source node config + setup (tech/project/flow arrays + flow_proc hooks)
            config_tcl = os.path.join(work_dir, 'run', 'config.tcl')
            setup_tcl = os.path.join(work_dir, 'run', 'setup.tcl')
            if os.path.exists(config_tcl):
                tf.write(f'source "{config_tcl}"\n')
            if os.path.exists(setup_tcl):
                tf.write(f'source "{setup_tcl}"\n')
            tf.write(f'source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"\n\n')

            if tool_name == 'fc':
                # Fusion Compiler — open NDM library
                nlib_path = os.path.join(work_dir, f'{load_node}.nlib')
                nlib_alt = os.path.join(run_dir, 'work', flow_type, load_node, f'{load_node}.nlib')
                tf.write(f"# Open design library\n")
                tf.write(f'set nlib_path "{nlib_path}"\n')
                tf.write(f'set nlib_alt  "{nlib_alt}"\n')
                tf.write(f'if {{[file exists $nlib_path]}} {{\n')
                tf.write(f'    open_lib $nlib_path\n')
                tf.write(f'    puts "INFO: Loaded design library: $nlib_path"\n')
                tf.write(f'}} elseif {{[file exists $nlib_alt]}} {{\n')
                tf.write(f'    open_lib $nlib_alt\n')
                tf.write(f'    puts "INFO: Loaded design library: $nlib_alt"\n')
                tf.write(f'}} else {{\n')
                tf.write(f'    puts "WARNING: No .nlib found for {load_node}"\n')
                tf.write(f'    puts "  Searched: $nlib_path"\n')
                tf.write(f'    puts "  Searched: $nlib_alt"\n')
                tf.write(f'    puts "  Starting empty session"\n')
                tf.write(f'}}\n\n')
                tf.write(f'puts ""\n')
                tf.write(f'puts "═══════════════════════════════════════════════════"\n')
                tf.write(f'puts "  CBflow Interactive — {load_node} loaded"\n')
                tf.write(f'puts "  Run directory: {run_dir}"\n')
                tf.write(f'puts "  Session: INTERACTIVE/{session_name}"\n')
                tf.write(f'puts "═══════════════════════════════════════════════════"\n')

            elif tool_name == 'pt':
                # PrimeTime — restore session
                ss_dir = os.path.join(run_dir, 'work', flow_type, load_node, 'run')
                tf.write(f"# Restore PrimeTime session\n")
                tf.write(f'set session_dir "{ss_dir}"\n')
                tf.write(f'set session_files [glob -nocomplain "$session_dir/*.session"]\n')
                tf.write(f'if {{[llength $session_files] > 0}} {{\n')
                tf.write(f'    set ss [lindex $session_files end]\n')
                tf.write(f'    restore_session $ss\n')
                tf.write(f'    puts "INFO: Restored session: $ss"\n')
                tf.write(f'}} else {{\n')
                tf.write(f'    # Try loading timing DB\n')
                tf.write(f'    set db_files [glob -nocomplain "$session_dir/*.db"]\n')
                tf.write(f'    if {{[llength $db_files] > 0}} {{\n')
                tf.write(f'        read_db [lindex $db_files end]\n')
                tf.write(f'        puts "INFO: Loaded timing DB"\n')
                tf.write(f'    }} else {{\n')
                tf.write(f'        puts "WARNING: No saved session found for {load_node}"\n')
                tf.write(f'        puts "  Starting empty session — use read_verilog, read_sdc, etc."\n')
                tf.write(f'    }}\n')
                tf.write(f'}}\n\n')
                tf.write(f'puts ""\n')
                tf.write(f'puts "═══════════════════════════════════════════════════"\n')
                tf.write(f'puts "  CBflow Interactive — {load_node} (PrimeTime)"\n')
                tf.write(f'puts "  Run directory: {run_dir}"\n')
                tf.write(f'puts "═══════════════════════════════════════════════════"\n')

            elif tool_name == 'innovus':
                # Innovus — restore design from outputs/
                enc_dat = os.path.join(work_dir, 'outputs', f'{node_base}.enc.dat')
                design_name = env_vars.get('CBFLOW_DESIGN_NAME', '')
                tf.write(f"# Restore Innovus design\n")
                tf.write(f'set _db "{enc_dat}"\n')
                tf.write(f'if {{[file exists $_db]}} {{\n')
                _nt = ' -noTiming' if notiming else ''
                tf.write(f'    restoreDesign{_nt} $_db {design_name}\n')
                tf.write(f'    puts "INFO: Restored design: $_db ({design_name}){"  [noTiming]" if notiming else ""}"\n')
                tf.write(f'}} else {{\n')
                tf.write(f'    puts "WARNING: No .enc.dat found: $_db"\n')
                tf.write(f'    puts "  Run the flow first or check outputs/ directory"\n')
                tf.write(f'}}\n')
                tf.write(f'\nputs ""\n')
                tf.write(f'puts "═══════════════════════════════════════════════════"\n')
                tf.write(f'puts "  CBflow Interactive — {load_node} ({tool_name})"\n')
                tf.write(f'puts "  Design: {design_name}"\n')
                tf.write(f'puts "  Run directory: {run_dir}"\n')
                tf.write(f'puts "  Session: INTERACTIVE/{session_name}"\n')
                tf.write(f'puts "═══════════════════════════════════════════════════"\n')

            elif tool_name == 'tempus':
                # Tempus — similar to PT
                tf.write(f"# Restore Tempus session\n")
                tf.write(f'set session_dir "{work_dir}"\n')
                tf.write(f'set db_files [glob -nocomplain "$session_dir/*.db"]\n')
                tf.write(f'if {{[llength $db_files] > 0}} {{\n')
                tf.write(f'    read_db [lindex $db_files end]\n')
                tf.write(f'    puts "INFO: Loaded timing DB"\n')
                tf.write(f'}} else {{\n')
                tf.write(f'    puts "WARNING: No saved session found for {load_node}"\n')
                tf.write(f'}}\n')

            else:
                tf.write(f'puts "INFO: Interactive session for {load_node} ({tool_name})"\n')
                tf.write(f'puts "  Work dir: {work_dir}"\n')

        logger.info(f"  Load TCL:  {load_tcl_path}")

    # ── Read LSF and xterm settings from flow_config ─────────────────────
    import re as _re
    use_lsf = False
    xterm_cmd = 'xterm'
    xterm_geom = '200x50'
    lsf_queue = 'normal'
    lsf_memory = '16000'
    lsf_runtime = '6:00'

    # All four files (flow_config, user_config, lsf_config, tool_launch_config)
    # contribute keys to the resolver — no raw .tcl reads here anymore. The
    # cascade order is enforced by the resolver, so user_config's override of
    # flow(use_lsf) takes effect automatically.
    import cbflow_config as _cbflow_cfg
    resolved = _cbflow_cfg.load_resolved_config(flow_type, run_dir, env=env_vars)
    use_lsf = (_cbflow_cfg.optional(resolved, 'flow(use_lsf)') == 'true')
    lsf_queue = _cbflow_cfg.optional(resolved, 'lsf(interactive,queue)') or lsf_queue
    lsf_runtime = _cbflow_cfg.optional(resolved, 'lsf(interactive,runtime_limit)') or lsf_runtime
    _mem = _cbflow_cfg.optional(resolved, 'lsf(interactive,memory)')
    if _mem:
        lsf_memory = (str(int(_mem[:-2]) * 1000)
                      if _mem.upper().endswith('GB') else _mem)
    xterm_cmd = _cbflow_cfg.optional(resolved, 'lsf(xterm,command)') or xterm_cmd
    xterm_geom = _cbflow_cfg.optional(resolved, 'lsf(xterm,geometry)') or xterm_geom

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
        wf.write(f"source {run_dir}/.run.cbflow.env\n\n")

        # Build tool invocation with load TCL script
        if load_tcl_path:
            if tool_name == 'fc':
                wf.write(f'{tool_shell} -gui -f "{load_tcl_path}"\n')
            elif tool_name in ('pt', 'tempus'):
                wf.write(f'{tool_shell} -f "{load_tcl_path}"\n')
            elif tool_name == 'innovus':
                wf.write(f'{tool_shell} -init "{load_tcl_path}"\n')
            elif tool_name == 'genus':
                wf.write(f'{tool_shell} -f "{load_tcl_path}"\n')
            elif tool_name == 'fm':
                wf.write(f'{tool_shell} -gui -f "{load_tcl_path}"\n')
            else:
                wf.write(f'{tool_shell} -f "{load_tcl_path}"\n')
        else:
            # No node to load — just open empty tool
            if tool_name == 'fc':
                wf.write(f"{tool_shell} -gui\n")
            elif tool_name == 'icv':
                wf.write(f"icv -vue\n")
            elif tool_name == 'calibre':
                wf.write(f"calibredrv\n")
            elif tool_name == 'fm':
                wf.write(f"{tool_shell} -gui\n")
            else:
                wf.write(f"{tool_shell}\n")
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
        # Submit via LSF with interactive xterm
        bsub_cmd = [
            'bsub', '-Is', '-q', lsf_queue,
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
        # Local xterm
        logger.info(f"  Launch: xterm (local)")
        logger.info(f"  Opening: {xterm_cmd} -geometry {xterm_geom} -title \"{title}\"")
        logger.info("")
        try:
            subprocess.Popen([
                xterm_cmd, '-geometry', xterm_geom,
                '-title', title, '-e', wrapper_path
            ])
            logger.info(f"  Interactive session launched.")
        except FileNotFoundError:
            logger.error(f"  xterm not found. Run the wrapper manually:")
            logger.error(f"    {wrapper_path}")
            return 1

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
    logger.info("  cbflow run stage --name place           Run a single stage")
    logger.info("  cbflow run stage --name cts --validate  Run stage with validation")
    logger.info("  cbflow run stage --name route --lsf     Submit single stage to LSF")
    logger.info("")

    logger.info(f"STATUS & MONITORING:")
    logger.info("  cbflow run status                 Show stage completion status")
    logger.info("  cbflow run status --details       Show all subnodes per stage")
    logger.info("  cbflow run status --output s.txt  Dump status to file")
    logger.info("  cbflow run report                 Detailed per-node report (setup, config, errors)")
    logger.info("  cbflow run report --node place1   Report for a specific node only")
    logger.info("  cbflow run report --no-dump       Report without dumping setup file contents")
    logger.info("  cbflow run targets                List all available make targets")
    logger.info("  cbflow run lsf-status             Show LSF job queue status")
    logger.info("")

    logger.info(f"VALIDATION:")
    logger.info("  cbflow run validate                    Validate config + inputs + outputs")
    logger.info("  cbflow run validate --type config      Validate configuration only")
    logger.info("  cbflow run validate --type inputs      Validate netlist, SDC, DEF")
    logger.info("  cbflow run validate --stage place      Validate outputs for 'place' stage")
    logger.info("  cbflow run validate --type exit --stage cts  Check CTS exit criteria")
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
    logger.info("  cbflow run retrace --from cts     Invalidate from CTS stage onwards")
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
    logger.info("  cbflow run add-node --node eco1 --type eco --dep signoff")
    logger.info("                                    Add custom node after signoff")
    logger.info("  cbflow run delete-node --node eco1")
    logger.info("                                    Remove custom node")
    logger.info("")

    logger.info(f"BRANCH MANAGEMENT:")
    logger.info("  cbflow run create-branch --branch fix_timing --from place")
    logger.info("                                    Branch from place stage")
    logger.info("  cbflow run list-branches          List all branches")
    logger.info("  cbflow run delete-branch --branch fix_timing")
    logger.info("")

    logger.info(f"RELEASE & UPDATE:")
    logger.info("  cbflow run release-info           Show current release version")
    logger.info("  cbflow run update                 Update to latest workspace release")
    logger.info("  cbflow run update --release v1.0.1  Update to specific version")
    logger.info("  cbflow run gen-makefile           Verify engine DAG structure")
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
    logger.info("  cbflow run interactive                        Open tool in xterm (GUI)")
    logger.info("  cbflow run interactive --load place1          Load place1 design")
    logger.info("  cbflow run interactive --load signoff1        Load signoff checkpoint")
    logger.info("")

    logger.info(f"CLEANUP:")
    logger.info("  cbflow run clean --confirm        Delete work/, logs/, stamps/")
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
  cbflow run stage --name place                  Run single stage
  cbflow run status --details                    Show detailed progress
  cbflow run validate --stage cts                Validate stage outputs
  cbflow run logs --tail 50 --level ERROR        View recent errors
  cbflow run show-graph --detail                 Visualize flow graph
  cbflow run add-node --node eco1 --type export_data --dep signoff
  cbflow run retrace --from cts                  Rerun from CTS onwards
  cbflow run report                              Detailed node report with setup dumps
  cbflow run report --node place1                Report for specific node
  cbflow run lsf-status                          Check LSF job queue
  cbflow run checklist --milestone BTO --phase P3  Run exit milestone checklist
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
  cbflow run stage --name place              Run full placement stage (all subnodes)
  cbflow run stage -n cts                    Short form
  cbflow run stage --name init_design1 --subnode run    Run only the 'run' subnode
  cbflow run stage -n cts1 -s setup          Run only CTS setup subnode
  cbflow run stage --name route --validate   Run with validation
  cbflow run stage --name signoff --lsf      Submit to LSF""")
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
    retrace_parser = subparsers.add_parser('retrace', help='Clear stamps to force rerun',
        formatter_class=_fmt, description="""Remove completion stamps so stages will rerun.

Does NOT automatically rerun - only clears stamps. Use --run to also execute.

Examples:
  cbflow run retrace                 Clear all stamps
  cbflow run retrace --from cts      Clear from CTS stage onwards
  cbflow run retrace --run           Clear all stamps and rerun
  cbflow run retrace --from cts --run  Clear from CTS and rerun""")
    retrace_parser.add_argument('--from', dest='from_stage', help='Retrace from this stage onwards')
    retrace_parser.add_argument('--run', action='store_true', help='Rerun flow after clearing stamps')

    # bypass command
    bypass_parser = subparsers.add_parser('bypass', help='Skip stages (mark as done without running)',
        formatter_class=_fmt, description="""Mark stages as DONE without executing.
Useful for skipping stages not needed in this run (e.g., skip export_data).

Examples:
  cbflow run bypass --stages export_data1,release_data1
  cbflow run bypass --stages init_design1        Skip just init_design""")
    bypass_parser.add_argument('--stages', '-s', required=True,
                               help='Comma-separated stages to bypass')

    # force command
    force_parser = subparsers.add_parser('force', help='Force re-run specific stages only',
        formatter_class=_fmt, description="""Force re-execute specific stages without invalidating downstream.
Only the named stages are invalidated and re-run. Dependencies must already be DONE.

Examples:
  cbflow run force --stages place1               Re-run place only
  cbflow run force --stages cts1,cts_opt1        Re-run CTS stages""")
    force_parser.add_argument('--stages', '-s', required=True,
                              help='Comma-separated stages to force re-run')

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
  cbflow run forcevalidate --from route1   Mark route onwards as done""")
    fv_parser.add_argument('--node', '-n', help='Single stage to mark as completed')
    fv_parser.add_argument('--from', dest='from_stage', help='Start of range (inclusive)')
    fv_parser.add_argument('--to', dest='to_stage', help='End of range (inclusive)')
    fv_parser.add_argument('--stages', '-s', help='Comma-separated list (backward compat)')

    # clean command
    clean_parser = subparsers.add_parser('clean', help='Clean run directory',
        formatter_class=_fmt, description="""Delete all work files, logs, and stamps.

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
  cbflow run add-node --type drc --dep inputs1          # auto-names as drc2
  cbflow run add-node --type place --dep cts1           # auto-names as place2
  cbflow run add-node --node eco_fix1 --type eco --dep signoff1  # explicit name

  Use 'cbflow run list-nodes' to see existing nodes
  Use 'cbflow run show-graph' to see the dependency graph""")
    add_node_parser.add_argument('--node', '-n', required=False, default=None,
                                help='Node name (optional - auto-generated from type if omitted)')
    add_node_parser.add_argument('--type', '-t', required=True,
                                help='Node type - must be a valid stage type for current flow')
    add_node_parser.add_argument('--dep', '-d',
                                help='Dependency node - the new node runs after this one')

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
  cbflow run create-branch --branch fix_timing --from place
  cbflow run create-branch -b experiment -from cts""")
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
    subparsers.add_parser('gen-makefile', help='Verify engine DAG',
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

Release is milestone-gated: all required flows for the active tag must have completed runs.
Tags are predefined in release_config.tcl. The active tag is set by leads in project config.

Examples:
  cbflow run release                    Release using active tag from project config
  cbflow run release --tag BTO          Override with explicit tag
  cbflow run release --dry-run          Validate only, don't copy files""")
    release_parser.add_argument('--tag', '-t', help='Release tag override (default: project active_tag)')
    release_parser.add_argument('--dry-run', action='store_true', help='Validate only, no file copy')

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
  cbflow run release-check --tag BTO --project ravendrive --phase P2
  cbflow run release-check --tag PLACE_EXIT --project ravendrive
  cbflow run release-check --tag BTO --project ravendrive --block cpu_core""")
    rc_parser.add_argument('--tag', '-t', required=True, help='Release tag to check')
    rc_parser.add_argument('--project', '-p', required=True, help='Project name')
    rc_parser.add_argument('--phase', default='P0', help='Design phase (default: P0)')
    rc_parser.add_argument('--block', '-b', help='Check specific block only (default: all blocks)')

    # targets command
    subparsers.add_parser('targets', help='List make targets',
        formatter_class=_fmt, description="""List all available make targets in the Makefile.

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
  cbflow run validate --stage place      Validate stage outputs + exit criteria
  cbflow run validate --type exit --stage cts   Check CTS exit criteria""")
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
    lsf_parser = subparsers.add_parser('lsf-status', help='Show LSF job status')
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

Examples:
  cbflow run interactive --node place1          Load place1 design
  cbflow run interactive --node signoff1        Load signoff1 checkpoint
  cbflow run interactive -n floorplan1          Load floorplan1 design""")
    interactive_parser.add_argument('--node', '-n', required=True,
                                   help='Node to restore (e.g., place1, cts1, signoff1)')
    interactive_parser.add_argument('--notiming', action='store_true', default=False,
                                   help='Launch Innovus without timing libraries (faster startup)')

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
    ck.add_argument('--milestone', '-m', help='Exit milestone (FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO)')
    ck.add_argument('--phase', '-p', help='Design phase (P0, P1, P2, P3)')
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
run's deep-link. The daemon's port is deterministic per-user
(9000 + uid %% 1000) — pass --port to 'cbflow dashboard start',
not here.

Examples:
  cbflow run gui                  Register + open in daemon (default)
  cbflow run gui --no-browser     Register but don't open browser
  cbflow run gui --foreground     Legacy: per-run foreground server
  cbflow run gui --foreground --port 9090
                                  Legacy server on a specific port""")
    dash_parser.add_argument('--port', '-p', type=int, default=0,
                             help='Port for --foreground mode only (default: auto). '
                                  'In daemon mode use: cbflow dashboard start --port N')
    dash_parser.add_argument('--no-browser', action='store_true', dest='no_browser', help='Don\'t open browser')
    dash_parser.add_argument('--foreground', action='store_true',
                             help='Run a per-run foreground server (legacy). Skips the daemon.')
    dash_parser.add_argument('--daemon', action='store_true',
                             help='Explicitly use daemon mode (now the default; flag kept for clarity)')

    db_parser = subparsers.add_parser('db-manage', help='Manage RACE database sessions',
        formatter_class=_fmt, description="""Manage RACE SQLite database sessions.

Lists all existing RACE databases for the current user, shows disk usage,
and provides options to delete old/unwanted sessions.

The maximum number of DB sessions is controlled by flow(race,db_max_sessions)
in flow_config.tcl (default: 10). A warning is issued when the threshold is reached.""")
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
        return _cmd_gui_daemon(no_browser)

    # --foreground: legacy per-run server (unchanged).
    import sys
    sys.path.insert(0, os.path.join(os.environ.get('FLOW_DIR', ''), 'utils', 'dashboard'))
    try:
        from race_dashboard import start_dashboard
    except ImportError:
        dashboard_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'dashboard')
        sys.path.insert(0, dashboard_dir)
        from race_dashboard import start_dashboard
    return start_dashboard(os.getcwd(), port=port, open_browser=not no_browser) or 0


def _cmd_gui_daemon(no_browser):
    """Register the current run with the per-user dashboard daemon."""
    import sys
    dashboard_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'dashboard')
    if dashboard_dir not in sys.path:
        sys.path.insert(0, dashboard_dir)
    import lifecycle  # noqa: E402

    try:
        lifecycle.ensure_daemon()
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

    flow_dir = os.environ.get('FLOW_DIR', '')
    if not flow_dir:
        env_file = os.path.join(os.getcwd(), '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if 'FLOW_DIR=' in line:
                        flow_dir = line.split('=', 1)[1].strip().strip('"')

    # Read limits from flow_config
    max_sessions = 10
    fc_path = os.path.join(flow_dir, 'config', 'flow', 'v1.0.0', 'flow_config.tcl')
    if os.path.exists(fc_path):
        with open(fc_path) as f:
            for line in f:
                m = _re.search(r'flow\(race,db_max_sessions\)\s+(\d+)', line)
                if m: max_sessions = int(m.group(1))
    warn_threshold = int(max_sessions * 0.8)

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

    # Search race area (primary location)
    race_area = ''
    project_name = os.environ.get('CBFLOW_PROJECT_NAME', '')
    config_root = os.environ.get('CONFIG_ROOT', flow_dir)
    if project_name and config_root:
        for cfg_file in Path(os.path.join(config_root, 'config', 'project', project_name)).rglob('*_config.tcl'):
            try:
                with open(cfg_file) as f:
                    for line in f:
                        m = _re.match(r'set\s+project\(race,db_path\)\s+"([^"]+)"', line.strip())
                        if m:
                            race_area = m.group(1)
                            break
            except (OSError, UnicodeDecodeError):
                pass
            if race_area:
                break

    if race_area and os.path.isdir(race_area):
        # Scan all .db files in race area for this user
        for db_file in Path(race_area).rglob('*.db'):
            _scan_db(db_file, db_file.stem)
    else:
        # Fallback: search local workarea
        workarea = os.path.dirname(os.getcwd()) if is_run_directory() else os.getcwd()
        for run_dir in Path(workarea).iterdir():
            if not run_dir.is_dir():
                continue
            # Check pointer file first
            pointer = run_dir / '.race_db_pointer'
            if pointer.exists():
                try:
                    db_path = pointer.read_text().strip()
                    if db_path and os.path.exists(db_path):
                        _scan_db(Path(db_path), str(run_dir.name))
                        continue
                except (OSError, IOError):
                    pass
            # Local .race_*.db files
            for db_file in run_dir.glob('.race_*.db'):
                _scan_db(db_file, str(run_dir.name))

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
    # Check project(autoppt,enabled) — default false
    _enabled = False
    _uc = os.path.join(os.getcwd(), 'setup', 'user_config.tcl')
    if os.path.exists(_uc):
        with open(_uc, 'r') as _f:
            for _line in _f:
                if 'autoppt,enabled' in _line and '"true"' in _line:
                    _enabled = True
                    break
    if not _enabled:
        # Also check project_config via env
        env_vars = load_run_env() if 'load_run_env' in dir() else {}
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
