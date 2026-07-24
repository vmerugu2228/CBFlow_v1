"""Post-cascade config validation.

Reads the `flow(mandatory_vars,all)` + `flow(mandatory_vars,<FLOW>)` lists
emitted by config_resolver.tcl and verifies each named key is present and
non-empty in the resolved config. Fails fast — before any work directory is
created, before any subprocess is launched.

Contract with the TCL side:
    flow_config.tcl declares `flow(mandatory_vars,all)` (cross-flow) and
    `flow(mandatory_vars,<FLOW>)` (per-flow). Each entry is a whitespace-
    separated list of resolved-config keys. Missing / empty values at those
    keys → validation fails.

Callers:
    - race_engine.build() runs this before DAG assembly
    - cmd_validate_workspace runs this per run directory
"""

from __future__ import annotations

from typing import Dict, List, Tuple

from cbflow_config import ConfigError


def collect_mandatory_keys(cfg: Dict[str, str], flow_type: str) -> List[str]:
    """Return the ordered list of keys the cascade declared mandatory.

    Combines `flow(mandatory_vars,all)` and `flow(mandatory_vars,<flow_type>)`.
    Order matters for the error message: cross-flow first, per-flow second.
    Duplicates are dropped (list order preserved).
    """
    keys: List[str] = []
    seen: set = set()
    for scope in ('all', flow_type):
        raw = cfg.get(f'flow(mandatory_vars,{scope})', '')
        for k in raw.split():
            if k in seen:
                continue
            seen.add(k)
            keys.append(k)
    return keys


def validate_mandatory_vars(cfg: Dict[str, str], flow_type: str) -> List[str]:
    """Return the list of mandatory keys that are missing or empty in cfg.

    Empty list → pass. Non-empty → these keys have no value in the resolved
    cascade. Same "missing OR empty" semantics as cbflow_config.require().
    """
    missing: List[str] = []
    for key in collect_mandatory_keys(cfg, flow_type):
        val = cfg.get(key)
        if not val:
            missing.append(key)
    return missing


def format_validation_error(missing: List[str], cfg: Dict[str, str],
                            flow_type: str) -> str:
    """Human-readable multi-line error naming the missing keys and the
    contributing config files, so the user knows where to fix it."""
    sources = cfg.get('_sources', '<resolver did not report sources>')
    lines = [
        f"CBflow config validation failed for flow={flow_type!r} — "
        f"{len(missing)} mandatory key(s) missing or empty:",
    ]
    for k in missing:
        lines.append(f"  • {k}")
    lines.append("")
    lines.append(f"Sourced files (cascade order): {sources}")
    lines.append(
        "Set each key above in user_config.tcl, the relevant <FLOW>_config.tcl, "
        "or flow_config.tcl — then re-run."
    )
    return "\n".join(lines)


def assert_mandatory_vars(cfg: Dict[str, str], flow_type: str) -> None:
    """Convenience: raise ConfigError if any mandatory key is missing.

    ConfigError inherits from KeyError; existing callers that catch KeyError
    around config lookups will catch this too. The error message names every
    missing key (not just the first), which is what the user wants when the
    cascade is broken in multiple places at once.
    """
    missing = validate_mandatory_vars(cfg, flow_type)
    if not missing:
        return
    # ConfigError takes (key, cfg); pass a synthesized composite key that
    # renders naturally in the parent's message, then use its .args to carry
    # the full formatted report.
    composite = f"mandatory_vars,{flow_type}[{len(missing)} missing]"
    err = ConfigError(composite, cfg)
    err.args = (format_validation_error(missing, cfg, flow_type),)
    err.missing_keys = missing
    raise err
