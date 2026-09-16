#!/usr/bin/env python3
"""
Build CBflow_Methodology_Deck.pptx.

Deck is built up slide-by-slide per user instruction. Current contents:

    1  library-manager + mmmc-manager  (features + commands)
    2  PD flow hierarchy — all 12 CBflow nodes with arrows
    3  SYNTH_PNR — all subnodes, dependency arrows, exit stages marked
    4  Full-chip hierarchical flow — FCFP + design_hierarchy variables
    5  Zero-ECO cycle — pre-cleanup methodology to reduce real ECO iterations
    6  Clock tree topologies — H-tree, mesh, spine + CPU hybrid
    7  Deep-Dive 1 — RTL → PD handoff and kickoff deliverables
    8  Deep-Dive 2 — Floorplan (tasks, techniques, checks, deliverables)
    9  Deep-Dive 3 — Placement + CTS (tasks, techniques, checks)
   10  Deep-Dive 4 — Routing + Post-Route Optimization
   11  Deep-Dive 5 — Timing signoff (STA + LEC + CLP)
   12  Deep-Dive 6 — Physical + Power signoff (PV + EMIR)
   13  Deep-Dive 7 — Partitioned power domains: Rapid AI (PON, 800G, AFE, Core/Mem, LPDDR)
   14  Deep-Dive 8 — Package co-design (SI/PI signoff with package team)
   15  Exit milestones — FP_EXIT → MTO with per-gate criteria (final slide)

Additional slides will be added as instructions arrive.

Brand palette (SmartSoC): green primary #00D700, dark-green ink #007a00,
blue secondary #0000FF, dark text #0F141B, body #333946, muted #6B7280.
Slide: 13.33" × 7.5" (16:9). Font: Montserrat with Helvetica fallback.
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

FONT = 'Montserrat'
MONO = 'Courier New'

SW = Inches(13.333)
SH = Inches(7.5)

TOTAL_SLIDES = 15    # bumped as slides are added


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
    add_text(slide, Inches(0.5), Inches(0.25), Inches(8), Inches(0.3),
             kicker, size=10, bold=False, color=MUTED)
    add_text(slide, Inches(0.5), Inches(0.55), Inches(12.3), Inches(0.75),
             title, size=26, bold=True, color=INK)
    if subtitle:
        add_text(slide, Inches(0.5), Inches(1.22), Inches(12.3), Inches(0.5),
                 subtitle, size=12, bold=False, color=MUTED)
    add_text(slide, Inches(0.5), Inches(7.15), Inches(9), Inches(0.25),
             'SmartSoC Solutions',
             size=9, color=MUTED)
    if footer_page:
        add_text(slide, Inches(12.5), Inches(7.15), Inches(0.7), Inches(0.25),
                 f'{footer_page}/{TOTAL_SLIDES}', size=9, bold=True, color=MUTED,
                 align=PP_ALIGN.RIGHT)


# ═══════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════
prs = Presentation()
prs.slide_width = SW; prs.slide_height = SH
blank = prs.slide_layouts[6]


# ── SLIDE 1: library-manager + mmmc-manager ────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'TOOLING',
           'library-manager  &  mmmc-manager',
           subtitle='Config generators. library-manager writes lib_config.tcl, mmmc-manager writes mmmc_config.tcl.',
           footer_page=1)

# Panel geometry
p_top = Inches(1.9); p_h = Inches(5.2)
lp_x = Inches(0.5); lp_w = Inches(6.15)
rp_x = Inches(6.8); rp_w = Inches(6.05)

def _panel(x, w, name, subtitle, header_color, features, commands, cmd_color, cmd_prefix):
    # Frame
    add_rect(s, x, p_top, w, p_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
    # Colored header band
    add_rect(s, x, p_top, w, Inches(0.5), fill=header_color)
    add_text(s, x + Inches(0.25), p_top + Inches(0.1), w - Inches(0.5), Inches(0.32),
             name, size=16, bold=True, color=WHITE, font=MONO)
    # Subtitle just under header
    add_text(s, x + Inches(0.25), p_top + Inches(0.6), w - Inches(0.5), Inches(0.3),
             subtitle, size=11, color=MUTED)

    # FEATURES section
    fs_top = p_top + Inches(1.05)
    add_text(s, x + Inches(0.25), fs_top, w - Inches(0.5), Inches(0.25),
             'FEATURES', size=9, bold=True, color=MUTED)
    fy = fs_top + Inches(0.3)
    for f in features:
        add_text(s, x + Inches(0.4), fy, w - Inches(0.55), Inches(0.28),
                 '·  ' + f, size=10, color=BODY)
        fy += Inches(0.3)

    # COMMANDS section
    cs_top = fs_top + Inches(0.35) + Inches(0.3) * len(features) + Inches(0.15)
    add_text(s, x + Inches(0.25), cs_top, w - Inches(0.5), Inches(0.25),
             'COMMANDS', size=9, bold=True, color=MUTED)
    cy = cs_top + Inches(0.3)
    for cmd, desc in commands:
        # Continuation lines (start with two spaces) render as flag/option, not full cmd
        is_cont = cmd.startswith('  ')
        line = cmd if is_cont else f'$ cbflow flow {cmd_prefix} {cmd}'
        add_text(s, x + Inches(0.4), cy, w - Inches(0.55), Inches(0.22),
                 line, size=8, bold=True, color=cmd_color, font=MONO)
        if desc:
            add_text(s, x + Inches(0.4), cy + Inches(0.2), w - Inches(0.55), Inches(0.22),
                     '  ' + desc, size=8, color=BODY)
            cy += Inches(0.42)
        else:
            cy += Inches(0.24)


# ── LEFT: library-manager ────────────────
_panel(
    lp_x, lp_w,
    name='library-manager',
    subtitle='Generates lib_config.tcl from the tech\'s library filesystem.',
    header_color=GREEN_DARK,
    features=[
        'Scans .lib / .ndm / .lef files under tech(lib_root)',
        'Categorizes libs by track × VT × corner',
        'Handles stdcell, memory, IO, analog and IP libs separately',
        'Merge mode preserves lib_config entries not in the current scan',
        'Multi-VT and multi-metal-stack aware',
        'Fail-fast if tech_config.tcl is missing',
    ],
    commands=[
        ('scan --tech <name>',                    'walk lib_root, group by prefix / corner / VT'),
        ('generate --tech <name> --tag <P0>',     'write lib_config_<tag>.tcl'),
        ('check --tech <name>',                   'verify every declared path exists on disk'),
        ('list --tech <name>',                    'show configured library sets, optional filters'),
        ('status --tech <name>',                  'signoff-readiness report per track / VT'),
        ('coverage --tech <name>',                'tracks × VTs × corners coverage matrix'),
    ],
    cmd_color=GREEN_DARK,
    cmd_prefix='library-manager',
)


# ── RIGHT: mmmc-manager ─────────────────
_panel(
    rp_x, rp_w,
    name='mmmc-manager',
    subtitle='Generates mmmc_config.tcl from the tech\'s PVT axes.',
    header_color=BLUE,
    features=[
        'Expands corners × voltages × temperatures into a full view matrix',
        'Auto-generates analysis views (modes × corners × PVT points)',
        'Filters scenario sets: setup, hold, signoff, power, all',
        'Detects PVT combos with no matching lib_set_ref in lib_config',
        'Per-project filtering — only VTs the project enables',
        'Reads the same tech_config.tcl as library-manager',
    ],
    commands=[
        ('list-corners --tech <name>',                       'show characterisation available in the tech'),
        ('generate --tech <name> --project <p> --tag <P0>',  'write mmmc_config.tcl for this project'),
        ('  --corners ss,tt,ff',                             'corner list'),
        ('  --voltages 0.72,0.80,0.88',                      'voltage list'),
        ('  --temperatures -40,25,125',                      'temperature list'),
        ('  --allow-missing',                                'proceed if a PVT combo has no lib_set_ref'),
    ],
    cmd_color=BLUE,
    cmd_prefix='mmmc-manager',
)


# ── SLIDE 2: PD flow hierarchy — 12 CBflow nodes with arrows ───────────
s = prs.slides.add_slide(blank)
add_header(s, 'PD FLOW',
           'Full hierarchy — all 12 CBflow nodes',
           subtitle='From SYNTH to PV. Arrows show dependency (what a node needs before it can run), not calendar sequence.',
           footer_page=2)

# ── Geometry ───────────────────────────────────────────────────────────
CX = Inches(6.665)             # slide horizontal center
NODE_H = Inches(0.6)           # fits expansion + tool hint (two content lines)
NODE_W = Inches(1.65)

# Vertical positions per tier (tightened gaps to make room for taller nodes)
Y_RTL   = Inches(1.85)
Y_T1    = Inches(2.27)   # SYNTH + SYNTH_PNR
Y_T2    = Inches(3.00)   # FP + FCFP
Y_T3    = Inches(3.73)   # PNR
Y_T4    = Inches(4.46)   # POPT
Y_T5    = Inches(5.20)   # 5 signoff nodes
Y_T6    = Inches(6.04)   # ECO
Y_END   = Inches(6.78)   # TAPEOUT label

LINE_W_EMU = 15000       # ~1.2 pt thick line for connectors


# ── Helpers ────────────────────────────────────────────────────────────
def _node(x, y, name, expansion, tools, color, w=NODE_W, h=NODE_H):
    """Draw a flow node — colored header stripe with acronym,
    expansion (bold ink) on line 1, tool hint (muted) on line 2."""
    add_rect(s, x, y, w, h, fill=WHITE, line=color, line_w=Pt(1.5))
    add_rect(s, x, y, w, Inches(0.22), fill=color)
    add_text(s, x, y + Inches(0.02), w, Inches(0.2),
             name, size=11, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, font=MONO)
    # Line 1 — expansion (what the acronym means)
    add_text(s, x, y + Inches(0.24), w, Inches(0.18),
             expansion, size=8, bold=True, color=INK,
             align=PP_ALIGN.CENTER)
    # Line 2 — tool hint
    add_text(s, x, y + Inches(0.42), w, Inches(0.16),
             tools, size=7, color=MUTED,
             align=PP_ALIGN.CENTER)

def _v_line(cx, y1, y2, color=MUTED):
    """Vertical connector line."""
    add_rect(s, cx - Emu(LINE_W_EMU // 2), y1, Emu(LINE_W_EMU), y2 - y1,
             fill=color, line=None)

def _h_line(x1, x2, y, color=MUTED):
    """Horizontal connector line."""
    add_rect(s, x1, y - Emu(LINE_W_EMU // 2), x2 - x1, Emu(LINE_W_EMU),
             fill=color, line=None)

def _arrowhead_down(cx, y_top, color=MUTED):
    """Small filled triangle arrowhead pointing down."""
    arr = s.shapes.add_shape(MSO_SHAPE.DOWN_ARROW,
                              cx - Inches(0.09), y_top,
                              Inches(0.18), Inches(0.14))
    arr.fill.solid(); arr.fill.fore_color.rgb = color
    arr.line.fill.background()


# ── Tier labels (right margin) ─────────────────────────────────────────
tier_labels = [
    (Y_T1, 'IMPLEMENTATION', GREEN),
    (Y_T4, 'OPTIMIZATION',   GREEN_DARK),
    (Y_T5, 'SIGNOFF',        BLUE),
    (Y_T6, 'POST-SIGNOFF',   BLUE_DARK),
]
for y_pos, label, color in tier_labels:
    add_text(s, Inches(12.05), y_pos + Inches(0.18), Inches(1.2), Inches(0.25),
             label, size=9, bold=True, color=color, align=PP_ALIGN.RIGHT)

# Left margin: input label
add_text(s, Inches(0.5), Inches(1.9), Inches(1.5), Inches(0.25),
         'INPUT', size=9, bold=True, color=MUTED)


# ── TIER 0: RTL / SDC / UPF input pill ─────────────────────────────────
add_pill(s, CX - Inches(2.0), Y_RTL, Inches(4.0), Inches(0.32),
         'RTL   ·   SDC   ·   UPF   ·   DEF',
         fill=PANEL, color=INK, size=11)

# Arrow from RTL down to SYNTH row
_v_line(CX, Y_RTL + Inches(0.32), Y_T1 - Inches(0.05))
_arrowhead_down(CX, Y_T1 - Inches(0.14))


# ── TIER 1: SYNTH_PNR + SYNTH ──────────────────────────────────────────
# SYNTH_PNR — left branch (combined synth+PNR path)
SP_X = Inches(2.35)
_node(SP_X, Y_T1, 'SYNTH_PNR', 'Synthesis + PNR', 'Innovus / FC', GREEN)

# SYNTH — main path (centered)
S_X = CX - NODE_W / 2
_node(S_X, Y_T1, 'SYNTH', 'Synthesis', 'Genus / FC', GREEN)

# Arrow from SYNTH down to floorplan tier
_v_line(CX, Y_T1 + NODE_H, Y_T2 - Inches(0.05))
_arrowhead_down(CX, Y_T2 - Inches(0.14))


# ── TIER 2: FP + FCFP ──────────────────────────────────────────────────
# FP — block floorplan (left of center)
FP_X  = CX - NODE_W - Inches(0.15)
FCFP_X = CX + Inches(0.15)
_node(FP_X,   Y_T2, 'FP',   'Floorplan', 'Innovus / FC', GREEN)
_node(FCFP_X, Y_T2, 'FCFP', 'Full-Chip Floorplan', 'Innovus / FC', GREEN)

# Fan-in from SYNTH tier → FP and FCFP (T-splitter)
_h_line(FP_X + NODE_W / 2, FCFP_X + NODE_W / 2, Y_T2 - Inches(0.14))
# Left arm down to FP
_v_line(FP_X + NODE_W / 2, Y_T2 - Inches(0.14), Y_T2 - Inches(0.02))
_arrowhead_down(FP_X + NODE_W / 2, Y_T2 - Inches(0.11))
# Right arm down to FCFP
_v_line(FCFP_X + NODE_W / 2, Y_T2 - Inches(0.14), Y_T2 - Inches(0.02))
_arrowhead_down(FCFP_X + NODE_W / 2, Y_T2 - Inches(0.11))

# Fan-in from FP + FCFP → PNR (converging arrows)
_v_line(FP_X + NODE_W / 2,   Y_T2 + NODE_H, Y_T3 - Inches(0.14))
_v_line(FCFP_X + NODE_W / 2, Y_T2 + NODE_H, Y_T3 - Inches(0.14))
_h_line(FP_X + NODE_W / 2, FCFP_X + NODE_W / 2, Y_T3 - Inches(0.14))
_v_line(CX, Y_T3 - Inches(0.14), Y_T3 - Inches(0.02))
_arrowhead_down(CX, Y_T3 - Inches(0.14))


# ── TIER 3: PNR ────────────────────────────────────────────────────────
PNR_X = CX - NODE_W / 2
_node(PNR_X, Y_T3, 'PNR', 'Place & Route', 'Innovus / FC', GREEN)

# SYNTH_PNR bypass path → PNR (L-shape from SYNTH_PNR down-right to PNR)
sp_cx = SP_X + NODE_W / 2
_v_line(sp_cx, Y_T1 + NODE_H, Y_T3 + NODE_H / 2, color=GREEN)
_h_line(sp_cx, PNR_X, Y_T3 + NODE_H / 2, color=GREEN)
# Arrowhead pointing right into PNR
arr = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW,
                          PNR_X - Inches(0.16),
                          Y_T3 + NODE_H / 2 - Inches(0.07),
                          Inches(0.16), Inches(0.14))
arr.fill.solid(); arr.fill.fore_color.rgb = GREEN
arr.line.fill.background()
# Small label on the bypass path
add_text(s, sp_cx + Inches(0.1), Y_T3 + Inches(0.03),
         Inches(2.0), Inches(0.22),
         '(combined path)', size=8, color=GREEN_DARK, font=FONT)

# Arrow PNR → POPT
_v_line(CX, Y_T3 + NODE_H, Y_T4 - Inches(0.05))
_arrowhead_down(CX, Y_T4 - Inches(0.14))


# ── TIER 4: POPT ───────────────────────────────────────────────────────
POPT_X = CX - NODE_W / 2
_node(POPT_X, Y_T4, 'POPT', 'Power Optimization', 'PT-PX / Voltus', GREEN_DARK)

# Optional feedback loop label — POPT can iterate back to PNR
add_text(s, POPT_X + NODE_W + Inches(0.15), Y_T4 + Inches(0.15),
         Inches(3.0), Inches(0.25),
         '↺  iterates back to PNR if targets unmet',
         size=8, color=MUTED, font=FONT)

# Arrow POPT down to signoff bus
_v_line(CX, Y_T4 + NODE_H, Y_T5 - Inches(0.28))
_arrowhead_down(CX, Y_T5 - Inches(0.28))


# ── TIER 5: SIGNOFF (5 parallel nodes) ─────────────────────────────────
signoff = [
    ('STA',  'Static Timing Analysis',  'PT / Tempus'),
    ('LEC',  'Logic Equivalence Check', 'Formality / Conformal'),
    ('CLP',  'Low-Power Verification',  'VC-LP / Conformal-LP'),
    ('PV',   'Physical Verification',   'ICV / Calibre'),
    ('EMIR', 'EM & IR-drop Analysis',   'RedHawk / Voltus'),
]
SN_W = Inches(1.9); SN_GAP = Inches(0.18); SN_H = Inches(0.7)
SN_TOTAL_W = 5 * SN_W + 4 * SN_GAP    # = 9.3"
SN_START = CX - SN_TOTAL_W / 2

sn_centers = []
for i, (name, expansion, tools) in enumerate(signoff):
    x = SN_START + i * (SN_W + SN_GAP)
    _node(x, Y_T5, name, expansion, tools, BLUE, w=SN_W, h=SN_H)
    sn_centers.append(x + SN_W / 2)

# Fan-out bus: horizontal line spanning all 5 signoff nodes at their top edge
BUS_Y_TOP = Y_T5 - Inches(0.15)
_h_line(sn_centers[0], sn_centers[-1], BUS_Y_TOP, color=BLUE)
# Short down segments from bus to each signoff node top
for xc in sn_centers:
    _v_line(xc, BUS_Y_TOP, Y_T5 - Inches(0.02), color=BLUE)
    _arrowhead_down(xc, Y_T5 - Inches(0.14), color=BLUE)

# Converge from 5 signoff → ECO (bottom bus)
BUS_Y_BOT = Y_T5 + SN_H + Inches(0.15)
_h_line(sn_centers[0], sn_centers[-1], BUS_Y_BOT, color=BLUE)
for xc in sn_centers:
    _v_line(xc, Y_T5 + SN_H, BUS_Y_BOT, color=BLUE)
# Down from bottom bus to ECO
_v_line(CX, BUS_Y_BOT, Y_T6 - Inches(0.05))
_arrowhead_down(CX, Y_T6 - Inches(0.14))


# ── TIER 6: ECO ────────────────────────────────────────────────────────
ECO_X = CX - NODE_W / 2
_node(ECO_X, Y_T6, 'ECO', 'Engineering Change Order', 'PT-ECO / Innovus', BLUE_DARK)

# ECO feedback label — routes fixes back through signoff
add_text(s, ECO_X + NODE_W + Inches(0.15), Y_T6 + Inches(0.15),
         Inches(3.5), Inches(0.25),
         '↺  loops back through signoff for verification',
         size=8, color=MUTED, font=FONT)

# Arrow ECO → TAPEOUT
_v_line(CX, Y_T6 + NODE_H, Y_END - Inches(0.05))
_arrowhead_down(CX, Y_END - Inches(0.14))


# ── TAPEOUT endpoint ───────────────────────────────────────────────────
add_pill(s, CX - Inches(1.5), Y_END, Inches(3.0), Inches(0.32),
         'TAPEOUT   ·   BTO → MTO',
         fill=INK, color=WHITE, size=11)


# ── SLIDE 3: SYNTH_PNR — all subnodes, deps, exit stages marked ────────
s = prs.slides.add_slide(blank)
add_header(s, 'SYNTH_PNR',
           'All subnodes of the SYNTH_PNR flow',
           subtitle='Real subnode names from SYNTH_PNR_config.tcl. Arrows are hard dependencies. Amber-badged subnodes are exit gates.',
           footer_page=3)

# Real subnodes from PD/config/flow/v1.0.0/node_configs/SYNTH_PNR_config.tcl
# stages: rtl1 sdc1 upf1 init_design1 synthesis1 place1 cts1 cts_opt1
#         route1 pro1 signoff1 export_data1 release_data1

LINE_W_EMU_S3 = 15000

def _connector_v(cx, y1, y2, color=MUTED):
    add_rect(s, cx - Emu(LINE_W_EMU_S3 // 2), y1, Emu(LINE_W_EMU_S3),
             y2 - y1, fill=color, line=None)

def _connector_h(x1, x2, y, color=MUTED):
    add_rect(s, x1, y - Emu(LINE_W_EMU_S3 // 2), x2 - x1,
             Emu(LINE_W_EMU_S3), fill=color, line=None)

def _arrow_r(x_tip, y_center, color=MUTED, w=Inches(0.16)):
    """Right-pointing arrowhead ending at (x_tip, y_center)."""
    arr = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW,
                              x_tip - w, y_center - Inches(0.07),
                              w, Inches(0.14))
    arr.fill.solid(); arr.fill.fore_color.rgb = color
    arr.line.fill.background()

def _arrow_d(cx, y_tip, color=MUTED, h=Inches(0.16)):
    """Down-pointing arrowhead ending at (cx, y_tip)."""
    arr = s.shapes.add_shape(MSO_SHAPE.DOWN_ARROW,
                              cx - Inches(0.07), y_tip - h,
                              Inches(0.14), h)
    arr.fill.solid(); arr.fill.fore_color.rgb = color
    arr.line.fill.background()

def _stage(x, y, w, h, name, node_type, color, exit_tag=None):
    """One flow subnode. Amber badge above it if it's an exit stage."""
    if exit_tag:
        # Amber ribbon on top of the stage box
        add_rect(s, x, y - Inches(0.28), w, Inches(0.24),
                 fill=AMBER, line=AMBER_DARK, line_w=Pt(0.75))
        add_text(s, x, y - Inches(0.26), w, Inches(0.2),
                 exit_tag, size=9, bold=True, color=WHITE,
                 align=PP_ALIGN.CENTER, font=MONO)
    # Stage box
    box_line_w = Pt(2.0) if exit_tag else Pt(1.25)
    add_rect(s, x, y, w, h, fill=WHITE, line=color, line_w=box_line_w)
    add_rect(s, x, y, w, Inches(0.22), fill=color)
    add_text(s, x, y + Inches(0.02), w, Inches(0.2),
             name, size=10, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, font=MONO)
    add_text(s, x, y + Inches(0.26), w, Inches(0.28),
             node_type, size=8, color=BODY,
             align=PP_ALIGN.CENTER)

# ── ROW 0: Input subnodes (rtl1, sdc1, upf1) ──────────────────────────
IN_Y = Inches(2.05)
IN_W = Inches(1.5); IN_H = Inches(0.55)
IN_GAP = Inches(0.25)
IN_TOTAL = 3 * IN_W + 2 * IN_GAP    # 5.0"
IN_START = Inches(0.7)
inputs = [
    ('rtl1',  'RTL netlist'),
    ('sdc1',  'timing constraints'),
    ('upf1',  'power intent'),
]
in_centers = []
for i, (name, hint) in enumerate(inputs):
    x = IN_START + i * (IN_W + IN_GAP)
    _stage(x, IN_Y, IN_W, IN_H, name, hint, MUTED)
    in_centers.append(x + IN_W / 2)

# Section label on the right
add_text(s, Inches(6.5), IN_Y + Inches(0.1), Inches(6.5), Inches(0.3),
         'Three input subnodes → converge into init_design1',
         size=11, bold=True, color=MUTED)
add_text(s, Inches(6.5), IN_Y + Inches(0.32), Inches(6.5), Inches(0.25),
         'inputs land in the run dir, then the execution chain kicks off',
         size=9, color=MUTED)


# ── ROW 1: main execution chain, part 1 (5 stages) ────────────────────
R1_Y = Inches(3.35)
STG_W = Inches(2.28); STG_H = Inches(0.7)
STG_GAP = Inches(0.14)
STG_START = Inches(0.5)

row1 = [
    ('init_design1', 'floorplan + PG',    GREEN,      'FP_EXIT'),
    ('synthesis1',   'synthesis',         GREEN,       None),
    ('place1',       'placement',         GREEN_DARK, 'PLACE_EXIT'),
    ('cts1',         'clock tree',        GREEN_DARK,  None),
    ('cts_opt1',     'CTS optimization',  GREEN_DARK, 'CTS_EXIT'),
]
r1_centers = []
r1_positions = []
for i, (name, ntype, color, exit_tag) in enumerate(row1):
    x = STG_START + i * (STG_W + STG_GAP)
    _stage(x, R1_Y, STG_W, STG_H, name, ntype, color, exit_tag=exit_tag)
    r1_centers.append(x + STG_W / 2)
    r1_positions.append(x)

# Input → init_design1 fan-in
in_conv_y = R1_Y - Inches(0.15)
_connector_h(in_centers[0], in_centers[-1], in_conv_y, color=MUTED)
for xc in in_centers:
    _connector_v(xc, IN_Y + IN_H, in_conv_y, color=MUTED)
# Drop-down from center of input bus to init_design1
init_cx = r1_centers[0]
_connector_v(init_cx, in_conv_y, R1_Y, color=MUTED)
# Also draw connector from input bus midpoint to init_design1 column
bus_mid = (in_centers[0] + in_centers[-1]) // 2
_connector_h(min(bus_mid, init_cx), max(bus_mid, init_cx), in_conv_y, color=MUTED)
_arrow_d(init_cx, R1_Y, color=MUTED)

# Row 1 horizontal arrows between stages
for i in range(len(row1) - 1):
    x_from = r1_positions[i] + STG_W
    x_to   = r1_positions[i+1]
    y_mid  = R1_Y + STG_H / 2
    _connector_h(x_from, x_to, y_mid, color=MUTED)
    _arrow_r(x_to, y_mid, color=MUTED)


# ── ROW 1 → ROW 2 wrap (cts_opt1 → route1) ─────────────────────────────
# End of row 1 (cts_opt1) → wraps down and left to start of row 2 (route1)
R2_Y = Inches(4.85)
end_r1_x = r1_positions[-1] + STG_W       # right edge of cts_opt1
wrap_y   = R2_Y - Inches(0.2)              # horizontal wrap-back level
_connector_h(end_r1_x, end_r1_x + Inches(0.25),
             R1_Y + STG_H / 2, color=MUTED)
_connector_v(end_r1_x + Inches(0.25),
             R1_Y + STG_H / 2, wrap_y, color=MUTED)
_connector_h(STG_START + STG_W / 2, end_r1_x + Inches(0.25),
             wrap_y, color=MUTED)
_connector_v(STG_START + STG_W / 2, wrap_y, R2_Y, color=MUTED)
_arrow_d(STG_START + STG_W / 2, R2_Y, color=MUTED)


# ── ROW 2: main execution chain, part 2 (5 stages) ────────────────────
row2 = [
    ('route1',        'routing',            GREEN_DARK,  None),
    ('pro1',          'post-route opt',     GREEN_DARK, 'PRO_EXIT'),
    ('signoff1',      'signoff',            BLUE,        None),
    ('export_data1',  'output manifest',    BLUE_DARK,   None),
    ('release_data1', 'publish release',    BLUE_DARK,   None),
]
r2_positions = []
for i, (name, ntype, color, exit_tag) in enumerate(row2):
    x = STG_START + i * (STG_W + STG_GAP)
    _stage(x, R2_Y, STG_W, STG_H, name, ntype, color, exit_tag=exit_tag)
    r2_positions.append(x)

# Row 2 horizontal arrows between stages
for i in range(len(row2) - 1):
    x_from = r2_positions[i] + STG_W
    x_to   = r2_positions[i+1]
    y_mid  = R2_Y + STG_H / 2
    _connector_h(x_from, x_to, y_mid, color=MUTED)
    _arrow_r(x_to, y_mid, color=MUTED)


# ── LOW-POWER CALLOUT (points at init_design1 / floorplan) ─────────────
LP_Y = Inches(6.15); LP_H = Inches(0.85)
LP_X = Inches(0.5);  LP_W = Inches(12.35)
add_rect(s, LP_X, LP_Y, LP_W, LP_H, fill=BLUE_TINT, line=BLUE, line_w=Pt(1))

# Left column of callout — the flag
add_rect(s, LP_X, LP_Y, Inches(0.14), LP_H, fill=BLUE)
add_text(s, LP_X + Inches(0.3), LP_Y + Inches(0.08),
         Inches(11.5), Inches(0.3),
         'Low-power implementation lives in init_design1 (floorplan)',
         size=12, bold=True, color=BLUE)
add_text(s, LP_X + Inches(0.3), LP_Y + Inches(0.38),
         Inches(11.7), Inches(0.5),
         "Power domains and PG mesh for switched domains are built here. "
         "Isolation and level-shifter cells inserted per UPF. Retention "
         "flops in place before synthesis lands its netlist. If low-power "
         "is wrong at init_design1, everything downstream inherits it.",
         size=10, color=BODY)


# ── SLIDE 4: Full-chip hierarchical flow — FCFP + design_hierarchy ─────
s = prs.slides.add_slide(blank)
add_header(s, 'HIERARCHICAL',
           'Full-chip flow — FCFP owns the top, blocks flow in parallel',
           subtitle='Example: bumblebee project. chip_top → cpu_complex → cpu_core → sub-blocks. Real design_hierarchy variables from PD/config/project/bumblebee.',
           footer_page=4)

# ── SECTION 1: FCFP + integration + PV signoff (3 top cards) ──────────
ov_top = Inches(1.85); ov_h = Inches(1.15)
top_card_w = Inches(4.05); top_card_gap = Inches(0.1)
top_x0 = Inches(0.5)

def _top_card(x, title, color, bullets):
    add_rect(s, x, ov_top, top_card_w, ov_h, fill=WHITE, line=color, line_w=Pt(1.25))
    add_rect(s, x, ov_top, top_card_w, Inches(0.28), fill=color)
    add_text(s, x + Inches(0.15), ov_top + Inches(0.04),
             top_card_w - Inches(0.3), Inches(0.22),
             title, size=10, bold=True, color=WHITE, font=MONO)
    py = ov_top + Inches(0.34)
    for pt in bullets:
        add_text(s, x + Inches(0.2), py, top_card_w - Inches(0.35), Inches(0.24),
                 '·  ' + pt, size=8, color=BODY)
        py += Inches(0.24)

# Card 1: FCFP
_top_card(
    top_x0, 'FCFP · Full-Chip Floorplan', GREEN_DARK,
    ['Top-level chip_top layout, IO ring, top PG grid',
     "Defines each block's boundary + placement region",
     'Top clock + top-level nets; blocks see the boundary as a hard interface'],
)

# Card 2: Hierarchical integration
_top_card(
    top_x0 + top_card_w + top_card_gap, 'Hierarchical integration', BLUE,
    ['Blocks flow in parallel — full SYNTH → PNR → signoff independently',
     'Blocks return ETM (timing) + ILM (interface logic) + LEF/LIB',
     'chip_top integrates: hierarchical STA on ETMs; boundary reconciliation'],
)

# Card 3: Full-chip PV integration & signoff (new)
_top_card(
    top_x0 + 2 * (top_card_w + top_card_gap), 'Full-chip PV integration & signoff', AMBER_DARK,
    ['Merge block GDS + top routing → chip DRC / LVS / antenna / density',
     'Fill insertion + boundary rules between blocks (foundry deck runsets)',
     'ERC + reliability at chip level. PV sign-off gates MTO.'],
)


# ── SECTION 2: Hierarchy tree diagram ──────────────────────────────────
# Real hierarchy from bumblebee_config.tcl: chip_top → 4 DL2 → several DL3 → DL4 (for cpu_core)
tree_top = Inches(3.15); tree_h = Inches(2.2)

# Left column label
add_text(s, Inches(0.5), tree_top + Inches(0.05), Inches(1.5), Inches(0.25),
         'DESIGN HIERARCHY', size=9, bold=True, color=MUTED)
add_text(s, Inches(0.5), tree_top + Inches(0.28), Inches(1.5), Inches(0.25),
         '(bumblebee project)', size=8, color=MUTED)

# Level labels on left margin
lvl_x = Inches(0.5)
lvl_labels = [
    (tree_top + Inches(0.65), 'DL1'),
    (tree_top + Inches(1.15), 'DL2'),
    (tree_top + Inches(1.65), 'DL3'),
]
for ly, lbl in lvl_labels:
    add_pill(s, lvl_x, ly, Inches(0.5), Inches(0.24), lbl,
             fill=INK, color=WHITE, size=8)

# chip_top box (DL1) — centered at CX
CX_S4 = Inches(6.8)
CT_W = Inches(1.8); CT_H = Inches(0.4)
CT_X = CX_S4 - CT_W / 2
CT_Y = tree_top + Inches(0.55)
add_rect(s, CT_X, CT_Y, CT_W, CT_H, fill=INK, line=None)
add_text(s, CT_X, CT_Y + Inches(0.03), CT_W, Inches(0.2),
         'chip_top', size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER, font=MONO)
add_text(s, CT_X, CT_Y + Inches(0.23), CT_W, Inches(0.15),
         'Full chip (DL1)', size=7, color=WHITE, align=PP_ALIGN.CENTER)

# 4 DL2 subsystem boxes
dl2 = [
    ('cpu_complex',   'CPU + cache',      GREEN_DARK, True),   # will be expanded to DL3
    ('memory_subsys', 'Memory ctrl',      GREEN,      False),
    ('io_subsys',     'IO peripherals',   GREEN,      False),
    ('power_mgmt',    'Power mgmt',       GREEN,      False),
]
DL2_W = Inches(2.5); DL2_H = Inches(0.4); DL2_GAP = Inches(0.15)
DL2_TOTAL_W = 4 * DL2_W + 3 * DL2_GAP
DL2_START = CX_S4 - DL2_TOTAL_W / 2
DL2_Y = tree_top + Inches(1.15)

dl2_centers = []
for i, (name, desc, color, focus) in enumerate(dl2):
    x = DL2_START + i * (DL2_W + DL2_GAP)
    fill = color if focus else WHITE
    line_col = color
    text_col = WHITE if focus else INK
    desc_col = WHITE if focus else MUTED
    add_rect(s, x, DL2_Y, DL2_W, DL2_H, fill=fill, line=line_col, line_w=Pt(1.25))
    add_text(s, x, DL2_Y + Inches(0.03), DL2_W, Inches(0.2),
             name, size=10, bold=True, color=text_col,
             align=PP_ALIGN.CENTER, font=MONO)
    add_text(s, x, DL2_Y + Inches(0.23), DL2_W, Inches(0.15),
             desc, size=7, color=desc_col, align=PP_ALIGN.CENTER)
    dl2_centers.append(x + DL2_W / 2)

# Fan-out from chip_top → 4 DL2 subsystems
fan_bus_y = CT_Y + CT_H + Inches(0.15)
add_rect(s, min(dl2_centers), fan_bus_y - Emu(LINE_W_EMU // 2),
         max(dl2_centers) - min(dl2_centers), Emu(LINE_W_EMU),
         fill=MUTED, line=None)
add_rect(s, CX_S4 - Emu(LINE_W_EMU // 2), CT_Y + CT_H,
         Emu(LINE_W_EMU), fan_bus_y - (CT_Y + CT_H),
         fill=MUTED, line=None)
for xc in dl2_centers:
    add_rect(s, xc - Emu(LINE_W_EMU // 2), fan_bus_y,
             Emu(LINE_W_EMU), DL2_Y - fan_bus_y,
             fill=MUTED, line=None)

# DL3 expansion under cpu_complex (the focused subsystem)
dl3 = ['cpu_core', 'l1_cache', 'l2_cache']
DL3_Y = tree_top + Inches(1.65)
DL3_W = Inches(1.5); DL3_H = Inches(0.35); DL3_GAP = Inches(0.1)
DL3_TOTAL_W = 3 * DL3_W + 2 * DL3_GAP
DL3_START = dl2_centers[0] - DL3_TOTAL_W / 2
dl3_centers = []
for i, name in enumerate(dl3):
    x = DL3_START + i * (DL3_W + DL3_GAP)
    color = BLUE_DARK if name == 'cpu_core' else BLUE
    fill = color if name == 'cpu_core' else WHITE
    text_col = WHITE if name == 'cpu_core' else INK
    add_rect(s, x, DL3_Y, DL3_W, DL3_H, fill=fill, line=color, line_w=Pt(1.0))
    add_text(s, x, DL3_Y + Inches(0.06), DL3_W, Inches(0.22),
             name, size=9, bold=True, color=text_col,
             align=PP_ALIGN.CENTER, font=MONO)
    dl3_centers.append(x + DL3_W / 2)

# Connector: cpu_complex → 3 DL3 blocks
dl3_bus_y = DL2_Y + DL2_H + Inches(0.1)
add_rect(s, min(dl3_centers), dl3_bus_y - Emu(LINE_W_EMU // 2),
         max(dl3_centers) - min(dl3_centers), Emu(LINE_W_EMU),
         fill=GREEN_DARK, line=None)
add_rect(s, dl2_centers[0] - Emu(LINE_W_EMU // 2), DL2_Y + DL2_H,
         Emu(LINE_W_EMU), dl3_bus_y - (DL2_Y + DL2_H),
         fill=GREEN_DARK, line=None)
for xc in dl3_centers:
    add_rect(s, xc - Emu(LINE_W_EMU // 2), dl3_bus_y,
             Emu(LINE_W_EMU), DL3_Y - dl3_bus_y,
             fill=GREEN_DARK, line=None)

# DL4 note under cpu_core (alu / fetch_unit / decode_unit)
dl4_y = DL3_Y + DL3_H + Inches(0.05)
dl4_text = 'cpu_core → children: alu · fetch_unit · decode_unit'
add_text(s, DL3_START - Inches(0.5), dl4_y, Inches(6.0), Inches(0.22),
         dl4_text, size=8, bold=True, color=BLUE_DARK, font=MONO)

# Note next to memory/io/power DL2 boxes
note_y = DL2_Y + DL2_H + Inches(0.15)
add_text(s, dl2_centers[1] - Inches(2.0), note_y, Inches(9), Inches(0.4),
         'each DL2 has its own DL3 children — omitted here for space '
         '(mem_arbiter, ddr_ctrl · pcie_ctrl, gpio_ctrl, uart_ctrl, spi_ctrl · '
         'power_ctrl, clock_mgr, reset_ctrl)',
         size=7, color=MUTED)


# ── SECTION 3: TCL code snippet — real design_hierarchy variables ──────
code_top = Inches(5.5); code_h = Inches(1.6)
add_rect(s, Inches(0.5), code_top, Inches(12.35), code_h, fill=INK, line=None)
add_text(s, Inches(0.65), code_top + Inches(0.08), Inches(12), Inches(0.24),
         'PD/config/project/bumblebee/v1.0.0/bumblebee_config.tcl   —   real design_hierarchy variables',
         size=9, bold=True, color=GREEN, font=MONO)

code_lines = [
    ('set project(design_hierarchy) {',                             WHITE),
    ('    chip_top {',                                              WHITE),
    ('        description "Full chip top level (DL1)"',             MUTED),
    ('        level "DL1"   parent ""',                             MUTED),
    ('        children {cpu_complex memory_subsys io_subsys power_mgmt}', GREEN),
    ('    }',                                                       WHITE),
    ('    cpu_complex {',                                           WHITE),
    ('        description "CPU and cache subsystem (DL2)"',         MUTED),
    ('        level "DL2"   parent "chip_top"',                     MUTED),
    ('        children {cpu_core l1_cache l2_cache}',               GREEN),
    ('    }',                                                       WHITE),
    ('    cpu_core {  level "DL3"  parent "cpu_complex"  children {alu fetch_unit decode_unit}  }', GREEN),
    ('}',                                                           WHITE),
    ('# Derived automatically',                                     MUTED),
    ('set project(valid_design_names) [dict keys $project(design_hierarchy)]', AMBER),
    ('set project(block_list) <DL2 subsystem list>', AMBER),
]
cy = code_top + Inches(0.36)
for line, color in code_lines:
    add_text(s, Inches(0.7), cy, Inches(12.1), Inches(0.16),
             line, size=8, color=color, font=MONO)
    cy += Inches(0.078)


# ── SLIDE 5: Zero-ECO cycle — pre-cleanup methodology ─────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'METHODOLOGY · ZERO-ECO',
           'Zero-ECO cycle — clean the DB before the real ECOs arrive',
           subtitle='Preparatory DRV cleanup after BTO. When functional / timing ECOs land, they start from a clean base — fewer iterations, faster tapeout.',
           footer_page=5)

# ── SECTION A: Concept strip (top) ─────────────────────────────────────
ca_top = Inches(1.85); ca_h = Inches(0.9)
add_rect(s, Inches(0.5), ca_top, Inches(12.35), ca_h, fill=PANEL, line=LINE, line_w=Pt(0.5))
add_rect(s, Inches(0.5), ca_top, Inches(0.15), ca_h, fill=AMBER)
add_text(s, Inches(0.85), ca_top + Inches(0.13), Inches(11.8), Inches(0.35),
         'Fix the DRVs before the real ECOs land.',
         size=17, bold=True, color=INK)
add_text(s, Inches(0.85), ca_top + Inches(0.55), Inches(11.8), Inches(0.35),
         "Every functional ECO creates new DRVs on top of whatever's already sitting in the DB. "
         "If transition, cap, fanout and long-net violations are cleaned first, each real ECO becomes smaller — and the schedule to MTO shortens.",
         size=10, color=BODY)


# ── SECTION B: Two columns — DRVs cleaned + methodology steps ─────────
sb_top = Inches(2.9); sb_h = Inches(2.85)

# Left column: WHAT WE CLEAN
lc_x = Inches(0.5); lc_w = Inches(6.15)
add_rect(s, lc_x, sb_top, lc_w, sb_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, lc_x, sb_top, lc_w, Inches(0.4), fill=GREEN_DARK)
add_text(s, lc_x + Inches(0.2), sb_top + Inches(0.08), lc_w - Inches(0.4), Inches(0.28),
         'What gets cleaned', size=12, bold=True, color=WHITE, font=MONO)

drvs = [
    ('Max transition',  'Weak drivers, wrong buffer choice — upsize or buffer the endpoints'),
    ('Max capacitance', 'Net loading over spec — buffer insertion or cell upsize'),
    ('Max fanout',      'What HFN synthesis missed — force clone or buffer tree'),
    ('Long nets',       'Route-length beyond spec — repeaters on the long haul'),
    ('Antenna',         'Charge accumulation — diode insertion or jog to higher metal'),
    ('Weak hold',       'Not violations yet — safety hold buffers on near-zero margin paths'),
]
dy = sb_top + Inches(0.55)
for name, desc in drvs:
    add_rect(s, lc_x + Inches(0.2), dy, Inches(1.5), Inches(0.32),
             fill=GREEN_TINT, line=GREEN_DARK, line_w=Pt(0.5))
    add_text(s, lc_x + Inches(0.2), dy + Inches(0.06), Inches(1.5), Inches(0.22),
             name, size=9, bold=True, color=GREEN_DARK, align=PP_ALIGN.CENTER)
    add_text(s, lc_x + Inches(1.8), dy + Inches(0.03), lc_w - Inches(1.95), Inches(0.32),
             desc, size=9, color=BODY)
    dy += Inches(0.37)


# Right column: THE METHODOLOGY
rc_x = Inches(6.8); rc_w = Inches(6.05)
add_rect(s, rc_x, sb_top, rc_w, sb_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, rc_x, sb_top, rc_w, Inches(0.4), fill=BLUE)
add_text(s, rc_x + Inches(0.2), sb_top + Inches(0.08), rc_w - Inches(0.4), Inches(0.28),
         'The 5 steps', size=12, bold=True, color=WHITE, font=MONO)

steps = [
    ('DRV survey',        "Pull the full violator list from PT on the BTO release. "
                          "Bucket by category."),
    ('Compute the fix',   "PT-ECO writes the change script — buffer / upsize / delay-cell insertion. "
                          "No functional touch."),
    ('Apply, route-preserve', "Innovus or FC applies the ECO with existing routes locked. "
                              "Only the ECO cells change."),
    ('Re-verify (touched only)', "STA + LEC + CLP re-run on the ECO-touched netlist. "
                                  "Untouched signoff stays valid."),
    ('Publish ECO_READY tag', "Release the cleaned DB as P{n}_ECO_READY. "
                              "Real ECOs start from here."),
]
sy = sb_top + Inches(0.55)
for i, (name, desc) in enumerate(steps):
    # Numbered circle
    add_rect(s, rc_x + Inches(0.2), sy, Inches(0.35), Inches(0.35), fill=BLUE)
    add_text(s, rc_x + Inches(0.2), sy + Inches(0.05), Inches(0.35), Inches(0.28),
             str(i+1), size=13, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
    add_text(s, rc_x + Inches(0.65), sy + Inches(0.02), rc_w - Inches(0.85), Inches(0.22),
             name, size=10, bold=True, color=INK)
    add_text(s, rc_x + Inches(0.65), sy + Inches(0.22), rc_w - Inches(0.85), Inches(0.28),
             desc, size=8, color=BODY)
    sy += Inches(0.44)


# ── SECTION C: Schedule impact ─────────────────────────────────────────
sc_top = Inches(5.9); sc_h = Inches(1.2)

# Left panel — WITHOUT zero-ECO
sc_left_x = Inches(0.5); sc_left_w = Inches(6.15)
add_rect(s, sc_left_x, sc_top, sc_left_w, sc_h, fill=WHITE, line=MUTED, line_w=Pt(1))
add_pill(s, sc_left_x + Inches(0.15), sc_top + Inches(0.12), Inches(1.6), Inches(0.28),
         'WITHOUT zero-ECO', fill=MUTED, color=WHITE, size=9)
add_text(s, sc_left_x + Inches(0.15), sc_top + Inches(0.5),
         sc_left_w - Inches(0.3), Inches(0.3),
         'Every real ECO fights the baseline DRVs too',
         size=11, bold=True, color=INK)
add_text(s, sc_left_x + Inches(0.15), sc_top + Inches(0.8),
         sc_left_w - Inches(0.3), Inches(0.35),
         '3-4 iteration loops per real ECO. Each loop touches placement / routing / signoff. Long path to MTO.',
         size=9, color=BODY)

# Right panel — WITH zero-ECO
sc_right_x = Inches(6.8); sc_right_w = Inches(6.05)
add_rect(s, sc_right_x, sc_top, sc_right_w, sc_h, fill=GREEN_TINT, line=GREEN_DARK, line_w=Pt(1))
add_pill(s, sc_right_x + Inches(0.15), sc_top + Inches(0.12), Inches(1.6), Inches(0.28),
         'WITH zero-ECO', fill=GREEN_DARK, color=WHITE, size=9)
add_text(s, sc_right_x + Inches(0.15), sc_top + Inches(0.5),
         sc_right_w - Inches(0.3), Inches(0.3),
         'Real ECOs only fix their own delta',
         size=11, bold=True, color=INK)
add_text(s, sc_right_x + Inches(0.15), sc_top + Inches(0.8),
         sc_right_w - Inches(0.3), Inches(0.35),
         '1-2 iterations per real ECO. Cleaner risk profile. Schedule to MTO shortens by weeks per tapeout.',
         size=9, color=BODY)


# ── SLIDE 6: Clock tree topologies — H-tree, mesh, spine + CPU hybrid ─
s = prs.slides.add_slide(blank)
add_header(s, 'METHODOLOGY · CLOCK TREE',
           'Clock tree topologies — pick the one the block asks for',
           subtitle='H-tree, mesh, spine — each earns its place. CPU-class blocks need tighter skew than any single topology gives.',
           footer_page=6)

# ── Small helpers for the topology mini-diagrams ──────────────────────
LW = 15000  # ~1.2 pt line

def _line_v(cx, y1, y2, color=INK, w=LW):
    add_rect(s, cx - Emu(w // 2), y1, Emu(w), y2 - y1, fill=color, line=None)

def _line_h(x1, x2, cy, color=INK, w=LW):
    add_rect(s, x1, cy - Emu(w // 2), x2 - x1, Emu(w), fill=color, line=None)

def _dot(x, y, size=Inches(0.07), color=INK):
    add_rect(s, x - size / 2, y - size / 2, size, size, fill=color, line=None)


# ── SECTION A: Concept strip (one-liner) ──────────────────────────────
ca_top = Inches(1.85); ca_h = Inches(0.5)
add_rect(s, Inches(0.5), ca_top, Inches(12.35), ca_h, fill=PANEL, line=LINE, line_w=Pt(0.5))
add_rect(s, Inches(0.5), ca_top, Inches(0.15), ca_h, fill=BLUE)
add_text(s, Inches(0.85), ca_top + Inches(0.11), Inches(11.8), Inches(0.3),
         'Match the topology to the block. Getting it wrong costs area, power, or timing — sometimes all three.',
         size=12, bold=True, color=INK)


# ── SECTION B: Three topology cards ───────────────────────────────────
sb_top = Inches(2.55); sb_h = Inches(2.75)
card_w = Inches(3.95); card_gap = Inches(0.175)
card_x0 = Inches(0.5)

def _card_shell(x, color, title):
    add_rect(s, x, sb_top, card_w, sb_h, fill=WHITE, line=color, line_w=Pt(1.25))
    add_rect(s, x, sb_top, card_w, Inches(0.36), fill=color)
    add_text(s, x, sb_top + Inches(0.07), card_w, Inches(0.24),
             title, size=12, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, font=MONO)

def _card_props(x, when, skew, latency, power):
    py = sb_top + Inches(2.05)
    labels = [('when',    when,    INK),
              ('skew',    skew,    GREEN_DARK),
              ('latency', latency, GREEN_DARK),
              ('power',   power,   BLUE)]
    for lab, val, col in labels:
        add_text(s, x + Inches(0.2), py, Inches(0.6), Inches(0.16),
                 lab + ':', size=7, bold=True, color=MUTED, font=MONO)
        add_text(s, x + Inches(0.9), py, card_w - Inches(1.0), Inches(0.16),
                 val, size=8, color=col)
        py += Inches(0.16)

# ── Card 1: H-TREE ────────────
c1_x = card_x0
_card_shell(c1_x, GREEN_DARK, 'H-TREE')
# H-tree mini diagram — recursive H (2 levels)
diag_cx = c1_x + card_w / 2
diag_cy = sb_top + Inches(1.15)
# Level 1: one horizontal + two vertical drops
_line_h(diag_cx - Inches(1.0), diag_cx + Inches(1.0), diag_cy, color=GREEN_DARK, w=25000)
_line_v(diag_cx - Inches(1.0), diag_cy - Inches(0.55), diag_cy + Inches(0.55), color=GREEN_DARK, w=25000)
_line_v(diag_cx + Inches(1.0), diag_cy - Inches(0.55), diag_cy + Inches(0.55), color=GREEN_DARK, w=25000)
# Level 2: small H at each end of the level-1 verticals
for xoff in (-1.0, 1.0):
    for yoff in (-0.55, 0.55):
        cx2 = diag_cx + Inches(xoff); cy2 = diag_cy + Inches(yoff)
        _line_h(cx2 - Inches(0.35), cx2 + Inches(0.35), cy2, color=GREEN_DARK)
        _line_v(cx2 - Inches(0.35), cy2 - Inches(0.2), cy2 + Inches(0.2), color=GREEN_DARK)
        _line_v(cx2 + Inches(0.35), cy2 - Inches(0.2), cy2 + Inches(0.2), color=GREEN_DARK)
        # Leaf dots
        for xleaf in (-0.35, 0.35):
            for yleaf in (-0.2, 0.2):
                _dot(cx2 + Inches(xleaf), cy2 + Inches(yleaf), color=GREEN_DARK)
_card_props(c1_x,
            when='regular arrays, well-behaved logic',
            skew='good, geometric',
            latency='moderate',
            power='moderate')

# ── Card 2: MESH ────────────
c2_x = card_x0 + card_w + card_gap
_card_shell(c2_x, BLUE, 'MESH')
diag_cx = c2_x + card_w / 2
diag_cy = sb_top + Inches(1.15)
# Draw a 5x4 grid
xs = [diag_cx + Inches(x) for x in [-1.3, -0.65, 0.0, 0.65, 1.3]]
ys = [diag_cy + Inches(y) for y in [-0.6, -0.2, 0.2, 0.6]]
for yy in ys:
    _line_h(xs[0], xs[-1], yy, color=BLUE, w=15000)
for xx in xs:
    _line_v(xx, ys[0], ys[-1], color=BLUE, w=15000)
# Dots at every intersection
for xx in xs:
    for yy in ys:
        _dot(xx, yy, color=BLUE, size=Inches(0.06))
_card_props(c2_x,
            when='dense, tightly-coupled distribution',
            skew='excellent (all leaves near a wire)',
            latency='low',
            power='high (wire cap)')

# ── Card 3: SPINE ────────────
c3_x = card_x0 + 2 * (card_w + card_gap)
_card_shell(c3_x, AMBER_DARK, 'SPINE')
diag_cx = c3_x + card_w / 2
diag_cy = sb_top + Inches(1.15)
# Main spine — thick horizontal
_line_h(diag_cx - Inches(1.4), diag_cx + Inches(1.4), diag_cy, color=AMBER_DARK, w=35000)
# Vertical ribs off the spine — 6 ribs on each side (12 total)
rib_xs = [diag_cx + Inches(x) for x in [-1.2, -0.75, -0.3, 0.15, 0.6, 1.05]]
for i, xx in enumerate(rib_xs):
    # Alternate up and down for visual variety
    if i % 2 == 0:
        _line_v(xx, diag_cy - Inches(0.55), diag_cy, color=AMBER_DARK)
        _dot(xx, diag_cy - Inches(0.55), color=AMBER_DARK)
    else:
        _line_v(xx, diag_cy, diag_cy + Inches(0.55), color=AMBER_DARK)
        _dot(xx, diag_cy + Inches(0.55), color=AMBER_DARK)
_card_props(c3_x,
            when='elongated or asymmetric blocks',
            skew='good along spine axis',
            latency='low-to-moderate',
            power='moderate')


# ── SECTION C: CPU hybrid callout ─────────────────────────────────────
sc_top = Inches(5.5); sc_h = Inches(1.55)
add_rect(s, Inches(0.5), sc_top, Inches(12.35), sc_h, fill=INK, line=None)
# Amber accent bar
add_rect(s, Inches(0.5), sc_top, Inches(0.15), sc_h, fill=AMBER)

# Title
add_text(s, Inches(0.85), sc_top + Inches(0.12), Inches(11.8), Inches(0.3),
         'CPU-class blocks — one topology is never enough',
         size=13, bold=True, color=WHITE)

# Body text
add_text(s, Inches(0.85), sc_top + Inches(0.44), Inches(7.8), Inches(0.6),
         "A CPU pipeline needs sub-20 ps skew across thousands of registers "
         "clustered tight, with latency low enough not to eat cycle time. "
         "No single topology holds that at real die sizes — so we layer them.",
         size=9, color=WHITE)

# Right side: layered structure
lay_x = Inches(8.9)
add_text(s, lay_x, sc_top + Inches(0.45), Inches(3.9), Inches(0.22),
         'HYBRID STRUCTURE', size=8, bold=True, color=AMBER, font=MONO)
layers = [
    ('Top',   'H-tree divides the block into quadrants',                GREEN_DARK),
    ('Mid',   'Spine feeds each quadrant along its length',             AMBER_DARK),
    ('Local', 'Mesh at every register cluster — tight local skew',      BLUE),
]
ly = sc_top + Inches(0.67)
for tag, desc, col in layers:
    add_pill(s, lay_x, ly, Inches(0.55), Inches(0.2), tag,
             fill=col, color=WHITE, size=8)
    add_text(s, lay_x + Inches(0.65), ly + Inches(0.03), Inches(3.3), Inches(0.2),
             desc, size=8, color=WHITE)
    ly += Inches(0.24)

# Bottom band: what it gets you
bp_y = sc_top + sc_h - Inches(0.3)
add_text(s, Inches(0.85), bp_y, Inches(12), Inches(0.22),
         'Result:  sub-20 ps skew across the CPU  ·  latency close to mesh  ·  '
         'power close to H-tree  ·  same MMMC scenarios drive both stages',
         size=9, bold=True, color=AMBER)


# ═══════════════════════════════════════════════════════════════════════
# DEEP-DIVE HELPERS — shared across DD1..DD8
# ═══════════════════════════════════════════════════════════════════════

def dd_column(x, y, w, h, title_text, title_color, bullets,
              text_size=9, title_size=11):
    """A titled column with a colored header stripe and a bulleted body."""
    add_rect(s, x, y, w, h, fill=WHITE, line=LINE, line_w=Pt(0.75))
    add_rect(s, x, y, w, Inches(0.36), fill=title_color)
    add_text(s, x + Inches(0.15), y + Inches(0.06), w - Inches(0.3), Inches(0.24),
             title_text, size=title_size, bold=True, color=WHITE, font=MONO)
    by = y + Inches(0.45)
    for b in bullets:
        add_text(s, x + Inches(0.2), by, w - Inches(0.35), Inches(0.32),
                 '·  ' + b, size=text_size, color=BODY)
        by += Inches(0.28)


# ── SLIDE 7: DEEP-DIVE 1 — RTL → PD handoff and kickoff ───────────────
s = prs.slides.add_slide(blank)
add_header(s, 'DEEP DIVE 1 · RTL → PD HANDOFF',
           'Front-end / back-end interface — what we receive, what we hand back',
           subtitle='Every project kicks off with an input audit. Bad inputs at kickoff cost weeks of ECOs later; catching them here is the cheapest fix in the flow.',
           footer_page=7)

# 4-column: Inputs from RTL / Sanity checks / Handshake artifacts / Tools
dd1_top = Inches(1.95); dd1_h = Inches(4.9)
col_w = Inches(3.0); col_gap = Inches(0.12); col_x = Inches(0.5)

dd_column(col_x, dd1_top, col_w, dd1_h, 'INPUTS FROM RTL', GREEN_DARK, [
    'Gate-level netlist (post-synth or golden RTL)',
    'SDC — all modes (func, test, scan, retention)',
    'UPF power intent (domains, retention, iso)',
    'Initial DEF (if hierarchical partition exists)',
    'RTL freeze tag + revision number',
    'IO map + top-level pin assignment',
    'Design constraints: die area, target freq, budgets',
])

dd_column(col_x + (col_w + col_gap), dd1_top, col_w, dd1_h, 'SANITY CHECKS', GREEN, [
    'Formality LEC: netlist ↔ RTL',
    'SDC lint: exceptions, unclocked regs, false paths',
    'UPF integrity: domain closure, retention control',
    'Synthesis QoR review (Genus/DC report)',
    'IO map vs floorplan pad ring',
    'Reset / clock domain crossing (CDC) audit',
    'Power estimate sanity (activity × cap)',
])

dd_column(col_x + 2*(col_w + col_gap), dd1_top, col_w, dd1_h, 'HANDBACK TO RTL', BLUE, [
    'Timing budget per block (interface paths)',
    'Physical constraints: aspect ratio, pin locations',
    'IO buffer choice + drive strength',
    'Congestion + utilization estimate',
    'Preliminary PG plan + IR budget',
    'ECO turn-around expectation',
    'Reference release_tag: <project>_P0_KICKOFF',
])

dd_column(col_x + 3*(col_w + col_gap), dd1_top, col_w, dd1_h, 'TOOLS', BLUE_DARK, [
    'Formality / Conformal — LEC',
    'PrimeTime / Tempus — SDC lint + estimate',
    'Genus / Design Compiler — synth review',
    'VC-LP / Conformal-LP — UPF audit',
    'CBflow: cbflow flow inputs check',
    'CBflow: cbflow flow lec run',
    'Delivered as: P0_KICKOFF release tag',
])


# ── SLIDE 8: DEEP-DIVE 2 — Floorplan ──────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'DEEP DIVE 2 · FLOORPLAN',
           'Where the physical design shape is committed',
           subtitle='Macros, PG grid, IO ring, blockages, low-power domains. Get this right and the rest of the flow follows; get it wrong and PLACE_EXIT is a rewrite.',
           footer_page=8)

dd2_top = Inches(1.95); dd2_h = Inches(4.9)
col_w = Inches(3.0); col_gap = Inches(0.12); col_x = Inches(0.5)

dd_column(col_x, dd2_top, col_w, dd2_h, 'KEY DESIGN TASKS', GREEN_DARK, [
    'Aspect ratio + utilization target',
    'Macro placement (with keep-outs)',
    'Power grid (PG mesh) sizing',
    'IO ring + pad-to-core routing plan',
    'Power domain boundaries (from UPF)',
    'Row site definition + tap/well ties',
    'Blockage strategy (hard/soft/partial)',
])

dd_column(col_x + (col_w + col_gap), dd2_top, col_w, dd2_h, 'TECHNIQUES', GREEN, [
    'Utilization: start 55-65%, tune per congestion',
    'Macros: relational placement, orientation lock',
    'PG mesh: sized against static IR budget',
    'Domain isolation: iso cells inserted from UPF',
    'Retention flops placed in AON region',
    'Corner sites + endcap cells for DFM',
    'Halo around hard macros for routing air',
])

dd_column(col_x + 2*(col_w + col_gap), dd2_top, col_w, dd2_h, 'QUALITY CHECKS', BLUE, [
    'Static IR estimate < spec (from PG)',
    'Congestion prediction (2D map)',
    'Utilization report vs target',
    'PG connectivity + short/open',
    'DRC-lite on ring + PG',
    'UPF vs floorplan CLP audit',
    'Macro-to-core aspect ratio review',
])

dd_column(col_x + 3*(col_w + col_gap), dd2_top, col_w, dd2_h, 'TOOLS + EXIT', BLUE_DARK, [
    'Innovus / FC — floorplan editor',
    'Voltus / RedHawk — static IR estimate',
    'ICV / Calibre — DRC-lite',
    'CBflow: cbflow run all --to fp1',
    'Deliverable: floorplan.def',
    'Deliverable: PG.tcl + IR estimate report',
    'Gate: FP_EXIT (Phase P0)',
])


# ── SLIDE 9: DEEP-DIVE 3 — Placement + CTS ────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'DEEP DIVE 3 · PLACEMENT + CTS',
           'From placed cells to a skew-balanced clock tree',
           subtitle='Two related stages that decide 80% of the final timing. Placement sets the topology, CTS lands the clock skew.',
           footer_page=9)

dd3_top = Inches(1.9); dd3_h = Inches(5.0)
col_w = Inches(6.05); col_gap = Inches(0.2); col_x = Inches(0.5)

# Placement panel
p_x = col_x
add_rect(s, p_x, dd3_top, col_w, dd3_h, fill=WHITE, line=GREEN_DARK, line_w=Pt(1.5))
add_rect(s, p_x, dd3_top, col_w, Inches(0.4), fill=GREEN_DARK)
add_text(s, p_x + Inches(0.2), dd3_top + Inches(0.08), col_w - Inches(0.4), Inches(0.26),
         'PLACEMENT', size=13, bold=True, color=WHITE, font=MONO)

# Placement sub-sections in 2 rows
p_sub_top = dd3_top + Inches(0.55)
sub_h = Inches(2.05); sub_w = col_w - Inches(0.3)
add_text(s, p_x + Inches(0.2), p_sub_top, sub_w, Inches(0.22),
         'TASKS', size=9, bold=True, color=MUTED)
place_tasks = [
    'Global placement (timing + wirelength driven)',
    'Cell legalization (row-snap, orientation)',
    'HFN synthesis (high-fanout net cloning)',
    'Congestion-driven cell spreading',
    'Clock-region-aware placement',
    'Useful-skew potential preserved',
]
ty = p_sub_top + Inches(0.25)
for t in place_tasks:
    add_text(s, p_x + Inches(0.35), ty, sub_w - Inches(0.15), Inches(0.24),
             '·  ' + t, size=9, color=BODY)
    ty += Inches(0.24)

p_check_top = p_sub_top + Inches(1.9)
add_text(s, p_x + Inches(0.2), p_check_top, sub_w, Inches(0.22),
         'CHECKS · TOOLS · DELIVERABLES', size=9, bold=True, color=MUTED)
place_bottom = [
    'Congestion < 2% overflow',
    'Pre-CTS WNS trending positive',
    'Tools: Innovus / Fusion Compiler',
    'Deliverable: place.def + WNS report',
    'Gate: PLACE_EXIT (Phase P0-P1)',
]
ty = p_check_top + Inches(0.25)
for t in place_bottom:
    add_text(s, p_x + Inches(0.35), ty, sub_w - Inches(0.15), Inches(0.24),
             '·  ' + t, size=9, color=BODY)
    ty += Inches(0.24)

# CTS panel
c_x = col_x + col_w + col_gap
add_rect(s, c_x, dd3_top, col_w, dd3_h, fill=WHITE, line=BLUE, line_w=Pt(1.5))
add_rect(s, c_x, dd3_top, col_w, Inches(0.4), fill=BLUE)
add_text(s, c_x + Inches(0.2), dd3_top + Inches(0.08), col_w - Inches(0.4), Inches(0.26),
         'CTS  (Clock Tree Synthesis)', size=13, bold=True, color=WHITE, font=MONO)

c_sub_top = dd3_top + Inches(0.55)
add_text(s, c_x + Inches(0.2), c_sub_top, sub_w, Inches(0.22),
         'TASKS', size=9, bold=True, color=MUTED)
cts_tasks = [
    'Topology choice: H-tree / mesh / spine / hybrid',
    'ICG-aware balancing (integrated clock gates)',
    'Skew + latency + insertion-delay budget',
    'Useful-skew moves on critical endpoints',
    'Clock domain isolation + cross-domain CTS',
    'Multi-Vt clock buffer selection',
]
ty = c_sub_top + Inches(0.25)
for t in cts_tasks:
    add_text(s, c_x + Inches(0.35), ty, sub_w - Inches(0.15), Inches(0.24),
             '·  ' + t, size=9, color=BODY)
    ty += Inches(0.24)

c_check_top = c_sub_top + Inches(1.9)
add_text(s, c_x + Inches(0.2), c_check_top, sub_w, Inches(0.22),
         'CHECKS · TOOLS · DELIVERABLES', size=9, bold=True, color=MUTED)
cts_bottom = [
    'Skew within spec (block-dependent)',
    'Max transition / cap DRV clean',
    'Tools: Innovus CCOpt / FC CTS',
    'Deliverable: cts.def + skew/latency report',
    'Gate: CTS_EXIT (Phase P1)',
]
ty = c_check_top + Inches(0.25)
for t in cts_bottom:
    add_text(s, c_x + Inches(0.35), ty, sub_w - Inches(0.15), Inches(0.24),
             '·  ' + t, size=9, color=BODY)
    ty += Inches(0.24)


# ── SLIDE 10: DEEP-DIVE 4 — Routing + Post-Route Optimization ────────
s = prs.slides.add_slide(blank)
add_header(s, 'DEEP DIVE 4 · ROUTING + POST-ROUTE OPT',
           'From nets on the placer to a DRC/SI-clean, timing-closed database',
           subtitle='Routing lays down every wire; post-route opt closes the last mile of timing and DRV. This is where the design becomes tapeout-ready.',
           footer_page=10)

dd4_top = Inches(1.95); dd4_h = Inches(4.9)
col_w = Inches(3.0); col_gap = Inches(0.12); col_x = Inches(0.5)

dd_column(col_x, dd4_top, col_w, dd4_h, 'ROUTING TASKS', GREEN_DARK, [
    'Global route → track assignment → detail',
    'NDR (non-default rules) on clocks + critical',
    'Layer directives per net class',
    'Antenna-aware + via-doubling in-flow',
    'SI-aware spacing (crosstalk-driven)',
    'Repeater / long-net buffer insertion',
    'DRC-clean route to exit',
])

dd_column(col_x + (col_w + col_gap), dd4_top, col_w, dd4_h, 'POST-ROUTE OPT', GREEN, [
    'PT-guided ECO (timing-driven)',
    'Route-preserve buffer/upsize',
    'Hold-fix via delay cell insertion',
    'SI closure (crosstalk delta minimization)',
    'IR-driven cell relocation (spot fix)',
    'Fanout balancing on late-arriving nets',
    'Post-CTS clock repair (skew tune)',
])

dd_column(col_x + 2*(col_w + col_gap), dd4_top, col_w, dd4_h, 'QUALITY CHECKS', BLUE, [
    'Zero DRC (design rule) violations',
    'Zero SI (crosstalk) violations',
    'Setup + hold timing closed (all corners)',
    'Antenna violations clean',
    'Density / uniformity within spec',
    'MMMC per-scenario STA pass',
    'Post-route WNS matches pre-route intent',
])

dd_column(col_x + 3*(col_w + col_gap), dd4_top, col_w, dd4_h, 'TOOLS + EXIT', BLUE_DARK, [
    'Innovus / FC — global + detailed route',
    'PT-ECO — post-route timing fix scripts',
    'Innovus / FC — route-preserve ECO',
    'ICV / Calibre — DRC (in-flow)',
    'CBflow: cbflow run all --to pro1',
    'Deliverable: route.def + STA reports',
    'Gate: PRO_EXIT (Phase P1-P2)',
])


# ── SLIDE 11: DEEP-DIVE 5 — Timing signoff (STA + LEC + CLP) ─────────
s = prs.slides.add_slide(blank)
add_header(s, 'DEEP DIVE 5 · TIMING & FUNCTIONAL SIGNOFF',
           'STA + LEC + CLP — the three checks that gate BTO',
           subtitle='Static timing across every corner, logic equivalence at every checkpoint, low-power intent verified. All three must be green before BTO.',
           footer_page=11)

dd5_top = Inches(1.95); dd5_h = Inches(4.9)
col_w = Inches(4.05); col_gap = Inches(0.14); col_x = Inches(0.5)

# STA column
dd_column(col_x, dd5_top, col_w, dd5_h, 'STA — Static Timing', BLUE, [
    'Setup timing (all MMMC corners)',
    'Hold timing (all MMMC corners)',
    'Removal / recovery (async reset paths)',
    'Transition / max-cap DRV',
    'Crosstalk (SI-aware delay calculation)',
    'Uncertainty + clock jitter budget',
    'Per-scenario corner-by-corner sign-off',
    '',
    'Tools: PrimeTime / Tempus',
    'Deliverable: STA reports per scenario',
    'Gate: BTO signoff pillar #1',
])

# LEC column
dd_column(col_x + (col_w + col_gap), dd5_top, col_w, dd5_h, 'LEC — Logic Equivalence', BLUE_DARK, [
    'RTL ↔ SYNTH gate netlist',
    'SYNTH ↔ post-PNR netlist',
    'Pre-ECO ↔ post-ECO netlist',
    'Retention + isolation cells validated',
    'Level-shifter insertion verified',
    'Scan chain integrity',
    'Clock gate equivalence (ICG cells)',
    '',
    'Tools: Formality / Conformal LEC',
    'Deliverable: LEC pass certificate',
    'Gate: BTO signoff pillar #2',
])

# CLP column
dd_column(col_x + 2*(col_w + col_gap), dd5_top, col_w, dd5_h, 'CLP — UPF Verification', GREEN_DARK, [
    'Power domain boundary integrity',
    'Isolation strategy (hi/lo/latched)',
    'Level-shifter placement rules',
    'Retention register control chain',
    'Power switch (MTCMOS) integrity',
    'Always-on domain reachability',
    'Wake-up sequence validation',
    '',
    'Tools: VC-LP / Conformal-LP',
    'Deliverable: UPF verification report',
    'Gate: BTO signoff pillar #3',
])


# ── SLIDE 12: DEEP-DIVE 6 — Physical + Power signoff (PV + EMIR) ─────
s = prs.slides.add_slide(blank)
add_header(s, 'DEEP DIVE 6 · PHYSICAL + POWER SIGNOFF',
           'PV + EMIR — the two checks that gate MTO',
           subtitle='Physical verification against the foundry deck; power integrity across every switching scenario. Both must be clean before tapeout data leaves.',
           footer_page=12)

dd6_top = Inches(1.95); dd6_h = Inches(4.9)
col_w = Inches(6.05); col_gap = Inches(0.2); col_x = Inches(0.5)

# PV panel
pv_x = col_x
add_rect(s, pv_x, dd6_top, col_w, dd6_h, fill=WHITE, line=GREEN_DARK, line_w=Pt(1.5))
add_rect(s, pv_x, dd6_top, col_w, Inches(0.4), fill=GREEN_DARK)
add_text(s, pv_x + Inches(0.2), dd6_top + Inches(0.08), col_w - Inches(0.4), Inches(0.26),
         'PV — Physical Verification', size=13, bold=True, color=WHITE, font=MONO)

pv_sub_top = dd6_top + Inches(0.55)
sub_w = col_w - Inches(0.3)
add_text(s, pv_x + Inches(0.2), pv_sub_top, sub_w, Inches(0.22),
         'CHECKS', size=9, bold=True, color=MUTED)
pv_checks = [
    'DRC — foundry design rules',
    'LVS — layout vs schematic (netlist)',
    'PERC — reliability / voltage-aware DRC',
    'PERC-LDL — layout-dependent leakage',
    'XOR — pre/post fill comparison',
    'Antenna + fill density',
    'Fill-merge-GDS pipeline (15-stage DAG)',
]
ty = pv_sub_top + Inches(0.25)
for t in pv_checks:
    add_text(s, pv_x + Inches(0.35), ty, sub_w - Inches(0.15), Inches(0.24),
             '·  ' + t, size=9, color=BODY)
    ty += Inches(0.24)

pv_tools_top = pv_sub_top + Inches(2.15)
add_text(s, pv_x + Inches(0.2), pv_tools_top, sub_w, Inches(0.22),
         'TOOLS · DELIVERABLES', size=9, bold=True, color=MUTED)
pv_bottom = [
    'Tools: ICV (Synopsys) or Calibre (Siemens)',
    'Deliverable: DRC/LVS/PERC clean reports',
    'Deliverable: signed GDS',
    'Gate: PV signoff → MTO',
]
ty = pv_tools_top + Inches(0.25)
for t in pv_bottom:
    add_text(s, pv_x + Inches(0.35), ty, sub_w - Inches(0.15), Inches(0.24),
             '·  ' + t, size=9, color=BODY)
    ty += Inches(0.24)

# EMIR panel
em_x = col_x + col_w + col_gap
add_rect(s, em_x, dd6_top, col_w, dd6_h, fill=WHITE, line=BLUE, line_w=Pt(1.5))
add_rect(s, em_x, dd6_top, col_w, Inches(0.4), fill=BLUE)
add_text(s, em_x + Inches(0.2), dd6_top + Inches(0.08), col_w - Inches(0.4), Inches(0.26),
         'EMIR — Power Integrity', size=13, bold=True, color=WHITE, font=MONO)

em_sub_top = dd6_top + Inches(0.55)
add_text(s, em_x + Inches(0.2), em_sub_top, sub_w, Inches(0.22),
         'CHECKS', size=9, bold=True, color=MUTED)
em_checks = [
    'Static IR-drop (per PG mesh corner)',
    'Dynamic IR (vector-based, real switching)',
    'EM (electromigration) — signal + PG',
    'Wake-up rush current (power switches)',
    'PG mesh integrity + decap coverage',
    'Multi-domain scenario coverage',
    'Cross-domain reference to STA scenarios',
]
ty = em_sub_top + Inches(0.25)
for t in em_checks:
    add_text(s, em_x + Inches(0.35), ty, sub_w - Inches(0.15), Inches(0.24),
             '·  ' + t, size=9, color=BODY)
    ty += Inches(0.24)

em_tools_top = em_sub_top + Inches(2.15)
add_text(s, em_x + Inches(0.2), em_tools_top, sub_w, Inches(0.22),
         'TOOLS · DELIVERABLES', size=9, bold=True, color=MUTED)
em_bottom = [
    'Tools: RedHawk (Ansys) or Voltus (Cadence)',
    'Deliverable: IR / EM / dynamic reports',
    'Deliverable: PG audit + decap coverage',
    'Gate: EMIR signoff → BTO',
]
ty = em_tools_top + Inches(0.25)
for t in em_bottom:
    add_text(s, em_x + Inches(0.35), ty, sub_w - Inches(0.15), Inches(0.24),
             '·  ' + t, size=9, color=BODY)
    ty += Inches(0.24)


# ── SLIDE 13: DEEP-DIVE 7 — Partitioned power domains: Rapid AI ─────
s = prs.slides.add_slide(blank)
add_header(s, 'DEEP DIVE 7 · PARTITIONED POWER DOMAINS · RAPID AI',
           'Power-domain partition mirrors the functional-block partition',
           subtitle='PON, 800G, AFE, Core/Mem and LPDDR each get their own power domain. Line-side and system-side interfaces are grouped separately for isolation and noise control.',
           footer_page=13)

# Left: chip floorplan visualization
fp_x = Inches(0.5); fp_y = Inches(1.9); fp_w = Inches(7.5); fp_h = Inches(4.5)
add_rect(s, fp_x, fp_y, fp_w, fp_h, fill=PANEL, line=INK, line_w=Pt(1.5))
add_text(s, fp_x + Inches(0.2), fp_y + Inches(0.08), fp_w - Inches(0.4), Inches(0.25),
         'Rapid AI chip — power-domain floorplan (representative)',
         size=10, bold=True, color=INK)

# Chip die outline
die_x = fp_x + Inches(0.3); die_y = fp_y + Inches(0.45)
die_w = fp_w - Inches(0.6); die_h = fp_h - Inches(0.65)
add_rect(s, die_x, die_y, die_w, die_h, fill=WHITE, line=MUTED, line_w=Pt(0.75))

# Core/Mem (center, always-on)
core_x = die_x + die_w/2 - Inches(1.5); core_y = die_y + die_h/2 - Inches(0.8)
core_w = Inches(3.0); core_h = Inches(1.6)
add_rect(s, core_x, core_y, core_w, core_h, fill=GREEN_TINT, line=GREEN_DARK, line_w=Pt(1.5))
add_text(s, core_x, core_y + Inches(0.15), core_w, Inches(0.28),
         'CORE / MEM', size=12, bold=True, color=GREEN_DARK,
         align=PP_ALIGN.CENTER, font=MONO)
add_text(s, core_x, core_y + Inches(0.5), core_w, Inches(0.25),
         'PD_CORE (switched)', size=9, color=BODY, align=PP_ALIGN.CENTER)
add_text(s, core_x, core_y + Inches(0.75), core_w, Inches(0.25),
         'PD_AON (always-on)', size=9, color=BODY, align=PP_ALIGN.CENTER)
add_text(s, core_x, core_y + Inches(1.0), core_w, Inches(0.25),
         'Retention + wake ctrl', size=9, color=MUTED,
         align=PP_ALIGN.CENTER)

# Line-side interfaces (right side): 800G + PON
line_x = die_x + die_w - Inches(1.6); line_y = die_y + Inches(0.15)
line_w = Inches(1.4)

# 800G
add_rect(s, line_x, line_y, line_w, Inches(1.1), fill=BLUE_TINT, line=BLUE, line_w=Pt(1.5))
add_text(s, line_x, line_y + Inches(0.1), line_w, Inches(0.25),
         '800G', size=12, bold=True, color=BLUE, align=PP_ALIGN.CENTER, font=MONO)
add_text(s, line_x, line_y + Inches(0.38), line_w, Inches(0.22),
         'Ethernet SERDES', size=8, color=BODY, align=PP_ALIGN.CENTER)
add_text(s, line_x, line_y + Inches(0.6), line_w, Inches(0.22),
         'PD_800G', size=8, bold=True, color=BLUE, align=PP_ALIGN.CENTER)
add_text(s, line_x, line_y + Inches(0.8), line_w, Inches(0.22),
         'noise-isolated', size=8, color=MUTED, align=PP_ALIGN.CENTER)

# PON (below 800G)
pon_y = line_y + Inches(1.25)
add_rect(s, line_x, pon_y, line_w, Inches(1.1), fill=BLUE_TINT, line=BLUE, line_w=Pt(1.5))
add_text(s, line_x, pon_y + Inches(0.1), line_w, Inches(0.25),
         'PON', size=12, bold=True, color=BLUE, align=PP_ALIGN.CENTER, font=MONO)
add_text(s, line_x, pon_y + Inches(0.38), line_w, Inches(0.22),
         'optical network', size=8, color=BODY, align=PP_ALIGN.CENTER)
add_text(s, line_x, pon_y + Inches(0.6), line_w, Inches(0.22),
         'PD_PON', size=8, bold=True, color=BLUE, align=PP_ALIGN.CENTER)
add_text(s, line_x, pon_y + Inches(0.8), line_w, Inches(0.22),
         'AFE-adjacent', size=8, color=MUTED, align=PP_ALIGN.CENTER)

# AFE (bottom-right, isolated)
afe_x = line_x; afe_y = pon_y + Inches(1.25)
add_rect(s, afe_x, afe_y, line_w, Inches(0.95), fill=AMBER_TINT, line=AMBER_DARK, line_w=Pt(1.5))
add_text(s, afe_x, afe_y + Inches(0.08), line_w, Inches(0.25),
         'AFE', size=12, bold=True, color=AMBER_DARK, align=PP_ALIGN.CENTER, font=MONO)
add_text(s, afe_x, afe_y + Inches(0.35), line_w, Inches(0.22),
         'analog front end', size=8, color=BODY, align=PP_ALIGN.CENTER)
add_text(s, afe_x, afe_y + Inches(0.55), line_w, Inches(0.22),
         'PD_AFE (analog)', size=8, bold=True, color=AMBER_DARK, align=PP_ALIGN.CENTER)
add_text(s, afe_x, afe_y + Inches(0.72), line_w, Inches(0.22),
         'guard ring', size=8, color=MUTED, align=PP_ALIGN.CENTER)

# System-side interfaces (left side): LPDDR + misc IO
sys_x = die_x + Inches(0.15); sys_y = die_y + Inches(0.15)
sys_w = Inches(1.4)
add_rect(s, sys_x, sys_y, sys_w, Inches(1.5), fill=GREEN_TINT, line=GREEN_DARK, line_w=Pt(1.5))
add_text(s, sys_x, sys_y + Inches(0.1), sys_w, Inches(0.25),
         'LPDDR', size=12, bold=True, color=GREEN_DARK, align=PP_ALIGN.CENTER, font=MONO)
add_text(s, sys_x, sys_y + Inches(0.4), sys_w, Inches(0.22),
         'memory interface', size=8, color=BODY, align=PP_ALIGN.CENTER)
add_text(s, sys_x, sys_y + Inches(0.62), sys_w, Inches(0.22),
         'PD_LPDDR', size=8, bold=True, color=GREEN_DARK, align=PP_ALIGN.CENTER)
add_text(s, sys_x, sys_y + Inches(0.82), sys_w, Inches(0.22),
         'dedicated PG', size=8, color=MUTED, align=PP_ALIGN.CENTER)
add_text(s, sys_x, sys_y + Inches(1.02), sys_w, Inches(0.22),
         'DLL + ZQ cal AON', size=8, color=MUTED, align=PP_ALIGN.CENTER)

# System IOs bottom-left
sio_y = sys_y + Inches(1.65)
add_rect(s, sys_x, sio_y, sys_w, Inches(0.95), fill=PANEL, line=MUTED, line_w=Pt(1))
add_text(s, sys_x, sio_y + Inches(0.08), sys_w, Inches(0.25),
         'SYS IO', size=11, bold=True, color=INK, align=PP_ALIGN.CENTER, font=MONO)
add_text(s, sys_x, sio_y + Inches(0.35), sys_w, Inches(0.22),
         'mgmt / debug', size=8, color=BODY, align=PP_ALIGN.CENTER)
add_text(s, sys_x, sio_y + Inches(0.55), sys_w, Inches(0.22),
         'PD_AON', size=8, bold=True, color=INK, align=PP_ALIGN.CENTER)

# Right: partition rationale panel
r_x = Inches(8.15); r_y = Inches(1.9); r_w = Inches(4.7); r_h = Inches(4.5)
add_rect(s, r_x, r_y, r_w, r_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, r_x, r_y, r_w, Inches(0.36), fill=INK)
add_text(s, r_x + Inches(0.2), r_y + Inches(0.06), r_w - Inches(0.4), Inches(0.24),
         'PARTITION RATIONALE', size=11, bold=True, color=WHITE, font=MONO)

rationale = [
    ('Line side isolation',
     '800G + PON grouped on one edge, away from digital switching noise. Their power domains have their own PG and iso cells.'),
    ('AFE isolation',
     'Analog front end sits in its own domain with a guard ring. Substrate and supply are isolated from digital.'),
    ('LPDDR interface',
     'System side, own PG mesh. DLL + ZQ calibration lives in AON so memory stays trained across PD_CORE cycles.'),
    ('Core/Mem power gating',
     'PD_CORE gated by MTCMOS switches; retention flops in PD_AON. Wake-up sequenced to avoid IR collapse.'),
    ('System IO in AON',
     'Management and debug IOs stay powered so the chip is reachable through core sleep.'),
]
ry = r_y + Inches(0.5)
for title, body in rationale:
    add_text(s, r_x + Inches(0.2), ry, r_w - Inches(0.4), Inches(0.22),
             title, size=10, bold=True, color=GREEN_DARK)
    add_text(s, r_x + Inches(0.2), ry + Inches(0.24), r_w - Inches(0.4), Inches(0.5),
             body, size=8, color=BODY)
    ry += Inches(0.76)


# ── SLIDE 14: DEEP-DIVE 8 — Package co-design (SI/PI signoff) ────────
s = prs.slides.add_slide(blank)
add_header(s, 'DEEP DIVE 8 · PACKAGE CO-DESIGN · SI/PI',
           'Die + package + PCB — signed off together with the package team',
           subtitle='High-speed interfaces (800G, PON, LPDDR) live or die at the package. Co-design gate blocks BTO until SI and PI clean at the pin-to-pin level.',
           footer_page=14)

# Top: stack visualization
st_x = Inches(0.5); st_y = Inches(1.9); st_w = Inches(12.35); st_h = Inches(1.8)
add_rect(s, st_x, st_y, st_w, st_h, fill=PANEL, line=LINE, line_w=Pt(0.75))
add_text(s, st_x + Inches(0.2), st_y + Inches(0.1), st_w - Inches(0.4), Inches(0.25),
         'Signal path stack — every layer contributes SI and PI',
         size=10, bold=True, color=INK)

# 4-layer stack: Die → μBump → Package substrate → PCB
layers = [
    ('SILICON DIE', 'IO pads, ESD, on-die decap', GREEN_DARK),
    ('μBUMP / C4', 'die-to-package interconnect (rise-time hit)', BLUE),
    ('PACKAGE SUBSTRATE', 'routing + PG planes + package decap', AMBER_DARK),
    ('BGA + PCB', 'ball grid array to board (loss + reflections)', MUTED),
]
lay_top = st_y + Inches(0.5)
lay_w = Inches(2.85); lay_gap = Inches(0.13)
lay_x = st_x + Inches(0.25)
for i, (name, desc, color) in enumerate(layers):
    x = lay_x + i * (lay_w + lay_gap)
    add_rect(s, x, lay_top, lay_w, Inches(1.05), fill=WHITE, line=color, line_w=Pt(1.5))
    add_rect(s, x, lay_top, lay_w, Inches(0.32), fill=color)
    add_text(s, x, lay_top + Inches(0.06), lay_w, Inches(0.22),
             name, size=10, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, font=MONO)
    add_text(s, x + Inches(0.15), lay_top + Inches(0.4), lay_w - Inches(0.3), Inches(0.6),
             desc, size=8, color=BODY, align=PP_ALIGN.CENTER)
    if i < len(layers) - 1:
        arr = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW,
                                  x + lay_w + Inches(0.005),
                                  lay_top + Inches(0.45),
                                  lay_gap - Inches(0.01), Inches(0.14))
        arr.fill.solid(); arr.fill.fore_color.rgb = MUTED
        arr.line.fill.background()

# Bottom: 3 columns — SI checks / PI checks / Co-design workflow
b_top = Inches(3.85); b_h = Inches(3.05)
col_w = Inches(4.05); col_gap = Inches(0.14); col_x = Inches(0.5)

dd_column(col_x, b_top, col_w, b_h, 'SI — Signal Integrity', BLUE, [
    'Insertion loss (S21) per interface',
    'Return loss (S11) — impedance discontinuity',
    'Crosstalk (NEXT / FEXT) between lanes',
    'Eye diagram + jitter at package pins',
    'Simultaneous Switching Noise (SSN)',
    'Tools: HSPICE / Sigrity / HFSS',
])

dd_column(col_x + (col_w + col_gap), b_top, col_w, b_h, 'PI — Power Integrity', GREEN_DARK, [
    'Package IR-drop (per-domain)',
    'Package + PCB PDN impedance vs freq',
    'Chip-package-PCB decap co-tuning',
    'On-die + on-package decap coverage',
    'Wake-up rush current (system-level)',
    'Tools: RedHawk-CPA / Voltus-XFI',
])

dd_column(col_x + 2*(col_w + col_gap), b_top, col_w, b_h, 'CO-DESIGN WORKFLOW', AMBER_DARK, [
    'Weekly sync with package team',
    'IO buffer + package model exchange',
    'Full-stack simulation (die+pkg+PCB)',
    'Joint sign-off checklist',
    'Package release_tag consumed by CBflow',
    'Gate: SI/PI sign-off → BTO',
])

# ── SLIDE 15: Exit milestones — 6-gate chain with per-gate criteria ──
s = prs.slides.add_slide(blank)
add_header(s, 'METHODOLOGY · EXIT MILESTONES',
           'Six gates from floorplan to foundry — every gate has a checklist',
           subtitle='FP_EXIT → PLACE_EXIT → CTS_EXIT → PRO_EXIT → BTO → MTO. No stage advances unless the previous gate is signed.',
           footer_page=15)

# ── Milestone definitions ──────────────────────────────────────────────
# (tag, title, phase, criteria list, color)
milestones = [
    ('FP_EXIT',    'Floorplan',       'P0',
     ['Macros placed and fixed',
      'PG mesh built to IR budget',
      'IO ring + pad-to-core plan stable',
      'UPF domain boundaries set',
      'Utilization within target'],
     GREEN),
    ('PLACE_EXIT', 'Placement',       'P0-P1',
     ['All cells placed and legalized',
      'Congestion under 2%',
      'HFN synthesis complete',
      'Pre-CTS WNS trending positive',
      'No overlap violations'],
     GREEN_DARK),
    ('CTS_EXIT',   'Clock Tree',      'P1',
     ['Clock tree built (H-tree / mesh / spine)',
      'Skew within spec',
      'Clock latency in budget',
      'ICG cells honored',
      'DRV clean on clock nets'],
     BLUE),
    ('PRO_EXIT',   'Post-Route Opt',  'P1-P2',
     ['Setup + hold timing closed',
      'Zero DRC violations',
      'Zero SI (crosstalk) violations',
      'Antenna clean',
      'All routes committed'],
     BLUE_DARK),
    ('BTO',        'Backend Tapeout', 'P2',
     ['All 5 signoff pillars green',
      'STA + LEC + CLP + PV + EMIR clean',
      '292 checks pass or waived',
      'Release manifest published',
      'No open blockers'],
     AMBER_DARK),
    ('MTO',        'Metal Tapeout',   'P3',
     ['GDS finalized and locked',
      'Foundry deliverables complete',
      'Metal-only ECOs only from here',
      'Design data package sealed',
      'Tapeout sign-off recorded'],
     INK),
]

# ── Section A: concept strip (top) ────────────────────────────────────
ca_top = Inches(1.85); ca_h = Inches(0.45)
add_rect(s, Inches(0.5), ca_top, Inches(12.35), ca_h, fill=PANEL, line=LINE, line_w=Pt(0.5))
add_rect(s, Inches(0.5), ca_top, Inches(0.15), ca_h, fill=GREEN_DARK)
add_text(s, Inches(0.85), ca_top + Inches(0.09), Inches(11.8), Inches(0.3),
         'Each gate is a config, not a spreadsheet. Every criterion is a script that either passes or writes a waiver with a reason.',
         size=11, bold=True, color=INK)


# ── Section B: 6 milestone cards in a row with arrows between ─────────
sb_top = Inches(2.5); sb_h = Inches(4.5)
gap = Inches(0.08)
card_w = Emu((int(Inches(12.35)) - int(gap) * 5) // 6)
card_x0 = Inches(0.5)

# Position tracking for arrows between cards
card_positions = []
for i, (tag, title, phase, criteria, color) in enumerate(milestones):
    x = card_x0 + i * (card_w + gap)
    card_positions.append(x)

    # Frame
    add_rect(s, x, sb_top, card_w, sb_h, fill=WHITE, line=color, line_w=Pt(1.5))

    # Header stripe (colored) — milestone tag
    add_rect(s, x, sb_top, card_w, Inches(0.42), fill=color)
    add_text(s, x, sb_top + Inches(0.06), card_w, Inches(0.3),
             tag, size=13, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, font=MONO)

    # Subtitle — human name of the milestone
    add_text(s, x + Inches(0.1), sb_top + Inches(0.52), card_w - Inches(0.2), Inches(0.28),
             title, size=11, bold=True, color=INK, align=PP_ALIGN.CENTER)

    # Phase pill
    add_pill(s, x + card_w / 2 - Inches(0.35), sb_top + Inches(0.82),
             Inches(0.7), Inches(0.22),
             phase, fill=color, color=WHITE, size=8)

    # Divider line
    div_y = sb_top + Inches(1.15)
    add_rect(s, x + Inches(0.15), div_y, card_w - Inches(0.3), Emu(9000),
             fill=LINE, line=None)

    # "EXIT CRITERIA" label
    add_text(s, x + Inches(0.15), div_y + Inches(0.08),
             card_w - Inches(0.3), Inches(0.22),
             'EXIT CRITERIA', size=8, bold=True, color=MUTED, font=MONO)

    # Criteria bullets
    cy = div_y + Inches(0.32)
    for crit in criteria:
        # Colored dot
        add_rect(s, x + Inches(0.2), cy + Inches(0.06),
                 Inches(0.08), Inches(0.08),
                 fill=color, line=None)
        # Text
        add_text(s, x + Inches(0.35), cy, card_w - Inches(0.45), Inches(0.4),
                 crit, size=8, color=BODY)
        cy += Inches(0.35)

# ── Arrows between milestone cards ────────────────────────────────────
arrow_y = sb_top + Inches(0.21)
for i in range(len(milestones) - 1):
    x_from = card_positions[i] + card_w
    x_to = card_positions[i + 1]
    arr = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW,
                             x_from + Inches(0.005),
                             arrow_y - Inches(0.05),
                             gap - Inches(0.01),
                             Inches(0.1))
    arr.fill.solid()
    arr.fill.fore_color.rgb = MUTED
    arr.line.fill.background()


# ── SAVE ────────────────────────────────────────────────────────────────
out = 'PD/docs/sales/CBflow_Methodology_Deck.pptx'
prs.save(out)
print(f'Wrote {out} with {len(prs.slides)} slide(s).')
