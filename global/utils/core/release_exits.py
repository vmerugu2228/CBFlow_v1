"""PD exit milestones per phase — read from configs only.

  * Exit order:      MILESTONE_ORDER in PD/config/flow/<ver>/release_config.tcl
  * Exits per phase: project(phase_exits) in the project config
                     (global/config/project/<proj>/<ver>/*.tcl), e.g.
                         set project(phase_exits) {
                             P0 {FP_EXIT PRO_EXIT}
                             P2 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
                         }

Single source for the schedule, the SmartGrid publish order and the default
release tag. A project or phase without a declaration raises
PhaseExitsError — there is no fallback.
"""

import os
import re

_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     os.pardir, os.pardir, os.pardir))
_TAG_RE = re.compile(r'set\s+release_tags\((\w+)\)\s+\{(.*)\}\s*$', re.M)


class PhaseExitsError(Exception):
    pass


_CACHE = {}


def _read_cached(path):
    """File text, re-read only when its mtime changes."""
    mtime = os.path.getmtime(path)
    hit = _CACHE.get(path)
    if hit and hit[0] == mtime:
        return hit[1]
    with open(path, encoding='utf-8', errors='replace') as f:
        text = f.read()
    _CACHE[path] = (mtime, text)
    return text


def _release_config_text():
    ver = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    core = os.environ.get('CBFLOW_CORE_DIR') or os.path.join(_ROOT, 'PD')
    path = os.path.join(core, 'config', 'flow', ver, 'release_config.tcl')
    try:
        return _read_cached(path)
    except OSError as e:
        raise PhaseExitsError(f'cannot read {path}: {e}')


def milestone_order():
    m = re.search(r'^\s*set\s+MILESTONE_ORDER\s+\{([^}]*)\}', _release_config_text(), re.M)
    if not m:
        raise PhaseExitsError('MILESTONE_ORDER is not set in release_config.tcl')
    return m.group(1).split()


def tapeout_milestones():
    m = re.search(r'^\s*set\s+TAPEOUT_MILESTONES\s+\{([^}]*)\}', _release_config_text(), re.M)
    if not m:
        raise PhaseExitsError('TAPEOUT_MILESTONES is not set in release_config.tcl')
    return m.group(1).split()


def release_tags():
    """{exit: {description, required_flows}} from release_tags(*)."""
    out = {}
    for m in _TAG_RE.finditer(_release_config_text()):
        body = m.group(2)
        d = re.search(r'description\s+"([^"]*)"', body)
        r = re.search(r'required_flows\s+\{([^}]*)\}', body)
        out[m.group(1)] = {'description': d.group(1) if d else '',
                           'required_flows': r.group(1).split() if r else []}
    return out


def _project_config_paths(project):
    ver = os.environ.get('PROJECT_CONFIG_VERSION', 'v1.0.0')
    paths = []
    for disc in ('global', 'PD'):
        d = os.path.join(_ROOT, disc, 'config', 'project', project, ver)
        if os.path.isdir(d):
            paths += [os.path.join(d, n) for n in sorted(os.listdir(d))
                      if n.endswith('.tcl') and not n.startswith(('mmmc_', 'schedule_'))]
    return paths


def phase_exits(project):
    """{phase: [exits]} from project(phase_exits); each list validated
    against MILESTONE_ORDER and returned in that order."""
    body = None
    for p in _project_config_paths(project):
        m = re.search(r'^\s*set\s+project\(phase_exits\)\s+\{(.*?)^\}', _read_cached(p),
                      re.M | re.S)
        if m:
            body = m.group(1)          # later files (PD overlay) win
    if body is None:
        raise PhaseExitsError(
            f'project(phase_exits) is not set for project {project} '
            f'(global/config/project/{project}/<ver>/{project}_config.tcl)')
    order = milestone_order()
    out = {}
    for m in re.finditer(r'(\S+)\s*\{([^}]*)\}', body):
        exits = m.group(2).split()
        unknown = [e for e in exits if e not in order]
        if unknown:
            raise PhaseExitsError(f'project(phase_exits) {m.group(1)}: unknown exit(s) '
                                  f'{" ".join(unknown)} (MILESTONE_ORDER: {" ".join(order)})')
        out[m.group(1)] = [e for e in order if e in exits]
    return out


def exits_for_phase(project, phase):
    pe = phase_exits(project)
    if phase not in pe:
        raise PhaseExitsError(f'project(phase_exits) for {project} has no entry for '
                              f'phase {phase} (declared: {" ".join(pe)})')
    return pe[phase]
