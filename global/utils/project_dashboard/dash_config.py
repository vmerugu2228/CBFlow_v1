"""Config reads for SmartGrid — one place, no hardcoded fallbacks.

Every value comes from core.registry:
  * project config      project(<key>) across global + discipline overlays
  * flow registry       flow(smartgrid,*), flow(dashboard,*), flow(metric,*),
                        flow(discipline_color,*)
  * release config      release(marker,*), release(file,*), release(dir,*),
                        flow_input_handshake(*,<input>)

Required keys raise registry.RegistryError with the key name; optional
display keys (byline, contact) return '' so the page renders nothing.
"""

import os
import re
import sys

_UTILS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _UTILS_DIR not in sys.path:
    sys.path.insert(0, _UTILS_DIR)

from core import registry                      # noqa: E402

RegistryError = registry.RegistryError


# ─── Project config ─────────────────────────────────────────────────────────

def has_project_config(project):
    """True when the project has config files. Launcher / registry problems
    (version env var unset, flow(disciplines) missing) still raise."""
    registry.config_version('PROJECT_CONFIG_VERSION')
    registry.flow_disciplines()
    try:
        registry.project_config_paths(project)
        return True
    except RegistryError:
        return False


def project_value(project, key):
    """project(<key>) or None (also None for a project without config, e.g.
    a master_projects.json entry that has no project directory yet)."""
    if not has_project_config(project):
        return None
    return registry.project_value(project, key)


def require_project_value(project, key):
    return registry.require_project_value(project, key)


def project_info(project):
    """Header values from the project config (None when unset)."""
    info = {k: project_value(project, k) for k in (
        'tapeout_date', 'current_phase', 'technology', 'metal_stack',
        'lib_config_tag', 'cbflow_release')}
    info['developed_by'] = project_value(project, 'dashboard,developed_by')
    phases = project_value(project, 'phases')
    if phases is not None:
        info['phases'] = registry.tcl_list(phases)
    return info


def parse_hierarchy(body):
    """project(design_hierarchy) body → {block: {level, parent, children,
    description}} in declaration order."""
    out, i = {}, 0
    blk_re = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*\{')
    while True:
        mb = blk_re.search(body or '', i)
        if not mb:
            break
        depth, j = 1, mb.end()
        while j < len(body) and depth:
            depth += {'{': 1, '}': -1}.get(body[j], 0)
            j += 1
        entry = body[mb.end():j - 1]
        spec = {}
        for k in ('level', 'parent', 'description'):
            mk = re.search(r'\b' + k + r'\s+"([^"]*)"', entry)
            spec[k] = mk.group(1) if mk else ''
        mc = re.search(r'\bchildren\s+\{([^}]*)\}', entry)
        spec['children'] = mc.group(1).split() if mc else []
        out[mb.group(1)] = spec
        i = j
    return out


def hierarchy(project):
    """{block: spec} from project(design_hierarchy); {} when unset."""
    return parse_hierarchy(project_value(project, 'design_hierarchy') or '')


def header(project):
    """{'org', 'developed_by', 'contact_email'} for the page header — each ''
    when the project does not set it (nothing is rendered then)."""
    return {
        'org': project_value(project, 'dashboard,org') or '',
        'developed_by': project_value(project, 'dashboard,developed_by') or '',
        'contact_email': project_value(project, 'dashboard,contact_email') or '',
    }


def expected_flows(project):
    """Every flow the project enables, across all disciplines
    (master_projects.json enabled_flows_by_discipline), in flow(disciplines)
    order."""
    cmds = os.path.join(_UTILS_DIR, 'commands')
    if cmds not in sys.path:
        sys.path.insert(0, cmds)
    from tcl_config_parser import get_project_disciplines, get_project_enabled_flows
    enabled = set(get_project_disciplines(project))
    out = []
    for disc in registry.flow_disciplines():
        if disc in enabled:
            out += [f for f in get_project_enabled_flows(project, disc) if f not in out]
    return out


# ─── Flow registry ──────────────────────────────────────────────────────────

_SLACK_RE = re.compile(r'(\b|_)(WNS|TNS)\b', re.I)


def fmt_slack(name, value):
    """WNS / TNS (a metric / check whose name or description names WNS or TNS) with flow(report,slack_digits)
    decimals; other metrics and non-numeric values unchanged."""
    if value is None or not _SLACK_RE.search(name or ''):
        return value
    try:
        f = float(value)
    except (TypeError, ValueError):
        return value
    return f'{f:.{int(registry.require_flow_value("report,slack_digits"))}f}'


def waiver_policy():
    """array set waiver_policy { key value ... } from the exit config's
    waiver_config.tcl — {key: value} (strings)."""
    path = os.path.join(registry.root(), 'global', 'config', 'exit',
                        registry.config_version('FLOW_CONFIG_VERSION'), 'waiver_config.tcl')
    with open(path, encoding='utf-8') as f:
        text = f.read()
    m = re.search(r'array\s+set\s+waiver_policy\s*\{(.*?)^\}', text, re.S | re.M)
    if not m:
        raise registry.RegistryError(f'waiver_policy is not set in {path}')
    out = {}
    for line in m.group(1).splitlines():
        line = line.split('#', 1)[0].strip()
        if line:
            k, _, v = line.partition(' ')
            out[k] = v.strip().strip('"')
    return out


def smartgrid(key):
    """flow(smartgrid,<key>) — required."""
    return registry.require_flow_value(f'smartgrid,{key}')


def discipline_colors():
    """{discipline: colour} for every flow(disciplines) entry."""
    return {d: registry.require_flow_value(f'discipline_color,{d}')
            for d in registry.flow_disciplines()}


def discipline_css():
    """CSS for the discipline chips / tiles / cards, from the colours."""
    rules = []
    for d, c in discipline_colors().items():
        k = d.lower()
        rules.append(f'.disc-chip.disc-{k}{{background:{c}}}'
                     f'.sg-tile-disc.disc-{k}{{--tile-accent:{c}}}'
                     f'.disc-card.{k}{{--disc-accent:{c}}}')
    return '<style>' + ''.join(rules) + '</style>'


def top_metrics(disc):
    """flow(dashboard,top_metrics,<DISC>) as a list; [] when the discipline
    declares none."""
    v = registry.flow_value(f'dashboard,top_metrics,{disc}')
    return registry.tcl_list(v) if v else []


def metric_polarities():
    """{metric: 'higher_better' | 'lower_better'} from flow(metric,*,polarity)."""
    out = {}
    for k, v in registry.flow_values('metric,').items():
        if k.endswith(',polarity'):
            if v not in ('higher_better', 'lower_better'):
                raise RegistryError(f'flow(metric,{k}) = {v!r}: expected '
                                    'higher_better or lower_better')
            out[k[:-len(',polarity')]] = v
    return out


def stage_tables():
    """[(title, [categories])] from flow(dashboard,stage_tables)."""
    items = registry.tcl_list(registry.require_flow_value('dashboard,stage_tables'))
    return [(items[i], registry.tcl_list(items[i + 1])) for i in range(0, len(items) - 1, 2)]


def category_tabs():
    """{metric category: tab} from flow(dashboard,category_tab,*)."""
    return registry.flow_values('dashboard,category_tab,')


def timing_name_tokens():
    return registry.tcl_list(registry.require_flow_value('dashboard,timing_name_tokens'))


def lef_node_type():
    return registry.require_flow_value('dashboard,lef_node_type')


# ─── Release config ─────────────────────────────────────────────────────────

def release_name(key):
    """release(<key>) — a marker / file / dir name inside a release tag dir."""
    return registry.require_release_value(key)


def release_names(key):
    """release(<key>) as a list (e.g. file,timing_snapshot candidates)."""
    return registry.tcl_list(registry.require_release_value(key))


def handshake_location(input_type):
    """(category, filename_pattern) shared by every flow_input_handshake
    entry of `input_type`; error when none or they disagree."""
    entries = registry.handshake_entries(input_type)
    if not entries:
        raise RegistryError(f'no flow_input_handshake(*,{input_type}) in release_config.tcl')
    locs = {tuple(v[1:3]) for v in entries.values() if len(v) >= 3}
    if len(locs) != 1:
        raise RegistryError(f'flow_input_handshake(*,{input_type}) entries disagree on '
                            f'category/filename: {sorted(locs)}')
    return next(iter(locs))
