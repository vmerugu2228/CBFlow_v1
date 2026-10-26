#!/usr/bin/env python3
"""
Build SmartSoC_PD_Upskilling_Plan.pptx — standalone 4-slide deck covering
the PD team skillset evaluation and Q4-2026 upskilling plan.

Built on the official SmartSoC master template so the deck ships with
brand chrome (header group, divider, confidentiality footer, slide number).

Slides:
  1  Cover
  2  Skillset evaluation — current vs target across 9 PD domains
  3  Q4-2026 upskilling Gantt — 12-week plan across the same 9 domains
  4  Methodology — Foundation → Hands-on → Project phases, assessment
"""

import os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

TEMPLATE = os.path.expanduser(
    '~/Downloads/SmartSoC_Presentation_Template V3.0  (Jan 26).pptx')
OUT      = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'SmartSoC_PD_Upskilling_Plan.pptx')

# Brand palette (matches the Micron RFP deck)
NAVY    = RGBColor(0x0B, 0x1F, 0x3A)
NAVY_D  = RGBColor(0x05, 0x12, 0x24)
TEAL    = RGBColor(0x0E, 0xA5, 0xE9)
TEAL_D  = RGBColor(0x02, 0x74, 0x90)
ACCENT  = RGBColor(0x4F, 0x46, 0xE5)
GREEN   = RGBColor(0x00, 0xA6, 0x4F)
AMBER   = RGBColor(0xF5, 0x9E, 0x0B)
GRAY    = RGBColor(0x9C, 0xA3, 0xAF)
INK     = RGBColor(0x0F, 0x14, 0x1B)
BODY    = RGBColor(0x33, 0x39, 0x46)
MUTED   = RGBColor(0x6B, 0x72, 0x80)
WHITE   = RGBColor(0xFF, 0xFF, 0xFF)
PANEL   = RGBColor(0xF4, 0xF6, 0xFB)
LINE    = RGBColor(0xD4, 0xDA, 0xE5)
BAND    = RGBColor(0xEE, 0xF4, 0xFB)

FONT = 'Calibri'

LEVEL_COLORS = {
    'Beg': GRAY, 'Int': AMBER, 'Adv': TEAL, 'Exp': GREEN,
}

# Phase colors
FND  = ACCENT  # Foundation / refresher
HOL  = TEAL    # Hands-on labs
PROJ = GREEN   # Project exercises / Micron-chip orientation

# PD domain roster. Each row:
#   (domain, current_level, target_level, [phases])
#   phase = (start_week, end_week, label, color)
DOMAINS = [
    ('Synthesis (Genus / Design Compiler)',  'Int', 'Exp',
        [(1, 3,  'Foundation', FND), (4, 7,  'Hands-on', HOL),
         (8, 12, 'Project',    PROJ)]),
    ('Full-Chip Floorplan (FCFP)',           'Int', 'Exp',
        [(1, 4,  'Foundation', FND), (5, 9,  'Hands-on', HOL),
         (10, 12,'Project',    PROJ)]),
    ('Floorplan + Powerplan (ICC2 / Innovus)','Adv', 'Exp',
        [(1, 2,  'Refresher',  FND), (3, 7,  'Hands-on', HOL),
         (8, 12, 'Project',    PROJ)]),
    ('Place & Route (block implementation)', 'Int', 'Exp',
        [(1, 3,  'Foundation', FND), (4, 8,  'Hands-on', HOL),
         (9, 12, 'Project',    PROJ)]),
    ('Clock Tree Synthesis (CTS)',           'Int', 'Adv',
        [(2, 4,  'Foundation', FND), (5, 9,  'Hands-on', HOL)]),
    ('STA Signoff (PrimeTime / Tempus)',     'Adv', 'Exp',
        [(1, 2,  'Refresher',  FND), (3, 8,  'Hands-on', HOL),
         (9, 12, 'Project',    PROJ)]),
    ('EMIR / IR drop (RedHawk / Voltus)',    'Int', 'Adv',
        [(1, 4,  'Foundation', FND), (5, 10, 'Hands-on', HOL),
         (11, 12,'Project',    PROJ)]),
    ('LEC / CLP (Formality / Conformal LP)', 'Adv', 'Exp',
        [(5, 7,  'Refresher',  FND), (8, 12, 'Hands-on', HOL)]),
    ('Physical Verification (Calibre)',      'Adv', 'Exp',
        [(3, 5,  'Refresher',  FND), (6, 10, 'Hands-on', HOL),
         (11, 12,'Project',    PROJ)]),
]


# ── Helpers ────────────────────────────────────────────────────────────
def _strip_existing_slides(prs):
    sldIdLst = prs.slides._sldIdLst
    for sldId in list(sldIdLst):
        rId = sldId.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
        prs.part.drop_rel(rId)
        sldIdLst.remove(sldId)


def _add_rect(slide, l, t, w, h, fill, line=None):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, l, t, w, h)
    if line is None:
        sh.line.fill.background()
    else:
        sh.line.color.rgb = line
        sh.line.width = Pt(0.75)
    sh.fill.solid(); sh.fill.fore_color.rgb = fill
    sh.shadow.inherit = False
    return sh


def _tb(slide, l, t, w, h, text, *, font=FONT, size=11, bold=False,
        italic=False, color=INK, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP):
    tx = slide.shapes.add_textbox(l, t, w, h).text_frame
    tx.margin_left = tx.margin_right = Inches(0.04)
    tx.margin_top = tx.margin_bottom = Inches(0.02)
    tx.word_wrap = True
    tx.vertical_anchor = anchor
    p = tx.paragraphs[0]; p.alignment = align
    r = p.add_run(); r.text = text
    r.font.name = font; r.font.size = Pt(size); r.font.bold = bold
    r.font.italic = italic; r.font.color.rgb = color
    return tx


def _content_header(s, kicker, title):
    _tb(s, Inches(0.7), Inches(1.65), Inches(18.6), Inches(0.35),
        kicker.upper(), size=12, bold=True, color=TEAL_D)
    _tb(s, Inches(0.7), Inches(2.0), Inches(18.6), Inches(0.6),
        title, size=28, bold=True, color=NAVY)
    _add_rect(s, Inches(0.7), Inches(2.65), Inches(1.0), Inches(0.06), TEAL)


def _chip(s, l, t, w, h, text, color):
    _add_rect(s, l, t, w, h, color)
    _tb(s, l, t, w, h, text,
        size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)


# ── Slide 1: Cover ─────────────────────────────────────────────────────
def slide_cover(prs):
    s = prs.slides.add_slide(prs.slide_layouts[7])
    for ph in s.placeholders:
        name = ph.name.lower()
        tf = ph.text_frame; tf.clear()
        p = tf.paragraphs[0]; p.alignment = PP_ALIGN.LEFT
        if 'title' in name and 'subtitle' not in name:
            r = p.add_run()
            r.text = 'PD Team · Skillset Evaluation + Upskilling Plan'
            r.font.size = Pt(42); r.font.bold = True
            r.font.color.rgb = NAVY
            p2 = tf.add_paragraph()
            r2 = p2.add_run()
            r2.text = 'Q4 2026 ramp to engagement-ready proficiency'
            r2.font.size = Pt(24); r2.font.bold = True
            r2.font.color.rgb = TEAL_D
        elif 'subtitle' in name:
            r = p.add_run()
            r.text = ('9 PD domains  ·  12-week Oct → Dec plan  ·  '
                      'Target: Advanced / Expert across all tracks by Jan 2027')
            r.font.size = Pt(18); r.font.color.rgb = BODY
            p2 = tf.add_paragraph(); r2 = p2.add_run()
            r2.text = ('SmartSoC CAD  ·  Varun Reddy Merugu  ·  '
                       'varun@smartsocs.com')
            r2.font.size = Pt(14); r2.font.bold = True
            r2.font.color.rgb = NAVY


# ── Slide 2: Skillset evaluation (current vs target) ──────────────────
def slide_skill_matrix(prs):
    s = prs.slides.add_slide(prs.slide_layouts[4])
    _content_header(s, 'SKILLSET EVALUATION',
                    'Current vs target proficiency across 9 PD domains')

    tbl_t  = Inches(3.0)
    tbl_l  = Inches(0.7)
    name_w = Inches(7.0)
    chip_w = Inches(1.8)
    gap_w  = Inches(1.6)
    note_w = Inches(20.0 - 0.7 - 7.0 - 1.8 - 1.8 - 1.6 - 0.7)
    row_h  = Inches(0.6)

    # Header
    _add_rect(s, tbl_l, tbl_t, name_w, row_h, NAVY)
    _tb(s, tbl_l + Inches(0.2), tbl_t, name_w, row_h,
        'PD Domain', size=14, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, tbl_l + name_w, tbl_t, chip_w, row_h, NAVY)
    _tb(s, tbl_l + name_w, tbl_t, chip_w, row_h,
        'Current', size=13, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, tbl_l + name_w + chip_w, tbl_t, chip_w, row_h, NAVY)
    _tb(s, tbl_l + name_w + chip_w, tbl_t, chip_w, row_h,
        'Target', size=13, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, tbl_l + name_w + 2*chip_w, tbl_t, gap_w, row_h, NAVY)
    _tb(s, tbl_l + name_w + 2*chip_w, tbl_t, gap_w, row_h,
        'Gap', size=13, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, tbl_l + name_w + 2*chip_w + gap_w, tbl_t, note_w, row_h, NAVY)
    _tb(s, tbl_l + name_w + 2*chip_w + gap_w + Inches(0.2), tbl_t,
        note_w, row_h, 'Primary upskilling focus',
        size=13, bold=True, color=WHITE, anchor=MSO_ANCHOR.MIDDLE)

    # Short upskilling-focus notes per domain
    FOCUS = {
        'Synthesis (Genus / Design Compiler)':
            'Modern constraints + QoR tuning on 7nm+ reference flow',
        'Full-Chip Floorplan (FCFP)':
            'Hierarchical partition + top-level timing budget methodology',
        'Floorplan + Powerplan (ICC2 / Innovus)':
            'Multi-VT grid + mesh/strap optimization on 7nm reference',
        'Place & Route (block implementation)':
            'Flow convergence + ECO methodology on advanced-node blocks',
        'Clock Tree Synthesis (CTS)':
            'Skew + latency control on complex clock meshes',
        'STA Signoff (PrimeTime / Tempus)':
            'MMMC closure + variation-aware signoff',
        'EMIR / IR drop (RedHawk / Voltus)':
            'Dynamic IR + full-chip EM signoff on advanced-node PGs',
        'LEC / CLP (Formality / Conformal LP)':
            'Multi-voltage LEC + CLP sign-off on UPF-isolated designs',
        'Physical Verification (Calibre)':
            'DRC+LVS deck mastery + fill / antenna / LVS-stage flow',
    }

    GAP_LABEL = {
        ('Int', 'Exp'): ('Int → Exp', '2 levels'),
        ('Int', 'Adv'): ('Int → Adv', '1 level'),
        ('Adv', 'Exp'): ('Adv → Exp', '1 level'),
        ('Beg', 'Int'): ('Beg → Int', '1 level'),
        ('Beg', 'Adv'): ('Beg → Adv', '2 levels'),
    }

    y = tbl_t + row_h
    for name, cur, tgt, _phases in DOMAINS:
        _add_rect(s, tbl_l, y, name_w, row_h, PANEL, line=LINE)
        _tb(s, tbl_l + Inches(0.2), y, name_w, row_h,
            name, size=12, bold=True, color=INK,
            anchor=MSO_ANCHOR.MIDDLE)

        # Current chip
        _add_rect(s, tbl_l + name_w, y, chip_w, row_h, WHITE, line=LINE)
        _chip(s, tbl_l + name_w + Inches(0.3),
              y + Inches(0.12), chip_w - Inches(0.6), row_h - Inches(0.24),
              cur, LEVEL_COLORS[cur])

        # Target chip
        _add_rect(s, tbl_l + name_w + chip_w, y, chip_w, row_h, WHITE,
                  line=LINE)
        _chip(s, tbl_l + name_w + chip_w + Inches(0.3),
              y + Inches(0.12), chip_w - Inches(0.6), row_h - Inches(0.24),
              tgt, LEVEL_COLORS[tgt])

        # Gap chip
        _add_rect(s, tbl_l + name_w + 2*chip_w, y, gap_w, row_h, WHITE,
                  line=LINE)
        label, size_lbl = GAP_LABEL.get((cur, tgt), (f'{cur}→{tgt}', '—'))
        _tb(s, tbl_l + name_w + 2*chip_w, y, gap_w, row_h - Inches(0.18),
            label, size=12, bold=True, color=NAVY, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        _tb(s, tbl_l + name_w + 2*chip_w, y + Inches(0.3), gap_w,
            Inches(0.3), size_lbl, size=10, color=MUTED,
            align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)

        # Note
        _add_rect(s, tbl_l + name_w + 2*chip_w + gap_w, y, note_w, row_h,
                  BAND, line=LINE)
        _tb(s, tbl_l + name_w + 2*chip_w + gap_w + Inches(0.2), y,
            note_w - Inches(0.3), row_h, FOCUS.get(name, ''),
            size=11, color=BODY, anchor=MSO_ANCHOR.MIDDLE)

        y += row_h

    # Legend
    leg_y = y + Inches(0.25)
    _tb(s, tbl_l, leg_y - Inches(0.3), Inches(5), Inches(0.3),
        'Skill levels:', size=12, bold=True, color=MUTED)
    for i, (lvl, text) in enumerate([
            ('Beg', 'Beginner — training required'),
            ('Int', 'Intermediate — proficient on vendor flow'),
            ('Adv', 'Advanced — tape-out-grade block owner'),
            ('Exp', 'Expert — mentors, drives methodology')]):
        kx = tbl_l + Inches(4.4) * i
        _add_rect(s, kx, leg_y, Inches(0.6), Inches(0.3), LEVEL_COLORS[lvl])
        _tb(s, kx, leg_y - Inches(0.02), Inches(0.6), Inches(0.35),
            lvl, size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        _tb(s, kx + Inches(0.7), leg_y - Inches(0.02),
            Inches(3.5), Inches(0.35), text,
            size=10, color=BODY, anchor=MSO_ANCHOR.MIDDLE)


# ── Slide 3: Q4-2026 Gantt chart ──────────────────────────────────────
def slide_q4_gantt(prs):
    s = prs.slides.add_slide(prs.slide_layouts[4])
    _content_header(s, 'Q4-2026 UPSKILLING PLAN',
                    '12-week Gantt · Oct → Dec across 9 PD domains')

    tbl_t   = Inches(3.0)
    tbl_l   = Inches(0.7)
    name_w  = Inches(5.5)
    weeks_w = Inches(20.0 - 0.7 - 5.5 - 0.7)
    week_w  = weeks_w / 12
    row_h   = Inches(0.52)

    # Month ribbon
    _add_rect(s, tbl_l, tbl_t, name_w, Inches(0.26), NAVY_D)
    _tb(s, tbl_l + Inches(0.2), tbl_t, name_w, Inches(0.26),
        'PD Domain', size=10, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    MONTH_LABELS = [('Oct 2026', 4), ('Nov 2026', 4), ('Dec 2026', 4)]
    gx = tbl_l + name_w
    for mlabel, span in MONTH_LABELS:
        mw = week_w * span
        _add_rect(s, gx, tbl_t, mw, Inches(0.26), TEAL_D)
        _tb(s, gx, tbl_t, mw, Inches(0.26), mlabel,
            size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        gx += mw
    # Week numbers
    _add_rect(s, tbl_l, tbl_t + Inches(0.26), name_w, Inches(0.28), NAVY)
    _tb(s, tbl_l + Inches(0.2), tbl_t + Inches(0.26), name_w, Inches(0.28),
        '(domain)', size=10, italic=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i in range(12):
        x = tbl_l + name_w + week_w * i
        _add_rect(s, x, tbl_t + Inches(0.26), week_w, Inches(0.28), NAVY)
        _tb(s, x, tbl_t + Inches(0.26), week_w, Inches(0.28), f'W{i+1}',
            size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)

    # Data rows
    y = tbl_t + Inches(0.54)
    for name, cur, tgt, phases in DOMAINS:
        # Row label with level chips inline
        _add_rect(s, tbl_l, y, name_w, row_h, PANEL, line=LINE)
        _tb(s, tbl_l + Inches(0.2), y, name_w - Inches(1.4), row_h,
            name, size=11, bold=True, color=INK, anchor=MSO_ANCHOR.MIDDLE)
        # Mini chips at right edge of name cell
        _chip(s, tbl_l + name_w - Inches(1.3), y + Inches(0.14),
              Inches(0.52), row_h - Inches(0.28),
              cur, LEVEL_COLORS[cur])
        _tb(s, tbl_l + name_w - Inches(0.75), y + Inches(0.12),
            Inches(0.3), row_h - Inches(0.24),
            '→', size=12, bold=True, color=MUTED, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        _chip(s, tbl_l + name_w - Inches(0.52), y + Inches(0.14),
              Inches(0.52), row_h - Inches(0.28),
              tgt, LEVEL_COLORS[tgt])

        # Gridlines
        for i in range(12):
            x = tbl_l + name_w + week_w * i
            _add_rect(s, x, y, week_w, row_h, WHITE, line=LINE)

        # Phase bars
        bar_h = row_h - Inches(0.16)
        bar_pad_y = Inches(0.08)
        for (ws, we, label, color) in phases:
            bx = tbl_l + name_w + week_w * (ws - 1) + Inches(0.04)
            bw = week_w * (we - ws + 1) - Inches(0.08)
            _add_rect(s, bx, y + bar_pad_y, bw, bar_h, color)
            if (we - ws + 1) >= 2:
                _tb(s, bx, y + bar_pad_y, bw, bar_h, label,
                    size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
                    anchor=MSO_ANCHOR.MIDDLE)
        y += row_h

    # Legend + assessment marker
    leg_y = y + Inches(0.2)
    legend = [
        (FND,  'Foundation / Refresher — vendor materials, concept review'),
        (HOL,  'Hands-on labs — vendor-led workshops on reference designs'),
        (PROJ, 'Project exercises — Micron-chip orientation + sign-off dry run'),
    ]
    lx = tbl_l
    for color, text in legend:
        _add_rect(s, lx, leg_y, Inches(0.3), Inches(0.3), color)
        _tb(s, lx + Inches(0.42), leg_y - Inches(0.02),
            Inches(6.0), Inches(0.35), text,
            size=11, bold=True, color=INK, anchor=MSO_ANCHOR.MIDDLE)
        lx += Inches(6.3)


# ── Slide 4: Methodology + assessment ─────────────────────────────────
def slide_methodology(prs):
    s = prs.slides.add_slide(prs.slide_layouts[4])
    _content_header(s, 'METHODOLOGY',
                    'Three-phase progression + assessment gates')

    # Three phase cards side by side
    card_t = Inches(3.0)
    card_w = Inches((20.0 - 0.7 - 0.7 - 2 * 0.4) / 3)
    card_h = Inches(4.6)
    gap    = Inches(0.4)

    phases = [
        ('FOUNDATION', 'Weeks 1–4', FND,
         'Baseline refresh of principles + vendor materials',
         [
             'Theory refresher — timing, floorplanning, power, PV concepts',
             'Vendor documentation walkthrough (Cadence / Synopsys / Siemens)',
             'Flow-level overview of the Micron reference methodology',
             'Pre-assessment to confirm Current → Target gap size',
         ],
         'Exit gate: concept quiz + flow-sequence quiz · >= 80% to advance.'),
        ('HANDS-ON', 'Weeks 3–10', HOL,
         'Vendor-led workshops on real reference designs',
         [
             'Guided labs on a representative block (7nm-class reference)',
             'Daily short-cycle runs with the engineer owning the knobs',
             'Pair-mentoring from a senior PD engineer on each domain',
             'Weekly QoR / closure checkpoints vs reference-run targets',
         ],
         'Exit gate: block-level QoR must match reference baseline within '
         '5% WNS / 10% leakage.'),
        ('PROJECT', 'Weeks 8–12', PROJ,
         'Micron-chip orientation + sign-off dry run',
         [
             'Micron tech + methodology orientation (NDA under RFP terms)',
             'End-to-end block run on Micron-representative RTL + constraints',
             'Full MMMC sign-off dry run with LEC / CLP / PV handoff',
             'Pre-engagement checkpoint review with Micron CAD / PD leads',
         ],
         'Exit gate: tape-out-ready block checkpoint reviewed + signed off '
         'by SmartSoC PD lead + Micron reviewer.'),
    ]

    for i, (name, dates, color, head, bullets, gate) in enumerate(phases):
        cx = Inches(0.7) + (card_w + gap) * i
        # Phase header strip
        _add_rect(s, cx, card_t, card_w, Inches(0.75), color)
        _tb(s, cx + Inches(0.3), card_t + Inches(0.08),
            card_w - Inches(0.6), Inches(0.32),
            name, size=14, bold=True, color=WHITE)
        _tb(s, cx + Inches(0.3), card_t + Inches(0.42),
            card_w - Inches(0.6), Inches(0.3),
            dates, size=11, bold=True, color=WHITE)
        # Body
        _add_rect(s, cx, card_t + Inches(0.75), card_w,
                  card_h - Inches(0.75), PANEL, line=LINE)
        _tb(s, cx + Inches(0.3), card_t + Inches(0.9),
            card_w - Inches(0.6), Inches(0.5),
            head, size=12, bold=True, italic=True, color=NAVY,
            anchor=MSO_ANCHOR.MIDDLE)
        # Bullets
        by = card_t + Inches(1.5)
        for bullet in bullets:
            # Bullet dot
            dot = s.shapes.add_shape(MSO_SHAPE.OVAL,
                                     cx + Inches(0.35), by + Inches(0.1),
                                     Inches(0.1), Inches(0.1))
            dot.fill.solid(); dot.fill.fore_color.rgb = color
            dot.line.fill.background(); dot.shadow.inherit = False
            _tb(s, cx + Inches(0.55), by, card_w - Inches(0.8), Inches(0.6),
                bullet, size=11, color=BODY)
            by += Inches(0.55)
        # Gate strip at bottom of card
        gate_t = card_t + card_h - Inches(0.85)
        _add_rect(s, cx + Inches(0.2), gate_t, card_w - Inches(0.4),
                  Inches(0.72), WHITE, line=color)
        _add_rect(s, cx + Inches(0.2), gate_t, Inches(0.08),
                  Inches(0.72), color)
        _tb(s, cx + Inches(0.4), gate_t + Inches(0.04),
            card_w - Inches(0.6), Inches(0.3),
            'EXIT GATE', size=9, bold=True, color=color)
        _tb(s, cx + Inches(0.4), gate_t + Inches(0.26),
            card_w - Inches(0.6), Inches(0.55),
            gate, size=10, color=BODY)

    # Readiness strip at the bottom
    strip_t = card_t + card_h + Inches(0.4)
    _add_rect(s, Inches(0.7), strip_t, Inches(20 - 1.4), Inches(0.9), NAVY)
    _add_rect(s, Inches(0.7), strip_t, Inches(0.1), Inches(0.9), GREEN)
    _tb(s, Inches(1.0), strip_t + Inches(0.1), Inches(5), Inches(0.3),
        'JAN 2027 — ENGAGEMENT READINESS', size=11, bold=True, color=GREEN)
    _tb(s, Inches(1.0), strip_t + Inches(0.4), Inches(20 - 2), Inches(0.5),
        'Every PD domain certified at its target level · '
        'Team is productive from Day 1 of block-level implementation.',
        size=13, bold=True, color=WHITE)


# ── Main ──────────────────────────────────────────────────────────────
def main():
    if not os.path.isfile(TEMPLATE):
        raise SystemExit(f'template not found: {TEMPLATE}')
    prs = Presentation(TEMPLATE)
    _strip_existing_slides(prs)

    slide_cover(prs)
    slide_skill_matrix(prs)
    slide_q4_gantt(prs)
    slide_methodology(prs)

    prs.save(OUT)
    print(f'wrote: {OUT}')
    print(f'  slides: {len(prs.slides)}')


if __name__ == '__main__':
    main()
