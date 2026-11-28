#!/usr/bin/env python3
"""cmd-manager helper (cmd-manager skill): audit, create, update and retire CBflow
command files and subnode handlers.

    cmdm.py audit  [--disc PD DFT DV RTL] [--flow F] [--tool T] [--json out.json]
    cmdm.py list   --flow F --tool T
    cmdm.py lint   --file <cmd or handler .tcl>
    cmdm.py new    --flow F --tool T --stage <node_type> [--from <node_type>] [--apply --framework]
    cmdm.py retire --flow F --tool T --stage <node_type> [--force] [--apply --framework]

Layout: <DISC>/cmds/<FLOW>/<vendor>/<tool>/<version>/
          <node_type>_subnode_handler.tcl    (the engine runs it per node: setup / run /
                                              validate / finish via handler_dispatch)
          <node_type>_<tool>.tcl             (the command file the handler names in cmd_file)
        DISC = flow(discipline,<FLOW>); vendor / version = <arr>(tool,vendor|version) of
        node_configs/<FLOW>_<tool>_config.tcl; node types = the stages' node_types
        (the tool overlay's stages / node_types when it declares its own); input stages
        use the shared inputs_subnode_handler.tcl.
audit   per flow x tool: node types without a handler, handlers without their command
        file, command files no stage uses (orphans), lint findings; "suggest" lines for
        what to create. Exit 1 when anything is missing.
lint    a command file: Tcl complete, the 14-line bootstrap (run_dir, .run.cbflow.tcl,
        utils.tcl, FLOW_TYPE / STAGE_NAME / NODE_NAME, config.tcl, setup.tcl,
        setup_dirs), FLOW_TYPE = the path's flow, STAGE_NAME = the file's node type,
        flow_exec_all at the end. A handler: handler_common, handler_dispatch, the
        cmd_file it names exists.
new     handler + command file for a node type: from a sibling node type of the same
        tool (--from, else the first existing one) with the stage name substituted;
        the command file body is a bootstrap + flow_proc skeleton to fill. Dry run
        unless --apply; command files are framework code: --apply needs --framework
        (the user's explicit go-ahead).
retire  moves the handler + command file to <dir>/.retired/<timestamp>/ (reversible);
        refused while a stage of the flow / tool still uses the node type (--force).
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
DISCS = ('PD', 'DFT', 'DV', 'RTL')
BOOT = [r'set\s+run_dir\s', r'\.run\.cbflow\.tcl',
        r'utils\.tcl', r'set\s+FLOW_TYPE\s+"?\w+',
        r'set\s+STAGE_NAME\s+"?\w+', r'set\s+NODE_NAME\s',
        r'/run/config\.tcl', r'/run/setup\.tcl', r'setup_dirs\s']


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def registry_disc():
    t = open(os.path.join(ROOT, 'global', 'config', 'flow', 'v1.0.0', 'flow_registry.tcl')).read()
    return dict(re.findall(r'set\s+flow\(discipline,(\w+)\)\s+"?(\w+)', t))


def kv_block(text):
    """key -> value of `array set <arr> { key value ... }` and `set <arr>(key) value` lines."""
    out = {}
    for m in re.finditer(r'^\s*([\w,]+)\s+"([^"]*)"', text, re.M):
        out[m.group(1)] = m.group(2)
    for m in re.finditer(r'^\s*set\s+\w+\(([\w,]+)\)\s+"?([^"\n]*)"?', text, re.M):
        out.setdefault(m.group(1), m.group(2).strip())
    return out


def flow_tools(disc, flow):
    """[(tool, vendor, version, overlay path)] from node_configs/<FLOW>_<tool>_config.tcl
    (not another flow's configs: SYNTH_PNR_* is not a SYNTH tool)."""
    nc = os.path.join(ROOT, disc, 'config', 'flow', 'v1.0.0', 'node_configs')
    flows = set(registry_disc())
    out = []
    for f in sorted(glob.glob(os.path.join(nc, f'{flow}_*_config.tcl'))):
        tool = os.path.basename(f)[len(flow) + 1:-len('_config.tcl')]
        if any(f'{flow}_{tool}' == g or f'{flow}_{tool}'.startswith(g + '_') for g in flows if g != flow):
            continue
        kv = kv_block(open(f).read())
        out.append((tool, kv.get('tool,vendor', ''), kv.get('tool,version', 'v1.0.0'), f))
    return out


def node_types(disc, flow, tool_cfg):
    """{stage: node_type}: the node config sourced in Tcl with the tool selected (as
    the engine resolves it); the text parse below only when sourcing fails."""
    import subprocess
    arr = flow.lower()
    tool = os.path.basename(tool_cfg)[len(flow) + 1:-len('_config.tcl')] if tool_cfg else ''
    base = os.path.join(ROOT, disc, 'config', 'flow', 'v1.0.0', 'node_configs', f'{flow}_config.tcl')
    script = (f'array set project {{}}\narray set tech {{}}\narray set flow {{}}\narray set {arr} {{}}\n'
              f'set flow(type) {flow}\nset flow(design_name) x\nset {arr}(tool,name) {tool}\n'
              f'set ::env(CBFLOW_CORE_DIR) {{{os.path.join(ROOT, "PD")}}}\nset ::env(FLOW_DIR) {{{ROOT}}}\n'
              f'set ::env(FLOW_CONFIG_VERSION) v1.0.0\n'
              'rename exit __exit\nproc exit {args} { error exit }\n'
              f'catch {{ source {{{base}}} }}\n'
              f'if {{![info exists {arr}(stages)] || [lsearch [array names {arr}] node_types,*] < 0}} {{ catch {{ source {{{tool_cfg}}} }} }}\n'
              f'if {{[info exists {arr}(stages)]}} {{ foreach s ${arr}(stages) {{\n'
              f'  set nt [expr {{[info exists {arr}(node_types,$s)] ? ${arr}(node_types,$s) : ""}}]\n'
              f'  set ty [expr {{[info exists {arr}(stage_types,$s)] ? ${arr}(stage_types,$s) : ""}}]\n'
              '  puts "S\t$s\t$nt\t$ty" } }\n')
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    rows = [l.split('\t') for l in r.stdout.splitlines() if l.startswith('S\t')]
    if rows:
        return {s_: ('inputs' if ty == 'inputs' else (nt or s_.rstrip('0123456789'))) for _, s_, nt, ty in rows}
    return _node_types_text(disc, flow, tool_cfg)


def _node_types_text(disc, flow, tool_cfg):
    """{stage: node_type} from the node config text (tool overlay stages win)."""
    base = os.path.join(ROOT, disc, 'config', 'flow', 'v1.0.0', 'node_configs', f'{flow}_config.tcl')
    txt = open(base).read() if os.path.exists(base) else ''
    tt = open(tool_cfg).read() if tool_cfg and os.path.exists(tool_cfg) else ''
    st_rx = r'(?:^\s*stages|\(stages\))\s+\{([^}]+)\}'
    nt_rx = r'node_types,(\w+)\)?\s+"(\w+)"'
    ty_rx = r'stage_types,(\w+)\)?\s+"(\w+)"'
    m = re.search(st_rx, tt, re.M) or re.search(st_rx, txt, re.M)
    stages = [x for x in (m.group(1).split() if m else []) if re.fullmatch(r'\w+', x)]
    nt = dict(re.findall(nt_rx, txt))
    nt.update(dict(re.findall(nt_rx, tt)))
    # stage_types "inputs" marks an input stage whatever its node type name
    for st_, ty in list(re.findall(ty_rx, txt)) + list(re.findall(ty_rx, tt)):
        if ty == 'inputs':
            nt[st_] = 'inputs'
    # dynamic stage lists (foreach) — take every node_types entry as a stage too
    for s in nt:
        if s not in stages:
            stages.append(s)
    return {s: nt.get(s, s.rstrip('0123456789')) for s in stages}


def cmd_dir(disc, flow, vendor, tool, version):
    return os.path.join(ROOT, disc, 'cmds', flow, vendor, tool, version)


def lint_file(path):
    """[problem] for a command file or handler."""
    t = open(path, errors='replace').read()
    probs = []
    if not t.strip():
        return ['empty file']
    # balanced braces (Tcl info complete would need tclsh; a fast check here)
    if t.count('{') - t.count('\\{') != t.count('}') - t.count('\\}'):
        probs.append('unbalanced braces')
    name = os.path.basename(path)
    flow = path.split(os.sep + 'cmds' + os.sep)[1].split(os.sep)[0] if os.sep + 'cmds' + os.sep in path else ''
    if name.endswith('_subnode_handler.tcl'):
        if 'handler_common.tcl' not in t:
            probs.append('handler does not source handler_common.tcl')
        if not re.search(r'handler_dispatch|handler_setup|handler_validate', t) and 'inputs' not in name:
            probs.append('handler calls none of handler_dispatch / handler_setup / handler_validate')
        m = re.search(r'set cmd_file "([^"]+)"', t)
        if m:
            cf = m.group(1).replace('$::env(FLOW_DIR)', ROOT)
            cf = re.sub(r'\$_tool_ver|\$::env\(\w+_VERSION\)', os.path.basename(os.path.dirname(path)), cf)
            if '$' not in cf and not os.path.exists(cf):
                probs.append(f'cmd_file does not exist: {os.path.relpath(cf, ROOT)}')
        m = re.search(r'set stage_name "(\w+)"', t)
        if m and m.group(1) != name[:-len('_subnode_handler.tcl')]:
            probs.append(f'stage_name "{m.group(1)}" != file node type "{name[:-len("_subnode_handler.tcl")]}"')
        return probs
    missing = [p for p in BOOT if not re.search(p, t)]
    if missing:
        probs.append(f'bootstrap incomplete ({len(missing)} of {len(BOOT)} lines missing: '
                     + ', '.join(re.sub(r'[\\()]', '', p)[:28] for p in missing[:3]) + ')')
    m = re.search(r'set\s+FLOW_TYPE\s+"?(\w+)', t)
    if m and flow and m.group(1) != flow:
        probs.append(f'FLOW_TYPE "{m.group(1)}" != path flow "{flow}"')
    stage = re.sub(r'_[^_]+\.tcl$', '', name)
    m = re.search(r'set\s+STAGE_NAME\s+"?(\w+)', t)
    if m and m.group(1) != stage:
        probs.append(f'STAGE_NAME "{m.group(1)}" != file node type "{stage}"')
    if 'flow_exec_all' not in t and 'flow_proc' in t:
        probs.append('flow_procs defined but flow_exec_all never called')
    return probs


def audit_one(disc, flow, tool, vendor, version, cfg):
    d = cmd_dir(disc, flow, vendor, tool, version)
    nts = node_types(disc, flow, cfg)
    need = sorted({nt for nt in nts.values() if nt != 'inputs'})
    res = {'flow': flow, 'tool': tool, 'vendor': vendor, 'dir': os.path.relpath(d, ROOT),
           'missing_handler': [], 'missing_cmd': [], 'orphans': [], 'lint': [], 'ok': []}
    if not vendor:
        res['lint'].append(f'{os.path.relpath(cfg, ROOT)}: no tool,vendor')
        return res
    if not os.path.isdir(d):
        res['missing_handler'] = need
        return res
    for nt in need:
        h = os.path.join(d, f'{nt}_subnode_handler.tcl')
        c = os.path.join(d, f'{nt}_{tool}.tcl')
        if not os.path.exists(h):
            res['missing_handler'].append(nt)
            continue
        if not os.path.exists(c) and 'set cmd_file' in open(h).read():
            res['missing_cmd'].append(nt)
        else:
            res['ok'].append(nt)
        for f in (h, c):
            if os.path.exists(f):
                res['lint'] += [f'{os.path.relpath(f, ROOT)}: {p}' for p in lint_file(f)]
    if any(nt == 'inputs' for nt in nts.values()) and not os.path.exists(os.path.join(d, 'inputs_subnode_handler.tcl')):
        res['missing_handler'].append('inputs')
    used = set(need) | {'inputs'}
    for f in sorted(glob.glob(os.path.join(d, '*_subnode_handler.tcl'))):
        nt = os.path.basename(f)[:-len('_subnode_handler.tcl')]
        if nt not in used:
            res['orphans'].append(os.path.basename(f))
    return res


def cmd_audit(a):
    dmap = registry_disc()
    rows = []
    for flow, disc in sorted(dmap.items()):
        if a.disc and disc not in a.disc:
            continue
        if a.flow and flow != a.flow:
            continue
        for tool, vendor, version, cfg in flow_tools(disc, flow):
            if a.tool and tool != a.tool:
                continue
            rows.append(audit_one(disc, flow, tool, vendor, version, cfg))
    bad = 0
    for r in rows:
        n = len(r['missing_handler']) + len(r['missing_cmd'])
        status = 'OK ' if not n and not r['lint'] else ('MISS' if n else 'LINT')
        bad += bool(n)
        print(f'[{status}] {r["flow"]:16s} {r["vendor"]}/{r["tool"]:12s} {len(r["ok"])} ok'
              + (f', missing handler: {" ".join(r["missing_handler"])}' if r['missing_handler'] else '')
              + (f', missing command file: {" ".join(r["missing_cmd"])}' if r['missing_cmd'] else '')
              + (f', orphan: {" ".join(r["orphans"])}' if r['orphans'] else ''))
        for l in r['lint'][:6]:
            print(f'        lint  {l}')
        for nt in r['missing_handler'] + r['missing_cmd']:
            print(f'        suggest  cmdm.py new --flow {r["flow"]} --tool {r["tool"]} --stage {nt}')
    print(f'\n{len(rows)} flow/tool pair(s); {bad} with missing files')
    if a.json:
        json.dump(rows, open(a.json, 'w'), indent=1)
    return 1 if bad else 0


def find_tool(flow, tool):
    disc = registry_disc().get(flow)
    if not disc:
        die(f'{flow}: no flow(discipline,{flow}) in flow_registry.tcl')
    for t, vendor, version, cfg in flow_tools(disc, flow):
        if t == tool:
            return disc, vendor, version, cfg
    die(f'{flow}: no node_configs/{flow}_{tool}_config.tcl (tools: '
        f'{", ".join(t for t, *_ in flow_tools(disc, flow)) or "none"})')


def cmd_list(a):
    disc, vendor, version, cfg = find_tool(a.flow, a.tool)
    d = cmd_dir(disc, a.flow, vendor, a.tool, version)
    nts = node_types(disc, a.flow, cfg)
    print(f'{a.flow} {vendor}/{a.tool} {version}  ({os.path.relpath(d, ROOT)})')
    for s, nt in nts.items():
        h = os.path.exists(os.path.join(d, f'{nt}_subnode_handler.tcl'))
        c = os.path.exists(os.path.join(d, f'{nt}_{a.tool}.tcl'))
        print(f'  {s:24s} {nt:18s} handler {"✓" if h else "✗"}   command {"✓" if c else ("–" if nt == "inputs" else "✗")}')
    return 0


def cmd_lint(a):
    p = lint_file(os.path.abspath(a.file))
    for x in p:
        print(f'  {x}')
    print('clean' if not p else f'{len(p)} problem(s)')
    return 1 if p else 0


CMD_SKELETON = '''#!/usr/bin/env tclsh
# =============================================================================
# CBflow {flow} ({vendor} {tool}) — {stage}
# Generated by cmd-manager from {src}; fill the flow_procs.
# =============================================================================
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "{flow}"
set STAGE_NAME "{stage}"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
{extra_src}
# Load the previous stage's database
flow_proc load_design {{
    # TODO(cmd-manager): read the upstream database
}}

# The {stage} operation
flow_proc {stage} {{
    # TODO(cmd-manager): {stage}
}}

# Reports
flow_proc report {{
    # TODO(cmd-manager): reports into $::REPORTS_DIR
}}

# Save the stage database into outputs/
flow_proc save_design {{
    # TODO(cmd-manager): write outputs
}}

flow_exec_all
exit
'''


def cmd_new(a):
    disc, vendor, version, cfg = find_tool(a.flow, a.tool)
    d = cmd_dir(disc, a.flow, vendor, a.tool, version)
    h_new = os.path.join(d, f'{a.stage}_subnode_handler.tcl')
    c_new = os.path.join(d, f'{a.stage}_{a.tool}.tcl')
    if os.path.exists(h_new) or os.path.exists(c_new):
        die(f'{a.stage} exists in {os.path.relpath(d, ROOT)} — edit it instead')
    sibs = sorted(os.path.basename(f)[:-len('_subnode_handler.tcl')]
                  for f in glob.glob(os.path.join(d, '*_subnode_handler.tcl')) if 'inputs' not in f)
    src = a.from_stage or (sibs[0] if sibs else None)
    if a.stage not in node_types(disc, a.flow, cfg).values():
        print(f'NOTE  {a.stage} is not a node type of {a.flow}/{a.tool} yet — add the stage to the node config '
              f'(node_types,<stage>1 "{a.stage}") or the engine never runs it (config-manager skill)')
    files = {}
    if src:
        h_src = os.path.join(d, f'{src}_subnode_handler.tcl')
        if not os.path.exists(h_src):
            die(f'--from {src}: no {os.path.relpath(h_src, ROOT)}')
        files[h_new] = re.sub(rf'\b{re.escape(src)}\b', a.stage, open(h_src).read())
        c_src = os.path.join(d, f'{src}_{a.tool}.tcl')
        extra = ''
        if os.path.exists(c_src):
            extra = ''.join(l for l in open(c_src) if re.match(r'source .*_utils\.tcl"?\s*$', l) and 'utils.tcl"' not in l)
        files[c_new] = CMD_SKELETON.format(flow=a.flow, vendor=vendor, tool=a.tool, stage=a.stage,
                                           src=f'{src}_{a.tool}.tcl', extra_src=extra)
    else:
        die(f'no sibling handler in {os.path.relpath(d, ROOT)} to derive from — pass --from or create the tool dir first')
    for f, t in files.items():
        print(f'{"write" if a.apply else "would write"} {os.path.relpath(f, ROOT)} ({len(t.splitlines())} lines)')
    if not a.apply:
        print('dry run — --apply --framework to write (command files are framework code: user\'s explicit go-ahead)')
        return 0
    if not a.framework:
        die('--apply on command files needs --framework (the user\'s explicit go-ahead)')
    os.makedirs(d, exist_ok=True)
    for f, t in files.items():
        with open(f, 'w') as fh:
            fh.write(t)
        if f.endswith('_subnode_handler.tcl'):
            os.chmod(f, 0o755)
    for f in files:
        for p in lint_file(f):
            print(f'  lint {os.path.basename(f)}: {p}')
    return 0


def cmd_retire(a):
    disc, vendor, version, cfg = find_tool(a.flow, a.tool)
    d = cmd_dir(disc, a.flow, vendor, a.tool, version)
    files = [f for f in (os.path.join(d, f'{a.stage}_subnode_handler.tcl'), os.path.join(d, f'{a.stage}_{a.tool}.tcl'))
             if os.path.exists(f)]
    if not files:
        die(f'no {a.stage} files in {os.path.relpath(d, ROOT)}')
    users = [s for s, nt in node_types(disc, a.flow, cfg).items() if nt == a.stage]
    if users and not a.force:
        die(f'{a.stage} is still used by stage(s) {", ".join(users)} of {a.flow}/{a.tool} — remove them from the '
            f'node config first, or --force')
    dst = os.path.join(d, '.retired', datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    for f in files:
        print(f'{"move" if a.apply else "would move"} {os.path.relpath(f, ROOT)} -> {os.path.relpath(dst, ROOT)}/')
    if not a.apply:
        print('dry run — --apply --framework to move (reversible: move the files back)')
        return 0
    if not a.framework:
        die('--apply on command files needs --framework (the user\'s explicit go-ahead)')
    os.makedirs(dst, exist_ok=True)
    for f in files:
        shutil.move(f, os.path.join(dst, os.path.basename(f)))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('audit')
    p.add_argument('--disc', nargs='*', choices=DISCS)
    p.add_argument('--flow')
    p.add_argument('--tool')
    p.add_argument('--json')
    p = sub.add_parser('list')
    p.add_argument('--flow', required=True)
    p.add_argument('--tool', required=True)
    p = sub.add_parser('lint')
    p.add_argument('--file', required=True)
    for n in ('new', 'retire'):
        p = sub.add_parser(n)
        p.add_argument('--flow', required=True)
        p.add_argument('--tool', required=True)
        p.add_argument('--stage', required=True, help='node type, e.g. place, timing, drc')
        if n == 'new':
            p.add_argument('--from', dest='from_stage')
        else:
            p.add_argument('--force', action='store_true')
        p.add_argument('--apply', action='store_true')
        p.add_argument('--framework', action='store_true')
    a = ap.parse_args()
    return {'audit': cmd_audit, 'list': cmd_list, 'lint': cmd_lint, 'new': cmd_new, 'retire': cmd_retire}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
