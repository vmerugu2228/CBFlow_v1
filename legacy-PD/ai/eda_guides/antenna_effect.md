# Antenna Effect: Plasma Charging, Antenna Rules, and Manufacturing-Aware Routing

## Overview

The antenna effect (also called plasma-induced gate oxide damage, process antenna effect, or charge damage) is a manufacturing reliability issue where electrical charge accumulates on metal interconnects during plasma-based fabrication steps (etching, deposition, ashing). This accumulated charge creates a voltage potential across the thin gate oxide of connected transistors. If the voltage exceeds the oxide breakdown threshold, it causes damage ranging from threshold voltage shifts to permanent dielectric breakdown. The antenna effect is one of the most common DRC violations in physical design and must be addressed during routing and signoff.

The name "antenna" comes from the observation that long metal wires act like antennas that collect charge from the plasma during processing. The longer the wire, the more charge it collects, and the higher the voltage across connected gate oxides.

---

## Physics of the Antenna Effect

### Plasma Processing in IC Fabrication

Modern IC fabrication uses plasma processes extensively:

1. **Reactive Ion Etching (RIE)**: Plasma ions bombard the wafer surface to etch patterns in metal, oxide, and polysilicon layers. Ions carry positive charge; electrons in the plasma provide some neutralization, but there is a net positive charge imbalance at the wafer surface.

2. **Chemical Vapor Deposition (CVD)**: Plasma-enhanced CVD (PECVD) uses plasma to deposit dielectric films. The plasma creates charge accumulation on exposed conductors.

3. **Photoresist Ashing**: Oxygen plasma removes photoresist after patterning, creating charge on exposed metal surfaces.

4. **Ion Implantation**: While not plasma-based, ion implantation can also cause charge accumulation on connected conductors.

### Charge Accumulation Mechanism

During plasma etching of a metal layer:

1. The metal pattern is being defined by etching. As the etch progresses, metal features become isolated conductors.
2. Plasma ions (positive charge) and electrons bombard the surface. Due to the directional nature of RIE, ions reach the wafer surface more efficiently than electrons, creating a net positive charge on metal features.
3. The charge on a metal feature is proportional to its exposed area (the area of metal on that layer that is being etched).
4. This charge must discharge somewhere. If the metal feature is connected (through lower metal layers and vias) to a gate oxide, the charge discharges through the oxide.
5. The voltage across the oxide is V = Q/C_ox, where Q is the accumulated charge and C_ox is the gate oxide capacitance.
6. If V exceeds the oxide's damage threshold (~10-15V for thick oxide, ~5-8V for thin oxide at advanced nodes), damage occurs.

### Damage Mechanisms

- **Fowler-Nordheim tunneling**: At moderate voltages, electrons tunnel through the oxide, causing trapped charge that shifts the transistor's threshold voltage. This is a soft failure — the transistor still works but with different characteristics.
- **Hot carrier injection**: Accelerated carriers cause interface state generation at the Si/SiO2 boundary, degrading mobility and threshold voltage.
- **Oxide breakdown**: At high voltages, the oxide ruptures, creating a permanent conductive path. This is a hard failure — the transistor is destroyed.
- **Latent damage**: Even if the oxide survives fabrication, charge-induced trap sites reduce the oxide's reliability lifetime (accelerated TDDB).

---

## Antenna Ratios and Rules

### Antenna Ratio Definition

The antenna ratio quantifies the risk of antenna damage. It is the ratio of the charging area (metal area exposed to plasma) to the sensitive area (gate oxide area of connected transistors).

**Process Antenna Ratio (PAR):**
```
PAR = (Metal area on layer N connected to gate) / (Gate oxide area)
```

**Cumulative Antenna Ratio (CAR):**
```
CAR = (Total metal area on all layers up to N connected to gate) / (Gate oxide area)
```

**Differential Antenna Ratio (DAR):**
```
DAR = PAR(layer N) - PAR(layer N-1)
```
DAR isolates the contribution of a single layer, useful for identifying which layer causes the violation.

### Side-Wall Antenna Ratio

Some foundries also specify a side-wall antenna ratio based on the perimeter (not area) of the metal:

```
Side-wall PAR = (Metal perimeter on layer N) / (Gate oxide area)
```

The side-wall ratio matters because charge collection depends on both the top surface area and the side-wall area of the metal feature. At advanced nodes where metal features are tall and narrow, the side-wall contribution dominates.

### Foundry Antenna Rules

Foundry design rule manuals specify antenna ratio limits per layer. These vary by process technology and layer:

| Layer | Typical PAR Limit | Typical CAR Limit | Notes |
|-------|-------------------|-------------------|-------|
| Poly | 200:1 | 200:1 | Most sensitive (thinnest oxide) |
| M1 | 400:1 | 400:1 | |
| M2 | 400:1 | 800:1 | Cumulative includes M1 |
| M3 | 400:1 | 1200:1 | |
| M4 | 1000:1 | 2000:1 | Upper metals less critical |
| M5-M7 | 1000:1 | 5000:1 | Thick metals, wide wires |
| M8+ (RDL) | 5000:1 | 10000:1 | Redistribution layers |
| Via (each layer) | 200:1 (via area) | - | Via area contributes |

**Important**: These numbers are illustrative. Actual values depend on the specific foundry process and node. Always refer to the current design rule manual (DRM).

### Gate Oxide Thickness Dependence

Thinner gate oxides are more susceptible to antenna damage because:
1. The breakdown voltage is lower (scales roughly linearly with oxide thickness)
2. The tunneling current increases exponentially with decreasing oxide thickness
3. At advanced nodes (7nm, 5nm, 3nm), high-k/metal-gate (HKMG) structures have different susceptibility profiles

Foundries often specify different antenna limits for:
- Core devices (thin oxide, most vulnerable)
- I/O devices (thick oxide, more tolerant)
- High-Vt vs Low-Vt devices (different oxide thickness in some processes)
- NMOS vs PMOS (different sensitivity due to oxide charge polarity)

---

## Diode Insertion Strategies

### How Diodes Protect Against Antenna Damage

A reverse-biased diode connected between the metal wire and the substrate provides a discharge path for accumulated charge. During plasma processing, when positive charge accumulates on the metal, the diode (connected to the substrate at ~0V) becomes forward-biased and conducts, clamping the voltage to ~0.6V — well below the oxide damage threshold.

### Types of Protection Diodes

#### N-well diode (NMOS-connected)
An n-diffusion in a p-well forms a diode with the cathode on the metal wire and the anode on the substrate. Forward-biases when the metal wire goes positive relative to the substrate.

#### P-well diode (PMOS-connected)
A p-diffusion in an n-well forms a diode. Forward-biases when the metal wire goes negative relative to the n-well.

#### Dual diodes
Both N-well and P-well diodes for protection against both polarities of charge.

### Diode Cell Libraries

Foundries provide dedicated antenna diode cells in the standard cell library:

```
ANTENNADIODE_X1  — smallest diode, minimal area (~1 site)
ANTENNADIODE_X2  — medium diode, more discharge capacity
ANTENNADIODE_X4  — large diode, for severe violations
```

The diode's gate oxide area contributes to the denominator of the antenna ratio, effectively reducing the ratio.

### Diode Insertion Approaches

#### Post-Route Diode Insertion
After routing is complete, the tool identifies antenna violations and inserts diodes:

```tcl
# Innovus post-route diode insertion
setNanoRouteMode -routeInsertAntennaDiode true
setNanoRouteMode -routeAntennaCellName ANTENNADIODE_X1
setNanoRouteMode -droutePostRouteSpreadWire false

# Run antenna fix
editAddAntennaDiode -antennaCell ANTENNADIODE_X1

# Alternatively, during detailed route
routeDesign -fixAntenna
```

```tcl
# Innovus: check and fix antenna violations
verifyConnectivity -type antenna
fixAntenna -diodeCell ANTENNADIODE_X1 \
  -maxDiodePerNet 10 \
  -preferredLayers {M1 M2}
```

#### Pre-Route Diode Insertion (Preventive)
Insert diodes on all gate inputs during placement, before routing. This guarantees no antenna violations but wastes area for nets that would not have violations.

```tcl
# Insert diodes on all gate inputs during placement
addAntennaDiode -cell ANTENNADIODE_X1 -prefix ANTENNA
```

This approach is less common in modern flows because it wastes area. Most teams use post-route insertion.

#### Synthesis-Time Diode Insertion
Some synthesis tools can insert diodes during gate-level synthesis:

```tcl
# Design Compiler
set_fix_antenna_options -diode_cell ANTENNADIODE_X1
```

### Diode Insertion Guidelines

- Use the smallest diode cell that resolves the violation (ANTENNADIODE_X1 first)
- Place diodes close to the gate they protect (minimizes additional wire length)
- Verify that diode insertion does not cause placement congestion or DRC violations
- Check that diode leakage is acceptable (each diode adds junction leakage)
- For clock nets, be cautious: diode capacitance adds to clock load, affecting skew
- After diode insertion, re-run antenna DRC to verify all violations are fixed

---

## Jumper Insertion (Metal Hopping)

### Concept

An alternative to diode insertion is "jumper" insertion: breaking a long wire on one layer and routing a short segment on a higher metal layer. This works because:

1. Antenna damage accumulates layer by layer during fabrication (bottom-up processing)
2. When a lower metal layer is being etched, the upper metal layers do not exist yet
3. By breaking the wire and jumping to a higher layer, the effective antenna area on the lower layer is reduced
4. The upper layer's antenna area is assessed separately when that layer is processed, but by then the complete wire (including the gate connection through lower layers) provides more discharge paths

### How Jumpers Work

Original wire (M2, long):
```
Gate ──────── M2 (500um long) ────────── Source
```
PAR = (500um * width) / (gate area) = VIOLATION

After jumper insertion:
```
Gate ── M2 (50um) ── Via23 ── M3 (short) ── Via23 ── M2 (450um) ── Source
```
Now when M2 is processed, only 50um of M2 connects to the gate (the other 450um is not connected yet because M3 hasn't been fabricated). PAR for M2 = (50um * width) / (gate area) = OK.

When M3 is processed, the total area includes M2 + M3, but the gate is now connected through a complete path to the substrate (through the transistor's source/drain), providing a discharge path.

### Jumper Insertion in EDA Tools

```tcl
# Innovus: enable antenna jumper insertion during routing
setNanoRouteMode -routeInsertAntennaJumper true

# Specify which layers can be used for jumpers
setNanoRouteMode -routeAntennaJumperLayers {M3 M4 M5}

# Set maximum number of jumpers per net
setNanoRouteMode -routeMaxAntennaJumperPerNet 5
```

### Jumper vs Diode Tradeoffs

| Aspect | Diode | Jumper |
|--------|-------|--------|
| Area overhead | Diode cell area | Via + short wire segment |
| Routing impact | Minimal (cell placed, not on signal path) | Adds vias and wire, increases resistance and capacitance |
| Timing impact | Diode capacitance on signal (small) | Extra via resistance + wire delay |
| DRC risk | Potential placement DRC | Additional via DRC, potential congestion |
| Reliability | Diode leakage | Extra vias may have via EM concerns |
| Effectiveness | Always works if diode is large enough | May not fix severe violations |
| Preference | Preferred for most cases | Used when diode placement is difficult |

---

## Antenna-Aware Routing

### Router Configuration

Modern routers have built-in antenna awareness. Key settings:

```tcl
# Innovus NanoRoute antenna settings
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -routeWithSiDriven true
setNanoRouteMode -routeInsertAntennaDiode true
setNanoRouteMode -routeAntennaCellName ANTENNADIODE_X1
setNanoRouteMode -routeInsertAntennaJumper true

# Set antenna rules (usually read from tech LEF)
# The router reads antenna rules from the technology file

# Control antenna-fixing aggressiveness
setNanoRouteMode -drouteFixAntenna true
setNanoRouteMode -drouteAntennaFactor 1.0  ;# 1.0 = exact rules, <1.0 = more aggressive
```

```tcl
# ICC2 / Fusion Compiler antenna settings
set_route_options -antenna true
set_antenna_rules -diode_cell ANTENNADIODE_X1
route_auto -antenna
```

### Layer-Specific Antenna Considerations

Different metal layers have different antenna characteristics:

**Lower metals (M1-M3):**
- Thinnest, closest to transistors
- Most antenna-sensitive (smallest PAR limits)
- Most interconnections to gates
- Router must be careful with wire lengths on these layers

**Middle metals (M4-M6):**
- Moderate antenna limits
- Primary routing layers for signal nets
- Jumper targets for lower-layer violations

**Upper metals (M7+):**
- Highest antenna limits (thick metals, wide wires)
- Used for power/ground, clocks, long-distance signals
- Large metal area but usually connected to many gates, diluting the ratio

**Via layers:**
- Each via contributes to antenna area
- Via arrays (redundant vias) increase via antenna area
- Foundries specify separate via antenna limits

### Net-Specific Antenna Control

For critical nets (clocks, resets), antenna management needs special attention:

```tcl
# Innovus: set antenna constraints per net
setAttribute -net clk_core -antenna_max_ratio 200
setAttribute -net rst_n -antenna_diode_cell ANTENNADIODE_X2  ;# larger diode for critical signal
```

---

## Antenna DRC Checking and Fixing

### Running Antenna DRC

Antenna checks are part of the physical verification DRC run:

```tcl
# Calibre antenna check (in SVRF rule file)
ANTENNA_CHECK LAYER M1 RATIO 400
ANTENNA_CHECK LAYER M2 RATIO 400
ANTENNA_CHECK LAYER M3 RATIO 400
ANTENNA_DIODE LAYER ndiode  ;# specify diode recognition layer

# ICV antenna check
ANTENNA {
  LAYER M1 {
    MAX_RATIO 400.0
    DIODE_LAYER NWDIODE
  }
}
```

```tcl
# In-design antenna check (Innovus)
verifyProcessAntenna -reportFile antenna_violations.rpt

# Read Calibre antenna results in Innovus
loadViolationReport -type antenna antenna_violations.rpt
```

### Iterative Antenna Fixing Flow

1. **Route design** with antenna awareness enabled
2. **Run antenna DRC** (in-design or with Calibre/ICV)
3. **Fix violations** using diodes and/or jumpers:
   ```tcl
   # Fix with diodes first
   editAddAntennaDiode -antennaCell ANTENNADIODE_X1

   # Re-check
   verifyProcessAntenna -reportFile antenna_post_fix.rpt

   # If violations remain, try jumpers
   editAddAntennaJumper

   # Final check
   verifyProcessAntenna -reportFile antenna_final.rpt
   ```
4. **Verify no new DRC violations** from diode/jumper insertion
5. **Verify timing impact** of added diodes (capacitance) and jumpers (resistance)
6. **Re-run signoff DRC** with Calibre/ICV to confirm clean

### Antenna Violations on Clock Nets

Clock nets are particularly challenging for antenna because:
- Clock trees have long wire segments (especially trunk routes)
- Clock nets connect to many flip-flop clock pins (many gate oxide targets)
- Adding diodes to clock nets adds capacitance, affecting clock skew and insertion delay
- Jumpers on clock nets add resistance, potentially degrading clock quality

Strategies for clock net antenna:
- Use upper metal layers for clock routing (higher antenna limits)
- Break clock trunk into segments with intermediate buffers (each buffer provides a gate-connected discharge path)
- Use dedicated clock-antenna diode cells with minimal capacitance
- Account for antenna diode capacitance in CTS optimization

### Antenna Violations on Power/Ground Nets

Power and ground nets typically have very large metal area but are connected to many source/drain diffusions (not gates). Since antenna rules apply to gate connections, power/ground nets rarely have antenna violations unless they connect to power switch gates or decap cell gates.

However, some foundries also specify antenna rules for diffusion areas (source/drain junction damage). Check the DRM for diffusion antenna rules.

---

## Advanced Antenna Topics

### Antenna at Advanced Nodes (7nm/5nm/3nm)

At advanced process nodes:
- Gate oxide is thinner (even with high-k) → lower damage threshold
- Wire pitch is tighter → more charge collection per unit area
- Via density is higher → more cumulative antenna area
- Multi-patterning adds complexity: different mask exposures may have different charge characteristics
- FinFET gate area calculation differs from planar: gate area = fin_height x fin_count x gate_length x 2 (both sides)
- Some foundries allow reduced antenna limits for FinFET due to the 3D gate structure's better charge dissipation

### Antenna in Multi-Patterning

Double patterning (LELE or SADP) means that a single metal layer is processed in two separate masks/etching steps. Antenna rules may need to be evaluated per mask color:

```
M2_Color_A: Antenna ratio for features on mask A
M2_Color_B: Antenna ratio for features on mask B
M2_Combined: Total antenna for all M2 features
```

This is foundry-specific and defined in the DRM.

### Antenna Waivers

When an antenna violation cannot be fixed without significant design impact (e.g., on a critical timing path where any additional capacitance is unacceptable), a waiver may be requested from the foundry. The waiver process typically requires:

1. Detailed report of the violation (net name, ratio, layer)
2. Justification for why the violation cannot be fixed
3. Risk assessment (what is the expected yield impact)
4. Foundry review and approval

Waivers should be a last resort, not a routine practice.

---

## Troubleshooting

### Common Antenna Issues

**Persistent violations after fixing**: The fix introduced new routing that created new violations. Re-run iteratively until convergent.

**Antenna violations on short nets**: Usually caused by wide metal features (bus wires) or dense via arrays. Check if via antenna contributes significantly.

**Violations only on one layer**: Usually M1 or M2. These layers have the tightest limits and the most gate connections. Consider re-routing affected nets on higher layers.

**Timing degradation after diode insertion**: The diode adds 2-5fF per instance. For timing-critical nets, this can be significant. Use the smallest possible diode and verify timing after insertion.

**Antenna violations in macro/IP boundaries**: Pre-hardened macros may have long M1/M2 routes inside that contribute to antenna when connected externally. Route the external connection on higher metals to minimize added antenna area.

### Expert Tips

- Enable antenna-aware routing from the start; fixing after the fact is harder
- Review antenna DRC results immediately after detail routing, before ECO timing fixes
- Budget 0.5-1.0% area overhead for antenna diodes
- For memories and hard macros, check the antenna status of the macro's pin connections — some macros have built-in antenna protection on their pins
- Track antenna violation count as a QoR metric across implementation iterations
- At advanced nodes, consider antenna early in the routing strategy: prefer upper metals for long routes connecting to gate-heavy instances
- Antenna violations are purely a manufacturing concern and do not affect pre-silicon simulation or functionality — but they absolutely affect silicon yield and reliability
- Always run the foundry-certified Calibre/ICV antenna DRC deck for signoff, not just the in-design checker
