"""
CBflow Core — Path resolution.

Single source of truth for all path calculations.
Every command module imports from here instead of re-implementing.
"""

import os
import sys


def get_cbflow_core_dir() -> str:
    """Resolve the CBflow core directory (PD/).

    Resolution order:
    1. CBFLOW_CORE_DIR environment variable (explicit, highest priority)
    2. Calculated from this file's location (PD/utils/core/paths.py → PD/)

    Raises ValueError if resolution fails — never returns empty string.
    """
    env_val = os.environ.get('CBFLOW_CORE_DIR', '')
    if env_val and os.path.isdir(env_val):
        return env_val

    # Calculate from file location: PD/utils/core/paths.py → PD/
    this_dir = os.path.dirname(os.path.abspath(__file__))
    core_dir = os.path.dirname(os.path.dirname(this_dir))

    if os.path.isdir(core_dir) and os.path.isdir(os.path.join(core_dir, 'config')):
        return core_dir

    raise ValueError(
        "Cannot resolve CBFLOW_CORE_DIR. "
        "Set the CBFLOW_CORE_DIR environment variable or run from a valid CBflow installation."
    )


def get_flow_config_version() -> str:
    """Get the flow config version string.

    Reads from FLOW_CONFIG_VERSION env var.
    Raises ValueError if not set — config version is mandatory.
    """
    version = os.environ.get('FLOW_CONFIG_VERSION', '')
    if not version:
        # Fallback to v1.0.0 ONLY during development/testing
        return 'v1.0.0'
    return version


def get_config_root() -> str:
    """Get the config root directory.

    Returns: <core_dir>/config/
    Raises ValueError if not found.
    """
    core = get_cbflow_core_dir()
    config_root = os.path.join(core, 'config')
    if not os.path.isdir(config_root):
        raise ValueError("Config root not found: {}".format(config_root))
    return config_root


def get_tech_config_path(tech_name: str, version: str = None) -> str:
    """Get path to a technology's tech_config.tcl.

    Args:
        tech_name: Technology name (e.g., 'gf_22nm', 'gf_28nm')
        version: Config version (default: from env)

    Returns: Absolute path to tech_config.tcl
    Raises FileNotFoundError if not found.
    """
    ver = version or get_flow_config_version()
    path = os.path.join(get_config_root(), 'tech', tech_name, ver, 'tech_config.tcl')
    if not os.path.isfile(path):
        raise FileNotFoundError("Tech config not found: {}".format(path))
    return path


def get_node_config_path(flow_type: str, version: str = None) -> str:
    """Get path to a flow's node config.

    Returns: Absolute path to <FLOW>_config.tcl
    Raises FileNotFoundError if not found.
    """
    ver = version or get_flow_config_version()
    path = os.path.join(get_config_root(), 'flow', ver, 'node_configs',
                        '{}_config.tcl'.format(flow_type))
    if not os.path.isfile(path):
        raise FileNotFoundError("Node config not found: {}".format(path))
    return path
