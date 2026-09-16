# IO Libraries: Cell Types, ESD, Pad Ring Design, and IO Timing

## Overview

Input/Output (IO) cells form the interface between the chip's internal logic and the external world. IO libraries provide a collection of pre-designed, characterized cells that handle signal buffering, voltage level shifting, electrostatic discharge (ESD) protection, and pad connectivity. IO design is a specialized discipline within physical design, and incorrect IO planning can cause chip failure through ESD damage, signal integrity issues, or inability to route the pad ring.

## IO Cell Types

### Input Cells

Input cells receive signals from external sources and present them to the core logic:

- **Standard input**: Basic CMOS input buffer with Schmitt trigger option for noise immunity
- **Differential input**: Receives differential signal pairs (e.g., LVDS, CML)
- **Tolerant input**: Handles input voltages higher than the core supply (e.g., 3.3V-tolerant input on a 1.8V design)
- **Analog input**: Passes analog signals through to internal circuitry with minimal distortion

Input cell features:
- Input threshold levels (CMOS, TTL, Schmitt trigger)
- Input delay and capacitance specifications
- Hysteresis for noise rejection (Schmitt trigger)
- Optional internal pull-up or pull-down resistors

### Output Cells

Output cells drive signals from the core logic to external loads:

- **Standard output**: Push-pull CMOS output driver
- **Open-drain output**: NMOS pull-down only; requires external pull-up resistor
- **Tri-state output**: Output can be driven high, low, or placed in high-impedance state
- **Differential output**: Drives differential signal pairs

Output cell features:
- Drive strength selection (2mA, 4mA, 8mA, 12mA, 16mA, 24mA)
- Slew rate control (fast/slow edge rate)
- Supply voltage (1.2V, 1.8V, 2.5V, 3.3V)
- Impedance matching (series termination resistors)

### Bidirectional Cells

Bidirectional IO cells combine input and output functions:

- Controlled by an output enable (OEN) signal
- When OEN is active, the cell drives output; when inactive, it receives input
- Most general-purpose IOs are bidirectional
- Available in various drive strengths and voltage standards

### Special IO Cells

- **Analog IO**: Pass-through cells for analog signals with ESD protection but no digital buffering
- **Power/ground pads**: Dedicated cells for VDD, VSS, VDDIO connections
- **Supply clamp cells**: ESD clamp circuits placed between power and ground pads
- **Corner cells**: Structural cells at pad ring corners for physical continuity
- **Filler cells (IO filler)**: Fill gaps between IO cells in the pad ring
- **Breaker cells**: Separate different IO power domains in the pad ring

## ESD Protection

### Why ESD Protection is Critical

Electrostatic discharge events (human body model: 2kV, charged device model: 500V) can destroy gate oxides in nanoseconds. Every pin that connects to the outside world must have ESD protection structures.

### ESD Protection Structures

- **Primary ESD clamp**: Large diodes or SCR (silicon controlled rectifier) structures at every IO pad. Shunts ESD current to power/ground rails
- **Secondary ESD clamp**: Smaller series resistance and diodes closer to the core. Limits current reaching thin-oxide core devices
- **Power clamp**: VDD-to-VSS clamp that provides a discharge path between supply rails during ESD events
- **CDM protection**: Charged device model protection requires whole-chip ESD strategy, not just per-pin protection

### ESD Design Rules

- Minimum number of power clamp cells per power domain
- Maximum distance from IO pad to nearest power clamp
- Minimum IO-to-power-pad spacing requirements
- Bus resistance limits from pad to clamp
- Power/ground bus continuity requirements around the pad ring

### PD Impact

- ESD structures consume significant area within IO cells (30-50% of IO cell area)
- Power clamp cells must be distributed evenly around the pad ring
- IO power ring resistance must be low enough for effective ESD clamping
- Missing or incorrectly placed ESD cells can result in chip failure during qualification testing

## Pad Ring Design

### Pad Ring Architecture

The pad ring is the ring of IO cells arranged around the chip periphery:

- IO cells are placed in rows along each die edge (top, bottom, left, right)
- Core logic is inside the pad ring
- Power/ground pads are distributed among signal pads
- Corner cells connect the pad ring at the four die corners

### Pad Ring Planning Steps

1. **IO count**: Determine total number of IOs (signal + power + ground)
2. **Die size estimation**: Pad-limited or core-limited:
   - Pad-limited: IO count determines minimum die perimeter. Die must be large enough to fit all pads
   - Core-limited: Logic area determines die size; IO pads fit easily
3. **Pad pitch**: IO cell width determines how many pads fit per edge
   - Wire-bond: pad pitch 50-100 um (staggered or inline)
   - Flip-chip: bump pitch 100-200 um on a 2D array
4. **Power pad distribution**: Typically 20-30% of pads are power/ground. Distribute evenly for low impedance
5. **Signal grouping**: Group related signals (buses, clocks) on the same die edge for clean routing

### Pad Ring Construction

```
Typical pad ring construction in a PD tool:
1. Define IO cell placement rows on each die edge
2. Place IO cells according to the pad assignment
3. Insert corner cells
4. Insert IO filler cells to fill gaps
5. Insert power/ground pads at required intervals
6. Insert breaker cells at power domain boundaries
7. Connect IO power ring (VDDIO, VSSIO, VDD, VSS)
```

### Wire-Bond vs. Flip-Chip

**Wire-bond:**
- Pads around die periphery, connected by bond wires to package leads
- Single row or staggered dual-row pad arrangement
- Lower cost for low pin count
- Higher inductance per connection
- Pad pitch: 50-80 um

**Flip-chip:**
- Bumps on a 2D array across the die surface
- No peripheral pad ring needed (though IO cells may still be at periphery)
- Lower inductance, better power delivery
- Supports much higher IO count
- Requires RDL (redistribution layer) routing from IO cells to bump locations
- Higher package cost

## IO Power Domains

### Multiple IO Voltages

Modern SoCs interface with external devices at different voltage levels:
- Core logic: 0.7-0.9V
- LPDDR: 1.1V (LPDDR5)
- GPIO: 1.8V or 3.3V
- LVDS: 2.5V
- USB: 3.3V

Each IO voltage requires its own VDDIO supply domain:
- Separate VDDIO/VSSIO rings for each voltage
- Breaker cells isolate different IO power domains
- Level shifters convert between core voltage and IO voltage (often built into the IO cell)

### IO Power Ring

- VDDIO and VSSIO rings run along the pad ring, connecting IO cell power pins
- Core VDD and VSS also run through the pad ring for ESD and core power delivery
- Ring width must support the total current draw of all IO cells
- EM analysis on IO power rings is critical for high-drive-strength configurations

## IO Timing

### IO Cell Timing Characteristics

- **Input delay**: Time from pad transition to internal logic output
- **Output delay**: Time from internal logic input to pad transition
- **Setup/hold time**: Requirements for input data relative to input clock
- **Drive impedance**: Output driver impedance (affects signal integrity)
- **Slew rate**: Edge rate at the pad (affects EMI and signal integrity)

### Timing Constraints for IO

- IO timing constraints must account for board-level delays, package delays, and IO cell delays
- Input constraints: set_input_delay defines when data arrives at the pad relative to the clock
- Output constraints: set_output_delay defines when data must be valid at the pad
- IO cell delay is included in the Liberty model and accounted for by STA

### Signal Integrity at IOs

- **Simultaneous switching noise (SSN)**: Multiple outputs switching simultaneously causes ground bounce. Mitigate by distributing power/ground pads and staggering output switching
- **Impedance matching**: Match output driver impedance to PCB trace impedance (typically 50 ohm) to minimize reflections
- **Crosstalk**: Adjacent IO pads can couple. Separate sensitive signals with ground pads

## Practical Guidance

1. **Plan IO early**: IO count and type directly affect die size for pad-limited designs. Start IO planning during architecture phase
2. **Power pad ratio**: Use at least 1 power/ground pair per 4-5 signal pads. More for high-speed interfaces
3. **ESD compliance**: Verify ESD protection meets the target specification (HBM 2kV, CDM 500V) with the IO library vendor
4. **Corner cells and fillers**: Never leave gaps in the pad ring. Every space must have an IO cell, filler, or breaker
5. **IO ring routing**: Plan the IO power ring before placing the first IO cell. Ring width and layer assignment affect routability
6. **Drive strength selection**: Use the minimum drive strength that meets timing. Over-driving wastes power and increases SSN
7. **Domain crossings**: Verify level shifter and isolation cell placement at every IO voltage domain boundary
