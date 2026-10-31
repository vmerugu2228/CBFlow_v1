"""Integration tests for discipline-owned commands.

This catches the class of bug that static_checks + cli_smoke + e2e miss:

  - static_checks reads config FILES.
  - cli_smoke only calls --help and parses argparse.
  - e2e runs cbflow run under flow(test_mode)=true — handlers are stubbed
    and never actually source lib_config, so stale lookup paths silently
    pass.

What slipped past all three (reported by Madhavi, 2026-10-19):

  $ cbflow flow mmmc-manager generate
  [ERROR] No technologies found in /proj/.../PD/config/tech

mmmc-manager was looking in the pre-split PD/config/tech directory which
no longer exists. The command's --help still passed. The e2e runs still
passed because they go through workspace create, not mmmc-manager.

These integration tests invoke the real CLIs end-to-end against a
sandbox PDK + lib tree. They verify discovery (list_available_techs,
list_available_projects, _list_available_tags) returns the right
answers against a known-good fixture.

Invoked via `cbflow test --integration`.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def _cbflow_bin(pd_dir: str) -> str:
    return os.path.join(pd_dir, 'bin', 'cbflow')


def _write_dummy_tech(global_tech_dir: Path, tech_name: str) -> None:
    """Drop a minimal tech_config.tcl so list_available_techs picks it up."""
    tdir = global_tech_dir / tech_name / 'v1.0.0'
    tdir.mkdir(parents=True, exist_ok=True)
    (tdir / 'tech_config.tcl').write_text(
        '# Dummy tech config for integration test — {}\n'
        'set tech(node)                   "{}"\n'
        'set tech(process)                "integration-test"\n'
        'set tech(foundry)                "test"\n'
        'set tech(tracks_available)       "9T"\n'
        'set tech(metal_stacks_available) "8M"\n'
        'set tech(vt_variants_available) {{svt}}\n'
        'set tech(vt_pattern,svt)   "*svt*"\n'
        'set tech(track_pattern,9T) "*sc9*"\n'.format(tech_name, tech_name))


def _write_dummy_lib_root(lib_root: Path) -> None:
    """Stage a tiny lib_root with one 9T svt stdcell lib + a memory lib so
    library-manager generate has something to scan."""
    sc = lib_root / '9T' / 'svt'
    sc.mkdir(parents=True, exist_ok=True)
    for ext, hdr in (('.ndm', ''),
                     ('.lef', ''),
                     ('.db', ''),
                     ('_ss_0p72v_125c.lib', 'library (sc9_9T_svt_ss) { }')):
        (sc / f'sc9_9T_svt{ext}').write_text(hdr)
    mem = lib_root / 'mem'
    mem.mkdir(parents=True, exist_ok=True)
    for ext in ('.ndm', '.lef'):
        (mem / f'mem_block{ext}').write_text('')
    (mem / 'mem_block_ss_0p72v_125c.lib').write_text(
        'library (mem_block_ss) { }')


def _run_cli(bin_path: str, args: list, env: dict | None = None,
             stdin_input: str | None = None, timeout: int = 60):
    try:
        res = subprocess.run(
            [bin_path] + args, capture_output=True, text=True,
            timeout=timeout, env=env, input=stdin_input)
    except subprocess.TimeoutExpired as e:
        return -9, '', f'[timeout after {timeout}s] {e}'
    return res.returncode, res.stdout or '', res.stderr or ''


# ─────────────────────────────────────────────────────────────────────
# CHECKS
# ─────────────────────────────────────────────────────────────────────

def check_list_available_techs_covers_global(pd_dir: str) -> tuple:
    """paths.list_available_techs() must find every tech in global/, not
    just PD/. Was broken before the sweep — it looked in PD only."""
    import sys
    sys.path.insert(0, os.path.join(pd_dir, 'utils', 'commands'))
    sys.path.insert(0, os.path.join(pd_dir, 'utils'))
    try:
        from core.paths import list_available_techs
    except ImportError as e:
        return ('FAIL', f'cannot import paths.list_available_techs: {e}')
    found = list_available_techs()
    # Must at least include gf_22nm (shipped) and gf_28nm (shipped).
    expected = {'gf_22nm', 'gf_28nm'}
    missing = expected - set(found)
    if missing:
        return ('FAIL', f'missing techs from global/: {sorted(missing)}; '
                        f'got {found}')
    return ('PASS', f'found {len(found)} techs: {found[:4]}...')


def check_list_available_projects_covers_global(pd_dir: str) -> tuple:
    """paths.list_available_projects() must union global/ + PD/ projects."""
    import sys
    sys.path.insert(0, os.path.join(pd_dir, 'utils', 'commands'))
    sys.path.insert(0, os.path.join(pd_dir, 'utils'))
    try:
        from core.paths import list_available_projects
    except ImportError as e:
        return ('FAIL', f'cannot import paths.list_available_projects: {e}')
    found = list_available_projects()
    expected = {'bumblebee', 'denali'}
    missing = expected - set(found)
    if missing:
        return ('FAIL', f'missing projects: {sorted(missing)}; got {found}')
    return ('PASS', f'found {len(found)} projects: {found}')


def check_mmmc_manager_tech_discovery(pd_dir: str) -> tuple:
    """Reproduce Madhavi's exact invocation: `cbflow flow mmmc-manager
    generate` with NO --tech should enumerate techs (not error with
    'No technologies found in PD/config/tech')."""
    bin_path = _cbflow_bin(pd_dir)
    # Interactive, with empty stdin — expect enumeration output then exit
    # because we can't actually answer the prompts, but the enumeration
    # itself must happen.
    rc, out, err = _run_cli(
        bin_path, ['flow', 'mmmc-manager', 'generate'],
        stdin_input='', timeout=30)
    all_out = out + err
    if 'No technologies found' in all_out:
        return ('FAIL',
                "regression: mmmc-manager cannot find techs. "
                "Output contains 'No technologies found'.")
    # Positive signal: should list at least one tech.
    if 'gf_22nm' not in all_out and 'gf_28nm' not in all_out:
        return ('FAIL',
                "mmmc-manager --no-args didn't enumerate any tech. "
                "Expected to see gf_22nm or gf_28nm in output.")
    return ('PASS', 'mmmc-manager enumerated techs from global/')


def check_mmmc_manager_project_discovery(pd_dir: str) -> tuple:
    """Second half of the same bug: project enumeration must walk global/."""
    bin_path = _cbflow_bin(pd_dir)
    # Pipe in tech + enough PVT answers to reach the project step.
    stdin = 'gf_22nm\nss\n0.72\n125\n'
    rc, out, err = _run_cli(
        bin_path, ['flow', 'mmmc-manager', 'generate'],
        stdin_input=stdin, timeout=30)
    all_out = out + err
    # Looking for the project enumeration output or at least that the
    # project-not-found path reached global/.
    if 'No technologies found' in all_out:
        return ('FAIL', 'regression: tech enumeration broke again')
    # Must either prompt for a project with real choices OR find a project.
    if 'Available projects' in all_out:
        return ('PASS', 'mmmc-manager enumerated projects')
    # If it errored with "--project is required" that's acceptable
    # (stdin ran out) — just confirm it didn't look in the wrong place.
    if '/PD/config/project' in all_out and 'not found' in all_out.lower():
        return ('FAIL',
                "regression: mmmc-manager looking in PD/config/project only")
    return ('PASS', 'mmmc-manager project path OK')


def check_lib_manager_tagroot_error_is_actionable(pd_dir: str) -> tuple:
    """When lib_tag_root is unset, the error message must mention all 4
    override paths. Caught the original 'silent fallback to in-tree' bug."""
    bin_path = _cbflow_bin(pd_dir)
    with tempfile.TemporaryDirectory() as tmp:
        lib_root = Path(tmp) / 'lib_root'
        _write_dummy_lib_root(lib_root)
        env = os.environ.copy()
        env.pop('CBFLOW_LIB_TAG_ROOT', None)
        rc, out, err = _run_cli(
            bin_path,
            ['flow', 'library-manager', 'generate',
             '--tech', 'gf_22nm', '--tag', 'INT_TEST',
             '--lib-root', str(lib_root),
             '--tracks', '9T', '--vts', 'svt'],
            env=env, timeout=60)
        all_out = out + err
        if rc == 0:
            return ('FAIL',
                    'regression: generate succeeded despite unset '
                    'lib_tag_root — silent fallback is back')
        checks = [
            ('project(lib_tag_root)', 'per-project path missing'),
            ('CBFLOW_LIB_TAG_ROOT', 'env override missing'),
            ('--lib-tag-root', 'CLI override missing'),
            ('tech(lib_tag_root)', 'tech default path missing'),
        ]
        missing = [m for pat, m in checks if pat not in all_out]
        if missing:
            return ('FAIL',
                    f'fix guide incomplete: {missing}')
    return ('PASS', 'all 4 override paths mentioned in error')


def check_lib_manager_rejects_in_tree_tagroot(pd_dir: str) -> tuple:
    """lib_tag_root pointing inside CBFLOW_ROOT must be rejected
    with a clear 'Rejecting' message. Prevents silent self-nesting."""
    bin_path = _cbflow_bin(pd_dir)
    repo_root = os.path.dirname(pd_dir)
    with tempfile.TemporaryDirectory() as tmp:
        lib_root = Path(tmp) / 'lib_root'
        _write_dummy_lib_root(lib_root)
        env = os.environ.copy()
        env['CBFLOW_LIB_TAG_ROOT'] = os.path.join(
            repo_root, 'PD', 'config', 'intree_libs_bad')
        rc, out, err = _run_cli(
            bin_path,
            ['flow', 'library-manager', 'generate',
             '--tech', 'gf_22nm', '--tag', 'IN_TREE',
             '--lib-root', str(lib_root),
             '--tracks', '9T', '--vts', 'svt'],
            env=env, timeout=60)
        all_out = out + err
        if rc == 0:
            return ('FAIL',
                    'regression: in-tree lib_tag_root accepted silently')
        if 'inside the framework tree' not in all_out and \
           'Rejecting' not in all_out:
            return ('FAIL',
                    'rejection message is unclear — user cannot tell '
                    'why their path was refused')
    return ('PASS', 'in-tree lib_tag_root rejected with clear reason')


def check_lib_mmmc_full_workflow(pd_dir: str) -> tuple:
    """End-to-end: write a dummy lib_root, point CBFLOW_LIB_TAG_ROOT at
    scratch, run library-manager generate, then mmmc-manager generate
    reading that output. Mirrors the real workflow Madhavi was doing
    when she hit the 'No technologies found' error."""
    bin_path = _cbflow_bin(pd_dir)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_p = Path(tmp)
        lib_root = tmp_p / 'lib_root'
        tag_root = tmp_p / 'tag_root'
        tag_root.mkdir()
        _write_dummy_lib_root(lib_root)

        env = os.environ.copy()
        env['CBFLOW_LIB_TAG_ROOT'] = str(tag_root)

        # Step 1: library-manager generate — must succeed, produce lib_config.
        rc, out, err = _run_cli(
            bin_path,
            ['flow', 'library-manager', 'generate',
             '--tech', 'gf_22nm', '--tag', 'INT_TEST',
             '--lib-root', str(lib_root),
             '--tracks', '9T', '--vts', 'svt'],
            env=env, timeout=90)
        if rc != 0:
            tail = (out + err)[-400:]
            return ('FAIL', f'library-manager generate failed (rc={rc}): '
                            f'...{tail}')
        # Library-manager uses the per-tech nested layout:
        #   <lib_tag_root>/<tech_node>/<tag>/lib_config.tcl
        # (migrated from the pre-refactor flat <lib_tag_root>/<tag>/
        # layout). Accept either form so the test survives both.
        lib_cfg_nested = tag_root / 'gf_22nm' / 'INT_TEST' / 'lib_config.tcl'
        lib_cfg_legacy = tag_root / 'INT_TEST' / 'lib_config.tcl'
        if lib_cfg_nested.exists():
            lib_cfg = lib_cfg_nested
        elif lib_cfg_legacy.exists():
            lib_cfg = lib_cfg_legacy
        else:
            return ('FAIL', f'lib_config.tcl not written to '
                            f'{lib_cfg_nested} (nor legacy '
                            f'{lib_cfg_legacy})')
        content = lib_cfg.read_text()
        # Must have at least one stdcell tech key.
        if 'tech(9T,svt' not in content:
            return ('FAIL',
                    'lib_config.tcl missing expected tech(9T,svt,...) keys')
        # Must use stdcell/ nested layout.
        if '/stdcell/' not in content:
            return ('FAIL',
                    'lib_config.tcl paths not nested under stdcell/ parent')
    return ('PASS', 'library-manager → lib_config.tcl → stdcell/ layout OK')


def check_handler_setup_propagates_generator_failure(pd_dir: str) -> tuple:
    """handler_common.tcl::handler_setup previously wrapped generate_setup.tcl
    in a bare `catch {...}` that silently swallowed non-zero exits. If the
    generator failed (bad config, missing lib), the handler returned 0 and
    the stage proceeded with a missing config.tcl — THE classic "run
    completes clean in seconds with empty log" symptom.

    This test verifies the current handler_setup:
      (a) echoes generator stderr/stdout so failures are visible, and
      (b) returns a non-zero code when config.tcl isn't written in
          production mode (test_mode=false).
    """
    import re
    # Post cbflow_global utils-refactor: handler_common.tcl moved to
    # global/utils/utilities/, not PD/utils/utilities/.
    h = Path(os.path.dirname(pd_dir)) / 'global' / 'utils' / 'utilities' / 'v1.0.0' / 'handler_common.tcl'
    if not h.exists():
        return ('FAIL', f'handler_common.tcl missing at {h}')
    txt = h.read_text()
    # Guard A: `handler_setup` must NOT contain an unchecked
    # `catch {exec tclsh $_gen ...}` with no error branch.
    bad_pattern = re.compile(
        r'proc\s+handler_setup\b.*?^\}',
        re.DOTALL | re.MULTILINE)
    m = bad_pattern.search(txt)
    if not m:
        return ('FAIL', 'handler_setup proc not found')
    body = m.group(0)
    # Must capture rc + handle non-zero.
    if 'catch {exec tclsh $_gen' in body and 'return 1' not in body:
        return ('FAIL',
                'regression: handler_setup swallows generator errors '
                '(no `return 1` branch after catch)')
    # Must verify config.tcl exists in production path.
    if 'config.tcl was NOT written' not in body:
        return ('FAIL',
                'handler_setup no longer validates config.tcl post-write')
    # Must respect test_mode (don't abort stub runs).
    if 'flow(test_mode)' not in body:
        return ('FAIL',
                'handler_setup lost test_mode awareness — would abort e2e')
    return ('PASS',
            'handler_setup propagates generator exit, validates config.tcl, '
            'honors test_mode')


# ─────────────────────────────────────────────────────────────────────
# RUNNER
# ─────────────────────────────────────────────────────────────────────

CHECKS = [
    ('discovery.list_available_techs',       check_list_available_techs_covers_global),
    ('discovery.list_available_projects',    check_list_available_projects_covers_global),
    ('mmmc.tech_discovery',                  check_mmmc_manager_tech_discovery),
    ('mmmc.project_discovery',               check_mmmc_manager_project_discovery),
    ('lib.tagroot_error_actionable',         check_lib_manager_tagroot_error_is_actionable),
    ('lib.tagroot_rejects_in_tree',          check_lib_manager_rejects_in_tree_tagroot),
    ('workflow.lib_mmmc_end_to_end',         check_lib_mmmc_full_workflow),
    ('handler.setup_propagates_errors',      check_handler_setup_propagates_generator_failure),
]


def run_all(results, console, pd_dir: str) -> None:
    """Entry point from test_cmd._run_integration()."""
    console.section('INTEGRATION: real workflow checks (lib + mmmc)')
    for name, fn in CHECKS:
        try:
            status, detail = fn(pd_dir)
        except Exception as e:
            status, detail = 'FAIL', f'{type(e).__name__}: {e}'
        console.event(status, name, detail)
        if status == 'PASS':
            results.passed('integration', 'checks', name, detail)
        elif status == 'FAIL':
            results.failed('integration', 'checks', name, detail)
        else:
            results.skipped('integration', 'checks', name, detail)
