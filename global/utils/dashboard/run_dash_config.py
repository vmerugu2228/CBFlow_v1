"""Config accessors for the run dashboard — every value the dashboard used to
hardcode (port bands, poll cadence, flow / discipline colours, workarea
discovery) is read here from config. Missing keys raise
core.registry.RegistryError; there are no built-in defaults.

Sources:
  global/config/flow/<ver>/flow_registry.tcl
      flow(dashboard,*)            ports, poll cadence, default discipline
      flow(color,<FLOW>)           flow badge colour
      flow(discipline_color*,<D>)  discipline pill / banner branding
  project configs (core.registry.project_value)
      project(workarea_path)       run discovery roots
"""

import json
import os
import sys

_UTILS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _UTILS_DIR not in sys.path:
    sys.path.insert(0, _UTILS_DIR)

# NB: the dashboard package has its own `registry` module (run registry);
# the config registry is always imported under this alias.
from core import registry as cfg_registry          # noqa: E402
from core.registry import RegistryError             # noqa: E402,F401
from core.db import COMPLETED_STATES                # noqa: E402,F401


def flow_value(key: str) -> str:
    """Required `set flow(<key>) …` from flow_registry.tcl."""
    v = cfg_registry._registry_value(key)
    if v is None or v == '':
        raise RegistryError(f'flow({key}) is not set in flow_registry.tcl')
    return v


def flow_int(key: str) -> int:
    v = flow_value(key)
    try:
        return int(v)
    except ValueError:
        raise RegistryError(f'flow({key}) must be an integer (got {v!r})')


# ── Disciplines ─────────────────────────────────────────────────────────────

def disciplines() -> tuple:
    return tuple(cfg_registry.flow_disciplines())


def default_discipline() -> str:
    d = flow_value('dashboard,default_discipline').upper()
    if d not in disciplines():
        raise RegistryError(f'flow(dashboard,default_discipline) {d!r} is not in '
                            f'flow(disciplines) {disciplines()}')
    return d


def flow_discipline(flow_type: str) -> str:
    return cfg_registry.flow_discipline(flow_type).upper()


def discipline_branding(disc: str) -> dict:
    """{'color', 'border', 'banner'} for a discipline's pill + banner."""
    return {
        'color':  flow_value(f'discipline_color,{disc}'),
        'border': flow_value(f'discipline_color_border,{disc}'),
        'banner': flow_value(f'discipline_banner,{disc}'),
    }


# ── Flow colours ────────────────────────────────────────────────────────────

def flow_colors() -> dict:
    """{FLOW: colour} for every registered flow (flow(types))."""
    return {f: flow_value(f'color,{f}') for f in cfg_registry.flow_types()}


def unknown_flow_color() -> str:
    """Badge colour for a run whose flow_type is not registered / unknown."""
    return flow_value('dashboard,unknown_flow_color')


# ── Ports ───────────────────────────────────────────────────────────────────

def daemon_port_band(disc: str) -> tuple:
    """(base, width) of the per-user discipline daemon band."""
    return flow_int(f'dashboard,port_base,{disc}'), flow_int('dashboard,port_width')


def project_port_band(disc: str) -> tuple:
    """(base, width) of the per-project daemon band."""
    return (flow_int(f'dashboard,project_port_base,{disc}'),
            flow_int('dashboard,project_port_width'))


def run_port_range() -> tuple:
    """(min, max) inclusive for per-run foreground dashboards."""
    lo, hi = flow_int('dashboard,run_port_min'), flow_int('dashboard,run_port_max')
    if lo > hi:
        raise RegistryError(f'flow(dashboard,run_port_min) {lo} > run_port_max {hi}')
    return lo, hi


def app_port_range() -> tuple:
    """(min, max) inclusive for the project/run browser (dashboard/app.py)."""
    lo, hi = flow_int('dashboard,app_port_min'), flow_int('dashboard,app_port_max')
    if lo > hi:
        raise RegistryError(f'flow(dashboard,app_port_min) {lo} > app_port_max {hi}')
    return lo, hi


# ── Browser polling ─────────────────────────────────────────────────────────

def poll_config() -> dict:
    """Polling cadence (ms) shipped to every page as window.__cbf.poll."""
    return {
        'fixed':          flow_int('dashboard,poll_ms'),
        'active':         flow_int('dashboard,poll_active_ms'),
        'idle':           flow_int('dashboard,poll_idle_ms'),
        'errorBackoff':   flow_int('dashboard,poll_error_ms'),
        'runViewActive':  flow_int('dashboard,poll_active_ms,run_view'),
    }


def page_config_json(discipline: str) -> bytes:
    """JSON object substituted for {{CBF_CONFIG}} in the run templates."""
    b = discipline_branding(discipline)
    return json.dumps({
        'poll': poll_config(),
        'completed_states': sorted(COMPLETED_STATES),
        'discipline': discipline,
        'disc_color': b['color'],
        'disc_border': b['border'],
    }).encode()


# ── Workarea discovery ──────────────────────────────────────────────────────

def project_names() -> list:
    """Every project with an identity config under global/config/project/."""
    ver = cfg_registry.config_version('PROJECT_CONFIG_VERSION')
    base = os.path.join(cfg_registry.root(), 'global', 'config', 'project')
    if not os.path.isdir(base):
        raise RegistryError(f'project config root not found: {base}')
    return sorted(n for n in os.listdir(base)
                  if os.path.isdir(os.path.join(base, n, ver)))


def workarea_paths() -> set:
    """{(project, project(workarea_path))} for every project declaring one."""
    out = set()
    for p in project_names():
        wa = cfg_registry.project_value(p, 'workarea_path')
        if wa:
            out.add((p, wa))
    return out
