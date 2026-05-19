# Siemens Calibre Verification Guide

## Overview

Calibre is Siemens EDA's (formerly Mentor Graphics) industry-standard physical verification suite. Calibre has been the dominant signoff verification tool for decades, with the largest installed base across foundries and design houses. It provides DRC (nmDRC), LVS (nmLVS), parasitic extraction (xRC), pattern matching (pDRC), and metal fill capabilities. Foundries develop and certify Calibre rule decks as the golden reference for tapeout signoff.

## Calibre Tool Suite

| Tool | Function |
|------|----------|
| Calibre nmDRC | Design Rule Checking |
| Calibre nmLVS | Layout vs. Schematic |
| Calibre xRC | Parasitic extraction |
| Calibre pDRC | Pattern-based DRC |
| Calibre DESIGNrev | Layout viewer/editor |
| Calibre RVE | Results Viewing Environment |
| Calibre Interactive | GUI-based run manager |

## Rule Formats: SVRF and TVF

### SVRF (Standard Verification Rule Format)

SVRF is Calibre's traditional rule language. Rules are written as a sequence of geometric operations.

```svrf
// Layer definitions
LAYER M1      30
LAYER M1_DRW  30:0
LAYER VIA1    31
LAYER M2      32

// Derived layers
M1_WIRE = M1_DRW NOT M1_DUMMY

// DRC rule: M1 minimum width
M1.W.1 {
    INTERNAL M1_WIRE < 0.040
    DESCRIPTION "M1 minimum width = 40nm"
}

// DRC rule: M1 minimum spacing
M1.S.1 {
    EXTERNAL M1_WIRE < 0.040
    DESCRIPTION "M1 minimum spacing = 40nm"
}

// DRC rule: VIA1 enclosure by M1
V1.EN.1 {
    ENCLOSE VIA1 M1_WIRE < 0.010
    DESCRIPTION "VIA1 enclosure by M1 = 10nm"
}

// Density rule
M1.DN.1 {
    DENSITY M1_WIRE < 0.20 WINDOW 50 STEP 25
    DESCRIPTION "M1 minimum density = 20%"
}
```

### TVF (Tcl Verification Format)

TVF is Calibre's Tcl-based rule format, providing programmatic control for complex rule definitions.

```tcl
# TVF rule example
tvf::RULE M1.W.1 {
    tvf::DESCRIPTION "M1 minimum width = 40nm"
    set M1_shapes [tvf::LAYER_MAP 30 0]
    tvf::INTERNAL $M1_shapes < 0.040
}

tvf::RULE M1.S.1 {
    tvf::DESCRIPTION "M1 minimum spacing = 40nm"
    tvf::EXTERNAL $M1_shapes < 0.040
}
```

TVF advantages over SVRF:
- Variables and loops for parameterized rules
- Conditional rule execution
- Better code reuse and maintainability

## Calibre nmDRC

### Running nmDRC

```bash
# Command-line invocation
calibre -drc -hier drc_rules.svrf

# With specific options
calibre -drc -hier \
    -turbo 16 \          # Multi-threaded with 16 cores
    -hyper \             # Enable Hyper acceleration
    drc_rules.svrf
```

### DRC Rule Deck Input Section

```svrf
// Input configuration
LAYOUT PATH "top.gds"
LAYOUT PRIMARY "top_cell"
LAYOUT SYSTEM GDSII

// Output configuration
DRC RESULTS DATABASE "drc_results.db" GDSII
DRC MAXIMUM RESULTS 1000 PER RULE
DRC SUMMARY REPORT "drc_summary.rpt" REPLACE

// Processing controls
DRC CHECK TEXT
DRC CELL NAME YES
VIRTUAL CONNECT COLON YES
VIRTUAL CONNECT NAME "VDD" "VSS"

// Multi-threading
LAYOUT PROCESS COUNT 16
```

### DRC Results Review with RVE

```bash
# Open results in RVE
calibre -rve -drc drc_results.db
```

RVE (Results Viewing Environment) provides:
- Violation browser sorted by rule and severity
- Layout overlay showing violation markers
- Cross-probing between violation list and layout
- Filtering by rule, region, or violation count
- Waiver management

### Calibre Interactive for DRC

Calibre Interactive (CI) provides a GUI-based interface for configuring and running DRC:

```bash
# Launch Calibre Interactive
calibredrv -m top.gds -l drc_rules.svrf
```

CI features:
- Rule deck browser and editor
- Run configuration (input/output, parallelism)
- One-click run and results viewing
- Integration with layout editors (Virtuoso, Custom Compiler)

## Calibre nmLVS

### LVS Flow

```svrf
// LVS rule deck structure
LAYOUT PATH "top.gds"
LAYOUT PRIMARY "top_cell"
LAYOUT SYSTEM GDSII

SOURCE PATH "top_routed.v"
SOURCE PRIMARY "top"
SOURCE SYSTEM VERILOG

LVS REPORT "lvs_results.rpt"
LVS REPORT OPTION A B C D
LVS POWER NAME "VDD"
LVS GROUND NAME "VSS"

// Device recognition
DEVICE MN nmos_3p3
    [gate_oxide AND poly AND ndiff] // gate
    [ndiff OUTSIDE poly]            // source/drain
    [pwell_id]                      // bulk
DEVICE MP pmos_3p3
    [gate_oxide AND poly AND pdiff]
    [pdiff OUTSIDE poly]
    [nwell]

// Connectivity extraction
CONNECT M1 M2 BY VIA1
CONNECT M2 M3 BY VIA2
// ... etc for all layers

// Comparison
LVS COMPARE RESULTS "lvs_compare.rpt"
```

### Running nmLVS

```bash
# Command-line LVS
calibre -lvs -hier lvs_rules.svrf

# With multi-threading
calibre -lvs -hier -turbo 16 -hyper lvs_rules.svrf
```

### LVS Results

The LVS report contains:

1. **Summary:** CLEAN or INCORRECT status
2. **Instance comparison:** Matched/unmatched instances
3. **Net comparison:** Matched/unmatched nets
4. **Device comparison:** Matched/unmatched devices with property checks
5. **Discrepancy details:** Specific mismatches with layout/source locations

### LVS Debug with RVE

```bash
# Open LVS results in RVE
calibre -rve -lvs lvs_results.db
```

RVE LVS debug features:
- Side-by-side layout vs. schematic view
- Net highlighting and tracing
- Cross-probing between matched/unmatched components
- Connectivity browser for tracing opens and shorts
- Device property comparison

### Common LVS Techniques

**Net name matching:**
```svrf
// Force net name matching for power/ground
LVS POWER NAME "VDD" "VDDIO" "VDDH"
LVS GROUND NAME "VSS" "VSSIO"

// Soft connect for intentional shorts
LVS SOFTCHK
```

**Supply extraction:**
```svrf
// Extract power and ground as separate nets
LVS POWER NAME "VDD"
LVS GROUND NAME "VSS"
LVS RECOGNIZE GATES ALL
```

**Black boxing:**
```svrf
// Skip LVS on certain cells (e.g., analog IP)
LVS BOX "analog_block" "sram_macro"
```

## Calibre xRC (Parasitic Extraction)

### xRC Flow

```bash
# Run extraction
calibre -xrc -hier xrc_rules.svrf
```

### xRC Configuration

```svrf
// xRC setup
LAYOUT PATH "top_filled.gds"
LAYOUT PRIMARY "top_cell"

// Extraction type
EXTRACTION TYPE RC_COUPLED

// Output format
EXTRACTION OUTPUT FILE "top.spef"
EXTRACTION OUTPUT FORMAT SPEF

// Coupling capacitance threshold
CAPACITANCE COUPLING_ABS_THRESHOLD 3ff
CAPACITANCE COUPLING_REL_THRESHOLD 0.03

// Technology file
EXTRACTION TECH FILE "xrc_tech.rul"

// Netlist for back-annotation
SOURCE PATH "top_routed.v"
SOURCE PRIMARY "top"
SOURCE SYSTEM VERILOG
```

## Distributed Processing (Calibre MT and Hyper)

### Calibre Multi-Threaded (MT)

```bash
# Multi-threaded DRC
calibre -drc -hier -turbo 32 drc_rules.svrf
```

### Calibre Hyper

Hyper provides advanced scaling beyond basic MT by using a hierarchical distribution model:

```bash
# Hyper mode
calibre -drc -hier -turbo 64 -hyper drc_rules.svrf
```

### Remote Processing (Calibre MTflex)

```bash
# Distributed across machines
calibre -drc -hier -turbo 16 \
    -remotefile remote_config.txt \
    drc_rules.svrf

# remote_config.txt
MACHINE host1 16 /tmp/calibre
MACHINE host2 16 /tmp/calibre
MACHINE host3 16 /tmp/calibre
```

## Integration with PnR Tools

### Calibre in Innovus

```tcl
# Run Calibre DRC from within Innovus
set_verify_drc_mode -tool calibre \
    -rule_file drc_rules.svrf \
    -gds_file top.gds

verify_drc

# Run Calibre LVS from Innovus
set_verify_lvs_mode -tool calibre \
    -rule_file lvs_rules.svrf \
    -source_file top_routed.v

verify_lvs
```

### Calibre RealTime in Virtuoso

For custom/analog design, Calibre RealTime provides interactive DRC checking within the Virtuoso layout editor — violations appear in real-time as the designer draws shapes.

## Advanced Features

### Pattern-Based DRC (pDRC)

pDRC uses pattern libraries to identify known-problematic layouts that pass geometric DRC but cause yield issues.

```svrf
// Pattern matching
PDRC LIBRARY "pattern_lib.gds"
PDRC MATCH LAYER M1
PDRC RESULTS DATABASE "pdrc_results.db"
```

### Multi-Patterning Verification

For double patterning (DP) and triple patterning (TP) at advanced nodes:

```svrf
// Double patterning coloring check
DPC RULES {
    LAYER M1_mask1 = M1_DRW WHERE colorA
    LAYER M1_mask2 = M1_DRW WHERE colorB

    // Minimum spacing between same-color shapes
    DPC.S.1 {
        EXTERNAL M1_mask1 < 0.060
    }
}
```

### PERC (Programmable ERC)

Calibre PERC provides electrical rule checking beyond basic DRC/LVS:

- Point-to-point resistance checks
- Current density analysis
- ESD path verification
- Voltage-aware DRC

## Common Issues and Fixes

**Issue: DRC rule deck fails to load**
- Check SVRF syntax — missing semicolons, unbalanced braces.
- Verify layer definitions match the GDS layer map.
- Check file paths in the rule deck — absolute paths are safer.
- Run with `-drc -checkrules` to validate the rule deck without running DRC.

**Issue: LVS shows "unmatched nets" for power/ground**
- Verify `LVS POWER NAME` and `LVS GROUND NAME` include all supply net names.
- Check that virtual connect settings are correct: `VIRTUAL CONNECT COLON YES`.
- Ensure all power/ground vias are present in the layout.

**Issue: Calibre DRC results differ from ICV results**
- Compare rule implementations — some geometric operations have subtle differences between tools.
- Verify layer mapping is identical.
- Check rule deck versions — both must use the same foundry release.
- Run a small test pattern through both tools to isolate the discrepancy.

**Issue: Very long LVS runtime**
- Enable hierarchical mode: `-hier` flag.
- Use multi-threading: `-turbo N`.
- Black-box large IP blocks that have been independently verified.
- Check for pathological connectivity extraction (e.g., massive bus structures).

**Issue: xRC extraction produces unexpected parasitic values**
- Verify the extraction technology file matches the process node.
- Check coupling threshold settings — too high may miss coupling, too low may include noise.
- Compare with PnR extraction on a few representative nets.

## Best Practices

1. **Always use hierarchical mode** (`-hier`) for designs > 1M instances.
2. **Enable multi-threading** (`-turbo`) — Calibre scales well to 32-64 cores.
3. **Use the latest foundry-certified rule deck** — older versions may miss critical rules.
4. **Run Calibre Interactive** for initial debug and familiarization — then script production runs.
5. **Review DRC summary report** before diving into individual violations — identify systematic issues first.
6. **Use RVE for visual debug** — text reports cannot convey spatial relationships.
7. **Black-box verified IP** in LVS to reduce runtime and focus on new logic.
8. **Automate with Makefiles** — DRC/LVS/xRC should be reproducible single-command operations.
9. **Track violation counts** across design iterations — they should converge to zero.
10. **Cross-validate critical blocks** with a second tool (ICV) for highest confidence.
