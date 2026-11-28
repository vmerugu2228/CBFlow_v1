#!/usr/bin/env python3
"""spec2rtl helpers (spec2rtl skill) — deterministic parts of the spec -> RTL loop.

    s2r.py ctx      --spec <block.spec.yaml> --work <dir> [--lib-config <lib_config.tcl>]
    s2r.py scaffold --spec <block.spec.yaml> --work <dir> --rtl <dir>
    s2r.py gate     --spec <block.spec.yaml> --work <dir> --rtl <dir>
                    [--lib-config <lib_config.tcl>] [--tb <file.sv | cocotb dir>] [--sby <file.sby>]
                    [--only lint,synth,ports,sim,formal]

ctx       compiles the spec (spec_tool check) and the register block (PeakRDL,
          spec_tool regs), and writes <work>/ctx.md: clocks / resets, ports per
          interface with protocol, register map + the hwif struct fields the
          logic drives / reads, memories with their macro ports, features.
scaffold  writes (never overwrites) <rtl>/<top>.sv — the exact port list of the
          spec, the register block instance, hwif structs, memory macro
          instances — and <rtl>/<top>_sva.sv (valid / ready and APB protocol
          assertions, bound to the top) + <work>/<top>.sby (SymbiYosys).
gate      runs in the CBflow open-source container (global/bin/cbflow-oss):
          lint     verilator --lint-only -Wall + slang (errors fail; warnings listed)
          synth    sv2v + yosys: no latches, no multiple drivers / undriven
                   (check), cell statistics
          ports    yosys JSON vs the spec ports + memories (spec_tool ports)
          sim      a SystemVerilog testbench (verilator --binary --timing) or a
                   cocotb directory (make); pass = exit 0, a PASS line, no FAIL / ERROR
          formal   sby -f <sby> (DONE (PASS))
          writes <work>/gate.json (with --only: gate_<stages>.json) and prints one line per
          stage; exit 1 on any FAIL. Testbench convention: a line starting with PASS
          (or TEST PASSED) when all pass; FAIL ... (or ERROR:) per failure.
Environment: CBFLOW_OSS_TOOLS (PeakRDL Python, z3) as for the CBflow RTL flows.
"""
import argparse
import glob
import json
import os
import re
import shlex
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
OSS = os.path.join(ROOT, 'global', 'bin', 'cbflow-oss')
SPEC_TOOL = os.path.join(ROOT, 'RTL', 'utils', 'oss', 'spec_tool.py')
MOUNTS = set()          # host dirs the container needs (work / rtl / spec / tb / library tag)


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def oss(cmd, log, cwd=None, timeout=1800):
    """Run a shell command in the container; output to log; (rc, text)."""
    if not os.environ.get('CBFLOW_OSS_TOOLS'):
        die('CBFLOW_OSS_TOOLS is not set (the tools dir the CBflow RTL flows use, lsf(oss,tools_dir))')
    full = (f'cd {shlex.quote(cwd)} && ' if cwd else '') + \
        'export PYTHONPATH=${CBFLOW_OSS_PYTHON:-}${PYTHONPATH:+:$PYTHONPATH}; ' + cmd
    mounts = ':'.join(sorted({ROOT, os.path.realpath(cwd or ROOT)} | MOUNTS | set(
        p for p in os.environ.get('CBFLOW_OSS_MOUNTS', '').split(':') if p)))
    env = dict(os.environ, CBFLOW_OSS_MOUNTS=mounts)
    r = subprocess.run([OSS, 'exec', '--', 'bash', '-c', full], capture_output=True, text=True,
                       timeout=timeout, env=env)
    out = r.stdout + r.stderr
    with open(log, 'w') as fh:
        fh.write(out)
    return r.returncode, out


def load_spec(path):
    import yaml
    s = yaml.safe_load(open(path))
    for k in ('block', 'ports', 'rtl'):
        if k not in s:
            die(f'{path}: no "{k}"')
    return s


def regs_rdl(spec_path, s):
    for itf in s.get('interfaces', []) or []:
        if itf.get('registers'):
            p = os.path.join(os.path.dirname(os.path.abspath(spec_path)), itf['registers'])
            return p, itf
    return None, None


def compile_regs(spec_path, s, work):
    """PeakRDL register block -> <work>/regs (spec_tool regs); [rtl files]."""
    rdl, _ = regs_rdl(spec_path, s)
    if not rdl:
        return []
    if not rdl.endswith('.rdl'):
        rdl_out = os.path.join(work, f'{s["block"]}_regs.rdl')
        rc, out = oss(f'python3 {SPEC_TOOL} xls2rdl --xls {shlex.quote(rdl)} --addrmap {s["block"]}_regs '
                      f'-o {rdl_out}', os.path.join(work, 'xls2rdl.log'))
        if rc:
            die(f'xls2rdl failed: {out[-400:]}')
        rdl = rdl_out
    out_dir = os.path.join(work, 'regs')
    rc, out = oss(f'python3 {SPEC_TOOL} regs --rdl {shlex.quote(rdl)} --out {out_dir}',
                  os.path.join(work, 'regs.log'))
    if rc:
        die(f'register block generation failed (see {work}/regs.log): {out[-400:]}')
    rtl = sorted(glob.glob(os.path.join(out_dir, 'rtl', '*.sv')), key=lambda f: (not f.endswith('_pkg.sv'), f))
    return rtl


def hwif_fields(pkg):
    """struct name -> [(member, type)] of the PeakRDL package."""
    txt = open(pkg).read()
    out = {}
    for m in re.finditer(r'typedef struct(?: packed)?\s*\{(.*?)\}\s*(\w+)\s*;', txt, re.S):
        out[m.group(2)] = re.findall(r'^\s*([\w:]+(?:\s*\[[^\]]+\])?)\s+(\w+)\s*;', m.group(1), re.M)
    return out


def flatten_hwif(structs, top, prefix):
    """hwif_in / hwif_out leaf paths: [(path, type)]."""
    out = []
    for typ, name in structs.get(top, []):
        base = typ.split('[')[0].strip()
        if base in structs:
            out += flatten_hwif(structs, base, f'{prefix}.{name}')
        else:
            out.append((f'{prefix}.{name}', typ))
    return out


def macro_ports(lib_config, macro):
    """Ports of a memory macro from the library tag's Verilog model."""
    if not lib_config:
        return []
    r = subprocess.run(['tclsh'], input=f'array set project {{}}\nsource {{{lib_config}}}\n'
                       'if {[info exists tech(verilog,memory)]} { puts [join $tech(verilog,memory) \\n] }\n',
                       capture_output=True, text=True)
    for v in r.stdout.split():
        if not os.path.exists(v):
            continue
        txt = re.sub(r'//[^\n]*', '', open(v).read())
        # power pins (`ifdef USE_POWER_PINS) are not connected in RTL
        txt = re.sub(r'`ifdef\s+USE_POWER_PINS.*?`endif', '', txt, flags=re.S)
        m = re.search(r'module\s+' + re.escape(macro) + r'\b(.*?)endmodule', txt, re.S)
        if not m:
            continue
        body = m.group(1)
        ports = []
        for d, w, names in re.findall(r'\b(input|output|inout)\s+(?:wire\s+|reg\s+)?(\[[^\]]+\])?\s*([\w\s,]+?);', body):
            for n in names.split(','):
                n = n.strip()
                if n:
                    ports.append((d, w or '', n))
        return ports
    return []


def width(p):
    return f'[{p["width"] - 1}:0] ' if int(p['width']) > 1 else ''


# ── ctx ─────────────────────────────────────────────────────────────────────
def cmd_ctx(a):
    s = load_spec(a.spec)
    os.makedirs(a.work, exist_ok=True)
    rc, out = oss(f'python3 {SPEC_TOOL} check --spec {shlex.quote(os.path.abspath(a.spec))} '
                  f'-o {a.work}/spec.json --report {a.work}/spec_check.rpt', os.path.join(a.work, 'spec_check.log'))
    if rc:
        die(f'spec check failed (see {a.work}/spec_check.log):\n{out[-800:]}')
    regs = compile_regs(a.spec, s, a.work)
    L = [f'# {s["block"]} — design brief (from {os.path.basename(a.spec)})', '',
         (s.get('description') or '').strip(), '']
    L += ['## Clocks / resets'] + [f'- clock `{c["port"]}` {c.get("period_ns")} ns' for c in s.get('clocks', [])] + \
         [f'- reset `{r["port"]}` active-{r.get("active", "high")}, '
          f'{"synchronous" if r.get("synchronous", True) else "asynchronous"}' for r in s.get('resets', [])] + ['']
    by_itf = {}
    for p in s['ports']:
        by_itf.setdefault(p.get('interface', '-'), []).append(p)
    itfs = {i['name']: i for i in s.get('interfaces', []) or []}
    L.append('## Ports (exact names / widths — the RTL must match)')
    for itf, ps in by_itf.items():
        i = itfs.get(itf, {})
        L.append(f'### {itf}' + (f' — {i.get("protocol")} {i.get("mode")}' if i else ''))
        for p in ps:
            L.append(f'- `{p["dir"]:3s} [{p["width"]}] {p["name"]}`' + (f' — {p["desc"]}' if p.get('desc') else ''))
    L.append('')
    if regs:
        pkg = next((f for f in regs if f.endswith('_pkg.sv')), None)
        top_mod = next((os.path.basename(f)[:-3] for f in regs if not f.endswith('_pkg.sv')), '')
        L += ['## Register block (generated — instantiate, never hand-write)',
              f'- module `{top_mod}` + package `{os.path.basename(pkg)[:-3] if pkg else "?"}`: files '
              + ', '.join(os.path.relpath(f, a.work) for f in regs),
              '- CPU interface: APB4 flattened `s_apb_*`, plus `clk`, `rst`, `hwif_in`, `hwif_out`']
        if pkg:
            st = hwif_fields(pkg)
            for kind in ('in', 'out'):
                t = f'{top_mod}__{kind}_t'
                leaves = flatten_hwif(st, t, f'hwif_{kind}')
                if leaves:
                    L.append(f'- `{t}` ({"logic drives" if kind == "in" else "logic reads"}):')
                    L += [f'  - `{p}` : {ty}' for p, ty in leaves]
        rj = os.path.join(a.work, 'regs', 'regs.json')
        if os.path.exists(rj):
            L.append(f'- register map: {json.load(open(rj)).get("registers")} registers; '
                     f'docs {os.path.relpath(os.path.join(a.work, "regs", "html", "index.html"), a.work)}')
        rdl, _ = regs_rdl(a.spec, s)
        if rdl and rdl.endswith('.rdl'):
            L += ['', '```systemrdl', open(rdl).read().strip(), '```']
        L.append('')
    if s.get('memories'):
        L.append('## Memories (hard macros of the library tag)')
        for m in s['memories']:
            L.append(f'- `{m["inst"]}` : {m["macro"]} {m.get("depth")}x{m.get("width")} — {m.get("desc", "")}')
            for pt in m.get('ports', []):
                L.append(f'  - port {pt["name"]} ({pt["type"]}) — {pt.get("use", "")}')
            mp = macro_ports(a.lib_config, m['macro'])
            if mp:
                L.append('  - macro pins: ' + ', '.join(f'{d} {w}{n}'.replace('  ', ' ') for d, w, n in mp))
        L.append('')
    if s.get('features'):
        L.append('## Features (each must be implemented and tested)')
        for f in s['features']:
            L.append(f'- **{f["id"]} {f["name"]}** ({f.get("priority")}, {f.get("milestone")}): {f["desc"]}'
                     + (f' — tests {", ".join(f.get("tests", []))}' if f.get('tests') else ''))
        L.append('')
    L += ['## RTL', f'- top `{s["rtl"]["top"]}`, {s["rtl"].get("language", "systemverilog")}',
          f'- sources (spec rtl.sources): {", ".join(s["rtl"].get("sources", []))}']
    with open(os.path.join(a.work, 'ctx.md'), 'w') as fh:
        fh.write('\n'.join(L) + '\n')
    print(f'brief: {a.work}/ctx.md  ({len(s["ports"])} ports, {len(regs)} register-block files, '
          f'{len(s.get("memories") or [])} memories, {len(s.get("features") or [])} features)')
    return 0


# ── scaffold ────────────────────────────────────────────────────────────────
def cmd_scaffold(a):
    s = load_spec(a.spec)
    top = s['rtl']['top']
    os.makedirs(a.rtl, exist_ok=True)
    os.makedirs(a.work, exist_ok=True)
    regs = sorted(glob.glob(os.path.join(a.work, 'regs', 'rtl', '*.sv')))
    reg_mod = next((os.path.basename(f)[:-3] for f in regs if not f.endswith('_pkg.sv')), '')
    rdl, itf = regs_rdl(a.spec, s)
    if rdl and not reg_mod:
        die(f'register block not generated — run ctx first ({a.work}/regs)')
    written = []
    f_top = os.path.join(a.rtl, f'{top}.sv')
    if not os.path.exists(f_top):
        rst = (s.get('resets') or [{}])[0]
        clk = (s.get('clocks') or [{}])[0]
        L = [f'// {top} — generated scaffold (spec2rtl): ports, register block and memories from',
             f'// {os.path.basename(a.spec)}. Fill the logic; keep the port list as the spec defines it.',
             '`default_nettype none', f'module {top}' + (f'\n    import {reg_mod}_pkg::*;' if reg_mod else ''), '(']
        ports = s['ports']
        for i, p in enumerate(ports):
            d = {'in': 'input ', 'out': 'output', 'inout': 'inout '}[p['dir']]
            L.append(f'    {d} wire {width(p):8s}{p["name"]}{"," if i < len(ports) - 1 else ""}'
                     + (f'  // {p["desc"]}' if p.get('desc') else ''))
        L += [');', '']
        if reg_mod:
            pre = (itf or {}).get('prefix', 's_apb_')
            names = [p['name'] for p in ports if p['name'].startswith(pre)]
            L += ['    // ── registers (generated register block) ──',
                  f'    {reg_mod}__in_t  hwif_in;', f'    {reg_mod}__out_t hwif_out;', '',
                  f'    {reg_mod} u_regs (',
                  f'        .clk({clk.get("port", "clk")}), .rst({rst.get("port", "reset")}),']
            L += [f'        .{n}({n}),' for n in names]
            L += ['        .hwif_in(hwif_in), .hwif_out(hwif_out)', '    );', '']
        for m in s.get('memories') or []:
            mp = macro_ports(a.lib_config, m['macro'])
            L.append(f'    // ── {m["inst"]}: {m["macro"]} {m.get("depth")}x{m.get("width")} — {m.get("desc", "")}')
            if mp:
                L.append(f'    {m["macro"]} {m["inst"]} (')
                L += [f'        .{n}(/* {d} {w} */){"," if j < len(mp) - 1 else ""}' for j, (d, w, n) in enumerate(mp)]
                L.append('    );')
            else:
                L.append(f'    // {m["macro"]} {m["inst"]} (...);  — pins: pass --lib-config to list them')
            L.append('')
        L += ['    // ── logic ──', '    // TODO(spec2rtl): implement the features of the spec', '', 'endmodule',
              '`default_nettype wire', '']
        with open(f_top, 'w') as fh:
            fh.write('\n'.join(L))
        written.append(f_top)
    # protocol checks: immediate assertions with $past (Verilator --assert and the
    # open-source SymbiYosys front end — no concurrent SVA), in <top>_sva bound to
    # the top for simulation, and in the formal harness <top>_ftop for sby
    f_sva = os.path.join(a.rtl, f'{top}_sva.sv')
    clk = (s.get('clocks') or [{}])[0].get('port', 'clk')
    rst = (s.get('resets') or [{}])[0]
    rst_p = rst.get('port', 'reset')
    in_rst = f'{rst_p}' if rst.get('active', 'high') == 'high' else f'!{rst_p}'
    if not os.path.exists(f_sva):
        pdir = {p['name']: p for p in s['ports']}
        L = [f'// {top} protocol checks (spec2rtl): immediate assertions with $past.',
             f'// Simulation: bound to {top} (verilator --assert). Formal: {top}_ftop + {top}.sby.',
             f'module {top}_sva (', '    ' + ',\n    '.join(f'input wire {width(p)}{p["name"]}' for p in s['ports']),
             ');', '    reg past_ok;', '    initial past_ok = 1\'b0;', f'    always @(posedge {clk}) past_ok <= 1\'b1;',
             f'    always @(posedge {clk}) begin', f'        if (past_ok && !{in_rst} && !$past({in_rst})) begin']
        for i in s.get('interfaces', []) or []:
            sg = i.get('signals', {})
            if i.get('protocol') == 'valid_ready' and {'valid', 'ready'} <= set(sg):
                v, r, dat = sg['valid'], sg['ready'], sg.get('data')
                kind = 'assert' if pdir.get(v, {}).get('dir') == 'out' else 'assume'
                L += [f'            // {i["name"]} ({i.get("mode")}): valid held until ready, data stable while waiting',
                      f'            if ($past({v} && !{r})) {kind} ({v});']
                if dat:
                    L.append(f'            if ($past({v} && !{r})) {kind} ({dat} == $past({dat}));')
            if i.get('protocol') in ('apb4', 'apb') and i.get('mode') == 'slave':
                pre = i.get('prefix', 's_apb_')
                L += [f'            // {i["name"]}: APB slave — setup then access; held while not ready',
                      f'            if ($past({pre}psel && !{pre}penable)) assume ({pre}psel && {pre}penable);',
                      f'            if ($past({pre}psel && {pre}penable && !{pre}pready)) assume ({pre}psel && {pre}penable '
                      f'&& {pre}paddr == $past({pre}paddr) && {pre}pwrite == $past({pre}pwrite));',
                      f'            if (!{pre}psel) assume (!{pre}penable);']
        L += ['        end', '    end', 'endmodule', '`ifndef FORMAL', f'bind {top} {top}_sva u_sva (.*);', '`endif', '']
        with open(f_sva, 'w') as fh:
            fh.write('\n'.join(L))
        written.append(f_sva)
    f_ft = os.path.join(a.work, f'{top}_ftop.sv')
    if not os.path.exists(f_ft):
        ins = [p for p in s['ports'] if p['dir'] == 'in']
        outs = [p for p in s['ports'] if p['dir'] != 'in']
        L = [f'// formal harness: free inputs, {top} + {top}_sva (spec2rtl)', f'module {top}_ftop (',
             '    ' + ',\n    '.join(f'input wire {width(p)}{p["name"]}' for p in ins), ');']
        L += [f'    wire {width(p)}{p["name"]};' for p in outs]
        L += [f'    // start in reset', f'    reg init = 1\'b1;', f'    always @(posedge {clk}) init <= 1\'b0;',
              f'    always @(*) if (init) assume ({in_rst});',
              f'    {top} u_dut (' + ', '.join(f'.{p["name"]}({p["name"]})' for p in s['ports']) + ');',
              f'    {top}_sva u_sva (' + ', '.join(f'.{p["name"]}({p["name"]})' for p in s['ports']) + ');',
              'endmodule', '']
        with open(f_ft, 'w') as fh:
            fh.write('\n'.join(L))
        written.append(f_ft)
    f_sby = os.path.join(a.work, f'{top}.sby')
    if not os.path.exists(f_sby):
        with open(f_sby, 'w') as fh:
            fh.write(f'[options]\nmode prove\ndepth 12\n\n[engines]\nsmtbmc z3\n\n[script]\n'
                     f'read_slang -D FORMAL --top {top}_ftop @FILES@\nprep -top {top}_ftop\n'
                     f'chformal -early\n\n[files]\n@FILELIST@\n')
        written.append(f_sby)
    for w in written:
        print(f'wrote {w}')
    if not written:
        print('nothing written (files exist)')
    return 0


# ── gate ────────────────────────────────────────────────────────────────────
def rtl_files(a, s):
    top = s['rtl']['top']
    regs = sorted(glob.glob(os.path.join(a.work, 'regs', 'rtl', '*.sv')),
                  key=lambda f: (not f.endswith('_pkg.sv'), f))
    own = sorted(f for f in glob.glob(os.path.join(a.rtl, '*.sv')) + glob.glob(os.path.join(a.rtl, '*.v')))
    pkgs = [f for f in own if f.endswith('_pkg.sv')]
    sva = [f for f in own if f.endswith('_sva.sv')]
    body = [f for f in own if f not in pkgs and f not in sva]
    return regs + pkgs + body, sva, top


def macro_models(lib_config):
    if not lib_config:
        return []
    r = subprocess.run(['tclsh'], input=f'array set project {{}}\nsource {{{lib_config}}}\n'
                       'if {[info exists tech(verilog,memory)]} { puts [join $tech(verilog,memory) \\n] }\n',
                       capture_output=True, text=True)
    return [v for v in r.stdout.split() if os.path.exists(v)]


def macro_stubs(models, work):
    """Black-box stubs of the memory macro models (header, parameters, port
    declarations): formal treats the memories' outputs as free."""
    out = []
    for m in models:
        txt = re.sub(r'//[^\n]*', '', open(m).read())
        # power pins (`ifdef USE_POWER_PINS) are not part of the RTL instance
        txt = re.sub(r'`ifdef\s+USE_POWER_PINS.*?`endif', '', txt, flags=re.S)
        txt = re.sub(r'^\s*`\w+[^\n]*$', '', txt, flags=re.M)
        for mm in re.finditer(r'\bmodule\s+(\w+)\s*\((.*?)\)\s*;(.*?)\bendmodule', txt, re.S):
            name, plist, body = mm.groups()
            keep = [l.strip() for l in body.split(';')
                    if re.match(r'\s*(parameter|localparam|input|output|inout)\b', l)]
            stub = os.path.join(work, f'{name}_bb.v')
            outs = []
            for k in keep:
                mo = re.match(r'output\s+(?:reg\s+|wire\s+)?(\[[^\]]+\])?\s*([\w\s,]+)$', k)
                if mo:
                    outs += [(mo.group(1) or '', n.strip()) for n in mo.group(2).split(',') if n.strip()]
            body_k = [re.sub(r'^output\s+reg\b', 'output wire', k) for k in keep]
            with open(stub, 'w') as fh:
                fh.write(f'// free-output model of {name} for formal (spec2rtl)\n'
                         f'module {name}({" ".join(plist.split())});\n'
                         + ''.join(f'  {k};\n' for k in body_k)
                         + ''.join(f'  assign {n} = $anyseq;\n' for _, n in outs) + 'endmodule\n')
            out.append(stub)
    return out


def first_lines(txt, pat, n=12):
    return [l for l in txt.splitlines() if re.search(pat, l)][:n]


def cmd_gate(a):
    s = load_spec(a.spec)
    os.makedirs(a.work, exist_ok=True)
    # the spec JSON and the register block the gates need (as ctx makes them)
    if not os.path.exists(os.path.join(a.work, 'spec.json')):
        rc, out = oss(f'python3 {SPEC_TOOL} check --spec {shlex.quote(os.path.abspath(a.spec))} '
                      f'-o {a.work}/spec.json --report {a.work}/spec_check.rpt', os.path.join(a.work, 'spec_check.log'))
        if rc:
            die(f'spec check failed (see {a.work}/spec_check.log)')
    if regs_rdl(a.spec, s)[0] and not glob.glob(os.path.join(a.work, 'regs', 'rtl', '*.sv')):
        compile_regs(a.spec, s, a.work)
    files, sva, top = rtl_files(a, s)
    if not files:
        die(f'no RTL in {a.rtl}')
    mem = macro_models(a.lib_config)
    only = set(a.only.split(',')) if a.only else {'lint', 'synth', 'ports', 'sim', 'formal'}
    q = ' '.join(shlex.quote(f) for f in files)
    res = {}

    def stage(name, ok, detail, lines=()):
        res[name] = {'status': 'PASS' if ok else 'FAIL', 'detail': detail, 'messages': list(lines)}
        print(f'[{"PASS" if ok else "FAIL"}] {name:7s} {detail}')
        for l in lines:
            print(f'          {l}')

    if 'lint' in only:
        mq = ' '.join(f'-v {shlex.quote(m)}' for m in mem)
        rc1, o1 = oss(f'verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM '
                      f'--top-module {top} {mq} {q} {" ".join(shlex.quote(f) for f in sva)}',
                      os.path.join(a.work, 'lint_verilator.log'))
        rc2, o2 = oss(f'slang --top {top} {" ".join(shlex.quote(m) for m in mem)} {q}',
                      os.path.join(a.work, 'lint_slang.log'))
        # the agent's own RTL is gated; messages from the generated register block
        # and the PDK memory models are counted apart (not ours to fix)
        own = re.escape(a.rtl)
        mine = lambda pat, txt: [l for l in first_lines(txt, pat, 500) if re.search(own, l)]  # noqa: E731
        errs = mine(r'%Error', o1) + mine(r'error:', o2)
        warns = mine(r'%Warning', o1) + mine(r'warning:', o2)
        other = len(first_lines(o1, r'%(Error|Warning)', 500)) + len(first_lines(o2, r'(error|warning):', 500)) \
            - len(errs) - len(warns)
        fatal = [l for l in first_lines(o1, r'%Error', 50) if 'Exiting due to' not in l and not re.search(r'\.v:', l)
                 and not re.search(own, l) and 'regs' not in l]
        # warning classes that are design bugs in our RTL (research: latches, widths,
        # blocking in sequential logic, drivers) fail the gate; style ones are listed
        bad_cls = r'%Warning-(LATCH|WIDTH\w*|BLKSEQ|COMBDLY|MULTIDRIVEN|UNDRIVEN|IMPLICIT|SELRANGE|CASEINCOMPLETE|' \
                  r'ALWCOMBORDER|MULTITOP|UNOPTFLAT)\b'
        errs += [w for w in warns if re.search(bad_cls, w)]
        warns = [w for w in warns if not re.search(bad_cls, w)]
        stage('lint', not errs and not fatal,
              f'{len(errs)} error(s), {len(warns)} warning(s) in {os.path.basename(a.rtl)}/ '
              f'(verilator -Wall + slang; {other} message(s) in generated / library files)',
              errs + fatal + warns[:15])
    if 'synth' in only or 'ports' in only:
        v = os.path.join(a.work, f'{top}_sv2v.v')
        rc, o = oss(f'sv2v {q} > {shlex.quote(v)}', os.path.join(a.work, 'sv2v.log'))
        if rc:
            stage('synth', False, 'sv2v failed', first_lines(o, r'.', 10))
        else:
            libs = '; '.join(f'read_verilog -lib {shlex.quote(m)}' for m in mem)
            script = (f'{libs + "; " if libs else ""}read_verilog {v}; hierarchy -check -top {top}; proc; '
                      f'write_json {a.work}/design.json; '
                      f'select -assert-none t:$dlatch t:$adlatch t:$dlatchsr t:$_DLATCH_* ; '
                      f'check; flatten; synth -top {top} -run coarse:; stat')
            rc, o = oss(f'yosys -p {shlex.quote(script)}', os.path.join(a.work, 'synth.log'))
            latches = first_lines(o, r'^Latch inferred|selection is not empty', 10)
            probs = first_lines(o, r'Warning: (multiple conflicting drivers|Wire .* is used but has no driver|'
                                   r'found logic loop|Driver-driver conflict)', 10)
            cells = re.findall(r'^\s*(\d+)\s+cells\s*$', o, re.M) or re.findall(r'Number of cells:\s+(\d+)', o)
            if 'synth' in only:
                stage('synth', rc == 0 and not latches and not probs,
                      f'{len(latches)} latch(es), {len(probs)} driver problem(s), '
                      f'{cells[-1] if cells else "?"} cells (yosys)',
                      latches + probs + (first_lines(o, r'ERROR', 6) if rc else []))
            if 'ports' in only:
                macros = [os.path.basename(m)[:-2] for m in mem]
                rc2, o2 = oss(f'python3 {SPEC_TOOL} ports --spec {a.work}/spec.json --json {a.work}/design.json '
                              + (f'--memory-macros {" ".join(macros)} ' if macros else '')
                              + f'--report {a.work}/ports.rpt', os.path.join(a.work, 'ports.log'))
                if not os.path.exists(os.path.join(a.work, 'spec.json')):
                    stage('ports', False, 'no spec.json — run ctx first')
                else:
                    stage('ports', rc2 == 0, 'RTL ports / memories vs spec', first_lines(o2, r'ERROR', 12))
    if 'sim' in only and a.tb:
        if os.path.isdir(a.tb):
            rc, o = oss('make', os.path.join(a.work, 'sim.log'), cwd=a.tb)
            fails = first_lines(o, r'^\s*(FAIL\b|ERROR:)|FAIL=[1-9]|Traceback', 12)
            passed = rc == 0 and re.search(r'TESTS=(\d+) PASS=(\d+) FAIL=0', o) and not fails
        else:
            obj = os.path.join(a.work, 'obj_sim')
            m = re.search(r'^\s*module\s+(\w+)', open(a.tb).read(), re.M)
            tbtop = m.group(1) if m else os.path.basename(a.tb).split('.')[0]
            mq = ' '.join(shlex.quote(m) for m in mem)
            rc, o = oss(f'verilator --binary --timing --assert -Wno-fatal -Wno-lint -Wno-style --top-module {tbtop} '
                        f'-Mdir {obj} {mq} {q} {" ".join(shlex.quote(f) for f in sva)} {shlex.quote(a.tb)} '
                        f'&& {obj}/V{tbtop}', os.path.join(a.work, 'sim.log'), timeout=3600)
            fails = first_lines(o, r'^\s*(\[\S+\]\s*)?(FAIL\b|TEST FAILED|%Error|ERROR:)|Assertion failed|Assertion error', 12)
            passed = rc == 0 and re.search(r'^\s*(\[\S+\]\s*)?(PASS\b|TEST PASSED)', o, re.M) and not fails
        stage('sim', bool(passed), f'testbench {os.path.basename(a.tb)}', fails)
    if 'formal' in only and a.sby:
        ft = os.path.join(a.work, f'{top}_ftop.sv')
        fl = [f for f in files] + sva + ([ft] if os.path.exists(ft) else [])
        fl = macro_stubs(mem, a.work) + fl
        stubs = [f for f in fl if f.endswith('_bb.v')]
        rest = [f for f in fl if f not in stubs]
        txt = open(a.sby).read().replace(
            'read_slang -D FORMAL --top', ''.join(f'read_verilog -formal {os.path.basename(f)}\n' for f in stubs)
            + 'read_slang -D FORMAL --extern-modules --top') \
            .replace('@FILES@', ' '.join(os.path.basename(f) for f in rest)) \
            .replace('@FILELIST@', '\n'.join(fl))
        run_sby = os.path.join(a.work, f'{top}_run.sby')
        with open(run_sby, 'w') as fh:
            fh.write(txt)
        # sby through its real path: the image's bin/sby symlink breaks its module lookup
        rc, o = oss(f'rm -rf {top}_run && "$(readlink -f "$(command -v sby)")" -f {shlex.quote(run_sby)}',
                    os.path.join(a.work, 'formal.log'),
                    cwd=a.work, timeout=3600)
        ok = 'DONE (PASS' in o
        stage('formal', ok, os.path.basename(a.sby) + ('' if ok else f' — counterexample: {a.work}/{top}_run/engine_0/trace.vcd'),
              [] if ok else first_lines(o, r'Assert failed|ERROR|counterexample trace|DONE \(', 12))
    rep_name = 'gate.json' if not a.only else f'gate_{a.only.replace(",", "_")}.json'
    with open(os.path.join(a.work, rep_name), 'w') as fh:
        json.dump({'top': top, 'files': files, 'stages': res}, fh, indent=1)
    bad = [k for k, v in res.items() if v['status'] != 'PASS']
    print(f'\n{len(res) - len(bad)}/{len(res)} stage(s) passed' + (f' — failing: {", ".join(bad)}' if bad else ''))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    for n in ('ctx', 'scaffold', 'gate'):
        p = sub.add_parser(n)
        p.add_argument('--spec', required=True)
        p.add_argument('--work', required=True)
        p.add_argument('--lib-config')
        if n in ('scaffold', 'gate'):
            p.add_argument('--rtl', required=True)
        if n == 'gate':
            p.add_argument('--tb')
            p.add_argument('--sby')
            p.add_argument('--only')
    a = ap.parse_args()
    a.work = os.path.abspath(a.work)
    os.makedirs(a.work, exist_ok=True)
    MOUNTS.update({a.work, os.path.dirname(os.path.abspath(a.spec))})
    if getattr(a, 'rtl', None):
        a.rtl = os.path.abspath(a.rtl)
        os.makedirs(a.rtl, exist_ok=True)
        MOUNTS.add(a.rtl)
    if getattr(a, 'tb', None):
        MOUNTS.add(os.path.dirname(os.path.abspath(a.tb)) if os.path.isfile(a.tb) else os.path.abspath(a.tb))
    if getattr(a, 'lib_config', None):
        MOUNTS.add(os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(a.lib_config)))))
        MOUNTS.update(os.path.dirname(os.path.realpath(m)) for m in macro_models(a.lib_config))
    return {'ctx': cmd_ctx, 'scaffold': cmd_scaffold, 'gate': cmd_gate}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
