# RC Corner Extraction: Parasitic Corners for Timing Analysis

## The Role of RC Extraction

After routing, every wire in the design has parasitic resistance (R) and capacitance (C) that affect signal delay and timing. RC extraction converts the physical layout geometry into an electrical parasitic network that timing analysis tools use to compute wire delays. The accuracy of extraction directly determines the accuracy of post-route timing.

Like transistor PVT corners, interconnect parasitics also vary with process and temperature. RC corner extraction models these variations to ensure timing is correct across the full range of manufacturing and operating conditions.

## Parasitic Components

### Wire Resistance

Wire resistance depends on:
- **Metal width and thickness:** Narrower, thinner wires have higher resistance
- **Metal resistivity:** Material property (copper, cobalt, ruthenium at advanced nodes)
- **Wire length:** Resistance scales linearly with length
- **Temperature:** Metal resistance increases with temperature (positive temperature coefficient)
- **Via resistance:** Each via transition adds resistance; at advanced nodes, via resistance is significant

### Wire Capacitance

Wire capacitance has two components:
- **Ground capacitance (Cg):** Capacitance from the wire to the substrate or adjacent ground planes (metal layers above and below)
- **Coupling capacitance (Cc):** Capacitance between adjacent wires on the same layer or between layers

At advanced nodes (7nm and below), coupling capacitance can be 60-80% of total wire capacitance, making signal integrity analysis critical.

### Capacitance Factors

Capacitance depends on:
- **Wire spacing:** Closer spacing increases coupling capacitance
- **Wire width:** Wider wires have more capacitance to ground and to neighbors
- **Dielectric constant (k):** Lower-k dielectrics reduce capacitance (low-k and ultra-low-k ILD)
- **Metal density and fill patterns:** Dummy metal fill alters the local dielectric environment
- **Layer stack-up:** The relative position of metal layers and dielectric thicknesses

## Standard RC Corners

Foundries define a set of standard RC corners that capture the range of parasitic variation:

### Cmax (Maximum Capacitance)

- **Thicker, wider wires** with minimum spacing
- **Higher dielectric constant** (upper bound)
- **Maximum coupling capacitance**
- **Primary use:** Setup timing analysis (maximum wire delay due to high C)
- **Paired with:** Slow process corner (SS) for worst-case setup

### Cmin (Minimum Capacitance)

- **Thinner, narrower wires** with maximum spacing
- **Lower dielectric constant** (lower bound)
- **Minimum coupling capacitance**
- **Primary use:** Hold timing analysis (minimum wire delay, data arrives too fast)
- **Paired with:** Fast process corner (FF) for worst-case hold

### Ctyp (Typical Capacitance)

- Nominal wire dimensions and spacing
- Nominal dielectric constant
- **Primary use:** Power estimation, typical performance analysis
- **Paired with:** TT process corner

### RCmax (Maximum RC Product)

- **Maximum resistance AND maximum capacitance**
- Used when both R and C are at their worst simultaneously
- Some foundries separate Rmax+Cmax from Cmax alone

### RCmin (Minimum RC Product)

- **Minimum resistance AND minimum capacitance**
- Paired with FF corner for hold analysis

### Rcmax (Maximum Resistance, Minimum Capacitance)

A cross-corner where resistance is maximum but capacitance is minimum. This corner can be critical for:
- **Long resistive paths** where Elmore delay is R-dominated
- **Advanced nodes** where resistance is a larger proportion of total delay
- Also called the "RC worst" corner at some foundries

### Rcmin (Minimum Resistance, Maximum Capacitance)

Cross-corner with minimum resistance and maximum capacitance. Less commonly used but may be relevant for specific path types.

## Temperature Effects on RC

### Resistance and Temperature

Metal resistance increases linearly with temperature:

```
R(T) = R(T0) * (1 + TCR * (T - T0))
```

Where TCR (Temperature Coefficient of Resistance) is approximately 0.003-0.004 per degree C for copper.

At 125C vs. 25C, resistance increases by approximately 30-40%. At advanced nodes where wire resistance is a significant component of total delay, this temperature effect is substantial.

### Capacitance and Temperature

Capacitance has weak temperature dependence. The dielectric constant changes slightly with temperature, but this is typically less than 5% across the full temperature range. For practical purposes, capacitance is considered temperature-independent in most extraction flows.

### Temperature in Extraction

Extraction tools accept a temperature parameter that adjusts resistance accordingly:

```tcl
# Innovus QRC extraction with temperature
setExtractRCMode -engine postRoute
setExtractRCMode -effortLevel signoff
extractRC -outfile design.spef -rcCorner cmax -temperature 125

# Or set in the RC corner definition
create_rc_corner -name rc_cmax_125c -T 125 \
  -qrc_tech /path/to/qrcTechFile
```

## Metal Fill Impact

Metal fill (dummy fill) is added to meet minimum density requirements and improve CMP (Chemical Mechanical Polishing) uniformity. Fill affects parasitics:

- **Grounded fill** increases coupling capacitance to adjacent signal wires and ground capacitance
- **Floating fill** has a smaller but non-negligible capacitance impact
- **Fill density** varies across the chip, making its impact non-uniform

### Accounting for Fill in Extraction

Signoff extraction should include the effect of metal fill:

```tcl
# Extract with fill-aware mode
extractRC -outfile design.spef -fillAware true
```

If fill has not been inserted at the time of extraction, the tool can model expected fill statistically. However, signoff should always use actual fill data.

## Extraction Tools and Formats

### Industry Extraction Tools

| Tool | Vendor | Technology File | Output |
|---|---|---|---|
| QRC (Quantus) | Cadence | QRC techfile | SPEF |
| StarRC | Synopsys | nxtgrd | SPEF |
| xRC (xACT) | Synopsys | ITF/TLU+ | SPEF |

### Technology Files

- **QRC techfile:** Cadence-format file describing the metal stack, dielectric properties, and extraction rules. Provided by the foundry as part of the PDK.
- **nxtgrd:** Synopsys StarRC format. Contains detailed extraction models for each metal layer.
- **ITF (Interconnect Technology Format):** Describes the process cross-section for Synopsys tools.
- **TLU+ (Table Lookup Plus):** Pre-computed parasitic lookup tables derived from ITF. Faster but less accurate than field-solver extraction.

### Extraction Output: SPEF

Standard Parasitic Exchange Format (SPEF) is the IEEE standard for representing extracted parasitics. SPEF files contain:

- **Header:** Design name, units, extraction conditions
- **Name map:** Net and instance name encoding for file size reduction
- **Port and net parasitics:** R, C, and CC (coupling capacitance) values for each net

```spef
*NAME_MAP
*1 net_clk
*2 net_data

*D_NET *1 0.0532
*CONN
*P clk_port I
*I inst1:CK I
*CAP
1 *1:1 0.012
2 *1:2 0.008
3 *1:1 *2:3 0.005  ;# coupling cap to net_data
*RES
1 *1:1 *1:2 1.23
*END
```

### SPEF Types

- **Detailed SPEF (D):** Full RC network with distributed R and C elements. Most accurate.
- **Reduced SPEF (R):** Lumped R and C. Faster to read but less accurate.
- **Standard SPEF (S):** Intermediate detail level.

For signoff, always use detailed SPEF. Reduced SPEF is acceptable for early-stage timing estimation.

## RC Corner Selection for MMMC

The standard pairing of RC corners with PVT corners:

| Timing Check | PVT Corner | RC Corner | Rationale |
|---|---|---|---|
| Setup (worst) | SS, low V, high T | Cmax | Maximum wire delay adds to slow cell delay |
| Hold (worst) | FF, high V, low T | Cmin | Minimum wire delay adds to fast cell delay |
| Setup (check) | SS, low V, low T | Cmax | Temperature inversion check at advanced nodes |
| Power | TT, nominal | Ctyp | Typical conditions for power estimation |

### Advanced RC Corner Strategies

At 7nm and below, consider:
- **Rcmax corner** for paths dominated by long resistive wires (especially lower metal layers)
- **Multiple extraction temperatures** when resistance temperature dependence significantly impacts timing
- **Separate local and global metal corners** if the foundry provides them

## Practical Recommendations

1. **Use signoff-quality extraction for signoff timing.** TLU+ is acceptable during implementation, but final signoff must use field-solver extraction (QRC or StarRC).

2. **Match RC corner temperature to PVT corner temperature.** Do not use 25C extraction with 125C library characterization. The resistance temperature dependence will be unmodeled.

3. **Include coupling capacitance in extraction.** Signoff SPEF must include coupling caps for SI analysis. Ground-only extraction misses crosstalk effects.

4. **Extract with metal fill.** Signoff extraction after fill insertion produces the most accurate parasitics.

5. **Verify extraction accuracy.** Correlate extracted parasitics with test chip measurements when available. A 10-15% correlation error is typical; larger errors indicate extraction setup issues.

6. **Use consistent extraction settings.** All RC corners should use the same extraction engine, effort level, and coupling cap threshold. Inconsistent settings across corners produce inconsistent timing.

7. **Monitor extraction runtime and file size.** Detailed SPEF for a large SoC can be tens of gigabytes. Ensure adequate disk space and plan for extraction runtime in the project schedule.

RC extraction is the bridge between physical layout and electrical behavior. Getting it right is essential for accurate timing analysis and ultimately for silicon that meets its performance targets.
