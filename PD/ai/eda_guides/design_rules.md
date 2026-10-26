# Design Rules for Physical Design Engineers

## Overview

Design rules are the fundamental geometric constraints that govern how shapes can be drawn on each mask layer in an integrated circuit. They are derived from the manufacturing process capabilities and ensure that fabricated devices and interconnects function correctly with acceptable yield. Every physical design engineer must deeply understand design rules because violations (DRC errors) block tapeout.

Design rules fall into several categories: minimum width, minimum spacing, enclosure/overlap, density, and technology-specific rules such as double patterning and cut metal rules at advanced nodes.

## Metal Pitch, Spacing, and Width

### Minimum Width

Every metal and via layer has a minimum width rule. The minimum width is the smallest dimension that the lithography and etch process can reliably produce. For example, at 28nm TSMC, M1 minimum width is typically 0.056 um. At lower metals (M1-M3), minimum widths are tighter than at upper metals (M5-M8) because lower metals use finer lithography.

Key considerations:
- Signal routes generally use minimum-width wires for density
- Power routes use wider wires to reduce resistance and meet EM constraints
- Clock routes may use non-default rules (NDR) with 2x or 3x minimum width for reduced resistance and improved shielding

### Minimum Spacing

Spacing rules define the minimum distance between two shapes on the same layer. Spacing rules can be complex:

- **Same-net spacing**: Often relaxed compared to different-net spacing
- **Width-dependent spacing**: Wider wires require larger spacing to neighboring wires. This is expressed as a spacing table indexed by width
- **Parallel-run-length spacing**: When two wires run parallel for a long distance, spacing must increase. Longer parallel runs create more capacitive coupling and increase crosstalk risk
- **End-of-line (EOL) spacing**: The end of a wire has special spacing requirements to adjacent wires, often more restrictive than side-to-side spacing
- **Corner-to-corner spacing**: Diagonal distance between wire corners may have specific rules

### Metal Pitch

Metal pitch is the minimum center-to-center distance between two adjacent wires on the same layer. Pitch = minimum width + minimum spacing. Metal pitch is the single most important parameter defining routing density. For example:
- TSMC N7: M1 pitch = 36nm, M2 pitch = 36nm
- TSMC N5: M1 pitch = 28nm, M2 pitch = 28nm
- TSMC N3: M1 pitch = 22nm

Routing track density directly follows from pitch: tracks per micron = 1000 / pitch(nm).

## Via Rules

Vias connect adjacent metal layers. Via rules include:

- **Minimum via size**: The minimum dimensions of the via cut (e.g., 0.050 x 0.050 um)
- **Via spacing**: Minimum distance between two via cuts on the same via layer
- **Via enclosure**: The minimum overlap of the metal layer over the via cut on each side. Enclosure rules often differ by direction (X vs Y) and can depend on whether the via is at the end of a line or in the middle
- **Via array rules**: When multiple vias are placed together (for lower resistance), there are specific array spacing rules and enclosure requirements
- **Stacked via rules**: Restrictions on placing vias directly on top of each other across multiple layers

Multi-cut vias (via arrays) are strongly preferred over single-cut vias for reliability. Most design flows insert multi-cut vias wherever space permits during optimization.

## Enclosure Rules

Enclosure (or overlap) rules specify how much one layer must extend beyond another. Common examples:

- Metal enclosure of via: Metal must extend beyond the via cut by a minimum distance on all sides
- Contact enclosure by metal and by diffusion/poly
- Well enclosure of active area
- Implant layer enclosure of active

Enclosure rules ensure that even with mask misalignment during fabrication, the intended overlap still exists.

## Density Rules

Foundries impose both minimum and maximum density requirements on metal and poly layers:

- **Minimum density**: Typically 20-30% for metal layers. Prevents dishing during CMP (Chemical Mechanical Polishing). Metal fill (dummy metal) is added to meet minimum density
- **Maximum density**: Typically 70-80% for metal layers. Prevents excessive topography variation
- **Density window**: Density is checked in sliding windows (e.g., 50x50 um with 25 um step). Both local and global density must be within bounds
- **Density gradient**: The density difference between adjacent windows must be below a threshold to ensure uniform CMP polishing

Density violations are fixed during chip finishing by adding metal fill shapes in empty areas.

## Double Patterning Rules

At 20nm and below (for certain layers), a single lithography exposure cannot resolve features at the required pitch. Double patterning splits one mask layer into two separate masks (colors), each printed with a separate exposure.

### LELE (Litho-Etch-Litho-Etch)

Each mask is exposed and etched separately. The router must ensure that no two shapes on the same mask violate minimum spacing. This introduces coloring constraints:

- **Same-color spacing**: Shapes on the same mask must be spaced at least 2x the minimum pitch apart
- **Coloring conflicts**: Odd cycles in the spacing graph where three mutually close shapes cannot be split into two colors
- **Stitch rules**: A single shape may be split across two masks with a stitch (overlap region), but stitches cause yield loss and are minimized

### SADP (Self-Aligned Double Patterning)

Uses a mandrel and spacer process. The mandrel defines one set of features; spacers on its sidewalls define the second set. SADP imposes strict grid-based routing: wires must be on-grid or off-grid following specific patterns. Tip-to-tip and tip-to-side rules become critical.

## Cut Rules (Advanced Nodes)

At 7nm and below, metal lines are often manufactured as continuous lines that are then "cut" to create separate segments. Cut metal rules include:

- **Minimum cut spacing**: Distance between two cuts on the same track
- **Cut-to-wire-end spacing**: Distance from a cut to the nearest wire end on an adjacent track
- **Cut enclosure**: How much the cut must be enclosed within the metal line

Cut rules significantly impact routing, especially at line ends and jogs. Routers must be cut-aware to avoid DRC violations.

## Practical Implications for PD Engineers

1. **LEF/Tech LEF accuracy**: All design rules must be correctly captured in the technology LEF. Incorrect rules cause DRC violations that appear only in signoff
2. **NDR for critical nets**: Non-default rules (wider width, larger spacing) improve signal integrity for clocks and critical signals but consume more routing resources
3. **Via optimization**: Always prefer multi-cut vias. Check via enclosure carefully at jogs and bends
4. **Metal fill strategy**: Plan for density requirements early. Timing-aware fill avoids coupling to critical nets
5. **DRC rule deck vs. PnR rules**: The PnR tool uses simplified rules. Always run foundry DRC (Calibre/Pegasus) for signoff
6. **Process antenna rules**: Metal shapes connected to gates must not exceed antenna ratio limits. Antenna diodes or routing changes fix violations

## Rule Deck Versions

Always verify you are using the correct rule deck version matching the PDK version. Foundries regularly update design rules, and mismatched versions cause false DRC errors or, worse, missed real violations. Track the rule deck version in your project configuration and validate it during setup.

Understanding design rules deeply is what separates a productive PD engineer from one who spends weeks chasing DRC violations. Invest time in reading the foundry design rule manual for your target process -- it is the single most important reference document for physical design.
