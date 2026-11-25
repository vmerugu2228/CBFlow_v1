#!/usr/bin/env python3
"""Spec tools for the CBflow RTL_SPEC flow (open-source, tool rtlcheck).

Runs inside the CBflow tool container (python3, PyYAML, lxml there); the
SystemRDL / PeakRDL / openpyxl packages come from CBFLOW_OSS_PYTHON
(global/utils/oss/install_pytools.sh), added to sys.path here only.

Sources (industry formats):
  block spec   YAML  <block>.spec.yaml   (CBflow spec schema v1)
  registers    SystemRDL <regs>.rdl, or an XLS register sheet (xls2rdl)
  verification XLS vPlan (generated from the spec's features: vplan-init)

  check     --spec <yaml> -o spec.json --report <rpt> [--rdl-out <rdl>]
            schema + consistency (ports / interfaces / clocks / resets /
            power / memories / rtl sources / registers file / features);
            normalized spec (absolute paths) for the later stages
  xls2rdl   --xls <xlsx> --addrmap <name> -o <rdl>     register sheet -> SystemRDL
  rdl2xls   --rdl <rdl> -o <xlsx>                      SystemRDL -> register sheet
  regs      --rdl <rdl> --out <dir> [--cpuif apb4-flat]
            PeakRDL: regblock SV (+ package), UVM RAL, C header, IP-XACT
            memory map (1685-2014), HTML docs
  ipxact    --spec spec.json --memmap <peakrdl ip-xact xml> -o <component.xml>
            --schema <index.xsd>   IP-XACT 1685-2014 component (ports, bus
            interfaces, memory map, file sets) validated against the schema
  sdc       --spec spec.json -o <sdc>        clocks / IO delays / load
  upf       --spec spec.json -o <upf>        power domains (IEEE 1801)
  filelist  --spec spec.json --regs <dir> -o <f>   generated register block + RTL
  ports     --spec spec.json --json <yosys json> --report <rpt> [--memory-macros …]
            RTL top ports (direction / width) against the spec's ports; spec
            memories instantiated with their macro, every memory macro of the
            RTL declared, macros in the library tag
  vplan-init --spec spec.json -o <xlsx>      verification plan from the features
"""
import argparse
import json
import os
import re
import sys

if os.environ.get('CBFLOW_OSS_PYTHON'):
    sys.path.insert(0, os.environ['CBFLOW_OSS_PYTHON'])

SCHEMA_VERSION = 1
MBIST_ALGORITHMS = {'march_c_minus', 'march_c', 'march_b', 'mats_plus'}
PROTOCOLS = {'valid_ready', 'apb4'}
APB4_SIGNALS = ['psel', 'penable', 'pwrite', 'pprot', 'paddr', 'pwdata', 'pstrb', 'pready', 'prdata', 'pslverr']
# IP-XACT logical names of the AMBA APB4 abstraction (ARM AMBA 4 APB4 rtl)
APB4_LOGICAL = {'psel': 'PSELx', 'penable': 'PENABLE', 'pwrite': 'PWRITE', 'pprot': 'PPROT', 'paddr': 'PADDR',
                'pwdata': 'PWDATA', 'pstrb': 'PSTRB', 'pready': 'PREADY', 'prdata': 'PRDATA', 'pslverr': 'PSLVERR'}


def _die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════
# check
# ═══════════════════════════════════════════════════════════════════════════
def _yaml_load(path):
    """YAML with 1.2 booleans: only true / false are booleans — ON / OFF /
    yes / no stay strings (power states, enable names) instead of turning into
    True / False as PyYAML's 1.1 resolver does."""
    import yaml

    class Loader(yaml.SafeLoader):
        pass
    Loader.yaml_implicit_resolvers = {k: [(t, r) for t, r in v if t != 'tag:yaml.org,2002:bool']
                                      for k, v in yaml.SafeLoader.yaml_implicit_resolvers.items()}
    Loader.add_implicit_resolver('tag:yaml.org,2002:bool', re.compile(r'^(?:true|True|TRUE|false|False|FALSE)$'),
                                 list('tTfF'))
    return yaml.load(open(path), Loader=Loader)


def cmd_check(a):
    import yaml
    path = os.path.abspath(a.spec)
    base = os.path.dirname(path)
    try:
        s = _yaml_load(path)
    except yaml.YAMLError as e:
        _die(f'{path}: YAML: {e}')
    errs, warns = [], []

    def need(d, key, ctx, typ=None):
        if not isinstance(d, dict) or key not in d:
            errs.append(f'{ctx}: missing "{key}"')
            return None
        if typ and not isinstance(d[key], typ):
            errs.append(f'{ctx}.{key}: expected {typ.__name__ if isinstance(typ, type) else typ}')
            return None
        return d[key]

    if not isinstance(s, dict):
        _die(f'{path}: not a mapping')
    if s.get('spec_version') != SCHEMA_VERSION:
        errs.append(f'spec_version must be {SCHEMA_VERSION}, got {s.get("spec_version")!r}')
    for k in ('block', 'version', 'vendor', 'library', 'description'):
        need(s, k, 'spec')
    ports = {}
    for i, p in enumerate(need(s, 'ports', 'spec', list) or []):
        ctx = f'ports[{i}]'
        n = need(p, 'name', ctx, str)
        d = need(p, 'dir', ctx, str)
        w = need(p, 'width', ctx, int)
        if d and d not in ('in', 'out', 'inout'):
            errs.append(f'{ctx}.dir: in | out | inout, got {d}')
        if w is not None and w < 1:
            errs.append(f'{ctx}.width: >= 1')
        if n:
            if n in ports:
                errs.append(f'port {n} declared twice')
            ports[n] = p
    clocks = need(s, 'clocks', 'spec', list) or []
    for i, c in enumerate(clocks):
        ctx = f'clocks[{i}]'
        need(c, 'name', ctx, str)
        cp = need(c, 'port', ctx, str)
        per = need(c, 'period_ns', ctx, (int, float))
        if cp and (cp not in ports or ports[cp]['dir'] != 'in'):
            errs.append(f'{ctx}.port {cp}: not an input port')
        if per is not None and per <= 0:
            errs.append(f'{ctx}.period_ns: > 0')
    for i, r in enumerate(s.get('resets', []) or []):
        ctx = f'resets[{i}]'
        rp = need(r, 'port', ctx, str)
        act = need(r, 'active', ctx, str)
        if rp and (rp not in ports or ports[rp]['dir'] != 'in'):
            errs.append(f'{ctx}.port {rp}: not an input port')
        if act and act not in ('high', 'low'):
            errs.append(f'{ctx}.active: high | low')
    regs_file = None
    for i, itf in enumerate(s.get('interfaces', []) or []):
        ctx = f'interfaces[{i}]'
        nm = need(itf, 'name', ctx, str)
        proto = need(itf, 'protocol', ctx, str)
        mode = need(itf, 'mode', ctx, str)
        if mode and mode not in ('master', 'slave'):
            errs.append(f'{ctx}.mode: master | slave')
        if proto and proto not in PROTOCOLS:
            errs.append(f'{ctx}.protocol: one of {sorted(PROTOCOLS)}')
        if proto == 'valid_ready':
            sig = need(itf, 'signals', ctx, dict) or {}
            for k in ('valid', 'ready', 'data'):
                if k not in sig:
                    errs.append(f'{ctx}.signals: missing {k}')
                elif sig[k] not in ports:
                    errs.append(f'{ctx}.signals.{k}: port {sig[k]} not declared')
            if sig.get('valid') in ports and sig.get('ready') in ports:
                vin = ports[sig['valid']]['dir'] == 'in'
                if (mode == 'slave') != vin:
                    errs.append(f'{ctx}: {mode} valid/ready — valid must be an {"input" if mode == "slave" else "output"}')
        if proto == 'apb4':
            pre = need(itf, 'prefix', ctx, str) or ''
            for sname in APB4_SIGNALS:
                if f'{pre}{sname}' not in ports:
                    errs.append(f'{ctx}: APB4 signal {pre}{sname} not a declared port')
            rf = itf.get('registers')
            if rf:
                rp = os.path.normpath(os.path.join(base, rf))
                if not os.path.isfile(rp):
                    errs.append(f'{ctx}.registers: {rp} not found')
                elif not rp.endswith(('.rdl', '.xlsx')):
                    errs.append(f'{ctx}.registers: SystemRDL (.rdl) or register sheet (.xlsx)')
                else:
                    itf['registers'] = rp
                    if regs_file:
                        errs.append('more than one register interface (one register block per spec)')
                    regs_file = rp
    for p in ports.values():
        if p.get('interface') and p['interface'] not in {i.get('name') for i in s.get('interfaces', []) or []}:
            errs.append(f'port {p["name"]}: interface {p["interface"]} not declared')
    pw = s.get('power')
    if pw:
        for i, d in enumerate(need(pw, 'domains', 'power', list) or []):
            ctx = f'power.domains[{i}]'
            need(d, 'name', ctx, str)
            sup = need(d, 'supply', ctx, dict) or {}
            for k in ('power', 'ground'):
                if k not in sup:
                    errs.append(f'{ctx}.supply: missing {k}')
    else:
        warns.append('no power section — no UPF generated')
    mem_insts = set()
    for i, m in enumerate(s.get('memories', []) or []):
        ctx = f'memories[{i}]'
        inst = need(m, 'inst', ctx, str)
        need(m, 'macro', ctx, str)
        dep = need(m, 'depth', ctx, int)
        wid = need(m, 'width', ctx, int)
        if inst in mem_insts:
            errs.append(f'{ctx}: memory instance {inst} declared twice')
        mem_insts.add(inst)
        for k, val in (('depth', dep), ('width', wid)):
            if val is not None and val < 1:
                errs.append(f'{ctx}.{k}: >= 1')
        mps = need(m, 'ports', ctx, list) or []
        if not mps:
            errs.append(f'{ctx}.ports: at least one port')
        for j, mp in enumerate(mps):
            t = need(mp, 'type', f'{ctx}.ports[{j}]', str)
            need(mp, 'name', f'{ctx}.ports[{j}]', str)
            if t and t not in ('rw', 'r', 'w'):
                errs.append(f'{ctx}.ports[{j}].type: rw | r | w')
        mb = m.get('mbist')
        if mb is None:
            warns.append(f'{ctx} ({inst}): no mbist section — the memory is not planned for memory test')
        elif isinstance(mb, dict):
            if mb.get('enable', True) and mb.get('algorithm') not in MBIST_ALGORITHMS:
                errs.append(f'{ctx}.mbist.algorithm: one of {sorted(MBIST_ALGORITHMS)}')
            if mb.get('enable', True) and not mb.get('group'):
                errs.append(f'{ctx}.mbist.group: the MBIST controller group')
        else:
            errs.append(f'{ctx}.mbist: a mapping')
    rtl = need(s, 'rtl', 'spec', dict) or {}
    top = need(rtl, 'top', 'rtl', str)
    srcs = []
    for f in need(rtl, 'sources', 'rtl', list) or []:
        fp = os.path.normpath(os.path.join(base, f))
        if not os.path.isfile(fp):
            errs.append(f'rtl.sources: {fp} not found')
        srcs.append(fp)
    rtl['sources'] = srcs
    if top and top != s.get('block'):
        warns.append(f'rtl.top {top} differs from block {s.get("block")}')
    fids = set()
    for i, f in enumerate(s.get('features', []) or []):
        ctx = f'features[{i}]'
        fid = need(f, 'id', ctx, str)
        need(f, 'name', ctx, str)
        ms = need(f, 'milestone', ctx, str)
        if ms and ms not in ('M1', 'M2', 'M3', 'M4'):
            errs.append(f'{ctx}.milestone: M1..M4')
        if fid in fids:
            errs.append(f'feature id {fid} twice')
        fids.add(fid)
        if not f.get('tests'):
            warns.append(f'{ctx} ({fid}): no tests')
    if not s.get('features'):
        warns.append('no features — the verification plan will be empty')
    s['_spec_file'] = path
    s['_registers'] = regs_file
    lines = [f'Spec check — {s.get("block")} ({path})',
             f'  Ports       : {len(ports)}',
             f'  Clocks      : {len(clocks)}',
             f'  Interfaces  : {len(s.get("interfaces", []) or [])}',
             f'  Registers   : {regs_file or "-"}',
             f'  Memories    : {len(s.get("memories", []) or [])}',
             f'  Features    : {len(s.get("features", []) or [])}',
             f'  Errors      : {len(errs)}',
             f'  Warnings    : {len(warns)}'] + [f'  ERROR: {e}' for e in errs] + [f'  WARN : {w}' for w in warns]
    open(a.report, 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines), file=sys.stderr)
    if errs:
        sys.exit(1)
    # the register source as SystemRDL for the later stages (an XLS register
    # sheet is converted; the addrmap is named <block>_regs)
    if a.rdl_out and regs_file:
        if regs_file.endswith('.xlsx'):
            cmd_xls2rdl(argparse.Namespace(xls=regs_file, addrmap=f'{s["block"]}_regs', output=a.rdl_out))
        else:
            open(a.rdl_out, 'w').write(open(regs_file).read())
        s['_registers_rdl'] = os.path.abspath(a.rdl_out)
    json.dump(s, open(a.output, 'w'), indent=1)


# ═══════════════════════════════════════════════════════════════════════════
# Register sheet <-> SystemRDL
# ═══════════════════════════════════════════════════════════════════════════
SHEET_COLS = ['Register', 'Offset', 'Register Name', 'Register Description', 'Field', 'MSB', 'LSB',
              'SW', 'HW', 'Reset', 'OnWrite', 'Flags', 'Field Description']


def _rdl_compile(rdl):
    from systemrdl import RDLCompiler, RDLCompileError
    c = RDLCompiler()
    # PeakRDL-regblock's user-defined properties (buffer_writes, rd_swacc, …)
    # must be known to the compiler, as the peakrdl CLI registers them
    from peakrdl_regblock.udps import ALL_UDPS
    for udp in ALL_UDPS:
        c.register_udp(udp)
    try:
        c.compile_file(rdl)
        return c.elaborate()
    except RDLCompileError:
        _die(f'SystemRDL compile failed: {rdl}')


def cmd_rdl2xls(a):
    import openpyxl
    from systemrdl.node import RegNode
    root = _rdl_compile(a.rdl)
    top = root.top
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = top.inst_name
    ws.append(SHEET_COLS)
    for reg in top.descendants(unroll=True):
        if not isinstance(reg, RegNode):
            continue
        for fld in reg.fields():
            flags = [k for k in ('singlepulse', 'hwset', 'hwclr') if fld.get_property(k)]
            ow = fld.get_property('onwrite')
            ws.append([reg.inst_name, f'0x{reg.address_offset:X}', reg.get_property('name') or '',
                       reg.get_property('desc') or '', fld.inst_name, fld.msb, fld.lsb,
                       fld.get_property('sw').name, fld.get_property('hw').name,
                       '' if fld.get_property('reset') is None else f'0x{fld.get_property("reset"):X}',
                       ow.name if ow else '', ','.join(flags), fld.get_property('desc') or ''])
    ws2 = wb.create_sheet('addrmap')
    ws2.append(['name', 'desc', 'regwidth'])
    ws2.append([top.get_property('name') or '', top.get_property('desc') or '', 32])
    wb.save(a.output)
    print(f'rdl2xls: {a.rdl} -> {a.output}', file=sys.stderr)


def cmd_xls2rdl(a):
    import openpyxl
    wb = openpyxl.load_workbook(a.xls, data_only=True)
    ws = wb[wb.sheetnames[0]]
    rows = list(ws.iter_rows(values_only=True))
    hdr = [str(h).strip() if h is not None else '' for h in rows[0]]
    miss = [c for c in SHEET_COLS if c not in hdr]
    if miss:
        _die(f'{a.xls}: register sheet columns missing: {miss} (expected {SHEET_COLS})')
    ix = {c: hdr.index(c) for c in SHEET_COLS}
    meta = {'name': '', 'desc': ''}
    if 'addrmap' in wb.sheetnames:
        m = list(wb['addrmap'].iter_rows(values_only=True))
        if len(m) > 1:
            meta = {'name': m[1][0] or '', 'desc': m[1][1] or ''}
    regs, order = {}, []
    for r in rows[1:]:
        if not r or r[ix['Register']] in (None, ''):
            continue
        g = lambda c: r[ix[c]]
        rn = str(g('Register')).strip()
        if rn not in regs:
            regs[rn] = {'offset': str(g('Offset')).strip(), 'name': g('Register Name') or '',
                        'desc': g('Register Description') or '', 'fields': []}
            order.append(rn)
        regs[rn]['fields'].append(r)
    q = lambda t: '"' + str(t).replace('\\', '\\\\').replace('"', '\\"') + '"'
    out = [f'// Generated from {os.path.basename(a.xls)} by spec_tool.py xls2rdl', f'addrmap {a.addrmap} {{']
    if meta['name']:
        out.append(f'    name = {q(meta["name"])};')
    if meta['desc']:
        out.append(f'    desc = {q(meta["desc"])};')
    out.append('    default regwidth = 32;')
    for rn in order:
        rg = regs[rn]
        out.append('')
        out.append('    reg {')
        if rg['name']:
            out.append(f'        name = {q(rg["name"])};')
        if rg['desc']:
            out.append(f'        desc = {q(rg["desc"])};')
        for f in rg['fields']:
            g = lambda c: f[ix[c]]
            props = [f'sw = {str(g("SW")).strip()}', f'hw = {str(g("HW")).strip()}']
            if g('OnWrite'):
                props.append(str(g('OnWrite')).strip())
            for fl in str(g('Flags') or '').split(','):
                if fl.strip():
                    props.append(fl.strip())
            if g('Field Description'):
                props.append(f'desc = {q(g("Field Description"))}')
            rst = '' if g('Reset') in (None, '') else f' = {str(g("Reset")).strip()}'
            out.append(f'        field {{ {"; ".join(props)}; }} {g("Field")}[{g("MSB")}:{g("LSB")}]{rst};')
        out.append(f'    }} {rn} @ {rg["offset"]};')
    out.append('};')
    open(a.output, 'w').write('\n'.join(out) + '\n')
    _rdl_compile(a.output)          # must compile
    print(f'xls2rdl: {a.xls} -> {a.output} ({len(order)} registers)', file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# regs (PeakRDL)
# ═══════════════════════════════════════════════════════════════════════════
def cmd_regs(a):
    from peakrdl_regblock import RegblockExporter
    from peakrdl_regblock.cpuif.apb4 import APB4_Cpuif_flattened
    from peakrdl_uvm import UVMExporter
    from peakrdl_cheader.exporter import CHeaderExporter
    from peakrdl_ipxact import IPXACTExporter, Standard
    from peakrdl_html import HTMLExporter
    root = _rdl_compile(a.rdl)
    top = root.top
    name = top.inst_name
    os.makedirs(a.out, exist_ok=True)
    cpuif = {'apb4-flat': APB4_Cpuif_flattened}.get(a.cpuif)
    if cpuif is None:
        _die(f'cpuif {a.cpuif}: supported apb4-flat')
    for d in ('rtl', 'uvm', 'c', 'ipxact', 'html'):
        os.makedirs(os.path.join(a.out, d), exist_ok=True)
    RegblockExporter().export(top, os.path.join(a.out, 'rtl'), cpuif_cls=cpuif)
    UVMExporter().export(top, os.path.join(a.out, 'uvm', f'{name}_ral_pkg.sv'))
    CHeaderExporter().export(top, os.path.join(a.out, 'c', f'{name}.h'))
    IPXACTExporter(standard=Standard.IEEE_1685_2014, vendor='cbflow', library='regs', version='1.0').export(
        top, os.path.join(a.out, 'ipxact', f'{name}.memmap.xml'))
    HTMLExporter().export(top, os.path.join(a.out, 'html'))
    regs = [n for n in top.descendants() if n.__class__.__name__ == 'RegNode']
    json.dump({'addrmap': name, 'registers': len(regs), 'size': top.size,
               'files': {'rtl': sorted(os.listdir(os.path.join(a.out, 'rtl'))),
                         'uvm': f'uvm/{name}_ral_pkg.sv', 'c': f'c/{name}.h',
                         'ipxact': f'ipxact/{name}.memmap.xml', 'html': 'html/index.html'}},
              open(os.path.join(a.out, 'regs.json'), 'w'), indent=1)
    print(f'regs: {name}: {len(regs)} registers, {top.size} bytes -> {a.out}', file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# IP-XACT component (IEEE 1685-2014)
# ═══════════════════════════════════════════════════════════════════════════
IPX = 'http://www.accellera.org/XMLSchema/IPXACT/1685-2014'


def cmd_ipxact(a):
    from lxml import etree
    s = json.load(open(a.spec))
    E = lambda tag, text=None, **at: _el(etree, tag, text, **at)
    comp = etree.Element(f'{{{IPX}}}component', nsmap={'ipxact': IPX})
    for k in ('vendor', 'library'):
        comp.append(E(k, s[k]))
    comp.append(E('name', s['block']))
    comp.append(E('version', str(s['version'])))
    ports = {p['name']: p for p in s['ports']}
    mm_name = None
    mm = None
    if a.memmap:
        src = etree.parse(a.memmap).getroot()
        mms = src.find(f'{{{IPX}}}memoryMaps')
        if mms is None or not len(mms):
            _die(f'{a.memmap}: no memoryMaps')
        mm = mms
        mm_name = mms[0].find(f'{{{IPX}}}name').text
    bis = E('busInterfaces')
    for itf in s.get('interfaces', []) or []:
        bi = E('busInterface')
        bi.append(E('name', itf['name']))
        if itf['protocol'] == 'apb4':
            bi.append(E('busType', vendor='amba.com', library='AMBA4', name='APB4', version='r0p0_0'))
            ats = E('abstractionTypes')
            at = E('abstractionType')
            at.append(E('abstractionRef', vendor='amba.com', library='AMBA4', name='APB4_rtl', version='r0p0_0'))
            pms = E('portMaps')
            for sname in APB4_SIGNALS:
                pm = E('portMap')
                lp = E('logicalPort')
                lp.append(E('name', APB4_LOGICAL[sname]))
                pm.append(lp)
                pp = E('physicalPort')
                pp.append(E('name', f'{itf["prefix"]}{sname}'))
                pm.append(pp)
                pms.append(pm)
            at.append(pms)
            ats.append(at)
            bi.append(ats)
        else:
            # valid/ready: no standard bus definition — a CBflow one
            bi.append(E('busType', vendor='cbflow', library='interface', name='valid_ready', version='1.0'))
            ats = E('abstractionTypes')
            at = E('abstractionType')
            at.append(E('abstractionRef', vendor='cbflow', library='interface', name='valid_ready_rtl', version='1.0'))
            pms = E('portMaps')
            for lname, pname in itf['signals'].items():
                pm = E('portMap')
                lp = E('logicalPort')
                lp.append(E('name', lname.upper()))
                pm.append(lp)
                pp = E('physicalPort')
                pp.append(E('name', pname))
                pm.append(pp)
                pms.append(pm)
            at.append(pms)
            ats.append(at)
            bi.append(ats)
        if itf['mode'] == 'slave':
            sl = E('slave')
            if itf['protocol'] == 'apb4' and mm_name:
                sl.append(E('memoryMapRef', memoryMapRef=mm_name))
            bi.append(sl)
        else:
            bi.append(E('master'))
        bis.append(bi)
    comp.append(bis)
    if mm is not None:
        comp.append(mm)
    model = E('model')
    views = E('views')
    v = E('view')
    v.append(E('name', 'rtl'))
    v.append(E('componentInstantiationRef', 'rtl_implementation'))
    views.append(v)
    model.append(views)
    insts = E('instantiations')
    ci = E('componentInstantiation')
    ci.append(E('name', 'rtl_implementation'))
    ci.append(E('language', 'SystemVerilog'))
    ci.append(E('moduleName', s['rtl']['top']))
    fsr = E('fileSetRef')
    fsr.append(E('localName', 'rtl_sources'))
    ci.append(fsr)
    insts.append(ci)
    model.append(insts)
    pts = E('ports')
    for p in s['ports']:
        pe = E('port')
        pe.append(E('name', p['name']))
        if p.get('desc'):
            pe.append(E('description', p['desc']))
        w = E('wire')
        w.append(E('direction', {'in': 'in', 'out': 'out', 'inout': 'inout'}[p['dir']]))
        if p['width'] > 1:
            vs = E('vectors')
            vec = E('vector')
            vec.append(E('left', str(p['width'] - 1)))
            vec.append(E('right', '0'))
            vs.append(vec)
            w.append(vs)
        pe.append(w)
        pts.append(pe)
    model.append(pts)
    comp.append(model)
    fss = E('fileSets')
    fs = E('fileSet')
    fs.append(E('name', 'rtl_sources'))
    for f in a.files or []:
        fe = E('file')
        fe.append(E('name', f))
        fe.append(E('fileType', 'systemVerilogSource' if f.endswith('.sv') else 'verilogSource'))
        fs.append(fe)
    fss.append(fs)
    comp.append(fss)
    if s.get('description'):
        comp.append(E('description', ' '.join(s['description'].split())))
    tree = etree.ElementTree(comp)
    tree.write(a.output, pretty_print=True, xml_declaration=True, encoding='UTF-8')
    # schema validation
    schema = etree.XMLSchema(etree.parse(a.schema))
    doc = etree.parse(a.output)
    ok = schema.validate(doc)
    rep = [f'IP-XACT component — {s["block"]} (IEEE 1685-2014)', f'  File        : {a.output}',
           f'  Ports       : {len(s["ports"])}', f'  Bus interfaces : {len(s.get("interfaces", []) or [])}',
           f'  Memory map  : {mm_name or "-"}', f'  Schema      : {"VALID" if ok else "INVALID"}']
    for e in schema.error_log:
        rep.append(f'  ERROR: line {e.line}: {e.message}')
    open(a.report, 'w').write('\n'.join(rep) + '\n')
    print('\n'.join(rep[:7]), file=sys.stderr)
    if not ok:
        sys.exit(1)


def _el(etree, tag, text=None, **at):
    e = etree.Element(f'{{{IPX}}}{tag}')
    if text is not None:
        e.text = text
    for k, v in at.items():
        e.set(k, v)          # 1685-2014 attributes are unqualified (VLNV, memoryMapRef)
    return e


# ═══════════════════════════════════════════════════════════════════════════
# SDC / UPF / filelist
# ═══════════════════════════════════════════════════════════════════════════
def cmd_sdc(a):
    s = json.load(open(a.spec))
    t = s.get('io_timing', {})
    lines = [f'# {s["block"]} functional constraints — generated by the RTL_SPEC flow from',
             f'# {os.path.basename(s["_spec_file"])} (edit the spec, not this file)']
    clk_ports = []
    for c in s['clocks']:
        lines.append(f'create_clock -name {c["name"]} -period {c["period_ns"]} [get_ports {c["port"]}]')
        if c.get('uncertainty_ns') is not None:
            lines.append(f'set_clock_uncertainty {c["uncertainty_ns"]} [get_clocks {c["name"]}]')
        clk_ports.append(c['port'])
    if len(s['clocks']) == 1:
        c = s['clocks'][0]
        if 'input_delay_pct' in t:
            d = round(c['period_ns'] * t['input_delay_pct'] / 100.0, 3)
            lines.append(f'set_input_delay  {d} -clock {c["name"]} [delete_from_list [all_inputs] [get_ports {{{" ".join(clk_ports)}}}]]')
        if 'output_delay_pct' in t:
            d = round(c['period_ns'] * t['output_delay_pct'] / 100.0, 3)
            lines.append(f'set_output_delay {d} -clock {c["name"]} [all_outputs]')
    elif 'input_delay_pct' in t or 'output_delay_pct' in t:
        lines.append('# io_timing: more than one clock — IO delays per interface are not generated')
    if 'output_load_pf' in t:
        lines.append(f'set_load {t["output_load_pf"]} [all_outputs]')
    for r in s.get('resets', []) or []:
        if not r.get('synchronous', True):
            lines.append(f'set_false_path -from [get_ports {r["port"]}]')
    open(a.output, 'w').write('\n'.join(lines) + '\n')


def cmd_upf(a):
    s = json.load(open(a.spec))
    pw = s['power']
    out = [f'# {s["block"]} power intent (IEEE 1801-{pw.get("upf_version", "2.1")}) — generated by the RTL_SPEC flow',
           f'# from {os.path.basename(s["_spec_file"])} (edit the spec, not this file)',
           f'upf_version {pw.get("upf_version", "2.1")}', 'set_scope .', '']
    sups = []
    for d in pw['domains']:
        el = d.get('elements', ['.'])
        out.append(f'create_power_domain {d["name"]} ' + ('-include_scope' if el == ['.'] else f'-elements {{{" ".join(el)}}}'))
    out.append('')
    for d in pw['domains']:
        for k in ('power', 'ground'):
            if d['supply'][k] not in sups:
                sups.append(d['supply'][k])
    out += [f'create_supply_port {n} -direction in' for n in sups]
    out += [f'create_supply_net  {n}' for n in sups]
    out += [f'connect_supply_net {n} -ports {n}' for n in sups]
    for d in pw['domains']:
        out.append(f'set_domain_supply_net {d["name"]} -primary_power_net {d["supply"]["power"]} -primary_ground_net {d["supply"]["ground"]}')
    out.append('')
    for d in pw['domains']:
        st = d.get('states', {'ON': 1.8})
        p, g = d['supply']['power'], d['supply']['ground']
        fmt = lambda v: f'{v:.2f}' if isinstance(v, (int, float)) else str(v)
        out.append(f'add_port_state {p} ' + ' '.join(f'-state {{{k} {fmt(v)}}}' for k, v in st.items()))
        out.append(f'add_port_state {g} -state {{GND 0.00}}')
        out.append(f'create_pst pst_{s["block"]} -supplies {{{p} {g}}}')
        for k, v in st.items():
            out.append(f'add_pst_state {"RUN" if k == "ON" else k} -pst pst_{s["block"]} -state {{{k:<3} GND}}')
    open(a.output, 'w').write('\n'.join(out) + '\n')


def cmd_filelist(a):
    s = json.load(open(a.spec))
    files = []
    if a.regs:
        rtl = os.path.join(a.regs, 'rtl')
        pk = sorted(f for f in os.listdir(rtl) if f.endswith('_pkg.sv'))
        other = sorted(f for f in os.listdir(rtl) if f.endswith('.sv') and f not in pk)
        files += [os.path.abspath(os.path.join(rtl, f)) for f in pk + other]
    files += s['rtl']['sources']
    open(a.output, 'w').write('\n'.join(files) + '\n')
    print(f'filelist: {len(files)} files -> {a.output}', file=sys.stderr)


def cmd_ports(a):
    s = json.load(open(a.spec))
    d = json.load(open(a.json))
    top = s['rtl']['top']
    if top not in d['modules']:
        _die(f'module {top} not in {a.json}')
    rtl = {n: (p['direction'], len(p['bits'])) for n, p in d['modules'][top]['ports'].items()}
    spec = {p['name']: ({'in': 'input', 'out': 'output', 'inout': 'inout'}[p['dir']], p['width']) for p in s['ports']}
    errs = []
    for n, (dr, w) in spec.items():
        if n not in rtl:
            errs.append(f'spec port {n} missing in RTL {top}')
        elif rtl[n] != (dr, w):
            errs.append(f'port {n}: spec {dr}[{w}] vs RTL {rtl[n][0]}[{rtl[n][1]}]')
    for n in rtl:
        if n not in spec:
            errs.append(f'RTL port {n} not in the spec')
    # memories: every spec memory instantiated with its macro, every memory
    # macro instance of the RTL declared in the spec, macros in the library tag
    macros = set(a.memory_macros or [])
    cells = {}

    def walk(mod, prefix):
        for cn, c in d['modules'][mod].get('cells', {}).items():
            cells[prefix + cn] = c['type']
            sub = d['modules'].get(c['type'])
            if sub and not sub.get('attributes', {}).get('blackbox'):
                walk(c['type'], prefix + cn + '/')
    walk(top, '')
    mem_errs = []
    spec_mems = {m['inst'].replace('.', '/'): m for m in s.get('memories', []) or []}
    for inst, m in spec_mems.items():
        if inst not in cells:
            mem_errs.append(f'memory {inst}: not instantiated in {top}')
        elif cells[inst] != m['macro']:
            mem_errs.append(f'memory {inst}: RTL instantiates {cells[inst]}, spec says {m["macro"]}')
        if macros and m['macro'] not in macros:
            mem_errs.append(f'memory {inst}: macro {m["macro"]} not in the library tag ({", ".join(sorted(macros))})')
    for inst, ct in cells.items():
        if ct in macros and inst not in spec_mems:
            mem_errs.append(f'memory macro instance {inst} ({ct}) not declared in the spec')
    errs += mem_errs
    lines = [f'RTL vs spec ports — {top}', f'  Spec ports : {len(spec)}', f'  RTL ports  : {len(rtl)}',
             f'  Spec memories : {len(spec_mems)}',
             f'  Mismatches : {len(errs)}'] + [f'  ERROR: {e}' for e in errs]
    open(a.report, 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines), file=sys.stderr)
    if errs:
        sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════
# Verification plan (XLS)
# ═══════════════════════════════════════════════════════════════════════════
VPLAN_COLS = ['Feature ID', 'Feature', 'Description', 'Priority', 'Milestone', 'Tests', 'Coverage Items',
              'Owner', 'Status', 'Waiver']


def cmd_vplan_init(a):
    import openpyxl
    from openpyxl.styles import Font
    s = json.load(open(a.spec))
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'vplan'
    ws.append(VPLAN_COLS)
    for c in ws[1]:
        c.font = Font(bold=True)
    for f in s.get('features', []) or []:
        ws.append([f['id'], f['name'], f.get('desc', ''), f.get('priority', ''), f['milestone'],
                   ', '.join(f.get('tests', [])), ', '.join(f.get('coverage', [])), f.get('owner', ''), 'planned', ''])
    meta = wb.create_sheet('meta')
    meta.append(['block', 'spec', 'spec_version'])
    meta.append([s['block'], os.path.basename(s['_spec_file']), s['spec_version']])
    wb.save(a.output)
    print(f'vplan-init: {len(s.get("features", []) or [])} features -> {a.output}', file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('check'); p.add_argument('--spec', required=True); p.add_argument('-o', '--output', required=True)
    p.add_argument('--report', required=True); p.add_argument('--rdl-out')
    p = sp.add_parser('xls2rdl'); p.add_argument('--xls', required=True); p.add_argument('--addrmap', required=True)
    p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('rdl2xls'); p.add_argument('--rdl', required=True); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('regs'); p.add_argument('--rdl', required=True); p.add_argument('--out', required=True)
    p.add_argument('--cpuif', default='apb4-flat')
    p = sp.add_parser('ipxact'); p.add_argument('--spec', required=True); p.add_argument('--memmap')
    p.add_argument('--files', nargs='*'); p.add_argument('-o', '--output', required=True)
    p.add_argument('--schema', required=True); p.add_argument('--report', required=True)
    for n in ('sdc', 'upf'):
        p = sp.add_parser(n); p.add_argument('--spec', required=True); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('filelist'); p.add_argument('--spec', required=True); p.add_argument('--regs')
    p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('ports'); p.add_argument('--spec', required=True); p.add_argument('--json', required=True)
    p.add_argument('--memory-macros', nargs='*')
    p.add_argument('--report', required=True)
    p = sp.add_parser('vplan-init'); p.add_argument('--spec', required=True); p.add_argument('-o', '--output', required=True)
    a = ap.parse_args()
    {'check': cmd_check, 'xls2rdl': cmd_xls2rdl, 'rdl2xls': cmd_rdl2xls, 'regs': cmd_regs, 'ipxact': cmd_ipxact,
     'sdc': cmd_sdc, 'upf': cmd_upf, 'filelist': cmd_filelist, 'ports': cmd_ports,
     'vplan-init': cmd_vplan_init}[a.cmd](a)


if __name__ == '__main__':
    main()
