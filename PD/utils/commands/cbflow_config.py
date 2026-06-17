"""CBflow resolved-config — the only Python entry point for cascade reads.

Every Python caller (race_engine, dashboard, run_cmd, workspace_cmd,
makefile_generator, node_manager, tcl_config_parser) goes through this module.
No regex parse of `*_config.tcl` files anywhere else in the codebase — the
static-check guard in `test_suite/static_checks.py` enforces it.

API surface (intentionally small):

    cfg = load_resolved_config(flow_type, run_dir)        # full cascade
    cfg = load_resolved_config(flow_type, run_dir=None)   # project baseline only

    require(cfg, key)            -> str               # KeyError if missing
    require_list(cfg, key)       -> list[str]         # errors if missing or empty
    optional(cfg, key)           -> str | None        # None if absent — NO default

The resolver is `PD/utils/commands/config_resolver.tcl`. It owns the cascade
order and the emission schema. This module validates `_schema_version` on every
load and refuses to consume an unfamiliar schema.

Caching:
    Results are cached per (flow_type, abs_run_dir) per Python process. The
    cache invalidates if `setup/user_config.tcl` or `setup/runtime_flow_config.tcl`
    mtime changes — typical case during a single command, neither moves. The
    upstream files (`flow_config.tcl`, `<FLOW>_config.tcl`, `mmmc_config.tcl`)
    are immutable for the duration of a run so they don't trigger invalidation.
"""

from __future__ import annotations

import os
import subprocess
from typing import Dict, Optional, Tuple

SCHEMA_VERSION = '2'

# (flow_type, abs_run_dir_or_NORUN) → (dict, (user_mtime, runtime_mtime))
_cache: Dict[Tuple[str, str], Tuple[Dict[str, str], Tuple[float, float]]] = {}


# ── Public API ─────────────────────────────────────────────────────────────


class ConfigError(KeyError):
    """Raised by require()/require_list() when a key isn't in the resolved
    cascade. Always names the missing key and the contributing files so the
    caller can find the config to fix."""

    def __init__(self, key: str, cfg: Dict[str, str]):
        sources = cfg.get('_sources', '<resolver did not report sources>')
        super().__init__(
            f"CBflow config: required key {key!r} not in resolved cascade. "
            f"Last sourced from: {sources}. "
            f"Set it in user_config.tcl, the relevant <FLOW>_config.tcl, "
            f"or flow_config.tcl — then re-run."
        )
        self.key = key
        self.sources = sources


def load_resolved_config(flow_type: str, run_dir: Optional[str] = None,
                         env: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    """Run the cascade resolver and return the resolved key→value dict.

    `run_dir=None` → project baseline only (no user_config / runtime override).
    Used by pre-run commands like `cbflow flow types` that don't have a run.
    Otherwise the full cascade runs, with user_config taking precedence.
    """
    if not flow_type:
        raise ValueError("load_resolved_config: flow_type required")

    cache_key = (flow_type, _cache_path(run_dir))
    mtimes = _mtimes(run_dir)
    if cache_key in _cache:
        cached_cfg, cached_mtimes = _cache[cache_key]
        if cached_mtimes == mtimes:
            return cached_cfg

    cfg = _run_resolver(flow_type, run_dir, env)
    _validate_schema(cfg, flow_type, run_dir)
    _cache[cache_key] = (cfg, mtimes)
    return cfg


def require(cfg: Dict[str, str], key: str) -> str:
    """Return the value, raising ConfigError if the key is absent OR empty.

    Empty values are treated as missing because an empty Tcl array element is
    indistinguishable from an undefined one for our consumers — every key the
    engine looks up *must* carry a meaningful value."""
    if key not in cfg or cfg[key] == '':
        raise ConfigError(key, cfg)
    return cfg[key]


def require_list(cfg: Dict[str, str], key: str) -> list:
    """Same as require(), but split the value on whitespace and return a list.
    Errors if the list is empty (which a Tcl `{}` would produce)."""
    value = require(cfg, key)
    items = value.split()
    if not items:
        raise ConfigError(key, cfg)
    return items


def optional(cfg: Dict[str, str], key: str) -> Optional[str]:
    """Return the value or None — NO default. Callers handle the None case
    explicitly so the absence is visible at the call site."""
    val = cfg.get(key)
    if val == '':
        return None
    return val


def clear_cache() -> None:
    """Drop every cache entry. Tests and the dashboard's `Save user_config`
    path call this when they know the cascade has been mutated mid-process."""
    _cache.clear()


def preview_user_config(path: str) -> Dict[str, str]:
    """Source a user_config.tcl file in isolation and return the flow(...) /
    project(...) atoms set by the user.

    Used by `cbflow workspace create` *before* a run directory exists — at
    that point the cascade resolver can't run, but we need to know the flow
    type and run name to know where to create the run. Tcl evaluates the
    file (not regex) so escapes, line continuations, and `set` over
    `array set` all resolve correctly.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"user_config not found: {path}")

    # Snapshot globals → source user_config → diff. Tcl built-ins (env,
    # errorInfo, …) are excluded by the before/after comparison; the catch
    # variable, the loop-local scratch, and Tcl's own bookkeeping are
    # excluded by name.
    script = r'''
set _before [info globals]
if {[catch {source "%s"} _err]} {
    puts stderr "ERROR sourcing user_config: $_err"
    exit 1
}
set _ignore {_before _err _name _idx _scratch errorInfo errorCode}
foreach _name [info globals] {
    if {[lsearch -exact $_before $_name] >= 0} { continue }
    if {[lsearch -exact $_ignore $_name] >= 0} { continue }
    if {[string match _* $_name]} { continue }
    if {[array exists ::$_name]} {
        foreach _idx [array names ::$_name] {
            regsub -all {\s+} [string trim [set ::${_name}($_idx)]] { } _scratch
            puts "CBFLOW_UC:[set _name]($_idx)=$_scratch"
        }
    } elseif {[info exists ::$_name]} {
        regsub -all {\s+} [string trim [set ::$_name]] { } _scratch
        puts "CBFLOW_UC:[set _name]=$_scratch"
    }
}
''' % path.replace('"', r'\"')

    try:
        result = subprocess.run(
            ['tclsh'], input=script, capture_output=True, text=True, timeout=15,
        )
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"user_config preview timed out: {path}") from e

    if result.returncode != 0:
        raise RuntimeError(
            f"user_config preview failed for {path}\n"
            f"stderr: {result.stderr.strip()}"
        )

    out: Dict[str, str] = {}
    for line in result.stdout.splitlines():
        if not line.startswith('CBFLOW_UC:'):
            continue
        kv = line[len('CBFLOW_UC:'):]
        eq = kv.find('=')
        if eq <= 0:
            continue
        out[kv[:eq]] = kv[eq + 1:]
    return out


# ── Implementation ─────────────────────────────────────────────────────────


def _resolver_path() -> str:
    """Path to config_resolver.tcl — sits next to this module."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'config_resolver.tcl')


def _cache_path(run_dir: Optional[str]) -> str:
    return os.path.abspath(run_dir) if run_dir else '<NORUN>'


def _mtimes(run_dir: Optional[str]) -> Tuple[float, float]:
    """Return (user_config_mtime, runtime_flow_mtime). 0.0 if a file is absent.
    Used to invalidate the cache when either file changes."""
    if not run_dir:
        return (0.0, 0.0)
    setup = os.path.join(run_dir, 'setup')
    return (
        _mtime_or_zero(os.path.join(setup, 'user_config.tcl')),
        _mtime_or_zero(os.path.join(setup, 'runtime_flow_config.tcl')),
    )


def _mtime_or_zero(path: str) -> float:
    try:
        return os.path.getmtime(path)
    except OSError:
        return 0.0


def _run_resolver(flow_type: str, run_dir: Optional[str],
                  env: Optional[Dict[str, str]]) -> Dict[str, str]:
    """Spawn `tclsh config_resolver.tcl` and parse its CBFLOW_CFG: lines."""
    resolver = _resolver_path()
    if not os.path.exists(resolver):
        raise FileNotFoundError(f"CBflow config resolver not found: {resolver}")

    run_arg = os.path.abspath(run_dir) if run_dir else '--no-run'
    cmd_env = dict(os.environ)
    if env:
        # Caller-provided env wins (typically the run's CBFLOW_* / FLOW_DIR).
        cmd_env.update({k: v for k, v in env.items() if v is not None})

    try:
        result = subprocess.run(
            ['tclsh', resolver, flow_type, run_arg],
            capture_output=True, text=True, timeout=30, env=cmd_env,
        )
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(
            f"CBflow config resolver timed out (>30s) for "
            f"flow={flow_type} run_dir={run_arg}"
        ) from e

    if result.returncode != 0:
        raise RuntimeError(
            f"CBflow config resolver failed for flow={flow_type} run_dir={run_arg}\n"
            f"stderr: {result.stderr.strip()}"
        )

    cfg: Dict[str, str] = {}
    for line in result.stdout.splitlines():
        if not line.startswith('CBFLOW_CFG:'):
            continue
        kv = line[len('CBFLOW_CFG:'):]
        eq = kv.find('=')
        if eq <= 0:
            continue
        cfg[kv[:eq]] = kv[eq + 1:]
    return cfg


def _validate_schema(cfg: Dict[str, str], flow_type: str,
                     run_dir: Optional[str]) -> None:
    """Refuse to consume output the resolver produced for a different schema.
    The version bumps when emissions change; this catches the case where the
    Python and Tcl halves drift out of sync (e.g., user upgrades one and not
    the other)."""
    got = cfg.get('_schema_version', '')
    if got != SCHEMA_VERSION:
        raise RuntimeError(
            f"CBflow config resolver schema mismatch: expected {SCHEMA_VERSION!r}, "
            f"got {got!r} (flow={flow_type} run_dir={run_dir or '<NORUN>'}). "
            f"Likely cause: config_resolver.tcl and cbflow_config.py are from "
            f"different versions — sync them."
        )
    if cfg.get('_done') != 'true':
        raise RuntimeError(
            f"CBflow config resolver did not finish cleanly "
            f"(missing _done=true marker) for flow={flow_type} "
            f"run_dir={run_dir or '<NORUN>'}."
        )
