"""DEF + LEF parsers for the CBflow-ProjectDashboard floorplan viewer.

Extracts the minimum needed to render a management-facing floorplan canvas:

  - DIEAREA (design boundary rectangle/polygon)
  - ROWS  (site rows for placement guides)
  - COMPONENTS (cell name, macro, x/y, orientation)
  - MACRO SIZE (x, y) from LEF — used to draw each cell rectangle

We deliberately do NOT parse PINS, NETS, VIAS, obstructions, or the full LEF
cell geometry. The goal is a schematic overview, not a full layout viewer.

Parsers are hand-rolled (no external deps), stream line-by-line, and cope
with truncated / test-mode stub DEF files by returning empty lists.
"""

import glob
import os
import re


# ─── DEF ────────────────────────────────────────────────────────────────────

_DEF_UNITS_RE = re.compile(r'^\s*UNITS\s+DISTANCE\s+MICRONS\s+(\d+)\s*;',
                            re.I | re.M)
# DIEAREA can be a rectangle or a polygon; we take the bounding box.
_DEF_DIEAREA_RE = re.compile(r'^\s*DIEAREA\s+(.+?)\s*;', re.I | re.M | re.S)
_DEF_ROW_RE = re.compile(
    r'^\s*ROW\s+(\S+)\s+(\S+)\s+(-?\d+)\s+(-?\d+)\s+(\S+)\s+'
    r'(?:DO\s+(\d+)\s+BY\s+(\d+)\s+STEP\s+(\d+)\s+(\d+))?',
    re.I)
_DEF_COMP_HDR_RE = re.compile(r'^\s*COMPONENTS\s+(\d+)\s*;', re.I)
_DEF_COMP_END_RE = re.compile(r'^\s*END\s+COMPONENTS\s*$', re.I)
# Component entry — may span multiple lines. We accept both single-line and
# multi-line forms. Body of interest: `- <name> <macro> [... + PLACED ( x y ) N ]`.
_DEF_COMP_RE = re.compile(
    r'-\s+(\S+)\s+(\S+).*?\+\s*(?:PLACED|FIXED|COVER)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*(\S+)?',
    re.I | re.S)


def parse_def(path, max_cells=200000, density_cols=400, density_rows=200,
              macro_heights_um=None):
    """Return {boundary, rows, cells, density, units} extracted from a DEF file.

    boundary: {'x1', 'y1', 'x2', 'y2'} in DEF units (typically nm)
    rows:     list of {'name', 'site', 'x', 'y', 'orient', 'count_x', 'count_y',
                       'step_x', 'step_y'}
    cells:    list of {'name', 'macro', 'x', 'y', 'orient'}. Downsampled to
              `max_cells` for the interactive layer (browser can't fillRect
              5M rectangles in real time). The overview is unaffected — see
              `density`, which is computed over ALL parsed cells.
    density:  {'cols', 'rows', 'counts', 'max', 'total'} — an integer grid
              of cell counts over the die area. Constant-cost overview: works
              at any cell count because the grid size is fixed.
    units:    int (DBUs per micron), default 1000
    """
    out = {'boundary': {}, 'rows': [], 'cells': [],
           'density': {'cols': 0, 'rows': 0, 'counts': [], 'max': 0, 'total': 0},
           'units': 1000}
    if not path or not os.path.isfile(path):
        return out

    try:
        with open(path, errors='replace') as f:
            content = f.read()
    except OSError:
        return out

    # Units
    m = _DEF_UNITS_RE.search(content)
    if m:
        try:
            out['units'] = int(m.group(1))
        except ValueError:
            pass

    # DIEAREA — bounding box across all points listed.
    m = _DEF_DIEAREA_RE.search(content)
    if m:
        pts = re.findall(r'\(\s*(-?\d+)\s+(-?\d+)\s*\)', m.group(1))
        if pts:
            xs = [int(x) for x, _ in pts]
            ys = [int(y) for _, y in pts]
            out['boundary'] = {'x1': min(xs), 'y1': min(ys),
                               'x2': max(xs), 'y2': max(ys)}

    # ROWS
    for line in content.splitlines():
        rm = _DEF_ROW_RE.match(line)
        if rm:
            out['rows'].append({
                'name': rm.group(1), 'site': rm.group(2),
                'x': int(rm.group(3)), 'y': int(rm.group(4)),
                'orient': rm.group(5),
                'count_x': int(rm.group(6)) if rm.group(6) else 1,
                'count_y': int(rm.group(7)) if rm.group(7) else 1,
                'step_x':  int(rm.group(8)) if rm.group(8) else 0,
                'step_y':  int(rm.group(9)) if rm.group(9) else 0,
            })

    # COMPONENTS — parse only the block bounded by `COMPONENTS N ;` /
    # `END COMPONENTS` so we don't confuse `- <name>` lines outside of it.
    for i, line in enumerate(content.splitlines()):
        if _DEF_COMP_HDR_RE.match(line):
            start = i
            break
    else:
        start = None
    if start is not None:
        block_lines = []
        for line in content.splitlines()[start:]:
            if _DEF_COMP_END_RE.match(line):
                break
            block_lines.append(line)
        # Components can span multiple lines terminated by `;`. Split on `;`.
        text = ' '.join(block_lines)
        entries = [e.strip() for e in text.split(';') if e.strip().startswith('-')]
        for e in entries:
            cm = _DEF_COMP_RE.search(e)
            if cm:
                out['cells'].append({
                    'name': cm.group(1),
                    'macro': cm.group(2),
                    'x': int(cm.group(3)),
                    'y': int(cm.group(4)),
                    'orient': cm.group(5) or 'N',
                })

    # Density grid — computed BEFORE downsampling so the overview reflects
    # every cell in the DEF, not just the sampled subset. Bucket size is
    # derived from the DIEAREA so tall/thin dies still get useful resolution.
    b = out['boundary']
    if b and out['cells']:
        dw = b['x2'] - b['x1']
        dh = b['y2'] - b['y1']
        if dw > 0 and dh > 0:
            # Pick cols/rows keeping bucket aspect roughly square.
            aspect = dw / dh
            if aspect >= 1:
                cols = density_cols
                rows = max(4, int(density_cols / aspect))
            else:
                rows = density_rows
                cols = max(4, int(density_rows * aspect))
            grid = [0] * (cols * rows)
            gx_scale = cols / dw
            gy_scale = rows / dh
            max_count = 0
            for c in out['cells']:
                gx = int((c['x'] - b['x1']) * gx_scale)
                gy = int((c['y'] - b['y1']) * gy_scale)
                if gx < 0: gx = 0
                if gy < 0: gy = 0
                if gx >= cols: gx = cols - 1
                if gy >= rows: gy = rows - 1
                idx = gy * cols + gx
                grid[idx] += 1
                if grid[idx] > max_count:
                    max_count = grid[idx]
            out['density'] = {
                'cols': cols, 'rows': rows,
                'counts': grid, 'max': max_count,
                'total': len(out['cells']),
            }

    # Downsample stdcells for the interactive layer. The density grid above
    # is authoritative for the overview; this only limits how many
    # rectangles the browser has to hit-test during zoom-in.
    #
    # Hard macros (SRAM / ROM / block-level) are ALWAYS preserved — they're
    # what management cares most about in a floorplan view. Detection uses
    # the LEF macro heights (if the client passed them in) plus a name
    # heuristic (SRAM/ROM/MEM/CACHE) as a fallback when the LEF is missing.
    if len(out['cells']) > max_cells:
        # Estimate the row band height so we can classify macros = h ≥ 1.5 rows.
        # rowStep already computed for the density grid; recompute here too.
        rowYs = sorted(r['y'] for r in out['rows'])
        row_step = 0
        for i in range(1, len(rowYs)):
            d = rowYs[i] - rowYs[i-1]
            if d > 0 and (row_step == 0 or d < row_step):
                row_step = d
        if not row_step:
            row_step = 2000

        macro_h_um = macro_heights_um or {}
        cutoff_um = row_step * 1.5 / (out['units'] or 1000)
        name_re = re.compile(r'^(SRAM|ROM|MEM|CACHE|RF|IPRAM|DPRAM)',
                             re.I)

        def _is_macro(cell):
            h = macro_h_um.get(cell['macro'])
            if h is not None:
                return h >= cutoff_um
            return bool(name_re.match(cell['macro']))

        macros_cells = [c for c in out['cells'] if _is_macro(c)]
        std_cells    = [c for c in out['cells'] if not _is_macro(c)]

        # Downsample the stdcell layer only.
        step = max(1, len(std_cells) // max(1, max_cells - len(macros_cells)))
        std_kept = std_cells[::step]
        out['cells'] = std_kept + macros_cells
        out['downsampled'] = True
        out['preserved_macros'] = len(macros_cells)

    return out


# ─── LEF (macro SIZE only) ──────────────────────────────────────────────────

_LEF_MACRO_RE = re.compile(r'^\s*MACRO\s+(\S+)', re.I)
_LEF_SIZE_RE = re.compile(
    r'^\s*SIZE\s+([\d.]+)\s+BY\s+([\d.]+)\s*;', re.I)
_LEF_END_MACRO_RE = re.compile(r'^\s*END\s+(\S+)\s*$', re.I)


def parse_lef_macros(path):
    """Return {macro_name: {'w': width_um, 'h': height_um}}.

    Only reads MACRO ... SIZE lines. Skips PINS, OBS, geometry, PROPERTY.
    """
    out = {}
    if not path or not os.path.isfile(path):
        return out
    try:
        with open(path, errors='replace') as f:
            current_macro = None
            for line in f:
                mm = _LEF_MACRO_RE.match(line)
                if mm:
                    current_macro = mm.group(1)
                    continue
                if current_macro:
                    sm = _LEF_SIZE_RE.match(line)
                    if sm:
                        out[current_macro] = {
                            'w': float(sm.group(1)),
                            'h': float(sm.group(2)),
                        }
                        continue
                    em = _LEF_END_MACRO_RE.match(line)
                    if em and em.group(1) == current_macro:
                        current_macro = None
    except OSError:
        return out
    return out


def parse_lef_dir(lef_paths):
    """Parse a list of LEF files and merge their macro tables.

    Later files override earlier ones for duplicate macro names (last wins,
    matching how EDA tools apply LEF include order).
    """
    macros = {}
    for p in lef_paths:
        for k, v in parse_lef_macros(p).items():
            macros[k] = v
    return macros


# ─── Extraction from a release ──────────────────────────────────────────────

# The resolved node config.tcl lists per-stack per-track tech LEF and per-track
# cell LEF lists. We look for these known key patterns.
_LEF_KEYS_IN_RESOLVED = (
    'tech(*,*,lef_tech)',
    'tech(*,lef)',
    'pnr(input,lef_files)',
    'synth_pnr(input,lef_files)',
    'fp(input,lef_files)',
)


def _find_def(release_dir):
    """Prefer signoff → PNR → SYNTH_PNR → FP → any *.def."""
    for flow in ('PNR', 'SYNTH_PNR', 'FP', 'SYNTH'):
        for cand in (
            os.path.join(release_dir, flow, 'def'),
            os.path.join(release_dir, flow),
        ):
            if os.path.isdir(cand):
                defs = sorted(glob.glob(os.path.join(cand, '*.def')))
                if defs:
                    return defs[0]
    hits = sorted(glob.glob(os.path.join(release_dir, '**', '*.def'),
                            recursive=True))
    return hits[0] if hits else ''


def _collect_lefs_from_config(config_path):
    """Grep a resolved config.tcl for LEF file paths.

    We don't try to source the TCL — a regex sweep is enough because the
    resolver emits `set tech(...) "/path/to/x.lef"` and `set <flow>(input,lef_files) [list "..."]`.
    Duplicates removed while preserving order.
    """
    lefs = []
    if not config_path or not os.path.isfile(config_path):
        return lefs
    try:
        with open(config_path, errors='replace') as f:
            text = f.read()
    except OSError:
        return lefs
    # `set ... "/absolute/path.lef"`
    for m in re.finditer(r'set\s+[^\s]+\s+"([^"]+\.lef)"', text, re.I):
        lefs.append(m.group(1))
    # `set ... [list "..." "..."]` — grab every quoted .lef inside a list
    for m in re.finditer(r'set\s+[^\s]+\s+\[list\s+(.+?)\]', text, re.S):
        for lm in re.finditer(r'"([^"]+\.lef)"', m.group(1), re.I):
            lefs.append(lm.group(1))
    seen, ordered = set(), []
    for p in lefs:
        if p in seen:
            continue
        seen.add(p)
        ordered.append(p)
    return ordered


def _find_resolved_config(run_dir):
    """Find any node's resolved config.tcl for the LEF path sweep. Prefer
    PNR/SYNTH_PNR init_design since those load the widest LEF set."""
    for candidate in (
        'work/PNR/init_design1/run/config.tcl',
        'work/SYNTH_PNR/init_design1/run/config.tcl',
        'work/FP/init_design1/run/config.tcl',
        'work/FCFP/init_design1/run/config.tcl',
    ):
        p = os.path.join(run_dir, candidate)
        if os.path.isfile(p):
            return p
    # Fallback: any config.tcl under work/
    hits = sorted(glob.glob(os.path.join(run_dir, 'work', '**', 'config.tcl'),
                            recursive=True))
    return hits[0] if hits else ''


def extract_from_release(release_dir, run_dir):
    """Build the floorplan payload for the publish snapshot.

    Returns a dict with 4 keys — safe to embed under payload['floorplan']:
      def_path         source DEF (empty if not found)
      lef_paths        list of LEFs we parsed
      def              output of parse_def()
      macros           output of parse_lef_dir()
    """
    payload = {
        'def_path': '',
        'lef_paths': [],
        'def': {'boundary': {}, 'rows': [], 'cells': [], 'units': 1000},
        'macros': {},
    }
    # 1. LEFs first — we need macro heights before parsing the DEF so the
    #    downsampler can preserve hard macros (SRAMs / blocks) regardless
    #    of where they appear in the file.
    lefs = []
    if run_dir:
        cfg_path = _find_resolved_config(run_dir)
        lefs = _collect_lefs_from_config(cfg_path)
    payload['lef_paths'] = lefs
    macros_all = parse_lef_dir(lefs) if lefs else {}
    macro_h_um = {k: v.get('h') for k, v in macros_all.items() if v.get('h')}

    # 2. DEF — parse_def receives the macro heights so it never drops a
    #    macro during the stdcell downsample.
    def_path = _find_def(release_dir) if release_dir else ''
    payload['def_path'] = def_path
    if def_path:
        payload['def'] = parse_def(def_path, macro_heights_um=macro_h_um)

    # 3. Trim the macros dict to only those referenced by DEF cells so the
    #    JSON stays small.
    cell_macros = {c['macro'] for c in payload['def']['cells']} if payload['def']['cells'] else set()
    if cell_macros:
        macros_all = {k: v for k, v in macros_all.items() if k in cell_macros}
    payload['macros'] = macros_all
    return payload
