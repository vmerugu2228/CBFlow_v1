# Memory Interface Design

## Overview

Memory interfaces are critical components in almost every digital system. From register files to cache controllers, from DMA engines to network buffers, the ability to efficiently store and retrieve data determines system performance. This guide covers SRAM interfaces, FIFO architectures, arbiter design, and memory controller fundamentals, with emphasis on the RTL design patterns that produce efficient, timing-clean implementations.

## SRAM Interface Design

### Single-Port SRAM

A single-port SRAM has one address port shared between reads and writes. Only one operation can occur per clock cycle.

```systemverilog
module sram_sp #(
  parameter DEPTH = 1024,
  parameter WIDTH = 32,
  parameter ADDR_W = $clog2(DEPTH)
)(
  input  logic              clk,
  input  logic              cs_n,     // chip select (active low)
  input  logic              we_n,     // write enable (active low)
  input  logic [ADDR_W-1:0] addr,
  input  logic [WIDTH-1:0]  wdata,
  output logic [WIDTH-1:0]  rdata
);

  logic [WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (!cs_n) begin
      if (!we_n)
        mem[addr] <= wdata;
      rdata <= mem[addr];  // read-during-write: returns old data
    end
  end

endmodule
```

### Dual-Port SRAM

Dual-port SRAMs have independent read and write ports, allowing simultaneous read and write operations. They are essential for FIFOs and register files.

```systemverilog
module sram_dp #(
  parameter DEPTH = 1024,
  parameter WIDTH = 32,
  parameter ADDR_W = $clog2(DEPTH)
)(
  input  logic              clk,
  // Write port
  input  logic              wen,
  input  logic [ADDR_W-1:0] waddr,
  input  logic [WIDTH-1:0]  wdata,
  // Read port
  input  logic              ren,
  input  logic [ADDR_W-1:0] raddr,
  output logic [WIDTH-1:0]  rdata
);

  logic [WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (wen)
      mem[waddr] <= wdata;
    if (ren)
      rdata <= mem[raddr];
  end

endmodule
```

### SRAM Wrapper Design

In ASIC design, SRAMs are typically hard macros (compiled memories) with specific interface timing. The RTL wrapper adapts the design's interface to the SRAM macro's interface.

```systemverilog
module sram_wrapper #(
  parameter DEPTH = 1024,
  parameter WIDTH = 32
)(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              req,
  input  logic              wr,
  input  logic [$clog2(DEPTH)-1:0] addr,
  input  logic [WIDTH-1:0]  wdata,
  input  logic [WIDTH/8-1:0] byte_en,
  output logic [WIDTH-1:0]  rdata,
  output logic              rdata_valid
);

  // SRAM macro instance (technology-specific)
  // Handles byte-enable to bit-mask conversion
  // Handles timing margin adjustments
  // Handles BIST mux for testability

  // Read latency tracking
  logic req_d1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) req_d1 <= 1'b0;
    else        req_d1 <= req && !wr;
  end
  assign rdata_valid = req_d1;

endmodule
```

Key wrapper responsibilities include byte-enable to bitmask conversion, BIST multiplexing for testability, timing margin adjustments (setup/hold for SRAM inputs), and power management (chip select gating).

## FIFO Design

### Synchronous FIFO

A synchronous FIFO uses a single clock for both write and read operations. It is simpler than an asynchronous FIFO and is used within a single clock domain for buffering and flow control.

```systemverilog
module sync_fifo #(
  parameter DEPTH = 16,
  parameter WIDTH = 32,
  parameter ADDR_W = $clog2(DEPTH)
)(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             full,
  output logic             empty,
  output logic [ADDR_W:0]  count
);

  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [ADDR_W-1:0] wr_ptr, rd_ptr;
  logic [ADDR_W:0] fifo_count;

  assign full  = (fifo_count == DEPTH);
  assign empty = (fifo_count == '0);
  assign count = fifo_count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr     <= '0;
      rd_ptr     <= '0;
      fifo_count <= '0;
    end else begin
      case ({wr_en && !full, rd_en && !empty})
        2'b10: begin  // write only
          mem[wr_ptr] <= wr_data;
          wr_ptr      <= wr_ptr + 1'b1;
          fifo_count  <= fifo_count + 1'b1;
        end
        2'b01: begin  // read only
          rd_ptr     <= rd_ptr + 1'b1;
          fifo_count <= fifo_count - 1'b1;
        end
        2'b11: begin  // simultaneous read and write
          mem[wr_ptr] <= wr_data;
          wr_ptr      <= wr_ptr + 1'b1;
          rd_ptr      <= rd_ptr + 1'b1;
          // count unchanged
        end
        default: ; // no operation
      endcase
    end
  end

  assign rd_data = mem[rd_ptr];

endmodule
```

### Almost Full / Almost Empty

For flow control, `almost_full` and `almost_empty` signals provide early warning, allowing the controller time to react before the FIFO actually fills or empties.

```systemverilog
parameter ALMOST_FULL_THRESH  = DEPTH - 4;
parameter ALMOST_EMPTY_THRESH = 4;

assign almost_full  = (fifo_count >= ALMOST_FULL_THRESH);
assign almost_empty = (fifo_count <= ALMOST_EMPTY_THRESH);
```

## Arbiter Design

Arbiters resolve contention when multiple requesters compete for a shared resource (memory port, bus, etc.).

### Fixed Priority Arbiter

The simplest arbiter; lower-numbered requesters always win.

```systemverilog
module arbiter_fixed #(parameter N = 4)(
  input  logic [N-1:0] req,
  output logic [N-1:0] grant
);
  always_comb begin
    grant = '0;
    for (int i = 0; i < N; i++) begin
      if (req[i]) begin
        grant[i] = 1'b1;
        break;
      end
    end
  end
endmodule
```

Fixed priority can starve low-priority requesters. Use only when priority ordering is inherently correct (e.g., interrupt priority).

### Round-Robin Arbiter

Rotates priority after each grant to ensure fairness.

```systemverilog
module arbiter_rr #(parameter N = 4)(
  input  logic         clk,
  input  logic         rst_n,
  input  logic [N-1:0] req,
  output logic [N-1:0] grant
);
  logic [N-1:0] priority_mask;
  logic [N-1:0] masked_req, unmasked_grant, masked_grant;

  // Masked request: only consider requests at or below current priority
  assign masked_req = req & priority_mask;

  // Two fixed-priority arbiters: one for masked, one for unmasked
  // Use masked result if any masked request exists
  always_comb begin
    masked_grant   = masked_req & (~masked_req + 1'b1);   // lowest set bit
    unmasked_grant = req & (~req + 1'b1);                   // lowest set bit
    grant = |masked_req ? masked_grant : unmasked_grant;
  end

  // Update priority mask after each grant
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      priority_mask <= '1;
    else if (|grant)
      priority_mask <= ~((grant - 1'b1) | grant);  // mask out granted and lower
  end

endmodule
```

### Weighted Round-Robin

Each requester gets a configurable number of grants per round. Used for bandwidth allocation in network-on-chip and memory controllers.

## Memory Controller Basics

A memory controller manages access to external memory (DDR SDRAM, HBM, etc.), handling address mapping, command scheduling, refresh, and timing constraints.

### Key Functions

1. **Address Mapping**: Translates system addresses to bank/row/column addresses. Interleaving across banks maximizes parallelism.
2. **Command Scheduling**: Orders read, write, activate, precharge, and refresh commands to maximize bandwidth while respecting timing constraints (tRCD, tRP, tRAS, tCL, etc.).
3. **Reordering**: Out-of-order command scheduling to hide latency (e.g., scheduling a read to an open row while waiting for a precharge on another bank).
4. **Refresh Management**: Periodic refresh commands must be issued to prevent data loss. The controller must balance refresh with normal access.
5. **Data Path**: Manages the DQ (data) bus, including read/write leveling, DQS alignment, and ODT (on-die termination) control.

### Simplified Controller Architecture

```
Request Queue -> Address Decoder -> Command Scheduler -> PHY Interface
                                          |
                                    Refresh Manager
                                          |
                                    Timing Engine (enforces tRCD, tRP, etc.)
```

### Bank State Tracking

```systemverilog
typedef enum logic [1:0] {
  BANK_IDLE,
  BANK_ACTIVE,
  BANK_PRECHARGING,
  BANK_REFRESHING
} bank_state_t;

bank_state_t bank_state [0:NUM_BANKS-1];
logic [ROW_W-1:0] active_row [0:NUM_BANKS-1];
```

The controller tracks the state of each bank to determine whether an activate, precharge, or direct read/write is needed.

## Best Practices

1. Use compiled SRAM macros for memories larger than ~256 bits; flip-flop arrays are area-prohibitive.
2. Add BIST wrappers around all SRAM macros for manufacturing test.
3. Use byte-enable or bit-mask writes to avoid read-modify-write overhead.
4. Size FIFOs based on worst-case burst analysis, not average throughput.
5. Use round-robin arbitration as the default; fixed priority only when justified.
6. Register all SRAM outputs to meet timing.
7. Add ECC for critical data stores (especially in safety or high-reliability designs).
8. Verify memory interfaces with both directed tests and constrained-random stimulus targeting corner cases (simultaneous read/write, full/empty transitions, back-to-back operations).
