# DRC Methodology: Design Rule Checking for Physical Verification

## Overview

Design Rule Checking (DRC) is the process of verifying that a physical layout complies with the geometric constraints (design rules) specified by the semiconductor foundry. These rules ensure that the design can be manufactured with acceptable yield. DRC is a mandatory signoff requirement; no design proceeds to mask generation with DRC violations. PD engineers must understand DRC rule categories, debugging methodologies, and the distinction between real and soft violations.

## DRC Rule Categories

Foundry design rules span dozens of categories with thousands of individual rules at advanced nodes. The major categories are described below.

### Spacing Rules

Spacing rules define the minimum distance between edges of geometric shapes on the same or different layers.

- **Minimum spacing**: The smallest allowed gap between two shapes on the same layer (e.g., metal1 minimum spacing = 0.04um at 7nm).
- **Wide-metal spacing**: Wider metal shapes require larger spacing to adjacent shapes. The wider the metal, the larger the required spacing (a step function with multiple width thresholds).
- **End-of-line (EOL) spacing**: Additional spacing required near the end of a metal line to account for lithographic rounding and pattern fidelity.
- **Corner-to-corner spacing**: Diagonal distance between shape corners may have different limits.
- **Same-net spacing**: Some rules differentiate between same-net and different-net spacing. Same-net spacing may be more relaxed.
- **Parallel run length spacing**: When two wires run parallel for a long distance, the required spacing increases to prevent systematic yield loss.

### Width Rules

Width rules define the minimum and maximum dimensions for shapes on each layer.

- **Minimum width**: The smallest allowed width for a shape (e.g., M1 min width = 0.028um at 7nm).
- **Maximum width**: Some layers have maximum width rules to prevent stress-related cracking or CMP dishing.
- **Minimum area**: Each shape must have a minimum area to ensure pattern fidelity during lithography.
- **Minimum enclosed area**: The minimum area of an enclosed void within a shape.

### Enclosure Rules

Enclosure rules specify how much one layer must extend beyond the boundary of another layer it contains.

- **Via enclosure**: The metal layer must extend a minimum distance around each via (e.g., M2 must enclose VIA1 by at least 0.01um on each side).
- **Contact enclosure**: Active/poly must enclose contacts by a minimum amount.
- **Well enclosure**: NWELL must enclose PMOS active by a minimum distance.
- **Directional enclosure**: At advanced nodes, enclosure requirements may differ in the preferred and non-preferred routing directions.

### Density Rules

Density rules ensure uniform pattern density across the die for CMP (Chemical-Mechanical Polishing) planarity.

- **Minimum density**: Each metal and via layer must meet a minimum density (typically 20-30%) in every window of specified size (e.g., 50um x 50um).
- **Maximum density**: Cannot exceed maximum density (typically 70-80%) to avoid CMP dishing.
- **Density gradient**: The density difference between adjacent windows must be below a limit.
- **Global density**: The overall die density must fall within a specified range.

Metal fill (dummy metal) is inserted after routing to meet density rules. This is typically automated by the fill tool (Calibre Fill, ICV Fill, or in-tool fill generators).

### Other Rule Categories

- **Antenna rules**: Maximum ratio of metal area to gate oxide area (see antenna_effect.md).
- **Via rules**: Via array rules, staggered via requirements, via-under-wire rules.
- **OPC-related rules**: Rules for optical proximity correction compatibility (e.g., jog length, notch width).
- **Multi-patterning rules**: Color-aware spacing rules for LELE/SADP processes (e.g., same-color spacing vs. different-color spacing).
- **ESD rules**: Minimum metal width for ESD discharge paths.
- **Recommended rules**: Non-mandatory rules that improve yield (e.g., recommended via doubling).

## DRC Violation Debugging

### Systematic Debugging Approach

1. **Categorize**: Sort violations by rule type. Address the most common and most critical rules first.
2. **Locate**: Use the DRC results viewer (Calibre RVE, ICV WorkBench, or Innovus/ICC2 built-in DRC browser) to navigate to each violation.
3. **Understand the rule**: Read the foundry design rule manual (DRM) entry for the specific rule being violated. Understand the intent of the rule.
4. **Identify the cause**: Determine whether the violation is caused by placement, routing, via insertion, metal fill, or cell-level issues.
5. **Fix**: Apply the appropriate fix (reroute, move cell, adjust via, remove fill, etc.).

### Common Causes and Fixes

| Cause | Typical Rules Violated | Fix |
|---|---|---|
| Routing congestion | Spacing, short | Reroute with more resources or spread placement |
| Cell abutment | Spacing, enclosure | Adjust placement, add filler cells |
| Via location | Enclosure, spacing | Re-drop via or use alternate via definition |
| Metal fill | Spacing, density | Re-run fill with updated rules or remove offending fill |
| Macro placement | Spacing, well | Adjust macro-to-macro spacing, add keepout |
| Power grid | Width, spacing, EM-related | Adjust strap width/spacing in PG script |

### Tool Commands for DRC

```tcl
# Synopsys ICC2/Fusion Compiler:
check_drc
report_drc -file drc_report.rpt

# Cadence Innovus:
verify_drc
verifyGeometry

# Siemens Calibre (standalone):
calibre -drc -hier runset_file
```

## DRC Waivers

In practice, achieving zero DRC violations is the goal, but sometimes certain violations cannot be fixed without unacceptable impact on timing, area, or power. In these cases, DRC waivers may be granted.

### Waiver Process

1. **Document the violation**: Exact location, rule number, geometry involved, measured vs. required value.
2. **Justify**: Explain why the violation cannot be fixed and the expected impact on yield.
3. **Risk assessment**: Foundry FAE evaluates the yield risk.
4. **Formal approval**: The waiver must be documented and approved by both the design team lead and the foundry.
5. **Waiver file**: A waiver file (e.g., Calibre waiver file) is created so that the violation is marked as waived in subsequent DRC runs.

### When Waivers Are Appropriate

- Violations in IP blocks provided by third parties (the IP vendor must provide waivers).
- Violations caused by known foundry rule bugs that will be fixed in a rule deck update.
- Marginal violations (within 5% of the limit) that the foundry confirms are yield-safe.
- Violations in non-critical regions (e.g., seal ring, test structures) with foundry approval.

Waivers are NEVER appropriate for fundamental rules like minimum spacing or minimum width on active manufacturing layers.

## Foundry-Specific Rules

Each foundry (TSMC, Samsung, Intel, GlobalFoundries) has its own design rule manual with proprietary rules. Key differences include:

- **Rule numbering**: TSMC uses alphanumeric codes (e.g., M1.S.1), Samsung uses similar but distinct naming.
- **Rule values**: Even at the same node, different foundries have different minimum dimensions.
- **Rule deck format**: TSMC provides Calibre and ICV rule decks; Samsung provides Calibre decks; Intel provides proprietary format.
- **Process options**: Different foundries offer different process options (e.g., extra metal layers, thick metals, MIM caps) that have additional rules.

PD engineers must use the correct rule deck version for their specific process (e.g., TSMC N5, 1P13M_2X1Y1Z1U, version 1.2r3).

## Real vs. Soft DRC

### Real DRC Violations

Real DRC violations represent actual manufacturing risks. They must be fixed or formally waived before tapeout. Examples:
- Metal spacing below minimum
- Via without proper enclosure
- Active region too narrow

### Soft DRC Violations

Soft DRC violations are reported by the foundry rule deck but may not represent immediate manufacturing risks. They include:

- **Recommended rules**: Best practices that improve yield but are not mandatory (e.g., "recommended minimum via enclosure" may be larger than the "required minimum via enclosure").
- **Density advisory**: Density outside the recommended range but within the required range.
- **Pattern recommendations**: Preferred routing patterns that improve lithographic fidelity.

Most teams target zero soft DRC violations as well, since they represent yield improvement opportunities. However, soft DRC violations do not block tapeout.

## DRC in the Physical Design Flow

DRC checking should be performed incrementally throughout the flow, not just at signoff:

1. **Post-floorplan**: Check macro placement, power grid, and boundary rules.
2. **Post-placement**: Check cell placement legality, minimum spacing.
3. **Post-CTS**: Check clock tree routing, shield routing.
4. **Post-route**: Full DRC on signal and power routing.
5. **Post-fill**: Full DRC including metal fill.
6. **Signoff DRC**: Final DRC with the foundry signoff rule deck (Calibre or ICV). This is the golden DRC run.

Running DRC early and often catches problems when they are easy to fix, rather than at signoff when the design is frozen.
