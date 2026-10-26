# Parasitic Models: Extraction Technology Files and Formats

## The Role of Parasitic Models

Parasitic models describe how the physical interconnect (metal wires and vias) translates into electrical resistance and capacitance. These models are used by extraction tools to convert the routed layout into an electrical netlist (SPEF) that timing analysis tools consume. The accuracy of parasitic models directly determines the accuracy of post-route timing, power, and signal integrity analysis.

Different extraction tools use different technology file formats, but they all describe the same underlying physics: the geometry and material properties of the metal stack.

## TLU+: Table Lookup Plus

### Overview

TLU+ (Table Lookup Plus) is the parasitic model format used by Synopsys tools (PrimeTime, IC Compiler, Fusion Compiler) for fast parasitic estimation during implementation. TLU+ uses pre-computed lookup tables of capacitance and resistance values indexed by wire geometry parameters.

### How TLU+ Works

During placement and routing, the tool looks up parasitic values from the TLU+ tables based on:
- Metal layer
- Wire width
- Wire spacing to neighbors
- Presence of upper/lower metal layers (shielding effects)
- Via configurations

The lookup is fast (simple table interpolation) but less accurate than field-solver extraction. TLU+ is primarily used for:
- Pre-route timing estimation
- In-design optimization (during placement and routing)
- Quick timing updates without running full extraction

### TLU+ File Generation

TLU+ files are generated from ITF (Interconnect Technology Format) files using Synopsys's grdgenxo utility:

```bash
grdgenxo -itf_file tech.itf \
         -process_corner max \
         -output_file tech_cmax.tluplus

grdgenxo -itf_file tech.itf \
         -process_corner min \
         -output_file tech_cmin.tluplus

grdgenxo -itf_file tech.itf \
         -process_corner nominal \
         -output_file tech_ctyp.tluplus
```

### TLU+ in the Flow

```tcl
# IC Compiler II / Fusion Compiler
set_parasitic_parameters \
  -late_spec tech_cmax.tluplus \
  -early_spec tech_cmin.tluplus

# PrimeTime
read_parasitics -format tlu+ -tlup_file tech_cmax.tluplus
```

### TLU+ Limitations

- **Accuracy:** TLU+ is an approximation. For signoff, full field-solver extraction is required.
- **Coupling capacitance:** TLU+ models ground capacitance well but coupling capacitance modeling is limited compared to field-solver tools.
- **Advanced nodes:** At 7nm and below, the complex metal geometries and high coupling ratios exceed TLU+ accuracy capabilities.

## ITF: Interconnect Technology Format

### Overview

ITF is Synopsys's format for describing the interconnect process stack. It contains the physical and material properties of each metal and dielectric layer.

### ITF Contents

```itf
TECHNOLOGY = "7nm_advanced"
METAL_LEVELS = 13

CONDUCTOR M1 {
  thickness = 0.036
  min_width = 0.024
  min_spacing = 0.024
  resistivity = 2.2e-6   ;# ohm-cm (copper)
  barrier_thickness = 0.002
  height_from_substrate = 0.100
}

DIELECTRIC ILD_M1_M2 {
  dielectric_constant = 3.0  ;# low-k dielectric
  conformal_thickness = 0.040
}

CONDUCTOR M2 {
  thickness = 0.036
  min_width = 0.024
  min_spacing = 0.024
  resistivity = 2.2e-6
  height_from_substrate = 0.176
}

VIA VIA12 {
  width = 0.032
  height = 0.040
  resistivity = 3.0e-6    ;# via plug resistivity
  spacing = 0.040
}
```

### ITF to TLU+ Flow

```
Foundry Process Data -> ITF -> grdgenxo -> TLU+ (for Synopsys tools)
```

The ITF is the primary input; TLU+ is a derived format optimized for fast lookup.

## QRC Techfile: Cadence Quantus/QRC

### Overview

The QRC technology file is the parasitic model format used by Cadence Quantus (QRC) extraction tool. It contains detailed process stack information and extraction rules that the field-solver engine uses to compute accurate parasitics.

### QRC Techfile Contents

The QRC techfile describes:
- **Process cross-section:** Layer thicknesses, positions, and materials
- **Conductor properties:** Resistivity, sheet resistance, barrier effects
- **Dielectric properties:** Permittivity (dielectric constant) for each dielectric layer
- **Via properties:** Resistance, geometry
- **Extraction rules:** Coupling distance, accuracy settings
- **Temperature coefficients:** How resistance and capacitance vary with temperature

```
# QRC techfile excerpt (simplified)
TECHNOLOGY {
  name = "7nm"
  dielectric_constant = 3.0
  temperature = 25
}

CONDUCTOR M1 {
  layer_number = 31
  min_width = 0.024
  min_spacing = 0.024
  resistivity = 2.2e-6
  thickness = 0.036
  bottom_height = 0.100
  barrier_thickness = 0.002
  temperature_coefficient = 0.00385
}
```

### QRC in the Flow

```tcl
# Define RC corner with QRC tech file
create_rc_corner -name rc_cmax \
  -qrc_tech /path/to/qrcTechFile_cmax \
  -T 125

# Run extraction
setExtractRCMode -engine postRoute -effortLevel signoff
extractRC -outfile design.spef
```

### QRC Accuracy

QRC uses a 3D field solver that computes capacitance and resistance from first principles (solving Maxwell's equations numerically). This provides high accuracy:
- **Capacitance accuracy:** Within 1-3% of test chip measurements
- **Resistance accuracy:** Within 2-5% of measurements
- **Coupling capacitance:** Accurately models coupling between adjacent and non-adjacent wires

QRC is the standard signoff extraction tool in Cadence-based flows.

## nxtgrd: Synopsys StarRC

### Overview

nxtgrd (Next Generation Rule Deck) is the technology file format used by Synopsys StarRC extraction tool. Like QRC, StarRC is a field-solver-based extraction engine used for signoff-quality parasitic extraction.

### nxtgrd Contents

nxtgrd files contain:
- Process cross-section geometry
- Material properties (conductivity, permittivity)
- Extraction rules and calibration data
- Temperature-dependent models
- Process corner definitions (Cmax, Cmin, Rcmax, etc.)

### nxtgrd in the Flow

```tcl
# StarRC command file
TCAD_GRD_FILE: /path/to/nxtgrd_cmax
MAPPING_FILE: /path/to/layer.map
EXTRACT_VIA_CAPS: YES
COUPLE_TO_GROUND: NO
COUPLING_ABS_THRESHOLD: 1e-18
REDUCTION: RC_STAR
```

```bash
# Run StarRC extraction
StarXtract -clean design.cmd
```

### StarRC vs. QRC

Both are signoff-quality field-solver extractors. The choice is typically determined by the tool ecosystem:

| Aspect | StarRC (nxtgrd) | QRC (qrcTechFile) |
|---|---|---|
| Vendor | Synopsys | Cadence |
| Accuracy | Signoff quality | Signoff quality |
| Speed | Optimized for large designs | Optimized for large designs |
| Integration | PrimeTime, ICC2, FC | Tempus, Innovus |
| Format | nxtgrd | qrcTechFile |
| Output | SPEF, DSPF | SPEF, DSPF |

## SPEF: Standard Parasitic Exchange Format

### Overview

SPEF (IEEE 1481) is the standard format for transferring extracted parasitic data between tools. Regardless of which extraction tool (QRC, StarRC) or technology file format is used, the output is SPEF.

### SPEF Structure

```spef
*SPEF "IEEE 1481-2009"
*DESIGN "my_design"
*DATE "2026-05-18"
*VENDOR "Cadence"
*PROGRAM "Quantus"
*DESIGN_FLOW "PIN_CAP NONE"
*DIVIDER /
*DELIMITER :
*BUS_DELIMITER [ ]
*T_UNIT 1 NS
*C_UNIT 1 PF
*R_UNIT 1 OHM
*L_UNIT 1 HENRY

*NAME_MAP
*1 net_clk
*2 net_data_0
*3 net_data_1

*PORTS
clk_port I *C 0.0123

*D_NET *1 0.0532                    ;# Total cap of net *1
*CONN
*P clk_port I                       ;# Port connection
*I inst1:CK I *C 0.002 *L 0 *D BUF_X4
*CAP
1 *1:1 0.0120                      ;# Ground cap
2 *1:2 0.0085
3 *1:1 *2:3 0.0052                 ;# Coupling cap to net *2
4 *1:2 *3:1 0.0031                 ;# Coupling cap to net *3
*RES
1 *1:1 *1:2 1.230                  ;# Resistance between nodes
2 *1:2 *1:3 0.890
*END

*D_NET *2 0.0345
...
```

### SPEF Variants

- **DSPF (Detailed Standard Parasitic Format):** Older format, less commonly used
- **Reduced SPEF:** Lumped RC model (faster but less accurate)
- **Detailed SPEF:** Distributed RC model (signoff quality)
- **SPEF with coupling:** Includes CC (coupling capacitance) -- required for SI analysis

### SPEF Best Practices

1. **Always use detailed SPEF for signoff.** Reduced SPEF is acceptable for early-stage timing.
2. **Include coupling capacitances.** Without CC, SI analysis cannot be performed.
3. **Verify SPEF consistency.** Net names in SPEF must match the design netlist. Missing nets indicate extraction errors.
4. **Check SPEF statistics.** After extraction, review the total capacitance, resistance, and coupling cap statistics to sanity-check against expectations.

## Parasitic Model Calibration

### Test Chip Correlation

Foundries calibrate their extraction technology files against silicon measurements from test chips:

1. **Fabricate test structures** with various wire widths, spacings, and configurations
2. **Measure actual R and C** values using on-chip measurement circuits
3. **Compare with extraction results** using the same geometry
4. **Adjust technology file parameters** to minimize the error

### Correlation Targets

| Parameter | Typical Correlation Target |
|---|---|
| Ground capacitance | Within 2% |
| Coupling capacitance | Within 5% |
| Wire resistance | Within 3% |
| Via resistance | Within 10% |
| Total net delay | Within 5% |

### User-Side Validation

Physical design teams should validate extraction accuracy for their specific design:

```tcl
# Compare extraction results between tools
# Run both QRC and StarRC on the same design
# Compare total cap, resistance, and timing
```

Discrepancies greater than 5% in total capacitance or 10% in delay warrant investigation.

## Practical Recommendations

1. **Use field-solver extraction for signoff.** TLU+ is for estimation during implementation; QRC or StarRC is for signoff.

2. **Match extraction temperature to the PVT corner.** Resistance depends strongly on temperature. Extract at 125C for the SS corner and -40C for the FF corner.

3. **Use the foundry-provided technology files.** Do not modify extraction technology files unless directed by the foundry. Incorrect modifications corrupt all downstream timing.

4. **Verify coupling capacitance extraction.** Run a test with and without coupling caps to understand the SI impact on your design.

5. **Monitor extraction runtime and memory.** Full-chip signoff extraction can take hours and consume hundreds of GB of memory. Plan computational resources accordingly.

6. **Keep SPEF files for signoff records.** Archive the signoff SPEF alongside the design database and timing reports for post-silicon debug and future reference.

7. **Understand the extraction corner matrix.** Know which RC corner (Cmax, Cmin, Rcmax, etc.) is paired with which PVT corner and why. This is fundamental to the MMMC setup.

Parasitic models are the bridge between physical layout and electrical behavior. The choice of extraction tool, technology file, and RC corner directly affects the accuracy and reliability of timing signoff.
