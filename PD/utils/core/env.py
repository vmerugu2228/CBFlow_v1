"""
CBflow Core — Run environment resolution.

Single source of truth for reading .run.cbflow.tcl and .run.cbflow.env files.
"""

import os
import re


def load_run_env(run_dir: str = None) -> dict:
    """Load CBflow run environment variables from .run.cbflow.tcl.

    Args:
        run_dir: Run directory path. If None, uses current directory.

    Returns: Dict of environment variables (key → value).
    Raises FileNotFoundError if no run env file found.
    """
    run_dir = run_dir or os.getcwd()
    env_vars = {}

    # Try TCL format first
    tcl_file = os.path.join(run_dir, '.run.cbflow.tcl')
    if os.path.isfile(tcl_file):
        with open(tcl_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Match: set ::env(KEY) "VALUE"
                m = re.match(r'set\s+::env\((\w+)\)\s+"([^"]*)"', line)
                if m:
                    env_vars[m.group(1)] = m.group(2)
        return env_vars

    # Try shell format
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if os.path.isfile(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('#') or '=' not in line:
                    continue
                line = line.lstrip('export ')
                key, _, val = line.partition('=')
                env_vars[key.strip()] = val.strip().strip('"').strip("'")
        return env_vars

    return env_vars


def require_env(key: str, env_vars: dict = None) -> str:
    """Get a required environment variable.

    Checks env_vars dict first, then os.environ.
    Raises ValueError if not found — never returns empty string for required vars.
    """
    if env_vars and key in env_vars and env_vars[key]:
        return env_vars[key]
    val = os.environ.get(key, '')
    if not val:
        raise ValueError(
            "Required environment variable not set: {}. "
            "Ensure you are in a valid CBflow run directory.".format(key)
        )
    return val
