#!/usr/bin/env python3
# ===============================================================================
# CBFlow - MMMC Manager Command Handler
# Description: Comprehensive Multi-Mode Multi-Corner management with interactive
#              CLI for scenario creation, validation, and view definition generation.
# Usage: cbflow flow mmmc-manager <subcommand> [options]
# ===============================================================================

import argparse
import os
import sys
import re
import json
import logging
from pathlib import Path
from typing import List, Dict, Optional, Tuple, Set
from collections import OrderedDict

# Configure unified logging
from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.mmmc_manager')


def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory from environment or determine from script location."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


# -------------------------------------------------------------------------------
# Prompt Helpers
# -------------------------------------------------------------------------------

def _prompt(msg, default=None):
    """Prompt user for input with optional default value."""
    while True:
        try:
            if default is not None:
                val = input(f"{msg} [{default}]: ").strip()
                return val if val else str(default)
            val = input(f"{msg}: ").strip()
            if not val:
                print("  [!] Input cannot be empty. Please try again.")
                continue
            return val
        except (EOFError, KeyboardInterrupt):
            print("\n  [!] Aborted by user.")
            sys.exit(1)


def _prompt_int(msg, default=None, min_val=None, max_val=None):
    """Prompt for an integer with validation."""
    while True:
        try:
            raw = _prompt(msg, default)
            val = int(raw)
            if min_val is not None and val < min_val:
                print(f"  [!] Value must be >= {min_val}. Got: {val}")
                continue
            if max_val is not None and val > max_val:
                print(f"  [!] Value must be <= {max_val}. Got: {val}")
                continue
            return val
        except ValueError:
            print(f"  [!] Please enter a number. Got: '{raw}'")


def _prompt_float(msg, default=None, min_val=None, max_val=None):
    """Prompt for a float with validation."""
    while True:
        try:
            raw = _prompt(msg, default)
            val = float(raw)
            if min_val is not None and val < min_val:
                print(f"  [!] Value must be >= {min_val}. Got: {val}")
                continue
            if max_val is not None and val > max_val:
                print(f"  [!] Value must be <= {max_val}. Got: {val}")
                continue
            return val
        except ValueError:
            print(f"  [!] Please enter a number (e.g., 0.80). Got: '{raw}'")


def _prompt_list(msg, default=None, valid_items=None):
    """Prompt for a comma-separated list with validation."""
    while True:
        raw = _prompt(msg, default)
        items = [x.strip() for x in raw.split(',') if x.strip()]
        if not items:
            print("  [!] Please enter at least one item (comma-separated).")
            continue
        if valid_items:
            bad = [x for x in items if x not in valid_items]
            if bad:
                print(f"  [!] Invalid: {', '.join(bad)}. Valid options: {', '.join(valid_items)}")
                continue
        return items


def _confirm(msg="Confirm?", default=True):
    """Ask user for yes/no confirmation."""
    suffix = "Y/n" if default else "y/N"
    while True:
        try:
            val = input(f"{msg} [{suffix}]: ").strip().lower()
            if not val:
                return default
            if val in ('y', 'yes'):
                return True
            if val in ('n', 'no'):
                return False
            print("  [!] Please enter 'y' or 'n'.")
        except (EOFError, KeyboardInterrupt):
            print("\n  [!] Aborted by user.")
            sys.exit(1)


# -------------------------------------------------------------------------------
# TCL Config Parser
# -------------------------------------------------------------------------------

class MmmcConfigParser:
    """Parse mmmc_config.tcl into Python data structures."""

    def __init__(self, config_path: str):
        self.config_path = config_path
        self.raw_content = ""
        self.process_corners = {}
        self.operating_modes = {}
        self.rc_corners = {}
        self.scenario_sets = {}
        self.analysis_views = {}
        self.node_mappings = {}

    def parse(self) -> bool:
        """Parse the mmmc_config.tcl file. Returns True on success."""
        if not os.path.isfile(self.config_path):
            logger.error(f"Config file not found: {self.config_path}")
            return False

        with open(self.config_path, 'r') as f:
            self.raw_content = f.read()

        self.process_corners = self._parse_tcl_array('process_corners')
        self.operating_modes = self._parse_tcl_array('operating_modes')
        self.rc_corners = self._parse_tcl_array('rc_corners')
        self.scenario_sets = self._parse_tcl_array('mmmc_scenario_sets')
        self.analysis_views = self._parse_tcl_array('analysis_views')
        self.node_mappings = self._parse_tcl_array('mmmc')
        return True

    def _parse_tcl_array(self, array_name: str) -> Dict:
        """Parse a TCL 'array set <name> { ... }' block into a dict of dicts."""
        # Match the array set block, handling nested braces
        pattern = re.compile(
            rf'array\s+set\s+{re.escape(array_name)}\s*\{{',
            re.DOTALL
        )
        match = pattern.search(self.raw_content)
        if not match:
            return {}

        # Find matching closing brace
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

        block = self.raw_content[start:pos - 1]
        return self._parse_entries(block)

    def _parse_entries(self, block: str) -> Dict:
        """Parse top-level key-value entries from a TCL array block."""
        result = {}
        # Remove comment lines
        lines = []
        for line in block.split('\n'):
            stripped = line.strip()
            if not stripped.startswith('#'):
                lines.append(line)
        block = '\n'.join(lines)

        # Find entries: "key" { ... } or key { ... }
        pos = 0
        while pos < len(block):
            # Skip whitespace
            while pos < len(block) and block[pos] in ' \t\n\r':
                pos += 1
            if pos >= len(block):
                break

            # Parse key (quoted or unquoted)
            key = None
            if block[pos] == '"':
                end_quote = block.index('"', pos + 1)
                key = block[pos + 1:end_quote]
                pos = end_quote + 1
            else:
                key_start = pos
                while pos < len(block) and block[pos] not in ' \t\n\r{':
                    pos += 1
                key = block[key_start:pos]

            if not key:
                break

            # Skip whitespace to opening brace
            while pos < len(block) and block[pos] in ' \t\n\r':
                pos += 1
            if pos >= len(block) or block[pos] != '{':
                break

            # Find matching closing brace for value
            pos += 1  # skip opening brace
            depth = 1
            val_start = pos
            while pos < len(block) and depth > 0:
                if block[pos] == '{':
                    depth += 1
                elif block[pos] == '}':
                    depth -= 1
                pos += 1

            value_str = block[val_start:pos - 1].strip()
            result[key] = self._parse_value_block(value_str)

        return result

    def _parse_value_block(self, value_str: str) -> Dict:
        """Parse key-value pairs from a TCL block body."""
        data = {}
        # Try to parse as key-value pairs
        tokens = self._tokenize_tcl(value_str)
        i = 0
        while i < len(tokens) - 1:
            key = tokens[i]
            val = tokens[i + 1]
            # Strip quotes from values
            if isinstance(val, str) and val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            data[key] = val
            i += 2
        return data

    def _tokenize_tcl(self, text: str) -> List[str]:
        """Tokenize a TCL value string, handling braces and quotes."""
        tokens = []
        pos = 0
        while pos < len(text):
            # Skip whitespace and newlines
            while pos < len(text) and text[pos] in ' \t\n\r':
                pos += 1
            if pos >= len(text):
                break

            # Skip comments
            if text[pos] == '#':
                while pos < len(text) and text[pos] != '\n':
                    pos += 1
                continue

            # Quoted string
            if text[pos] == '"':
                end = pos + 1
                while end < len(text) and text[end] != '"':
                    if text[end] == '\\':
                        end += 1
                    end += 1
                tokens.append(text[pos:end + 1])
                pos = end + 1
            # Braced block
            elif text[pos] == '{':
                depth = 1
                end = pos + 1
                while end < len(text) and depth > 0:
                    if text[end] == '{':
                        depth += 1
                    elif text[end] == '}':
                        depth -= 1
                    end += 1
                # Return inner content without braces
                inner = text[pos + 1:end - 1].strip()
                tokens.append(inner)
                pos = end
            # Bare word
            else:
                end = pos
                while end < len(text) and text[end] not in ' \t\n\r{}':
                    end += 1
                tokens.append(text[pos:end])
                pos = end

        return tokens


# -------------------------------------------------------------------------------
# Scenario Generator
# -------------------------------------------------------------------------------

class MmmcScenarioGenerator:
    """Generate MMMC scenarios from process corners, modes, voltages, temps, and RC corners."""

    CORNER_NAMES = {
        'ss': 'slow_slow',
        'tt': 'typical_typical',
        'ff': 'fast_fast',
        'sf': 'slow_fast',
        'fs': 'fast_slow',
    }

    CORNER_DESCRIPTIONS = {
        'ss': 'Slow NMOS, Slow PMOS (worst setup timing)',
        'tt': 'Typical NMOS, Typical PMOS (nominal)',
        'ff': 'Fast NMOS, Fast PMOS (worst hold timing)',
        'sf': 'Slow NMOS, Fast PMOS',
        'fs': 'Fast NMOS, Slow PMOS',
    }

    RC_DESCRIPTIONS = {
        'rcmax': ('Maximum RC (worst setup)', 'setup_critical'),
        'rctyp': ('Typical RC (nominal)', 'nominal'),
        'rcmin': ('Minimum RC (worst hold)', 'hold_critical'),
    }

    RC_MULTIPLIERS = {
        'rcmax': {'metal': 1.15, 'via': 1.25, 'cap': 1.10, 'res': 1.15},
        'rctyp': {'metal': 1.00, 'via': 1.00, 'cap': 1.00, 'res': 1.00},
        'rcmin': {'metal': 0.85, 'via': 0.75, 'cap': 0.90, 'res': 0.85},
    }

    @staticmethod
    def _infer_rc_usage(rc_name: str) -> str:
        """Infer RC corner usage from its name pattern."""
        lower = rc_name.lower()
        if 'max' in lower or 'worst' in lower:
            return 'setup_critical'
        if 'min' in lower or 'best' in lower:
            return 'hold_critical'
        if 'typ' in lower or 'nom' in lower:
            return 'nominal'
        return 'user_defined'

    @staticmethod
    def _infer_rc_description(rc_name: str) -> str:
        """Infer RC corner description from its name."""
        lower = rc_name.lower()
        if 'max' in lower and 'cworst' in lower:
            return 'Maximum RC, C-worst extraction'
        if 'min' in lower and 'cbest' in lower:
            return 'Minimum RC, C-best extraction'
        if 'max' in lower:
            return f'Maximum RC ({rc_name})'
        if 'min' in lower:
            return f'Minimum RC ({rc_name})'
        if 'typ' in lower:
            return f'Typical RC ({rc_name})'
        return f'Custom RC corner ({rc_name})'

    SETUP_CORNERS = {'ss', 'sf'}
    HOLD_CORNERS = {'ff', 'fs'}
    NOMINAL_CORNERS = {'tt'}

    def __init__(self):
        self.corners = []
        self.voltage_nom = 0.0
        self.voltage_low = 0.0
        self.voltage_high = 0.0
        self.temperatures = []
        self.modes = []
        self.rc_corners = []
        self.analysis_views = OrderedDict()
        self.scenario_sets = OrderedDict()
        self.node_mappings = OrderedDict()

    def _format_voltage(self, v: float) -> str:
        """Format voltage for scenario names: 0.76 -> '0p76v'."""
        return f"{v:.2f}".replace('.', 'p') + 'v'

    def _format_temp(self, t: int) -> str:
        """Format temperature for scenario names: -40 -> 'm40c', 150 -> '150c'."""
        if t < 0:
            return f"m{abs(t)}c"
        return f"{t}c"

    def _lib_set_key(self, corner: str, voltage: float, temp: int) -> str:
        """Generate library set reference key: ss_0760v_150c."""
        v_str = f"{voltage:.2f}".replace('.', '')
        if temp < 0:
            t_str = f"m{abs(temp)}c"
        else:
            t_str = f"{temp}c"
        return f"{corner}_{v_str}v_{t_str}"

    def _rc_corner_name(self, rc: str) -> str:
        """Convert rc corner shorthand to display name.

        Standard: rcmax -> rc_max, rctyp -> rc_typ, rcmin -> rc_min
        Custom: kept as-is (e.g., rcmax_cworst stays rcmax_cworst)
        """
        if rc in ('rcmax', 'rctyp', 'rcmin'):
            return rc.replace('rc', 'rc_')
        return rc

    def _analysis_type(self, corner: str) -> str:
        """Determine analysis type from corner."""
        if corner in self.SETUP_CORNERS:
            return 'setup'
        elif corner in self.HOLD_CORNERS:
            return 'hold'
        return 'setup_hold'

    def generate_views(self):
        """Generate all analysis views from the configured parameters."""
        self.analysis_views.clear()

        for mode_info in self.modes:
            mode = mode_info['name']
            sdc = mode_info['sdc']

            for corner in self.corners:
                # Determine which voltages to use for this corner
                if corner in self.SETUP_CORNERS:
                    voltages = [self.voltage_low, self.voltage_nom]
                elif corner in self.HOLD_CORNERS:
                    voltages = [self.voltage_high, self.voltage_nom]
                else:
                    voltages = [self.voltage_nom]

                # Determine which RC corners to use for this process corner
                # RC corners containing 'max' or 'worst' pair with setup (SS)
                # RC corners containing 'min' or 'best' pair with hold (FF)
                # RC corners containing 'typ' or 'nom' pair with nominal (TT)
                # If no pattern matches, use all RC corners (full matrix)
                if corner in self.SETUP_CORNERS:
                    rcs = [rc for rc in self.rc_corners if 'max' in rc or 'worst' in rc]
                    if not rcs:
                        rcs = self.rc_corners  # No max-pattern found, use all
                elif corner in self.HOLD_CORNERS:
                    rcs = [rc for rc in self.rc_corners if 'min' in rc or 'best' in rc]
                    if not rcs:
                        rcs = self.rc_corners  # No min-pattern found, use all
                else:
                    rcs = [rc for rc in self.rc_corners if 'typ' in rc or 'nom' in rc]
                    if not rcs:
                        rcs = self.rc_corners  # No typ-pattern found, use all

                for voltage in voltages:
                    for rc in rcs:
                        for temp in self.temperatures:
                            v_str = self._format_voltage(voltage)
                            t_str = self._format_temp(temp)
                            rc_name = self._rc_corner_name(rc)
                            view_name = f"{mode}_{corner}_{v_str}_{rc}_{t_str}"

                            analysis_type = self._analysis_type(corner)
                            lib_ref = self._lib_set_key(corner, voltage, temp)

                            desc_parts = []
                            desc_parts.append(mode_info.get('description', mode).split()[0])
                            if analysis_type == 'setup':
                                desc_parts.append('setup')
                            elif analysis_type == 'hold':
                                desc_parts.append('hold')
                            else:
                                desc_parts.append('nominal')
                            desc_parts.append(f"{corner.upper()}, {voltage:.2f}V, {temp}C, {rc} RC")

                            self.analysis_views[view_name] = {
                                'corner': corner,
                                'mode': mode,
                                'voltage': voltage,
                                'temperature': temp,
                                'analysis_type': analysis_type,
                                'constraint_file': sdc,
                                'lib_set_ref': lib_ref,
                                'rc_corner': rc_name,
                                'description': f"{' '.join(desc_parts)}",
                            }

    def generate_scenario_sets(self):
        """Auto-generate scenario sets (setup, hold, signoff, power, etc.)."""
        self.scenario_sets.clear()
        all_views = list(self.analysis_views.keys())

        # Setup: SS corner + low voltage + hot temp + rcmax
        setup_views = [v for v, info in self.analysis_views.items()
                       if info['analysis_type'] == 'setup']
        self.scenario_sets['setup'] = {
            'scenarios': setup_views,
            'description': 'Setup-critical scenarios (slow corner, low voltage, hot/cold)',
        }

        # Hold: FF corner + high voltage + cold temp + rcmin
        hold_views = [v for v, info in self.analysis_views.items()
                      if info['analysis_type'] == 'hold']
        self.scenario_sets['hold'] = {
            'scenarios': hold_views,
            'description': 'Hold-critical scenarios (fast corner, high voltage, cold)',
        }

        # Power: mix of corners for power analysis -- use typical + extremes with rctyp
        power_views = [v for v, info in self.analysis_views.items()
                       if info['analysis_type'] == 'setup_hold']
        # Also add some setup/hold views with nominal voltage for power
        for v, info in self.analysis_views.items():
            if info['voltage'] == self.voltage_nom and v not in power_views:
                power_views.append(v)
        self.scenario_sets['power'] = {
            'scenarios': power_views,
            'description': 'Power analysis scenarios (leakage + dynamic)',
        }

        # Signoff: setup + hold + nominal
        signoff_views = list(set(setup_views + hold_views + power_views))
        signoff_views.sort()
        self.scenario_sets['signoff'] = {
            'scenarios': signoff_views,
            'description': 'Complete signoff scenarios (setup + hold + nominal)',
        }

        # STA-specific sets
        self.scenario_sets['sta_setup'] = {
            'scenarios': setup_views[:],
            'description': 'STA setup-critical scenarios',
        }
        self.scenario_sets['sta_hold'] = {
            'scenarios': hold_views[:],
            'description': 'STA hold-critical scenarios (worst-case hold timing)',
        }
        sta_signoff = list(set(setup_views + hold_views + power_views))
        sta_signoff.sort()
        self.scenario_sets['sta_signoff'] = {
            'scenarios': sta_signoff,
            'description': f'STA full signoff scenarios ({len(sta_signoff)} scenarios: setup + hold + nominal)',
        }

        # All
        self.scenario_sets['all'] = {
            'scenarios': sorted(all_views),
            'description': f'All available scenarios ({len(all_views)} total)',
        }

    def generate_node_mappings(self):
        """Auto-generate progressive node-to-scenario mappings."""
        self.node_mappings.clear()

        setup_views = [v for v, info in self.analysis_views.items()
                       if info['analysis_type'] == 'setup']
        hold_views = [v for v, info in self.analysis_views.items()
                      if info['analysis_type'] == 'hold']
        nominal_views = [v for v, info in self.analysis_views.items()
                         if info['analysis_type'] == 'setup_hold']

        # Helper: pick N views from a list, preferring func mode first
        def _pick(views: List[str], count: int) -> List[str]:
            func_first = sorted(views, key=lambda v: (
                0 if v.startswith('func_') else 1, v
            ))
            return func_first[:min(count, len(func_first))]

        # init_design: 1 setup + 1 hold (or 1 nominal)
        if nominal_views:
            self.node_mappings['init_design'] = {
                'setup': _pick(nominal_views, 1),
                'hold': _pick(nominal_views, 1),
            }
        else:
            self.node_mappings['init_design'] = {
                'setup': _pick(setup_views, 1),
                'hold': _pick(hold_views, 1),
            }

        # floorplan: 1 setup + 1 hold
        self.node_mappings['floorplan'] = {
            'setup': _pick(setup_views, 1),
            'hold': _pick(hold_views, 1),
        }

        # powerplan: 1 setup + 1 hold
        self.node_mappings['powerplan'] = {
            'setup': _pick(setup_views, 1),
            'hold': _pick(hold_views, 1),
        }

        # placement: 2 setup + 2 hold
        self.node_mappings['placement'] = {
            'setup': _pick(setup_views, 2),
            'hold': _pick(hold_views, 2),
        }

        # cts: 3 setup + 3 hold
        self.node_mappings['cts'] = {
            'setup': _pick(setup_views, 3),
            'hold': _pick(hold_views, 3),
        }

        # cts_opt: 4 setup + 3 hold (more scenarios for post-CTS optimization)
        self.node_mappings['cts_opt'] = {
            'setup': _pick(setup_views, 4),
            'hold': _pick(hold_views, 3),
        }

        # route: 4 setup + 4 hold
        self.node_mappings['route'] = {
            'setup': _pick(setup_views, 4),
            'hold': _pick(hold_views, 4),
        }

        # post_route: all setup + all hold + nominal
        post_setup = sorted(set(setup_views + _pick(nominal_views, 1)))
        post_hold = sorted(set(hold_views + _pick(nominal_views, 1)))
        self.node_mappings['post_route'] = {
            'setup': post_setup,
            'hold': post_hold,
        }

        # signoff: all setup + all hold
        self.node_mappings['signoff'] = {
            'setup': sorted(setup_views),
            'hold': sorted(hold_views),
        }

        # synthesis: setup corners for multi-corner compile
        self.node_mappings['synthesis'] = {
            'setup': _pick(setup_views, 4),
            'hold': _pick(hold_views, 3),
        }

    def generate_tcl_output(self) -> str:
        """Generate the complete mmmc_config.tcl content."""
        lines = []
        lines.append('#!/usr/bin/env tclsh')
        lines.append('# ' + '=' * 77)
        lines.append('# CBFlow Multi-Mode Multi-Corner (MMMC) Configuration')
        lines.append('# Auto-generated by CBFlow mmmc-manager')
        lines.append('# ' + '=' * 77)
        lines.append('')

        # Global config
        lines.append('# Global MMMC configuration')
        lines.append('array set mmmc_config {')
        lines.append('    enabled                 true')
        lines.append('    version                 "3.0"')
        lines.append('    timing_derate_early    0.95')
        lines.append('    timing_derate_late     1.05')
        lines.append('    clock_uncertainty      0.1')
        lines.append('    max_transition         0.5')
        lines.append('    max_capacitance        2.0')
        lines.append('    max_fanout             16')
        lines.append('}')
        lines.append('')

        # Process corners
        lines.append('# ' + '=' * 77)
        lines.append('# PROCESS CORNERS DEFINITION')
        lines.append('# ' + '=' * 77)
        lines.append('')
        lines.append('array set process_corners {')
        for corner in self.corners:
            cname = self.CORNER_NAMES.get(corner, corner)
            cdesc = self.CORNER_DESCRIPTIONS.get(corner, corner.upper())
            is_setup = corner in self.SETUP_CORNERS
            is_hold = corner in self.HOLD_CORNERS
            lines.append(f'    {corner} {{')
            lines.append(f'        name                "{cname}"')
            lines.append(f'        description         "{cdesc}"')
            lines.append(f'        voltage_nominal     {self.voltage_nom:.2f}')
            lines.append(f'        voltage_low         {self.voltage_low:.2f}')
            lines.append(f'        voltage_high        {self.voltage_high:.2f}')
            # Temperatures
            temps_sorted = sorted(self.temperatures)
            lines.append(f'        temperature_hot     {temps_sorted[-1]}')
            if len(temps_sorted) >= 2:
                mid = temps_sorted[len(temps_sorted) // 2]
                lines.append(f'        temperature_nom     {mid}')
            else:
                lines.append(f'        temperature_nom     {temps_sorted[0]}')
            lines.append(f'        temperature_cold    {temps_sorted[0]}')
            if is_setup:
                lines.append(f'        process_condition   "slow"')
            elif is_hold:
                lines.append(f'        process_condition   "fast"')
            else:
                lines.append(f'        process_condition   "typical"')
            lines.append(f'        setup_critical      {"true" if is_setup else "false"}')
            lines.append(f'        hold_critical       {"true" if is_hold else "false"}')
            lines.append(f'        leakage_critical    {"true" if is_hold else "false"}')
            lines.append('    }')
            lines.append('')
        lines.append('}')
        lines.append('')

        # Operating modes
        lines.append('# ' + '=' * 77)
        lines.append('# OPERATING MODES DEFINITION')
        lines.append('# ' + '=' * 77)
        lines.append('')
        lines.append('array set operating_modes {')
        for mode_info in self.modes:
            lines.append(f'    {mode_info["name"]} {{')
            lines.append(f'        name                "{mode_info["name"]}"')
            lines.append(f'        description         "{mode_info["description"]}"')
            lines.append(f'        voltage_nom         {self.voltage_nom:.2f}')
            lines.append(f'        voltage_low         {self.voltage_low:.2f}')
            lines.append(f'        voltage_high        {self.voltage_high:.2f}')
            lines.append(f'        clock_frequency     "{mode_info["freq"]}"')
            lines.append(f'        constraint_file     "{mode_info["sdc"]}"')
            lines.append('    }')
            lines.append('')
        lines.append('}')
        lines.append('')

        # Scenario sets
        lines.append('# ' + '=' * 77)
        lines.append('# PREDEFINED SCENARIO SETS')
        lines.append('# ' + '=' * 77)
        lines.append('')
        lines.append('array set mmmc_scenario_sets {')
        for set_name, set_info in self.scenario_sets.items():
            lines.append(f'    {set_name} {{')
            lines.append('        scenarios {')
            for s in set_info['scenarios']:
                lines.append(f'            {s}')
            lines.append('        }')
            lines.append(f'        description "{set_info["description"]}"')
            lines.append('    }')
            lines.append('')
        lines.append('}')
        lines.append('')

        # Analysis views
        lines.append('# ' + '=' * 77)
        lines.append('# ANALYSIS VIEWS DEFINITION')
        lines.append('# ' + '=' * 77)
        lines.append('')
        lines.append('array set analysis_views {')
        current_mode = None
        current_type = None
        for view_name, view_info in self.analysis_views.items():
            # Add section comments when mode or analysis type changes
            if view_info['mode'] != current_mode or view_info['analysis_type'] != current_type:
                current_mode = view_info['mode']
                current_type = view_info['analysis_type']
                type_label = current_type.replace('_', '/').title()
                lines.append(f'    # -- {current_mode.upper()} Mode: {type_label} --')
            lines.append(f'    "{view_name}" {{')
            lines.append(f'        corner "{view_info["corner"]}" '
                         f'mode "{view_info["mode"]}" '
                         f'voltage {view_info["voltage"]:.2f} '
                         f'temperature {view_info["temperature"]}')
            lines.append(f'        analysis_type "{view_info["analysis_type"]}" '
                         f'constraint_file "{view_info["constraint_file"]}"')
            lines.append(f'        lib_set_ref "{view_info["lib_set_ref"]}" '
                         f'rc_corner "{view_info["rc_corner"]}"')
            lines.append(f'        description "{view_info["description"]}"')
            lines.append('    }')
        lines.append('}')
        lines.append('')

        # RC corners
        lines.append('# ' + '=' * 77)
        lines.append('# RC CORNERS DEFINITION')
        lines.append('# ' + '=' * 77)
        lines.append('')
        lines.append('array set rc_corners {')
        for rc in self.rc_corners:
            rc_full = self._rc_corner_name(rc)
            if rc in self.RC_DESCRIPTIONS:
                desc, usage = self.RC_DESCRIPTIONS[rc]
            else:
                desc = self._infer_rc_description(rc)
                usage = self._infer_rc_usage(rc)
            mults = self.RC_MULTIPLIERS.get(rc, {})
            temps_sorted = sorted(self.temperatures)
            # Assign temperature based on usage
            if usage == 'setup_critical':
                rc_temp = temps_sorted[-1]
            elif usage == 'hold_critical':
                rc_temp = temps_sorted[0]
            else:
                rc_temp = temps_sorted[len(temps_sorted) // 2] if len(temps_sorted) >= 2 else temps_sorted[0]
            lines.append(f'    {rc_full} {{')
            lines.append(f'        name                "{rc_full}"')
            lines.append(f'        description         "{desc}"')
            lines.append(f'        temperature         {rc_temp}')
            lines.append(f'        metal_multiplier    {mults.get("metal", 1.0):.2f}')
            lines.append(f'        via_multiplier      {mults.get("via", 1.0):.2f}')
            lines.append(f'        cap_multiplier      {mults.get("cap", 1.0):.2f}')
            lines.append(f'        res_multiplier      {mults.get("res", 1.0):.2f}')
            lines.append(f'        usage               "{usage}"')
            lines.append('    }')
            if rc != self.rc_corners[-1]:
                lines.append('')
        lines.append('}')
        lines.append('')

        # Node mappings
        lines.append('# ' + '=' * 77)
        lines.append('# NODE-SPECIFIC MMMC SCENARIO ASSIGNMENTS')
        lines.append('# ' + '=' * 77)
        lines.append('')
        lines.append('array set mmmc {')
        for node_name, node_info in self.node_mappings.items():
            setup_list = node_info.get('setup', [])
            hold_list = node_info.get('hold', [])
            lines.append(f'    {node_name} {{')
            if len(setup_list) <= 1:
                lines.append(f'        setup {{{setup_list[0] if setup_list else ""}}}')
            else:
                lines.append('        setup {')
                for s in setup_list:
                    lines.append(f'            {s}')
                lines.append('        }')
            if len(hold_list) <= 1:
                lines.append(f'        hold  {{{hold_list[0] if hold_list else ""}}}')
            else:
                lines.append('        hold {')
                for s in hold_list:
                    lines.append(f'            {s}')
                lines.append('        }')
            lines.append('    }')
            lines.append('')
        lines.append('}')
        lines.append('')

        # Utility procs
        lines.append('# ' + '=' * 77)
        lines.append('# UTILITY FUNCTIONS')
        lines.append('# ' + '=' * 77)
        lines.append('')
        lines.append(_UTILITY_PROCS)
        lines.append('')

        return '\n'.join(lines)


# TCL utility procs to embed in generated config
_UTILITY_PROCS = r'''proc get_scenario_set {type} {
    global mmmc_scenario_sets
    if {[info exists mmmc_scenario_sets($type)]} {
        array set set_info $mmmc_scenario_sets($type)
        return $set_info(scenarios)
    }
    return {}
}

proc list_scenario_sets {} {
    global mmmc_scenario_sets
    puts "Available MMMC scenario sets:"
    foreach type [lsort [array names mmmc_scenario_sets]] {
        array set set_info $mmmc_scenario_sets($type)
        set count [llength $set_info(scenarios)]
        puts "  $type ($count scenarios): $set_info(description)"
    }
}

proc get_analysis_view {scenario_name} {
    global analysis_views
    if {[info exists analysis_views($scenario_name)]} {
        return $analysis_views($scenario_name)
    }
    return {}
}

proc list_all_scenarios {} {
    global analysis_views
    puts "All available MMMC scenarios:"
    foreach scenario [lsort [array names analysis_views]] {
        array set view_info $analysis_views($scenario)
        puts "  $scenario: $view_info(description)"
    }
}

proc is_mmmc_enabled {} {
    global mmmc_config
    return $mmmc_config(enabled)
}

proc get_node_scenarios {node_name {analysis_type "all"}} {
    global mmmc
    if {![info exists mmmc($node_name)]} {
        return {}
    }
    array set node_info $mmmc($node_name)
    switch $analysis_type {
        "setup" { return $node_info(setup) }
        "hold"  { return $node_info(hold) }
        "all"   {
            set combined $node_info(setup)
            foreach s $node_info(hold) {
                if {$s ni $combined} { lappend combined $s }
            }
            return $combined
        }
    }
    return {}
}

proc list_mmmc_nodes {} {
    global mmmc
    puts "MMMC Node Scenario Assignments:"
    puts [string repeat "=" 70]
    foreach node [lsort [array names mmmc]] {
        array set node_info $mmmc($node)
        set setup_count [llength $node_info(setup)]
        set hold_count [llength $node_info(hold)]
        puts "  $node: $setup_count setup, $hold_count hold scenarios"
        array unset node_info
    }
    puts [string repeat "=" 70]
}

proc get_node_setup_scenarios {node_name} {
    return [get_node_scenarios $node_name "setup"]
}

proc get_node_hold_scenarios {node_name} {
    return [get_node_scenarios $node_name "hold"]
}

proc create_mmmc_scenarios_for_node {node_name} {
    global analysis_views
    set scenarios [get_node_scenarios $node_name "all"]
    set created {}
    foreach scenario $scenarios {
        if {[info exists analysis_views($scenario)]} {
            array set view $analysis_views($scenario)
            puts "INFO: Creating scenario: $scenario ($view(description))"
            lappend created $scenario
            array unset view
        } else {
            puts "WARNING: Scenario $scenario not found in analysis_views"
        }
    }
    return $created
}


puts "INFO: MMMC configuration loaded successfully"
puts "INFO: MMMC enabled: $mmmc_config(enabled)"
puts "INFO: Analysis views defined: [llength [array names analysis_views]]"
puts "INFO: Scenario sets available: [join [array names mmmc_scenario_sets] { }]"
puts "INFO: Node scenarios configured: [llength [array names mmmc]] nodes"
puts "INFO: Use list_scenario_sets to see available sets"
puts "INFO: Use list_mmmc_nodes to see node-specific scenarios"
puts "INFO: Use get_node_scenarios <node> to get scenarios for a specific node"'''


# -------------------------------------------------------------------------------
# View Definition Generator
# -------------------------------------------------------------------------------

class ViewDefinitionGenerator:
    """Generate Cadence Innovus/Tempus view_definition.tcl from MMMC config."""

    def __init__(self, parser: MmmcConfigParser):
        self.parser = parser

    def generate(self) -> str:
        """Generate view_definition.tcl content."""
        lines = []
        lines.append('# Cadence MMMC View Definition File')
        lines.append('# Auto-generated by CBFlow mmmc-manager')
        lines.append('')

        # Collect unique library sets, RC corners, constraint modes
        lib_sets = set()
        rc_corners_used = set()
        constraint_modes = {}
        setup_views = []
        hold_views = []

        for view_name, view_data in self.parser.analysis_views.items():
            lib_ref = view_data.get('lib_set_ref', '')
            if lib_ref:
                lib_sets.add(lib_ref)
            rc = view_data.get('rc_corner', '')
            if rc:
                rc_corners_used.add(rc)
            mode = view_data.get('mode', '')
            sdc = view_data.get('constraint_file', '')
            if mode and sdc:
                constraint_modes[mode] = sdc
            atype = view_data.get('analysis_type', '')
            if atype == 'setup':
                setup_views.append(view_name)
            elif atype == 'hold':
                hold_views.append(view_name)

        # Create library sets
        lines.append('# ' + '-' * 70)
        lines.append('# Library Sets')
        lines.append('# ' + '-' * 70)
        lines.append('')
        for lib_set in sorted(lib_sets):
            lines.append(f'create_library_set -name {lib_set} \\')
            lines.append(f'    -timing [list /path/to/libs/{lib_set}_ccs.lib] \\')
            lines.append(f'    -si [list /path/to/libs/{lib_set}_ccs.lib]')
            lines.append('')

        # Create RC corners
        lines.append('# ' + '-' * 70)
        lines.append('# RC Corners')
        lines.append('# ' + '-' * 70)
        lines.append('')
        rc_data = self.parser.rc_corners
        for rc_name in sorted(rc_corners_used):
            rc_info = rc_data.get(rc_name, {})
            temp = rc_info.get('temperature', '25')
            res_mult = rc_info.get('res_multiplier', '1.00')
            cap_mult = rc_info.get('cap_multiplier', '1.00')

            rc_short = rc_name.replace('rc_', '')
            lines.append(f'create_rc_corner -name {rc_name} \\')
            lines.append(f'    -T {temp} \\')
            lines.append(f'    -cap_table /path/to/cap_table_{rc_short}.cap \\')
            lines.append(f'    -preRoute_res {res_mult} \\')
            lines.append(f'    -preRoute_cap {cap_mult} \\')
            lines.append(f'    -postRoute_res {res_mult} \\')
            lines.append(f'    -postRoute_cap {cap_mult}')
            lines.append('')

        # Create constraint modes
        lines.append('# ' + '-' * 70)
        lines.append('# Constraint Modes')
        lines.append('# ' + '-' * 70)
        lines.append('')
        for mode_name, sdc_file in sorted(constraint_modes.items()):
            lines.append(f'create_constraint_mode -name {mode_name}_mode \\')
            lines.append(f'    -sdc_files [list {sdc_file}]')
            lines.append('')

        # Create delay corners and analysis views
        lines.append('# ' + '-' * 70)
        lines.append('# Delay Corners')
        lines.append('# ' + '-' * 70)
        lines.append('')
        for view_name, view_data in self.parser.analysis_views.items():
            lib_ref = view_data.get('lib_set_ref', '')
            rc = view_data.get('rc_corner', '')
            dc_name = f"{view_name}_dc"
            lines.append(f'create_delay_corner -name {dc_name} \\')
            lines.append(f'    -library_set {lib_ref} \\')
            lines.append(f'    -rc_corner {rc} \\')
            lines.append(f'    -opcond_library {lib_ref}_ccs \\')
            lines.append(f'    -opcond {lib_ref}')
            lines.append('')

        # Create analysis views
        lines.append('# ' + '-' * 70)
        lines.append('# Analysis Views')
        lines.append('# ' + '-' * 70)
        lines.append('')
        for view_name, view_data in self.parser.analysis_views.items():
            mode = view_data.get('mode', '')
            dc_name = f"{view_name}_dc"
            lines.append(f'create_analysis_view -name {view_name} \\')
            lines.append(f'    -delay_corner {dc_name} \\')
            lines.append(f'    -constraint_mode {mode}_mode')
            lines.append('')

        # Set active views
        lines.append('# ' + '-' * 70)
        lines.append('# Active Analysis Views')
        lines.append('# ' + '-' * 70)
        lines.append('')
        if setup_views:
            setup_str = ' '.join(setup_views)
            lines.append(f'set_analysis_view -setup [list {setup_str}] \\')
        if hold_views:
            hold_str = ' '.join(hold_views)
            lines.append(f'    -hold [list {hold_str}]')
        lines.append('')

        return '\n'.join(lines)


# -------------------------------------------------------------------------------
# Command Implementations
# -------------------------------------------------------------------------------

def _get_default_config_path() -> str:
    """Get the default mmmc_config.tcl path."""
    core_dir = get_cbflow_core_dir()
    config_version = os.environ.get('CBFLOW_CONFIG_VERSION', 'v1.0.0')
    return os.path.join(core_dir, 'config', 'flow', config_version, 'mmmc_config.tcl')


def cmd_create(args: argparse.Namespace) -> int:
    """Create a new MMMC configuration interactively or from CLI args."""
    gen = MmmcScenarioGenerator()

    if args.interactive:
        return _create_interactive(gen, args)
    else:
        return _create_from_args(gen, args)


def _create_interactive(gen: MmmcScenarioGenerator, args: argparse.Namespace) -> int:
    """Walk user through MMMC setup interactively."""
    logger.info("")
    logger.info("=" * 70)
    logger.info("  CBFlow MMMC Configuration Creator (Interactive)")
    logger.info("=" * 70)
    logger.info("")

    # Step 1: Process corners
    logger.info("Step 1: Process Corners")
    logger.info("-" * 40)
    valid_corners = ['ss', 'tt', 'ff', 'sf', 'fs']
    gen.corners = _prompt_list("Enter process corners (comma-separated)", "ss,tt,ff", valid_corners)
    logger.info(f"  -> Corners: {', '.join(gen.corners)}")
    logger.info("")

    # Step 2: Voltages
    logger.info("Step 2: Voltage Configuration")
    logger.info("-" * 40)
    gen.voltage_nom = _prompt_float("Enter nominal voltage (V)", "0.80", min_val=0.1, max_val=5.0)
    tol_pct = _prompt_float("Enter voltage tolerance (%)", "5", min_val=0, max_val=50)
    tol_str = str(int(tol_pct)) if tol_pct == int(tol_pct) else str(tol_pct)
    tolerance = tol_pct / 100.0
    gen.voltage_low = round(gen.voltage_nom * (1.0 - tolerance), 2)
    gen.voltage_high = round(gen.voltage_nom * (1.0 + tolerance), 2)
    logger.info(f"  -> Voltages: {gen.voltage_low:.2f}V (low, -{tol_str}%), "
                f"{gen.voltage_nom:.2f}V (nom), "
                f"{gen.voltage_high:.2f}V (high, +{tol_str}%)")
    if not _confirm():
        logger.info("Aborted by user.")
        return 1
    logger.info("")

    # Step 3: Temperatures
    logger.info("Step 3: Temperature Configuration")
    logger.info("-" * 40)
    temps_raw = _prompt_list("Enter temperatures (comma-separated, C)", "-40,25,150")
    try:
        gen.temperatures = sorted([int(t) for t in temps_raw])
    except ValueError:
        print("  [!] Invalid temperature values. Please enter integers (e.g., -40,25,150)")
        return 1
    logger.info(f"  -> Temperatures: {', '.join(str(t) + 'C' for t in gen.temperatures)}")
    logger.info("")

    # Step 4: Operating modes
    logger.info("Step 4: Operating Modes")
    logger.info("-" * 40)
    num_modes = _prompt_int("How many operating modes?", "2", min_val=1, max_val=10)
    gen.modes = []
    for i in range(1, num_modes + 1):
        name = _prompt(f"Mode {i} name")
        desc = _prompt(f"Mode {i} description")
        freq = _prompt(f"Mode {i} clock frequency")
        sdc = _prompt(f"Mode {i} constraint file")
        gen.modes.append({
            'name': name,
            'description': desc,
            'freq': freq,
            'sdc': sdc,
        })
    logger.info("")

    # Step 5: RC corners
    logger.info("Step 5: RC Corners")
    logger.info("-" * 40)
    logger.info("  Standard: rcmax, rctyp, rcmin")
    logger.info("  Custom:   rcmax_cworst, rcmin_cbest, rctyp_T, rcmax_flat, etc.")
    logger.info("  Pairing:  corners with 'max'/'worst' -> SS (setup)")
    logger.info("            corners with 'min'/'best'  -> FF (hold)")
    logger.info("            corners with 'typ'/'nom'   -> TT (nominal)")
    logger.info("            no pattern match -> paired with all process corners")
    gen.rc_corners = _prompt_list("RC corners (comma-separated)", "rcmax,rctyp,rcmin")
    logger.info(f"  -> RC corners: {', '.join(gen.rc_corners)}")
    logger.info("")

    # Step 6: Generate scenarios
    logger.info("Step 6: Generating Analysis Views")
    logger.info("-" * 40)
    gen.generate_views()
    logger.info(f"  Generated {len(gen.analysis_views)} analysis views:")
    logger.info("")
    for i, (vname, vinfo) in enumerate(gen.analysis_views.items(), 1):
        logger.info(f"    {i:>3}. {vname}")
    logger.info("")
    if not _confirm(f"Accept {len(gen.analysis_views)} analysis views?"):
        logger.info("Aborted by user.")
        return 1
    logger.info("")

    # Step 7: Generate scenario sets
    logger.info("Step 7: Generating Scenario Sets")
    logger.info("-" * 40)
    gen.generate_scenario_sets()
    for set_name, set_info in gen.scenario_sets.items():
        count = len(set_info['scenarios'])
        logger.info(f"  {set_name:<15} {count:>3} scenarios  - {set_info['description']}")
    logger.info("")

    # Step 8: Generate node mappings
    logger.info("Step 8: Generating Node Scenario Mappings")
    logger.info("-" * 40)
    gen.generate_node_mappings()
    for node, ninfo in gen.node_mappings.items():
        s_count = len(ninfo.get('setup', []))
        h_count = len(ninfo.get('hold', []))
        logger.info(f"  {node:<15} {s_count} setup, {h_count} hold")
    logger.info("")

    # Step 9: Write output
    logger.info("Step 9: Writing Output")
    logger.info("-" * 40)
    tcl_content = gen.generate_tcl_output()

    output_path = getattr(args, 'output', None)
    if output_path:
        out_dir = os.path.dirname(os.path.abspath(output_path))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(output_path, 'w') as f:
            f.write(tcl_content)
        logger.info(f"  Written to: {output_path}")
        logger.info(f"  Analysis views: {len(gen.analysis_views)}")
        logger.info(f"  Scenario sets: {len(gen.scenario_sets)}")
        logger.info(f"  Node mappings: {len(gen.node_mappings)}")
    else:
        print(tcl_content)

    logger.info("")
    logger.info("MMMC configuration created successfully.")
    logger.info("")
    return 0


def _create_from_args(gen: MmmcScenarioGenerator, args: argparse.Namespace) -> int:
    """Create MMMC config from CLI arguments (non-interactive)."""
    # Validate required args
    if not args.corners:
        logger.error("--corners is required in non-interactive mode")
        return 1
    if not args.voltages:
        logger.error("--voltages is required in non-interactive mode (format: nom,tolerance%)")
        return 1
    if not args.temps:
        logger.error("--temps is required in non-interactive mode")
        return 1
    if not args.modes:
        logger.error("--modes is required in non-interactive mode (format: name:desc:freq:sdc,...)")
        return 1

    # Parse corners
    gen.corners = [c.strip().lower() for c in args.corners.split(',')]

    # Parse voltages: "0.80,5" -> nom=0.80, tolerance=5%
    v_parts = args.voltages.split(',')
    gen.voltage_nom = float(v_parts[0])
    tolerance = float(v_parts[1]) / 100.0 if len(v_parts) > 1 else 0.05
    gen.voltage_low = round(gen.voltage_nom * (1.0 - tolerance), 2)
    gen.voltage_high = round(gen.voltage_nom * (1.0 + tolerance), 2)

    # Parse temperatures
    gen.temperatures = sorted([int(t.strip()) for t in args.temps.split(',')])

    # Parse modes: "func:Functional:1000MHz:func.sdc,test:DFT:100MHz:test.sdc"
    gen.modes = []
    for mode_spec in args.modes.split(','):
        parts = mode_spec.strip().split(':')
        if len(parts) < 4:
            logger.error(f"Invalid mode spec: {mode_spec} (expected name:desc:freq:sdc)")
            return 1
        gen.modes.append({
            'name': parts[0],
            'description': parts[1],
            'freq': parts[2],
            'sdc': parts[3],
        })

    # Parse RC corners
    rc_str = getattr(args, 'rc_corners', None) or 'rcmax,rctyp,rcmin'
    gen.rc_corners = [r.strip().lower() for r in rc_str.split(',')]

    # Generate
    gen.generate_views()
    gen.generate_scenario_sets()
    gen.generate_node_mappings()

    logger.info(f"Generated {len(gen.analysis_views)} analysis views")
    logger.info(f"Generated {len(gen.scenario_sets)} scenario sets")
    logger.info(f"Generated {len(gen.node_mappings)} node mappings")

    tcl_content = gen.generate_tcl_output()

    output_path = getattr(args, 'output', None)
    if output_path:
        out_dir = os.path.dirname(os.path.abspath(output_path))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(output_path, 'w') as f:
            f.write(tcl_content)
        logger.info(f"Config written to: {output_path}")
    else:
        print(tcl_content)

    return 0


def cmd_show(args: argparse.Namespace) -> int:
    """Parse and display current mmmc_config.tcl."""
    config_path = getattr(args, 'config', None) or _get_default_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    logger.info("")
    logger.info("=" * 70)
    logger.info(f"  MMMC Configuration Summary")
    logger.info(f"  Source: {config_path}")
    logger.info("=" * 70)
    logger.info("")

    # Process corners
    logger.info("  Process Corners:")
    logger.info("  " + "-" * 66)
    for corner, cinfo in sorted(parser.process_corners.items()):
        desc = cinfo.get('description', '')
        v_nom = cinfo.get('voltage_nominal', '?')
        logger.info(f"    {corner:<6} {desc:<50} V={v_nom}")
    logger.info("")

    # Operating modes
    logger.info("  Operating Modes:")
    logger.info("  " + "-" * 66)
    for mode, minfo in sorted(parser.operating_modes.items()):
        desc = minfo.get('description', '')
        freq = minfo.get('clock_frequency', '?')
        sdc = minfo.get('constraint_file', '?')
        logger.info(f"    {mode:<8} {desc:<35} {freq:<12} {sdc}")
    logger.info("")

    # RC corners
    logger.info("  RC Corners:")
    logger.info("  " + "-" * 66)
    for rc, rinfo in sorted(parser.rc_corners.items()):
        desc = rinfo.get('description', '')
        temp = rinfo.get('temperature', '?')
        logger.info(f"    {rc:<10} {desc:<45} T={temp}")
    logger.info("")

    # Scenario sets
    logger.info("  Scenario Sets:")
    logger.info("  " + "-" * 66)
    for set_name, sinfo in sorted(parser.scenario_sets.items()):
        scenarios = sinfo.get('scenarios', '')
        if isinstance(scenarios, str):
            count = len(scenarios.split()) if scenarios.strip() else 0
        else:
            count = 0
        desc = sinfo.get('description', '')
        logger.info(f"    {set_name:<15} {count:>3} scenarios  {desc}")
    logger.info("")

    # Node mappings
    logger.info("  Node Scenario Mappings:")
    logger.info("  " + "-" * 66)
    for node, ninfo in sorted(parser.node_mappings.items()):
        setup_str = ninfo.get('setup', '')
        hold_str = ninfo.get('hold', '')
        s_count = len(setup_str.split()) if isinstance(setup_str, str) and setup_str.strip() else 0
        h_count = len(hold_str.split()) if isinstance(hold_str, str) and hold_str.strip() else 0
        logger.info(f"    {node:<15} {s_count:>2} setup, {h_count:>2} hold")
    logger.info("")

    # Total analysis views
    logger.info(f"  Total Analysis Views: {len(parser.analysis_views)}")
    logger.info("=" * 70)
    logger.info("")

    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    """Validate mmmc_config.tcl for consistency."""
    config_path = getattr(args, 'config', None) or _get_default_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    logger.info("")
    logger.info("=" * 70)
    logger.info(f"  MMMC Configuration Validation")
    logger.info(f"  Source: {config_path}")
    logger.info("=" * 70)
    logger.info("")

    all_view_names = set(parser.analysis_views.keys())
    errors = []
    warnings = []

    # Check 1: All scenarios in sets exist in analysis_views
    logger.info("  Check 1: Scenario sets reference valid analysis views")
    logger.info("  " + "-" * 66)
    for set_name, sinfo in parser.scenario_sets.items():
        scenarios_str = sinfo.get('scenarios', '')
        if isinstance(scenarios_str, str):
            scenarios = scenarios_str.split()
        else:
            scenarios = []
        missing = [s for s in scenarios if s and s not in all_view_names]
        if missing:
            for m in missing:
                msg = f"Scenario set '{set_name}' references missing view: {m}"
                errors.append(msg)
                logger.info(f"    [FAIL] {msg}")
        else:
            logger.info(f"    [PASS] {set_name}: {len(scenarios)} scenarios OK")
    logger.info("")

    # Check 2: All scenarios in node mappings exist in analysis_views
    logger.info("  Check 2: Node mappings reference valid analysis views")
    logger.info("  " + "-" * 66)
    for node, ninfo in parser.node_mappings.items():
        for atype in ('setup', 'hold'):
            scenarios_str = ninfo.get(atype, '')
            if isinstance(scenarios_str, str):
                scenarios = scenarios_str.split()
            else:
                scenarios = []
            missing = [s for s in scenarios if s and s not in all_view_names]
            if missing:
                for m in missing:
                    msg = f"Node '{node}' {atype} references missing view: {m}"
                    errors.append(msg)
                    logger.info(f"    [FAIL] {msg}")
        if node not in [e.split("'")[1] for e in errors if "Node" in e]:
            s_str = ninfo.get('setup', '')
            h_str = ninfo.get('hold', '')
            s_count = len(s_str.split()) if isinstance(s_str, str) and s_str.strip() else 0
            h_count = len(h_str.split()) if isinstance(h_str, str) and h_str.strip() else 0
            logger.info(f"    [PASS] {node}: {s_count} setup + {h_count} hold OK")
    logger.info("")

    # Check 3: lib_set_ref consistency
    logger.info("  Check 3: Library set references are consistent")
    logger.info("  " + "-" * 66)
    lib_refs = set()
    for view_name, vinfo in parser.analysis_views.items():
        ref = vinfo.get('lib_set_ref', '')
        if ref:
            lib_refs.add(ref)
    logger.info(f"    Unique library set references: {len(lib_refs)}")
    for ref in sorted(lib_refs):
        views_using = [v for v, vi in parser.analysis_views.items()
                       if vi.get('lib_set_ref', '') == ref]
        logger.info(f"    {ref:<25} used by {len(views_using)} views")
    logger.info("")

    # Check 4: Orphan scenarios (in views but not in any set)
    logger.info("  Check 4: Orphan analysis views (not in any scenario set)")
    logger.info("  " + "-" * 66)
    referenced_in_sets = set()
    for set_name, sinfo in parser.scenario_sets.items():
        scenarios_str = sinfo.get('scenarios', '')
        if isinstance(scenarios_str, str):
            for s in scenarios_str.split():
                if s:
                    referenced_in_sets.add(s)
    orphans = all_view_names - referenced_in_sets
    if orphans:
        for o in sorted(orphans):
            msg = f"Analysis view '{o}' is not in any scenario set"
            warnings.append(msg)
            logger.info(f"    [WARN] {msg}")
    else:
        logger.info(f"    [PASS] All {len(all_view_names)} views are referenced in scenario sets")
    logger.info("")

    # Summary
    logger.info("  " + "-" * 66)
    if errors:
        logger.info(f"  VALIDATION FAILED: {len(errors)} errors, {len(warnings)} warnings")
    elif warnings:
        logger.info(f"  VALIDATION PASSED with {len(warnings)} warnings")
    else:
        logger.info("  VALIDATION PASSED: No errors or warnings")
    logger.info("=" * 70)
    logger.info("")

    return 1 if errors else 0


def cmd_generate_view_def(args: argparse.Namespace) -> int:
    """Generate Cadence Innovus/Tempus view_definition.tcl from MMMC config."""
    config_path = getattr(args, 'config', None) or _get_default_config_path()

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    if not parser.analysis_views:
        logger.error("No analysis views found in config")
        return 1

    vdg = ViewDefinitionGenerator(parser)
    content = vdg.generate()

    output_path = getattr(args, 'output', None)
    if output_path:
        out_dir = os.path.dirname(os.path.abspath(output_path))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(output_path, 'w') as f:
            f.write(content)
        logger.info(f"View definition written to: {output_path}")
        logger.info(f"  Analysis views: {len(parser.analysis_views)}")
        logger.info(f"  Library sets: {len(set(v.get('lib_set_ref', '') for v in parser.analysis_views.values()))}")
        logger.info(f"  RC corners: {len(parser.rc_corners)}")
    else:
        print(content)

    return 0


def cmd_add_mode(args: argparse.Namespace) -> int:
    """Add a new operating mode to existing mmmc_config.tcl."""
    config_path = getattr(args, 'config', None) or _get_default_config_path()

    if not os.path.isfile(config_path):
        logger.error(f"Config file not found: {config_path}")
        return 1

    with open(config_path, 'r') as f:
        content = f.read()

    mode_name = args.name
    mode_desc = args.desc
    mode_freq = args.freq
    mode_sdc = args.sdc

    # Check if mode already exists
    if re.search(rf'^\s*{re.escape(mode_name)}\s*\{{', content, re.MULTILINE):
        logger.error(f"Operating mode '{mode_name}' already exists in config")
        return 1

    # Find the operating_modes array and insert new mode before closing brace
    pattern = re.compile(
        r'(array\s+set\s+operating_modes\s*\{.*?)(^\})',
        re.DOTALL | re.MULTILINE
    )
    match = pattern.search(content)
    if not match:
        logger.error("Could not find operating_modes array in config")
        return 1

    # Parse existing config to get voltage values
    parser = MmmcConfigParser(config_path)
    parser.parse()
    # Get voltage from first existing mode
    v_nom = "0.80"
    v_low = "0.76"
    v_high = "0.84"
    for mname, minfo in parser.operating_modes.items():
        v_nom = minfo.get('voltage_nom', v_nom)
        v_low = minfo.get('voltage_low', v_low)
        v_high = minfo.get('voltage_high', v_high)
        break

    new_mode_block = (
        f'\n    {mode_name} {{\n'
        f'        name                "{mode_name}"\n'
        f'        description         "{mode_desc}"\n'
        f'        voltage_nom         {v_nom}\n'
        f'        voltage_low         {v_low}\n'
        f'        voltage_high        {v_high}\n'
        f'        clock_frequency     "{mode_freq}"\n'
        f'        constraint_file     "{mode_sdc}"\n'
        f'    }}\n'
    )

    # Insert before closing brace of operating_modes
    new_content = content[:match.start(2)] + new_mode_block + content[match.start(2):]

    with open(config_path, 'w') as f:
        f.write(new_content)

    logger.info(f"Added operating mode '{mode_name}' to {config_path}")
    logger.info(f"  Description: {mode_desc}")
    logger.info(f"  Frequency:   {mode_freq}")
    logger.info(f"  SDC:         {mode_sdc}")
    logger.info("")
    logger.info("NOTE: Run 'cbflow flow mmmc-manager create' to regenerate scenarios")
    logger.info("      with the new mode included.")

    return 0


def cmd_remove_mode(args: argparse.Namespace) -> int:
    """Remove an operating mode and all its scenarios from mmmc_config.tcl."""
    config_path = getattr(args, 'config', None) or _get_default_config_path()

    if not os.path.isfile(config_path):
        logger.error(f"Config file not found: {config_path}")
        return 1

    with open(config_path, 'r') as f:
        content = f.read()

    mode_name = args.name

    # Check if mode exists
    parser = MmmcConfigParser(config_path)
    parser.parse()

    if mode_name not in parser.operating_modes:
        logger.error(f"Operating mode '{mode_name}' not found in config")
        logger.info(f"Available modes: {', '.join(parser.operating_modes.keys())}")
        return 1

    # Count scenarios that will be removed
    views_to_remove = [v for v, vi in parser.analysis_views.items()
                       if vi.get('mode', '') == mode_name]

    logger.info(f"Removing mode '{mode_name}' will affect:")
    logger.info(f"  Analysis views to remove: {len(views_to_remove)}")
    for v in views_to_remove:
        logger.info(f"    - {v}")

    # Remove the mode from operating_modes block
    # Match the mode entry: mode_name { ... }
    mode_pattern = re.compile(
        rf'(\s*{re.escape(mode_name)}\s*\{{[^}}]*\}})\s*\n?',
        re.DOTALL
    )
    content = mode_pattern.sub('', content)

    # Remove analysis views for this mode
    for view_name in views_to_remove:
        view_pattern = re.compile(
            rf'\s*"{re.escape(view_name)}"\s*\{{[^}}]*\}}\s*\n?',
            re.DOTALL
        )
        content = view_pattern.sub('\n', content)

    # Remove scenarios from scenario sets and node mappings
    for view_name in views_to_remove:
        # Remove from scenario lists (bare word in braced list)
        content = re.sub(
            rf'^\s*{re.escape(view_name)}\s*$',
            '',
            content,
            flags=re.MULTILINE
        )

    # Clean up empty lines
    content = re.sub(r'\n{3,}', '\n\n', content)

    with open(config_path, 'w') as f:
        f.write(content)

    logger.info(f"Removed operating mode '{mode_name}' from {config_path}")
    logger.info(f"  Removed {len(views_to_remove)} analysis views")
    logger.info("")
    logger.info("NOTE: Review scenario sets and node mappings for consistency.")
    logger.info("      Run 'cbflow flow mmmc-manager validate' to check.")

    return 0


# -------------------------------------------------------------------------------
# Argument Parser
# -------------------------------------------------------------------------------

def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow mmmc-manager',
        description='CBFlow - MMMC Manager: Multi-Mode Multi-Corner configuration management',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow mmmc-manager create --interactive
  cbflow flow mmmc-manager create --interactive --output mmmc_config.tcl
  cbflow flow mmmc-manager create --corners ss,tt,ff --voltages 0.80,5 \\
      --temps -40,25,150 --modes func:Functional:1000MHz:func.sdc \\
      --output mmmc_config.tcl
  cbflow flow mmmc-manager show
  cbflow flow mmmc-manager show --config path/to/mmmc_config.tcl
  cbflow flow mmmc-manager validate
  cbflow flow mmmc-manager validate --config path/to/mmmc_config.tcl
  cbflow flow mmmc-manager generate-view-def --output view_definition.tcl
  cbflow flow mmmc-manager add-mode --name scan --desc "Scan mode" \\
      --freq 200MHz --sdc design_scan.sdc
  cbflow flow mmmc-manager remove-mode --name scan
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='MMMC manager commands')

    # create command
    create_sub = subparsers.add_parser(
        'create', help='Create new MMMC configuration')
    create_sub.add_argument('--interactive', action='store_true', default=False,
                            help='Interactive mode (walk through setup step-by-step)')
    create_sub.add_argument('--output', default=None,
                            help='Output file path (default: stdout)')
    create_sub.add_argument('--corners', default=None,
                            help='Process corners, comma-separated (e.g., ss,tt,ff)')
    create_sub.add_argument('--voltages', default=None,
                            help='Nominal voltage and tolerance (e.g., 0.80,5 for 0.80V +/-5%%)')
    create_sub.add_argument('--temps', default=None,
                            help='Temperatures, comma-separated (e.g., -40,25,150)')
    create_sub.add_argument('--modes', default=None,
                            help='Operating modes as name:desc:freq:sdc (comma-separated)')
    create_sub.add_argument('--rc-corners', default=None, dest='rc_corners',
                            help='RC corners, comma-separated (default: rcmax,rctyp,rcmin)')

    # show command
    show_sub = subparsers.add_parser(
        'show', help='Show current MMMC configuration summary')
    show_sub.add_argument('--config', default=None,
                          help='Path to mmmc_config.tcl (auto-detected if omitted)')

    # validate command
    validate_sub = subparsers.add_parser(
        'validate', help='Validate MMMC configuration for consistency')
    validate_sub.add_argument('--config', default=None,
                              help='Path to mmmc_config.tcl (auto-detected if omitted)')

    # generate-view-def command
    viewdef_sub = subparsers.add_parser(
        'generate-view-def', help='Generate Cadence view_definition.tcl')
    viewdef_sub.add_argument('--config', default=None,
                             help='Path to mmmc_config.tcl (auto-detected if omitted)')
    viewdef_sub.add_argument('--output', default=None,
                             help='Output file path (default: stdout)')

    # add-mode command
    addmode_sub = subparsers.add_parser(
        'add-mode', help='Add a new operating mode to existing config')
    addmode_sub.add_argument('--name', required=True,
                             help='Mode name (e.g., scan)')
    addmode_sub.add_argument('--desc', required=True,
                             help='Mode description')
    addmode_sub.add_argument('--freq', required=True,
                             help='Clock frequency (e.g., 200MHz)')
    addmode_sub.add_argument('--sdc', required=True,
                             help='Constraint file path')
    addmode_sub.add_argument('--config', default=None,
                             help='Path to mmmc_config.tcl (auto-detected if omitted)')

    # remove-mode command
    rmmode_sub = subparsers.add_parser(
        'remove-mode', help='Remove an operating mode and its scenarios')
    rmmode_sub.add_argument('--name', required=True,
                            help='Mode name to remove')
    rmmode_sub.add_argument('--config', default=None,
                            help='Path to mmmc_config.tcl (auto-detected if omitted)')

    return parser


# -------------------------------------------------------------------------------
# Main Entry Point
# -------------------------------------------------------------------------------

def main() -> int:
    """Main entry point."""
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    # Command dispatch
    commands = {
        'create': cmd_create,
        'show': cmd_show,
        'validate': cmd_validate,
        'generate-view-def': cmd_generate_view_def,
        'add-mode': cmd_add_mode,
        'remove-mode': cmd_remove_mode,
    }

    if args.command not in commands:
        logger.error(f"Unknown command: {args.command}")
        logger.info(f"Available commands: {', '.join(commands.keys())}")
        return 1

    # Validate config file if specified
    config = getattr(args, 'config', None)
    if config and not os.path.exists(config):
        logger.error(f"Config file not found: {config}")
        logger.info("  Use --config to specify a valid mmmc_config.tcl path")
        return 1

    # Run with error handling
    try:
        return commands[args.command](args)
    except KeyboardInterrupt:
        logger.info("\n  Aborted by user (Ctrl+C)")
        return 1
    except PermissionError as e:
        logger.error(f"Permission denied: {e}")
        return 1
    except FileNotFoundError as e:
        logger.error(f"File not found: {e}")
        return 1
    except Exception as e:
        logger.error(f"Unexpected error: {type(e).__name__}: {e}")
        logger.info(f"  Command: cbflow flow mmmc-manager {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
