# Operating Modes: Design Modes and Mode-Specific Constraints

## What Are Operating Modes?

An operating mode represents a distinct functional state of a chip where the active logic paths, clock configurations, and timing requirements differ from other states. Modern SoCs have multiple operating modes because a single chip must support normal operation, testing, debugging, and various power-saving states. Each mode requires its own set of timing constraints, and physical design must ensure timing closure across all modes simultaneously.

## Functional Mode

Functional mode is the primary operating state where the chip performs its intended function. This mode has the highest clock frequencies, the most complex clock structures, and the largest number of active timing paths.

### Characteristics
- All functional clocks are active at their target frequencies
- All logic paths are sensitizable (no test muxes selected, no bypass modes)
- Full clock tree structure is active including clock gating cells
- Represents the most demanding timing scenario for setup analysis

### Constraint Considerations
- Primary clocks defined with `create_clock` at target frequency
- Generated clocks for all PLL outputs, dividers, and clock muxes
- IO constraints (`set_input_delay`, `set_output_delay`) reflect real board timing
- Inter-clock domain exceptions (false paths, multicycle paths) model actual CDC behavior
- Clock gating checks enabled

Multiple sub-modes may exist within functional mode if the design supports different performance levels (e.g., turbo mode at 2GHz vs. nominal mode at 1.5GHz) or different interface configurations.

## Test and Scan Modes

Test modes are used during manufacturing test to detect fabrication defects. Scan-based testing is the dominant DFT methodology.

### Scan Shift Mode
- Scan clocks are active; functional clocks are either gated or driven by the scan clock through test muxes
- Clock frequency is typically much lower than functional (e.g., 100-500MHz vs. 2GHz)
- Shift paths go through scan chain connections (SI -> Q -> SI of next flop)
- Long combinational paths through scan chain reordering can be timing-critical despite the lower frequency
- All scan enables are asserted

```tcl
# Scan shift mode SDC
create_clock -name scan_clk -period 5.0 [get_ports scan_clk]
set_case_analysis 1 [get_pins test_mux/sel]
set_case_analysis 1 [get_ports scan_enable]
# Disable functional clock paths
set_false_path -from [get_clocks func_clk]
```

### Scan Capture Mode
- A single clock pulse captures the response of combinational logic to the scanned-in pattern
- Capture is typically at-speed (functional frequency) for delay fault testing
- Launch-off-shift (LOS) or launch-off-capture (LOC) determines the timing relationship
- Only one or two clock edges are applied, so dynamic power management logic may not be in steady state

### Compression Mode (DFTMAX, LBIST)
- Test compression logic (compressors/decompressors) is active
- Additional timing paths through compression logic must be constrained
- EDT (Embedded Deterministic Test) or codec logic introduces paths not present in functional mode

### ATPG Considerations for Physical Design
- Scan chain routing can create long physical paths -- scan reordering post-placement shortens these
- Hold violations in scan chains are critical because buffer insertion for hold affects area and congestion
- Test clocks often have different clock tree structures than functional clocks

## JTAG / Boundary Scan Mode

The JTAG interface (IEEE 1149.1) provides boundary scan access and debug functionality.

### Characteristics
- TCK (Test Clock) runs at low frequency, typically 10-50MHz
- TAP controller state machine is active
- Boundary scan cells around IO pads are active
- Internal scan may be accessed through JTAG for in-system debug

### Constraint Requirements
- TCK defined as a separate clock domain
- Paths from functional clocks to TCK domain are false paths (or have specific multicycle requirements)
- Boundary scan paths have relaxed timing due to low TCK frequency
- Focus is on hold timing since TCK is slow but data paths through boundary scan cells can be short

```tcl
# JTAG mode SDC
create_clock -name TCK -period 50.0 [get_ports TCK]
set_false_path -from [get_clocks {func_clk pll_clk}] -to [get_clocks TCK]
set_false_path -from [get_clocks TCK] -to [get_clocks {func_clk pll_clk}]
```

## Low-Power Modes

Power management in modern SoCs involves multiple low-power states, each with different levels of functionality and power savings.

### Active Low-Power (Clock Gating)
- Not a separate mode per se, but clock gating cells dynamically disable clock branches
- Clock gating checks (setup and hold on the enable signal relative to the clock) must be met
- ICG (Integrated Clock Gating) cells are characterized with specific timing arcs

### Retention Mode
- Most logic is powered down, but retention flip-flops preserve state
- Retention clamps hold output values at defined levels
- Save and restore sequences have specific timing requirements
- The retention power supply (always-on) runs at potentially different voltage
- Isolation cells on power domain boundaries must be constrained

```tcl
# Retention mode constraints
# Only always-on domain clocks are active
create_clock -name ret_clk -period 20.0 [get_ports ret_clk]
# All other clocks are off
set_case_analysis 0 [get_pins pll/clk_out_en]
# Retention save/restore timing
set_max_delay 10.0 -from [get_pins */retention_save] -to [get_pins */ret_ff/D]
```

### Sleep Mode (Power Gating)
- Entire power domains are shut down via header/footer power switches
- Isolation cells clamp outputs of shut-down domains to prevent floating inputs
- Rush current during wake-up must be managed by staged power switch activation
- No timing paths exist within shut-down domains, but the power-up sequence has timing requirements

### Deep Sleep / Shutdown
- Maximum power savings with most of the chip powered off
- Only always-on logic (PMU, wake-up controller, RTC) remains active
- Minimal timing constraints -- only the always-on domain needs signoff

## DVFS Modes

Dynamic Voltage and Frequency Scaling creates multiple operating points, each effectively a separate mode-corner combination.

### Example DVFS Table

| Performance Level | Voltage | Frequency | Use Case |
|---|---|---|---|
| Turbo | 0.85V | 2.0GHz | Peak performance burst |
| Nominal | 0.75V | 1.5GHz | Normal operation |
| Low Power | 0.65V | 800MHz | Background tasks |
| Ultra Low | 0.55V | 400MHz | Always-on sensing |

Each DVFS level requires its own set of timing constraints at the appropriate voltage and frequency. The voltage and frequency must be paired correctly -- running at high frequency with low voltage will fail timing.

## Mode-Specific Constraint Management

### Constraint File Organization

Organize SDC files by mode with a common base:

```
constraints/
  common_clocks.sdc        # Clock definitions shared across modes
  func_mode.sdc            # Functional mode exceptions
  scan_shift_mode.sdc      # Scan shift constraints
  scan_capture_mode.sdc    # At-speed capture constraints
  jtag_mode.sdc            # JTAG/boundary scan constraints
  retention_mode.sdc       # Retention mode constraints
```

### Case Analysis for Mode Selection

Use `set_case_analysis` to model mode-select signals that configure muxes, enables, and clock sources:

```tcl
# Functional mode: test_mode=0, scan_enable=0
set_case_analysis 0 [get_ports test_mode]
set_case_analysis 0 [get_ports scan_enable]

# Scan shift mode: test_mode=1, scan_enable=1
set_case_analysis 1 [get_ports test_mode]
set_case_analysis 1 [get_ports scan_enable]
```

### Mode Interaction and Verification

- Verify that mode-select signals are properly constrained in every mode
- Ensure no timing paths are missed because they are false-pathed in all modes
- Validate that isolation and level-shifter cells are properly constrained in power mode transitions
- Check that all clock mux configurations are covered by at least one mode

## Practical Guidelines

1. **Define modes early in the project.** The mode list should be finalized before constraints are written. Late addition of modes causes significant rework.

2. **Minimize the number of active modes during optimization.** Each mode adds runtime. Use 3-5 modes for optimization and verify the rest at signoff.

3. **Keep mode-specific SDC files clean.** Each file should only contain constraints unique to that mode. Shared constraints go in a common file.

4. **Verify mode coverage.** Every timing path in the design should be analyzed in at least one mode. Use `report_timing -unconstrained` to find gaps.

5. **Test mode timing is not optional.** Scan shift hold violations cause test failures in the fab. Treat test modes with the same rigor as functional mode.

6. **Document mode-select signal values.** Maintain a table mapping each mode to the required values of all mode-select pins. This is essential for constraint consistency and debug.

Properly defining and constraining all operating modes is a prerequisite for reliable silicon that works not only in the lab but also through manufacturing test, in-field debug, and across all power states.
