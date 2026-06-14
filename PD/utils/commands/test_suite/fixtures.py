"""Locate user_config.tcl fixtures and rewrite them for an isolated test run."""

import os
import re
import uuid
from pathlib import Path


def discover_workarea_test_dir(repo_root):
    """workarea_test/ holds the curated uc_<FLOW>.tcl fixtures."""
    return os.path.join(repo_root, 'workarea_test')


def list_fixtures(workarea_test):
    """Return list of fixture files (Path objects) found under workarea_test/."""
    return sorted(Path(workarea_test).glob('uc_*.tcl'))


def pick_fixture(workarea_test, flow, vendor=None):
    """Pick the best fixture for a flow. Prefer plain uc_<FLOW>.tcl; if that's
    missing fall back to a vendor-specific variant.

    Returns None if no fixture is available.
    """
    plain = Path(workarea_test) / f'uc_{flow}.tcl'
    if plain.exists():
        return plain

    if vendor:
        variant = Path(workarea_test) / f'uc_{flow}_{vendor}.tcl'
        if variant.exists():
            return variant

    matches = sorted(Path(workarea_test).glob(f'uc_{flow}_*.tcl'))
    return matches[0] if matches else None


_RUN_NAME_RE = re.compile(r'(set\s+flow\(run_name\)\s+)"[^"]*"')
_TEST_MODE_RE = re.compile(r'(set\s+flow\(test_mode\)\s+)"[^"]*"')


def rewrite_for_isolation(fixture_path, dest_dir, run_name_suffix=None):
    """Copy a fixture into dest_dir with run_name patched to a unique value
    and test_mode forced to true.

    Returns (dest_path, run_name).
    """
    if run_name_suffix is None:
        run_name_suffix = uuid.uuid4().hex[:8]
    run_name = f'cbflowtest_{run_name_suffix}'

    src = Path(fixture_path).read_text()

    if _RUN_NAME_RE.search(src):
        src = _RUN_NAME_RE.sub(rf'\1"{run_name}"', src, count=1)
    else:
        src += f'\nset flow(run_name) "{run_name}"\n'

    if _TEST_MODE_RE.search(src):
        src = _TEST_MODE_RE.sub(r'\1"true"', src, count=1)
    else:
        src += '\nset flow(test_mode) "true"\n'

    os.makedirs(dest_dir, exist_ok=True)
    dest = Path(dest_dir) / Path(fixture_path).name
    dest.write_text(src)
    return dest, run_name


def parse_user_config_field(fixture_path, field):
    """Cheap parser for `set project(name) "x"` / `set flow(design_name) "y"`.
    `field` is like 'project(name)' or 'flow(design_name)'.
    """
    pat = re.compile(rf'set\s+{re.escape(field)}\s+"([^"]*)"')
    with open(fixture_path) as f:
        for line in f:
            m = pat.search(line)
            if m:
                return m.group(1)
    return None
