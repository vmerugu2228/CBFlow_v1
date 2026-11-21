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

# Post cbflow_global utils-refactor: shared Python packages (core.paths,
# core.interactive, logging_config, cbflow_config, …) live under
# global/utils/, not PD/utils/. This PD-only command adds BOTH to sys.path
# so an un-sparsed clone resolves them whether the invoker set env or not.
import sys as _bootstrap_sys
_this = os.path.dirname(os.path.abspath(__file__))
_pd_utils = os.path.dirname(_this)
_umbrella = os.path.dirname(os.path.dirname(_pd_utils))
_global_utils = os.path.join(_umbrella, 'global', 'utils')
_global_cmds = os.path.join(_global_utils, 'commands')
if os.path.isdir(_global_cmds) and _global_cmds not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_cmds)
if os.path.isdir(_global_utils) and _global_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_utils)
if _pd_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _pd_utils)

from logging_config import configure_logging, get_logger

import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import (
    get_cbflow_core_dir, get_flow_config_version, require_tech_config,
    preflight_tech_config_or_exit, get_global_config_root,
)
from core.interactive import run_repl

logger = configure_logging('cbflow.mmmc_manager')


# ===============================================================================
# Config Path Resolution
# ===============================================================================

def get_mmmc_config_path(project_name: Optional[str] = None) -> str:
    """Resolve mmmc_config.tcl path.

    Post-cbflow_global refactor, mmmc_config.tcl is per-project and lives at
    `<global>/config/project/<project>/<ver>/mmmc_config.tcl`. The caller may
    pass project_name explicitly; otherwise we read CBFLOW_PROJECT_NAME from
    the environment (set by `workspace create` inside a run shell). If still
    unresolved and exactly one project exists under global/config/project/,
    we use that — any ambiguity errors out.
    """
    version = get_flow_config_version()
    grot = get_global_config_root()
    if not grot:
        raise RuntimeError("cannot resolve global config root")

    proj = project_name or os.environ.get('CBFLOW_PROJECT_NAME', '').strip()
    if not proj:
        projects_root = os.path.join(grot, 'project')
        if os.path.isdir(projects_root):
            projects = [d for d in os.listdir(projects_root)
                        if os.path.isdir(os.path.join(projects_root, d))
                        and not d.startswith('.')]
            if len(projects) == 1:
                proj = projects[0]

    if not proj:
        raise RuntimeError(
            "cannot resolve project for mmmc-manager — pass --project <name>, "
            "export CBFLOW_PROJECT_NAME, or run from inside a workspace shell"
        )
    return os.path.join(grot, 'project', proj, version, 'mmmc_config.tcl')


def get_mmmc_node_scenarios_path(project_name: Optional[str] = None) -> str:
    """Resolve mmmc_node_scenarios.tcl path for a project.

    Node-level scenario assignments (the `array set mmmc { cts {...} place
    {...} ... }` block) live in a sibling file to mmmc_config.tcl so the
    auto-generated view/scenario-set config doesn't get mixed with
    engineer-managed per-node mappings. set-node mutates THIS file —
    passing --config here is still honored for ad-hoc paths.
    """
    base = get_mmmc_config_path(project_name)
    return os.path.join(os.path.dirname(base), 'mmmc_node_scenarios.tcl')


# ===============================================================================
# TCL Config Parser
# ===============================================================================

class MmmcConfigParser:
    """Parse mmmc_config.tcl into Python data structures.

    Handles the exact formats used in the config:
      - set mmmc(process_corners) {ss tt ff}          (simple list)
      - set mmmc(pvt,ss) {{0p76v 150c} {0p76v 25c}}   (PVT points)
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

    Returns dict with keys:
      analysis_views (list of names), scenario_sets (dict of lists),
      view_data (dict name -> {corner, mode, voltage, temperature,
                               lib_set_ref, rc_corner}).
    view_data is the authoritative per-view metadata — consumers must
    read fields from it instead of splitting the view name on `_`
    (rc-corner names such as `rc_max` contain underscores).
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

# Dump per-view fields (one line per view, tab-separated)
puts "===VIEWDATA_START==="
foreach v [lsort [array names analysis_views]] {{
    set _row [list $v]
    foreach _f {{corner mode voltage temperature lib_set_ref rc_corner}} {{
        if {{[dict exists $analysis_views($v) $_f]}} {{
            lappend _row [dict get $analysis_views($v) $_f]
        }} else {{
            lappend _row ""
        }}
    }}
    puts [join $_row "\t"]
}}
puts "===VIEWDATA_END==="

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
    data = {'analysis_views': [], 'scenario_sets': {}, 'view_data': {}}

    # Parse views
    m = re.search(r'===VIEWS_START===\n(.*?)===VIEWS_END===', stdout, re.DOTALL)
    if m:
        data['analysis_views'] = [
            line.strip() for line in m.group(1).splitlines() if line.strip()
        ]

    # Parse per-view fields
    m = re.search(r'===VIEWDATA_START===\n(.*?)===VIEWDATA_END===', stdout, re.DOTALL)
    if m:
        _fields = ('corner', 'mode', 'voltage', 'temperature',
                   'lib_set_ref', 'rc_corner')
        for line in m.group(1).splitlines():
            if not line.strip():
                continue
            cols = line.split('\t')
            cols += [''] * (len(_fields) + 1 - len(cols))
            data['view_data'][cols[0]] = dict(zip(_fields, cols[1:]))

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
    """Create a timestamped backup under a dedicated `backup/` sidecar
    directory next to the file. Returns the backup path.

    Old behavior wrote `<file>.bak` right next to the source, cluttering the
    config directory with .bak files that shadowed the real config in
    tab-complete and made version-control grep noisier. Every backup now
    goes into `<config_dir>/backup/<basename>.YYYYMMDD-HHMMSS.bak`.
    Naming keeps timestamps so multiple edits per day don't overwrite each
    other. Multi-day retention is trivial to trim (`find ... -mtime +N`).
    """
    from datetime import datetime as _dt_local
    cfg_dir = os.path.dirname(os.path.abspath(config_path))
    backup_dir = os.path.join(cfg_dir, 'backup')
    os.makedirs(backup_dir, exist_ok=True)
    ts = _dt_local.now().strftime('%Y%m%d-%H%M%S')
    backup = os.path.join(backup_dir,
                          '{}.{}.bak'.format(os.path.basename(config_path), ts))
    shutil.copy2(config_path, backup)
    return backup


def _read_config(config_path: str) -> str:
    """Read config file content."""
    with open(config_path, 'r') as f:
        return f.read()


def _write_config(config_path: str, content: str):
    """Write config file content atomically.

    mmmc_config.tcl has no backup on the mutation path (backups only
    exist for show/generate), so a truncated write would surface as a
    TCL parse error on the next `cbflow run all`. atomic rename keeps
    the target either untouched or fully written.
    """
    from core.paths import atomic_write
    atomic_write(config_path, content)


def _find_top_level_entry(content: str, body_start: int, name: str):
    """Return (start, end) of the `<name> { ... }` entry that sits at the top
    level of a braced TCL array body beginning at `body_start` (just after
    the opening `{`), or None. Comments and nested entries are skipped, and
    the name must match a whole token.
    """
    i, n, depth = body_start, len(content), 1
    while i < n and depth > 0:
        c = content[i]
        if depth == 1 and c == '#':
            # Skip the comment for name matching, but keep counting its
            # braces: Tcl's brace matching inside a braced word does.
            while i < n and content[i] != '\n':
                if content[i] == '{':
                    depth += 1
                elif content[i] == '}':
                    depth -= 1
                i += 1
            continue
        if c == '{':
            depth += 1
            i += 1
            continue
        if c == '}':
            depth -= 1
            i += 1
            continue
        if depth == 1 and not c.isspace():
            j = i
            while j < n and not content[j].isspace() and content[j] not in '{}':
                j += 1
            token = content[i:j]
            k = j
            while k < n and content[k].isspace():
                k += 1
            if token == name and k < n and content[k] == '{':
                d, m = 1, k + 1
                while m < n and d > 0:
                    if content[m] == '{':
                        d += 1
                    elif content[m] == '}':
                        d -= 1
                    m += 1
                return i, m
            i = j
            continue
        i += 1
    return None


def _stale_references(valid_views, scenario_sets=None, node_mappings=None):
    """Return [(source, name)] for every scenario-set member and node
    assignment that is not a generated analysis view. `source` is
    ('set', <set name>) or ('node', <node>, <setup|hold>). The single
    implementation behind validate, set-node, generate, generate-view-def
    and the post-mutation warning.
    """
    valid = set(valid_views)
    stale = []
    for sname in sorted(scenario_sets or {}):
        stale += [(('set', sname), v)
                  for v in scenario_sets[sname] if v not in valid]
    for node, mapping in (node_mappings or {}).items():
        for atype in ('setup', 'hold'):
            stale += [(('node', node, atype), v)
                      for v in mapping.get(atype, []) if v not in valid]
    return stale


def _stale_label(source) -> str:
    if source[0] == 'set':
        return f"scenario set '{source[1]}'"
    return f"node '{source[1]}' {source[2]}"


def _load_node_mappings(config_path: str, parser: 'MmmcConfigParser'):
    """Return (node_mappings, source_path) for the config at `config_path`.

    Node-scenario assignments (`array set mmmc { cts {...} ... }`) live in
    the sibling `mmmc_node_scenarios.tcl` — the file `set-node` writes and
    the config resolver sources. A legacy config that still carries the
    block inline is honored too. Returns ({}, '') when neither exists.
    """
    if parser.node_mappings:
        return parser.node_mappings, config_path
    sibling = os.path.join(os.path.dirname(os.path.abspath(config_path)),
                           'mmmc_node_scenarios.tcl')
    if os.path.isfile(sibling) and \
            os.path.abspath(sibling) != os.path.abspath(config_path):
        ns = MmmcConfigParser(sibling)
        if ns.parse():
            return ns.node_mappings, sibling
    return {}, ''


def _prune_removed_views(config_path: str) -> None:
    """After remove-pvt / remove-mode: drop every scenario-set member and
    node assignment that no longer names a generated view, then report
    what was removed. Nothing but the removed PVT/mode could still want
    those views, and a stale name makes STA schedule a subnode for a view
    that no longer exists.

    Only the literal `set mmmc_scenario_sets(<name>) { ... }` blocks of
    mmmc_config.tcl and the sibling mmmc_node_scenarios.tcl are edited;
    derived sets (`[concat ...]`, `[lsort ...]`) follow automatically.
    """
    tcl_data = execute_tcl_config(config_path)
    if tcl_data is None:
        return
    valid = set(tcl_data['analysis_views'])

    def _prune_body(body: str, removed: list) -> str:
        def _drop(m):
            tok = m.group(0)
            if tok in valid:
                return tok
            removed.append(tok)
            return ''
        # View names are bare tokens (letters, digits, `_`, `.`, `-`).
        out = re.sub(r'(?<![\w.\-])[A-Za-z]\w*(?:[.\-]\w+)*(?![\w.\-])', _drop, body)
        # Drop lines left empty by the removal.
        return re.sub(r'\n[ \t]+(?=\n)', '', out)

    report = []

    # 1. Literal scenario sets in mmmc_config.tcl
    content = _read_config(config_path)
    pieces, pos = [], 0
    for m in re.finditer(r'set\s+mmmc_scenario_sets\((\w+)\)\s*\{', content):
        body_start = m.end()
        d, k = 1, body_start
        while k < len(content) and d > 0:
            if content[k] == '{':
                d += 1
            elif content[k] == '}':
                d -= 1
            k += 1
        body = content[body_start:k - 1]
        removed = []
        new_body = _prune_body(body, removed)
        pieces.append(content[pos:body_start] + new_body)
        pos = k - 1
        report += [f"scenario set '{m.group(1)}': {v}" for v in removed]
    new_content = ''.join(pieces) + content[pos:]
    if new_content != content:
        _write_config(config_path, new_content)

    # 2. Node assignments in the sibling mmmc_node_scenarios.tcl
    ns_path = os.path.join(os.path.dirname(os.path.abspath(config_path)),
                           'mmmc_node_scenarios.tcl')
    if os.path.isfile(ns_path):
        ns_content = _read_config(ns_path)
        parser = MmmcConfigParser(ns_path)
        if parser.parse():
            stale = {name for _src, name in _stale_references(
                valid, node_mappings=parser.node_mappings)}
            if stale:
                for src, name in _stale_references(
                        valid, node_mappings=parser.node_mappings):
                    report.append(f"{_stale_label(src)}: {name}")
                pruned = ns_content
                for name in sorted(stale, key=len, reverse=True):
                    pruned = re.sub(r'(?<![\w.\-])' + re.escape(name) +
                                    r'(?![\w.\-])', '', pruned)
                pruned = re.sub(r'\n[ \t]+(?=\n)', '', pruned)
                _backup_config(ns_path)
                _write_config(ns_path, pruned)

    if report:
        logger.info("Removed %d reference(s) to views that are no longer generated:",
                    len(report))
        for line in report:
            logger.info("    %s", line)
    _warn_stale_references(config_path)


def _warn_stale_references(config_path: str) -> None:
    """After a mutation that removes views (remove-pvt / remove-mode), warn
    about scenario-set and node-scenario entries that no longer name a
    generated view. Scenario sets are engineer-declared literal lists, so
    nothing rewrites them automatically — the engineer decides what
    replaces a removed view.
    """
    tcl_data = execute_tcl_config(config_path)
    if tcl_data is None:
        return
    node_mappings = {}
    parser = MmmcConfigParser(config_path)
    if parser.parse():
        node_mappings, _src = _load_node_mappings(config_path, parser)
    stale = [f"{_stale_label(src)}: {name}" for src, name in _stale_references(
        tcl_data['analysis_views'], tcl_data['scenario_sets'], node_mappings)]
    if stale:
        logger.warning("%d reference(s) now name views that are no longer "
                       "generated — update them by hand:", len(stale))
        for line in stale:
            logger.warning("    %s", line)


# ===============================================================================
# Command: show
# ===============================================================================

def cmd_show(args: argparse.Namespace) -> int:
    """Parse and display current config in readable table format."""
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    # Execute TCL to get auto-generated views and sets
    tcl_data = execute_tcl_config(config_path)
    if tcl_data is None:
        # Fail loudly rather than falling back to `[] / {}` — a silent
        # "0 views configured" misdirects users to blame their
        # mmmc_config when tclsh itself is missing / timing out / crashing.
        logger.error("Could not execute mmmc_config.tcl via tclsh — see "
                     "ERROR line above for root cause. Views/scenarios "
                     "cannot be shown.")
        views, sets = [], {}
    else:
        views = tcl_data['analysis_views']
        sets = tcl_data['scenario_sets']

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
    print(f"  Analysis Views: {len(views)} ({num_modes} modes x {num_pvt} PVT combos "
          f"x {len(parser.rc_corners)} RC corners)")

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

    # Node mappings (sibling mmmc_node_scenarios.tcl)
    node_mappings, node_src = _load_node_mappings(config_path, parser)
    if node_mappings:
        print(f"  Node Scenario Assignments:  ({os.path.basename(node_src)})")
        for node, mapping in node_mappings.items():
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
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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

    # Check 2: RC corners are defined (views are a Cartesian over them)
    defined_rc = set(parser.rc_corners.keys())
    print("  [2] RC corners defined")
    if not defined_rc:
        msg = "No rc_corners defined — no analysis views can be generated"
        errors.append(msg)
        print(f"      FAIL  {msg}")
    else:
        print(f"      PASS  {' '.join(sorted(defined_rc))}")

    # Check 3: every RC corner carries a temperature (view definitions need it)
    print("  [3] RC corners have a temperature")
    for rc_name in sorted(defined_rc):
        if not parser.rc_corners[rc_name].get('temperature'):
            msg = f"RC corner '{rc_name}' has no temperature"
            errors.append(msg)
            print(f"      FAIL  {msg}")
        else:
            print(f"      PASS  {rc_name}: {parser.rc_corners[rc_name]['temperature']}")

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

    # Check 6: Node mapping scenarios reference valid views. Assignments
    # are read from the sibling mmmc_node_scenarios.tcl (what set-node
    # writes and the resolver sources), not from mmmc_config.tcl.
    if tcl_data:
        print("  [6] Node scenarios reference valid analysis views")
        valid_views = set(tcl_data['analysis_views'])
        node_mappings, node_src = _load_node_mappings(config_path, parser)
        if not node_mappings:
            msg = ("no node scenario assignments found (expected "
                   "mmmc_node_scenarios.tcl next to the config)")
            warnings.append(msg)
            print(f"      WARN  {msg}")
        else:
            print(f"      Source: {node_src}")
        _node_stale = _stale_references(valid_views, node_mappings=node_mappings)
        _bad_nodes = {src[1] for src, _n in _node_stale}
        for src, name in _node_stale:
            msg = f"Node '{src[1]}' {src[2]}: '{name}' not a valid view"
            errors.append(msg)
            print(f"      FAIL  {msg}")
        for node, mapping in node_mappings.items():
            if node not in _bad_nodes:
                s_n = len(mapping.get('setup', []))
                h_n = len(mapping.get('hold', []))
                print(f"      PASS  {node}: {s_n} setup + {h_n} hold OK")

        # Check 7: scenario sets are engineer-declared literal lists, so
        # they can go stale when PVT points / modes / RC corners change.
        print("  [7] Scenario sets reference valid analysis views")
        _set_stale = _stale_references(valid_views, tcl_data['scenario_sets'])
        _bad_sets = {src[1] for src, _n in _set_stale}
        for src, name in _set_stale:
            msg = f"Scenario set '{src[1]}': '{name}' not a valid view"
            errors.append(msg)
            print(f"      FAIL  {msg}")
        for sname in sorted(tcl_data['scenario_sets']):
            if sname in _bad_sets:
                continue
            members = tcl_data['scenario_sets'][sname]
            if not members:
                msg = f"Scenario set '{sname}' is empty"
                warnings.append(msg)
                print(f"      WARN  {msg}")
            else:
                print(f"      PASS  {sname}: {len(members)} views")

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
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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
    _prune_removed_views(config_path)
    return 0


# ===============================================================================
# Command: add-pvt
# ===============================================================================

def cmd_add_pvt(args: argparse.Namespace) -> int:
    """Add a PVT point to a corner in mmmc_config.tcl in-place."""
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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
    _prune_removed_views(config_path)
    return 0


# ===============================================================================
# Command: add-rc
# ===============================================================================

def cmd_add_rc(args: argparse.Namespace) -> int:
    """Add an RC corner definition to mmmc_config.tcl in-place."""
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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
    """Set node scenario assignments in mmmc_node_scenarios.tcl in-place.

    Node-scenario assignments live in a sibling file to mmmc_config.tcl
    (see `get_mmmc_node_scenarios_path`). An explicit --config still wins
    so users can retarget a one-off file.
    """
    config_path = args.config or get_mmmc_node_scenarios_path(getattr(args, "project", None))

    parser = MmmcConfigParser(config_path)
    if not parser.parse():
        return 1

    node = args.node
    setup_scenarios = args.setup.split() if args.setup else None
    hold_scenarios = args.hold.split() if args.hold else None

    if setup_scenarios is None and hold_scenarios is None:
        logger.error("At least one of --setup or --hold is required")
        return 1

    # Reject names that are not generated analysis views. Views come from
    # the mmmc_config.tcl sitting next to the node-scenarios file.
    _views_cfg = os.path.join(os.path.dirname(os.path.abspath(config_path)),
                              'mmmc_config.tcl')
    if os.path.isfile(_views_cfg):
        _tcl = execute_tcl_config(_views_cfg)
        if _tcl is None:
            logger.error("Cannot validate scenario names: %s failed to execute",
                         _views_cfg)
            return 1
        _bad = [name for _src, name in _stale_references(
            _tcl['analysis_views'],
            node_mappings={node: {'setup': setup_scenarios or [],
                                  'hold': hold_scenarios or []}})]
        if _bad:
            logger.error("Not generated analysis views in %s: %s",
                         _views_cfg, ' '.join(_bad))
            logger.error("  List valid names with: cbflow flow mmmc-manager list-views")
            return 1
    else:
        logger.warning("No mmmc_config.tcl next to %s — scenario names were "
                       "NOT validated against analysis views", config_path)

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

        # Locate the node entry at the TOP LEVEL of the array body. A regex
        # search for `<node> {` would also match a node whose name merely
        # ends in <node> (`timing` inside `merge_timing`) and splice the new
        # block into the wrong entry, corrupting a file every run sources.
        span = _find_top_level_entry(content, array_match.end(), node)
        if span is None:
            logger.error("Could not find node '%s' in mmmc array", node)
            return 1
        ent_start, ent_end = span
        content = content[:ent_start] + new_node_block.lstrip() + content[ent_end:]
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

    previous = _read_config(config_path)
    _write_config(config_path, content)

    # The resolver sources this file for every run of the project: refuse
    # to leave it in a state that no longer parses or lost a node.
    check = MmmcConfigParser(config_path)
    expected = (set(parser.node_mappings) | {node})
    if not check.parse() or set(check.node_mappings) != expected or \
            check.node_mappings.get(node, {}).get('setup', []) != list(setup_scenarios) or \
            check.node_mappings.get(node, {}).get('hold', []) != list(hold_scenarios):
        _write_config(config_path, previous)
        logger.error("set-node produced an inconsistent %s — change rolled back",
                     config_path)
        return 1

    s_n = len(setup_scenarios)
    h_n = len(hold_scenarios)
    logger.info("Set node '%s': %d setup, %d hold scenarios", node, s_n, h_n)
    return 0


# ===============================================================================
# Command: list-views
# ===============================================================================

def cmd_list_views(args: argparse.Namespace) -> int:
    """Execute TCL config and list all generated analysis views."""
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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
    config_path = args.config or get_mmmc_config_path(getattr(args, "project", None))

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

    if getattr(args, 'style', 'standalone') == 'flow':
        return _generate_flow_view_def(args, config_path, parser, tcl_data)

    lines = []
    lines.append('# Cadence MMMC View Definition File')
    lines.append('# Auto-generated by CBflow mmmc-manager from mmmc_config.tcl')
    lines.append('')

    # -- Library Sets --
    # Per-view fields come from the executed config (view_data), never
    # from splitting the view name: rc-corner names like `rc_max` contain
    # underscores, so a positional split mis-assigns rc and temperature.
    lib_sets = set()
    view_info = {}
    view_data = tcl_data.get('view_data', {})
    for v in views:
        d = view_data.get(v)
        if not d or not d.get('lib_set_ref') or not d.get('rc_corner') \
                or not d.get('mode'):
            logger.error(
                "analysis view '%s' is missing mode / lib_set_ref / rc_corner "
                "in %s — cannot generate a view definition", v, config_path)
            return 1
        rc = d['rc_corner']
        if rc not in parser.rc_corners:
            logger.error(
                "analysis view '%s' references rc_corner '%s' which is not "
                "declared in rc_corners %s", v, rc, sorted(parser.rc_corners))
            return 1
        lib_sets.add(d['lib_set_ref'])
        view_info[v] = {
            'mode': d['mode'], 'corner': d['corner'],
            'voltage': d['voltage'], 'rc': rc,
            'temp': d['temperature'], 'lib_ref': d['lib_set_ref'],
        }

    lines.append('# ' + '-' * 70)
    lines.append('# Library Sets')
    lines.append('# ' + '-' * 70)
    lines.append('')
    for ls in sorted(lib_sets):
        lines.append(f'create_library_set -name {ls} \\')
        # ::lib_dir — fully qualified so the ref resolves when this file is
        # sourced from inside `read_mmmc` (a Tcl proc) rather than the global
        # scope.
        lines.append(f'    -timing [list ${{::lib_dir}}/{ls}_ccs.lib]')
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
        lines.append(f'    -qx_tech_file [list ${{::tech_dir}}/qrc/{rc_name}/qrcTechFile]')
        lines.append('')

    # -- Constraint Modes --
    lines.append('# ' + '-' * 70)
    lines.append('# Constraint Modes')
    lines.append('# ' + '-' * 70)
    lines.append('')
    for mode, info in sorted(parser.operating_modes.items()):
        sdc = (info.get('constraint_file') or '').strip()
        if not sdc:
            logger.error(
                "operating_mode '%s' missing constraint_file — "
                "create_constraint_mode requires -sdc_files; aborting", mode)
            return 1
        # Emit on a single line — eliminates any chance of a dangling '\'
        # if downstream edits remove the continuation argument.
        lines.append(
            f'create_constraint_mode -name {mode}_mode -sdc_files [list {sdc}]')
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
        rc_key = info['rc']   # validated against rc_corners above
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
    # Setup/hold activation comes from the engineer-declared scenario sets,
    # not from a corner-name pattern (ss→setup / ff→hold is project policy).
    _sets = tcl_data.get('scenario_sets', {})
    _stale = _stale_references(
        views, {k: _sets.get(k, []) for k in ('setup', 'hold')})
    for _src, _name in _stale:
        logger.error("%s names a view that is not generated: %s",
                     _stale_label(_src), _name)
    if _stale:
        return 1
    setup_views = list(_sets.get('setup', []))
    hold_views = list(_sets.get('hold', []))
    if not setup_views and not hold_views:
        logger.warning(
            "mmmc_scenario_sets(setup) and (hold) are both empty — no "
            "set_analysis_view line emitted")
    if setup_views or hold_views:
        # One line — no trailing-backslash continuation. Empty {} for either
        # side is still legal: Innovus reads it as "deactivate all of that kind",
        # which command files then override.
        lines.append(
            f'set_analysis_view '
            f'-setup [list {" ".join(setup_views)}] '
            f'-hold [list {" ".join(hold_views)}]')
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

def _generate_flow_view_def(args, config_path, parser, tcl_data) -> int:
    """`generate-view-def --style flow`: (re)write the flow-consumed
    mmmc_view_definition.tcl from an existing mmmc_config.tcl."""
    view_data = tcl_data.get('view_data', {})
    sets = tcl_data.get('scenario_sets', {})
    known = set(tcl_data['analysis_views'])

    _stale = _stale_references(
        known, {k: sets.get(k, []) for k in ('setup', 'hold', 'signoff')})
    for src, name in _stale:
        logger.error("%s names a view that is not generated: %s",
                     _stale_label(src), name)
    if _stale:
        return 1
    setup_views = list(sets.get('setup', []))
    hold_views = list(sets.get('hold', []))
    selected = sorted(set(setup_views) | set(hold_views)
                      | set(sets.get('signoff', [])))
    if not selected:
        logger.error("mmmc_scenario_sets setup / hold / signoff are all empty in "
                     "%s — nothing to define", config_path)
        return 1

    view_fields = {}
    for v in selected:
        d = view_data.get(v, {})
        if not (d.get('mode') and d.get('lib_set_ref') and d.get('rc_corner')):
            logger.error("analysis view '%s' is missing mode / lib_set_ref / "
                         "rc_corner in %s", v, config_path)
            return 1
        rc = d['rc_corner']
        if rc not in parser.rc_corners:
            logger.error("analysis view '%s': rc_corner '%s' is not declared in "
                         "rc_corners", v, rc)
            return 1
        view_fields[v] = {
            'mode': d['mode'], 'corner': d['corner'], 'voltage': d['voltage'],
            'temp': d['temperature'], 'rc': rc, 'lib_set_ref': d['lib_set_ref'],
        }

    cfg_dir = os.path.dirname(os.path.abspath(config_path))
    # <...>/project/<name>/<ver>/mmmc_config.tcl -> <name>
    project_name = getattr(args, 'project', None) or \
        os.path.basename(os.path.dirname(cfg_dir))
    tech_name = getattr(args, 'tech', None) or os.environ.get('CBFLOW_TECH_NODE', '')
    content = _render_flow_view_definition(
        tech_name, project_name, selected, view_fields, parser.rc_corners,
        setup_views, hold_views)

    output_path = getattr(args, 'output', None)
    if not output_path:
        print(content, end='')
        return 0
    if os.path.exists(output_path):
        logger.info("Backup: %s", _backup_config(output_path))
    from core.paths import atomic_write
    out_dir = os.path.dirname(os.path.abspath(output_path))
    os.makedirs(out_dir, exist_ok=True)
    atomic_write(output_path, content)
    logger.info("Flow view definition written to: %s", output_path)
    logger.info("  Analysis views: %d  (setup %d / hold %d active)",
                len(selected), len(setup_views), len(hold_views))
    return 0


def _render_flow_view_definition(tech_name, project_name, selected,
                                 view_fields, rc_corners, setup_views,
                                 hold_views) -> str:
    """Render the Cadence mmmc_view_definition.tcl consumed by the flows
    (Innovus / Tempus / Genus `read_mmmc`).

    selected     — view names to define (the engineer's sign-off set)
    view_fields  — name -> {mode, corner, voltage, temp, rc, lib_set_ref};
                   fields are passed in, never parsed out of the view name
    rc_corners   — rc_corners dict from mmmc_config (rc key -> properties)
    setup_views / hold_views — engineer-declared mmmc_scenario_sets, used
                   for the initial set_analysis_view (no corner inference)
    """
    from datetime import datetime
    vd_lines = []
    vw = vd_lines.append
    vw('#!/usr/bin/env tclsh')
    vw('# ' + '=' * 77)
    vw('# Cadence MMMC View Definition — Auto-Generated')
    vw('# Generated: {} | Tech: {} | Project: {}'.format(
        datetime.now().strftime('%Y-%m-%d %H:%M'), tech_name, project_name))
    vw('# Scenarios: {} (mmmc_scenario_sets: setup + hold + signoff)'.format(len(selected)))
    vw('# Sourced via: read_mmmc -file <this_file>')
    vw('# DO NOT EDIT — regenerate with: cbflow flow mmmc-manager generate-view-def --style flow')
    vw('# ' + '=' * 77)
    vw('')
    # EDA tools (Innovus / Tempus / Genus) source this file from inside their
    # internal `read_mmmc` procedure. Bare `$tech(...)` refs would resolve
    # against THAT proc's local scope and error with "can't read tech: no
    # such variable". The fully-qualified `$::tech(...)` always resolves
    # to the global. Same reasoning for project / operating_modes below.
    vw('# Variables are referenced via the global namespace ($::) so the')
    vw('# file works when sourced from inside read_mmmc (a Tcl proc).')
    vw('')

    parts = {sc: view_fields[sc] for sc in selected}
    lib_sets = sorted({sp['lib_set_ref'] for sp in parts.values()})
    modes = sorted({sp['mode'] for sp in parts.values()})

    def _temp_value(t):
        # View temperature token -> number for create_rc_corner -T
        # ("125c" -> 125, "m40c" -> -40).
        t = str(t).strip().lower().rstrip('c')
        return '-' + t[1:] if t.startswith(('m', 'n')) else t

    def _rc(sp):
        # One Cadence RC corner per (rc_corner, view temperature): wire RC
        # must scale at the view's own temperature, not one fixed -T per
        # rc_corners key (a 125C hold view would otherwise time rc_min at
        # -40C).
        return '{}_{}'.format(sp['rc'], sp['temp'])

    def _dc(sp):
        # One delay corner per unique (lib_set, rc corner @ temperature).
        return '{}_{}_{}_{}_dc'.format(sp['corner'], sp['voltage'], sp['rc'], sp['temp'])

    # 1. Library Sets
    vw('# ' + '-' * 77)
    vw('# Library Sets')
    vw('# ' + '-' * 77)
    vw('')
    for lib_ref in lib_sets:
        vw('create_library_set -name {}_ls \\'.format(lib_ref))
        vw('    -timing $::tech($::project(track_variant),lib,{},timing)'.format(lib_ref))
        vw('')

    # 2. RC Corners — <rc_corner>_<temp>, QRC tech from the rc_corners key
    vw('# ' + '-' * 77)
    vw('# RC Corners (one per rc_corner x view temperature)')
    vw('# ' + '-' * 77)
    vw('')
    for rc_name, temp in sorted({(sp['rc'], sp['temp']) for sp in parts.values()}):
        vw('create_rc_corner -name {}_{} \\'.format(rc_name, temp))
        vw('    -qrc_tech $::tech(rcx,{},qrc) \\'.format(rc_name))
        vw('    -T {}'.format(_temp_value(temp)))
        vw('')

    # 3. Delay Corners
    vw('# ' + '-' * 77)
    vw('# Delay Corners')
    vw('# ' + '-' * 77)
    vw('')
    written = set()
    for sc in selected:
        sp = parts[sc]
        dc_name = _dc(sp)
        if dc_name in written:
            continue
        written.add(dc_name)
        vw('create_delay_corner -name {} \\'.format(dc_name))
        vw('    -library_set {}_ls \\'.format(sp['lib_set_ref']))
        vw('    -rc_corner {}'.format(_rc(sp)))
        vw('')

    # 4. Constraint Modes — SDC resolved at runtime from operating_modes
    vw('# ' + '-' * 77)
    vw('# Constraint Modes')
    vw('# ' + '-' * 77)
    vw('')
    vw('# SDC files resolved at runtime from operating_modes array')
    vw('# create_constraint_mode REQUIRES -sdc_files — error loudly if missing.')
    for mode in modes:
        vw('if {![info exists ::operating_modes(%s,constraint_file)] || $::operating_modes(%s,constraint_file) eq ""} {'
           % (mode, mode))
        vw('    error "MMMC: operating_modes(%s,constraint_file) not set — '
           'create_constraint_mode requires -sdc_files (mode=%s)"' % (mode, mode))
        vw('}')
        # Emit the create_constraint_mode on a single line so a future hand-
        # edit that drops the -sdc_files argument can't leave a dangling '\'.
        vw('create_constraint_mode -name %s_cm -sdc_files [list [subst $::operating_modes(%s,constraint_file)]]'
           % (mode, mode))
        vw('')

    # 5. Analysis Views
    vw('# ' + '-' * 77)
    vw('# Analysis Views')
    vw('# ' + '-' * 77)
    vw('')
    for sc in selected:
        sp = parts[sc]
        vw('create_analysis_view -name {} \\'.format(sc))
        vw('    -constraint_mode {}_cm \\'.format(sp['mode']))
        vw('    -delay_corner {}'.format(_dc(sp)))
        vw('')

    # 6. Initial activation — straight from the engineer-declared sets.
    # Command files then activate their node-specific subset.
    _sel = set(selected)
    vw('# ' + '-' * 77)
    vw('# Activate Views (mmmc_scenario_sets setup / hold)')
    vw('# Command files will: set_analysis_view -setup {} -hold {} (deactivate all)')
    vw('# then activate only their node-specific scenarios')
    vw('# ' + '-' * 77)
    vw('')
    # One line — no chance of a stray trailing '\' if either side is empty.
    vw('set_analysis_view -setup [list {}] -hold [list {}]'.format(
        ' '.join(v for v in setup_views if v in _sel),
        ' '.join(v for v in hold_views if v in _sel)))
    vw('')
    return '\n'.join(vd_lines) + '\n'


# ===============================================================================
# Generate mmmc_config.tcl — user-driven PVT matrix, validated against lib_config
# ===============================================================================

def cmd_generate_mmmc_config(args: argparse.Namespace) -> int:
    """Generate mmmc_config.tcl from user-specified PVT matrix, validated against lib_config.

    Flow: User defines corners/voltages/temps → Cartesian product → validate each
    lib_set_ref against lib_config → skip missing → write only valid scenarios.
    """
    from datetime import datetime

    version = get_flow_config_version()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    core_dir = os.path.dirname(os.path.dirname(script_dir))

    # ── Interactive CLI: prompt for missing inputs ──
    print('')
    print('=' * 60)
    print('  CBflow MMMC Config Generator')
    print('=' * 60)
    print('')

    # Tech name — --tech-config wins when provided; derive tech_name
    # from its path convention so the user can run outside a flow dir
    # with an arbitrary tech_config path.
    _tc_override = getattr(args, 'tech_config', None)
    if _tc_override:
        if not os.path.isfile(_tc_override):
            logger.error("--tech-config path does not exist: {}".format(_tc_override))
            return 1
        from core.paths import tech_name_from_config_path
        derived = tech_name_from_config_path(_tc_override)
        tech_name = args.tech or derived
        if not tech_name:
            logger.error("Could not derive tech name from {}. Pass --tech explicitly.".format(_tc_override))
            return 1
        args.tech = tech_name
        logger.info("Using explicit --tech-config: {}".format(_tc_override))
    else:
        tech_name = args.tech
        if not tech_name:
            from core.paths import list_available_techs, get_tech_search_roots
            available_techs = list_available_techs(getattr(args, 'version', None))
            if not available_techs:
                searched = get_tech_search_roots() or ['<no global/, no PD config/tech>']
                logger.error("No technologies found. Searched:")
                for p in searched:
                    logger.error("  {}".format(p))
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

        # Preflight — tech_config.tcl MUST exist for this tech/version.
        require_tech_config(tech_name, version)

    # Tech dir is in global (post 2026-10-11). The `tech_dir` variable is
    # used for logging + lib_config auto-select; both expect the actual
    # on-disk location.
    from core.paths import get_cbflow_global_dir
    _gdir = get_cbflow_global_dir()
    tech_dir = (os.path.join(_gdir, 'config', 'tech', tech_name, version)
                if _gdir else '')

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
    # --lib-config takes highest precedence: when the user passes a raw
    # lib_config.tcl path, use it directly and skip the lib_tag_root →
    # tag → lib_config.tcl cascade entirely. Lets mmmc-manager run
    # outside a flow dir with an arbitrary lib_config path (same
    # usability goal as library-manager's --tech-config).
    #
    # Otherwise: post 2026-10-10 lib_config lives inside a tag directory
    # (<tech_dir>/<TAG>/lib_config.tcl). Fall back to the legacy flat form
    # (<tech_dir>/lib_config_<TAG>.tcl) if the directory doesn't exist yet,
    # so pre-migration tags keep working.
    from library_manager_cmd import (_resolve_lib_config_path,
                                     _list_available_tags)
    lib_tag = args.lib_tag if hasattr(args, 'lib_tag') and args.lib_tag else None
    lib_config_path = None

    _lc_override = getattr(args, 'lib_config', None)
    if _lc_override:
        if not os.path.isfile(_lc_override):
            logger.error("--lib-config path does not exist: {}".format(_lc_override))
            return 1
        lib_config_path = os.path.realpath(_lc_override)
        if not lib_tag:
            # Derive a tag label from <lib_tag_root>/<TAG>/lib_config.tcl.
            _parent = os.path.basename(os.path.dirname(lib_config_path))
            lib_tag = _parent if _parent and _parent != 'tech' else 'EXPLICIT'
            args.lib_tag = lib_tag
        logger.info("Using explicit --lib-config: {}".format(lib_config_path))
    elif lib_tag:
        lib_config_path = _resolve_lib_config_path(tech_name, lib_tag, version)
        if not lib_config_path:
            # Distinguish the three failure modes so the error message
            # points at the ACTUAL cause (user misdirection = bad UX):
            #   (a) lib_tag_root was configured but rejected as in-tree
            #   (b) lib_tag_root set + tag missing under it
            #   (c) lib_tag_root unset + no legacy in-tree file either
            from library_manager_cmd import (
                _resolve_lib_tag_root as _rltr,
                _lib_tag_root_was_configured as _rltr_was,
            )
            _root = _rltr(tech_name, version)
            _was = _rltr_was(tech_name, version)
            if _was and not _root:
                logger.error("lib_config for tag '{}' not resolvable: "
                             "lib_tag_root was configured but REJECTED "
                             "(points inside the framework tree). See the "
                             "earlier ERROR line for the specific source.".format(lib_tag))
            elif _root:
                logger.error("No lib_config found for tag '{}'".format(lib_tag))
                logger.error("  Searched: {}/{}/lib_config.tcl".format(_root, lib_tag))
            else:
                logger.error("No lib_config found for tag '{}' in {}".format(
                    lib_tag, tech_dir))
            avail = _list_available_tags(tech_name, version)
            if avail:
                logger.error("  Available tags: {}".format(", ".join(avail)))
            logger.info("  Run: cbflow flow library-manager generate --tech {} --tag {}".format(
                tech_name, lib_tag))
            return 1
    else:
        # No tag given — auto-select if exactly one is available.
        avail = _list_available_tags(tech_name, version)
        if len(avail) == 1:
            lib_tag = avail[0]
            lib_config_path = _resolve_lib_config_path(tech_name, lib_tag, version)
            if not lib_config_path:
                # Race: tag was listed but file is gone, OR lib_tag_root
                # resolution disagrees with the listing (e.g. stale cache).
                logger.error("Auto-selected tag '{}' but its lib_config.tcl "
                             "could not be resolved.".format(lib_tag))
                logger.info("  Run: cbflow flow library-manager generate "
                            "--tech {} --tag {}".format(tech_name, lib_tag))
                return 1
            logger.info("Auto-selected tag: {} (only one available)".format(lib_tag))
        elif len(avail) > 1:
            # Interactive: prompt the user to pick one. Non-interactive
            # (CI, pipes): keep the hard-error so scripts fail fast.
            if sys.stdin.isatty():
                print('')
                print('  Multiple lib_config tags available for {}:'.format(tech_name))
                for i, t in enumerate(avail, 1):
                    print('    {}. {}'.format(i, t))
                choice = input('  Select tag [1-{}]: '.format(len(avail))).strip()
                picked = ''
                try:
                    idx = int(choice) - 1
                    if 0 <= idx < len(avail):
                        picked = avail[idx]
                except ValueError:
                    if choice in avail:
                        picked = choice
                if not picked:
                    logger.error("Invalid selection; aborting.")
                    return 1
                lib_tag = picked
                lib_config_path = _resolve_lib_config_path(
                    tech_name, lib_tag, version)
                if not lib_config_path:
                    logger.error("Tag '{}' selected but its lib_config.tcl "
                                 "could not be resolved.".format(lib_tag))
                    return 1
                logger.info("Selected tag: {}".format(lib_tag))
            else:
                logger.error("Multiple lib_config tags available:")
                for t in avail:
                    logger.error("  --lib-tag {}".format(t))
                logger.error("Please specify --lib-tag to select one")
                return 1
        else:
            logger.error("No lib_config found under {}".format(tech_dir))
            logger.info("  Run: cbflow flow library-manager generate --tech {} --tag <tag>".format(tech_name))
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

    # ── Pre-flight: refuse to generate if any requested PVT combo is missing ──
    # Historically we silently skipped combos with no matching lib_set_ref and
    # wrote a partial mmmc_config. The user sees "generated" but downstream STA
    # fails at the missing corner. Now: fail-fast unless --allow-missing is set.
    _allow_missing = (getattr(args, 'allow_missing', False)
                      or os.environ.get('CBFLOW_ALLOW_MISSING', '').lower() in ('1', 'true', 'yes'))
    if missing_refs and not _allow_missing:
        print('')
        print('  ═══════════════════════════════════════════════════════════')
        print('  ERROR: Pre-flight failed — {} requested PVT combo(s) have no'.format(len(missing_refs)))
        print('         matching lib_set_ref in {}'.format(os.path.basename(lib_config_path)))
        print('  ═══════════════════════════════════════════════════════════')
        for _ref in sorted(missing_refs):
            _key = 'tech({},lib,{},timing)'.format(track_for_check or '<track>', _ref)
            print('    [MISSING] {}'.format(_key))
        print('')
        print('  Requested PVT matrix:')
        for _c in corners_input:
            print('    corner={} voltages={} temps={}'.format(_c, ' '.join(voltages_input), ' '.join(temps_input)))
        print('')
        print('  Fix — pick one:')
        print('    (a) Add the missing lib_set_ref entries to the tech config')
        print('        (or run: cbflow flow library-manager generate --tech <t>)')
        print('    (b) Re-run this command with a narrower --corners / --voltages')
        print('        / --temperatures list that only covers characterised PVT')
        print('    (c) Re-run with --allow-missing (or export CBFLOW_ALLOW_MISSING=1')
        print('        for CI/nightly wrappers) if you MUST proceed with a partial')
        print('        mmmc_config (bootstrapping only) — downstream STA WILL fail')
        print('        at the missing corners')
        print('')
        return 1

    if missing_refs:
        # --allow-missing path: warn loudly, then continue with skipped_pvt
        print('')
        print('  ═══════════════════════════════════════════════════════════')
        print('  WARNING: --allow-missing set — skipping {} PVT combo(s):'.format(len(missing_refs)))
        for _ref in sorted(missing_refs):
            print('    [SKIP] {}'.format(_ref))
        print('  Generated mmmc_config will be INCOMPLETE.')
        print('  ═══════════════════════════════════════════════════════════')

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

    # ── Output locations (resolved first: the config being replaced is the
    #    source for modes, RC corners and scenario sets) ──
    # Default output location: the SAME directory as lib_config.tcl.
    # When the user invokes with --lib-config /path/to/.../tag/lib_config.tcl,
    # we write mmmc_config.tcl to /path/to/.../tag/ — co-located so a
    # single tag directory ships both configs. If --project is passed
    # (legacy per-project workflow) we honor it by also writing a copy
    # under <project>/v1.0.0/mmmc_config.tcl.
    project_name = args.project if hasattr(args, 'project') and args.project else None
    # Primary output: alongside lib_config.
    output_path = os.path.join(os.path.dirname(lib_config_path), 'mmmc_config.tcl')
    logger.info("Primary mmmc output: {}".format(output_path))

    # Optional secondary: per-project mmmc_config.tcl (keeps legacy
    # flow-cascade working for projects that still read from their
    # project config dir).
    proj_output_path = None
    if project_name:
        from core.paths import get_global_config_root
        _grot = get_global_config_root()
        proj_dir = None
        for root in filter(None, [_grot and os.path.join(_grot, 'project'),
                                   os.path.join(core_dir, 'config', 'project')]):
            candidate = os.path.join(root, project_name, version)
            if os.path.isdir(candidate):
                proj_dir = candidate
                break
        if proj_dir is None:
            logger.warning("Project '{}' dir not found; skipping per-project mirror".format(
                project_name))
        else:
            proj_output_path = os.path.join(proj_dir, 'mmmc_config.tcl')
            logger.info("Secondary mmmc output (per-project): {}".format(proj_output_path))

    # The existing config this run replaces — project copy wins, since
    # that is the one the flow cascade sources.
    prior_cfg_path = next((c for c in (proj_output_path, output_path)
                           if c and os.path.exists(c)), None)
    prior_cfg = None
    if prior_cfg_path:
        prior_cfg = MmmcConfigParser(prior_cfg_path)
        if not prior_cfg.parse():
            logger.error("Existing {} could not be parsed — refusing to "
                         "regenerate over it".format(prior_cfg_path))
            return 1
    # Node scenarios + view definition belong next to the config the flows
    # read: the project dir when --project is given, else beside lib_config.
    aux_dir = os.path.dirname(proj_output_path or output_path)

    # ── 5. Operating modes ──
    modes = {}
    sdc_pattern = args.sdc_pattern if hasattr(args, 'sdc_pattern') and args.sdc_pattern else '${design_name}_{mode}.sdc'
    if hasattr(args, 'modes') and args.modes:
        for mode_name in args.modes.split():
            modes[mode_name] = sdc_pattern.replace('{mode}', mode_name)
    else:
        if prior_cfg:
            for m, props in prior_cfg.operating_modes.items():
                modes[m] = props.get('constraint_file') or sdc_pattern.replace('{mode}', m)
        if not modes:
            modes = {'func': '${design_name}_func.sdc', 'test': '${design_name}_test.sdc'}

    # ── 6. RC corners: carried over from the config being replaced, so
    #    project-specific names (wcrcmin, wcrcworst, …) survive a regenerate.
    #    Only a first-time generate seeds the rc_max / rc_typ / rc_min triad.
    rc_corners_data = dict(prior_cfg.rc_corners) if prior_cfg else {}
    # Validate BEFORE anything is written: a carried-over RC corner without
    # a temperature fails `validate`, so refuse to regenerate around it.
    _bad_rc = [n for n, props in rc_corners_data.items()
               if not (props or {}).get('temperature')]
    if _bad_rc:
        logger.error("rc_corners in {} have no temperature: {} — fix them "
                     "first; nothing was written".format(
                         prior_cfg_path, ' '.join(sorted(_bad_rc))))
        return 1
    if not rc_corners_data:
        logger.warning("No existing mmmc_config.tcl to take rc_corners from — "
                       "seeding rc_max / rc_typ / rc_min; edit them (or use "
                       "mmmc-manager add-rc) to match the tech's RC corners")
        rc_corners_data = {
            'rc_max': {'temperature': '125', 'metal_multiplier': '1.15', 'via_multiplier': '1.25',
                       'cap_multiplier': '1.10', 'res_multiplier': '1.15'},
            'rc_typ': {'temperature': '25', 'metal_multiplier': '1.00', 'via_multiplier': '1.00',
                       'cap_multiplier': '1.00', 'res_multiplier': '1.00'},
            'rc_min': {'temperature': '-40', 'metal_multiplier': '0.85', 'via_multiplier': '0.75',
                       'cap_multiplier': '0.90', 'res_multiplier': '0.85'},
        }

    # ── 7. Node assignments (only from valid PVT) ──
    # Analysis views are a full Cartesian: mode x corner x pvt x rc_corner.
    # The generator never decides which view serves setup / hold / power,
    # and never pairs a process corner with an RC corner — that is project
    # policy, declared by engineers in mmmc_scenario_sets and
    # mmmc_node_scenarios.tcl.
    view_fields = {}   # view name -> {mode, corner, voltage, temp, rc, lib_set_ref}
    for _mode in sorted(modes.keys()):
        for _corner in process_corners:
            for _v, _t in valid_pvt.get(_corner, []):
                for _rc in sorted(rc_corners_data.keys()):
                    view_fields['{}_{}_{}_{}_{}'.format(_mode, _corner, _v, _rc, _t)] = {
                        'mode': _mode, 'corner': _corner, 'voltage': _v,
                        'temp': _t, 'rc': _rc,
                        'lib_set_ref': '{}_{}_{}'.format(_corner, _v, _t),
                    }
    total_views = len(view_fields)

    # ── Discover real node_types from project's active flows ──
    # Read project(default_tools) to find active flows, then read their node_configs
    _active_node_types = set()
    project_name = args.project if hasattr(args, 'project') and args.project else None
    # Try to find project config for flow detection
    _proj_config = ''
    if project_name:
        _proj_config = os.path.join(core_dir, 'config', 'project', project_name, version,
                                    '{}_config.tcl'.format(project_name))
    _active_flows = []
    if os.path.exists(_proj_config):
        with open(_proj_config, 'r') as _pf:
            _pc = _pf.read()
        # Parse project(default_tools) { SYNTH "genus" PNR "innovus" ... }
        m = re.search(r'set\s+project\(default_tools\)\s*\{([^}]+)\}', _pc)
        if m:
            _pairs = m.group(1).split()
            _active_flows = [_pairs[i] for i in range(0, len(_pairs), 2)]
            logger.info("Active flows from project: {}".format(' '.join(_active_flows)))

    if _active_flows:
        flow_config_ver = version
        for flow in _active_flows:
            nc_path = os.path.join(core_dir, 'config', 'flow', flow_config_ver,
                                   'node_configs', '{}_config.tcl'.format(flow))
            if os.path.exists(nc_path):
                with open(nc_path, 'r') as _nf:
                    for _m in re.finditer(r'node_types,\S+\s+"([^"]+)"', _nf.read()):
                        nt = _m.group(1)
                        # Only timing-driven node_types need MMMC scenarios
                        # Exclude: inputs, export, release, merge, reporting,
                        #          PV stages, LEC/CLP, EMIR analysis
                        _non_mmmc = ('inputs', 'export_data', 'export_db',
                                     'release_data', 'merge_data', 'reporting',
                                     'drc', 'lvs', 'fill', 'erc', 'perc', 'xor',
                                     'compare', 'clp', 'eco',
                                     'power_analysis', 'ir_drop', 'thermal_analysis')
                        if nt not in _non_mmmc:
                            _active_node_types.add(nt)
        logger.info("Active node_types: {}".format(' '.join(sorted(_active_node_types))))

    if not _active_node_types:
        # Fallback: common node_types across major flows
        _active_node_types = {'init_design', 'synthesis', 'place', 'cts', 'cts_opt',
                              'route', 'pro', 'signoff', 'timing', 'extraction'}
        logger.info("Using default node_types (no project flows detected)")

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

    # RC corners — declared BEFORE view generation: the Cartesian loop
    # iterates [array names rc_corners].
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

    # Analysis views — full Cartesian, no role → RC mapping
    w('# ' + '=' * 77)
    w('# ANALYSIS VIEWS — FULL CARTESIAN: mode x corner x pvt x rc_corner')
    w('# The framework imposes no setup/hold role and no corner -> RC pairing.')
    w('# Engineers pick the views for each purpose in mmmc_scenario_sets below.')
    w('# View name: ${mode}_${corner}_${voltage}_${rc_corner}_${temp}')
    w('# ' + '=' * 77)
    w('')
    w('array set analysis_views {}')
    w('foreach _mode [array names operating_modes] {')
    w('    set _sdc [dict get $operating_modes($_mode) constraint_file]')
    w('    foreach _corner $mmmc(process_corners) {')
    w('        if {![info exists mmmc(pvt,$_corner)]} continue')
    w('        foreach _pvt $mmmc(pvt,$_corner) {')
    w('            set _v [lindex $_pvt 0]')
    w('            set _t [lindex $_pvt 1]')
    w('            foreach _rc_name [array names rc_corners] {')
    w('                set _name "${_mode}_${_corner}_${_v}_${_rc_name}_${_t}"')
    w('                set _lib_ref "${_corner}_${_v}_${_t}"')
    w('                set analysis_views($_name) [list \\')
    w('                    corner $_corner mode $_mode voltage $_v temperature $_t \\')
    w('                    constraint_file $_sdc \\')
    w('                    lib_set_ref $_lib_ref rc_corner $_rc_name]')
    w('            }')
    w('        }')
    w('    }')
    w('}')
    w('')

    # Scenario sets — engineer-declared. Carry forward whatever the config
    # being replaced already declares (dropping names that are no longer
    # generated views); a first-time generate emits empty lists to fill in.
    _DERIVED_SETS = ('all', 'sta_setup', 'sta_hold', 'sta_signoff')
    prior_sets = {}
    if prior_cfg_path:
        _prior = execute_tcl_config(prior_cfg_path)
        if _prior is None:
            logger.warning("Could not read scenario sets from existing {} — "
                           "they will NOT be carried forward".format(prior_cfg_path))
        else:
            prior_sets = _prior['scenario_sets']
    dropped_set_members = {}
    kept_sets = {}
    _carry = {k: v for k, v in prior_sets.items() if k not in _DERIVED_SETS}
    for _src, _name in _stale_references(view_fields, _carry):
        dropped_set_members.setdefault(_src[1], []).append(_name)
    for _sname, _members in _carry.items():
        kept_sets[_sname] = [v for v in _members if v in view_fields]
    for _base in ('setup', 'hold', 'power'):
        kept_sets.setdefault(_base, [])

    def _emit_set(name, members):
        if not members:
            w('set mmmc_scenario_sets({}) {{}}'.format(name))
            return
        w('set mmmc_scenario_sets({}) {{'.format(name))
        for _m in members:
            w('    {}'.format(_m))
        w('}')

    w('# ── Scenario sets — EXPLICIT, engineer-declared ──')
    w('# Each set lists analysis-view names (keys of analysis_views above).')
    w('#   setup / hold : drive setup/hold roles in FC, DMSA and Cadence views')
    w('#   power        : views for power analysis')
    w('#   signoff      : full sign-off set (STA fans out over this by default)')
    w('#   all          : every generated view (auto)')
    w('# List names with: cbflow flow mmmc-manager list-views')
    w('# Check for stale names after changing PVT/modes/RC corners with:')
    w('#   cbflow flow mmmc-manager validate')
    w('array set mmmc_scenario_sets {}')
    for _base in ('setup', 'hold', 'power'):
        _emit_set(_base, kept_sets[_base])
    _so = kept_sets.get('signoff')
    if _so and _so != kept_sets['setup'] + kept_sets['hold']:
        _emit_set('signoff', _so)
    else:
        w('set mmmc_scenario_sets(signoff) [concat \\')
        w('    $mmmc_scenario_sets(setup) $mmmc_scenario_sets(hold)]')
    for _sname in sorted(kept_sets):
        if _sname not in ('setup', 'hold', 'power', 'signoff'):
            _emit_set(_sname, kept_sets[_sname])
    w('set mmmc_scenario_sets(all)         [lsort [array names analysis_views]]')
    w('set mmmc_scenario_sets(sta_setup)   $mmmc_scenario_sets(setup)')
    w('set mmmc_scenario_sets(sta_hold)    $mmmc_scenario_sets(hold)')
    w('set mmmc_scenario_sets(sta_signoff) $mmmc_scenario_sets(signoff)')
    w('')

    # Node assignments live in the sibling mmmc_node_scenarios.tcl
    w('# ' + '=' * 77)
    w('# NODE-SPECIFIC SCENARIO ASSIGNMENTS')
    w('# Declared in mmmc_node_scenarios.tcl next to this file (engineer-managed;')
    w('# edit with: cbflow flow mmmc-manager set-node)')
    w('# ' + '=' * 77)
    w('')

    # Node-scenario template: one entry per timing-driven node type, with
    # EMPTY setup/hold lists. Which views a node times is project policy.
    node_lines = []
    nw = node_lines.append
    nw('# ── MMMC Node Scenario Assignments ──')
    nw('# Template from: cbflow flow mmmc-manager generate --tech {}'.format(tech_name))
    nw('# Fill each node with analysis-view names (see: mmmc-manager list-views),')
    nw('# by hand or with: cbflow flow mmmc-manager set-node --node <n> --setup "..." --hold "..."')
    nw('array set mmmc {')
    for node_name in sorted(_active_node_types):
        nw('    {} {{'.format(node_name))
        nw('        setup {}')
        nw('        hold  {}')
        nw('    }')
        nw('')
    nw('}')
    node_assignment_text = '\n'.join(node_lines) + '\n'

    # Write — confirm overwrite + backup
    output_text = '\n'.join(lines) + '\n'

    if os.path.exists(output_path):
        print('  WARNING: {} already exists'.format(output_path))
        if sys.stdin.isatty():
            confirm = input('  Overwrite? (y/n) [y]: ').strip().lower()
            if confirm and confirm not in ('y', 'yes'):
                print('  Aborted — no changes made.')
                return 0
        # Route through shared helper so the backup lands in `backup/` under
        # the config directory (not inline). See _backup_config().
        backup_path = _backup_config(output_path)
        print('  Backup: {}'.format(backup_path))

    # Atomic rewrite — pre-fix non-atomic open-w could truncate on kill.
    from core.paths import atomic_write
    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
    except OSError:
        pass
    atomic_write(output_path, output_text)

    # If --project was given, mirror to the per-project location too so
    # the flow cascade (which still reads project_config/mmmc_config.tcl)
    # keeps working.
    if proj_output_path:
        try:
            os.makedirs(os.path.dirname(proj_output_path), exist_ok=True)
        except OSError:
            pass
        atomic_write(proj_output_path, output_text)
        print('  Also wrote: {}'.format(proj_output_path))

    # Node assignments are engineer-managed: write the empty template only
    # when no file exists yet. An existing file is kept, and names in it
    # that are no longer generated views are reported.
    node_template_path = os.path.join(aux_dir, 'mmmc_node_scenarios.tcl')
    stale_node_names = []
    if os.path.exists(node_template_path):
        _ns = MmmcConfigParser(node_template_path)
        if _ns.parse():
            stale_node_names = [
                '{}: {}'.format(_stale_label(_src), _n)
                for _src, _n in _stale_references(
                    view_fields, node_mappings=_ns.node_mappings)]
        print('  Node scenarios kept (engineer-managed): {}'.format(node_template_path))
    else:
        atomic_write(node_template_path, node_assignment_text)
        print('  Node scenario template (empty — fill in): {}'.format(node_template_path))

    # ── Generate Cadence MMMC View Definition File ──
    # Defines the engineer's sign-off set; nodes activate their own subset.
    # With no scenario sets declared yet there is nothing to select, so the
    # file is not written — run `mmmc-manager generate-view-def --style flow`
    # once the sets are filled in.
    _vd_setup = kept_sets['setup']
    _vd_hold = kept_sets['hold']
    _vd_selected = sorted(set(_vd_setup) | set(_vd_hold)
                          | set(kept_sets.get('signoff') or []))
    vd_path = os.path.join(aux_dir, 'mmmc_view_definition.tcl')
    if _vd_selected:
        atomic_write(vd_path, _render_flow_view_definition(
            tech_name, project_name, _vd_selected, view_fields,
            rc_corners_data, _vd_setup, _vd_hold))
        print('  View definition: {}'.format(vd_path))
    else:
        print('  View definition NOT written — mmmc_scenario_sets are empty.')

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
    print('    Analysis views: {} (modes x PVT points x {} RC corners)'.format(
        total_views, len(rc_corners_data)))
    if vt_filter:
        print('    VT filter: {}'.format(' '.join(vt_filter)))
    print('')
    print('  Scenario sets (engineer-declared, carried forward where still valid):')
    for _sname in ('setup', 'hold', 'power'):
        print('    {:<8} {} views'.format(_sname + ':', len(kept_sets[_sname])))
    for _sname, _gone in sorted(dropped_set_members.items()):
        logger.warning("scenario set '{}': dropped {} name(s) that are no longer "
                       "generated views: {}".format(_sname, len(_gone), ' '.join(_gone)))
    if not kept_sets['setup'] and not kept_sets['hold']:
        logger.warning("mmmc_scenario_sets(setup) and (hold) are EMPTY in the "
                       "generated config — list the views for each in {} before "
                       "running flows (names: mmmc-manager list-views)".format(output_path))
    if stale_node_names:
        logger.warning("{} node-scenario name(s) in {} are not generated views — "
                       "fix with mmmc-manager set-node: {}".format(
                           len(stale_node_names), node_template_path,
                           '; '.join(stale_node_names)))
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
    p.add_argument('--style', choices=['standalone', 'flow'], default='standalone',
                   help='standalone (default): self-contained file, every view, '
                        'library paths via ::lib_dir. flow: the '
                        'mmmc_view_definition.tcl the Cadence flows read — '
                        'views from mmmc_scenario_sets setup+hold+signoff, '
                        'libraries/QRC via $::tech(...).')

    # -- generate --
    p = sub.add_parser('generate',
                       help='Generate mmmc_config.tcl — interactive CLI, validated against lib_config')
    p.add_argument('--tech', default=None,
                   help='Technology name (e.g., gf_22nm). Prompted if omitted. '
                        'Optional when --tech-config is set.')
    p.add_argument('--tech-config', default=None,
                   help='Path to tech_config.tcl. Takes precedence over --tech/CBFLOW_TECH_NODE '
                        '— use when running outside a flow dir with a raw path.')
    p.add_argument('--lib-config', default=None,
                   help='Path to lib_config.tcl. When set, this is the authoritative '
                        'library config — bypasses --lib-tag / lib_tag_root resolution. '
                        'Pair with --tech-config to run fully config-path-driven, no '
                        'framework-tree lookup needed.')
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
    p.add_argument('--project', default=None,
                   help='Project name (e.g., denali). Output goes to config/project/<name>/v1.0.0/')
    p.add_argument('--allow-missing', action='store_true', default=False,
                   help='Proceed even if requested PVT combos have no matching lib_set_ref '
                        'in lib_config. Default is fail-fast — use only when bootstrapping.')

    # Make --project a universal flag — accepted before OR after the subcommand.
    # argparse keeps subparser args scoped to their parser, so the top-level
    # --project isn't visible to a subparser; mirror it onto every subparser
    # that doesn't already define it (just `generate` has its own).
    for name, p in sub.choices.items():
        if not any(a.option_strings == ['--project'] for a in p._actions):
            p.add_argument('--project', default=None,
                           help='Project name (resolves mmmc_config.tcl path)')

    # Make --tech a universal flag on every subparser so the preflight's
    # "pass --tech <name>" error message is actually actionable (previously
    # only `generate` accepted --tech; show/validate/list-* etc. forced
    # the user to export CBFLOW_TECH_NODE or pass --tech-config).
    for name, p in sub.choices.items():
        if not any(a.option_strings == ['--tech'] for a in p._actions):
            p.add_argument('--tech', default=None,
                           help='Technology name (resolves tech_config.tcl path)')

    return top


# ===============================================================================
# Main Entry Point
# ===============================================================================

DISPATCH = {
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


def main() -> int:
    """Main entry point for mmmc-manager.

    With a subcommand: preflight tech_config, then dispatch.
    Without a subcommand: drop into an interactive REPL that prompts for
        tech and accepts subcommands until the user types exit.
    """
    top = create_parser()
    args = top.parse_args()

    # No subcommand → interactive REPL (per user request: prompt, don't die)
    if not args.command:
        return run_repl(top, DISPATCH, tool_name="mmmc-manager", logger=logger)

    handler = DISPATCH.get(args.command)
    if not handler:
        logger.error("Unknown command: %s", args.command)
        return 1

    # ── Hard gate: every subcommand requires tech_config.tcl ───────────
    # No exceptions. Adding a new subcommand cannot silently bypass this
    # because it's here at the dispatcher, not inside individual handlers.
    # Interactive mode is exempt from this hard-exit — the REPL prompts
    # for tech and calls require_tech_config directly.
    preflight_tech_config_or_exit(args, tool_name="mmmc-manager")

    try:
        rc = handler(args)
        return rc if isinstance(rc, int) else 0
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
