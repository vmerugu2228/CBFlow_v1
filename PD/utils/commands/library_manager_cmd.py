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
try:
    from dataclasses import dataclass, field, asdict
except ImportError:
    # Python 3.6 fallback — dataclasses added in 3.7
    # pip install dataclasses  (backport available on PyPI)
    raise ImportError("dataclasses required — run: pip install dataclasses (Python 3.6 backport)")
from typing import List, Dict, Optional, Tuple
from collections import defaultdict

# Configure unified logging
from logging_config import configure_logging, get_logger

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir, get_flow_config_version

logger = configure_logging('cbflow.library_manager')



def _resolve_lib_root_from_tech_config(tech_name=None) -> str:
    """Read tech(lib_root) from tech_config.tcl. Returns path or empty string."""
    core_dir = get_cbflow_core_dir()
    version = get_flow_config_version()
    # Try specific tech
    if tech_name:
        tc = os.path.join(core_dir, 'config', 'tech', tech_name, version, 'tech_config.tcl')
        if os.path.exists(tc):
            with open(tc, 'r') as f:
                m = re.search(r'set\s+tech\(lib_root\)\s+"([^"]+)"', f.read())
                if m:
                    return m.group(1)
    # Scan all tech configs
    tech_dir = os.path.join(core_dir, 'config', 'tech')
    if os.path.isdir(tech_dir):
        for t in os.listdir(tech_dir):
            tc = os.path.join(tech_dir, t, version, 'tech_config.tcl')
            if os.path.exists(tc):
                with open(tc, 'r') as f:
                    m = re.search(r'set\s+tech\(lib_root\)\s+"([^"]+)"', f.read())
                    if m:
                        return m.group(1)
    return ''


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
        """Parse a tech config and return library sets.

        Tries two schemas in order:
          1. Legacy `array set library_sets { ... }` in the tech_config.tcl
             itself (older config style).
          2. Per-key `set tech(<corner>,<voltage>,<temp>,db|lib) [list ...]`
             and `set tech(<track>,<vt>,ndm) [list ...]` in the sibling
             `lib_config.tcl` (current style — written by `library-manager
             generate`, kept track-categorized).
        """
        if not os.path.exists(path):
            logger.error(f"Tech config not found: {path}")
            return {}

        with open(path, 'r') as f:
            content = f.read()

        sets = self._parse_library_sets(content)
        if sets:
            return sets

        # Fall back to sibling lib_config.tcl (current generate output).
        sibling = os.path.join(os.path.dirname(path), 'lib_config.tcl')
        if os.path.exists(sibling):
            logger.info(
                f"No library_sets array in tech_config; using sibling "
                f"{os.path.basename(sibling)} (per-key schema)"
            )
            with open(sibling, 'r') as f:
                return self._parse_lib_config_per_key(f.read())

        return sets

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

    @staticmethod
    def _voltage_str(v: str) -> str:
        # "0p80v" → "0.80"
        return v.replace('v', '').replace('p', '.')

    @staticmethod
    def _temp_str(t: str) -> str:
        # "125c" → "125", "m40c" → "-40"
        t = t.rstrip('c')
        return f'-{t[1:]}' if t.startswith('m') else t

    def _parse_lib_config_per_key(self, content: str) -> Dict:
        """Synthesize a library_sets-shape dict from the per-key schema.

        Recognized lines in lib_config.tcl:
          set tech(<corner>,<voltage>,<temp>,db|lib)  [list "<path>" ...]
          set tech(<track>,<vt>,ndm|db|lib)            [list "<path>" ...]
          set tech(ndm|db|lib,memory|io|analog)        [list "<path>" ...]

        Sets are keyed so list/check can present them in the same table
        shape as the legacy library_sets array.
        """
        sets: Dict[str, Dict] = {}

        def _split_paths(raw: str) -> List[str]:
            return re.findall(r'"([^"]+)"', raw)

        # PVT entries: <corner>,<voltage>,<temp>,<kind>
        pvt_re = re.compile(
            r'^\s*set\s+tech\(\s*(\w+)\s*,\s*(\d+p\d+v)\s*,\s*(\w+)\s*,\s*(db|lib|ndm)\s*\)'
            r'\s+\[list\s+(.+?)\]\s*$',
            re.MULTILINE
        )
        for m in pvt_re.finditer(content):
            corner, volt, temp, kind = m.group(1), m.group(2), m.group(3), m.group(4)
            paths = _split_paths(m.group(5))
            if not paths:
                continue
            set_name = f'{corner}_{volt}_{temp}'
            entry = sets.setdefault(set_name, {
                'corner': corner,
                'voltage': self._voltage_str(volt),
                'temperature': self._temp_str(temp),
            })
            lib_key = 'timing_libraries' if kind in ('db', 'lib') else 'ndm_libraries'
            entry.setdefault(lib_key, []).extend(paths)

        # Per-track/per-VT physical: tech(<track>,<vt>,<kind>)
        track_vt_re = re.compile(
            r'^\s*set\s+tech\(\s*([0-9.]+T)\s*,\s*(\w+)\s*,\s*(ndm|db|lib)\s*\)'
            r'\s+\[list\s+(.+?)\]\s*$',
            re.MULTILINE
        )
        for m in track_vt_re.finditer(content):
            track, vt, kind = m.group(1), m.group(2), m.group(3)
            paths = _split_paths(m.group(4))
            if not paths:
                continue
            set_name = f'physical_{track}_{vt}'
            entry = sets.setdefault(set_name, {
                'corner': 'physical',
                'voltage': '-',
                'temperature': '-',
            })
            lib_key = 'ndm_libraries' if kind == 'ndm' else 'timing_libraries'
            entry.setdefault(lib_key, []).extend(paths)

        # Shared physical: tech(<kind>,memory|io|analog)
        shared_re = re.compile(
            r'^\s*set\s+tech\(\s*(ndm|db|lib)\s*,\s*(memory|io|analog)\s*\)'
            r'\s+\[list\s+(.+?)\]\s*$',
            re.MULTILINE
        )
        for m in shared_re.finditer(content):
            kind, category = m.group(1), m.group(2)
            paths = _split_paths(m.group(3))
            if not paths:
                continue
            set_name = f'shared_{category}'
            entry = sets.setdefault(set_name, {
                'corner': 'physical',
                'voltage': '-',
                'temperature': '-',
            })
            lib_key = 'ndm_libraries' if kind == 'ndm' else 'timing_libraries'
            entry.setdefault(lib_key, []).extend(paths)

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


    # cmd_create removed — replaced by cmd_generate which produces lib_config.tcl


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
# Generate lib_config.tcl — auto-discover libraries from directories
# -------------------------------------------------------------------------------

# Patterns for parsing library filenames
_TRACK_RE = re.compile(r'(\d+p?\d*t)', re.IGNORECASE)

# Corner regex: handles both formats
#   TSMC/GF22 style: ss0p76v150c (no separators)
#   GF28 style:      ss_nominal_max_0p90v_m40c (underscores, extra fields)
# Corner regex: handles both formats
#   TSMC/GF22: tcbn22cllbwp9tsvtss0p76v150c (no separators, ss after cell name)
#   GF28:      sc7mcz_base_rvt_c30_ss_nominal_max_0p90v_m40c (underscores, extra fields)
_CORNER_RE = re.compile(
    r'(ss|tt|ff|sf|fs)'                      # process corner
    r'(?:_[a-z]+)*?'                         # optional condition words (nominal, max, etc.)
    r'_?(\d+p\d+v)'                          # voltage: 0p76v, 0p90v, 1p10v
    r'_?(m?\d+c)',                            # temperature
    re.IGNORECASE
)

# Channel length regex: c28, c30, c35
_CHANNEL_RE = re.compile(r'[_/]c(\d+)[_/.]', re.IGNORECASE)

# Default VT keywords — covers all common foundry VTs
_VT_KEYWORDS = ['ulvt', 'elvt', 'slvt', 'lvt', 'svt', 'rvt', 'hvt']


def _is_lib_file(filename):
    """Check if file is a liberty library (handles .gz, multi-part extensions)."""
    fn = filename.lower()
    return (fn.endswith('.lib') or fn.endswith('.lib.gz')
            or '.lib_ccs' in fn or '.lib_nldm' in fn)


def _is_lef_file(filename):
    """Check if file is a LEF."""
    return filename.lower().endswith('.lef')


def _is_ndm_file(filename):
    """Check if file is an NDM."""
    return filename.lower().endswith('.ndm')


def _is_db_file(filename):
    """Check if file is a DB."""
    return filename.lower().endswith('.db')


def _strip_lib_extension(filename):
    """Strip library extension for parsing. Returns (base_name, lib_type)."""
    fn = filename
    if fn.endswith('.gz'):
        fn = fn[:-3]
    if '.lib_ccs_tn' in fn:
        return fn.split('.lib_ccs_tn')[0], 'ccs_tn'
    if '.lib_ccs_p' in fn:
        return fn.split('.lib_ccs_p')[0], 'ccs_p'
    if fn.endswith('_ccs.lib'):
        return fn[:-8], 'ccs'
    if fn.endswith('_nldm.lib'):
        return fn[:-9], 'nldm'
    if fn.endswith('.lib'):
        return fn[:-4], 'lib'
    return fn, 'unknown'


def _detect_lib_type_from_path(filepath):
    """Detect library type from parent directory name."""
    parts = filepath.lower().replace('\\', '/').split('/')
    for p in parts:
        if 'lib-ccs-tn' in p or 'lib_ccs_tn' in p or 'timing' in p:
            return 'timing'
        if 'lib-ccs-p' in p or 'lib_ccs_p' in p or 'power' in p:
            return 'power'
        if 'lib-nldm' in p or 'nldm' in p:
            return 'timing'
    return 'timing'  # default


def _extract_vt(filename, vt_patterns=None):
    """Extract VT flavor from filename. Returns (vt, match_pos) or (None, -1)."""
    fn_lower = filename.lower()
    vts = vt_patterns or _VT_KEYWORDS
    for vt in sorted(vts, key=len, reverse=True):  # longest first (ulvt before lvt)
        # Match VT as a whole word boundary: _rvt_ or _rvt. or start/end
        pattern = r'(?:^|[_/])' + re.escape(vt.lower()) + r'(?:[_/.]|$)'
        m = re.search(pattern, fn_lower)
        if m:
            return vt, m.start()
    # Fallback: simple substring (backward compat)
    for vt in sorted(vts, key=len, reverse=True):
        idx = fn_lower.find(vt.lower())
        if idx >= 0:
            return vt, idx
    return None, -1


def _extract_track(filename, tracks_available=None, track_patterns=None):
    """Extract track from filename (e.g., '9t', '7p5t', '5t').

    Supports track_patterns dict: {'7T': '*sc7*', '9T': '*sc9*'} for non-standard naming.
    """
    import fnmatch as _fn
    fn_lower = filename.lower()
    # Priority 1: track patterns from tech_config (e.g., tech(track_pattern,7T) "*sc7*")
    if track_patterns:
        for trk, pat in track_patterns.items():
            if _fn.fnmatch(fn_lower, pat.lower()):
                return trk
    # Priority 2: substring match (TSMC/GF22 style: "9t" in filename)
    if tracks_available:
        for trk in sorted(tracks_available, key=len, reverse=True):
            trk_lower = trk.lower().replace('.', 'p')
            if trk_lower in fn_lower:
                return trk
    # Priority 3: regex fallback
    m = _TRACK_RE.search(fn_lower)
    if m:
        raw = m.group(1).upper().replace('P', '.').rstrip('T') + 'T'
        return raw
    return None


def _extract_corner(filename):
    """Extract corner key from filename (e.g., 'ss_0p76v_150c')."""
    m = _CORNER_RE.search(filename.lower())
    if m:
        pvt = m.group(1)
        voltage = m.group(2)
        temp = m.group(3)
        return "{}_{}_{}".format(pvt, voltage, temp)
    return None


def _format_corner_key(corner_str):
    """Normalize corner key to standard format (e.g., 'ss_0p76v_150c')."""
    return corner_str


def _prompt_choice(prompt_text, options):
    """Display numbered list and prompt user to select one."""
    print('  {}:'.format(prompt_text))
    for i, opt in enumerate(options, 1):
        print('    {}. {}'.format(i, opt))
    choice = input('  Select [1-{}]: '.format(len(options))).strip()
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(options):
            return options[idx]
    except ValueError:
        if choice in options:
            return choice
    return None


def _prompt_paths(label, base_dir=None):
    """Prompt user for one or more directory paths. Empty line to finish.
    Paths are resolved as absolute. If base_dir is given, relative paths
    resolve relative to it (not cwd)."""
    paths = []
    hint = ' (relative to {})'.format(base_dir) if base_dir else ''
    print('  {}{} (one per line, empty line to finish):'.format(label, hint))
    while True:
        p = input('    path: ').strip()
        if not p:
            break
        # Resolve relative paths against base_dir, not cwd
        if not os.path.isabs(p) and base_dir:
            p = os.path.join(base_dir, p)
        p = os.path.abspath(p)
        if os.path.isdir(p):
            paths.append(p)
            print('    OK: {}'.format(p))
        else:
            print('    WARNING: directory not found: {}'.format(p))
            add_anyway = input('    Add anyway? [y/N]: ').strip().lower()
            if add_anyway == 'y':
                paths.append(p)
    return paths if paths else None


def cmd_generate(args: argparse.Namespace) -> int:
    """Generate lib_config_<tag>.tcl by scanning library directories.

    Discovers all available libraries (NDM, DB, LEF, lib_nom, timing)
    organized by track x VT x corner. Writes fully resolved absolute paths.
    """
    # Detect interactive mode (stdin is a terminal)
    _interactive = sys.stdin.isatty()

    if _interactive:
        print('')
        print('  ============================================================')
        print('  CBflow Library Config Generator')
        print('  ============================================================')
        print('')

    # 1. Technology
    tech_name = args.tech
    if not tech_name:
        if not _interactive:
            logger.error("--tech is required in non-interactive mode")
            return 1
        core_dir = get_cbflow_core_dir()
        tech_base = os.path.join(core_dir, 'config', 'tech')
        available = sorted(d for d in os.listdir(tech_base)
                          if os.path.isdir(os.path.join(tech_base, d))) if os.path.isdir(tech_base) else []
        if not available:
            logger.error("No technologies found in {}".format(tech_base))
            return 1
        tech_name = _prompt_choice('Select technology', available)
        if not tech_name:
            logger.error("Invalid selection"); return 1
        print('  -> {}'.format(tech_name))
    args.tech = tech_name

    # 2. Tag (mandatory)
    tag = args.tag if hasattr(args, 'tag') and args.tag else None
    if not tag and not args.output:
        if not _interactive:
            logger.error("--tag is required (e.g., --tag P0, --tag timing_v1)")
            return 1
        print('')
        # Show existing tags
        core_dir = get_cbflow_core_dir()
        version = args.version or "v1.0.0"
        _tag_dir = os.path.join(core_dir, "config", "tech", tech_name, version)
        _existing_tags = []
        if os.path.isdir(_tag_dir):
            for f in sorted(os.listdir(_tag_dir)):
                if f.startswith('lib_config_') and f.endswith('.tcl'):
                    _existing_tags.append(f.replace('lib_config_', '').replace('.tcl', ''))
        if _existing_tags:
            print('  Existing lib_config tags: {}'.format(', '.join(_existing_tags)))
        tag = input('  Config tag (e.g., P0, timing_v1, signoff): ').strip()
        if not tag:
            logger.error("Tag is required. Output will be: lib_config_<tag>.tcl")
            return 1
        args.tag = tag
        # Check if tag already exists
        _tag_file = os.path.join(_tag_dir, 'lib_config_{}.tcl'.format(tag))
        if os.path.exists(_tag_file):
            print('  WARNING: lib_config_{}.tcl already exists'.format(tag))
            overwrite = input('  Overwrite? [y/N]: ').strip().lower()
            if overwrite != 'y':
                logger.info("Aborted — choose a different tag")
                return 1
            print('  -> will overwrite lib_config_{}.tcl'.format(tag))
        else:
            print('  -> lib_config_{}.tcl (new)'.format(tag))

    # 3. Library root (stdcell base)
    lib_root = args.lib_root
    if not lib_root:
        lib_root = _resolve_lib_root_from_tech_config(tech_name)
        if lib_root and _interactive:
            print('')
            print('  Stdcell lib root (from project_config): {}'.format(lib_root))
            use_it = input('  Use this? [Y/n]: ').strip().lower()
            if use_it == 'n':
                lib_root = None
    if not lib_root and _interactive:
        print('')
        lib_root = input('  Stdcell library root path: ').strip()
    if not lib_root:
        logger.error("lib_root is required. Provide --lib-root or set project(lib_root) in project_config")
        return 1
    if not os.path.isdir(lib_root):
        logger.error("lib_root directory not found: {}".format(lib_root))
        logger.info("  Update project(lib_root) in project_config, or use --lib-root to override")
        return 1

    lib_root = os.path.abspath(lib_root)
    tech_name = args.tech or os.path.basename(lib_root)
    version = args.version or "v1.0.0"

    # 4. Additional library paths — interactive prompts only if stdin is a terminal
    _interactive = sys.stdin.isatty()

    if _interactive:
        if not (hasattr(args, 'stdcell_path') and args.stdcell_path):
            print('')
            print('  Additional stdcell paths? (beyond lib_root)')
            extra = _prompt_paths('Stdcell paths', lib_root)
            if extra:
                args.stdcell_path = extra

        if not (hasattr(args, 'memory_path') and args.memory_path):
            print('')
            extra = _prompt_paths('Memory library paths', lib_root)
            if extra:
                args.memory_path = extra

        if not (hasattr(args, 'io_path') and args.io_path):
            print('')
            extra = _prompt_paths('IO library paths', lib_root)
            if extra:
                args.io_path = extra

        if not (hasattr(args, 'ip_path') and args.ip_path):
            print('')
            extra = _prompt_paths('IP/Analog library paths', lib_root)
            if extra:
                args.ip_path = extra

        # 5. Exclude patterns
        if not (hasattr(args, 'exclude') and args.exclude):
            print('')
            excl = input('  Exclude patterns (space-separated globs, e.g., *channel* *dummy*): ').strip()
            if excl:
                args.exclude = excl.split()

    # ── Confirm all inputs ──
    print('')
    print('  ────────────────────────────────────────────────────────────')
    print('  Configuration Summary')
    print('  ────────────────────────────────────────────────────────────')
    print('  Technology:    {}'.format(tech_name))
    print('  Tag:           {}'.format(args.tag if hasattr(args, 'tag') and args.tag else '(custom output)'))
    print('  Lib root:      {}'.format(lib_root))
    _all_paths_ok = os.path.isdir(lib_root)
    for label, attr in [('Stdcell paths', 'stdcell_path'), ('Memory paths', 'memory_path'),
                        ('IO paths', 'io_path'), ('IP paths', 'ip_path')]:
        paths = getattr(args, attr, None) if hasattr(args, attr) else None
        if paths:
            for p in paths:
                exists = os.path.isdir(p)
                status = '' if exists else ' [NOT FOUND]'
                if not exists:
                    _all_paths_ok = False
                print('  {}:  {}{}'.format(label, p, status))
    excl = getattr(args, 'exclude', [])
    if excl:
        print('  Exclude:       {}'.format(' '.join(excl)))
    print('  ────────────────────────────────────────────────────────────')

    if not _all_paths_ok:
        print('')
        print('  WARNING: Some paths do not exist.')
        if _interactive:
            proceed = input('  Continue anyway? [y/N]: ').strip().lower()
            if proceed != 'y':
                logger.info("Aborted by user")
                return 1

    if _interactive:
        confirm = input('  Proceed with scan? [Y/n]: ').strip().lower()
        if confirm == 'n':
            logger.info("Aborted by user")
            return 1
    print('')

    # Exclude patterns (glob wildcards)
    import fnmatch
    exclude_patterns = args.exclude if hasattr(args, 'exclude') and args.exclude else []
    def _is_excluded(filepath):
        """Match exclude patterns against full absolute path and filename."""
        fp_lower = filepath.lower()
        fn_lower = os.path.basename(filepath).lower()
        for pat in exclude_patterns:
            pat_lower = pat.lower()
            if fnmatch.fnmatch(fp_lower, pat_lower) or fnmatch.fnmatch(fn_lower, pat_lower):
                return True
        return False

    # Resolve tracks and VTs — try reading from tech_config.tcl first
    tracks = args.tracks.split() if args.tracks else None
    vt_list = args.vts.split() if args.vts else None

    _track_patterns = {}  # tech(track_pattern,<track>) patterns for non-standard naming

    if not tracks or not vt_list or not _track_patterns:
        core_dir = get_cbflow_core_dir()
        tc_path = os.path.join(core_dir, "config", "tech", tech_name, version, "tech_config.tcl")
        if os.path.exists(tc_path):
            with open(tc_path, 'r') as _tcf:
                _tc_content = _tcf.read()
            if not tracks:
                m = re.search(r'set\s+tech\(tracks_available\)\s+"([^"]+)"', _tc_content)
                if m:
                    tracks = m.group(1).split()
                    logger.info("Auto-detected tracks from tech_config: {}".format(" ".join(tracks)))
            # Read track patterns: tech(track_pattern,7T) "*sc7*"
            _track_patterns = {}
            for tp_m in re.finditer(r'set\s+tech\(track_pattern,(\S+)\)\s+"([^"]+)"', _tc_content):
                _track_patterns[tp_m.group(1)] = tp_m.group(2)
            if _track_patterns:
                logger.info("Track patterns: {}".format(
                    ", ".join("{}={}".format(k, v) for k, v in _track_patterns.items())))
            if not vt_list:
                m = re.search(r'set\s+tech\(vt_variants_available\)\s+\{([^}]+)\}', _tc_content)
                if m:
                    vt_list = m.group(1).split()
                    logger.info("Auto-detected VTs from tech_config: {}".format(" ".join(vt_list)))
            # Read additional lib paths from tech_config
            if not (hasattr(args, 'stdcell_path') and args.stdcell_path):
                m = re.search(r'set\s+tech\(lib_paths,stdcell\)\s+\[list\s+(.+?)\]', _tc_content)
                if m and m.group(1).strip():
                    extra = re.findall(r'"([^"]+)"', m.group(1))
                    if extra:
                        args.stdcell_path = extra
                        logger.info("Auto-detected stdcell paths from tech_config: {}".format(" ".join(extra)))
            if not (hasattr(args, 'memory_path') and args.memory_path):
                m = re.search(r'set\s+tech\(lib_paths,memory\)\s+\[list\s+(.+?)\]', _tc_content)
                if m and m.group(1).strip():
                    extra = re.findall(r'"([^"]+)"', m.group(1))
                    if extra:
                        args.memory_path = extra
                        logger.info("Auto-detected memory paths from tech_config: {}".format(" ".join(extra)))
            if not (hasattr(args, 'io_path') and args.io_path):
                m = re.search(r'set\s+tech\(lib_paths,io\)\s+\[list\s+(.+?)\]', _tc_content)
                if m and m.group(1).strip():
                    extra = re.findall(r'"([^"]+)"', m.group(1))
                    if extra:
                        args.io_path = extra
                        logger.info("Auto-detected IO paths from tech_config: {}".format(" ".join(extra)))

    if not vt_list:
        vt_list = _VT_KEYWORDS

    if exclude_patterns:
        logger.info("Exclude patterns: {}".format(", ".join(exclude_patterns)))

    # ── Directory discovery — NO hardcoded paths ──
    # Recursively scan all user-given paths and classify by file content.
    # Classification: ndm → .ndm files, lef → .lef files,
    #   memory → dir name contains 'memory'/'mem', io → 'io'/'iolib',
    #   everything else with .lib/.db → stdcell
    ndm_dirs = []
    lef_dirs = []
    stdcell_dirs = []
    memory_dirs = []
    io_dirs = []

    def _scan_tree(root_path, target_category=None):
        """Recursively walk root_path, classify each directory by content.
        If target_category is set, all lib/db dirs go to that category."""
        if not os.path.isdir(root_path):
            return
        for root, dirs, files in os.walk(root_path):
            has_ndm = any(_is_ndm_file(f) for f in files)
            has_lef = any(_is_lef_file(f) for f in files)
            has_lib = any(_is_lib_file(f) or _is_db_file(f) for f in files)
            if has_ndm and root not in ndm_dirs:
                ndm_dirs.append(root)
            if has_lef and root not in lef_dirs:
                lef_dirs.append(root)
            if has_lib and root not in stdcell_dirs and root not in memory_dirs and root not in io_dirs:
                if target_category == 'memory':
                    memory_dirs.append(root)
                elif target_category == 'io':
                    io_dirs.append(root)
                elif target_category == 'stdcell':
                    stdcell_dirs.append(root)
                else:
                    # Auto-classify by directory name components
                    _dir_parts = root.lower().replace('\\', '/').split('/')
                    _basename = _dir_parts[-1] if _dir_parts else ''
                    if any(p in ('memory', 'mem') or p.startswith('mem_') for p in _dir_parts):
                        memory_dirs.append(root)
                    elif any(p in ('io', 'iolib') or p.startswith('io_') for p in _dir_parts):
                        io_dirs.append(root)
                    else:
                        stdcell_dirs.append(root)

    # 1. Scan lib_root (auto-classify)
    logger.info("Scanning lib_root: {}".format(lib_root))
    _scan_tree(lib_root)

    # 2. Additional stdcell paths (force stdcell category)
    if hasattr(args, 'stdcell_path') and args.stdcell_path:
        for sp in args.stdcell_path:
            sp = os.path.abspath(sp)
            logger.info("Scanning stdcell path: {}".format(sp))
            _scan_tree(sp, target_category='stdcell')

    # 3. Memory paths override auto-classification
    if hasattr(args, 'memory_path') and args.memory_path:
        memory_dirs = []  # reset auto-detected
        for mp in args.memory_path:
            mp = os.path.abspath(mp)
            logger.info("Scanning memory path: {}".format(mp))
            _scan_tree(mp, target_category='memory')

    # 4. IO paths override auto-classification
    if hasattr(args, 'io_path') and args.io_path:
        io_dirs = []  # reset auto-detected
        for ip in args.io_path:
            ip = os.path.abspath(ip)
            logger.info("Scanning IO path: {}".format(ip))
            _scan_tree(ip, target_category='io')

    # 5. IP/Analog paths (treat as stdcell for now — separate category TBD)
    if hasattr(args, 'ip_path') and args.ip_path:
        for ipp in args.ip_path:
            ipp = os.path.abspath(ipp)
            logger.info("Scanning IP path: {}".format(ipp))
            _scan_tree(ipp, target_category='stdcell')

    # ── Discovery ──────────────────────────────────────────────────────────
    # Data structures: {(track, vt): [path, ...]}
    ndm_libs = defaultdict(list)      # (track,vt) → [ndm paths]
    db_libs = defaultdict(list)       # (track,vt) → [db paths]
    lef_libs = defaultdict(list)      # (track,vt) → [lef paths]
    lib_nom_libs = defaultdict(list)  # (track,vt) → [lib_nom paths]
    timing_libs = defaultdict(list)   # (track,vt,corner) → [timing lib paths]
    power_libs = defaultdict(list)    # (track,vt,corner) → [power lib paths]

    # Shared libs
    ndm_memory = []
    ndm_io = []
    lef_memory = []
    lef_io = []
    lib_nom_memory = []
    lib_nom_io = []
    timing_memory = defaultdict(list)   # corner → [paths]
    timing_io = defaultdict(list)       # corner → [paths]

    discovered_tracks = set()
    discovered_vts = set()
    discovered_corners = set()

    excluded_count = 0

    # ── Scan NDMs ──
    for ndm_dir in ndm_dirs:
        if not os.path.isdir(ndm_dir):
            continue
        for f in sorted(os.listdir(ndm_dir)):
            if not _is_ndm_file(f):
                continue
            fpath = os.path.join(ndm_dir, f)
            if _is_excluded(fpath):
                excluded_count += 1; continue
            fl = f.lower()
            if 'memory' in fl or 'mem' in fl:
                ndm_memory.append(fpath)
                continue
            if '_io' in fl or 'io.' in fl:
                ndm_io.append(fpath)
                continue
            vt, _ = _extract_vt(f, vt_list)
            trk = _extract_track(f, tracks, _track_patterns)
            if not trk and vt:
                trk = tracks[0] if tracks else 'default'
            if vt and trk:
                ndm_libs[(trk, vt)].append(fpath)
                discovered_tracks.add(trk)
                discovered_vts.add(vt)

    # ── Scan LEFs ──
    for lef_dir in lef_dirs:
        if not os.path.isdir(lef_dir):
            continue
        for f in sorted(os.listdir(lef_dir)):
            if not _is_lef_file(f):
                continue
            fpath = os.path.join(lef_dir, f)
            if _is_excluded(fpath):
                excluded_count += 1; continue
            fl = f.lower()
            if 'tech' in fl:
                continue
            if 'memory' in fl or 'mem' in fl:
                lef_memory.append(fpath)
                continue
            if '_io' in fl or 'io.' in fl:
                lef_io.append(fpath)
                continue
            vt, _ = _extract_vt(f, vt_list)
            trk = _extract_track(f, tracks, _track_patterns)
            if not trk and vt:
                trk = tracks[0] if tracks else 'default'
            if vt and trk:
                lef_libs[(trk, vt)].append(fpath)

    # ── Scan stdcell timing/DB ──
    for stdcell_dir in stdcell_dirs:
        if not os.path.isdir(stdcell_dir):
            continue
        for f in sorted(os.listdir(stdcell_dir)):
            fpath = os.path.join(stdcell_dir, f)
            if _is_excluded(fpath):
                excluded_count += 1; continue
            vt, _ = _extract_vt(f, vt_list)
            trk = _extract_track(f, tracks, _track_patterns)
            base_for_corner, _ = _strip_lib_extension(f)
            corner = _extract_corner(base_for_corner)
            # Use default track when filename has no track identifier
            if not trk and vt:
                trk = tracks[0] if tracks else 'default'

            if vt and trk:
                discovered_tracks.add(trk)
                discovered_vts.add(vt)

            if _is_db_file(f):
                if vt and trk:
                    db_libs[(trk, vt)].append(fpath)
            elif _is_lib_file(f):
                # Determine lib type from extension/path
                base_name, lib_type = _strip_lib_extension(f)
                path_lib_type = _detect_lib_type_from_path(fpath)
                is_timing = lib_type in ('ccs', 'ccs_tn', 'nldm', 'lib') and path_lib_type == 'timing'
                is_power = lib_type == 'ccs_p' or path_lib_type == 'power'

                # Parse corner from base name (stripped of extension)
                corner = _extract_corner(base_name)

                if vt and trk and corner and is_timing:
                    timing_libs[(trk, vt, corner)].append(fpath)
                    discovered_corners.add(corner)
                elif vt and trk and corner and is_power:
                    power_libs[(trk, vt, corner)].append(fpath)
                elif vt and trk and not corner:
                    lib_nom_libs[(trk, vt)].append(fpath)

    # ── Scan memory timing libs ──
    for memory_dir in memory_dirs:
        if not os.path.isdir(memory_dir):
            continue
        for f in sorted(os.listdir(memory_dir)):
            if not _is_lib_file(f):
                continue
            fpath = os.path.join(memory_dir, f)
            if _is_excluded(fpath):
                excluded_count += 1; continue
            base_name, _ = _strip_lib_extension(f)
            corner = _extract_corner(base_name)
            if corner:
                timing_memory[corner].append(fpath)
            else:
                lib_nom_memory.append(fpath)

    # ── Scan IO timing libs ──
    for io_dir in io_dirs:
        if not os.path.isdir(io_dir):
            continue
        for f in sorted(os.listdir(io_dir)):
            if not _is_lib_file(f):
                continue
            fpath = os.path.join(io_dir, f)
            if _is_excluded(fpath):
                excluded_count += 1; continue
            base_name, _ = _strip_lib_extension(f)
            corner = _extract_corner(base_name)
            if corner:
                timing_io[corner].append(fpath)
            else:
                lib_nom_io.append(fpath)

    # ── Sort discovered sets ──
    def _track_sort_key(t):
        try:
            return float(t.replace('T', '').replace('P', '.'))
        except ValueError:
            return 0.0
    all_tracks = sorted(discovered_tracks, key=_track_sort_key)
    if tracks:
        all_tracks = [t for t in tracks if t in discovered_tracks]
    all_vts = [v for v in vt_list if v in discovered_vts]
    all_corners = sorted(discovered_corners)

    if not all_tracks:
        logger.error("No tracks discovered. Check --lib-root directory structure.")
        return 1

    # ── Verify: read .lib headers and cross-check PVT against filenames ──
    pvt_mismatches = []
    pvt_verified = 0
    pvt_skipped = 0
    # Collect all .lib paths from timing_libs + timing_memory + timing_io
    all_lib_paths = []
    for paths in timing_libs.values():
        all_lib_paths.extend(paths)
    for paths in timing_memory.values():
        all_lib_paths.extend(paths)
    for paths in timing_io.values():
        all_lib_paths.extend(paths)

    for libpath in all_lib_paths:
        if not os.path.isfile(libpath) or os.path.getsize(libpath) == 0:
            pvt_skipped += 1
            continue
        fname = os.path.basename(libpath)
        # Extract PVT from filename
        fn_corner = _extract_corner(fname)
        if not fn_corner:
            pvt_skipped += 1
            continue
        # Parse: corner format is "ss_0p76v_150c"
        parts = fn_corner.split('_')
        if len(parts) != 3:
            pvt_skipped += 1
            continue
        fn_voltage = float(parts[1].rstrip('v').replace('p', '.'))
        t_str = parts[2].rstrip('c')
        fn_temp = -int(t_str[1:]) if t_str.startswith('m') else int(t_str)

        # Read .lib header
        char = LibertyParser.parse_file(libpath)
        if char.nom_voltage == 0 and char.oc_voltage == 0:
            pvt_skipped += 1
            continue

        pvt_verified += 1
        mismatch_details = []
        lib_v = char.nom_voltage if char.nom_voltage > 0 else char.oc_voltage
        lib_t = int(char.nom_temperature) if char.nom_temperature != 0 else int(char.oc_temperature)

        if lib_v > 0 and abs(lib_v - fn_voltage) > 0.01:
            mismatch_details.append("voltage: file={:.3f}V header={:.3f}V".format(fn_voltage, lib_v))
        if lib_t != 0 and lib_t != fn_temp:
            mismatch_details.append("temp: file={}C header={}C".format(fn_temp, lib_t))

        if mismatch_details:
            pvt_mismatches.append((fname, mismatch_details))

    # ── Generate output ────────────────────────────────────────────────────
    from datetime import datetime
    lines = []
    w = lines.append

    w("#!/usr/bin/env tclsh")
    w("# " + "=" * 77)
    w("# AUTO-GENERATED by: cbflow flow library-manager generate")
    w("# Tech: {} | Generated: {}".format(tech_name, datetime.now().strftime("%Y-%m-%d %H:%M")))
    w("# Source: {}".format(lib_root))
    w("# Tracks: {} | VTs: {}".format(" ".join(all_tracks), " ".join(all_vts)))
    w("# Corners: {}".format(len(all_corners)))
    w("# DO NOT EDIT — regenerate with: cbflow flow library-manager generate")
    w("# " + "=" * 77)
    w("")

    # ── NDM per track per VT ──
    w("# ── NDM per track per VT ──")
    for trk in all_tracks:
        for vt in all_vts:
            paths = ndm_libs.get((trk, vt), [])
            if paths:
                w('set tech({},{},ndm) [list {}]'.format(
                    trk, vt, " ".join('"{}"'.format(p) for p in paths)))
    w("")

    # ── NDM shared ──
    w("# ── NDM shared ──")
    w('set tech(ndm,memory) [list {}]'.format(
        " ".join('"{}"'.format(p) for p in ndm_memory) if ndm_memory else ""))
    w('set tech(ndm,io) [list {}]'.format(
        " ".join('"{}"'.format(p) for p in ndm_io) if ndm_io else ""))
    w('set tech(ndm,analog) [list]')
    w("")

    # ── NDM combined per track (all VTs + shared) ──
    w("# ── NDM combined per track ──")
    for trk in all_tracks:
        combined = []
        for vt in all_vts:
            combined.extend(ndm_libs.get((trk, vt), []))
        combined.extend(ndm_memory)
        combined.extend(ndm_io)
        w('set tech({},ndm) [list {}]'.format(
            trk, " ".join('"{}"'.format(p) for p in combined)))
    w("")

    # ── DB per track per VT ──
    w("# ── DB per track per VT ──")
    for trk in all_tracks:
        for vt in all_vts:
            paths = db_libs.get((trk, vt), [])
            if paths:
                w('set tech({},{},db) [list {}]'.format(
                    trk, vt, " ".join('"{}"'.format(p) for p in paths)))
    w("")

    # ── DB shared ──
    db_mem = []
    db_io = []
    # DB memory/io: scan for .db files in memory/io dirs
    for dirs, lst in [(memory_dirs, db_mem), (io_dirs, db_io)]:
        for d in dirs:
            if os.path.isdir(d):
                for f in sorted(os.listdir(d)):
                    if _is_db_file(f):
                        lst.append(os.path.join(d, f))
    w("# ── DB shared ──")
    w('set tech(db,memory) [list {}]'.format(
        " ".join('"{}"'.format(p) for p in db_mem) if db_mem else ""))
    w('set tech(db,io) [list {}]'.format(
        " ".join('"{}"'.format(p) for p in db_io) if db_io else ""))
    w("")

    # ── DB combined per track ──
    w("# ── DB combined per track ──")
    for trk in all_tracks:
        combined = []
        for vt in all_vts:
            combined.extend(db_libs.get((trk, vt), []))
        combined.extend(db_mem)
        combined.extend(db_io)
        w('set tech({},db) [list {}]'.format(
            trk, " ".join('"{}"'.format(p) for p in combined)))
    w("")

    # ── lib_nom per track per VT ──
    w("# ── lib_nom per track per VT ──")
    for trk in all_tracks:
        for vt in all_vts:
            paths = lib_nom_libs.get((trk, vt), [])
            if paths:
                w('set tech({},{},lib_nom) [list {}]'.format(
                    trk, vt, " ".join('"{}"'.format(p) for p in paths)))
    w("")

    # ── lib_nom shared ──
    w("# ── lib_nom shared ──")
    w('set tech(lib_nom,memory) [list {}]'.format(
        " ".join('"{}"'.format(p) for p in lib_nom_memory) if lib_nom_memory else ""))
    w('set tech(lib_nom,io) [list {}]'.format(
        " ".join('"{}"'.format(p) for p in lib_nom_io) if lib_nom_io else ""))
    w("")

    # ── lib_nom combined per track ──
    # lib_nom = nominal corner (first TT corner found). If no explicit lib_nom,
    # use the TT nominal timing libs as lib_nom (standard practice)
    tt_corners = [c for c in all_corners if c.startswith('tt')]
    # Prefer room temperature (25c) as nominal
    nom_corner = None
    for c in tt_corners:
        if '25c' in c:
            nom_corner = c
            break
    if not nom_corner and tt_corners:
        nom_corner = tt_corners[0]
    w("# ── lib_nom combined per track (from TT nominal: {}) ──".format(nom_corner or "none"))
    for trk in all_tracks:
        combined = []
        for vt in all_vts:
            explicit = lib_nom_libs.get((trk, vt), [])
            if explicit:
                combined.extend(explicit)
            elif nom_corner:
                combined.extend(timing_libs.get((trk, vt, nom_corner), []))
        if not combined:
            combined.extend(lib_nom_memory)
            combined.extend(lib_nom_io)
        else:
            mem_nom = lib_nom_memory if lib_nom_memory else timing_memory.get(nom_corner, [])
            io_nom = lib_nom_io if lib_nom_io else timing_io.get(nom_corner, [])
            combined.extend(mem_nom)
            combined.extend(io_nom)
        w('set tech({},lib_nom) [list {}]'.format(
            trk, " ".join('"{}"'.format(p) for p in combined)))
    w("")

    # ── LEF per track per VT ──
    w("# ── LEF per track per VT ──")
    for trk in all_tracks:
        for vt in all_vts:
            paths = lef_libs.get((trk, vt), [])
            if paths:
                w('set tech({},{},lef) [list {}]'.format(
                    trk, vt, " ".join('"{}"'.format(p) for p in paths)))
    w("")

    # ── LEF shared ──
    w("# ── LEF shared ──")
    w('set tech(lef,memory) [list {}]'.format(
        " ".join('"{}"'.format(p) for p in lef_memory) if lef_memory else ""))
    w('set tech(lef,io) [list {}]'.format(
        " ".join('"{}"'.format(p) for p in lef_io) if lef_io else ""))
    w("")

    # ── LEF combined per track ──
    w("# ── LEF combined per track ──")
    for trk in all_tracks:
        combined = []
        for vt in all_vts:
            combined.extend(lef_libs.get((trk, vt), []))
        combined.extend(lef_memory)
        combined.extend(lef_io)
        w('set tech({},lef) [list {}]'.format(
            trk, " ".join('"{}"'.format(p) for p in combined)))
    w("")

    # ── Corners discovered ──
    w("# ── Corners discovered ──")
    w('set tech(corners) {{{}}}'.format(" ".join(all_corners)))
    w("")

    # ── Timing libs per track per VT per corner ──
    w("# ── Timing libs per track per VT per corner ──")
    for trk in all_tracks:
        for corner in all_corners:
            for vt in all_vts:
                paths = timing_libs.get((trk, vt, corner), [])
                if paths:
                    w('set tech({},{},lib,{},timing) [list {}]'.format(
                        trk, vt, corner, " ".join('"{}"'.format(p) for p in paths)))
    w("")

    # ── Timing libs shared per corner ──
    w("# ── Timing libs shared per corner (memory + IO) ──")
    for corner in all_corners:
        mem_paths = timing_memory.get(corner, [])
        io_paths = timing_io.get(corner, [])
        w('set tech(lib,{},timing,memory) [list {}]'.format(
            corner, " ".join('"{}"'.format(p) for p in mem_paths) if mem_paths else ""))
        w('set tech(lib,{},timing,io) [list {}]'.format(
            corner, " ".join('"{}"'.format(p) for p in io_paths) if io_paths else ""))
    w("")

    # ── Timing combined per track per corner (all VTs + shared) ──
    w("# ── Timing combined per track per corner ──")
    for trk in all_tracks:
        for corner in all_corners:
            combined = []
            for vt in all_vts:
                combined.extend(timing_libs.get((trk, vt, corner), []))
            combined.extend(timing_memory.get(corner, []))
            combined.extend(timing_io.get(corner, []))
            if combined:
                w('set tech({},lib,{},timing) [list {}]'.format(
                    trk, corner, " ".join('"{}"'.format(p) for p in combined)))
    w("")

    # ── Write output ──
    output_text = "\n".join(lines) + "\n"

    output_path = args.output
    tag = args.tag if hasattr(args, 'tag') and args.tag else None
    if not tag and not output_path:
        logger.error("--tag is required (e.g., --tag P0, --tag timing_v1)")
        logger.error("This sets the lib_config name: lib_config_<tag>.tcl")
        return 1
    if not output_path:
        core_dir = get_cbflow_core_dir()
        fname = "lib_config_{}.tcl".format(tag)
        output_path = os.path.join(core_dir, "config", "tech", tech_name, version, fname)

    # ── Incremental: merge with existing lib_config ──
    incremental = hasattr(args, 'incremental') and args.incremental
    if incremental and os.path.exists(output_path):
        # Read existing entries, keep anything not overwritten by new scan
        existing_keys = set()
        new_keys = set()
        for line in lines:
            m = re.match(r'set tech\(([^)]+)\)', line)
            if m:
                new_keys.add(m.group(1))

        existing_lines = []
        with open(output_path, 'r') as ef:
            for eline in ef:
                m = re.match(r'set tech\(([^)]+)\)', eline.strip())
                if m:
                    key = m.group(1)
                    if key not in new_keys:
                        existing_lines.append(eline.rstrip())
                        existing_keys.add(key)

        if existing_lines:
            lines.append("")
            lines.append("# ── Retained from previous lib_config (incremental merge) ──")
            lines.extend(existing_lines)
            output_text = "\n".join(lines) + "\n"
            logger.info("Incremental: retained {} existing entries, added {} new".format(
                len(existing_keys), len(new_keys)))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w') as fh:
        fh.write(output_text)

    # ── Discovery report ──
    total_stdcell_timing = len(timing_libs)
    missing_memory = []
    missing_io = []
    for corner in all_corners:
        if corner not in timing_memory:
            missing_memory.append(corner)
        if corner not in timing_io:
            missing_io.append(corner)

    print("")
    print("=" * 60)
    print("  Library Discovery Report — {}".format(tech_name))
    print("=" * 60)
    if excluded_count > 0:
        print("  Excluded:  {} files (patterns: {})".format(excluded_count, ", ".join(exclude_patterns)))
    print("  Tracks:    {}".format(" ".join(all_tracks)))
    print("  VTs:       {}".format(" ".join(all_vts)))
    print("  Corners:   {}".format(len(all_corners)))
    print("  NDM:       {} stdcell + {} memory + {} io".format(
        len(ndm_libs), len(ndm_memory), len(ndm_io)))
    print("  DB:        {} stdcell".format(len(db_libs)))
    print("  LEF:       {} stdcell + {} memory + {} io".format(
        len(lef_libs), len(lef_memory), len(lef_io)))
    print("  lib_nom:   {} stdcell".format(len(lib_nom_libs)))
    print("  Timing:    {} stdcell sets".format(total_stdcell_timing))
    print("")
    mem_ok = len(all_corners) - len(missing_memory)
    io_ok = len(all_corners) - len(missing_io)
    sym_mem = "ok" if not missing_memory else "MISSING"
    sym_io = "ok" if not missing_io else "MISSING"
    print("  Memory corners: {}/{} {}".format(mem_ok, len(all_corners), sym_mem))
    if missing_memory:
        for c in missing_memory:
            print("    MISSING: memory corner {}".format(c))
    print("  IO corners:     {}/{} {}".format(io_ok, len(all_corners), sym_io))
    if missing_io:
        for c in missing_io:
            print("    MISSING: io corner {}".format(c))
    print("")
    # PVT verification results
    print("  PVT Verification (filename vs .lib header):")
    if pvt_verified == 0 and pvt_skipped > 0:
        print("    Skipped: {} (empty/mock files)".format(pvt_skipped))
    else:
        print("    Verified: {}  Skipped: {}".format(pvt_verified, pvt_skipped))
        if pvt_mismatches:
            print("    MISMATCHES: {}".format(len(pvt_mismatches)))
            for fname, details in pvt_mismatches:
                print("      {} — {}".format(fname, "; ".join(details)))
        else:
            print("    All verified libs match — PVT consistent")
    print("")
    print("  Output: {}".format(output_path))
    print("=" * 60)
    print("")

    return 0


def cmd_coverage(args: argparse.Namespace) -> int:
    """Show library coverage matrix: tracks × VTs × corners."""
    # Read lib_config.tcl and parse tech() variables
    tech_name = args.tech
    version = args.version or "v1.0.0"
    core_dir = get_cbflow_core_dir()

    lib_config = os.path.join(core_dir, "config", "tech", tech_name, version, "lib_config.tcl")
    if not os.path.exists(lib_config):
        logger.error("lib_config.tcl not found: {}".format(lib_config))
        logger.info("  Run: cbflow flow library-manager generate --tech {} first".format(tech_name))
        return 1

    # Parse the file for tech() keys
    with open(lib_config, 'r') as f:
        content = f.read()

    # Extract timing keys: tech(<track>,<vt>,lib,<corner>,timing)
    timing_re = re.compile(r'set tech\((\S+?),(\S+?),lib,(\S+?),timing\)')
    coverage = defaultdict(set)  # (track, corner) → set of VTs
    for m in timing_re.finditer(content):
        trk, vt, corner = m.group(1), m.group(2), m.group(3)
        coverage[(trk, corner)].add(vt)

    # Extract tracks and corners
    tracks_m = re.search(r'Tracks:\s*(.+?)(?:\||$)', content)
    corners_m = re.search(r'set tech\(corners\)\s*\{(.+?)\}', content)

    tracks = tracks_m.group(1).strip().split() if tracks_m else sorted(set(k[0] for k in coverage))
    corners = corners_m.group(1).strip().split() if corners_m else sorted(set(k[1] for k in coverage))

    # All VTs found
    all_vts = sorted(set(v for vts in coverage.values() for v in vts),
                     key=lambda x: _VT_KEYWORDS.index(x) if x in _VT_KEYWORDS else 99)

    print("")
    print("=" * 70)
    print("  Library Coverage Matrix — {}".format(tech_name))
    print("=" * 70)

    # Header
    hdr = "  {:>20s}".format("Corner")
    for trk in tracks:
        hdr += "  {:>10s}".format(trk)
    print(hdr)
    print("  " + "-" * (22 + 12 * len(tracks)))

    for corner in corners:
        row = "  {:>20s}".format(corner)
        for trk in tracks:
            vts = coverage.get((trk, corner), set())
            if len(vts) == len(all_vts):
                row += "  {:>10s}".format("ALL")
            elif vts:
                row += "  {:>10s}".format(",".join(sorted(vts)))
            else:
                row += "  {:>10s}".format("---")
        print(row)

    print("")
    print("  VTs: {}".format(", ".join(all_vts)))
    print("  Total corners: {}  |  Tracks: {}".format(len(corners), len(tracks)))
    print("=" * 70)
    print("")
    return 0


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
  cbflow flow library-manager generate --lib-root /libs/gf_22nm --tech gf_22nm
  cbflow flow library-manager generate --tech gf_28nm --stdcell-path /libs/eco --tag P0
  cbflow flow library-manager generate --tech gf_22nm --exclude "*ulvt*" --tag svt_only
  cbflow flow library-manager coverage --tech gf_22nm
  cbflow flow library-manager check --verbose
  cbflow flow library-manager list --corner ss --voltage 0.80
  cbflow flow library-manager scan --path /libs/gf22 --recursive
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Library manager commands')

    # scan command
    scan_parser = subparsers.add_parser('scan', help='Scan directory for .lib files')
    scan_parser.add_argument('--path', default=None,
                             help='Directory to scan for .lib files')
    scan_parser.add_argument('--recursive', action='store_true', default=False,
                             help='Scan subdirectories recursively')
    scan_parser.add_argument('--format', choices=['text', 'json'], default='text',
                             help='Output format (default: text)')

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
    verify_parser.add_argument('--path', default=None,
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
    mmmc_parser.add_argument('--path', default=None,
                             help='Directory to scan for .lib files')
    mmmc_parser.add_argument('--output', default=None,
                             help='Output file path (default: stdout)')

    # generate command — auto-discover and write lib_config.tcl
    gen_parser = subparsers.add_parser(
        'generate', help='Generate lib_config.tcl from library directories')
    gen_parser.add_argument('--lib-root', default=None,
                            help='Library root directory. Auto-read from tech(lib_root) in tech_config if omitted')
    gen_parser.add_argument('--tech', default=None,
                            help='Technology name (e.g., gf_22nm). Default: dirname of lib-root')
    gen_parser.add_argument('--version', default='v1.0.0',
                            help='Config version (default: v1.0.0)')
    gen_parser.add_argument('--tracks', default=None,
                            help='Space-separated track list (e.g., "9T 7.5T 8T"). Auto-detected if omitted')
    gen_parser.add_argument('--vts', default=None,
                            help='Space-separated VT list (e.g., "svt lvt hvt"). Default: svt lvt ulvt hvt')
    gen_parser.add_argument('--stdcell-path', nargs='+', default=None,
                            help='Additional stdcell lib roots (can be lib_root structure or flat dirs)')
    gen_parser.add_argument('--memory-path', nargs='+', default=None,
                            help='Override memory lib directories (multiple allowed)')
    gen_parser.add_argument('--io-path', nargs='+', default=None,
                            help='Override IO lib directories (multiple allowed)')
    gen_parser.add_argument('--ip-path', nargs='+', default=None,
                            help='IP/Analog lib directories (multiple allowed)')
    gen_parser.add_argument('--exclude', nargs='+', default=[],
                            help='Glob patterns to exclude (e.g., "*channel*" "*dummy*" "*eco*")')
    gen_parser.add_argument('--tag', default=None,
                            help='Named tag for lib_config (e.g., P0, timing_closure). Output: lib_config_<tag>.tcl')
    gen_parser.add_argument('--incremental', action='store_true', default=False,
                            help='Merge new libs into existing lib_config (keep entries not in current scan)')
    gen_parser.add_argument('--output', default=None,
                            help='Output file path (default: config/tech/<tech>/<version>/lib_config[_<tag>].tcl)')

    # coverage command — show track × VT × corner matrix
    cov_parser = subparsers.add_parser(
        'coverage', help='Show library coverage matrix')
    cov_parser.add_argument('--tech', required=True,
                            help='Technology name (e.g., gf_22nm)')
    cov_parser.add_argument('--version', default='v1.0.0',
                            help='Config version (default: v1.0.0)')

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
        'check': cmd_check,
        'list': cmd_list,
        'verify': cmd_verify,
        'generate-mmmc': cmd_generate_mmmc,
        'generate': cmd_generate,
        'coverage': cmd_coverage,
    }

    if args.command not in commands:
        logger.error(f"Unknown command: {args.command}")
        logger.info(f"Available commands: {', '.join(commands.keys())}")
        return 1

    # Auto-resolve --path from tech_config if not provided
    if hasattr(args, 'path') and args.path is None and args.command in ('scan', 'verify', 'generate-mmmc'):
        tech_name = args.tech_node if hasattr(args, 'tech_node') and args.tech_node else None
        resolved = _resolve_lib_root_from_tech_config(tech_name)
        if resolved:
            args.path = resolved
            logger.info("Using lib_root from tech_config: {}".format(resolved))
        else:
            logger.error("--path not provided and tech(lib_root) not found in tech_config")
            logger.info("  Provide --path <lib_directory> or ensure tech_config has tech(lib_root)")
            return 1

    # Validate path arguments before dispatching
    if hasattr(args, 'path') and args.path is not None:
        if not _validate_path_arg(args, 'path'):
            return 1

    if hasattr(args, 'lib_root') and args.lib_root is not None:
        if not _validate_path_arg(args, 'lib_root'):
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
