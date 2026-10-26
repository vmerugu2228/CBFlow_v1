# Semiconductor Manufacturing

## Overview

Understanding the fabrication process helps PD engineers make better design decisions. Every design rule in the DRM exists because of a physical manufacturing constraint. When PD engineers understand why a spacing rule is 28nm and not 20nm, they can make informed tradeoffs rather than blindly following rules. This guide covers the major steps in semiconductor manufacturing, from raw silicon to finished wafer, focusing on aspects most relevant to physical design.

## Wafer Preparation

### Silicon Ingot Growth

Semiconductor manufacturing begins with ultra-pure silicon. The Czochralski process grows a single-crystal silicon ingot by slowly pulling a seed crystal from a crucible of molten silicon.

- **Purity**: 99.999999999% pure (eleven nines)
- **Crystal orientation**: (100) plane is standard for CMOS
- **Ingot diameter**: 300mm (12 inches) is the current industry standard; 450mm was explored but not widely adopted
- **Doping**: Lightly doped P-type (boron) for standard CMOS substrates

### Wafer Slicing and Polishing

The ingot is sliced into thin wafers (0.775mm thick for 300mm wafers), then ground and polished to an extremely flat, mirror-smooth surface.

- **Total thickness variation (TTV)**: < 1um across the wafer
- **Surface roughness**: < 0.1nm RMS (atomic-level flatness)

This extreme flatness is essential for lithography, where features are defined with nanometer precision.

## Photolithography

Photolithography is the pattern transfer process at the heart of chip manufacturing. It defines the shapes of transistors, wires, and vias.

### Process Steps

1. **Coat with photoresist**: Spin a thin layer of light-sensitive polymer (photoresist) onto the wafer
2. **Expose**: Project a pattern from the photomask through a lens system onto the photoresist. The lens reduces the mask pattern (typically 4x) to the target size on the wafer
3. **Develop**: Dissolve the exposed (or unexposed, depending on resist type) photoresist, leaving a pattern on the wafer
4. **Etch/deposit**: Use the photoresist pattern as a mask to etch underlying material or deposit new material
5. **Strip resist**: Remove the remaining photoresist

### Light Source

- **DUV (Deep Ultraviolet)**: 193nm wavelength using ArF excimer laser. Used for 32nm-7nm nodes with immersion and multiple patterning
- **EUV (Extreme Ultraviolet)**: 13.5nm wavelength. Used for 7nm and below. Enables single-exposure patterning for smaller features
- **Resolution**: Minimum feature size ~ k1 * wavelength / NA (numerical aperture). k1 is a process-dependent factor (0.25-0.35)

### Physical Design Relevance

- **Minimum feature size**: Determines the smallest wire width and spacing PD engineers can use
- **Restricted design rules**: At advanced nodes, certain geometries that are mathematically possible are not lithographically printable. This leads to restricted routing rules (preferred directions, minimum jog lengths, end-of-line extensions)
- **Overlay accuracy**: Alignment between layers determines via enclosure rules. If layers can be misaligned by +/-3nm, the via enclosure must be at least 3nm larger than the via itself

## Etching

Etching removes material from areas not protected by photoresist or hard masks.

### Dry Etching (Plasma Etching)

Reactive ions in a plasma chamber chemically and physically remove material.

- **Anisotropic etching**: Removes material primarily in the vertical direction, creating straight sidewalls. Essential for defining narrow features
- **Selectivity**: The etch must remove the target material without significantly damaging the layer underneath (etch stop layer)
- **Used for**: Gate patterning, metal patterning, via etching, trench etching

### Wet Etching

Chemical solutions dissolve material isotropically (equally in all directions).

- **Used for**: Cleaning, removing sacrificial layers, some thick oxide removal
- **Not suitable for**: Fine feature patterning (isotropic etching undercuts the mask)

### Physical Design Relevance

- **Etch uniformity**: Etch rate can vary across the wafer, causing feature size variation. This contributes to within-die and die-to-die timing variation
- **Loading effects**: Dense arrays etch differently from isolated features. Uniform density (metal fill) reduces this effect
- **Aspect ratio limits**: Very deep, narrow trenches or vias are difficult to etch cleanly. This limits via aspect ratios and trench depths

## Deposition

Deposition adds thin layers of material onto the wafer surface.

### Chemical Vapor Deposition (CVD)

Gaseous precursors react on the wafer surface to form a solid film.

- **Variants**: PECVD (Plasma-Enhanced), LPCVD (Low-Pressure), HDPCVD (High-Density Plasma)
- **Used for**: Dielectric layers (SiO2, Si3N4, low-k dielectrics), barrier metals

### Physical Vapor Deposition (PVD / Sputtering)

Atoms are ejected from a solid target by ion bombardment and deposited on the wafer.

- **Used for**: Metal seed layers (copper seed for electroplating), barrier layers (TaN, TiN), aluminum metallization

### Electroplating (ECD)

Copper is electrochemically deposited into trenches and vias (the damascene process).

- **Used for**: All copper interconnect layers in modern processes
- **Process**: Deposit a thin copper seed layer (PVD), then electroplate to fill trenches and vias, then CMP to remove excess copper

### Atomic Layer Deposition (ALD)

Deposits material one atomic layer at a time for extreme thickness control.

- **Used for**: High-k gate dielectrics (HfO2), ultra-thin barrier layers
- **Advantage**: Conformal coating with angstrom-level thickness control

### Physical Design Relevance

- **Interconnect resistance**: The quality and thickness of copper deposition determines wire resistance. Process variation in deposition affects timing
- **Dielectric constant (k)**: Low-k dielectrics reduce wire capacitance and improve timing. Ultra-low-k dielectrics are fragile and require careful CMP
- **Barrier layers**: Thin barrier layers (TaN/Ta) between copper and dielectric prevent copper diffusion but add resistance

## Ion Implantation

Ion implantation introduces dopant atoms (boron, phosphorus, arsenic) into the silicon to create P-type and N-type regions.

- **Energy**: Determines implant depth (10 keV to 1 MeV)
- **Dose**: Determines dopant concentration (10^11 to 10^16 atoms/cm2)
- **Used for**: Source/drain formation, well formation, threshold voltage adjustment, channel doping

### Physical Design Relevance

- **Well rules**: Implantation defines N-well and P-well boundaries. Well spacing and enclosure rules in the DRM derive from implant characteristics
- **Threshold voltage**: Multi-Vt libraries (HVT, SVT, LVT) are created by varying the channel implant dose. The foundry controls this during manufacturing
- **Latch-up**: Improper well/substrate biasing can trigger parasitic thyristor structures. Well tap placement rules prevent this

## Chemical Mechanical Polishing (CMP)

CMP planarizes the wafer surface by combining chemical etching with mechanical abrasion.

### Why CMP is Needed

After deposition or etching, the wafer surface is not flat. Stacked layers amplify topography. Without planarization:

- Lithography cannot focus on an uneven surface (depth of focus is < 100nm at advanced nodes)
- Metal deposition in trenches would be incomplete if the surface is not flat
- Step coverage problems would cause reliability failures

### Copper Damascene CMP

The primary CMP application in back-end-of-line (BEOL) processing:

1. Trenches are etched in the dielectric
2. Copper is electroplated to fill trenches (with excess copper on top)
3. CMP removes the excess copper, leaving copper only in the trenches

### CMP Effects on Design

- **Dishing**: Large metal features (wide power stripes) dish during CMP, becoming thinner in the center. This increases resistance
- **Erosion**: Dense metal arrays erode during CMP, becoming thinner overall
- **Metal fill purpose**: Fill shapes equalize density, reducing both dishing and erosion

**Physical design relevance**: Wide power stripes must account for CMP dishing (use slots or fingers instead of solid fills). Metal fill density rules exist specifically because of CMP uniformity requirements.

## Advanced Process Modules

### FinFET Transistors

Starting at 22nm (Intel) / 16nm (TSMC/Samsung), planar transistors were replaced by FinFET (3D) transistors.

- **Fin**: A thin vertical silicon ridge that forms the transistor channel
- **Gate**: Wraps around the fin on three sides, providing better electrostatic control
- **Quantized width**: Transistor width comes in discrete fin counts (1 fin, 2 fins, 3 fins, ...). This affects standard cell design and library architecture

**Physical design relevance**: Fin quantization means cell widths are discretized. PD engineers see this as fixed cell heights and limited sizing options.

### Gate-All-Around (GAA) / Nanosheet

At 3nm and below, FinFETs are replaced by nanosheet transistors where the gate wraps completely around stacked horizontal silicon sheets.

- **Better electrostatic control**: Than FinFET (gate on all four sides)
- **Variable sheet width**: Allows more flexible transistor width tuning than fins

### Back-End-of-Line (BEOL) Metal Stack

The interconnect metal stack typically consists of:

- **Local interconnects (M1-M2)**: Thin, fine-pitch metal for cell-level connections
- **Intermediate metals (M3-M6)**: Medium pitch for block-level routing
- **Semi-global metals (M7-M9)**: Thicker metals for longer routes
- **Global metals (M10+)**: Thick metals for power distribution, clock routing, and long-distance signals

Each layer has different width, spacing, and resistance characteristics. PD tools use this information from the tech LEF to make routing decisions.

## Metrology

Metrology is the science of measurement in manufacturing. Key measurements include:

- **CD (Critical Dimension)**: Actual wire width or gate length after etching. Compared against target to monitor process control
- **Overlay**: Alignment accuracy between successive lithography layers
- **Film thickness**: Measured by ellipsometry or reflectometry
- **Defect inspection**: Optical or e-beam inspection to detect particles, pattern defects, and missing features
- **Electrical test**: In-line parametric tests (transistor Vt, sheet resistance, contact resistance) on test structures

### Physical Design Relevance

Metrology data feeds back into process models that determine timing variation. Better metrology leads to tighter process control, which reduces OCV derating and improves timing margins. PD engineers benefit indirectly from process improvements that reduce variation.

## Fab Process and Physical Design Connection

Understanding manufacturing helps PD engineers:

1. **Respect design rules**: Rules are not arbitrary; they reflect physical manufacturing limits
2. **Optimize for yield**: DFM-aware routing reduces critical area
3. **Understand variation**: Process variation in litho, etch, CMP, and implant causes timing/power variation that STA must account for
4. **Communicate with foundry**: When requesting waivers or reporting issues, understanding the manufacturing context enables more productive discussions
5. **Evaluate technology options**: When choosing metal stack options, understanding the BEOL tradeoffs (resistance vs. capacitance, routing density vs. reliability) informs better decisions
