# Pin Assignment: IO Ring Planning, Pin Grouping, and Escape Routing

## Overview

Pin assignment (also called pin placement) determines where signals enter and exit a block or the chip. For top-level chip design, this means assigning signals to IO pads and bump locations. For block-level design in hierarchical flows, this means placing logical pins on the block boundary where other blocks or top-level routing will connect.

Pin placement profoundly impacts routability, timing, and congestion. Poorly placed pins force signals to travel long distances, create routing bottlenecks, and cause timing violations. Good pin placement aligns with the internal logic placement and creates clean, short routing paths.

## Top-Level IO Ring Planning

### IO Pad Assignment

For a chip with a peripheral IO pad ring, each signal must be assigned to a specific pad location:

1. **Interface grouping**: Group pads by interface (DDR, PCIe, GPIO, SPI, I2C, etc.)
2. **Edge assignment**: Assign each interface to a die edge based on package and board routing
3. **Power pad distribution**: Interleave VDD/VSS pads among signal pads (1 power pair per 4-5 signals)
4. **Noise-sensitive separation**: Separate analog/RF pads from high-speed digital switching outputs
5. **Ground pads between groups**: Place dedicated ground pads between different interface groups

### Flip-Chip Bump Map

For flip-chip designs, signals are assigned to bumps on a 2D array:

- **Signal bumps**: Core area bumps for signals, peripheral bumps for legacy IO
- **Power/ground bumps**: 30-50% of all bumps are power/ground for low impedance power delivery
- **Controlled impedance**: High-speed signals need specific bump locations for impedance matching
- **Thermal bumps**: Some bumps serve as thermal heat sinks (connected to ground planes)
- **Bump map drives RDL routing**: The bump map determines redistribution layer (RDL) routing from IO cells to bumps

### Package Co-Design

Pin assignment must be co-designed with the package:
- Chip pad locations must map to package ball/lead locations with legal routing
- Wire-bond designs need pad-to-lead mapping that avoids crossing wires
- Flip-chip designs need bump-to-ball routing within the substrate
- Early package co-design prevents costly respins

## Block-Level Pin Placement

### Pin Placement Principles

For hierarchical blocks, pins are placed on the block boundary at specific metal layers:

1. **Face the connection**: Place pins on the edge closest to the connecting logic/block
2. **Minimize detour**: Pins should be near the internal logic they serve
3. **Distribute uniformly**: Avoid concentrating all pins on one edge
4. **Layer selection**: Place pins on the metal layer that aligns with the top-level routing direction
5. **Grid alignment**: Pins must be on the routing grid for legal connections

### Pin Grouping

Group related pins together for clean routing:

- **Bus pins**: Data bus bits should be ordered and adjacent (D[0] through D[31] in sequence)
- **Control signals**: Group address, control, and clock signals for each interface
- **Clock pins**: Place clock pins centrally on the edge to balance clock tree to internal sinks
- **Power pins**: Distribute VDD/VSS pins on all edges for power grid connectivity

### Pin Spacing

- **Minimum spacing**: At least 1-2 routing track pitches between pins for clean escape routing
- **Bus spacing**: Bus pins may use every other track (1-track gap) or every track (dense)
- **Clock pin clearance**: Extra spacing around clock pins to reduce crosstalk coupling
- **Pin-to-pin spacing on same net**: If multiple pins exist for the same net (power), space them for uniform distribution

## Bus Ordering

### Why Bus Order Matters

If bus bits are randomly ordered, the routes will cross each other, creating a twisted bus that:
- Increases wire length and delay
- Creates routing congestion at the crossover region
- Wastes routing resources resolving the twist

### Ordering Strategies

- **Bit-order alignment**: Match the internal bit order. If the internal data bus flows left-to-right from D[0] to D[31], place pins in the same order
- **MSB/LSB grouping**: Group most-significant and least-significant bytes near their respective logic
- **Byte-lane ordering**: For memory interfaces, group pins by byte lane to match PHY requirements
- **Address bus**: Order address bits to match the decoder/memory controller layout

### Handling Bus Reversal

Sometimes the optimal internal order conflicts with the package/board order. Options:
- Accept the crossing and let the router resolve it (adds congestion)
- Insert a bus-reversal region with dedicated routing channels
- Adjust internal placement to match the pin order (preferred)

## Feedthrough Planning

### What Are Feedthroughs?

Feedthrough signals pass through a block without connecting to any internal logic. In hierarchical designs, a signal from Block A may pass through Block B to reach Block C.

### Feedthrough Strategies

1. **Avoid feedthroughs**: Rearrange the floorplan so signals do not need to pass through unrelated blocks
2. **Dedicated feedthrough channels**: Reserve routing corridors through the block for feedthrough signals
3. **Feedthrough pins**: Create input/output pin pairs on opposite block edges for signals that must pass through
4. **Top-level routing**: Route feedthrough signals at the top level over the block (using upper metals) instead of through it

### Feedthrough Impact

- Each feedthrough signal consumes routing resources within the block
- Many feedthroughs can significantly increase block congestion
- Feedthroughs add delay to the passing signal
- Plan feedthrough count and location during floorplanning

## Pin Access Analysis

### Purpose

Pin access analysis verifies that every block pin can be reached by the top-level router without DRC violations. Issues include:

- Pins blocked by other routing or obstructions
- Pins on layers that cannot connect to the top-level routing direction
- Insufficient space between pins for via-down connections
- Pins in congested regions where no routing resources are available

### Analysis Methods

1. **Visual inspection**: Display pin locations overlaid with the routing grid and blockages
2. **Trial routing**: Run a quick global route at the top level to identify pin access failures
3. **Access point analysis**: PnR tools can report accessible routing tracks for each pin
4. **DRC checking**: Run DRC on the pin region to verify spacing and via legality

### Fixing Pin Access Issues

- Move pins to less congested locations
- Change pin layer to match the routing direction
- Add via access points near pins
- Widen the routing channel adjacent to dense pin areas
- Reduce the number of pins on a single edge

## Escape Routing

### Definition

Escape routing is the routing from a dense array of pins (e.g., bump pads or macro pins) to the general routing fabric. The challenge is extracting all signals from a dense region without creating congestion or DRC violations.

### Bump Escape Routing (Flip-Chip)

In flip-chip designs, signals must be routed from bump pad locations to the IO cells or directly to the core:
- Inner bumps need to escape through the surrounding bump array
- Escape routing uses multiple metal layers, typically upper metals
- Each row of bumps uses a different metal layer for escape
- Power/ground bumps simplify escape by not requiring signal routing

### Macro Pin Escape

Large macros with many pins (e.g., wide SRAM banks) create similar escape challenges:
- Bus pins must fan out from the dense pin array to the routing fabric
- Use multiple metal layers for escape routing
- Plan escape direction during macro placement

### Escape Routing Guidelines

1. Allocate 2-4 metal layers for escape routing from dense pin arrays
2. Route innermost pins on the lowest available layer, outermost on higher layers
3. Ensure enough routing tracks exist between pin rows for escape routes
4. Avoid routing escape patterns that conflict with the power grid

## Practical Guidance for PD Engineers

1. **Pin placement is a floorplanning decision**: Do not defer pin placement to later stages. Fix pin locations during floorplanning
2. **Co-optimize pin placement and macro placement**: Macro orientation and pin placement are interdependent. Iterate together
3. **Bus ordering saves effort**: Spending 30 minutes on correct bus ordering saves days of routing congestion debugging
4. **Validate with trial routing**: After pin placement, run a quick global route to verify routability. Fix issues before committing
5. **Document pin assignments**: Create a pin assignment spreadsheet or constraint file that maps every signal to its physical pin location
6. **Plan for ECOs**: Leave some unassigned pin positions for late-stage signal additions
7. **Clock pin centrality**: Place clock input pins at the center of the edge to minimize clock distribution skew
8. **Power pin adequacy**: Ensure sufficient VDD/VSS pins for the block's current requirements. Under-provisioned power pins cause IR drop issues at the block boundary
9. **Review with package team**: Pin assignments affect package routing. Get package team review before finalizing
10. **Feedthrough budgeting**: Limit feedthroughs to 5-10% of total routing capacity through any block
