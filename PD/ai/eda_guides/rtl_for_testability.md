# RTL for Testability (DFT)

## Overview

Design for Testability (DFT) ensures that manufactured chips can be thoroughly tested for manufacturing defects. While DFT insertion is typically performed by dedicated DFT engineers at the gate level, the RTL coding style profoundly affects DFT efficiency, coverage, and area overhead. An RTL designer who writes DFT-unfriendly code forces expensive post-synthesis fixes, increases test area overhead, and may reduce fault coverage. This guide covers the RTL coding practices that enable clean, efficient DFT insertion.

## Scan Design Fundamentals

### What Is Scan

Scan testing replaces the functional flip-flops in a design with scan flip-flops that have an additional scan input (SI) and scan enable (SE) control. When scan enable is active, all flip-flops are chained into shift registers (scan chains). Test patterns are shifted in, the design is clocked once in functional mode to capture results, and the captured values are shifted out for comparison against expected values.

### Scan Flow

```
1. Shift test pattern into scan chains (SE=1, many clock cycles)
2. Pulse functional clock (SE=0, one or few cycles) to capture response
3. Shift out captured response (SE=1, many clock cycles)
4. Compare response against expected values
```

### Coverage Metrics

- **Stuck-at fault coverage**: Percentage of single stuck-at faults (net stuck at 0 or 1) detected.
- **Transition fault coverage**: Percentage of slow-to-rise/slow-to-fall faults detected.
- **Target**: 95%+ stuck-at coverage is typical; 90%+ transition coverage.

## Scan-Friendly RTL Coding

### Avoid Gated Clocks Without ICG Cells

Manually gated clocks prevent scan chain formation because the scan shift clock is blocked.

```systemverilog
// BAD: manual clock gating blocks scan
wire gated_clk = clk & enable;
always_ff @(posedge gated_clk) begin
  data_reg <= data_in;
end

// GOOD: use enable inference (synthesis inserts ICG with test bypass)
always_ff @(posedge clk) begin
  if (enable)
    data_reg <= data_in;
end
```

ICG (Integrated Clock Gating) cells have a built-in test enable (TE) input that bypasses the gate during scan, ensuring the scan clock reaches all flip-flops.

### Avoid Asynchronous Set/Reset on Data Registers

Asynchronous set/reset pins on flip-flops complicate scan because they can corrupt scan shift data. If the set/reset is active during scan shifting, it overrides the shifted data.

```systemverilog
// PROBLEMATIC: async reset on data path register
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) data_reg <= '0;
  else        data_reg <= data_in;
end

// BETTER for DFT: synchronous reset on data path registers
always_ff @(posedge clk) begin
  if (!rst_n) data_reg <= '0;
  else        data_reg <= data_in;
end
```

Use asynchronous reset only for control registers that must be in a known state immediately at power-up (FSM state registers, reset controllers). Use synchronous reset for data path registers.

### Avoid Internally Generated Clocks

Flip-flops clocked by internally generated clocks (derived from data signals or dividers) create separate clock domains that complicate scan chain stitching.

```systemverilog
// BAD: data-derived clock
wire derived_clk = data_toggle;
always_ff @(posedge derived_clk) begin
  capture_reg <= data_in;
end

// GOOD: use the system clock with an enable
always_ff @(posedge clk) begin
  if (data_toggle_edge)
    capture_reg <= data_in;
end
```

If clock dividers are necessary, use scannable clock divider cells from the DFT library that include scan muxes to bypass the divider during test.

### Avoid Feedback Loops in Combinational Logic

Combinational loops are untestable because the loop creates an oscillation or indeterminate state during test application. They also cause synthesis and timing analysis failures.

### Avoid Tri-State Internal Buses

Internal tri-state buses are untestable because the high-impedance state cannot be controlled or observed through scan. Replace with mux-based bus architectures.

### Avoid Latches Where Possible

Latches are transparent (level-sensitive), making them difficult to control during scan shifting. A latch that is transparent during scan shift allows data to flow through, corrupting the scan chain. If latches are necessary, use them in pairs (master-slave) or ensure they are controlled by signals that are inactive during scan.

## Test Point Insertion

Test points are additional logic inserted to improve controllability (ability to set internal nodes to desired values) and observability (ability to observe internal node values).

### Observation Points

An observation point captures an internal signal into a scan flip-flop, making it visible in the scan output.

```systemverilog
// RTL-level observation point
(* test_point = "observe" *)
wire internal_signal;

// After DFT insertion, a scan flip-flop samples internal_signal
```

### Control Points

A control point adds a mux that allows a scan flip-flop to override an internal signal during test.

```systemverilog
// Conceptual: DFT tool inserts a mux
// func_signal = test_mode ? test_override : normal_logic;
```

### When to Add Test Points

1. **Low-controllability nodes**: Signals deep in the logic cone that are hard to set to both 0 and 1.
2. **Low-observability nodes**: Signals whose effects are masked by downstream logic.
3. **Random-pattern-resistant faults**: Faults that require specific, unlikely input patterns.

### Automated vs Manual

Modern DFT tools (Synopsys DFT Compiler, Mentor Tessent) automatically identify and insert test points. The RTL designer's role is to ensure the RTL structure does not block the tool's ability to insert them.

## BIST-Friendly Memory Design

### Memory BIST (MBIST)

SRAMs and other embedded memories cannot be tested with scan chains (they are not made of flip-flops). Memory BIST generates test patterns internally, writes them to the memory, reads them back, and compares results.

### RTL Requirements for MBIST

1. **Standard memory interface**: The SRAM wrapper must have clean address, data, write-enable, and chip-select ports that the BIST controller can drive.
2. **BIST mux**: A multiplexer at the memory inputs selects between functional signals and BIST signals.

```systemverilog
module mem_wrapper (
  input  logic        clk,
  input  logic        bist_mode,
  // Functional interface
  input  logic        func_cs,
  input  logic        func_we,
  input  logic [9:0]  func_addr,
  input  logic [31:0] func_wdata,
  output logic [31:0] func_rdata,
  // BIST interface
  input  logic        bist_cs,
  input  logic        bist_we,
  input  logic [9:0]  bist_addr,
  input  logic [31:0] bist_wdata
);

  wire       cs    = bist_mode ? bist_cs    : func_cs;
  wire       we    = bist_mode ? bist_we    : func_we;
  wire [9:0] addr  = bist_mode ? bist_addr  : func_addr;
  wire [31:0] wdata = bist_mode ? bist_wdata : func_wdata;

  // SRAM macro instantiation
  sram_1024x32 u_sram (
    .CLK(clk), .CS(cs), .WE(we),
    .ADDR(addr), .DI(wdata), .DO(func_rdata)
  );

endmodule
```

3. **Memory grouping**: Memories with the same configuration (same depth and width) can share a BIST controller, reducing area overhead.
4. **Memory access during BIST**: The memory must be exclusively accessible by the BIST controller during test (no functional accesses).

### MBIST Patterns

Common MBIST algorithms include:
- **March C-**: Tests all stuck-at and many coupling faults. 10N operations (N = memory depth).
- **March B**: More comprehensive, tests bridging faults. 17N operations.
- **Checkerboard**: Writes alternating 0/1 patterns to detect data retention and neighboring cell interference.

### Repair

Many modern SRAMs include redundant rows/columns. MBIST identifies failing addresses, and a fuse/anti-fuse mechanism redirects those addresses to spare rows/columns.

## Scan Compression

Scan compression (DFTMAX, Tessent ScanPro) reduces test time and data volume by using a compressor/decompressor that drives multiple internal scan chains from fewer external scan pins.

### RTL Impact

The RTL designer does not typically need to code for scan compression explicitly, but must ensure:
1. The design is scan-friendly (no blocking clocks, no async resets during shift).
2. Sufficient pipeline registers exist for compressor/decompressor insertion.
3. The hierarchical structure allows the DFT tool to stitch chains efficiently.

## JTAG (IEEE 1149.1)

JTAG provides a standard interface for boundary scan testing and debug access.

### RTL Considerations

1. **Boundary scan cells**: Added at I/O pads by the DFT tool. The RTL designer must ensure I/O pad interfaces are compatible.
2. **TAP controller**: The JTAG Test Access Port controller is usually instantiated as a hard macro or generated by the DFT tool.
3. **User-defined registers**: JTAG can access internal registers for debug. The RTL designer defines which registers are JTAG-accessible.

## DFT-Friendly RTL Checklist

1. Use ICG cells or enable-based coding for clock gating (no manual clock gating).
2. Use synchronous reset for data path registers.
3. Avoid internally generated clocks; use clock enables instead.
4. Avoid combinational feedback loops.
5. Avoid internal tri-state buses.
6. Minimize latch usage; use flip-flops wherever possible.
7. Provide standard SRAM wrapper interfaces for MBIST.
8. Structure hierarchy so that scan chain stitching can proceed cleanly.
9. Ensure all flip-flops are scannable (no blocking conditions on scan shift path).
10. Run DFT rule checks (SpyGlass DFT, Tessent DRC) alongside lint.

## Summary

DFT-friendly RTL is not about adding test logic; it is about avoiding coding patterns that block or complicate test insertion. The primary rules are straightforward: avoid manual clock gating, avoid async resets on data registers, avoid internal clocks, and provide clean memory interfaces. Following these guidelines enables the DFT tools to achieve high fault coverage with minimal area overhead.
