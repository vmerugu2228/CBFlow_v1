#!/usr/bin/env python3
"""New CBflow project from a kickoff spec (project-kickoff skill).

    kickoff.py template --like <ref project> --name <new> --out spec.json
    kickoff.py check    --spec spec.json
    kickoff.py generate --spec spec.json --stage <dir>      renders into <dir> only
    kickoff.py apply    --stage <dir>                       copies into the repo (new files only)
    kickoff.py validate --project <name> [--smoke-block <b>] [--keep-smoke]

The spec is JSON. Fields the user must decide are "ASK" in the template; the
rest is copied from the reference project and listed under "_assumed" so the
skill can show them for confirmation. `check` exits 1 while any ASK / invalid
item remains. `generate` writes the whole project into a staging tree that
mirrors the repo (global/, PD/, DFT/, DV/, workarea/) plus external dirs listed
in STAGE.json; `apply` refuses to overwrite anything and records what it made
in <stage>/APPLIED.json.
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
CB = os.path.join(ROOT, 'bin', 'cbflow')
DISCS = ('PD', 'DFT', 'DV', 'RTL')
ASK = 'ASK'


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def tcl(script):
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if r.returncode:
        die(f'tclsh: {r.stderr.strip()}')
    return r.stdout


def proj_files(p):
    g = os.path.join(ROOT, 'global', 'config', 'project', p, 'v1.0.0')
    out = {'global': os.path.join(g, f'{p}_config.tcl'), 'mmmc': os.path.join(g, 'mmmc_config.tcl'),
           'node_scen': os.path.join(g, 'mmmc_node_scenarios.tcl'), 'schedule': os.path.join(g, 'schedule_config.tcl')}
    for d in DISCS:
        out[d] = os.path.join(ROOT, d, 'config', 'project', p, 'v1.0.0', f'{p}_{d.lower()}_config.tcl')
    return out


def registry():
    return json.load(open(os.path.join(ROOT, 'global', 'config', 'master_projects.json')))


def flow_registry():
    """flow types, discipline per flow, MILESTONE_ORDER and every exit milestone."""
    out = tcl(f'''
source {{{ROOT}/global/config/flow/v1.0.0/flow_registry.tcl}}
set fh [open {{{ROOT}/PD/config/flow/v1.0.0/release_config.tcl}}]; set t [read $fh]; close $fh
regexp {{set MILESTONE_ORDER \\{{([^}}]*)\\}}}} $t -> mo
puts "order\\t$mo"
foreach k [array names flow discipline,*] {{ puts "disc\\t[lindex [split $k ,] 1]\\t$flow($k)" }}
''')
    reg = {'disc': {}, 'order': []}
    for line in out.splitlines():
        f = line.split('\t')
        if f[0] == 'order':
            reg['order'] = f[1].split()
        elif f[0] == 'disc':
            reg['disc'][f[1]] = f[2]
    reg['exits'] = {}
    for c in glob.glob(os.path.join(ROOT, 'global', 'config', 'exit', 'v1.0.0', '*_config.tcl')):
        m = re.search(r'set milestone_info\(discipline\)\s+"(\w+)"', open(c).read())
        name = os.path.basename(c)[:-len('_config.tcl')]
        if m:
            reg['exits'][name] = m.group(1)
    return reg


def tool_overlays(flow):
    disc_dirs = [os.path.join(ROOT, d, 'config', 'flow', 'v1.0.0', 'node_configs') for d in DISCS]
    tools = set()
    for d in disc_dirs:
        for f in glob.glob(os.path.join(d, f'{flow}_*_config.tcl')):
            tools.add(os.path.basename(f)[len(flow) + 1:-len('_config.tcl')])
    return tools


# ── template ────────────────────────────────────────────────────────────────
def read_reference(ref):
    f = proj_files(ref)
    if not os.path.exists(f['global']):
        die(f'reference project {ref}: no {f["global"]}')
    srcs = ' '.join('{%s}' % f[k] for k in ['global', 'PD', 'DFT', 'DV', 'RTL', 'mmmc'] if os.path.exists(f[k]))
    keys = ['phases', 'current_phase', 'technology', 'vt_flavors', 'track_variant', 'metal_stack', 'top_module',
            'sdc_modes', 'default_sdc_mode', 'power,vdd_net', 'power,vss_net', 'power,vdd_pin', 'power,vss_pin',
            'power,rail_nets', 'pdn,enable', 'dft,enable', 'dft,max_chain_length', 'dft,clock_mixing',
            'dft,scan_enable_pattern', 'dft,scan_in_pattern', 'dft,scan_out_pattern', 'dft,atpg,test_coverage_min',
            'dft,atpg,fault_coverage_min', 'lib_root', 'lib_tag_root', 'lib_config_tag', 'lsf,enabled',
            'lsf,default_queue', 'release,structure', 'owner', 'contact', 'description', 'tapeout_date']
    out = tcl(f'''
foreach f {{{srcs}}} {{ source $f }}
foreach k {{{" ".join(keys)}}} {{ if {{[info exists project($k)]}} {{ puts "p\\t$k\\t$project($k)" }} }}
foreach k [array names project phase_exits*] {{ dict for {{ph ex}} $project($k) {{ puts "x\\t$k\\t$ph\\t$ex" }} }}
foreach k [array names project dv,targets,*] {{ puts "dv\\t[lindex [split $k ,] 2]\\t$project($k)" }}
if {{[info exists project(default_tools)]}} {{ dict for {{fl tl}} $project(default_tools) {{ puts "t\\t$fl\\t$tl" }} }}
foreach k {{voltage,nom voltage,low voltage,high temperature,hot temperature,nom temperature,cold process_corners}} {{
    if {{[info exists mmmc($k)]}} {{ puts "m\\t$k\\t$mmmc($k)" }}
}}
foreach k [array names mmmc pvt,*] {{ puts "pvt\\t[lindex [split $k ,] 1]\\t[list {{*}}$mmmc($k)]" }}
foreach k [array names rc_corners] {{ puts "rc\\t$k\\t[list {{*}}$rc_corners($k)]" }}
foreach k [array names operating_modes] {{ puts "mode\\t$k\\t[dict get $operating_modes($k) constraint_file]" }}
''')
    ref_vals = {'p': {}, 'x': {}, 'dv': {}, 't': {}, 'm': {}, 'pvt': {}, 'rc': {}, 'mode': {}}
    for line in out.splitlines():
        f = line.split('\t')
        if f[0] == 'x':
            ref_vals['x'].setdefault(f[1], {})[f[2]] = f[3].split()
        elif f[0] in ref_vals:
            ref_vals[f[0]][f[1]] = f[2]
    return ref_vals


def _newest_release():
    rd = os.path.join(ROOT, 'global', 'releases')
    vs = [d for d in os.listdir(rd) if d.startswith('v') and os.path.isfile(os.path.join(rd, d, 'MANIFEST.json'))] \
        if os.path.isdir(rd) else []
    return max(vs, key=lambda v: [int(x) if x.isdigit() else x for x in re.split(r'[.\-]', v[1:])]) if vs else ASK


def cmd_template(a):
    r = read_reference(a.like)
    rp = r['p']
    entry = registry().get('projects', {}).get(a.like, {})
    tw = lambda v: v.split()  # noqa: E731
    pex = {}
    for k, v in r['x'].items():
        disc = k.split(',')[1] if ',' in k else 'PD'
        pex[disc] = v
    spec = {
        'like': a.like, 'name': a.name or ASK, 'description': ASK, 'owner': ASK, 'contact': ASK,
        'chip_lead': ASK, 'technology': rp.get('technology', ASK),
        'cbflow_release': _newest_release(),
        'phases': tw(rp.get('phases', '')), 'current_phase': rp.get('current_phase', ''),
        'phase_exits': pex,
        'top_module': ASK,
        'hierarchy': ASK,
        'enabled_flows': entry.get('enabled_flows_by_discipline', {}),
        'default_tools': r['t'],
        'process': {'vt_flavors': rp.get('vt_flavors', ''), 'track_variant': rp.get('track_variant', ''),
                    'metal_stack': rp.get('metal_stack', '')},
        'sdc_modes': r['mode'],
        'power': {'vdd_net': rp.get('power,vdd_net', ''), 'vss_net': rp.get('power,vss_net', ''),
                  'vdd_pin': rp.get('power,vdd_pin', ''), 'vss_pin': rp.get('power,vss_pin', ''),
                  'rail_nets': tw(rp.get('power,rail_nets', ''))},
        'pdn_enable': rp.get('pdn,enable', 'true'),
        'paths': {'workarea': ASK, 'release': ASK, 'race_db': ASK, 'release_disks': [],
                  'lib_root': rp.get('lib_root', ASK), 'lib_tag_root': rp.get('lib_tag_root', ASK)},
        'library': {'base_tag': ASK, 'project_tag': ''},
        'mmmc': {'voltage': {k.split(',')[1]: r['m'][k] for k in r['m'] if k.startswith('voltage')},
                 'temperature': {k.split(',')[1]: r['m'][k] for k in r['m'] if k.startswith('temperature')},
                 'process_corners': tw(r['m'].get('process_corners', '')),
                 'pvt': {c: [list(x.split()) for x in re.findall(r'\{([^{}]*)\}', v)] for c, v in r['pvt'].items()},
                 'rc_corners': {k: dict(zip(v.split()[::2], v.split()[1::2])) for k, v in r['rc'].items()}},
        'dft': {k.split(',', 1)[1]: rp[k] for k in rp if k.startswith('dft,')},
        'dv_targets': {k: dict(zip(v.split()[::2], v.split()[1::2])) for k, v in r['dv'].items()},
        'lsf': {'enabled': rp.get('lsf,enabled', 'false'), 'default_queue': rp.get('lsf,default_queue', '')},
        'dates': {'start': datetime.date.today().isoformat(), 'tapeout': ASK},
        'block_inputs': {},
        '_assumed': ['cbflow_release', 'technology', 'phases', 'current_phase', 'phase_exits', 'enabled_flows', 'default_tools',
                     'process', 'sdc_modes', 'power', 'pdn_enable', 'paths.lib_root', 'paths.lib_tag_root',
                     'mmmc', 'dft', 'dv_targets', 'lsf'],
        '_help': {
            'hierarchy': '{"<block>": {"level": "DL1|DL2|DL3", "parent": "<block or empty>", '
                         '"children": [...], "description": "..."}} — one DL1 top',
            'block_inputs': '{"<leaf or any block>": {"rtl_filelist": "<.f>", "sdc": "<.sdc>", '
                            '"upf": "<optional>"}} — SYNTH inputs per block (phase-independent paths)',
            'library': 'base_tag: an existing base tag (cells) under lib_tag_root/<tech>/; '
                       'project_tag: default <NAME>_T1 (created empty; blocks added after their releases)',
            'paths': 'workarea / release / race_db outside the CBflow tree; release_disks optional',
        },
    }
    with open(a.out, 'w') as fh:
        json.dump(spec, fh, indent=2)
    print(f'spec template: {a.out}  (from {a.like}; ASK fields need the user; _assumed came from {a.like})')
    return 0


# ── check ───────────────────────────────────────────────────────────────────
def walk_ask(o, path=''):
    if o == ASK:
        yield path
    elif isinstance(o, dict):
        for k, v in o.items():
            if not k.startswith('_'):
                yield from walk_ask(v, f'{path}.{k}' if path else k)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            yield from walk_ask(v, f'{path}[{i}]')


def inside_repo(p):
    rp = os.path.realpath(p)
    return rp == ROOT or rp.startswith(ROOT + os.sep)


def check_spec(spec):
    """(missing, errors, warnings)"""
    missing = list(walk_ask(spec))
    errs, warns = [], []
    name = spec.get('name', '')
    if name != ASK:
        if not re.match(r'^[a-z][a-z0-9_]{1,31}$', name or ''):
            errs.append(f'name {name!r}: lowercase letters / digits / _, starting with a letter')
        if name in registry().get('projects', {}) or os.path.exists(proj_files(name)['global']):
            errs.append(f'project {name} already exists')
    rel = spec.get('cbflow_release')
    if rel and rel != ASK and not os.path.isfile(os.path.join(ROOT, 'global', 'releases', rel, 'MANIFEST.json')):
        errs.append(f'cbflow_release {rel}: no global/releases/{rel} (flow-manager skill: flowm.py status)')
    tech = spec.get('technology')
    if tech != ASK and not os.path.exists(os.path.join(ROOT, 'global', 'config', 'tech', tech or '_', 'v1.0.0',
                                                       'tech_config.tcl')):
        errs.append(f'technology {tech}: no global/config/tech/{tech}/v1.0.0/tech_config.tcl')
    reg = flow_registry()
    phases = spec.get('phases') or []
    if spec.get('current_phase') not in phases:
        errs.append(f'current_phase {spec.get("current_phase")} not in phases {phases}')
    for disc, flows in (spec.get('enabled_flows') or {}).items():
        for fl in flows:
            if reg['disc'].get(fl) != disc:
                errs.append(f'enabled_flows.{disc}: {fl} is not a {disc} flow '
                            f'(flow_registry: {reg["disc"].get(fl, "unknown")})')
    for fl, tool in (spec.get('default_tools') or {}).items():
        if tool not in tool_overlays(fl):
            errs.append(f'default_tools {fl} "{tool}": no node_configs/{fl}_{tool}_config.tcl '
                        f'(available: {", ".join(sorted(tool_overlays(fl))) or "none"})')
    for disc, plan in (spec.get('phase_exits') or {}).items():
        for ph, exits in plan.items():
            if ph not in phases:
                errs.append(f'phase_exits.{disc}: phase {ph} not in phases')
            for x in exits:
                if x not in reg['exits']:
                    errs.append(f'phase_exits.{disc}.{ph}: {x} is not an exit milestone')
                elif reg['exits'][x] != disc:
                    errs.append(f'phase_exits.{disc}.{ph}: {x} is a {reg["exits"][x]} exit')
    h = spec.get('hierarchy')
    if isinstance(h, dict):
        tops = [b for b, d in h.items() if not d.get('parent')]
        if len(tops) != 1:
            errs.append(f'hierarchy: exactly one top (no parent) — found {tops}')
        for b, d in h.items():
            if not re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', b):
                errs.append(f'hierarchy: block name {b!r}')
            if d.get('level') not in ('DL1', 'DL2', 'DL3'):
                errs.append(f'hierarchy.{b}.level {d.get("level")!r}: DL1 / DL2 / DL3')
            p = d.get('parent')
            if p and (p not in h or b not in h[p].get('children', [])):
                errs.append(f'hierarchy.{b}: parent {p} does not list it as a child')
            for c in d.get('children', []):
                if c not in h or h[c].get('parent') != b:
                    errs.append(f'hierarchy.{b}: child {c} missing or with another parent')
        if spec.get('top_module') not in (ASK, None) and tops and spec['top_module'] != tops[0]:
            errs.append(f'top_module {spec["top_module"]} is not the hierarchy top {tops[0]}')
        # SYNTH inputs per block: rtl_filelist + sdc, and upf when the reference
        # SYNTH user config sets one (the SYNTH flow config makes it mandatory)
        if 'SYNTH' in (spec.get('enabled_flows') or {}).get('PD', []):
            need = ['rtl_filelist', 'sdc']
            _, ruc = pick_uc(spec.get('like', ''), 'SYNTH', True) if spec.get('like') else (None, None)
            if ruc and re.search(r'^set\s+synth\(input,upf_file\)', open(ruc).read(), re.M):
                need.append('upf')
            for b in h:
                bi = (spec.get('block_inputs') or {}).get(b, {})
                for k in need:
                    if not bi.get(k):
                        missing.append(f'block_inputs.{b}.{k}')
                    elif not os.path.isfile(bi[k]):
                        errs.append(f'block_inputs.{b}.{k}: {bi[k]} does not exist')
    paths = spec.get('paths') or {}
    for k in ('workarea', 'release', 'race_db'):
        v = paths.get(k)
        if v and v != ASK:
            if not os.path.isabs(v):
                errs.append(f'paths.{k} {v}: absolute path')
            elif k != 'workarea' and inside_repo(v):
                errs.append(f'paths.{k} {v}: must be outside the CBflow tree {ROOT}')
    for k in ('lib_root', 'lib_tag_root'):
        v = paths.get(k)
        if v and v != ASK and not os.path.isdir(v):
            errs.append(f'paths.{k} {v}: not a directory')
    for d in paths.get('release_disks') or []:
        if not os.path.isdir(d):
            errs.append(f'paths.release_disks: {d} is not a directory')
    lib = spec.get('library') or {}
    if lib.get('base_tag') not in (ASK, None, '') and paths.get('lib_tag_root') not in (ASK, None) and tech != ASK:
        bt = os.path.join(paths['lib_tag_root'], tech, lib['base_tag'])
        if not os.path.isfile(os.path.join(bt, 'lib_config.tcl')):
            errs.append(f'library.base_tag {lib["base_tag"]}: no {bt}/lib_config.tcl (library-manager generate)')
        elif os.path.isfile(os.path.join(bt, 'blocks_config.tcl')):
            errs.append(f'library.base_tag {lib["base_tag"]} carries blocks (combined tag) — pick a cells-only base tag')
    m = spec.get('mmmc') or {}
    for c in m.get('process_corners', []):
        if c not in (m.get('pvt') or {}):
            errs.append(f'mmmc.pvt has no points for process corner {c}')
    if not m.get('rc_corners'):
        errs.append('mmmc.rc_corners empty')
    for k, v in (m.get('rc_corners') or {}).items():
        if not v or 'temperature' not in v:
            errs.append(f'mmmc.rc_corners.{k}: needs temperature + multipliers')
    return missing, errs, warns


def cmd_check(a):
    spec = json.load(open(a.spec))
    missing, errs, warns = check_spec(spec)
    for x in missing:
        print(f'ASK      {x}' + (f'   — {spec.get("_help", {}).get(x.split(".")[0], "")}'
                                 if x.split('.')[0] in spec.get('_help', {}) else ''))
    for e in errs:
        print(f'INVALID  {e}')
    for w in warns:
        print(f'WARN     {w}')
    for x in spec.get('_assumed', []):
        print(f'ASSUMED  {x} (from {spec.get("like")}) — confirm with the user')
    print(f'\n{len(missing)} to ask, {len(errs)} invalid, {len(warns)} warning(s)')
    return 1 if missing or errs else 0


# ── generate ────────────────────────────────────────────────────────────────
def tcl_word(v):
    s = str(v)
    return s if re.match(r'^[A-Za-z0-9_.,:/+\-*@%]+$', s) else '"' + s.replace('"', '\\"') + '"'


def tcl_list(vals):
    return '{' + ' '.join(str(x) for x in vals) + '}'


def replace_stmt(text, var, value_tcl):
    """Replace `set <var> <value>` (value braced / quoted / bare word, possibly
    multi-line) by `set <var> <value_tcl>`; appended when absent."""
    m = re.search(r'^(\s*)set\s+' + re.escape(var) + r'(\s+)', text, re.M)
    if not m:
        return text.rstrip('\n') + f'\nset {var} {value_tcl}\n'
    i = m.end()
    if text[i] == '{':
        depth, j = 0, i
        while j < len(text):
            depth += {'{': 1, '}': -1}.get(text[j], 0)
            if depth == 0:
                break
            j += 1
        end = j + 1
    elif text[i] == '"':
        end = text.index('"', i + 1) + 1
    else:
        end = i + len(re.match(r'\S+', text[i:]).group(0))
    eol = text.find('\n', end)
    tail = text[end:eol if eol >= 0 else len(text)]
    tail = tail if tail.strip().startswith(';#') else ''
    return text[:m.start()] + f'{m.group(1)}set {var}{m.group(2)}{value_tcl}{tail}' + text[eol if eol >= 0 else len(text):]


def remove_stmt(text, var):
    m = re.search(r'^\s*set\s+' + re.escape(var) + r'\s+', text, re.M)
    if not m:
        return text
    probe = replace_stmt(text, var, '@@CUT@@')
    return re.sub(r'^\s*set\s+' + re.escape(var) + r'\s+@@CUT@@[^\n]*\n?', '', probe, flags=re.M)


def render_dict(d, indent='    '):
    lines = ['{']
    for k, v in d.items():
        lines.append(f'{indent}{k} {tcl_list(v) if isinstance(v, list) else tcl_word(v)}')
    lines.append('}')
    return '\n'.join(lines)


def render_hierarchy(h):
    lines = ['{']
    for b, d in h.items():
        lines += [f'    {b} {{',
                  f'        description {tcl_word(d.get("description", b))}',
                  f'        level       "{d["level"]}"',
                  f'        parent      "{d.get("parent", "")}"',
                  f'        children    {tcl_list(d.get("children", []))}',
                  '    }']
    lines.append('}')
    return '\n'.join(lines)


def substitute_ref(text, ref, new):
    return re.sub(r'\b' + re.escape(ref) + r'\b', new, text)


def gen_project(spec, ref):
    f = proj_files(ref)
    name = spec['name']
    out = {}
    # global project config
    t = substitute_ref(open(f['global']).read(), ref, name)
    t = replace_stmt(t, 'project(name)', f'"{name}"')
    t = replace_stmt(t, 'project(phases)', tcl_list(spec['phases']))
    t = replace_stmt(t, 'project(current_phase)', f'"{spec["current_phase"]}"')
    for disc, plan in spec['phase_exits'].items():
        key = 'project(phase_exits)' if disc == 'PD' else f'project(phase_exits,{disc})'
        t = replace_stmt(t, key, render_dict(plan))
    for k in list(re.findall(r'^\s*set\s+(project\(signoff_chain,[^)]*\))', t, re.M)):
        t = remove_stmt(t, k)          # the chain is per project: write one when the flows run
    simple = {'project(description)': spec['description'], 'project(owner)': spec['owner'],
              'project(contact)': spec['contact'], 'project(technology)': spec['technology'],
              'project(vt_flavors)': spec['process']['vt_flavors'], 'project(top_module)': spec['top_module'],
              'project(tapeout_date)': spec['dates']['tapeout'],
              'project(power,vdd_net)': spec['power']['vdd_net'], 'project(power,vss_net)': spec['power']['vss_net'],
              'project(power,vdd_pin)': spec['power']['vdd_pin'], 'project(power,vss_pin)': spec['power']['vss_pin'],
              'project(pdn,enable)': spec['pdn_enable'],
              'project(cbflow_release)': spec['cbflow_release']}
    for k, v in simple.items():
        t = replace_stmt(t, k, f'"{v}"' if not re.match(r'^(true|false|\d+)$', str(v)) else str(v))
    t = replace_stmt(t, 'project(power,rail_nets)', tcl_list(spec['power']['rail_nets']))
    t = replace_stmt(t, 'project(sdc_modes)', tcl_list(list(spec['sdc_modes'])))
    t = replace_stmt(t, 'project(default_sdc_mode)', f'"{list(spec["sdc_modes"])[0]}"')
    for k in ('enable', 'max_chain_length', 'clock_mixing', 'scan_enable_pattern'):
        if k in spec['dft']:
            t = replace_stmt(t, f'project(dft,{k})', str(spec['dft'][k]))
    t = replace_stmt(t, 'project(design_hierarchy)', render_hierarchy(spec['hierarchy']))
    out[f'global/config/project/{name}/v1.0.0/{name}_config.tcl'] = t
    # PD overlay
    t = substitute_ref(open(f['PD']).read(), ref, name)
    p = spec['paths']
    for k, v in {'project(workarea_path)': p['workarea'], 'project(track_variant)': spec['process']['track_variant'],
                 'project(metal_stack)': spec['process']['metal_stack'], 'project(lib_root)': p['lib_root'],
                 'project(lib_tag_root)': p['lib_tag_root'],
                 'project(lib_config_tag)': spec['library'].get('project_tag') or spec['library']['base_tag'],
                 'project(race,db_path)': p['race_db'], 'project(release,path)': p['release'],
                 'project(release,phase)': spec['current_phase'], 'project(lsf,enabled)': spec['lsf']['enabled'],
                 'project(lsf,default_queue)': spec['lsf']['default_queue']}.items():
        t = replace_stmt(t, k, f'"{v}"')
    if p.get('release_disks'):
        t = replace_stmt(t, 'project(release,disks)', tcl_list(p['release_disks']))
    t = replace_stmt(t, 'project(default_tools)', render_dict(spec['default_tools']))
    for k in ('project(dashboard,org)', 'project(dashboard,developed_by)', 'project(dashboard,contact_email)'):
        t = remove_stmt(t, k)
    out[f'PD/config/project/{name}/v1.0.0/{name}_pd_config.tcl'] = t
    # DFT / DV overlays (RTL when the reference has one)
    if os.path.exists(f['DFT']):
        t = substitute_ref(open(f['DFT']).read(), ref, name)
        for k in ('scan_in_pattern', 'scan_out_pattern', 'atpg,test_coverage_min', 'atpg,fault_coverage_min'):
            if k in spec['dft']:
                t = replace_stmt(t, f'project(dft,{k})', str(spec['dft'][k]))
        out[f'DFT/config/project/{name}/v1.0.0/{name}_dft_config.tcl'] = t
    if os.path.exists(f['DV']):
        t = substitute_ref(open(f['DV']).read(), ref, name)
        for m, d in spec['dv_targets'].items():
            t = replace_stmt(t, f'project(dv,targets,{m})', '{' + ' '.join(f'{k} {v}' for k, v in d.items()) + '}')
        out[f'DV/config/project/{name}/v1.0.0/{name}_dv_config.tcl'] = t
    if os.path.exists(f['RTL']):
        out[f'RTL/config/project/{name}/v1.0.0/{name}_rtl_config.tcl'] = substitute_ref(open(f['RTL']).read(), ref, name)
    # MMMC config
    m = spec['mmmc']
    t = substitute_ref(open(f['mmmc']).read(), ref, name)
    for k, v in m['voltage'].items():
        t = replace_stmt(t, f'mmmc(voltage,{k})', str(v))
    for k, v in m['temperature'].items():
        t = replace_stmt(t, f'mmmc(temperature,{k})', str(v))
    t = replace_stmt(t, 'mmmc(process_corners)', tcl_list(m['process_corners']))
    for c in re.findall(r'^\s*set\s+mmmc\(pvt,(\w+)\)', t, re.M):
        if c not in m['pvt']:
            t = remove_stmt(t, f'mmmc(pvt,{c})')
    for c, pts in m['pvt'].items():
        t = replace_stmt(t, f'mmmc(pvt,{c})', '{' + ' '.join('{%s}' % ' '.join(x) for x in pts) + '}')
    rc = '{\n' + '\n'.join(f'    {k} {{\n' + '\n'.join(f'        {a:22s} {b}' for a, b in v.items()) + '\n    }'
                           for k, v in m['rc_corners'].items()) + '\n}'
    t = re.sub(r'array set rc_corners \{.*?\n\}\n', lambda _: f'array set rc_corners {rc}\n', t, count=1, flags=re.S)
    modes = '{\n' + '\n'.join(f'    {k} {{ constraint_file "{v}" }}' for k, v in spec['sdc_modes'].items()) + '\n}'
    t = re.sub(r'array set operating_modes \{.*?\n\}\n', lambda _: f'array set operating_modes {modes}\n', t, count=1,
               flags=re.S)
    out[f'global/config/project/{name}/v1.0.0/mmmc_config.tcl'] = t
    out[f'global/config/project/{name}/v1.0.0/mmmc_node_scenarios.tcl'] = gen_node_scenarios(spec, ref, f)
    out[f'global/config/project/{name}/v1.0.0/schedule_config.tcl'] = gen_schedule(spec)
    return out


def views_of(spec):
    m = spec['mmmc']
    out = []
    for mode in spec['sdc_modes']:
        for c in m['process_corners']:
            for v, t in m['pvt'].get(c, []):
                for rc in m['rc_corners']:
                    out.append({'name': f'{mode}_{c}_{v}_{rc}_{t}', 'mode': mode, 'corner': c, 'rc': rc})
    return out


def gen_node_scenarios(spec, ref, f):
    """Per-node setup / hold from the reference assignment, re-targeted to the new
    views by role: a reference view of process corner X / RC corner Y maps to the
    new views of X / Y (slow -> slow, fast -> fast, typical -> typical)."""
    ref_out = tcl(f'source {{{f["node_scen"]}}}\nforeach n [array names mmmc] {{ '
                  f'if {{[catch {{dict get $mmmc($n) setup}} s]}} continue\n'
                  f'puts "$n\\t$s\\t[dict get $mmmc($n) hold]" }}\n')
    new = views_of(spec)
    names = {v['name'] for v in new}

    def remap(views):
        out = []
        for rv in views.split():
            if rv in names:
                out.append(rv)
                continue
            p = rv.split('_')
            corner, rc = (p[1], '_'.join(p[3:-1])) if len(p) >= 5 else ('', '')
            cand = [v['name'] for v in new if v['corner'] == corner and v['rc'] == rc] or \
                   [v['name'] for v in new if v['corner'] == corner]
            out += [c for c in cand if c not in out]
        return out or [new[0]['name']]
    lines = ['#!/usr/bin/env tclsh', f'# Per-node MMMC scenarios — {spec["name"]} (project-kickoff from {ref};',
             '# re-targeted by role; review with: cbflow flow mmmc-manager list-scenarios / set-node)',
             'array set mmmc {']
    for line in sorted(l for l in ref_out.splitlines() if l.count('\t') == 2):
        n, s, h = line.split('\t')
        lines += [f'    {n} {{', '        setup {', *[f'            {x}' for x in remap(s)], '        }',
                  '        hold  {', *[f'            {x}' for x in remap(h)], '        }', '    }']
    lines.append('}')
    return '\n'.join(lines) + '\n'


def gen_schedule(spec):
    lines = ['# SmartGrid schedule (project-kickoff) — fill exit dates per phase',
             f'set schedule(start_date)             "{spec["dates"]["start"]}"',
             f'set schedule(tapeout_date)           "{spec["dates"]["tapeout"]}"',
             'set schedule(block_lead_days)        7']
    return '\n'.join(lines) + '\n'


def pick_uc(ref, flow, leaf):
    """A reference user config for <flow>: a block of the same kind (leaf / parent),
    the newest phase, the simplest name (uc_<FLOW>[_<tool>]_<phase>.tcl)."""
    reg = registry()['projects'].get(ref, {})
    hier = read_hierarchy(ref)
    blocks = [b for b, d in hier.items() if (not d['children']) == leaf] + list(hier)
    for b in blocks:
        cands = sorted(glob.glob(os.path.join(ROOT, 'workarea', b, f'uc_{flow}*.tcl')))
        simple = [c for c in cands if re.match(r'uc_' + flow + r'(_[a-z]+)?_P\d+\.tcl$', os.path.basename(c))]
        if simple:
            return b, sorted(simple, key=lambda c: re.findall(r'P(\d+)', c)[-1])[-1]
    return None, None


def read_hierarchy(p):
    out = tcl(f'source {{{proj_files(p)["global"]}}}\n'
              'dict for {b d} $project(design_hierarchy) { puts "$b\\t[dict get $d children]" }\n')
    return {l.split('\t')[0]: {'children': l.split('\t')[1].split()} for l in out.splitlines()}


def gen_workarea(spec, ref, ref_paths):
    """workarea/<block>/uc_<FLOW>[_tool]_<phase>.tcl per block x enabled flow
    (current phase), from the reference's user configs with the project, block,
    phase, paths and library tag substituted."""
    out, notes = {}, []
    name, ph = spec['name'], spec['current_phase']
    flows = [fl for d in DISCS for fl in spec['enabled_flows'].get(d, [])]
    ltag = spec['library'].get('project_tag') or spec['library']['base_tag']
    for b, d in spec['hierarchy'].items():
        leaf = not d.get('children')
        for fl in flows:
            rb, uc = pick_uc(ref, fl, leaf)
            if not uc:
                notes.append(f'{b}: no reference user config for {fl} — write workarea/{b}/uc_{fl}_{ph}.tcl by hand')
                continue
            t = open(uc).read()
            rph = re.search(r'_P(\d+)\.tcl$', uc).group(0)[1:-4]
            t = re.sub(r'^(set\s+project\(name\)\s+).*$', rf'\g<1>"{name}"', t, flags=re.M)
            t = re.sub(r'^(set\s+flow\(design_name\)\s+).*$', rf'\g<1>"{b}"', t, flags=re.M)
            t = re.sub(r'^(set\s+flow\(run_name\)\s+).*$', rf'\g<1>"{ph.lower()}_{fl.lower()}"', t, flags=re.M)
            t = re.sub(r'^(set\s+project\((?:release,)?phase\)\s+).*$', rf'\g<1>"{ph}"', t, flags=re.M)
            t = re.sub(r'^(set\s+project\(lib_config_tag\)\s+).*$', rf'\g<1>"{ltag}"', t, flags=re.M)
            t = re.sub(r'^set\s+flow\(test_mode\)\s+.*$', 'set flow(test_mode)            "false"', t, flags=re.M)
            t = t.replace(ref_paths['release'], spec['paths']['release'])
            t = re.sub(r'/' + re.escape(rph) + r'/' + re.escape(rb) + r'/', f'/{ph}/{b}/', t)
            t = re.sub(r'/' + re.escape(rb) + r'/' + re.escape(rph) + r'/', f'/{b}/{ph}/', t)
            t = re.sub(r'\b' + re.escape(rb) + r'(?=\b|_)', b, t)
            t = substitute_ref(t, ref, name)
            t = re.sub(r'\b' + re.escape(rph) + r'_', f'{ph}_', t)
            bi = (spec.get('block_inputs') or {}).get(b, {})
            if fl == 'SYNTH':
                arr = 'synth'
                for k, key in (('rtl_filelist', 'input,rtl_filelist'), ('sdc', 'input,sdc_func_file'),
                               ('upf', 'input,upf_file')):
                    if bi.get(k):
                        t = replace_stmt(t, f'{arr}({key})', f'"{bi[k]}"')
                    elif k != 'upf':
                        notes.append(f'{b}: SYNTH {k} not given — set {arr}({key}) in workarea/{b}/'
                                     f'{os.path.basename(uc).replace(rph, ph)}')
            stale = sorted(set(re.findall(r'/inputs/[^"\s]+', t)))
            for s_ in stale:
                notes.append(f'{b} {fl}: input path {s_} (from {ref}) — supply the {name} file')
            fn = os.path.basename(uc).replace(f'_{rph}.tcl', f'_{ph}.tcl')
            out[f'workarea/{b}/{fn}'] = (f'# {b} {fl} {ph} — project-kickoff from {os.path.relpath(uc, ROOT)}\n' + t)
    return out, notes


def cmd_generate(a):
    spec = json.load(open(a.spec))
    missing, errs, warns = check_spec(spec)
    if missing or errs:
        die(f'spec not ready ({len(missing)} to ask, {len(errs)} invalid) — run check')
    ref = spec['like']
    files = gen_project(spec, ref)
    ref_vals = read_reference(ref)['p']
    ref_paths = {'release': tcl(f'source {{{proj_files(ref)["PD"]}}}\nputs $project(release,path)').strip()}
    wa, notes = gen_workarea(spec, ref, ref_paths)
    if os.path.realpath(spec['paths']['workarea']) != os.path.join(ROOT, 'workarea'):
        wa = {k.replace('workarea/', '@WORKAREA@/', 1): v for k, v in wa.items()}
    files.update(wa)
    if os.path.exists(a.stage) and os.listdir(a.stage):
        die(f'stage dir {a.stage} is not empty')
    for rel, text in files.items():
        dst = os.path.join(a.stage, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, 'w') as fh:
            fh.write(text)
    entry = dict(registry()['projects'].get(ref, {}))
    entry.update({'name': spec['name'], 'description': spec['description'], 'chip_lead': spec['chip_lead'],
                  'technology': spec['technology'], 'status': 'active',
                  'created': datetime.datetime.now().isoformat(timespec='seconds'), 'phases': spec['phases'],
                  'project_start_date': spec['dates']['start'], 'tapeout_date': spec['dates']['tapeout'],
                  'enabled_flows_by_discipline': spec['enabled_flows'], 'milestone_targets': {},
                  'tags': [spec['technology']]})
    stage = {'project': spec['name'], 'technology': spec['technology'], 'registry_entry': entry,
             'workarea': spec['paths']['workarea'],
             'mkdirs': [spec['paths']['release'], spec['paths']['race_db'], spec['paths']['workarea']] +
                       [os.path.join(spec['paths']['workarea'], b) for b in spec['hierarchy']],
             'library': spec['library'], 'lib_tag_root': spec['paths']['lib_tag_root'],
             'notes': notes, 'warnings': warns, 'spec': os.path.abspath(a.spec)}
    with open(os.path.join(a.stage, 'STAGE.json'), 'w') as fh:
        json.dump(stage, fh, indent=2)
    print(f'Staged {len(files)} file(s) in {a.stage}:')
    for rel in sorted(files):
        print(f'  {rel}')
    for n in notes + warns:
        print(f'NOTE  {n}')
    return 0


# ── apply ───────────────────────────────────────────────────────────────────
def cmd_apply(a):
    st = json.load(open(os.path.join(a.stage, 'STAGE.json')))
    files = [os.path.relpath(os.path.join(dp, f), a.stage) for dp, _, fs in os.walk(a.stage) for f in fs
             if f not in ('STAGE.json', 'APPLIED.json')]
    targets = {rel: os.path.join(st['workarea'], rel.split('/', 1)[1]) if rel.startswith('@WORKAREA@/')
               else os.path.join(ROOT, rel) for rel in files}
    clash = [t for t in targets.values() if os.path.exists(t)]
    if clash:
        die('would overwrite: ' + ', '.join(clash))
    if st['project'] in registry().get('projects', {}):
        die(f'project {st["project"]} already in master_projects.json')
    made = []
    for d in st['mkdirs']:
        if not os.path.isdir(d):
            os.makedirs(d)
            made.append(d)
    for rel, dst in targets.items():
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(a.stage, rel), dst)
        made.append(dst)
    regp = os.path.join(ROOT, 'global', 'config', 'master_projects.json')
    reg = json.load(open(regp))
    reg.setdefault('projects', {})[st['project']] = st['registry_entry']
    tmp = regp + '.tmp'
    with open(tmp, 'w') as fh:
        json.dump(reg, fh, indent=2)
    os.replace(tmp, regp)
    made.append(f'{regp} (projects.{st["project"]})')
    # MMMC view definition, generated from the new mmmc_config
    vd = os.path.join(ROOT, 'global', 'config', 'project', st['project'], 'v1.0.0', 'mmmc_view_definition.tcl')
    r = subprocess.run([CB, 'flow', 'mmmc-manager', 'generate-view-def', '--style', 'flow', '--tech', st['technology'],
                        '--project', st['project'], '--output', vd], capture_output=True, text=True)
    print(('view definition: ' + vd) if r.returncode == 0 and os.path.exists(vd)
          else f'WARN  generate-view-def failed: {(r.stdout + r.stderr).strip()[-300:]}')
    if os.path.exists(vd):
        made.append(vd)
    # project library tag
    lib = st['library']
    if lib.get('project_tag'):
        r = subprocess.run([CB, 'flow', 'library-manager', 'project-tag', 'create', '--tech', st['technology'],
                            '--project', st['project'], '--tag', lib['project_tag'], '--base', lib['base_tag']],
                           capture_output=True, text=True)
        print(f'project tag {lib["project_tag"]}: ' + ('created' if r.returncode == 0 else
                                                       f'FAILED {(r.stdout + r.stderr).strip()[-300:]}'))
        if r.returncode == 0:
            made.append(os.path.join(st['lib_tag_root'], st['technology'], 'projects', st['project'],
                                     lib['project_tag']))
    with open(os.path.join(a.stage, 'APPLIED.json'), 'w') as fh:
        json.dump({'at': datetime.datetime.now().isoformat(timespec='seconds'), 'made': made}, fh, indent=2)
    print(f'Applied: {len(made)} item(s) (list in {a.stage}/APPLIED.json)')
    return 0


# ── validate ────────────────────────────────────────────────────────────────
def run(cmd, cwd=None, timeout=900):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout + r.stderr


def cmd_validate(a):
    p = a.project
    f = proj_files(p)
    results = []

    def res(name, ok, detail=''):
        results.append((name, ok, detail))
        print(f'[{"PASS" if ok else "FAIL"}] {name}' + (f' — {detail}' if detail else ''))
    srcs = ' '.join('{%s}' % f[k] for k in ['global', 'PD', 'DFT', 'DV', 'RTL', 'mmmc', 'node_scen'] if os.path.exists(f[k]))
    r = subprocess.run(['tclsh'], input=f'foreach f {{{srcs}}} {{ source $f }}\n'
                       'puts "$project(name) [llength [dict keys $project(design_hierarchy)]] blocks '
                       '[llength [array names analysis_views]] views"\n', capture_output=True, text=True)
    res('project configs source cleanly', r.returncode == 0, (r.stdout + r.stderr).strip()[-200:])
    tech = tcl(f'source {{{f["global"]}}}\nputs $project(technology)').strip()
    ltag = tcl(f'source {{{f["PD"]}}}\nputs $project(lib_config_tag)').strip()
    rc, o = run([CB, 'flow', 'project', 'info', '--name', p])
    res('cbflow flow project info', rc == 0, '' if rc == 0 else o.strip()[-200:])
    rc, o = run([CB, 'flow', 'mmmc-manager', 'validate', '--tech', tech, '--project', p, '--lib-tag', ltag])
    res('mmmc-manager validate', rc == 0, re.findall(r'(PASSED.*|FAILED.*)', o)[-1:] and re.findall(r'(PASSED.*|FAILED.*)', o)[-1] or o.strip()[-200:])
    rc, o = run([CB, 'flow', 'library-manager', 'check', '--tech', tech, '--project', p, '--lib_tag', ltag])
    res(f'library-manager check --lib_tag {ltag}', rc == 0, (re.findall(r'Overall: (.*)', o) or [o.strip()[-200:]])[-1])
    # smoke: SYNTH of a leaf block in test mode
    wa = tcl(f'source {{{f["PD"]}}}\nputs $project(workarea_path)').strip()
    hier = read_hierarchy(p)
    blk = a.smoke_block or next((b for b, d in hier.items() if not d['children']), None)
    ucs = sorted(glob.glob(os.path.join(wa, blk or '_', 'uc_SYNTH*.tcl')))
    if not ucs:
        res('smoke SYNTH (test mode)', False, f'no workarea/{blk}/uc_SYNTH*.tcl')
    else:
        smoke_uc = os.path.join(wa, blk, '.kickoff_smoke_uc.tcl')
        t = open(ucs[0]).read()
        t = re.sub(r'^set\s+flow\(test_mode\).*$', 'set flow(test_mode) "true"', t, flags=re.M)
        t = re.sub(r'^set\s+flow\(use_xterm\).*$', 'set flow(use_xterm) "false"', t, flags=re.M)
        t = re.sub(r'^set\s+flow\(use_lsf\).*$', 'set flow(use_lsf) "false"', t, flags=re.M)
        t = re.sub(r'^set\s+flow\(run_name\).*$', 'set flow(run_name) "kickoff_smoke"', t, flags=re.M)
        with open(smoke_uc, 'w') as fh:
            fh.write(t)
        before = set(glob.glob(os.path.join(wa, blk, '*_run_SYNTH_*')))
        rc, o = run([CB, 'workspace', 'create', '--config', smoke_uc], cwd=os.path.join(wa, blk))
        new = sorted(set(glob.glob(os.path.join(wa, blk, '*_run_SYNTH_*'))) - before)
        if rc or not new:
            res('smoke SYNTH (test mode): workspace create', False, o.strip()[-300:])
        else:
            rc, o = run([CB, 'run', 'all'], cwd=new[0], timeout=1800)
            ok = 'result=PASS' in o
            res(f'smoke SYNTH (test mode) {blk}', ok, os.path.basename(new[0]) if ok else o.strip()[-300:])
            if not a.keep_smoke:
                run([CB, 'run', 'db-manage', '--delete', os.path.basename(new[0])], cwd=os.path.join(wa, blk))
                shutil.rmtree(new[0], ignore_errors=True)
        os.remove(smoke_uc)
    bad = [r for r in results if not r[1]]
    print(f'\n{len(results) - len(bad)}/{len(results)} passed')
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('template')
    p.add_argument('--like', required=True)
    p.add_argument('--name')
    p.add_argument('--out', required=True)
    p = sub.add_parser('check')
    p.add_argument('--spec', required=True)
    p = sub.add_parser('generate')
    p.add_argument('--spec', required=True)
    p.add_argument('--stage', required=True)
    p = sub.add_parser('apply')
    p.add_argument('--stage', required=True)
    p = sub.add_parser('validate')
    p.add_argument('--project', required=True)
    p.add_argument('--smoke-block')
    p.add_argument('--keep-smoke', action='store_true')
    a = ap.parse_args()
    return {'template': cmd_template, 'check': cmd_check, 'generate': cmd_generate, 'apply': cmd_apply,
            'validate': cmd_validate}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
