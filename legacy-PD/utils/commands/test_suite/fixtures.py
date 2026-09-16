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

    When `project` is set (e.g. 'bumblebee', 'denali'), only fixtures whose
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


# ── Mode classification + multi-fixture picker ────────────────────────────
# Downstream flows (STA, LEC, ECO, PV, EMIR, CLP, POPT) consume outputs from
# upstream flows. CBflow supports three input mechanisms per CLAUDE.md:
#   1. `direct`      — explicit paths + variables (netlist, def, sdc, spef …)
#   2. `from_run`    — reads output_manifest.tcl of a prior run directory
#   3. `release_tag` — reads from a release directory pinned by tag
# `pick_fixtures` (plural) returns every fixture that matches (flow, project)
# so the e2e runner can iterate all input modes for full-matrix coverage.

_FROM_RUN_RE = re.compile(r'^\s*set\s+\w+\(input,from_run\)', re.M)
_RELEASE_TAG_RE = re.compile(r'^\s*set\s+\w+\(input,\w+_release_tag\)', re.M)


def classify_fixture_mode(path):
    """Classify a fixture by its input-handoff style.

    Returns one of: 'from_run', 'release_tag', 'direct'. `direct` is the
    default — used both when explicit `input,<file>` keys are present and
    when the fixture omits inputs entirely (upstream flows like SYNTH).
    """
    try:
        text = Path(path).read_text(errors='replace')
    except OSError:
        return 'direct'
    if _FROM_RUN_RE.search(text):
        return 'from_run'
    if _RELEASE_TAG_RE.search(text):
        return 'release_tag'
    return 'direct'


def pick_fixtures(workarea_test, flow, vendor=None, project=None):
    """Return ALL fixtures for (flow, project) so the runner can iterate
    every input-mode variant.

    Each returned entry is (fixture_path, mode_tag) where mode_tag is
    'direct' / 'from_run' / 'release_tag'. When two fixtures share the
    same mode, only the first (glob-sorted) one is kept — no point
    running two "direct" variants for the same (project, flow).

    Returns [] when no fixtures match.
    """
    seen_modes = set()
    out = []

    def _push(cand):
        if not _fixture_matches_flow(cand, flow):
            return
        if project and parse_user_config_field(cand, 'project(name)') != project:
            return
        mode = classify_fixture_mode(cand)
        if mode in seen_modes:
            return
        seen_modes.add(mode)
        out.append((cand, mode))

    # 1. Explicit project-tagged fixtures.
    if project:
        for cand in sorted(Path(workarea_test).glob(f'uc_{flow}_{project}_*.tcl')):
            _push(cand)

    # 2. Plain uc_{flow}.tcl.
    plain = Path(workarea_test) / f'uc_{flow}.tcl'
    if plain.exists():
        _push(plain)

    # 3. Vendor variant when unfiltered by project.
    if vendor and not project:
        variant = Path(workarea_test) / f'uc_{flow}_{vendor}.tcl'
        if variant.exists():
            _push(variant)

    # 4. Any uc_{flow}_*.tcl variant (from_run / release_tag are the
    #    typical suffixes; also picks up per-tool variants).
    for cand in sorted(Path(workarea_test).glob(f'uc_{flow}_*.tcl')):
        _push(cand)

    return out


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
