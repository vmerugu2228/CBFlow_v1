# FIFO Design

## Overview

FIFOs (First-In First-Out) are ubiquitous in digital design. They buffer data between producers and consumers that operate at different rates, in different clock domains, or with bursty traffic patterns. A synchronous FIFO operates within a single clock domain, while an asynchronous FIFO bridges two independent clock domains. FIFO design errors, particularly in asynchronous FIFOs, are among the most dangerous bugs in digital systems because they cause intermittent, timing-dependent failures. This guide covers both synchronous and asynchronous FIFO design in detail.

## Synchronous FIFO

A synchronous FIFO uses a single clock for both write and read operations. It is structurally simple: a dual-port memory with write and read pointers.

### Architecture

```
            +-----------+
  wr_data ->| Dual-port |-> rd_data
  wr_en   ->|  Memory   |<- rd_en
            +-----------+
               ^     ^
               |     |
            wr_ptr  rd_ptr
               |     |
            +--+-----+--+
            | Count/Flag |
            |   Logic    |
            +------------+
            full  empty  count
```

### Implementation

```systemverilog
module sync_fifo #(
  parameter int DEPTH = 16,
  parameter int WIDTH = 32
)(
  input  logic             clk,
  input  logic             rst_n,
  // Write interface
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  // Read interface
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  // Status
  output logic             full,
  output logic             empty,
  output logic [$clog2(DEPTH):0] count
);

  localparam int PTR_W = $clog2(DEPTH);

  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr, rd_ptr;
  logic [PTR_W:0]   fifo_count;

  wire wr_valid = wr_en && !full;
  wire rd_valid = rd_en && !empty;

  // Write logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      wr_ptr <= '0;
    else if (wr_valid) begin
      mem[wr_ptr] <= wr_data;
      wr_ptr <= wr_ptr + 1'b1;
    end
  end

  // Read logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rd_ptr <= '0;
    else if (rd_valid)
      rd_ptr <= rd_ptr + 1'b1;
  end

  // Read data (registered output for timing)
  always_ff @(posedge clk) begin
    if (rd_valid)
      rd_data <= mem[rd_ptr];
  end

  // Count and flags
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      fifo_count <= '0;
    else begin
      case ({wr_valid, rd_valid})
        2'b10:   fifo_count <= fifo_count + 1'b1;
        2'b01:   fifo_count <= fifo_count - 1'b1;
        default: fifo_count <= fifo_count;  // 2'b00 or 2'b11
      endcase
    end
  end

  assign full  = (fifo_count == DEPTH);
  assign empty = (fifo_count == '0);
  assign count = fifo_count;

endmodule
```

### First-Word Fall-Through (FWFT)

In a standard FIFO, the read data is available one cycle after `rd_en` is asserted. In an FWFT FIFO, the first word is already present on the read data output as soon as the FIFO becomes non-empty, with zero read latency.

```systemverilog
// FWFT: combinational read data output
assign rd_data = mem[rd_ptr];  // no register on read data

// Or: add a prefetch register
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    prefetch_valid <= 1'b0;
  else if (!prefetch_valid && !empty)
    prefetch_valid <= 1'b1;  // auto-read first word
  else if (rd_en && empty)
    prefetch_valid <= 1'b0;
end
```

FWFT simplifies consumer logic (no need for a "prefetch read") but adds combinational paths that may complicate timing.

## Asynchronous FIFO

An asynchronous FIFO bridges two independent clock domains. This is one of the most critical and error-prone structures in digital design.

### Architecture

The key insight is that Gray-coded pointers can be safely synchronized between clock domains because only one bit changes per increment, eliminating the multi-bit synchronization problem.

```
Write Domain:                          Read Domain:
  wr_ptr (binary) ----+            +---- rd_ptr (binary)
  bin2gray(wr_ptr) --> | sync to   | <-- bin2gray(rd_ptr)
  wr_ptr_gray ------> | rd domain | <--- rd_ptr_gray
                       +----+------+
                            |
                       Dual-port RAM
                       (true dual-port)
```

### Gray Code Conversion

```systemverilog
function automatic logic [PTR_W:0] bin2gray(input logic [PTR_W:0] bin);
  return bin ^ (bin >> 1);
endfunction

function automatic logic [PTR_W:0] gray2bin(input logic [PTR_W:0] gray);
  logic [PTR_W:0] bin;
  bin[PTR_W] = gray[PTR_W];
  for (int i = PTR_W-1; i >= 0; i--)
    bin[i] = bin[i+1] ^ gray[i];
  return bin;
endfunction
```

### Full and Empty Detection Using Gray Code

The pointers are extended by one extra MSB to distinguish full from empty (both would otherwise look like `wr_ptr == rd_ptr`).

**Empty condition** (in read domain): The synchronized write pointer Gray code equals the read pointer Gray code.

```systemverilog
assign empty = (rd_ptr_gray == wr_ptr_gray_sync);
```

**Full condition** (in write domain): The synchronized read pointer Gray code equals the write pointer Gray code with the two MSBs inverted.

```systemverilog
assign full = (wr_ptr_gray == {~rd_ptr_gray_sync[PTR_W:PTR_W-1],
                                rd_ptr_gray_sync[PTR_W-2:0]});
```

The two-MSB inversion works because in Gray code, inverting the MSB represents a pointer that is exactly DEPTH ahead. With the extra MSB, this uniquely identifies the full condition.

### Complete Asynchronous FIFO

```systemverilog
module async_fifo #(
  parameter int DEPTH = 16,
  parameter int WIDTH = 32
)(
  // Write interface (wr_clk domain)
  input  logic             wr_clk,
  input  logic             wr_rst_n,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic             full,
  // Read interface (rd_clk domain)
  input  logic             rd_clk,
  input  logic             rd_rst_n,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             empty
);

  localparam int PTR_W = $clog2(DEPTH);

  // Dual-port RAM
  logic [WIDTH-1:0] mem [0:DEPTH-1];

  // Binary and Gray pointers
  logic [PTR_W:0] wr_ptr_bin, rd_ptr_bin;
  logic [PTR_W:0] wr_ptr_gray, rd_ptr_gray;
  logic [PTR_W:0] wr_ptr_gray_sync, rd_ptr_gray_sync;

  // --- Write domain ---
  wire wr_valid = wr_en && !full;

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_ptr_bin  <= '0;
      wr_ptr_gray <= '0;
    end else if (wr_valid) begin
      mem[wr_ptr_bin[PTR_W-1:0]] <= wr_data;
      wr_ptr_bin  <= wr_ptr_bin + 1'b1;
      wr_ptr_gray <= bin2gray(wr_ptr_bin + 1'b1);
    end
  end

  // Synchronize rd_ptr_gray into write domain
  sync_2ff #(.WIDTH(PTR_W+1)) u_sync_rd (
    .clk(wr_clk), .rst_n(wr_rst_n),
    .data_in(rd_ptr_gray), .data_out(rd_ptr_gray_sync)
  );

  assign full = (wr_ptr_gray == {~rd_ptr_gray_sync[PTR_W:PTR_W-1],
                                   rd_ptr_gray_sync[PTR_W-2:0]});

  // --- Read domain ---
  wire rd_valid = rd_en && !empty;

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_ptr_bin  <= '0;
      rd_ptr_gray <= '0;
    end else if (rd_valid) begin
      rd_ptr_bin  <= rd_ptr_bin + 1'b1;
      rd_ptr_gray <= bin2gray(rd_ptr_bin + 1'b1);
    end
  end

  assign rd_data = mem[rd_ptr_bin[PTR_W-1:0]];

  // Synchronize wr_ptr_gray into read domain
  sync_2ff #(.WIDTH(PTR_W+1)) u_sync_wr (
    .clk(rd_clk), .rst_n(rd_rst_n),
    .data_in(wr_ptr_gray), .data_out(wr_ptr_gray_sync)
  );

  assign empty = (rd_ptr_gray == wr_ptr_gray_sync);

endmodule
```

### Critical Design Rule: Power-of-Two Depth

Asynchronous FIFO depth must be a power of two. Gray code only guarantees single-bit changes for binary counters that wrap at power-of-two boundaries. Non-power-of-two depths break the Gray code property and cause multi-bit transitions that are unsafe for synchronization.

For non-power-of-two effective depths, use the next larger power of two and implement an almost-full threshold at the desired effective depth.

## FIFO Depth Calculation

### Bandwidth Matching

When the write and read clocks have different frequencies, the FIFO must be deep enough to absorb the rate difference during bursts.

```
Minimum Depth = Burst_Length - (Burst_Length * f_read / f_write)
             = Burst_Length * (1 - f_read / f_write)
```

Example: 100 MHz write, 80 MHz read, burst of 100 words:
```
Depth >= 100 * (1 - 80/100) = 100 * 0.2 = 20 entries
```

Round up to the next power of two: 32 entries.

### Back-to-Back Bursts

If bursts can arrive back-to-back before the previous burst is fully drained, additional depth is needed:

```
Depth = Burst_Length * N_backtoback * (1 - f_read / f_write)
```

### Practical Margin

Add 25-50% margin to the calculated depth for safety. FIFO underflow or overflow is a catastrophic failure.

## Almost Full and Almost Empty

```systemverilog
parameter ALMOST_FULL_THRESH  = DEPTH - 4;  // 4 entries before full
parameter ALMOST_EMPTY_THRESH = 4;           // 4 entries before empty

assign almost_full  = (count >= ALMOST_FULL_THRESH);
assign almost_empty = (count <= ALMOST_EMPTY_THRESH);
```

These signals provide early warning for flow control. The threshold must account for the pipeline latency of the flow control path (the number of cycles between asserting backpressure and the upstream actually stopping).

## FIFO Verification

1. **Corner cases**: Write when full, read when empty, simultaneous read/write at full, simultaneous at empty.
2. **Pointer wrap**: Verify behavior when pointers wrap around.
3. **Clock ratios**: For async FIFOs, test with various frequency ratios including 1:1, near-equal, and extreme ratios.
4. **Reset**: Verify that reset clears the FIFO and both domains recover correctly.
5. **Assertions**: Add protocol assertions for overflow/underflow detection.

```systemverilog
assert property (@(posedge wr_clk) disable iff (!wr_rst_n)
  wr_en |-> !full) else $error("FIFO overflow: write when full");

assert property (@(posedge rd_clk) disable iff (!rd_rst_n)
  rd_en |-> !empty) else $error("FIFO underflow: read when empty");
```

## Summary

Synchronous FIFOs are straightforward but must handle simultaneous read/write and flag generation correctly. Asynchronous FIFOs require Gray-coded pointers, two-FF synchronizers, power-of-two depths, and careful full/empty detection. Always calculate FIFO depth from worst-case burst analysis, add margin, and verify exhaustively including all corner cases.
