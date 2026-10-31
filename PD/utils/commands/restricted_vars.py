"""Restricted-variable scanner.

The list of restricted variable name patterns lives in TCL
(`PD/config/flow/v1.0.0/edit_restricted_config.tcl`) so the same source of
truth drives both TCL-side validation and Python-side guardrails. This
module parses the patterns out of that file and matches them with fnmatch.

Patterns support `*` glob segments so per-metal-stack / per-track schemas
like `tech(rcx,*,rc_max,tluplus)` need just one rule.
"""

import fnmatch
import os

# Post cbflow_global utils-refactor: shared Python packages (core.*,
# logging_config, cbflow_config, …) live under global/utils/, not PD/utils/.
# Add both to sys.path so inner `from core.* import …` calls resolve even
# when the invoker didn't preset env.
import sys as _bootstrap_sys
_this = os.path.dirname(os.path.abspath(__file__))
_pd_utils = os.path.dirname(_this)
_umbrella = os.path.dirname(os.path.dirname(_pd_utils))
_global_utils = os.path.join(_umbrella, 'global', 'utils')
_global_cmds = os.path.join(_global_utils, 'commands')
if os.path.isdir(_global_cmds) and _global_cmds not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_cmds)
if os.path.isdir(_global_utils) and _global_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_utils)
if _pd_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _pd_utils)

import re
from functools import lru_cache


def _config_path() -> str:
    """Locate edit_restricted_config.tcl.

    Tries FLOW_DIR env var first (set at run time by the engine), then falls
    back to the in-repo path via core.paths.get_cbflow_core_dir() which is
    available at workspace-create time before any run env is built.
    """
    flow_dir = os.environ.get('FLOW_DIR', '')
    if not flow_dir:
        try:
            from core.paths import get_cbflow_core_dir, get_flow_config_version
            flow_dir = get_cbflow_core_dir()
            version = get_flow_config_version()
        except Exception:
            return ''
    else:
        version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    return os.path.join(flow_dir, 'config', 'flow', version,
                        'edit_restricted_config.tcl')


@lru_cache(maxsize=4)
def load_patterns(config_path: str = '') -> tuple:
    """Return the flattened tuple of restricted-variable glob patterns.

    Parses every `set restricted_*_variables { ... }` block out of the TCL
    file. Returns an empty tuple if the file is missing — callers should
    treat that as "nothing to check" (not a fatal error) so workspace
    creation still works on stripped-down dev setups.
    """
    path = config_path or _config_path()
    if not path or not os.path.exists(path):
        return ()
    with open(path) as f:
        text = f.read()
    patterns = []
    for m in re.finditer(
        r'set\s+restricted_\w+_variables\s+\{([^}]*)\}', text, re.DOTALL
    ):
        block = m.group(1)
        for line in block.splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            # Strip enclosing double quotes; the TCL list items are quoted.
            if line.startswith('"') and line.endswith('"'):
                line = line[1:-1]
            if line:
                patterns.append(line)
    return tuple(patterns)


def is_restricted(var_name: str, patterns=None) -> bool:
    """True if var_name matches any restricted pattern (fnmatch glob)."""
    pats = patterns if patterns is not None else load_patterns()
    for p in pats:
        if fnmatch.fnmatchcase(var_name, p):
            return True
    return False


def scan_file(path: str, patterns=None) -> list:
    """Return [(lineno, var_name, raw_line), ...] for restricted `set` lines.

    Only `set <name> ...` statements are considered — comments and other
    syntax are ignored. The variable name is the bare token after `set`.
    """
    if not os.path.exists(path):
        return []
    pats = patterns if patterns is not None else load_patterns()
    if not pats:
        return []
    hits = []
    set_re = re.compile(r'^\s*set\s+(\S+)\s+')
    with open(path) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            m = set_re.match(line)
            if not m:
                continue
            var_name = m.group(1)
            if is_restricted(var_name, pats):
                hits.append((lineno, var_name, raw.rstrip()))
    return hits
