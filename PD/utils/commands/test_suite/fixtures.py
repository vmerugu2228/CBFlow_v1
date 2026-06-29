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


def _fixture_matches_flow(path, flow):
    """True iff the fixture's `flow(type)` field equals `flow`.

    Filename-only globbing can't distinguish `uc_SYNTH_*.tcl` from
    `uc_SYNTH_PNR.tcl` — both names match `SYNTH_*`. The authoritative
    answer is the `set flow(type) "..."` line inside the file.
    """
    declared = parse_user_config_field(path, 'flow(type)')
    return declared == flow


def pick_fixture(workarea_test, flow, vendor=None, project=None):
    """Pick the best fixture for a flow.

    When `project` is set (e.g. 'ravendrive', 'denali'), only fixtures whose
    `project(name)` parses to that project are considered — this is how the
    e2e runner iterates per-project so each project's tool stack gets
    exercised end-to-end.

    Every returned fixture is verified to declare the right `flow(type)`,
    not just match the filename glob (which would treat `uc_SYNTH_PNR.tcl`
    as a SYNTH fixture).

    Selection order when project is set:
      1. uc_{flow}_{project}_<anything>.tcl    (explicit project tag in name)
      2. uc_{flow}_*.tcl                       (any fixture for the flow whose
                                                contents declare this project)
      3. uc_{flow}.tcl                         (project-agnostic plain fixture
                                                whose contents declare this project)

    Without `project`, falls back to the original behavior: prefer plain
    uc_{flow}.tcl, then a vendor variant, then any matching variant.

    Returns None if no fixture matches.
    """
    def _ok(p):
        return p.exists() and _fixture_matches_flow(p, flow)

    if project:
        # 1. Explicit project-tagged fixture (filename + flow + project match).
        for cand in sorted(Path(workarea_test).glob(f'uc_{flow}_{project}_*.tcl')):
            if _ok(cand) and parse_user_config_field(cand, 'project(name)') == project:
                return cand
        # 2. Any uc_{flow}_*.tcl whose contents declare the right project + flow.
        for cand in sorted(Path(workarea_test).glob(f'uc_{flow}_*.tcl')):
            if _ok(cand) and parse_user_config_field(cand, 'project(name)') == project:
                return cand
        # 3. Plain uc_{flow}.tcl, if it declares the right project + flow.
        plain = Path(workarea_test) / f'uc_{flow}.tcl'
        if _ok(plain) and parse_user_config_field(plain, 'project(name)') == project:
            return plain
        return None

    # Original (project-agnostic) selection.
    plain = Path(workarea_test) / f'uc_{flow}.tcl'
    if _ok(plain):
        return plain

    if vendor:
        variant = Path(workarea_test) / f'uc_{flow}_{vendor}.tcl'
        if _ok(variant):
            return variant

    for cand in sorted(Path(workarea_test).glob(f'uc_{flow}_*.tcl')):
        if _ok(cand):
            return cand
    return None


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
