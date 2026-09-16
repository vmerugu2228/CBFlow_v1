# LVS Methodology: Layout vs. Schematic Verification

## Overview

Layout vs. Schematic (LVS) is the physical verification process that confirms the fabricated chip layout correctly implements the intended circuit schematic. LVS compares two netlists: one extracted from the physical layout and one derived from the original design (RTL-synthesized gate-level netlist). Any discrepancy indicates a potential functional failure. LVS clean status is a mandatory tapeout requirement.

## How LVS Works

The LVS process consists of two main phases: extraction and comparison.

### Phase 1: Netlist Extraction

The LVS tool reads the layout (GDS/OASIS) and the technology rule deck, then identifies devices and connectivity.

**Device Recognition**: The tool recognizes transistors, resistors, capacitors, and diodes by identifying specific layer combinations:
- NMOS: Gate poly over N+ active in P-well
- PMOS: Gate poly over P+ active in N-well
- Resistor: Specific resistor ID layer over poly or diffusion
- MIM capacitor: Metal-insulator-metal stack with capacitor ID layer
- Diode: P+ in N-well or N+ in P-well with diode ID layer

**Connectivity Extraction**: The tool traces metal and via connections to build a netlist of interconnected devices. It follows the connectivity from the lowest layer (diffusion/poly) through contacts and vias up through the metal stack to identify how all devices are wired together.

**Extracted Netlist**: The result is a SPICE-like netlist listing every device instance, its terminal connections, and its properties (channel length, channel width, number of fins, etc.).

### Phase 2: Comparison

The extracted netlist is compared against the source (schematic) netlist. The comparison engine:

1. **Identifies corresponding nets and devices** through a matching algorithm.
2. **Checks connectivity**: Are all devices connected in the same way in both netlists?
3. **Checks device properties**: Do device parameters (W/L, number of fins, multiplicity) match?
4. **Reports discrepancies**: Any mismatch is reported as an LVS error.

## LVS Check Types

### Hard Checks

Hard checks are strict pass/fail criteria. Any hard check failure means the layout does not match the schematic.

- **Shorts**: Two nets that should be separate are electrically connected in the layout. Common causes include routing errors, metal bridging, and missing cuts in power grid.
- **Opens**: A net that should be continuous is broken in the layout. Common causes include missing vias, broken metal connections, and gaps in power grid.
- **Missing devices**: A device exists in the schematic but is not found in the layout. Occurs when cells are missing or incorrectly placed.
- **Extra devices**: A device exists in the layout but not in the schematic. Occurs due to parasitic devices, incorrect fill, or stray geometry.
- **Mismatched device count**: The number of devices on a net differs between layout and schematic.
- **Property mismatch**: Device properties (W/L, number of fins) differ between layout and schematic.

### Soft Checks

Soft checks are warnings that do not necessarily indicate a functional error but may represent reliability or yield concerns.

- **Floating nets**: A net that is connected to device terminals but has no external connection (may be intentional for decoupling or test structures).
- **Floating gates**: A transistor gate that has no driving connection. This is almost always an error.
- **Undriven inputs**: Standard cell inputs that are not connected to any signal source.
- **Property tolerance**: Device property mismatch within an acceptable tolerance (e.g., resistor width within 5% of schematic value).

## Comparison Methodology

### Flat vs. Hierarchical LVS

**Flat LVS**: Flattens both the layout and schematic to the transistor level before comparison. Provides the most thorough check but is slow and memory-intensive for large designs.

**Hierarchical LVS**: Preserves the design hierarchy during comparison. Matches cells hierarchically, only flattening when necessary. Much faster and uses less memory. This is the standard approach for multi-million-gate designs.

```
# Calibre hierarchical LVS example:
calibre -lvs -hier -spice extracted.sp -schematic source.v lvs_runset
```

### Cell-by-Cell vs. Top-Level LVS

For designs using foundry-qualified standard cells and hard IP:
- The standard cells are typically **LVS black-boxed**: their internal layout is assumed correct, and only the pin connectivity is verified.
- Hard IP (SRAM, SerDes, PLL) is similarly black-boxed with an abstract netlist.
- Full transistor-level LVS is only run on the top-level integration (routing, power grid, bumps/pads).

This approach significantly reduces runtime while still catching integration errors.

## Device Recognition

Device recognition is the process by which the LVS tool identifies transistors and other devices in the layout.

### Standard Devices

For CMOS processes, the tool identifies:
- **NMOS/PMOS transistors**: Identified by gate poly crossing active diffusion within the appropriate well type. Multi-finger devices are recognized by counting gate stripes.
- **FinFET devices**: At advanced nodes, the tool recognizes fins and counts the number of active fins per device.
- **Resistors**: Identified by resistor body layers (RPDMY, etc.) combined with specific material layers.
- **Capacitors**: MOM (metal-oxide-metal) and MIM capacitors identified by specific layer stacks and ID layers.

### Device Property Extraction

After recognizing devices, the tool extracts properties:
- **Transistors**: Channel length (L), total width (W), number of fins (NFIN), number of fingers (NF).
- **Resistors**: Length, width, number of squares, sheet resistance.
- **Capacitors**: Area, perimeter, capacitance per unit area.

These properties are compared against the schematic values. Any mismatch beyond the allowed tolerance is flagged.

## Short and Open Debugging

### Short Debugging

A short means two nets are unintentionally connected. Debugging steps:

1. **Identify the short pair**: The LVS report lists the two nets that are shorted (e.g., VDD shorted to net_A).
2. **Locate the short**: Use the LVS debug tool (Calibre RVE, ICV) to highlight the geometry causing the short. The tool shows the exact layer and location where the connection occurs.
3. **Common causes**:
   - Metal routing overlap between two different signal nets.
   - Via landing on the wrong metal track.
   - Power strap overlapping with signal routing.
   - Cell pin extending beyond the cell boundary and touching adjacent routing.
4. **Fix**: Reroute the offending net, adjust the power grid, or fix the cell placement.

### Open Debugging

An open means a net is broken (not continuous). Debugging steps:

1. **Identify the open net**: The LVS report identifies the net with missing connectivity.
2. **Trace the net**: Follow the net from source to destination, checking each via and metal connection.
3. **Common causes**:
   - Missing via between metal layers (via dropped during routing).
   - Gap in a metal segment (routing error).
   - Pin connection missing (cell pin not reached by routing).
   - Power grid discontinuity (strap break, missing via array).
4. **Fix**: Add the missing via, repair the metal connection, or re-route the net.

### Debugging Tools and Techniques

```tcl
# Calibre: Use RVE (Results Viewing Environment) for interactive debugging
# Launch from Calibre GUI or command line:
calibre -rve lvs_results.db

# ICV: Use ICValidator results browser
# Synopsys IC Validator integrates with ICC2/FC for in-design LVS debugging
```

Effective LVS debugging requires:
- Ability to cross-probe between the schematic and layout views.
- Understanding of the extraction rules (which layers form devices, which form connections).
- Familiarity with the text report format to quickly identify the root cause class.

## LVS in the Design Flow

### When to Run LVS

- **Post-route (in-design)**: Run a quick LVS using the P&R tool's built-in connectivity checker. This catches gross connectivity errors early.
- **Post-fill**: Metal fill can cause shorts. Re-run LVS after fill insertion.
- **Signoff**: Run full Calibre/ICV LVS with the foundry-certified rule deck. This is the golden LVS run.
- **Post-ECO**: Any ECO change (route fix, cell swap) requires re-running LVS.

### LVS Flow Integration

```
Layout (GDS) ----+
                 |----> LVS Tool ----> PASS/FAIL
Schematic (Verilog/SPICE) --+

If FAIL:
  - Debug errors using results viewer
  - Fix in P&R tool (ECO)
  - Re-export GDS
  - Re-run LVS
  - Iterate until clean
```

### Common Pitfalls

- Not including all IP blocks in the LVS run (missing SRAM GDS, missing analog block).
- Text/label mismatches between layout and schematic (net name case sensitivity, bus notation differences).
- Forgetting to include the substrate/well connections (tap cells must be present).
- Running LVS with an outdated rule deck version.
- Not accounting for cell-internal shorts introduced by metal fill.

LVS is non-negotiable for tapeout. A design that is not LVS clean will not function correctly. PD engineers should run LVS early and often, fixing issues incrementally rather than leaving them to signoff.
