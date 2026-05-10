#!/usr/bin/env python3
"""
CBFlow Validation Command Handler

Orchestrates validation scripts for workspace and run validation.
Integrates existing TCL validators into the Python command pipeline.
"""

import argparse
import os
import sys
import subprocess
import json
import logging
from pathlib import Path
from datetime import datetime

# Configure unified logging
from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.validation')


def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


def get_validation_dir() -> str:
    """Get validation scripts directory."""
    core_dir = get_cbflow_core_dir()
    version = os.environ.get('UTILITIES_VERSION', 'v1.0.0')
    return os.path.join(core_dir, 'utils', 'validation', version)


def get_exit_config_dir() -> str:
    """Get exit criteria config directory."""
    core_dir = get_cbflow_core_dir()
    version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    return os.path.join(core_dir, 'config', 'exit', version)


class ValidationRunner:
    """Orchestrates validation across workspace and run stages."""

    def __init__(self, run_dir: str = None, flow_type: str = None):
        self.run_dir = run_dir or os.getcwd()
        self.flow_type = flow_type or os.environ.get('CBFLOW_FLOW_TYPE', '')
        self.validation_dir = get_validation_dir()
        self.exit_config_dir = get_exit_config_dir()
        self.results = {
            'timestamp': datetime.now().isoformat(),
            'run_dir': self.run_dir,
            'flow_type': self.flow_type,
            'validations': [],
            'passed': 0,
            'failed': 0,
            'warnings': 0
        }

    def _run_tcl_script(self, script_path: str, args: list = None, env_extra: dict = None) -> dict:
        """Run a TCL validation script and capture results."""
        if not os.path.exists(script_path):
            return {
                'script': os.path.basename(script_path),
                'status': 'skipped',
                'message': f'Script not found: {script_path}',
                'returncode': -1
            }

        cmd = ['tclsh', script_path] + (args or [])
        env = os.environ.copy()
        env['FLOW_DIR'] = get_cbflow_core_dir()
        if env_extra:
            env.update(env_extra)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                env=env,
                cwd=self.run_dir,
                timeout=300
            )

            status = 'passed' if result.returncode == 0 else 'failed'
            return {
                'script': os.path.basename(script_path),
                'status': status,
                'returncode': result.returncode,
                'stdout': result.stdout[-2000:] if len(result.stdout) > 2000 else result.stdout,
                'stderr': result.stderr[-1000:] if len(result.stderr) > 1000 else result.stderr
            }
        except subprocess.TimeoutExpired:
            return {
                'script': os.path.basename(script_path),
                'status': 'timeout',
                'message': 'Validation timed out after 300 seconds',
                'returncode': -2
            }
        except Exception as e:
            return {
                'script': os.path.basename(script_path),
                'status': 'error',
                'message': str(e),
                'returncode': -3
            }

    def validate_config(self, config_file: str = None) -> dict:
        """Validate configuration files."""
        script = os.path.join(self.validation_dir, 'validate_config.tcl')
        args = [config_file] if config_file else []
        result = self._run_tcl_script(script, args)
        self._record_result('config_validation', result)
        return result

    def validate_netlist(self) -> dict:
        """Validate netlist files."""
        script = os.path.join(self.validation_dir, 'validate_netlist.tcl')
        result = self._run_tcl_script(script)
        self._record_result('netlist_validation', result)
        return result

    def validate_sdc(self) -> dict:
        """Validate SDC constraint files."""
        script = os.path.join(self.validation_dir, 'validate_sdc.tcl')
        result = self._run_tcl_script(script)
        self._record_result('sdc_validation', result)
        return result

    def validate_floorplan(self) -> dict:
        """Validate floorplan/DEF files."""
        script = os.path.join(self.validation_dir, 'validate_floorplan.tcl')
        result = self._run_tcl_script(script)
        self._record_result('floorplan_validation', result)
        return result

    def run_pre_stage(self, stage: str) -> dict:
        """Run pre-stage validation before a stage executes.

        - For 'inputs' stage: validate config + netlist + SDC
        - For 'place'/'floorplan' stages: validate floorplan
        - For all stages: validate config
        """
        logger.info(f"Running pre-stage validation for {self.flow_type}/{stage}...")
        results = []

        # Always validate config
        config_file = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
        if os.path.exists(config_file):
            results.append(self.validate_config(config_file))

        # Input-specific validations
        stage_base = stage.rstrip('0123456789')  # Strip numeric suffix
        if stage_base in ('inputs', 'input'):
            results.append(self.validate_netlist())
            results.append(self.validate_sdc())
        elif stage_base in ('place', 'placement', 'floorplan', 'fp'):
            results.append(self.validate_floorplan())

        passed = all(r.get('status') in ('passed', 'skipped') for r in results)
        return {
            'stage': stage,
            'phase': 'pre',
            'passed': passed,
            'validations': results
        }

    def run_post_stage(self, stage: str) -> dict:
        """Run post-stage validation after a stage completes.

        Runs validate_run.tcl with stage-specific checks.
        """
        logger.info(f"Running post-stage validation for {self.flow_type}/{stage}...")

        script = os.path.join(self.validation_dir, 'validate_run.tcl')
        flow_dir = get_cbflow_core_dir()
        result = self._run_tcl_script(
            script,
            [self.flow_type, stage, self.run_dir, flow_dir]
        )
        self._record_result(f'post_stage_{stage}', result)

        # Also run enhanced validation if available
        enhanced_script = os.path.join(self.validation_dir, 'enhanced_validate_run.tcl')
        if os.path.exists(enhanced_script):
            enhanced_result = self._run_tcl_script(
                enhanced_script,
                [self.flow_type, stage, self.run_dir]
            )
            self._record_result(f'enhanced_post_stage_{stage}', enhanced_result)

        return {
            'stage': stage,
            'phase': 'post',
            'passed': result.get('status') == 'passed',
            'result': result
        }

    def check_exit_criteria(self, stage: str) -> dict:
        """Check exit criteria for a stage/milestone.

        Loads the appropriate exit config and checks if criteria are met.
        """
        # Map stages to exit config files
        stage_to_exit = {
            'floorplan': 'FP_EXIT_config.tcl',
            'fp': 'FP_EXIT_config.tcl',
            'place': 'PLACE_EXIT_config.tcl',
            'placement': 'PLACE_EXIT_config.tcl',
            'cts': 'CTS_EXIT_config.tcl',
            'route': 'PRO_EXIT_config.tcl',
            'pro': 'PRO_EXIT_config.tcl',
            'signoff': 'MTO_config.tcl',
        }

        stage_base = stage.rstrip('0123456789')
        exit_config = stage_to_exit.get(stage_base)

        if not exit_config:
            return {
                'stage': stage,
                'exit_criteria': 'none',
                'message': f'No exit criteria defined for stage: {stage}'
            }

        config_path = os.path.join(self.exit_config_dir, exit_config)
        if not os.path.exists(config_path):
            return {
                'stage': stage,
                'exit_criteria': 'missing',
                'message': f'Exit config not found: {config_path}'
            }

        # Check for mandatory files listed in exit criteria
        mandatory_files = self._parse_exit_mandatory_files(config_path)
        missing_files = []
        found_files = []

        for mf in mandatory_files:
            full_path = os.path.join(self.run_dir, mf)
            if os.path.exists(full_path):
                found_files.append(mf)
            else:
                missing_files.append(mf)

        passed = len(missing_files) == 0
        result = {
            'stage': stage,
            'exit_criteria': exit_config,
            'passed': passed,
            'mandatory_files_found': len(found_files),
            'mandatory_files_missing': len(missing_files),
            'missing_files': missing_files
        }

        self._record_result(f'exit_criteria_{stage}',
                          {'status': 'passed' if passed else 'failed',
                           'script': exit_config})

        if not passed:
            logger.warning(f"Exit criteria not met for {stage}: {len(missing_files)} mandatory files missing")
            for mf in missing_files[:5]:
                logger.warning(f"  Missing: {mf}")
        else:
            logger.info(f"Exit criteria met for {stage}")

        return result

    def _parse_exit_mandatory_files(self, config_path: str) -> list:
        """Parse mandatory files from exit criteria TCL config."""
        mandatory_files = []
        try:
            with open(config_path, 'r') as f:
                content = f.read()

            # Look for mandatory_files pattern in TCL array
            import re
            # Match patterns like: mandatory_files {file1 file2 file3}
            match = re.search(r'mandatory_files\s+\{([^}]+)\}', content)
            if match:
                files_str = match.group(1).strip()
                mandatory_files = files_str.split()

            # Also check for mandatory_checks
            match = re.search(r'mandatory_checks\s+\{([^}]+)\}', content)
            if match:
                # These are check names, not files, but we track them
                pass

        except Exception as e:
            logger.debug(f"Could not parse exit config {config_path}: {e}")

        return mandatory_files

    def _record_result(self, name: str, result: dict):
        """Record a validation result."""
        self.results['validations'].append({
            'name': name,
            **result
        })
        status = result.get('status', 'unknown')
        if status == 'passed':
            self.results['passed'] += 1
        elif status == 'failed':
            self.results['failed'] += 1
        elif status == 'warning':
            self.results['warnings'] += 1

    def generate_report(self) -> dict:
        """Generate a validation summary report."""
        total = self.results['passed'] + self.results['failed'] + self.results['warnings']
        self.results['total'] = total
        self.results['overall_status'] = 'PASSED' if self.results['failed'] == 0 else 'FAILED'
        return self.results

    def print_report(self):
        """Print a formatted validation report."""
        report = self.generate_report()

        logger.info("")
        logger.info(f"{'═'*60}")
        logger.info(f"  Validation Report - {report['flow_type']}")
        logger.info(f"{'═'*60}")
        logger.info(f"  Status:   {report['overall_status']}")
        logger.info(f"  Passed:   {report['passed']}")
        logger.info(f"  Failed:   {report['failed']}")
        logger.info(f"  Warnings: {report['warnings']}")
        logger.info(f"  Total:    {report['total']}")
        logger.info(f"{'─'*60}")

        for v in report['validations']:
            status_icon = '[PASS]' if v.get('status') == 'passed' else '[FAIL]' if v.get('status') == 'failed' else '[SKIP]'
            logger.info(f"  {status_icon}  {v.get('name', 'unknown')}")
            if v.get('status') == 'failed' and v.get('stderr'):
                for line in v['stderr'].strip().split('\n')[:3]:
                    logger.info(f"         {line}")

        logger.info(f"{'═'*60}")
        logger.info("")


def cmd_validate(args: argparse.Namespace) -> int:
    """Run validation on current run directory."""
    run_dir = os.getcwd()

    # Detect flow type
    flow_type = os.environ.get('CBFLOW_FLOW_TYPE', '')
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if not flow_type and os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                if 'CBFLOW_FLOW_TYPE' in line:
                    flow_type = line.split('=', 1)[-1].strip().strip('"').strip("'")
                    break

    if not flow_type:
        logger.error("Cannot determine flow type. Set CBFLOW_FLOW_TYPE or run from a valid run directory.")
        return 1

    runner = ValidationRunner(run_dir=run_dir, flow_type=flow_type)

    # Determine what to validate
    validate_type = getattr(args, 'type', 'all')
    stage = getattr(args, 'stage', None)

    if validate_type == 'config' or validate_type == 'all':
        config_file = os.path.join(run_dir, 'setup', 'user_config.tcl')
        if os.path.exists(config_file):
            runner.validate_config(config_file)

    if validate_type == 'inputs' or validate_type == 'all':
        runner.validate_netlist()
        runner.validate_sdc()
        runner.validate_floorplan()

    if stage:
        runner.run_post_stage(stage)
        runner.check_exit_criteria(stage)

    if validate_type == 'exit' and stage:
        runner.check_exit_criteria(stage)

    runner.print_report()

    report = runner.generate_report()

    # Save report as JSON
    report_dir = os.path.join(run_dir, 'logs')
    os.makedirs(report_dir, exist_ok=True)
    report_file = os.path.join(report_dir, f'validation_report_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json')
    with open(report_file, 'w') as f:
        json.dump(report, f, indent=2, default=str)
    logger.info(f"Report saved to: {report_file}")

    return 0 if report['failed'] == 0 else 1


def cmd_validate_workspace(args: argparse.Namespace) -> int:
    """Validate workspace configuration."""
    workspace_dir = os.getcwd()

    # Check for workspace environment
    env_file = os.path.join(workspace_dir, '.cbflow.env')
    tcl_file = os.path.join(workspace_dir, '.cbflow.tcl')

    if not os.path.exists(env_file) and not os.path.exists(tcl_file):
        logger.error("Not in a valid workspace directory (no .cbflow.env or .cbflow.tcl found)")
        return 1

    logger.info("")
    logger.info(f"{'═'*60}")
    logger.info(f"  Workspace Validation")
    logger.info(f"{'═'*60}")

    checks_passed = 0
    checks_failed = 0

    # Check environment file
    if os.path.exists(env_file):
        logger.info(f"  [PASS]  .cbflow.env exists")
        checks_passed += 1
    else:
        logger.info(f"  [FAIL]  .cbflow.env missing")
        checks_failed += 1

    if os.path.exists(tcl_file):
        logger.info(f"  [PASS]  .cbflow.tcl exists")
        checks_passed += 1
    else:
        logger.info(f"  [FAIL]  .cbflow.tcl missing")
        checks_failed += 1

    # Parse environment
    env_vars = {}
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('export ') and '=' in line:
                    key_val = line[7:]  # Remove 'export '
                    key, val = key_val.split('=', 1)
                    env_vars[key] = val.strip('"').strip("'")

    # Check required variables
    required_vars = ['CBFLOW_PROJECT', 'CBFLOW_FLOW_TYPE', 'CBFLOW_BLOCK_NAME', 'CBFLOW_RELEASE_VERSION']
    for var in required_vars:
        if var in env_vars and env_vars[var]:
            logger.info(f"  [PASS]  {var} = {env_vars[var]}")
            checks_passed += 1
        else:
            logger.info(f"  [FAIL]  {var} not set")
            checks_failed += 1

    # Check release version exists
    release_version = env_vars.get('CBFLOW_RELEASE_VERSION', '')
    if release_version:
        core_dir = get_cbflow_core_dir()
        release_dir = os.path.join(core_dir, 'releases', release_version)
        if os.path.exists(release_dir):
            logger.info(f"  [PASS]  Release {release_version} exists")
            checks_passed += 1
        else:
            logger.info(f"  [FAIL]  Release {release_version} not found at {release_dir}")
            checks_failed += 1

    logger.info(f"")
    logger.info(f"  Results: {checks_passed} passed, {checks_failed} failed")
    logger.info(f"{'═'*60}")

    return 0 if checks_failed == 0 else 1


def create_parser() -> argparse.ArgumentParser:
    """Create argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow validate',
        description='CBFlow Validation',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow run validate                         Validate current run
  cbflow run validate --type config           Validate configuration only
  cbflow run validate --type inputs           Validate input files
  cbflow run validate --stage place1          Validate specific stage
  cbflow workspace validate                   Validate workspace setup
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Validation commands')

    # run validation
    run_parser = subparsers.add_parser('run', help='Validate run directory')
    run_parser.add_argument('--type', choices=['all', 'config', 'inputs', 'exit'],
                           default='all', help='Validation type')
    run_parser.add_argument('--stage', help='Specific stage to validate')

    # workspace validation
    subparsers.add_parser('workspace', help='Validate workspace')

    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    commands = {
        'run': cmd_validate,
        'workspace': cmd_validate_workspace,
    }

    if args.command in commands:
        return commands[args.command](args)

    return 1


if __name__ == '__main__':
    sys.exit(main())
