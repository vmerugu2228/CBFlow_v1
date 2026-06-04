#!/usr/bin/env python3
"""
CBFlow LSF Command Handler

Bridges the Python command layer to the existing TCL LSF infrastructure.
Provides LSF job submission, monitoring, and cost tracking.
"""

import argparse
import os
import sys
import subprocess
import json
import logging
from pathlib import Path
from datetime import datetime

from logging_config import configure_logging, get_logger

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir, get_flow_config_version

logger = configure_logging('cbflow.lsf')



def get_lsf_config_path() -> str:
    """Get LSF configuration file path."""
    core_dir = get_cbflow_core_dir()
    version = get_flow_config_version()
    return os.path.join(core_dir, 'config', 'flow', version, 'lsf_config.tcl')


def get_lsf_utils_path() -> str:
    """Get LSF utilities script path."""
    core_dir = get_cbflow_core_dir()
    version = os.environ.get('UTILITIES_VERSION', 'v1.0.0')
    return os.path.join(core_dir, 'utils', 'utilities', version, 'lsf_utils.tcl')


# Queue specs and mappings loaded from lsf_config.tcl at runtime
_lsf_config_cache = None

def _load_lsf_config():
    """Load LSF config from lsf_config.tcl (cached)."""
    global _lsf_config_cache
    if _lsf_config_cache is not None:
        return _lsf_config_cache

    from lsf_manager_cmd import LsfConfigParser, _get_lsf_config_path
    parser = LsfConfigParser(_get_lsf_config_path())
    if parser.parse():
        # Convert to QUEUE_SPECS format for backward compat
        specs = {}
        for qname, qinfo in parser.queues.items():
            mem_str = qinfo.get('memory', '0GB')
            mem_gb = int(mem_str.replace('GB', '').replace('gb', '')) if 'GB' in mem_str.upper() else 0
            specs[qname] = {
                'memory_gb': mem_gb,
                'cpu': int(qinfo.get('cpu', 1)),
                'time_limit': qinfo.get('runtime_limit', '2:00'),
                'cost_factor': float(qinfo.get('cost_factor', 1.0)),
            }
        _lsf_config_cache = {'specs': specs, 'parser': parser}
    else:
        # Fallback if config not found
        _lsf_config_cache = {'specs': {}, 'parser': None}

    return _lsf_config_cache


def _get_queue_specs():
    """Get queue specs from lsf_config.tcl."""
    return _load_lsf_config()['specs']

# Module-level alias for backward compat
QUEUE_SPECS = None  # Lazy-loaded, use _get_queue_specs()


def get_queue_recommendation(flow_type: str, stage: str) -> str:
    """Get recommended LSF queue for a flow type and stage (from lsf_config.tcl).

    Args:
        flow_type: Flow type (e.g., 'PNR')
        stage: Stage name (e.g., 'place1')

    Returns:
        Queue type (e.g., 'L')
    """
    cfg = _load_lsf_config()
    parser = cfg.get('parser')
    if parser:
        queue = parser.get_queue_for_stage(flow_type.upper(), stage)
    else:
        queue = 'M'

    return queue


def create_bsub_command(flow_type: str, stage: str, queue: str = None,
                        job_name: str = None) -> str:
    """Generate a bsub command string for LSF submission.

    Args:
        flow_type: Flow type
        stage: Stage name
        queue: Optional queue override
        job_name: Optional job name

    Returns:
        bsub command string
    """
    if not queue:
        queue = get_queue_recommendation(flow_type, stage)

    specs = _get_queue_specs().get(queue, _get_queue_specs()['M'])

    if not job_name:
        run_name = os.environ.get('CBFLOW_RUN_NAME', 'run')
        job_name = f"cbflow_{flow_type}_{stage}_{run_name}"

    memory_kb = specs['memory_gb'] * 1024 * 1024  # Convert to KB for rusage

    parts = [
        'bsub',
        f'-q {queue}',
        f'-J "{job_name}"',
        f'-n {specs["cpu"]}',
        f'-R "rusage[mem={memory_kb}]"',
        f'-W {specs["time_limit"]}',
        f'-o logs/lsf_{stage}_%J.log',
        f'-e logs/lsf_{stage}_%J.err',
    ]

    return ' '.join(parts)


def cmd_lsf_status(args: argparse.Namespace) -> int:
    """Show LSF job status for current run."""
    run_name = os.environ.get('CBFLOW_RUN_NAME', '')
    flow_type = os.environ.get('CBFLOW_FLOW_TYPE', '')

    logger.info("")
    logger.info(f"{'═'*60}")
    logger.info(f"  LSF Job Status")
    logger.info(f"{'═'*60}")

    # Check if bjobs is available
    try:
        result = subprocess.run(['bjobs', '-w'], capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            if result.stdout.strip():
                logger.info(f"\n  Active Jobs:")
                for line in result.stdout.strip().split('\n'):
                    logger.info(f"    {line}")
            else:
                logger.info(f"  No active LSF jobs")
        else:
            logger.info(f"  bjobs returned: {result.stderr.strip()}")
    except FileNotFoundError:
        logger.warning("  LSF commands not available (bjobs not found)")
        logger.info("  LSF integration requires LSF to be installed and configured")
        logger.info("")

        # Show what would be submitted
        logger.info(f"  Queue Recommendations for {flow_type}:")
        logger.info(f"  {'─'*50}")

        if flow_type:
            try:
                from tcl_config_parser import get_flow_stages
                stages = get_flow_stages(flow_type)
                for stage in stages:
                    queue = get_queue_recommendation(flow_type, f"{stage}1")
                    specs = _get_queue_specs().get(queue, {})
                    logger.info(f"    {stage:20s} -> Queue {queue:5s} "
                              f"({specs.get('memory_gb', '?')}GB, {specs.get('cpu', '?')} CPU)")
            except ImportError:
                pass

    except subprocess.TimeoutExpired:
        logger.error("  bjobs command timed out")

    logger.info(f"{'═'*60}")
    logger.info("")
    return 0


def cmd_lsf_cost(args: argparse.Namespace) -> int:
    """Show LSF cost tracking for current run."""
    logger.info("")
    logger.info(f"{'═'*60}")
    logger.info(f"  LSF Cost Summary")
    logger.info(f"{'═'*60}")
    logger.info("")

    # Show queue cost factors
    logger.info(f"  Queue Cost Factors:")
    logger.info(f"  {'─'*50}")
    logger.info(f"  {'Queue':8s} {'Memory':>8s} {'CPU':>6s} {'Time':>8s} {'Cost/hr':>10s}")
    logger.info(f"  {'─'*50}")

    cpu_cost_per_hour = 0.50
    mem_cost_per_gb_hour = 0.10

    for queue, specs in sorted(_get_queue_specs().items(), key=lambda x: x[1]['cost_factor']):
        hourly_cost = (specs['cpu'] * cpu_cost_per_hour +
                      specs['memory_gb'] * mem_cost_per_gb_hour)
        logger.info(f"  {queue:8s} {specs['memory_gb']:>6d}GB {specs['cpu']:>5d} "
                   f"{specs['time_limit']:>8s} ${hourly_cost:>8.2f}")

    logger.info(f"")
    logger.info(f"  Pricing: CPU=${cpu_cost_per_hour}/hr, Memory=${mem_cost_per_gb_hour}/GB/hr")
    logger.info(f"{'═'*60}")
    logger.info("")
    return 0


def cmd_lsf_queues(args: argparse.Namespace) -> int:
    """Show LSF queue information."""
    flow_type = getattr(args, 'flow', None) or os.environ.get('CBFLOW_FLOW_TYPE', '')

    logger.info("")
    logger.info(f"{'═'*60}")
    logger.info(f"  LSF Queue Configuration")
    logger.info(f"{'═'*60}")
    logger.info("")

    # Show available queues
    logger.info(f"  Available Queues:")
    logger.info(f"  {'─'*50}")
    logger.info(f"  {'Queue':8s} {'Memory':>8s} {'CPU':>6s} {'Time Limit':>12s}")
    logger.info(f"  {'─'*50}")

    for queue, specs in sorted(_get_queue_specs().items(), key=lambda x: x[1]['cost_factor']):
        logger.info(f"  {queue:8s} {specs['memory_gb']:>6d}GB {specs['cpu']:>5d} "
                   f"{specs['time_limit']:>12s}")

    # Show flow-specific mappings
    if flow_type:
        logger.info("")
        logger.info(f"  Queue Mappings for {flow_type}:")
        logger.info(f"  {'─'*50}")

        cfg = _load_lsf_config()
        flow_queues = cfg['parser'].flow_mappings.get(flow_type.upper(), {}) if cfg.get('parser') else {}
        if flow_queues:
            for stage, queue in sorted(flow_queues.items()):
                specs = _get_queue_specs().get(queue, {})
                logger.info(f"    {stage:20s} -> {queue:5s} "
                          f"({specs.get('memory_gb', '?')}GB, {specs.get('cpu', '?')} CPU)")
        else:
            logger.info(f"    No specific mappings for {flow_type}")
            logger.info(f"    Default queue selection will be used")

    logger.info(f"")
    logger.info(f"{'═'*60}")
    return 0


def cmd_lsf_submit(args: argparse.Namespace) -> int:
    """Submit a direct bsub command, bypassing lsf_config queue mappings."""

    # If user gives a raw command, just wrap it in bsub
    if args.command_str:
        # User-supplied raw command
        cmd_str = args.command_str

        bsub_parts = ['bsub']

        # Optional overrides
        if args.queue:
            bsub_parts.append(f'-q {args.queue}')
        if args.memory:
            mem_kb = int(args.memory.rstrip('GgMm')) * (1024*1024 if args.memory.upper().endswith('G') else 1024)
            bsub_parts.append(f'-R "rusage[mem={mem_kb}]"')
        if args.cpu:
            bsub_parts.append(f'-n {args.cpu}')
        if args.time:
            bsub_parts.append(f'-W {args.time}')
        if args.name:
            bsub_parts.append(f'-J "{args.name}"')
        else:
            bsub_parts.append(f'-J "cbflow_direct_{os.getpid()}"')
        if args.log_dir:
            os.makedirs(args.log_dir, exist_ok=True)
            bsub_parts.append(f'-o {args.log_dir}/lsf_%J.log')
            bsub_parts.append(f'-e {args.log_dir}/lsf_%J.err')

        bsub_parts.append(cmd_str)
        full_cmd = ' '.join(bsub_parts)

        logger.info("")
        logger.info(f"{'='*60}")
        logger.info(f"  LSF Direct Submit")
        logger.info(f"{'='*60}")
        logger.info(f"  Command: {full_cmd}")
        logger.info("")

        if args.dry_run:
            logger.info(f"  [DRY RUN] Command not submitted")
            logger.info(f"  Copy and run: {full_cmd}")
        else:
            try:
                result = subprocess.run(full_cmd, shell=True, capture_output=True, text=True, timeout=30)
                if result.returncode == 0:
                    logger.info(f"  Submitted: {result.stdout.strip()}")
                else:
                    logger.error(f"  Submit failed: {result.stderr.strip()}")
                    return 1
            except FileNotFoundError:
                logger.error("  bsub not found. LSF not available on this machine.")
                logger.info(f"  Command would be: {full_cmd}")
                return 1
            except subprocess.TimeoutExpired:
                logger.error("  bsub command timed out")
                return 1

        logger.info(f"{'='*60}")
        return 0

    # If no raw command, generate from flow/stage
    flow_type = args.flow or os.environ.get('CBFLOW_FLOW_TYPE', '')
    stage = args.stage or ''

    if not flow_type or not stage:
        logger.error("Either --cmd <command> or --flow + --stage required")
        return 1

    queue = args.queue or get_queue_recommendation(flow_type, stage)
    bsub_cmd = create_bsub_command(flow_type, stage, queue, args.name)

    # Add the make target as the command to run
    make_cmd = f"make -C {os.getcwd()} {stage.rstrip('0123456789')}"
    full_cmd = f"{bsub_cmd} '{make_cmd}'"

    logger.info("")
    logger.info(f"{'='*60}")
    logger.info(f"  LSF Submit: {flow_type} / {stage}")
    logger.info(f"{'='*60}")
    logger.info(f"  Queue: {queue}")
    specs = _get_queue_specs().get(queue, {})
    logger.info(f"  Resources: {specs.get('memory_gb', '?')}GB, {specs.get('cpu', '?')} CPU, {specs.get('time_limit', '?')}")
    logger.info(f"  Command: {full_cmd}")

    if args.dry_run:
        logger.info(f"  [DRY RUN] Not submitted")
    else:
        try:
            result = subprocess.run(full_cmd, shell=True, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                logger.info(f"  Submitted: {result.stdout.strip()}")
            else:
                logger.error(f"  Failed: {result.stderr.strip()}")
                return 1
        except FileNotFoundError:
            logger.error("  bsub not found")
            return 1

    logger.info(f"{'='*60}")
    return 0


def cmd_lsf_run(args: argparse.Namespace) -> int:
    """Run a command directly with specific LSF resources (no config lookup)."""
    if not args.command_str:
        logger.error("--cmd <command> is required")
        return 1

    queue = args.queue or 'M'
    specs = _get_queue_specs().get(queue, _get_queue_specs()['M'])

    # Allow full override of resources
    memory = args.memory or f"{specs['memory_gb']}G"
    cpu = args.cpu or specs['cpu']
    time_limit = args.time or specs['time_limit']
    job_name = args.name or f"cbflow_run_{os.getpid()}"

    mem_val = int(memory.rstrip('GgMm'))
    if memory.upper().endswith('G'):
        mem_kb = mem_val * 1024 * 1024
    else:
        mem_kb = mem_val * 1024

    log_dir = args.log_dir or 'logs'
    os.makedirs(log_dir, exist_ok=True)

    bsub_cmd = (
        f'bsub -q {queue} -J "{job_name}" -n {cpu} '
        f'-R "rusage[mem={mem_kb}]" -W {time_limit} '
        f'-o {log_dir}/lsf_%J.log -e {log_dir}/lsf_%J.err '
        f'{args.command_str}'
    )

    logger.info("")
    logger.info(f"{'='*60}")
    logger.info(f"  LSF Direct Run")
    logger.info(f"{'='*60}")
    logger.info(f"  Queue:    {queue}")
    logger.info(f"  Memory:   {memory}")
    logger.info(f"  CPU:      {cpu}")
    logger.info(f"  Time:     {time_limit}")
    logger.info(f"  Job Name: {job_name}")
    logger.info(f"  Command:  {args.command_str}")
    logger.info(f"  Full:     {bsub_cmd}")
    logger.info("")

    if args.dry_run:
        logger.info(f"  [DRY RUN] Not submitted. Copy and run:")
        logger.info(f"  {bsub_cmd}")
    else:
        try:
            result = subprocess.run(bsub_cmd, shell=True, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                logger.info(f"  Submitted: {result.stdout.strip()}")
            else:
                logger.error(f"  Failed: {result.stderr.strip()}")
                return 1
        except FileNotFoundError:
            logger.error("  bsub not found on this machine")
            logger.info(f"  Command would be: {bsub_cmd}")
            return 1

    logger.info(f"{'='*60}")
    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow lsf',
        description='CBFlow LSF Integration',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow run lsf-status                      Show LSF job status
  cbflow run lsf-queues --flow PNR            Show queue mappings
  cbflow run lsf-cost                         Show cost info

  # Direct submit - bypass lsf_config, give your own command:
  cbflow run lsf-submit --cmd "make place" --queue L --memory 32G --cpu 16
  cbflow run lsf-submit --cmd "tclsh my_script.tcl" --queue XL --name my_job
  cbflow run lsf-submit --cmd "make all" --dry-run   # Preview only

  # Direct run - full resource control:
  cbflow run lsf-run --cmd "pt_shell -f timing.tcl" --queue L --memory 64G --cpu 8
  cbflow run lsf-run --cmd "innovus -batch -f pnr.tcl" --queue XL --time 12:00

  # Flow-aware submit (uses queue mappings):
  cbflow run lsf-submit --flow PNR --stage place1
  cbflow run lsf-submit --flow STA --stage timing1 --queue XL  # Override queue
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='LSF commands')

    # status command
    subparsers.add_parser('status', help='Show LSF job status')

    # cost command
    subparsers.add_parser('cost', help='Show LSF cost tracking')

    # queues command
    queues_parser = subparsers.add_parser('queues', help='Show queue configuration')
    queues_parser.add_argument('--flow', help='Show mappings for specific flow type')

    # submit command - direct bsub, bypassing lsf_config
    submit_parser = subparsers.add_parser('submit', help='Submit command via LSF (direct or flow-aware)')
    submit_parser.add_argument('--cmd', dest='command_str', default=None,
                                help='Direct command to submit (bypasses flow config)')
    submit_parser.add_argument('--flow', default=None, help='Flow type (for flow-aware submit)')
    submit_parser.add_argument('--stage', default=None, help='Stage name (for flow-aware submit)')
    submit_parser.add_argument('--queue', '-q', default=None,
                                help='LSF queue (XS/S/M/L/XL/ultra) - overrides auto-selection')
    submit_parser.add_argument('--memory', '-m', default=None, help='Memory (e.g., 32G, 16384M)')
    submit_parser.add_argument('--cpu', '-n', type=int, default=None, help='Number of CPUs')
    submit_parser.add_argument('--time', '-W', default=None, help='Wall time limit (e.g., 4:00)')
    submit_parser.add_argument('--name', '-J', default=None, help='Job name')
    submit_parser.add_argument('--log-dir', default='logs', help='Log directory (default: logs)')
    submit_parser.add_argument('--dry-run', action='store_true', help='Show command without submitting')

    # run command - direct bsub with full resource control
    run_parser = subparsers.add_parser('run', help='Run command with specific LSF resources')
    run_parser.add_argument('--cmd', dest='command_str', required=True,
                             help='Command to run')
    run_parser.add_argument('--queue', '-q', default='M', help='LSF queue (default: M)')
    run_parser.add_argument('--memory', '-m', default=None, help='Memory (e.g., 32G)')
    run_parser.add_argument('--cpu', '-n', type=int, default=None, help='Number of CPUs')
    run_parser.add_argument('--time', '-W', default=None, help='Wall time limit')
    run_parser.add_argument('--name', '-J', default=None, help='Job name')
    run_parser.add_argument('--log-dir', default='logs', help='Log directory')
    run_parser.add_argument('--dry-run', action='store_true', help='Show command without submitting')

    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    commands = {
        'status': cmd_lsf_status,
        'cost': cmd_lsf_cost,
        'queues': cmd_lsf_queues,
        'submit': cmd_lsf_submit,
        'run': cmd_lsf_run,
    }

    if args.command in commands:
        return commands[args.command](args)

    return 1


if __name__ == '__main__':
    sys.exit(main())
