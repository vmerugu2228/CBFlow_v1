# CMOS Process Technology: From Planar to FinFET to GAA

## The Evolution of CMOS Transistors

The history of CMOS process technology is a story of relentless scaling: making transistors smaller, faster, and more power-efficient. Each technology generation shrinks the critical dimensions, but as feature sizes approach atomic scales, new transistor architectures have been necessary to maintain Moore's Law. Understanding the underlying technology is essential for physical design engineers because transistor characteristics directly determine cell behavior, timing, power, and reliability.

## Planar CMOS (180nm to 28nm)

### Architecture

Planar (bulk) CMOS is the original transistor architecture that dominated semiconductor manufacturing for decades. The transistor is formed on a flat (planar) silicon substrate:

- **Gate:** A polysilicon or metal gate electrode sits on top of a thin gate oxide, controlling the channel between source and drain
- **Channel:** Current flows horizontally through a thin region of the silicon substrate beneath the gate
- **Gate control:** The gate controls the channel from one side (top) only

### Key Characteristics

- **Simple fabrication:** Well-understood manufacturing process
- **Well scaling:** Down to 28nm, planar transistors provided adequate gate control
- **Threshold voltage control:** Achieved through channel doping (ion implantation)
- **Leakage:** At 28nm and below, leakage current became a major concern due to thin gate oxides (gate leakage) and short channels (subthreshold leakage)

### Short Channel Effects

As gate length decreases, several parasitic effects become significant:

- **Drain-Induced Barrier Lowering (DIBL):** The drain voltage reduces the effective threshold voltage, increasing leakage
- **Velocity saturation:** Carrier velocity reaches a maximum, limiting current drive improvement from scaling
- **Gate oxide tunneling:** Electrons tunnel directly through the ultra-thin gate oxide, causing gate leakage
- **Random Dopant Fluctuation (RDF):** Statistical variation in the number and placement of dopant atoms in the channel causes significant threshold voltage variation

At 20nm and below, planar transistors could not provide sufficient gate control over the channel, and leakage became unacceptable. This led to the adoption of FinFET technology.

## FinFET (16nm/14nm to 5nm/3nm)

### Architecture

FinFET (Fin Field-Effect Transistor) uses a 3D transistor structure where the channel is a thin vertical "fin" of silicon protruding from the substrate. The gate wraps around the fin on three sides (top and both sidewalls).

```
Cross-section view:
        Gate
       /    \
  Gate |  Fin  | Gate    <- Gate wraps around fin on 3 sides
       |      |
  -----+------+-----    <- Substrate (buried oxide for SOI, bulk silicon for bulk FinFET)
```

### Key Characteristics

- **Tri-gate control:** The gate controls the channel from three sides, providing far superior electrostatic control compared to planar
- **Reduced leakage:** Better gate control reduces subthreshold leakage by 10-100x compared to equivalent planar
- **Undoped channel:** FinFET channels are typically undoped, eliminating random dopant fluctuation and improving variability
- **Quantized width:** Transistor width is determined by the number of fins (1, 2, 3, ...). You cannot have fractional fins, leading to discrete drive strength levels

### FinFET Implications for Physical Design

**Drive strength quantization:** Cell drive strengths come in discrete steps (1-fin, 2-fin, 3-fin) rather than continuous sizing. This affects optimization granularity.

**Fin pitch and cell height:** Cell height is determined by the number of fins and the fin pitch. Common cell architectures:
- 6T (6-track): Compact, fewer fins, lower drive strength
- 7.5T: Balanced density and performance
- 9T and 12T: Higher drive strength, more fins per device

**Self-heating:** The thin fin has limited thermal conduction paths, causing the transistor to heat up during switching. Self-heating reduces effective drive current and increases delay. It is more pronounced at fast corners and high activity.

**Back-End-of-Line (BEOL) scaling:** While FinFETs improved transistor performance, the interconnect (metal wires) became the bottleneck. Wire resistance increases dramatically at each node due to narrower and thinner metal layers.

### FinFET Generations

| Node | Fin Pitch | Metal Pitch | Key Features |
|---|---|---|---|
| 16nm/14nm | 42-48nm | 64nm | First production FinFET |
| 10nm | 34nm | 36-48nm | EUV for select layers |
| 7nm | 30nm | 36nm | Extensive EUV adoption |
| 5nm | 25-27nm | 28nm | Full EUV, ~5 fins/cell |
| 3nm | 23-25nm | 21-24nm | Last FinFET generation (some foundries) |

## GAA: Gate-All-Around (2nm and Beyond)

### Why GAA?

As FinFETs scale below 3nm, the fins become so narrow that quantum effects degrade mobility, and the three-sided gate wrapping is insufficient for electrostatic control. GAA transistors address this by having the gate completely surround the channel on all four sides.

### Nanosheet Architecture

The dominant GAA implementation uses horizontally stacked nanosheets (or nanowires):

```
Cross-section view:
  Gate surrounds each nanosheet
  +---Gate---+
  | +------+ |
  | |Sheet3| |     <- Multiple stacked nanosheets
  | +------+ |
  | +------+ |
  | |Sheet2| |
  | +------+ |
  | +------+ |
  | |Sheet1| |
  | +------+ |
  +----------+
```

Each nanosheet is a thin, wide ribbon of silicon completely enclosed by the gate material. Multiple nanosheets are stacked vertically to increase drive current.

### Key Characteristics

- **4-side gate control:** Gate wraps around the entire channel, providing the best possible electrostatic control
- **Variable width:** Unlike FinFETs where width is quantized by fin count, nanosheet width can be varied continuously by changing the sheet width
- **Higher drive per footprint:** Stacked nanosheets provide more effective channel width in the same area
- **Reduced leakage:** Superior gate control further reduces subthreshold and gate leakage

### GAA Implications for Physical Design

- **Even tighter metal pitches:** 2nm node features metal pitches below 20nm, making interconnect resistance and signal integrity even more critical
- **New cell architectures:** GAA enables different cell design tradeoffs. Sheet width and stack height become new optimization variables.
- **Increased self-heating:** Stacked channels have even more constrained thermal dissipation
- **BEOL remains the bottleneck:** Transistor improvement from GAA is significant, but wire delay continues to limit overall performance

## Mobility Enhancement Techniques

### Strain Engineering

Mechanical strain in the silicon channel increases carrier mobility and therefore drive current:

- **SiGe source/drain (for PMOS):** Compressive strain in the channel boosts hole mobility
- **Stress memorization technique (SMT):** Tensile stress for NMOS enhances electron mobility
- **Stressed liners:** Silicon nitride films with intrinsic stress deposited over transistors

Strain engineering has been used since the 90nm node and continues at advanced nodes. It provides 10-30% performance improvement at each generation.

### Channel Material Engineering

- **SiGe channel:** Higher hole mobility than pure silicon. Used for PMOS in some advanced processes.
- **High-k/Metal gate (HKMG):** Replacing SiO2 gate oxide with high-k dielectric (HfO2) allows a physically thicker gate insulator while maintaining the same electrical thickness, reducing gate leakage by 100x.
- **Future materials:** III-V compounds (InGaAs) for NMOS and Germanium for PMOS are under research for future nodes.

## Process Technology Impact on Physical Design

### Timing and Power

| Technology Trend | Timing Impact | Power Impact |
|---|---|---|
| Shorter gate length | Faster switching | Higher leakage |
| FinFET/GAA | Better drive, less variability | Lower leakage at same speed |
| Thinner wires | Higher wire resistance/delay | Higher wire dynamic power |
| Lower voltage | Less speed headroom | Lower dynamic power |
| More VT flavors | Better speed-power tradeoff | Finer leakage control |

### Design Rule Complexity

Each new node introduces more complex design rules:
- **Multi-patterning:** SADP (Self-Aligned Double Patterning), SAQP (Quad Patterning), and EUV reduce feature sizes but add coloring constraints
- **Minimum area rules:** Prevent reliability issues from overly small metal features
- **Via enclosure rules:** Ensure reliable via-to-metal connections
- **Cut rules for GAA:** New rules for nanosheet patterning and gate cuts

### Standard Cell Libraries at Advanced Nodes

Cell libraries become more constrained:
- Fewer routing tracks per cell (6T, 7.5T) to improve density
- Pin access becomes more challenging (fewer metal layers available for pin connections)
- More cell variants (VT flavors, drive strengths) to enable fine-grained optimization
- Complex cell layout rules require close collaboration between library design and PD

## Practical Relevance for PD Engineers

1. **Understand your technology's constraints.** Read the PDK design rule manual. Know the metal pitch, via rules, and routing track availability for your node.

2. **Wire delay matters more at each node.** Budget more effort for interconnect optimization (buffering, layer assignment, spacing) as you move to smaller nodes.

3. **Self-heating affects fast-corner timing.** At FinFET/GAA nodes, be aware that self-heating can reduce the expected FF corner speed advantage.

4. **Variability is technology-dependent.** FinFET and GAA have better variability than planar, which affects OCV derating values. Use the foundry-recommended AOCV/POCV tables.

5. **EUV vs. multi-patterning affects routing.** EUV layers have simpler design rules; multi-patterned layers have coloring constraints that the router must respect.

6. **Power density is increasing.** Smaller transistors in the same area means more switching in less space. Thermal analysis and power grid design are increasingly critical.

Process technology is the foundation on which all physical design is built. Staying current with technology evolution ensures that PD methodologies and tool flows are aligned with the capabilities and constraints of the silicon.
