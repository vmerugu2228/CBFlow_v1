# Design Reuse and IP Integration

## Overview

Design reuse is a cornerstone of modern SoC development. No team designs every block from scratch: processors, memories, PHYs, PLLs, and standard interfaces come as pre-designed intellectual property (IP). Effective reuse reduces design time, risk, and verification effort, but it demands rigorous integration practices. This guide covers the types of reusable IP, platform-based design strategies, integration checklists, and the abstraction models that enable seamless physical integration.

## Types of Reusable IP

### Hard Macros

Hard macros are pre-placed and pre-routed blocks delivered as GDSII (or equivalent). The physical implementation is fixed.

- **Examples**: SRAM compilers, analog blocks (PLLs, ADCs, DACs), I/O pads, standard cell memories
- **Deliverables**: GDSII, LEF abstract, timing models (.lib for multiple corners), power models, CDL netlist for LVS
- **Advantages**: Guaranteed timing, area, and power; no implementation effort by the integrator
- **Disadvantages**: Inflexible (cannot be resized or reshaped), technology-specific, long lead time for new versions
- **Integration concerns**: Pin placement must align with the surrounding logic; keep-out zones and blockage layers must be respected

### Soft Macros

Soft macros are delivered as synthesizable RTL. The integrator implements them using their own flow and libraries.

- **Examples**: Bus protocol controllers (AXI, AHB), UART/SPI/I2C peripherals, DMA engines
- **Deliverables**: RTL (Verilog/SystemVerilog), constraints (SDC), verification testbenches, integration guide
- **Advantages**: Portable across technology nodes, flexible (can be optimized for the target application)
- **Disadvantages**: Timing/area/power are not guaranteed until implementation; more integration work required
- **Integration concerns**: Must be synthesized and implemented with the target libraries; constraint compatibility must be verified

### Firm Macros

Firm macros are an intermediate form: partially implemented (e.g., placed but not routed, or structurally optimized netlist) but not fully hardened.

- **Examples**: Some DSP cores, crypto accelerators
- **Deliverables**: Gate-level netlist with placement guidance, constraints, timing models
- **Use case**: When the IP vendor wants to guarantee timing at the gate level but allow the integrator flexibility in routing and physical optimization

## Platform-Based Design

### Concept

Platform-based design defines a reusable physical platform that multiple derivative products share. The platform includes:

- A fixed floorplan with pre-placed hard macros and power grid
- A qualified PnR flow and constraint methodology
- Reusable clock tree topologies
- Standardized I/O ring and bump map

### Benefits

- **Derivative designs** can be created by swapping soft IP blocks or adjusting parameters without re-doing the entire physical implementation
- **Reduced risk**: The platform has already been silicon-proven
- **Faster time-to-market**: Only the changed blocks require full implementation; the platform infrastructure is inherited

### Implementation Strategy

1. Define the platform architecture with the largest/most complex derivative in mind
2. Implement and silicon-validate the platform
3. For each derivative, modify only the changed blocks; keep the platform floorplan, power grid, and I/O ring intact
4. Rerun signoff on modified regions; full-chip signoff may be abbreviated if changes are isolated

### Challenges

- Platform must be designed with sufficient flexibility to accommodate all planned derivatives
- Over-constraining the platform limits derivative options; under-constraining leads to integration problems
- Configuration management becomes critical: tracking which derivative uses which version of each IP

## IP Integration Checklist

### Pre-Integration Checks

Before beginning physical integration of an IP block:

- [ ] **Deliverables complete**: All required files received (LEF, .lib, GDSII, CDL, Verilog model)
- [ ] **Version verified**: IP version matches the project's qualified version; no unauthorized updates
- [ ] **Technology match**: IP is characterized for the correct foundry, process node, and metal stack
- [ ] **Corner coverage**: Timing models (.lib) available for all required PVT corners
- [ ] **Voltage compatibility**: IP operating voltage matches the power domain it will be placed in
- [ ] **Pin naming convention**: IP pins follow the project's naming convention (or a mapping is documented)

### Physical Integration Checks

During floorplan and placement:

- [ ] **Macro placement**: IP placed per floorplan plan, respecting minimum spacing to other macros and core boundary
- [ ] **Orientation**: Correct orientation (N, S, FN, FS, E, W) per IP integration guide; incorrect orientation can cause DRC violations or incorrect power rail connections
- [ ] **Power connections**: IP power/ground pins connected to the correct power domain and voltage level
- [ ] **Keep-out zones**: Placement and routing blockages created per IP integration guide
- [ ] **Pin access**: IP signal pins are accessible by the router (not blocked by other macros or obstructions)
- [ ] **Well taps**: Proper well tap placement around the macro to prevent latch-up
- [ ] **Boundary cells**: End-cap and boundary cells placed adjacent to the macro as required by the technology

### Timing Integration Checks

- [ ] **Constraint compatibility**: IP timing constraints (SDC) are compatible with the top-level constraint methodology
- [ ] **Clock connectivity**: IP clock pins receive the correct clock signal with appropriate skew management
- [ ] **Interface timing**: Timing budgets at IP boundaries are consistent between the IP model and the surrounding logic
- [ ] **Multi-mode handling**: IP operating modes (active, standby, sleep) are correctly modeled in the MMMC setup
- [ ] **Extraction correlation**: If using extracted parasitics from the IP vendor, verify they correlate with the project's extraction methodology

### Signoff Checks

- [ ] **LVS clean**: IP instance passes LVS (layout vs. schematic) at the chip level
- [ ] **DRC clean**: No DRC violations at IP boundaries or within IP keep-out zones
- [ ] **ERC clean**: Electrical rule checks pass (correct power/ground connectivity, no floating nets)
- [ ] **Antenna clean**: No antenna violations on nets connecting to IP pins
- [ ] **IR drop**: IP power pins meet voltage drop requirements under load

## Timing Abstraction

### ETM (Extracted Timing Model)

An ETM is a black-box timing model extracted from the IP's full implementation. It contains:

- Input/output pin timing arcs (setup, hold, propagation delay)
- Clock-to-output delays
- No internal detail (paths, cells, nets are hidden)

**When to use**: For signoff STA when the IP vendor does not provide internal detail. ETMs are fast to load and provide accurate boundary timing.

**Limitation**: Cannot analyze paths through the IP; treats it as a black box.

### ILM (Interface Logic Model)

An ILM retains the logic near the IP's boundary (typically one or two stages of registers and combinational logic) while abstracting away the interior.

- **When to use**: For STA with better accuracy than ETM; allows the timer to see logic near the boundary
- **Advantage over ETM**: Can model complex interactions between closely spaced input/output paths
- **Limitation**: Larger than ETM; still cannot analyze deep internal paths

### Liberty (.lib) Models

Standard timing models provided by IP vendors in Liberty format. These are the most common timing abstraction.

- **NLDM**: Non-Linear Delay Model (lookup table of delay vs. input slew and output load)
- **CCS**: Composite Current Source (more accurate for advanced nodes; models current waveforms)
- **ECSM**: Effective Current Source Model (similar to CCS, used by some tools)

## Physical Abstraction

### LEF (Library Exchange Format)

The LEF abstract describes the physical footprint of the IP:

- **Dimensions**: Width, height, and origin
- **Pin locations**: Metal layer, shape, and direction for each pin
- **Obstructions**: Metal layers blocked inside the IP (router cannot use these layers over the IP)
- **Symmetry**: Allowed orientations
- **Site definition**: For standard cells, defines the placement grid

### GDS vs. LEF

The GDSII contains the full physical layout; the LEF is an abstraction for PnR tools. PnR tools use LEF for placement and routing; GDSII is used only for final merge and physical verification.

### Abstraction Quality

Poor LEF abstractions cause integration failures:

- Missing pin shapes lead to unroutable connections
- Missing obstructions lead to DRC violations (router uses metal that the IP actually occupies)
- Incorrect dimensions lead to placement overlaps
- Always validate the LEF against GDSII using abstraction verification tools

## IP Integration Flow

A typical IP integration flow:

1. **Receive IP deliverables** and run pre-integration checks
2. **Import into design database**: Read LEF for physical, .lib for timing, Verilog for logical
3. **Place in floorplan**: Position the IP, set orientation, create blockages
4. **Connect power**: Route power/ground to IP power pins
5. **Constrain interfaces**: Create timing constraints for IP boundaries
6. **Implement surrounding logic**: Run PnR with IP as a fixed obstruction
7. **Run signoff**: STA with ETM/ILM, DRC/LVS with GDSII, power analysis with power model
8. **Merge GDSII**: Combine IP GDSII with the rest of the design for tapeout

## Common Integration Pitfalls

- **Stale IP versions**: Using an old IP version that has known bugs or missing corners
- **Incorrect power domain mapping**: Connecting IP to the wrong voltage rail or missing level shifters at domain boundaries
- **Missing blockages**: Not creating routing blockages per the IP guide, leading to shorts
- **Pin access violations**: Placing macros too close together so that pins are unreachable by the router
- **Clock skew imbalance**: Not including IP internal clock delay in the clock tree balancing strategy
- **Thermal issues**: Placing high-power IP blocks adjacent to each other without adequate thermal spacing

Diligent use of the integration checklist and automated verification at each step prevents most of these issues.
