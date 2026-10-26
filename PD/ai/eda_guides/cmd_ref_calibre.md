# Siemens Calibre Physical Verification — Complete Command Reference

## Table of Contents

1. [Overview and Architecture](#overview-and-architecture)
2. [SVRF Language Reference](#svrf-language-reference)
3. [Calibre nmDRC](#calibre-nmdrc)
4. [Calibre nmLVS](#calibre-nmlvs)
5. [Calibre xRC (Parasitic Extraction)](#calibre-xrc)
6. [Calibre PERC (Reliability)](#calibre-perc)
7. [Calibre Pattern Matching](#calibre-pattern-matching)
8. [RVE (Results Viewing Environment)](#rve)
9. [Calibre Interactive](#calibre-interactive)
10. [Batch Mode and Distributed Calibre](#batch-mode-and-distributed-calibre)
11. [Common Recipes and Patterns](#common-recipes-and-patterns)

---

## 1. Overview and Architecture

### Calibre Tool Suite Components

| Tool | Purpose | Primary Input | Primary Output |
|------|---------|---------------|----------------|
| nmDRC | Design Rule Checking | GDSII/OASIS + SVRF rules | DRC results database |
| nmLVS | Layout vs. Schematic | GDSII/OASIS + SVRF rules + netlist | LVS results database |
| xRC | Parasitic Extraction | GDSII/OASIS + xRC rules | SPEF/DSPF/Spectre netlist |
| PERC | Reliability Checks | GDSII/OASIS + PERC rules | PERC results |
| Pattern Matching | Layout pattern search | GDSII/OASIS + patterns | Pattern match results |
| RVE | Results viewing | Any Calibre results DB | Interactive display |
| Calibre Interactive | Real-time checking | Layout editor database | Highlighted violations |

### File Formats

- **SVRF** — Standard Verification Rule Format (primary rule language)
- **TVF** — Tcl Verification Format (Tcl-based rule language)
- **GDSII** — Layout database (stream format)
- **OASIS** — Layout database (newer, compressed)
- **SPEF** — Standard Parasitic Exchange Format
- **DSPF** — Detailed Standard Parasitic Format

### Invocation Methods

```bash
# Command-line invocation
calibre -drc <rule_file>
calibre -lvs <rule_file>
calibre -xrc <rule_file>
calibre -perc <rule_file>

# With specific options
calibre -drc -hier -turbo <rule_file>
calibre -lvs -hier -spice <netlist> <rule_file>

# Batch mode with runset
calibre -gui -drc <runset_file>
calibre -batch -drc <runset_file>
```

---

## 2. SVRF Language Reference

### 2.1 Basic SVRF Syntax

SVRF is a keyword-driven language. Each statement begins with a keyword and is typically one line (continuation with `\`).

```svrf
// Single-line comment
/* Multi-line
   comment */

// Variable assignment
VARIABLE name = value

// Include another file
INCLUDE "path/to/file.svrf"
```

### 2.2 Layout System Specification

```svrf
// Specify layout file
LAYOUT PATH "design.gds"
LAYOUT PRIMARY "top_cell"
LAYOUT SYSTEM GDSII    // or OASIS, LEFDEF

// Specify layout precision
PRECISION 1000          // database units per micron
RESOLUTION 1            // minimum resolution

// Layer mapping
LAYOUT MAP 1 DATATYPE 0  // map GDS layer 1, datatype 0
```

### 2.3 Layer Definitions

```svrf
// Basic layer definition from GDS
LAYER metal1   10                    // GDS layer number
LAYER metal1   10 0                  // GDS layer + datatype
LAYER via1     11 0

// Layer with datatype range
LAYER poly     20 0-10

// Derived layers (computed from operations)
LAYER metal1_wide = SIZE metal1 BY 0.5

// Text layer
TEXT LAYER 10 1000

// Layer aliases
LAYER MAP 10 DATATYPE 0 metal1
LAYER MAP 11 DATATYPE 0 via1
LAYER MAP 20 DATATYPE 0 poly
LAYER MAP 30 DATATYPE 0 ndiff
LAYER MAP 31 DATATYPE 0 pdiff
LAYER MAP 40 DATATYPE 0 nwell
LAYER MAP 41 DATATYPE 0 pwell
LAYER MAP 50 DATATYPE 0 contact
```

### 2.4 Layer Boolean Operations

```svrf
// OR (union)
metal_all = metal1 OR metal2
metal_all = metal1 | metal2

// AND (intersection)
poly_over_diff = poly AND ndiff
poly_over_diff = poly & ndiff

// NOT (subtraction)
field_oxide = NOT ndiff
metal1_no_via = metal1 NOT via1
metal1_no_via = metal1 - via1

// XOR (symmetric difference)
diff_xor = ndiff XOR pdiff
diff_xor = ndiff ^ pdiff

// INTERACT — select shapes that interact (touch or overlap)
metal1_with_via = metal1 INTERACT via1

// ENCLOSE — select shapes that completely enclose other shapes
metal1_enclosing_via = metal1 ENCLOSE via1

// NOT INTERACT — select shapes that do NOT interact
metal1_no_via = metal1 NOT INTERACT via1
```

### 2.5 Geometric (Sizing) Operations

```svrf
// SIZE — grow or shrink shapes
metal1_grown = SIZE metal1 BY 0.1        // grow by 0.1 um
metal1_shrunk = SIZE metal1 BY -0.1      // shrink by 0.1 um
metal1_sized = SIZE metal1 BY 0.1 0.2    // different X, Y sizing

// SIZE with options
metal1_grown = SIZE metal1 BY 0.1 INSIDE OF metal2    // constrained sizing
metal1_grown = SIZE metal1 BY 0.1 OUTSIDE OF metal2

// GROW — directional sizing
metal1_right = GROW metal1 EAST BY 0.1
metal1_up = GROW metal1 NORTH BY 0.5

// SHRINK — directional shrinking
metal1_trim = SHRINK metal1 WEST BY 0.1

// HOLES — extract holes from shapes
metal1_holes = HOLES metal1

// RECTANGLES — decompose into rectangles
metal1_rects = RECTANGLES metal1
```

### 2.6 Selection Operations

```svrf
// AREA — select by area
big_metal1 = AREA metal1 >= 100        // shapes >= 100 sq um
small_metal1 = AREA metal1 < 1         // shapes < 1 sq um

// PERIMETER — select by perimeter
long_perim = PERIMETER metal1 > 50

// LENGTH — select edges by length
long_edges = LENGTH edge_layer > 10

// VERTEX — select by vertex count
complex_shapes = VERTEX metal1 > 20

// RECTANGLE — select only rectangular shapes
rect_only = RECTANGLE metal1

// CONVEX — select convex shapes
convex_only = CONVEX metal1

// TOUCH — select shapes that touch (share edge but don't overlap)
metal1_touching_via = metal1 TOUCH via1

// INSIDE — select shapes entirely inside
via_inside_metal = via1 INSIDE metal1

// OUTSIDE — select shapes entirely outside
via_outside_metal = via1 OUTSIDE metal1

// CUT — cut shapes at intersections
metal1_cut = CUT metal1 BY via1

// STAMP — stamp shapes
metal1_stamp = STAMP metal1 via1
```

### 2.7 Edge Operations

```svrf
// EDGE — convert polygon boundaries to edges
metal1_edges = EDGE metal1

// INSIDE EDGE / OUTSIDE EDGE
inside_edges = INSIDE EDGE metal1 metal2
outside_edges = OUTSIDE EDGE metal1 metal2

// COINCIDENT EDGE
shared_edges = COINCIDENT EDGE metal1 metal2

// LENGTH — filter edges by length
long_edges = LENGTH metal1_edges > 10.0

// ANGLE — filter edges by angle
horiz_edges = ANGLE metal1_edges == 0
vert_edges = ANGLE metal1_edges == 90

// EDGE with direction
north_edges = EDGE metal1 NORTH
south_edges = EDGE metal1 SOUTH
east_edges = EDGE metal1 EAST
west_edges = EDGE metal1 WEST
```

### 2.8 Measurement Operations

```svrf
// INT — internal distance check (within same layer)
// Checks minimum spacing between shapes on the same layer
metal1_space_check { @ "Metal1 spacing < 0.2"
    INT metal1 < 0.2
}

// EXT — external distance check (between different layers)
// Checks minimum distance between shapes on different layers
metal_clearance { @ "Metal1-Metal2 clearance"
    EXT metal1 metal2 < 0.3
}

// ENCLOSURE — minimum enclosure check
encl_check { @ "Metal1 enclosure of via1"
    ENC via1 metal1 < 0.05
}

// WIDTH — minimum width check
width_check { @ "Metal1 minimum width"
    INT metal1 < 0.1 OPPOSITE
}

// NOTCH — notch check (concave space)
notch_check { @ "Metal1 notch"
    INT metal1 < 0.15 NOTCH
}

// WITH EDGE — measure with specific edge constraints
space_with_edge { @ "Spacing with parallel run"
    INT metal1 < 0.2 WITH EDGE [constraint] PARALLEL >= 0.5
}

// AREA INTERACTION — count interacting shapes
via_count = AREA INTERACT via1 metal1
```

### 2.9 DRC Check Measurement Modifiers

```svrf
// Distance measurement modifiers
INT metal1 < 0.2                    // Euclidean (default)
INT metal1 < 0.2 EUCLIDEAN          // Explicit Euclidean
INT metal1 < 0.2 MANHATTAN          // Manhattan distance
INT metal1 < 0.2 SQUARE             // Square distance
INT metal1 < 0.2 OPPOSITE           // Opposite edges only (width)
INT metal1 < 0.2 OPPOSITE EXTENDED  // Extended opposite

// Projection modifiers
INT metal1 < 0.2 PROJECTING >= 0.5  // Projection length >= 0.5
INT metal1 < 0.2 PARALLEL >= 0.5    // Parallel run length >= 0.5
INT metal1 < 0.2 PERPENDICULAR      // Perpendicular measurement

// Corner-to-corner checks
INT metal1 < 0.2 CORNER TO CORNER
INT metal1 < 0.2 CORNER TO EDGE
INT metal1 < 0.2 EDGE TO CORNER

// Region constraints
INT metal1 < 0.2 REGION              // Only in overlapping regions
INT metal1 < 0.2 ABUT == 0           // Non-abutting only
INT metal1 < 0.2 ABUT > 0            // Abutting only
INT metal1 < 0.2 ABUT < 0            // None

// Shielded checks
INT metal1 < 0.2 SHIELDED            // Shielded measurement
INT metal1 < 0.2 NOT SHIELDED        // Not shielded

// Step constraint
INT metal1 < 0.2 STEP >= 0.1         // Step height constraint

// Singular
INT metal1 < 0.2 SINGULAR            // Check individual edges
```

### 2.10 CONNECT Statement

```svrf
// Electrical connectivity specification
CONNECT metal1 metal2 BY via1
CONNECT metal2 metal3 BY via2
CONNECT poly ndiff BY contact
CONNECT poly pdiff BY contact

// Direct connection (same-layer connectivity)
CONNECT metal1 metal1

// Sconnect — soft connection (for LVS)
SCONNECT metal1 metal2 BY via1

// Connect with resistance
CONNECT metal1 metal2 BY via1 RESISTANCE 5.0
```

### 2.11 DEVICE Recognition

```svrf
// NMOS device recognition
DEVICE MN nmos_mod
    GATE poly ndiff BY gate_oxide
    SOURCE ndiff
    DRAIN ndiff
    BULK pwell
    [PROPERTY W, L]

// PMOS device recognition
DEVICE MP pmos_mod
    GATE poly pdiff BY gate_oxide
    SOURCE pdiff
    DRAIN pdiff
    BULK nwell
    [PROPERTY W, L]

// Resistor device recognition
DEVICE R res_mod
    PLUS rh_layer
    MINUS rh_layer
    [PROPERTY R, W, L]

// Capacitor device recognition
DEVICE C cap_mod
    PLUS metal1
    MINUS metal2
    [PROPERTY C, W, L]

// Diode device recognition
DEVICE D diode_mod
    PLUS ndiff
    MINUS pwell

// Device property extraction
DEVICE PROPERTY MN nmos_mod
    W [width_function]
    L [length_function]
    AS [area_source]
    AD [area_drain]
    PS [perim_source]
    PD [perim_drain]
    NF [finger_count]
```

### 2.12 LVS Statements

```svrf
// Netlist specification
LVS NETLIST "source.spice" SOURCE SYSTEM SPICE
LVS NETLIST "source.cdl" SOURCE SYSTEM CDL

// LVS comparison options
LVS COMPARE [ON | OFF]
LVS REPORT "lvs_results.rep"

// LVS box type
LVS BOX "cellname" [BLACK | GRAY | WHITE]
LVS RECOGNIZE GATES [ALL | NONE | list]

// Pin name mapping
LVS POWER NAME "VDD" "VDDQ"
LVS GROUND NAME "VSS" "VSSQ"

// Filter
LVS FILTER [NONE | SHORT | OPEN | ALL]

// Reduce
LVS REDUCE [ON | OFF]
LVS REDUCE PARALLEL MOS [YES | NO]
LVS REDUCE SERIES MOS [YES | NO]

// Spice options
LVS SPICE MULTIPLIER NODE "M"

// Abort on supply errors
LVS ABORT ON SUPPLY ERROR [YES | NO]

// Report options
LVS REPORT OPTION [option_list]

// Execute LVS
LVS COMPARE
```

### 2.13 Variables and Expressions

```svrf
// Variable definition
VARIABLE min_width 0.1
VARIABLE min_space 0.2

// Using variables in checks
width_check { @ "Minimum width"
    INT metal1 < $min_width OPPOSITE
}

// Arithmetic expressions
VARIABLE double_space = $min_space * 2
VARIABLE half_width = $min_width / 2

// Conditional
#IFDEF METAL5
    LAYER metal5 50
#ELSE
    // no metal5
#ENDIF

// Define
#DEFINE METAL5
#DEFINE TECH_NODE 7
```

### 2.14 Output Specifications

```svrf
// DRC check output
DRC CHECK MAP "layer_name" GDSII layer_number [datatype]

// Results database
DRC RESULTS DATABASE "drc_results.db" [ASCII | BINARY]
DRC RESULTS DATABASE "drc_results.gds" GDSII

// Maximum results
DRC MAXIMUM RESULTS 1000
DRC MAXIMUM RESULTS ALL

// Summary report
DRC SUMMARY REPORT "drc_summary.rpt" [HIER | FLAT]

// Cell-level report
DRC CELL NAME [YES | NO]

// Timestamp
DRC RESULTS DATABASE TIMESTAMP [YES | NO]
```

---

## 3. Calibre nmDRC

### 3.1 DRC Rule File Structure

```svrf
// ========================================
// Standard DRC Rule File Template
// ========================================

// Header
LAYOUT PATH  "$layout_path"
LAYOUT PRIMARY "$top_cell"
LAYOUT SYSTEM GDSII

// Precision
PRECISION 10000
RESOLUTION 5

// Results
DRC RESULTS DATABASE "drc_results.db" ASCII
DRC SUMMARY REPORT "drc_summary.rpt" REPLACE HIER

// Maximum results per check
DRC MAXIMUM RESULTS ALL
DRC MAXIMUM VERTEX 4096

// Layer definitions
LAYER metal1    10
LAYER metal1_dr 10 1
LAYER via1      11
LAYER metal2    20
LAYER poly      30
LAYER ndiff     40
LAYER pdiff     41
LAYER nwell     50
LAYER pwell     51
LAYER contact   60

// Derived layers
metal1_wide = metal1 NOT RECTANGLE metal1 BY 0.5 0.5
gate_poly = poly AND (ndiff OR pdiff)

// DRC Rules
// ========================================

// Metal1 minimum width
M1.W.1 { @ "Metal1 minimum width = 0.1um"
    INTERNAL metal1 < 0.1 OPPOSITE
}

// Metal1 minimum spacing
M1.S.1 { @ "Metal1 minimum spacing = 0.2um"
    EXTERNAL metal1 < 0.2
}

// Metal1 minimum area
M1.A.1 { @ "Metal1 minimum area = 0.04 sq um"
    AREA metal1 < 0.04
}

// Via1 enclosure by metal1
V1.E.1 { @ "Via1 enclosure by metal1 >= 0.05um"
    ENCLOSURE via1 metal1 < 0.05
}

// Via1 enclosure by metal2
V1.E.2 { @ "Via1 enclosure by metal2 >= 0.05um"
    ENCLOSURE via1 metal2 < 0.05
}

// Via1 minimum spacing
V1.S.1 { @ "Via1 minimum spacing = 0.15um"
    EXTERNAL via1 < 0.15
}

// Metal1 spacing dependent on width
M1.S.2 { @ "Metal1 spacing 0.3um when width >= 0.5um"
    metal1_wide = WIDTH metal1 >= 0.5
    EXTERNAL metal1_wide metal1 < 0.3
}

// Density checks
M1.D.1 { @ "Metal1 density 20%-80%"
    DENSITY metal1 < 0.2 WINDOW 50 STEP 25
    DENSITY metal1 > 0.8 WINDOW 50 STEP 25
}
```

### 3.2 DRC Command-Line Options

```bash
# Basic DRC run
calibre -drc rule_file.svrf

# Hierarchical DRC
calibre -drc -hier rule_file.svrf

# Turbo mode (faster)
calibre -drc -turbo rule_file.svrf

# Combined hierarchical + turbo
calibre -drc -hier -turbo rule_file.svrf

# Specify number of CPUs
calibre -drc -turbo -hyper rule_file.svrf  # hyper-threading

# 64-bit mode
calibre -64 -drc rule_file.svrf

# Specify transcript file
calibre -drc rule_file.svrf -transcript drc_transcript.log

# Specify license
calibre -drc -lic_wait rule_file.svrf

# Remote execution
calibre -drc -remote -remotefile hosts.txt rule_file.svrf

# With environment variables
CALIBRE_LVS_REPORT=lvs.rep calibre -lvs rule_file.svrf
```

### 3.3 Advanced DRC Constructs

```svrf
// Antenna rules
ANTENNA RATIO metal1 poly 400     // area ratio check

// Density checks with windows
DENSITY metal1 < 0.2 WINDOW 100.0 STEP 50.0
DENSITY metal1 > 0.8 WINDOW 100.0 STEP 50.0

// Recommended rules (warnings, not errors)
RECOMMENDED RULES
M1.W.REC { @ "Recommended metal1 width >= 0.15"
    INT metal1 < 0.15 OPPOSITE
}

// Off-grid check
offgrid_check { @ "Metal1 off-grid"
    OFFGRID metal1 0.005   // 5nm grid
}

// Acute angle check
angle_check { @ "Metal1 acute angle"
    ACUTE ANGLE metal1 < 90
}

// Metal slot rules
slot_check { @ "Metal1 slot required for width > 3um"
    metal1_wide = WIDTH metal1 > 3.0
    metal1_no_slot = metal1_wide NOT INTERACT metal1_slot
    // Flag metal1_no_slot as error
}

// Width-dependent spacing table
M1.S.TABLE { @ "Metal1 width-dependent spacing"
    @ Width Range | Min Spacing
    @ 0 - 0.5    | 0.2
    @ 0.5 - 1.5  | 0.3
    @ > 1.5      | 0.5
    metal1_w1 = WIDTH metal1 >= 0 < 0.5
    metal1_w2 = WIDTH metal1 >= 0.5 < 1.5
    metal1_w3 = WIDTH metal1 >= 1.5
    EXT metal1_w1 < 0.2
    EXT metal1_w2 metal1 < 0.3
    EXT metal1_w3 metal1 < 0.5
}

// End-of-line spacing
M1.EOL.1 { @ "Metal1 end-of-line spacing"
    metal1_eol_edge = LENGTH (EDGE metal1) < 0.1
    EXT metal1 < 0.15 EDGE metal1_eol_edge
}

// Minimum enclosed area (prevents small holes)
M1.EA.1 { @ "Metal1 minimum enclosed area"
    HOLES metal1
    AREA (HOLES metal1) < 0.1
}

// Corner-to-corner spacing
M1.CC.1 { @ "Metal1 corner-to-corner spacing"
    INT metal1 < 0.15 CORNER TO CORNER
}
```

### 3.4 Conditional DRC Rules

```svrf
// Rule severity
M1.W.1 { @ "Metal1 minimum width" SEVERITY 1
    INT metal1 < 0.1 OPPOSITE
}

// Rule with waiver
M1.S.1 { @ "Metal1 spacing" WAIVABLE
    EXT metal1 < 0.2
}

// Rule filtering by cell
M1.W.1 CELL FILTER "pad_*" {
    // different rules for pad cells
    INT metal1 < 0.5 OPPOSITE
}

// Exclude regions
exclude_region = TEXT LAYER 100
M1.S.1 { @ "Metal1 spacing (non-excluded)"
    EXT (metal1 NOT INTERACT exclude_region) < 0.2
}
```

---

## 4. Calibre nmLVS

### 4.1 LVS Rule File Structure

```svrf
// ========================================
// Standard LVS Rule File Template
// ========================================

// Layout specification
LAYOUT PATH "$layout_path"
LAYOUT PRIMARY "$top_cell"
LAYOUT SYSTEM GDSII

// Source netlist specification
SOURCE PATH "$source_netlist"
SOURCE PRIMARY "$top_cell"
SOURCE SYSTEM SPICE

// LVS report
LVS REPORT "$lvs_report"
LVS REPORT OPTION S V

// Precision
PRECISION 10000

// ========================================
// Layer Definitions
// ========================================
LAYER metal1   10
LAYER metal2   20
LAYER via1     11
LAYER poly     30
LAYER ndiff    40
LAYER pdiff    41
LAYER nwell    50
LAYER pwell    51
LAYER contact  60
LAYER gate_ox  70

// Text layers for net names
TEXT LAYER 10 1000    // metal1 text
TEXT LAYER 20 1000    // metal2 text

// ========================================
// Connectivity
// ========================================
CONNECT metal1 metal2 BY via1
CONNECT metal1 ndiff BY contact
CONNECT metal1 pdiff BY contact
CONNECT metal1 poly BY contact
CONNECT poly ndiff BY gate_ox
CONNECT poly pdiff BY gate_ox

// Substrate connectivity
CONNECT nwell pwell BY OVERLAP

// ========================================
// Device Recognition
// ========================================

// NMOS
DEVICE MN nmos (G poly) (S ndiff) (D ndiff) (B pwell)
    [PROPERTY W, L, AS, AD, PS, PD]

// PMOS
DEVICE MP pmos (G poly) (S pdiff) (D pdiff) (B nwell)
    [PROPERTY W, L, AS, AD, PS, PD]

// Resistor
DEVICE R rppoly (PLUS poly_res) (MINUS poly_res)
    [PROPERTY R, W, L]

// Capacitor
DEVICE C mimcap (PLUS cap_top) (MINUS cap_bot)
    [PROPERTY C, W, L]

// Diode
DEVICE D ndiode (PLUS ndiff_diode) (MINUS pwell)

// ========================================
// LVS Options
// ========================================

// Power/ground names
LVS POWER NAME "VDD" "VDDQ" "VDDPLL"
LVS GROUND NAME "VSS" "VSSQ" "VSSPLL"

// Gate recognition
LVS RECOGNIZE GATES ALL

// Reduce parallel/series devices
LVS REDUCE PARALLEL MOS YES
LVS REDUCE SERIES MOS NO
LVS REDUCE SPLIT GATES YES

// Handling of black boxes
LVS BOX "SRAM*" BLACK
LVS BOX "analog_block" GRAY

// Filter shorts
LVS FILTER SHORTS SOURCE

// Compare
LVS COMPARE

// ERC (Electrical Rule Check) within LVS
ERC RESULTS DATABASE "erc_results.db"
ERC CELL NAME YES
ERC MAXIMUM RESULTS 1000
ERC CHECK [
    floating_gate
    floating_diff
    well_not_connected
]
```

### 4.2 LVS Command-Line Options

```bash
# Basic LVS run
calibre -lvs rule_file.svrf

# Hierarchical LVS
calibre -lvs -hier rule_file.svrf

# 64-bit LVS
calibre -64 -lvs rule_file.svrf

# LVS with turbo
calibre -lvs -turbo rule_file.svrf

# Specify SPICE netlist separately
calibre -lvs -spice source.cdl rule_file.svrf

# LVS with hcells (hierarchical cells)
calibre -lvs -hcell hcell_file rule_file.svrf

# Combined with transcript
calibre -lvs -hier -turbo rule_file.svrf 2>&1 | tee lvs.log
```

### 4.3 Advanced LVS Features

```svrf
// ========================================
// Parameterized cells (Pcells)
// ========================================
LVS SPICE OPTION INLINE_PARAMS YES

// Device multiplier
LVS SPICE MULTIPLIER NODE "M"

// Property tolerance
LVS PROPERTY MN(nmos) W TOLERANCE 0.01
LVS PROPERTY MN(nmos) L TOLERANCE 0.001

// ========================================
// Gate Recognition
// ========================================
LVS RECOGNIZE GATES ALL
// Specific gate types:
// NAND, NOR, NOT, AND, OR, XOR, MUX, LATCH, FLIPFLOP

LVS RECOGNIZE GATES NAND NOR NOT AND OR

// ========================================
// Bus handling
// ========================================
LVS SPICE REORDER PORT YES

// ========================================
// Black Box / Softchk
// ========================================
LVS SOFTCHK "cellname" LAYOUT SOURCE
LVS BOX "cellname" BLACK

// ========================================
// Net name assignment priority
// ========================================
LVS NET NAME PRIORITY
    LABEL > PIN > SIGNAL > AUTO

// ========================================
// ERC within LVS
// ========================================
ERC PATHCHK metal1 metal2 metal3 RESISTANCE < 100
ERC CHECK OPEN
ERC CHECK SHORT
ERC FLOATING CONNECT BY nwell pwell
```

### 4.4 LVS Report Interpretation

```
Key sections of LVS report:

OVERALL COMPARISON RESULTS:
  ##########################
  #    CORRECT    #         # — Correct = all match
  ##########################
  # or                      #
  # INCORRECT              # — Mismatch found
  ##########################

NET COMPARISON:
  Layout nets: XXX
  Source nets: XXX
  Matched:     XXX
  Unmatched:   XXX (layout) / XXX (source)

DEVICE COMPARISON:
  Layout devices: XXX
  Source devices:  XXX
  Matched:        XXX

PROPERTY COMPARISON:
  Properties compared: W, L, AS, AD, PS, PD
  Property errors: XXX

UNMATCHED NETS:
  Net Name (Layout)  |  Net Name (Source)
  ...

UNMATCHED DEVICES:
  Device (Layout)  |  Device (Source)
  ...
```

### 4.5 Common LVS Debug Techniques

```svrf
// Increase verbosity
LVS REPORT OPTION S    // include source netlist in report
LVS REPORT OPTION V    // verbose matching info
LVS REPORT OPTION A    // ambiguity analysis
LVS REPORT OPTION P    // property comparison details
LVS REPORT OPTION N    // net info
LVS REPORT OPTION D    // device info

// Flatten specific cells for debugging
LVS FLATTEN CELL "problem_cell"

// Write extracted netlist
LVS WRITE LAYOUT NETLIST "extracted.sp" SPICE
LVS WRITE SOURCE NETLIST "source_clean.sp" SPICE

// Net tracing
LVS NET TRACE LAYOUT "net_name"

// Ignore specific cells
LVS IGNORE CELL "decap_*"
```

---

## 5. Calibre xRC (Parasitic Extraction)

### 5.1 xRC Rule File Structure

```svrf
// ========================================
// Calibre xRC Extraction Rule File
// ========================================

// Input files
LAYOUT PATH "$layout_path"
LAYOUT PRIMARY "$top_cell"
LAYOUT SYSTEM GDSII

// Precision
PRECISION 10000

// ========================================
// Layer Definitions (same as LVS)
// ========================================
LAYER metal1    10
LAYER metal2    20
LAYER via1      11
LAYER poly      30
// ... (all layers)

// ========================================
// Connectivity (same as LVS)
// ========================================
CONNECT metal1 metal2 BY via1
// ... (all connections)

// ========================================
// Device Recognition (same as LVS)
// ========================================
DEVICE MN nmos ...
DEVICE MP pmos ...

// ========================================
// Extraction Setup
// ========================================

// PEX (Parasitic Extraction) options
PEX NETLIST "extracted.spef" SPEF
// or
PEX NETLIST "extracted.dspf" DSPF
// or
PEX NETLIST "extracted.sp" SPECTRE

// Extraction type
PEX EXTRACT RC           // R and C extraction
PEX EXTRACT C            // C only
PEX EXTRACT R            // R only
PEX EXTRACT RCC          // R, Cc (coupling), Cg (ground)

// Reduction
PEX REDUCE YES           // reduce parasitic network
PEX REDUCE ANALOG NO     // don't reduce analog nets
PEX REDUCE STAR          // star reduction
PEX REDUCE PI            // pi reduction

// Frequency setting for reduction
PEX REDUCE FREQUENCY 1e9    // 1 GHz

// Ground node
PEX GROUND NAME "VSS"

// Report
PEX REPORT "xrc_report.rpt"
```

### 5.2 Process Technology File (xcal/xtech)

```svrf
// Technology file for parasitic extraction
// Defines physical layer properties

// Conductor definitions
CONDUCTOR metal1 THICKNESS 0.36 SHEET_RESISTANCE 0.08
CONDUCTOR metal2 THICKNESS 0.36 SHEET_RESISTANCE 0.08
CONDUCTOR metal3 THICKNESS 0.72 SHEET_RESISTANCE 0.04
CONDUCTOR poly   THICKNESS 0.15 SHEET_RESISTANCE 8.0

// Via resistance
VIA via1 RESISTANCE 4.5
VIA via2 RESISTANCE 4.5
VIA contact RESISTANCE 10.0

// Dielectric definitions
DIELECTRIC oxide1 ABOVE metal1 THICKNESS 0.5 PERMITTIVITY 3.9
DIELECTRIC oxide2 ABOVE metal2 THICKNESS 0.5 PERMITTIVITY 3.2
DIELECTRIC ild    BETWEEN metal1 metal2 THICKNESS 0.3 PERMITTIVITY 3.0

// Conformal dielectric
CONFORMAL_DIELECTRIC barrier THICKNESS 0.01 PERMITTIVITY 7.0

// Substrate
SUBSTRATE THICKNESS 500 RESISTIVITY 10
```

### 5.3 xRC Command-Line Options

```bash
# Basic extraction
calibre -xrc rule_file.svrf

# Hierarchical extraction
calibre -xrc -hier rule_file.svrf

# 64-bit extraction
calibre -64 -xrc rule_file.svrf

# Combined with turbo
calibre -xrc -turbo rule_file.svrf

# Extract specific nets only
calibre -xrc -xcell xcell_file rule_file.svrf

# With parallel processing
calibre -xrc -turbo -hyper rule_file.svrf
```

### 5.4 Advanced xRC Features

```svrf
// ========================================
// Net Selection
// ========================================

// Extract specific nets
PEX EXTRACT NET "clk" "reset" "data_bus*"

// Exclude nets
PEX EXCLUDE NET "VDD" "VSS"

// Critical nets (higher accuracy)
PEX CRITICAL NET "clk*" "scan*"
PEX CRITICAL NET ACCURACY HIGH

// ========================================
// Coupling Capacitance
// ========================================

// Enable coupling cap extraction
PEX EXTRACT CC YES
PEX CC THRESHOLD 0.01    // minimum coupling cap (fF)

// Coupling cap between specific nets
PEX CC NET "clk" "data"

// ========================================
// Via Modeling
// ========================================
PEX VIA MODEL DISTRIBUTED    // distributed via model
PEX VIA MODEL LUMPED         // lumped via model

// ========================================
// Advanced Reduction
// ========================================
PEX REDUCE TICER              // TICER reduction
PEX REDUCE ARNOLDI            // Arnoldi reduction

// Reduction with error bound
PEX REDUCE ERROR 5            // 5% error bound

// Keep pins in reduced netlist
PEX REDUCE KEEP PIN YES

// ========================================
// Inductance Extraction
// ========================================
PEX EXTRACT L YES              // enable inductance
PEX L FREQUENCY 5e9            // frequency for inductance

// ========================================
// Temperature
// ========================================
PEX TEMPERATURE 25             // 25C
PEX TEMPERATURE RANGE 0 125    // corner range

// ========================================
// Output Format Options
// ========================================

// SPEF options
PEX NETLIST "output.spef" SPEF
PEX SPEF VERSION 1.5           // SPEF version
PEX SPEF UNITS R OHM C FF L NH T PS  // units

// DSPF options
PEX NETLIST "output.dspf" DSPF
PEX DSPF INCLUDE_DEVICE YES

// Spectre format
PEX NETLIST "output.sp" SPECTRE
PEX NETLIST INCLUDE SUBCIRCUIT YES

// Multiple output formats
PEX NETLIST "output.spef" SPEF
PEX NETLIST "output.dspf" DSPF
```

### 5.5 xRC Calibration

```svrf
// ========================================
// Process Calibration
// ========================================

// Calibration corners
PEX CORNER BEST    // best-case parasitics
PEX CORNER WORST   // worst-case parasitics
PEX CORNER NOMINAL // nominal parasitics

// Custom corner scaling
PEX SCALE RC 1.0 1.2    // R scale, C scale for worst case
PEX SCALE RC 1.0 0.8    // for best case

// Process variation
PEX VARIATION METAL1 THICKNESS 0.36 SIGMA 0.02
PEX VARIATION METAL1 WIDTH 0.1 SIGMA 0.005
```

---

## 6. Calibre PERC (Reliability)

### 6.1 PERC Overview

PERC (Programmable Electrical Rule Check) performs reliability-focused electrical verification including:
- ESD (Electrostatic Discharge) path verification
- Latch-up checks
- Voltage-aware DRC
- Current density checks
- Gate oxide integrity

### 6.2 PERC Rule File

```svrf
// ========================================
// Calibre PERC Rule File
// ========================================

LAYOUT PATH "$layout_path"
LAYOUT PRIMARY "$top_cell"
LAYOUT SYSTEM GDSII

PRECISION 10000

// Layer definitions (same as LVS)
// Connectivity (same as LVS)
// Device recognition (same as LVS)

// ========================================
// PERC Specific Checks
// ========================================

// Voltage annotation
PERC VOLTAGE "VDD" 1.0
PERC VOLTAGE "VDDQ" 1.8
PERC VOLTAGE "VSS" 0.0

// ========================================
// ESD Checks
// ========================================

// ESD protection path verification
PERC ESD CHECK
    FROM_PIN "PAD"
    TO_SUPPLY "VDD" "VSS"
    THROUGH_DEVICE "esd_diode"
    MAX_RESISTANCE 5.0

// ESD current path
PERC ESD PATH
    SOURCE "PAD*"
    SINK "VDD" "VSS"
    MIN_DEVICE_COUNT 1
    MAX_PATH_RESISTANCE 10.0

// ========================================
// Latch-up Checks
// ========================================

PERC LATCHUP CHECK
    GUARD_RING_REQUIRED YES
    MIN_GUARD_RING_WIDTH 0.5
    MAX_DISTANCE_TO_GUARD 10.0

// N-well to P-well spacing for latch-up
PERC LATCHUP WELL_SPACING
    NWELL_TO_PWELL_MIN 5.0

// ========================================
// Voltage-Aware DRC (VA-DRC)
// ========================================

// Spacing rules based on voltage difference
PERC VOLTAGE_AWARE
    metal1_high_voltage = NET metal1 VOLTAGE > 1.0
    metal1_low_voltage = NET metal1 VOLTAGE <= 1.0
    EXT metal1_high_voltage metal1_low_voltage < 0.5

// Gate oxide voltage check
PERC GATE_OXIDE CHECK
    MAX_VGS 1.1       // max gate-source voltage
    MAX_VGD 1.1       // max gate-drain voltage
    MAX_VGB 1.1       // max gate-bulk voltage

// ========================================
// Current Density
// ========================================

// Metal current density
PERC CURRENT_DENSITY metal1
    MAX_AVERAGE 2.0    // mA/um
    MAX_PEAK 5.0       // mA/um
    MAX_RMS 3.0        // mA/um

// Via current density
PERC CURRENT_DENSITY via1
    MAX_PER_VIA 0.5    // mA per via cut

// Electromigration-aware checks
PERC EM CHECK
    TEMPERATURE 105
    LIFETIME 10        // years
    FAILURE_RATE 100   // ppm
```

### 6.3 PERC Command-Line

```bash
# Run PERC
calibre -perc rule_file.svrf

# Hierarchical PERC
calibre -perc -hier rule_file.svrf

# 64-bit PERC
calibre -64 -perc rule_file.svrf

# With turbo
calibre -perc -turbo rule_file.svrf
```

---

## 7. Calibre Pattern Matching

### 7.1 Overview

Calibre Pattern Matching identifies specific layout patterns that cause yield or reliability issues. Patterns can be defined from known-bad structures or automatically generated.

### 7.2 Pattern Definition

```svrf
// ========================================
// Pattern Matching Rule File
// ========================================

LAYOUT PATH "$layout_path"
LAYOUT PRIMARY "$top_cell"
LAYOUT SYSTEM GDSII

// Layer definitions
LAYER metal1 10
LAYER metal2 20
LAYER via1   11

// ========================================
// Pattern Library
// ========================================

// Load pattern library
PATTERN LIBRARY "$pattern_lib_path"

// Pattern matching on specific layers
PATTERN MATCH metal1 {
    LIBRARY "$metal1_patterns.lib"
    MATCH_TYPE EXACT        // or FUZZY
    TOLERANCE 0.01          // matching tolerance
    REPORT "pattern_results.rpt"
}

// ========================================
// Pattern Creation from Markers
// ========================================

// Create pattern from DRC markers
PATTERN CREATE FROM DRC
    RULE "M1.S.1"
    CONTEXT 2.0             // context window (um)
    OUTPUT "new_pattern.lib"

// Create pattern from coordinates
PATTERN CREATE AT (100.5, 200.3)
    LAYER metal1 metal2
    CONTEXT 5.0
    OUTPUT "coord_pattern.lib"
```

### 7.3 Pattern Matching Commands

```bash
# Run pattern matching
calibre -drc -patternMatch rule_file.svrf

# Interactive pattern creation
calibre -rve -patternMatch results.db

# Batch pattern analysis
calibre -batch -patternMatch -lib pattern_lib.lib layout.gds
```

### 7.4 Advanced Pattern Features

```svrf
// Fuzzy matching with tolerance
PATTERN MATCH metal1 {
    LIBRARY "$lib"
    MATCH_TYPE FUZZY
    POSITION_TOLERANCE 0.05
    SIZE_TOLERANCE 0.02
    ROTATION YES           // match rotated patterns
    MIRROR YES             // match mirrored patterns
}

// Pattern scoring
PATTERN SCORE {
    WEIGHT yield_impact 0.7
    WEIGHT reliability_impact 0.3
    THRESHOLD 0.5
}

// Pattern filtering
PATTERN FILTER {
    MIN_OCCURRENCE 5       // minimum occurrences
    LAYER_COUNT >= 2       // minimum layer count
    AREA < 100             // maximum pattern area
}

// Pattern classification
PATTERN CLASSIFY {
    CATEGORY "yield_killer" SCORE > 0.8
    CATEGORY "marginal" SCORE > 0.5
    CATEGORY "acceptable" SCORE <= 0.5
}
```

---

## 8. RVE (Results Viewing Environment)

### 8.1 Launching RVE

```bash
# Launch RVE standalone
calibre -rve results.db

# Launch RVE for DRC results
calibre -rve drc_results.db

# Launch RVE for LVS results
calibre -rve lvs_results.db

# Launch with layout
calibre -rve -layout design.gds results.db

# Launch RVE from Tcl
calibredrv -rve results.db
```

### 8.2 RVE Navigation and Debug

```tcl
# RVE Tcl commands (calibredrv scripting)

# Open results database
$L open results "drc_results.db"

# List all DRC checks
$L listChecks results

# Get violations for a specific check
$L getViolations results "M1.S.1"

# Count violations
$L countViolations results "M1.S.1"

# Navigate to violation
$L gotoViolation results "M1.S.1" 1    ;# go to violation #1

# Highlight violation
$L highlight results "M1.S.1" 1

# Export results
$L export results "M1.S.1" -format ASCII -file violations.txt

# Waive violation
$L waive results "M1.S.1" 1 -reason "Accepted by foundry"
```

### 8.3 RVE Batch Commands

```bash
# Generate report from results database
calibre -rve -batch -report drc_results.db > report.txt

# Count violations
calibre -rve -batch -count drc_results.db

# Export specific check results
calibre -rve -batch -export "M1.S.1" drc_results.db > m1_spacing.txt

# Compare two results databases
calibre -rve -batch -compare old_results.db new_results.db
```

---

## 9. Calibre Interactive

### 9.1 Overview

Calibre Interactive provides real-time DRC/LVS checking within layout editors (Cadence Virtuoso, Siemens L-Edit, etc.). It allows designers to run checks interactively during layout editing.

### 9.2 Calibre Interactive in Virtuoso

```tcl
# Launch Calibre Interactive from Virtuoso
# Menu: Calibre > Run DRC
# Menu: Calibre > Run LVS

# Programmatic launch
CalibreDRC -runsetFile "drc_runset" -cell "top_cell"
CalibreLVS -runsetFile "lvs_runset" -cell "top_cell"

# Run specific DRC checks
CalibreDRC -ruleFile "rules.svrf" -checkList "M1.S.1 M1.W.1"

# Incremental DRC (check only modified area)
CalibreDRC -incremental YES -modifiedArea "100 200 150 250"
```

### 9.3 Runset File Format

```
// Calibre Interactive Runset File
*drcRulesFile: /path/to/rules.svrf
*drcRunDir: /path/to/run_dir
*drcLayoutPath: /path/to/layout.gds
*drcLayoutPrimary: top_cell
*drcResultsFile: drc_results.db
*drcSummaryFile: drc_summary.rpt
*drcTurboMode: 1
*drcHierMode: 1
*drcResultsFormat: ASCII

// LVS runset
*lvsRulesFile: /path/to/lvs_rules.svrf
*lvsRunDir: /path/to/lvs_run
*lvsLayoutPath: /path/to/layout.gds
*lvsSourcePath: /path/to/source.cdl
*lvsSpiceFile: /path/to/source.cdl
*lvsReport: lvs_report.rpt
*lvsHierMode: 1
```

### 9.4 Real-Time DRC (RealTime DRC / CalibreDRC-RealTime)

```tcl
# Enable real-time DRC in Virtuoso
CalibreDRC -realtime ON

# Configure real-time DRC
CalibreDRC -realtime ON \
    -ruleFile "rules.svrf" \
    -checkList "M1.S.1 M1.W.1 V1.E.1" \
    -window 50    ;# check window size in um

# Disable real-time DRC
CalibreDRC -realtime OFF

# Configure severity highlighting
CalibreDRC -realtime ON \
    -severity1Color "red" \
    -severity2Color "yellow" \
    -severity3Color "blue"
```

---

## 10. Batch Mode and Distributed Calibre

### 10.1 Batch Mode Execution

```bash
# Run DRC in batch mode
calibre -batch -drc rule_file.svrf

# Batch mode with runset
calibre -batch -drc -runset drc_runset.runset

# Submit to LSF queue
bsub -q long -n 8 calibre -drc -turbo -hyper rule_file.svrf

# Submit to SGE
qsub -pe smp 8 calibre_drc.sh
```

### 10.2 Distributed Calibre (Multi-Machine)

```bash
# Host file format (hosts.txt)
# hostname  num_cpus  memory(MB)
host1  8  16384
host2  8  16384
host3  4  8192

# Run distributed DRC
calibre -drc -turbo -remote -remotefile hosts.txt rule_file.svrf

# Remote with specific options
calibre -drc -turbo \
    -remote \
    -remotefile hosts.txt \
    -remotedata /shared/data \
    rule_file.svrf
```

### 10.3 Calibre Multi-Threaded Options

```bash
# Hyper-threading (use all CPUs)
calibre -drc -turbo -hyper rule_file.svrf

# Specific thread count
calibre -drc -turbo -hyper -mt 16 rule_file.svrf

# Memory limit
calibre -drc -turbo -hyper -mt 16 -memory 32768 rule_file.svrf
```

### 10.4 CalibreDRV (Calibre Driver) Scripting

```tcl
#!/usr/bin/env calibredrv

# CalibreDRV is the Tcl-based scripting interface for Calibre

# Open layout
set L [layout create "design.gds" -dt_expand]

# Get cell list
set cells [$L cells]

# Get layer list
set layers [$L layers]

# Iterate over cells
foreach cell $cells {
    puts "Cell: $cell"
    set bbox [$L bbox $cell]
    puts "  BBox: $bbox"
}

# Read specific layer
set shapes [$L iterator poly $cell range 0 0 100 100]
while {[$shapes next] != 0} {
    set coords [$shapes get -xy]
    puts "Shape at: $coords"
}
$shapes destroy

# Create new shapes
$L create_polygon $cell metal1 {0 0  10 0  10 5  0 5}

# Delete shapes
$L delete_polygon $cell metal1 {0 0  10 0  10 5  0 5}

# Save layout
$L gdsout "modified_design.gds"

# Close layout
$L close
```

---

## 11. Common Recipes and Patterns

### 11.1 Full Signoff DRC Flow

```bash
#!/bin/bash
# Full Calibre DRC signoff flow

export DESIGN="my_design"
export LAYOUT="${DESIGN}.gds"
export RULES="/foundry/calibre/drc_rules.svrf"
export RUNDIR="./calibre_drc"

mkdir -p $RUNDIR
cd $RUNDIR

# Create rule file wrapper
cat > drc_run.svrf << EOF
INCLUDE "$RULES"
LAYOUT PATH "../$LAYOUT"
LAYOUT PRIMARY "$DESIGN"
DRC RESULTS DATABASE "${DESIGN}_drc.db" ASCII
DRC SUMMARY REPORT "${DESIGN}_drc_summary.rpt" REPLACE HIER
DRC MAXIMUM RESULTS ALL
EOF

# Run DRC
calibre -64 -drc -hier -turbo drc_run.svrf 2>&1 | tee drc.log

# Check results
if grep -q "TOTAL DRC Results Generated = 0" drc.log; then
    echo "DRC CLEAN"
else
    echo "DRC VIOLATIONS FOUND"
    grep "TOTAL DRC Results" drc.log
fi
```

### 11.2 Full Signoff LVS Flow

```bash
#!/bin/bash
# Full Calibre LVS signoff flow

export DESIGN="my_design"
export LAYOUT="${DESIGN}.gds"
export NETLIST="${DESIGN}.cdl"
export RULES="/foundry/calibre/lvs_rules.svrf"
export RUNDIR="./calibre_lvs"

mkdir -p $RUNDIR
cd $RUNDIR

# Create rule file wrapper
cat > lvs_run.svrf << EOF
INCLUDE "$RULES"
LAYOUT PATH "../$LAYOUT"
LAYOUT PRIMARY "$DESIGN"
SOURCE PATH "../$NETLIST"
SOURCE PRIMARY "$DESIGN"
SOURCE SYSTEM SPICE
LVS REPORT "${DESIGN}_lvs.rep"
LVS REPORT OPTION S V
LVS POWER NAME "VDD" "VDDQ"
LVS GROUND NAME "VSS" "VSSQ"
LVS RECOGNIZE GATES ALL
LVS REDUCE PARALLEL MOS YES
LVS REDUCE SERIES MOS NO
EOF

# Run LVS
calibre -64 -lvs -hier -turbo lvs_run.svrf 2>&1 | tee lvs.log

# Check results
if grep -q "CORRECT" ${DESIGN}_lvs.rep; then
    echo "LVS CORRECT"
else
    echo "LVS INCORRECT"
fi
```

### 11.3 Parasitic Extraction Flow

```bash
#!/bin/bash
# Calibre xRC extraction flow

export DESIGN="my_design"
export LAYOUT="${DESIGN}.gds"
export RULES="/foundry/calibre/xrc_rules.svrf"
export RUNDIR="./calibre_xrc"

mkdir -p $RUNDIR
cd $RUNDIR

# Create extraction rule file
cat > xrc_run.svrf << EOF
INCLUDE "$RULES"
LAYOUT PATH "../$LAYOUT"
LAYOUT PRIMARY "$DESIGN"
PEX NETLIST "${DESIGN}.spef" SPEF
PEX EXTRACT RC
PEX EXTRACT CC YES
PEX CC THRESHOLD 0.01
PEX REDUCE YES
PEX REDUCE TICER
PEX GROUND NAME "VSS"
PEX TEMPERATURE 25
EOF

# Run extraction for different corners
for corner in rcbest rcworst rcnom; do
    cat > xrc_${corner}.svrf << EOF
INCLUDE "xrc_run.svrf"
PEX CORNER ${corner}
PEX NETLIST "${DESIGN}_${corner}.spef" SPEF
EOF
    calibre -64 -xrc -hier xrc_${corner}.svrf 2>&1 | tee xrc_${corner}.log &
done
wait

echo "Extraction complete for all corners"
```

### 11.4 Incremental DRC After ECO

```svrf
// Incremental DRC — check only modified region
LAYOUT PATH "design_eco.gds"
LAYOUT PRIMARY "top_cell"

// Define modified region
DRC INCREMENTAL CONNECT YES
DRC INCREMENTAL REGION 100 200 300 400    // x1 y1 x2 y2

// Or use difference-based incremental
LAYOUT COMPARE "design_original.gds"
DRC INCREMENTAL DELTA YES
```

### 11.5 Metal Fill DRC

```svrf
// Metal fill density checking and insertion guide

// Check density before fill
prefill_density { @ "Pre-fill metal1 density"
    DENSITY metal1 < 0.2 WINDOW 100 STEP 50
    DENSITY metal1 > 0.8 WINDOW 100 STEP 50
}

// After fill — exclude fill from certain checks
metal1_signal = metal1 NOT metal1_fill
metal1_all = metal1 OR metal1_fill

// Signal-only spacing
M1.S.signal { @ "Signal metal1 spacing"
    EXT metal1_signal < 0.2
}

// Fill-to-signal spacing (may be relaxed)
M1.S.fill { @ "Fill to signal spacing"
    EXT metal1_fill metal1_signal < 0.15
}
```

### 11.6 Multi-Patterning DRC (SADP/LELE)

```svrf
// Double patterning (LELE) decomposition check

// Two-color assignment
LAYER metal1_colorA 10 1
LAYER metal1_colorB 10 2

// Minimum same-color spacing
DP.S.same { @ "Same-color spacing"
    EXT metal1_colorA < 0.08
    EXT metal1_colorB < 0.08
}

// Odd-cycle check (uncolorable)
DP.ODD { @ "Odd cycle - undecomposable"
    DRC MULTI_PATTERNING metal1 2 DECOMPOSE
}
```

### 11.7 Useful Environment Variables

```bash
# Calibre environment variables
export CALIBRE_HOME=/opt/siemens/calibre/2024.1
export PATH=$CALIBRE_HOME/bin:$PATH
export MGLS_LICENSE_FILE=27000@license_server

# Performance tuning
export CALIBRE_TURBO_LITE=1              # lightweight turbo
export CALIBRE_MULTI_THREAD=16           # thread count
export CALIBRE_TMPDIR=/fast_disk/tmp     # temp directory (use fast storage)
export CALIBRE_MEMORY_LIMIT=65536        # memory limit in MB

# Debug
export CALIBRE_DEBUG=1
export CALIBRE_TRANSCRIPT=transcript.log
export CALIBRE_RUNDIR=./calibre_run
```

---

*This document covers the Siemens Calibre Physical Verification suite including nmDRC, nmLVS, xRC, PERC, Pattern Matching, RVE, and Calibre Interactive. For foundry-specific rules and technology files, consult your foundry PDK documentation.*
