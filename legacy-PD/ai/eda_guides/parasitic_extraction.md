# Parasitic Extraction

## Overview

Parasitic extraction computes the resistance (R) and capacitance (C) of all metal interconnections in a routed design. These parasitic values are critical inputs to static timing analysis, signal integrity analysis, power analysis, and IR drop analysis. The accuracy of parasitic extraction directly determines the accuracy of all downstream analyses — inaccurate parasitics lead to incorrect timing, missed SI violations, and unreliable power estimates.

## Extraction Fundamentals

### What Gets Extracted

- **Resistance (R):** Metal wire resistance, via resistance, contact resistance. Determines RC delay and IR drop.
- **Ground Capacitance (Cg):** Capacitance from a wire to the substrate or surrounding ground planes. Also called area and fringe capacitance.
- **Coupling Capacitance (Cc):** Capacitance between two adjacent signal wires. Critical for crosstalk analysis.
- **Via Resistance:** Resistance of via connections between metal layers. Often the dominant resistance component in a net.

### Parasitic Models

| Model | Components | Use Case |
|-------|-----------|----------|
| C-only | Capacitance to ground | Quick estimation, early flow |
| RC (lumped) | Single R + single C per net | Fast analysis, large designs |
| RC (distributed) | R and C segments per wire | Standard signoff accuracy |
| RCC | R + Cg + Cc (coupling) | SI analysis, crosstalk |
| RLCK | R + L + C + K (mutual inductance) | High-frequency, > 5 GHz |

### Extraction Output Formats

- **SPEF (Standard Parasitic Exchange Format):** Industry standard. Contains R, C, and coupling data. Used by all STA tools.
- **DSPF (Detailed Standard Parasitic Format):** More detailed than SPEF, includes exact geometry-level parasitics.
- **SBPF (Synopsys Binary Parasitic Format):** Binary format for faster read by Synopsys tools (PrimeTime, PT-SI).

## Extraction Engines

### Pattern Matching

Uses pre-characterized lookup tables of capacitance and resistance values for common wire geometries (width, spacing, layer stack combinations). Fast but less accurate for unusual geometries.

**Advantages:** Fast (minutes to hours for large designs), low memory.
**Disadvantages:** Less accurate for non-standard geometries, limited accuracy at sub-7nm.

**Tools:** Cadence QRC (default mode), Synopsys StarRC (rule-based mode).

### Field Solver

Solves Maxwell's equations numerically (finite element, boundary element, or random walk methods) to compute exact capacitance and resistance values for the actual 3D geometry of each wire neighborhood.

**Advantages:** Highest accuracy, handles complex geometries, double-patterning effects.
**Disadvantages:** Slower (hours to days), higher memory requirements.

**Tools:** Synopsys StarRC (field solver mode), Cadence QRC (field solver mode), Mentor Calibre xRC.

### Hybrid Approach

Most production flows use pattern matching as the default with field solver selectively applied to critical nets or nets flagged by SI analysis.

## Synopsys StarRC

StarRC is Synopsys's signoff parasitic extractor, tightly integrated with PrimeTime for timing signoff.

### StarRC Flow

```bash
# StarRC command-line invocation
StarXtract -clean \
    -techdir ./star_tech/ \
    -top_cell top \
    -gds top_routed.gds \
    -lef "tech.lef stdcell.lef" \
    -mapping gds_layer.map \
    -netlist top_routed.v \
    -spef top_ss.spef \
    -operating_condition ss_corner \
    -nxtgrd nxtgrd_ss.nxtgrd \
    -reduction star
```

### Key StarRC Options

```
# Extraction mode
EXTRACTION: RC
COUPLING_ABS_THRESHOLD: 3fF       # Minimum coupling cap to report
COUPLING_REL_THRESHOLD: 0.03      # 3% of total cap

# Reduction
NETLIST_TYPE: SPEF
REDUCTION: STAR                    # Recommended for timing

# Corner selection
OPERATING_TEMPERATURE: 125
METAL_FILL_POLYGON_HANDLING: FLOATING

# Via modeling
VIA_ARRAY_RESISTANCE: TRUE
VIA_CONTACT_RESISTANCE: TRUE
```

### TLU+ Models

TLU+ (Table Look-Up Plus) models are Synopsys's technology-specific lookup tables for parasitic extraction in IC Compiler II and Fusion Compiler.

```tcl
# In FC/ICC2
read_parasitic_tech -tlup max_tlu.tluplus -layermap layer.map -name worst
read_parasitic_tech -tlup min_tlu.tluplus -layermap layer.map -name best
```

### nxtgrd Models

nxtgrd is StarRC's native technology file format, providing higher accuracy than TLU+ for signoff extraction.

## Cadence QRC (Quantus)

QRC (now part of Quantus) is Cadence's parasitic extraction engine, integrated with Innovus and Tempus.

### QRC Technology File

```tcl
# In Innovus/Tempus MMMC setup
create_rc_corner -name rc_worst \
    -qrc_tech /path/to/worst/qrcTechFile \
    -temperature 125

create_rc_corner -name rc_best \
    -qrc_tech /path/to/best/qrcTechFile \
    -temperature -40
```

### Standalone QRC Extraction

```bash
# Quantus command line
quantus -cmd extract.cmd

# extract.cmd contents:
input_db -type innovus -design_dir top_routed.enc.dat
output_db -type spef -file top_worst.spef
extraction_setup -technology_file worst.qrcTechFile
extraction_setup -advanced_node true
extraction_setup -coupling_mode full_coupling
run_extraction
```

### QRC Options

```tcl
# In Innovus
setExtractRCMode -engine postRoute
setExtractRCMode -coupled true
setExtractRCMode -effortLevel signoff
setExtractRCMode -total_c_th 5   ;# fF threshold for coupling

# Run extraction
extractRC

# Write SPEF
rcOut -spef top_worst.spef -rc_corner rc_worst
```

## Extraction Corners

Parasitic values vary with process conditions (metal thickness, width, ILD thickness). Multiple extraction corners capture this variation:

| Corner | Metal R | Metal C | Coupling C | Use |
|--------|---------|---------|------------|-----|
| C-worst (Cmax) | Nominal | Maximum | Maximum | Setup timing (worst delay) |
| C-best (Cmin) | Nominal | Minimum | Minimum | Hold timing (best delay) |
| RC-worst | Maximum R | Maximum C | Maximum | SI analysis, IR drop |
| RC-best | Minimum R | Minimum C | Minimum | Hold analysis |

Typical signoff requires at least 2-3 extraction corners. Advanced designs may use 5-8 corners.

## Coupling Capacitance

### Importance for SI

Coupling capacitance between adjacent wires causes crosstalk:

- **Functional failure:** A switching aggressor induces a glitch on a quiet victim net, causing a logic error.
- **Timing impact:** A switching aggressor adds or subtracts delay from a switching victim (delta delay).

### Coupling Threshold Management

```tcl
# Set coupling capacitance thresholds
# Absolute threshold: ignore coupling caps below this value
COUPLING_ABS_THRESHOLD: 2fF

# Relative threshold: ignore coupling caps below this fraction of total net cap
COUPLING_REL_THRESHOLD: 0.03
```

**Trade-off:** Lower thresholds capture more coupling effects (more accurate SI analysis) but increase SPEF file size and STA runtime. For signoff, use thresholds of 2-5 fF absolute and 1-3% relative.

## Metal Fill Impact

Metal fill (dummy metal) inserted for density compliance affects parasitic extraction:

- **Floating fill:** Electrically unconnected metal fill increases coupling capacitance.
- **Grounded fill:** Fill connected to ground increases ground capacitance but reduces coupling.

```
# StarRC fill handling
METAL_FILL_POLYGON_HANDLING: FLOATING
# Options: FLOATING, GROUNDED, IGNORE
```

**Best practice:** Always include metal fill in signoff extraction. Using FLOATING is the most conservative and accurate approach.

## Common Issues and Fixes

**Issue: Timing mismatch between PnR extraction and signoff extraction**
- Verify that both extractors use the same technology file (TLU+, QRC tech, nxtgrd).
- Check that coupling thresholds are consistent.
- Ensure metal fill handling matches (floating vs. grounded vs. ignored).
- Compare total net capacitance between PnR and signoff SPEF for representative nets.

**Issue: SPEF file is too large (> 10 GB)**
- Increase coupling thresholds to reduce the number of coupling caps reported.
- Use binary SPEF format (SBPF for Synopsys tools).
- Split extraction by hierarchy — extract blocks separately.
- Use reduction (STAR reduction in StarRC) to simplify RC networks.

**Issue: Extraction runtime is too long**
- Use pattern matching instead of field solver for non-critical blocks.
- Increase coupling thresholds.
- Use distributed extraction across multiple machines.
- Extract at block level and stitch at the top.

**Issue: Negative coupling caps in SPEF**
- This is usually a tool or technology file issue. Verify the extraction technology file version.
- Check for negative capacitance handling in the STA tool: `set_app_var si_filter_negative_cap true`.

**Issue: Via resistance not matching measured silicon**
- Ensure via resistance modeling is enabled.
- Verify that via array reduction rules are correctly specified in the technology file.
- Check for via resistance scaling factors in the extraction setup.

## Best Practices

1. **Use the same extraction engine for PnR optimization and signoff** to minimize correlation gaps.
2. **Always extract with coupling** for signoff — C-only extraction misses SI effects.
3. **Include metal fill** in signoff extraction — it significantly affects coupling.
4. **Run extraction at all required corners** (Cmax, Cmin, RCmax at minimum).
5. **Validate extraction against test structures** if available — compare extracted vs. measured RC for representative wire geometries.
6. **Set coupling thresholds carefully** — too aggressive (low) wastes runtime; too relaxed (high) misses real SI issues.
7. **Use distributed extraction** for designs > 10M instances to manage runtime.
8. **Cross-check total capacitance** between different extraction tools/modes on a few representative nets to build confidence in extraction accuracy.
9. **Keep extraction technology files versioned** and synchronized with the foundry PDK release.
10. **Extract at signoff quality** (field solver or high-accuracy pattern matching) for tapeout — quick extraction modes are for exploration only.
