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


def _tcl_word(rest: str) -> str:
    """The Tcl word at the start of `rest`: "quoted", {braced} (nested braces
    and multiple lines allowed; outer braces stripped) or a bare word."""
    if rest.startswith('"'):
        end = rest.find('"', 1)
        return rest[1:end] if end > 0 else rest[1:]
    if rest.startswith('{'):
        depth = 0
        for i, ch in enumerate(rest):
            depth += {'{': 1, '}': -1}.get(ch, 0)
            if depth == 0:
                return rest[1:i]
        return rest[1:]
    return rest.split(None, 1)[0] if rest.strip() else ''


def _array_values(text: str, array: str, key_re: str):
    """[(key, value)] for every `set <array>(<key>) <word>` whose key matches
    key_re, in file order."""
    out = []
    for m in re.finditer(r'^\s*set\s+' + re.escape(array) + r'\((' + key_re + r')\)[ \t]+',
                         text, re.M):
        out.append((m.group(1), _tcl_word(text[m.end():])))
    return out


def tcl_list(value: str) -> list:
    """Split a Tcl list string into its elements ({a b} and "a b" kept whole)."""
    out, i, s = [], 0, value or ''
    while i < len(s):
        if s[i].isspace():
            i += 1
            continue
        if s[i] in '{"':
            word = _tcl_word(s[i:])
            out.append(word)
            if s[i] == '"':
                i += len(word) + 2
            else:
                depth, j = 0, i
                while j < len(s):
                    depth += {'{': 1, '}': -1}.get(s[j], 0)
                    j += 1
                    if depth == 0:
                        break
                i = j
            continue
        j = i
        while j < len(s) and not s[j].isspace():
            j += 1
        out.append(s[i:j])
        i = j
    return out


def _registry_value(key: str):
    """Value of `set flow(<key>) …` in flow_registry.tcl, or None."""
    hits = _array_values(_read(flow_registry_path()), 'flow', re.escape(key))
    return hits[0][1] if hits else None


def flow_value(key: str):
    """Value of `set flow(<key>) …` in flow_registry.tcl, or None."""
    return _registry_value(key)


def require_flow_value(key: str) -> str:
    v = _registry_value(key)
    if v is None or v == '':
        raise RegistryError(f'flow({key}) is not set in flow_registry.tcl')
    return v


def flow_values(prefix: str) -> dict:
    """{suffix: value} for every `set flow(<prefix><suffix>) …` in
    flow_registry.tcl (declaration order)."""
    return {k[len(prefix):]: v for k, v in
            _array_values(_read(flow_registry_path()), 'flow', re.escape(prefix) + r'[^)]+')}


def release_config_path() -> str:
    """The release config (exit order, handshake map, release layout keys)."""
    return os.path.join(discipline_dir('PD'), 'config', 'flow',
                        config_version('FLOW_CONFIG_VERSION'), 'release_config.tcl')


def release_value(key: str):
    """Value of `set release(<key>) …` in release_config.tcl, or None."""
    hits = _array_values(_read(release_config_path()), 'release', re.escape(key))
    return hits[0][1] if hits else None


def require_release_value(key: str) -> str:
    v = release_value(key)
    if v is None or v == '':
        raise RegistryError(f'release({key}) is not set in release_config.tcl')
    return v


def handshake_entries(input_type: str) -> dict:
    """{downstream_flow: [source_flow, category, filename]} for every
    flow_input_handshake(<FLOW>,<input_type>) in release_config.tcl."""
    out = {}
    for k, v in _array_values(_read(release_config_path()), 'flow_input_handshake',
                              r'[A-Z0-9_]+,' + re.escape(input_type)):
        out[k.split(',', 1)[0]] = tcl_list(v)
    return out


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
        for _, v in _array_values(_read(p), 'project', re.escape(key)):
            val = v
    return val


def require_project_value(project: str, key: str) -> str:
    v = project_value(project, key)
    if v is None or v == '':
        raise RegistryError(f'project({key}) is not set for {project}')
    return v
