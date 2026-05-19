# Manufacturing Signoff: Tapeout Preparation and Foundry Handoff

## Overview

Manufacturing signoff (tapeout) is the culmination of the physical design process. It is the point at which the design data is finalized and delivered to the semiconductor foundry for mask fabrication. Tapeout is irreversible and expensive; mask sets at advanced nodes cost $5-15M. Every error that escapes to tapeout results in a costly mask respin. PD engineers must execute a rigorous signoff checklist covering DRC, LVS, ERC, antenna compliance, density verification, GDS preparation, and foundry-specific requirements.

## Final DRC Clean

DRC clean status means zero violations against the foundry's signoff rule deck.

### DRC Signoff Requirements

1. **Signoff tool and version**: Use the foundry-specified tool version (e.g., Calibre 2024.1.2, ICV T-2024.03). Different tool versions may interpret rules differently.
2. **Signoff rule deck version**: Use the exact rule deck version specified by the foundry for your process variant. Rule decks are updated regularly; using an outdated version can result in missing new rules.
3. **All layers**: DRC must cover all layers, including those added during fill, frame generation, and IP integration.
4. **Hierarchical vs. flat**: Foundries typically accept hierarchical DRC clean. Flat DRC is run on specific areas of concern.

### Final DRC Flow

```bash
# Calibre DRC signoff run:
calibre -drc -hier -turbo 8 \
    -layout final_chip.gds \
    -rule foundry_drc_rules_v1.2 \
    > drc_signoff.log 2>&1

# Verify zero errors:
grep "TOTAL DRC Results Generated" drc_signoff.log
# Expected: TOTAL DRC Results Generated = 0
```

### Managing DRC Waivers

If any violations cannot be fixed:
- Document each violation with location, rule, and measured vs. required value.
- Obtain written foundry approval for each waiver.
- Create a waiver file for the DRC tool so waived violations are excluded from the count.
- Include the waiver documentation in the tapeout package.

## Final LVS Clean

LVS verifies that the layout netlist matches the schematic netlist (see lvs_methodology.md for details).

### LVS Signoff Requirements

- Zero shorts, opens, and device mismatches.
- All IP blocks included (SRAM, PLL, analog IP, I/O cells).
- Correct text/label conventions matching the foundry's extraction rules.
- Property checking enabled (device W/L, fin count, etc.).

### Post-Merge LVS

The final LVS must be run on the **merged** GDS (after all IP integration, fill, and frame merging), not on intermediate data. A common mistake is running LVS on the P&R output but not re-running after GDS merge operations.

## Final ERC Clean

ERC checks for electrical correctness beyond connectivity (see erc_methodology.md).

### ERC Signoff Items

- No floating gates.
- All wells properly connected (well tap spacing within limits).
- ESD protection paths verified for all I/O pads.
- Power domain connectivity verified for multi-voltage designs.
- No undriven or unconnected standard cell inputs.

## Antenna Clean

Antenna compliance ensures no process-induced damage to gate oxide during manufacturing.

### Antenna Signoff

- Zero antenna violations on all metal and via layers.
- Antenna diodes properly connected (verified by LVS).
- Post-ECO antenna re-verification completed.
- Antenna checking includes both partial and cumulative area ratios.

## Density Compliance

Metal and via density must meet foundry requirements for CMP uniformity and process stability.

### Density Verification

1. **Metal density**: Each metal layer must meet minimum (typically 20-30%) and maximum (typically 70-80%) density requirements in specified window sizes.
2. **Via density**: Via layers have density requirements (usually minimum only).
3. **Poly/active density**: Front-end layers may have density requirements.
4. **Density gradient**: The density difference between adjacent windows must be within limits.
5. **Global density**: Overall chip density must fall within the specified range.

### Density Fix Flow

```
1. Run initial density analysis on routed design
2. Insert metal fill to meet minimum density
3. Re-run DRC (fill may cause spacing violations)
4. Fix fill-related DRC violations (remove or resize offending fill)
5. Re-run density analysis to confirm compliance
6. Re-run LVS to confirm fill didn't create shorts
7. Iterate if needed
```

### Fill Considerations

- **Timing impact**: Dense fill near critical signal routes increases coupling capacitance. Re-extract and re-run timing after fill insertion.
- **EM impact**: Fill does not carry current but increases local temperature due to reduced thermal via effectiveness.
- **Fill types**: Floating fill (unconnected), grounded fill (connected to VSS), or cheesed fill (perforated patterns). Each has different DRC implications.

## GDS Merge

The final GDS file is created by merging all design components.

### Merge Inputs

- Top-level routing GDS (from P&R tool export).
- Standard cell GDS library.
- Memory macro GDS (SRAM, ROM, register files).
- Analog/mixed-signal IP GDS (PLL, ADC, DAC, SerDes).
- I/O cell GDS.
- Metal fill GDS.
- Seal ring / die frame GDS.
- Pad/bump/RDL GDS.

### Merge Verification

After merge:
1. Verify cell count matches expectations.
2. Verify all expected layers are present.
3. Verify die size matches specification.
4. Run final DRC/LVS on the merged GDS.
5. Generate and verify checksums.

## Foundry Checklist

Each foundry provides a specific tapeout checklist. Common items across foundries include:

### Design Information

- Design name and revision number.
- Process node and metal stack option (e.g., TSMC N5, 1P13M_2X1Y1Z1U).
- Die size (width x height in micrometers).
- Total metal layer count.
- Special process options used (e.g., MIM cap, thick oxide, ESD option).

### Verification Reports

- DRC clean report (zero violations or documented waivers).
- LVS clean report (CORRECT status).
- ERC clean report.
- Antenna clean report.
- Density report showing compliance for all layers.
- EM signoff report (within current density limits).

### Data Files

- GDS/OASIS file with checksum.
- Layer mapping file.
- Cell list (all cells in hierarchy).
- Bump/pad coordinates (for flip-chip or wire-bond).
- Die ID and lot tracking marks.
- Alignment mark coordinates.

### Legal and Administrative

- Signed foundry NDA and purchase order.
- Wafer quantity and lot priority.
- Contact information for engineering questions.
- Shipping address for test wafers.

## Frame Generation

The die frame (also called seal ring or scribe structure) is the boundary structure around the die that provides:

- **Seal ring**: A continuous metal ring around the die perimeter that prevents moisture and contaminant ingress after die singulation.
- **Crack stop**: A structure that arrests crack propagation from the scribe lane.
- **Scribe line structures**: Alignment marks, process monitors, and die ID in the space between dies.
- **Corner cells**: Special structures at the die corners where the seal ring turns.

### Frame Implementation

- Foundries provide parameterizable frame generators or pre-built frame GDS.
- The frame must be sized to match the die dimensions.
- The seal ring must be continuous (no breaks) and connected to ground.
- The frame occupies the outermost 10-50um of the die edge.

## Final Signoff Sequence

The recommended sequence for final signoff:

```
1. Freeze the design (no more ECO changes)
2. Export GDS from P&R tool
3. Run metal fill insertion
4. Re-run DRC on filled design
5. Fix any fill-related DRC violations
6. Re-run LVS on filled design
7. Run antenna check
8. Run density check
9. Run ERC
10. Merge all GDS components (IP, fill, frame)
11. Run final DRC on merged GDS
12. Run final LVS on merged GDS
13. Run final antenna check on merged GDS
14. Generate checksums
15. Prepare tapeout package per foundry checklist
16. Internal review (management sign-off)
17. Upload to foundry portal
18. Foundry acknowledgment and DRC verification
```

## Common Tapeout Failures

- Missing IP GDS in the merge (causes LVS opens).
- Wrong rule deck version (new rules not checked).
- Incorrect layer mapping (layers swapped or missing).
- Text labels on wrong layer (LVS cannot match pin names).
- Seal ring break (moisture ingress, reliability failure).
- Density violation in a small region (fill tool missed a window).
- Stale data (GDS exported before the last ECO was applied).
- Checksum mismatch (data corruption during transfer).

## Best Practices

- Start tapeout preparation 2-4 weeks before the target date.
- Run the full signoff suite at least twice: once as a dry run and once as the final run.
- Maintain a version-controlled tapeout log documenting every step, tool version, and result.
- Have a second engineer independently verify the final GDS (four-eyes principle).
- Never modify the GDS after final signoff. If a change is needed, re-run the entire signoff.
- Keep the pre-tapeout GDS and all verification reports archived indefinitely.

Tapeout is the highest-stakes milestone in physical design. Meticulous execution of the manufacturing signoff checklist is the difference between first-silicon success and a multi-million-dollar mask respin.
