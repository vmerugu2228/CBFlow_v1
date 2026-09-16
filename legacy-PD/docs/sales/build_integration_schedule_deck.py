#!/usr/bin/env python3
"""
Build CBflow_Sbarmathi_Integration_Schedule.pptx — 3-week execution plan.

Timeline: 9 Sep → 30 Sep 2026
Leads:    Madhavi (CBflow side)  ·  Rupit (Sbarmathi side)
Goal:     tapeout-quality database with full signoff, checklists, scripts

Contents (10 slides):
     1  Title + leads + timeline
     2  Goal & scope — what tapeout-quality means
     3  Team & ownership matrix
     4  3-week Gantt (workstreams × dates)
     5  Week 1 (Sept 9-15) — Foundation
     6  Week 2 (Sept 16-22) — Flow bring-up + signoff wiring
     7  Week 3 (Sept 23-30) — Checklists + tapeout DB
     8  Deliverables — files, owners, paths
     9  Risks + mitigation + sync cadence
    10  Closing / immediate next steps
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

# ── Palette (SmartSoC brand) ────────────────────────────────────────────
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
TOTAL_SLIDES = 10


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
    add_text(slide, Inches(0.5), Inches(0.52), Inches(12.3), Inches(0.6),
             title, size=26, bold=True, color=INK)
    if subtitle:
        add_text(slide, Inches(0.5), Inches(1.2), Inches(12.3), Inches(0.4),
                 subtitle, size=13, bold=False, color=MUTED)
    add_text(slide, Inches(0.5), Inches(7.15), Inches(9), Inches(0.25),
             'CBflow × Sbarmathi Integration   ·   SmartSoC Solutions',
             size=10, color=MUTED)
    if footer_page:
        add_text(slide, Inches(12.5), Inches(7.15), Inches(0.7), Inches(0.25),
                 f'{footer_page}/{TOTAL_SLIDES}', size=10, bold=True, color=MUTED,
                 align=PP_ALIGN.RIGHT)


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

add_text(s, Inches(1.0), Inches(1.6), Inches(11.5), Inches(1.1),
         'CBflow × Sbarmathi', size=52, bold=True, color=INK)
add_text(s, Inches(1.0), Inches(2.5), Inches(11.5), Inches(1.0),
         'Integration Schedule.', size=44, bold=True, color=GREEN_DARK)

add_text(s, Inches(1.0), Inches(3.7), Inches(11.5), Inches(0.5),
         'Kickoff → tapeout-quality database.',
         size=20, color=BODY)

# Timeline pill
add_pill(s, Inches(1.0), Inches(4.7), Inches(3.8), Inches(0.5),
         '9 SEP → 30 SEP 2026  ·  3 weeks',
         fill=AMBER, color=WHITE, size=14)

# Leads block
leads_top = Inches(5.5)
add_text(s, Inches(1.0), leads_top, Inches(3), Inches(0.3),
         'LEADS', size=11, bold=True, color=MUTED)
add_pill(s, Inches(1.0), leads_top + Inches(0.4), Inches(2.4), Inches(0.5),
         'MADHAVI', fill=GREEN_TINT, color=GREEN_DARK, size=14)
add_text(s, Inches(3.55), leads_top + Inches(0.5), Inches(3), Inches(0.3),
         'CBflow side', size=12, color=BODY)

add_pill(s, Inches(1.0), leads_top + Inches(1.0), Inches(2.4), Inches(0.5),
         'RUPIT', fill=BLUE_TINT, color=BLUE, size=14)
add_text(s, Inches(3.55), leads_top + Inches(1.1), Inches(3), Inches(0.3),
         'Sbarmathi side', size=12, color=BODY)

# Bottom sign-off
add_text(s, Inches(1.0), Inches(7.15), Inches(11), Inches(0.3),
         'SmartSoC Solutions   ·   Prepared for kickoff review',
         size=11, color=MUTED)


# ── SLIDE 2: GOAL & SCOPE ─────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'GOAL',
           'Build a tapeout-quality database on Sbarmathi',
           subtitle='Every flow configured, every check scripted, every deliverable in the release tag. Ready for downstream consumption on Oct 1.',
           footer_page=2)

# Big statement in a highlight band
h_top = Inches(1.85); h_h = Inches(1.05)
add_rect(s, Inches(0.5), h_top, Inches(12.35), h_h, fill=AMBER_TINT,
         line=AMBER_DARK, line_w=Pt(1))
add_rect(s, Inches(0.5), h_top, Inches(0.15), h_h, fill=AMBER)
add_text(s, Inches(0.85), h_top + Inches(0.18), Inches(11.8), Inches(0.4),
         '"Tapeout-quality" means every artifact a downstream team needs',
         size=18, bold=True, color=INK)
add_text(s, Inches(0.85), h_top + Inches(0.6), Inches(11.8), Inches(0.4),
         'to consume Sbarmathi through a release_tag — with zero verbal handoff.',
         size=14, color=BODY)

# Two-column: what's in / what's out
sc_top = Inches(3.1); sc_h = Inches(3.85)
col_w = Inches(6.05); col_gap = Inches(0.2)

# In-scope
in_x = Inches(0.5)
add_rect(s, in_x, sc_top, col_w, sc_h, fill=WHITE, line=GREEN_DARK, line_w=Pt(1.25))
add_rect(s, in_x, sc_top, col_w, Inches(0.4), fill=GREEN_DARK)
add_text(s, in_x + Inches(0.2), sc_top + Inches(0.08),
         col_w - Inches(0.4), Inches(0.24),
         'IN SCOPE', size=12, bold=True, color=WHITE, font=MONO)

in_items = [
    'All 12 CBflow flows configured for Sbarmathi tech',
    'Signoff on 5 pillars — STA, LEC, CLP, PV, EMIR',
    '292 built-in checks + Sbarmathi-specific extensions',
    'Every checklist scripted (not spreadsheet)',
    'Release tag P0_BTO published + consumable',
    'Runbook + SmartGenie KB ingested',
    'Full audit trail in per-run SQLite',
    'MMMC scenarios for Sbarmathi PVT axes',
]
iy = sc_top + Inches(0.55)
for item in in_items:
    add_text(s, in_x + Inches(0.35), iy, col_w - Inches(0.5), Inches(0.32),
             '·  ' + item, size=11, color=BODY)
    iy += Inches(0.38)

# Out-of-scope
out_x = Inches(6.75)
add_rect(s, out_x, sc_top, col_w, sc_h, fill=WHITE, line=MUTED, line_w=Pt(1))
add_rect(s, out_x, sc_top, col_w, Inches(0.4), fill=MUTED)
add_text(s, out_x + Inches(0.2), sc_top + Inches(0.08),
         col_w - Inches(0.4), Inches(0.24),
         'OUT OF SCOPE (this phase)', size=12, bold=True, color=WHITE, font=MONO)

out_items = [
    'Functional ECOs — reserved for post-BTO',
    'DFT insertion / scan chain routing',
    'Package co-design (SI/PI) — Phase 2',
    'Foundry-specific runset customization',
    'Multi-project batch scheduling',
    'Cross-project release management',
    'Analog / mixed-signal blocks',
    'Custom EDA tool integrations beyond Cadence/Synopsys',
]
iy = sc_top + Inches(0.55)
for item in out_items:
    add_text(s, out_x + Inches(0.35), iy, col_w - Inches(0.5), Inches(0.32),
             '·  ' + item, size=11, color=MUTED)
    iy += Inches(0.38)


# ── SLIDE 3: TEAM & OWNERSHIP ─────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'TEAM',
           'Ownership by flow — who integrates what',
           subtitle='Madhavi owns front-end + functional/timing signoff (SYNTH, STA, LEC). Rupit owns project prep + physical flow (project configs, MMMC, library, FP, PNR). Cadence tools only.',
           footer_page=3)

# Two big lead cards
td_top = Inches(1.85); td_h = Inches(2.6)
card_w = Inches(6.05); card_gap = Inches(0.25)

# Madhavi card
m_x = Inches(0.5)
add_rect(s, m_x, td_top, card_w, td_h, fill=GREEN_TINT,
         line=GREEN_DARK, line_w=Pt(1.5))
add_rect(s, m_x, td_top, card_w, Inches(0.5), fill=GREEN_DARK)
add_text(s, m_x + Inches(0.25), td_top + Inches(0.12),
         card_w - Inches(0.5), Inches(0.28),
         'MADHAVI  ·  SYNTH  +  STA  +  LEC',
         size=14, bold=True, color=WHITE, font=MONO)

m_items = [
    'SYNTH flow integration (Genus)',
    'STA signoff integration (Tempus) — scenarios + closure',
    'LEC checkpoints (Conformal) — RTL↔SYNTH↔PNR',
    'Timing / functional checklists + custom checks',
    'Waivers + sign-off scripts for SYNTH / STA / LEC',
    'SmartGenie KB ingest for SYNTH / STA / LEC',
]
iy = td_top + Inches(0.7)
for it in m_items:
    add_text(s, m_x + Inches(0.35), iy, card_w - Inches(0.5), Inches(0.28),
             '·  ' + it, size=11, color=BODY)
    iy += Inches(0.30)

# Rupit card
r_x = Inches(6.8)
add_rect(s, r_x, td_top, card_w, td_h, fill=BLUE_TINT,
         line=BLUE, line_w=Pt(1.5))
add_rect(s, r_x, td_top, card_w, Inches(0.5), fill=BLUE)
add_text(s, r_x + Inches(0.25), td_top + Inches(0.12),
         card_w - Inches(0.5), Inches(0.28),
         'RUPIT  ·  PROJECT PREP  +  FP  +  PNR',
         size=14, bold=True, color=WHITE, font=MONO)

r_items = [
    'Project configs + tech_config.tcl authoring',
    'library-manager — lib_config generation',
    'mmmc-manager — MMMC scenarios for Sbarmathi PVT',
    'FP / FCFP flow integration (Innovus)',
    'PNR flow integration (Innovus) — place, CTS, route, opt',
    'Physical checklists + waivers for FP / PNR',
]
iy = td_top + Inches(0.7)
for it in r_items:
    add_text(s, r_x + Inches(0.35), iy, card_w - Inches(0.5), Inches(0.28),
             '·  ' + it, size=11, color=BODY)
    iy += Inches(0.30)

# Joint responsibilities band
j_top = Inches(4.65); j_h = Inches(2.35)
add_rect(s, Inches(0.5), j_top, Inches(12.35), j_h, fill=WHITE,
         line=AMBER_DARK, line_w=Pt(1.5))
add_rect(s, Inches(0.5), j_top, Inches(12.35), Inches(0.5), fill=AMBER_DARK)
add_text(s, Inches(0.75), j_top + Inches(0.12), Inches(12), Inches(0.28),
         'JOINT  ·  Madhavi + Rupit',
         size=14, bold=True, color=WHITE, font=MONO)

joint = [
    ('SYNTH_PNR combined flow', 'Straddles Madhavi\'s SYNTH and Rupit\'s PNR — wire together end-to-end, joint owner'),
    ('CLP / PV / EMIR signoff', 'Downstream pillars — Rupit provides tool bring-up + runsets, Madhavi wires checklists'),
    ('BTO gate dry run',        'End-to-end BTO rehearsal Sept 26 — both leads on the call, walk every check'),
    ('Sign-off review',         'Final release_tag publish — no verbal green-lights, everything in writing'),
    ('Escalation path',         'Anything blocking > 1 day → both leads sync with SmartSoC PMO'),
]
jy = j_top + Inches(0.65)
for label, desc in joint:
    add_text(s, Inches(0.75), jy, Inches(3.0), Inches(0.28),
             '·  ' + label, size=11, bold=True, color=AMBER_DARK)
    add_text(s, Inches(3.9), jy, Inches(8.9), Inches(0.3),
             desc, size=10, color=BODY)
    jy += Inches(0.32)


# ── SLIDE 4: 3-WEEK GANTT ─────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'TIMELINE',
           '3-week Gantt — workstreams vs dates',
           subtitle='Sept 9 → Sept 30. Each workstream has an accountable lead and a hard exit criterion.',
           footer_page=4)

# Gantt chart geometry
gantt_x = Inches(0.5); gantt_y = Inches(1.85)
gantt_w = Inches(12.35); gantt_h = Inches(4.9)

# Chart area
chart_left = gantt_x + Inches(3.2)   # left column for workstream labels
chart_top  = gantt_y + Inches(0.5)   # header row for dates
chart_w    = gantt_w - Inches(3.2)   # 9.15" for the date grid
chart_h    = gantt_h - Inches(0.5)   # bar rows

# Date scale — 22 days (Sept 9 → Sept 30)
DAYS = 22
day_w = chart_w / DAYS  # width per day column

# Draw date-header row
# Week bands
week_bands = [
    (0,   7,  'WEEK 1  ·  9 - 15 SEP',   GREEN_DARK,  GREEN_TINT),
    (7,   14, 'WEEK 2  ·  16 - 22 SEP',  BLUE,        BLUE_TINT),
    (14,  22, 'WEEK 3  ·  23 - 30 SEP',  AMBER_DARK,  AMBER_TINT),
]
for start, end, label, color, tint in week_bands:
    bw = day_w * (end - start)
    bx = chart_left + day_w * start
    add_rect(s, bx, chart_top - Inches(0.4), bw, Inches(0.32),
             fill=color, line=None)
    add_text(s, bx, chart_top - Inches(0.37), bw, Inches(0.24),
             label, size=10, bold=True, color=WHITE,
             align=PP_ALIGN.CENTER, font=MONO)

# Day markers (small ticks at bottom)
for d in range(DAYS + 1):
    x = chart_left + day_w * d
    add_rect(s, x - Emu(3000), chart_top - Inches(0.05),
             Emu(6000), chart_h + Inches(0.05),
             fill=LINE, line=None)

# Workstreams (label, start_day, end_day, color, lead)
workstreams = [
    ('Project prep + tech_config',    0,  4,  BLUE,       'R'),
    ('library-manager (lib_config)',  1,  6,  BLUE,       'R'),
    ('mmmc-manager (scenarios)',      3,  8,  BLUE,       'R'),
    ('SYNTH bring-up (Genus)',        2,  9,  GREEN_DARK, 'M'),
    ('FP + PNR bring-up (Innovus)',   5, 14,  BLUE,       'R'),
    ('STA bring-up (Tempus)',         8, 15,  GREEN_DARK, 'M'),
    ('LEC bring-up (Conformal)',      9, 15,  GREEN_DARK, 'M'),
    ('CLP + PV + EMIR wiring',       12, 18,  AMBER_DARK, 'R+M'),
    ('Checklists + custom checks',   14, 20,  AMBER_DARK, 'R+M'),
    ('BTO dry run',                  17, 20,  AMBER,      'R+M'),
    ('Release tag + runbook',        19, 21,  AMBER_DARK, 'R+M'),
    ('SmartGenie ingest + closeout', 20, 22,  INK,        'R+M'),
]

row_h = chart_h / (len(workstreams) + 0.5)
for i, (name, s_day, e_day, color, lead) in enumerate(workstreams):
    row_y = chart_top + Inches(0.1) + i * row_h
    # Workstream label
    add_text(s, gantt_x, row_y + Inches(0.03), Inches(3.05), row_h - Inches(0.02),
             name, size=10, bold=True, color=INK)
    # Bar
    bar_x = chart_left + day_w * s_day
    bar_w = day_w * (e_day - s_day)
    add_rect(s, bar_x, row_y + Inches(0.06),
             bar_w, row_h - Inches(0.12),
             fill=color, line=None)
    # Lead tag on the bar
    add_text(s, bar_x + Inches(0.05), row_y + Inches(0.07),
             bar_w, row_h - Inches(0.12),
             lead, size=9, bold=True, color=WHITE, font=MONO)

# Legend
leg_y = Inches(6.85)
add_text(s, Inches(0.5), leg_y, Inches(1.2), Inches(0.22),
         'LEGEND:', size=9, bold=True, color=MUTED)
legends = [
    ('M', 'Madhavi'),
    ('R', 'Rupit'),
    ('R+M', 'Joint'),
]
lx = Inches(1.5)
for tag, desc in legends:
    add_pill(s, lx, leg_y - Inches(0.02), Inches(0.55), Inches(0.24),
             tag, fill=INK, color=WHITE, size=9)
    add_text(s, lx + Inches(0.62), leg_y, Inches(1.1), Inches(0.22),
             desc, size=9, color=BODY)
    lx += Inches(1.6)


# ── SLIDE 5: WEEK 1 (Sept 9-15) — FOUNDATION ─────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'WEEK 1  ·  9 - 15 SEP',
           'Foundation — environment, PDK, first dummy run',
           subtitle='Exit criterion: SYNTH_PNR runs end-to-end in test_mode against Sbarmathi tech_config.',
           footer_page=5)

# Two columns: Deliverables + Owners/Dates
wk_top = Inches(1.85); wk_h = Inches(5.1)
col_w = Inches(6.05); col_gap = Inches(0.25)

# Left: Deliverables
d_x = Inches(0.5)
add_rect(s, d_x, wk_top, col_w, wk_h, fill=WHITE, line=GREEN_DARK, line_w=Pt(1.25))
add_rect(s, d_x, wk_top, col_w, Inches(0.42), fill=GREEN_DARK)
add_text(s, d_x + Inches(0.2), wk_top + Inches(0.1),
         col_w - Inches(0.4), Inches(0.26),
         'DELIVERABLES', size=13, bold=True, color=WHITE, font=MONO)

w1_deliverables = [
    ('D1', 'CBflow installed under Sbarmathi paths (CBFLOW_CORE_DIR set)'),
    ('D2', 'Kickoff meeting held — roles, dates, escalation confirmed'),
    ('D3', 'Sbarmathi tech_config.tcl + project configs authored'),
    ('D4', 'library-manager scan + generate → lib_config_P0.tcl'),
    ('D5', 'mmmc-manager list-corners → coverage confirmed'),
    ('D6', 'User-config templates tuned (Cadence flow only)'),
    ('D7', 'Dummy SYNTH_PNR run passes in test_mode'),
]
dy = wk_top + Inches(0.6)
for tag, item in w1_deliverables:
    add_pill(s, d_x + Inches(0.25), dy + Inches(0.03), Inches(0.55), Inches(0.28),
             tag, fill=GREEN, color=WHITE, size=10)
    add_text(s, d_x + Inches(0.9), dy + Inches(0.06), col_w - Inches(1.1), Inches(0.3),
             item, size=11, color=BODY)
    dy += Inches(0.42)

# Right: Owners + dates
o_x = Inches(6.8)
add_rect(s, o_x, wk_top, col_w, wk_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, o_x, wk_top, col_w, Inches(0.42), fill=INK)
add_text(s, o_x + Inches(0.2), wk_top + Inches(0.1),
         col_w - Inches(0.4), Inches(0.26),
         'OWNERS  ·  KEY DATES', size=13, bold=True, color=WHITE, font=MONO)

w1_owners = [
    ('D1', 'Rupit',   '9 Sep',     'Sbarmathi filesystem + env vars'),
    ('D2', 'Both',    '10 Sep',    'Kickoff meeting @ 10 AM'),
    ('D3', 'Rupit',   '11 Sep',    'reviewed with Madhavi'),
    ('D4', 'Rupit',   '11-12 Sep', 'library-manager generate --tag P0'),
    ('D5', 'Rupit',   '12-13 Sep', 'PVT axes for Sbarmathi'),
    ('D6', 'Both',    '13 Sep',    'uc_SYNTH.tcl (M) + uc_PNR.tcl (R)'),
    ('D7', 'Madhavi', '15 Sep',    'W1 exit gate'),
]
oy = wk_top + Inches(0.6)
for tag, owner, when, note in w1_owners:
    add_pill(s, o_x + Inches(0.2), oy + Inches(0.03), Inches(0.5), Inches(0.28),
             tag, fill=GREEN, color=WHITE, size=9)
    add_text(s, o_x + Inches(0.8), oy + Inches(0.02), Inches(1.4), Inches(0.28),
             owner, size=11, bold=True, color=INK)
    add_text(s, o_x + Inches(2.3), oy + Inches(0.02), Inches(1.4), Inches(0.28),
             when, size=10, color=AMBER_DARK, font=MONO)
    add_text(s, o_x + Inches(0.8), oy + Inches(0.24), col_w - Inches(1.0), Inches(0.24),
             note, size=9, color=MUTED)
    oy += Inches(0.42)


# ── SLIDE 6: WEEK 2 (Sept 16-22) — Flow bring-up + signoff ───────────
s = prs.slides.add_slide(blank)
add_header(s, 'WEEK 2  ·  16 - 22 SEP',
           'Flow bring-up + signoff wiring — real design data',
           subtitle='Exit criterion: SYNTH_PNR + STA + LEC + CLP + PV + EMIR all run against real design inputs; PRO_EXIT green.',
           footer_page=6)

wk_top = Inches(1.85); wk_h = Inches(5.1)
col_w = Inches(6.05)

# Left: Deliverables
d_x = Inches(0.5)
add_rect(s, d_x, wk_top, col_w, wk_h, fill=WHITE, line=BLUE, line_w=Pt(1.25))
add_rect(s, d_x, wk_top, col_w, Inches(0.42), fill=BLUE)
add_text(s, d_x + Inches(0.2), wk_top + Inches(0.1),
         col_w - Inches(0.4), Inches(0.26),
         'DELIVERABLES', size=13, bold=True, color=WHITE, font=MONO)

w2_deliverables = [
    ('D8',  'mmmc-manager generate → mmmc_config.tcl'),
    ('D9',  'Real design inputs wired (netlist, SDC, UPF, DEF)'),
    ('D10', 'SYNTH flow closes on real RTL (Genus)'),
    ('D11', 'FP + PNR flow runs to PRO_EXIT (Innovus)'),
    ('D12', 'STA scenarios pass for baseline setup + hold (Tempus)'),
    ('D13', 'LEC checkpoints wired: RTL↔SYNTH, SYNTH↔PNR (Conformal)'),
    ('D14', 'CLP verifying UPF vs netlist (Conformal-LP)'),
    ('D15', 'PV + EMIR first pass (Pegasus + Voltus)'),
]
dy = wk_top + Inches(0.6)
for tag, item in w2_deliverables:
    add_pill(s, d_x + Inches(0.25), dy + Inches(0.03), Inches(0.55), Inches(0.28),
             tag, fill=BLUE, color=WHITE, size=10)
    add_text(s, d_x + Inches(0.9), dy + Inches(0.06), col_w - Inches(1.1), Inches(0.3),
             item, size=11, color=BODY)
    dy += Inches(0.38)

# Right: Owners + dates
o_x = Inches(6.8)
add_rect(s, o_x, wk_top, col_w, wk_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, o_x, wk_top, col_w, Inches(0.42), fill=INK)
add_text(s, o_x + Inches(0.2), wk_top + Inches(0.1),
         col_w - Inches(0.4), Inches(0.26),
         'OWNERS  ·  KEY DATES', size=13, bold=True, color=WHITE, font=MONO)

w2_owners = [
    ('D8',  'Rupit',   '16 Sep',    'mmmc-manager generate for cpu_core'),
    ('D9',  'Rupit',   '16-17 Sep', 'real inputs staged, checked'),
    ('D10', 'Madhavi', '18 Sep',    'first Genus run on real RTL'),
    ('D11', 'Rupit',   '19-20 Sep', 'Innovus PNR to PRO_EXIT'),
    ('D12', 'Madhavi', '20 Sep',    'Tempus MMMC scenarios'),
    ('D13', 'Madhavi', '21 Sep',    'Conformal LEC checkpoints'),
    ('D14', 'Madhavi', '21-22 Sep', 'Conformal-LP UPF audit'),
    ('D15', 'Rupit',   '22 Sep',    'W2 exit gate — Pegasus + Voltus'),
]
oy = wk_top + Inches(0.6)
for tag, owner, when, note in w2_owners:
    add_pill(s, o_x + Inches(0.2), oy + Inches(0.03), Inches(0.5), Inches(0.28),
             tag, fill=BLUE, color=WHITE, size=9)
    add_text(s, o_x + Inches(0.8), oy + Inches(0.02), Inches(1.4), Inches(0.28),
             owner, size=11, bold=True, color=INK)
    add_text(s, o_x + Inches(2.3), oy + Inches(0.02), Inches(1.6), Inches(0.28),
             when, size=10, color=AMBER_DARK, font=MONO)
    add_text(s, o_x + Inches(0.8), oy + Inches(0.24), col_w - Inches(1.0), Inches(0.22),
             note, size=9, color=MUTED)
    oy += Inches(0.38)


# ── SLIDE 7: WEEK 3 (Sept 23-30) — Checklists + tapeout DB ──────────
s = prs.slides.add_slide(blank)
add_header(s, 'WEEK 3  ·  23 - 30 SEP',
           'Checklists + tapeout DB — the closing week',
           subtitle='Exit criterion: BTO release_tag published, all 292+ checks green or documented-waived, runbook signed off.',
           footer_page=7)

wk_top = Inches(1.85); wk_h = Inches(5.1)
col_w = Inches(6.05)

# Left: Deliverables
d_x = Inches(0.5)
add_rect(s, d_x, wk_top, col_w, wk_h, fill=WHITE, line=AMBER_DARK, line_w=Pt(1.25))
add_rect(s, d_x, wk_top, col_w, Inches(0.42), fill=AMBER_DARK)
add_text(s, d_x + Inches(0.2), wk_top + Inches(0.1),
         col_w - Inches(0.4), Inches(0.26),
         'DELIVERABLES', size=13, bold=True, color=WHITE, font=MONO)

w3_deliverables = [
    ('D16', 'All 6 milestone checklists functional (FP → MTO)'),
    ('D17', 'Sbarmathi-specific custom checks added'),
    ('D18', 'Waivers recorded with rationale for any known gaps'),
    ('D19', 'BTO dry run — full 292-check pass'),
    ('D20', 'P0_BTO release_tag published + release-check clean'),
    ('D21', 'Runbook written + reviewed'),
    ('D22', 'SmartGenie KB ingested from new content'),
    ('D23', 'Final sign-off by both leads'),
]
dy = wk_top + Inches(0.6)
for tag, item in w3_deliverables:
    add_pill(s, d_x + Inches(0.25), dy + Inches(0.03), Inches(0.55), Inches(0.28),
             tag, fill=AMBER_DARK, color=WHITE, size=10)
    add_text(s, d_x + Inches(0.9), dy + Inches(0.06), col_w - Inches(1.1), Inches(0.3),
             item, size=11, color=BODY)
    dy += Inches(0.38)

# Right: Owners + dates
o_x = Inches(6.8)
add_rect(s, o_x, wk_top, col_w, wk_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, o_x, wk_top, col_w, Inches(0.42), fill=INK)
add_text(s, o_x + Inches(0.2), wk_top + Inches(0.1),
         col_w - Inches(0.4), Inches(0.26),
         'OWNERS  ·  KEY DATES', size=13, bold=True, color=WHITE, font=MONO)

w3_owners = [
    ('D16', 'Both',    '23-24 Sep', 'checklists for all 6 milestones'),
    ('D17', 'Both',    '24-25 Sep', 'M: TMG checks · R: RTG/PHY/MFG'),
    ('D18', 'Both',    '25 Sep',    'waivers signed by both leads'),
    ('D19', 'Both',    '26 Sep',    'BTO dry run — all-hands review'),
    ('D20', 'Rupit',   '27 Sep',    'release_tag P0_BTO'),
    ('D21', 'Both',    '28-29 Sep', 'runbook + escalation guide'),
    ('D22', 'Madhavi', '29 Sep',    'ingest --all --rebuild'),
    ('D23', 'Both',    '30 Sep',    'FINAL exit — deck to leadership'),
]
oy = wk_top + Inches(0.6)
for tag, owner, when, note in w3_owners:
    add_pill(s, o_x + Inches(0.2), oy + Inches(0.03), Inches(0.5), Inches(0.28),
             tag, fill=AMBER_DARK, color=WHITE, size=9)
    add_text(s, o_x + Inches(0.8), oy + Inches(0.02), Inches(1.4), Inches(0.28),
             owner, size=11, bold=True, color=INK)
    add_text(s, o_x + Inches(2.3), oy + Inches(0.02), Inches(1.6), Inches(0.28),
             when, size=10, color=AMBER_DARK, font=MONO)
    add_text(s, o_x + Inches(0.8), oy + Inches(0.24), col_w - Inches(1.0), Inches(0.22),
             note, size=9, color=MUTED)
    oy += Inches(0.38)


# ── SLIDE 8: DELIVERABLES CHECKLIST ───────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'DELIVERABLES',
           'What ships on Sept 30 — every artifact, every path, one owner',
           subtitle='This is what "tapeout-quality database" resolves to on the filesystem.',
           footer_page=8)

# Full-width table
dl_x = Inches(0.5); dl_y = Inches(1.85)
dl_w = Inches(12.35); dl_h = Inches(5.15)
add_rect(s, dl_x, dl_y, dl_w, dl_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
add_rect(s, dl_x, dl_y, dl_w, Inches(0.4), fill=INK)
add_text(s, dl_x + Inches(0.15), dl_y + Inches(0.08),
         dl_w - Inches(0.3), Inches(0.24),
         'FINAL DELIVERABLES  ·  30 SEP 2026',
         size=13, bold=True, color=WHITE, font=MONO)

# Column headers
hdr_y = dl_y + Inches(0.5)
add_text(s, dl_x + Inches(0.2), hdr_y, Inches(3.3), Inches(0.24),
         'ARTIFACT', size=10, bold=True, color=MUTED, font=MONO)
add_text(s, dl_x + Inches(3.6), hdr_y, Inches(6.7), Inches(0.24),
         'PATH', size=10, bold=True, color=MUTED, font=MONO)
add_text(s, dl_x + Inches(10.4), hdr_y, Inches(1.85), Inches(0.24),
         'OWNER', size=10, bold=True, color=MUTED, font=MONO)

deliverables = [
    ('tech_config.tcl',       '$CBFLOW_CORE_DIR/config/tech/sbarmathi/v1.0.0/tech_config.tcl',        'Rupit'),
    ('lib_config_P0.tcl',     '$CBFLOW_CORE_DIR/config/tech/sbarmathi/v1.0.0/lib_config_P0.tcl',     'Rupit'),
    ('mmmc_config.tcl',       '$CBFLOW_CORE_DIR/config/project/sbarmathi/v1.0.0/mmmc_config.tcl',    'Rupit'),
    ('SYNTH user config',     '$CBFLOW_CORE_DIR/config/templates/uc_SYNTH_genus.tcl (Sbarmathi)',    'Madhavi'),
    ('FP + PNR user configs', '$CBFLOW_CORE_DIR/config/templates/uc_FP_innovus.tcl · uc_PNR_innovus.tcl', 'Rupit'),
    ('STA + LEC user configs','$CBFLOW_CORE_DIR/config/templates/uc_STA_tempus.tcl · uc_LEC_conformal.tcl', 'Madhavi'),
    ('CLP + PV + EMIR configs','uc_CLP_conformal_lp.tcl · uc_PV_pegasus.tcl · uc_EMIR_voltus.tcl',   'Both'),
    ('Timing checks',         '$CBFLOW_CORE_DIR/config/exit/v1.0.0/checks/sbarmathi_tmg_*.tcl',      'Madhavi'),
    ('Physical + power checks','$CBFLOW_CORE_DIR/config/exit/v1.0.0/checks/sbarmathi_{rtg,phy,pwr}_*.tcl', 'Rupit'),
    ('Checklist configs',     '$CBFLOW_CORE_DIR/config/exit/v1.0.0/{FP,PLACE,CTS,PRO,BTO,MTO}_config.tcl', 'Both'),
    ('P0_BTO release',        'test_releases/sbarmathi/<design>/P0_BTO/  (MANIFEST.json)',           'Rupit'),
    ('Runbook',               'PD/docs/runbooks/sbarmathi_integration_runbook.md',                   'Both'),
    ('SmartGenie KB',         '~/.cbflow/smartgenie/kb/  (rebuilt with Sbarmathi content)',         'Madhavi'),
]
ey = hdr_y + Inches(0.32)
for i, (art, path, owner) in enumerate(deliverables):
    bg = PANEL if i % 2 == 0 else WHITE
    add_rect(s, dl_x + Inches(0.1), ey - Inches(0.03),
             dl_w - Inches(0.2), Inches(0.34), fill=bg, line=None)
    add_text(s, dl_x + Inches(0.2), ey, Inches(3.3), Inches(0.28),
             art, size=10, bold=True, color=GREEN_DARK, font=MONO)
    add_text(s, dl_x + Inches(3.6), ey, Inches(6.7), Inches(0.28),
             path, size=9, color=BODY, font=MONO)
    owner_color = GREEN_DARK if owner == 'Madhavi' else BLUE if owner == 'Rupit' else AMBER_DARK
    add_text(s, dl_x + Inches(10.4), ey, Inches(1.85), Inches(0.28),
             owner, size=10, bold=True, color=owner_color)
    ey += Inches(0.32)


# ── SLIDE 9: RISKS + SYNC CADENCE ─────────────────────────────────────
s = prs.slides.add_slide(blank)
add_header(s, 'RISKS  &  CADENCE',
           'What could slip  ·  how we stay ahead of it',
           subtitle='Named risks with owners. Daily sync + mid-week review + Friday leadership readout.',
           footer_page=9)

# Left: Risks
rk_x = Inches(0.5); rk_y = Inches(1.85)
rk_w = Inches(7.5); rk_h = Inches(5.15)
add_rect(s, rk_x, rk_y, rk_w, rk_h, fill=WHITE, line=RED_DARK, line_w=Pt(1.25))
add_rect(s, rk_x, rk_y, rk_w, Inches(0.42), fill=RED_DARK)
add_text(s, rk_x + Inches(0.2), rk_y + Inches(0.1),
         rk_w - Inches(0.4), Inches(0.26),
         'RISKS  ·  MITIGATION  ·  OWNER',
         size=13, bold=True, color=WHITE, font=MONO)

risks = [
    ('Sbarmathi PDK missing corners',
     'Bootstrap with --allow-missing; document gaps in W1 for later fills',
     'Rupit'),
    ('LSF license contention',
     'Reserve queue for W2/W3; fall back to local runs for smoke tests',
     'Rupit'),
    ('Foundry deck update mid-flight',
     'Freeze runset at kickoff (Sept 9); any late deck goes into Phase 2',
     'Rupit'),
    ('Real design inputs not ready',
     'W1 uses test_mode; W2 needs firm delivery date from design team',
     'Rupit'),
    ('MMMC scenario explosion',
     'Filter to signoff-set only for BTO; power/opt scenarios can wait',
     'Madhavi'),
    ('Signoff gate reveals blockers',
     'Mid-week review Sept 19 catches issues early; escalate same day',
     'Both'),
    ('SmartGenie KB drift on new content',
     'ingest --all --rebuild scheduled at W3 close; verify with sample queries',
     'Madhavi'),
]
ry_y = rk_y + Inches(0.55)
for name, mit, owner in risks:
    add_text(s, rk_x + Inches(0.25), ry_y, rk_w - Inches(0.4), Inches(0.24),
             '·  ' + name, size=11, bold=True, color=RED_DARK)
    add_text(s, rk_x + Inches(0.45), ry_y + Inches(0.26),
             rk_w - Inches(2.0), Inches(0.4),
             mit, size=9, color=BODY)
    owner_color = GREEN_DARK if owner == 'Madhavi' else BLUE if owner == 'Rupit' else AMBER_DARK
    add_pill(s, rk_x + rk_w - Inches(0.95), ry_y + Inches(0.28),
             Inches(0.75), Inches(0.24),
             owner, fill=owner_color, color=WHITE, size=8)
    ry_y += Inches(0.63)

# Right: Sync cadence
sc_x = Inches(8.15); sc_y = Inches(1.85)
sc_w = Inches(4.7); sc_h = Inches(5.15)
add_rect(s, sc_x, sc_y, sc_w, sc_h, fill=WHITE, line=BLUE, line_w=Pt(1.25))
add_rect(s, sc_x, sc_y, sc_w, Inches(0.42), fill=BLUE)
add_text(s, sc_x + Inches(0.2), sc_y + Inches(0.1),
         sc_w - Inches(0.4), Inches(0.26),
         'SYNC CADENCE', size=13, bold=True, color=WHITE, font=MONO)

cadence = [
    ('DAILY',     'Standup 15 min',       'Madhavi + Rupit, 9:30 AM'),
    ('MID-WEEK',  'Progress review',     'Wednesdays, 11 AM (Sept 17, 24)'),
    ('WEEKLY',    'Leadership readout',  'Fridays, 4 PM (Sept 12, 19, 26)'),
    ('AD-HOC',    'Blocker escalation',  'Same-day if anything blocks > 1 day'),
    ('GATE',      'W1 exit review',      'Mon 15 Sep AM'),
    ('GATE',      'W2 exit review',      'Mon 22 Sep AM'),
    ('GATE',      'BTO dry run',         'Fri 26 Sep — all-hands'),
    ('FINAL',     'Signoff + handoff',   'Tue 30 Sep — deck to leadership'),
]
cy = sc_y + Inches(0.55)
for tag, name, when in cadence:
    add_pill(s, sc_x + Inches(0.2), cy + Inches(0.03),
             Inches(0.95), Inches(0.28),
             tag, fill=BLUE, color=WHITE, size=9)
    add_text(s, sc_x + Inches(1.25), cy + Inches(0.02),
             sc_w - Inches(1.4), Inches(0.28),
             name, size=11, bold=True, color=INK)
    add_text(s, sc_x + Inches(1.25), cy + Inches(0.24),
             sc_w - Inches(1.4), Inches(0.24),
             when, size=9, color=MUTED)
    cy += Inches(0.55)


# ── SLIDE 10: CLOSING / NEXT STEPS ────────────────────────────────────
s = prs.slides.add_slide(blank)
add_rect(s, 0, 0, Inches(0.4), SH, fill=GREEN)
add_rect(s, Inches(0.4), 0, Inches(0.15), SH, fill=BLUE)

add_text(s, Inches(1.0), Inches(0.7), Inches(11.5), Inches(0.4),
         'NEXT STEPS', size=13, bold=True, color=MUTED)
add_text(s, Inches(1.0), Inches(1.05), Inches(11.5), Inches(0.9),
         'On Sept 30, hand over a tapeout-quality Sbarmathi database.',
         size=26, bold=True, color=INK)
add_text(s, Inches(1.0), Inches(1.85), Inches(11.5), Inches(0.5),
         'Signed off. Consumable via release_tag. Reproducible from CBflow config.',
         size=14, color=BODY)

# 3-column: Today | This Week | End of Sept
nx_top = Inches(3.0); nx_h = Inches(3.5)
col_w = Inches(4.0); col_gap = Inches(0.13)

def _next_card(x, kicker, kicker_color, big, small, items):
    add_rect(s, x, nx_top, col_w, nx_h, fill=WHITE, line=LINE, line_w=Pt(0.75))
    add_rect(s, x, nx_top, col_w, Inches(0.42), fill=kicker_color)
    add_text(s, x + Inches(0.15), nx_top + Inches(0.1),
             col_w - Inches(0.3), Inches(0.24),
             kicker, size=11, bold=True, color=WHITE, font=MONO)
    add_text(s, x + Inches(0.2), nx_top + Inches(0.6),
             col_w - Inches(0.4), Inches(0.4),
             big, size=20, bold=True, color=INK)
    add_text(s, x + Inches(0.2), nx_top + Inches(1.0),
             col_w - Inches(0.4), Inches(0.28),
             small, size=10, color=MUTED)
    iy = nx_top + Inches(1.4)
    for it in items:
        add_text(s, x + Inches(0.3), iy, col_w - Inches(0.5), Inches(0.28),
                 '·  ' + it, size=10, color=BODY)
        iy += Inches(0.32)

_next_card(Inches(1.0), 'TODAY  ·  9 SEP', GREEN_DARK,
           'Kickoff', 'Confirm everything in this deck',
           ['Roles + escalation confirmed',
            'Rupit starts env setup',
            'Madhavi opens flow-config PRs',
            'Team channels created'])

_next_card(Inches(1.0) + col_w + col_gap, 'THIS WEEK  ·  W1', BLUE,
           'Foundation', 'Sept 9 - 15 (see slide 5)',
           ['tech_config.tcl (Rupit)',
            'lib_config_P0.tcl (Madhavi)',
            'Test-mode SYNTH_PNR (Both)',
            'Kickoff meeting Sept 10'])

_next_card(Inches(1.0) + 2 * (col_w + col_gap), 'GOAL  ·  30 SEP', AMBER_DARK,
           'Tapeout-DB', 'Complete + signed off',
           ['P0_BTO release_tag published',
            '292+ checks green (or waived)',
            'Runbook + SmartGenie KB',
            'Deck to leadership'])

add_text(s, Inches(1.0), Inches(7.05), Inches(11), Inches(0.3),
         'Questions to leads: Madhavi (CBflow) · Rupit (Sbarmathi)   ·   SmartSoC Solutions',
         size=11, color=MUTED)


# ── SAVE ────────────────────────────────────────────────────────────────
out = 'PD/docs/sales/CBflow_Sbarmathi_Integration_Schedule.pptx'
prs.save(out)
print(f'Wrote {out} with {len(prs.slides)} slide(s).')
