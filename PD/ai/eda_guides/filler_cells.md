# Filler Cells: Well-Taps, Decaps, Fillers, and Endcaps

## Overview

Filler cells are non-functional standard cells inserted into the design to satisfy manufacturing requirements, ensure reliability, and improve performance. While they do not appear in the logical netlist, they are essential for physical design correctness. There are four main categories: well-tap cells (latch-up prevention), decap cells (local decoupling), filler cells (DRC compliance), and endcap cells (boundary protection).

Understanding when, where, and how to insert each type of filler cell is a core PD engineering skill. Incorrect or insufficient filler cell insertion can cause silicon failures that are impossible to fix post-fabrication.

## Well-Tap Cells (Tap Cells)

### Purpose: Latch-Up Prevention

Latch-up is a parasitic thyristor (PNPN) effect in CMOS that can create a low-resistance path between VDD and VSS, causing destructive current flow. Latch-up is triggered by voltage spikes, radiation, or noise. The primary defense is to keep the N-well and P-substrate properly biased by providing low-resistance connections to VDD and VSS, respectively.

Well-tap cells provide these connections. They contain N-well contacts tied to VDD and P-substrate contacts tied to VSS, but no transistors or logic gates.

### Placement Requirements

- **Maximum tap-to-tap distance**: Foundries specify a maximum distance between well taps, typically 30-60 um (varies by process). Every active device must be within this distance of a well tap
- **Checkerboard pattern**: Taps are typically placed in a regular grid pattern. Every N rows offset by half the tap pitch creates a checkerboard pattern ensuring full coverage
- **Pre-placement**: Well taps are inserted after floorplanning but before standard cell placement, so the placer can work around them
- **Abutment**: Taps must abut neighboring standard cells on both sides (no gaps)

### Insertion Strategy

```
Typical tap placement command (Innovus):
  addWellTap -cell TAPCELLFILLER -cellInterval 30 -checkerBoard
```

Key parameters:
- Cell interval: distance between taps in each row (e.g., 30 um)
- Checkerboard: alternates offset between even/odd rows
- Tap cell name from the standard cell library

### Verification

- After placement, verify that no standard cell is farther than the maximum allowed distance from a well tap
- DRC rule decks include latch-up distance checks
- In SOI technologies (like GF 22FDX), latch-up is inherently prevented by the BOX layer, so well-tap requirements are relaxed

## Decap Cells (Decoupling Capacitor Cells)

### Purpose: Local Power Supply Decoupling

When large groups of transistors switch simultaneously, they draw a sudden spike of current from the local power supply. The inductance in the power delivery network prevents instantaneous current delivery, causing a transient voltage droop (dynamic IR drop). Decoupling capacitors provide a local reservoir of charge that supplies current during these transients.

Decap cells are standard cells that contain large MOS capacitors (thin-oxide gates) connected between VDD and VSS. They store charge locally and release it during switching events.

### Capacitance per Cell

Decap cells come in different sizes (widths), with capacitance proportional to cell width:
- Small decap (1x width): ~10-20 fF
- Medium decap (4x width): ~40-80 fF
- Large decap (8x width): ~80-160 fF

Total on-die decap in a large SoC can range from 10-100 nF, supplementing off-die package capacitors.

### Placement Strategy

- **Near high-activity regions**: Place decaps near blocks with high switching activity (clock buffers, data buses, arithmetic units)
- **Fill empty space**: Use decap cells to fill whitespace that would otherwise require plain filler cells. This provides capacitance at zero area cost
- **Distribution**: Spread decaps uniformly across the die for baseline decoupling, then add extra concentration near hotspots
- **Post-route insertion**: After routing is complete, fill remaining gaps with decaps before plain fillers

### Leakage Consideration

Decap cells use thin-oxide MOS capacitors, which contribute gate leakage current. In low-power designs:
- Limit total decap cell area to control leakage
- Use thick-oxide decap variants where available (less leakage but lower capacitance density)
- In power-gated domains, decap cells are disconnected during sleep, so leakage is not a concern during shutdown
- Balance decap benefit (reduced dynamic IR drop) against leakage cost

### Verification

- Run dynamic IR drop analysis with and without decap cells to quantify benefit
- Monitor total decap cell leakage contribution in power reports
- Verify that decap cells do not create DRC issues (N-well spacing, etc.)

## Filler Cells (Physical Fill)

### Purpose: DRC Compliance and Continuity

Standard cells have continuous N-well and implant layers that must extend without gaps across the cell row. When there are spaces between placed cells (due to placement density < 100%), filler cells fill these gaps to ensure:

1. **N-well continuity**: N-well must be continuous across the row. Gaps in N-well violate DRC rules
2. **Implant continuity**: NWELL, PPLUS, NPLUS implant layers must not have gaps
3. **Poly continuity**: Some processes require continuous dummy poly patterns (CPO rules)
4. **Metal fill base**: Filler cells provide M1 power rail continuity

### Filler Cell Sizes

Libraries provide filler cells in various widths to fill any gap:
- Minimum-width filler (1 CPP or 1 site width)
- 2x, 4x, 8x, 16x width fillers
- The insertion algorithm fills large gaps with large fillers and small gaps with small fillers

### Insertion

Filler cells are inserted as the last step before DRC signoff:
```
Typical filler insertion command (Innovus):
  addFiller -cell {FILLER64 FILLER32 FILLER16 FILLER8 FILLER4 FILLER2 FILLER1} -prefix FILLER
```

The tool fills from largest to smallest, ensuring complete coverage with minimal cell count.

### Priority Order

The recommended insertion order is:
1. Well-tap cells (placed during floorplanning/pre-placement)
2. Decap cells (fill whitespace with useful capacitance)
3. Plain filler cells (fill remaining gaps for DRC compliance)

## Endcap Cells

### Purpose: Row-End Protection

Endcap cells are placed at the beginning and end of each standard cell row to protect the row boundary. They serve several purposes:

1. **Well-tie at boundaries**: Provide N-well and P-substrate contacts at row edges where no neighboring cell exists
2. **Dummy poly**: Add dummy poly gates at row boundaries to maintain uniform poly density and prevent lithographic edge effects
3. **OD (oxide diffusion) termination**: Properly terminate the active area at row edges
4. **Metal termination**: Ensure M1 power rails are properly terminated

### Types of Endcap Cells

- **Left endcap**: Placed at the left edge of each row
- **Right endcap**: Placed at the right edge of each row
- **Top endcap**: Placed at the top boundary of the placement region
- **Bottom endcap**: Placed at the bottom boundary
- **Corner endcap**: Special cells for the four corners of the placement region

### Placement

Endcaps are placed automatically by the PnR tool at boundary detection:
```
Typical endcap insertion (Innovus):
  setEndCapMode -leftEdge ENDCAP_L -rightEdge ENDCAP_R \
    -topEdge ENDCAP_T -bottomEdge ENDCAP_B \
    -leftTopCorner ENDCAP_LT -rightTopCorner ENDCAP_RT \
    -leftBottomCorner ENDCAP_LB -rightBottomCorner ENDCAP_RB
  addEndCap
```

### Where Endcaps are Needed

- At the left and right edges of each standard cell row
- Adjacent to hard macros (the row terminates next to macro halo)
- At power domain boundaries where rows are split
- Around routing blockages that terminate cell rows
- At the boundary of placement regions created by rectilinear die shapes

## Practical Workflow

### Insertion Sequence in a Typical PD Flow

1. **After floorplanning**: Insert well-tap cells with proper spacing
2. **After power grid creation**: Verify taps do not conflict with power stripes
3. **After placement**: Verify tap coverage and add supplemental taps if needed
4. **After CTS and route**: Insert decap cells in remaining whitespace
5. **After optimization**: Insert plain filler cells to fill all remaining gaps
6. **Final step**: Insert endcap cells at all row boundaries

### Common Issues

- **Missing fillers**: Any gap without a filler cell causes DRC violations (N-well, implant discontinuity)
- **Filler library mismatch**: The filler cell site height and width granularity must match the standard cell library
- **Tap spacing violations**: After ECO changes or incremental placement, verify tap coverage is still valid
- **Decap leakage**: Over-using decap cells in low-power designs can blow the leakage budget
- **Endcap conflicts**: When macros or blockages create irregular row boundaries, endcap placement can be tricky. Manual fixes may be needed

### Verification Checklist

- [ ] All cell rows have continuous N-well (no gaps)
- [ ] Well-tap spacing meets foundry requirement everywhere
- [ ] All row ends have appropriate endcap cells
- [ ] Decap cell count and distribution are reasonable
- [ ] Total filler cell leakage is within budget
- [ ] DRC clean after filler insertion
- [ ] No filler cells overlap with placed instances or routing
