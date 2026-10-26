#!/usr/bin/env python3
"""
Build SmartSoC_Micron_RFP_Deck.pptx on top of the SmartSoC master
template so the deck ships with the official brand chrome
(header group, divider line, confidentiality footer, slide number).

Template: ~/Downloads/SmartSoC_Presentation_Template V3.0  (Jan 26).pptx
  slide dims: 20.0" × 11.25"  (16:9 widescreen)
  layouts used:
    [7]  'Title Slide'  — cover
    [4]  'Blank SS'     — content pages (keeps brand chrome, our shapes on top)

Content — 4-slide response-document companion:
  1  Cover
  2  Scope + 8-month engagement window
  3  Program timeline — milestones + workstream Gantt bars
  4  Resource plan — PD + Analog combined into one table

(PD team upskilling plan is now a SEPARATE deck —
 build_pd_skilling_deck.py / SmartSoC_PD_Upskilling_Plan.pptx.)
"""

import os
from copy import deepcopy
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from lxml import etree

TEMPLATE = os.path.expanduser(
    '~/Downloads/SmartSoC_Presentation_Template V3.0  (Jan 26).pptx')
OUT      = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'SmartSoC_Micron_RFP_Deck.pptx')

# SmartSoC brand palette (match template header gradient blues/greens)
NAVY       = RGBColor(0x0B, 0x1F, 0x3A)
NAVY_D     = RGBColor(0x05, 0x12, 0x24)
TEAL       = RGBColor(0x0E, 0xA5, 0xE9)
TEAL_D     = RGBColor(0x02, 0x74, 0x90)
ACCENT     = RGBColor(0x4F, 0x46, 0xE5)
GREEN      = RGBColor(0x00, 0xA6, 0x4F)
INK        = RGBColor(0x0F, 0x14, 0x1B)
BODY       = RGBColor(0x33, 0x39, 0x46)
MUTED      = RGBColor(0x6B, 0x72, 0x80)
WHITE      = RGBColor(0xFF, 0xFF, 0xFF)
PANEL      = RGBColor(0xF4, 0xF6, 0xFB)
LINE       = RGBColor(0xD4, 0xDA, 0xE5)
BAND_PD    = RGBColor(0xE0, 0xF2, 0xFE)
BAND_AN    = RGBColor(0xFF, 0xF3, 0xDC)

FONT = 'Calibri'

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


# ── Helpers ────────────────────────────────────────────────────────────
def _strip_existing_slides(prs):
    """Keep layouts + masters, remove every pre-existing content slide
    so our 5 new slides are the only content when the deck opens."""
    sldIdLst = prs.slides._sldIdLst
    # Remove all slide relationships from the presentation part
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


# ── Slide builders ────────────────────────────────────────────────────
def slide_cover(prs):
    """Use Title Slide layout. SW=20in, SH=11.25in."""
    s = prs.slides.add_slide(prs.slide_layouts[7])
    SW = prs.slide_width; SH = prs.slide_height

    # Fill the two placeholders provided by the layout
    for ph in s.placeholders:
        name = ph.name.lower()
        tf = ph.text_frame
        tf.clear()
        p = tf.paragraphs[0]
        p.alignment = PP_ALIGN.LEFT
        if 'title' in name and 'subtitle' not in name:
            r = p.add_run()
            r.text = 'Micron · PD + Analog Design Services'
            r.font.size = Pt(44); r.font.bold = True
            r.font.color.rgb = NAVY
            # second line
            p2 = tf.add_paragraph()
            r2 = p2.add_run()
            r2.text = 'RFP Response — Resource & Timeline Plan'
            r2.font.size = Pt(26); r2.font.bold = True
            r2.font.color.rgb = TEAL_D
        elif 'subtitle' in name:
            r = p.add_run()
            r.text = ('Dec 2026 → Jul 2027   ·   8-month engagement   ·   '
                      '15 engineers (PD + Analog)')
            r.font.size = Pt(18); r.font.color.rgb = BODY
            # submitter line
            p2 = tf.add_paragraph()
            r2 = p2.add_run()
            r2.text = 'Submitted by SmartSoC CAD · Varun Reddy Merugu · varun@smartsocs.com'
            r2.font.size = Pt(14); r2.font.bold = True
            r2.font.color.rgb = NAVY


def _content_header(s, kicker, title):
    """Top band on content slides. Positioned below the template header
    chrome (which lives roughly in the top 1.4" strip of the master).
    Our content strip sits at ~1.6" so we don't overlap it."""
    SW = s.part.slide_width if hasattr(s.part, 'slide_width') else Inches(20)
    _tb(s, Inches(0.7), Inches(1.65), Inches(18.6), Inches(0.35),
        kicker.upper(), size=12, bold=True, color=TEAL_D)
    _tb(s, Inches(0.7), Inches(2.0), Inches(18.6), Inches(0.6),
        title, size=28, bold=True, color=NAVY)
    # underline accent
    _add_rect(s, Inches(0.7), Inches(2.65), Inches(1.0), Inches(0.06), TEAL)


def slide_scope(prs):
    s = prs.slides.add_slide(prs.slide_layouts[4])  # Blank SS
    _content_header(s, 'ENGAGEMENT SCOPE',
                    'Scope coverage · 8-month delivery window')

    col_t  = Inches(3.0)
    col_w  = Inches(8.9)
    col_h  = Inches(7.0)
    gap    = Inches(0.4)
    l1     = Inches(0.7)
    l2     = l1 + col_w + gap

    # Coverage column
    _add_rect(s, l1, col_t, col_w, Inches(0.65), NAVY)
    _tb(s, l1 + Inches(0.3), col_t, col_w, Inches(0.65),
        'COVERAGE', size=15, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, l1, col_t + Inches(0.65), col_w, col_h - Inches(0.65),
              PANEL, line=LINE)
    cov_rows = [
        ('Physical Design',
         'Synthesis · FCFP · Block implementation · FCT / STA · '
         'EMIR + PDN · Signoff (LEC / CLP) · Physical Verification '
         '(DRC / LVS) · Program management'),
        ('Analog',
         'Analog design · Analog layout (ramped headcount through peak)'),
    ]
    y = col_t + Inches(0.95)
    for name, detail in cov_rows:
        _tb(s, l1 + Inches(0.4), y, col_w - Inches(0.8), Inches(0.4),
            name, size=18, bold=True, color=NAVY)
        _tb(s, l1 + Inches(0.4), y + Inches(0.45), col_w - Inches(0.8),
            Inches(2.3), detail, size=14, color=BODY)
        y += Inches(2.6)

    # Window column
    _add_rect(s, l2, col_t, col_w, Inches(0.65), NAVY)
    _tb(s, l2 + Inches(0.3), col_t, col_w, Inches(0.65),
        'WINDOW', size=15, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, l2, col_t + Inches(0.65), col_w, col_h - Inches(0.65),
              PANEL, line=LINE)
    win_rows = [
        ('Start',                'December 2026'),
        ('End',                  'July 2027'),
        ('Duration',             '8 calendar months'),
        ('Peak headcount',       '18 engineers (PD + Analog)'),
        ('Program-months · PD',  '64 person-months'),
        ('Program-months · Analog', '108 person-months'),
    ]
    y = col_t + Inches(1.1)
    for k, v in win_rows:
        _tb(s, l2 + Inches(0.4), y, Inches(3.8), Inches(0.5),
            k, size=14, bold=True, color=MUTED, anchor=MSO_ANCHOR.MIDDLE)
        _tb(s, l2 + Inches(4.2), y, col_w - Inches(4.6), Inches(0.5),
            v, size=16, bold=True, color=NAVY, anchor=MSO_ANCHOR.MIDDLE)
        y += Inches(0.85)


def slide_timeline(prs):
    """Workstream Gantt + top-of-slide milestone ribbon.

    Each PD workstream becomes a horizontal bar coloured by discipline.
    Analog takes two bars (design + layout). Milestone markers sit on a
    ribbon above the Gantt bars so the reader sees the critical dates
    at a glance.
    """
    s = prs.slides.add_slide(prs.slide_layouts[4])
    _content_header(s, 'PROGRAM TIMELINE',
                    'Milestones + workstream schedule · Dec 2026 → Jul 2027')

    # Gantt geometry
    tbl_t = Inches(3.6)
    tbl_l = Inches(0.7)
    name_w = Inches(5.5)
    track_w = Inches((20.0 - 0.7 - 5.5 - 0.7) / 8)
    row_h = Inches(0.5)

    # Month-column header
    _add_rect(s, tbl_l, tbl_t, name_w, row_h, NAVY)
    _tb(s, tbl_l + Inches(0.2), tbl_t, name_w, row_h,
        'Workstream', size=13, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, m in enumerate(MONTHS):
        x = tbl_l + name_w + track_w * i
        _add_rect(s, x, tbl_t, track_w, row_h, NAVY)
        _tb(s, x, tbl_t, track_w, row_h, m,
            size=12, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)

    # Workstream rows — (label, start_month_idx, end_month_idx, color)
    # Months indexed 0=Dec-26 .. 7=Jul-27
    bars = [
        ('Program setup + team ramp',          0, 1, GREEN),
        ('Synthesis',                          0, 6, ACCENT),
        ('Full-Chip Floorplan (FCFP)',         1, 3, ACCENT),
        ('Block-Level Implementation',         1, 6, ACCENT),
        ('FCT / STA',                          2, 7, ACCENT),
        ('EMIR / PDN / Signoff (LEC/CLP)',     3, 7, ACCENT),
        ('Physical Verification (DRC/LVS)',    4, 7, ACCENT),
        ('Analog Design',                      0, 7, TEAL),
        ('Analog Layout',                      0, 7, TEAL),
        ('Tape-out hand-off + closeout',       7, 7, GREEN),
    ]
    y = tbl_t + row_h
    bar_h = row_h - Inches(0.14)
    bar_pad_y = Inches(0.07)
    for label, start, end, color in bars:
        # Row label
        _add_rect(s, tbl_l, y, name_w, row_h, PANEL, line=LINE)
        _tb(s, tbl_l + Inches(0.2), y, name_w, row_h,
            label, size=11, bold=True, color=INK, anchor=MSO_ANCHOR.MIDDLE)
        # Month-column gridlines
        for i in range(8):
            x = tbl_l + name_w + track_w * i
            _add_rect(s, x, y, track_w, row_h, WHITE, line=LINE)
        # Gantt bar
        bx = tbl_l + name_w + track_w * start + Inches(0.08)
        bw = track_w * (end - start + 1) - Inches(0.16)
        _add_rect(s, bx, y + bar_pad_y, bw, bar_h, color)
        # Endpoint-dot visual
        _add_rect(s, bx - Inches(0.03), y + bar_pad_y, Inches(0.06), bar_h,
                  NAVY_D)
        _add_rect(s, bx + bw - Inches(0.03), y + bar_pad_y,
                  Inches(0.06), bar_h, NAVY_D)
        y += row_h

    # Milestone ribbon above the Gantt (same month-grid alignment)
    ms_t = tbl_t - Inches(0.55)
    _tb(s, tbl_l, ms_t - Inches(0.1), name_w, Inches(0.3),
        'Key milestones', size=11, bold=True, color=TEAL_D,
        anchor=MSO_ANCHOR.MIDDLE)
    milestones = [
        (0, 'Kickoff'),
        (1, 'Team at full strength'),
        (3, 'FP freeze'),
        (4, 'Layout peak'),
        (6, 'Signoff iteration'),
        (7, 'Tape-out'),
    ]
    for mi, lbl in milestones:
        x = tbl_l + name_w + track_w * mi + track_w / 2
        # Diamond marker
        dm = s.shapes.add_shape(MSO_SHAPE.DIAMOND,
                                x - Inches(0.11), ms_t,
                                Inches(0.22), Inches(0.22))
        dm.fill.solid(); dm.fill.fore_color.rgb = TEAL_D
        dm.line.color.rgb = WHITE; dm.line.width = Pt(1.0)
        dm.shadow.inherit = False
        _tb(s, x - Inches(1.2), ms_t + Inches(0.26),
            Inches(2.4), Inches(0.3),
            lbl, size=10, bold=True, color=NAVY_D,
            align=PP_ALIGN.CENTER)

    # Legend
    leg_y = y + Inches(0.25)
    legend = [(GREEN, 'Program ops'), (ACCENT, 'Physical design'),
              (TEAL, 'Analog')]
    lx = tbl_l + Inches(0.1)
    for color, text in legend:
        _add_rect(s, lx, leg_y, Inches(0.28), Inches(0.28), color)
        _tb(s, lx + Inches(0.4), leg_y - Inches(0.02),
            Inches(2.0), Inches(0.35), text,
            size=12, bold=True, color=INK, anchor=MSO_ANCHOR.MIDDLE)
        lx += Inches(2.8)


def slide_resources_combined(prs):
    """Single slide — PD + Analog resource plan merged into one table
    with a group-header separator between the two disciplines."""
    s = prs.slides.add_slide(prs.slide_layouts[4])
    _content_header(s, 'RESOURCE PLAN',
                    'PD + Analog engineering ramp · Dec 2026 → Jul 2027')

    tbl_t = Inches(2.95)
    tbl_l = Inches(0.7)
    name_w = Inches(6.3)
    cell_w = Inches((20.0 - 0.7 - 6.3 - 1.3 - 0.7) / 8)
    totals_w = Inches(1.3)
    row_h = Inches(0.45)
    group_h = Inches(0.4)

    # Header row
    _add_rect(s, tbl_l, tbl_t, name_w, row_h, NAVY)
    _tb(s, tbl_l + Inches(0.2), tbl_t, name_w, row_h,
        'Discipline', size=13, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, m in enumerate(MONTHS):
        x = tbl_l + name_w + cell_w * i
        _add_rect(s, x, tbl_t, cell_w, row_h, NAVY)
        _tb(s, x, tbl_t, cell_w, row_h, m,
            size=12, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
    x = tbl_l + name_w + cell_w * 8
    _add_rect(s, x, tbl_t, totals_w, row_h, TEAL_D)
    _tb(s, x, tbl_t, totals_w, row_h, 'PM-mo',
        size=12, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)

    y = tbl_t + row_h
    totals_col = [0]*8
    pd_subtotal = [0]*8; pd_grand = 0
    an_subtotal = [0]*8; an_grand = 0

    tbl_full_w = name_w + cell_w * 8 + totals_w

    # Group banner — PHYSICAL DESIGN
    _add_rect(s, tbl_l, y, tbl_full_w, group_h, TEAL_D)
    _tb(s, tbl_l + Inches(0.2), y, tbl_full_w, group_h,
        'PHYSICAL DESIGN', size=12, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    y += group_h

    for row_name, counts in PD_ROWS:
        _add_rect(s, tbl_l, y, name_w, row_h, BAND_PD, line=LINE)
        _tb(s, tbl_l + Inches(0.2), y, name_w, row_h,
            row_name, size=11, bold=True, color=INK,
            anchor=MSO_ANCHOR.MIDDLE)
        row_sum = 0
        for i, cnt in enumerate(counts):
            x = tbl_l + name_w + cell_w * i
            _add_rect(s, x, y, cell_w, row_h, WHITE, line=LINE)
            _tb(s, x, y, cell_w, row_h, str(cnt),
                size=13, bold=True, color=NAVY, align=PP_ALIGN.CENTER,
                anchor=MSO_ANCHOR.MIDDLE)
            row_sum += cnt
            totals_col[i] += cnt
            pd_subtotal[i] += cnt
        x = tbl_l + name_w + cell_w * 8
        _add_rect(s, x, y, totals_w, row_h, PANEL, line=LINE)
        _tb(s, x, y, totals_w, row_h, str(row_sum),
            size=12, bold=True, color=TEAL_D, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        pd_grand += row_sum
        y += row_h

    # PD subtotal strip
    _add_rect(s, tbl_l, y, name_w, row_h, NAVY)
    _tb(s, tbl_l + Inches(0.2), y, name_w, row_h,
        'PD subtotal', size=12, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, t in enumerate(pd_subtotal):
        x = tbl_l + name_w + cell_w * i
        _add_rect(s, x, y, cell_w, row_h, NAVY)
        _tb(s, x, y, cell_w, row_h, str(t),
            size=12, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
    x = tbl_l + name_w + cell_w * 8
    _add_rect(s, x, y, totals_w, row_h, TEAL)
    _tb(s, x, y, totals_w, row_h, str(pd_grand),
        size=12, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)
    y += row_h

    # Group banner — ANALOG
    _add_rect(s, tbl_l, y, tbl_full_w, group_h, TEAL_D)
    _tb(s, tbl_l + Inches(0.2), y, tbl_full_w, group_h,
        'ANALOG', size=12, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    y += group_h

    for row_name, counts in ANALOG_ROWS:
        _add_rect(s, tbl_l, y, name_w, row_h, BAND_AN, line=LINE)
        _tb(s, tbl_l + Inches(0.2), y, name_w, row_h,
            row_name, size=11, bold=True, color=INK,
            anchor=MSO_ANCHOR.MIDDLE)
        row_sum = 0
        for i, cnt in enumerate(counts):
            x = tbl_l + name_w + cell_w * i
            _add_rect(s, x, y, cell_w, row_h, WHITE, line=LINE)
            _tb(s, x, y, cell_w, row_h, str(cnt),
                size=13, bold=True, color=NAVY, align=PP_ALIGN.CENTER,
                anchor=MSO_ANCHOR.MIDDLE)
            row_sum += cnt
            totals_col[i] += cnt
            an_subtotal[i] += cnt
        x = tbl_l + name_w + cell_w * 8
        _add_rect(s, x, y, totals_w, row_h, PANEL, line=LINE)
        _tb(s, x, y, totals_w, row_h, str(row_sum),
            size=12, bold=True, color=TEAL_D, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        an_grand += row_sum
        y += row_h

    # Analog subtotal strip
    _add_rect(s, tbl_l, y, name_w, row_h, NAVY)
    _tb(s, tbl_l + Inches(0.2), y, name_w, row_h,
        'Analog subtotal', size=12, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, t in enumerate(an_subtotal):
        x = tbl_l + name_w + cell_w * i
        _add_rect(s, x, y, cell_w, row_h, NAVY)
        _tb(s, x, y, cell_w, row_h, str(t),
            size=12, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
    x = tbl_l + name_w + cell_w * 8
    _add_rect(s, x, y, totals_w, row_h, TEAL)
    _tb(s, x, y, totals_w, row_h, str(an_grand),
        size=12, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)
    y += row_h

    # Program total strip
    _add_rect(s, tbl_l, y, name_w, row_h + Inches(0.1), NAVY_D)
    _tb(s, tbl_l + Inches(0.2), y, name_w, row_h + Inches(0.1),
        'Program total', size=13, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    for i, t in enumerate(totals_col):
        x = tbl_l + name_w + cell_w * i
        _add_rect(s, x, y, cell_w, row_h + Inches(0.1), NAVY_D)
        _tb(s, x, y, cell_w, row_h + Inches(0.1), str(t),
            size=13, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
    x = tbl_l + name_w + cell_w * 8
    _add_rect(s, x, y, totals_w, row_h + Inches(0.1), ACCENT)
    _tb(s, x, y, totals_w, row_h + Inches(0.1), str(pd_grand + an_grand),
        size=14, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)
    y += row_h + Inches(0.1)

    # Caption
    _tb(s, Inches(0.7), y + Inches(0.1), Inches(18), Inches(0.35),
        'Numbers are concurrent-engineer headcount per month. '
        'PM-mo = sum across the 8-month window (person-months). '
        'Analog layout ramps 6 → 10 through peak (Apr–Jun) then tapers to 8.',
        size=12, italic=True, color=MUTED)


# ── Slide 5: PD readiness — skillset evaluation + Q4 upskilling Gantt ─
def slide_upskilling(prs):
    """Compact skill matrix on the left + Q4-2026 (12-week) Gantt on the
    right. Each PD domain row has a current→target skill chip pair and
    a bar across the Oct-Nov-Dec weeks showing the planned activity
    phases (Foundation → Hands-on → Project / certification)."""
    s = prs.slides.add_slide(prs.slide_layouts[4])
    _content_header(s, 'PD READINESS',
                    'Skillset evaluation + Q4-2026 upskilling plan')

    # ── Domain roster + skill levels ────────────────────────────────────
    # (name, current, target, [phases])
    # Each phase: (start_week, end_week, label, color)
    # Weeks: 1..12 across Oct W1..Dec W4.
    FND  = ACCENT        # Foundation / refresher
    HOL  = TEAL          # Hands-on labs / vendor-led
    PROJ = GREEN         # Project exercises + Micron orientation
    rows = [
        ('Synthesis (Genus / DC)',           'Int', 'Exp',
            [(1, 3, 'Foundation', FND), (4, 7, 'Hands-on', HOL),
             (8, 12, 'Project', PROJ)]),
        ('Full-Chip Floorplan (FCFP)',       'Int', 'Exp',
            [(1, 4, 'Foundation', FND), (5, 9, 'Hands-on', HOL),
             (10, 12, 'Project', PROJ)]),
        ('Floorplan + Powerplan (ICC2/INV)', 'Adv', 'Exp',
            [(1, 2, 'Refresher', FND), (3, 7, 'Hands-on', HOL),
             (8, 12, 'Project', PROJ)]),
        ('Place & Route (block impl)',       'Int', 'Exp',
            [(1, 3, 'Foundation', FND), (4, 8, 'Hands-on', HOL),
             (9, 12, 'Project', PROJ)]),
        ('Clock Tree Synthesis (CTS)',       'Int', 'Adv',
            [(2, 4, 'Foundation', FND), (5, 9, 'Hands-on', HOL)]),
        ('STA Signoff (PrimeTime / Tempus)', 'Adv', 'Exp',
            [(1, 2, 'Refresher', FND), (3, 8, 'Hands-on', HOL),
             (9, 12, 'Project', PROJ)]),
        ('EMIR / IR drop (RedHawk/Voltus)',  'Int', 'Adv',
            [(1, 4, 'Foundation', FND), (5, 10, 'Hands-on', HOL),
             (11, 12, 'Project', PROJ)]),
        ('LEC / CLP (Formality / Conformal)','Adv', 'Exp',
            [(5, 7, 'Refresher', FND), (8, 12, 'Hands-on', HOL)]),
        ('Physical Verification (Calibre)',  'Adv', 'Exp',
            [(3, 5, 'Refresher', FND), (6, 10, 'Hands-on', HOL),
             (11, 12, 'Project', PROJ)]),
    ]

    # ── Table geometry ──────────────────────────────────────────────────
    tbl_t   = Inches(3.0)
    tbl_l   = Inches(0.7)
    name_w  = Inches(4.6)
    cur_w   = Inches(0.75)
    tgt_w   = Inches(0.75)
    weeks_w = Inches(20.0 - 0.7 - 4.6 - 0.75 - 0.75 - 0.7)
    week_w  = weeks_w / 12
    row_h   = Inches(0.5)

    # ── Header row ──────────────────────────────────────────────────────
    _add_rect(s, tbl_l, tbl_t, name_w, row_h, NAVY)
    _tb(s, tbl_l + Inches(0.2), tbl_t, name_w, row_h,
        'Domain', size=13, bold=True, color=WHITE,
        anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, tbl_l + name_w, tbl_t, cur_w, row_h, NAVY)
    _tb(s, tbl_l + name_w, tbl_t, cur_w, row_h,
        'Cur', size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)
    _add_rect(s, tbl_l + name_w + cur_w, tbl_t, tgt_w, row_h, NAVY)
    _tb(s, tbl_l + name_w + cur_w, tbl_t, tgt_w, row_h,
        'Tgt', size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
        anchor=MSO_ANCHOR.MIDDLE)
    # Month-group header spans (ribbon above the week numbers)
    month_bar_t = tbl_t
    MONTH_LABELS = [('Oct 2026', 4), ('Nov 2026', 4), ('Dec 2026', 4)]
    week_start_x = tbl_l + name_w + cur_w + tgt_w
    gx = week_start_x
    for mlabel, span in MONTH_LABELS:
        mw = week_w * span
        _add_rect(s, gx, month_bar_t, mw, Inches(0.26), TEAL_D)
        _tb(s, gx, month_bar_t, mw, Inches(0.26), mlabel,
            size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        gx += mw
    # Week-number sub-header
    for i in range(12):
        x = week_start_x + week_w * i
        _add_rect(s, x, month_bar_t + Inches(0.26), week_w,
                  row_h - Inches(0.26), NAVY)
        _tb(s, x, month_bar_t + Inches(0.26), week_w, row_h - Inches(0.26),
            f'W{i+1}', size=9, bold=True, color=WHITE,
            align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)

    # ── Data rows ───────────────────────────────────────────────────────
    LEVEL_COLORS = {
        'Beg':  RGBColor(0x9C, 0xA3, 0xAF),  # gray
        'Int':  RGBColor(0xF5, 0x9E, 0x0B),  # amber
        'Adv':  RGBColor(0x0E, 0xA5, 0xE9),  # teal
        'Exp':  GREEN,
    }

    y = tbl_t + row_h
    for name, cur, tgt, phases in rows:
        # Name cell
        _add_rect(s, tbl_l, y, name_w, row_h, PANEL, line=LINE)
        _tb(s, tbl_l + Inches(0.2), y, name_w, row_h,
            name, size=11, bold=True, color=INK,
            anchor=MSO_ANCHOR.MIDDLE)
        # Current-level chip
        _add_rect(s, tbl_l + name_w, y, cur_w, row_h, WHITE, line=LINE)
        chip_c = LEVEL_COLORS.get(cur, MUTED)
        _add_rect(s, tbl_l + name_w + Inches(0.08),
                  y + Inches(0.1), cur_w - Inches(0.16),
                  row_h - Inches(0.2), chip_c)
        _tb(s, tbl_l + name_w, y, cur_w, row_h, cur,
            size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        # Target-level chip
        _add_rect(s, tbl_l + name_w + cur_w, y, tgt_w, row_h, WHITE,
                  line=LINE)
        chip_t = LEVEL_COLORS.get(tgt, MUTED)
        _add_rect(s, tbl_l + name_w + cur_w + Inches(0.08),
                  y + Inches(0.1), tgt_w - Inches(0.16),
                  row_h - Inches(0.2), chip_t)
        _tb(s, tbl_l + name_w + cur_w, y, tgt_w, row_h, tgt,
            size=11, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        # Week gridlines
        for i in range(12):
            x = week_start_x + week_w * i
            _add_rect(s, x, y, week_w, row_h, WHITE, line=LINE)
        # Gantt phase bars for this domain
        bar_h = row_h - Inches(0.14)
        bar_pad_y = Inches(0.07)
        for (ws, we, label, color) in phases:
            bx = week_start_x + week_w * (ws - 1) + Inches(0.03)
            bw = week_w * (we - ws + 1) - Inches(0.06)
            _add_rect(s, bx, y + bar_pad_y, bw, bar_h, color)
            # Label inside the bar if it's wide enough (>= 2 weeks)
            if (we - ws + 1) >= 2:
                _tb(s, bx, y + bar_pad_y, bw, bar_h, label,
                    size=9, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
                    anchor=MSO_ANCHOR.MIDDLE)
        y += row_h

    # ── Phase legend ────────────────────────────────────────────────────
    leg_y = y + Inches(0.2)
    legend = [
        (FND,  'Foundation / Refresher — vendor materials, concept review'),
        (HOL,  'Hands-on labs — vendor-led workshops on reference designs'),
        (PROJ, 'Project exercises — Micron-chip orientation + sign-off dry run'),
    ]
    lx = tbl_l
    for color, text in legend:
        _add_rect(s, lx, leg_y, Inches(0.28), Inches(0.28), color)
        _tb(s, lx + Inches(0.4), leg_y - Inches(0.02),
            Inches(6.1), Inches(0.35), text,
            size=11, bold=True, color=INK, anchor=MSO_ANCHOR.MIDDLE)
        lx += Inches(6.3)

    # ── Skill-level legend ──────────────────────────────────────────────
    leg2_y = leg_y + Inches(0.5)
    skill_legend = [
        ('Int', 'Intermediate — proficient on vendor flow'),
        ('Adv', 'Advanced — tape-out-grade owner for a block'),
        ('Exp', 'Expert — can mentor, drives methodology'),
    ]
    lx = tbl_l
    for level, text in skill_legend:
        chip = LEVEL_COLORS[level]
        _add_rect(s, lx, leg2_y, Inches(0.55), Inches(0.28), chip)
        _tb(s, lx, leg2_y - Inches(0.02), Inches(0.55), Inches(0.35),
            level, size=10, bold=True, color=WHITE, align=PP_ALIGN.CENTER,
            anchor=MSO_ANCHOR.MIDDLE)
        _tb(s, lx + Inches(0.65), leg2_y - Inches(0.02),
            Inches(5.5), Inches(0.35), text,
            size=11, color=BODY, anchor=MSO_ANCHOR.MIDDLE)
        lx += Inches(6.3)


# ── Main ──────────────────────────────────────────────────────────────
def main():
    if not os.path.isfile(TEMPLATE):
        raise SystemExit(f'template not found: {TEMPLATE}')

    prs = Presentation(TEMPLATE)
    print(f'template: {os.path.basename(TEMPLATE)}')
    print(f'  slide dims: {prs.slide_width/914400:.2f}" × {prs.slide_height/914400:.2f}"')
    print(f'  layouts: {len(prs.slide_layouts)}')
    print(f'  pre-existing slides: {len(prs.slides)}')

    _strip_existing_slides(prs)
    print(f'  after strip: {len(prs.slides)} slides')

    slide_cover(prs)
    slide_scope(prs)
    slide_timeline(prs)
    slide_resources_combined(prs)

    prs.save(OUT)
    print(f'wrote: {OUT}')
    print(f'  final slides: {len(prs.slides)}')


if __name__ == '__main__':
    main()
