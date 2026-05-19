# Hard Macro Integration: PLL, ADC/DAC, SerDes, PHY, and P&R Considerations

## Overview

Hard macros are pre-designed, pre-verified physical blocks that are integrated into an SoC as fixed-layout entities. Unlike standard cells that are placed and routed by the PnR tool, hard macros come with fixed GDS layouts, timing models, and abstract views. They include analog/mixed-signal IP such as PLLs, ADCs/DACs, SerDes transceivers, memory PHYs (DDR/LPDDR), and high-speed interfaces.

Integrating hard macros correctly is a critical PD skill. Poor macro integration causes timing failures, routing congestion, DRC violations, and signal integrity issues that are difficult to debug and fix.

## Common Hard Macro Types

### PLL (Phase-Locked Loop)

- Generates internal clocks from a reference clock
- Analog-sensitive: requires clean power supply and noise isolation
- Typically small (50x100 um to 200x300 um depending on node and features)
- Usually placed at the chip periphery near clock input pads
- May require dedicated analog power supply (AVDD/AVSS)

### ADC/DAC (Analog-to-Digital / Digital-to-Analog Converters)

- Convert between analog and digital signal domains
- Extremely sensitive to noise, substrate coupling, and power supply variation
- Require guard rings and isolation from digital switching noise
- Often need dedicated analog power/ground domains
- Placement near the analog IO pads to minimize analog signal routing

### SerDes (Serializer/Deserializer)

- High-speed serial interfaces (PCIe, USB, SATA, Ethernet)
- Include analog TX/RX circuits, clock recovery, and equalization
- Large macros (500x500 um or more)
- Must be placed at the die edge near high-speed IO pads
- Require strict power supply filtering and isolation
- Impedance-controlled routing from pad to macro

### Memory PHY (DDR/LPDDR/HBM)

- Physical interface between the memory controller and external memory
- Includes IO drivers, DLL/PLL, calibration circuits
- Very large macros (may be several mm in one dimension)
- Must be placed at die edge with direct access to memory IO pads
- Strict placement rules: PHY byte lanes must align with bump/pad assignments
- Data bus routing between controller and PHY is timing-critical

### Other Hard Macros

- **USB PHY**: USB 2.0/3.0 physical layer
- **MIPI PHY**: Camera/display interface
- **eFuse/OTP**: One-time programmable memory for calibration and security
- **Voltage regulators**: On-die LDOs or switched-capacitor regulators
- **Temperature sensors**: On-die thermal monitoring

## Views Required for Integration

Each hard macro must provide a complete set of views for the PD flow:

### LEF (Abstract View)

- Defines macro outline (bounding box dimensions)
- Pin locations, layers, and directions
- Routing blockages (layers blocked within macro for PnR tool)
- Power pin locations for grid connection
- The LEF abstract must be accurate -- incorrect pin positions cause LVS failures

### Liberty (.lib) Timing Model

- Timing arcs for all input-to-output paths
- Setup and hold times for input pins
- Clock-to-output delays
- Power consumption per operating mode
- Available at multiple PVT corners

### GDS/OASIS (Physical Layout)

- Complete physical layout for manufacturing
- Merged into the top-level GDS for tapeout
- Used for physical verification (DRC/LVS) at top level

### Verilog Model

- Behavioral model for functional simulation
- May include timing annotation for gate-level simulation

### SPICE/CDL Netlist

- Transistor-level netlist for LVS verification
- Required for top-level LVS flow

### Additional Views

- **SPEF/parasitic model**: For detailed timing analysis
- **EM model**: Electromigration current limits on macro pins
- **Noise model**: For signal integrity analysis
- **Antenna model**: Antenna diode information for antenna rule compliance

## Halo and Blockage Planning

### Placement Halo

A halo (or keep-out region) is an exclusion zone around a hard macro where standard cells cannot be placed:

- **Purpose**: Provides routing space for connections to macro pins and prevents congestion
- **Typical halo size**: 2-10 um per side (varies by macro and design)
- **Soft halo**: Cells are discouraged but allowed if needed (optimization can override)
- **Hard halo**: Cells are strictly prohibited

### Routing Blockage

Routing blockages prevent the router from using specific metal layers within or near the macro:

- **Internal blockage**: Metals used within the macro are blocked (defined in LEF)
- **Pin blockage**: Layers used for macro pins may need keep-clear zones for access routing
- **Halo routing blockage**: Additional routing blockage around macro to prevent shorts to internal routing
- **Partial blockage**: Some layers may be partially blocked (e.g., 50% congestion factor)

### Blockage Best Practices

- Block all metal layers used internally by the macro (from LEF)
- Add routing blockage on the pin layer extending 1-2 tracks beyond the macro for clean pin access
- Do not over-block -- excessive blockages waste routing resources
- Verify blockages by running DRC on the macro boundary region

## Timing Models for Hard Macros

### Liberty-Based Models

Standard Liberty models provide:
- Combinational delays (delay tables indexed by input slew and output load)
- Sequential timing (setup, hold, clock-to-Q)
- Transition time limits on inputs
- Maximum output capacitance limits

### ETM (Extracted Timing Model)

- A simplified timing model extracted from the full block timing
- Preserves interface timing while hiding internal details
- Used when full Liberty characterization is not available
- Accurate for block-level integration

### ILM (Interface Logic Model)

- Contains actual logic near the block boundary for more accurate timing
- Larger than ETM but more accurate
- Used in hierarchical timing closure flows

### Timing Integration Checklist

- Verify all required PVT corners are available
- Check that Liberty models include all operating modes
- Validate setup/hold constraints against expected clock frequencies
- Verify input transition and output load assumptions match the design context

## P&R Considerations

### Macro Placement Strategy

1. **Place macros first**: Hard macros should be placed during floorplanning, before standard cell placement
2. **Edge placement**: Macros with external IO connections (PHY, SerDes) must be at the die edge
3. **Orientation**: Choose macro orientation to align pins with routing channels and power grid
4. **Grouping**: Group related macros (e.g., multiple SRAM banks) to minimize interconnect
5. **Channel planning**: Ensure adequate routing channels between macros for signal and power routing

### Pin Access

- Verify that macro pins are accessible from the routing grid
- Pins on blocked layers need via stacks to reach routable layers
- Pins deep inside the macro (far from edges) may need pre-routes
- Pin density on one macro edge can create local congestion -- orient to distribute pin access

### Power Connection

- Connect macro VDD/VSS pins to the power grid with adequate via arrays
- Analog macros may need dedicated power domains with isolated supplies
- Verify IR drop from the power grid to macro power pins meets the macro's requirements
- Some macros have internal power routing that must align with the chip-level grid

### Signal Routing to Macros

- Route timing-critical signals to macro pins with minimum detour
- Shield sensitive analog signals from digital switching noise
- Use NDR (wider space/width) for high-speed signals to/from SerDes and PHY macros
- Avoid routing unrelated signals over sensitive analog macros

### Verification

- **DRC**: Run DRC at macro boundaries. Check for spacing violations between macro internal shapes and top-level routing
- **LVS**: Ensure macro CDL/SPICE netlist is included in top-level LVS. Verify pin names match
- **Antenna**: Check antenna rules on nets connected to macro pins
- **EM**: Verify current through macro pin connections meets EM limits

## Practical Guidance

1. **Get views early**: Request all macro views from the IP vendor early. Missing or incorrect views cause schedule delays
2. **Validate views**: Run DRC/LVS on the standalone macro before integration. Verify LEF matches GDS
3. **Plan analog isolation**: Analog macros need guard rings, dedicated supplies, and physical separation from noisy digital logic
4. **Document placement constraints**: Record macro placement rules (orientation, edge requirements, minimum spacing) in the design constraints
5. **Interface timing budgeting**: Budget timing for macro interface paths during RTL design, not during implementation
6. **Macro model updates**: When the IP vendor provides updated views, carefully merge them. Check for pin name changes, size changes, or timing changes
7. **Floorplan iterations**: Expect 3-5 floorplan iterations to optimize macro placement for routability, timing, and power
