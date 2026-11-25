#!/usr/bin/env python3
"""Open-source DFT helpers for the CBflow DFT flows (SCAN_INSERT / ATPG / GLS).

Runs inside the CBflow tool container (python3 there), called by the DFT
command files. Standard library only; netlists are read as Yosys JSON
(`write_json` of the flattened netlist, library cells / macros blackboxed).

  cells  --lib <liberty> -o cells.json
         sequential cells (flop / latch, clock pin + edge, async clear/preset),
         scan flops (test_cell signal_type: scan in / enable / out), clock-gating
         cells, buffers and inverters — everything the tracer needs, from the
         liberty, never from a cell-name list.
  trace  --json <netlist.json> --top <t> --cells cells.json
         --scan-in <glob> --scan-out <glob> --scan-enable <glob> [--max-length N]
         -o scan.json [--scandef <file>] [--report <file>]
         scan chains traced through the netlist: scan_out port back through
         buffers / inverters, flop Q -> its scan-in pin -> ... -> scan_in port;
         per chain the clock port + edge (through buffers / ICGs), the scan
         enable port reaching every SE pin; unscanned flops; rule violations.
  flush-tb --scan scan.json --top <t> -o tb.v
         chain-flush testbench: shift 0011… through every chain and compare
         scan_out after the chain length (inversions between flops included).
  bench-clean --bench in.bench -o out.bench --map map.json [--hold port=v ...]
         Atalanta-ready bench: header line, constants removed (unused) or
         rebuilt, dead logic pruned (floating outputs: cones of removed macros /
         scan path), held ports removed, names made alphanumeric (map kept).
  patterns --test <atalanta.test> --map map.json --scan scan.json --top <t>
         [--hold port=v ...] -o patterns.json --stil <file> --tb <file>
         Atalanta patterns (pseudo-inputs = flop Q, pseudo-outputs = flop D)
         mapped onto the traced chain order: serial load / capture / unload,
         STIL-style pattern file and a self-checking serial-scan testbench.
  coverage --log <atalanta stdout> --bench-orig <bench> --bench <clean bench>
         [--ufaults <file>] -o coverage.rpt [--json coverage.json]
  fsim   --bench <clean bench> --test <atalanta.test> [--map map.json] [--sample N]
         -o fault_sim.rpt [--json]   independent stuck-at fault simulation of the
         pattern set (all patterns bit-parallel, fan-out cone per fault)
  census --json <netlist.json> --top <t> --cells cells.json --scan-in <glob>
         --scan-enable <glob> -o census.rpt   sequential / scan / blackbox counts
  stubs  --json <netlist.json> --top <t> --cells cells.json -o stubs.v
         macro stubs (outputs held 0) for scan / ATPG simulations
  model-fix --model <v> -o <v>   behavioral model with memory declarations first
  toggle --vcd <file> -o coverage.rpt   toggle coverage of the dumped nets
"""
import argparse
import fnmatch
import json
import os
import re
import sys


# ═══════════════════════════════════════════════════════════════════════════
# Liberty
# ═══════════════════════════════════════════════════════════════════════════
def _groups(text, kind):
    """(name, body) of each top-level `kind (name) { … }` group in text."""
    out = []
    for m in re.finditer(r'\b' + kind + r'\s*\(([^)]*)\)\s*\{', text):
        i, depth = m.end(), 1
        while depth and i < len(text):
            c = text[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            i += 1
        out.append((m.group(1).strip().strip('"'), text[m.end():i - 1], m.start()))
    return out


def _attr(body, name):
    m = re.search(r'\b' + name + r'\s*:\s*"?([^";\n]*)"?\s*;', body)
    return m.group(1).strip() if m else None


def _strip_nested(body):
    """body with nested groups removed (attributes of this level only)."""
    out, depth = [], 0
    for c in body:
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        elif depth == 0:
            out.append(c)
    return ''.join(out)


def parse_liberty(path):
    text = open(path, errors='replace').read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = text.replace('\\\n', ' ')
    cells = {}
    for name, body, _ in _groups(text, 'cell'):
        c = {'pins': {}}
        test = _groups(body, 'test_cell')
        top = body
        if test:
            tb = test[0][1]
            top = body.replace(tb, '')
            for pn, pb, _ in _groups(tb, 'pin'):
                st = _attr(pb, 'signal_type')
                if st:
                    c.setdefault('test', {})[st] = pn
        for pn, pb, _ in _groups(top, 'pin'):
            lvl = _strip_nested(pb)
            c['pins'][pn] = {'dir': _attr(lvl, 'direction'), 'function': _attr(lvl, 'function'),
                             'state_function': _attr(lvl, 'state_function'),
                             'cg_clock': _attr(lvl, 'clock_gate_clock_pin') == 'true',
                             'cg_out': _attr(lvl, 'clock_gate_out_pin') == 'true',
                             'cg_enable': _attr(lvl, 'clock_gate_enable_pin') == 'true',
                             'cg_test': _attr(lvl, 'clock_gate_test_pin') == 'true'}
        ff = _groups(top, 'ff')
        latch = _groups(top, 'latch')
        cg = _attr(_strip_nested(top), 'clock_gating_integrated_cell')
        if ff:
            fb = ff[0][1]
            iq = ff[0][0].split(',')[0].strip().strip('"')
            clk = _attr(fb, 'clocked_on') or ''
            c['seq'] = {'kind': 'ff', 'clock': clk.lstrip('!').strip('()'),
                        'edge': 'neg' if clk.startswith('!') else 'pos',
                        'clear': _attr(fb, 'clear'), 'preset': _attr(fb, 'preset'),
                        'next_state': _attr(fb, 'next_state'),
                        'q': [p for p, v in c['pins'].items() if v['dir'] == 'output' and v['function'] and v['function'].strip('()') == iq],
                        'qn': [p for p, v in c['pins'].items() if v['dir'] == 'output' and v['function'] and v['function'].replace(' ', '').strip('()') in ('!' + iq, iq + "'")]}
        elif latch and not cg:
            c['seq'] = {'kind': 'latch'}
        if cg:
            c['icg'] = {'clock': next((p for p, v in c['pins'].items() if v['cg_clock']), None),
                        'out': next((p for p, v in c['pins'].items() if v['cg_out']), None),
                        'enable': next((p for p, v in c['pins'].items() if v['cg_enable']), None),
                        'test': next((p for p, v in c['pins'].items() if v['cg_test']), None)}
        ins = [p for p, v in c['pins'].items() if v['dir'] == 'input']
        outs = [p for p, v in c['pins'].items() if v['dir'] == 'output']
        if 'seq' not in c and 'icg' not in c and len(ins) == 1 and len(outs) == 1:
            f = (c['pins'][outs[0]]['function'] or '').replace(' ', '')
            if f.strip('()') == ins[0]:
                c['buf'] = {'a': ins[0], 'y': outs[0], 'inv': False}
            elif f.strip('()') in ('!' + ins[0], ins[0] + "'"):
                c['buf'] = {'a': ins[0], 'y': outs[0], 'inv': True}
        cells[name] = c
    return cells


def cmd_cells(a):
    cells = {}
    for lib in a.lib:
        cells.update(parse_liberty(lib))
    scan = sorted(n for n, c in cells.items() if c.get('seq', {}).get('kind') == 'ff' and
                  {'test_scan_in', 'test_scan_enable'} <= set(c.get('test', {})))
    seq = sorted(n for n, c in cells.items() if 'seq' in c)
    doc = {'libs': a.lib, 'cells': cells, 'scan_flops': scan, 'sequential': seq,
           'icgs': sorted(n for n, c in cells.items() if 'icg' in c),
           'buffers': sorted(n for n, c in cells.items() if 'buf' in c)}
    json.dump(doc, open(a.output, 'w'), indent=0)
    print(f"cells: {len(cells)} cells, {len(seq)} sequential, {len(scan)} scan flops, "
          f"{len(doc['icgs'])} clock gates, {len(doc['buffers'])} buffers/inverters", file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# Netlist (Yosys JSON, flat top)
# ═══════════════════════════════════════════════════════════════════════════
class Netlist:
    def __init__(self, path, top):
        d = json.load(open(path))
        if top not in d['modules']:
            raise SystemExit(f"ERROR: module {top} not in {path}")
        m = d['modules'][top]
        self.top = top
        self.ports = m['ports']
        self.cells = m['cells']
        self.driver = {}       # bit -> ('port', name, idx) | ('cell', inst, pin)
        self.loads = {}        # bit -> [('cell', inst, pin) | ('port', name, idx)]
        for pn, p in self.ports.items():
            for i, b in enumerate(p['bits']):
                if p['direction'] == 'input':
                    self.driver[b] = ('port', pn, i)
                else:
                    self.loads.setdefault(b, []).append(('port', pn, i))
        for cn, c in self.cells.items():
            dirs = c.get('port_directions', {})
            for pin, bits in c['connections'].items():
                for b in bits:
                    if isinstance(b, str):
                        continue
                    if dirs.get(pin) == 'output':
                        self.driver[b] = ('cell', cn, pin)
                    else:
                        self.loads.setdefault(b, []).append(('cell', cn, pin))
        self.names = {}
        for nn, n in m.get('netnames', {}).items():
            for i, b in enumerate(n['bits']):
                if not isinstance(b, str) and (b not in self.names or not n.get('hide_name')):
                    self.names[b] = nn if len(n['bits']) == 1 else f'{nn}[{i}]'

    def pin_bit(self, inst, pin):
        bits = self.cells[inst]['connections'].get(pin, [])
        return bits[0] if bits else None

    def port_bits(self, pattern):
        """[(port_name, bit_index, bit, display_name)] of ports matching a glob."""
        out = []
        for pn, p in self.ports.items():
            for i, b in enumerate(p['bits']):
                disp = pn if len(p['bits']) == 1 else f'{pn}[{i}]'
                if fnmatch.fnmatchcase(pn, pattern) or fnmatch.fnmatchcase(disp, pattern):
                    out.append((pn, i, b, disp))
        return out


def _port_disp(nl, pn, i):
    return pn if len(nl.ports[pn]['bits']) == 1 else f'{pn}[{i}]'


def trace_back(nl, cells, bit, through_icg=False):
    """Follow a net back through buffers / inverters (and ICG clock paths).
    Returns (driver tuple, inversion parity, path of buffer instances)."""
    inv, path, seen = False, [], set()
    while True:
        if bit in seen or isinstance(bit, str):
            return (('const', bit, 0) if isinstance(bit, str) else ('loop', bit, 0)), inv, path
        seen.add(bit)
        drv = nl.driver.get(bit)
        if drv is None:
            return ('undriven', bit, 0), inv, path
        if drv[0] == 'port':
            return drv, inv, path
        _, inst, pin = drv
        ct = cells.get(nl.cells[inst]['type'], {})
        if 'buf' in ct and pin == ct['buf']['y']:
            inv ^= ct['buf']['inv']
            path.append(inst)
            bit = nl.pin_bit(inst, ct['buf']['a'])
            continue
        if through_icg and 'icg' in ct and pin == ct['icg']['out']:
            path.append(inst)
            bit = nl.pin_bit(inst, ct['icg']['clock'])
            continue
        return drv, inv, path


def trace_fwd(nl, cells, bit):
    """Loads of a net, followed forward through buffers / inverters:
    [(load tuple, inversion parity)] — cell pins that are not buffer inputs,
    and output ports."""
    out, todo, seen = [], [(bit, False)], set()
    while todo:
        b, inv = todo.pop()
        if b in seen or b is None or isinstance(b, str):
            continue
        seen.add(b)
        for ld in nl.loads.get(b, []):
            if ld[0] == 'cell':
                ct = cells.get(nl.cells[ld[1]]['type'], {})
                if 'buf' in ct and ld[2] == ct['buf']['a']:
                    todo.append((nl.pin_bit(ld[1], ct['buf']['y']), inv ^ ct['buf']['inv']))
                    continue
            out.append((ld, inv))
    return out


def cmd_trace(a):
    cells = json.load(open(a.cells))['cells']
    nl = Netlist(a.json, a.top)
    scan_types = {n for n, c in cells.items() if c.get('seq', {}).get('kind') == 'ff' and
                  {'test_scan_in', 'test_scan_enable'} <= set(c.get('test', {}))}
    seq = {cn: c['type'] for cn, c in nl.cells.items() if 'seq' in cells.get(c['type'], {})}
    unknown = sorted({c['type'] for c in nl.cells.values() if c['type'] not in cells})
    violations = []
    sins = nl.port_bits(a.scan_in)
    sout_bits = {b: disp for _, _, b, disp in nl.port_bits(a.scan_out)}
    ses = {b: disp for _, _, b, disp in nl.port_bits(a.scan_enable)}
    chains, on_chain = [], set()
    # Chains are traced forward from each scan-in port: through buffers /
    # inverters to the one scan flop scan-in pin it feeds, from that flop's
    # Q / QN to the next scan-in pin, … The tail flop's output reaches the
    # scan-out: a dedicated scan-out port (--scan-out) or, when the inserter
    # reused a functional output (OpenROAD does when a flop already drives an
    # output port), that functional output port.
    for pn, idx, bit, sin in sorted(sins, key=lambda x: _natkey(x[3])):
        flops, sout, inv_in = [], None, False
        loads = trace_fwd(nl, cells, bit)
        while True:
            si_loads = [(l, inv) for l, inv in loads if l[0] == 'cell' and nl.cells[l[1]]['type'] in scan_types and
                        l[2] == cells[nl.cells[l[1]]['type']]['test']['test_scan_in']]
            if not si_loads:
                break
            if len(si_loads) > 1:
                violations.append(f"chain {sin}: fans out to {len(si_loads)} scan-in pins after {flops[-1]['inst'] if flops else sin}: "
                                  f"{[l[1] for l, _ in si_loads][:5]}")
            (_, inst, _), inv = si_loads[0]
            if inst in on_chain:
                violations.append(f"chain {sin}: flop {inst} reached twice (loop / shared)")
                break
            if flops:
                flops[-1]['inv_out'] ^= inv
            else:
                inv_in = inv
            ct = nl.cells[inst]['type']
            lc = cells[ct]
            # the flop output that continues the chain: Q (or QN) feeding the
            # next scan-in pin / the scan-out; prefer Q
            outs = [(p, p in lc['seq']['qn']) for p in lc['seq']['q'] + lc['seq']['qn']
                    if nl.pin_bit(inst, p) is not None]
            nxt, chosen = None, None
            for p, qn in outs:
                ld = trace_fwd(nl, cells, nl.pin_bit(inst, p))
                if any(l[0] == 'cell' and nl.cells[l[1]]['type'] in scan_types and
                       l[2] == cells[nl.cells[l[1]]['type']]['test']['test_scan_in'] for l, _ in ld) or \
                   any(l[0] == 'port' for l, _ in ld):
                    nxt, chosen = ld, (p, qn)
                    break
            if chosen is None:
                chosen = outs[0] if outs else (None, False)
                nxt = []
            flops.append({'inst': inst, 'cell': ct, 'q': chosen[0], 'qn': chosen[1], 'inv_out': chosen[1]})
            on_chain.add(inst)
            loads = nxt
        # scan-out: an output port fed by the tail (buffers / inverters only)
        ports_ = [(l, inv) for l, inv in loads if l[0] == 'port']
        ded = [(l, inv) for l, inv in ports_ if nl.ports[l[1]]['bits'][l[2]] in sout_bits]
        pick = (ded or ports_ or [None])[0]
        shared = False
        if pick is None:
            violations.append(f"chain {sin}: tail flop {flops[-1]['inst'] if flops else '-'} reaches no output port (no scan-out)")
        else:
            (_, opn, oi), inv = pick
            sout = _port_disp(nl, opn, oi)
            shared = not ded
            if flops:
                flops[-1]['inv_out'] ^= inv
        if not flops:
            violations.append(f"chain {sin}: scan-in port feeds no scan flop")
        disp = sin
        ch = {'scan_out': sout, 'scan_out_shared': shared, 'scan_in': sin,
              'scan_in_inv': inv_in, 'length': len(flops), 'flops': flops}
        # clock + scan enable per flop
        clocks, se_ports, se_bad = {}, set(), []
        for f in flops:
            lc = cells[f['cell']]
            cdrv, cinv, cpath = trace_back(nl, cells, nl.pin_bit(f['inst'], lc['seq']['clock']), through_icg=True)
            edge = lc['seq']['edge']
            if cinv:
                edge = 'neg' if edge == 'pos' else 'pos'
            ck = _port_disp(nl, cdrv[1], cdrv[2]) if cdrv[0] == 'port' else f'<{cdrv[0]}>'
            clocks.setdefault((ck, edge), 0)
            clocks[(ck, edge)] += 1
            f['clock'], f['edge'] = ck, edge
            edrv, einv, _ = trace_back(nl, cells, nl.pin_bit(f['inst'], lc['test']['test_scan_enable']))
            if edrv[0] == 'port' and edrv[2] is not None and nl.ports[edrv[1]]['bits'][edrv[2]] in ses:
                se_ports.add((_port_disp(nl, edrv[1], edrv[2]), einv))
            else:
                se_bad.append(f['inst'])
        ch['clocks'] = [{'port': k[0], 'edge': k[1], 'flops': v} for k, v in clocks.items()]
        ch['scan_enable'] = [{'port': p, 'inverted': i} for p, i in sorted(se_ports)]
        if se_bad:
            violations.append(f"chain {disp}: {len(se_bad)} flop(s) with scan enable not driven by a scan-enable port ({a.scan_enable}): {se_bad[:5]}")
        if len(se_ports) > 1:
            violations.append(f"chain {disp}: scan enable from more than one port / polarity: {sorted(se_ports)}")
        if len(clocks) > 1 and a.clock_mixing == 'no_mix':
            violations.append(f"chain {disp}: mixes clock domains under no_mix: {[f'{k[0]}/{k[1]}' for k in clocks]}")
        if any(c['port'].startswith('<') for c in ch['clocks']):
            violations.append(f"chain {disp}: flop clock not traced to a top-level port")
        if a.max_length and len(flops) > a.max_length:
            violations.append(f"chain {disp}: length {len(flops)} > max_chain_length {a.max_length}")
        chains.append(ch)
    unscanned = sorted((i, t) for i, t in seq.items() if i not in on_chain)
    nonscan_types = sorted({t for _, t in unscanned})
    for t in unknown:
        violations.append(f"cell type {t} not in the liberty (blackbox / macro) — not traced")
    doc = {'top': a.top, 'chains': chains, 'scan_in_pattern': a.scan_in, 'scan_out_pattern': a.scan_out,
           'scan_enable_pattern': a.scan_enable, 'sequential': len(seq), 'scanned': len(on_chain),
           'unscanned': [{'inst': i, 'cell': t} for i, t in unscanned], 'blackbox_types': unknown,
           'violations': [v for v in violations if not v.startswith('cell type')],
           'notes': [v for v in violations if v.startswith('cell type')],
           'inputs': [_port_disp(nl, pn, i) for pn, p in nl.ports.items() if p['direction'] == 'input' for i in range(len(p['bits']))],
           'outputs': [_port_disp(nl, pn, i) for pn, p in nl.ports.items() if p['direction'] != 'input' for i in range(len(p['bits']))]}
    json.dump(doc, open(a.output, 'w'), indent=1)
    if a.scandef:
        with open(a.scandef, 'w') as f:
            f.write(f"# CBflow scandef (open-source DFT) — {a.top}\n# chain: scan_in -> flops (load order) -> scan_out\n")
            f.write(f"SCANCHAINS {len(chains)} ;\n")
            for k, ch in enumerate(chains):
                ck = ', '.join(f"{c['port']} {c['edge']}" for c in ch['clocks'])
                se = ', '.join(s['port'] + (' (inv)' if s['inverted'] else '') for s in ch['scan_enable'])
                f.write(f"- chain{k}\n  + START PIN {ch['scan_in']}\n  + STOP PIN {ch['scan_out']}\n"
                        f"  + LENGTH {ch['length']}\n  + CLOCK {ck}\n  + ENABLE {se}\n  + ORDERED\n")
                for fl in ch['flops']:
                    f.write(f"      {fl['inst']} ( IN {cells[fl['cell']]['test']['test_scan_in']} ) "
                            f"( OUT {fl['q']} ) {fl['cell']}{' INV' if fl['inv_out'] else ''}\n")
                f.write("  ;\n")
            f.write("END SCANCHAINS\n")
    lines = [f"Scan chain report — {a.top}",
             f"  scan ports       : in {a.scan_in}  out {a.scan_out}  enable {a.scan_enable}",
             f"  chains           : {len(chains)}",
             f"  sequential cells : {len(seq)}",
             f"  scanned flops    : {len(on_chain)}",
             f"  unscanned        : {len(unscanned)}" + (f"  ({', '.join(nonscan_types)})" if nonscan_types else ""),
             f"  scan coverage %  : {100.0 * len(on_chain) / len(seq) if seq else 100.0:.2f}",
             ""]
    for k, ch in enumerate(chains):
        ck = ', '.join(f"{c['port']}/{c['edge']} ({c['flops']})" for c in ch['clocks'])
        se = ', '.join(s['port'] + ('/inv' if s['inverted'] else '') for s in ch['scan_enable'])
        lines.append(f"  chain{k}: {ch['scan_in']} -> {ch['scan_out']}  length {ch['length']}  clock {ck}  enable {se}")
    if unknown:
        lines += ["", "  blackbox cells (not traced): " + ', '.join(unknown)]
    lines += ["", f"  Violations : {len(doc['violations'])}"] + [f"    - {v}" for v in doc['violations']]
    if unscanned:
        lines += ["", "  Unscanned flops:"] + [f"    {i} ({t})" for i, t in unscanned[:200]]
    rpt = '\n'.join(lines) + '\n'
    if a.report:
        open(a.report, 'w').write(rpt)
    print(rpt, file=sys.stderr)


def _natkey(s):
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', s)]


def cmd_census(a):
    """Cell census of a netlist: sequential / scan-flop / blackbox counts and
    the scan ports present — the init stages' scan-exists check."""
    cells = json.load(open(a.cells))['cells']
    nl = Netlist(a.json, a.top)
    seq = scan = latch = 0
    bb, seq_types = {}, set()
    for c in nl.cells.values():
        ct = cells.get(c['type'])
        if ct is None:
            bb[c['type']] = bb.get(c['type'], 0) + 1
            continue
        if 'seq' in ct:
            seq += 1
            seq_types.add(c['type'])
            if ct['seq'].get('kind') == 'latch':
                latch += 1
            if {'test_scan_in', 'test_scan_enable'} <= set(ct.get('test', {})):
                scan += 1
    si = [d for _, _, _, d in nl.port_bits(a.scan_in)]
    se = [d for _, _, _, d in nl.port_bits(a.scan_enable)]
    lines = [f"Cell census — {a.top}",
             f"  Cells             : {len(nl.cells)}",
             f"  Sequential cells  : {seq}",
             f"  Scan flops        : {scan}",
             f"  Latches           : {latch}",
             f"  Scan-in ports     : {len(si)}  {' '.join(si)}",
             f"  Scan-enable ports : {len(se)}  {' '.join(se)}",
             f"  Blackbox macros   : {sum(bb.values())}  " + ' '.join(f'{k}x{v}' for k, v in sorted(bb.items())),
             f"  Sequential types  : {len(seq_types)}  {' '.join(sorted(seq_types))}"]
    open(a.output, 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines), file=sys.stderr)


def cmd_stubs(a):
    """Verilog stubs for the blackboxed macros of a netlist (memories, child
    blocks): every output driven 0. Scan / ATPG simulations use them — the
    ATPG model treats macro outputs as held 0 (no memory bypass), so the
    pattern simulation must match that assumption."""
    d = json.load(open(a.json))
    used = {c['type'] for c in d['modules'][a.top]['cells'].values()}
    libcells = set(json.load(open(a.cells))['cells']) if a.cells else set()
    out = [f"// CBflow open-source DFT — macro stubs for {a.top} (outputs held 0; generated by oss_dft.py)"]
    n = 0
    for name in sorted(used):
        m = d['modules'].get(name)
        if name in libcells or m is None:
            continue
        ports = m.get('ports', {})
        decl = []
        for pn, p in ports.items():
            w = len(p['bits'])
            rng = f'[{w - 1}:0] ' if w > 1 else ''
            decl.append(f"  {p['direction']} {rng}{_vid(pn)};")
            if p['direction'] == 'output':
                decl.append(f"  assign {_vid(pn)} = {w}'b0;")
        out += [f"module {_vid(name)} ({', '.join(_vid(p) for p in ports)});"] + decl + ["endmodule", ""]
        n += 1
    open(a.output, 'w').write('\n'.join(out) + '\n')
    print(f"stubs: {n} macro stub(s) -> {a.output}", file=sys.stderr)


def cmd_model_fix(a):
    """Copy a behavioral model with memory-array declarations moved to the top
    of their module (iverilog rejects `mem[addr]` used before `reg … mem[…]`;
    OpenRAM SRAM models declare the array after the always blocks). The fix is
    declaration order only."""
    t = open(a.model).read()
    out = []
    for mod in re.split(r'(?=^\s*module\b)', t, flags=re.M):
        decls = re.findall(r'^\s*reg\s*(?:\[[^\]]*\])?\s*\w+\s*\[[^\]]*\]\s*;\s*$', mod, re.M)
        if decls:
            for dcl in decls:
                mod = mod.replace(dcl, '')
            # before the first procedural block / instance (parameters and
            # ports are declared by then)
            m = re.search(r'^\s*(always|initial|assign)\b', mod, re.M)
            if m:
                mod = mod[:m.start()] + '\n' + '\n'.join(decls) + '\n' + mod[m.start():]
            else:
                mod = re.sub(r'(?=^\s*endmodule\b)', '\n'.join(decls) + '\n', mod, count=1, flags=re.M)
        out.append(mod)
    open(a.output, 'w').write(f"// CBflow: {os.path.basename(a.model)} with memory declarations first (iverilog)\n" + ''.join(out))
    print(f"model-fix: {a.model} -> {a.output}", file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# Testbench helpers
# ═══════════════════════════════════════════════════════════════════════════
def _vid(name):
    """Verilog reference for a top port bit name ('a', 'bus[3]')."""
    m = re.match(r'^(.*)\[(\d+)\]$', name)
    base = m.group(1) if m else name
    ref = base if re.match(r'^[A-Za-z_][A-Za-z0-9_$]*$', base) else '\\' + base + ' '
    return f'{ref}[{m.group(2)}]' if m else ref


def _port_decls(scan):
    """reg/wire declarations + instance connections for the DUT ports."""
    width = {}
    for n in scan['inputs'] + scan['outputs']:
        m = re.match(r'^(.*)\[(\d+)\]$', n)
        b, i = (m.group(1), int(m.group(2))) if m else (n, None)
        width.setdefault(b, set())
        if i is not None:
            width[b].add(i)
    ins = {re.sub(r'\[\d+\]$', '', n) for n in scan['inputs']}
    decl, conn = [], []
    for b, idx in width.items():
        rng = f'[{max(idx)}:{min(idx)}] ' if idx else ''
        ref = _vid(b)
        decl.append(f"  {'reg ' if b in ins else 'wire'} {rng}{ref};")
        conn.append(f"    .{ref}({ref})")
    return decl, conn


def _single_clock(scan):
    clocks = {(c['port'], c['edge']) for ch in scan['chains'] for c in ch['clocks']}
    if len(clocks) != 1:
        raise SystemExit(f"ERROR: the scan testbench needs one scan clock; chains use {sorted(clocks)}")
    return clocks.pop()


def _single_se(scan):
    ses = {(s['port'], s['inverted']) for ch in scan['chains'] for s in ch['scan_enable']}
    if len(ses) != 1:
        raise SystemExit(f"ERROR: the scan testbench needs one scan-enable port; chains use {sorted(ses)}")
    return ses.pop()


def _tb_head(scan, top, name, holds):
    decl, conn = _port_decls(scan)
    (ck, edge), (se, se_inv) = _single_clock(scan), _single_se(scan)
    idle = '0' if edge == 'pos' else '1'
    act = '1' if edge == 'pos' else '0'
    se_on, se_off = ('0', '1') if se_inv else ('1', '0')
    h = [f"// CBflow open-source DFT — {name} (generated by oss_dft.py)", "`timescale 1ns/1ps",
         f"module {name};"] + decl + [
        f"  {_vid(top)} dut (", ",\n".join(conn), "  );",
        "  integer errors = 0; integer checks = 0;",
        f"  task pulse; begin #5 {_vid(ck)} = {act}; #5 {_vid(ck)} = {idle}; end endtask",
        "  initial begin",
        f"    {_vid(ck)} = {idle};"]
    for n in scan['inputs']:
        if n == ck:
            continue
        h.append(f"    {_vid(n)} = 1'b{holds.get(n, '0')};")
    return h, ck, se, se_on, se_off


def cmd_flush_tb(a):
    scan = json.load(open(a.scan))
    holds = dict(h.split('=') for h in (a.hold or []))
    h, ck, se, se_on, se_off = _tb_head(scan, a.top, 'cbflow_scan_flush_tb', holds)
    L = max(ch['length'] for ch in scan['chains'])
    n = 2 * L + 8
    pat = ''.join('0011'[(i % 4)] for i in range(n))
    b = h + [f"    {_vid(se)} = 1'b{se_on};", "    #10;"]
    for k, ch in enumerate(scan['chains']):
        par = ch['scan_in_inv']
        for f in ch['flops']:
            par ^= f['inv_out']
        b.append(f"    // chain{k}: {ch['scan_in']} -> {ch['scan_out']} length {ch['length']}, inversion {int(par)}")
    b.append(f"    // shift {n} bits; scan_out(t) = scan_in(t - length) ^ inversion")
    for t in range(n):
        for ch in scan['chains']:
            b.append(f"    {_vid(ch['scan_in'])} = 1'b{pat[t]};")
        b.append("    #2;")
        for ch in scan['chains']:
            L_ch = ch['length']
            if t >= L_ch:
                par = ch['scan_in_inv']
                for f in ch['flops']:
                    par ^= f['inv_out']
                exp = int(pat[t - L_ch]) ^ int(par)
                so = _vid(ch['scan_out'])
                b.append(f"    checks = checks + 1; if ({so} !== 1'b{exp}) begin errors = errors + 1; "
                         f"$display(\"FLUSH MISMATCH chain {ch['scan_out']} bit {t}: got %b exp {exp}\", {so}); end")
        b.append("    pulse;")
    b += ["    $display(\"Flush checks: %0d\", checks);", "    $display(\"Mismatches: %0d\", errors);",
          "    if (errors == 0) $display(\"FLUSH TEST PASSED\"); else $display(\"FLUSH TEST FAILED\");",
          "    $finish;", "  end", "endmodule"]
    open(a.output, 'w').write('\n'.join(b) + '\n')
    print(f"flush-tb: {len(scan['chains'])} chain(s), {n} shift cycles -> {a.output}", file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# Bench (Atalanta)
# ═══════════════════════════════════════════════════════════════════════════
def _safe(name):
    s = re.sub(r'[^A-Za-z0-9_]', '_', name.replace('\\', ''))
    return s if s and not s[0].isdigit() else 'n' + s


def read_bench(path):
    ins, outs, gates = [], [], {}
    for ln in open(path):
        ln = ln.strip()
        if not ln or ln.startswith('#'):
            continue
        m = re.match(r'INPUT\((.+)\)$', ln)
        if m:
            ins.append(m.group(1).strip())
            continue
        m = re.match(r'OUTPUT\((.+)\)$', ln)
        if m:
            outs.append(m.group(1).strip())
            continue
        m = re.match(r'(.+?)\s*=\s*(\w+)\((.*)\)$', ln)
        if not m:
            raise SystemExit(f"ERROR: cannot parse bench line: {ln}")
        gates[m.group(1).strip()] = (m.group(2).upper(), [x.strip() for x in m.group(3).split(',') if x.strip()])
    return ins, outs, gates


def cmd_bench_clean(a):
    ins, outs, gates = read_bench(a.bench)
    holds = dict(h.split('=') for h in (a.hold or []))
    stats = {'gates_in': len(gates), 'inputs_in': len(ins)}
    # held ports: replaced by constants
    consts = {}
    for g, (t, args) in list(gates.items()):
        if t in ('VDD', 'VCC', 'ONE'):
            consts[g] = '1'
        elif t in ('VSS', 'GND', 'ZERO'):
            consts[g] = '0'
    for p, v in holds.items():
        if p in ins:
            ins.remove(p)
            consts[p] = v
    for g in list(gates):
        if g in consts:
            del gates[g]
    # propagate constants (simple: AND/NAND/OR/NOR/NOT/BUF with a constant input)
    changed = True
    while changed:
        changed = False
        for g, (t, args) in list(gates.items()):
            vals = [consts.get(x) for x in args]
            if not any(v is not None for v in vals):
                continue
            live = [x for x, v in zip(args, vals) if v is None]
            cv = [v for v in vals if v is not None]
            ctrl = {'AND': '0', 'NAND': '0', 'OR': '1', 'NOR': '1'}.get(t)
            res = None
            if t in ('NOT', 'BUF', 'BUFF'):
                res = cv[0] if t != 'NOT' else str(1 - int(cv[0]))
            elif ctrl is not None and ctrl in cv:
                res = ctrl if t in ('AND', 'OR') else str(1 - int(ctrl))
            elif ctrl is not None:          # all constants non-controlling
                if not live:
                    nc = str(1 - int(ctrl))
                    res = nc if t in ('AND', 'OR') else ctrl
                else:
                    gates[g] = (t, live) if len(live) > 1 or t in ('AND', 'OR', 'NAND', 'NOR') else (t, live)
                    if len(live) == 1:
                        gates[g] = ('BUFF' if t in ('AND', 'OR') else 'NOT', live)
                    changed = True
                    continue
            elif t in ('XOR', 'XNOR') and len(args) == 2:
                if not live:
                    x = int(cv[0]) ^ int(cv[1])
                    res = str(x if t == 'XOR' else 1 - x)
                else:
                    flip = int(cv[0]) ^ (t == 'XNOR')
                    gates[g] = ('NOT' if flip else 'BUFF', live)
                    changed = True
                    continue
            if res is not None:
                consts[g] = res
                del gates[g]
                changed = True
    # outputs tied to a constant: keep as PO driven by a constant tautology of an input
    const_outs = [o for o in outs if o in consts]
    for o in const_outs:
        outs.remove(o)
    # prune dead logic
    while True:
        used = set(outs)
        for t, args in gates.values():
            used.update(args)
        dead = [g for g in gates if g not in used]
        if not dead:
            break
        for g in dead:
            del gates[g]
    used = set(outs)
    for t, args in gates.values():
        used.update(args)
    pruned_in = [i for i in ins if i not in used]
    ins = [i for i in ins if i in used]
    undefined = sorted(u for u in used if u not in gates and u not in ins)
    if undefined:
        raise SystemExit(f"ERROR: bench nets with no driver after cleanup: {undefined[:10]}")
    # names
    m, back, taken = {}, {}, set()
    for n in ins + outs + list(gates):
        if n in m:
            continue
        s = _safe(n)
        k = s
        i = 1
        while k in taken:
            k = f'{s}_{i}'
            i += 1
        taken.add(k)
        m[n] = k
        back[k] = n
    with open(a.output, 'w') as f:
        f.write(f"# {_safe(os.path.basename(a.output).split('.')[0])}\n")
        for i in ins:
            f.write(f"INPUT({m[i]})\n")
        for o in outs:
            f.write(f"OUTPUT({m[o]})\n")
        for g, (t, args) in gates.items():
            t = 'BUFF' if t == 'BUF' else t
            f.write(f"{m[g]} = {t}({', '.join(m[x] for x in args)})\n")
    stats.update({'gates_out': len(gates), 'inputs_out': len(ins), 'outputs': len(outs),
                  'pruned_gates': stats['gates_in'] - len(gates), 'pruned_inputs': pruned_in,
                  'constant_outputs': {o: consts[o] for o in const_outs}, 'held': holds})
    json.dump({'to_safe': m, 'to_orig': back, 'inputs': [m[i] for i in ins], 'outputs': [m[o] for o in outs],
               'stats': stats}, open(a.map, 'w'), indent=0)
    print(f"bench-clean: {stats['gates_in']} -> {len(gates)} gates, {len(ins)} inputs, {len(outs)} outputs; "
          f"pruned inputs {pruned_in}; constant outputs {list(stats['constant_outputs'])}", file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# Patterns: Atalanta test -> chain order -> STIL + serial testbench
# ═══════════════════════════════════════════════════════════════════════════
def read_atalanta_test(path):
    t = open(path).read()
    def names(section):
        m = re.search(r'\* ' + section + r'\s*:\s*\n(.*?)\n\s*\n', t, re.S)
        return m.group(1).split() if m else []
    pis, pos = names('Primary inputs'), names('Primary outputs')
    pats = []
    for m in re.finditer(r'^\s*\d+:\s*([01xX]+)\s+([01xX]+)\s*$', t, re.M):
        pats.append((m.group(1), m.group(2)))
    return pis, pos, pats


def cmd_patterns(a):
    scan = json.load(open(a.scan))
    mp = json.load(open(a.map))
    orig = mp['to_orig']
    holds = dict(h.split('=') for h in (a.hold or []))
    pis, pos, pats = read_atalanta_test(a.test)
    if not pats:
        raise SystemExit(f"ERROR: no patterns in {a.test}")
    # pseudo inputs: the cut flop name; pseudo outputs: '<inst>.d' (fault cut)
    flop_of = {}
    for k, ch in enumerate(scan['chains']):
        for j, f in enumerate(ch['flops']):
            flop_of[f['inst']] = (k, j)
    def classify_in(s):
        o = orig.get(s, s).lstrip('\\').strip()
        if o in flop_of:
            return ('flop', o)
        if o in scan['inputs']:
            return ('pi', o)
        raise SystemExit(f"ERROR: ATPG input {o} is neither a top input nor a traced scan flop")
    def classify_out(s):
        o = orig.get(s, s).lstrip('\\').strip()
        if o.endswith('.d') and o[:-2] in flop_of:
            return ('flop', o[:-2])
        if o in scan['outputs']:
            return ('po', o)
        raise SystemExit(f"ERROR: ATPG output {o} is neither a top output nor a traced scan flop D")
    cin = [classify_in(s) for s in pis]
    cout = [classify_out(s) for s in pos]
    missing = sorted(set(flop_of) - {n for k, n in cin if k == 'flop'})
    nchain = len(scan['chains'])
    L = max(ch['length'] for ch in scan['chains'])
    out_pats = []
    for vi, vo in pats:
        load = [['0'] * ch['length'] for ch in scan['chains']]
        pi = {}
        for (k, n), v in zip(cin, vi):
            v = '0' if v in 'xX' else v
            if k == 'flop':
                c, j = flop_of[n]
                load[c][j] = v
            else:
                pi[n] = v
        po, unload = {}, [['x'] * ch['length'] for ch in scan['chains']]
        for (k, n), v in zip(cout, vo):
            if k == 'flop':
                c, j = flop_of[n]
                unload[c][j] = v.lower()
            else:
                po[n] = v.lower()
        out_pats.append({'load': [''.join(x) for x in load], 'pi': pi, 'po': po, 'unload': [''.join(x) for x in unload]})
    doc = {'top': a.top, 'patterns': len(out_pats), 'chains': [{'scan_in': ch['scan_in'], 'scan_out': ch['scan_out'],
           'length': ch['length'], 'flops': [f['inst'] for f in ch['flops']]} for ch in scan['chains']],
           'holds': holds, 'unconstrained_flops': missing, 'data': out_pats}
    json.dump(doc, open(a.output, 'w'), indent=0)
    (ck, edge), (se, se_inv) = _single_clock(scan), _single_se(scan)
    # ── STIL-style pattern file ─────────────────────────────────────────────
    if a.stil:
        with open(a.stil, 'w') as f:
            f.write(f"STIL 1.0;\n// CBflow open-source ATPG patterns — {a.top} (Atalanta, stuck-at)\n")
            f.write(f"// scan clock {ck} ({edge}edge), scan enable {se}{' (active low)' if se_inv else ''}\n")
            f.write("ScanStructures {\n")
            for k, ch in enumerate(scan['chains']):
                f.write(f"  ScanChain \"chain{k}\" {{ ScanLength {ch['length']}; ScanIn \"{ch['scan_in']}\"; "
                        f"ScanOut \"{ch['scan_out']}\"; ScanCells {' '.join(fl['inst'] for fl in ch['flops'])}; }}\n")
            f.write("}\nPattern \"_pattern_\" {\n")
            for i, p in enumerate(out_pats):
                f.write(f"  \"pattern {i}\": Call \"load_unload\" {{ " +
                        ' '.join(f"\"chain{k}\"={p['load'][k]};" for k in range(nchain)) + " }\n")
                f.write("    Call \"capture\" { _pi=" + ''.join(p['pi'].get(n, holds.get(n, '0')) for n in scan['inputs']) +
                        "; _po=" + ''.join(p['po'].get(n, 'x') for n in scan['outputs']) + "; }\n")
                f.write("    // expected unload: " + ' '.join(f"chain{k}={p['unload'][k]}" for k in range(nchain)) + "\n")
            f.write("}\n")
    # ── serial-scan testbench ───────────────────────────────────────────────
    if a.tb:
        h, ck, se, se_on, se_off = _tb_head(scan, a.top, a.tb_name, holds)
        b = list(h)
        sel = {ch['scan_out'] for ch in scan['chains']}
        def shift(load, unload, tag):
            # shift L cycles: bit for flop j enters at cycle (L - len) + (len-1-j) ... load order:
            # the first bit shifted in ends in the last flop (nearest scan_out).
            s = [f"    {_vid(se)} = 1'b{se_on};"]
            for t in range(L):
                for k, ch in enumerate(scan['chains']):
                    n = ch['length']
                    pos_ = t - (L - n)          # chains shorter than L start late
                    if pos_ >= 0:
                        j = n - 1 - pos_        # flop that this bit ends in
                        v = load[k][j] if load else '0'
                        # undo the inversions between scan_in and flop j
                        par = ch['scan_in_inv']
                        for f in ch['flops'][:j]:
                            par ^= f['inv_out']
                        v = str(int(v) ^ int(par))
                    else:
                        v = '0'
                    s.append(f"    {_vid(ch['scan_in'])} = 1'b{v};")
                s.append("    #2;")
                if unload:
                    for k, ch in enumerate(scan['chains']):
                        n = ch['length']
                        # scan_out shows flop n-1 first, then n-2, …
                        if t < n:
                            j = n - 1 - t
                            v = unload[k][j]
                            if v in '01':
                                par = ch['flops'][j]['inv_out']
                                for f in ch['flops'][j + 1:]:
                                    par ^= f['inv_out']
                                v = str(int(v) ^ int(par))
                                so = _vid(ch['scan_out'])
                                s.append(f"    checks = checks + 1; if ({so} !== 1'b{v}) begin errors = errors + 1; "
                                         f"$display(\"MISMATCH {tag} unload chain{k} cell {ch['flops'][j]['inst']}: got %b exp {v}\", {so}); end")
                s.append("    pulse;")
            return s
        prev = None
        for i, p in enumerate(out_pats):
            b.append(f"    // ── pattern {i}")
            b += shift(p['load'], prev['unload'] if prev else None, f"p{i - 1}")
            b.append(f"    {_vid(se)} = 1'b{se_off};")
            for n in scan['inputs']:
                if n == ck or n in sel:
                    continue
                if n in p['pi']:
                    b.append(f"    {_vid(n)} = 1'b{p['pi'][n]};")
            b.append("    #4;")
            for n, v in p['po'].items():
                if v in '01':
                    b.append(f"    checks = checks + 1; if ({_vid(n)} !== 1'b{v}) begin errors = errors + 1; "
                             f"$display(\"MISMATCH p{i} capture PO {n}: got %b exp {v}\", {_vid(n)}); end")
            b.append("    pulse;")
            prev = p
        b.append("    // ── unload of the last pattern")
        b += shift(None, prev['unload'], f"p{len(out_pats) - 1}")
        b += [f"    $display(\"Patterns: {len(out_pats)}\");", "    $display(\"Checks: %0d\", checks);",
              "    $display(\"Mismatches: %0d\", errors);",
              "    if (errors == 0) $display(\"SCAN PATTERN TEST PASSED\"); else $display(\"SCAN PATTERN TEST FAILED\");",
              "    $finish;", "  end", "endmodule"]
        open(a.tb, 'w').write('\n'.join(b) + '\n')
    print(f"patterns: {len(out_pats)} patterns, {nchain} chain(s), max length {L}; unconstrained flops {len(missing)}", file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# Fault simulation (independent of the ATPG engine)
# ═══════════════════════════════════════════════════════════════════════════
def _eval(t, ins, ones):
    if t in ('BUFF', 'BUF'):
        return ins[0]
    if t == 'NOT':
        return ~ins[0] & ones
    if t in ('AND', 'NAND'):
        v = ones
        for x in ins:
            v &= x
        return v if t == 'AND' else ~v & ones
    if t in ('OR', 'NOR'):
        v = 0
        for x in ins:
            v |= x
        return v if t == 'OR' else ~v & ones
    if t in ('XOR', 'XNOR'):
        v = 0
        for x in ins:
            v ^= x
        return v if t == 'XOR' else ~v & ones
    raise SystemExit(f"ERROR: fsim: unsupported gate type {t}")


def cmd_fsim(a):
    """Stuck-at fault simulation of an ATPG pattern set on the (clean) bench:
    every net stem and every fan-out branch, stuck-at-0 and stuck-at-1
    (uncollapsed pin faults), all patterns bit-parallel, each fault
    re-simulated over its fan-out cone only. --sample N simulates a random
    sample of N faults (fixed seed): fault coverage estimate +- 95 % CI."""
    import random
    ins, outs, gates = read_bench(a.bench)
    pis, pos, pats = read_atalanta_test(a.test)
    if pis != ins:
        raise SystemExit("ERROR: fsim: pattern input order differs from the bench inputs")
    P = len(pats)
    ones = (1 << P) - 1
    # topological order
    order, state = [], {}
    fan = {}
    for g, (t, args) in gates.items():
        for x in args:
            fan.setdefault(x, []).append(g)
    sys.setrecursionlimit(1000000)
    def visit(n):
        st = state.get(n)
        if st == 2 or n not in gates:
            return
        if st == 1:
            raise SystemExit(f"ERROR: fsim: combinational loop at {n}")
        state[n] = 1
        for x in gates[n][1]:
            visit(x)
        state[n] = 2
        order.append(n)
    for g in gates:
        visit(g)
    topo = {g: i for i, g in enumerate(order)}
    good = {}
    for k, n in enumerate(ins):
        v = 0
        for p, (vi, _) in enumerate(pats):
            if vi[k] == '1':
                v |= 1 << p
        good[n] = v
    for g in order:
        t, args = gates[g]
        good[g] = _eval(t, [good[x] for x in args], ones)
    po_set = set(outs)
    # Pin fault model: nl2bench decomposes each library cell into gates named
    # <cell output net>.<k>.<k>… — those internal nets are not netlist pins.
    # Faults: stuck-at 0/1 on every real net (stem) and, for a net feeding
    # several cells, on each cell input branch (the net forced in every gate of
    # that cell).
    mp_ = json.load(open(a.map))['to_orig'] if a.map else {}
    def cell_of(g):
        o = mp_.get(g, g)
        return re.sub(r'(\.\d+)+$', '', o) if re.search(r'\.\d+$', o) else o
    internal = {g for g in gates if cell_of(g) != mp_.get(g, g)}
    owner = {g: cell_of(g) for g in gates}
    faults = []
    for n in list(ins) + order:
        if n in internal:
            continue
        for sv in (0, 1):
            faults.append((n, None, sv))
        groups = {}
        for g in fan.get(n, []):
            groups.setdefault(owner[g], []).append(g)
        if len(groups) > 1:
            for cg, gl in groups.items():
                for sv in (0, 1):
                    faults.append((n, tuple(gl), sv))
    total = len(faults)
    if a.sample and a.sample < total:
        random.Random(a.seed).shuffle(faults)
        faults = faults[:a.sample]
    cone_cache = {}
    def cone(start_gates):
        key = tuple(sorted(start_gates))
        if key in cone_cache:
            return cone_cache[key]
        seen, todo = set(), list(start_gates)
        while todo:
            g = todo.pop()
            if g in seen:
                continue
            seen.add(g)
            todo.extend(fan.get(g, []))
        res = sorted(seen, key=topo.get)
        if len(cone_cache) < 20000:
            cone_cache[key] = res
        return res
    detected = 0
    undetected = []
    for n, br, sv in faults:
        fv = ones if sv else 0
        bad = {}
        if br is None:
            if good[n] == fv:
                undetected.append((n, br, sv))
                continue
            bad[n] = fv
            diff = fv ^ good[n] if n in po_set else 0
            gl = cone(fan.get(n, []))
        else:
            # the net forced at the input of every gate of one cell; the
            # cell's gates are re-evaluated in topological order
            diff, starts = 0, []
            for b in sorted(br, key=topo.get):
                t, args = gates[b]
                v = _eval(t, [fv if x == n else bad.get(x, good[x]) for x in args], ones)
                if v != good[b]:
                    bad[b] = v
                    starts.extend(fan.get(b, []))
                    if b in po_set:
                        diff |= v ^ good[b]
            if not bad:
                undetected.append((n, br, sv))
                continue
            gl = [g for g in cone(starts) if g not in br]
        for g in gl:
            t, args = gates[g]
            v = _eval(t, [bad.get(x, good[x]) for x in args], ones)
            if v != good[g]:
                bad[g] = v
                if g in po_set:
                    diff |= v ^ good[g]
            if diff:
                break
        if diff:
            detected += 1
        else:
            undetected.append((n, br, sv))
    sim = len(faults)
    fc = 100.0 * detected / sim if sim else 100.0
    ci = 196.0 * ((fc / 100 * (1 - fc / 100)) / sim) ** 0.5 if (a.sample and a.sample < total and sim) else 0.0
    d = {'patterns': P, 'fault_universe': total, 'faults_simulated': sim, 'sampled': bool(a.sample and a.sample < total),
         'detected': detected, 'fault_coverage_pct': round(fc, 3), 'ci95_pct': round(ci, 3)}
    mp = {}
    if a.map:
        mp = json.load(open(a.map))['to_orig']
    name = lambda n: mp.get(n, n)
    lines = [f"Fault simulation — independent of the ATPG engine (oss_dft.py fsim)",
             f"  Patterns            : {P}",
             f"  Fault universe      : {total} (stuck-at 0/1 on every netlist net and cell input branch, uncollapsed)",
             f"  Faults simulated    : {sim}" + (f" (random sample, seed {a.seed})" if d['sampled'] else ""),
             f"  Detected            : {detected}",
             f"  Fault coverage      : {fc:.3f} %" + (f"  (+- {ci:.2f} % at 95 % confidence)" if d['sampled'] else ""),
             "", f"  Undetected (first 100 of {len(undetected)}):"]
    lines += [f"    {name(n)}{(' -> ' + cell_of(br[0])) if br else ''} stuck-at-{sv}" for n, br, sv in undetected[:100]]
    open(a.output, 'w').write('\n'.join(lines) + '\n')
    if a.json:
        json.dump(d, open(a.json, 'w'), indent=1)
    print('\n'.join(lines[:6]), file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# Reports
# ═══════════════════════════════════════════════════════════════════════════
def cmd_coverage(a):
    log = open(a.log).read()
    g = lambda pat, cast=float: (cast(m.group(1)) if (m := re.search(pat, log)) else None)
    d = {'patterns': g(r'after compaction\s*:\s*(\d+)', int) or g(r'Number of test patterns before compaction\s*:\s*(\d+)', int),
         'fault_coverage_pct': g(r'Fault coverage\s*:\s*([\d.]+)'),
         'collapsed_faults': g(r'Number of collapsed faults\s*:\s*(\d+)', int),
         'redundant_faults': g(r'identified redundant faults\s*:\s*(\d+)', int),
         'aborted_faults': g(r'Number of aborted faults\s*:\s*(\d+)', int),
         'backtracks': g(r'Total number of backtrackings\s*:\s*(\d+)', int),
         'atpg_cpu_s': g(r'Total\s*:\s*([\d.]+)\s*Secs')}
    if None in (d['collapsed_faults'], d['redundant_faults'], d['aborted_faults']):
        raise SystemExit(f"ERROR: Atalanta summary not found in {a.log}")
    det = d['collapsed_faults'] - d['redundant_faults'] - d['aborted_faults']
    d['detected_faults'] = det
    d['test_coverage_pct'] = round(100.0 * det / (d['collapsed_faults'] - d['redundant_faults']), 3) \
        if d['collapsed_faults'] > d['redundant_faults'] else 100.0
    m = json.load(open(a.map))['stats'] if a.map else {}
    d['bench_gates_total'] = m.get('gates_in')
    d['bench_gates_tested'] = m.get('gates_out')
    d['excluded_gates'] = m.get('pruned_gates')
    d['excluded_inputs'] = m.get('pruned_inputs')
    d['held_ports'] = m.get('held')
    d['excluded_logic_pct'] = round(100.0 * d['excluded_gates'] / d['bench_gates_total'], 2) if d.get('bench_gates_total') else None
    fs = json.load(open(a.fsim)) if a.fsim else None
    if fs:
        d['fsim'] = fs
    lines = [f"ATPG coverage report — {a.design} (stuck-at, Atalanta)",
             f"  Patterns              : {d['patterns']}",
             f"  Collapsed faults      : {d['collapsed_faults']}",
             f"  Detected faults       : {det}",
             f"  Redundant (untestable): {d['redundant_faults']}",
             f"  Aborted               : {d['aborted_faults']}",
             f"  Fault coverage        : {d['fault_coverage_pct']:.3f} %",
             f"  Test coverage         : {d['test_coverage_pct']:.3f} %",
             f"  ATPG CPU time s       : {d['atpg_cpu_s']}",
             "",
             "  Fault universe: the scan-cut combinational netlist (flops -> pseudo inputs / outputs).",
             f"  Logic outside ATPG    : {d['excluded_gates']} of {d['bench_gates_total']} gates ({d['excluded_logic_pct']} %) —",
             "                          unobservable / uncontrollable after the cut (scan-shift path, macro",
             "                          boundaries, held ports); their faults are not in the counts above.",
             f"  Inputs unused by ATPG : {', '.join(d['excluded_inputs'] or []) or '-'}",
             f"  Held ports            : {', '.join(f'{k}={v}' for k, v in (d['held_ports'] or {}).items()) or '-'}"]
    if fs:
        lines += ["", "  Independent fault simulation (cell-pin stuck-at faults, oss_dft.py fsim):",
                  f"  Pin faults            : {fs['fault_universe']}" + (f" ({fs['faults_simulated']} sampled)" if fs['sampled'] else ''),
                  f"  Pin fault coverage    : {fs['fault_coverage_pct']:.3f} %" + (f"  (+- {fs['ci95_pct']} %)" if fs['sampled'] else '')]
    if a.ufaults and os.path.isfile(a.ufaults):
        uf = [ln.strip() for ln in open(a.ufaults) if ln.strip()]
        d['undetected_listed'] = len(uf)
        lines += ["", f"  Undetected faults (redundant + aborted, first 50 of {len(uf)}):"] + [f"    {u}" for u in uf[:50]]
    open(a.output, 'w').write('\n'.join(lines) + '\n')
    if a.json:
        json.dump(d, open(a.json, 'w'), indent=1)
    print('\n'.join(lines[:9]), file=sys.stderr)


def cmd_toggle(a):
    """Toggle coverage from a VCD: a bit counts as toggled when it was seen at
    0 and at 1 (both transitions) after the first value change."""
    ids, vals, seen = {}, {}, {}
    scope = []
    with open(a.vcd, errors='replace') as f:
        header = True
        for ln in f:
            ln = ln.strip()
            if header:
                if ln.startswith('$scope'):
                    scope.append(ln.split()[2])
                elif ln.startswith('$upscope'):
                    scope.pop()
                elif ln.startswith('$var'):
                    p = ln.split()
                    width, code, name = int(p[2]), p[3], p[4]
                    ids.setdefault(code, []).append(('.'.join(scope + [name]), width))
                elif ln.startswith('$enddefinitions'):
                    header = False
                continue
            if not ln or ln[0] in '#$':
                continue
            if ln[0] in '01xzXZ':
                v, code = ln[0], ln[1:]
                bits = [v]
            elif ln[0] in 'bB':
                v, code = ln[1:].split()
                bits = list(v)
            else:
                continue
            if code not in ids:
                continue
            w = ids[code][0][1]
            bits = (['0'] * (w - len(bits)) + bits) if len(bits) < w else bits[-w:]
            st = seen.setdefault(code, [set() for _ in range(w)])
            for i, bv in enumerate(bits):
                if bv in '01':
                    st[i].add(bv)
    total = toggled = 0
    for code, nm in ids.items():
        w = nm[0][1]
        st = seen.get(code, [set() for _ in range(w)])
        total += w
        toggled += sum(1 for s in st if s == {'0', '1'})
    pct = 100.0 * toggled / total if total else 0.0
    open(a.output, 'w').write(f"Toggle coverage — {a.vcd}\n  Signal bits : {total}\n  Toggled     : {toggled}\n"
                              f"  Toggle coverage : {pct:.2f} %\n")
    print(f"toggle: {toggled}/{total} bits ({pct:.2f} %)", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('cells'); p.add_argument('--lib', action='append', required=True); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('trace')
    for k in ('json', 'top', 'cells', 'scan-in', 'scan-out', 'scan-enable'):
        p.add_argument('--' + k, required=True)
    p.add_argument('--max-length', type=int, default=0); p.add_argument('--clock-mixing', default='no_mix')
    p.add_argument('-o', '--output', required=True); p.add_argument('--scandef'); p.add_argument('--report')
    p = sp.add_parser('flush-tb'); p.add_argument('--scan', required=True); p.add_argument('--top', required=True)
    p.add_argument('--hold', action='append'); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('bench-clean'); p.add_argument('--bench', required=True); p.add_argument('-o', '--output', required=True)
    p.add_argument('--map', required=True); p.add_argument('--hold', action='append')
    p = sp.add_parser('patterns')
    for k in ('test', 'map', 'scan', 'top'):
        p.add_argument('--' + k, required=True)
    p.add_argument('--hold', action='append'); p.add_argument('-o', '--output', required=True)
    p.add_argument('--stil'); p.add_argument('--tb'); p.add_argument('--tb-name', default='cbflow_scan_tb')
    p = sp.add_parser('coverage'); p.add_argument('--log', required=True); p.add_argument('--map')
    p.add_argument('--design', default=''); p.add_argument('--ufaults'); p.add_argument('--fsim')
    p.add_argument('-o', '--output', required=True); p.add_argument('--json')
    p = sp.add_parser('toggle'); p.add_argument('--vcd', required=True); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('stubs'); p.add_argument('--json', required=True); p.add_argument('--top', required=True)
    p.add_argument('--cells'); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('census')
    for k in ('json', 'top', 'cells', 'scan-in', 'scan-enable'):
        p.add_argument('--' + k, required=True)
    p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('fsim'); p.add_argument('--bench', required=True); p.add_argument('--test', required=True)
    p.add_argument('--map'); p.add_argument('--sample', type=int, default=0); p.add_argument('--seed', type=int, default=1)
    p.add_argument('-o', '--output', required=True); p.add_argument('--json')
    p = sp.add_parser('model-fix'); p.add_argument('--model', required=True); p.add_argument('-o', '--output', required=True)
    a = ap.parse_args()
    {'cells': cmd_cells, 'trace': cmd_trace, 'flush-tb': cmd_flush_tb, 'bench-clean': cmd_bench_clean,
     'patterns': cmd_patterns, 'coverage': cmd_coverage, 'toggle': cmd_toggle, 'stubs': cmd_stubs,
     'model-fix': cmd_model_fix, 'fsim': cmd_fsim, 'census': cmd_census}[a.cmd](a)


if __name__ == '__main__':
    main()
