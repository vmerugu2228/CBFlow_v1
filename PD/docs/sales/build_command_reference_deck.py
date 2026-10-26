#!/usr/bin/env python3
"""
Build CBflow_Command_Reference_Deck.pptx — per-command deep reference.

Each command gets its own slide with:
    - SYNTAX             — usage line with placeholders
    - OPTIONS            — flag / type / description table
    - EXAMPLE            — copy-pasteable transcript
    - PRODUCES / NOTES   — what it emits + gotchas

Contents (~33 slides):
     1  Title
     2  Command tree overview
   3-6  workspace: create, status, list-runs+validate, clean
  7-15  run: all, status, retrace, add-node+create-branch, release,
             release-check, gui+dashboard, force+bypass, db-manage
 16-17  flow info: types+info+stages+nodes, check+version
 18-21  library-manager: scan, generate, check+list, status+coverage
 22-23  mmmc-manager: list-corners, generate
 24-27  checklist: list+list-checks, generate+status,
                    sign-off+waiver, add-check+remove-check
 28-29  smartgenie: interactive+one-shot+search, setup+ingest+server
    30  migrate
    31  project-dashboard
 32-33  reference: env vars, gotchas

Same SmartSoC palette + fonts + geometry as the methodology deck.
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

# ── Palette ─────────────────────────────────────────────────────────────
GREEN       = RGBColor(0x00, 0xD7, 0x00)
GREEN_DARK  = RGBColor(0x00, 0x7A, 0x00)
GREEN_TINT  = RGBColor(0xF3, 0xFF, 0xF3)
BLUE        = RGBColor(0x00, 0x00, 0xFF)
BLUE_DARK   = RGBColor(0x1E, 0x3A, 0x8A)
BLUE_TINT   = RGBColor(0xEB, 0xEB, 0xFF)
INK         = RGBColor(0x0F, 0x14, 0x1B)
BODY        = RGBColor(0x33, 0x39, 0x46)
MUTED       = RGBColor(0x6B, 0x72, 0x80)
WHITE       = RGBColor(0xFF, 0xFF, 0xFF)
LINE        = RGBColor(0xE5, 0xE7, 0xEB)
PANEL       = RGBColor(0xF9, 0xFA, 0xFB)
AMBER       = RGBColor(0xF5, 0x9E, 0x0B)
AMBER_DARK  = RGBColor(0xB4, 0x53, 0x09)
AMBER_TINT  = RGBColor(0xFE, 0xF3, 0xC7)
RED_DARK    = RGBColor(0xB9, 0x1C, 0x1C)

FONT = 'Montserrat'
MONO = 'Courier New'
SW = Inches(13.333)
SH = Inches(7.5)
TOTAL_SLIDES = 33


# ── Helpers ─────────────────────────────────────────────────────────────
def _apply_font(run, name=FONT, size=None, bold=None, color=None):
    run.font.name = name
    if size is not None: run.font.size = Pt(size)
    if bold is not None: run.font.bold = bold
    if color is not None: run.font.color.rgb = color

def add_text(slide, left, top, width, height, text,
             size=14, bold=False, color=BODY, align=PP_ALIGN.LEFT,
             anchor=MSO_ANCHOR.TOP, font=FONT):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.margin_left = Emu(0); tf.margin_right = Emu(0)
    tf.margin_top = Emu(0); tf.margin_bottom = Emu(0)
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    lines = text.split('\n') if isinstance(text, str) else text
    for i, ln in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        r = p.add_run(); r.text = ln
        _apply_font(r, name=font, size=size, bold=bold, color=color)
    return tb

def add_rect(slide, left, top, width, height, fill=None, line=None, line_w=None):
    shp = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    shp.shadow.inherit = False
    if fill is None: shp.fill.background()
    else: shp.fill.solid(); shp.fill.fore_color.rgb = fill
    if line is None: shp.line.fill.background()
    else:
        shp.line.color.rgb = line
        if line_w is not None: shp.line.width = line_w
    shp.text_frame.text = ''
    return shp

def add_pill(slide, left, top, width, height, text,
             fill=GREEN_TINT, color=GREEN_DARK, size=10, bold=True):
    shp = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    shp.shadow.inherit = False
    shp.fill.solid(); shp.fill.fore_color.rgb = fill
    shp.line.fill.background()
    shp.adjustments[0] = 0.5
    tf = shp.text_frame
    tf.margin_left = Emu(0); tf.margin_right = Emu(0)
    tf.margin_top = Emu(0); tf.margin_bottom = Emu(0)
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
    r = p.add_run(); r.text = text
    _apply_font(r, size=size, bold=bold, color=color)
    return shp

def add_header(slide, kicker, title, subtitle=None, footer_page=None):
    add_rect(slide, 0, 0, SW, Inches(0.05), fill=GREEN)
    add_text(slide, Inches(0.5), Inches(0.22), Inches(11), Inches(0.3),
             kicker, size=12, bold=True, color=MUTED)
    add_text(slide, Inches(0.5), Inches(0.52), Inches(12.3), Inches(0.55),
             title, size=22, bold=True, color=INK)
    if subtitle:
        add_text(slide, Inches(0.5), Inches(1.12), Inches(12.3), Inches(0.4),
                 subtitle, size=13, bold=False, color=MUTED)
    add_text(slide, Inches(0.5), Inches(7.15), Inches(9), Inches(0.25),
             'CBflow · Command Reference   ·   SmartSoC Solutions',
             size=10, color=MUTED)
    if footer_page:
        add_text(slide, Inches(12.5), Inches(7.15), Inches(0.7), Inches(0.25),
                 f'{footer_page}/{TOTAL_SLIDES}', size=10, bold=True, color=MUTED,
                 align=PP_ALIGN.RIGHT)


# ─────────────────────────────────────────────────────────────────────
# COMMAND-DETAIL SLIDE FACTORY
#
# Every command slide has the same shape so the reader learns the
# layout once and can flip through fast:
#
#   ┌ HEADER (kicker + title + subtitle) ───────────────────────────┐
#   ├─────────────────────────────┬─────────────────────────────────┤
#   │ SYNTAX (mono, green box)    │ EXAMPLE (mono, dark box)        │
#   ├─────────────────────────────┤                                 │
#   │ OPTIONS (flag / type / desc)│                                 │
#   │                             ├─────────────────────────────────┤
#   │                             │ PRODUCES / NOTES / GOTCHAS      │
#   └─────────────────────────────┴─────────────────────────────────┘
# ─────────────────────────────────────────────────────────────────────
def command_slide(section, cmd_name, purpose, syntax, options,
                  example, produces, notes, page,
                  section_color=GREEN_DARK):
    s = prs.slides.add_slide(blank)
    add_header(s, section,
               f'{cmd_name}  —  {purpose}',
               footer_page=page)

    # ── SYNTAX box (top-left) ────────────────────────────────────────
    sx_x = Inches(0.5); sx_y = Inches(1.65); sx_w = Inches(6.15); sx_h = Inches(1.5)
    add_rect(s, sx_x, sx_y, sx_w, sx_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
    add_rect(s, sx_x, sx_y, sx_w, Inches(0.36), fill=section_color)
    add_text(s, sx_x + Inches(0.15), sx_y + Inches(0.07),
             sx_w - Inches(0.3), Inches(0.24),
             'SYNTAX', size=12, bold=True, color=WHITE, font=MONO)
    # Syntax lines
    sy = sx_y + Inches(0.48)
    for line in syntax:
        add_text(s, sx_x + Inches(0.2), sy, sx_w - Inches(0.4), Inches(0.28),
                 line, size=12, bold=True, color=section_color, font=MONO)
        sy += Inches(0.30)

    # ── OPTIONS box (middle-left) ────────────────────────────────────
    op_x = sx_x; op_y = sx_y + sx_h + Inches(0.14)
    op_h = Inches(3.65)
    add_rect(s, op_x, op_y, sx_w, op_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
    add_rect(s, op_x, op_y, sx_w, Inches(0.36), fill=section_color)
    add_text(s, op_x + Inches(0.15), op_y + Inches(0.07),
             sx_w - Inches(0.3), Inches(0.24),
             'OPTIONS', size=12, bold=True, color=WHITE, font=MONO)
    # Options table header
    hdr_y = op_y + Inches(0.46)
    add_text(s, op_x + Inches(0.2), hdr_y, Inches(1.8), Inches(0.24),
             'FLAG', size=10, bold=True, color=MUTED, font=MONO)
    add_text(s, op_x + Inches(2.1), hdr_y, Inches(0.9), Inches(0.24),
             'TYPE', size=10, bold=True, color=MUTED, font=MONO)
    add_text(s, op_x + Inches(3.1), hdr_y, sx_w - Inches(3.3), Inches(0.24),
             'DESCRIPTION', size=10, bold=True, color=MUTED, font=MONO)
    # Options rows
    oy = hdr_y + Inches(0.3)
    for flag, otype, desc in options:
        add_text(s, op_x + Inches(0.2), oy, Inches(1.9), Inches(0.28),
                 flag, size=10, bold=True, color=section_color, font=MONO)
        add_text(s, op_x + Inches(2.1), oy, Inches(0.95), Inches(0.28),
                 otype, size=10, color=MUTED, font=MONO)
        add_text(s, op_x + Inches(3.1), oy, sx_w - Inches(3.3), Inches(0.4),
                 desc, size=10, color=BODY)
        oy += Inches(0.36)

    # ── EXAMPLE box (top-right) ──────────────────────────────────────
    ex_x = Inches(6.8); ex_y = Inches(1.65); ex_w = Inches(6.05); ex_h = Inches(3.35)
    add_rect(s, ex_x, ex_y, ex_w, ex_h, fill=INK, line=None)
    add_text(s, ex_x + Inches(0.15), ex_y + Inches(0.09),
             ex_w - Inches(0.3), Inches(0.24),
             'EXAMPLE', size=12, bold=True, color=AMBER, font=MONO)
    ey = ex_y + Inches(0.44)
    for line, col in example:
        add_text(s, ex_x + Inches(0.2), ey, ex_w - Inches(0.4), Inches(0.26),
                 line, size=11, color=col, font=MONO)
        ey += Inches(0.28)

    # ── PRODUCES / NOTES box (bottom-right) ──────────────────────────
    nt_x = ex_x; nt_y = ex_y + ex_h + Inches(0.14); nt_h = Inches(2.0)
    add_rect(s, nt_x, nt_y, ex_w, nt_h, fill=AMBER_TINT, line=AMBER_DARK, line_w=Pt(0.75))
    add_text(s, nt_x + Inches(0.15), nt_y + Inches(0.09),
             ex_w - Inches(0.3), Inches(0.24),
             'PRODUCES  ·  NOTES', size=12, bold=True, color=AMBER_DARK, font=MONO)
    ny = nt_y + Inches(0.44)
    for line in produces + notes:
        add_text(s, nt_x + Inches(0.25), ny, ex_w - Inches(0.4), Inches(0.30),
                 '·  ' + line, size=11, color=BODY)
        ny += Inches(0.30)


# ═══════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════
prs = Presentation()
prs.slide_width = SW; prs.slide_height = SH
blank = prs.slide_layouts[6]


# ── SLIDE 1: TITLE ─────────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_rect(s, 0, 0, Inches(0.4), SH, fill=GREEN)
add_rect(s, Inches(0.4), 0, Inches(0.15), SH, fill=BLUE)

add_text(s, Inches(1.0), Inches(2.0), Inches(11.5), Inches(1.4),
         'CBflow', size=64, bold=True, color=INK)
add_text(s, Inches(1.0), Inches(3.0), Inches(11.5), Inches(1.4),
         'Command Reference.', size=48, bold=True, color=GREEN_DARK)

add_text(s, Inches(1.0), Inches(4.3), Inches(11.5), Inches(0.5),
         'Every subcommand, every option, worked examples.',
         size=18, color=BODY)

# Topic pills
pills_top = Inches(5.3)
topics = ['WORKSPACE', 'RUN', 'FLOW', 'LIB-MGR',
          'MMMC-MGR', 'CHECKLIST', 'SMARTGENIE', 'MIGRATE']
px = Inches(1.0)
for t in topics:
    w = Inches(0.15 + 0.09 * len(t))
    add_pill(s, px, pills_top, w, Inches(0.32), t,
             fill=GREEN_TINT, color=GREEN_DARK, size=9)
    px += w + Inches(0.1)

add_text(s, Inches(1.0), Inches(6.5), Inches(11), Inches(0.3),
         f'SmartSoC Solutions   ·   {TOTAL_SLIDES} slides',
         size=11, color=MUTED)


# ── SLIDE 2: COMMAND TREE OVERVIEW ─────────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'OVERVIEW',
           'The cbflow command tree',
           subtitle='Every family runs from a specific working directory. Each command in this deck gets its own detailed slide.',
           footer_page=2)

CX = Inches(6.665)
root_y = Inches(1.75); root_w = Inches(2.0); root_h = Inches(0.5)
add_rect(s, CX - root_w / 2, root_y, root_w, root_h, fill=INK, line=None)
add_text(s, CX - root_w / 2, root_y + Inches(0.13), root_w, Inches(0.3),
         '$ cbflow', size=15, bold=True, color=WHITE,
         align=PP_ALIGN.CENTER, font=MONO)

families = [
    ('workspace',       'workarea/<design>/',  GREEN_DARK,
     ['create', 'status', 'list-runs', 'validate', 'clean']),
    ('run',             'run directory',        GREEN,
     ['all', 'status', 'retrace', 'add-node', 'create-branch',
      'release', 'release-check', 'gui', 'force', 'bypass', 'db-manage']),
    ('flow',            'anywhere',             BLUE,
     ['types', 'info', 'stages', 'nodes', 'check', 'version',
      'library-manager', 'mmmc-manager', 'checklist']),
    ('smartgenie',      'anywhere',             BLUE_DARK,
     ['(interactive)', 'setup', 'ingest', 'search', 'server']),
    ('migrate',         'anywhere',             AMBER_DARK,
     ['--old <old.tcl>', '--new <new.tcl>', '--dry-run']),
    ('project-dashboard','anywhere',             AMBER,
     ['start', 'stop', 'status', '--list-users']),
    ('run dashboard',   'run directory',        MUTED,
     ['logs --follow']),
]
fam_top = Inches(2.7); fam_h = Inches(2.05)
fam_w = Inches(3.0); fam_gap = Inches(0.1)
for i, (name, where, color, subs) in enumerate(families):
    row = i // 4
    col = i % 4
    x = Inches(0.5) + col * (fam_w + fam_gap)
    y = fam_top + row * (fam_h + Inches(0.15))
    add_rect(s, x, y, fam_w, fam_h, fill=WHITE, line=color, line_w=Pt(1.5))
    add_rect(s, x, y, fam_w, Inches(0.38), fill=color)
    add_text(s, x, y + Inches(0.06), fam_w, Inches(0.26),
             name, size=13, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, font=MONO)
    add_text(s, x + Inches(0.15), y + Inches(0.44), fam_w - Inches(0.3), Inches(0.22),
             f'run from: {where}', size=9, color=MUTED, font=MONO)
    sy = y + Inches(0.72)
    for sub in subs:
        add_text(s, x + Inches(0.2), sy, fam_w - Inches(0.3), Inches(0.22),
                 '· ' + sub, size=10, color=BODY, font=MONO)
        sy += Inches(0.18)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: WORKSPACE  (slides 3-6)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 3: workspace create ─────────────────────────────────────────
command_slide(
    section='WORKSPACE · CREATE',
    cmd_name='workspace create',
    purpose='Create a new run directory from a user config',
    syntax=[
        '$ cd workarea/<design_name>/',
        '$ cbflow workspace create --config <uc_FLOW.tcl>',
        '                          [--force]',
    ],
    options=[
        ('--config',   '<file>',    'user config tcl (uc_<FLOW>_<tool>.tcl)'),
        ('--force',    'flag',      'recreate the run directory if it already exists'),
        ('--dry-run',  'flag',      'validate the config without creating anything'),
    ],
    example=[
        ('$ cd workarea/cpu_core', MUTED),
        ('$ cp $CBFLOW_CORE_DIR/config/templates/uc_PNR_innovus.tcl \\', WHITE),
        ('    my_pnr.tcl', WHITE),
        ('$ vi my_pnr.tcl    # edit inputs, run_name, ...', MUTED),
        ('$ cbflow workspace create --config my_pnr.tcl', GREEN),
        ('  Creating run: P0_run_PNR_test1', MUTED),
        ('  Validating user_config...  OK', MUTED),
        ('  Resolving inputs...        OK', MUTED),
        ('  Generating .run.cbflow.tcl OK', MUTED),
        ('  Run directory ready.', GREEN),
    ],
    produces=[
        'Creates <phase>_run_<FLOW>_<name>/ under the workarea',
        'Generates .run.cbflow.tcl + .run.cbflow.env',
        'Registers the run with the dashboard daemon',
    ],
    notes=[
        'Must be run from inside workarea/<design>/',
        'Phase from project(current_phase) unless overridden',
    ],
    page=3, section_color=GREEN_DARK,
)

# ── SLIDE 4: workspace status ─────────────────────────────────────────
command_slide(
    section='WORKSPACE · STATUS',
    cmd_name='workspace status',
    purpose='Inspect the workspace and its runs (read-only)',
    syntax=[
        '$ cbflow workspace status',
        '$ cbflow workspace status --run <N>',
        '$ cbflow workspace status --run <N> --summary',
    ],
    options=[
        ('--run',      '<N>',       'target run number (from list-runs)'),
        ('--summary',  'flag',      'expand with timing / errors / metrics'),
        ('--json',     'flag',      'machine-readable output'),
    ],
    example=[
        ('$ cbflow workspace status', GREEN),
        ('  Workspace: /projects/bumblebee/workarea/cpu_core', MUTED),
        ('  Runs: 3', MUTED),
        ('    #1  P0_run_SYNTH_PNR_baseline  READY  (3/13)', GREEN),
        ('    #2  P0_run_STA_signoff         RUNNING (7/13)', BLUE),
        ('    #3  P0_run_PV_final            FAIL   at drc1', RED_DARK),
        ('', WHITE),
        ('$ cbflow workspace status --run 2 --summary', GREEN),
        ('  Stage: cts_opt1  RUNNING  ETA 12m', WHITE),
        ('  WNS setup: -0.024 ns   WNS hold: +0.012 ns', WHITE),
        ('  Congestion: 2.1%       Scenarios: 48/48', WHITE),
    ],
    produces=[
        'Table of runs with state, progress, ETA',
        '--summary adds live metrics from the run\'s SQLite DB',
    ],
    notes=[
        'Read-only — safe to run from any user',
        'Ownership not enforced for status queries',
    ],
    page=4, section_color=GREEN_DARK,
)

# ── SLIDE 5: workspace list-runs + validate ──────────────────────────
command_slide(
    section='WORKSPACE · LIST-RUNS + VALIDATE',
    cmd_name='workspace list-runs  /  validate',
    purpose='Enumerate every run  ·  sanity-check the workspace config',
    syntax=[
        '$ cbflow workspace list-runs [--filter <state>]',
        '$ cbflow workspace validate',
    ],
    options=[
        ('--filter',   '<state>',   'READY | RUNNING | PASS | FAIL | STALE'),
        ('--sort',     '<key>',     'created | name | state'),
        ('--verbose',  'flag',      'more detail (owner, elapsed)'),
    ],
    example=[
        ('$ cbflow workspace list-runs', GREEN),
        ('  ┌────┬─────────────────────────┬─────────┬──────────┐', MUTED),
        ('  │ ID │ NAME                    │ STATE   │ OWNER    │', WHITE),
        ('  ├────┼─────────────────────────┼─────────┼──────────┤', MUTED),
        ('  │  1 │ P0_run_SYNTH_PNR_base   │ PASS    │ alice    │', WHITE),
        ('  │  2 │ P0_run_STA_signoff      │ RUNNING │ bob      │', WHITE),
        ('  │  3 │ P0_run_PV_final         │ FAIL    │ alice    │', WHITE),
        ('  └────┴─────────────────────────┴─────────┴──────────┘', MUTED),
        ('', WHITE),
        ('$ cbflow workspace validate', GREEN),
        ('  Checking user_configs...      OK (3 files)', WHITE),
        ('  Checking release consistency...OK', WHITE),
        ('  Workspace: VALID', GREEN),
    ],
    produces=[
        'list-runs: table of runs with ID, name, state, owner',
        'validate: consistency report across user_configs',
    ],
    notes=[
        'validate catches template drift before "workspace create"',
        'list-runs is what "cbflow workspace status" iterates over',
    ],
    page=5, section_color=GREEN_DARK,
)

# ── SLIDE 6: workspace clean ──────────────────────────────────────────
command_slide(
    section='WORKSPACE · CLEAN',
    cmd_name='workspace clean',
    purpose='Delete run directories (destructive — requires --confirm)',
    syntax=[
        '$ cbflow workspace clean --confirm',
        '$ cbflow workspace clean --run <N> --confirm',
        '$ cbflow workspace clean --older-than <days> --confirm',
    ],
    options=[
        ('--confirm',    'flag',      'required — destructive op guard'),
        ('--run',        '<N>',       'clean only a specific run'),
        ('--older-than', '<days>',    'clean runs older than N days'),
        ('--keep-passed','flag',      'preserve runs in PASS state'),
        ('--dry-run',    'flag',      'list what would be deleted, delete nothing'),
    ],
    example=[
        ('$ cbflow workspace clean --dry-run', GREEN),
        ('  Would delete 5 run directories:', WHITE),
        ('    P0_run_SYNTH_PNR_baseline    (STALE, 42d old)', MUTED),
        ('    P0_run_STA_smoke             (FAIL, 12d old)', MUTED),
        ('    ...', MUTED),
        ('  Total size: 187 GB. Nothing deleted (--dry-run).', WHITE),
        ('', WHITE),
        ('$ cbflow workspace clean --keep-passed --confirm', GREEN),
        ('  Deleting 3 non-passing runs...', WHITE),
        ('    P0_run_STA_smoke ... done', GREEN),
        ('    P0_run_PV_debug  ... done', GREEN),
        ('  Reclaimed: 132 GB', GREEN),
    ],
    produces=[
        'Deletes matching run directories from disk',
        'Deregisters the runs from the dashboard daemon',
    ],
    notes=[
        'Destructive — always dry-run first',
        'Only the run owner (or workspace admin) can clean',
        '--keep-passed is the safer default for cleanup jobs',
    ],
    page=6, section_color=RED_DARK,
)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: RUN  (slides 7-15)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 7: run all ──────────────────────────────────────────────────
command_slide(
    section='RUN · ALL',
    cmd_name='run all',
    purpose='Execute the complete flow end-to-end',
    syntax=[
        '$ cbflow run all',
        '$ cbflow run all --from <stage>',
        '$ cbflow run all --to <stage>',
        '$ cbflow run all --from <stage> --to <stage>',
    ],
    options=[
        ('--from',    '<stage>',   'start execution from this stage (inclusive)'),
        ('--to',      '<stage>',   'stop execution at this stage (inclusive)'),
        ('--parallel','<N>',       'max concurrent LSF jobs (default: from lsf_config)'),
        ('--dry-run', 'flag',      'print the DAG that would run; execute nothing'),
        ('--verbose', 'flag',      'stream per-stage log tails to stdout'),
    ],
    example=[
        ('$ cd P0_run_SYNTH_PNR_test1/', MUTED),
        ('$ cbflow run all', GREEN),
        ('  RACE engine started (PID 12345)', WHITE),
        ('  Scheduling 13 stages...', WHITE),
        ('  rtl1        DONE  (0.4s)', GREEN),
        ('  sdc1        DONE  (0.2s)', GREEN),
        ('  upf1        DONE  (0.3s)', GREEN),
        ('  init_design1 DONE (2m 14s)  →  FP_EXIT gate', GREEN),
        ('  synthesis1  RUNNING (LSF job 4471082)', BLUE),
        ('  ...', MUTED),
        ('  release_data1 DONE (0.9s)', GREEN),
        ('  All 13 stages PASSED. Elapsed 1h 47m.', GREEN),
    ],
    produces=[
        'Populates work/<FLOW>/<stage>/{run,log,reports}/',
        'Writes stage_metrics + jobs rows to run\'s SQLite DB',
        'Emits output_manifest.tcl at release_data1',
    ],
    notes=[
        'Ownership: only the run creator can execute',
        'Retrace-from-stage auto-invalidates downstream',
    ],
    page=7, section_color=GREEN,
)

# ── SLIDE 8: run status ───────────────────────────────────────────────
command_slide(
    section='RUN · STATUS',
    cmd_name='run status',
    purpose='Current DAG state — per-stage progress and metrics',
    syntax=[
        '$ cbflow run status',
        '$ cbflow run status --details',
        '$ cbflow run status --json',
    ],
    options=[
        ('--details',  'flag',      'per-stage breakdown with elapsed + owner'),
        ('--stage',    '<name>',    'zoom in on one stage'),
        ('--json',     'flag',      'machine-readable (for scripts)'),
        ('--watch',    'flag',      'live-refresh every 2s'),
    ],
    example=[
        ('$ cbflow run status', GREEN),
        ('  Run: P0_run_SYNTH_PNR_test1', WHITE),
        ('  Progress: 8/13 stages   (61%)', WHITE),
        ('  Current:  cts_opt1  RUNNING', BLUE),
        ('  WNS pre-CTS: -0.037 ns   Congestion: 1.8%', WHITE),
        ('', WHITE),
        ('$ cbflow run status --details --stage cts_opt1', GREEN),
        ('  Stage:    cts_opt1', WHITE),
        ('  Type:     cts_opt', WHITE),
        ('  Subnodes: setup=DONE  run=RUNNING  validate=WAIT  finish=WAIT', WHITE),
        ('  LSF:      job 4471147, queue L, 8h wall', WHITE),
        ('  Elapsed:  22m 14s (of ~45m estimated)', WHITE),
    ],
    produces=[
        'Terminal table of stages + state (color-coded)',
        '--details adds subnode-level breakdown + LSF ids',
    ],
    notes=[
        'Read-only — anyone can query',
        '--watch is handy during long CTS/route runs',
    ],
    page=8, section_color=GREEN,
)

# ── SLIDE 9: run retrace ──────────────────────────────────────────────
command_slide(
    section='RUN · RETRACE',
    cmd_name='run retrace',
    purpose='Re-run from a stage — downstream auto-invalidated',
    syntax=[
        '$ cbflow run retrace --from <stage>',
        '$ cbflow run retrace --from <stage> --to <stage>',
    ],
    options=[
        ('--from',     '<stage>',   'first stage to re-run (required)'),
        ('--to',       '<stage>',   'last stage (optional — defaults to end)'),
        ('--preserve', '<stage>',   'DO NOT invalidate this stage (advanced)'),
        ('--dry-run',  'flag',      'show what would run; execute nothing'),
    ],
    example=[
        ('# RTL team pushed a new netlist', MUTED),
        ('$ cp new_netlist.v inputs/cpu_core.v', WHITE),
        ('', WHITE),
        ('$ cbflow run retrace --from synthesis1', GREEN),
        ('  Invalidating stages downstream of synthesis1:', WHITE),
        ('    synthesis1  place1  cts1  cts_opt1  route1', MUTED),
        ('    pro1  signoff1  export_data1  release_data1', MUTED),
        ('  Re-running from synthesis1...', WHITE),
        ('  synthesis1  RUNNING (LSF 4471203)', BLUE),
        ('  ...', MUTED),
        ('  All 10 stages re-executed. Elapsed 1h 22m.', GREEN),
    ],
    produces=[
        'Marks downstream stages as INVALID in the run DB',
        'Re-executes from --from through --to (or end)',
    ],
    notes=[
        'Ownership required',
        'Prefer this over deleting stamps or running individual stages',
        'Handshake tags (release_tag) auto-refresh downstream flows',
    ],
    page=9, section_color=GREEN,
)

# ── SLIDE 10: run add-node + create-branch ────────────────────────────
command_slide(
    section='RUN · ADD-NODE + CREATE-BRANCH',
    cmd_name='run add-node  /  run create-branch',
    purpose='Add a new stage to the live DAG  ·  fork a branch for what-if',
    syntax=[
        '$ cbflow run add-node --node <name> --type <type> --dep <parent>',
        '$ cbflow run create-branch --branch <name> --from <stage>',
    ],
    options=[
        ('--node',    '<name>',    'unique node name (add-node)'),
        ('--type',    '<type>',    'node type: place, cts, route, ...'),
        ('--dep',     '<parent>',  'upstream dependency (add-node)'),
        ('--branch',  '<name>',    'branch label (create-branch)'),
        ('--from',    '<stage>',   'stage to fork from (create-branch)'),
    ],
    example=[
        ('# add a second placement iteration:', MUTED),
        ('$ cbflow run add-node \\', GREEN),
        ('    --node place2 \\', GREEN),
        ('    --type place \\', GREEN),
        ('    --dep place1', GREEN),
        ('  DAG updated: place2 depends on place1', WHITE),
        ('', WHITE),
        ('# fork a branch for timing_fix experiments:', MUTED),
        ('$ cbflow run create-branch \\', GREEN),
        ('    --branch timing_fix \\', GREEN),
        ('    --from cts1', GREEN),
        ('  Branch timing_fix forked at cts1 (snapshot)', WHITE),
        ('  Switch back with: cbflow run branch --checkout main', MUTED),
    ],
    produces=[
        'add-node: new DAG row + subnode dirs under work/<FLOW>/<node>/',
        'create-branch: snapshot of run state at --from',
    ],
    notes=[
        'Ownership required for both',
        'Branches share the release_tag pool with main',
    ],
    page=10, section_color=GREEN,
)

# ── SLIDE 11: run release ─────────────────────────────────────────────
command_slide(
    section='RUN · RELEASE',
    cmd_name='run release',
    purpose='Publish run outputs as a release_tag for downstream flows',
    syntax=[
        '$ cbflow run release --tag <TAG>',
        '$ cbflow run release --tag <TAG> --project <name>',
    ],
    options=[
        ('--tag',      '<TAG>',     'milestone tag (P0_BTO, PLACE_EXIT, ...)'),
        ('--project',  '<name>',    'override project (defaults to project(name))'),
        ('--dry-run',  'flag',      'assemble manifest, do not publish'),
        ('--force',    'flag',      'overwrite an existing release (guarded)'),
    ],
    example=[
        ('# publish BTO release from a completed run:', MUTED),
        ('$ cbflow run release --tag P0_BTO', GREEN),
        ('  Assembling manifest...', WHITE),
        ('    netlist:  work/PNR/release_data1/out/cpu_core.pt.v', WHITE),
        ('    sdc:      work/PNR/release_data1/out/cpu_core.func.sdc', WHITE),
        ('    def:      work/PNR/release_data1/out/cpu_core.def', WHITE),
        ('    upf:      work/PNR/release_data1/out/cpu_core.upf', WHITE),
        ('  Copying to: releases/bumblebee/cpu_core/P0_BTO/', WHITE),
        ('  Writing MANIFEST.json', WHITE),
        ('  Writing RELEASE_COMPLETE marker', WHITE),
        ('  Released. Downstream flows can consume via:', GREEN),
        ('    set sta(input,netlist_release_tag) "P0_BTO"', MUTED),
    ],
    produces=[
        'releases/<project>/<design>/<phase>_<TAG>/ directory',
        'MANIFEST.json listing every deliverable',
        'RELEASE_COMPLETE marker file',
    ],
    notes=[
        'Ownership required',
        'Tag must be defined in release_config.tcl',
    ],
    page=11, section_color=GREEN,
)

# ── SLIDE 12: run release-check ───────────────────────────────────────
command_slide(
    section='RUN · RELEASE-CHECK',
    cmd_name='run release-check',
    purpose='Verify a release is complete and consumable (read-only)',
    syntax=[
        '$ cbflow run release-check --tag <TAG> --project <name>',
    ],
    options=[
        ('--tag',      '<TAG>',     'release tag to check'),
        ('--project',  '<name>',    'project name'),
        ('--verbose',  'flag',      'per-deliverable file existence report'),
    ],
    example=[
        ('$ cbflow run release-check --tag P0_BTO --project bumblebee', GREEN),
        ('  Release: bumblebee/cpu_core/P0_BTO', WHITE),
        ('  MANIFEST.json         OK', WHITE),
        ('  RELEASE_COMPLETE       OK', WHITE),
        ('  Deliverables (7/7):', WHITE),
        ('    netlist   .../cpu_core.pt.v         OK  (2.4 MB)', GREEN),
        ('    sdc       .../cpu_core.func.sdc     OK  (451 KB)', GREEN),
        ('    def       .../cpu_core.def          OK  (8.7 MB)', GREEN),
        ('    upf       .../cpu_core.upf          OK  (12 KB)', GREEN),
        ('    spef      .../cpu_core.spef.gz      OK  (47 MB)', GREEN),
        ('    reports   .../reports/              OK', GREEN),
        ('    checklist .../checklist_BTO.tcl     OK', GREEN),
        ('  Release VALID.', GREEN),
    ],
    produces=[
        'Report of every declared deliverable + on-disk state',
        'Non-zero exit if any deliverable is missing',
    ],
    notes=[
        'Read-only — safe for CI gates',
        'Use before consuming via release_tag in another flow',
    ],
    page=12, section_color=GREEN,
)

# ── SLIDE 13: run gui + dashboard logs ────────────────────────────────
command_slide(
    section='RUN · GUI + DASHBOARD LOGS',
    cmd_name='run gui  /  run dashboard logs',
    purpose='Open the web dashboard  ·  tail the daemon log',
    syntax=[
        '$ cbflow run gui',
        '$ cbflow run dashboard logs [--follow]',
        '$ cbflow run dashboard status',
    ],
    options=[
        ('--follow',   'flag',      'stream new log lines (like tail -f)'),
        ('--lines',    '<N>',       'show last N lines (default 200)'),
        ('--port',     '<N>',       'override daemon port (default 25000+hash)'),
    ],
    example=[
        ('$ cbflow run gui', GREEN),
        ('  Registering run with dashboard daemon...', WHITE),
        ('  Daemon running at http://localhost:25137', WHITE),
        ('  Opening browser: http://localhost:25137/run/1', WHITE),
        ('', WHITE),
        ('# in the browser you get:', MUTED),
        ('  · live DAG with color-coded stage states', MUTED),
        ('  · per-scenario MMMC status', MUTED),
        ('  · log tail per stage', MUTED),
        ('  · live metrics (WNS, congestion, DRC, ...)', MUTED),
        ('  · checklist panel', MUTED),
        ('', WHITE),
        ('$ cbflow run dashboard logs --follow', GREEN),
        ('  [2026-09-08 10:14:22] cts_opt1 → RUNNING (LSF 4471147)', WHITE),
        ('  [2026-09-08 10:15:04] cts_opt1 → DONE  (elapsed 42s)', GREEN),
    ],
    produces=[
        'Registers run with a per-user dashboard daemon',
        'gui: opens localhost URL in default browser',
    ],
    notes=[
        'One daemon per user; every registered run shares it',
        'Read-only for non-owners (HTTP 403 on mutations)',
    ],
    page=13, section_color=GREEN,
)

# ── SLIDE 14: run force + bypass ──────────────────────────────────────
command_slide(
    section='RUN · FORCE + BYPASS',
    cmd_name='run force  /  run bypass  /  run forcevalidate',
    purpose='Advanced state overrides — use with rationale in commit',
    syntax=[
        '$ cbflow run force --stage <name> --state <STATE>',
        '$ cbflow run bypass --stage <name> --reason "..."',
        '$ cbflow run forcevalidate --stage <name>',
    ],
    options=[
        ('--stage',    '<name>',    'target stage'),
        ('--state',    '<STATE>',   'PASS | FAIL | WAIT | STALE (force only)'),
        ('--reason',   '<text>',    'REQUIRED for bypass — kept in DB'),
        ('--waiver-id','<id>',      'optional waiver reference'),
    ],
    example=[
        ('# stage stuck on a stale lock file:', MUTED),
        ('$ cbflow run force --stage cts1 --state STALE', GREEN),
        ('  Overriding cts1: RUNNING → STALE', WHITE),
        ('  Downstream stages invalidated.', WHITE),
        ('  You can now retrace from cts1.', WHITE),
        ('', WHITE),
        ('# lint1 non-critical for this project:', MUTED),
        ('$ cbflow run bypass --stage lint1 \\', GREEN),
        ('    --reason "customer-approved: lint1 waived P0-P1"', GREEN),
        ('  Stage lint1 marked BYPASSED', WHITE),
        ('  Reason logged to bypass_events table.', WHITE),
        ('', WHITE),
        ('# manually promote a stage to PASS after external run:', MUTED),
        ('$ cbflow run forcevalidate --stage synthesis1', GREEN),
    ],
    produces=[
        'Writes state override + rationale to run\'s SQLite DB',
        'bypass_events / force_events tables retain full audit trail',
    ],
    notes=[
        'Ownership required. All three commands are audited.',
        'bypass requires --reason; empty rationale rejected',
        'Prefer retrace over force whenever possible',
    ],
    page=14, section_color=AMBER_DARK,
)

# ── SLIDE 15: run db-manage ───────────────────────────────────────────
command_slide(
    section='RUN · DB-MANAGE',
    cmd_name='run db-manage',
    purpose='Query and manage the per-run SQLite database',
    syntax=[
        '$ cbflow run db-manage status',
        '$ cbflow run db-manage backup',
        '$ cbflow run db-manage query --table <name> [--status <S>]',
        '$ cbflow run db-manage export --format <csv|json>',
    ],
    options=[
        ('status',     'subcmd',    'show DB location, size, table row counts'),
        ('backup',     'subcmd',    'copy DB to timestamped backup file'),
        ('query',      'subcmd',    'SQL-style filter across tables'),
        ('export',     'subcmd',    'dump tables to csv or json'),
        ('--table',    '<name>',    'jobs | stage_metrics | run_info | dag_structure | ...'),
        ('--status',   '<S>',       'PASS | FAIL | RUNNING | WAIT | STALE'),
        ('--format',   '<fmt>',     'csv | json'),
    ],
    example=[
        ('$ cbflow run db-manage status', GREEN),
        ('  DB path:   .race_P0_run_SYNTH_PNR_alice_a4b1c2d.db', WHITE),
        ('  DB size:   14.7 MB', WHITE),
        ('  Tables:    13 (jobs=847, stage_metrics=13, jobs=847)', WHITE),
        ('', WHITE),
        ('$ cbflow run db-manage query --table jobs --status FAIL', GREEN),
        ('  ┌────────────┬──────────────┬─────────┬──────────────┐', MUTED),
        ('  │ stage      │ subnode      │ retries │ error        │', WHITE),
        ('  ├────────────┼──────────────┼─────────┼──────────────┤', MUTED),
        ('  │ drc1       │ run          │ 3       │ ICV crashed  │', WHITE),
        ('  └────────────┴──────────────┴─────────┴──────────────┘', MUTED),
        ('', WHITE),
        ('$ cbflow run db-manage export --format csv', GREEN),
        ('  Exported 13 tables to db_export_2026-09-08.tar.gz', WHITE),
    ],
    produces=[
        'status: DB file path + size + per-table row counts',
        'backup: timestamped .db copy in the run dir',
        'export: tarball of csv/json per table',
    ],
    notes=[
        'DB naming: .race_<run>_<user>_<hash>.db',
        'DB lives in project(race,db_path) if set',
    ],
    page=15, section_color=GREEN,
)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: FLOW INFO  (slides 16-17)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 16: flow types + info + stages + nodes ──────────────────────
command_slide(
    section='FLOW · INTROSPECTION',
    cmd_name='flow types  /  info  /  stages  /  nodes',
    purpose='Read-only introspection over the framework\'s flow catalog',
    syntax=[
        '$ cbflow flow types',
        '$ cbflow flow info    --flow <FLOW>',
        '$ cbflow flow stages  --flow <FLOW>',
        '$ cbflow flow nodes   --flow <FLOW>',
    ],
    options=[
        ('--flow',     '<FLOW>',    'flow type: SYNTH_PNR | PNR | STA | ...'),
        ('--vendor',   '<name>',    'filter by vendor: synopsys | cadence'),
        ('--json',     'flag',      'machine-readable output'),
    ],
    example=[
        ('$ cbflow flow types', BLUE),
        ('  Flow       Description                        Vendor   Tool', WHITE),
        ('  SYNTH      Logic synthesis                    cadence  genus', WHITE),
        ('  SYNTH_PNR  Synthesis + Place & Route          cadence  innovus', WHITE),
        ('  PNR        Place & Route                      cadence  innovus', WHITE),
        ('  STA        Static Timing Analysis             synopsys pt', WHITE),
        ('  ...  (12 flows total)', MUTED),
        ('', WHITE),
        ('$ cbflow flow stages --flow SYNTH_PNR', BLUE),
        ('  rtl1 sdc1 upf1 init_design1 synthesis1', GREEN),
        ('  place1 cts1 cts_opt1 route1 pro1', GREEN),
        ('  signoff1 export_data1 release_data1', GREEN),
        ('  Exit gates: FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT', AMBER),
    ],
    produces=[
        'types: table of all flows with vendor + tool',
        'info: flow metadata (stages, node types, subnodes)',
        'stages: ordered stage list (DAG topological)',
        'nodes: stages + their subnodes (setup/run/validate/finish)',
    ],
    notes=[
        'Zero side-effects — safe to run anywhere',
        'Great first commands when onboarding',
    ],
    page=16, section_color=BLUE,
)

# ── SLIDE 17: flow check + version ────────────────────────────────────
command_slide(
    section='FLOW · CHECK + VERSION',
    cmd_name='flow check  /  flow version',
    purpose='Verify installation integrity  ·  show framework version',
    syntax=[
        '$ cbflow flow check',
        '$ cbflow flow check --tool <tool>',
        '$ cbflow flow version',
    ],
    options=[
        ('--tool',     '<name>',    'check a specific EDA tool binary'),
        ('--verbose',  'flag',      'per-tool version + license lookup'),
    ],
    example=[
        ('$ cbflow flow check', BLUE),
        ('  Framework:   CBflow v2.0.0', WHITE),
        ('  Core dir:    /projects/cbflow/PD', WHITE),
        ('  Config ver:  v1.0.0', WHITE),
        ('  Python:      3.10.14  OK', GREEN),
        ('  tclsh:       8.6.13   OK', GREEN),
        ('  EDA tools:', WHITE),
        ('    innovus    22.11-e100  OK', GREEN),
        ('    genus      22.10-e100  OK', GREEN),
        ('    primetime  2023.12     OK', GREEN),
        ('    icv        2023.12     OK', GREEN),
        ('    redhawk    2023.R2     OK', GREEN),
        ('  All checks passed.', GREEN),
        ('', WHITE),
        ('$ cbflow flow version', BLUE),
        ('  CBflow v2.0.0   Config v1.0.0   Python 3.10.14', WHITE),
    ],
    produces=[
        'check: pass/fail per component with detected versions',
        'version: one-line summary',
    ],
    notes=[
        'flow check is the first thing to run in a new environment',
        '--verbose adds license server lookups per tool',
    ],
    page=17, section_color=BLUE,
)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: library-manager  (slides 18-21)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 18: library-manager scan ────────────────────────────────────
command_slide(
    section='LIBRARY-MANAGER · SCAN',
    cmd_name='flow library-manager scan',
    purpose='Walk lib_root and categorize every library file by track × VT × corner',
    syntax=[
        '$ cbflow flow library-manager scan --tech <name>',
        '                                   [--version <ver>]',
    ],
    options=[
        ('--tech',        '<name>',   'tech directory to scan (gf_22nm, tsmc_5nm, ...)'),
        ('--version',     '<ver>',    'config version (default v1.0.0)'),
        ('--lib-root',    '<path>',   'override tech(lib_root)'),
        ('--verbose',     'flag',      'per-file categorization output'),
    ],
    example=[
        ('$ cbflow flow library-manager scan --tech gf_22nm', GREEN),
        ('  Scanning: /pdk/gf22/liberty/', WHITE),
        ('  Found:', WHITE),
        ('    .lib files:  1,247', WHITE),
        ('    .ndm files:  384', WHITE),
        ('    .lef files:  91', WHITE),
        ('  Categorized:', WHITE),
        ('    tracks:  7p5t (932)  9t (398)  12t (215)', WHITE),
        ('    VTs:     LVT (487)  SVT (612)  HVT (446)', WHITE),
        ('    corners: ss (581)  tt (498)  ff (466)', WHITE),
        ('  Coverage matrix ready. Run "generate" next.', GREEN),
    ],
    produces=[
        'Console report of what\'s in the lib_root',
        'No files written — read-only preview',
    ],
    notes=[
        'Preflight requires tech_config.tcl',
        'Scan is fast (~seconds); safe to iterate',
    ],
    page=18, section_color=GREEN_DARK,
)

# ── SLIDE 19: library-manager generate ────────────────────────────────
command_slide(
    section='LIBRARY-MANAGER · GENERATE',
    cmd_name='flow library-manager generate',
    purpose='Write lib_config_<tag>.tcl with every set_ref populated',
    syntax=[
        '$ cbflow flow library-manager generate \\',
        '     --tech <name> --tag <tag>',
        '     [--merge] [--allow-missing]',
    ],
    options=[
        ('--tech',           '<name>',   'target tech'),
        ('--tag',            '<tag>',    'output tag → lib_config_<tag>.tcl'),
        ('--merge',          'flag',      'keep entries not in current scan'),
        ('--allow-missing',  'flag',      'proceed with missing source paths'),
        ('--stdcell-path',   '<path>',   'override stdcell scan root'),
        ('--memory-path',    '<path>',   'override memory scan root'),
        ('--output',         '<file>',   'custom output path'),
    ],
    example=[
        ('$ cbflow flow library-manager generate \\', GREEN),
        ('     --tech gf_22nm --tag P0', GREEN),
        ('  Preflight: tech_config.tcl found  OK', WHITE),
        ('  Preflight: source paths exist    OK', WHITE),
        ('  Scanning...', WHITE),
        ('  Categorizing 1,722 files...', WHITE),
        ('  Writing:', WHITE),
        ('    config/tech/gf_22nm/v1.0.0/lib_config_P0.tcl', GREEN),
        ('  Entries written:', WHITE),
        ('    tech(7p5t,ndm,stdcell)     287 refs', WHITE),
        ('    tech(7p5t,lib,ss_0p72,timing) → 96 refs', WHITE),
        ('    tech(ndm,memory)           42 refs', WHITE),
        ('    tech(ndm,io)               18 refs', WHITE),
        ('  lib_config_P0.tcl ready. Elapsed 12s.', GREEN),
    ],
    produces=[
        'config/tech/<tech>/v1.0.0/lib_config_<tag>.tcl',
    ],
    notes=[
        'Fail-fast on missing paths — set CBFLOW_ALLOW_MISSING=1 in CI',
        '--merge preserves hand-added entries (custom IPs)',
    ],
    page=19, section_color=GREEN_DARK,
)

# ── SLIDE 20: library-manager check + list ────────────────────────────
command_slide(
    section='LIBRARY-MANAGER · CHECK + LIST',
    cmd_name='flow library-manager check  /  list',
    purpose='Validate declared paths exist  ·  show configured library sets',
    syntax=[
        '$ cbflow flow library-manager check --tech <name>',
        '$ cbflow flow library-manager list  --tech <name> [--filter <expr>]',
    ],
    options=[
        ('--tech',      '<name>',   'target tech'),
        ('--tag',       '<tag>',    'check specific lib_config_<tag>.tcl'),
        ('--filter',    '<expr>',   'e.g. "track=7p5t vt=lvt"'),
        ('--json',      'flag',      'machine-readable output'),
    ],
    example=[
        ('$ cbflow flow library-manager check --tech gf_22nm', GREEN),
        ('  Checking lib_config_P0.tcl against disk...', WHITE),
        ('  tech(7p5t,ndm,stdcell)   287/287  OK', GREEN),
        ('  tech(9t,ndm,stdcell)     398/398  OK', GREEN),
        ('  tech(rcx,ss,tluplus)     4/4      OK', GREEN),
        ('  tech(ndm,memory)         42/42    OK', GREEN),
        ('  All 1,722 declared paths exist.', GREEN),
        ('', WHITE),
        ('$ cbflow flow library-manager list --tech gf_22nm \\', GREEN),
        ('    --filter "track=7p5t vt=lvt"', GREEN),
        ('  Library sets matching filter:', WHITE),
        ('    7p5t,lvt,ss_0p72v_150c    96 refs', WHITE),
        ('    7p5t,lvt,tt_0p80v_25c     96 refs', WHITE),
        ('    7p5t,lvt,ff_0p88v_-40c    96 refs', WHITE),
    ],
    produces=[
        'check: OK/MISSING per declared path with counts',
        'list: filtered library-set enumeration',
    ],
    notes=[
        'Non-zero exit code on any missing path — CI-friendly',
        'list supports project + tag filters for focus',
    ],
    page=20, section_color=GREEN_DARK,
)

# ── SLIDE 21: library-manager status + coverage ──────────────────────
command_slide(
    section='LIBRARY-MANAGER · STATUS + COVERAGE',
    cmd_name='flow library-manager status  /  coverage',
    purpose='Signoff-readiness per track/VT  ·  tracks × VTs × corners matrix',
    syntax=[
        '$ cbflow flow library-manager status   --tech <name>',
        '$ cbflow flow library-manager coverage --tech <name>',
    ],
    options=[
        ('--tech',      '<name>',   'target tech'),
        ('--project',   '<name>',   'filter by project(vt_flavors) only'),
        ('--tag',       '<tag>',    'inspect specific lib_config_<tag>.tcl'),
    ],
    example=[
        ('$ cbflow flow library-manager status --tech gf_22nm', GREEN),
        ('  Multi-VT signoff readiness:', WHITE),
        ('    7p5t + LVT:  READY  (all corners, all RCs)', GREEN),
        ('    7p5t + SVT:  READY', GREEN),
        ('    7p5t + HVT:  MISSING (rcmax @ ss)', RED_DARK),
        ('  Recommendation: rerun generate with --allow-missing', WHITE),
        ('  or characterize HVT rcmax@ss and rerun.', WHITE),
        ('', WHITE),
        ('$ cbflow flow library-manager coverage --tech gf_22nm', GREEN),
        ('           ss     tt     ff', WHITE),
        ('  7p5t/LVT ✓      ✓      ✓', GREEN),
        ('  7p5t/SVT ✓      ✓      ✓', GREEN),
        ('  7p5t/HVT ✗(rc)  ✓      ✓', AMBER),
        ('  9t/LVT   ✓      ✓      ✓', GREEN),
    ],
    produces=[
        'status: per (track,VT) verdict — READY / MISSING',
        'coverage: axis matrix with visual gap map',
    ],
    notes=[
        'Ideal for pre-signoff audits',
        'Use --project to reduce noise for a specific product',
    ],
    page=21, section_color=GREEN_DARK,
)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: mmmc-manager  (slides 22-23)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 22: mmmc-manager list-corners ───────────────────────────────
command_slide(
    section='MMMC-MANAGER · LIST-CORNERS',
    cmd_name='flow mmmc-manager list-corners',
    purpose='Show every characterisation corner available in the tech',
    syntax=[
        '$ cbflow flow mmmc-manager list-corners --tech <name>',
    ],
    options=[
        ('--tech',      '<name>',   'target tech'),
        ('--voltage',   '<V>',      'filter by voltage'),
        ('--temperature','<T>',     'filter by temperature'),
        ('--json',      'flag',      'machine-readable output'),
    ],
    example=[
        ('$ cbflow flow mmmc-manager list-corners --tech gf_22nm', BLUE),
        ('  Characterization available:', WHITE),
        ('    Corners:       ss  tt  ff  sf  fs', WHITE),
        ('    Voltages:      0.72 0.80 0.88 1.00 (V)', WHITE),
        ('    Temperatures:  -40  25  85  125 (°C)', WHITE),
        ('    RC corners:    rcmin rctyp rcmax cworst rcbest', WHITE),
        ('', WHITE),
        ('  Total PVT points: 5 × 4 × 4 = 80', WHITE),
        ('  RC-paired views:  80 × 5 = 400', WHITE),
        ('', WHITE),
        ('$ cbflow flow mmmc-manager list-corners --tech gf_22nm \\', BLUE),
        ('     --voltage 0.72', BLUE),
        ('  PVT combos at 0.72V:', WHITE),
        ('    ss_0p72v_-40c   ss_0p72v_25c   ss_0p72v_125c', WHITE),
    ],
    produces=[
        'Console table of every characterization axis available',
        'PVT combo count + RC-paired view count',
    ],
    notes=[
        'Read-only — use to plan the scenario set',
        'Preflight requires tech_config.tcl',
    ],
    page=22, section_color=BLUE,
)

# ── SLIDE 23: mmmc-manager generate ───────────────────────────────────
command_slide(
    section='MMMC-MANAGER · GENERATE',
    cmd_name='flow mmmc-manager generate',
    purpose='Auto-generate mmmc_config.tcl for a project from PVT axes',
    syntax=[
        '$ cbflow flow mmmc-manager generate \\',
        '     --tech <name> --project <name> --tag <tag>',
        '     [--corners ss,tt,ff] [--voltages 0.72,0.80]',
        '     [--temperatures -40,25,125] [--allow-missing]',
    ],
    options=[
        ('--tech',           '<name>',   'target tech'),
        ('--project',        '<name>',   'project (filters by enabled VTs)'),
        ('--tag',            '<tag>',    'reads lib_config_<tag>.tcl'),
        ('--corners',        '<list>',   'comma-separated corner list'),
        ('--voltages',       '<list>',   'comma-separated voltage list'),
        ('--temperatures',   '<list>',   'comma-separated temperature list'),
        ('--allow-missing',  'flag',      'proceed if lib_set_ref missing'),
    ],
    example=[
        ('$ cbflow flow mmmc-manager generate \\', BLUE),
        ('     --tech gf_22nm --project cpu_core --tag P0 \\', BLUE),
        ('     --corners ss,tt,ff \\', BLUE),
        ('     --voltages 0.72,0.80,0.88 \\', BLUE),
        ('     --temperatures -40,25,125', BLUE),
        ('  Preflight: tech_config.tcl found  OK', WHITE),
        ('  Preflight: lib_config_P0.tcl found OK', WHITE),
        ('  Preflight: lib_set_ref check      OK (36/36 combos)', WHITE),
        ('  Expanding matrix: 3 × 3 × 3 = 27 PVT points', WHITE),
        ('  RC-pairing: 27 × 5 = 135 analysis views', WHITE),
        ('  Filtering scenario sets: setup hold signoff power', WHITE),
        ('  Writing:', WHITE),
        ('    config/project/cpu_core/v1.0.0/mmmc_config.tcl', GREEN),
        ('  135 views written. Elapsed 3s.', GREEN),
    ],
    produces=[
        'config/project/<name>/v1.0.0/mmmc_config.tcl',
        'Every mode × corner × PVT view expanded',
    ],
    notes=[
        'Fail-fast on missing lib_set_ref combos',
        'Downstream tools (Genus, Innovus, PT, Tempus) all read the same file',
    ],
    page=23, section_color=BLUE,
)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: checklist  (slides 24-27)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 24: checklist list + list-checks ────────────────────────────
command_slide(
    section='CHECKLIST · LIST + LIST-CHECKS',
    cmd_name='flow checklist list  /  list-checks',
    purpose='Enumerate milestones  ·  enumerate checks within a milestone',
    syntax=[
        '$ cbflow flow checklist list',
        '$ cbflow flow checklist list-checks --milestone <TAG>',
    ],
    options=[
        ('--milestone', '<TAG>',    'FP_EXIT | PLACE_EXIT | ... | BTO | MTO'),
        ('--phase',     '<P>',      'P0 | P1 | P2 | P3'),
        ('--category',  '<cat>',    'TMG | PLC | CLK | PWR | RTG | PHY | SI | MFG'),
    ],
    example=[
        ('$ cbflow flow checklist list', GREEN),
        ('  Milestone     Phase    Checks   Mandatory   Waivable', WHITE),
        ('  FP_EXIT       P0-P3    28       21          7', WHITE),
        ('  PLACE_EXIT    P0-P3    41       32          9', WHITE),
        ('  CTS_EXIT      P1-P3    36       29          7', WHITE),
        ('  PRO_EXIT      P1-P3    52       48          4', WHITE),
        ('  BTO           P2-P3    89       89          0', WHITE),
        ('  MTO           P3       46       46          0', WHITE),
        ('', WHITE),
        ('$ cbflow flow checklist list-checks --milestone BTO \\', GREEN),
        ('     --category TMG', GREEN),
        ('  TMG-001  setup_slack_all_scenarios       critical', WHITE),
        ('  TMG-002  hold_slack_all_scenarios        critical', WHITE),
        ('  TMG-003  transition_max                  critical', WHITE),
        ('  ... (32 timing checks total)', MUTED),
    ],
    produces=[
        'list: milestone table with counts',
        'list-checks: per-check id, description, severity',
    ],
    notes=[
        'Read-only — safe anywhere',
        'Filter by --category to focus a review',
    ],
    page=24, section_color=GREEN_DARK,
)

# ── SLIDE 25: checklist generate + status ─────────────────────────────
command_slide(
    section='CHECKLIST · GENERATE + STATUS',
    cmd_name='flow checklist generate  /  status',
    purpose='Materialize checklist against a run  ·  show pass/fail/waived state',
    syntax=[
        '$ cbflow flow checklist generate --milestone <TAG>',
        '$ cbflow flow checklist status   --milestone <TAG> --run-dir <path>',
    ],
    options=[
        ('--milestone', '<TAG>',    'target milestone'),
        ('--run-dir',   '<path>',   'run directory (default: current)'),
        ('--summary',   'flag',      'one-line pass/fail summary'),
        ('--json',      'flag',      'machine-readable output'),
    ],
    example=[
        ('$ cbflow flow checklist generate --milestone BTO', GREEN),
        ('  Materializing 89 BTO checks against current run...', WHITE),
        ('  Wrote: checklist_BTO.tcl', GREEN),
        ('  Wrote: checklist_BTO_results.json (empty scaffold)', GREEN),
        ('', WHITE),
        ('$ cbflow flow checklist status --milestone BTO --run-dir .', GREEN),
        ('  BTO checklist status:', WHITE),
        ('    PASS:    86 / 89', GREEN),
        ('    FAIL:    2  (TMG-014, RTG-003)', RED_DARK),
        ('    WAIVED:  1  (SI-007, waived by alice 2026-08-14)', AMBER),
        ('    OPEN:    0', WHITE),
        ('  Verdict: NOT READY — 2 blockers', RED_DARK),
        ('  Details:', WHITE),
        ('    TMG-014  setup slack negative on I2C bus (-0.024 ns)', RED_DARK),
        ('    RTG-003  3 SI violations on clk_mux path', RED_DARK),
    ],
    produces=[
        'generate: checklist_<TAG>.tcl + results scaffold in run',
        'status: per-check verdict + summary + failure details',
    ],
    notes=[
        'status is what CI gates on before sign-off',
        'Non-zero exit if any FAIL',
    ],
    page=25, section_color=GREEN_DARK,
)

# ── SLIDE 26: checklist sign-off + waiver ─────────────────────────────
command_slide(
    section='CHECKLIST · SIGN-OFF + WAIVER',
    cmd_name='flow checklist sign-off  /  waiver',
    purpose='Record sign-off  ·  waive a specific check with a reason',
    syntax=[
        '$ cbflow flow checklist sign-off --milestone <TAG> --run-dir <path>',
        '$ cbflow flow checklist waiver \\',
        '     --milestone <TAG> --check-id <ID> --reason "<text>"',
    ],
    options=[
        ('--milestone', '<TAG>',    'target milestone'),
        ('--run-dir',   '<path>',   'run directory'),
        ('--check-id',  '<ID>',     'e.g. TMG-014 (waiver only)'),
        ('--reason',    '<text>',   'REQUIRED for waiver — kept in DB'),
        ('--waiver-id', '<id>',     'optional external waiver reference'),
        ('--force',     'flag',      'sign-off with open FAILs (not recommended)'),
    ],
    example=[
        ('# waive one check first:', MUTED),
        ('$ cbflow flow checklist waiver \\', AMBER_DARK),
        ('     --milestone BTO \\', AMBER_DARK),
        ('     --check-id TMG-014 \\', AMBER_DARK),
        ('     --reason "corner not characterized in P0"', AMBER_DARK),
        ('  Waiver recorded:', WHITE),
        ('    BTO / TMG-014 / alice / 2026-09-08 10:14 UTC', WHITE),
        ('    Reason: corner not characterized in P0', WHITE),
        ('', WHITE),
        ('# then sign off:', MUTED),
        ('$ cbflow flow checklist sign-off --milestone BTO --run-dir .', GREEN),
        ('  Verifying: PASS=87 WAIVED=2 FAIL=0 OPEN=0', WHITE),
        ('  Signing off BTO for run P0_run_SYNTH_PNR_test1', WHITE),
        ('  Signed by: alice   at 2026-09-08 10:14:22 UTC', GREEN),
        ('  Sign-off recorded in run DB.', GREEN),
    ],
    produces=[
        'waiver: row in waivers table with owner + timestamp',
        'sign-off: row in sign_offs table (immutable)',
    ],
    notes=[
        'Ownership required for both',
        '--reason cannot be empty; auto-rejected',
        'Sign-off blocked if any FAIL or OPEN — override with --force (audited)',
    ],
    page=26, section_color=AMBER_DARK,
)

# ── SLIDE 27: checklist add-check + remove-check ─────────────────────
command_slide(
    section='CHECKLIST · ADD-CHECK + REMOVE-CHECK',
    cmd_name='flow checklist add-check  /  remove-check',
    purpose='Attach a custom check to a milestone  ·  detach one',
    syntax=[
        '$ cbflow flow checklist add-check \\',
        '     --milestone <TAG> --check-id <ID>',
        '$ cbflow flow checklist remove-check \\',
        '     --milestone <TAG> --check-id <ID>',
    ],
    options=[
        ('--milestone', '<TAG>',    'target milestone'),
        ('--check-id',  '<ID>',     'check identifier (e.g. TMG-042)'),
        ('--project',   '<name>',   'project-scoped modification'),
        ('--reason',    '<text>',   'why (recommended, not required)'),
    ],
    example=[
        ('# add a project-specific check to BTO:', MUTED),
        ('$ cbflow flow checklist add-check \\', GREEN),
        ('     --milestone BTO \\', GREEN),
        ('     --check-id TMG-042 \\', GREEN),
        ('     --project bumblebee', GREEN),
        ('  Attached TMG-042 to BTO for project=bumblebee', WHITE),
        ('  New count: BTO now has 90 checks for bumblebee', WHITE),
        ('', WHITE),
        ('# detach a check that no longer applies:', MUTED),
        ('$ cbflow flow checklist remove-check \\', GREEN),
        ('     --milestone BTO \\', GREEN),
        ('     --check-id RTG-999 \\', GREEN),
        ('     --project bumblebee \\', GREEN),
        ('     --reason "check retired in R2"', GREEN),
        ('  Detached RTG-999 from BTO for project=bumblebee', WHITE),
        ('  Change logged: alice@2026-09-08 with reason', WHITE),
    ],
    produces=[
        'Modifies project-scoped checklist_config in place',
        'Every add/remove is audited (owner + timestamp + reason)',
    ],
    notes=[
        'Ownership required',
        'Prefer project-scoped edits over global changes',
        '--reason recommended for future audit trail',
    ],
    page=27, section_color=GREEN_DARK,
)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: smartgenie  (slides 28-29)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 28: smartgenie interactive + one-shot + search ─────────────
command_slide(
    section='SMARTGENIE · QUERY',
    cmd_name='smartgenie  /  smartgenie <query>  /  smartgenie search',
    purpose='Interactive AI agent  ·  one-shot query  ·  retrieval-only search',
    syntax=[
        '$ cbflow smartgenie',
        '$ cbflow smartgenie "<natural language query>"',
        '$ cbflow smartgenie search "<query>" [--top-k <N>]',
    ],
    options=[
        ('--model',     '<name>',   'override local model (default: llama3.1:8b)'),
        ('--top-k',     '<N>',      'retrieval hits to return (search only)'),
        ('--verbose',   'flag',      'show tool calls the agent makes'),
        ('--no-kb',     'flag',      'skip retrieval; pure model'),
    ],
    example=[
        ('$ cbflow smartgenie', BLUE_DARK),
        ('  SmartGenie v1.0 (local Ollama, llama3.1:8b)', WHITE),
        ('  smartgenie> Why did cts1 fail on scenario ss_0p76v_rcmax?', WHITE),
        ('  ', WHITE),
        ('  Diagnosis:', BLUE_DARK),
        ('  · CTS DRV cap-tran violation on 47 endpoints', WHITE),
        ('  · Trigger: buffer library uses LVT-only in ss_0p76v', WHITE),
        ('  · Root cause: mmmc(pvt,ss) missed HVT lib_set_ref', WHITE),
        ('  · Suggested fix:', WHITE),
        ('      cbflow flow mmmc-manager generate --tech tsmc_5nm \\', GREEN),
        ('        --project cpu_core --allow-missing', GREEN),
        ('', WHITE),
        ('$ cbflow smartgenie "how many BTO checks does bumblebee have?"', BLUE_DARK),
        ('  bumblebee/BTO has 90 checks (89 shared + 1 project-specific).', WHITE),
    ],
    produces=[
        'Diagnostic + suggested fix (with runnable commands)',
        'Grounded in run DB + local KB + docs',
    ],
    notes=[
        '100% local — no data leaves your machine',
        'Server mode: SMARTGENIE_SERVER=http://host:8091',
    ],
    page=28, section_color=BLUE_DARK,
)

# ── SLIDE 29: smartgenie setup + ingest + server ─────────────────────
command_slide(
    section='SMARTGENIE · SETUP + INGEST + SERVER',
    cmd_name='smartgenie setup  /  ingest  /  server start',
    purpose='One-time install checks  ·  build KB  ·  multi-user server',
    syntax=[
        '$ cbflow smartgenie setup',
        '$ cbflow smartgenie ingest --all',
        '$ cbflow smartgenie server start [--port <N>]',
        '$ cbflow smartgenie server stop',
    ],
    options=[
        ('--all',       'flag',      'ingest docs + code + configs + KB'),
        ('--path',      '<path>',   'ingest a specific directory'),
        ('--rebuild',   'flag',      'wipe the KB and re-ingest'),
        ('--port',      '<N>',       'server port (default 8091)'),
    ],
    example=[
        ('$ cbflow smartgenie setup', BLUE_DARK),
        ('  Checking Ollama...     OK (v0.3.14)', GREEN),
        ('  Checking model...      OK (llama3.1:8b, 4.7 GB)', GREEN),
        ('  Checking KB path...    OK (~/.cbflow/smartgenie/kb/)', GREEN),
        ('  KB status:             built (12,447 chunks, updated 2d ago)', WHITE),
        ('  SmartGenie ready.', GREEN),
        ('', WHITE),
        ('$ cbflow smartgenie ingest --all', BLUE_DARK),
        ('  Ingesting docs/...       847 chunks', WHITE),
        ('  Ingesting configs/...    3,124 chunks', WHITE),
        ('  Ingesting code/...       8,476 chunks', WHITE),
        ('  Rebuilding embeddings...', WHITE),
        ('  KB rebuilt: 12,447 chunks. Elapsed 4m 12s.', GREEN),
        ('', WHITE),
        ('$ cbflow smartgenie server start --port 8091', BLUE_DARK),
        ('  Server listening on 0.0.0.0:8091', WHITE),
    ],
    produces=[
        'setup: pass/fail report per component',
        'ingest: KB rebuild with chunk counts',
        'server: daemon on <port>, clients hit via SMARTGENIE_SERVER env',
    ],
    notes=[
        'ingest runs on first use automatically',
        '--rebuild after a big framework upgrade',
    ],
    page=29, section_color=BLUE_DARK,
)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: migrate + project-dashboard  (slides 30-31)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 30: migrate ─────────────────────────────────────────────────
command_slide(
    section='MIGRATE',
    cmd_name='migrate',
    purpose='Carry user values from an old config into a new template',
    syntax=[
        '$ cbflow migrate --old <old.tcl> --new <new.tcl>',
        '                 [--dry-run] [--report <path>]',
    ],
    options=[
        ('--old',       '<file>',   'source config (values to lift)'),
        ('--new',       '<file>',   'destination template (schema)'),
        ('--dry-run',   'flag',      'report only; do not touch --new'),
        ('--report',    '<path>',   'write migration report to this file'),
        ('--strict',    'flag',      'fail if any key from --old cannot be placed'),
    ],
    example=[
        ('$ cbflow migrate \\', AMBER_DARK),
        ('     --old workarea/cpu_core/uc_PNR_innovus.tcl \\', AMBER_DARK),
        ('     --new $CBFLOW_CORE_DIR/config/templates/uc_PNR_innovus.tcl \\', AMBER_DARK),
        ('     --report migration_report.txt', AMBER_DARK),
        ('  Parsing old config...   57 keys', WHITE),
        ('  Parsing new template... 62 keys', WHITE),
        ('  Migrating values:', WHITE),
        ('    · migrated:    54 keys (values carried over)', GREEN),
        ('    · new-only:    8 keys (in template, not in old)', BLUE),
        ('    · dropped:     3 keys (deprecated: schema drift)', AMBER_DARK),
        ('  Wrote migrated config to: uc_PNR_innovus.tcl', GREEN),
        ('  Report: migration_report.txt', WHITE),
    ],
    produces=[
        'Overwrites --new with your values applied (backup made)',
        'migration_report.txt with migrated / new / dropped lists',
    ],
    notes=[
        '--dry-run first to see the impact',
        'Backup of --new saved as <new>.bak.<timestamp>',
        'Only keys with the exact same access form migrate',
    ],
    page=30, section_color=AMBER_DARK,
)

# ── SLIDE 31: project-dashboard ───────────────────────────────────────
command_slide(
    section='PROJECT-DASHBOARD',
    cmd_name='project-dashboard',
    purpose='Project-wide tracking dashboard (all runs, all users, all blocks)',
    syntax=[
        '$ cbflow project-dashboard start  --project <name>',
        '$ cbflow project-dashboard stop   --project <name>',
        '$ cbflow project-dashboard status --project <name>',
        '$ cbflow project-dashboard --list-users',
    ],
    options=[
        ('start',       'subcmd',    'launch dashboard daemon in background'),
        ('stop',        'subcmd',    'stop the daemon'),
        ('status',      'subcmd',    'check daemon + registered runs'),
        ('--project',   '<name>',   'target project (bumblebee, phoenix, ...)'),
        ('--port',      '<N>',      'override port (default 25000 + hash%2500)'),
        ('--list-users','flag',      'show all users with a running dashboard'),
    ],
    example=[
        ('$ cbflow project-dashboard start --project bumblebee', AMBER),
        ('  Starting daemon on port 25743...', WHITE),
        ('  Discovering runs under: /projects/bumblebee/workarea/', WHITE),
        ('  Registered 47 runs across 12 blocks', WHITE),
        ('  Dashboard: http://<host>:25743', GREEN),
        ('  Log: ~/.cbflow/project_dashboard/bumblebee.log', MUTED),
        ('', WHITE),
        ('$ cbflow project-dashboard status --project bumblebee', AMBER),
        ('  Daemon: RUNNING (PID 21847, port 25743)', WHITE),
        ('  Blocks: 12   Runs: 47   Active: 8', WHITE),
        ('  Latest release_tag: P0_BTO (2026-09-06)', WHITE),
        ('', WHITE),
        ('$ cbflow project-dashboard --list-users', AMBER),
        ('  alice   bumblebee   port 25743   3 blocks tracked', WHITE),
        ('  bob     phoenix     port 25891   5 blocks tracked', WHITE),
    ],
    produces=[
        'HTTP dashboard covering every run in the project',
        'Cross-block progress, release-tag traceability, per-user activity',
    ],
    notes=[
        'One daemon per (user, project)',
        'Port derived from project name hash — deterministic',
    ],
    page=31, section_color=AMBER,
)


# ═══════════════════════════════════════════════════════════════════════
# SECTION: reference  (slides 32-33)
# ═══════════════════════════════════════════════════════════════════════

# ── SLIDE 32: Environment variables ───────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'REFERENCE',
           'Environment variables',
           subtitle='Every env var CBflow reads. Set once in the workspace shell; every command below inherits them.',
           footer_page=32)

env_x = Inches(0.5); env_y = Inches(1.7); env_w = Inches(12.35); env_h = Inches(5.3)
add_rect(s, env_x, env_y, env_w, env_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, env_x, env_y, env_w, Inches(0.4), fill=INK)
add_text(s, env_x + Inches(0.15), env_y + Inches(0.08), env_w - Inches(0.3), Inches(0.26),
         'ENVIRONMENT VARIABLES', size=13, bold=True, color=WHITE, font=MONO)

# Table header
hdr_y = env_y + Inches(0.55)
add_text(s, env_x + Inches(0.2), hdr_y, Inches(3.2), Inches(0.26),
         'VAR', size=11, bold=True, color=MUTED, font=MONO)
add_text(s, env_x + Inches(3.5), hdr_y, Inches(2.5), Inches(0.26),
         'EXAMPLE VALUE', size=11, bold=True, color=MUTED, font=MONO)
add_text(s, env_x + Inches(6.1), hdr_y, env_w - Inches(6.3), Inches(0.26),
         'PURPOSE / SET BY', size=11, bold=True, color=MUTED, font=MONO)

env_vars = [
    ('CBFLOW_CORE_DIR',      '/proj/cbflow/PD',    'framework root — resolved from install path if unset'),
    ('FLOW_CONFIG_VERSION',  'v1.0.0',             'flow config version to use'),
    ('PROJECT_VERSION',      'v1.0.0',             'project config version'),
    ('CBFLOW_TECH_NODE',     'gf_22nm',            'tech name; set by workspace create'),
    ('TECH_NAME',            'gf_22nm',            'alias for CBFLOW_TECH_NODE'),
    ('CBFLOW_BLOCK_NAME',    'cpu_core',           'design_name (block)'),
    ('CBFLOW_PROJECT_NAME',  'bumblebee',          'project name'),
    ('CBFLOW_PROJECT_PHASE', 'LC1',                'P0-P3 or project-specific (LC1-LC5)'),
    ('CBFLOW_RUN_DIR',       '.../P0_run_PNR_a',   'current run directory (absolute)'),
    ('CBFLOW_ALLOW_MISSING', '1',                  '1/true/yes → skip missing-source hard-fail'),
    ('CONFIG_ROOT',          '<CBFLOW_CORE_DIR>/config', 'config tree root; derived'),
    ('SCRIPTS_ROOT',         '<CBFLOW_CORE_DIR>/utils',  'utility scripts; derived'),
    ('SMARTGENIE_SERVER',    'http://host:8091',   'server-mode base URL (client-side)'),
    ('LSB_QUEUE',            'L',                  'LSF queue override (per-stage from lsf_config)'),
]
ey = hdr_y + Inches(0.32)
for var, val, desc in env_vars:
    add_text(s, env_x + Inches(0.25), ey, Inches(3.25), Inches(0.28),
             var, size=11, bold=True, color=GREEN_DARK, font=MONO)
    add_text(s, env_x + Inches(3.5), ey, Inches(2.55), Inches(0.28),
             val, size=10, color=BLUE, font=MONO)
    add_text(s, env_x + Inches(6.1), ey, env_w - Inches(6.3), Inches(0.28),
             desc, size=10, color=BODY)
    ey += Inches(0.32)


# ── SLIDE 33: Gotchas + tips ──────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'REFERENCE',
           'Gotchas, rules of thumb, CI recipes',
           subtitle='The set of behaviors and options that catch new users. Read once.',
           footer_page=33)

# Two columns
left_x = Inches(0.5); left_w = Inches(6.15)
right_x = Inches(6.8); right_w = Inches(6.05)
top_y = Inches(1.75); box_h = Inches(5.2)

# Left: gotchas
add_rect(s, left_x, top_y, left_w, box_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, left_x, top_y, left_w, Inches(0.36), fill=AMBER_DARK)
add_text(s, left_x + Inches(0.15), top_y + Inches(0.07), left_w - Inches(0.3), Inches(0.22),
         'GOTCHAS', size=11, bold=True, color=WHITE, font=MONO)

gotchas = [
    ('Run ownership',
     'Only the run creator can execute / retrace / release / force. '
     'Read-only ops (status, GUI, logs) are open to all.'),
    ('Workarea path enforced',
     'Runs must live under project(workarea_path)/<design>/. '
     'workspace create refuses to run outside this tree.'),
    ('tech_config.tcl required',
     'library-manager and mmmc-manager preflight-check this file. '
     'Missing → hard-fail with a fix guide.'),
    ('Input file naming',
     'Convention: <design>[.<mode>].<ext>  (e.g. cpu_core.func.sdc). '
     'Advisory by default; strict via flow(strict_input_naming) true.'),
    ('MMMC drift',
     'Never hand-edit mmmc_config.tcl. Always regenerate via '
     'mmmc-manager so scenario sets stay consistent across tools.'),
    ('SmartGenie is local',
     'No data leaves your machine unless SMARTGENIE_SERVER is set. '
     'KB is on-disk, model is local Ollama.'),
]
gy = top_y + Inches(0.55)
for title, body in gotchas:
    add_text(s, left_x + Inches(0.25), gy, left_w - Inches(0.4), Inches(0.28),
             '·  ' + title, size=12, bold=True, color=AMBER_DARK)
    add_text(s, left_x + Inches(0.5), gy + Inches(0.28), left_w - Inches(0.65), Inches(0.55),
             body, size=10, color=BODY)
    gy += Inches(0.78)

# Right: CI recipes
add_rect(s, right_x, top_y, right_w, box_h, fill=INK, line=None)
add_text(s, right_x + Inches(0.15), top_y + Inches(0.08), right_w - Inches(0.3), Inches(0.22),
         'CI RECIPES', size=11, bold=True, color=GREEN, font=MONO)

recipes = [
    ('# nightly regeneration (non-interactive)', MUTED),
    ('export CBFLOW_ALLOW_MISSING=1', WHITE),
    ('cbflow flow library-manager generate \\', GREEN),
    ('  --tech gf_22nm --tag P0_nightly', GREEN),
    ('cbflow flow mmmc-manager generate \\', GREEN),
    ('  --tech gf_22nm --project cpu_core --tag P0_nightly', GREEN),
    ('', WHITE),
    ('# release gate (fail CI on any FAIL)', MUTED),
    ('cbflow flow checklist status \\', GREEN),
    ('  --milestone BTO --run-dir . --json | \\', GREEN),
    ('  jq -e ".fail == 0"', GREEN),
    ('', WHITE),
    ('# validate a release exists before consuming', MUTED),
    ('cbflow run release-check \\', GREEN),
    ('  --tag P0_BTO --project bumblebee', GREEN),
    ('', WHITE),
    ('# db export for offline analysis', MUTED),
    ('cbflow run db-manage export --format csv', GREEN),
    ('', WHITE),
    ('# smartgenie ingest on framework upgrade', MUTED),
    ('cbflow smartgenie ingest --all --rebuild', GREEN),
]
ry = top_y + Inches(0.5)
for line, col in recipes:
    add_text(s, right_x + Inches(0.2), ry, right_w - Inches(0.4), Inches(0.26),
             line, size=11, color=col, font=MONO)
    ry += Inches(0.24)


# ── SAVE ────────────────────────────────────────────────────────────────
out = 'PD/docs/sales/CBflow_Command_Reference_Deck.pptx'
prs.save(out)
print(f'Wrote {out} with {len(prs.slides)} slide(s).')
