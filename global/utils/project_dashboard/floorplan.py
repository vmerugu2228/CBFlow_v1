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

import dash_config


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


_LEF_PIN_RE = re.compile(r'^\s*PIN\s+(\S+)', re.I)
_LEF_DIR_RE = re.compile(r'^\s*DIRECTION\s+(\w+)', re.I)
_LEF_USE_RE = re.compile(r'^\s*USE\s+(\w+)', re.I)
_LEF_LAYER_RE = re.compile(r'^\s*LAYER\s+(\S+)', re.I)
_LEF_RECT_RE = re.compile(
    r'^\s*RECT\s+(?:MASK\s+\d+\s+)?(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s*;', re.I)
_MAX_PIN_RECTS = 12


def parse_lef_macros(path):
    """Return {macro: {'w', 'h', 'pins': {pin: {'dir', 'use', 'rects'}}}}.

    Reads MACRO SIZE and each PIN's DIRECTION / USE and PORT rectangles
    (µm, macro-local, at most _MAX_PIN_RECTS per pin — enough to draw pins
    inside a cell). Skips OBS, PROPERTY and everything else.
    """
    out = {}
    if not path or not os.path.isfile(path):
        return out
    try:
        with open(path, errors='replace') as f:
            current_macro = None
            pin = None
            layer = ''
            for line in f:
                mm = _LEF_MACRO_RE.match(line)
                if mm:
                    current_macro = mm.group(1)
                    out.setdefault(current_macro, {'w': 0.0, 'h': 0.0, 'pins': {}})
                    pin = None
                    continue
                if not current_macro:
                    continue
                em = _LEF_END_MACRO_RE.match(line)
                if em:
                    if pin is not None and em.group(1) == pin:
                        pin = None
                        continue
                    if em.group(1) == current_macro:
                        current_macro = None
                        pin = None
                        continue
                sm = _LEF_SIZE_RE.match(line)
                if sm:
                    out[current_macro]['w'] = float(sm.group(1))
                    out[current_macro]['h'] = float(sm.group(2))
                    continue
                pm = _LEF_PIN_RE.match(line)
                if pm:
                    pin = pm.group(1)
                    out[current_macro]['pins'][pin] = {'dir': '', 'use': '', 'rects': []}
                    continue
                if line.strip().upper().startswith('OBS'):
                    pin = None
                    continue
                if pin is None:
                    continue
                rec = out[current_macro]['pins'][pin]
                dm = _LEF_DIR_RE.match(line)
                if dm:
                    rec['dir'] = dm.group(1).upper()
                    continue
                um = _LEF_USE_RE.match(line)
                if um:
                    rec['use'] = um.group(1).upper()
                    continue
                lm = _LEF_LAYER_RE.match(line)
                if lm:
                    layer = lm.group(1)
                    continue
                rm = _LEF_RECT_RE.match(line)
                if rm and len(rec['rects']) < _MAX_PIN_RECTS:
                    rec['rects'].append([round(float(v), 4) for v in rm.groups()] + [layer])
    except OSError:
        return out
    return {k: v for k, v in out.items() if v['w'] and v['h']}


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

def _find_def(release_dir, block):
    """The released DEF: <release_dir>/<category>/<filename> from the
    release handshake map (flow_input_handshake(*,def_file) in
    release_config.tcl, ${design_name} = block). '' when not released."""
    category, pattern = dash_config.handshake_location('def_file')
    name = pattern.replace('${design_name}', block).replace('$design_name', block)
    p = os.path.join(release_dir, category, name)
    return p if os.path.isfile(p) else ''


def _lefs_in_tcl_text(text):
    """Quoted .lef paths in `set x "..."` and `set x [list "..." ...]`."""
    out = []
    for m in re.finditer(r'set\s+[^\s]+\s+"([^"]+\.lef)"', text, re.I):
        out.append(m.group(1))
    for m in re.finditer(r'set\s+[^\s]+\s+\[list\s+(.+?)\]', text, re.S):
        for lm in re.finditer(r'"([^"]+\.lef)"', m.group(1), re.I):
            out.append(lm.group(1))
    return out


def _lefs_from_tag_file(path, _depth=0):
    """LEFs declared by a library tag file (lib_config.tcl / blocks_config.tcl),
    with $_lib_tag_dir expanded to the file's directory; follows the tag's
    own `source "$_lib_tag_dir/blocks_config.tcl"` hook."""
    if _depth > 2 or not os.path.isfile(path):
        return []
    tag_dir = os.path.dirname(os.path.abspath(path))
    try:
        with open(path, errors='replace') as f:
            text = f.read().replace('$_lib_tag_dir', tag_dir).replace('${_lib_tag_dir}', tag_dir)
    except OSError:
        return []
    out = [p for p in _lefs_in_tcl_text(text) if os.path.isfile(p)]
    for sm in re.finditer(r'source\s+"([^"]+\.tcl)"', text):
        if sm.group(1) != path:
            out.extend(_lefs_from_tag_file(sm.group(1), _depth + 1))
    return out


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
    lefs.extend(_lefs_in_tcl_text(text))
    # Library-manager tags are `source`d, not inlined: follow
    # lib_config.tcl / blocks_config.tcl and expand $_lib_tag_dir.
    for sm in re.finditer(r'source\s+"([^"]*(?:lib_config|blocks_config)\.tcl)"', text):
        lefs.extend(_lefs_from_tag_file(sm.group(1)))
    seen, ordered = set(), []
    for p in lefs:
        if p in seen:
            continue
        seen.add(p)
        ordered.append(p)
    return ordered


def _nodes_of_type(flow, node_type):
    """Nodes of `node_type` in the flow's node config (node_types,<node>)."""
    reg = dash_config.registry
    path = os.path.join(reg.discipline_dir(reg.flow_discipline(flow)), 'config', 'flow',
                        reg.config_version('FLOW_CONFIG_VERSION'), 'node_configs',
                        f'{flow}_config.tcl')
    try:
        with open(path, errors='replace') as f:
            text = f.read()
    except OSError:
        return []
    return re.findall(r'node_types,(\S+)\s+"?' + re.escape(node_type) + r'"?\s*$', text, re.M)


def _find_resolved_config(run_dir):
    """Resolved config.tcl of the run's node of type
    flow(dashboard,lef_node_type) (init_design — loads the widest LEF set),
    for each flow the run has under work/, in flow(types) order. '' when the
    run has no such node."""
    node_type = dash_config.lef_node_type()
    work = os.path.join(run_dir, 'work')
    for flow in dash_config.registry.flow_types():
        if not os.path.isdir(os.path.join(work, flow)):
            continue
        for node in _nodes_of_type(flow, node_type):
            p = os.path.join(work, flow, node, 'run', 'config.tcl')
            if os.path.isfile(p):
                return p
    return ''


def _fit_cells_budget(d, macro_h_um, max_bytes):
    """Sample the std-cell layer of a parse_def() result down until its JSON
    fits max_bytes. Hard macros (LEF height >= 1.5 rows) are always kept; the
    density grid is untouched (it already counts every cell)."""
    import json
    cells = d.get('cells') or []
    size = len(json.dumps(cells))
    if size <= max_bytes:
        return
    rowYs = sorted(r['y'] for r in d.get('rows', []))
    step_y = min((b - a for a, b in zip(rowYs, rowYs[1:]) if b > a), default=2000)
    cutoff = step_y * 1.5 / (d.get('units') or 1000)
    macros = [c for c in cells if (macro_h_um.get(c['macro']) or 0) >= cutoff]
    std = [c for c in cells if (macro_h_um.get(c['macro']) or 0) < cutoff]
    keep = max(1, int(len(std) * max_bytes / size))
    stride = max(1, -(-len(std) // keep))
    d['cells'] = std[::stride] + macros
    d['downsampled'] = True
    d['preserved_macros'] = len(macros)


def extract_from_release(release_dir, run_dir, block):
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
    # The release's own LEFs (e.g. the block's abstract) come last so they
    # describe its macros when the config misses them.
    if release_dir:
        lef_dir = os.path.join(release_dir, dash_config.release_name('dir,lef'))
        for p in sorted(glob.glob(os.path.join(lef_dir, '*.lef'))):
            if p not in lefs:
                lefs.append(p)
    payload['lef_paths'] = lefs
    macros_all = parse_lef_dir(lefs) if lefs else {}
    macro_h_um = {k: v.get('h') for k, v in macros_all.items() if v.get('h')}

    # 2. DEF — parse_def receives the macro heights so it never drops a
    #    macro during the stdcell downsample.
    def_path = _find_def(release_dir, block) if release_dir else ''
    payload['def_path'] = def_path
    if def_path:
        payload['def'] = parse_def(def_path, macro_heights_um=macro_h_um)
        _fit_cells_budget(payload['def'], macro_h_um, dash_config.floorplan_cells_max_bytes())

    # 3. Trim the macros dict to only those referenced by DEF cells so the
    #    JSON stays small.
    cell_macros = {c['macro'] for c in payload['def']['cells']} if payload['def']['cells'] else set()
    if cell_macros:
        macros_all = {k: v for k, v in macros_all.items() if k in cell_macros}
    payload['macros'] = macros_all
    return payload


# ─── DEF NETS — per-instance connectivity (on demand) ───────────────────────
# The floorplan payload stays geometry-only; connectivity for one clicked
# instance is served from an index built once per DEF (cached by path+mtime).
_NET_START_RE = re.compile(r'^\s*-\s+(\S+)')
_CONN_RE = re.compile(r'\(\s*(\S+)\s+(\S+)\s*\)')
_net_index_cache = {}


# ─── DEF PINS (IO pins, on demand for the viewer's IO-pin switch) ──────────

# DEF pin orientation: (x, y) of a port shape relative to its placement point
_PIN_ORIENT = {
    'N':  lambda x, y: (x, y),   'S':  lambda x, y: (-x, -y),
    'E':  lambda x, y: (-y, x),  'W':  lambda x, y: (y, -x),
    'FN': lambda x, y: (-x, y),  'FS': lambda x, y: (x, -y),
    'FE': lambda x, y: (y, x),   'FW': lambda x, y: (-y, -x),
}
_PIN_LAYER_RE = re.compile(
    r'\+\s*LAYER\s+(\S+)(?:\s+MASK\s+\d+)?(?:\s+SPACING\s+\d+|\s+DESIGNRULEWIDTH\s+\d+)?'
    r'\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)')
_PIN_PLACE_RE = re.compile(r'\+\s*(?:PLACED|FIXED|COVER)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*(\w+)')
_PIN_MAX_RECTS = 64
_PIN_CACHE = {}


def parse_def_pins(def_path):
    """IO pins of a DEF: [{'name','net','dir','use','rects':[[x1,y1,x2,y2,layer],...]}]
    in DEF units, absolute (port shapes transformed by their placement
    orientation). Supply pins keep at most _PIN_MAX_RECTS shapes. Cached per
    (path, mtime)."""
    try:
        mt = os.path.getmtime(def_path)
    except OSError:
        return []
    hit = _PIN_CACHE.get(def_path)
    if hit and hit[0] == mt:
        return hit[1]
    pins, buf, inside = [], [], False
    with open(def_path, errors='replace') as fh:
        for line in fh:
            s = line.strip()
            if not inside:
                if s.startswith('PINS ') or s == 'PINS':
                    inside = True
                continue
            if s.startswith('END PINS'):
                break
            buf.append(s)
            if not s.endswith(';'):
                continue
            entry = ' '.join(buf); buf = []
            m = re.match(r'-\s+(\S+)', entry)
            if not m:
                continue
            p = {'name': m.group(1), 'net': '', 'dir': '', 'use': 'SIGNAL', 'rects': []}
            for key, rx in (('net', r'\+\s*NET\s+(\S+)'), ('dir', r'\+\s*DIRECTION\s+(\w+)'),
                            ('use', r'\+\s*USE\s+(\w+)')):
                mm = re.search(rx, entry)
                if mm:
                    p[key] = mm.group(1)
            # Each PORT (or the whole entry when there is no PORT keyword)
            # lists its shapes, then its placement.
            parts = re.split(r'\+\s*PORT\b', entry)
            for part in (parts[1:] if len(parts) > 1 else parts):
                pm = _PIN_PLACE_RE.search(part)
                if not pm:
                    continue
                ox, oy, orient = int(pm.group(1)), int(pm.group(2)), pm.group(3)
                tf = _PIN_ORIENT.get(orient, _PIN_ORIENT['N'])
                for lm in _PIN_LAYER_RE.finditer(part):
                    if len(p['rects']) >= _PIN_MAX_RECTS:
                        break
                    ax, ay = tf(int(lm.group(2)), int(lm.group(3)))
                    bx, by = tf(int(lm.group(4)), int(lm.group(5)))
                    p['rects'].append([ox + min(ax, bx), oy + min(ay, by),
                                       ox + max(ax, bx), oy + max(ay, by), lm.group(1)])
            pins.append(p)
    _PIN_CACHE[def_path] = (mt, pins)
    return pins


def build_net_index(def_path):
    """{'inst_pins': {inst: [(pin, net)]}, 'net_conns': {net: [(inst, pin)]}}
    from the DEF NETS section (SPECIALNETS — power — skipped). Top-level
    ports appear as inst 'PIN'."""
    key = (def_path, os.path.getmtime(def_path) if os.path.isfile(def_path) else 0)
    if key in _net_index_cache:
        return _net_index_cache[key]
    inst_pins, net_conns, comps = {}, {}, {}
    in_nets = False
    in_comps = False
    net, buf = None, []
    comp_re = re.compile(r'^\s*-\s+(\S+)\s+(\S+).*?\+\s+(?:PLACED|FIXED|COVER)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\w+)')
    comp_buf = ''

    def _flush():
        if net is None:
            return
        text = ' '.join(buf)
        # connections come before the first '+' (routing / properties follow)
        head = text.split(' + ', 1)[0]
        conns = [(i, p) for i, p in _CONN_RE.findall(head)]
        net_conns[net] = conns
        for i, p in conns:
            inst_pins.setdefault(i, []).append((p, net))

    with open(def_path, errors='replace') as f:
        for line in f:
            st = line.strip()
            if in_comps:
                if st.startswith('END COMPONENTS'):
                    in_comps = False
                    continue
                comp_buf += ' ' + st
                if st.endswith(';'):
                    cm = comp_re.match(comp_buf.strip())
                    if cm:
                        comps[cm.group(1)] = (cm.group(2), int(cm.group(3)), int(cm.group(4)), cm.group(5))
                    comp_buf = ''
                continue
            if not in_nets:
                if st.startswith('COMPONENTS '):
                    in_comps = True
                elif st.startswith('NETS '):
                    in_nets = True
                continue
            if st.startswith('END NETS'):
                _flush()
                break
            m = _NET_START_RE.match(line)
            if m:
                _flush()
                net, buf = m.group(1), [st[st.index(m.group(1)) + len(m.group(1)):]]
            elif net is not None:
                buf.append(st)
    # DEF without NETS (placement / floorplan DEF): take connectivity from
    # the release's gate-level netlist (<release>/netlist/<design>.v).
    if not net_conns:
        nl = _release_netlist_for(def_path)
        if nl:
            inst_pins, net_conns = _netlist_connectivity(nl)
    idx = {'inst_pins': inst_pins, 'net_conns': net_conns, 'comps': comps}
    _net_index_cache.clear()          # keep one DEF index in memory at a time
    _net_index_cache[key] = idx
    return idx


def _release_netlist_for(def_path):
    """<release>/netlist/<design>.v next to <release>/def/<design>.def."""
    rel = os.path.dirname(os.path.dirname(os.path.abspath(def_path)))
    design = os.path.splitext(os.path.basename(def_path))[0]
    for cand in (os.path.join(rel, 'netlist', design + '.v'),
                 os.path.join(rel, 'netlist', design + '.lvs.v')):
        if os.path.isfile(cand):
            return cand
    return ''


_V_INST_RE = re.compile(r'^\s*([A-Za-z_][\w$]*)\s+(\\\S+|[A-Za-z_][\w$\[\]]*)\s*\((.*)\)\s*$', re.S)
_V_PORT_RE = re.compile(r'\.(\w+)\s*\(\s*([^()]*?)\s*\)')
_V_SKIP = {'module', 'endmodule', 'input', 'output', 'inout', 'wire', 'reg', 'assign', 'supply0', 'supply1'}


def _netlist_connectivity(path):
    """(inst_pins, net_conns) from a flat structural Verilog netlist:
    `cell inst (.PIN(net), ...);` statements (escaped names kept as written,
    minus the leading backslash, to match DEF component names)."""
    inst_pins, net_conns = {}, {}
    with open(path, errors='replace') as f:
        text = f.read()
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    for stmt in text.split(';'):
        m = _V_INST_RE.match(stmt)
        if not m or m.group(1) in _V_SKIP:
            continue
        inst = m.group(2).lstrip('\\').strip()
        for pin, net in _V_PORT_RE.findall(m.group(3)):
            net = net.strip().lstrip('\\').strip()
            if not net or net.startswith("1'b") or net.startswith('{'):
                continue
            inst_pins.setdefault(inst, []).append((pin, net))
            net_conns.setdefault(net, []).append((inst, pin))
    return inst_pins, net_conns


def cell_connectivity(def_path, inst, max_peers=200):
    """Pins of `inst` with their nets and the other (inst, pin) on each net.
    Nets larger than `max_peers` (clocks, resets) return the first peers and
    the full fanout count."""
    idx = build_net_index(def_path)
    comps = idx['comps']
    out = []
    for pin, net in idx['inst_pins'].get(inst, []):
        conns = [c for c in idx['net_conns'].get(net, []) if c != (inst, pin)]
        peers = []
        for i, p in conns[:max_peers]:
            rec = {'inst': i, 'pin': p}
            if i in comps:
                m, x, y, o = comps[i]
                rec.update({'macro': m, 'x': x, 'y': y, 'orient': o})
            peers.append(rec)
        out.append({'pin': pin, 'net': net, 'fanout': len(conns), 'peers': peers})
    return out
