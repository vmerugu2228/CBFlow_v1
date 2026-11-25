#!/usr/bin/env python3
# =============================================================================
# uvmgen.py — SystemVerilog UVM testbench from the CBflow block spec
#
#   uvmgen.py gen --spec <b>.spec.yaml --ral <b>_ral.sv --rtl-f <b>.f
#                 [--vplan <b>_vplan.xlsx] [--user-dir <tb dir>] [--models f...]
#                 -o <out dir> --report <rpt>
#
# From the spec's interfaces (valid_ready, apb4) and the PeakRDL UVM register
# model it writes a complete, compilable UVM environment:
#   <b>_if.sv          one SV interface per spec interface (+ <b>_misc_if for
#                      the ports outside every interface)
#   <b>_agents.sv      per interface: item, driver, monitor, sequencer, agent;
#                      valid_ready the TB drives (DUT slave) / responds to
#                      (DUT master: random back-pressure, protocol checks);
#                      APB4 master + RAL adapter
#   <b>_scoreboard.sv  every input transaction -> the reference model, every
#                      output transaction compared with its expectation
#   <b>_env.sv         agents, register model (+ predictor), scoreboard,
#                      coverage
#   <b>_seqs.sv        random sequence per driven interface
#   <b>_base_test.sv   base test (reset, watchdog, objection) + sanity test
#   <b>_test_stubs.sv  one failing stub per vPlan test nobody wrote yet
#   <b>_tb_pkg.sv      package including the above, <b>_tb_top.sv, tb.f (the
#                      compile list), rtl.f (the DUT sources: code coverage scope)
# User-owned (generated as stubs, meant to be copied into the TB directory and
# written): <b>_ref_model.sv, <b>_coverage.sv, <b>_tests.sv.
#
# Ownership: any file of the same name in --user-dir replaces the generated
# one (and extra files there are carried along — `include them from a user
# file). Regenerating never touches the user directory. The report lists
# generated / user-owned files and what is still a stub.
#
# Timing convention of the generated agents: the TB drives 1 time unit after
# the rising edge and samples at the rising edge (the values before the edge's
# updates — what the DUT's flops capture, and when an APB master / a valid-ready
# sink samples). Sampling mid-cycle would read memory models inside their
# output-transition window.
# =============================================================================

import argparse
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..',
                                'RTL', 'utils', 'oss'))
from spec_tool import _yaml_load            # noqa: E402  (YAML 1.2 booleans)

APB_SIGS = ['psel', 'penable', 'pwrite', 'pprot', 'paddr', 'pwdata', 'pstrb',
            'pready', 'prdata', 'pslverr']
APB_TB_DRIVEN = {'psel', 'penable', 'pwrite', 'pprot', 'paddr', 'pwdata', 'pstrb'}
USER_OWNED = ['ref_model', 'coverage', 'tests']


class GenError(Exception):
    pass


def _rng(w):
    return '' if w == 1 else f'[{w - 1}:0] '


# ── spec model ───────────────────────────────────────────────────────────────
class Spec:
    def __init__(self, path):
        s = _yaml_load(path)
        self.b = s['block']
        self.ports = {p['name']: p for p in s.get('ports') or []}
        clocks = s.get('clocks') or []
        if len(clocks) != 1:
            raise GenError(f'uvmgen supports one clock; the spec declares {len(clocks)}')
        self.clock = clocks[0]
        resets = s.get('resets') or []
        if len(resets) != 1:
            raise GenError(f'uvmgen supports one reset; the spec declares {len(resets)}')
        self.reset = resets[0]
        self.vr, self.apb = [], []
        used = {self.clock['port'], self.reset['port']}
        for i in s.get('interfaces') or []:
            proto = i.get('protocol')
            if proto == 'valid_ready':
                sig = i['signals']
                w = self.ports[sig['data']]['width']
                self.vr.append({'name': i['name'], 'mode': i['mode'], 'valid': sig['valid'],
                                'ready': sig['ready'], 'data': sig['data'], 'w': w})
                used |= {sig['valid'], sig['ready'], sig['data']}
            elif proto == 'apb4':
                if i['mode'] != 'slave':
                    raise GenError(f'interface {i["name"]}: uvmgen drives APB4 slaves only')
                pre = i['prefix']
                ports = {g: pre + g for g in APB_SIGS}
                for g, p in ports.items():
                    if p not in self.ports:
                        raise GenError(f'interface {i["name"]}: port {p} not in the spec')
                self.apb.append({'name': i['name'], 'ports': ports,
                                 'aw': self.ports[ports['paddr']]['width'],
                                 'dw': self.ports[ports['pwdata']]['width'],
                                 'regs': bool(i.get('registers'))})
                used |= set(ports.values())
            else:
                raise GenError(f'interface {i["name"]}: protocol {proto!r} not supported by uvmgen '
                               '(valid_ready, apb4)')
        self.misc = [p for n, p in self.ports.items() if n not in used]
        self.reg_if = next((a for a in self.apb if a['regs']), None)

    @property
    def vr_in(self):          # the TB drives (DUT slave)
        return [v for v in self.vr if v['mode'] == 'slave']

    @property
    def vr_out(self):         # the DUT drives (DUT master)
        return [v for v in self.vr if v['mode'] == 'master']


def ral_info(path):
    t = open(path).read()
    pk = re.search(r'^\s*package\s+(\w+)\s*;', t, re.M)
    blocks = re.findall(r'class\s+(\w+)\s+extends\s+uvm_reg_block', t)
    if not pk or not blocks:
        raise GenError(f'{path}: no package / uvm_reg_block class (PeakRDL UVM register model expected)')
    return pk.group(1), blocks[-1]


def vplan_tests(path):
    """[(feature id, milestone, [tests])] from the vPlan (sheet 'vplan')."""
    if not path:
        return []
    sys.path.insert(0, os.environ.get('CBFLOW_OSS_PYTHON', ''))
    import openpyxl
    ws = openpyxl.load_workbook(path, read_only=True)['vplan']
    rows = list(ws.iter_rows(values_only=True))
    hdr = [str(h or '').strip().lower() for h in rows[0]]
    fi, mi, ti = hdr.index('feature id'), hdr.index('milestone'), hdr.index('tests')
    out = []
    for r in rows[1:]:
        if not r[fi]:
            continue
        tests = [x.strip() for x in str(r[ti] or '').split(',') if x.strip()]
        out.append((str(r[fi]), str(r[mi] or ''), tests))
    return out


# ── SV writers ───────────────────────────────────────────────────────────────
def gen_if(sp):
    b = sp.b
    o = [f'// {b} — testbench interfaces (generated by CBflow uvmgen from {b}.spec.yaml)', '']
    for v in sp.vr:
        o += [f'interface {b}_{v["name"]}_if (input logic clk, input logic rst);',
              f'    logic        valid;', f'    logic        ready;',
              f'    logic {_rng(v["w"])}data;', 'endinterface', '']
    for a in sp.apb:
        o += [f'interface {b}_{a["name"]}_if (input logic clk, input logic rst);']
        for g in APB_SIGS:
            o.append(f'    logic {_rng(sp.ports[a["ports"][g]]["width"])}{g};')
        o += ['endinterface', '']
    o += [f'// ports outside every spec interface', f'interface {b}_misc_if (input logic clk, input logic rst);']
    for p in sp.misc:
        o.append(f'    logic {_rng(p["width"])}{p["name"]};')
    o += ['endinterface', '']
    return '\n'.join(o)


def gen_agents(sp):
    b = sp.b
    o = [f'// {b} — agents (generated by CBflow uvmgen)', '']
    o += [f'class {b}_env_cfg extends uvm_object;',
          f'    `uvm_object_utils({b}_env_cfg)',
          '    int unsigned timeout_cycles = 2000000;   // watchdog (clock cycles)']
    for v in sp.vr_out:
        o.append(f'    int unsigned {v["name"]}_ready_pct = 100;   // % of cycles {v["name"]} ready is high')
    o += [f'    function new(string name = "{b}_env_cfg"); super.new(name); endfunction', 'endclass', '']
    for v in sp.vr:
        n, w = f'{b}_{v["name"]}', v['w']
        drive = v['mode'] == 'slave'
        o += [f'// ── {v["name"]}: valid/ready, DUT {v["mode"]} '
              f'({"the TB drives requests" if drive else "the TB drives ready / monitors"}) ──',
              f'class {n}_item extends uvm_sequence_item;',
              f'    `uvm_object_utils({n}_item)',
              f'    rand bit {_rng(w)}data;']
        if drive:
            o += ['    rand int unsigned delay;                 // idle cycles before valid',
                  '    constraint c_delay { delay dist {0 :/ 70, [1:3] :/ 25, [4:8] :/ 5}; }']
        o += [f'    function new(string name = "{n}_item"); super.new(name); endfunction',
              f'    virtual function string convert2string(); return $sformatf("data=0x%0h", data); endfunction',
              'endclass', '',
              f'typedef uvm_sequencer #({n}_item) {n}_sequencer;', '']
        o += [f'class {n}_driver extends uvm_driver #({n}_item);', f'    `uvm_component_utils({n}_driver)',
              f'    virtual {n}_if vif;', f'    {b}_env_cfg cfg;',
              '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
              '    task run_phase(uvm_phase phase);']
        if drive:
            o += ['        vif.valid = 0;', "        vif.data = '0;",
                  '        @(posedge vif.clk); while (vif.rst) @(posedge vif.clk);',
                  '        #1;',
                  '        forever begin',
                  '            seq_item_port.get_next_item(req);',
                  '            repeat (req.delay) begin vif.valid = 0; @(posedge vif.clk); #1; end',
                  '            vif.valid = 1; vif.data = req.data;',
                  '            do @(posedge vif.clk); while (!vif.ready);   // transfer at this edge',
                  '            #1; vif.valid = 0;',
                  '            seq_item_port.item_done();',
                  '        end']
        else:
            o += ['        vif.ready = 0;',
                  '        forever begin',
                  '            @(posedge vif.clk); #1;',
                  f'            vif.ready = !vif.rst && ($urandom_range(99) < cfg.{v["name"]}_ready_pct);',
                  '        end']
        o += ['    endtask', 'endclass', '']
        o += [f'class {n}_monitor extends uvm_monitor;', f'    `uvm_component_utils({n}_monitor)',
              f'    virtual {n}_if vif;', f'    uvm_analysis_port #({n}_item) ap;',
              '    function new(string name, uvm_component parent); super.new(name, parent); ap = new("ap", this); endfunction',
              '    task run_phase(uvm_phase phase);']
        if not drive:
            o += [f'        bit pend = 0; bit {_rng(w)}pdata;']
        o += ['        forever begin', '            @(posedge vif.clk);',
              '            if (vif.rst) continue;']
        if not drive:
            o += ['            // protocol: valid held with stable data until ready',
                  '            if (pend && !vif.valid) `uvm_error("VR-PROTOCOL", "valid dropped before ready")',
                  '            if (pend && vif.valid && vif.data !== pdata)',
                  '                `uvm_error("VR-PROTOCOL", $sformatf("data changed while waiting for ready: 0x%0h -> 0x%0h", pdata, vif.data))',
                  '            pend = vif.valid && !vif.ready; pdata = vif.data;']
        o += ['            if (vif.valid && vif.ready) begin',
              f'                {n}_item t = {n}_item::type_id::create("t");',
              '                t.data = vif.data;', '                ap.write(t);', '            end',
              '        end', '    endtask', 'endclass', '']
        o += [f'class {n}_agent extends uvm_agent;', f'    `uvm_component_utils({n}_agent)',
              f'    {n}_sequencer sqr; {n}_driver drv; {n}_monitor mon;',
              f'    virtual {n}_if vif; {b}_env_cfg cfg;',
              '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
              '    function void build_phase(uvm_phase phase);',
              f'        if (!uvm_config_db #(virtual {n}_if)::get(this, "", "vif", vif))',
              f'            `uvm_fatal("NOVIF", "{v["name"]} virtual interface not set")',
              f'        mon = {n}_monitor::type_id::create("mon", this);',
              f'        drv = {n}_driver::type_id::create("drv", this);']
        if drive:
            o.append(f'        sqr = {n}_sequencer::type_id::create("sqr", this);')
        o += ['    endfunction', '    function void connect_phase(uvm_phase phase);',
              '        mon.vif = vif; drv.vif = vif; drv.cfg = cfg;']
        if drive:
            o.append('        drv.seq_item_port.connect(sqr.seq_item_export);')
        o += ['    endfunction', 'endclass', '']
    for a in sp.apb:
        n, aw, dw = f'{b}_{a["name"]}', a['aw'], a['dw']
        sw = sp.ports[a['ports']['pstrb']]['width']
        o += [f'// ── {a["name"]}: APB4 master (DUT slave) ──',
              f'class {n}_item extends uvm_sequence_item;', f'    `uvm_object_utils({n}_item)',
              '    rand bit write;', f'    rand bit {_rng(aw)}addr;', f'    rand bit {_rng(dw)}data;',
              f"    bit {_rng(sw)}strb = '1;", '    bit slverr;',
              f'    function new(string name = "{n}_item"); super.new(name); endfunction',
              '    virtual function string convert2string();',
              '        return $sformatf("%s addr=0x%0h data=0x%0h%s", write ? "WR" : "RD", addr, data, slverr ? " SLVERR" : "");',
              '    endfunction', 'endclass', '',
              f'typedef uvm_sequencer #({n}_item) {n}_sequencer;', '',
              f'class {n}_driver extends uvm_driver #({n}_item);', f'    `uvm_component_utils({n}_driver)',
              f'    virtual {n}_if vif;',
              '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
              '    task run_phase(uvm_phase phase);',
              "        vif.psel = 0; vif.penable = 0; vif.pwrite = 0; vif.pprot = '0; vif.paddr = '0; vif.pwdata = '0; vif.pstrb = '0;",
              '        @(posedge vif.clk); while (vif.rst) @(posedge vif.clk);',
              '        forever begin',
              '            seq_item_port.get_next_item(req);',
              '            @(posedge vif.clk); #1;',
              '            vif.psel = 1; vif.penable = 0; vif.pwrite = req.write; vif.paddr = req.addr;',
              "            vif.pwdata = req.write ? req.data : '0; vif.pstrb = req.write ? req.strb : '0;",
              '            @(posedge vif.clk); #1; vif.penable = 1;',
              '            do @(posedge vif.clk); while (!vif.pready);   // access completes at this edge',
              '            if (!req.write) req.data = vif.prdata;',
              '            req.slverr = vif.pslverr;',
              '            #1; vif.psel = 0; vif.penable = 0;',
              '            seq_item_port.item_done();',
              '        end', '    endtask', 'endclass', '',
              f'class {n}_monitor extends uvm_monitor;', f'    `uvm_component_utils({n}_monitor)',
              f'    virtual {n}_if vif;', f'    uvm_analysis_port #({n}_item) ap;',
              '    function new(string name, uvm_component parent); super.new(name, parent); ap = new("ap", this); endfunction',
              '    task run_phase(uvm_phase phase);',
              '        forever begin',
              '            @(posedge vif.clk);',
              '            if (!vif.rst && vif.psel && vif.penable && vif.pready) begin',
              f'                {n}_item t = {n}_item::type_id::create("t");',
              '                t.write = vif.pwrite; t.addr = vif.paddr; t.strb = vif.pstrb;',
              '                t.data = vif.pwrite ? vif.pwdata : vif.prdata; t.slverr = vif.pslverr;',
              '                ap.write(t);', '            end', '        end', '    endtask', 'endclass', '',
              f'class {n}_reg_adapter extends uvm_reg_adapter;', f'    `uvm_object_utils({n}_reg_adapter)',
              f'    function new(string name = "{n}_reg_adapter"); super.new(name); endfunction',
              '    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);',
              f'        {n}_item t = {n}_item::type_id::create("t");',
              '        t.write = (rw.kind == UVM_WRITE); t.addr = rw.addr; t.data = rw.data;',
              '        return t;', '    endfunction',
              '    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);',
              f'        {n}_item t;',
              '        if (!$cast(t, bus_item)) `uvm_fatal("ADAPTER", "wrong bus item type")',
              '        rw.kind = t.write ? UVM_WRITE : UVM_READ; rw.addr = t.addr; rw.data = t.data;',
              '        rw.status = t.slverr ? UVM_NOT_OK : UVM_IS_OK;', '    endfunction', 'endclass', '',
              f'class {n}_agent extends uvm_agent;', f'    `uvm_component_utils({n}_agent)',
              f'    {n}_sequencer sqr; {n}_driver drv; {n}_monitor mon; virtual {n}_if vif;',
              '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
              '    function void build_phase(uvm_phase phase);',
              f'        if (!uvm_config_db #(virtual {n}_if)::get(this, "", "vif", vif))',
              f'            `uvm_fatal("NOVIF", "{a["name"]} virtual interface not set")',
              f'        sqr = {n}_sequencer::type_id::create("sqr", this);',
              f'        drv = {n}_driver::type_id::create("drv", this);',
              f'        mon = {n}_monitor::type_id::create("mon", this);',
              '    endfunction', '    function void connect_phase(uvm_phase phase);',
              '        mon.vif = vif; drv.vif = vif; drv.seq_item_port.connect(sqr.seq_item_export);',
              '    endfunction', 'endclass', '']
    return '\n'.join(o)


def gen_ref_model(sp):
    b = sp.b
    o = [f'// {b}_ref_model — reference model (USER-OWNED: copy into the TB directory and',
         f'// write it; uvmgen regenerates this stub only when no user copy exists).',
         f'// Called with every transaction the DUT accepts on an input interface; push',
         f'// the expected transactions of the output interfaces onto exp_<if>.',
         f'class {b}_ref_model extends uvm_object;', f'    `uvm_object_utils({b}_ref_model)']
    for v in sp.vr_out:
        o.append(f'    {b}_{v["name"]}_item exp_{v["name"]}[$];')
    o += ['    bit stub = 1;                        // a written model clears this',
          f'    function new(string name = "{b}_ref_model"); super.new(name); endfunction']
    for i in [v['name'] for v in sp.vr_in] + [a['name'] for a in sp.apb]:
        o += [f'    virtual function void observe_{i}({b}_{i}_item t);', '    endfunction']
    o += ['endclass', '']
    return '\n'.join(o)


def gen_scoreboard(sp):
    b = sp.b
    ins = [v['name'] for v in sp.vr_in] + [a['name'] for a in sp.apb]
    o = [f'// {b} — scoreboard (generated by CBflow uvmgen)',
         f'class {b}_scoreboard extends uvm_scoreboard;', f'    `uvm_component_utils({b}_scoreboard)',
         f'    {b}_ref_model model;']
    for i in ins + [v['name'] for v in sp.vr_out]:
        o.append(f'    uvm_tlm_analysis_fifo #({b}_{i}_item) {i}_fifo;')
    o += ['    int unsigned n_compared, n_mismatch;',
          '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
          '    function void build_phase(uvm_phase phase);']
    for i in ins + [v['name'] for v in sp.vr_out]:
        o.append(f'        {i}_fifo = new("{i}_fifo", this);')
    o += [f'        if (model == null) model = {b}_ref_model::type_id::create("model");',
          '    endfunction', '    task run_phase(uvm_phase phase);', '        fork']
    for i in ins:
        o.append(f'            forever begin {b}_{i}_item t; {i}_fifo.get(t); model.observe_{i}(t); end')
    for v in sp.vr_out:
        n = v['name']
        o += ['            forever begin',
              f'                {b}_{n}_item t, e; {n}_fifo.get(t);',
              f'                if (model.stub) `uvm_error("SB-NOMODEL", "{b}_ref_model is a stub — {n} not checked")',
              f'                else if (model.exp_{n}.size() == 0) `uvm_error("SB-UNEXPECTED", $sformatf("{n}: unexpected %s", t.convert2string()))',
              '                else begin',
              f'                    e = model.exp_{n}.pop_front(); n_compared++;',
              '                    if (t.data !== e.data) begin',
              '                        n_mismatch++;',
              f'                        `uvm_error("SB-MISMATCH", $sformatf("{n}: got %s, expected %s", t.convert2string(), e.convert2string()))',
              '                    end', '                end', '            end']
    o += ['        join', '    endtask',
          '    // expected output transactions not seen yet (the test drains them)',
          '    function int unsigned outstanding();',
          '        return 0' + ''.join(f' + model.exp_{v["name"]}.size()' for v in sp.vr_out) + ';',
          '    endfunction',
          '    function void check_phase(uvm_phase phase);']
    for v in sp.vr_out:
        o.append(f'        if (model.exp_{v["name"]}.size()) `uvm_error("SB-MISSING", '
                 f'$sformatf("{v["name"]}: %0d expected transaction(s) never seen", model.exp_{v["name"]}.size()))')
    o += ['    endfunction', '    function void report_phase(uvm_phase phase);',
          '        `uvm_info("SB", $sformatf("compared %0d, mismatches %0d", n_compared, n_mismatch), UVM_LOW)',
          '    endfunction', 'endclass', '']
    return '\n'.join(o)


def gen_coverage(sp, items):
    b = sp.b
    ins = [v['name'] for v in sp.vr] + [a['name'] for a in sp.apb]
    o = [f'// {b}_coverage — functional coverage (USER-OWNED: copy into the TB directory',
         f'// and write the covergroups). A vPlan coverage item is a coverpoint / cross',
         f'// of that name in any covergroup; CBflow reads the bins from the merged',
         f'// coverage database. vPlan coverage items to implement:']
    for f, it in items:
        o.append(f'//   {f}: {", ".join(it)}')
    o += [f'class {b}_coverage extends uvm_component;', f'    `uvm_component_utils({b}_coverage)']
    if sp.reg_if:
        o.append('    uvm_reg_block regmodel;')
    for i in ins:
        o.append(f'    uvm_tlm_analysis_fifo #({b}_{i}_item) {i}_fifo;')
    o += ['    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
          '    function void build_phase(uvm_phase phase);']
    for i in ins:
        o.append(f'        {i}_fifo = new("{i}_fifo", this);')
    o += ['    endfunction', '    task run_phase(uvm_phase phase);', '        fork']
    for i in ins:
        o.append(f'            forever begin {b}_{i}_item t; {i}_fifo.get(t); sample_{i}(t); end')
    o += ['        join', '    endtask']
    for i in ins:
        o += [f'    virtual function void sample_{i}({b}_{i}_item t);', '    endfunction']
    o += ['endclass', '']
    return '\n'.join(o)


def gen_env(sp, ral_pkg, ral_cls):
    b = sp.b
    o = [f'// {b} — environment (generated by CBflow uvmgen)',
         f'class {b}_env extends uvm_env;', f'    `uvm_component_utils({b}_env)', f'    {b}_env_cfg cfg;']
    for v in sp.vr:
        o.append(f'    {b}_{v["name"]}_agent {v["name"]}_agt;')
    for a in sp.apb:
        o.append(f'    {b}_{a["name"]}_agent {a["name"]}_agt;')
    r = sp.reg_if
    if r:
        n = f'{b}_{r["name"]}'
        o += [f'    {ral_pkg}::{ral_cls} regmodel;', f'    {n}_reg_adapter adapter;',
              f'    uvm_reg_predictor #({n}_item) predictor;']
    o += [f'    {b}_scoreboard sb;', f'    {b}_coverage cov;', f'    virtual {b}_misc_if misc_vif;',
          '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
          '    function void build_phase(uvm_phase phase);',
          f'        if (cfg == null && !uvm_config_db #({b}_env_cfg)::get(this, "", "cfg", cfg)) cfg = {b}_env_cfg::type_id::create("cfg");',
          f'        if (!uvm_config_db #(virtual {b}_misc_if)::get(this, "", "misc_vif", misc_vif))',
          '            `uvm_fatal("NOVIF", "misc virtual interface not set")']
    for v in sp.vr:
        o.append(f'        {v["name"]}_agt = {b}_{v["name"]}_agent::type_id::create("{v["name"]}_agt", this); {v["name"]}_agt.cfg = cfg;')
    for a in sp.apb:
        o.append(f'        {a["name"]}_agt = {b}_{a["name"]}_agent::type_id::create("{a["name"]}_agt", this);')
    if r:
        n = f'{b}_{r["name"]}'
        o += ['        regmodel = new("regmodel");', '        regmodel.build();', '        regmodel.lock_model();',
              f'        adapter = {n}_reg_adapter::type_id::create("adapter");',
              f'        predictor = uvm_reg_predictor #({n}_item)::type_id::create("predictor", this);']
    o += [f'        sb = {b}_scoreboard::type_id::create("sb", this);',
          f'        cov = {b}_coverage::type_id::create("cov", this);', '    endfunction',
          '    function void connect_phase(uvm_phase phase);']
    for v in sp.vr:
        n = v['name']
        o.append(f'        {n}_agt.mon.ap.connect(sb.{n}_fifo.analysis_export); '
                 f'{n}_agt.mon.ap.connect(cov.{n}_fifo.analysis_export);')
    for a in sp.apb:
        n = a['name']
        o.append(f'        {n}_agt.mon.ap.connect(sb.{n}_fifo.analysis_export); '
                 f'{n}_agt.mon.ap.connect(cov.{n}_fifo.analysis_export);')
    if r:
        n = r['name']
        o += [f'        regmodel.default_map.set_sequencer({n}_agt.sqr, adapter);',
              '        regmodel.default_map.set_auto_predict(0);',
              '        predictor.map = regmodel.default_map; predictor.adapter = adapter;',
              f'        {n}_agt.mon.ap.connect(predictor.bus_in);', '        cov.regmodel = regmodel;']
    o += ['    endfunction', '    task wait_reset_done();',
          '        @(posedge misc_vif.clk); while (misc_vif.rst) @(posedge misc_vif.clk);', '    endtask',
          '    task wait_cycles(int unsigned n); repeat (n) @(posedge misc_vif.clk); endtask',
          'endclass', '']
    return '\n'.join(o)


def gen_seqs(sp):
    b = sp.b
    o = [f'// {b} — sequences (generated by CBflow uvmgen)']
    for v in sp.vr_in:
        n = f'{b}_{v["name"]}'
        o += [f'class {n}_rand_seq extends uvm_sequence #({n}_item);', f'    `uvm_object_utils({n}_rand_seq)',
              '    int unsigned count = 20;',
              f'    function new(string name = "{n}_rand_seq"); super.new(name); endfunction',
              '    task body();', '        repeat (count) begin',
              f'            {n}_item t = {n}_item::type_id::create("t");',
              '            start_item(t);',
              '            if (!t.randomize()) `uvm_fatal("RAND", "randomize failed")',
              '            finish_item(t);', '        end', '    endtask', 'endclass', '']
    return '\n'.join(o)


def gen_base_test(sp, user_classes):
    b = sp.b
    o = [f'// {b} — base test + sanity test (generated by CBflow uvmgen)',
         f'class {b}_base_test extends uvm_test;', f'    `uvm_component_utils({b}_base_test)',
         f'    {b}_env env; {b}_env_cfg cfg;',
         '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
         '    // tests adjust cfg here (back-pressure, timeout) before the env is built',
         '    virtual function void configure(); endfunction',
         '    function void build_phase(uvm_phase phase);',
         f'        cfg = {b}_env_cfg::type_id::create("cfg");', '        configure();',
         f'        uvm_config_db #({b}_env_cfg)::set(this, "env", "cfg", cfg);',
         f'        env = {b}_env::type_id::create("env", this);', '    endfunction',
         '    // the stimulus of a test',
         '    virtual task body(); endtask',
         '    task run_phase(uvm_phase phase);',
         '        phase.raise_objection(this);',
         '        fork',
         '            begin env.wait_cycles(cfg.timeout_cycles);',
         '                  `uvm_fatal("TIMEOUT", $sformatf("test did not finish in %0d cycles", cfg.timeout_cycles)) end',
         '        join_none',
         '        env.wait_reset_done();', '        body();',
         '        // drain: every expected output transaction (watchdog bounds it)',
         '        while (env.sb.outstanding()) env.wait_cycles(1);',
         '        env.wait_cycles(20);',
         '        phase.drop_objection(this);', '    endtask', 'endclass', '']
    if f'{b}_sanity_test' not in user_classes:
        o += [f'// sanity: random traffic on every driven interface, register reset values',
              f'class {b}_sanity_test extends {b}_base_test;', f'    `uvm_component_utils({b}_sanity_test)',
              '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
              '    task body();']
        if sp.reg_if:
            o += ['        uvm_reg_hw_reset_seq rst_seq = uvm_reg_hw_reset_seq::type_id::create("rst_seq");',
                  '        rst_seq.model = env.regmodel;', '        rst_seq.start(null);']
        o.append('        fork')
        for v in sp.vr_in:
            n = f'{b}_{v["name"]}'
            o.append(f'            begin {n}_rand_seq s = {n}_rand_seq::type_id::create("s"); '
                     f's.start(env.{v["name"]}_agt.sqr); end')
        o += ['        join', '    endtask', 'endclass', '']
    return '\n'.join(o)


def gen_stubs(sp, plan, user_classes):
    b = sp.b
    o = [f'// {b} — vPlan tests not written yet (generated by CBflow uvmgen). Each fails',
         '// with TEST-TODO until a class of that name exists in the TB directory.']
    stubs = []
    for f, m, tests in plan:
        for t in tests:
            if t in user_classes or t == f'{b}_sanity_test' or t in stubs:
                continue
            stubs.append(t)
            o += [f'class {t} extends {b}_base_test;', f'    `uvm_component_utils({t})',
                  '    function new(string name, uvm_component parent); super.new(name, parent); endfunction',
                  f'    task body(); `uvm_error("TEST-TODO", "{t} not implemented (vPlan {f}, {m})") endtask',
                  'endclass', '']
    return '\n'.join(o) + '\n', stubs


def gen_pkg(sp, ral_pkg):
    b = sp.b
    files = ['agents', 'ref_model', 'scoreboard', 'coverage', 'env', 'seqs', 'base_test', 'tests', 'test_stubs']
    o = [f'// {b} — testbench package (generated by CBflow uvmgen)', f'package {b}_tb_pkg;',
         '    `include "uvm_macros.svh"', '    import uvm_pkg::*;', f'    import {ral_pkg}::*;']
    o += [f'    `include "{b}_{f}.sv"' for f in files]
    o += ['endpackage', '']
    return '\n'.join(o)


def gen_top(sp):
    b = sp.b
    per = float(sp.clock.get('period_ns'))
    act_low = str(sp.reset.get('active', 'high')).lower() == 'low'
    o = ['`timescale 1ns/1ps', f'// {b} — testbench top (generated by CBflow uvmgen)', f'module {b}_tb_top;',
         '    import uvm_pkg::*;', f'    import {b}_tb_pkg::*;',
         '    logic clk = 0;', '    logic rst = 1;                        // active high inside the TB',
         f'    always #({per / 2:g}) clk = ~clk;      // {sp.clock["name"]}: {per:g} ns',
         '    initial begin repeat (5) @(posedge clk); #1 rst = 0; end']
    for v in sp.vr:
        o.append(f'    {b}_{v["name"]}_if u_{v["name"]}_if (clk, rst);')
    for a in sp.apb:
        o.append(f'    {b}_{a["name"]}_if u_{a["name"]}_if (clk, rst);')
    o.append(f'    {b}_misc_if u_misc_if (clk, rst);')
    for p in sp.misc:
        if p['dir'] == 'in':
            o.append(f"    initial u_misc_if.{p['name']} = '0;")
    conns = [f'.{sp.clock["port"]}(clk)', f'.{sp.reset["port"]}({"~rst" if act_low else "rst"})']
    for v in sp.vr:
        i = f'u_{v["name"]}_if'
        conns += [f'.{v["valid"]}({i}.valid)', f'.{v["ready"]}({i}.ready)', f'.{v["data"]}({i}.data)']
    for a in sp.apb:
        conns += [f'.{a["ports"][g]}(u_{a["name"]}_if.{g})' for g in APB_SIGS]
    conns += [f'.{p["name"]}(u_misc_if.{p["name"]})' for p in sp.misc]
    o.append(f'    {b} dut (')
    o.append(',\n'.join(f'        {c}' for c in conns))
    o += ['    );', '    initial begin']
    for v in sp.vr:
        o.append(f'        uvm_config_db #(virtual {b}_{v["name"]}_if)::set(null, "*.{v["name"]}_agt", "vif", u_{v["name"]}_if);')
    for a in sp.apb:
        o.append(f'        uvm_config_db #(virtual {b}_{a["name"]}_if)::set(null, "*.{a["name"]}_agt", "vif", u_{a["name"]}_if);')
    o += [f'        uvm_config_db #(virtual {b}_misc_if)::set(null, "*", "misc_vif", u_misc_if);',
          '        run_test();', '    end', 'endmodule', '']
    return '\n'.join(o)


# ── gen ──────────────────────────────────────────────────────────────────────
def _classes(path):
    return set(re.findall(r'^\s*class\s+(\w+)', open(path, errors='replace').read(), re.M))


def cmd_gen(a):
    sp = Spec(a.spec)
    b = sp.b
    ral_pkg, ral_cls = ral_info(a.ral)
    plan = vplan_tests(a.vplan)
    items = []
    if a.vplan:
        import openpyxl
        ws = openpyxl.load_workbook(a.vplan, read_only=True)['vplan']
        rows = list(ws.iter_rows(values_only=True))
        hdr = [str(h or '').strip().lower() for h in rows[0]]
        fi, ci = hdr.index('feature id'), hdr.index('coverage items')
        items = [(str(r[fi]), [x.strip() for x in str(r[ci] or '').split(',') if x.strip()])
                 for r in rows[1:] if r[fi]]
    user = {}
    if a.user_dir:
        if not os.path.isdir(a.user_dir):
            raise GenError(f'TB directory {a.user_dir} not found')
        for f in sorted(os.listdir(a.user_dir)):
            p = os.path.join(a.user_dir, f)
            if os.path.isfile(p) and f.endswith(('.sv', '.svh', '.v')):
                user[f] = p
    user_classes = set()
    for p in user.values():
        user_classes |= _classes(p)
    os.makedirs(a.output, exist_ok=True)
    stubs_src, stubs = gen_stubs(sp, plan, user_classes)
    gen = {f'{b}_if.sv': gen_if(sp), f'{b}_agents.sv': gen_agents(sp),
           f'{b}_ref_model.sv': gen_ref_model(sp), f'{b}_scoreboard.sv': gen_scoreboard(sp),
           f'{b}_coverage.sv': gen_coverage(sp, items), f'{b}_env.sv': gen_env(sp, ral_pkg, ral_cls),
           f'{b}_seqs.sv': gen_seqs(sp), f'{b}_base_test.sv': gen_base_test(sp, user_classes),
           f'{b}_tests.sv': f'// {b}_tests — tests (USER-OWNED: write them in the TB directory)\n',
           f'{b}_test_stubs.sv': stubs_src, f'{b}_tb_pkg.sv': gen_pkg(sp, ral_pkg),
           f'{b}_tb_top.sv': gen_top(sp)}
    written, owned = [], []
    for f, txt in gen.items():
        if f in user:
            continue
        with open(os.path.join(a.output, f), 'w') as fh:
            fh.write(txt)
        written.append(f)
    for f, p in user.items():
        shutil.copy2(p, os.path.join(a.output, f))
        owned.append(f)
    for m in a.models or []:                 # memory models travel with the TB
        shutil.copy2(m, os.path.join(a.output, os.path.basename(m)))
    ral_dst = os.path.join(a.output, os.path.basename(a.ral))
    shutil.copy2(a.ral, ral_dst)
    rtl = [l.strip() for l in open(a.rtl_f) if l.strip() and not l.strip().startswith(('#', '//'))]
    for r in rtl:
        if not os.path.isfile(r):
            raise GenError(f'RTL source {r} ({a.rtl_f}) not found')
    out = os.path.abspath(a.output)
    flist = rtl + [os.path.join(out, os.path.basename(m)) for m in (a.models or [])] + \
        [os.path.join(out, f) for f in (f'{b}_if.sv', os.path.basename(a.ral), f'{b}_tb_pkg.sv', f'{b}_tb_top.sv')]
    with open(os.path.join(a.output, 'tb.f'), 'w') as fh:
        fh.write(f'+incdir+{out}\n' + '\n'.join(flist) + '\n')
    with open(os.path.join(a.output, 'rtl.f'), 'w') as fh:     # the DUT sources (code coverage scope)
        fh.write('\n'.join(rtl) + '\n')
    model_stub = f'{b}_ref_model.sv' not in user
    cov_stub = f'{b}_coverage.sv' not in user
    tests_all = sorted({t for _, _, ts in plan for t in ts})
    lines = [f'UVM testbench — {b} (uvmgen)',
             f'  Top               : {b}_tb_top (DUT {b}, clock {sp.clock["port"]} {sp.clock["period_ns"]} ns)',
             f'  Interfaces        : {len(sp.vr) + len(sp.apb)} '
             f'({", ".join([v["name"] + " valid_ready/" + v["mode"] for v in sp.vr] + [x["name"] + " apb4" for x in sp.apb])})',
             f'  Register model    : {ral_pkg}::{ral_cls}' + (f' on {sp.reg_if["name"]}' if sp.reg_if else ' (no register interface)'),
             f'  Generated files   : {len(written)}',
             f'  User-owned files  : {len(owned)}' + (f'  ({", ".join(owned)})' if owned else ''),
             f'  Reference model   : {"STUB — outputs not checked" if model_stub else "user"}',
             f'  Coverage model    : {"STUB — no functional coverage" if cov_stub else "user"}',
             f'  vPlan tests       : {len(tests_all)}',
             f'  Tests implemented : {len(tests_all) - len(stubs)}',
             f'  Test stubs        : {len(stubs)}' + (f'  ({", ".join(stubs)})' if stubs else ''), '']
    with open(a.report, 'w') as fh:
        fh.write('\n'.join(lines))
    print('\n'.join(lines))


def main():
    ap = argparse.ArgumentParser(description='UVM testbench from the CBflow block spec')
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('gen')
    p.add_argument('--spec', required=True); p.add_argument('--ral', required=True)
    p.add_argument('--rtl-f', required=True); p.add_argument('--vplan')
    p.add_argument('--user-dir'); p.add_argument('--models', nargs='*')
    p.add_argument('-o', '--output', required=True); p.add_argument('--report', required=True)
    a = ap.parse_args()
    try:
        cmd_gen(a)
    except GenError as e:
        sys.exit(f'uvmgen: ERROR: {e}')


if __name__ == '__main__':
    main()
