#!/usr/bin/env python3
"""
Build SmartSoC_Micron_RFP_Deck.pptx — 5-slide companion to the RFP response
document. Resources + timeline only. No pricing. No tool pitch.

Slides:
  1  Cover
  2  Scope + 8-month engagement window
  3  PD resource plan (Dec-26 → Jul-27)
  4  Analog resource plan (Dec-26 → Jul-27)
  5  Program total + delivery timeline summary

Brand: SmartSoC CAD · Varun Reddy Merugu <varun@smartsocs.com>
"""

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

# Palette
NAVY       = RGBColor(0x0B, 0x1F, 0x3A)
NAVY_D     = RGBColor(0x05, 0x12, 0x24)
TEAL       = RGBColor(0x0E, 0xA5, 0xE9)
TEAL_D     = RGBColor(0x02, 0x74, 0x90)
ACCENT     = RGBColor(0x4F, 0x46, 0xE5)
INK        = RGBColor(0x0F, 0x14, 0x1B)
BODY       = RGBColor(0x33, 0x39, 0x46)
MUTED      = RGBColor(0x6B, 0x72, 0x80)
WHITE      = RGBColor(0xFF, 0xFF, 0xFF)
PANEL      = RGBColor(0xF4, 0xF6, 0xFB)
LINE       = RGBColor(0xD4, 0xDA, 0xE5)
BAND_PD    = RGBColor(0xE0, 0xF2, 0xFE)
BAND_AN    = RGBColor(0xFF, 0xF3, 0xDC)
AMBER      = RGBColor(0xB4, 0x53, 0x09)

FONT = 'Calibri'
SW   = Inches(13.333)
SH   = Inches(7.5)

# ── Resource data (from supplied planning sheet) ────────────────────────
MONTHS = ['Dec-26', 'Jan-27', 'Feb-27', 'Mar-27', 'Apr-27',
          'May-27', 'Jun-27', 'Jul-27']

PD_ROWS = [
    ('Synthesis',                            [1]*8),
    ('Full-Chip Floorplan (FCFP) + Impl.',   [1]*8),
    ('Block-Level Implementation',           [2]*8),
    ('FCT / STA',                            [1]*8),
    ('EMIR / PDN / Signoff (LEC/CLP)',       [1]*8),
    ('Physical Verification (DRC/LVS)',      [1]*8),
    ('Project / Program Management',         [1]*8),
]

ANALOG_ROWS = [
    ('Analog Design',                        [5]*8),
    ('Analog Layout',                        [6, 8, 8, 8, 10, 10, 10, 8]),
]


def _add_rect(slide, l, t, w, h, fill, line=None):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, l, t, w, h)
    sh.line.fill.background() if line is None else _solid_line(sh, line)
    sh.fill.solid(); sh.fill.fore_color.rgb = fill
    sh.shadow.inherit = False
    return sh


def _solid_line(sh, color, width=0.75):
    sh.line.color.rgb = color
    sh.line.width = Pt(width)


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


def _bg(slide, fill=WHITE):
    _add_rect(slide, 0, 0, SW, SH, fill)


def _header(slide, kicker, title):
    _add_rect(slide, 0, 0, SW, Inches(0.9), NAVY)
    _add_rect(slide, 0, Inches(0.9), SW, Inches(0.04), TEAL)
    _tb(slide, Inches(0.5), Inches(0.1), SW, Inches(0.3),
        kicker, size=10, bold=True, color=TEAL,
        anchor=MSO_ANCHOR.TOP)
    _tb(slide, Inches(0.5), Inches(0.35), SW - Inches(1.0), Inches(0.55),
        title, size=22, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)


def _footer(slide):
    _add_rect(slide, 0, SH - Inches(0.38), SW, Inches(0.38), NAVY_D)
    _tb(slide, Inches(0.5), SH - Inches(0.38), SW - Inches(1), Inches(0.38),
        'SmartSoC CAD   ·   Varun Reddy Merugu   ·   varun@smartsocs.com',
        size=10, color=WHITE, anchor=MSO_ANCHOR.MIDDLE)


# ────────────────────────────────────────────────────────────────────────
# Slide 1 — Cover
# ────────────────────────────────────────────────────────────────────────
def slide_cover(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s, NAVY)
    # top accent band
    _add_rect(s, 0, 0, SW, Inches(0.12), TEAL)
    # bottom accent band
    _add_rect(s, 0, SH - Inches(0.12), SW, Inches(0.12), TEAL)

    _tb(s, Inches(0.9), Inches(1.1), SW - Inches(1.8), Inches(0.4),
        'MICRON   ·   PD + ANALOG DESIGN SERVICES   ·   RFP RESPONSE',
        size=14, bold=True, color=TEAL)

    _tb(s, Inches(0.9), Inches(1.6), SW - Inches(1.8), Inches(1.4),
        'Resource & Timeline Plan',
        size=48, bold=True, color=WHITE)

    _tb(s, Inches(0.9), Inches(3.1), SW - Inches(1.8), Inches(0.5),
        'Dec 2026 → Jul 2027   ·   8-month engagement   ·   15 PD + Analog resources',
        size=18, color=RGBColor(0xC7, 0xD2, 0xE0))

    # Submitter card
    card_l = Inches(0.9); card_t = Inches(4.6)
    card_w = SW - Inches(1.8); card_h = Inches(1.7)
    _add_rect(s, card_l, card_t, card_w, card_h, NAVY_D)
    _add_rect(s, card_l, card_t, Inches(0.08), card_h, TEAL)
    _tb(s, card_l + Inches(0.3), card_t + Inches(0.2),
        card_w - Inches(0.4), Inches(0.4),
        'SUBMITTED BY', size=10, bold=True, color=TEAL)
    _tb(s, card_l + Inches(0.3), card_t + Inches(0.5),
        card_w - Inches(0.4), Inches(0.5),
        'SmartSoC CAD', size=22, bold=True, color=WHITE)
    _tb(s, card_l + Inches(0.3), card_t + Inches(0.95),
        card_w - Inches(0.4), Inches(0.4),
        'Primary contact · Varun Reddy Merugu',
        size=13, color=RGBColor(0xE5, 0xE7, 0xEB))
    _tb(s, card_l + Inches(0.3), card_t + Inches(1.25),
        card_w - Inches(0.4), Inches(0.4),
        'varun@smartsocs.com',
        size=13, bold=True, color=TEAL)


# ────────────────────────────────────────────────────────────────────────
# Slide 2 — Scope & engagement window
# ────────────────────────────────────────────────────────────────────────
def slide_scope(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _header(s, 'ENGAGEMENT SCOPE', 'Scope coverage · 8-month delivery window')

    # Two columns: Coverage | Window
    col_t  = Inches(1.3)
    col_w  = Inches(6.1)
    col_h  = Inches(5.2)
    gap    = Inches(0.3)
    l1     = Inches(0.5)
    l2     = l1 + col_w + gap

    # Coverage column
    _add_rect(s, l1, col_t, col_w, Inches(0.6), NAVY)
    _tb(s, l1 + Inches(0.3), col_t, col_w, Inches(0.6),
        'COVERAGE', size=14, bold=True, color=WHITE, anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, l1, col_t + Inches(0.6), col_w, col_h - Inches(0.6), PANEL,
              line=LINE)
    cov_rows = [
        ('Physical Design',
         'Synthesis · FCFP · Block implementation · FCT/STA · '
         'EMIR + PDN · Signoff (LEC/CLP) · DRC/LVS · Program mgmt'),
        ('Analog',
         'Analog design · Analog layout (ramped headcount through peak)'),
    ]
    y = col_t + Inches(0.85)
    for name, detail in cov_rows:
        _tb(s, l1 + Inches(0.3), y, col_w - Inches(0.6), Inches(0.35),
            name, size=14, bold=True, color=NAVY)
        _tb(s, l1 + Inches(0.3), y + Inches(0.3), col_w - Inches(0.6),
            Inches(1.4), detail, size=11, color=BODY)
        y += Inches(1.85)

    # Window column
    _add_rect(s, l2, col_t, col_w, Inches(0.6), NAVY)
    _tb(s, l2 + Inches(0.3), col_t, col_w, Inches(0.6),
        'WINDOW', size=14, bold=True, color=WHITE, anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, l2, col_t + Inches(0.6), col_w, col_h - Inches(0.6), PANEL,
              line=LINE)
    win_rows = [
        ('Start',                'December 2026'),
        ('End',                  'July 2027'),
        ('Duration',             '8 calendar months'),
        ('Peak headcount',       '15 engineers (PD + Analog)'),
        ('Program-months (PD)',  '64 person-months'),
        ('Program-months (Analog)', '108 person-months'),
    ]
    y = col_t + Inches(0.85)
    for k, v in win_rows:
        _tb(s, l2 + Inches(0.3), y, Inches(2.6), Inches(0.3),
            k, size=11, bold=True, color=MUTED)
        _tb(s, l2 + Inches(3.0), y, col_w - Inches(3.3), Inches(0.3),
            v, size=12, bold=True, color=NAVY)
        y += Inches(0.55)

    _footer(s)


# ────────────────────────────────────────────────────────────────────────
# Slide 3 — PD resource plan
# ────────────────────────────────────────────────────────────────────────
def slide_pd_plan(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _header(s, 'RESOURCE PLAN · PHYSICAL DESIGN',
            'PD engineering ramp · Dec 2026 → Jul 2027')

    # Table geometry
    tbl_t = Inches(1.3)
    tbl_l = Inches(0.5)
    name_w = Inches(4.3)
    cell_w = Inches((13.333 - 0.5 - 4.3 - 0.9) / 8)  # per-month
    totals_w = Inches(0.9)
    row_h = Inches(0.42)

    # Header row
    _add_rect(s, tbl_l, tbl_t, name_w, row_h, NAVY)
    _tb(s, tbl_l + Inches(0.15), tbl_t, name_w, row_h,
        'Discipline', size=11, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, m in enumerate(MONTHS):
        x = tbl_l + name_w + cell_w * i
        _add_rect(s, x, tbl_t, cell_w, row_h, NAVY)
        _tb(s, x, tbl_t, cell_w, row_h, m,
            size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
    x = tbl_l + name_w + cell_w * 8
    _add_rect(s, x, tbl_t, totals_w, row_h, TEAL_D)
    _tb(s, x, tbl_t, totals_w, row_h, 'PM-mo',
        size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)

    # Data rows
    y = tbl_t + row_h
    totals_col = [0]*8
    grand = 0
    for row_name, counts in PD_ROWS:
        _add_rect(s, tbl_l, y, name_w, row_h, BAND_PD, line=LINE)
        _tb(s, tbl_l + Inches(0.15), y, name_w, row_h,
            row_name, size=10, bold=True, color=INK,
            anchor=MSO_ANCHOR.MIDDLE)
        row_sum = 0
        for i, cnt in enumerate(counts):
            x = tbl_l + name_w + cell_w * i
            _add_rect(s, x, y, cell_w, row_h, WHITE, line=LINE)
            _tb(s, x, y, cell_w, row_h, str(cnt),
                size=11, bold=True, color=NAVY, align=PP_ALIGN.CENTER,
                anchor=MSO_ANCHOR.MIDDLE)
            row_sum += cnt
            totals_col[i] += cnt
        x = tbl_l + name_w + cell_w * 8
        _add_rect(s, x, y, totals_w, row_h, PANEL, line=LINE)
        _tb(s, x, y, totals_w, row_h, str(row_sum),
            size=11, bold=True, color=TEAL_D, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        grand += row_sum
        y += row_h

    # Totals row
    _add_rect(s, tbl_l, y, name_w, row_h, NAVY_D)
    _tb(s, tbl_l + Inches(0.15), y, name_w, row_h,
        'Monthly headcount · PD', size=11, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, t in enumerate(totals_col):
        x = tbl_l + name_w + cell_w * i
        _add_rect(s, x, y, cell_w, row_h, NAVY_D)
        _tb(s, x, y, cell_w, row_h, str(t),
            size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
    x = tbl_l + name_w + cell_w * 8
    _add_rect(s, x, y, totals_w, row_h, TEAL)
    _tb(s, x, y, totals_w, row_h, str(grand),
        size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)

    # Caller key
    _tb(s, tbl_l, y + row_h + Inches(0.1), SW - Inches(1), Inches(0.3),
        'Numbers are concurrent-engineer headcount per month. '
        'PM-mo = sum across the 8-month window (person-months).',
        size=10, italic=True, color=MUTED)

    _footer(s)


# ────────────────────────────────────────────────────────────────────────
# Slide 4 — Analog resource plan
# ────────────────────────────────────────────────────────────────────────
def slide_analog_plan(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _header(s, 'RESOURCE PLAN · ANALOG',
            'Analog engineering ramp · Dec 2026 → Jul 2027')

    tbl_t = Inches(1.3)
    tbl_l = Inches(0.5)
    name_w = Inches(4.3)
    cell_w = Inches((13.333 - 0.5 - 4.3 - 0.9) / 8)
    totals_w = Inches(0.9)
    row_h = Inches(0.5)

    # Header row
    _add_rect(s, tbl_l, tbl_t, name_w, row_h, NAVY)
    _tb(s, tbl_l + Inches(0.15), tbl_t, name_w, row_h,
        'Discipline', size=11, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, m in enumerate(MONTHS):
        x = tbl_l + name_w + cell_w * i
        _add_rect(s, x, tbl_t, cell_w, row_h, NAVY)
        _tb(s, x, tbl_t, cell_w, row_h, m,
            size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
    x = tbl_l + name_w + cell_w * 8
    _add_rect(s, x, tbl_t, totals_w, row_h, TEAL_D)
    _tb(s, x, tbl_t, totals_w, row_h, 'PM-mo',
        size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)

    # Data rows
    y = tbl_t + row_h
    totals_col = [0]*8
    grand = 0
    for row_name, counts in ANALOG_ROWS:
        _add_rect(s, tbl_l, y, name_w, row_h, BAND_AN, line=LINE)
        _tb(s, tbl_l + Inches(0.15), y, name_w, row_h,
            row_name, size=11, bold=True, color=INK,
            anchor=MSO_ANCHOR.MIDDLE)
        row_sum = 0
        for i, cnt in enumerate(counts):
            x = tbl_l + name_w + cell_w * i
            _add_rect(s, x, y, cell_w, row_h, WHITE, line=LINE)
            _tb(s, x, y, cell_w, row_h, str(cnt),
                size=12, bold=True, color=NAVY, align=PP_ALIGN.CENTER,
                anchor=MSO_ANCHOR.MIDDLE)
            row_sum += cnt
            totals_col[i] += cnt
        x = tbl_l + name_w + cell_w * 8
        _add_rect(s, x, y, totals_w, row_h, PANEL, line=LINE)
        _tb(s, x, y, totals_w, row_h, str(row_sum),
            size=11, bold=True, color=TEAL_D, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        grand += row_sum
        y += row_h

    # Totals row
    _add_rect(s, tbl_l, y, name_w, row_h, NAVY_D)
    _tb(s, tbl_l + Inches(0.15), y, name_w, row_h,
        'Monthly headcount · Analog', size=11, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, t in enumerate(totals_col):
        x = tbl_l + name_w + cell_w * i
        _add_rect(s, x, y, cell_w, row_h, NAVY_D)
        _tb(s, x, y, cell_w, row_h, str(t),
            size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
    x = tbl_l + name_w + cell_w * 8
    _add_rect(s, x, y, totals_w, row_h, TEAL)
    _tb(s, x, y, totals_w, row_h, str(grand),
        size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)

    # Ramp note
    note_y = y + row_h + Inches(0.3)
    _add_rect(s, tbl_l, note_y, SW - Inches(1), Inches(1.6), PANEL, line=LINE)
    _add_rect(s, tbl_l, note_y, Inches(0.08), Inches(1.6), TEAL)
    _tb(s, tbl_l + Inches(0.3), note_y + Inches(0.1), Inches(10),
        Inches(0.35), 'LAYOUT RAMP',
        size=10, bold=True, color=TEAL_D)
    _tb(s, tbl_l + Inches(0.3), note_y + Inches(0.4), SW - Inches(1.6),
        Inches(1.1),
        'Analog layout headcount ramps from 6 → 8 (Jan) and peaks at 10 '
        'during Apr–Jun to clear the mid-program layout surge, then '
        'tapers to 8 for the Jul closeout. Analog design holds steady '
        'at 5 engineers for the full window to maintain spec continuity.',
        size=11, color=BODY)

    _footer(s)


# ────────────────────────────────────────────────────────────────────────
# Slide 5 — Program total + delivery timeline summary
# ────────────────────────────────────────────────────────────────────────
def slide_summary(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    _bg(s)
    _header(s, 'PROGRAM TOTAL',
            'Combined ramp · Dec 2026 → Jul 2027')

    # Monthly totals (PD + Analog)
    pd_tot    = [sum(r[1][i] for r in PD_ROWS) for i in range(8)]
    an_tot    = [sum(r[1][i] for r in ANALOG_ROWS) for i in range(8)]
    all_tot   = [pd_tot[i] + an_tot[i] for i in range(8)]

    # Headcount bars panel
    panel_t = Inches(1.3)
    panel_l = Inches(0.5)
    panel_w = SW - Inches(1.0)
    panel_h = Inches(3.6)
    _add_rect(s, panel_l, panel_t, panel_w, panel_h, PANEL, line=LINE)
    _tb(s, panel_l + Inches(0.3), panel_t + Inches(0.1), panel_w,
        Inches(0.35),
        'MONTHLY HEADCOUNT · PD + ANALOG',
        size=11, bold=True, color=NAVY)

    # Chart area
    chart_l = panel_l + Inches(0.5)
    chart_t = panel_t + Inches(0.65)
    chart_w = panel_w - Inches(1.0)
    chart_h = panel_h - Inches(1.3)
    max_v   = max(all_tot) + 2
    bar_w   = chart_w / 8 * 0.55
    bar_gap = chart_w / 8

    # Baseline
    _add_rect(s, chart_l, chart_t + chart_h, chart_w, Inches(0.02), LINE)

    for i, (pd, an) in enumerate(zip(pd_tot, an_tot)):
        total = pd + an
        bx = chart_l + bar_gap * i + (bar_gap - bar_w) / 2
        bh = chart_h * (total / max_v)
        by = chart_t + chart_h - bh
        # Analog bottom (bigger segment)
        an_h = chart_h * (an / max_v)
        pd_h = chart_h * (pd / max_v)
        _add_rect(s, bx, by + pd_h, bar_w, an_h, TEAL)
        _add_rect(s, bx, by,         bar_w, pd_h, ACCENT)
        # Total label on top
        _tb(s, bx - Inches(0.2), by - Inches(0.3), bar_w + Inches(0.4),
            Inches(0.25), str(total),
            size=11, bold=True, color=NAVY, align=PP_ALIGN.CENTER)
        # Month label at base
        _tb(s, bx - Inches(0.2), chart_t + chart_h + Inches(0.05),
            bar_w + Inches(0.4), Inches(0.3), MONTHS[i],
            size=10, color=MUTED, align=PP_ALIGN.CENTER)

    # Legend
    leg_y = panel_t + panel_h - Inches(0.4)
    _add_rect(s, panel_l + Inches(0.5), leg_y, Inches(0.2), Inches(0.2), ACCENT)
    _tb(s, panel_l + Inches(0.8), leg_y - Inches(0.02), Inches(1.5),
        Inches(0.3), 'PD',
        size=10, bold=True, color=INK, anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, panel_l + Inches(1.6), leg_y, Inches(0.2), Inches(0.2), TEAL)
    _tb(s, panel_l + Inches(1.9), leg_y - Inches(0.02), Inches(2.0),
        Inches(0.3), 'Analog',
        size=10, bold=True, color=INK, anchor=MSO_ANCHOR.MIDDLE)

    # KPI row underneath
    kpi_t = panel_t + panel_h + Inches(0.25)
    kpi_h = Inches(1.3)
    kpi_w = (panel_w - Inches(0.6)) / 4
    cards = [
        ('Peak headcount', '18', 'engineers · Apr-27'),
        ('PD total',       '64', 'person-months'),
        ('Analog total',   '108', 'person-months'),
        ('Program total',  '172', 'person-months'),
    ]
    for i, (lbl, big, sub) in enumerate(cards):
        kx = panel_l + Inches(0.2) + (kpi_w + Inches(0.2)) * i
        _add_rect(s, kx, kpi_t, kpi_w, kpi_h, NAVY)
        _add_rect(s, kx, kpi_t, Inches(0.08), kpi_h, TEAL)
        _tb(s, kx + Inches(0.3), kpi_t + Inches(0.15), kpi_w - Inches(0.4),
            Inches(0.3), lbl.upper(),
            size=9, bold=True, color=TEAL)
        _tb(s, kx + Inches(0.3), kpi_t + Inches(0.4), kpi_w - Inches(0.4),
            Inches(0.6), big,
            size=32, bold=True, color=WHITE)
        _tb(s, kx + Inches(0.3), kpi_t + Inches(0.95), kpi_w - Inches(0.4),
            Inches(0.3), sub,
            size=10, color=RGBColor(0xC7, 0xD2, 0xE0))

    _footer(s)


# ────────────────────────────────────────────────────────────────────────
def main():
    import os
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       'SmartSoC_Micron_RFP_Deck.pptx')
    prs = Presentation()
    prs.slide_width  = SW
    prs.slide_height = SH

    slide_cover(prs)
    slide_scope(prs)
    slide_pd_plan(prs)
    slide_analog_plan(prs)
    slide_summary(prs)

    prs.save(out)
    print(f'wrote: {out}')
    print(f'slides: {len(prs.slides)}')


if __name__ == '__main__':
    main()
