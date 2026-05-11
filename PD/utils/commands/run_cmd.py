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
logger = configure_logging('cbflow.run')

# Version
VERSION = "2.0.0"



def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory from environment or determine from script location."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


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


def get_flow_stages(flow_type: str) -> list:
    """Get ordered stages for a flow type.

    For single flows: loads from node config (e.g., PNR_config.tcl).
    For merged flows: builds combined prefixed stage list (e.g., synth_inputs, fp_floorplan).
    """
    from tcl_config_parser import is_merged_flow, get_merged_flow_stage_names
    from tcl_config_parser import get_flow_stages as _get_stages

    if is_merged_flow(flow_type):
        return get_merged_flow_stage_names(flow_type)
    return _get_stages(flow_type)


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
    flow_type = get_flow_type()
    valid_stages = get_flow_stages(flow_type)
    validate = getattr(args, 'validate', False)
    use_lsf = getattr(args, 'lsf', False)
    lsf_queue = getattr(args, 'queue', None)

    if stage not in valid_stages and stage != 'all':
        logger.error(f"Invalid stage: {stage}")
        logger.info(f"Valid stages for {flow_type}: {', '.join(valid_stages)}")
        return 1

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
    valid = get_flow_stages(flow_type)
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
    all_stages = get_flow_stages(flow_type)

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
    valid = get_flow_stages(flow_type)
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
                                stamp_file = os.path.join(stamps_dir, f'{subnode_stamp}.stamp')
                                mtime = datetime.fromtimestamp(os.path.getmtime(stamp_file))
                                logger.info(f"      [DONE] {subnode:<24} {mtime.strftime('%Y-%m-%d %H:%M:%S')}")
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
    all_stages = get_flow_stages(flow_type)

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
                # Remove stamp
                stamp = os.path.join(os.getcwd(), '.stamps', f'{name}.stamp')
                if os.path.exists(stamp):
                    os.remove(stamp)

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
    stages = get_flow_stages(flow_type)

    from tcl_config_parser import get_subnodes, _load_node_config, _parse_tcl_list
    node_config = _load_node_config(flow_type)

    stamps_dir = '.stamps'
    completed = set()
    if os.path.exists(stamps_dir):
        completed = {f.replace('.stamp', '') for f in os.listdir(stamps_dir) if f.endswith('.stamp')}

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
            if sn_done:
                stamp_file = os.path.join(stamps_dir, f'{sn_key}.stamp')
                if os.path.exists(stamp_file):
                    ts = datetime.fromtimestamp(os.path.getmtime(stamp_file)).strftime('%Y-%m-%d %H:%M:%S')
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

    dirs_to_clean = ['work', '.stamps', 'logs', ]
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


def cmd_list_nodes(args: argparse.Namespace) -> int:
    """List all flow nodes."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        logger.error("  Navigate to a run directory first: cd P0_run_PNR_run1")
        return 1

    flow_type = get_flow_type()
    stages = get_flow_stages(flow_type)

    # Check stamps for completion status
    stamps_dir = '.stamps'
    completed = set()
    if os.path.exists(stamps_dir):
        completed = {f.replace('.stamp', '') for f in os.listdir(stamps_dir) if f.endswith('.stamp')}

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
        stages = get_flow_stages(flow_type)
        node_config = _load_node_config(flow_type)
        parallel_set = set(get_parallel_stages(flow_type))
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

    # Check stamps for completion
    completed = set()
    if os.path.exists('.stamps'):
        completed = {f.replace('.stamp', '') for f in os.listdir('.stamps')
                     if f.endswith('.stamp')}

    # Get subnodes per stage if detail mode
    detail = getattr(args, 'detail', False)
    subnodes_map = {}
    if detail:
        from tcl_config_parser import _load_node_config, _parse_tcl_list
        node_config = _load_node_config(flow_type)
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
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', 'P0')

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
    load_node = getattr(args, 'load', None)

    # Determine tool from run env → user_config override → flow config default
    _ensure_run_env_loaded()

    vendor = os.environ.get('CBFLOW_TOOL_VENDOR', '')
    tool_name = os.environ.get('CBFLOW_TOOL_NAME', '')

    if not vendor or not tool_name:
        # Try reading from user_config in setup/
        user_cfg = os.path.join(run_dir, 'setup', 'user_config.tcl')
        if os.path.exists(user_cfg):
            import re as _re
            with open(user_cfg) as f:
                for line in f:
                    m = _re.match(r'set\s+\w+\(tool,vendor\)\s+"([^"]*)"', line.strip())
                    if m and not vendor:
                        vendor = m.group(1)
                    m = _re.match(r'set\s+\w+\(tool,name\)\s+"([^"]*)"', line.strip())
                    if m and not tool_name:
                        tool_name = m.group(1)

    if not vendor or not tool_name:
        sys.path.insert(0, os.path.join(os.environ.get('FLOW_DIR', ''), 'utils', 'commands'))
        from tcl_config_parser import get_tool_info
        tool_info = get_tool_info(flow_type)
        if not vendor:
            vendor = tool_info.get('vendor', 'synopsys')
        if not tool_name:
            tool_name = tool_info.get('name', 'fc')

    # Resolve tool shell from tool_launch_config
    tool_shell_map = {
        'fc': 'fc_shell', 'pt': 'pt_shell', 'fm': 'fm_shell',
        'genus': 'genus', 'innovus': 'innovus', 'tempus': 'tempus',
        'icv': 'icv', 'vc_lp': 'vc_lp_shell', 'redhawk': 'redhawk',
        'voltus': 'voltus', 'calibre': 'calibre',
    }
    tool_shell = tool_shell_map.get(tool_name, tool_name)

    # Module load
    module_map = {
        'fc': 'module load synopsysFusionCompiler/2025.06-SP2',
        'pt': 'module load synopsysPrimeTime/2025.06',
        'fm': 'module load synopsysFormality/2025.06',
        'icv': 'module load synopsysICV/2025.06',
        'genus': 'module load cadenceGenus/23.1',
        'innovus': 'module load cadenceInnovus/23.1',
        'tempus': 'module load cadenceTempus/23.1',
    }
    module_cmd = module_map.get(tool_name, '')

    # Create INTERACTIVE directory
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    if load_node:
        session_name = f"{load_node}_{ts}"
    else:
        session_name = f"session_{ts}"

    interactive_dir = os.path.join(run_dir, 'INTERACTIVE', session_name)
    os.makedirs(interactive_dir, exist_ok=True)

    # Build tool launch arguments
    tool_args = ""
    if load_node:
        # Determine what to load based on flow type
        if tool_name == 'fc':
            # FC: load NDM design library
            ndm_path = os.path.join(run_dir, 'work', flow_type, f'{load_node}', 'run',
                                    f'{load_node}.nlib')
            if os.path.exists(ndm_path):
                tool_args = f"-x 'open_lib {ndm_path}'"
            else:
                # Try .enc format
                enc_path = os.path.join(run_dir, 'work', flow_type, f'{load_node}', 'run',
                                       f'{load_node}.enc')
                if os.path.exists(enc_path):
                    tool_args = f"-x 'open_lib {enc_path}'"
                else:
                    logger.info(f"  No saved design found for {load_node} — opening empty session")
        elif tool_name == 'innovus':
            # Innovus: restore .enc session
            enc_path = os.path.join(run_dir, 'work', flow_type, f'{load_node}', 'run',
                                   f'{load_node}.enc')
            if os.path.exists(enc_path):
                tool_args = f"-init 'restoreDesign {enc_path}'"
        elif tool_name == 'pt':
            # PT: restore saved session
            ss_path = os.path.join(run_dir, 'results', 'sta', f'*_{load_node}_ss')
            tool_args = ""  # PT opens interactively, user can restore_session
        elif tool_name == 'icv':
            # ICV: point to GDS
            gds_path = os.path.join(run_dir, 'work', flow_type, f'{load_node}', 'run')
            tool_args = ""

    # Generate wrapper script
    wrapper_path = os.path.join(interactive_dir, 'launch_interactive.csh')
    with open(wrapper_path, 'w') as wf:
        wf.write("#!/bin/csh -f\n")
        wf.write(f"# CBflow Interactive Session — {flow_type} / {tool_name}\n")
        wf.write(f"# Session: {session_name}\n")
        wf.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        wf.write(f"cd {interactive_dir}\n")
        if module_cmd:
            wf.write(f"{module_cmd}\n")
        # Source run environment
        wf.write(f"source {run_dir}/.run.cbflow.env\n")
        # Launch tool in GUI mode
        if tool_name == 'fc':
            wf.write(f"{tool_shell} -gui {tool_args}\n")
        elif tool_name in ('innovus', 'genus', 'tempus', 'voltus'):
            wf.write(f"{tool_shell} {tool_args}\n")
        elif tool_name == 'pt':
            wf.write(f"{tool_shell} {tool_args}\n")
        elif tool_name == 'icv':
            wf.write(f"icv -vue {tool_args}\n")
        elif tool_name == 'fm':
            wf.write(f"{tool_shell} -gui {tool_args}\n")
        elif tool_name == 'calibre':
            wf.write(f"calibredrv {tool_args}\n")
        else:
            wf.write(f"{tool_shell} {tool_args}\n")
    os.chmod(wrapper_path, 0o755)

    # Print info
    logger.info("")
    logger.info(f"  ═══════════════════════════════════════════════════════")
    logger.info(f"  CBflow Interactive Session")
    logger.info(f"  ═══════════════════════════════════════════════════════")
    logger.info(f"  Flow:      {flow_type}")
    logger.info(f"  Tool:      {tool_name} ({vendor})")
    logger.info(f"  Shell:     {tool_shell}")
    if load_node:
        logger.info(f"  Load:      {load_node}")
    logger.info(f"  Session:   INTERACTIVE/{session_name}")
    logger.info(f"  Wrapper:   {wrapper_path}")
    logger.info("")

    # Launch mode from flow_config.tcl (not env vars)
    use_lsf = False
    xterm_cmd = 'xterm'
    xterm_geom = '200x50'

    # Read from tool_launch_config if available
    try:
        tlc_path = os.path.join(os.environ.get('CONFIG_ROOT', ''), 'flow',
                                os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0'),
                                'tool_launch_config.tcl')
        if os.path.exists(tlc_path):
            with open(tlc_path) as f:
                for line in f:
                    if 'lsf(xterm,command)' in line:
                        xterm_cmd = line.split('"')[1]
                    elif 'lsf(xterm,geometry)' in line:
                        xterm_geom = line.split('"')[1]
    except Exception:
        pass

    if use_lsf:
        logger.info(f"  Launch: LSF + xterm")
        # Would submit via bsub -Is xterm -e wrapper
    else:
        logger.info(f"  Launch: xterm (local)")

    # Launch xterm with tool
    title = f"CBflow {flow_type} {tool_name}"
    if load_node:
        title += f" [{load_node}]"

    logger.info(f"  Opening: {xterm_cmd} -geometry {xterm_geom} -title \"{title}\"")
    logger.info("")

    try:
        subprocess.Popen([
            xterm_cmd, '-geometry', xterm_geom,
            '-title', title,
            '-e', wrapper_path
        ])
        logger.info(f"  Interactive session launched in xterm.")
        logger.info(f"  Working directory: {interactive_dir}")
    except FileNotFoundError:
        logger.error(f"  xterm not found. Run the wrapper manually:")
        logger.error(f"    {wrapper_path}")
        return 1

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
        formatter_class=_fmt, description="""Run a single stage of the flow.

Examples:
  cbflow run stage --name place      Run the placement stage
  cbflow run stage -n cts            Short form
  cbflow run stage --name route --validate   Run with validation
  cbflow run stage --name signoff --lsf      Submit to LSF""")
    stage_parser.add_argument('--name', '-n', dest='stage', required=True, help='Stage name')
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
  cbflow run clean --confirm         Delete work/, logs/, .stamps/""")
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

    # help command
    # interactive command
    interactive_parser = subparsers.add_parser('interactive', help='Launch interactive EDA tool session',
        formatter_class=_fmt, description="""Open an interactive EDA tool session in xterm.

By default, launches the tool in GUI mode. Use --load to restore a saved design.
Creates a working directory under INTERACTIVE/<node>_<timestamp>.

Examples:
  cbflow run interactive                        Open tool in xterm (empty session)
  cbflow run interactive --load place1          Load place1 saved session/NDM
  cbflow run interactive --load signoff1        Load signoff1 checkpoint""")
    interactive_parser.add_argument('--load', '-l', default=None,
                                   help='Load saved design from this node (e.g., place1, cts1, signoff1)')

    # email command
    try:
        from email_cmd import create_parser as email_create_parser
        email_create_parser(subparsers)
    except ImportError:
        subparsers.add_parser('email', help='Send email notifications (email_cmd.py not found)')

    # autoppt command
    try:
        from autoppt_cmd import create_parser as autoppt_create_parser
        autoppt_create_parser(subparsers)
    except ImportError:
        subparsers.add_parser('autoppt', help='Generate run summary PPT/HTML (autoppt_cmd.py not found)')

    # checklist command — run-level only: status, generate, sign-off
    ck = subparsers.add_parser('checklist', help='Run exit milestone checklist',
        formatter_class=_fmt, description="""Run exit milestone checklist against the current run directory.

Validates mandatory checks, files, and deliverables for a given milestone and phase.
If run has completed stages (.stamps exist), shows PASS/FAIL status per check.
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
        formatter_class=_fmt, description="""Start the RACE GUI — a web-based flow visualization GUI.
Opens in browser with stage pipeline, DAG view, job grid, and job details.

Examples:
  cbflow run gui                  Start at http://localhost:8080
  cbflow run gui --port 9090      Custom port
  cbflow run gui --no-browser     Don't auto-open browser""")
    dash_parser.add_argument('--port', '-p', type=int, default=8080, help='Port (default: 8080)')
    dash_parser.add_argument('--no-browser', action='store_true', dest='no_browser', help='Don\'t open browser')

    subparsers.add_parser('help', help='Show detailed help')

    return parser


def cmd_gui(args):
    """Start RACE Dashboard web GUI."""
    if not is_run_directory():
        logger.error("Error: Not in a valid run directory")
        return 1
    import sys
    sys.path.insert(0, os.path.join(os.environ.get('FLOW_DIR', ''), 'utils', 'dashboard'))
    try:
        from race_dashboard import start_dashboard
    except ImportError:
        # Try relative path
        dashboard_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'dashboard')
        sys.path.insert(0, dashboard_dir)
        from race_dashboard import start_dashboard

    port = getattr(args, 'port', 8080) or 8080
    no_browser = getattr(args, 'no_browser', False)
    return start_dashboard(os.getcwd(), port=port, open_browser=not no_browser) or 0


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
    try:
        from autoppt_cmd import cmd_autoppt
        return cmd_autoppt(args)
    except ImportError:
        print("ERROR: autoppt_cmd module not found")
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

    # If run has stamps, run status check; otherwise generate template
    stamps_dir = os.path.join(run_dir, '.stamps')
    if os.path.isdir(stamps_dir) and os.listdir(stamps_dir):
        return checklist_cmd.cmd_status(args)
    else:
        return checklist_cmd.cmd_generate(args)


def main() -> int:
    """Main entry point."""
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
        'help': cmd_help,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
