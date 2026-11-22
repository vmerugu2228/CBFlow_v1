#!/usr/bin/env python3
"""No-hardcoding scanner for CBflow code.

CBflow rule: definitions that belong in config (node names, versions,
disciplines, exit milestones, phases, release layout, design names, power
nets / layers) must not be hardcoded in code, and code must not fall back
silently to a literal when config is missing.  This module scans code
(never config) for the common shapes of those violations.

Used two ways:
  * static-suite category "hardcode" (test_suite/static_checks.py)
  * script mode, for fixers and CI:

        python3 global/utils/commands/test_suite/hardcode_scan.py \
            [--rule RULE[,RULE]] [--summary] [--all] [--root DIR]

    exits 1 when non-allowlisted findings exist.

Allowlist: test_suite/hardcode_allowlist.txt, one entry per line:
    <rule> <repo-relative-path>:<line|*>   # reason
Keep it for genuinely central definitions only.

What is scanned / skipped
  * code: *.py *.tcl *.sh *.html *.js plus extension-less launchers in
    */bin (language from the shebang) under SCAN_ROOTS.
  * skipped: any */config/** dir, test_suite/ itself, docs, __pycache__.
  * stripped before matching: Tcl/shell '#' comments, Python comments and
    docstrings, JS/HTML comments, and the string arguments of message /
    help calls (print, log_*, puts, echo, argparse help=/epilog=, raise
    Error(...), ...) so prose mentioning e.g. "BTO" doesn't count.
"""

import argparse
import io
import os
import re
import sys
import tokenize
from collections import OrderedDict, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
# test_suite → commands → utils → global → <repo>
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
ALLOWLIST_PATH = os.path.join(HERE, 'hardcode_allowlist.txt')

SCAN_ROOTS = (
    'global/utils', 'global/bin',
    'PD/utils', 'PD/cmds', 'PD/bin',
    'DFT/cmds', 'DFT/utils', 'DFT/bin',
    'DV/cmds', 'DV/utils', 'DV/bin',
    'RTL/cmds', 'RTL/utils', 'RTL/bin',
)
CODE_EXT = {'.py': 'py', '.tcl': 'tcl', '.sh': 'sh', '.html': 'html', '.js': 'js'}
SKIP_DIR_NAMES = {'config', 'test_suite', 'docs', 'doc', '__pycache__', 'node_modules', '.git'}
# Test harnesses assert on fixture literals (BTO, LC1, ...) by design.
TEST_FILE_RX = re.compile(r'(?:^|/)(?:test_[^/]*\.py|[^/]*_test\.py|test_suite\.py|cbflow-verify)$')

# rule id → one-line description (order = report order)
RULES = OrderedDict([
    ('node-name',       'literal node name used as node identity (use cbflow_node_name / CBFLOW_NODE_NAME)'),
    ('node-path',       'path into another node by literal node name (use cbflow_upstream_node / cbflow_node_dir)'),
    ('version-default', 'literal version (v1.0.0) used as a default (use cbflow_version / registry.config_version)'),
    ('discipline-list', 'discipline list or discipline default in code (use cbflow_disciplines / registry.flow_disciplines)'),
    ('exit-literal',    'exit milestone name hardcoded in logic (read release/exit config)'),
    ('phase-literal',   'project phase literal (P0..P9 / LC1..LC9) in logic (read project(phases))'),
    ('release-layout',  'release path assembled by hand from phase + tag (use release_dir / cbflow_release_dir)'),
    ('design-default',  'silent design-name default (design / chip_top / pnr ...) (use cbflow_require)'),
    ('pd-net-layer',    'power-net or metal-layer literal as fallback value in PD cmds (read tech/project config)'),
])

PD_EXITS = ('FP_EXIT', 'PLACE_EXIT', 'CTS_EXIT', 'PRO_EXIT', 'BTO', 'MTO')


# ── File discovery ──────────────────────────────────────────────────────────

def _sniff_lang(path):
    try:
        with open(path, 'rb') as fh:
            first = fh.readline(200).decode('utf-8', 'replace')
    except OSError:
        return None
    if not first.startswith('#!'):
        return None
    if 'python' in first:
        return 'py'
    if 'tclsh' in first or 'wish' in first:
        return 'tcl'
    if re.search(r'\b(ba|z|k)?sh\b', first):
        return 'sh'
    return None


def iter_code_files(root=REPO_ROOT):
    """Yield (abs_path, rel_path, lang) for every code file in scope."""
    for sub in SCAN_ROOTS:
        base = os.path.join(root, sub)
        if not os.path.isdir(base):
            continue
        in_bin = sub.endswith('/bin')
        for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIR_NAMES
                                 and not d.startswith('.'))
            for fn in sorted(filenames):
                path = os.path.join(dirpath, fn)
                if TEST_FILE_RX.search(fn):
                    continue
                if os.path.islink(path):
                    continue          # launcher symlinks: scanned at their target
                ext = os.path.splitext(fn)[1]
                lang = CODE_EXT.get(ext)
                if lang in ('html', 'js'):
                    # web assets only under templates/ or static/
                    parts = os.path.relpath(path, root).split(os.sep)
                    if not ({'templates', 'static'} & set(parts)):
                        continue
                if lang is None and in_bin and not ext:
                    lang = _sniff_lang(path)
                if lang is None:
                    continue
                yield path, os.path.relpath(path, root).replace(os.sep, '/'), lang


# ── Comment / docstring / message stripping ─────────────────────────────────

_PY_MSG_FUNCS = {
    'print', 'debug', 'info', 'warning', 'warn', 'error', 'critical',
    'exception', 'log', 'fail', 'die', 'abort', 'echo', 'secho', 'notice',
    '_log', '_info', '_warn', '_warning', '_error', '_die', '_fail', '_print',
    'log_info', 'log_warn', 'log_warning', 'log_error', 'log_debug',
    'event', 'section', 'passed', 'failed', 'skipped', 'add_argument',
    'add_parser', 'ArgumentParser', 'add_argument_group', 'add_mutually_exclusive_group',
    'write', 'emit', 'status', 'note', 'ok', 'success',
}
_PY_MSG_KWARGS = {'help', 'epilog', 'description', 'usage', 'msg', 'message', 'title', 'metavar'}
_STRING_START = {tokenize.STRING}
for _n in ('FSTRING_START', 'TSTRING_START'):
    if hasattr(tokenize, _n):
        _STRING_START.add(getattr(tokenize, _n))
_STRING_END = {getattr(tokenize, n) for n in ('FSTRING_END', 'TSTRING_END') if hasattr(tokenize, n)}


def _blank_span(text, lines_off, start, end):
    """Replace span with '' keeping newlines (line numbers stay stable)."""
    s = lines_off[start[0] - 1] + start[1]
    e = lines_off[end[0] - 1] + end[1]
    return s, e, '""' + '\n' * text.count('\n', s, e)


def strip_python(text):
    """Remove comments, docstrings and message-call string args."""
    lines = text.splitlines(keepends=True)
    offs, acc = [], 0
    for ln in lines:
        offs.append(acc)
        acc += len(ln)
    offs.append(acc)
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, SyntaxError, IndentationError):
        return '\n'.join(re.sub(r'(^|\s)#.*$', r'\1', l.rstrip('\n')) for l in lines)

    edits = []
    # stack of booleans: is this paren group a message call?
    paren_msg = []
    prev_sig = None          # previous significant token
    prev_prev = None
    kw_msg_pending = False   # saw `help=` → next string expression is message
    stmt_start = True        # at the start of a logical line
    i, n = 0, len(toks)
    while i < n:
        tok = toks[i]
        tt, ts = tok.type, tok.string
        if tt == tokenize.COMMENT:
            s = offs[tok.start[0] - 1] + tok.start[1]
            e = offs[tok.end[0] - 1] + tok.end[1]
            edits.append((s, e, ''))
            i += 1
            continue
        if tt in (tokenize.NL, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT):
            if tt in (tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT):
                stmt_start = True
            i += 1
            continue
        if tt in _STRING_START:
            # collect the whole string (implicit concatenation included)
            start = tok.start
            j = i
            end = tok.end
            while j < n:
                t = toks[j]
                if t.type == tokenize.STRING:
                    end = t.end
                    j += 1
                elif t.type in _STRING_START:   # f-string: consume to matching END
                    depth = 0
                    while j < n:
                        if toks[j].type in _STRING_START and toks[j].type != tokenize.STRING:
                            depth += 1
                        elif toks[j].type in _STRING_END:
                            depth -= 1
                            if depth == 0:
                                end = toks[j].end
                                j += 1
                                break
                        j += 1
                elif t.type == tokenize.NL:
                    j += 1
                else:
                    break
                # continue only if the next significant token is another string
                k = j
                while k < n and toks[k].type == tokenize.NL:
                    k += 1
                if k < n and toks[k].type in _STRING_START:
                    j = k
                    continue
                break
            nxt = toks[j] if j < n else None
            is_doc = stmt_start and (nxt is None or nxt.type in (tokenize.NEWLINE, tokenize.ENDMARKER))
            in_msg = kw_msg_pending or (paren_msg and paren_msg[-1])
            if is_doc or in_msg:
                edits.append(_blank_span(text, offs, start, end))
            stmt_start = False
            prev_prev, prev_sig = prev_sig, toks[j - 1]
            i = j
            continue
        stmt_start = False
        if tt == tokenize.OP:
            if ts in '([{':
                is_call = (ts == '(' and prev_sig is not None and prev_sig.type == tokenize.NAME)
                name = prev_sig.string if is_call else ''
                is_raise = (is_call and prev_prev is not None and prev_prev.string == 'raise')
                parent = paren_msg[-1] if paren_msg else False
                paren_msg.append(parent or kw_msg_pending or
                                 (is_call and (name in _PY_MSG_FUNCS or is_raise
                                               or name.startswith(('print', 'log_'))
                                               or name.endswith(('Error', 'Exception', 'Warning')))))
                kw_msg_pending = False
            elif ts in ')]}':
                if paren_msg:
                    paren_msg.pop()
                kw_msg_pending = False
            elif ts == '=' and prev_sig is not None and prev_sig.type == tokenize.NAME \
                    and prev_sig.string in _PY_MSG_KWARGS and paren_msg:
                kw_msg_pending = True
            elif ts == ',':
                kw_msg_pending = False
        prev_prev, prev_sig = prev_sig, tok
        i += 1

    out = text
    for s, e, rep in sorted(edits, reverse=True):
        out = out[:s] + rep + out[e:]
    return out


_DQ_STR = re.compile(r'"(?:[^"\\]|\\.)*"')
_SQ_STR = re.compile(r"'(?:[^'\\]|\\.)*'")

_TCL_MSG = re.compile(
    r'(?:^\s*|[;{\[]\s*)(?:puts(?!\s+(?:-nonewline\s+)?\$(?!::)\w)|error|warning|log_\w+|\w+_log|\w*_(?:warn|info|error|msg|message|die|fail)'
    r'|cbflow_\w*(?:warn|info|error|msg)\w*|msg\w*|print_\w+|return\s+-code\s+error)\b')
_SH_MSG = re.compile(
    r'(?:^\s*|[;&|{(]\s*|\bthen\s+|\belse\s+|\bdo\s+)(?:echo|printf|log_\w+|\w+_log|die|fail|warn|info|error|usage)\b')


def _blank_strings_from(line, pos, pat=_DQ_STR):
    head, tail = line[:pos], line[pos:]
    return head + pat.sub('""', tail)


def strip_tcl(text):
    out = []
    for raw in text.split('\n'):
        s = raw.lstrip()
        if s.startswith('#'):
            out.append('')
            continue
        line = re.sub(r';\s*#.*$', '', raw)
        m = _TCL_MSG.search(line)
        if m:
            line = _blank_strings_from(line, m.start())
        out.append(line)
    return '\n'.join(out)


def strip_sh(text):
    out = []
    heredoc = None
    for raw in text.split('\n'):
        if heredoc:
            out.append('')
            if raw.strip() == heredoc:
                heredoc = None
            continue
        s = raw.lstrip()
        if s.startswith('#'):
            out.append('')
            continue
        line = raw
        # trailing comment: ' #' outside quotes (approximate: even quote count before it)
        for m in re.finditer(r'\s#', line):
            before = line[:m.start()]
            if before.count('"') % 2 == 0 and before.count("'") % 2 == 0:
                line = before
                break
        hm = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", line)
        if hm and re.match(r'\s*(cat|echo)\b', line):
            heredoc = hm.group(1)
        m = _SH_MSG.search(line)
        if m:
            line = _blank_strings_from(line, m.start())
            line = _blank_strings_from(line, m.start(), _SQ_STR)
        out.append(line)
    return '\n'.join(out)


def strip_web(text):
    # block comments (keep newlines)
    text = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    text = re.sub(r'<!--.*?-->', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    out = []
    for raw in text.split('\n'):
        s = raw.lstrip()
        if s.startswith('//'):
            out.append('')
            continue
        line = re.sub(r'(^|[\s;{}])//\s.*$', r'\1', raw)
        m = re.search(r'\bconsole\.\w+\s*\(|\balert\s*\(', line)
        if m:
            line = _blank_strings_from(line, m.start())
            line = _blank_strings_from(line, m.start(), _SQ_STR)
        out.append(line)
    return '\n'.join(out)


STRIPPERS = {'py': strip_python, 'tcl': strip_tcl, 'sh': strip_sh,
             'html': strip_web, 'js': strip_web}


# ── Rules ───────────────────────────────────────────────────────────────────

Q = r'''["']'''
LIT = r'[A-Za-z_][A-Za-z0-9_]*?'
STAGEVAR = r'(?:stage|stage_name|STAGE_NAME|stage_type|STAGE|stg|st|s)'
DISC = r'(?:PD|DFT|DV|RTL)'


def _exit_names(root):
    names = set(PD_EXITS)
    d = os.path.join(root, 'global', 'config', 'exit', 'v1.0.0')
    if os.path.isdir(d):
        for fn in os.listdir(d):
            if not fn.endswith('_config.tcl'):
                continue
            try:
                with open(os.path.join(d, fn), encoding='utf-8', errors='replace') as fh:
                    for ln in fh:
                        m = re.match(r'\s*set\s+milestone_info\(name\)\s+"?([A-Z0-9_]+)"?', ln)
                        if m:
                            names.add(m.group(1))
            except OSError:
                pass
    return sorted(names, key=lambda x: (-len(x), x))


def build_rules(root=REPO_ROOT):
    """Return {rule_id: [(compiled_regex, langs_or_None, path_prefixes_or_None)]}."""
    exits = '|'.join(re.escape(e) for e in _exit_names(root))
    nl = r'(?<![A-Za-z0-9_])'
    nr = r'(?![A-Za-z0-9_])'
    pd_lit = r'(?:VDD\w*|VSS\w*|VPWR|VGND|VCC|GND|M(?:1[0-9]?|[2-9])|metal(?:1[0-9]?|[2-9])|met[1-5]|li1)'
    design_lit = r'(?:design|chip_top|pnr|top|my_design|block|unknown_design|DESIGN|TOP)'
    R = {
        'node-name': [
            # Tcl: set NODE_NAME "${STAGE_NAME}1" | set node_name "place1"
            (re.compile(r'\bset\s+(?:::)?(?:NODE_NAME|node_name|node)\s+"?(?:\$\{?' + STAGEVAR
                        + r'\}?|' + LIT + r')1"?\s*(?:$|[;}\]])'), ('tcl',), None),
            # Tcl ternary default:  ... ? $::env(CBFLOW_NODE_NAME) : "release_data1"
            (re.compile(r'NODE_NAME\b[^\n]*:\s*"' + LIT + r'1"'), ('tcl',), None),
            # Tcl proc default:  proc x {... {node_name "place1"}}
            (re.compile(r'\{\s*node_name\s+"?' + LIT + r'1"?\s*\}'), ('tcl',), None),
            # Python: node_name = 'place1' / f'{stage}1' ; .get('node_name', 'x1') ; or 'x1'
            (re.compile(r'\b\w*node(?:_name)?\w*\s*(?:=|:)\s*f?' + Q + r'(?:\{' + STAGEVAR + r'\}|'
                        + LIT + r')1' + Q), ('py', 'js'), None),
            (re.compile(r'\.get\(\s*' + Q + r'\w*node\w*' + Q + r'\s*,\s*f?' + Q + r'[^\'"]*1' + Q),
             ('py',), None),
            (re.compile(r'\bnode\w*\b[^\n#]*\bor\s+f?' + Q + r'(?:\{' + STAGEVAR + r'\}|' + LIT + r')1' + Q),
             ('py',), None),
            # stage-derived node identity: f'{stage}1', stage + '1', "${stage}1"
            (re.compile(r'f' + Q + r'\{' + STAGEVAR + r'\}1' + Q), ('py',), None),
            (re.compile(r'\b' + STAGEVAR + r'\s*\+\s*' + Q + r'1' + Q), ('py', 'js'), None),
            (re.compile(r'`\$\{' + STAGEVAR + r'\}1`'), ('js', 'html'), None),
            (re.compile(r'"\$\{?' + STAGEVAR + r'\}?1"'), ('tcl', 'sh'), None),
        ],
        'node-path': [
            (re.compile(r'work/[^\s/\'"\]]+/[a-z][a-z0-9_]*[a-z_]1(?=/|["\'\s\]}]|$)'), None, None),
            (re.compile(Q + r'work' + Q + r'\s*,[^)\n]*' + Q + r'[a-z][a-z0-9_]*[a-z_]1' + Q), ('py',), None),
            (re.compile(r'file\s+join\s+[^\]\n]*\bwork\b[^\]\n]*\s[a-z][a-z0-9_]*[a-z_]1(?=[\s\]])'),
             ('tcl',), None),
        ],
        'version-default': [
            # (Tcl `variable version "vX"` = a module's own revision tag, not a default)
            (re.compile(r'^(?!\s*variable\s+version\b).*' + Q + r'v\d+\.\d+\.\d+' + Q), None, None),
            (re.compile(r':[-=]v\d+\.\d+\.\d+\b'), ('sh', 'tcl'), None),
            (re.compile(r'\bset\s+\S+\s+v\d+\.\d+\.\d+\s*$'), ('tcl',), None),
            (re.compile(r'^\s*(?:export\s+)?\w+=v\d+\.\d+\.\d+\b'), ('sh',), None),
        ],
        'discipline-list': [
            (re.compile(Q + DISC + Q + r'\s*,\s*' + Q + DISC + Q), ('py', 'js', 'html'), None),
            (re.compile(r'\{\s*' + DISC + r'(?:\s+' + DISC + r')+\s*\}'), ('tcl',), None),
            (re.compile(r'\blist\s+' + DISC + r'(?:\s+' + DISC + r')+\b'), ('tcl',), None),
            (re.compile(nl + DISC + r'\s+' + DISC + nr), ('sh',), None),
            (re.compile(r'\b(?:or|return)\s+' + Q + DISC + Q), ('py', 'js'), None),
            (re.compile(r'\.get\([^()\n]*,\s*' + Q + DISC + Q + r'\s*\)'), ('py', 'js'), None),
            (re.compile(r'\|\|\s*' + Q + DISC + Q), ('js', 'html'), None),
            (re.compile(r'\breturn\s+"?' + DISC + r'"?\s*$'), ('tcl', 'sh'), None),
            (re.compile(r'\?[^:\n]*:\s*"' + DISC + r'"'), ('tcl',), None),
            (re.compile(r'\$\{\w+:-' + DISC + r'\}'), ('sh',), None),
        ],
        'exit-literal': [
            (re.compile(nl + r'(?:' + exits + r')' + nr), None, None),
        ],
        'phase-literal': [
            (re.compile(Q + r'(?:P[0-9]|LC[1-9])' + Q), None, None),
            (re.compile(r'\{\s*(?:P[0-9]|LC[1-9])(?:\s+(?:P[0-9]|LC[1-9]))+\s*\}'), ('tcl',), None),
            (re.compile(r'(?:\beq|\bne|==|!=)\s+(?:P[0-9]|LC[1-9])' + nr), ('tcl',), None),
            (re.compile(r'\bset\s+\S*phase\S*\s+(?:P[0-9]|LC[1-9])\s*$'), ('tcl',), None),
        ],
        'release-layout': [],   # handled by _release_layout()
        'design-default': [
            (re.compile(r'(?:design|top|block)\w*\b[^\n]*\bor\s+' + Q + design_lit + Q), ('py', 'js'), None),
            (re.compile(r'\.get\(\s*' + Q + r'[^\'"]*(?:design|top_module|block_name)[^\'"]*' + Q
                        + r'\s*,\s*' + Q + design_lit + Q + r'\s*\)'), ('py',), None),
            (re.compile(r'(?:design|DESIGN|top|TOP)\w*\b[^\n]*\?[^:\n]*:\s*"' + design_lit + r'"'),
             ('tcl',), None),
            (re.compile(r'\$\{\w*(?:DESIGN|design|TOP_MODULE|BLOCK)\w*:-[^}]+\}'), ('sh',), None),
            (re.compile(r'\bset\s+(?:::)?(?:DESIGN_NAME|design_name|design|top_module|TOP|top_name)\s+"?'
                        + design_lit + r'"?\s*(?:$|[;}\]])'), ('tcl',), None),
            (re.compile(r'\{\s*(?:design_name|design|top)\s+"?' + design_lit + r'"?\s*\}'), ('tcl',), None),
        ],
        'pd-net-layer': [
            (re.compile(r'\?[^:\n]*:\s*"?' + pd_lit + r'"?\s*[\]})]'), ('tcl',), ('PD/cmds/',)),
            (re.compile(r'(?:eq\s*""|info\s+exists)[^\n]*\bset\s+\S+\s+"?' + pd_lit + r'"?\s*\}'),
             ('tcl',), ('PD/cmds/',)),
            (re.compile(r'\.get\([^()\n]*,\s*' + Q + pd_lit + Q + r'\s*\)'), ('py',), ('PD/cmds/',)),
            (re.compile(r'\bor\s+' + Q + pd_lit + Q), ('py',), ('PD/cmds/',)),
        ],
    }
    return R


_PHASE_TOK = r'(?:phase\w*|PHASE\w*|\w+_phase|\w+_PHASE)'
_TAG_TOK = r'(?:\w*tag\w*|\w*TAG\w*|\w*exit\w*|\w*EXIT\w*|milestone\w*|MILESTONE\w*)'
_RL_PY_JOIN = re.compile(r'(?:os\.path\.join|Path)\(([^\n]*)')
_RL_PY_F = re.compile(r'f(["\'])(.*?)\1')
_RL_DOLLAR = re.compile(r'"([^"\n]*\$[^"\n]*)"|\[file\s+join\s+([^\]\n]*)\]')
_RL_SKIP = re.compile(r'release_dir|cbflow_release_dir|release_exits')


def _release_layout(line, lang):
    if _RL_SKIP.search(line):
        return None
    has = lambda s, tok: re.search(r'(?<![A-Za-z0-9])' + tok + r'(?![A-Za-z0-9])', s)
    if lang == 'py':
        for m in _RL_PY_JOIN.finditer(line):
            seg = m.group(1)
            if has(seg, _PHASE_TOK) and has(seg, _TAG_TOK):
                return m.group(0)
        for m in _RL_PY_F.finditer(line):
            seg = m.group(2)
            if '/' in seg and re.search(r'\{' + _PHASE_TOK + r'\}', seg) and re.search(r'\{' + _TAG_TOK + r'\}', seg):
                return m.group(0)
    elif lang in ('tcl', 'sh'):
        for m in _RL_DOLLAR.finditer(line):
            seg = m.group(1) or m.group(2) or ''
            if ('/' in seg or m.group(2)) and re.search(r'\$\{?' + _PHASE_TOK, seg) \
                    and re.search(r'\$\{?(?:::)?' + _TAG_TOK, seg):
                return m.group(0)
    elif lang in ('js', 'html'):
        for m in re.finditer(r'`([^`\n]*)`', line):
            seg = m.group(1)
            if '/' in seg and re.search(r'\$\{' + _PHASE_TOK + r'\}', seg) and re.search(r'\$\{' + _TAG_TOK + r'\}', seg):
                return m.group(0)
    return None


# ── Scanning ────────────────────────────────────────────────────────────────

_FUNC_RX = {
    'py': re.compile(r'\s*(?:async\s+)?def\s+(\w+)'),
    'tcl': re.compile(r'\s*proc\s+(\S+)'),
    'sh': re.compile(r'\s*(?:function\s+)?(\w+)\s*\(\)\s*\{'),
    'js': re.compile(r'\s*(?:async\s+)?function\s+(\w+)'),
    'html': re.compile(r'\s*(?:async\s+)?function\s+(\w+)'),
}


class Finding(tuple):
    """(rule, rel_path, line_no, snippet, enclosing def/proc name)"""
    __slots__ = ()

    def __new__(cls, rule, path, line, snippet, func=''):
        return tuple.__new__(cls, (rule, path, line, snippet, func))

    rule = property(lambda s: s[0])
    path = property(lambda s: s[1])
    line = property(lambda s: s[2])
    snippet = property(lambda s: s[3])
    func = property(lambda s: s[4])

    def fmt(self):
        return f'{self.path}:{self.line}: [{self.rule}] {self.snippet}'


def scan_file(path, rel, lang, rules, only=None):
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            text = fh.read()
    except OSError:
        return []
    raw_lines = text.split('\n')
    code = STRIPPERS[lang](text).split('\n')
    func_rx = _FUNC_RX.get(lang)
    func = ''
    out = []
    for idx, line in enumerate(code):
        if func_rx:
            fm = func_rx.match(line)
            if fm:
                func = fm.group(1).split('::')[-1]
        if not line.strip():
            continue
        lineno = idx + 1
        snippet = raw_lines[idx].strip()[:160] if idx < len(raw_lines) else line.strip()[:160]
        for rule, pats in rules.items():
            if only and rule not in only:
                continue
            hit = False
            for rx, langs, prefixes in pats:
                if langs and lang not in langs:
                    continue
                if prefixes and not rel.startswith(prefixes):
                    continue
                if rx.search(line):
                    hit = True
                    break
            if not hit and rule == 'release-layout' and _release_layout(line, lang):
                hit = True
            if hit:
                out.append(Finding(rule, rel, lineno, snippet, func))
    return out


def scan(root=REPO_ROOT, only=None):
    rules = build_rules(root)
    findings = []
    for path, rel, lang in iter_code_files(root):
        findings.extend(scan_file(path, rel, lang, rules, only))
    return findings


# ── Allowlist ───────────────────────────────────────────────────────────────

def load_allowlist(path=ALLOWLIST_PATH):
    """Return list of (rule, path, line_or_'*', reason, source_lineno)."""
    entries = []
    if not os.path.isfile(path):
        return entries
    with open(path, encoding='utf-8') as fh:
        for no, raw in enumerate(fh, 1):
            body, _, reason = raw.partition('#')
            body = body.strip()
            if not body:
                continue
            parts = body.split()
            if len(parts) != 2 or ':' not in parts[1]:
                raise ValueError(f'{path}:{no}: malformed allowlist entry: {raw.rstrip()}')
            rule, loc = parts
            fpath, _, ln = loc.rpartition(':')
            if rule not in RULES and rule != '*':
                raise ValueError(f'{path}:{no}: unknown rule {rule!r}')
            entries.append((rule, fpath, ln, reason.strip(), no))
    return entries


def split_allowed(findings, allowlist):
    """Return (violations, allowed, unused_allowlist_entries)."""
    used = set()
    viol, allowed = [], []
    for f in findings:
        ok = False
        for i, (rule, fpath, ln, _, _) in enumerate(allowlist):
            if rule not in ('*', f.rule) or fpath != f.path:
                continue
            if ln == '*' or ln == str(f.line) or (ln.startswith('@') and ln[1:] == f.func):
                ok = True
                used.add(i)
                break
        (allowed if ok else viol).append(f)
    unused = [e for i, e in enumerate(allowlist) if i not in used]
    return viol, allowed, unused


def group_by_rule(findings):
    g = OrderedDict((r, []) for r in RULES)
    for f in findings:
        g.setdefault(f.rule, []).append(f)
    return g


# ── CLI ─────────────────────────────────────────────────────────────────────

def main(argv=None):
    ap = argparse.ArgumentParser(
        description='Scan CBflow code for hardcoded config definitions and silent fallbacks.')
    ap.add_argument('--rule', help='Comma-separated rule ids (default: all). '
                                   'Rules: ' + ', '.join(RULES))
    ap.add_argument('--summary', action='store_true', help='Counts per rule (and top files) only')
    ap.add_argument('--all', action='store_true', help='Also list allowlisted findings')
    ap.add_argument('--root', default=REPO_ROOT, help='Repo root (default: auto)')
    ap.add_argument('--allowlist', default=ALLOWLIST_PATH, help='Allowlist file')
    args = ap.parse_args(argv)

    only = None
    if args.rule:
        only = {r.strip() for r in args.rule.split(',') if r.strip()}
        bad = only - set(RULES)
        if bad:
            ap.error(f'unknown rule(s): {", ".join(sorted(bad))}')

    findings = scan(args.root, only)
    allow = load_allowlist(args.allowlist)
    viol, allowed, unused = split_allowed(findings, allow)

    grouped = group_by_rule(viol)
    for rule, items in grouped.items():
        if only and rule not in only:
            continue
        print(f'== {rule}: {len(items)}  — {RULES[rule]}')
        if args.summary:
            per_file = defaultdict(int)
            for f in items:
                per_file[f.path] += 1
            for p, c in sorted(per_file.items(), key=lambda x: (-x[1], x[0]))[:5]:
                print(f'     {c:4d}  {p}')
            if len(per_file) > 5:
                print(f'     ...   ({len(per_file)} files)')
        else:
            for f in items:
                print('  ' + f.fmt())
    if args.all and allowed:
        print(f'== allowlisted: {len(allowed)}')
        for f in allowed:
            print('  ' + f.fmt())
    for rule, fpath, ln, reason, no in unused:
        if not only or rule in only:
            print(f'[WARN] stale allowlist entry (line {no}): {rule} {fpath}:{ln}')
    print(f'TOTAL: {len(viol)} finding(s) not allowlisted, {len(allowed)} allowlisted')
    return 1 if viol else 0


if __name__ == '__main__':
    sys.exit(main())
