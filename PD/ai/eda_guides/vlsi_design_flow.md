# Complete VLSI Design Flow

## Overview

The VLSI design flow transforms a product concept into manufactured silicon. It is a multi-stage pipeline involving architecture, logic design, verification, physical implementation, manufacturing, packaging, and production testing. Each stage has specific inputs, outputs, tools, and acceptance criteria. Understanding the complete flow end-to-end is essential for PD engineers, who must understand how upstream decisions affect physical implementation and how their work feeds downstream manufacturing and testing.

## Specification

The flow begins with a product specification that defines:

- **Functionality**: What the chip does, its interfaces, and its operating modes
- **Performance targets**: Clock frequency, throughput, latency
- **Power budget**: Total power consumption, power per operating mode
- **Area/cost target**: Die size constraint driven by package and manufacturing cost
- **Technology choice**: Foundry, process node, metal stack
- **Environmental requirements**: Temperature range, voltage range, reliability standards

The specification drives all subsequent design decisions. PD engineers should understand the spec because it determines the physical constraints they must meet.

## Architecture and Microarchitecture

Architects translate the specification into a hardware architecture:

- **Block partitioning**: Decompose the chip into functional blocks (CPU, memory subsystem, I/O, accelerators)
- **Interconnect architecture**: Bus topology, network-on-chip (NoC), or crossbar connecting the blocks
- **Memory hierarchy**: Cache sizes, SRAM vs. register file, external memory interface
- **Clock domains**: Number and relationship of clock domains, clock frequencies
- **Power domains**: Voltage islands, power gating strategy, always-on regions

Architecture decisions have profound physical implications. For example, a multi-clock-domain design requires clock domain crossing (CDC) logic and complicates CTS. A power-gated design requires isolation cells, level shifters, and retention registers.

## RTL Design

Designers write Register Transfer Level (RTL) code in Verilog or SystemVerilog that implements the microarchitecture.

- **Coding guidelines**: Follow synthesizable coding rules to avoid simulation-synthesis mismatches
- **Clock gating**: Insert clock gating cells to reduce dynamic power
- **Design for Test (DFT)**: Structure the RTL to accommodate scan chains, BIST, and JTAG
- **Lint checks**: Run linting tools (Spyglass, Ascent) to catch common coding errors early

RTL quality directly affects PD quality. Poorly structured RTL (long combinational paths, excessive muxing, unbalanced pipelines) makes timing closure difficult regardless of the PD engineer's skill.

## Functional Verification

Before synthesis, the RTL must be verified to be functionally correct:

- **Simulation**: Directed tests and random/constrained-random testbenches verify functional behavior
- **Formal verification**: Mathematically prove properties about the design (no deadlocks, protocol compliance)
- **Emulation/FPGA prototyping**: Run the design on emulation hardware for system-level validation
- **Coverage closure**: Code coverage, functional coverage, and assertion coverage must meet targets

Verification typically consumes 60-70% of the total design effort. PD engineers depend on a verified netlist; functional bugs discovered after physical implementation waste weeks of PnR work.

## Logic Synthesis

Synthesis transforms RTL into a gate-level netlist using the target technology library.

- **Tool**: Design Compiler (Synopsys), Genus (Cadence)
- **Inputs**: RTL, SDC constraints, technology libraries (.lib, .lef)
- **Outputs**: Gate-level netlist (Verilog), timing reports, area reports, power reports
- **Key decisions**: Target clock period, optimization effort, multi-Vt strategy, clock gating style

Synthesis sets the baseline for all subsequent PD steps. Post-synthesis timing and area estimates should be within 10-15% of final signoff values.

## DFT Insertion

Design for Testability structures are inserted to enable post-manufacturing testing:

- **Scan insertion**: Replace flip-flops with scan flip-flops and stitch them into scan chains
- **BIST**: Built-In Self-Test for memories (MBIST) and logic (LBIST)
- **Boundary scan**: JTAG (IEEE 1149.1) for board-level testing
- **Compression**: Test data compression/decompression to reduce test time and cost
- **ATPG**: Automatic Test Pattern Generation produces test vectors that detect manufacturing defects

DFT adds 5-15% area overhead and creates additional timing constraints (scan shift frequency, capture clock requirements). PD engineers must handle these constraints during implementation.

## Floorplanning

Floorplanning is the first physical design step, defining the chip's spatial organization.

- **Die/core sizing**: Determine die dimensions based on area estimates and package constraints
- **Macro placement**: Position SRAMs, analog IP, I/O pads, and other hard macros
- **Power grid planning**: Define power/ground grid topology, stripe widths, and via stacks
- **Pin assignment**: Assign signal and power pins at block boundaries
- **Partition planning**: For hierarchical designs, define block boundaries and interface regions

A good floorplan makes everything downstream easier. A bad floorplan makes timing closure nearly impossible. Experienced PD engineers spend significant time on floorplan exploration.

## Placement

Placement assigns physical locations to all standard cells within the core area.

- **Global placement**: Initial coarse placement optimizing wirelength and congestion
- **Legalization**: Snap cells to the placement grid, resolve overlaps
- **Detailed placement**: Fine-tune placement for timing optimization
- **Optimization**: Cell sizing, buffer insertion, and logic restructuring during placement

Post-placement metrics (utilization, congestion, estimated timing) provide the first realistic assessment of whether the design will close.

## Clock Tree Synthesis (CTS)

CTS builds the physical clock distribution network.

- **Clock tree topology**: H-tree, fishbone, mesh, or hybrid
- **Buffer/inverter insertion**: Build the tree using clock buffers/inverters with balanced loading
- **Skew targets**: Minimize intra-clock skew while managing inter-clock relationships
- **Useful skew**: Intentionally skew clocks to fix timing violations (borrow time from adjacent stages)
- **Clock gating integration**: Ensure clock gating cells are properly placed and timed within the tree

CTS converts ideal clock assumptions into real clock networks. Post-CTS timing often reveals new violations that were hidden by ideal clock analysis.

## Routing

Routing creates the physical metal connections between cells.

- **Global routing**: Assign nets to routing regions, plan layer usage
- **Track assignment**: Assign nets to specific routing tracks
- **Detail routing**: Create exact wire geometries, insert vias, resolve DRC violations
- **Search and repair**: Iteratively fix remaining DRC violations
- **Shielding**: Add shielding wires for sensitive signals (clocks, critical data)

Routing quality affects timing (wire delay, crosstalk), power (wire switching, coupling capacitance), and manufacturability (DRC cleanliness, yield).

## Post-Route Optimization

After routing, additional optimization passes improve QoR:

- **Timing optimization**: Resize cells, insert buffers, swap pin connections
- **Hold fixing**: Insert delay buffers to fix hold violations
- **Crosstalk optimization**: Widen spacing, add shields, resize drivers
- **Signal integrity fixes**: Address noise, glitch, and SI-induced timing violations
- **Power optimization**: Multi-Vt swap (replace LVT with HVT where timing permits) to reduce leakage

## Signoff

Signoff is the final verification step before tapeout, confirming that the design meets all requirements.

### Timing Signoff

- **STA**: Run PrimeTime or Tempus across all MMMC scenarios
- **Requirements**: WNS >= 0, TNS = 0, no hold violations, across all corners and modes
- **SI-aware STA**: Include crosstalk effects (delta delays, glitch analysis)
- **On-chip variation (OCV)**: Apply derating factors for local process variation (AOCV, SOCV)

### Physical Signoff

- **DRC**: Zero violations (Calibre, ICV, Pegasus)
- **LVS**: Layout matches schematic (zero mismatches)
- **ERC**: Electrical rule checks clean (antenna, latch-up, ESD connectivity)
- **Metal density**: Meets minimum/maximum density requirements after fill

### Power Signoff

- **IR drop analysis**: Static and dynamic IR drop within limits
- **EM analysis**: Electromigration current density within limits for all wires and vias
- **Power estimation**: Total power within the budget

### Reliability Signoff

- **Hot carrier injection (HCI)**: Lifetime analysis for high-stress transistors
- **NBTI/PBTI**: Threshold voltage degradation over operating life
- **ESD compliance**: ESD protection structures meet target levels (CDM, HBM)

## Tapeout

Tapeout is the delivery of the final GDSII file to the foundry.

- **GDSII generation**: Merge all blocks, IP, fill, and chip-level structures
- **Final DRC/LVS**: Run full-chip verification on the merged GDSII
- **Chip assembly**: Add seal ring, scribe lane, alignment marks, chip ID
- **Data preparation**: Format conversion, fracturing for mask generation
- **Handoff**: Deliver to the foundry via secure transfer

## Packaging

After wafer fabrication, individual dies are packaged for use on circuit boards.

- **Wafer test**: Probe test at wafer level to identify good dies
- **Die singulation**: Cut the wafer into individual dies
- **Die attach**: Bond the die to the package substrate
- **Wire bond or flip-chip**: Connect die pads to package pins
- **Encapsulation**: Protect the die with molding compound
- **Package test**: Test the packaged part under operating conditions

## Production Testing

Production testing ensures that every shipped chip is functional:

- **Scan test**: Apply ATPG patterns through scan chains to detect stuck-at and transition faults
- **BIST**: Run built-in self-test for memories and logic
- **Functional test**: Run abbreviated functional patterns
- **Speed binning**: Sort chips by maximum operating frequency
- **Burn-in**: Accelerated stress testing to screen infant mortality failures (optional, for high-reliability parts)

## Flow Iteration

The VLSI flow is not purely sequential. Key iteration loops include:

- **Synthesis-PnR loop**: Timing feedback from PnR improves synthesis constraints
- **ECO loop**: Post-signoff fixes require targeted netlist changes and incremental implementation
- **Verification-implementation loop**: Functional bugs found during implementation require RTL fixes
- **Foundry feedback loop**: Foundry DRC updates or waiver rejections require design modifications

A mature PD methodology minimizes the number and severity of these iterations through early analysis, conservative margins, and automated regression tracking.
