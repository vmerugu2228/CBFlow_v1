# Boundary Scan: JTAG and IEEE 1149.1

## Overview and Motivation

Boundary scan, standardized as IEEE 1149.1 (commonly called JTAG after the Joint Test Action Group that developed it), is a test access architecture that provides controllability and observability of chip I/O pins through a serial scan path. Originally developed for board-level interconnect testing -- verifying that solder joints between components are correct -- JTAG has evolved into a universal interface for chip testing, debug, programming, and in-system configuration.

Before boundary scan, board-level testing relied on bed-of-nails fixtures that made physical contact with test points on the PCB. As packages became finer-pitch (BGA, flip-chip) and boards became denser (blind/buried vias, components on both sides), physical access became impossible. Boundary scan solved this by providing electrical access to every pin through a serial digital interface requiring only 4-5 wires.

## TAP Controller

The Test Access Port (TAP) controller is the heart of the JTAG architecture. It is a 16-state finite state machine clocked by TCK (Test Clock) and controlled by TMS (Test Mode Select). The TAP states manage the flow of data through the instruction and data registers.

### TAP Signals

**TCK (Test Clock)**: The clock for all JTAG operations. Independent of the chip's functional clocks. Typically 10-50 MHz.

**TMS (Test Mode Select)**: Controls TAP state transitions. Sampled on the rising edge of TCK.

**TDI (Test Data In)**: Serial data input. Sampled on the rising edge of TCK.

**TDO (Test Data Out)**: Serial data output. Changes on the falling edge of TCK (half-cycle delay from TDI for reliable board-level chain operation).

**TRST (Test Reset, optional)**: Asynchronous TAP controller reset. Active low. Optional in the standard; when absent, the TAP can be reset by holding TMS high for 5+ TCK cycles.

### TAP State Machine

Key states in the 16-state FSM:

**Test-Logic-Reset**: Default power-up state. All test logic disabled. Reached by holding TMS=1 for 5 cycles from any state.

**Run-Test/Idle**: Parking state between operations. The TAP remains here when no JTAG activity is needed.

**Shift-DR**: Data register bits shift from TDI through the selected data register to TDO. This is where test data is loaded and captured.

**Shift-IR**: Instruction register bits shift from TDI to TDO. This is where JTAG instructions are loaded.

**Capture-DR**: Parallel load of data into the selected data register (e.g., capture pin values into boundary scan cells).

**Update-DR**: Parallel transfer of shifted data to the data register outputs (e.g., drive boundary scan cell values onto pins).

**Capture-IR / Update-IR**: Analogous operations for the instruction register.

The state transitions follow a simple rule: at each rising TCK edge, TMS=0 generally moves toward the "shift" or "idle" states, while TMS=1 moves toward "exit" or "reset" states.

## Boundary Scan Cells

Each I/O pin on the chip is associated with a boundary scan cell (BSC). The BSC can capture the pin's functional value, drive a test value onto the pin, or pass through transparent to functional operation.

### BSC Types

**BC_1 (Basic input/output cell)**: Can capture and drive values. Used for bidirectional and output pins.

**BC_2 (Input-only cell)**: Captures input pin values but cannot drive them. Used for input-only pins.

**BC_4 (Clock cell)**: Specialized for clock pins; can capture but must not disrupt clock integrity during normal operation.

**BC_7 (Bidirectional cell)**: Enhanced cell for bidirectional pins with separate capture and drive paths for data and output enable.

Each BSC contains:
- A capture flip-flop (samples the pin value on Capture-DR)
- An update flip-flop (holds the drive value loaded during Shift-DR/Update-DR)
- A mux selecting between functional data and BSC-driven data

## Mandatory JTAG Instructions

**BYPASS (all 1s)**: Selects a single-bit bypass register, allowing data to pass through the chip with minimal delay (one TCK cycle). Used when this chip is not the target of the current operation but is in the scan chain.

**EXTEST**: Drives values from boundary scan cells onto output pins and captures values from input pins. Used for board-level interconnect testing.

**SAMPLE/PRELOAD**: Captures a snapshot of all pin values into the boundary scan register without disturbing functional operation (SAMPLE), or preloads values into the update flip-flops for subsequent EXTEST (PRELOAD).

## Optional JTAG Instructions

**INTEST**: Applies test values to the chip's core logic inputs (from the boundary scan cells toward the core) and captures core outputs. Tests the chip's internal logic via its boundary.

**IDCODE**: Reads a 32-bit device identification register containing manufacturer ID, part number, and version. Most devices implement this.

**USERCODE**: Reads a user-programmable identification code, often used for FPGA configuration version tracking.

**CLAMP**: Drives outputs to previously loaded boundary scan values while selecting the bypass register for data. Allows holding pin values while testing other chips on the board.

**HIGHZ**: Drives all outputs to high-impedance. Useful for isolating a chip during board-level diagnosis.

## BSDL (Boundary Scan Description Language)

BSDL is a standardized text file format (subset of VHDL) that describes a chip's JTAG implementation. Board test tools read BSDL files to automatically generate test vectors.

BSDL contents include:
- Pin mapping (physical pin to boundary scan cell)
- Instruction register length and instruction opcodes
- Boundary scan register length and cell descriptions
- TAP signal pin assignments
- Device ID register value
- Compliance-enable pins (if any)

Every JTAG-compliant chip must have a BSDL file. The chip vendor typically provides it as part of the design collateral.

## Board-Level Test Applications

### Interconnect Testing

The primary boundary scan application. The procedure:
1. Load EXTEST instruction on all devices
2. Drive known values from one chip's output BSCs
3. Capture values at connected chip's input BSCs
4. Compare captured values with expected values

Detects: open connections (stuck values), shorts between nets (bridging), missing components.

### In-Circuit Programming

JTAG is widely used to program FPGAs, CPLDs, and flash memories:
- FPGA configuration bitstreams are loaded through JTAG
- Microcontroller flash programming via JTAG debug interface
- EEPROM/Flash programming through boundary scan drive

### Cluster Testing

Groups of interconnected devices are tested together. A **cluster** is a set of devices and their interconnecting nets that can be fully tested through boundary scan without physical probe access.

## Chain Topology

In a typical board, multiple JTAG devices are connected in a daisy chain:

```
TDI -> Device1.TDI -> Device1.TDO -> Device2.TDI -> Device2.TDO -> ... -> TDO
```

All devices share TCK and TMS. TDI/TDO are chained serially. When addressing a specific device, all other devices are placed in BYPASS mode (1-bit pass-through) to minimize shift overhead.

### Multi-Drop JTAG

For boards with many JTAG devices, the serial chain becomes very long. Solutions include:
- **Addressable scan chains**: IEEE 1149.1-2013 added the ability to select specific devices by address
- **Star topology**: Separate TDI/TDO connections to each device with a multiplexer
- **IEEE 1687 (IJTAG)**: Flexible, reconfigurable test access networks with instruments

## IEEE 1149.1-2013 Updates

The 2013 revision added significant features:
- **Test Data Registers**: More flexibility in defining custom data registers
- **New instructions**: INIT_SETUP, INIT_SETUP_CLAMP, INIT_RUN for initialization sequences
- **Extensions to BSDL**: Support for new cell types and package descriptions
- **Procedural description**: Formal specification of device initialization procedures

## IEEE 1149.6: AC-Coupled Boundary Scan

Standard boundary scan (1149.1) cannot test AC-coupled (capacitively coupled) connections or differential signaling (LVDS, SERDES) because it drives DC levels. IEEE 1149.6 adds boundary scan cells capable of generating and detecting AC patterns through capacitively coupled and differential links.

1149.6 cells include:
- AC stimulus drivers that generate edge transitions
- Hysteresis-based receivers that detect transitions through AC coupling capacitors
- Differential driver/receiver pairs for differential link testing

## IEEE 1687 (IJTAG)

IJTAG extends JTAG with a flexible, reconfigurable access network for embedded instruments (BIST controllers, sensors, configuration registers). Key concepts:

**Segment Insertion Bit (SIB)**: A programmable element that includes or excludes a segment of the scan path. When SIB=0, the segment is bypassed. When SIB=1, the segment is included.

**ICL (Instrument Connectivity Language)**: Describes the network topology and instrument connections.

**PDL (Procedural Description Language)**: Scripts that define how to access and operate instruments.

IJTAG provides hierarchical, on-demand access to embedded test resources without permanently including them in the scan chain, reducing JTAG overhead for normal debug operations.

## JTAG in Modern SoCs

In modern SoCs, JTAG serves multiple purposes:
- **DFT access**: Control BIST, scan compression, and other test infrastructure
- **Debug**: ARM CoreSight, RISC-V debug module, and other debug architectures use JTAG as the transport
- **Trace**: Some trace systems use JTAG for configuration
- **Security**: Secure JTAG implementations add authentication before granting debug access to prevent reverse engineering and unauthorized access
- **System management**: Temperature sensors, voltage monitors, and other on-chip instruments accessible via JTAG/IJTAG

JTAG remains indispensable in modern IC design despite being over 30 years old, continually adapted through standard extensions and vendor-specific enhancements.
