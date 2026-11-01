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
from datetime import datetime  # for tag-dir README / MANIFEST timestamps

# Post cbflow_global utils-refactor: shared Python packages (core.paths,
# core.interactive, logging_config, cbflow_config, …) live under
# global/utils/, not PD/utils/. Add BOTH locations to sys.path so this
# PD-only command still resolves them without env setup.
import sys as _bootstrap_sys
_this = os.path.dirname(os.path.abspath(__file__))                 # PD/utils/commands
_pd_utils = os.path.dirname(_this)                                 # PD/utils
_umbrella = os.path.dirname(os.path.dirname(_pd_utils))            # <root>
_global_utils = os.path.join(_umbrella, 'global', 'utils')         # <root>/global/utils
_global_cmds = os.path.join(_global_utils, 'commands')             # for logging_config
if os.path.isdir(_global_cmds) and _global_cmds not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_cmds)
if os.path.isdir(_global_utils) and _global_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_utils)
if _pd_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _pd_utils)

# Configure unified logging
from logging_config import configure_logging, get_logger
from core.paths import get_cbflow_core_dir, get_flow_config_version, require_tech_config, preflight_tech_config_or_exit, atomic_write
from core.interactive import run_repl

logger = configure_logging('cbflow.library_manager')



def _resolve_lib_root_from_tech_config(tech_name=None) -> str:
    """Read tech(lib_root) from tech_config.tcl. Returns path or empty string.
    Tech lives in global/config/tech/ (single file per tech since 2026-10-11)."""
    from core.paths import get_cbflow_global_dir
    gdir = get_cbflow_global_dir()
    if not gdir:
        return ''
    version = get_flow_config_version()
    tech_base = os.path.join(gdir, 'config', 'tech')
    # Try specific tech first.
    if tech_name:
        tc = os.path.join(tech_base, tech_name, version, 'tech_config.tcl')
        if os.path.exists(tc):
            with open(tc, 'r') as f:
                m = re.search(r'set\s+tech\(lib_root\)\s+"([^"]+)"', f.read())
                if m:
                    return m.group(1)
    # Fall back to any tech that declares lib_root.
    if os.path.isdir(tech_base):
        for t in sorted(os.listdir(tech_base)):
            tc = os.path.join(tech_base, t, version, 'tech_config.tcl')
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

# Process-corner allowlist. Default set stays compact; techs that need
# more corners (e.g. GF 22FDX `fff`) declare them via
# tech(process_corners) in tech_config.tcl (space-separated TCL list).
# _CORNERS_ENV is the module-level mutable override installed by
# _apply_tech_corners() at CLI entry time once the tech has been
# resolved — all three regexes rebuild from this list.
_DEFAULT_PROCESS_CORNERS = ['ss', 'tt', 'ff', 'sf', 'fs']
_CORNERS_ENV = list(_DEFAULT_PROCESS_CORNERS)


def _corner_alternation(corners=None):
    """Return a regex alternation like 'ss|tt|ff|fff' sorted long-first
    so `fff` matches before `ff` and prevents the embedded-substring
    miscategorization bug.
    """
    cs = list(corners if corners is not None else _CORNERS_ENV)
    cs.sort(key=lambda s: (-len(s), s))
    return '|'.join(re.escape(c) for c in cs)


def _build_lib_patterns():
    """Rebuild LIB_PATTERN / ALT_LIB_PATTERN / _CORNER_RE from _CORNERS_ENV.

    Called whenever _apply_tech_corners() installs a new corner set.
    """
    global LIB_PATTERN, ALT_LIB_PATTERN, _CORNER_RE
    alt = _corner_alternation()
    LIB_PATTERN = re.compile(
        r'^(?P<prefix>.+?)(?P<corner>' + alt + r')'
        r'(?P<voltage>\d+p\d+v)(?P<temp>m?\d+c)'
        r'_(?P<type>ccs|power|noise|leakage|nldm)\.lib$'
    )
    ALT_LIB_PATTERN = re.compile(
        r'^(?P<prefix>.+?)_(?P<corner>' + alt + r')'
        r'(?P<voltage>\d+p\d+v)(?P<temp>m?\d+c)'
        r'_(?P<type>ccs|power|noise|leakage|nldm)\.lib$'
    )
    _CORNER_RE = re.compile(
        r'(' + alt + r')'                       # process corner
        r'(?:_[a-z]+)*?'                        # optional condition words
        r'_?(\d+p\d+v)'                         # voltage
        r'_?(m?\d+c)',                          # temperature
        re.IGNORECASE
    )


def _apply_tech_corners(tech_config_path):
    """Read tech(process_corners) from tech_config.tcl and swap the regex set.

    Techs declare their process corners via:
        set tech(process_corners) "ss tt ff fff sf fs"
    Omitted → fallback to the default 5-corner set. Longest-first
    sorting (in _corner_alternation) prevents a 3-letter corner like
    `fff` from being miscategorized as the embedded `ff` substring.
    """
    global _CORNERS_ENV
    # Reset to defaults FIRST so a REPL `tech <name>` switch to a tech
    # that omits process_corners does NOT inherit the previous tech's
    # custom corner set — otherwise libs for the new tech are scanned
    # with the stale fff-aware regex. Overlay the tech-specific set
    # only after the match succeeds.
    _CORNERS_ENV = list(_DEFAULT_PROCESS_CORNERS)
    _build_lib_patterns()
    if not tech_config_path:
        return
    try:
        with open(tech_config_path, 'r', encoding='utf-8', errors='replace') as fh:
            src = fh.read()
    except OSError:
        return
    m = re.search(
        r'^\s*set\s+tech\(process_corners\)\s+(?:\{([^}]+)\}|"([^"]+)")',
        src, re.MULTILINE)
    if not m:
        return
    raw = (m.group(1) or m.group(2) or '').strip()
    corners = [c for c in raw.split() if c]
    if corners:
        _CORNERS_ENV = corners
        _build_lib_patterns()


# Primary pattern: prefix immediately before corner (no underscore separator)
LIB_PATTERN = re.compile(
    r'^(?P<prefix>.+?)(?P<corner>' + _corner_alternation(_DEFAULT_PROCESS_CORNERS) + r')'
    r'(?P<voltage>\d+p\d+v)(?P<temp>m?\d+c)'
    r'_(?P<type>ccs|power|noise|leakage|nldm)\.lib$'
)

# Alternate pattern: IO-style with underscore before corner
ALT_LIB_PATTERN = re.compile(
    r'^(?P<prefix>.+?)_(?P<corner>' + _corner_alternation(_DEFAULT_PROCESS_CORNERS) + r')'
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

        Tries three schemas in order:
          1. Legacy `array set library_sets { ... }` in the tech_config.tcl
             itself (older config style).
          2. Per-key `set tech(<corner>,<voltage>,<temp>,db|lib) [list ...]`
             and `set tech(<track>,<vt>,ndm) [list ...]` in the sibling
             `lib_config.tcl` (current style — written by `library-manager
             generate`, kept track-categorized).
          3. Track-schema declarations DIRECTLY in tech_config.tcl —
             `tech(<metal_stack>,<track>,lef_tech)` for LEF-tech files,
             `tech(rcx,<metal_stack>,<rc_corner>,<format>)` for extraction
             files. This is the shipped `gf_22nm` / `gf_28nm` / `tsmc_5nm`
             / `tsmc_7nm` layout — none of them declare `.lib`/`.ndm` file
             paths in the tech config; those come from
             `library-manager generate` writing a `lib_config.tcl` sibling.
             Falling through to this parser means `list`/`check` don't
             error out on shipped tech configs — they instead show what
             IS declared (LEF, RCX) and note the .lib/.ndm gap explicitly.
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

        # Fall back to the track-schema (shipped tech configs). This
        # never finds .lib/.ndm — those need library-manager generate —
        # but it does surface LEF-tech and RCX declarations so the tool
        # is useful against out-of-the-box configs instead of erroring.
        track_sets = self._parse_tech_track_schema(content, path)
        if track_sets:
            logger.info(
                f"No library_sets array and no sibling lib_config.tcl; "
                f"using track-schema from {os.path.basename(path)} "
                f"(LEF/RCX only — run `library-manager generate` to add "
                f".lib/.ndm)"
            )
            return track_sets

        return sets

    def _parse_tech_track_schema(self, content: str, tech_config_path: str) -> Dict:
        """Synthesize library_sets from track-schema declarations that
        appear directly in tech_config.tcl (no library_sets array, no
        sibling lib_config.tcl).

        Recognized lines:
          set tech(<ms>,<track>,lef_tech)             "<path>"
          set tech(rcx,<ms>,<rc_corner>,<format>)     "<path>"
              where <format> ∈ {tluplus, nxtgrd, qrc}
          set tech(<track>,ndm|db|lib)                 "<path>"  (legacy shape)
          set tech(<track>,<vt>,ndm|db|lib)            "<path>"  (per-VT shape)

        `$project(...)` substitution is left literal — we return the
        template path so the operator sees exactly what's declared and
        can spot missing library-root vars themselves. Real resolution
        happens later when tclsh sources the file.
        """
        sets: Dict[str, Dict] = {}

        # LEF-tech per (metal_stack, track).
        lef_re = re.compile(
            r'^\s*set\s+tech\(\s*([0-9]+M)\s*,\s*([0-9.]+T)\s*,\s*lef_tech\s*\)\s+"([^"]+)"',
            re.MULTILINE
        )
        for m in lef_re.finditer(content):
            ms, trk, path = m.group(1), m.group(2), m.group(3)
            set_name = f'lef_{ms}_{trk}'
            entry = sets.setdefault(set_name, {
                'corner': 'physical', 'voltage': '-', 'temperature': '-',
                'metal_stack': ms, 'track': trk,
            })
            entry.setdefault('lef_files', []).append(path)

        # RCX per (metal_stack, rc_corner, format).
        rcx_re = re.compile(
            r'^\s*set\s+tech\(\s*rcx\s*,\s*([0-9]+M)\s*,\s*(rc_\w+)\s*,\s*(tluplus|nxtgrd|qrc)\s*\)'
            r'\s+"([^"]+)"',
            re.MULTILINE
        )
        for m in rcx_re.finditer(content):
            ms, rc, fmt, path = m.group(1), m.group(2), m.group(3), m.group(4)
            set_name = f'rcx_{ms}_{rc}'
            entry = sets.setdefault(set_name, {
                'corner': rc, 'voltage': '-', 'temperature': '-',
                'metal_stack': ms, 'rc_corner': rc,
            })
            entry.setdefault(f'{fmt}_files', []).append(path)

        # Per-track NDM/DB/LIB (legacy shape without VT).
        track_only_re = re.compile(
            r'^\s*set\s+tech\(\s*([0-9.]+T)\s*,\s*(ndm|db|lib)\s*\)\s+"([^"]+)"',
            re.MULTILINE
        )
        for m in track_only_re.finditer(content):
            trk, kind, path = m.group(1), m.group(2), m.group(3)
            set_name = f'physical_{trk}'
            entry = sets.setdefault(set_name, {
                'corner': 'physical', 'voltage': '-', 'temperature': '-',
                'track': trk,
            })
            lib_key = 'ndm_libraries' if kind == 'ndm' else 'timing_libraries'
            entry.setdefault(lib_key, []).append(path)

        # Per-track per-VT NDM/DB/LIB.
        #
        # ALLOWLIST approach: only names the tech explicitly declared
        # in `tech(vt_variants_available)` are accepted as VT flavors.
        # If a tech omits the declaration, fall back to the standard
        # foundry VT names (`rvt svt lvt ulvt elvt slvt hvt`) rather
        # than silently accepting any `\w+`.
        _declared_vts_m = re.search(
            r'set\s+tech\(vt_variants_available\)\s+(?:\{([^}]+)\}|"([^"]+)")',
            content
        )
        if _declared_vts_m:
            _allowed_vts = set(
                (_declared_vts_m.group(1) or _declared_vts_m.group(2) or '').split()
            )
        else:
            _allowed_vts = set(_VT_KEYWORDS)   # module-level fallback
        track_vt_re = re.compile(
            r'^\s*set\s+tech\(\s*([0-9.]+T)\s*,\s*(\w+)\s*,\s*(ndm|db|lib)\s*\)\s+"([^"]+)"',
            re.MULTILINE
        )
        for m in track_vt_re.finditer(content):
            trk, vt, kind = m.group(1), m.group(2), m.group(3)
            if vt not in _allowed_vts:
                continue
            path = m.group(4)
            set_name = f'physical_{trk}_{vt}'
            entry = sets.setdefault(set_name, {
                'corner': 'physical', 'voltage': '-', 'temperature': '-',
                'track': trk, 'vt': vt,
            })
            lib_key = 'ndm_libraries' if kind == 'ndm' else 'timing_libraries'
            entry.setdefault(lib_key, []).append(path)

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
        """Validate that all referenced library files exist on disk.

        Iterates ALL file-list keys — historically only `_libraries` was
        checked, but the track-schema fallback in load_tech_config also
        emits `lef_files`, `tluplus_files`, `nxtgrd_files`, `qrc_files`
        (and the coverage path can produce `ndm_libraries`). Missing
        those in the validator meant `check` reported PASS with 0 refs
        for every shipped tech config — a false-GREEN regression.

        Also treats `$project(...)` / `$env(...)` template paths as
        UNRESOLVED (a distinct status from missing-on-disk): a template
        path is not a real check — the Tcl resolver must run first for
        it to become a checkable path. Conflating "wrong path" with
        "config not yet resolved" produces false "missing" reports.
        """
        results = []

        _file_key_re = re.compile(r'.*(?:_libraries|_files)$')
        for set_name, set_data in sorted(config.items()):
            lib_keys = [k for k in set_data if _file_key_re.match(k)]
            for lib_key in lib_keys:
                lib_type = (lib_key
                            .replace('_libraries', '')
                            .replace('_files', ''))
                paths = set_data[lib_key]
                if not isinstance(paths, list):
                    continue
                for p in paths:
                    # `$project(lib_root)/foo.ndm`, `$env(VENDOR)/x.lib`
                    # etc. can't be checked without sourcing the Tcl —
                    # mark as UNRESOLVED (exists=False, lib_type prefixed
                    # so cmd_check can bucket them separately).
                    if '$' in p:
                        results.append(ValidationResult(
                            path=p,
                            exists=False,
                            lib_set=set_name,
                            lib_type=f'{lib_type}[UNRESOLVED]',
                        ))
                        continue
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


# ═══════════════════════════════════════════════════════════════════════════════
# Tag-directory layout (introduced 2026-10-10)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Each `--tag <TAG>` now materializes a self-contained directory next to the
# tech overlay instead of a single flat `lib_config_<tag>.tcl` sibling:
#
#   PD/config/tech/<tech>/<ver>/<TAG>/
#   ├── lib_config.tcl        ← rewritten with LOCAL symlink paths
#   ├── README.md             ← PVT matrix + source lib_root + file counts
#   ├── MANIFEST.tcl          ← symlink → vendor-target audit list
#   ├── ndm/<track>/*.ndm     ← all VTs flat inside per-track dir
#   ├── lib/<track>/*.lib     ← same shape
#   ├── db/<track>/*.db
#   ├── lef/<track>/*.lef
#   ├── memory/{lib,db,lef,ndm,gds,cdl,verilog}/*
#   ├── io/{lib,db,lef,ndm,gds,cdl,verilog}/*
#   ├── analog/{lib,db,lef,ndm,gds,cdl,verilog}/*
#   ├── ip/{lib,db,lef,ndm,gds,cdl,verilog}/*
#   └── logs/generate.log     ← scan trace
#
# Benefits:
#   · Tag dir is relocatable — `mv P0 P0_frozen` moves everything atomically.
#   · README gives humans an at-a-glance view of what the tag contains.
#   · Flow integration is one path: $project(lib_config_tag) → <TAG>/.
#   · lib_config.tcl values use `$_lib_tag_dir/...` so the tag survives a
#     move of the parent tech dir too (resolver anchors to its own location).
#
# Backwards compat: legacy flat `lib_config_<tag>.tcl` files are auto-migrated
# on the next `generate` call for that tag. All readers (mmmc-manager,
# cmd_status, cmd_coverage) consult the tag-dir first and fall back to the
# flat file so pre-migration tags keep working.
# ═══════════════════════════════════════════════════════════════════════════════


def _resolve_tech_dir(tech_name: str, version: str = None) -> str:
    """Return the on-disk tech directory (where tech_config.tcl lives).
    Post 2026-10-11 this is in global/config/tech/<tech>/<ver>/.
    """
    ver = version or 'v1.0.0'
    from core.paths import get_cbflow_global_dir
    gdir = get_cbflow_global_dir()
    if not gdir:
        return ''
    return os.path.join(gdir, 'config', 'tech', tech_name, ver)


class _CfgReadError(Exception):
    """File existed but could not be read (perms, encoding, I/O). Caller
    should treat this as FAIL-CLOSED — do NOT fall through to a lower-
    priority source, because the user's config is unreachable, not unset.
    """
    pass


def _read_tech_cfg_value(tech_name: str, version: str, key: str) -> str:
    """Extract `set tech(<key>) "<value>"` from tech_config.tcl.

    Returns the raw value string, or '' if the key / file / tech_dir is
    legitimately absent (configuration state: "not set"). Raises
    _CfgReadError if the file EXISTS but can't be read (OSError or
    UnicodeDecodeError) — distinguishing "unset" from "unreadable" so
    the resolver doesn't silently fail open on a perm/encoding glitch
    (NFS hiccup, chmod 000, bad locale) and place lib tags inside
    CBFLOW_ROOT because `_is_inside_framework` saw no roots to reject.
    """
    tech_dir = _resolve_tech_dir(tech_name, version)
    if not tech_dir:
        return ''
    tc = os.path.join(tech_dir, 'tech_config.tcl')
    if not os.path.isfile(tc):
        return ''
    try:
        with open(tc, encoding='utf-8') as f:
            m = re.search(
                r'^\s*set\s+tech\(' + re.escape(key)
                + r'\)\s+"([^"]*)"', f.read(), re.MULTILINE)
            return m.group(1).strip() if m else ''
    except (OSError, UnicodeDecodeError) as e:
        raise _CfgReadError(
            "cannot read tech_config.tcl for '{}' ({}: {})".format(
                tech_name, type(e).__name__, e))


def _read_project_cfg_value(project_name: str, version: str, key: str) -> str:
    """Extract `set project(<key>) "<value>"` from the project's PD overlay.

    Post 2026-11-01 rename: file is `<project>_pd_config.tcl`.

    Same tri-state semantics as _read_tech_cfg_value: '' for "key or file
    legitimately absent", raises _CfgReadError if file exists but is
    unreadable.
    """
    if not project_name:
        return ''
    try:
        core = get_cbflow_core_dir()
    except ValueError:
        return ''
    from core.paths import project_discipline_config_basename
    _basename = project_discipline_config_basename(project_name, 'pd')
    pc = os.path.join(core, 'config', 'project', project_name,
                      version or 'v1.0.0', _basename)
    if not os.path.isfile(pc):
        return ''
    try:
        with open(pc, encoding='utf-8') as f:
            m = re.search(
                r'^\s*set\s+project\(' + re.escape(key)
                + r'\)\s+"([^"]*)"', f.read(), re.MULTILINE)
            return m.group(1).strip() if m else ''
    except (OSError, UnicodeDecodeError) as e:
        raise _CfgReadError(
            "cannot read {} for '{}' ({}: {})".format(
                _basename, project_name, type(e).__name__, e))


def _framework_roots() -> list:
    """Absolute paths that `lib_tag_root` is forbidden from pointing inside.

    Rejecting these keeps the git tree clean: no accidental commits of
    generated tag directories, no silent self-nesting when a user sets
    lib_tag_root to a path inside CBFLOW_ROOT.
    """
    roots = []
    for env_var in ('CBFLOW_ROOT', 'CBFLOW_CORE_DIR', 'CBFLOW_GLOBAL_DIR',
                    'CBFLOW_DFT_DIR', 'CBFLOW_DV_DIR'):
        v = os.environ.get(env_var, '').strip()
        if v:
            try:
                roots.append(os.path.realpath(v))
            except OSError:
                pass
    try:
        core_dir = get_cbflow_core_dir()
        if core_dir:
            roots.append(os.path.realpath(core_dir))
            roots.append(os.path.realpath(os.path.dirname(core_dir)))
    except Exception:
        pass
    return sorted(set(roots))


def _is_inside_framework(path: str) -> bool:
    """True if `path` resolves inside any CBflow framework root.
    Used to reject lib_tag_root values that would nest tags in the git tree.
    """
    if not path:
        return False
    try:
        real = os.path.realpath(path)
    except OSError:
        real = path
    for root in _framework_roots():
        if real == root or real.startswith(root + os.sep):
            return True
    return False


def _resolve_lib_tag_root(tech_name: str, version: str = None,
                          project_name: str = None,
                          cli_override: str = None) -> str:
    """Resolve where library tags for this tech should be stored.

    Resolution order (first non-empty wins):
      1. `cli_override`                      — --lib-tag-root CLI flag
      2. $CBFLOW_LIB_TAG_ROOT                 — env var (CI / scratch)
      3. project(lib_tag_root)                — per-project override
      4. tech(lib_tag_root)                   — site-wide default per tech
      5. ''                                   — unset; caller must error-out

    Returns the absolute lib_tag_root path (no TAG segment, no version
    segment — the TAG itself carries version semantics via its name).

    Framework-tree fallback is deliberately NOT provided: externalizing
    the library area is mandatory. If a candidate resolves to a path
    inside the framework git tree (CBFLOW_ROOT / PD / global / DFT / DV),
    this function LOGS A WARNING AND REJECTS it so the caller sees the
    same empty-return behavior as an unset config and emits the fix
    guide. We don't silently fall through to the next source — a value
    was configured, it's just wrong.
    """
    # Returns (accepted_path, was_rejected). If was_rejected=True we
    # TERMINATE here — don't fall through to the next source. The user
    # misconfigured a specific source; silently preferring another one
    # hides the misconfiguration (exactly the bug we're trying to kill).
    _REJECTED = object()

    def _accept(src_label: str, candidate: str):
        candidate = os.path.abspath(candidate)
        if _is_inside_framework(candidate):
            logger.error(
                "lib_tag_root from {} points inside the framework tree: {}".format(
                    src_label, candidate))
            logger.error(
                "  Library tags MUST live outside CBFLOW_ROOT so flow updates don't "
                "require regen. Rejecting (not falling through to lower-priority sources).")
            return _REJECTED
        return candidate

    def _try(src_label, raw):
        """Returns path, '', or raises SystemExit on in-tree rejection."""
        if not raw:
            return ''
        r = _accept(src_label, raw)
        if r is _REJECTED:
            # Terminal reject: don't let a lower-priority source paper over
            # the misconfigured one.
            return _REJECTED
        return r

    for label, raw in (
        ('--lib-tag-root', cli_override),
        ('$CBFLOW_LIB_TAG_ROOT',
         os.environ.get('CBFLOW_LIB_TAG_ROOT', '').strip()),
    ):
        r = _try(label, raw)
        if r is _REJECTED:
            return ''
        if r:
            return r

    if not project_name:
        project_name = os.environ.get('CBFLOW_PROJECT_NAME', '')
    # If reading the project/tech config file fails (not "key absent"),
    # fail CLOSED — don't silently fall through to the next source and
    # accept a value from a lower-priority config while the user's
    # higher-priority config is unreachable (e.g. an NFS hiccup must
    # not let lib tags land under CBFLOW_ROOT).
    try:
        v = _read_project_cfg_value(project_name, version, 'lib_tag_root')
    except _CfgReadError as e:
        logger.error("lib_tag_root cascade: project config read failed: {}".format(e))
        return ''
    r = _try("project({}, lib_tag_root)".format(project_name or '<unknown>'), v)
    if r is _REJECTED:
        return ''
    if r:
        return r

    try:
        v = _read_tech_cfg_value(tech_name, version, 'lib_tag_root')
    except _CfgReadError as e:
        logger.error("lib_tag_root cascade: tech config read failed: {}".format(e))
        return ''
    r = _try("tech({}, lib_tag_root)".format(tech_name), v)
    if r is _REJECTED:
        return ''
    if r:
        return r

    return ''


def _lib_tag_root_fix_guide(tech_name: str, version: str) -> List[str]:
    """Return the multi-line error banner shown when lib_tag_root is unset.
    Called from `cmd_generate`, `cmd_add`, and any other write path."""
    tech_dir = _resolve_tech_dir(tech_name, version) or \
               '$CBFLOW_GLOBAL_DIR/config/tech/{}/v1.0.0'.format(tech_name)
    return [
        "lib_tag_root is not configured for '{}'.".format(tech_name),
        "",
        "Library tags MUST live OUTSIDE the framework git tree so flow",
        "updates don't force a regen. The framework ships NO default — you",
        "must point at a real site path explicitly. Pick ONE:",
        "",
        "  1. Per-project (recommended for team-wide use):",
        "     Edit $CBFLOW_CORE_DIR/config/project/<proj>/v1.0.0/<project>_pd_config.tcl:",
        "       set project(lib_tag_root) \"/proj/<proj>/pdk/{}\"".format(tech_name),
        "",
        "  2. Per-run via env var (CI, scratch areas):",
        "       export CBFLOW_LIB_TAG_ROOT=/scratch/<user>/pdk",
        "",
        "  3. Per-invocation via CLI flag:",
        "       cbflow flow library-manager generate ... --lib-tag-root <path>",
        "",
        "  4. Site-wide via tech default — uncomment this line in",
        "     {}/tech_config.tcl:".format(tech_dir),
        "       set tech(lib_tag_root) \"/proj/pdk/libs/{}\"".format(tech_name),
        "",
        "In all cases the path MUST be outside CBFLOW_ROOT. Final tag",
        "path = <lib_tag_root>/<TAG>/.",
    ]


def _resolve_lib_tag_dir(tech_name: str, tag: str, version: str = None,
                         project_name: str = None,
                         cli_override: str = None) -> str:
    """Absolute path to the tag directory. '' if lib_tag_root is unset."""
    root = _resolve_lib_tag_root(tech_name, version,
                                 project_name=project_name,
                                 cli_override=cli_override)
    return os.path.join(root, tag) if root else ''


def _lib_tag_root_was_configured(tech_name: str, version: str = None,
                                 project_name: str = None,
                                 cli_override: str = None) -> bool:
    """True iff any lib_tag_root source has a non-empty raw value, even
    if that value was later rejected by _accept (in-tree). Lets callers
    distinguish 'unset (fall back to legacy)' from 'configured but
    rejected (do NOT fall back; the user misconfigured something)'.
    """
    if cli_override:
        return True
    if os.environ.get('CBFLOW_LIB_TAG_ROOT', '').strip():
        return True
    if not project_name:
        project_name = os.environ.get('CBFLOW_PROJECT_NAME', '')
    # Treat read-failure as "configured" — the user has a config file we
    # can't read; we must NOT fall through to legacy. Only an empty read
    # (file genuinely absent / key absent) means "not configured here".
    try:
        if _read_project_cfg_value(project_name, version, 'lib_tag_root'):
            return True
    except _CfgReadError:
        return True
    try:
        if _read_tech_cfg_value(tech_name, version, 'lib_tag_root'):
            return True
    except _CfgReadError:
        return True
    return False


def _resolve_lib_config_path(tech_name: str, tag: str,
                             version: str = None,
                             project_name: str = None,
                             cli_override: str = None) -> str:
    """Return the lib_config.tcl path for a given tag, or '' if not found.

    Three distinct states:
      lib_tag_root SET + file exists   → return <root>/<TAG>/lib_config.tcl
      lib_tag_root SET + file missing  → return '' TERMINALLY.
      lib_tag_root REJECTED (in-tree)  → return '' TERMINALLY. The user
          configured a bad source; we must NOT paper over it with an
          in-tree legacy file (would reintroduce the externalization bug).
      lib_tag_root UNSET               → fall through to in-tree legacy
          (pre-externalization backcompat ramp):
             (a) <tech_dir>/<TAG>/lib_config.tcl
             (b) <tech_dir>/lib_config_<TAG>.tcl
    """
    root = _resolve_lib_tag_root(tech_name, version,
                                 project_name=project_name,
                                 cli_override=cli_override)
    if root:
        # Current layout: <lib_tag_root>/<tech_node>/<tag>/lib_config.tcl
        # — groups every tag for a tech under one dir so lib_config.tcl
        # and mmmc_config.tcl for the same (tech, tag) live together.
        new = os.path.join(root, tech_name, tag, 'lib_config.tcl')
        # Legacy layout (pre-tech-grouping): <lib_tag_root>/<tag>/lib_config.tcl
        legacy = os.path.join(root, tag, 'lib_config.tcl')
        _new_exists = os.path.isfile(new)
        _legacy_exists = os.path.isfile(legacy)
        if _new_exists and _legacy_exists:
            # Divergence detected — both layouts have the same tag. The
            # new layout wins (operators migrating from legacy expect
            # the tech-grouped tree to be authoritative), but surface a
            # loud warning so the user doesn't edit the stale file
            # under the mistaken impression it's active. This matches
            # the mtime-sensitive bug mmmc_manager would otherwise hit
            # by validating against stale library data.
            try:
                _new_mtime = os.path.getmtime(new)
                _legacy_mtime = os.path.getmtime(legacy)
                _mtime_note = (
                    f" (new mtime {int(_new_mtime)}, "
                    f"legacy mtime {int(_legacy_mtime)})"
                )
            except OSError:
                _mtime_note = ""
            logger.warning(
                "lib_config tag '%s' exists in BOTH layouts for tech '%s'%s. "
                "Using the tech-grouped file at %s; the legacy file at %s "
                "is being IGNORED. Delete the legacy file or re-run "
                "generate to resolve the ambiguity.",
                tag, tech_name, _mtime_note, new, legacy)
            return new
        if _new_exists:
            return new
        if _legacy_exists:
            return legacy
        return ''
    # root is '': could be "nothing configured" OR "configured but rejected".
    # Only fall back to legacy for the "nothing configured" case.
    if _lib_tag_root_was_configured(tech_name, version,
                                    project_name=project_name,
                                    cli_override=cli_override):
        return ''
    tech_dir = _resolve_tech_dir(tech_name, version)
    if tech_dir:
        legacy_dir = os.path.join(tech_dir, tag, 'lib_config.tcl')
        if os.path.isfile(legacy_dir):
            return legacy_dir
        legacy_flat = os.path.join(tech_dir, 'lib_config_{}.tcl'.format(tag))
        if os.path.isfile(legacy_flat):
            return legacy_flat
    return ''


def _list_available_tags(tech_name: str, version: str = None,
                         project_name: str = None,
                         cli_override: str = None) -> List[str]:
    """Enumerate every tag with a lib_config available.

    When lib_tag_root is set, only the external root is consulted — the
    in-tree legacy locations are ignored so stale tags there don't show up
    as valid selections. When lib_tag_root is unset, in-tree legacy is
    the only source (pre-externalization backcompat).
    """
    tags = set()
    root = _resolve_lib_tag_root(tech_name, version,
                                 project_name=project_name,
                                 cli_override=cli_override)
    if root:
        # Current layout: <root>/<tech_node>/<tag>/lib_config.tcl.
        tech_scoped = os.path.join(root, tech_name)
        if os.path.isdir(tech_scoped):
            for entry in os.listdir(tech_scoped):
                p = os.path.join(tech_scoped, entry)
                if os.path.isdir(p) and os.path.isfile(
                        os.path.join(p, 'lib_config.tcl')):
                    tags.add(entry)
        # Legacy layout: <root>/<tag>/lib_config.tcl (pre-tech-grouping).
        if os.path.isdir(root):
            for entry in os.listdir(root):
                if entry == tech_name:
                    continue  # already handled above
                p = os.path.join(root, entry)
                if os.path.isdir(p) and os.path.isfile(
                        os.path.join(p, 'lib_config.tcl')):
                    tags.add(entry)
        return sorted(tags)
    tech_dir = _resolve_tech_dir(tech_name, version)
    if tech_dir and os.path.isdir(tech_dir):
        for entry in os.listdir(tech_dir):
            p = os.path.join(tech_dir, entry)
            if os.path.isdir(p) and os.path.isfile(
                    os.path.join(p, 'lib_config.tcl')):
                tags.add(entry)
                continue
            if (os.path.isfile(p) and entry.startswith('lib_config_')
                    and entry.endswith('.tcl')):
                tags.add(entry[len('lib_config_'):-len('.tcl')])
    return sorted(tags)


def _collect_category(category: str, abs_paths: list) -> list:
    """Group a flat path list by its (track|category, filename) coordinates.
    Internal helper for _materialize_tag_dir. Returns a list of
    (subdir_relative_to_tag, filename, abs_target) tuples for symlink creation.
    """
    out = []
    for p in abs_paths:
        if not p:
            continue
        out.append((category, os.path.basename(p), p))
    return out


def _safe_symlink(src_abs: str, dst_abs: str) -> str:
    """Create a symlink dst_abs → src_abs, overwriting any prior link.
    Returns 'symlink' on success, 'copy' if symlink creation isn't permitted
    (NFS/noexec), or 'skip' if the source is missing (test-mode stub files).
    """
    if not src_abs:
        return 'skip'
    try:
        if os.path.islink(dst_abs) or os.path.exists(dst_abs):
            os.remove(dst_abs)
    except OSError:
        pass
    try:
        os.symlink(src_abs, dst_abs)
        return 'symlink'
    except OSError:
        # FS doesn't support symlinks — fall back to a stub pointer file
        # so the structure is still browsable but tools get a diagnostic.
        try:
            with open(dst_abs, 'w') as fh:
                fh.write("# CBflow symlink stub — target FS rejected symlink()\n")
                fh.write("# intended target: {}\n".format(src_abs))
            return 'stub'
        except OSError:
            return 'skip'


def _materialize_tag_dir(tag_dir: str,
                          tech_name: str,
                          tag: str,
                          lib_root: str,
                          all_tracks: list,
                          all_vts: list,
                          all_corners: list,
                          ndm_libs: dict,
                          db_libs: dict,
                          lef_libs: dict,
                          lib_nom_libs: dict,
                          timing_libs: dict,
                          # Shared (per-category) buckets. memory + io were
                          # the original two; analog + ip added 2026-10-10
                          # for IP deliverables and analog macros that
                          # arrive after the initial tag was generated.
                          ndm_memory: list = None, ndm_io: list = None,
                          ndm_analog: list = None, ndm_ip: list = None,
                          db_mem: list = None, db_io: list = None,
                          db_analog: list = None, db_ip: list = None,
                          lef_memory: list = None, lef_io: list = None,
                          lef_analog: list = None, lef_ip: list = None,
                          lib_nom_memory: list = None, lib_nom_io: list = None,
                          lib_nom_analog: list = None, lib_nom_ip: list = None,
                          timing_memory: dict = None, timing_io: dict = None,
                          timing_analog: dict = None, timing_ip: dict = None,
                          scan_log_lines: list = None,
                          preserve_other_categories: bool = False) -> dict:
    """Build tag directory contents. Returns dict mapping tech() key tuple
    → list of local tag-relative paths.

    When `preserve_other_categories` is True, categories NOT provided
    (passed as None or empty) are left untouched on disk — enables
    surgical `add` operations that extend one category without wiping
    the rest. Default False retains the pre-2026-10-10 behavior where
    `generate` rebuilds the whole tag.
    """
    # Normalize None → empty so loops are uniform.
    ndm_memory = ndm_memory or []; ndm_io = ndm_io or []
    ndm_analog = ndm_analog or []; ndm_ip = ndm_ip or []
    db_mem = db_mem or []; db_io = db_io or []
    db_analog = db_analog or []; db_ip = db_ip or []
    lef_memory = lef_memory or []; lef_io = lef_io or []
    lef_analog = lef_analog or []; lef_ip = lef_ip or []
    lib_nom_memory = lib_nom_memory or []; lib_nom_io = lib_nom_io or []
    lib_nom_analog = lib_nom_analog or []; lib_nom_ip = lib_nom_ip or []
    timing_memory = timing_memory or {}; timing_io = timing_io or {}
    timing_analog = timing_analog or {}; timing_ip = timing_ip or {}
    """Build the tag directory: subdirs, symlinks, README, MANIFEST, log.

    Returns a dict mapping each original tech() key tuple to the new LOCAL
    path the caller should emit into lib_config.tcl. Keys that didn't map to
    a file (empty source list) are skipped — the caller omits those lines.

    Mapping produced:
       (track, vt, 'ndm')          → "$_lib_tag_dir/ndm/<track>/<vt>_<basename>"
       (track, vt, corner, 'lib')  → "$_lib_tag_dir/lib/<track>/<vt>_<corner>_<basename>"
       ('memory'|'io'|'analog', 'lib'|'db'|'lef'|'ndm') → "$_lib_tag_dir/<cat>/<kind>/<basename>"
       ('memory'|'io', corner, 'lib')  → "$_lib_tag_dir/<cat>/lib/<corner>_<basename>"

    `scan_log_lines` is an optional list of pre-scan log entries to flush
    into logs/generate.log.
    """
    os.makedirs(tag_dir, exist_ok=True)
    # Fixed subdirs — created unconditionally so the layout is predictable
    # even for a sparse tag. Empty subdirs are documented in the README.
    #
    # Layout: each library category (stdcell / memory / io / analog / ip)
    # owns its own {ndm, lib, db, lef, gds, cdl, verilog} subtree. Pre-
    # fix, gds / cdl / verilog were materialized as top-level dirs — but
    # a GDS always belongs to a specific category (stdcell GDS vs memory
    # GDS vs analog GDS), so the top-level versions were ambiguous
    # scaffolding that nothing ever wrote into. Pulling them inside
    # each category removes the ambiguity and keeps the layout
    # consistent with how ndm/db/lef/lib are already organized.
    #
    # Only `logs/` stays at the top level — it's genuinely category-
    # agnostic (per-tag generate/add run logs, not per-library artifacts).
    _CATEGORIES = ('stdcell', 'memory', 'io', 'analog', 'ip')
    _KINDS      = ('ndm', 'lib', 'db', 'lef', 'gds', 'cdl', 'verilog')
    subdirs = ['{}/{}'.format(cat, kind)
               for cat in _CATEGORIES for kind in _KINDS]
    subdirs.append('logs')
    for sub in subdirs:
        os.makedirs(os.path.join(tag_dir, sub), exist_ok=True)

    def _tag_rel(*parts):
        """Build '$_lib_tag_dir/<rest>' — the resolver-local reference form."""
        return "$_lib_tag_dir/" + "/".join(parts)

    manifest = []     # list of (local_rel, vendor_abs) for MANIFEST.tcl
    local_map = {}    # map[(key_tuple)] = list of local tag-rel paths

    def _link_and_record(subdir_rel: str, fname: str, src_abs: str,
                         key_tuple: tuple):
        """Place one symlink in the tag dir, record in manifest + map.

        Collisions on filename (two VTs ship 'stdcell.ndm' both named the
        same) are resolved by prefixing with a de-duplicating counter.
        """
        host_dir = os.path.join(tag_dir, subdir_rel)
        os.makedirs(host_dir, exist_ok=True)
        candidate = fname
        n = 1
        while os.path.lexists(os.path.join(host_dir, candidate)):
            # Resolve collision by checking if existing is the same target.
            existing = os.path.join(host_dir, candidate)
            try:
                if (os.path.islink(existing) and
                        os.path.realpath(existing) == os.path.realpath(src_abs)):
                    # Same target → re-use link, no new entry
                    break
            except OSError:
                pass
            stem, ext = os.path.splitext(fname)
            candidate = '{}_{}{}'.format(stem, n, ext)
            n += 1
        dst_abs = os.path.join(host_dir, candidate)
        if not os.path.lexists(dst_abs):
            method = _safe_symlink(src_abs, dst_abs)
            manifest.append((subdir_rel + '/' + candidate, src_abs, method))
        local_map.setdefault(key_tuple, []).append(
            _tag_rel(subdir_rel, candidate))

    def _tidy_name(fname: str, *tokens) -> str:
        """Prefix `fname` with `<token>_<token>_...` only for tokens that
        aren't already somewhere in the filename. Keeps the symlink name
        readable without doubling encoding when the vendor file already
        carries `_9T_svt_` etc.
        """
        base = fname
        prefix_parts = []
        low = base.lower()
        for t in tokens:
            if t and t.lower() not in low:
                prefix_parts.append(t)
        return ('_'.join(prefix_parts) + '_' + base) if prefix_parts else base

    # ── Stdcell libraries — stdcell/<kind>/<track>/<file> ─────────────────
    # Nested under stdcell/ parent so the top-level layout is uniform with
    # memory/, io/, analog/, ip/ (each a single parent dir holding its
    # kind sub-dirs).
    for (trk, vt), paths in ndm_libs.items():
        for p in paths:
            _link_and_record('stdcell/ndm/{}'.format(trk),
                             _tidy_name(os.path.basename(p), vt),
                             p, (trk, vt, 'ndm'))
    for (trk, vt), paths in db_libs.items():
        for p in paths:
            _link_and_record('stdcell/db/{}'.format(trk),
                             _tidy_name(os.path.basename(p), vt),
                             p, (trk, vt, 'db'))
    for (trk, vt), paths in lef_libs.items():
        for p in paths:
            _link_and_record('stdcell/lef/{}'.format(trk),
                             _tidy_name(os.path.basename(p), vt),
                             p, (trk, vt, 'lef'))
    for (trk, vt), paths in lib_nom_libs.items():
        for p in paths:
            _link_and_record('stdcell/lib/{}'.format(trk),
                             _tidy_name(os.path.basename(p), vt, 'nom'),
                             p, (trk, vt, 'lib_nom'))
    for (trk, vt, corner), paths in timing_libs.items():
        for p in paths:
            _link_and_record('stdcell/lib/{}'.format(trk),
                             _tidy_name(os.path.basename(p), vt, corner),
                             p, (trk, vt, corner, 'lib_timing'))

    # ── Memory ───────────────────────────────────────────────────────────
    for p in ndm_memory:
        _link_and_record('memory/ndm', os.path.basename(p), p, ('memory', 'ndm'))
    for p in db_mem:
        _link_and_record('memory/db', os.path.basename(p), p, ('memory', 'db'))
    for p in lef_memory:
        _link_and_record('memory/lef', os.path.basename(p), p, ('memory', 'lef'))
    for p in lib_nom_memory:
        _link_and_record('memory/lib',
                         _tidy_name(os.path.basename(p), 'nom'),
                         p, ('memory', 'lib_nom'))
    for corner, paths in timing_memory.items():
        for p in paths:
            _link_and_record('memory/lib',
                             _tidy_name(os.path.basename(p), corner),
                             p, ('memory', corner, 'lib_timing'))

    # ── IO ───────────────────────────────────────────────────────────────
    for p in ndm_io:
        _link_and_record('io/ndm', os.path.basename(p), p, ('io', 'ndm'))
    for p in db_io:
        _link_and_record('io/db', os.path.basename(p), p, ('io', 'db'))
    for p in lef_io:
        _link_and_record('io/lef', os.path.basename(p), p, ('io', 'lef'))
    for p in lib_nom_io:
        _link_and_record('io/lib',
                         _tidy_name(os.path.basename(p), 'nom'),
                         p, ('io', 'lib_nom'))
    for corner, paths in timing_io.items():
        for p in paths:
            _link_and_record('io/lib',
                             _tidy_name(os.path.basename(p), corner),
                             p, ('io', corner, 'lib_timing'))

    # ── Analog ───────────────────────────────────────────────────────────
    for p in ndm_analog:
        _link_and_record('analog/ndm', os.path.basename(p), p, ('analog', 'ndm'))
    for p in db_analog:
        _link_and_record('analog/db', os.path.basename(p), p, ('analog', 'db'))
    for p in lef_analog:
        _link_and_record('analog/lef', os.path.basename(p), p, ('analog', 'lef'))
    for p in lib_nom_analog:
        _link_and_record('analog/lib',
                         _tidy_name(os.path.basename(p), 'nom'),
                         p, ('analog', 'lib_nom'))
    for corner, paths in timing_analog.items():
        for p in paths:
            _link_and_record('analog/lib',
                             _tidy_name(os.path.basename(p), corner),
                             p, ('analog', corner, 'lib_timing'))

    # ── IP ───────────────────────────────────────────────────────────────
    for p in ndm_ip:
        _link_and_record('ip/ndm', os.path.basename(p), p, ('ip', 'ndm'))
    for p in db_ip:
        _link_and_record('ip/db', os.path.basename(p), p, ('ip', 'db'))
    for p in lef_ip:
        _link_and_record('ip/lef', os.path.basename(p), p, ('ip', 'lef'))
    for p in lib_nom_ip:
        _link_and_record('ip/lib',
                         _tidy_name(os.path.basename(p), 'nom'),
                         p, ('ip', 'lib_nom'))
    for corner, paths in timing_ip.items():
        for p in paths:
            _link_and_record('ip/lib',
                             _tidy_name(os.path.basename(p), corner),
                             p, ('ip', corner, 'lib_timing'))

    # ── MANIFEST.tcl — audit trail: local → vendor ───────────────────────
    # When `preserve_other_categories` is set (incremental / add path),
    # union with any existing MANIFEST entries so prior category records
    # survive this scan. The current-scan tuples win on local_rel collisions.
    manifest_path = os.path.join(tag_dir, 'MANIFEST.tcl')
    final_manifest = list(manifest)
    if preserve_other_categories and os.path.isfile(manifest_path):
        try:
            seen_locals = {m[0] for m in manifest}
            # Parse existing: `set manifest({<local>}) {<vendor> <method>}`.
            _mre = re.compile(
                r'set\s+manifest\(\{([^}]+)\}\)\s+\{([^}]+)\s+(\w+)\}')
            with open(manifest_path, 'r') as ef:
                for ln in ef:
                    m = _mre.search(ln)
                    if not m:
                        continue
                    local_rel = m.group(1)
                    if local_rel in seen_locals:
                        continue
                    final_manifest.append(
                        (local_rel, m.group(2), m.group(3)))
        except OSError:
            pass

    # Atomic rewrite — pre-fix, open-w truncate + loop-write destroyed
    # the authoritative local→vendor audit trail if the process died
    # mid-write (disk full, OOM, host crash). No tmp+rename, no backup.
    _manifest_buf = []
    _manifest_buf.append("#!/usr/bin/env tclsh\n")
    _manifest_buf.append("# CBflow library-tag MANIFEST — audit trail for tag '{}'\n".format(tag))
    _manifest_buf.append("# Tech: {}  Generated: {}\n".format(
        tech_name, datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
    _manifest_buf.append("# Format: set manifest(<local_rel>) {<vendor_abs> <link_method>}\n")
    _manifest_buf.append("# link_method: symlink | stub | skip (source missing)\n\n")
    for local_rel, vendor_abs, method in sorted(final_manifest):
        _manifest_buf.append('set manifest({{{}}}) {{{} {}}}\n'.format(
            local_rel, vendor_abs, method))
    _manifest_buf.append("\nset manifest(_count) {}\n".format(len(final_manifest)))
    _manifest_buf.append("set manifest(_methods) {{symlink stub skip}}\n")
    atomic_write(manifest_path, "".join(_manifest_buf))

    # Reassign `manifest` so the README generator below sees the merged list.
    manifest = final_manifest

    # ── README.md — human overview ───────────────────────────────────────
    with open(os.path.join(tag_dir, 'README.md'), 'w') as fh:
        fh.write("# Library tag: `{}`\n\n".format(tag))
        fh.write("Technology: **{}**  \n".format(tech_name))
        fh.write("Generated: **{}**  \n".format(
            datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        fh.write("Source lib_root: `{}`\n\n".format(lib_root))
        fh.write("---\n\n")
        fh.write("## Flow integration\n\n")
        fh.write("Set `project(lib_config_tag)` to `{}` in user_config.tcl ".format(tag))
        fh.write("(or `<project>_pd_config.tcl`). The resolver auto-picks\n")
        fh.write("`global/config/tech/{}/v1.0.0/{}/lib_config.tcl`.\n\n".format(
            tech_name, tag))
        fh.write("## Coverage\n\n")
        # In add-mode, this scan may be track-agnostic (analog/ip) — showing
        # (none) would hide the stdcell coverage from the original generate.
        # Union with the full MANIFEST state to show the TAG's accumulated
        # coverage, not just the latest scan.
        _tracks_shown = set(all_tracks)
        _vts_shown = set(all_vts)
        _corners_shown = set(all_corners)
        if preserve_other_categories:
            # Infer tracks + VTs + corners from local_rel paths in the merged
            # manifest. e.g. 'stdcell/ndm/9T/stdcell_9T_svt.ndm' → track=9T.
            # Pre-nest layout (one-release backcompat): 'ndm/9T/*' is also
            # recognized so manifests written before the stdcell/ rename
            # still read cleanly.
            import re as _re_m
            for local_rel, _v, _m in manifest:
                parts = local_rel.split('/')
                # New layout: stdcell/<kind>/<track>/<file>
                if (len(parts) >= 4 and parts[0] == 'stdcell'
                        and parts[1] in ('ndm', 'lib', 'db', 'lef')):
                    _tracks_shown.add(parts[2])
                # Legacy layout: <kind>/<track>/<file> (pre stdcell/ nest)
                elif (len(parts) >= 3 and parts[0] in ('ndm', 'lib', 'db', 'lef')
                        and parts[1] not in ('memory', 'io', 'analog', 'ip',
                                              'stdcell')):
                    _tracks_shown.add(parts[1])
                # VT embedded in filename as _<vt>_ or <vt>_ prefix
                _fn = parts[-1].lower()
                for _vt in ('svt', 'lvt', 'hvt', 'ulvt', 'rvt'):
                    if '_{}_'.format(_vt) in _fn or _fn.startswith(_vt + '_'):
                        _vts_shown.add(_vt)
                # Corner tokens: ss_<v>_<t>c / tt_<v>_<t>c / ff_<v>_<t>c
                _m2 = _re_m.search(r'(ss|tt|ff|sss|fff)_(\d+p\d+v)_(m?\d+c)',
                                    _fn)
                if _m2:
                    _corners_shown.add('_'.join(_m2.groups()))
        _trk_s = " ".join(sorted(_tracks_shown)) if _tracks_shown else "(none)"
        _vt_s = " ".join(sorted(_vts_shown)) if _vts_shown else "(none)"
        _cnr_s = " ".join(sorted(_corners_shown)) if _corners_shown else "(none)"
        fh.write("- **Tracks:** {}\n".format(_trk_s))
        fh.write("- **VTs:**    {}\n".format(_vt_s))
        fh.write("- **Corners:** {}\n\n".format(_cnr_s))
        fh.write("## File counts per subdirectory\n\n")
        counts = {}
        for local_rel, _vendor, _m in manifest:
            top = local_rel.split('/', 1)[0]
            counts[top] = counts.get(top, 0) + 1
        if counts:
            fh.write("| subdir | files |\n|---|---:|\n")
            for sub in sorted(counts):
                fh.write("| `{}/` | {} |\n".format(sub, counts[sub]))
            fh.write("\n")
        else:
            fh.write("_(no files linked — scan found nothing in `{}`)_\n\n".format(lib_root))
        fh.write("## Layout\n\n```\n")
        fh.write("{}/\n".format(tag))
        fh.write("├── lib_config.tcl           # resolver-visible tech(...) keys, LOCAL paths\n")
        fh.write("├── MANIFEST.tcl             # symlink → vendor audit\n")
        fh.write("├── README.md                # this file\n")
        fh.write("├── stdcell/\n")
        fh.write("│   ├── ndm/<track>/         # stdcell NDM per track (all VTs flat)\n")
        fh.write("│   ├── lib/<track>/         # Liberty .lib timing + nominal\n")
        fh.write("│   ├── db/<track>/          # compiled .db for PT/FC\n")
        fh.write("│   ├── lef/<track>/         # abstract LEF\n")
        fh.write("│   ├── gds/                 # stdcell GDS\n")
        fh.write("│   ├── cdl/                 # stdcell CDL / SPICE netlists\n")
        fh.write("│   └── verilog/             # stdcell Verilog views\n")
        fh.write("├── memory/{{lib,db,lef,ndm,gds,cdl,verilog}}/\n")
        fh.write("├── io/{{lib,db,lef,ndm,gds,cdl,verilog}}/\n")
        fh.write("├── analog/{{lib,db,lef,ndm,gds,cdl,verilog}}/\n")
        fh.write("├── ip/{{lib,db,lef,ndm,gds,cdl,verilog}}/\n")
        fh.write("└── logs/generate.log\n")
        fh.write("```\n\n")
        fh.write("## Regenerate\n\n")
        fh.write("```\n")
        fh.write("cbflow flow library-manager generate --tech {} --tag {}\n".format(
            tech_name, tag))
        fh.write("```\n\n")
        fh.write("Regeneration rebuilds every symlink from the source `lib_root` ")
        fh.write("and rewrites `lib_config.tcl`. Older symlinks pointing at files ")
        fh.write("that disappeared from the vendor delivery are left in place with ")
        fh.write("`stub` method so flow-time breakage is loud, not silent.\n")

    # ── logs/generate.log ────────────────────────────────────────────────
    log_path = os.path.join(tag_dir, 'logs', 'generate.log')
    with open(log_path, 'w') as fh:
        fh.write("CBflow library-manager generate — {}\n".format(
            datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        fh.write("tech: {}\ntag:  {}\nlib_root: {}\n".format(tech_name, tag, lib_root))
        fh.write("─" * 70 + "\n")
        if scan_log_lines:
            for ln in scan_log_lines:
                fh.write(ln + "\n")
        fh.write("─" * 70 + "\n")
        fh.write("MANIFEST entries: {}\n".format(len(manifest)))
        n_sym = sum(1 for _, _, m in manifest if m == 'symlink')
        n_stub = sum(1 for _, _, m in manifest if m == 'stub')
        n_skip = sum(1 for _, _, m in manifest if m == 'skip')
        fh.write("  symlink: {}  stub: {}  skip: {}\n".format(n_sym, n_stub, n_skip))

    return local_map


def _auto_migrate_flat_tag(tech_name: str, tag: str, version: str = None) -> bool:
    """Convert a legacy flat `lib_config_<tag>.tcl` into the new tag-dir
    layout. Called at the top of `cmd_generate` so re-running an older tag
    migrates it transparently.

    Strategy: this is a BEST-EFFORT shim. We don't re-scan — the vendor
    source may have moved. Instead we leave the flat file in place with a
    deprecation banner, create an empty tag dir, and let the caller
    overwrite via the normal generate path. The flat file will be
    deleted at the end of a successful generate.

    Returns True if a legacy file was detected (not necessarily converted).
    """
    tech_dir = _resolve_tech_dir(tech_name, version)
    if not tech_dir:
        return False
    flat = os.path.join(tech_dir, 'lib_config_{}.tcl'.format(tag))
    return os.path.isfile(flat)


def cmd_check(args: argparse.Namespace) -> int:
    """Validate library configuration against actual files on disk."""
    # Determine tech_config path — --tech-config wins; otherwise resolve
    # via the cascade helper (global first, PD legacy fallback).
    tech_config_path = getattr(args, 'tech_config', None)
    if not tech_config_path:
        tech_node = (getattr(args, 'tech', None)
                     or os.environ.get('CBFLOW_TECH_NODE', '')
                     or os.environ.get('TECH_NAME', ''))
        if not tech_node:
            logger.warning("CBFLOW_TECH_NODE or TECH_NAME not set, library paths may be incomplete")
        # require_tech_config returns the correct global-or-PD path; the
        # dispatcher-level preflight already gated on file presence.
        tech_config_path = require_tech_config(tech_node, getattr(args, "version", None))

    logger.info(f"Checking library config: {tech_config_path}")

    validator = LibraryValidator()
    config = validator.load_tech_config(tech_config_path)

    if not config:
        logger.error("No library_sets found in tech config")
        return 1

    results = validator.validate_libraries(config)
    total = len(results)
    # Bucket the three distinct outcomes explicitly. `[UNRESOLVED]` is a
    # template-path (`$project(lib_root)/...`) that validate_libraries
    # can't dereference without sourcing the Tcl — reporting it as
    # "missing" would conflate config-not-yet-resolved with the actual
    # wrong-path case, and the old code that reported nothing at all
    # (total refs = 0, PASSED) turned a hard-fail into a false-GREEN
    # for every shipped tech config. Keep the three buckets separate.
    unresolved = [r for r in results if r.lib_type.endswith('[UNRESOLVED]')]
    checked = [r for r in results if not r.lib_type.endswith('[UNRESOLVED]')]
    found = sum(1 for r in checked if r.exists)
    missing = len(checked) - found

    verbose = getattr(args, 'verbose', False)

    logger.info("")
    logger.info(f"{'='*65}")
    logger.info(f"  Library Validation Report")
    logger.info(f"{'='*65}")
    logger.info(f"  Tech config:    {tech_config_path}")
    logger.info(f"  Library sets:   {len(config)}")
    logger.info(f"  Total refs:     {total}")
    logger.info(f"  Checked:        {len(checked)}  (found={found} missing={missing})")
    logger.info(f"  Unresolved:     {len(unresolved)}  (template paths — Tcl not sourced)")
    logger.info(f"{'─'*65}")

    if verbose:
        for r in results:
            if r.lib_type.endswith('[UNRESOLVED]'):
                status = "[SKIP]"
            elif r.exists:
                status = "[PASS]"
            else:
                status = "[FAIL]"
            logger.info(f"  {status}  [{r.lib_set}/{r.lib_type}]  {r.path}")
    else:
        if missing > 0:
            logger.info("  Missing files:")
            for r in checked:
                if not r.exists:
                    logger.info(f"    [FAIL]  [{r.lib_set}/{r.lib_type}]  {r.path}")
        if unresolved:
            logger.info(f"  Unresolved template paths (sample of {min(3, len(unresolved))}):")
            for r in unresolved[:3]:
                logger.info(f"    [SKIP]  [{r.lib_set}/{r.lib_type}]  {r.path}")
            if len(unresolved) > 3:
                logger.info(f"    ... {len(unresolved) - 3} more (re-run with --verbose)")

    # Exit-code semantics:
    #   0 = clean run: all checked refs present, unresolved is fine
    #   1 = missing files on disk
    #   2 = nothing was actually checked (all unresolved, or empty config)
    #       — this is the case the old `check` used to flag with exit 1
    #       + "No library_sets found". Keep the distinction so CI can
    #       fail hard when the tech isn't ready to be checked at all,
    #       instead of a green PASS masking an unresolved config.
    if missing > 0:
        overall = "FAILED"
        exit_code = 1
    elif len(checked) == 0:
        overall = "NOT_VALIDATED — no resolvable paths (source the Tcl or run library-manager generate)"
        exit_code = 2
    else:
        overall = "PASSED"
        exit_code = 0
    logger.info(f"{'─'*65}")
    logger.info(f"  Overall: {overall}")
    logger.info(f"{'='*65}")
    logger.info("")

    return exit_code


def cmd_list(args: argparse.Namespace) -> int:
    """List configured library sets with optional filtering."""
    # Determine tech_config path — same cascade as cmd_check.
    tech_config_path = getattr(args, 'tech_config', None)
    if not tech_config_path:
        tech_node = (getattr(args, 'tech', None)
                     or os.environ.get('CBFLOW_TECH_NODE', '')
                     or os.environ.get('TECH_NAME', ''))
        if not tech_node:
            logger.warning("CBFLOW_TECH_NODE or TECH_NAME not set, library paths may be incomplete")
        tech_config_path = require_tech_config(tech_node, getattr(args, "version", None))

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

            # Count libraries per type. Cover the legacy shape
            # (`*_libraries`), the track-schema NDM/timing lists, and the
            # LEF-tech / RCX file lists that the shipped tech configs
            # declare directly.
            lib_counts = []
            for key in ('timing_libraries', 'power_libraries',
                        'noise_libraries', 'leakage_libraries',
                        'ndm_libraries', 'lef_files',
                        'tluplus_files', 'nxtgrd_files', 'qrc_files'):
                paths = set_data.get(key, [])
                count = len(paths) if isinstance(paths, list) else 0
                if count > 0:
                    short_key = (key.replace('_libraries', '')
                                    .replace('_files', ''))
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
# See _CORNERS_ENV / _apply_tech_corners / _build_lib_patterns above —
# this is rebuilt from the tech-declared process_corners set when
# library-manager starts. Default is {ss,tt,ff,sf,fs}; techs that ship
# `fff` or other variants add them via tech(process_corners).
_CORNER_RE = re.compile(
    r'(' + _corner_alternation(_DEFAULT_PROCESS_CORNERS) + r')'  # process corner
    r'(?:_[a-z]+)*?'                         # optional condition words
    r'_?(\d+p\d+v)'                          # voltage
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
    # --tech-config takes precedence over --tech / env. When the user
    # passes a raw tech_config.tcl path, derive tech_name from its
    # location (`.../tech/<name>/<version>/tech_config.tcl`) so
    # downstream code that still keys on tech_name (lib_set naming,
    # output stamps) continues to work. Lets Madhavi run library-manager
    # outside the flow dir with an arbitrary tech_config path.
    _tc_override = getattr(args, 'tech_config', None)
    if _tc_override:
        from core.paths import tech_name_from_config_path
        derived = tech_name_from_config_path(_tc_override)
        if derived:
            args.tech = args.tech or derived
            tech_name = args.tech
        elif args.tech:
            tech_name = args.tech
        else:
            logger.error("Could not derive tech name from {}. Pass --tech explicitly.".format(_tc_override))
            return 1
        # tech_config_path is just the explicit override — no name-based lookup.
    else:
        tech_name = args.tech
        if not tech_name:
            if not _interactive:
                logger.error("--tech or --tech-config is required in non-interactive mode")
                return 1
            from core.paths import get_cbflow_global_dir
            _gdir = get_cbflow_global_dir()
            tech_base = os.path.join(_gdir, 'config', 'tech') if _gdir else ''
            available = sorted(d for d in os.listdir(tech_base)
                              if os.path.isdir(os.path.join(tech_base, d))) if tech_base and os.path.isdir(tech_base) else []
            if not available:
                logger.error("No technologies found in {}".format(tech_base))
                return 1
            tech_name = _prompt_choice('Select technology', available)
            if not tech_name:
                logger.error("Invalid selection"); return 1
            print('  -> {}'.format(tech_name))
        args.tech = tech_name

        # Preflight — tech_config.tcl MUST exist. Historically this scanned the
        # directory tree and produced a partial lib_config; downstream failed at
        # signoff. Fail-fast here instead with a fix guide.
        require_tech_config(tech_name, getattr(args, 'version', None))

    # 2. Tag (mandatory)
    tag = args.tag if hasattr(args, 'tag') and args.tag else None
    if not tag and not args.output:
        if not _interactive:
            logger.error("--tag is required (e.g., --tag P0, --tag timing_v1)")
            return 1
        print('')
        # Show existing tags (new tag-dir layout + legacy flat files).
        version = args.version or "v1.0.0"
        _existing_tags = _list_available_tags(tech_name, version)
        if _existing_tags:
            print('  Existing lib_config tags: {}'.format(', '.join(_existing_tags)))
        tag = input('  Config tag (e.g., P0, timing_v1, signoff): ').strip()
        if not tag:
            logger.error("Tag is required. Output: <tech_dir>/<TAG>/lib_config.tcl")
            return 1
        args.tag = tag
        # Check if tag already exists (either form)
        _existing_path = _resolve_lib_config_path(tech_name, tag, version)
        if _existing_path:
            print('  WARNING: tag "{}" already exists:'.format(tag))
            print('    {}'.format(_existing_path))
            overwrite = input('  Overwrite? [y/N]: ').strip().lower()
            if overwrite != 'y':
                logger.info("Aborted — choose a different tag")
                return 1
            print('  -> will regenerate {}/'.format(tag))
        else:
            print('  -> {}/ (new tag directory)'.format(tag))

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
        # The resolver reads BOTH `tech(lib_root)` and
        # `project(lib_root)` from tech_config.tcl / <project>_pd_config.tcl
        # respectively — surface both options in the error.
        logger.error("lib_root is required. Provide one of:")
        logger.error("  --lib-root <path>                              (CLI override)")
        logger.error("  set tech(lib_root)    in tech_config.tcl       (site-wide default)")
        logger.error("  set project(lib_root) in <project>_pd_config.tcl (per-project)")
        return 1
    if not os.path.isdir(lib_root):
        logger.error("lib_root directory not found: {}".format(lib_root))
        logger.info("  Fix via --lib-root, tech(lib_root), or project(lib_root) — see above")
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

    # ── Pre-flight: refuse to generate if any declared source path is missing ──
    # Historically this printed a warning and (in interactive mode) let the user
    # bypass — non-interactive mode silently continued. Both paths produced a
    # lib_config with holes that only surfaced later during `library-manager check`.
    # Now: fail-fast unless --allow-missing is explicitly set.
    if not _all_paths_ok:
        _missing = []
        if lib_root and not os.path.isdir(lib_root):
            _missing.append(('lib_root', lib_root))
        for _label, _attr in [('stdcell_path', 'stdcell_path'),
                              ('memory_path',  'memory_path'),
                              ('io_path',      'io_path'),
                              ('ip_path',      'ip_path')]:
            _paths = getattr(args, _attr, None) if hasattr(args, _attr) else None
            if _paths:
                for _p in _paths:
                    if not os.path.isdir(_p):
                        _missing.append((_label, _p))

        # CBFLOW_ALLOW_MISSING env var is the CI/non-interactive equivalent of
        # --allow-missing — lets nightly wrappers opt in without needing to
        # rewrite every job.
        _allow_missing = (getattr(args, 'allow_missing', False)
                          or os.environ.get('CBFLOW_ALLOW_MISSING', '').lower() in ('1', 'true', 'yes'))
        if not _allow_missing:
            print('')
            print('  ═══════════════════════════════════════════════════════════')
            print('  ERROR: Pre-flight failed — {} source path(s) do not exist'.format(len(_missing)))
            print('  ═══════════════════════════════════════════════════════════')
            for _label, _p in _missing:
                print('    [MISSING] {:<14s} {}'.format(_label + ':', _p))
            print('')
            print('  A lib_config generated with missing sources will silently')
            print('  omit the corresponding NDM/LEF/LIB entries. Fix — pick one:')
            print('    (a) Create the directories (or fix the paths above)')
            print('    (b) Update project(lib_root) / project(<label>_path) in')
            print('        the project config to point at real locations')
            print('    (c) Re-run with --allow-missing (or export CBFLOW_ALLOW_MISSING=1')
            print('        for CI/nightly wrappers) if you MUST proceed with a')
            print('        partial config (bootstrapping only)')
            print('')
            return 1
        else:
            print('')
            print('  ═══════════════════════════════════════════════════════════')
            print('  WARNING: allow-missing set — proceeding with {} missing source(s):'.format(len(_missing)))
            for _label, _p in _missing:
                print('    [SKIP] {:<14s} {}'.format(_label + ':', _p))
            print('  Generated lib_config will be INCOMPLETE.')
            print('  ═══════════════════════════════════════════════════════════')

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
        # Tech is in global (single file, post 2026-10-11).
        tc_path = require_tech_config(tech_name, version)
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
    analog_dirs = []       # analog macros (PLL, ADC, DAC, LDO, ...)
    ip_dirs = []           # digital/mixed-signal IP (hardened cores, PHYs, ...)

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
            # Explicit --<category>-path override: always claim the dir
            # for the requested category — regardless of what filetypes
            # live here. User telling us this is 'analog' / 'ip' is
            # authoritative. Must run unconditionally so dirs with ONLY
            # NDM/LEF (no .lib/.db) still get category-tagged for the
            # file-level _category_for_path() lookup.
            if target_category and (has_ndm or has_lef or has_lib):
                for other in (stdcell_dirs, memory_dirs, io_dirs,
                              analog_dirs, ip_dirs):
                    if root in other:
                        other.remove(root)
                dest = {
                    'memory': memory_dirs,
                    'io':     io_dirs,
                    'analog': analog_dirs,
                    'ip':     ip_dirs,
                    'stdcell': stdcell_dirs,
                }.get(target_category)
                if dest is not None and root not in dest:
                    dest.append(root)
            elif has_lib and not target_category:
                if (root not in stdcell_dirs
                        and root not in memory_dirs and root not in io_dirs
                        and root not in analog_dirs and root not in ip_dirs):
                    # Auto-classify by directory name components
                    _dir_parts = root.lower().replace('\\', '/').split('/')
                    _basename = _dir_parts[-1] if _dir_parts else ''
                    if any(p in ('memory', 'mem') or p.startswith('mem_') for p in _dir_parts):
                        memory_dirs.append(root)
                    elif any(p in ('io', 'iolib') or p.startswith('io_') for p in _dir_parts):
                        io_dirs.append(root)
                    elif any(p in ('analog', 'ams') or p.startswith('analog_')
                             or p.startswith('ana_') for p in _dir_parts):
                        analog_dirs.append(root)
                    elif any(p in ('ip', 'ips', 'hardip', 'softip')
                             or p.startswith('ip_') for p in _dir_parts):
                        ip_dirs.append(root)
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

    # 5. Analog paths (first-class category — tech(ndm,analog) etc.)
    if hasattr(args, 'analog_path') and args.analog_path:
        analog_dirs = []  # reset auto-detected
        for ap in args.analog_path:
            ap = os.path.abspath(ap)
            logger.info("Scanning analog path: {}".format(ap))
            _scan_tree(ap, target_category='analog')

    # 6. IP paths (first-class category — tech(ndm,ip) etc.)
    if hasattr(args, 'ip_path') and args.ip_path:
        ip_dirs = []  # reset auto-detected
        for ipp in args.ip_path:
            ipp = os.path.abspath(ipp)
            logger.info("Scanning IP path: {}".format(ipp))
            _scan_tree(ipp, target_category='ip')

    # ── Discovery ──────────────────────────────────────────────────────────
    # Data structures: {(track, vt): [path, ...]}
    ndm_libs = defaultdict(list)      # (track,vt) → [ndm paths]
    db_libs = defaultdict(list)       # (track,vt) → [db paths]
    lef_libs = defaultdict(list)      # (track,vt) → [lef paths]
    lib_nom_libs = defaultdict(list)  # (track,vt) → [lib_nom paths]
    timing_libs = defaultdict(list)   # (track,vt,corner) → [timing lib paths]
    power_libs = defaultdict(list)    # (track,vt,corner) → [power lib paths]

    # Shared (non-track) libs — one bucket per category
    ndm_memory = []; ndm_io = []; ndm_analog = []; ndm_ip = []
    lef_memory = []; lef_io = []; lef_analog = []; lef_ip = []
    db_memory  = []; db_io  = []; db_analog  = []; db_ip  = []
    lib_nom_memory = []; lib_nom_io = []; lib_nom_analog = []; lib_nom_ip = []
    timing_memory = defaultdict(list)   # corner → [paths]
    timing_io     = defaultdict(list)
    timing_analog = defaultdict(list)
    timing_ip     = defaultdict(list)

    # Fast lookup for dir-based classification. Takes a file path and
    # returns 'memory' | 'io' | 'analog' | 'ip' | None (= stdcell / unknown).
    def _category_for_path(fpath):
        for cat, dirs in (('memory', memory_dirs),
                          ('io',     io_dirs),
                          ('analog', analog_dirs),
                          ('ip',     ip_dirs)):
            for d in dirs:
                if fpath.startswith(d.rstrip('/') + '/') or fpath == d:
                    return cat
        return None

    discovered_tracks = set()
    discovered_vts = set()
    discovered_corners = set()

    excluded_count = 0

    # ── Scan NDMs ──
    # Classification priority: directory membership (explicit --memory-path,
    # --analog-path, etc.) → filename substring → stdcell default. Dir-based
    # wins because it's authoritative (user told us where things live).
    for ndm_dir in ndm_dirs:
        if not os.path.isdir(ndm_dir):
            continue
        for f in sorted(os.listdir(ndm_dir)):
            if not _is_ndm_file(f):
                continue
            fpath = os.path.join(ndm_dir, f)
            if _is_excluded(fpath):
                excluded_count += 1; continue
            # 1) Explicit --<category>-path membership wins.
            _cat = _category_for_path(fpath)
            if _cat == 'memory':  ndm_memory.append(fpath); continue
            if _cat == 'io':      ndm_io.append(fpath);     continue
            if _cat == 'analog':  ndm_analog.append(fpath); continue
            if _cat == 'ip':      ndm_ip.append(fpath);     continue
            # 2) Fallback filename substring for the lib_root auto-scan case.
            fl = f.lower()
            if 'memory' in fl or 'mem' in fl:
                ndm_memory.append(fpath)
                continue
            if '_io' in fl or 'io.' in fl:
                ndm_io.append(fpath)
                continue
            if 'analog' in fl or '_ana_' in fl:
                ndm_analog.append(fpath)
                continue
            if '_ip_' in fl or fl.startswith('ip_'):
                ndm_ip.append(fpath)
                continue
            vt, _ = _extract_vt(f, vt_list)
            trk = _extract_track(f, tracks, _track_patterns)
            # When only one side is detectable, fall back to a default so a
            # missing VT/track token in the filename doesn't drop the file
            # entirely — this used to hide whole track directories when
            # library filenames didn't encode VT.
            if not trk and vt:
                trk = tracks[0] if tracks else 'default'
            if trk and not vt:
                vt = vt_list[0] if vt_list else 'default'
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
            # 1) Dir-based classification wins.
            _cat = _category_for_path(fpath)
            if _cat == 'memory':  lef_memory.append(fpath); continue
            if _cat == 'io':      lef_io.append(fpath);     continue
            if _cat == 'analog':  lef_analog.append(fpath); continue
            if _cat == 'ip':      lef_ip.append(fpath);     continue
            # 2) Fallback filename substring.
            if 'memory' in fl or 'mem' in fl:
                lef_memory.append(fpath)
                continue
            if '_io' in fl or 'io.' in fl:
                lef_io.append(fpath)
                continue
            if 'analog' in fl or '_ana_' in fl:
                lef_analog.append(fpath)
                continue
            if '_ip_' in fl or fl.startswith('ip_'):
                lef_ip.append(fpath)
                continue
            vt, _ = _extract_vt(f, vt_list)
            trk = _extract_track(f, tracks, _track_patterns)
            if not trk and vt:
                trk = tracks[0] if tracks else 'default'
            if trk and not vt:
                vt = vt_list[0] if vt_list else 'default'
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
            # Fall back to defaults when either side is missing — libraries
            # with only one VT flavor or where the filename omits the VT
            # token (encoded via directory) should still be catalogued.
            if not trk and vt:
                trk = tracks[0] if tracks else 'default'
            if trk and not vt:
                vt = vt_list[0] if vt_list else 'default'

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

    # ── Scan category-specific .lib/.db (memory, io, analog, ip) ──
    # Each category has a single flat directory list (not keyed by track/VT)
    # because these macros are typically delivered as unified units with
    # corner suffixes encoding the PVT.
    _cat_bucket = {
        'memory': (timing_memory, lib_nom_memory, db_memory),
        'io':     (timing_io,     lib_nom_io,     db_io),
        'analog': (timing_analog, lib_nom_analog, db_analog),
        'ip':     (timing_ip,     lib_nom_ip,     db_ip),
    }
    for cat, dirs_list in (('memory', memory_dirs), ('io', io_dirs),
                           ('analog', analog_dirs), ('ip', ip_dirs)):
        tdict, nom_list, db_list = _cat_bucket[cat]
        for cat_dir in dirs_list:
            if not os.path.isdir(cat_dir):
                continue
            for f in sorted(os.listdir(cat_dir)):
                fpath = os.path.join(cat_dir, f)
                if _is_excluded(fpath):
                    excluded_count += 1; continue
                if _is_db_file(f):
                    db_list.append(fpath)
                    continue
                if not _is_lib_file(f):
                    continue
                base_name, _ = _strip_lib_extension(f)
                corner = _extract_corner(base_name)
                if corner:
                    tdict[corner].append(fpath)
                    discovered_corners.add(corner)
                else:
                    nom_list.append(fpath)

    # ── Sort discovered sets ──
    def _track_sort_key(t):
        try:
            return float(t.replace('T', '').replace('P', '.'))
        except ValueError:
            return 0.0
    all_tracks = sorted(discovered_tracks, key=_track_sort_key)
    if tracks:
        declared = set(tracks)
        extra   = discovered_tracks - declared
        missing = declared - discovered_tracks
        overlap = discovered_tracks & declared
        # Warn about mismatches — but include ALL discovered tracks so the
        # user's actual libraries are catalogued. Silently intersecting
        # with tech(tracks_available) was hiding real libs when the config
        # was out of date (e.g. gf_22nm declares 9T/7.5T/8T but disk has 6T).
        if extra:
            logger.warning(
                "Discovered tracks {} not in tech(tracks_available) {}. "
                "Cataloging them anyway — update tech_config to declare them "
                "if they're real.".format(sorted(extra), sorted(declared)))
        if missing:
            logger.warning(
                "tech(tracks_available) lists {} but no libraries were "
                "found for {}.".format(sorted(declared), sorted(missing)))
        if not overlap and not extra:
            # Tracks are mandatory for stdcell scans. For add-mode on a
            # non-stdcell category (analog / ip / memory / io), tracks are
            # legitimately absent — those blocks aren't track-keyed.
            _add_cat = (getattr(args, 'category', None)
                        if getattr(args, '_add_mode', False) else None)
            if _add_cat and _add_cat != 'stdcell':
                logger.info(
                    "No tracks matched for --category={} (track-agnostic — "
                    "scan continues).".format(_add_cat))
            else:
                logger.error(
                    "No tracks matched. tech(tracks_available)={} but nothing "
                    "on disk matches. Check --lib-root and file naming.".format(
                        sorted(declared)))
                return 1
        # Order: declared-and-found first (in tech_config order), then extras
        all_tracks = ([t for t in tracks if t in discovered_tracks]
                      + sorted(extra, key=_track_sort_key))
    all_vts = [v for v in vt_list if v in discovered_vts]
    all_corners = sorted(discovered_corners)

    if not all_tracks:
        # In add-mode we only need tracks if the user is adding stdcell libs.
        # Memory/io/analog/ip libs are track-agnostic — a late-arriving
        # analog IP shouldn't have to pretend it has a track.
        _add_cat = getattr(args, 'category', None) if getattr(args, '_add_mode', False) else None
        if _add_cat and _add_cat != 'stdcell':
            logger.info("No tracks (category={} is track-agnostic — OK)".format(_add_cat))
        else:
            logger.error("No tracks discovered. Check --lib-root directory structure "
                         "and confirm library filenames encode the track (e.g. '9T', '6T').")
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

    # ── Tag directory materialization (2026-10-10 layout) ──
    #
    # Preamble `lines` already contains the vendor-absolute `tech(...)`
    # entries. From this point we discard them and re-emit using LOCAL
    # paths rooted at `$_lib_tag_dir`, so the tag directory is relocatable
    # and `lib_config.tcl` doesn't dangle when the vendor delivery is
    # moved. The vendor-abs paths are recorded in MANIFEST.tcl for audit.

    tag = args.tag if hasattr(args, 'tag') and args.tag else None
    output_path = getattr(args, 'output', None)
    if not tag and not output_path:
        logger.error("--tag is required (e.g., --tag P0, --tag timing_v1)")
        logger.error("Output: <tech_dir>/<TAG>/lib_config.tcl")
        return 1

    # --output <path> is a developer escape hatch: write a single flat
    # file at that path with the old vendor-abs shape. Does NOT create a
    # tag dir — reserved for debug / scripting.
    if output_path and not tag:
        output_text = "\n".join(lines) + "\n"
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        with open(output_path, 'w') as fh:
            fh.write(output_text)
        logger.info("Flat output written to: {}".format(output_path))
        return 0

    # Tech config dir (where tech_config.tcl lives — still in global).
    tech_dir = _resolve_tech_dir(tech_name, version)
    if not tech_dir:
        logger.error("Cannot locate tech dir for {} (CBFLOW_GLOBAL_DIR not set?)".format(tech_name))
        return 1

    # Resolve the EXTERNAL lib_tag_root (post 2026-10-14 externalization).
    # Lives OUTSIDE the framework tree so flow updates don't require
    # regenerating libraries. Error-out if unset — user must explicitly
    # declare the site-wide library location.
    _lib_root = _resolve_lib_tag_root(
        tech_name, version,
        project_name=(getattr(args, 'project', None)
                      or os.environ.get('CBFLOW_PROJECT_NAME', '')),
        cli_override=getattr(args, 'lib_tag_root', None))
    if not _lib_root:
        logger.error("")
        for ln in _lib_tag_root_fix_guide(tech_name, version):
            logger.error("  " + ln)
        logger.error("")
        return 1
    try:
        os.makedirs(_lib_root, exist_ok=True)
    except OSError as e:
        logger.error("Cannot create lib_tag_root '{}': {}".format(_lib_root, e))
        return 1
    # Layout: <lib_tag_root>/<tech_node>/<tag>/. Groups every tag for a
    # tech under one dir so lib_config.tcl and mmmc_config.tcl for the
    # same (tech, tag) live together — a flat <root>/<tag>/ layout
    # would collide across techs sharing a lib_tag_root.
    tech_scoped_root = os.path.join(_lib_root, tech_name)
    try:
        os.makedirs(tech_scoped_root, exist_ok=True)
    except OSError as e:
        logger.error("Cannot create tech-scoped tag root '{}': {}".format(tech_scoped_root, e))
        return 1
    tag_dir = os.path.join(tech_scoped_root, tag)
    logger.info("Tag directory: {}".format(tag_dir))

    # Auto-migrate legacy flat `lib_config_<tag>.tcl` — detect + log the
    # takeover. The materialize step below rebuilds the tag dir cleanly
    # from the current scan, so we don't try to parse the old file. The
    # old file is deleted at the end once the new tag dir is complete.
    legacy_flat = os.path.join(tech_dir, 'lib_config_{}.tcl'.format(tag))
    migrated_from_flat = os.path.isfile(legacy_flat)
    if migrated_from_flat:
        logger.info("Legacy lib_config_{}.tcl detected — will migrate to {}/".format(
            tag, tag))

    # DB memory/io: scan for .db files in memory/io dirs — needed by the
    # materializer below. This computation used to live in the inline
    # emission block that's been replaced.
    # db_memory/db_io now populated during the main category-scan loop;
    # these local aliases kept for backward-compat variable names below.
    db_mem = db_memory

    # Build the on-disk structure (subdirs + symlinks + MANIFEST + README).
    scan_log = [
        "tracks:  {}".format(" ".join(all_tracks)),
        "vts:     {}".format(" ".join(all_vts)),
        "corners: {}".format(" ".join(all_corners)),
        "NDM: stdcell={} memory={} io={} analog={} ip={}".format(
            len(ndm_libs), len(ndm_memory), len(ndm_io),
            len(ndm_analog), len(ndm_ip)),
        "DB:  stdcell={} memory={} io={} analog={} ip={}".format(
            len(db_libs), len(db_memory), len(db_io),
            len(db_analog), len(db_ip)),
        "LEF: stdcell={} memory={} io={} analog={} ip={}".format(
            len(lef_libs), len(lef_memory), len(lef_io),
            len(lef_analog), len(lef_ip)),
        "timing_libs groups: {}  (track×vt×corner)".format(len(timing_libs)),
    ]
    local_map = _materialize_tag_dir(
        tag_dir=tag_dir,
        tech_name=tech_name,
        tag=tag,
        lib_root=lib_root,
        all_tracks=all_tracks,
        all_vts=all_vts,
        all_corners=all_corners,
        ndm_libs=ndm_libs,
        db_libs=db_libs,
        lef_libs=lef_libs,
        lib_nom_libs=lib_nom_libs,
        timing_libs=timing_libs,
        ndm_memory=ndm_memory,       ndm_io=ndm_io,
        ndm_analog=ndm_analog,       ndm_ip=ndm_ip,
        db_mem=db_memory,            db_io=db_io,
        db_analog=db_analog,         db_ip=db_ip,
        lef_memory=lef_memory,       lef_io=lef_io,
        lef_analog=lef_analog,       lef_ip=lef_ip,
        lib_nom_memory=lib_nom_memory, lib_nom_io=lib_nom_io,
        lib_nom_analog=lib_nom_analog, lib_nom_ip=lib_nom_ip,
        timing_memory=timing_memory, timing_io=timing_io,
        timing_analog=timing_analog, timing_ip=timing_ip,
        scan_log_lines=scan_log,
        preserve_other_categories=(getattr(args, 'incremental', False)
                                   or getattr(args, '_add_mode', False)),
    )

    # ── Emit lib_config.tcl using LOCAL tag-relative paths ───────────────
    # `$_lib_tag_dir` anchors to this file's own directory via
    # `[file dirname [info script]]`, so the whole tag dir is movable.
    new_lines = []
    def nw(s):
        new_lines.append(s)

    nw("#!/usr/bin/env tclsh")
    nw("# " + "=" * 77)
    nw("# AUTO-GENERATED by: cbflow flow library-manager generate")
    nw("# Tech: {}  |  Tag: {}  |  Generated: {}".format(
        tech_name, tag, datetime.now().strftime("%Y-%m-%d %H:%M")))
    nw("# Source lib_root: {}".format(lib_root))
    nw("# Tracks: {}  |  VTs: {}  |  Corners: {}".format(
        " ".join(all_tracks), " ".join(all_vts), len(all_corners)))
    nw("# ")
    nw("# Paths below are LOCAL to this file via $_lib_tag_dir. The actual")
    nw("# vendor-source target of every symlink is recorded in MANIFEST.tcl.")
    nw("# To relocate: `mv {} <new>` moves lib_config + every linked file".format(tag))
    nw("# with it. To regenerate: cbflow flow library-manager generate ...")
    nw("# " + "=" * 77)
    nw("")
    nw("# Anchor every path to this file's directory so the tag is portable.")
    nw("set _lib_tag_dir [file dirname [file normalize [info script]]]")
    nw("")

    def _fmt_list(key_tuple):
        """Lookup local paths for a key tuple; return formatted TCL list
        or an empty string if the materializer had nothing to link."""
        paths = local_map.get(key_tuple, [])
        if not paths:
            return ""
        return " ".join('"{}"'.format(p) for p in paths)

    # NDM per track per VT (local)
    nw("# ── NDM per track per VT ──")
    for trk in all_tracks:
        for vt in all_vts:
            v = _fmt_list((trk, vt, 'ndm'))
            if v:
                nw('set tech({},{},ndm) [list {}]'.format(trk, vt, v))
    nw("")

    nw("# ── NDM shared (memory / io / analog / ip) ──")
    for cat in ('memory', 'io', 'analog', 'ip'):
        nw('set tech(ndm,{}) [list {}]'.format(cat, _fmt_list((cat, 'ndm'))))
    nw("")

    nw("# ── NDM combined per track (all VTs + every shared category) ──")
    for trk in all_tracks:
        combined = []
        for vt in all_vts:
            combined.extend(local_map.get((trk, vt, 'ndm'), []))
        for cat in ('memory', 'io', 'analog', 'ip'):
            combined.extend(local_map.get((cat, 'ndm'), []))
        nw('set tech({},ndm) [list {}]'.format(
            trk, " ".join('"{}"'.format(p) for p in combined)))
    nw("")

    # DB
    nw("# ── DB per track per VT ──")
    for trk in all_tracks:
        for vt in all_vts:
            v = _fmt_list((trk, vt, 'db'))
            if v:
                nw('set tech({},{},db) [list {}]'.format(trk, vt, v))
    nw("")
    nw("# ── DB shared ──")
    for cat in ('memory', 'io', 'analog', 'ip'):
        nw('set tech(db,{}) [list {}]'.format(cat, _fmt_list((cat, 'db'))))
    nw("")
    nw("# ── DB combined per track ──")
    for trk in all_tracks:
        combined = []
        for vt in all_vts:
            combined.extend(local_map.get((trk, vt, 'db'), []))
        for cat in ('memory', 'io', 'analog', 'ip'):
            combined.extend(local_map.get((cat, 'db'), []))
        nw('set tech({},db) [list {}]'.format(
            trk, " ".join('"{}"'.format(p) for p in combined)))
    nw("")

    # lib_nom
    nw("# ── lib_nom per track per VT ──")
    for trk in all_tracks:
        for vt in all_vts:
            v = _fmt_list((trk, vt, 'lib_nom'))
            if v:
                nw('set tech({},{},lib_nom) [list {}]'.format(trk, vt, v))
    nw("")
    nw("# ── lib_nom shared ──")
    for cat in ('memory', 'io', 'analog', 'ip'):
        nw('set tech(lib_nom,{}) [list {}]'.format(
            cat, _fmt_list((cat, 'lib_nom'))))
    nw("")
    nw("# ── lib_nom combined per track (all VTs + every shared category) ──")
    # Fallback: when there's no explicit lib_nom per VT (vendors often ship
    # only timing libs per corner), use the TT nominal corner timing lib
    # (room temperature preferred) as the nominal library.
    _nom_corner = None
    for _c in all_corners:
        if _c.startswith('tt') and '25c' in _c:
            _nom_corner = _c; break
    if not _nom_corner:
        for _c in all_corners:
            if _c.startswith('tt'):
                _nom_corner = _c; break
    for trk in all_tracks:
        combined = []
        for vt in all_vts:
            explicit = local_map.get((trk, vt, 'lib_nom'), [])
            if explicit:
                combined.extend(explicit)
            elif _nom_corner:
                combined.extend(local_map.get(
                    (trk, vt, _nom_corner, 'lib_timing'), []))
        for cat in ('memory', 'io', 'analog', 'ip'):
            cat_nom = local_map.get((cat, 'lib_nom'), [])
            if cat_nom:
                combined.extend(cat_nom)
            elif _nom_corner:
                combined.extend(local_map.get(
                    (cat, _nom_corner, 'lib_timing'), []))
        nw('set tech({},lib_nom) [list {}]'.format(
            trk, " ".join('"{}"'.format(p) for p in combined)))
    nw("")

    # LEF
    nw("# ── LEF per track per VT ──")
    for trk in all_tracks:
        for vt in all_vts:
            v = _fmt_list((trk, vt, 'lef'))
            if v:
                nw('set tech({},{},lef) [list {}]'.format(trk, vt, v))
    nw("")
    nw("# ── LEF shared ──")
    for cat in ('memory', 'io', 'analog', 'ip'):
        nw('set tech(lef,{}) [list {}]'.format(cat, _fmt_list((cat, 'lef'))))
    nw("")
    nw("# ── LEF combined per track ──")
    for trk in all_tracks:
        combined = []
        for vt in all_vts:
            combined.extend(local_map.get((trk, vt, 'lef'), []))
        for cat in ('memory', 'io', 'analog', 'ip'):
            combined.extend(local_map.get((cat, 'lef'), []))
        nw('set tech({},lef) [list {}]'.format(
            trk, " ".join('"{}"'.format(p) for p in combined)))
    nw("")

    # Corners discovered
    nw("# ── Corners discovered ──")
    nw('set tech(corners) {{{}}}'.format(" ".join(all_corners)))
    nw("")

    # Timing libs per track per VT per corner
    nw("# ── Timing libs per track per VT per corner ──")
    for trk in all_tracks:
        for corner in all_corners:
            for vt in all_vts:
                v = _fmt_list((trk, vt, corner, 'lib_timing'))
                if v:
                    nw('set tech({},{},lib,{},timing) [list {}]'.format(
                        trk, vt, corner, v))
    nw("")

    nw("# ── Timing libs shared per corner (memory / io / analog / ip) ──")
    for corner in all_corners:
        for cat in ('memory', 'io', 'analog', 'ip'):
            nw('set tech(lib,{},timing,{}) [list {}]'.format(
                corner, cat, _fmt_list((cat, corner, 'lib_timing'))))
    nw("")

    nw("# ── Timing combined per track per corner ──")
    for trk in all_tracks:
        for corner in all_corners:
            combined = []
            for vt in all_vts:
                combined.extend(local_map.get((trk, vt, corner, 'lib_timing'), []))
            combined.extend(local_map.get(('memory', corner, 'lib_timing'), []))
            combined.extend(local_map.get(('io', corner, 'lib_timing'), []))
            if combined:
                nw('set tech({},lib,{},timing) [list {}]'.format(
                    trk, corner, " ".join('"{}"'.format(p) for p in combined)))
    nw("")

    output_text = "\n".join(new_lines) + "\n"
    output_path = os.path.join(tag_dir, 'lib_config.tcl')

    # ── Incremental merge (--incremental or `add` subcommand) ────────────
    # Three-way merge rule per tech(KEY):
    #   1. If new has non-empty value → new wins
    #   2. If new has empty-list value AND old has non-empty value → keep old
    #   3. If new absent → keep old
    # Rule 2 is critical for `add --category ip`: that scan emits
    # `tech(ndm,analog) [list ]` (because this scan found no analog), but
    # the tag already has analog content from a prior `add --category
    # analog`. Clobbering with an empty list would silently drop analog
    # from the config.
    incremental = getattr(args, 'incremental', False) or getattr(args, '_add_mode', False)
    if incremental and os.path.exists(output_path):
        # Index new lines by key, detect empty-list emissions.
        _empty_re = re.compile(r'set\s+tech\(([^)]+)\)\s+\[list\s*\]\s*$')
        _nonempty_re = re.compile(r'set\s+tech\(([^)]+)\)')
        new_nonempty_keys = set()
        new_empty_keys = set()
        new_lineno_by_key = {}  # key → index in new_lines (for replacement)
        for i, line in enumerate(new_lines):
            stripped = line.strip()
            if _empty_re.match(stripped):
                m = _empty_re.match(stripped)
                new_empty_keys.add(m.group(1))
                new_lineno_by_key[m.group(1)] = i
            else:
                m = _nonempty_re.match(stripped)
                if m:
                    new_nonempty_keys.add(m.group(1))
                    new_lineno_by_key[m.group(1)] = i

        retained = []
        with open(output_path, 'r') as ef:
            for ln in ef:
                stripped = ln.strip()
                m = _nonempty_re.match(stripped)
                if not m:
                    continue
                key = m.group(1)
                # Non-empty old value for a key the new scan emitted empty →
                # replace the empty new line in-place so the final order
                # stays organized under the proper section header.
                is_old_empty = bool(_empty_re.match(stripped))
                if key in new_empty_keys and not is_old_empty:
                    new_lines[new_lineno_by_key[key]] = ln.rstrip()
                elif key not in new_nonempty_keys and key not in new_empty_keys:
                    retained.append(ln.rstrip())

        if retained:
            new_lines.append("")
            new_lines.append("# ── Retained from previous lib_config (incremental merge) ──")
            new_lines.extend(retained)
            logger.info("Incremental: retained {} entries + preserved non-empty values".format(
                len(retained)))
        output_text = "\n".join(new_lines) + "\n"

    # Atomic rewrite — pre-fix, open-w truncate destroyed the entire
    # tech lib_config.tcl + the retention-merge computation above if the
    # process died mid-write. Subsequent flow runs crashed with
    # 'tech(...) not set' and the retained custom entries were lost.
    atomic_write(output_path, output_text)

    # Final step: remove the legacy flat file so the directory is the
    # single source of truth. Leaves a .migrated-to-dir marker in logs/
    # so an audit can tell where it went.
    if migrated_from_flat and os.path.isfile(legacy_flat):
        try:
            os.remove(legacy_flat)
            with open(os.path.join(tag_dir, 'logs', 'migrated_from_flat.txt'),
                      'w') as fh:
                fh.write("Legacy lib_config_{}.tcl was removed on {}.\n".format(
                    tag, datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
                fh.write("The tag directory '{}/' is now the single source of truth.\n".format(tag))
        except OSError as e:
            logger.warning("Could not remove legacy {}: {}".format(legacy_flat, e))

    # ── Discovery report ──
    total_stdcell_timing = len(timing_libs)

    # Effective lib_nom = EXPLICIT nominal libs if any, else the TT-corner
    # fallback library-manager uses when generating lib_config.tcl. The
    # discovery report must show the EFFECTIVE count — otherwise `lib_nom
    # = 0` on a tree that has a TT corner misleads the user into thinking
    # downstream flows will have nothing to use for nominal corner.
    #
    # The generated lib_config emits `tech(<track>,lib_nom)` from TT libs
    # when no explicit nominal exists (see cmd_generate's lib_nom emit).
    # Match that logic here.
    def _effective_nom_count(explicit_dict, timing_dict, per_track_vt=True):
        """Return effective lib_nom count for a category.
          explicit_dict  — the lib_nom_* dict (keyed on (track,vt) or similar)
          timing_dict    — the timing_* dict (keyed on (track,vt,corner))
          per_track_vt   — True = count unique (track,vt) pairs,
                           False = count TT-corner entries directly.
        """
        if explicit_dict:
            return sum(len(v) for v in explicit_dict.values()) \
                if hasattr(explicit_dict, 'values') else len(explicit_dict)
        # Fallback: TT-corner libs for this category.
        if hasattr(timing_dict, 'keys'):
            if per_track_vt:
                tt_track_vts = {(k[0], k[1]) for k in timing_dict.keys()
                                if len(k) >= 3 and str(k[2]).lower().startswith('tt')}
                return len(tt_track_vts)
            else:
                return sum(len(v) for k, v in timing_dict.items()
                           if str(k).lower().startswith('tt'))
        return 0

    stdcell_nom_eff = _effective_nom_count(lib_nom_libs, timing_libs, True)
    mem_nom_eff     = _effective_nom_count(lib_nom_memory, timing_memory, False)
    io_nom_eff      = _effective_nom_count(lib_nom_io,     timing_io,     False)
    analog_nom_eff  = _effective_nom_count(lib_nom_analog, timing_analog, False)
    ip_nom_eff      = _effective_nom_count(lib_nom_ip,     timing_ip,     False)

    # Per-category view counts — rows = categories, cols = view kinds.
    # Each cell holds the number of libs/files discovered for that
    # (category, kind) combination. Lets us flag:
    #   · categories the user explicitly asked for that found nothing
    #   · categories with partial coverage (has .lib but no .ndm — breaks PnR)
    #   · timing-corner holes per category (not just memory/io)
    _CAT_VIEW_COUNTS = {
        'stdcell': {'ndm': len(ndm_libs), 'db': len(db_libs),
                    'lef': len(lef_libs), 'lib_nom': stdcell_nom_eff,
                    'timing': total_stdcell_timing},
        'memory':  {'ndm': len(ndm_memory), 'db': len(db_memory),
                    'lef': len(lef_memory), 'lib_nom': mem_nom_eff,
                    'timing': sum(len(v) for v in timing_memory.values())},
        'io':      {'ndm': len(ndm_io), 'db': len(db_io),
                    'lef': len(lef_io), 'lib_nom': io_nom_eff,
                    'timing': sum(len(v) for v in timing_io.values())},
        'analog':  {'ndm': len(ndm_analog), 'db': len(db_analog),
                    'lef': len(lef_analog), 'lib_nom': analog_nom_eff,
                    'timing': sum(len(v) for v in timing_analog.values())},
        'ip':      {'ndm': len(ndm_ip), 'db': len(db_ip),
                    'lef': len(lef_ip), 'lib_nom': ip_nom_eff,
                    'timing': sum(len(v) for v in timing_ip.values())},
    }
    # Track whether each category's lib_nom came from explicit files
    # or TT fallback (for the footer legend).
    _CAT_NOM_SOURCE = {
        'stdcell': 'explicit' if lib_nom_libs    else 'TT-fallback',
        'memory':  'explicit' if lib_nom_memory  else 'TT-fallback',
        'io':      'explicit' if lib_nom_io      else 'TT-fallback',
        'analog':  'explicit' if lib_nom_analog  else 'TT-fallback',
        'ip':      'explicit' if lib_nom_ip      else 'TT-fallback',
    }
    _nom_fallback_used = any(src == 'TT-fallback'
                             and _CAT_VIEW_COUNTS[cat]['lib_nom'] > 0
                             for cat, src in _CAT_NOM_SOURCE.items())
    # Whether the user explicitly asked for each category via CLI.
    # Analog + IP are never implicitly populated — if the user DIDN'T ask
    # and nothing was found, that's expected, not a warning.
    _CAT_ASKED = {
        'stdcell': True,  # always expected
        'memory':  bool(getattr(args, 'memory_path', None) or True),
        'io':      bool(getattr(args, 'io_path', None) or True),
        'analog':  bool(getattr(args, 'analog_path', None)),
        'ip':      bool(getattr(args, 'ip_path', None)),
    }
    # Timing-corner missing per category (expanded from the old
    # memory+io-only check).
    _per_cat_timing = {
        'memory': timing_memory, 'io': timing_io,
        'analog': timing_analog, 'ip': timing_ip,
    }
    _missing_corners_per_cat = {}
    for cat, timing_dict in _per_cat_timing.items():
        if _CAT_VIEW_COUNTS[cat]['timing'] == 0 and not _CAT_ASKED[cat]:
            continue  # not requested, don't scold
        _missing_corners_per_cat[cat] = [c for c in all_corners
                                         if c not in timing_dict]

    print("")
    print("=" * 60)
    print("  Library Discovery Report — {}".format(tech_name))
    print("=" * 60)
    if excluded_count > 0:
        print("  Excluded:  {} files (patterns: {})".format(
            excluded_count, ", ".join(exclude_patterns)))
    print("  Tracks:    {}".format(" ".join(all_tracks)))
    print("  VTs:       {}".format(" ".join(all_vts)))
    print("  Corners:   {}".format(len(all_corners)))
    print("")

    # ── Per-category view coverage table ──────────────────────────────
    # Per-category view counts. LEF here is the PER-CATEGORY cell/macro
    # LEF (stdcell, memory, io, analog, ip) — one per cell or per
    # (track, VT). Tech LEFs (the metal-stack definition files) are a
    # separate class entirely: they're declared directly in
    # tech_config.tcl as `tech(<stack>,<track>,lef_tech)` and surfaced
    # by `cbflow flow library-manager status`. Do not conflate the two.
    _nom_hdr = 'lib_nom*' if _nom_fallback_used else 'lib_nom'
    print("  {:<9s} {:>5s} {:>5s} {:>5s} {:>8s} {:>8s}".format(
        'Category', 'NDM', 'DB', 'LEF', _nom_hdr, 'timing'))
    print("  " + "-" * 55)
    for cat in ('stdcell', 'memory', 'io', 'analog', 'ip'):
        counts = _CAT_VIEW_COUNTS[cat]
        nom_cell = '{:>8d}'.format(counts['lib_nom'])
        if (counts['lib_nom'] > 0
                and _CAT_NOM_SOURCE[cat] == 'TT-fallback'):
            nom_cell = '{:>7d}*'.format(counts['lib_nom'])
        print("  {:<9s} {:>5d} {:>5d} {:>5d} {} {:>8d}".format(
            cat, counts['ndm'], counts['db'], counts['lef'],
            nom_cell, counts['timing']))
    print("")
    print("  Note: LEF column counts cell/macro LEFs per category only. "
          "Tech LEFs (metal-stack")
    print("        files) are tracked separately via "
          "`cbflow flow library-manager status`.")
    if _nom_fallback_used:
        print("    *   lib_nom auto-derived from the TT corner (no explicit "
              "*_nom.lib found).")
    print("")

    # ── Per-category warnings ─────────────────────────────────────────
    # A category with zero libs that was explicitly asked for is a hard
    # warning. A category with partial coverage (has lib but no ndm,
    # etc.) breaks downstream flows.
    _warnings = []
    for cat in ('stdcell', 'memory', 'io', 'analog', 'ip'):
        counts = _CAT_VIEW_COUNTS[cat]
        any_view = any(counts[v] for v in counts)
        if not any_view:
            if _CAT_ASKED[cat] and cat not in ('memory', 'io'):
                # User asked for this (--analog-path/--ip-path) but got nothing.
                _warnings.append(
                    "{} category: 0 libs found — the --{}-path(s) you "
                    "passed resolved to no .lib/.ndm/.lef files. Check the "
                    "paths exist and contain libraries.".format(cat, cat))
            continue
        # Partial coverage check — flag kinds that are missing when at
        # least one kind is populated. Caveats:
        #   · lib_nom is NOT flagged when it was effectively populated
        #     via the TT-corner fallback (shown in the table as `n*`).
        #   · cellLEF (= 'lef' key) is flagged with a softer message
        #     — ICC2 doesn't need it since the NDM bundles the abstract,
        #     only Innovus / Calibre antenna do. Don't scare users off
        #     an ICC2 flow with 'will fail on signoff'.
        empty_kinds = []
        for v in ('ndm', 'db', 'lef', 'lib_nom', 'timing'):
            if counts[v] > 0:
                continue
            if v == 'lib_nom' and counts['lib_nom'] > 0:
                continue  # already handled above (table shows TT fallback)
            empty_kinds.append(v)
        if empty_kinds:
            # Separate cellLEF from the hard-missing set so the message
            # is tool-aware.
            hard_missing = [k for k in empty_kinds if k != 'lef']
            lef_missing  = ('lef' in empty_kinds)
            if hard_missing:
                _warnings.append(
                    "{} category: partial coverage — missing {}. "
                    "Downstream flows that need these view(s) will fail "
                    "on signoff.".format(cat, ", ".join(hard_missing)))
            if lef_missing:
                _warnings.append(
                    "{} category: no cell LEFs found. "
                    "Required for Innovus P&R + Calibre antenna. "
                    "ICC2 / FusionCompiler flows are OK — the NDM "
                    "bundles the LEF abstract.".format(cat))

    # Per-category timing-corner coverage.
    for cat, missing in _missing_corners_per_cat.items():
        n_corners = len(all_corners)
        if n_corners == 0:
            continue
        ok_count = n_corners - len(missing)
        sym = "ok" if not missing else "MISSING"
        print("  {:<9s} corners: {}/{} {}".format(cat, ok_count, n_corners, sym))
        if missing and (_CAT_VIEW_COUNTS[cat]['timing'] > 0 or _CAT_ASKED[cat]):
            for c in missing:
                print("    MISSING: {} timing corner {}".format(cat, c))
    print("")

    if _warnings:
        print("  " + "─" * 56)
        print("  WARNINGS")
        print("  " + "─" * 56)
        for w in _warnings:
            print("  ! " + w)
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


# ─── Helpers shared across status / other Tcl-parsing commands ───────────
_SAFE_NAME_RE = re.compile(r'^[A-Za-z0-9_.-]+$')


def _sanitize_name_arg(name: str, kind: str) -> str:
    """Reject `..`, slashes, shell metachars in a name that's about to be
    joined into a filesystem path. Prevents `--tech ../../etc` path
    traversal into the config tree."""
    if not name or not _SAFE_NAME_RE.match(name):
        raise ValueError(f'invalid {kind} name {name!r} — must match [A-Za-z0-9_.-]+')
    return name


def _tcl_list_from(content: str, arr: str, key: str) -> List[str]:
    """Extract a Tcl list from `set <arr>(<key>) {...}` OR `"..."` form.

    Both forms are used in shipped configs — accept both so a value
    written as `{svt lvt hvt}` isn't silently ignored by a quote-only
    regex.
    """
    m = re.search(
        rf'set\s+{re.escape(arr)}\({re.escape(key)}\)\s+\{{([^}}]+)\}}',
        content
    )
    if not m:
        m = re.search(
            rf'set\s+{re.escape(arr)}\({re.escape(key)}\)\s+"([^"]+)"',
            content
        )
    return m.group(1).split() if m else []


def cmd_status(args: argparse.Namespace) -> int:
    """Signoff-readiness report for a tech's library configuration.

    Reads tech_config.tcl (+ lib_config.tcl if present) and reports:
      - Available VT flavors (`tech(vt_variants_available)`)
      - Project-enabled VTs (`project(vt_flavors)` — if --project given)
      - LEF-tech per (metal_stack, track)
      - RCX per (metal_stack, rc_corner) × {tluplus, nxtgrd, qrc}
      - Timing/NDM per (track, VT) — from lib_config.tcl if present
      - Dont_use masks per track

    Multi-VT / multi-metal-stack aware: with --project, the verdict
    only counts coverage for the metal stack the project actually uses
    (`project(metal_stack)`) and only for the VTs the project has
    enabled (`project(vt_flavors)`). Without --project, the full
    declared axes are checked.
    """
    # --tech-config overrides --tech. Derive the tech name from the
    # path convention when the user passes an explicit tech_config
    # path so cmd_status works outside the flow dir.
    _tc_override = getattr(args, 'tech_config', None)
    if _tc_override and not args.tech:
        from core.paths import tech_name_from_config_path
        _derived = tech_name_from_config_path(_tc_override)
        if _derived:
            args.tech = _derived
    if not args.tech:
        logger.error("--tech or --tech-config is required")
        return 1
    # Sanitize path args before joining into core_dir paths.
    try:
        tech_name = _sanitize_name_arg(args.tech, 'tech')
    except ValueError as e:
        logger.error(str(e))
        return 1
    version = getattr(args, 'version', None) or 'v1.0.0'
    try:
        version = _sanitize_name_arg(version, 'version')
    except ValueError as e:
        logger.error(str(e))
        return 1

    # tech_config resolved via cascade helper (global first, PD fallback).
    # Reads both global + PD-overlay contents so status can report across
    # foundry data AND PD-specific metal/cell choices.
    tech_config = require_tech_config(tech_name, version)
    core_dir = get_cbflow_core_dir()
    # cmd_status reports on whichever tag is `project(lib_config_tag)` or the
    # first one it finds. Post 2026-10-10 the lib_config lives inside
    # <tech_dir>/<tag>/lib_config.tcl; fall back to legacy flat form.
    _preferred_tag = (getattr(args, 'tag', None)
                      or os.environ.get('CBFLOW_LIB_CONFIG_TAG', ''))
    _avail_tags = _list_available_tags(tech_name, version)
    _status_tag = _preferred_tag if _preferred_tag in _avail_tags else (
        _avail_tags[0] if _avail_tags else '')
    lib_config = (_resolve_lib_config_path(tech_name, _status_tag, version)
                  if _status_tag else '')

    # Read the concatenation of global tech_config + PD tech_pd_config so
    # legacy regex-parsers see the same key set the resolver would.
    from core.paths import get_tech_config_paths
    tc_parts = []
    for _p in get_tech_config_paths(tech_name, version):
        with open(_p) as f:
            tc_parts.append(f.read())
    tc = "\n".join(tc_parts)

    # ── Section 1: VT availability + project enablement ──
    available_vts = _tcl_list_from(tc, 'tech', 'vt_variants_available')
    vt_patterns = {}
    for m in re.finditer(r'set\s+tech\(vt_pattern,(\w+)\)\s+"([^"]+)"', tc):
        vt_patterns[m.group(1)] = m.group(2)
    metal_stacks_all = _tcl_list_from(tc, 'tech', 'metal_stacks_available')
    tracks_all = _tcl_list_from(tc, 'tech', 'tracks_available')

    # Build metal-stack regex dynamically from the declared tokens
    # (hardcoding `[0-9]+M` silently dropped techs using `1p8M`,
    # `stack_a`, etc.). Falls back to `[A-Za-z0-9]+M?` so shipped
    # `\d+M` configs still work if no list is declared.
    if metal_stacks_all:
        _ms_alt = '|'.join(re.escape(ms) for ms in metal_stacks_all)
    else:
        _ms_alt = r'[A-Za-z0-9]+M?'

    project_name = None
    try:
        project_name = getattr(args, 'project', None) or os.environ.get('CBFLOW_PROJECT_NAME')
        if project_name:
            project_name = _sanitize_name_arg(project_name, 'project')
    except ValueError as e:
        logger.error(str(e))
        return 1

    project_vts: List[str] = []
    project_metal_stack = ''    # Scope LEF/RCX verdict to this
    project_tracks: List[str] = []
    if project_name:
        # Walk global/ identity then PD/ overlay — concat contents so values
        # from either side are picked up (overlay wins on key collision).
        # Post 2026-11-01 rename: files are <project>_config.tcl (global)
        # and <project>_pd_config.tcl (PD overlay).
        from core.paths import (
            get_cbflow_global_dir, project_config_basename,
            project_discipline_config_basename,
        )
        _candidates = []
        _g = get_cbflow_global_dir()
        if _g:
            _candidates.append(os.path.join(
                _g, 'config', 'project', project_name, version,
                project_config_basename(project_name)))
        _candidates.append(os.path.join(
            core_dir, 'config', 'project', project_name, version,
            project_discipline_config_basename(project_name, 'pd')))
        _candidates.append(os.path.join(
            core_dir, 'config', 'project', project_name, version,
            f'{project_name}_config.tcl'))
        pc = ''
        for proj_config in _candidates:
            if os.path.exists(proj_config):
                with open(proj_config) as f:
                    pc += f.read() + '\n'
        if pc:
            # Accept both `"..."` and `{...}` forms.
            project_vts = _tcl_list_from(pc, 'project', 'vt_flavors')
            _pm = re.search(r'set\s+project\(metal_stack\)\s+"?([A-Za-z0-9._-]+)"?', pc)
            if _pm:
                project_metal_stack = _pm.group(1).strip()
            # Some projects declare a preferred track set.
            project_tracks = _tcl_list_from(pc, 'project', 'tracks')

    # ── Section 2: LEF-tech coverage per (metal_stack, track) ──
    lef_present = set()
    for m in re.finditer(rf'set\s+tech\(({_ms_alt}),([0-9.]+T),lef_tech\)', tc):
        lef_present.add((m.group(1), m.group(2)))

    # ── Section 3: RCX per (metal_stack, rc_corner, format) ──
    rcx_present = {}   # (ms, rc) → set of formats present
    for m in re.finditer(rf'set\s+tech\(rcx,({_ms_alt}),(rc_\w+),(tluplus|nxtgrd|qrc)\)', tc):
        rcx_present.setdefault((m.group(1), m.group(2)), set()).add(m.group(3))

    # ── Section 4: Timing / NDM from lib_config.tcl (if generated) ──
    lib_config_present = os.path.exists(lib_config)

    # Warn on stale sibling lib_config.tcl.
    if lib_config_present:
        try:
            if os.path.getmtime(lib_config) < os.path.getmtime(tech_config):
                logger.warning(
                    f'lib_config.tcl is older than tech_config.tcl '
                    f'({os.path.basename(lib_config)} mtime < '
                    f'{os.path.basename(tech_config)}) — data may be stale. '
                    f'Regenerate: cbflow flow library-manager generate --tech {tech_name}'
                )
        except OSError:
            pass

    lib_by_track_vt: Dict[tuple, Dict[str, int]] = {}
    if lib_config_present:
        with open(lib_config) as f:
            lc = f.read()
        # Accept BOTH `[list ...]` and `"..."` forms — the track-schema
        # parser writes the single-quoted-string form so both must be
        # handled or status disagrees with itself.
        _pat_list = re.compile(
            r'set\s+tech\(([0-9.]+T)\s*,\s*(\w+)\s*,\s*(ndm|db|lib)\)\s+\[list\s+(.+?)\]'
        )
        _pat_str = re.compile(
            r'set\s+tech\(([0-9.]+T)\s*,\s*(\w+)\s*,\s*(ndm|db|lib)\)\s+"([^"]+)"'
        )
        for m in _pat_list.finditer(lc):
            trk, vt, kind, raw = m.group(1), m.group(2), m.group(3), m.group(4)
            paths = re.findall(r'"([^"]+)"', raw)
            if paths:
                lib_by_track_vt.setdefault((trk, vt), {})[kind] = \
                    lib_by_track_vt.setdefault((trk, vt), {}).get(kind, 0) + len(paths)
        for m in _pat_str.finditer(lc):
            trk, vt, kind = m.group(1), m.group(2), m.group(3)
            lib_by_track_vt.setdefault((trk, vt), {})[kind] = \
                lib_by_track_vt.setdefault((trk, vt), {}).get(kind, 0) + 1

    # ── Section 5: dont_use per track ──
    dont_use = {}
    for m in re.finditer(r'set\s+tech\(([0-9.]+T),dont_use\)\s+"([^"]+)"', tc):
        dont_use[m.group(1)] = m.group(2)

    # ── Resolve effective axes (project-scoped when possible) ──
    # Filter LEF/RCX/Timing to the project's active metal stack +
    # track subset. Without --project, use the declared full axes.
    if project_metal_stack and project_metal_stack in metal_stacks_all:
        effective_metal_stacks = [project_metal_stack]
    else:
        effective_metal_stacks = metal_stacks_all
        if project_name and project_metal_stack:
            logger.warning(
                f'Project {project_name!r} sets metal_stack={project_metal_stack!r} '
                f'which is not in tech(metal_stacks_available)={metal_stacks_all} '
                f'— using full tech axes for verdict.'
            )
    effective_tracks = project_tracks if project_tracks else tracks_all
    effective_vts = project_vts if project_vts else available_vts

    # ── Render ──
    logger.info('')
    logger.info(f'  Library Manager Status — tech={tech_name} version={version}')
    logger.info(f'  {"=" * 70}')
    logger.info(f'  Source:     {tech_config}')
    if lib_config_present:
        logger.info(f'  lib_config: {lib_config}')
    else:
        logger.info(f'  lib_config: NOT GENERATED (run `library-manager generate`)')
    if project_name:
        scope_ms = project_metal_stack or '(all declared)'
        scope_vt = " ".join(project_vts) if project_vts else '(all available)'
        logger.info(f'  Project:    {project_name}  '
                    f'metal_stack={scope_ms}  vts={scope_vt}')
    logger.info('')

    # VT block
    logger.info('  VT flavors')
    logger.info(f'    Available in tech: {" ".join(available_vts) or "(none declared)"}')
    if project_name and project_vts:
        enabled_set = set(project_vts)
        for vt in available_vts:
            mark = 'ENABLED' if vt in enabled_set else '  off  '
            pat = vt_patterns.get(vt, '?')
            logger.info(f'      {mark}  {vt:<6} pattern={pat}')
        missing_from_tech = [v for v in project_vts if v not in available_vts]
        if missing_from_tech:
            logger.warning(f'    Project enables VTs not in tech: {" ".join(missing_from_tech)}')
    elif project_name:
        logger.info(f'    Project {project_name!r} sets no `vt_flavors` — all available VTs are candidates')
    logger.info('')

    # Metal stack / track block
    logger.info(f'  Metal stacks:  {" ".join(metal_stacks_all) or "(not declared)"}')
    logger.info(f'  Tracks:        {" ".join(tracks_all) or "(not declared)"}')
    logger.info('')

    # Per-axis issue counters (consistent granularity + breakdown)
    lef_missing = 0
    rcx_missing = 0
    timing_missing = 0

    # LEF coverage — iterate effective axes so project scope narrows the report.
    logger.info('  LEF-tech coverage (metal_stack × track)')
    if not effective_metal_stacks or not effective_tracks:
        logger.info('    (metal_stacks / tracks not set — cannot check)')
    else:
        for ms in effective_metal_stacks:
            row = []
            for trk in effective_tracks:
                have = (ms, trk) in lef_present
                if not have:
                    lef_missing += 1
                row.append(f'{trk}={"OK" if have else "MISSING"}')
            logger.info(f'    {ms:<5} {" ".join(row)}')
    logger.info('')

    # RCX coverage — iterate DECLARED axes (from mmmc/tech) so
    # entirely-missing (ms, rc) rows are also flagged.
    # Discover the rc_corners the tech is expected to have from any
    # rcx entry present + a default triad.
    declared_rc_corners = sorted({rc for (_ms, rc) in rcx_present.keys()}
                                 | {'rc_min', 'rc_typ', 'rc_max'})
    all_formats = ('tluplus', 'nxtgrd', 'qrc')
    logger.info('  RCX coverage (metal_stack × rc_corner × format)')
    if not effective_metal_stacks:
        logger.info('    (metal_stacks not set — cannot check)')
    else:
        for ms in effective_metal_stacks:
            for rc in declared_rc_corners:
                fmts = rcx_present.get((ms, rc), set())
                missing_fmts = set(all_formats) - fmts
                if not fmts:
                    marker = 'MISSING: entire (metal_stack, rc_corner) row'
                    rcx_missing += 1
                elif missing_fmts:
                    marker = f'MISSING: {",".join(sorted(missing_fmts))}'
                    rcx_missing += len(missing_fmts)
                else:
                    marker = 'OK'
                fmts_str = ",".join(sorted(fmts)) if fmts else '(none)'
                logger.info(f'    {ms:<5} {rc:<10} formats={fmts_str:<25} {marker}')
    logger.info('')

    # Timing/NDM coverage (from lib_config.tcl)
    logger.info('  Timing/NDM coverage (track × VT — from lib_config.tcl)')
    if not lib_config_present:
        logger.info('    lib_config.tcl not generated — no .lib/.ndm paths declared.')
        logger.info(f'    Generate: cbflow flow library-manager generate --tech {tech_name} \\')
        logger.info(f'                 --lib-root <path/to/vendor/libs>')
        timing_missing = -1   # sentinel: reported as a single lib_config-absent issue
    elif not effective_vts:
        # Empty vt_list would otherwise silently zero-issue.
        logger.error('    ERROR: no VT flavors declared in tech OR project — '
                     'cannot evaluate multi-VT coverage. Set '
                     'tech(vt_variants_available) or project(vt_flavors).')
        timing_missing = -2
    else:
        for trk in effective_tracks:
            for vt in effective_vts:
                counts = lib_by_track_vt.get((trk, vt), {})
                if counts:
                    parts = ' '.join(f'{k}={v}' for k, v in sorted(counts.items()))
                    logger.info(f'    {trk:<5} {vt:<6} {parts}')
                else:
                    # Per-row misses are info, not warning.
                    logger.info(f'    {trk:<5} {vt:<6} MISSING — no ndm/db/lib entries')
                    timing_missing += 1
    logger.info('')

    # Dont_use masks
    if dont_use:
        logger.info('  Dont_use masks per track')
        for trk, mask in sorted(dont_use.items()):
            logger.info(f'    {trk:<5} {mask}')
        logger.info('')

    # ── Verdict (per-axis breakdown) ──
    lib_config_issue = 1 if not lib_config_present else 0
    vt_config_issue = 1 if timing_missing == -2 else 0
    timing_effective = timing_missing if timing_missing >= 0 else 0
    total_issues = lef_missing + rcx_missing + timing_effective + lib_config_issue + vt_config_issue

    logger.info(f'  Per-axis coverage summary:')
    logger.info(f'    LEF-tech:      {lef_missing} missing')
    logger.info(f'    RCX:           {rcx_missing} missing')
    if lib_config_issue:
        logger.info(f'    Timing/NDM:    lib_config.tcl absent (1 issue)')
    elif vt_config_issue:
        logger.info(f'    Timing/NDM:    no VT flavors declared (1 issue)')
    else:
        logger.info(f'    Timing/NDM:    {timing_effective} missing')
    logger.info('')

    if total_issues == 0:
        logger.info('  READY — all declared axes populated. Multi-VT setup complete.')
        return 0
    else:
        # Warn only on the final verdict + one summary line.
        logger.warning(
            f'  NOT READY — {total_issues} issue(s): '
            f'lef={lef_missing} rcx={rcx_missing} '
            f'timing={"lib_config-missing" if lib_config_issue else ("vt-missing" if vt_config_issue else timing_effective)}'
        )
        return 1


def cmd_add(args: argparse.Namespace) -> int:
    """Surgically add one category's libraries to an existing tag.

    Flow:
      1. Verify the tag directory exists (fail if it doesn't — users must
         `generate` before `add`).
      2. Resolve `project(lib_root)` for logging purposes.
      3. Translate (--category <cat>, --path <dirs>) into the equivalent
         `--<cat>-path <dirs>` flags on an args namespace.
      4. Mark `_add_mode=True` so the materializer preserves other
         categories AND the lib_config merger retains their keys.
      5. Delegate to `cmd_generate`.

    Why delegate instead of a fresh scanner? Zero divergence risk. Every
    category's scan logic + materialize code lives in one place; `add`
    is purely a UX wrapper that pre-fills the right flags.
    """
    # --tech-config override: derive tech_name from the path convention.
    _tc_override = getattr(args, 'tech_config', None)
    if _tc_override and not args.tech:
        from core.paths import tech_name_from_config_path
        _derived = tech_name_from_config_path(_tc_override)
        if _derived:
            args.tech = _derived
    if not args.tech:
        logger.error("--tech or --tech-config is required")
        return 1
    tech_name = args.tech
    tag = args.tag
    version = args.version or 'v1.0.0'
    category = args.category

    # Must exist — `add` is explicitly for extending, not creating.
    existing = _resolve_lib_config_path(tech_name, tag, version)
    if not existing:
        # Show the ACTUAL resolved root — the resolver walks lib_tag_root
        # first, then falls back to in-tree legacy only when unset.
        # Pointing at $core_dir/config/tech here used to misdirect users
        # to the pre-refactor PD-only path, which no longer exists.
        _root = _resolve_lib_tag_root(tech_name, version) \
                or _resolve_tech_dir(tech_name, version) \
                or '<unresolved>'
        # Report the current layout first — legacy only kicks in during
        # read-fallback (see _resolve_lib_config_path).
        _looked = os.path.join(_root, tech_name, tag, 'lib_config.tcl')
        logger.error("No existing lib_config for tag '{}'.".format(tag))
        logger.error("  Searched: {}".format(_looked))
        logger.error("`add` extends an existing tag. To create a new tag:")
        logger.error("  cbflow flow library-manager generate --tech {} --tag {} --lib-root <path>".format(
            tech_name, tag))
        return 1

    # Reuse the generate pipeline. We force one category's path arg from
    # --path/--category, leave the others unset so no spurious scans run.
    args.stdcell_path = args.path if category == 'stdcell' else None
    args.memory_path  = args.path if category == 'memory'  else None
    args.io_path      = args.path if category == 'io'      else None
    args.analog_path  = args.path if category == 'analog'  else None
    args.ip_path      = args.path if category == 'ip'      else None

    # `generate` requires --lib-root. For `add`, use the project's lib_root
    # or the first --path as a stand-in — it's only used for logging now
    # that each category has its own explicit path.
    _lib_root = _resolve_lib_root_from_tech_config(tech_name)
    if not _lib_root or not os.path.isdir(_lib_root):
        _lib_root = args.path[0]
    args.lib_root = _lib_root

    # Signal to the generate pipeline: preserve categories we DIDN'T touch,
    # merge instead of overwrite in both MANIFEST and lib_config.tcl.
    args._add_mode = True
    args.incremental = True  # legacy flag — safe idempotent union below

    # Default no-opt args that `cmd_generate` reads.
    if not hasattr(args, 'tracks') or args.tracks is None:
        args.tracks = None
    if not hasattr(args, 'vts') or args.vts is None:
        args.vts = None
    if not hasattr(args, 'exclude') or args.exclude is None:
        args.exclude = []
    args.output = None   # tag-dir mode

    logger.info("ADD mode: category={} tag={} tech={}".format(category, tag, tech_name))
    for p in args.path:
        logger.info("  path: {}".format(p))
    return cmd_generate(args)


def cmd_coverage(args: argparse.Namespace) -> int:
    """Show library coverage matrix: tracks × VTs × corners."""
    # --tech-config override: derive tech_name from the path convention.
    _tc_override = getattr(args, 'tech_config', None)
    if _tc_override and not args.tech:
        from core.paths import tech_name_from_config_path
        _derived = tech_name_from_config_path(_tc_override)
        if _derived:
            args.tech = _derived
    if not args.tech:
        logger.error("--tech or --tech-config is required")
        return 1
    if getattr(args, "tech", None) and not _tc_override:
        require_tech_config(args.tech, getattr(args, "version", None))
    # Resolve lib_config via the tag-dir cascade (new) or legacy flat form.
    tech_name = args.tech
    version = args.version or "v1.0.0"
    core_dir = get_cbflow_core_dir()
    _preferred_tag = (getattr(args, 'tag', None)
                      or os.environ.get('CBFLOW_LIB_CONFIG_TAG', ''))
    _avail_tags = _list_available_tags(tech_name, version)
    _cov_tag = _preferred_tag if _preferred_tag in _avail_tags else (
        _avail_tags[0] if _avail_tags else '')
    lib_config = (_resolve_lib_config_path(tech_name, _cov_tag, version)
                  if _cov_tag else '')
    if not lib_config or not os.path.exists(lib_config):
        if not _avail_tags:
            _root = _resolve_lib_tag_root(tech_name, version)
            if _root:
                logger.error("No lib_config tags found under {} "
                             "(resolved lib_tag_root for {}).".format(
                                 _root, tech_name))
            else:
                logger.error("No lib_config tags for {} — lib_tag_root is "
                             "unset and no in-tree legacy tags exist.".format(
                                 tech_name))
                for ln in _lib_tag_root_fix_guide(tech_name, version):
                    logger.info("  " + ln)
        else:
            logger.error("lib_config not found for tag '{}' — available: {}".format(
                _preferred_tag or '(unspecified)', ", ".join(_avail_tags)))
        logger.info("  Run: cbflow flow library-manager generate --tech {} --tag <TAG>".format(tech_name))
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
    scan_parser.add_argument('--tech-config', default=None,
                             help='Path to tech_config.tcl. Takes precedence over --tech/CBFLOW_TECH_NODE — '
                                  'use when running outside a flow dir and you have a raw path.')
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
                             help='Filter by corner (default set: ss/tt/ff/sf/fs; techs may extend via tech(process_corners), e.g. adding `fff`)')
    list_parser.add_argument('--voltage', type=float, default=None,
                             help='Filter by voltage (e.g., 0.80)')
    list_parser.add_argument('--temp', type=int, default=None,
                             help='Filter by temperature (e.g., 125)')

    # verify command
    verify_parser = subparsers.add_parser(
        'verify', help='Verify library characterization by reading .lib file contents')
    verify_parser.add_argument('--path', default=None,
                                help='Directory to scan for .lib files')
    verify_parser.add_argument('--tech-config', default=None,
                                help='Path to tech_config.tcl (bypasses --tech lookup).')
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
    mmmc_parser.add_argument('--tech-config', default=None,
                             help='Path to tech_config.tcl (bypasses --tech lookup).')
    mmmc_parser.add_argument('--output', default=None,
                             help='Output file path (default: stdout)')

    # generate command — auto-discover and write lib_config.tcl
    gen_parser = subparsers.add_parser(
        'generate', help='Generate lib_config.tcl from library directories')
    gen_parser.add_argument('--lib-root', default=None,
                            help='Library root directory. Auto-read from tech(lib_root) in tech_config if omitted')
    gen_parser.add_argument('--tech', default=None,
                            help='Technology name (e.g., gf_22nm). Default: dirname of lib-root')
    gen_parser.add_argument('--tech-config', default=None,
                            help='Path to tech_config.tcl. When set, this is the authoritative '
                                 'tech config — bypasses --tech/CBFLOW_TECH_NODE lookup. Lets '
                                 'you run outside a flow dir with an arbitrary tech_config file.')
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
    gen_parser.add_argument('--analog-path', nargs='+', default=None,
                            help='Analog macro lib directories (multiple allowed). '
                                 'First-class category — materializes under '
                                 '<TAG>/analog/{ndm,lib,db,lef}/')
    gen_parser.add_argument('--ip-path', nargs='+', default=None,
                            help='IP block lib directories (multiple allowed). '
                                 'First-class category — materializes under '
                                 '<TAG>/ip/{ndm,lib,db,lef}/')
    gen_parser.add_argument('--exclude', nargs='+', default=[],
                            help='Glob patterns to exclude (e.g., "*channel*" "*dummy*" "*eco*")')
    gen_parser.add_argument('--tag', default=None,
                            help='Named tag for lib_config (e.g., P0, timing_closure). '
                                 'Output: <lib_tag_root>/<TAG>/lib_config.tcl.')
    gen_parser.add_argument('--incremental', action='store_true', default=False,
                            help='Merge new libs into existing lib_config (keep entries not in current scan)')
    gen_parser.add_argument('--lib-tag-root', default=None, dest='lib_tag_root',
                            help='Override lib_tag_root for this run. Lib content '
                                 'is written at <path>/<TAG>/. Precedence: this '
                                 'flag > CBFLOW_LIB_TAG_ROOT > project(lib_tag_root) '
                                 '> tech(lib_tag_root).')
    gen_parser.add_argument('--output', default=None,
                            help='Dev escape hatch — write a flat lib_config.tcl at '
                                 'this path (bypasses the tag-dir materialization).')
    gen_parser.add_argument('--allow-missing', action='store_true', default=False,
                            help='Proceed even if declared source paths do not exist. '
                                 'Default is fail-fast — use only when bootstrapping '
                                 'a partial tech setup. Emits a WARNING banner.')

    # add command — surgical: scan one category's path(s) and merge into
    # an existing tag directory. Preserves everything else.
    add_parser = subparsers.add_parser(
        'add',
        help='Add libraries for one category (analog/ip/memory/io/stdcell) '
             'to an existing tag. Preserves other categories.')
    add_parser.add_argument('--tech', default=None,
                            help='Technology name (e.g., gf_22nm). Optional when --tech-config is set.')
    add_parser.add_argument('--tech-config', default=None,
                            help='Path to tech_config.tcl (bypasses --tech lookup).')
    add_parser.add_argument('--tag', required=True,
                            help='Existing lib_config tag to extend')
    add_parser.add_argument('--category', required=True,
                            choices=['analog', 'ip', 'memory', 'io', 'stdcell'],
                            help='Which category the --path contents belong to')
    add_parser.add_argument('--path', nargs='+', required=True,
                            help='Directory (or multiple) containing the libraries')
    add_parser.add_argument('--version', default='v1.0.0',
                            help='Config version (default: v1.0.0)')
    add_parser.add_argument('--tracks', default=None,
                            help='Only for --category stdcell: '
                                 '"9T 7.5T 8T". Auto-detected if omitted.')
    add_parser.add_argument('--vts', default=None,
                            help='Only for --category stdcell: "svt lvt hvt". '
                                 'Auto-detected if omitted.')
    add_parser.add_argument('--exclude', nargs='+', default=[],
                            help='Glob patterns to exclude (optional)')
    add_parser.add_argument('--allow-missing', action='store_true', default=False,
                            help='Proceed if source paths missing (bootstrapping)')
    add_parser.add_argument('--lib-tag-root', default=None, dest='lib_tag_root',
                            help='Override lib_tag_root. Same precedence rules as '
                                 '`generate` — flag > env > project > tech.')

    # coverage command — show track × VT × corner matrix
    cov_parser = subparsers.add_parser(
        'coverage', help='Show library coverage matrix')
    cov_parser.add_argument('--tech', default=None,
                            help='Technology name (e.g., gf_22nm). Optional when --tech-config is set.')
    cov_parser.add_argument('--tech-config', default=None,
                            help='Path to tech_config.tcl (bypasses --tech lookup).')
    cov_parser.add_argument('--version', default='v1.0.0',
                            help='Config version (default: v1.0.0)')
    cov_parser.add_argument('--tag', default=None,
                            help='lib_config tag to read (default: first '
                                 'available; env: CBFLOW_LIB_CONFIG_TAG)')

    # status command — signoff-readiness report (multi-VT aware)
    status_parser = subparsers.add_parser(
        'status',
        help='Signoff-readiness report — available VTs, enabled VTs, '
             'per-track/per-VT library counts, LEF/RCX coverage, dont_use masks')
    status_parser.add_argument('--tech', default=None,
                               help='Technology name (e.g., gf_22nm). Optional when --tech-config is set.')
    status_parser.add_argument('--tech-config', default=None,
                               help='Path to tech_config.tcl (bypasses --tech lookup).')
    status_parser.add_argument('--project', default=None,
                               help='Project name (auto-detects enabled VTs '
                                    'from project(vt_flavors); omit for '
                                    'tech-wide view)')
    status_parser.add_argument('--version', default='v1.0.0',
                               help='Config version (default: v1.0.0)')
    status_parser.add_argument('--tag', default=None,
                               help='lib_config tag to introspect (default: '
                                    'first available; env: CBFLOW_LIB_CONFIG_TAG)')

    return parser


# -------------------------------------------------------------------------------
# Main Entry Point
# -------------------------------------------------------------------------------

def _validate_path_arg(args, attr='path'):
    """Validate that a path argument exists and is a directory.

    `attr` may be a single path (nargs=None) or a list (nargs='+'). The
    `add` subcommand uses nargs='+' for --path so each entry is validated
    independently.
    """
    path = getattr(args, attr, None)
    if path is None:
        return True  # Optional arg
    paths = path if isinstance(path, list) else [path]
    for p in paths:
        if not os.path.exists(p):
            logger.error(f"Path does not exist: {p}")
            logger.info(f"  Please provide a valid directory path with --{attr.replace('_', '-')}")
            return False
        if not os.path.isdir(p):
            logger.error(f"Path is not a directory: {p}")
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
    """Main entry point.

    With a subcommand: preflight tech_config, then dispatch.
    Without a subcommand: drop into an interactive REPL that prompts for
        tech and accepts subcommands until the user types exit.
    """
    parser = create_parser()
    args = parser.parse_args()

    # Command dispatch table
    commands = {
        'scan': cmd_scan,
        'check': cmd_check,
        'list': cmd_list,
        'verify': cmd_verify,
        'generate-mmmc': cmd_generate_mmmc,
        'generate': cmd_generate,
        'add': cmd_add,
        'coverage': cmd_coverage,
        'status': cmd_status,
    }

    # No subcommand → interactive REPL (mirrors mmmc-manager behavior)
    if not args.command:
        # post_tech_hook: install tech(process_corners) whenever the REPL
        # resolves (or switches) tech. Without this, generate/scan/etc.
        # dispatched from inside the REPL use the default 5-corner set
        # and miscategorize libs for techs declaring `fff` or similar.
        return run_repl(parser, commands, tool_name="library-manager",
                        logger=logger, post_tech_hook=_apply_tech_corners)

    if args.command not in commands:
        logger.error(f"Unknown command: {args.command}")
        logger.info(f"Available commands: {', '.join(commands.keys())}")
        return 1

    # ── Hard gate: every subcommand requires tech_config.tcl ───────────
    # No exceptions. Adding a new subcommand cannot silently bypass this
    # because it's here at the dispatcher, not inside individual handlers.
    # preflight_tech_config_or_exit() calls sys.exit(1) on failure with a
    # fix guide listing available techs.
    preflight_tech_config_or_exit(args, tool_name="library-manager")

    # ── Tech-declared process-corner set ────────────────────────────────
    # Load tech(process_corners) if the tech ships one — otherwise keep
    # the compiled-in default {ss,tt,ff,sf,fs}. Fixes the sabarmati-soc
    # case where GF 22FDX's `fff` corner silently miscategorized as the
    # embedded `ff` substring.
    try:
        _tech_node = getattr(args, 'tech_node', None) or os.environ.get('CBFLOW_TECH_NODE', '')
        _tech_cfg = getattr(args, 'tech_config', None)
        if not _tech_cfg and _tech_node:
            _tech_cfg = require_tech_config(_tech_node, getattr(args, 'version', None))
        if _tech_cfg:
            _apply_tech_corners(_tech_cfg)
    except Exception as _e:
        logger.debug(f"process_corners load skipped: {_e}")

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
