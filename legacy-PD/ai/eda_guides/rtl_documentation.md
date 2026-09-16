# RTL Documentation

## Overview

RTL documentation bridges the gap between design intent and implementation. It serves multiple audiences: verification engineers who must test the design, physical design engineers who must implement it, firmware engineers who must program it, and future designers who must maintain or extend it. Poor documentation leads to misinterpretation, integration bugs, and wasted engineering time. Good documentation is precise, complete, and maintained alongside the RTL. This guide covers the essential document types for RTL design: micro-architecture specifications, register specifications, interface specifications, and timing diagrams.

## Micro-Architecture Specification

The micro-architecture spec (uArch spec) is the primary design document. It describes what the block does and how it does it at the hardware level, without descending to RTL code detail.

### Document Structure

```
1. Overview
   1.1 Purpose and scope
   1.2 Features
   1.3 Block diagram
   1.4 Performance targets

2. Architecture
   2.1 Top-level block diagram
   2.2 Data flow description
   2.3 Control flow description
   2.4 Sub-block descriptions
   2.5 State machines (state transition diagrams)

3. Interfaces
   3.1 External interfaces (ports, protocols)
   3.2 Internal interfaces (between sub-blocks)
   3.3 Memory interfaces

4. Clocking and Reset
   4.1 Clock domains
   4.2 Clock domain crossings
   4.3 Reset strategy
   4.4 Clock gating strategy

5. Power Management
   5.1 Power domains
   5.2 Power states
   5.3 Power-on sequence
   5.4 Low-power features

6. Error Handling
   6.1 Error detection
   6.2 Error reporting
   6.3 Error recovery

7. Configuration
   7.1 Register map summary
   7.2 Parameterization

8. Performance
   8.1 Throughput analysis
   8.2 Latency analysis
   8.3 Resource utilization
```

### Key Elements

**Block Diagram**: The most important part of the spec. A clear, hierarchical block diagram that shows all sub-blocks, data paths, control paths, and interfaces. Use color coding to distinguish data paths (blue), control paths (red), and clock/reset (green).

**Data Flow**: Describe how data moves through the block from input to output. Include the width at each stage, any format conversions, and buffering.

**State Machines**: Document every FSM with a state transition diagram that includes all states, transition conditions, and actions. Use a table format for complex FSMs:

| Current State | Condition | Next State | Actions |
|--------------|-----------|------------|---------|
| IDLE | start=1 | SETUP | Load config |
| SETUP | config_done=1 | ACTIVE | Enable datapath |
| ACTIVE | error=1 | ERROR | Latch error code |
| ACTIVE | done=1 | IDLE | Assert complete |
| ERROR | clear=1 | IDLE | Clear error |

**Latency Analysis**: Document the cycle-by-cycle latency from input to output. This is critical for system-level integration.

```
Cycle 0: Request received
Cycle 1: Address decode, bank select
Cycle 2: SRAM access (read)
Cycle 3: ECC decode
Cycle 4: Data available at output
Total latency: 4 cycles
```

## Register Specification

The register spec defines the software-visible registers: their addresses, fields, access types, reset values, and functional descriptions. This is the primary interface between hardware and software teams.

### Register Table Format

```
Register: CTRL (Offset: 0x00)
+-------+--------+--------+-------+------+----------------------------+
| Bits  | Name   | Access | Reset | Size | Description                |
+-------+--------+--------+-------+------+----------------------------+
| 31:16 | RSVD   | RO     | 0x0   | 16   | Reserved                   |
| 15    | EN     | RW     | 0x0   | 1    | Block enable               |
| 14    | IE     | RW     | 0x0   | 1    | Interrupt enable           |
| 13:8  | RSVD   | RO     | 0x0   | 6    | Reserved                   |
| 7:4   | MODE   | RW     | 0x0   | 4    | Operating mode (0=idle,    |
|       |        |        |       |      | 1=mode_a, 2=mode_b)        |
| 3:1   | RSVD   | RO     | 0x0   | 3    | Reserved                   |
| 0     | SW_RST | RW/SC  | 0x0   | 1    | Software reset (self-clear)|
+-------+--------+--------+-------+------+----------------------------+

Register: STATUS (Offset: 0x04)
+-------+--------+--------+-------+------+----------------------------+
| Bits  | Name   | Access | Reset | Size | Description                |
+-------+--------+--------+-------+------+----------------------------+
| 31:4  | RSVD   | RO     | 0x0   | 28   | Reserved                   |
| 3     | ERROR  | RO/WC  | 0x0   | 1    | Error occurred (write 1    |
|       |        |        |       |      | to clear)                  |
| 2     | BUSY   | RO     | 0x0   | 1    | Block is busy              |
| 1     | DONE   | RO/WC  | 0x0   | 1    | Operation complete (write  |
|       |        |        |       |      | 1 to clear)                |
| 0     | READY  | RO     | 0x1   | 1    | Block is ready             |
+-------+--------+--------+-------+------+----------------------------+
```

### Access Type Definitions

| Access | Description |
|--------|-------------|
| RO | Read-only. Hardware writes, software reads. |
| RW | Read-write. Software can read and write. |
| WO | Write-only. Software writes, reads return 0. |
| RW/SC | Read-write, self-clearing. Hardware clears the bit after one cycle. |
| RO/WC | Read-only, write-1-to-clear. Software writes 1 to clear. |
| RW1S | Write-1-to-set. Writing 1 sets the bit; writing 0 has no effect. |
| RW1C | Write-1-to-clear. Writing 1 clears the bit; writing 0 has no effect. |

### Register Documentation Best Practices

1. **Address map summary**: Provide a table listing all registers with their offsets and names.
2. **Field encoding**: Document all enumerated values for encoded fields.
3. **Side effects**: Document any side effects of reading or writing (e.g., reading a FIFO pops the entry).
4. **Ordering constraints**: Document any required read/write ordering (e.g., write CONFIG before setting EN).
5. **Reserved fields**: Define behavior for writes to reserved bits (typically ignored on write, 0 on read).
6. **Reset values**: Document the reset value of every field. Distinguish between power-on reset and warm reset values if different.

### Generating Register Documentation

Use IP-XACT (IEEE 1685) or custom register description formats (YAML, JSON, CSV) to generate:
- RTL register modules
- C/C++ header files for firmware
- Documentation (HTML, PDF)
- UVM register models for verification

This single-source approach eliminates inconsistencies between hardware and software register views.

## Interface Specification

The interface spec defines the protocol-level behavior of each external port, including signal definitions, timing relationships, and handshake protocols.

### Signal Table

```
Interface: Data Input (AXI4-Stream Slave)
+----------+--------+---------+----------------------------------------+
| Signal   | Dir    | Width   | Description                            |
+----------+--------+---------+----------------------------------------+
| tdata    | input  | 64      | Data payload                           |
| tkeep    | input  | 8       | Byte qualifier (1=valid byte)          |
| tlast    | input  | 1       | Last beat of packet                    |
| tvalid   | input  | 1       | Data valid from master                 |
| tready   | output | 1       | Ready from slave (this block)          |
+----------+--------+---------+----------------------------------------+

Handshake: Transfer occurs when tvalid=1 AND tready=1.
Backpressure: This block deasserts tready when internal FIFO is full.
Latency: tready is combinational from tvalid (zero-cycle latency).
```

### Protocol Rules

Document all protocol rules as numbered requirements:

1. Once `tvalid` is asserted, it must remain asserted until `tready` is observed.
2. `tdata` and `tlast` must be stable while `tvalid` is high and `tready` is low.
3. `tready` may be asserted before `tvalid` (pre-ready).
4. `tready` must not depend on `tvalid` (no combinational loop).
5. After reset, `tvalid` must be low for at least one cycle.

### Transaction Sequences

Document typical and corner-case transaction sequences:

```
Normal write sequence:
  Cycle 1: Master asserts tvalid, tdata=D0, tlast=0
  Cycle 2: Slave asserts tready (transfer of D0 occurs)
  Cycle 3: Master asserts tdata=D1, tlast=0 (immediate next beat)
  Cycle 4: Slave deasserts tready (backpressure)
  Cycle 5: (stalled, tvalid held, tdata=D1 stable)
  Cycle 6: Slave asserts tready (transfer of D1 occurs)
  Cycle 7: Master asserts tdata=D2, tlast=1 (last beat)
  Cycle 8: Slave asserts tready (transfer of D2 occurs, packet complete)
```

## Timing Diagrams

Timing diagrams visually communicate the cycle-by-cycle behavior of interfaces and internal logic. They are essential for any protocol or handshake.

### Drawing Conventions

```
         ___     ___     ___     ___     ___     ___
clk  ___|   |___|   |___|   |___|   |___|   |___|   |___
         1       2       3       4       5       6
              _________________________________
valid  ______|                                 |__________

              _______________
ready  ______|               |____________________________

              XXXXXXXXX======XXXXXXXXX
data   ------XXXXXXXXX  D0  XXXXXXXXX---------------------

Transfer occurs at cycle 3 (rising edge where valid=1, ready=1)
```

### Diagram Best Practices

1. **Show clock cycles numbered** for reference in text.
2. **Mark transfer points** where handshakes complete.
3. **Show setup/hold regions** when documenting timing constraints.
4. **Use consistent signal ordering**: clock at top, address/control next, data below, status at bottom.
5. **Include multiple scenarios**: normal, stalled, error, back-to-back.
6. **Use tools**: WaveDrom (JSON-based, web tool), Wavedraw, or Timing Designer for professional diagrams.

### WaveDrom Example (JSON format for machine-readable diagrams)

```json
{
  "signal": [
    {"name": "clk",   "wave": "P......"},
    {"name": "valid", "wave": "0.1..0."},
    {"name": "ready", "wave": "0..10.."},
    {"name": "data",  "wave": "x.=..x.", "data": ["D0"]},
    {"name": "xfer",  "wave": "0..10.."}
  ],
  "head": {"text": "Valid-Ready Handshake"},
  "foot": {"text": "Transfer at cycle 4"}
}
```

## Documentation Maintenance

### Keep Docs in Version Control

Store all documentation alongside RTL in the same repository. Documentation changes should be committed with the corresponding RTL changes.

### Review Documentation with Code

Include documentation review as part of the code review process. Reviewers should verify that the docs accurately describe the implementation.

### Automated Consistency Checks

Use scripts to verify that:
- All registers in the register spec exist in the RTL.
- All ports in the interface spec match the RTL port list.
- All FSM states in the spec appear in the RTL enum.

### Living Documents

Documentation is never finished. Update it when:
- Requirements change.
- Bugs are found (document the correct behavior).
- Optimization changes behavior.
- New features are added.

## Summary

Good RTL documentation includes a micro-architecture spec (what the block does and how), a register spec (software-visible interface), an interface spec (hardware protocol details), and timing diagrams (cycle-accurate behavior). Generate register documentation from a single source. Keep documentation in version control alongside RTL. Review and update documentation continuously.
