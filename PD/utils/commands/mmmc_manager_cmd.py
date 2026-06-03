#!/usr/bin/env python3
# ===============================================================================
# CBflow - MMMC Manager Command Handler
# Description: Multi-Mode Multi-Corner configuration manager aligned with
#              mmmc_config.tcl structure. Parses, validates, and edits the
#              TCL config in-place without regenerating the whole file.
# Usage: cbflow flow mmmc-manager <subcommand> [options]
# ===============================================================================

import argparse
import os
import re
import shutil
import subprocess
import sys
import logging
from typing import Dict, List, Optional, Tuple

from logging_config import configure_logging, get_logger

logger = configure_logging('cbflow.mmmc_manager')


# ===============================================================================
# Config Path Resolution
# ===============================================================================

def get_mmmc_config_path() -> str:
    """Resolve mmmc_config.tcl path from environment."""
    core_dir = os.environ.get('CBFLOW_CORE_DIR', '')
    if not core_dir:
        # Fall back to relative from this script
        script_dir = os.path.dirname(os.path.abspath(__file__))
        core_dir = os.path.dirname(os.path.dirname(script_dir))
    version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    return os.path.join(core_dir, 'config', 'flow', version, 'mmmc_config.tcl')


# ===============================================================================
# TCL Config Parser
# ===============================================================================

class MmmcConfigParser:
    """Parse mmmc_config.tcl into Python data structures.

    Handles the exact formats used in the config:
      - set mmmc(process_corners) {ss tt ff}          (simple list)
      - set mmmc(pvt,ss) {{0p76v 150c} {0p76v 25c}}   (PVT points)
      - set mmmc(rc_pair,ss) "rcmax"                   (RC pairing)
      - array set operating_modes { ... }              (modes with SDC)
      - array set rc_corners { ... }                   (RC corner defs)
      - array set mmmc { ... }                         (node mappings)
    """

    def __init__(self, config_path: str):
        self.config_path = config_path
        self.raw_lines: List[str] = []
        self.raw_content: str = ''

        # Parsed data
        self.process_corners: List[str] = []
        self.pvt_points: Dict[str, List[Tuple[str, str]]] = {}
        self.rc_pairs: Dict[str, str] = {}
        self.operating_modes: Dict[str, Dict[str, str]] = {}
        self.rc_corners: Dict[str, Dict[str, str]] = {}
        self.node_mappings: Dict[str, Dict[str, List[str]]] = {}

        # Voltage/temperature globals
        self.voltage_nom: str = ''
        self.voltage_low: str = ''
        self.voltage_high: str = ''
        self.temp_hot: str = ''
        self.temp_nom: str = ''
        self.temp_cold: str = ''

    def parse(self) -> bool:
        """Parse the mmmc_config.tcl file. Returns True on success."""
        if not os.path.isfile(self.config_path):
            logger.error("Config file not found: %s", self.config_path)
            return False

        with open(self.config_path, 'r') as f:
            self.raw_content = f.read()
            self.raw_lines = self.raw_content.splitlines()

        self._parse_voltage_temperature()
        self._parse_process_corners()
        self._parse_pvt_points()
        self._parse_rc_pairs()
        self._parse_operating_modes()
        self._parse_rc_corners()
        self._parse_node_mappings()
        return True

    # -- Simple variable parsers ------------------------------------------------

    def _parse_voltage_temperature(self):
        """Parse mmmc(voltage,...) and mmmc(temperature,...) variables."""
        for line in self.raw_lines:
            m = re.match(r'set\s+mmmc\(voltage,nom\)\s+(\S+)', line)
            if m:
                self.voltage_nom = m.group(1)
            m = re.match(r'set\s+mmmc\(voltage,low\)\s+(\S+)', line)
            if m:
                self.voltage_low = m.group(1)
            m = re.match(r'set\s+mmmc\(voltage,high\)\s+(\S+)', line)
            if m:
                self.voltage_high = m.group(1)
            m = re.match(r'set\s+mmmc\(temperature,hot\)\s+(\S+)', line)
            if m:
                self.temp_hot = m.group(1)
            m = re.match(r'set\s+mmmc\(temperature,nom\)\s+(\S+)', line)
            if m:
                self.temp_nom = m.group(1)
            m = re.match(r'set\s+mmmc\(temperature,cold\)\s+(\S+)', line)
            if m:
                self.temp_cold = m.group(1)

    def _parse_process_corners(self):
        """Parse: set mmmc(process_corners) {ss tt ff}"""
        m = re.search(r'set\s+mmmc\(process_corners\)\s+\{([^}]+)\}', self.raw_content)
        if m:
            self.process_corners = m.group(1).split()

    def _parse_pvt_points(self):
        """Parse: set mmmc(pvt,ss) {{0p76v 150c} {0p76v 25c} ...}"""
        for m in re.finditer(
            r'set\s+mmmc\(pvt,(\w+)\)\s+\{(.*?)\}(?:\s*$|\s*\n)',
            self.raw_content, re.MULTILINE
        ):
            corner = m.group(1)
            body = m.group(2)
            points = []
            for pm in re.finditer(r'\{(\S+)\s+(\S+)\}', body):
                points.append((pm.group(1), pm.group(2)))
            self.pvt_points[corner] = points

    def _parse_rc_pairs(self):
        """Parse: set mmmc(rc_pair,ss) "rcmax" """
        for m in re.finditer(
            r'set\s+mmmc\(rc_pair,(\w+)\)\s+"(\w+)"', self.raw_content
        ):
            self.rc_pairs[m.group(1)] = m.group(2)

    # -- Array parsers ----------------------------------------------------------

    def _extract_array_body(self, array_name: str) -> Optional[str]:
        """Extract the body of an 'array set <name> { ... }' block."""
        pattern = re.compile(
            rf'array\s+set\s+{re.escape(array_name)}\s*\{{', re.DOTALL
        )
        match = pattern.search(self.raw_content)
        if not match:
            return None

        start = match.end()
        depth = 1
        pos = start
        while pos < len(self.raw_content) and depth > 0:
            ch = self.raw_content[pos]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
            pos += 1
        return self.raw_content[start:pos - 1]

    def _parse_operating_modes(self):
        """Parse: array set operating_modes { func { constraint_file "..." } ... }"""
        body = self._extract_array_body('operating_modes')
        if not body:
            return
        self.operating_modes = self._parse_flat_dict_entries(body)

    def _parse_rc_corners(self):
        """Parse: array set rc_corners { rc_max { temperature 125 ... } ... }"""
        body = self._extract_array_body('rc_corners')
        if not body:
            return
        self.rc_corners = self._parse_flat_dict_entries(body)

    def _parse_node_mappings(self):
        """Parse: array set mmmc { init_design { setup {...} hold {...} } ... }"""
        body = self._extract_array_body('mmmc')
        if not body:
            return
        # Top-level entries: node_name { setup {...} hold {...} }
        entries = self._extract_brace_entries(body)
        for name, value_str in entries:
            sub_entries = self._extract_brace_entries(value_str)
            mapping = {}
            for sub_key, sub_val in sub_entries:
                mapping[sub_key] = sub_val.split()
            self.node_mappings[name] = mapping

    # -- Low-level TCL brace parsers --------------------------------------------

    def _parse_flat_dict_entries(self, body: str) -> Dict[str, Dict[str, str]]:
        """Parse top-level key { k1 v1 k2 v2 ... } entries into dict of dicts."""
        result = {}
        entries = self._extract_brace_entries(body)
        for name, value_str in entries:
            kv = self._tokenize_kv(value_str)
            result[name] = kv
        return result

    def _extract_brace_entries(self, text: str) -> List[Tuple[str, str]]:
        """Extract name { value } pairs from a TCL block, skipping comments."""
        entries = []
        pos = 0
        length = len(text)
        while pos < length:
            # Skip whitespace
            while pos < length and text[pos] in ' \t\n\r':
                pos += 1
            if pos >= length:
                break
            # Skip comment lines
            if text[pos] == '#':
                while pos < length and text[pos] != '\n':
                    pos += 1
                continue
            # Read key
            key_start = pos
            while pos < length and text[pos] not in ' \t\n\r{':
                pos += 1
            key = text[key_start:pos]
            if not key:
                break
            # Skip to opening brace
            while pos < length and text[pos] in ' \t\n\r':
                pos += 1
            if pos >= length or text[pos] != '{':
                break
            # Extract braced value
            pos += 1
            depth = 1
            val_start = pos
            while pos < length and depth > 0:
                if text[pos] == '{':
                    depth += 1
                elif text[pos] == '}':
                    depth -= 1
                pos += 1
            value = text[val_start:pos - 1].strip()
            entries.append((key, value))
        return entries

    def _tokenize_kv(self, text: str) -> Dict[str, str]:
        """Tokenize key-value pairs from a flat TCL dict string."""
        result = {}
        tokens = []
        pos = 0
        length = len(text)
        while pos < length:
            while pos < length and text[pos] in ' \t\n\r':
                pos += 1
            if pos >= length:
                break
            if text[pos] == '#':
                while pos < length and text[pos] != '\n':
                    pos += 1
                continue
            if text[pos] == '"':
                end = text.index('"', pos + 1)
                tokens.append(text[pos + 1:end])
                pos = end + 1
            elif text[pos] == '{':
                depth = 1
                pos += 1
                start = pos
                while pos < length and depth > 0:
                    if text[pos] == '{':
                        depth += 1
                    elif text[pos] == '}':
                        depth -= 1
                    pos += 1
                tokens.append(text[start:pos - 1].strip())
            else:
                start = pos
                while pos < length and text[pos] not in ' \t\n\r{}':
                    pos += 1
                tokens.append(text[start:pos])
        i = 0
        while i < len(tokens) - 1:
            result[tokens[i]] = tokens[i + 1]
            i += 2
        return result


# ===============================================================================
# TCL Execution (for auto-generated views and scenario sets)
# ===============================================================================

def execute_tcl_config(config_path: str) -> Optional[Dict]:
    """Execute mmmc_config.tcl via tclsh and capture auto-generated data.

    Returns dict with keys: analysis_views (list), scenario_sets (dict of lists).
    Returns None on failure.
    """
    tcl_script = f'''
source "{config_path}"

# Dump analysis view names
puts "===VIEWS_START==="
foreach v [lsort [array names analysis_views]] {{
    puts $v
}}
puts "===VIEWS_END==="

# Dump scenario sets
puts "===SETS_START==="
foreach s [lsort [array names mmmc_scenario_sets]] {{
    puts "SET:$s"
    foreach v $mmmc_scenario_sets($s) {{
        puts "  $v"
    }}
}}
puts "===SETS_END==="
'''
    try:
        result = subprocess.run(
            ['tclsh'], input=tcl_script, capture_output=True, text=True, timeout=10
        )
    except FileNotFoundError:
        logger.error("tclsh not found -- cannot execute TCL config")
        return None
    except subprocess.TimeoutExpired:
        logger.error("tclsh timed out executing config")
        return None

    if result.returncode != 0:
        logger.error("tclsh failed:\n%s", result.stderr.strip())
        return None

    stdout = result.stdout
    data = {'analysis_views': [], 'scenario_sets': {}}

    # Parse views
    m = re.search(r'===VIEWS_START===\n(.*?)===VIEWS_END===', stdout, re.DOTALL)
    if m:
        data['analysis_views'] = [
            line.strip() for line in m.group(1).splitlines() if line.strip()
        ]

    # Parse scenario sets
    m = re.search(r'===SETS_START===\n(.*?)===SETS_END===', stdout, re.DOTALL)
    if m:
        current_set = None
        for line in m.group(1).splitlines():
            line = line.strip()
            if line.startswith('SET:'):
                current_set = line[4:]
                data['scenario_sets'][current_set] = []
            elif current_set and line:
                data['scenario_sets'][current_set].append(line)

    return data


# ===============================================================================
# In-Place Config Editor
# ===============================================================================

def _backup_config(config_path: str) -> str:
    """Create a backup of the config file. Returns backup path."""
    backup = config_path + '.bak'
    shutil.copy2(config_path, backup)
    return backup


def _read_config(config_path: str) -> str:
    """Read config file content."""
    with open(config_path, 'r') as f:
        return f.read()


def _write_config(config_path: str, content: str):
    """Write config file content."""
    with open(config_path, 'w') as f:
        f.write(content)


# ===============================================================================
# Command: show
# ===============================================================================

def cmd_show(args: argparse.Namespace) -> int:
    """Parse and display current config in readable table format."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    # Execute TCL to get auto-generated views and sets
    tcl_data = execute_tcl_config(config_path)
    views = tcl_data['analysis_views'] if tcl_data else []
    sets = tcl_data['scenario_sets'] if tcl_data else {}

    print()
    print("  MMMC Configuration")
    print("  " + "\u2550" * 45)

    # Process corners
    print(f"  Process Corners: {' '.join(parser.process_corners)}")
    print()

    # Operating modes
    print("  Operating Modes:")
    for mode, info in sorted(parser.operating_modes.items()):
        sdc = info.get('constraint_file', '?')
        print(f"    {mode} \u2014 {sdc}")
    print()

    # PVT points
    print("  PVT Points:")
    for corner in parser.process_corners:
        pts = parser.pvt_points.get(corner, [])
        pts_str = ' '.join(f'{{{v} {t}}}' for v, t in pts)
        print(f"    {corner}: {pts_str}")
    print()

    # RC pairing
    print("  RC Pairing:")
    for corner in parser.process_corners:
        rc = parser.rc_pairs.get(corner, '?')
        print(f"    {corner} \u2192 {rc}")
    print()

    # RC corners
    print("  RC Corners:")
    for name, info in sorted(parser.rc_corners.items()):
        temp = info.get('temperature', '?')
        cap = info.get('cap_multiplier', '?')
        res = info.get('res_multiplier', '?')
        print(f"    {name + ':':<18} temp={temp:<5} cap={cap:<5} res={res}")
    print()

    # Analysis views
    num_modes = len(parser.operating_modes)
    num_pvt = sum(len(pts) for pts in parser.pvt_points.values())
    print(f"  Analysis Views: {len(views)} ({num_modes} modes x {num_pvt} PVT combos)")

    # Scenario sets
    if sets:
        print("  Scenario Sets:")
        for sname in ('setup', 'hold', 'signoff', 'power', 'all'):
            if sname in sets:
                print(f"    {sname + ':':<12} {len(sets[sname])} views")
        # Show any extra sets not in the standard list
        for sname in sorted(sets.keys()):
            if sname not in ('setup', 'hold', 'signoff', 'power', 'all'):
                print(f"    {sname + ':':<12} {len(sets[sname])} views")
    print()

    # Node mappings
    if parser.node_mappings:
        print("  Node Scenario Assignments:")
        for node, mapping in parser.node_mappings.items():
            s_count = len(mapping.get('setup', []))
            h_count = len(mapping.get('hold', []))
            print(f"    {node + ':':<15} {s_count} setup, {h_count} hold")
        print()

    return 0


# ===============================================================================
# Command: validate
# ===============================================================================

def cmd_validate(args: argparse.Namespace) -> int:
    """Check consistency of mmmc_config.tcl."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    errors = []
    warnings = []

    print()
    print("  MMMC Validation")
    print("  " + "\u2550" * 45)
    print(f"  Source: {config_path}")
    print()

    # Check 1: Every corner in process_corners has PVT points
    print("  [1] PVT points defined for each process corner")
    for corner in parser.process_corners:
        if corner not in parser.pvt_points or not parser.pvt_points[corner]:
            msg = f"No PVT points defined for corner '{corner}'"
            errors.append(msg)
            print(f"      FAIL  {msg}")
        else:
            n = len(parser.pvt_points[corner])
            print(f"      PASS  {corner}: {n} PVT points")

    # Check 2: Every corner has an RC pair mapping
    print("  [2] RC pair mapping for each process corner")
    for corner in parser.process_corners:
        if corner not in parser.rc_pairs:
            msg = f"No RC pair mapping for corner '{corner}'"
            errors.append(msg)
            print(f"      FAIL  {msg}")
        else:
            print(f"      PASS  {corner} -> {parser.rc_pairs[corner]}")

    # Check 3: Every RC pair references a defined RC corner
    # The rc_pair values (e.g. "rcmax") map to rc_corners keys (e.g. "rc_max")
    # by inserting an underscore: rcmax -> rc_max, rctyp -> rc_typ, rcmin -> rc_min
    print("  [3] RC pairs reference defined RC corners")
    defined_rc = set(parser.rc_corners.keys())
    for corner, rc_name in parser.rc_pairs.items():
        # Normalize: rcmax -> rc_max, rctyp -> rc_typ, etc.
        rc_key = rc_name
        if rc_name not in defined_rc:
            rc_key = rc_name.replace('rc', 'rc_', 1)
        if rc_key not in defined_rc:
            msg = f"RC pair '{rc_name}' (for corner '{corner}') not in rc_corners"
            errors.append(msg)
            print(f"      FAIL  {msg}")
        else:
            print(f"      PASS  {rc_name} -> {rc_key} exists in rc_corners")

    # Check 4: Every mode has a constraint_file
    print("  [4] Operating modes have constraint files")
    for mode, info in parser.operating_modes.items():
        if 'constraint_file' not in info or not info['constraint_file']:
            msg = f"Mode '{mode}' missing constraint_file"
            errors.append(msg)
            print(f"      FAIL  {msg}")
        else:
            print(f"      PASS  {mode}: {info['constraint_file']}")

    # Check 5: Views can be generated without errors (TCL execution)
    print("  [5] TCL config executes without errors")
    tcl_data = execute_tcl_config(config_path)
    if tcl_data is None:
        msg = "TCL execution failed -- views cannot be generated"
        errors.append(msg)
        print(f"      FAIL  {msg}")
    else:
        n_views = len(tcl_data['analysis_views'])
        n_sets = len(tcl_data['scenario_sets'])
        print(f"      PASS  {n_views} views, {n_sets} scenario sets generated")

    # Check 6: Node mapping scenarios reference valid views
    if tcl_data:
        print("  [6] Node scenarios reference valid analysis views")
        valid_views = set(tcl_data['analysis_views'])
        for node, mapping in parser.node_mappings.items():
            for atype in ('setup', 'hold'):
                for scen in mapping.get(atype, []):
                    if scen not in valid_views:
                        msg = f"Node '{node}' {atype}: '{scen}' not a valid view"
                        errors.append(msg)
                        print(f"      FAIL  {msg}")
            s_ok = all(s in valid_views for s in mapping.get('setup', []))
            h_ok = all(s in valid_views for s in mapping.get('hold', []))
            if s_ok and h_ok:
                s_n = len(mapping.get('setup', []))
                h_n = len(mapping.get('hold', []))
                print(f"      PASS  {node}: {s_n} setup + {h_n} hold OK")

    # Summary
    print()
    if errors:
        print(f"  FAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
    elif warnings:
        print(f"  PASSED with {len(warnings)} warning(s)")
    else:
        print("  PASSED: all checks OK")
    print()
    return 1 if errors else 0


# ===============================================================================
# Command: add-mode
# ===============================================================================

def cmd_add_mode(args: argparse.Namespace) -> int:
    """Add an operating mode to mmmc_config.tcl in-place."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    name = args.name
    sdc = args.sdc

    if name in parser.operating_modes:
        logger.error("Operating mode '%s' already exists", name)
        return 1

    content = _read_config(config_path)
    _backup_config(config_path)

    # Find the closing brace of 'array set operating_modes { ... }'
    # Insert new entry just before it.
    pattern = re.compile(
        r'(array\s+set\s+operating_modes\s*\{.*?)(^\})',
        re.DOTALL | re.MULTILINE
    )
    match = pattern.search(content)
    if not match:
        logger.error("Could not find 'array set operating_modes' in config")
        return 1

    new_entry = f'    {name} {{ constraint_file "{sdc}" }}\n'
    content = content[:match.start(2)] + new_entry + content[match.start(2):]

    _write_config(config_path, content)
    logger.info("Added operating mode '%s' with SDC '%s'", name, sdc)
    return 0


# ===============================================================================
# Command: remove-mode
# ===============================================================================

def cmd_remove_mode(args: argparse.Namespace) -> int:
    """Remove an operating mode from mmmc_config.tcl in-place."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    name = args.name
    if name not in parser.operating_modes:
        logger.error("Operating mode '%s' not found. Available: %s",
                      name, ', '.join(parser.operating_modes.keys()))
        return 1

    content = _read_config(config_path)
    _backup_config(config_path)

    # Remove the mode entry line from operating_modes block
    # Match:   name { constraint_file "..." }  (single-line or multi-line)
    pattern = re.compile(
        rf'^\s*{re.escape(name)}\s*\{{[^}}]*\}}\s*\n?',
        re.MULTILINE
    )
    content = pattern.sub('', content)

    _write_config(config_path, content)
    logger.info("Removed operating mode '%s'", name)
    logger.info("Note: auto-generated views will update on next TCL execution")
    return 0


# ===============================================================================
# Command: add-pvt
# ===============================================================================

def cmd_add_pvt(args: argparse.Namespace) -> int:
    """Add a PVT point to a corner in mmmc_config.tcl in-place."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    corner = args.corner
    voltage = args.voltage
    temperature = args.temperature

    if corner not in parser.process_corners:
        logger.error("Corner '%s' not in process_corners: %s",
                      corner, ' '.join(parser.process_corners))
        return 1

    # Check if PVT point already exists
    existing = parser.pvt_points.get(corner, [])
    if (voltage, temperature) in existing:
        logger.error("PVT point {%s %s} already exists for corner '%s'",
                      voltage, temperature, corner)
        return 1

    content = _read_config(config_path)
    _backup_config(config_path)

    # Find the line: set mmmc(pvt,<corner>) {....}
    # PVT line is single line with nested braces — match from 'set mmmc(pvt,X)' to end of line
    pattern = re.compile(
        rf'(set\s+mmmc\(pvt,{re.escape(corner)}\)\s+\{{)(.+)(\}}\s*)$',
        re.MULTILINE
    )
    match = pattern.search(content)
    if not match:
        logger.error("Could not find mmmc(pvt,%s) in config", corner)
        return 1

    # Append new PVT point before the final closing brace
    old_body = match.group(2)  # e.g., "{0p84v m40c} {0p84v 25c} {0p84v 150c} {0p80v m40c}"
    new_body = old_body.rstrip() + f' {{{voltage} {temperature}}}'
    content = content[:match.start(2)] + new_body + content[match.end(2):]

    _write_config(config_path, content)
    logger.info("Added PVT point {%s %s} to corner '%s'", voltage, temperature, corner)
    return 0


# ===============================================================================
# Command: remove-pvt
# ===============================================================================

def cmd_remove_pvt(args: argparse.Namespace) -> int:
    """Remove a PVT point from a corner in mmmc_config.tcl in-place."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    corner = args.corner
    voltage = args.voltage
    temperature = args.temperature

    if corner not in parser.process_corners:
        logger.error("Corner '%s' not in process_corners: %s",
                      corner, ' '.join(parser.process_corners))
        return 1

    existing = parser.pvt_points.get(corner, [])
    if (voltage, temperature) not in existing:
        logger.error("PVT point {%s %s} not found for corner '%s'",
                      voltage, temperature, corner)
        pts_str = ', '.join(f'{{{v} {t}}}' for v, t in existing)
        logger.info("Available: %s", pts_str)
        return 1

    content = _read_config(config_path)
    _backup_config(config_path)

    # Remove {voltage temperature} from the pvt line
    pattern = re.compile(
        rf'(set\s+mmmc\(pvt,{re.escape(corner)}\)\s+\{{)(.+)(\}}\s*)$',
        re.MULTILINE
    )
    match = pattern.search(content)
    if not match:
        logger.error("Could not find mmmc(pvt,%s) in config", corner)
        return 1

    old_body = match.group(2)
    # Remove the {voltage temperature} token, including surrounding whitespace
    pvt_pattern = re.compile(
        rf'\s*\{{{re.escape(voltage)}\s+{re.escape(temperature)}\}}'
    )
    new_body = pvt_pattern.sub('', old_body)
    # Clean up leading/trailing whitespace inside braces
    new_body = re.sub(r'^\s+', '', new_body)
    new_body = re.sub(r'\s+$', '', new_body)

    content = content[:match.start(2)] + new_body + content[match.start(3):]

    _write_config(config_path, content)
    logger.info("Removed PVT point {%s %s} from corner '%s'",
                voltage, temperature, corner)
    return 0


# ===============================================================================
# Command: add-rc
# ===============================================================================

def cmd_add_rc(args: argparse.Namespace) -> int:
    """Add an RC corner definition to mmmc_config.tcl in-place."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    name = args.name
    if name in parser.rc_corners:
        logger.error("RC corner '%s' already exists", name)
        return 1

    content = _read_config(config_path)
    _backup_config(config_path)

    # Find the closing brace of 'array set rc_corners { ... }'
    pattern = re.compile(
        r'(array\s+set\s+rc_corners\s*\{.*?)(^\})',
        re.DOTALL | re.MULTILINE
    )
    match = pattern.search(content)
    if not match:
        logger.error("Could not find 'array set rc_corners' in config")
        return 1

    new_entry = (
        f'    {name} {{\n'
        f'        temperature         {args.temperature}\n'
        f'        metal_multiplier    {args.metal_mult}\n'
        f'        via_multiplier      {args.via_mult}\n'
        f'        cap_multiplier      {args.cap_mult}\n'
        f'        res_multiplier      {args.res_mult}\n'
        f'    }}\n'
    )

    content = content[:match.start(2)] + new_entry + content[match.start(2):]

    _write_config(config_path, content)
    logger.info("Added RC corner '%s' (temp=%s, cap=%s, res=%s)",
                name, args.temperature, args.cap_mult, args.res_mult)
    return 0


# ===============================================================================
# Command: set-node
# ===============================================================================

def cmd_set_node(args: argparse.Namespace) -> int:
    """Set node scenario assignments in mmmc_config.tcl in-place."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    node = args.node
    setup_scenarios = args.setup.split() if args.setup else None
    hold_scenarios = args.hold.split() if args.hold else None

    if setup_scenarios is None and hold_scenarios is None:
        logger.error("At least one of --setup or --hold is required")
        return 1

    content = _read_config(config_path)
    _backup_config(config_path)

    # Build new setup/hold lists from current + overrides
    current = parser.node_mappings.get(node, {})
    if setup_scenarios is None:
        setup_scenarios = current.get('setup', [])
    if hold_scenarios is None:
        hold_scenarios = current.get('hold', [])

    # Format the new node block
    def _format_list(items: List[str], label: str) -> str:
        if len(items) <= 1:
            val = items[0] if items else ''
            return f'        {label} {{{val}}}'
        lines = [f'        {label} {{']
        for item in items:
            lines.append(f'            {item}')
        lines.append('        }')
        return '\n'.join(lines)

    setup_block = _format_list(setup_scenarios, 'setup')
    hold_block = _format_list(hold_scenarios, 'hold ')

    new_node_block = f'    {node} {{\n{setup_block}\n{hold_block}\n    }}'

    if node in parser.node_mappings:
        # Replace existing node entry in the 'array set mmmc { ... }' block
        # Find the mmmc array body
        array_match = re.search(
            r'array\s+set\s+mmmc\s*\{', content
        )
        if not array_match:
            logger.error("Could not find 'array set mmmc' in config")
            return 1

        # Find the specific node entry within the mmmc array
        # We need to match from the node name to its closing brace, accounting
        # for nested braces.
        start_search = array_match.end()
        node_pat = re.compile(
            rf'(\n\s*#[^\n]*\n)?\s*{re.escape(node)}\s*\{{',
        )
        node_match = node_pat.search(content, start_search)
        if not node_match:
            logger.error("Could not find node '%s' in mmmc array", node)
            return 1

        # Find the matching closing brace for this node
        brace_start = content.index('{', node_match.start() +
                                    (len(node_match.group(1)) if node_match.group(1) else 0))
        pos = brace_start + 1
        depth = 1
        while pos < len(content) and depth > 0:
            if content[pos] == '{':
                depth += 1
            elif content[pos] == '}':
                depth -= 1
            pos += 1

        # Preserve any preceding comment line
        prefix = node_match.group(1) if node_match.group(1) else '\n'
        content = (content[:node_match.start()] + prefix +
                   new_node_block + content[pos:])
    else:
        # Insert new node before the closing brace of the mmmc array
        pattern = re.compile(
            r'(array\s+set\s+mmmc\s*\{.*?)(^\})',
            re.DOTALL | re.MULTILINE
        )
        match = pattern.search(content)
        if not match:
            logger.error("Could not find 'array set mmmc' in config")
            return 1

        content = (content[:match.start(2)] +
                   '\n' + new_node_block + '\n' +
                   content[match.start(2):])

    _write_config(config_path, content)

    s_n = len(setup_scenarios)
    h_n = len(hold_scenarios)
    logger.info("Set node '%s': %d setup, %d hold scenarios", node, s_n, h_n)
    return 0


# ===============================================================================
# Command: list-views
# ===============================================================================

def cmd_list_views(args: argparse.Namespace) -> int:
    """Execute TCL config and list all generated analysis views."""
    config_path = args.config or get_mmmc_config_path()

    if not os.path.isfile(config_path):
        logger.error("Config file not found: %s", config_path)
        return 1

    tcl_data = execute_tcl_config(config_path)
    if tcl_data is None:
        return 1

    views = tcl_data['analysis_views']
    print()
    print(f"  Analysis Views ({len(views)} total)")
    print("  " + "\u2550" * 45)
    for i, v in enumerate(views, 1):
        print(f"    {i:>3}. {v}")
    print()
    return 0


# ===============================================================================
# Command: list-scenarios
# ===============================================================================

def cmd_list_scenarios(args: argparse.Namespace) -> int:
    """List scenarios in a given scenario set."""
    config_path = args.config or get_mmmc_config_path()

    if not os.path.isfile(config_path):
        logger.error("Config file not found: %s", config_path)
        return 1

    tcl_data = execute_tcl_config(config_path)
    if tcl_data is None:
        return 1

    sets = tcl_data['scenario_sets']
    target = args.set

    if target not in sets:
        logger.error("Scenario set '%s' not found. Available: %s",
                      target, ', '.join(sorted(sets.keys())))
        return 1

    scenarios = sets[target]
    print()
    print(f"  Scenario Set: {target} ({len(scenarios)} views)")
    print("  " + "\u2550" * 45)
    for i, s in enumerate(scenarios, 1):
        print(f"    {i:>3}. {s}")
    print()
    return 0


# ===============================================================================
# Command: generate-view-def
# ===============================================================================

def cmd_generate_view_def(args: argparse.Namespace) -> int:
    """Generate Cadence view_definition.tcl from the MMMC config."""
    config_path = args.config or get_mmmc_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    tcl_data = execute_tcl_config(config_path)
    if tcl_data is None:
        return 1

    views = tcl_data['analysis_views']
    if not views:
        logger.error("No analysis views generated from config")
        return 1

    lines = []
    lines.append('# Cadence MMMC View Definition File')
    lines.append('# Auto-generated by CBflow mmmc-manager from mmmc_config.tcl')
    lines.append('')

    # -- Library Sets --
    # Derive unique lib_set references from view naming convention:
    # <mode>_<corner>_<voltage>_<rc>_<temp> -> lib_set = <corner>_<voltage>_<temp>
    lib_sets = set()
    view_info = {}
    for v in views:
        parts = v.split('_')
        # Expected: mode_corner_voltage_rc_temp (minimum 5 parts)
        if len(parts) >= 5:
            mode = parts[0]
            corner = parts[1]
            voltage = parts[2]
            rc = parts[3]
            temp = parts[4]
            lib_ref = f"{corner}_{voltage}_{temp}"
            lib_sets.add(lib_ref)
            view_info[v] = {
                'mode': mode, 'corner': corner, 'voltage': voltage,
                'rc': rc, 'temp': temp, 'lib_ref': lib_ref
            }

    lines.append('# ' + '-' * 70)
    lines.append('# Library Sets')
    lines.append('# ' + '-' * 70)
    lines.append('')
    for ls in sorted(lib_sets):
        lines.append(f'create_library_set -name {ls} \\')
        lines.append(f'    -timing [list ${{lib_dir}}/{ls}_ccs.lib]')
        lines.append('')

    # -- RC Corners --
    lines.append('# ' + '-' * 70)
    lines.append('# RC Corners')
    lines.append('# ' + '-' * 70)
    lines.append('')
    for rc_name, rc_info in sorted(parser.rc_corners.items()):
        temp = rc_info.get('temperature', '25')
        cap = rc_info.get('cap_multiplier', '1.00')
        res = rc_info.get('res_multiplier', '1.00')
        lines.append(f'create_rc_corner -name {rc_name} \\')
        lines.append(f'    -T {temp} \\')
        lines.append(f'    -preRoute_res {res} \\')
        lines.append(f'    -preRoute_cap {cap} \\')
        lines.append(f'    -postRoute_res {res} \\')
        lines.append(f'    -postRoute_cap {cap} \\')
        lines.append(f'    -qx_tech_file [list ${{tech_dir}}/qrc/{rc_name}/qrcTechFile]')
        lines.append('')

    # -- Constraint Modes --
    lines.append('# ' + '-' * 70)
    lines.append('# Constraint Modes')
    lines.append('# ' + '-' * 70)
    lines.append('')
    for mode, info in sorted(parser.operating_modes.items()):
        sdc = info.get('constraint_file', '')
        lines.append(f'create_constraint_mode -name {mode}_mode \\')
        lines.append(f'    -sdc_files [list {sdc}]')
        lines.append('')

    # -- Delay Corners --
    lines.append('# ' + '-' * 70)
    lines.append('# Delay Corners')
    lines.append('# ' + '-' * 70)
    lines.append('')
    for v in views:
        info = view_info.get(v, {})
        if not info:
            continue
        dc_name = f"{v}_dc"
        lib_ref = info['lib_ref']
        rc = info['rc']
        # Map rc shorthand to rc_corners key: rcmax -> rc_max, rctyp -> rc_typ
        rc_key = rc
        if rc in ('rcmax', 'rctyp', 'rcmin'):
            rc_key = rc.replace('rc', 'rc_')
        lines.append(f'create_delay_corner -name {dc_name} \\')
        lines.append(f'    -library_set {lib_ref} \\')
        lines.append(f'    -rc_corner {rc_key}')
        lines.append('')

    # -- Analysis Views --
    lines.append('# ' + '-' * 70)
    lines.append('# Analysis Views')
    lines.append('# ' + '-' * 70)
    lines.append('')
    for v in views:
        info = view_info.get(v, {})
        if not info:
            continue
        mode = info['mode']
        dc_name = f"{v}_dc"
        lines.append(f'create_analysis_view -name {v} \\')
        lines.append(f'    -delay_corner {dc_name} \\')
        lines.append(f'    -constraint_mode {mode}_mode')
        lines.append('')

    # -- Active Views --
    lines.append('# ' + '-' * 70)
    lines.append('# Active Analysis Views')
    lines.append('# ' + '-' * 70)
    lines.append('')
    setup_views = [v for v in views if '_ss_' in v]
    hold_views = [v for v in views if '_ff_' in v]
    if setup_views:
        lines.append(f'set_analysis_view \\')
        lines.append(f'    -setup [list {" ".join(setup_views)}] \\')
        lines.append(f'    -hold  [list {" ".join(hold_views)}]')
        lines.append('')

    content = '\n'.join(lines)

    output_path = getattr(args, 'output', None)
    if output_path:
        out_dir = os.path.dirname(os.path.abspath(output_path))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(output_path, 'w') as f:
            f.write(content)
        logger.info("View definition written to: %s", output_path)
        logger.info("  Analysis views: %d", len(views))
        logger.info("  Library sets: %d", len(lib_sets))
        logger.info("  RC corners: %d", len(parser.rc_corners))
    else:
        print(content)

    return 0


# ===============================================================================
# Argument Parser
# ===============================================================================

# ===============================================================================
# Generate mmmc_config.tcl — user-driven PVT matrix, validated against lib_config
# ===============================================================================

def cmd_generate_mmmc_config(args: argparse.Namespace) -> int:
    """Generate mmmc_config.tcl from user-specified PVT matrix, validated against lib_config.

    Flow: User defines corners/voltages/temps → Cartesian product → validate each
    lib_set_ref against lib_config → skip missing → write only valid scenarios.
    """
    from datetime import datetime

    version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    script_dir = os.path.dirname(os.path.abspath(__file__))
    core_dir = os.path.dirname(os.path.dirname(script_dir))

    # ── Interactive CLI: prompt for missing inputs ──
    print('')
    print('=' * 60)
    print('  CBflow MMMC Config Generator')
    print('=' * 60)
    print('')

    # Tech name
    tech_name = args.tech
    if not tech_name:
        tech_base = os.path.join(core_dir, 'config', 'tech')
        available_techs = sorted(d for d in os.listdir(tech_base)
                                if os.path.isdir(os.path.join(tech_base, d))) if os.path.isdir(tech_base) else []
        if not available_techs:
            logger.error("No technologies found in {}".format(tech_base))
            return 1
        print('  Available technologies:')
        for i, t in enumerate(available_techs, 1):
            print('    {}. {}'.format(i, t))
        choice = input('  Select technology [1-{}]: '.format(len(available_techs))).strip()
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(available_techs):
                tech_name = available_techs[idx]
            else:
                logger.error("Invalid selection")
                return 1
        except ValueError:
            # Allow typing the name directly too
            if choice in available_techs:
                tech_name = choice
            else:
                logger.error("Invalid selection: {}".format(choice))
                return 1
        print('  Selected: {}'.format(tech_name))

    tech_dir = os.path.join(core_dir, 'config', 'tech', tech_name, version)

    # Corners
    corners_input = args.corners.split() if args.corners else None
    if not corners_input:
        raw = input('  Process corners [ss tt ff]: ').strip()
        corners_input = raw.split() if raw else ['ss', 'tt', 'ff']

    # Voltages
    voltages_input = args.voltages.split() if args.voltages else None
    if not voltages_input:
        raw = input('  Voltages (e.g., 0p76v 0p80v 0p84v): ').strip()
        if not raw:
            logger.error("Voltages are required")
            return 1
        voltages_input = raw.split()

    # Temperatures
    temps_input = args.temperatures.split() if args.temperatures else None
    if not temps_input:
        raw = input('  Temperatures (e.g., 150c 25c m40c): ').strip()
        if not raw:
            logger.error("Temperatures are required")
            return 1
        temps_input = raw.split()

    print('')

    # Build full Cartesian product: corners × voltages × temps
    requested_pvt = {}  # corner → [(voltage, temp), ...]
    all_lib_refs = []   # all lib_set_ref strings to validate
    for corner in corners_input:
        pts = []
        for v in voltages_input:
            for t in temps_input:
                pts.append((v, t))
                all_lib_refs.append('{}_{}'.format(corner, '{}_{}'.format(v, t)))
        requested_pvt[corner] = pts

    total_requested = sum(len(pts) for pts in requested_pvt.values())
    logger.info("Requested PVT matrix: {} corners x {} voltages x {} temps = {} combinations".format(
        len(corners_input), len(voltages_input), len(temps_input), total_requested))

    # ── 2. Resolve lib_config for validation ──
    lib_tag = args.lib_tag if hasattr(args, 'lib_tag') and args.lib_tag else None
    lib_config_path = None

    if lib_tag:
        lib_config_path = os.path.join(tech_dir, 'lib_config_{}.tcl'.format(lib_tag))
    else:
        # Try default first
        default_path = os.path.join(tech_dir, 'lib_config.tcl')
        if os.path.exists(default_path):
            lib_config_path = default_path
        else:
            # No default — find available tagged configs
            available = sorted(f for f in os.listdir(tech_dir)
                              if f.startswith('lib_config') and f.endswith('.tcl'))
            if len(available) == 1:
                # Only one lib_config exists — use it automatically
                lib_config_path = os.path.join(tech_dir, available[0])
                tag_found = available[0].replace('lib_config_', '').replace('lib_config', '').replace('.tcl', '')
                logger.info("Auto-selected: {} (only lib_config available)".format(available[0]))
            elif len(available) > 1:
                logger.error("No default lib_config.tcl found. Multiple tagged configs available:")
                for a in available:
                    tag = a.replace('lib_config_', '').replace('.tcl', '')
                    logger.error("  {} → use --lib-tag {}".format(a, tag))
                logger.error("Please specify --lib-tag to select which one to validate against")
                return 1
            else:
                logger.error("No lib_config found in {}".format(tech_dir))
                logger.info("  Run: cbflow flow library-manager generate --tech {}".format(tech_name))
                return 1

    if not os.path.exists(lib_config_path):
        logger.error("lib_config not found: {}".format(lib_config_path))
        available = sorted(f for f in os.listdir(tech_dir)
                          if f.startswith('lib_config') and f.endswith('.tcl'))
        if available:
            logger.error("  Available: {}".format(', '.join(available)))
        return 1

    with open(lib_config_path, 'r') as f:
        lib_content = f.read()

    logger.info("Validating against: {}".format(os.path.basename(lib_config_path)))

    # ── 3. Validate each lib_set_ref against lib_config ──
    track_for_check = args.track if hasattr(args, 'track') and args.track else None
    if not track_for_check:
        trk_m = re.search(r'set tech\((\S+?),lib,\S+?,timing\)', lib_content)
        if trk_m:
            track_for_check = trk_m.group(1).split(',')[0]

    valid_refs = set()
    missing_refs = set()
    for ref in all_lib_refs:
        if track_for_check:
            pattern = re.escape('tech({},lib,{},timing)'.format(track_for_check, ref))
        else:
            pattern = r'tech\(\S+,lib,{},timing\)'.format(re.escape(ref))
        if re.search(pattern, lib_content):
            valid_refs.add(ref)
        else:
            missing_refs.add(ref)

    # Filter PVT: only keep combos that have matching libs
    valid_pvt = {}
    skipped_pvt = {}
    for corner, pts in requested_pvt.items():
        valid_pts = []
        skip_pts = []
        for v, t in pts:
            ref = '{}_{}'.format(corner, '{}_{}'.format(v, t))
            if ref in valid_refs:
                valid_pts.append((v, t))
            else:
                skip_pts.append((v, t))
        if valid_pts:
            valid_pvt[corner] = valid_pts
        if skip_pts:
            skipped_pvt[corner] = skip_pts

    process_corners = sorted(valid_pvt.keys())

    # VT filter
    vt_filter = args.vts.split() if hasattr(args, 'vts') and args.vts else None

    # ── 4. Derive voltage/temperature ranges from valid PVT ──
    def v_to_float(vs):
        return float(vs.rstrip('v').replace('p', '.'))
    def t_to_int(ts):
        ts = ts.rstrip('c')
        return -int(ts[1:]) if ts.startswith('m') else int(ts)

    v_floats = sorted(set(v_to_float(v) for v in voltages_input))
    v_nom = v_floats[len(v_floats) // 2] if v_floats else 0.80
    v_low = v_floats[0] if v_floats else 0.76
    v_high = v_floats[-1] if v_floats else 0.84

    t_ints = sorted(set(t_to_int(t) for t in temps_input))
    t_hot = t_ints[-1] if t_ints else 150
    t_nom = 25 if 25 in t_ints else (t_ints[len(t_ints) // 2] if t_ints else 25)
    t_cold = t_ints[0] if t_ints else -40

    # ── 5. Operating modes ──
    modes = {}
    sdc_pattern = args.sdc_pattern if hasattr(args, 'sdc_pattern') and args.sdc_pattern else '${design_name}_{mode}.sdc'
    if hasattr(args, 'modes') and args.modes:
        for mode_name in args.modes.split():
            modes[mode_name] = sdc_pattern.replace('{mode}', mode_name)
    else:
        existing_config = os.path.join(core_dir, 'config', 'flow', version, 'mmmc_config.tcl')
        if os.path.exists(existing_config):
            try:
                p = MmmcConfigParser(existing_config)
                for m, props in p.operating_modes.items():
                    modes[m] = props.get('constraint_file', sdc_pattern.replace('{mode}', m))
            except Exception:
                pass
        if not modes:
            modes = {'func': '${design_name}_func.sdc', 'test': '${design_name}_test.sdc'}

    # ── 6. RC corners from existing or defaults ──
    rc_corners_data = {}
    existing_config = os.path.join(core_dir, 'config', 'flow', version, 'mmmc_config.tcl')
    if os.path.exists(existing_config):
        try:
            p = MmmcConfigParser(existing_config)
            rc_corners_data = p.rc_corners
        except Exception:
            pass
    if not rc_corners_data:
        rc_corners_data = {
            'rc_max': {'temperature': '125', 'metal_multiplier': '1.15', 'via_multiplier': '1.25',
                       'cap_multiplier': '1.10', 'res_multiplier': '1.15'},
            'rc_typ': {'temperature': '25', 'metal_multiplier': '1.00', 'via_multiplier': '1.00',
                       'cap_multiplier': '1.00', 'res_multiplier': '1.00'},
            'rc_min': {'temperature': '-40', 'metal_multiplier': '0.85', 'via_multiplier': '0.75',
                       'cap_multiplier': '0.90', 'res_multiplier': '0.85'},
        }

    # ── 7. Node assignments (only from valid PVT) ──
    total_views = len(modes) * sum(len(pts) for pts in valid_pvt.values())

    def pick_scenarios(pvt_type, count, mode='func'):
        pts = valid_pvt.get(pvt_type, [])
        rc = {'ss': 'rcmax', 'tt': 'rctyp', 'ff': 'rcmin'}.get(pvt_type, 'rctyp')
        return ['{}_{}_{}_{}_{}'.format(mode, pvt_type, v, rc, t) for v, t in pts[:count]]

    nodes = {
        'init_design': {'setup': pick_scenarios('tt', 1) or pick_scenarios('ss', 1),
                        'hold':  pick_scenarios('tt', 1) or pick_scenarios('ff', 1)},
        'floorplan':   {'setup': pick_scenarios('ss', 1), 'hold': pick_scenarios('ff', 1)},
        'powerplan':   {'setup': pick_scenarios('ss', 1), 'hold': pick_scenarios('ff', 1)},
        'placement':   {'setup': pick_scenarios('ss', 2), 'hold': pick_scenarios('ff', 2)},
        'cts':         {'setup': pick_scenarios('ss', 3), 'hold': pick_scenarios('ff', 3)},
        'cts_opt':     {'setup': pick_scenarios('ss', 3), 'hold': pick_scenarios('ff', 3)},
        'route':       {'setup': pick_scenarios('ss', 3), 'hold': pick_scenarios('ff', 3)},
        'post_route':  {'setup': pick_scenarios('ss', 4), 'hold': pick_scenarios('ff', 4)},
        'synthesis':   {'setup': pick_scenarios('ss', 3), 'hold': pick_scenarios('ff', 2)},
    }
    # Signoff: all valid corners
    nodes['signoff'] = {
        'setup': ['{}_ss_{}_rcmax_{}'.format('func', v, t) for v, t in valid_pvt.get('ss', [])],
        'hold':  ['{}_ff_{}_rcmin_{}'.format('func', v, t) for v, t in valid_pvt.get('ff', [])],
    }

    # ── Write mmmc_config.tcl ──
    output_path = os.path.join(core_dir, 'config', 'flow', version, 'mmmc_config.tcl')

    lines = []
    w = lines.append

    w('#!/usr/bin/env tclsh')
    w('# ' + '=' * 77)
    w('# CBflow MMMC Configuration — Auto-Generated')
    w('# Generated: {} | Tech: {} | Corners: {}'.format(
        datetime.now().strftime('%Y-%m-%d %H:%M'), tech_name, len(valid_refs)))
    w('# Source: {}'.format(os.path.basename(lib_config_path)))
    w('# Views: {} | Modes: {} | Process: {}'.format(
        total_views, " ".join(sorted(modes.keys())), " ".join(process_corners)))
    w('# Regenerate: cbflow flow mmmc-manager generate --tech {}'.format(tech_name))
    w('# ' + '=' * 77)
    w('')

    # Global config
    w('# Global MMMC configuration')
    w('array set mmmc_config {')
    w('    timing_derate_early    0.95')
    w('    timing_derate_late     1.05')
    w('    clock_uncertainty      0.1')
    w('    max_transition         0.5')
    w('    max_capacitance        2.0')
    w('    max_fanout             16')
    w('}')
    w('')

    # Voltage & Temperature
    w('# ' + '=' * 77)
    w('# VOLTAGE & TEMPERATURE (discovered from lib_config corners)')
    w('# ' + '=' * 77)
    w('')
    w('set mmmc(voltage,nom)        {:.2f}'.format(v_nom))
    w('set mmmc(voltage,low)        {:.2f}'.format(v_low))
    w('set mmmc(voltage,high)       {:.2f}'.format(v_high))
    w('set mmmc(temperature,hot)    {}'.format(t_hot))
    w('set mmmc(temperature,nom)    {}'.format(t_nom))
    w('set mmmc(temperature,cold)   {}'.format(t_cold))
    w('')

    # Process corners
    w('# ' + '=' * 77)
    w('# PROCESS CORNERS & OPERATING MODES')
    w('# ' + '=' * 77)
    w('')
    w('set mmmc(process_corners) {{{}}}'.format(' '.join(process_corners)))
    w('')

    # Operating modes
    w('array set operating_modes {')
    for mode_name in sorted(modes.keys()):
        sdc = modes[mode_name]
        w('    {} {{ constraint_file "{}" }}'.format(mode_name, sdc))
    w('}')
    w('')

    # PVT points (only validated combos — missing lib sets skipped)
    w('# ' + '=' * 77)
    w('# PVT POINTS (user-specified, validated against lib_config)')
    w('# ' + '=' * 77)
    w('')
    for pvt_type in process_corners:
        pts = valid_pvt.get(pvt_type, [])
        pvt_str = ' '.join('{{{} {}}}'.format(v, t) for v, t in pts)
        w('set mmmc(pvt,{}) {{{}}}'.format(pvt_type, pvt_str))
    w('')

    # RC pairing
    w('# Corner -> RC corner pairing')
    for pvt_type in process_corners:
        rc = {'ss': 'rcmax', 'tt': 'rctyp', 'ff': 'rcmin'}.get(pvt_type, 'rctyp')
        w('set mmmc(rc_pair,{}) "{}"'.format(pvt_type, rc))
    w('')

    # Analysis view generation (TCL code — same as before)
    w('# ' + '=' * 77)
    w('# AUTO-GENERATE ANALYSIS VIEWS & SCENARIO SETS')
    w('# ' + '=' * 77)
    w('')
    w('array set analysis_views {}')
    w('foreach _mode [array names operating_modes] {')
    w('    set _sdc [dict get $operating_modes($_mode) constraint_file]')
    w('    foreach _corner $mmmc(process_corners) {')
    w('        set _rc $mmmc(rc_pair,$_corner)')
    w('        switch $_corner {')
    w('            ss { set _atype "setup" }')
    w('            tt { set _atype "setup_hold" }')
    w('            ff { set _atype "hold" }')
    w('        }')
    w('        foreach _pvt $mmmc(pvt,$_corner) {')
    w('            set _v [lindex $_pvt 0]')
    w('            set _t [lindex $_pvt 1]')
    w('            set _name "${_mode}_${_corner}_${_v}_${_rc}_${_t}"')
    w('            set _lib_ref "${_corner}_${_v}_${_t}"')
    w('            set analysis_views($_name) [list \\')
    w('                corner $_corner mode $_mode voltage $_v temperature $_t \\')
    w('                analysis_type $_atype constraint_file $_sdc \\')
    w('                lib_set_ref $_lib_ref rc_corner $_rc \\')
    w('            ]')
    w('        }')
    w('    }')
    w('}')
    w('')

    # Scenario sets
    w('# ── Scenario sets ──')
    w('set _all [lsort [array names analysis_views]]')
    w('')
    w('array set mmmc_scenario_sets {}')
    w('set mmmc_scenario_sets(setup)       [lsearch -all -inline $_all "*_ss_*"]')
    w('set mmmc_scenario_sets(hold)        [lsearch -all -inline $_all "*_ff_*"]')
    w('set mmmc_scenario_sets(power)       [concat \\')
    w('    [lsearch -all -inline $_all "*_tt_*_rctyp_*"] \\')
    w('    [lsearch -all -inline $_all "*_ss_*_rctyp_*"] \\')
    w(']')
    w('set mmmc_scenario_sets(signoff)     [concat \\')
    w('    $mmmc_scenario_sets(setup) \\')
    w('    $mmmc_scenario_sets(hold) \\')
    w('    [lsearch -all -inline $_all "func_tt_*_rctyp_*"] \\')
    w(']')
    w('set mmmc_scenario_sets(all)         $_all')
    w('set mmmc_scenario_sets(sta_setup)   $mmmc_scenario_sets(setup)')
    w('set mmmc_scenario_sets(sta_hold)    $mmmc_scenario_sets(hold)')
    w('set mmmc_scenario_sets(sta_signoff) $mmmc_scenario_sets(signoff)')
    w('')

    # RC corners
    w('# ' + '=' * 77)
    w('# RC CORNERS')
    w('# ' + '=' * 77)
    w('')
    w('array set rc_corners {')
    for rc_name in sorted(rc_corners_data.keys()):
        props = rc_corners_data[rc_name]
        w('    {} {{'.format(rc_name))
        for k in ['temperature', 'metal_multiplier', 'via_multiplier', 'cap_multiplier', 'res_multiplier']:
            if k in props:
                w('        {:<24s}{}'.format(k, props[k]))
        w('    }')
    w('}')
    w('')
    w('set rc_corner_list [lsort [array names rc_corners]]')
    w('')

    # Node assignments — NOT in mmmc_config (project-level, goes in project_config.tcl)
    w('# ' + '=' * 77)
    w('# NODE-SPECIFIC SCENARIO ASSIGNMENTS')
    w('# Defined in project_config.tcl (project-level decision, not auto-generated)')
    w('# ' + '=' * 77)
    w('')

    # Build node assignment block for project_config
    node_lines = []
    nw = node_lines.append
    nw('# ── MMMC Node Scenario Assignments ──')
    nw('# Generated by: cbflow flow mmmc-manager generate --tech {}'.format(tech_name))
    nw('# Add/modify these in project_config.tcl')
    nw('array set mmmc {')
    for node_name in ['init_design', 'floorplan', 'powerplan', 'placement',
                      'cts', 'cts_opt', 'route', 'post_route', 'signoff', 'synthesis']:
        if node_name not in nodes:
            continue
        nd = nodes[node_name]
        nw('    {} {{'.format(node_name))
        for atype in ['setup', 'hold']:
            scenarios = nd.get(atype, [])
            if len(scenarios) <= 1:
                nw('        {} {{{}}}'.format(atype, scenarios[0] if scenarios else ''))
            else:
                nw('        {} {{'.format(atype))
                for s in scenarios:
                    nw('            {}'.format(s))
                nw('        }')
        nw('    }')
        nw('')
    nw('}')
    node_assignment_text = '\n'.join(node_lines) + '\n'

    # Write — confirm overwrite + backup
    output_text = '\n'.join(lines) + '\n'

    if os.path.exists(output_path):
        print('  WARNING: {} already exists'.format(output_path))
        confirm = input('  Overwrite? (y/n) [y]: ').strip().lower()
        if confirm and confirm not in ('y', 'yes'):
            print('  Aborted — no changes made.')
            return 0
        # Backup with timestamp
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_path = '{}.bak_{}'.format(output_path, ts)
        shutil.copy2(output_path, backup_path)
        print('  Backup: {}'.format(backup_path))

    with open(output_path, 'w') as fh:
        fh.write(output_text)

    # Write node assignments template alongside mmmc_config
    node_template_path = os.path.join(os.path.dirname(output_path), 'mmmc_node_scenarios.tcl')
    with open(node_template_path, 'w') as fh:
        fh.write(node_assignment_text)

    print('  Node scenario template: {}'.format(node_template_path))
    print('  Copy node assignments to project_config.tcl if not already present')

    # ── Report ──
    print('')
    print('=' * 60)
    print('  MMMC Generation Report — {}'.format(tech_name))
    print('=' * 60)
    print('  Validated against: {}'.format(os.path.basename(lib_config_path)))
    print('')
    print('  Requested PVT matrix:')
    print('    Corners:      {}'.format(' '.join(corners_input)))
    print('    Voltages:     {}'.format(' '.join(voltages_input)))
    print('    Temperatures: {}'.format(' '.join(temps_input)))
    print('    Total combos: {}'.format(total_requested))
    print('')

    # Validation results
    print('  Library Set Validation{}:'.format(
        ' (track={})'.format(track_for_check) if track_for_check else ''))
    for ref in sorted(all_lib_refs):
        status = 'ok' if ref in valid_refs else 'SKIPPED (no libs)'
        sym = ' ' if ref in valid_refs else '!'
        print('   {} {:<30s} {}'.format(sym, ref, status))
    print('')
    print('  Valid:   {} / {}  |  Skipped: {}'.format(
        len(valid_refs), len(all_lib_refs), len(missing_refs)))

    if skipped_pvt:
        print('')
        print('  Skipped scenarios (no matching lib set in lib_config):')
        for corner, pts in sorted(skipped_pvt.items()):
            for v, t in pts:
                print('    {}_{}_{} — not in lib_config'.format(corner, v, t))

    print('')
    print('  Generated:')
    print('    Process corners: {}'.format(' '.join(process_corners)))
    for pc in process_corners:
        print('      {}: {} PVT points'.format(pc, len(valid_pvt.get(pc, []))))
    print('    Modes: {}'.format(' '.join(sorted(modes.keys()))))
    print('    Analysis views: {}'.format(total_views))
    if vt_filter:
        print('    VT filter: {}'.format(' '.join(vt_filter)))
    print('')
    print('  Output: {}'.format(output_path))
    print('=' * 60)
    print('')

    if missing_refs:
        logger.warning('{} PVT combos skipped — no matching libs in lib_config'.format(len(missing_refs)))

    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser with all subcommands."""
    top = argparse.ArgumentParser(
        prog='cbflow flow mmmc-manager',
        description='CBflow MMMC Manager -- Multi-Mode Multi-Corner configuration management',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow mmmc-manager show
  cbflow flow mmmc-manager show --config path/to/mmmc_config.tcl
  cbflow flow mmmc-manager validate
  cbflow flow mmmc-manager add-mode --name scan --sdc "${design_name}_scan.sdc"
  cbflow flow mmmc-manager remove-mode --name scan
  cbflow flow mmmc-manager add-pvt --corner ss --voltage 0p72v --temperature 175c
  cbflow flow mmmc-manager remove-pvt --corner ss --voltage 0p80v --temperature 25c
  cbflow flow mmmc-manager add-rc --name rc_max_cworst --temperature 125 \\
      --cap_mult 1.15 --res_mult 1.25 --metal_mult 1.15 --via_mult 1.25
  cbflow flow mmmc-manager set-node --node cts --setup "scen1 scen2" --hold "scen3"
  cbflow flow mmmc-manager list-views
  cbflow flow mmmc-manager list-scenarios --set signoff
  cbflow flow mmmc-manager generate-view-def --output view_definition.tcl
        """
    )

    sub = top.add_subparsers(dest='command', help='MMMC manager commands')

    # -- show --
    p = sub.add_parser('show', help='Display current MMMC config in table format')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl (auto-detected if omitted)')

    # -- validate --
    p = sub.add_parser('validate', help='Check config consistency')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl (auto-detected if omitted)')

    # -- add-mode --
    p = sub.add_parser('add-mode', help='Add an operating mode')
    p.add_argument('--name', required=True, help='Mode name (e.g., scan)')
    p.add_argument('--sdc', required=True,
                   help='Constraint file (e.g., "${design_name}_scan.sdc")')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- remove-mode --
    p = sub.add_parser('remove-mode', help='Remove an operating mode')
    p.add_argument('--name', required=True, help='Mode name to remove')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- add-pvt --
    p = sub.add_parser('add-pvt', help='Add a PVT point to a corner')
    p.add_argument('--corner', required=True, help='Process corner (e.g., ss)')
    p.add_argument('--voltage', required=True, help='Voltage (e.g., 0p72v)')
    p.add_argument('--temperature', required=True, help='Temperature (e.g., 175c)')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- remove-pvt --
    p = sub.add_parser('remove-pvt', help='Remove a PVT point from a corner')
    p.add_argument('--corner', required=True, help='Process corner (e.g., ss)')
    p.add_argument('--voltage', required=True, help='Voltage (e.g., 0p80v)')
    p.add_argument('--temperature', required=True, help='Temperature (e.g., 25c)')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- add-rc --
    p = sub.add_parser('add-rc', help='Add an RC corner definition')
    p.add_argument('--name', required=True,
                   help='RC corner name (e.g., rc_max_cworst)')
    p.add_argument('--temperature', required=True, help='Temperature (e.g., 125)')
    p.add_argument('--cap_mult', required=True, help='Capacitance multiplier')
    p.add_argument('--res_mult', required=True, help='Resistance multiplier')
    p.add_argument('--metal_mult', required=True, help='Metal multiplier')
    p.add_argument('--via_mult', required=True, help='Via multiplier')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- set-node --
    p = sub.add_parser('set-node', help='Set node scenario assignments')
    p.add_argument('--node', required=True, help='Node name (e.g., cts)')
    p.add_argument('--setup', default=None,
                   help='Setup scenarios (space-separated, quoted)')
    p.add_argument('--hold', default=None,
                   help='Hold scenarios (space-separated, quoted)')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- list-views --
    p = sub.add_parser('list-views',
                       help='Execute TCL and list all generated analysis views')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- list-scenarios --
    p = sub.add_parser('list-scenarios', help='List scenarios in a set')
    p.add_argument('--set', required=True, dest='set',
                   help='Scenario set name (e.g., setup, hold, signoff, all)')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- generate-view-def --
    p = sub.add_parser('generate-view-def',
                       help='Generate Cadence view_definition.tcl')
    p.add_argument('--output', default=None,
                   help='Output file path (default: stdout)')
    p.add_argument('--config', default=None,
                   help='Path to mmmc_config.tcl')

    # -- generate --
    p = sub.add_parser('generate',
                       help='Generate mmmc_config.tcl — interactive CLI, validated against lib_config')
    p.add_argument('--tech', default=None,
                   help='Technology name (e.g., gf_22nm). Prompted if omitted')
    p.add_argument('--corners', default=None,
                   help='Process corners (e.g., "ss tt ff"). Prompted if omitted')
    p.add_argument('--voltages', default=None,
                   help='Voltage points (e.g., "0p76v 0p80v 0p84v"). Prompted if omitted')
    p.add_argument('--temperatures', default=None,
                   help='Temperature points (e.g., "150c 25c m40c"). Prompted if omitted')
    p.add_argument('--vts', default=None,
                   help='VT flavors to include (e.g., "svt lvt hvt")')
    p.add_argument('--modes', default=None,
                   help='Operating modes (e.g., "func test scan"). Default: from existing config or func+test')
    p.add_argument('--sdc-pattern', default=None,
                   help='SDC naming pattern (default: ${design_name}_{mode}.sdc)')
    p.add_argument('--track', default=None,
                   help='Track to validate against (e.g., 9T)')
    p.add_argument('--lib-tag', default=None,
                   help='lib_config tag (e.g., P0 reads lib_config_P0.tcl)')

    return top


# ===============================================================================
# Main Entry Point
# ===============================================================================

def main() -> int:
    """Main entry point for mmmc-manager."""
    top = create_parser()
    args = top.parse_args()

    if not args.command:
        top.print_help()
        return 0

    dispatch = {
        'show':              cmd_show,
        'validate':          cmd_validate,
        'add-mode':          cmd_add_mode,
        'remove-mode':       cmd_remove_mode,
        'add-pvt':           cmd_add_pvt,
        'remove-pvt':        cmd_remove_pvt,
        'add-rc':            cmd_add_rc,
        'set-node':          cmd_set_node,
        'list-views':        cmd_list_views,
        'list-scenarios':    cmd_list_scenarios,
        'generate-view-def': cmd_generate_view_def,
        'generate':          cmd_generate_mmmc_config,
    }

    handler = dispatch.get(args.command)
    if not handler:
        logger.error("Unknown command: %s", args.command)
        return 1

    try:
        return handler(args)
    except KeyboardInterrupt:
        print("\nAborted.")
        return 1
    except PermissionError as e:
        logger.error("Permission denied: %s", e)
        return 1
    except FileNotFoundError as e:
        logger.error("File not found: %s", e)
        return 1
    except Exception as e:
        logger.error("Error: %s: %s", type(e).__name__, e)
        return 1


if __name__ == '__main__':
    sys.exit(main())
