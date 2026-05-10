#!/usr/bin/env python3
# ===============================================================================
# CBFlow - Library Manager Command Handler
# Description: Comprehensive library management for scanning, validation,
#              tech_config generation, and MMMC analysis view creation.
# Usage: cbflow flow library-manager <subcommand> [options]
# ===============================================================================

import argparse
import os
import sys
import re
import json
import logging
from pathlib import Path
from dataclasses import dataclass, field, asdict
from typing import List, Dict, Optional, Tuple
from collections import defaultdict

# Configure unified logging
from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.library_manager')


def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory from environment or determine from script location."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


# -------------------------------------------------------------------------------
# Data Structures
# -------------------------------------------------------------------------------

@dataclass
class LibraryFile:
    """Represents a parsed .lib file with extracted metadata."""
    path: str
    filename: str
    prefix: str        # cell family (e.g., sc7p5t_cln22fcg_base_)
    corner: str        # ss/tt/ff/sf/fs
    voltage: float     # 0.80, 0.72, 1.00
    temperature: int   # -40, 25, 125
    lib_type: str      # ccs/power/noise/leakage/nldm
    category: str      # stdcell/memory/io/analog

    @property
    def set_key(self) -> str:
        """Library set key: corner_voltageV_tempC."""
        v_str = f"{self.voltage:.2f}".replace('.', '')
        return f"{self.corner}_{v_str}v_{self.temperature}c"

    @property
    def voltage_str(self) -> str:
        return f"{self.voltage:.2f}"

    @property
    def temp_str(self) -> str:
        return str(self.temperature)


@dataclass
class LibraryCharacterization:
    """Internal characterization data extracted from .lib file contents."""
    library_name: str = ""
    nom_voltage: float = 0.0
    nom_temperature: float = 0.0
    nom_process: float = 0.0
    operating_conditions: str = ""
    oc_voltage: float = 0.0
    oc_temperature: float = 0.0
    delay_model: str = ""
    cell_count: int = 0
    date: str = ""
    comment: str = ""
    technology: str = ""
    voltage_maps: Dict[str, float] = field(default_factory=dict)


@dataclass
class ValidationResult:
    """Result of a single library path validation."""
    path: str
    exists: bool
    lib_set: str = ""
    lib_type: str = ""


# -------------------------------------------------------------------------------
# LibraryScanner
# -------------------------------------------------------------------------------

# Primary pattern: prefix immediately before corner (no underscore separator)
LIB_PATTERN = re.compile(
    r'^(?P<prefix>.+?)(?P<corner>ss|ff|tt|sf|fs)'
    r'(?P<voltage>\d+p\d+v)(?P<temp>m?\d+c)'
    r'_(?P<type>ccs|power|noise|leakage|nldm)\.lib$'
)

# Alternate pattern: IO-style with underscore before corner
ALT_LIB_PATTERN = re.compile(
    r'^(?P<prefix>.+?)_(?P<corner>ss|ff|tt|sf|fs)'
    r'(?P<voltage>\d+p\d+v)(?P<temp>m?\d+c)'
    r'_(?P<type>ccs|power|noise|leakage|nldm)\.lib$'
)

# Category classification based on common prefix substrings
CATEGORY_PATTERNS = {
    'stdcell': re.compile(r'(sc\d|stdcell|std_cell|standard_cell|base_|rvt|lvt|hvt|svt)', re.IGNORECASE),
    'memory':  re.compile(r'(sram|rom|rf_|regfile|mem_|memory|dpsram|spsram|dp_ram|sp_ram)', re.IGNORECASE),
    'io':      re.compile(r'(io_|iocell|gpio|pad_|bump_|esd_|iolib)', re.IGNORECASE),
    'analog':  re.compile(r'(pll|dac|adc|analog|serdes|phy_|ldo|bgr|osc)', re.IGNORECASE),
}


def _parse_voltage(raw: str) -> float:
    """Convert voltage string like '0p800v' to float 0.80."""
    v = raw.rstrip('v').replace('p', '.')
    return round(float(v), 3)


def _parse_temperature(raw: str) -> int:
    """Convert temperature string like 'm40c' to int -40, '125c' to 125."""
    t = raw.rstrip('c')
    if t.startswith('m'):
        return -int(t[1:])
    return int(t)


def _classify_category(prefix: str) -> str:
    """Classify library category from its prefix string."""
    for category, pattern in CATEGORY_PATTERNS.items():
        if pattern.search(prefix):
            return category
    return 'stdcell'  # default assumption


class LibertyParser:
    """Parse Liberty (.lib) file headers to extract characterization data.

    Reads only the first ~200 lines for performance -- header info is always
    at the top of the file before cell definitions begin.
    """

    @staticmethod
    def parse_file(filepath: str, max_lines: int = 300) -> LibraryCharacterization:
        """Extract characterization data from a .lib file's header."""
        char = LibraryCharacterization()
        try:
            with open(filepath, 'r', errors='replace') as f:
                lines_read = 0
                in_oc_block = False
                for line in f:
                    lines_read += 1
                    if lines_read > max_lines:
                        break
                    stripped = line.strip()

                    # Library name: library (name) {
                    m = re.match(r'library\s*\(\s*(\S+)\s*\)', stripped)
                    if m:
                        char.library_name = m.group(1)
                        continue

                    # nom_voltage : 0.800 ;
                    m = re.match(r'nom_voltage\s*:\s*([\d.]+)\s*;', stripped)
                    if m:
                        char.nom_voltage = float(m.group(1))
                        continue

                    # nom_temperature : 125.000 ;
                    m = re.match(r'nom_temperature\s*:\s*([-\d.]+)\s*;', stripped)
                    if m:
                        char.nom_temperature = float(m.group(1))
                        continue

                    # nom_process : 1.0 ;
                    m = re.match(r'nom_process\s*:\s*([\d.]+)\s*;', stripped)
                    if m:
                        char.nom_process = float(m.group(1))
                        continue

                    # delay_model : table_lookup ;
                    m = re.match(r'delay_model\s*:\s*(\S+)\s*;', stripped)
                    if m:
                        char.delay_model = m.group(1)
                        continue

                    # date : "2023-10-15" ;
                    m = re.match(r'date\s*:\s*"([^"]+)"\s*;', stripped)
                    if m:
                        char.date = m.group(1)
                        continue

                    # comment : "..." ;
                    m = re.match(r'comment\s*:\s*"([^"]+)"\s*;', stripped)
                    if m:
                        char.comment = m.group(1)
                        continue

                    # technology (cmos) ;
                    m = re.match(r'technology\s*\(\s*(\S+)\s*\)', stripped)
                    if m:
                        char.technology = m.group(1)
                        continue

                    # operating_conditions (name) {
                    m = re.match(r'operating_conditions\s*\(\s*(\S+)\s*\)', stripped)
                    if m:
                        char.operating_conditions = m.group(1)
                        in_oc_block = True
                        continue

                    # Inside operating_conditions block
                    if in_oc_block:
                        m = re.match(r'voltage\s*:\s*([\d.]+)\s*;', stripped)
                        if m:
                            char.oc_voltage = float(m.group(1))
                        m = re.match(r'temperature\s*:\s*([-\d.]+)\s*;', stripped)
                        if m:
                            char.oc_temperature = float(m.group(1))
                        if stripped == '}':
                            in_oc_block = False
                        continue

                    # voltage_map (VDD, 0.800) ;
                    m = re.match(r'voltage_map\s*\(\s*(\S+)\s*,\s*([\d.]+)\s*\)', stripped)
                    if m:
                        char.voltage_maps[m.group(1)] = float(m.group(2))
                        continue

                    # cell (name) { -- count cells
                    if re.match(r'cell\s*\(', stripped):
                        char.cell_count += 1

        except (IOError, OSError) as e:
            logger.warning(f"Cannot read {filepath}: {e}")

        return char

    @staticmethod
    def verify_against_filename(lib_file: 'LibraryFile', char: LibraryCharacterization) -> List[str]:
        """Compare filename-extracted metadata against internal .lib data.

        Returns list of mismatches (empty = all good).
        """
        mismatches = []

        if char.nom_voltage > 0 and abs(char.nom_voltage - lib_file.voltage) > 0.01:
            mismatches.append(
                f"Voltage mismatch: filename={lib_file.voltage:.3f}V, "
                f"lib_header={char.nom_voltage:.3f}V"
            )

        if char.nom_temperature != 0 and int(char.nom_temperature) != lib_file.temperature:
            mismatches.append(
                f"Temperature mismatch: filename={lib_file.temperature}C, "
                f"lib_header={int(char.nom_temperature)}C"
            )

        if char.oc_voltage > 0 and abs(char.oc_voltage - lib_file.voltage) > 0.01:
            mismatches.append(
                f"OC voltage mismatch: filename={lib_file.voltage:.3f}V, "
                f"operating_conditions={char.oc_voltage:.3f}V"
            )

        if char.oc_temperature != 0 and int(char.oc_temperature) != lib_file.temperature:
            mismatches.append(
                f"OC temperature mismatch: filename={lib_file.temperature}C, "
                f"operating_conditions={int(char.oc_temperature)}C"
            )

        # Check corner in operating_conditions name
        if char.operating_conditions:
            oc_lower = char.operating_conditions.lower()
            if lib_file.corner not in oc_lower:
                mismatches.append(
                    f"Corner mismatch: filename={lib_file.corner}, "
                    f"operating_conditions={char.operating_conditions}"
                )

        return mismatches


class LibraryScanner:
    """Scans directories for .lib files and extracts metadata."""

    def scan_directory(self, path: str, recursive: bool = False) -> List[LibraryFile]:
        """Scan a directory for .lib files and parse their metadata."""
        libs = []
        scan_path = Path(path)

        if not scan_path.is_dir():
            logger.error(f"Directory not found: {path}")
            return libs

        if recursive:
            lib_files = sorted(scan_path.rglob('*.lib'))
        else:
            lib_files = sorted(scan_path.glob('*.lib'))

        for lib_path in lib_files:
            parsed = self._parse_filename(lib_path)
            if parsed:
                libs.append(parsed)
            else:
                logger.debug(f"Could not parse library filename: {lib_path.name}")

        return libs

    def _parse_filename(self, lib_path: Path) -> Optional[LibraryFile]:
        """Parse a .lib filename into a LibraryFile dataclass."""
        filename = lib_path.name

        for pattern in (LIB_PATTERN, ALT_LIB_PATTERN):
            m = pattern.match(filename)
            if m:
                try:
                    voltage = _parse_voltage(m.group('voltage'))
                    temperature = _parse_temperature(m.group('temp'))
                    prefix = m.group('prefix')
                    category = _classify_category(prefix)

                    return LibraryFile(
                        path=str(lib_path.resolve()),
                        filename=filename,
                        prefix=prefix,
                        corner=m.group('corner'),
                        voltage=voltage,
                        temperature=temperature,
                        lib_type=m.group('type'),
                        category=category,
                    )
                except (ValueError, IndexError) as e:
                    logger.debug(f"Parse error for {filename}: {e}")
                    return None

        return None

    def group_by_set(self, libs: List[LibraryFile]) -> Dict[str, List[LibraryFile]]:
        """Group libraries by set key (corner_voltage_temp)."""
        groups: Dict[str, List[LibraryFile]] = defaultdict(list)
        for lib in libs:
            groups[lib.set_key].append(lib)
        return dict(sorted(groups.items()))

    def generate_tech_config(self, sets: Dict[str, List[LibraryFile]],
                             track: Optional[str] = None) -> str:
        """Generate tech_config.tcl library_sets block from grouped libraries."""
        lines = ['array set library_sets {']

        corner_descriptions = {
            'ss': 'Slow corner',
            'ff': 'Fast corner',
            'tt': 'Typical corner',
            'sf': 'Slow-NMOS Fast-PMOS corner',
            'fs': 'Fast-NMOS Slow-PMOS corner',
        }

        for set_key, libs in sorted(sets.items()):
            # Apply track filter if specified
            if track:
                libs = [l for l in libs if track.lower() in l.prefix.lower()]
                if not libs:
                    continue

            # Use first lib for common attributes
            ref = libs[0]
            desc = corner_descriptions.get(ref.corner, ref.corner.upper() + ' corner')
            desc += f", {ref.voltage_str}V, {ref.temp_str}C"

            lines.append(f'    "{set_key}" {{')
            lines.append(f'        description  "{desc}"')
            lines.append(f'        voltage      "{ref.voltage_str}"')
            lines.append(f'        temperature  "{ref.temp_str}"')
            lines.append(f'        corner       "{ref.corner}"')

            # Categorize libs by type within this set
            by_type: Dict[str, List[str]] = defaultdict(list)
            for lib in libs:
                by_type[lib.lib_type].append(lib.path)

            type_to_key = {
                'ccs':     'timing_libraries',
                'nldm':    'timing_libraries',
                'power':   'power_libraries',
                'noise':   'noise_libraries',
                'leakage': 'leakage_libraries',
            }

            # Merge into output keys (ccs and nldm both go to timing_libraries)
            merged: Dict[str, List[str]] = defaultdict(list)
            for t, paths in by_type.items():
                key = type_to_key.get(t, f'{t}_libraries')
                merged[key].extend(paths)

            # Output in consistent order
            for lib_key in ('timing_libraries', 'power_libraries',
                            'noise_libraries', 'leakage_libraries'):
                if lib_key in merged:
                    lines.append(f'        {lib_key} {{')
                    for p in sorted(merged[lib_key]):
                        lines.append(f'            "{p}"')
                    lines.append('        }')

            lines.append('    }')

        lines.append('}')
        return '\n'.join(lines) + '\n'

    def generate_mmmc_views(self, sets: Dict[str, List[LibraryFile]]) -> str:
        """Generate MMMC analysis_views TCL block from library sets."""
        analysis_type_map = {
            'ss': 'setup',
            'sf': 'setup',
            'ff': 'hold',
            'fs': 'hold',
            'tt': 'setup_hold',
        }

        rc_corner_map = {
            'ss': 'rc_max',
            'sf': 'rc_max',
            'ff': 'rc_min',
            'fs': 'rc_min',
            'tt': 'rc_typical',
        }

        lines = ['array set analysis_views {']

        for set_key, libs in sorted(sets.items()):
            ref = libs[0]
            analysis_type = analysis_type_map.get(ref.corner, 'setup')
            rc_corner = rc_corner_map.get(ref.corner, 'rc_typical')

            v_str = ref.voltage_str.replace('.', 'p')
            view_name = f"{ref.voltage_str}_func_{ref.corner}_{rc_corner.replace('rc_', 'rc')}_{ref.temp_str}c"

            lines.append(f'    "{view_name}" {{')
            lines.append(f'        corner          "{ref.corner}"')
            lines.append(f'        mode            "functional"')
            lines.append(f'        voltage         {ref.voltage_str}')
            lines.append(f'        temperature     {ref.temp_str}')
            lines.append(f'        analysis_type   "{analysis_type}"')
            lines.append(f'        lib_set_ref     "{set_key}"')
            lines.append(f'        rc_corner       "{rc_corner}"')
            lines.append('    }')

        lines.append('}')
        return '\n'.join(lines) + '\n'


# -------------------------------------------------------------------------------
# LibraryValidator
# -------------------------------------------------------------------------------

class LibraryValidator:
    """Validates library configuration from tech_config.tcl files."""

    def load_tech_config(self, path: str) -> Dict:
        """Parse a tech_config.tcl file and extract library_sets array."""
        if not os.path.exists(path):
            logger.error(f"Tech config not found: {path}")
            return {}

        with open(path, 'r') as f:
            content = f.read()

        return self._parse_library_sets(content)

    def _parse_library_sets(self, content: str) -> Dict:
        """Extract library_sets from TCL array definition.

        Handles the TCL 'array set library_sets { ... }' syntax.
        Supports multiple array set blocks and nested braces.
        Returns dict of set_name -> {description, voltage, temperature, corner, *_libraries}.
        """
        sets = {}

        # Find ALL library_sets blocks using brace counting
        block = ""
        for m in re.finditer(r'array\s+set\s+library_sets\s*\{', content):
            start = m.end()
            depth = 1
            pos = start
            while pos < len(content) and depth > 0:
                if content[pos] == '{':
                    depth += 1
                elif content[pos] == '}':
                    depth -= 1
                pos += 1
            if depth == 0:
                block += content[start:pos - 1] + "\n"

        # Also parse individual "set library_sets(key,field) value" format
        set_pattern_individual = re.compile(
            r'set\s+library_sets\(([^,]+),(\w+)\)\s+["\{]?([^"\}]*)["\}]?',
            re.MULTILINE
        )
        for m in set_pattern_individual.finditer(content):
            set_name = m.group(1).strip()
            field = m.group(2).strip()
            value = m.group(3).strip().strip('"')
            if set_name not in sets:
                sets[set_name] = {}
            sets[set_name][field] = value

        if not block.strip() and not sets:
            logger.warning("No library_sets array found in tech config")
            return sets

        if sets:
            return sets

        # Parse individual set entries: "set_name" { ... }
        set_pattern = re.compile(
            r'"(?P<name>[^"]+)"\s*\{(?P<body>[^}]*(?:\{[^}]*\}[^}]*)*)\}',
            re.DOTALL
        )

        for set_match in set_pattern.finditer(block):
            set_name = set_match.group('name')
            body = set_match.group('body')
            set_data = self._parse_set_body(body)
            sets[set_name] = set_data

        return sets

    def _parse_set_body(self, body: str) -> Dict:
        """Parse the body of a single library set entry."""
        data = {}

        # Parse simple key-value pairs: key "value" or key value
        simple_kv = re.compile(r'(\w+)\s+"([^"]*)"')
        for m in simple_kv.finditer(body):
            data[m.group(1)] = m.group(2)

        # Parse library list blocks: key { "path1" "path2" ... }
        list_pattern = re.compile(r'(\w+_libraries)\s*\{([^}]*)\}', re.DOTALL)
        for m in list_pattern.finditer(body):
            key = m.group(1)
            paths_raw = m.group(2)
            paths = re.findall(r'"([^"]+)"', paths_raw)
            data[key] = paths

        return data

    def validate_libraries(self, config: Dict) -> List[ValidationResult]:
        """Validate that all referenced library files exist on disk."""
        results = []

        for set_name, set_data in sorted(config.items()):
            lib_keys = [k for k in set_data if k.endswith('_libraries')]
            for lib_key in lib_keys:
                lib_type = lib_key.replace('_libraries', '')
                paths = set_data[lib_key]
                if isinstance(paths, list):
                    for p in paths:
                        results.append(ValidationResult(
                            path=p,
                            exists=os.path.isfile(p),
                            lib_set=set_name,
                            lib_type=lib_type,
                        ))

        return results


# -------------------------------------------------------------------------------
# Command Implementations
# -------------------------------------------------------------------------------

def cmd_scan(args: argparse.Namespace) -> int:
    """Scan a directory for .lib files and report metadata."""
    scanner = LibraryScanner()
    libs = scanner.scan_directory(args.path, recursive=args.recursive)

    if not libs:
        logger.warning(f"No parseable .lib files found in: {args.path}")
        return 0

    # Gather statistics
    corners = sorted(set(l.corner for l in libs))
    voltages = sorted(set(l.voltage for l in libs))
    temps = sorted(set(l.temperature for l in libs))
    prefixes = sorted(set(l.prefix for l in libs))
    categories = sorted(set(l.category for l in libs))
    lib_types = sorted(set(l.lib_type for l in libs))

    if args.format == 'json':
        output = {
            'directory': os.path.abspath(args.path),
            'recursive': args.recursive,
            'total_files': len(libs),
            'unique_corners': corners,
            'unique_voltages': voltages,
            'unique_temperatures': temps,
            'unique_prefixes': prefixes,
            'unique_categories': categories,
            'unique_lib_types': lib_types,
            'libraries': [asdict(l) for l in libs],
        }
        print(json.dumps(output, indent=2))
    else:
        logger.info("")
        logger.info(f"{'='*65}")
        logger.info(f"  Library Scan Results")
        logger.info(f"{'='*65}")
        logger.info(f"  Directory:     {os.path.abspath(args.path)}")
        logger.info(f"  Recursive:     {args.recursive}")
        logger.info(f"  Total files:   {len(libs)}")
        logger.info(f"{'─'*65}")
        logger.info(f"  Corners:       {', '.join(corners)}")
        logger.info(f"  Voltages:      {', '.join(f'{v:.2f}V' for v in voltages)}")
        logger.info(f"  Temperatures:  {', '.join(f'{t}C' for t in temps)}")
        logger.info(f"  Prefixes:      {len(prefixes)}")
        logger.info(f"  Categories:    {', '.join(categories)}")
        logger.info(f"  Lib types:     {', '.join(lib_types)}")
        logger.info(f"{'─'*65}")

        # Group by set for summary
        sets = scanner.group_by_set(libs)
        logger.info(f"  Library sets:  {len(sets)}")
        for set_key, set_libs in sets.items():
            types_in_set = sorted(set(l.lib_type for l in set_libs))
            logger.info(f"    {set_key:<25} {len(set_libs):>3} libs  [{', '.join(types_in_set)}]")

        logger.info(f"{'='*65}")
        logger.info("")

    return 0


def cmd_create(args: argparse.Namespace) -> int:
    """Auto-generate tech_config library_sets TCL block from scanned libraries."""
    scanner = LibraryScanner()
    libs = scanner.scan_directory(args.path, recursive=True)

    if not libs:
        logger.error(f"No parseable .lib files found in: {args.path}")
        return 1

    sets = scanner.group_by_set(libs)
    track = getattr(args, 'track', None)
    tcl_output = scanner.generate_tech_config(sets, track=track)

    output_path = getattr(args, 'output', None)
    if output_path:
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        with open(output_path, 'w') as f:
            header = (
                f"# Auto-generated by CBFlow library-manager create\n"
                f"# Source directory: {os.path.abspath(args.path)}\n"
            )
            tech_node = getattr(args, 'tech_node', None)
            if tech_node:
                header += f"# Tech node: {tech_node}\n"
            if track:
                header += f"# Track filter: {track}\n"
            header += f"# Library sets: {len(sets)}\n\n"
            f.write(header)
            f.write(tcl_output)
        logger.info(f"Tech config written to: {output_path}")
        logger.info(f"  Library sets generated: {len(sets)}")
    else:
        print(tcl_output)

    return 0


def cmd_check(args: argparse.Namespace) -> int:
    """Validate library configuration against actual files on disk."""
    # Determine tech_config path
    tech_config_path = getattr(args, 'tech_config', None)
    if not tech_config_path:
        core_dir = get_cbflow_core_dir()
        tech_node = os.environ.get('CBFLOW_TECH_NODE', '') or os.environ.get('TECH_NAME', '')
        if not tech_node:
            logger.warning("CBFLOW_TECH_NODE or TECH_NAME not set, library paths may be incomplete")
        tech_config_path = os.path.join(
            core_dir, 'config', 'tech', tech_node, 'v1.0.0', 'tech_config.tcl'
        )

    logger.info(f"Checking library config: {tech_config_path}")

    validator = LibraryValidator()
    config = validator.load_tech_config(tech_config_path)

    if not config:
        logger.error("No library_sets found in tech config")
        return 1

    results = validator.validate_libraries(config)
    total = len(results)
    found = sum(1 for r in results if r.exists)
    missing = total - found

    verbose = getattr(args, 'verbose', False)

    logger.info("")
    logger.info(f"{'='*65}")
    logger.info(f"  Library Validation Report")
    logger.info(f"{'='*65}")
    logger.info(f"  Tech config:    {tech_config_path}")
    logger.info(f"  Library sets:   {len(config)}")
    logger.info(f"  Total refs:     {total}")
    logger.info(f"  Found:          {found}")
    logger.info(f"  Missing:        {missing}")
    logger.info(f"{'─'*65}")

    if verbose:
        for r in results:
            status = "[PASS]" if r.exists else "[FAIL]"
            logger.info(f"  {status}  [{r.lib_set}/{r.lib_type}]  {r.path}")
    elif missing > 0:
        logger.info("  Missing files:")
        for r in results:
            if not r.exists:
                logger.info(f"    [FAIL]  [{r.lib_set}/{r.lib_type}]  {r.path}")

    overall = "PASSED" if missing == 0 else "FAILED"
    logger.info(f"{'─'*65}")
    logger.info(f"  Overall: {overall}")
    logger.info(f"{'='*65}")
    logger.info("")

    return 0 if missing == 0 else 1


def cmd_list(args: argparse.Namespace) -> int:
    """List configured library sets with optional filtering."""
    # Determine tech_config path
    tech_config_path = getattr(args, 'tech_config', None)
    if not tech_config_path:
        core_dir = get_cbflow_core_dir()
        tech_node = os.environ.get('CBFLOW_TECH_NODE', '') or os.environ.get('TECH_NAME', '')
        if not tech_node:
            logger.warning("CBFLOW_TECH_NODE or TECH_NAME not set, library paths may be incomplete")
        tech_config_path = os.path.join(
            core_dir, 'config', 'tech', tech_node, 'v1.0.0', 'tech_config.tcl'
        )

    validator = LibraryValidator()
    config = validator.load_tech_config(tech_config_path)

    if not config:
        logger.error(f"No library_sets found in: {tech_config_path}")
        return 1

    # Apply filters
    corner_filter = getattr(args, 'corner', None)
    voltage_filter = getattr(args, 'voltage', None)
    temp_filter = getattr(args, 'temp', None)

    filtered = {}
    for set_name, set_data in config.items():
        if corner_filter and set_data.get('corner') != corner_filter:
            continue
        if voltage_filter and set_data.get('voltage') != str(voltage_filter):
            continue
        if temp_filter and set_data.get('temperature') != str(temp_filter):
            continue
        filtered[set_name] = set_data

    logger.info("")
    logger.info(f"{'='*70}")
    logger.info(f"  Library Sets  (source: {os.path.basename(tech_config_path)})")
    logger.info(f"{'='*70}")

    if not filtered:
        logger.info("  No library sets match the specified filters.")
    else:
        header = f"  {'Set Name':<28} {'Corner':<8} {'Voltage':<9} {'Temp':<7} {'Libs'}"
        logger.info(header)
        logger.info(f"  {'─'*66}")

        for set_name, set_data in sorted(filtered.items()):
            corner = set_data.get('corner', '?')
            voltage = set_data.get('voltage', '?')
            temperature = set_data.get('temperature', '?')

            # Count libraries per type
            lib_counts = []
            for key in ('timing_libraries', 'power_libraries',
                        'noise_libraries', 'leakage_libraries'):
                paths = set_data.get(key, [])
                count = len(paths) if isinstance(paths, list) else 0
                if count > 0:
                    short_key = key.replace('_libraries', '')
                    lib_counts.append(f"{short_key}:{count}")

            count_str = ', '.join(lib_counts) if lib_counts else 'none'
            logger.info(f"  {set_name:<28} {corner:<8} {voltage:<9} {temperature:<7} {count_str}")

    logger.info(f"{'='*70}")
    logger.info(f"  Total sets: {len(filtered)} / {len(config)}")
    logger.info("")

    return 0


def cmd_generate_mmmc(args: argparse.Namespace) -> int:
    """Generate MMMC analysis views from discovered libraries."""
    scanner = LibraryScanner()
    libs = scanner.scan_directory(args.path, recursive=True)

    if not libs:
        logger.error(f"No parseable .lib files found in: {args.path}")
        return 1

    sets = scanner.group_by_set(libs)
    mmmc_output = scanner.generate_mmmc_views(sets)

    output_path = getattr(args, 'output', None)
    if output_path:
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        with open(output_path, 'w') as f:
            header = (
                f"# Auto-generated MMMC analysis views by CBFlow library-manager\n"
                f"# Source directory: {os.path.abspath(args.path)}\n"
                f"# Analysis views: {len(sets)}\n\n"
            )
            f.write(header)
            f.write(mmmc_output)
        logger.info(f"MMMC config written to: {output_path}")
        logger.info(f"  Analysis views generated: {len(sets)}")
    else:
        print(mmmc_output)

    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    """Verify library characterization by reading inside .lib files."""
    scanner = LibraryScanner()
    libs = scanner.scan_directory(args.path, recursive=args.recursive)

    if not libs:
        logger.error(f"No parseable .lib files found in: {args.path}")
        return 1

    logger.info("")
    logger.info("=" * 72)
    logger.info("  Library Characterization Verification")
    logger.info("=" * 72)
    logger.info(f"  Directory:  {os.path.abspath(args.path)}")
    logger.info(f"  Files:      {len(libs)}")
    logger.info("-" * 72)

    total = 0
    passed = 0
    failed = 0
    errors = []

    for lib in libs:
        total += 1
        char = LibertyParser.parse_file(lib.path)

        if not char.library_name and char.nom_voltage == 0:
            logger.info(f"  [SKIP]  {lib.filename}  (could not parse header)")
            continue

        mismatches = LibertyParser.verify_against_filename(lib, char)

        if mismatches:
            failed += 1
            status = "FAIL"
            for mm in mismatches:
                errors.append(f"  {lib.filename}: {mm}")
        else:
            passed += 1
            status = "PASS"

        if args.verbose or mismatches:
            logger.info(f"  [{status}]  {lib.filename}")
            if char.library_name:
                logger.info(f"           library_name: {char.library_name}")
            logger.info(f"           nom_voltage={char.nom_voltage:.3f}V  "
                         f"nom_temperature={int(char.nom_temperature)}C  "
                         f"cells={char.cell_count}")
            if char.operating_conditions:
                logger.info(f"           operating_conditions: {char.operating_conditions} "
                             f"(V={char.oc_voltage:.3f}, T={int(char.oc_temperature)}C)")
            if char.voltage_maps:
                maps_str = ", ".join(f"{k}={v:.3f}V" for k, v in char.voltage_maps.items())
                logger.info(f"           voltage_maps: {maps_str}")
            if char.date:
                logger.info(f"           date: {char.date}")
            for mm in mismatches:
                logger.info(f"           MISMATCH: {mm}")
            logger.info("")

    logger.info("-" * 72)
    logger.info(f"  Total: {total}  |  Passed: {passed}  |  Failed: {failed}  |  "
                 f"Skipped: {total - passed - failed}")
    if errors:
        logger.info("")
        logger.info("  MISMATCHES:")
        for e in errors:
            logger.info(e)
    logger.info("=" * 72)

    # JSON output
    if args.format == 'json':
        results = []
        for lib in libs:
            char = LibertyParser.parse_file(lib.path)
            mismatches = LibertyParser.verify_against_filename(lib, char)
            results.append({
                'filename': lib.filename,
                'filename_corner': lib.corner,
                'filename_voltage': lib.voltage,
                'filename_temperature': lib.temperature,
                'lib_name': char.library_name,
                'lib_nom_voltage': char.nom_voltage,
                'lib_nom_temperature': char.nom_temperature,
                'lib_cell_count': char.cell_count,
                'operating_conditions': char.operating_conditions,
                'mismatches': mismatches,
                'status': 'FAIL' if mismatches else 'PASS',
            })
        print(json.dumps(results, indent=2))

    return 1 if failed > 0 else 0


# -------------------------------------------------------------------------------
# Argument Parser
# -------------------------------------------------------------------------------

def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow library-manager',
        description='CBFlow - Library Manager',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow library-manager scan --path /libs/gf22 --recursive
  cbflow flow library-manager scan --path /libs/gf22 --format json
  cbflow flow library-manager create --path /libs/gf22 --output tech_config_libs.tcl
  cbflow flow library-manager create --path /libs/gf22 --track 9T
  cbflow flow library-manager check --tech-config config/tech/gf_22nm/v1.0.0/tech_config.tcl
  cbflow flow library-manager check --verbose
  cbflow flow library-manager list --corner ss --voltage 0.80
  cbflow flow library-manager generate-mmmc --path /libs/gf22 --output mmmc_scenarios.tcl
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Library manager commands')

    # scan command
    scan_parser = subparsers.add_parser('scan', help='Scan directory for .lib files')
    scan_parser.add_argument('--path', required=True,
                             help='Directory to scan for .lib files')
    scan_parser.add_argument('--recursive', action='store_true', default=False,
                             help='Scan subdirectories recursively')
    scan_parser.add_argument('--format', choices=['text', 'json'], default='text',
                             help='Output format (default: text)')

    # create command
    create_parser_sub = subparsers.add_parser(
        'create', help='Generate tech_config library_sets TCL block')
    create_parser_sub.add_argument('--path', required=True,
                                   help='Directory to scan for .lib files')
    create_parser_sub.add_argument('--tech-node', default=None,
                                   help='Technology node identifier (e.g., gf_22nm)')
    create_parser_sub.add_argument('--output', default=None,
                                   help='Output file path (default: stdout)')
    create_parser_sub.add_argument('--track', default=None,
                                   help='Filter libraries by track (e.g., 9T)')

    # check command
    check_parser = subparsers.add_parser(
        'check', help='Validate library config against disk')
    check_parser.add_argument('--tech-config', default=None,
                              help='Path to tech_config.tcl (auto-detected if omitted)')
    check_parser.add_argument('--verbose', action='store_true', default=False,
                              help='Show result for every referenced library')

    # list command
    list_parser = subparsers.add_parser('list', help='List configured library sets')
    list_parser.add_argument('--tech-config', default=None,
                             help='Path to tech_config.tcl (auto-detected if omitted)')
    list_parser.add_argument('--corner', default=None,
                             help='Filter by corner (ss/tt/ff/sf/fs)')
    list_parser.add_argument('--voltage', type=float, default=None,
                             help='Filter by voltage (e.g., 0.80)')
    list_parser.add_argument('--temp', type=int, default=None,
                             help='Filter by temperature (e.g., 125)')

    # verify command
    verify_parser = subparsers.add_parser(
        'verify', help='Verify library characterization by reading .lib file contents')
    verify_parser.add_argument('--path', required=True,
                                help='Directory to scan for .lib files')
    verify_parser.add_argument('--recursive', action='store_true', default=False,
                                help='Scan subdirectories recursively')
    verify_parser.add_argument('--verbose', action='store_true', default=False,
                                help='Show details for every file (not just failures)')
    verify_parser.add_argument('--format', choices=['text', 'json'], default='text',
                                help='Output format (default: text)')

    # generate-mmmc command
    mmmc_parser = subparsers.add_parser(
        'generate-mmmc', help='Generate MMMC analysis views')
    mmmc_parser.add_argument('--path', required=True,
                             help='Directory to scan for .lib files')
    mmmc_parser.add_argument('--output', default=None,
                             help='Output file path (default: stdout)')

    return parser


# -------------------------------------------------------------------------------
# Main Entry Point
# -------------------------------------------------------------------------------

def _validate_path_arg(args, attr='path'):
    """Validate that a path argument exists and is a directory."""
    path = getattr(args, attr, None)
    if path is None:
        return True  # Optional arg
    if not os.path.exists(path):
        logger.error(f"Path does not exist: {path}")
        logger.info(f"  Please provide a valid directory path with --{attr.replace('_', '-')}")
        return False
    if not os.path.isdir(path):
        logger.error(f"Path is not a directory: {path}")
        logger.info(f"  Please provide a directory, not a file")
        return False
    return True


def _validate_file_arg(args, attr):
    """Validate that a file argument exists."""
    path = getattr(args, attr, None)
    if path is None:
        return True  # Optional arg
    if not os.path.exists(path):
        logger.error(f"File does not exist: {path}")
        return False
    return True


def main() -> int:
    """Main entry point."""
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    # Command dispatch
    commands = {
        'scan': cmd_scan,
        'create': cmd_create,
        'check': cmd_check,
        'list': cmd_list,
        'verify': cmd_verify,
        'generate-mmmc': cmd_generate_mmmc,
    }

    if args.command not in commands:
        logger.error(f"Unknown command: {args.command}")
        logger.info(f"Available commands: {', '.join(commands.keys())}")
        return 1

    # Validate path arguments before dispatching
    if hasattr(args, 'path') and args.path is not None:
        if not _validate_path_arg(args, 'path'):
            return 1

    if hasattr(args, 'tech_config') and args.tech_config is not None:
        if not _validate_file_arg(args, 'tech_config'):
            return 1

    # Run command with error handling
    try:
        return commands[args.command](args)
    except KeyboardInterrupt:
        logger.info("\n  Aborted by user (Ctrl+C)")
        return 1
    except PermissionError as e:
        logger.error(f"Permission denied: {e}")
        logger.info("  Check file/directory permissions")
        return 1
    except FileNotFoundError as e:
        logger.error(f"File not found: {e}")
        logger.info("  Verify the path exists and is accessible")
        return 1
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON: {e}")
        return 1
    except Exception as e:
        logger.error(f"Unexpected error: {type(e).__name__}: {e}")
        logger.info("  If this is a bug, please report it with the full command and traceback")
        logger.info(f"  Command: cbflow flow library-manager {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
