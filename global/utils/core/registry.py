"""Config-backed registry helpers — the single source for values code must
not hardcode.

  * disciplines / flow → discipline / discipline dirs
        global/config/flow/<ver>/flow_registry.tcl  flow(disciplines),
        flow(discipline,<FLOW>), flow(discipline_dir,<DISC>), flow(types)
  * config versions        launcher env vars (FLOW_CONFIG_VERSION,
                           PROJECT_CONFIG_VERSION, TECH_CONFIG_VERSION,
                           UTILITIES_VERSION) — no built-in default
  * release directory      <release,path>/<phase>/<block>/<FLOW>/<tag>
  * project config files   global + every discipline overlay of the project

Every accessor raises RegistryError when the config it reads is missing —
there are no fallbacks.
"""

import os
import re

_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     os.pardir, os.pardir, os.pardir))
_CACHE = {}


class RegistryError(Exception):
    pass


def root() -> str:
    return os.environ.get('CBFLOW_ROOT') or _ROOT


def config_version(var: str) -> str:
    """Required version env var (set by the launcher)."""
    v = os.environ.get(var, '').strip()
    if not v:
        raise RegistryError(f'{var} is not set (exported by the cbflow launcher)')
    return v


def _read(path: str) -> str:
    try:
        mtime = os.path.getmtime(path)
    except OSError as e:
        raise RegistryError(f'cannot read {path}: {e}')
    hit = _CACHE.get(path)
    if hit and hit[0] == mtime:
        return hit[1]
    with open(path, encoding='utf-8', errors='replace') as f:
        text = f.read()
    _CACHE[path] = (mtime, text)
    return text


def flow_registry_path() -> str:
    return os.path.join(root(), 'global', 'config', 'flow',
                        config_version('FLOW_CONFIG_VERSION'), 'flow_registry.tcl')


def _registry_value(key: str):
    """Value of `set flow(<key>) …` in flow_registry.tcl, or None."""
    text = _read(flow_registry_path())
    m = re.search(r'^\s*set\s+flow\(' + re.escape(key) + r'\)\s+(?:"([^"]*)"|\{([^}]*)\}|(\S+))',
                  text, re.M)
    if not m:
        return None
    return next(g for g in m.groups() if g is not None)


def flow_disciplines() -> list:
    v = _registry_value('disciplines')
    if v is None:
        raise RegistryError('flow(disciplines) is not set in flow_registry.tcl')
    return v.split()


def flow_types() -> list:
    v = _registry_value('types')
    if v is None:
        raise RegistryError('flow(types) is not set in flow_registry.tcl')
    return v.split()


def flow_discipline(flow_type: str) -> str:
    v = _registry_value(f'discipline,{flow_type}')
    if not v:
        raise RegistryError(f'flow(discipline,{flow_type}) is not set in flow_registry.tcl')
    return v


def discipline_dir(disc: str) -> str:
    """Absolute $CBFLOW_ROOT/<flow(discipline_dir,<disc>)>."""
    v = _registry_value(f'discipline_dir,{disc}')
    if not v:
        raise RegistryError(f'flow(discipline_dir,{disc}) is not set in flow_registry.tcl')
    return os.path.join(root(), v)


def discipline_env_var(disc: str) -> str:
    """Env var naming a discipline root: CBFLOW_CORE_DIR for PD (historic
    name), CBFLOW_<DISC>_DIR for the others."""
    return 'CBFLOW_CORE_DIR' if disc == 'PD' else f'CBFLOW_{disc}_DIR'


def release_dir(release_path: str, phase: str, block: str, flow: str, tag: str) -> str:
    """The single definition of the release layout."""
    for name, val in (('release_path', release_path), ('phase', phase), ('block', block),
                      ('flow', flow), ('tag', tag)):
        if not val:
            raise RegistryError(f'release_dir: {name} is empty')
    return os.path.join(release_path, phase, block, flow, tag)


def project_config_paths(project: str) -> list:
    """Every project config file, global first then each discipline overlay
    (later files win on duplicate keys). Excludes generated MMMC and
    schedule files."""
    ver = config_version('PROJECT_CONFIG_VERSION')
    dirs = [os.path.join(root(), 'global', 'config', 'project', project, ver)]
    for disc in flow_disciplines():
        dirs.append(os.path.join(discipline_dir(disc), 'config', 'project', project, ver))
    out = []
    for d in dirs:
        if os.path.isdir(d):
            out += [os.path.join(d, n) for n in sorted(os.listdir(d))
                    if n.endswith('.tcl') and not n.startswith(('mmmc_', 'schedule_'))]
    if not out:
        raise RegistryError(f'no project config found for {project} (global/config/project/{project}/{ver})')
    return out


def project_value(project: str, key: str):
    """Last `set project(<key>) …` across the project config files, or None.
    Braced values may span lines."""
    val = None
    for p in project_config_paths(project):
        text = _read(p)
        for m in re.finditer(r'^\s*set\s+project\(' + re.escape(key) + r'\)\s+', text, re.M):
            rest = text[m.end():]
            if rest.startswith('"'):
                val = rest[1:rest.index('"', 1)]
            elif rest.startswith('{'):
                depth, i = 0, 0
                for i, ch in enumerate(rest):
                    depth += {'{': 1, '}': -1}.get(ch, 0)
                    if depth == 0:
                        break
                val = rest[1:i]
            else:
                val = rest.split(None, 1)[0] if rest.strip() else ''
    return val


def require_project_value(project: str, key: str) -> str:
    v = project_value(project, key)
    if v is None or v == '':
        raise RegistryError(f'project({key}) is not set for {project}')
    return v
