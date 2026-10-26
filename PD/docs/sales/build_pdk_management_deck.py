#!/usr/bin/env python3
"""
Build CBflow_Library_Manager_Deck.pptx — 4 focused slides on the
library-manager tool only.

Slides:
  1  Title — what library-manager is + why it exists
  2  Library tag directory layout — self-contained <TAG>/ structure
  3  library-manager commands — generate / add / status / coverage / verify / scan
  4  Adding to an existing tag — `add` mechanics (preserve + merge rules)

Deliberately NOT covered here (framework-level, separate decks):
  · Config cascade and resolver — framework scope
  · tech_config.tcl structure — tech subsystem, not library-manager
  · MMMC manager — separate tool
  · Lifecycle / release / signoff — orchestration-level
  · Roadmap

Brand follows the methodology deck conventions:
  green primary #00D700, dark-green #007a00, blue secondary #0000FF.
  16:9 (13.33" x 7.5"), Montserrat / Courier New.
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

# ── Palette (shared with methodology deck) ──────────────────────────────
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
TOTAL = 4


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
        run = p.add_run()
        run.text = ln
        _apply_font(run, name=font, size=size, bold=bold, color=color)
    return tb


def add_rect(slide, left, top, width, height,
             fill=WHITE, line=LINE, line_width=0.5):
    shp = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    shp.fill.solid(); shp.fill.fore_color.rgb = fill
    shp.line.color.rgb = line
    shp.line.width = Pt(line_width)
    shp.shadow.inherit = False
    return shp


def add_slide_frame(slide, slide_no, title, subtitle=None):
    # Top bar
    bar = add_rect(slide, 0, 0, SW, Inches(0.9), fill=GREEN_DARK, line=GREEN_DARK)
    add_text(slide, Inches(0.5), Inches(0.08), SW - Inches(1), Inches(0.44),
             f"CBflow Global — library-manager",
             size=12, bold=True, color=WHITE)
    add_text(slide, Inches(0.5), Inches(0.42), SW - Inches(1.5), Inches(0.5),
             title, size=22, bold=True, color=WHITE)
    add_text(slide, SW - Inches(1.5), Inches(0.42), Inches(1.0), Inches(0.5),
             f"{slide_no} / {TOTAL}",
             size=12, color=WHITE, align=PP_ALIGN.RIGHT)
    # Subtitle
    if subtitle:
        add_text(slide, Inches(0.5), Inches(1.0), SW - Inches(1), Inches(0.4),
                 subtitle, size=14, color=MUTED)
    # Footer
    add_text(slide, Inches(0.5), SH - Inches(0.35),
             SW - Inches(1), Inches(0.3),
             "SmartSoc Solutions — cbflow Global v2.0.0",
             size=9, color=MUTED, align=PP_ALIGN.CENTER)


def add_code_block(slide, left, top, width, height, text,
                   title=None, size=10):
    """Monospace code box with light panel background."""
    if title:
        add_text(slide, left, top, width, Inches(0.3), title,
                 size=11, bold=True, color=INK)
        top = top + Inches(0.35)
        height = height - Inches(0.35)
    add_rect(slide, left, top, width, height, fill=PANEL, line=LINE)
    add_text(slide, left + Inches(0.12), top + Inches(0.08),
             width - Inches(0.24), height - Inches(0.16),
             text, size=size, color=INK, font=MONO)


def add_bullet_block(slide, left, top, width, height, bullets,
                     title=None, header_color=GREEN_DARK):
    """Panel with title + bullet list."""
    add_rect(slide, left, top, width, height, fill=WHITE, line=LINE)
    if title:
        add_rect(slide, left, top, width, Inches(0.4),
                 fill=header_color, line=header_color)
        add_text(slide, left + Inches(0.15), top + Inches(0.04),
                 width - Inches(0.3), Inches(0.32),
                 title, size=12, bold=True, color=WHITE)
        bullet_top = top + Inches(0.5)
        bullet_h = height - Inches(0.6)
    else:
        bullet_top = top + Inches(0.1)
        bullet_h = height - Inches(0.2)
    body = '\n'.join('•  ' + b for b in bullets)
    add_text(slide, left + Inches(0.2), bullet_top,
             width - Inches(0.3), bullet_h,
             body, size=11, color=BODY)


# ────────────────────────────────────────────────────────────────────────
# SLIDE 1 — Title / overview
# ────────────────────────────────────────────────────────────────────────
def slide_01(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    add_rect(s, 0, 0, SW, SH, fill=GREEN_TINT, line=GREEN_TINT)
    # Big centered title block
    add_rect(s, Inches(1.0), Inches(1.0), SW - Inches(2), Inches(5.5),
             fill=WHITE, line=GREEN_DARK, line_width=1)
    add_text(s, Inches(1.3), Inches(1.4), SW - Inches(2.6), Inches(1.0),
             "library-manager",
             size=48, bold=True, color=GREEN_DARK, align=PP_ALIGN.CENTER)
    add_text(s, Inches(1.3), Inches(2.4), SW - Inches(2.6), Inches(0.6),
             "Vendor library drops → signoff-ready tag directories",
             size=20, color=BODY, align=PP_ALIGN.CENTER)

    # Three "what it does" blocks
    cell_w = Inches(3.3)
    cell_top = Inches(3.4)
    cell_h = Inches(1.9)
    cells = [
        ("Discover",
         "Scan a vendor delivery tree. Classify files by track × VT × corner, "
         "memory / IO / analog / IP. Report coverage gaps.",
         GREEN_DARK),
        ("Materialize",
         "Build a self-contained tag directory with symlinks to the vendor "
         "originals. README + MANIFEST audit trail written automatically.",
         BLUE_DARK),
        ("Evolve",
         "`add` extends an existing tag when late-arriving analog or IP "
         "deliveries show up. No full rescan, no rework.",
         AMBER_DARK),
    ]
    x0 = Inches(1.3)
    gap = Inches(0.15)
    for i, (name, desc, color) in enumerate(cells):
        x = x0 + (cell_w + gap) * i
        add_rect(s, x, cell_top, cell_w, Inches(0.5),
                 fill=color, line=color)
        add_text(s, x, cell_top + Inches(0.1), cell_w, Inches(0.4),
                 name, size=14, bold=True, color=WHITE,
                 align=PP_ALIGN.CENTER)
        add_rect(s, x, cell_top + Inches(0.5), cell_w, cell_h - Inches(0.5),
                 fill=PANEL, line=LINE)
        add_text(s, x + Inches(0.2), cell_top + Inches(0.65),
                 cell_w - Inches(0.4), cell_h - Inches(0.75),
                 desc, size=11, color=BODY)

    add_text(s, Inches(1.3), Inches(5.6), SW - Inches(2.6), Inches(0.5),
             "cbflow flow library-manager  <scan | generate | add | "
             "status | coverage | verify>",
             size=11, color=INK, font=MONO, align=PP_ALIGN.CENTER)
    add_text(s, Inches(0.5), SH - Inches(0.5), SW - Inches(1), Inches(0.3),
             "SmartSoc Solutions — cbflow Global v2.0.0",
             size=10, color=MUTED, align=PP_ALIGN.CENTER)


# ────────────────────────────────────────────────────────────────────────
# SLIDE 2 — Tag directory layout
# ────────────────────────────────────────────────────────────────────────
def slide_05(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    add_slide_frame(s, 2, "Library tag — self-contained directory",
                    "Each tag is a view: lib_config + README + MANIFEST + symlinks")

    add_code_block(s, Inches(0.5), Inches(1.6),
                   Inches(7.5), Inches(5.3),
                   title="global/config/tech/gf_22nm/v1.0.0/P0/",
                   text="""P0/
├── lib_config.tcl        ← tech(...) keys w/ $_lib_tag_dir-relative paths
├── README.md             ← PVT coverage + flow-integration cheat-sheet
├── MANIFEST.tcl          ← audit: symlink → vendor target + method
│
├── ndm/<track>/*.ndm     ← stdcell NDM, all VTs flat per-track
├── lib/<track>/*.lib     ← Liberty timing + nominal (VT+corner in name)
├── db/<track>/*.db       ← compiled .db for PT / FC
├── lef/<track>/*.lef     ← abstract LEF
│
├── memory/
│   └── {ndm, lib, db, lef}/*       ← memory macros
├── io/
│   └── {ndm, lib, db, lef}/*       ← IO pad library
├── analog/
│   └── {ndm, lib, db, lef}/*       ← analog macros (PLL, ADC, LDO, …)
├── ip/
│   └── {ndm, lib, db, lef}/*       ← IP blocks (DDR PHY, SerDes, cores)
│
├── gds/, cdl/, verilog/            ← reserved for signoff deliverables
└── logs/generate.log""")

    add_bullet_block(s, Inches(8.3), Inches(1.6),
                     Inches(4.6), Inches(2.5),
                     title="Why a directory?",
                     bullets=[
                         "Self-contained & relocatable: mv P0 P0_frozen",
                         "lib_config.tcl paths use $_lib_tag_dir — survives move",
                         "README gives humans PVT coverage at a glance",
                         "MANIFEST = audit trail of symlink targets",
                     ],
                     header_color=GREEN_DARK)

    add_bullet_block(s, Inches(8.3), Inches(4.3),
                     Inches(4.6), Inches(2.6),
                     title="Flow integration",
                     bullets=[
                         "Set project(lib_config_tag) \"P0\" in user_config",
                         "Resolver auto-picks P0/lib_config.tcl",
                         "Downstream tools unchanged — same tech(...) keys",
                         "Shippable: tar the whole P0/ dir, send to collab",
                     ],
                     header_color=BLUE_DARK)


# ────────────────────────────────────────────────────────────────────────
# SLIDE 6 — Library-manager commands
# ────────────────────────────────────────────────────────────────────────
def slide_06(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    add_slide_frame(s, 3, "library-manager commands",
                    "Six subcommands cover the full lifecycle of a tag")

    cmds = [
        ("scan", "Enumerate .lib / .ndm / .lef files in a directory tree.\nQuick inventory — doesn't modify tech config.",
         "cbflow flow library-manager scan --path /vendor/libs/", GREEN_DARK),
        ("generate", "Scan a lib_root + materialize a new tag directory.\nCreates symlinks, lib_config.tcl, README, MANIFEST.",
         "cbflow flow library-manager generate --tech gf_22nm --tag P0 \\\n    --lib-root /vendor/22nm --memory-path /vendor/mem", GREEN_DARK),
        ("add", "Surgically add ONE category to an existing tag.\nPreserves other categories. Zero rework.",
         "cbflow flow library-manager add --tech gf_22nm --tag P0 \\\n    --category analog --path /vendor/pll_v2", BLUE_DARK),
        ("status", "Signoff-readiness report. VT availability, LEF/RCX coverage,\nper-track lib counts. Reads project(lib_config_tag).",
         "cbflow flow library-manager status --tech gf_22nm --tag P0", GREEN_DARK),
        ("coverage", "Matrix view: tracks × VTs × corners.\nAt-a-glance signoff gaps.",
         "cbflow flow library-manager coverage --tech gf_22nm --tag P0", GREEN_DARK),
        ("verify", "Read .lib header, cross-check PVT against filename.\nCatches corrupt / mis-labelled vendor drops.",
         "cbflow flow library-manager verify --path /vendor/libs/", AMBER_DARK),
    ]
    row_h = Inches(0.85)
    top = Inches(1.5)
    for i, (name, desc, cmd, color) in enumerate(cmds):
        y = top + row_h * i
        # Name chip
        chip = add_rect(s, Inches(0.5), y, Inches(1.6), Inches(0.75),
                        fill=color, line=color)
        add_text(s, Inches(0.5), y + Inches(0.2), Inches(1.6), Inches(0.4),
                 name, size=14, bold=True, color=WHITE,
                 align=PP_ALIGN.CENTER)
        # Description
        add_text(s, Inches(2.3), y + Inches(0.0), Inches(5.0), Inches(0.75),
                 desc, size=10, color=BODY)
        # Command
        add_rect(s, Inches(7.4), y, Inches(5.4), Inches(0.75),
                 fill=PANEL, line=LINE)
        add_text(s, Inches(7.5), y + Inches(0.08),
                 Inches(5.2), Inches(0.6),
                 cmd, size=9, color=INK, font=MONO)


# ────────────────────────────────────────────────────────────────────────
# SLIDE 4 — Adding to an existing tag (incremental, no time progression)
# ────────────────────────────────────────────────────────────────────────
def slide_07(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    add_slide_frame(s, 4, "Adding to an existing tag",
                    "Extend any category of a tag without rescanning the rest")

    # Three-column: Before state → Command → After state
    col_w = Inches(4.1)
    gap = Inches(0.1)
    top = Inches(1.5)
    col_h = Inches(3.6)

    # Column 1 — Before (existing tag)
    x0 = Inches(0.5)
    add_rect(s, x0, top, col_w, Inches(0.5), fill=GREEN_DARK, line=GREEN_DARK)
    add_text(s, x0 + Inches(0.15), top + Inches(0.1),
             col_w - Inches(0.3), Inches(0.3),
             "EXISTING TAG", size=12, bold=True, color=WHITE)
    add_rect(s, x0, top + Inches(0.5), col_w, col_h - Inches(0.5),
             fill=PANEL, line=LINE)
    add_text(s, x0 + Inches(0.15), top + Inches(0.6),
             col_w - Inches(0.3), col_h - Inches(0.7),
             """P0/
├── lib_config.tcl
├── MANIFEST.tcl
├── README.md
├── ndm/9T/
│   └── stdcell.ndm
├── lib/9T/
│   └── stdcell_ss_0p80v_125c.lib
├── lef/9T/
│   └── stdcell.lef
├── memory/
│   ├── ndm/mem_256x32.ndm
│   └── lib/mem_ss_0p80v_125c.lib
├── io/
├── analog/        ← empty
└── ip/            ← empty""",
             size=9, color=INK, font=MONO)

    # Column 2 — Command
    x1 = x0 + col_w + gap
    add_rect(s, x1, top, col_w, Inches(0.5), fill=BLUE_DARK, line=BLUE_DARK)
    add_text(s, x1 + Inches(0.15), top + Inches(0.1),
             col_w - Inches(0.3), Inches(0.3),
             "RUN `add`", size=12, bold=True, color=WHITE)
    add_rect(s, x1, top + Inches(0.5), col_w, col_h - Inches(0.5),
             fill=PANEL, line=LINE)
    add_text(s, x1 + Inches(0.15), top + Inches(0.6),
             col_w - Inches(0.3), col_h - Inches(0.7),
             """cbflow flow library-manager add \\
  --tech gf_22nm \\
  --tag P0 \\
  --category analog \\
  --path /vendor/pll_v2 \\
          /vendor/adc_v1

Flags:
  --category   stdcell | memory | io |
               analog | ip
  --path       one or more dirs
  --tech / --tag  required

What happens:
  1. Scans only the given paths
  2. Symlinks files into
     <TAG>/<category>/{ndm,lib,
     db,lef}/
  3. Merges lib_config.tcl +
     MANIFEST.tcl in place
  4. Other categories untouched""",
             size=9, color=INK, font=MONO)

    # Column 3 — After
    x2 = x1 + col_w + gap
    add_rect(s, x2, top, col_w, Inches(0.5), fill=GREEN_DARK, line=GREEN_DARK)
    add_text(s, x2 + Inches(0.15), top + Inches(0.1),
             col_w - Inches(0.3), Inches(0.3),
             "AFTER", size=12, bold=True, color=WHITE)
    add_rect(s, x2, top + Inches(0.5), col_w, col_h - Inches(0.5),
             fill=GREEN_TINT, line=LINE)
    add_text(s, x2 + Inches(0.15), top + Inches(0.6),
             col_w - Inches(0.3), col_h - Inches(0.7),
             """P0/
├── lib_config.tcl    merged
├── MANIFEST.tcl      +4 entries
├── README.md         regen
├── ndm/9T/           preserved
├── lib/9T/           preserved
├── lef/9T/           preserved
├── memory/           preserved
├── io/               preserved
├── analog/           ← ADDED
│   ├── ndm/pll.ndm
│   ├── ndm/adc.ndm
│   ├── lib/pll_ss...
│   └── lef/pll.lef
└── ip/               still empty""",
             size=9, color=INK, font=MONO)

    # Bottom reference bar — mechanics summary
    bar_top = top + col_h + Inches(0.2)
    add_rect(s, Inches(0.5), bar_top, SW - Inches(1), Inches(1.4),
             fill=WHITE, line=GREEN_DARK, line_width=1)
    add_rect(s, Inches(0.5), bar_top, SW - Inches(1), Inches(0.35),
             fill=GREEN_DARK, line=GREEN_DARK)
    add_text(s, Inches(0.65), bar_top + Inches(0.04),
             SW - Inches(1.3), Inches(0.3),
             "Merge rules — how `add` preserves existing content",
             size=12, bold=True, color=WHITE)
    # Three-column rule explanation
    rule_cells = [
        ("Symlinks",
         "Existing symlinks in untouched categories are kept exactly as-is. "
         "New symlinks are placed under the target category's subdir only."),
        ("MANIFEST.tcl",
         "Union — new entries append, prior-category entries retained verbatim. "
         "Duplicate local-paths get overwritten by the fresh scan."),
        ("lib_config.tcl",
         "Three-way merge: new non-empty keys win, empty-list keys don't clobber "
         "existing non-empty values. tech() keys outside this category are kept."),
    ]
    rc_w = (SW - Inches(1.4)) / 3
    for i, (name, desc) in enumerate(rule_cells):
        rx = Inches(0.7) + rc_w * i
        add_text(s, rx, bar_top + Inches(0.45), rc_w - Inches(0.1), Inches(0.3),
                 name, size=11, bold=True, color=GREEN_DARK)
        add_text(s, rx, bar_top + Inches(0.72), rc_w - Inches(0.1), Inches(0.65),
                 desc, size=9, color=BODY)


# ────────────────────────────────────────────────────────────────────────
# Build
# ────────────────────────────────────────────────────────────────────────
def build(output_path):
    prs = Presentation()
    prs.slide_width  = SW
    prs.slide_height = SH
    # 4-slide library-manager-only deck:
    #   1. Title / overview        (slide_01)
    #   2. Tag directory layout    (slide_05 — kept its builder name)
    #   3. Commands                (slide_06)
    #   4. Adding to existing tag  (slide_07 — mechanics, not time-based)
    for fn in (slide_01, slide_05, slide_06, slide_07):
        fn(prs)
    prs.save(output_path)
    print(f"Wrote: {output_path}")


if __name__ == '__main__':
    import sys
    out = (sys.argv[1] if len(sys.argv) > 1
           else 'CBflow_Library_Manager_Deck.pptx')
    build(out)