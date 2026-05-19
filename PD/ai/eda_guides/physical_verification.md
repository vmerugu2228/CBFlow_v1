# Physical Verification Fundamentals

## Overview

Physical verification is the final gatekeeping step before a design is sent to the foundry for fabrication. It ensures that the layout (GDSII/OASIS) complies with all manufacturing rules and correctly implements the intended circuit. The three pillars of physical verification are Design Rule Checking (DRC), Layout vs. Schematic (LVS), and Electrical Rule Checking (ERC). A single missed violation can result in a non-functional chip or yield loss, making physical verification one of the most critical steps in the tapeout flow.

## Design Rule Checking (DRC)

### What DRC Checks

DRC verifies that all geometric shapes in the layout comply with the foundry's manufacturing design rules. These rules encode the physical limitations of the fabrication process.

### Common DRC Rule Categories

**Width rules:**
- Minimum width per metal layer
- Minimum width for specific via landing pads
- Minimum poly gate width

**Spacing rules:**
- Minimum spacing between same-layer shapes
- Minimum spacing between different nets (more restrictive than same-net)
- Spacing rules dependent on wire width (wide metal rules)
- End-of-line (EOL) spacing rules

**Enclosure rules:**
- Via enclosure by metal (minimum overlap)
- Contact enclosure by diffusion/poly
- Implant enclosure of active region

**Area rules:**
- Minimum metal area
- Minimum hole area (enclosed space within a metal shape)
- Maximum metal area (antenna-related)

**Density rules:**
- Minimum and maximum metal density per layer (typically 20-80%)
- Density uniformity (density variance across the chip must be within bounds)
- Via density requirements

**Advanced node rules (7nm and below):**
- Multi-patterning (double/triple patterning) coloring rules
- Cut metal rules (BEOL patterning)
- Self-aligned via rules
- Tip-to-tip spacing
- Minimum jog length

### DRC Debug Workflow

1. Run DRC and generate violation database.
2. Open violation database in the DRC viewer (RVE for Calibre, ICV Workbench for ICV).
3. Sort violations by rule — fix systematic violations first.
4. For each violation type:
   - Understand the rule (read the rule deck documentation)
   - Identify the root cause (placement, routing, or PG issue)
   - Apply the fix (usually in the PnR tool, then re-export GDSII)
5. Re-run DRC to verify fixes and check for new violations introduced.

### Common DRC Violations and Fixes

| Violation | Typical Cause | Fix |
|-----------|--------------|-----|
| Metal spacing | Congested routing | Increase routing spacing, reduce utilization |
| Via enclosure | Tight pin access | Adjust via rules, widen landing pads |
| Min area | Short wire stubs | Extend wires, remove unnecessary jogs |
| Density (low) | Sparse metal regions | Insert metal fill |
| Density (high) | Congested area | Reduce fill, spread routing |
| EOL spacing | Wire endpoints too close | Extend wires, increase spacing |
| Antenna | Long lower-metal routes to gates | Insert diodes, reroute to higher layers |

## Layout vs. Schematic (LVS)

### What LVS Checks

LVS verifies that the physical layout correctly implements the intended circuit (netlist). It extracts a circuit from the layout geometry and compares it against the source netlist (gate-level Verilog or schematic).

### LVS Extraction Process

1. **Device recognition:** Identify transistors, resistors, capacitors, and diodes from geometric shapes and layer intersections.
2. **Net extraction:** Trace connectivity through metal, via, and contact layers to form nets.
3. **Sub-circuit formation:** Group devices into cells that match library cell definitions.
4. **Hierarchy processing:** Build hierarchical netlist from extracted devices and connectivity.

### LVS Comparison

The extracted layout netlist is compared against the source netlist:

- **Device match:** Same number and type of devices
- **Net match:** Same connectivity between devices
- **Parameter match:** Device parameters (W/L for transistors) within tolerance

### LVS Result Categories

| Result | Meaning |
|--------|---------|
| CLEAN | Layout matches netlist — ready for tapeout |
| INCORRECT | Mismatches found — must debug and fix |

### Common LVS Errors

**Opens:**
- Missing via or contact connection
- Broken wire (gap in metal)
- Missing power/ground connection

**Shorts:**
- Two different nets connected by a stray metal shape
- Via landing on wrong net
- Fill metal shorting to a signal net

**Device mismatches:**
- Extra devices in layout (e.g., antenna diodes not in netlist)
- Missing devices (e.g., filler cells with active devices)
- Wrong device parameters (W/L mismatch)

**Port/pin mismatches:**
- Port names don't match between layout and netlist
- Missing port labels
- Extra ports due to power connections

### LVS Debug Workflow

1. Review the LVS comparison report.
2. Start with the highest-level mismatches (e.g., missing sub-circuit).
3. For shorts: trace the connectivity in the layout viewer to find the offending geometry.
4. For opens: verify via connections, look for missing vias or broken wires.
5. Fix in the PnR tool (preferred) or with manual geometry edits (last resort).
6. Re-run LVS to verify.

## Electrical Rule Checking (ERC)

### What ERC Checks

ERC verifies electrical correctness beyond geometric DRC:

- **Floating gates:** Gate connections not driven by any source
- **Floating wells/substrates:** N-well or P-substrate regions without proper bias connections
- **Missing well taps:** Body contacts not placed frequently enough
- **Antenna violations:** Metal antenna ratios exceeding gate oxide tolerance
- **ESD protection:** Verify ESD diodes are present on I/O pads

### Well Tap Requirements

Modern processes require well taps (body contacts) within a maximum distance from every transistor to prevent latch-up:

```
Maximum distance from any transistor to nearest well tap: typically 15-25 um
```

```tcl
# In PnR tool: insert well taps
addWellTap -cell WELLTIEPWCELL -cellInterval 20 -prefix WELLTAP
```

## Waiving Violations

Some DRC/LVS violations may be intentionally accepted (waived) based on engineering judgment:

- **Known good violations:** Rule violations in IP blocks that have been silicon-proven.
- **Foundry-approved waivers:** Violations approved by the foundry for specific use cases.
- **Risk-accepted violations:** Violations in non-critical areas where the risk is understood and accepted.

### Waiver Best Practices

1. Document every waiver with: violation type, location, justification, approver.
2. Get foundry sign-off for any waiver on a critical DRC rule.
3. Track waivers in a formal database — never rely on ad-hoc lists.
4. Review all waivers before each tapeout milestone.
5. Minimize waivers — fix violations whenever possible rather than waiving.

## Signoff Criteria

### DRC Signoff

- Zero violations on all mandatory rules
- All density rules met (or foundry-approved waivers)
- Antenna check clean
- Multi-patterning (if applicable) color-conflict free

### LVS Signoff

- Clean LVS comparison (zero mismatches)
- All ports matched
- All devices matched with correct parameters

### ERC Signoff

- No floating gates
- No floating wells
- Well tap spacing met everywhere
- Antenna ratios within limits

### Metal Fill Signoff

- All layers meet minimum and maximum density requirements
- Density uniformity within specification
- Fill does not cause timing/SI degradation beyond acceptable limits

## Common Issues and Fixes

**Issue: Thousands of DRC violations after routing**
- Check for systematic issues (one rule violated everywhere vs. scattered violations).
- Review PnR tool DRC vs. signoff DRC — discrepancies indicate rule deck mismatch.
- Ensure the PnR tool's DRC engine is calibrated to the signoff rule deck.
- Common root cause: PnR tool using an older/simplified rule set.

**Issue: LVS short caused by metal fill**
- Verify fill insertion rules prevent fill from connecting to signal nets.
- Use grounded fill (connected to VDD/VSS) instead of floating fill.
- Add fill blockages around critical signal nets.

**Issue: LVS open on power grid**
- Check via stacking between power grid layers.
- Verify that all PG via insertions are complete.
- Run `verify_pg_connectivity` in the PnR tool before LVS.

**Issue: Antenna violations persist after repair**
- Increase the number of antenna diode cells available.
- Allow the router to use higher metal layers for antenna-prone nets.
- Manually insert diodes at problematic gates.

**Issue: Density violations in sparse regions**
- Run metal fill insertion with correct density targets.
- Check fill rules — some cell types (e.g., SRAM, analog) have special fill requirements.
- Ensure fill is generated for all metal layers.

## Best Practices

1. **Run DRC and LVS early and often** — do not wait until the end of the flow to discover violations.
2. **Calibrate PnR DRC with signoff DRC** — run a comparison early in the project to identify rule gaps.
3. **Fix violations in the PnR tool** whenever possible — manual GDS edits are error-prone and not reproducible.
4. **Use hierarchical verification** for large designs — flat DRC/LVS on 50M+ instance designs is impractical.
5. **Automate the verification flow** — script DRC/LVS/ERC to run as part of the tapeout checklist.
6. **Version-control rule decks** — track which rule deck version was used for each verification run.
7. **Run metal fill before final DRC** — density violations are DRC violations.
8. **Maintain a violation trend chart** — track DRC count over time to ensure convergence.
9. **Never waive a violation without documentation** — undocumented waivers are ticking time bombs.
10. **Cross-reference DRC results across tools** — run both Calibre and ICV (or at least spot-check) to catch tool-specific blind spots.
