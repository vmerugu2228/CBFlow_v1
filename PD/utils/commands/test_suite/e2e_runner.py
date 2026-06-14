"""End-to-end runner: workspace create + run all + verify, per flow.

Each flow:
  1. Picks a fixture from workarea_test/
  2. Rewrites it into a temp dir with a unique run_name + test_mode=true
  3. Locates project(workarea_path)/<design> (the only place workspace create
     will accept) and cd's there
  4. Invokes `cbflow workspace create --config <rewritten.tcl>`
  5. Invokes `cbflow run all` in the created run directory
  6. Hands the run directory off to e2e_checks for verification
  7. Cleans up sandbox unless --keep / (--keep-on-fail AND failed)
"""

import os
import re
import subprocess
import sys
import time
from pathlib import Path

from . import fixtures
from .sandbox import Sandbox


def _cbflow_bin(pd_dir):
    return os.path.join(pd_dir, 'bin', 'cbflow')


def _project_workarea_path(pd_dir, project_name):
    """Read project(workarea_path) from PD/config/project/<name>/v1.0.0/<name>_config.tcl."""
    cfg = os.path.join(pd_dir, 'config', 'project', project_name, 'v1.0.0', f'{project_name}_config.tcl')
    if not os.path.exists(cfg):
        return None
    pat = re.compile(r'set\s+project\(workarea_path\)\s+"([^"]*)"')
    with open(cfg) as f:
        for line in f:
            m = pat.search(line)
            if m:
                return m.group(1)
    return None


def _resolve_run_dir(workarea_path, design_name, phase, flow_type, run_name):
    """Mirror start_run.create_run naming convention."""
    return os.path.join(os.path.abspath(workarea_path), design_name,
                        f'{phase}_run_{flow_type}_{run_name}')


def prepare_sandbox(flow, repo_root, pd_dir, workarea_test, vendor=None):
    """Pick fixture + rewrite + compute expected run directory.

    Returns (sandbox, fixture_path, cwd_for_create) or (None, error_message, None).
    """
    fixture = fixtures.pick_fixture(workarea_test, flow, vendor)
    if fixture is None:
        return None, f'no fixture in {workarea_test} for flow={flow}', None

    sandbox = Sandbox(flow, repo_root)
    rewritten, run_name = fixtures.rewrite_for_isolation(fixture, sandbox.tmp_dir)

    project_name = fixtures.parse_user_config_field(rewritten, 'project(name)') or ''
    design_name = fixtures.parse_user_config_field(rewritten, 'flow(design_name)') or ''
    phase = fixtures.parse_user_config_field(rewritten, 'project(phase)') or 'P0'
    flow_type = fixtures.parse_user_config_field(rewritten, 'flow(type)') or flow

    if not project_name or not design_name:
        sandbox.cleanup(keep=False)
        return None, f'fixture missing project(name)/flow(design_name): {fixture}', None

    workarea_path = _project_workarea_path(pd_dir, project_name)
    if not workarea_path:
        sandbox.cleanup(keep=False)
        return None, f'cannot resolve workarea_path for project={project_name}', None

    cwd_for_create = os.path.join(os.path.abspath(workarea_path), design_name)
    os.makedirs(cwd_for_create, exist_ok=True)

    run_dir = _resolve_run_dir(workarea_path, design_name, phase, flow_type, run_name)
    sandbox.set_run(run_dir, run_name)
    return sandbox, rewritten, cwd_for_create


def run_workspace_create(pd_dir, cwd, config_path, timeout, log_buf):
    """Returns (exit_code, duration_s)."""
    started = time.time()
    proc = subprocess.run(
        [_cbflow_bin(pd_dir), 'workspace', 'create', '--config', str(config_path), '--force'],
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        text=True,
    )
    log_buf.append(f'--- workspace create (cwd={cwd}) ---\n{proc.stdout}')
    return proc.returncode, time.time() - started


def run_all(pd_dir, run_dir, timeout, log_buf):
    """Returns (exit_code, duration_s)."""
    started = time.time()
    proc = subprocess.run(
        [_cbflow_bin(pd_dir), 'run', 'all'],
        cwd=run_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        text=True,
    )
    log_buf.append(f'--- run all (cwd={run_dir}) ---\n{proc.stdout}')
    return proc.returncode, time.time() - started
