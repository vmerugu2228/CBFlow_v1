"""
CBflow Core — TCL config file reader.

Reads TCL set/array statements from config files without executing TCL.
Used by Python tools to extract config values.
"""

import os
import re


def parse_user_config(config_path: str) -> dict:
    """Parse a user_config.tcl file into a dict.

    Extracts: set <arr>(<key>) "value" → dict key: '<arr>(<key>)', value: 'value'

    Args:
        config_path: Path to .tcl config file

    Returns: Dict of variable_name → value
    Raises FileNotFoundError if file doesn't exist.
    """
    if not os.path.isfile(config_path):
        raise FileNotFoundError("Config file not found: {}".format(config_path))

    result = {}
    with open(config_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            # Match: set <name>(<key>) "value"
            m = re.match(r'set\s+(\w+\([^)]+\))\s+"([^"]*)"', line)
            if m:
                result[m.group(1)] = m.group(2)
                continue
            # Match: set <name> "value"
            m = re.match(r'set\s+(\w+)\s+"([^"]*)"', line)
            if m:
                result[m.group(1)] = m.group(2)
    return result


def read_tcl_variable(file_path: str, var_pattern: str) -> str:
    """Read a single TCL variable value from a file.

    Args:
        file_path: Path to .tcl file
        var_pattern: Regex pattern for the variable (e.g., r'tech\\(lib_root\\)')

    Returns: Variable value, or empty string if not found.
    """
    if not os.path.isfile(file_path):
        return ''

    with open(file_path, 'r') as f:
        content = f.read()

    m = re.search(r'set\s+{}\s+"([^"]+)"'.format(var_pattern), content)
    return m.group(1) if m else ''


def read_tcl_list(file_path: str, var_pattern: str) -> list:
    """Read a TCL list variable from a file.

    Handles: set var {item1 item2 item3}

    Returns: List of values, or empty list if not found.
    """
    if not os.path.isfile(file_path):
        return []

    with open(file_path, 'r') as f:
        content = f.read()

    m = re.search(r'set\s+{}\s+\{{([^}}]+)\}}'.format(var_pattern), content)
    if m:
        return m.group(1).strip().split()
    return []
