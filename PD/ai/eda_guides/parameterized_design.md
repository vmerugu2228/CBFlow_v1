# Parameterized RTL Design

## Overview

Parameterized design is the practice of writing RTL modules that are configurable through parameters, enabling a single module to serve multiple use cases without code duplication. This is the hardware equivalent of generic programming. Well-parameterized IP blocks reduce development effort, improve quality through reuse, and simplify design integration. This guide covers parameter usage, generate blocks, configurable modules, and the principles of IP parameterization.

## Parameters and Localparams

### Parameter Declaration

Parameters are compile-time constants that can be overridden when a module is instantiated.

```systemverilog
module fifo #(
  parameter int DEPTH         = 16,
  parameter int WIDTH         = 32,
  parameter bit FWFT          = 1'b0,     // first-word-fall-through
  parameter int ALMOST_FULL   = DEPTH - 2,
  parameter int ALMOST_EMPTY  = 2
)(
  input  logic             clk,
  input  logic             rst_n,
  input  logic [WIDTH-1:0] wr_data,
  input  logic             wr_en,
  output logic [WIDTH-1:0] rd_data,
  input  logic             rd_en,
  output logic             full,
  output logic             empty,
  output logic             almost_full,
  output logic             almost_empty
);
```

### Localparam for Derived Constants

```systemverilog
localparam int ADDR_W     = $clog2(DEPTH);
localparam int COUNT_W    = $clog2(DEPTH) + 1;
localparam int BYTE_W     = WIDTH / 8;
```

`localparam` values cannot be overridden from outside the module. Use them for all constants derived from parameters.

### Parameter Types

SystemVerilog supports typed parameters:

```systemverilog
parameter int unsigned DEPTH = 16;       // unsigned integer
parameter bit          ECC_EN = 1'b0;    // single bit
parameter real         FREQ_MHZ = 100.0; // real (simulation only)
parameter type         DATA_T = logic [31:0]; // type parameter
```

Type parameters allow modules to be generic over data types:

```systemverilog
module register #(
  parameter type T = logic [31:0]
)(
  input  logic clk, rst_n,
  input  T     d,
  output T     q
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) q <= T'(0);
    else        q <= d;
  end
endmodule
```

## Parameter Override at Instantiation

### Named Parameter Override (Preferred)

```systemverilog
fifo #(
  .DEPTH(64),
  .WIDTH(128),
  .FWFT(1'b1),
  .ALMOST_FULL(60)
) u_data_fifo (
  .clk(clk),
  .rst_n(rst_n),
  .wr_data(data_in),
  .wr_en(wr_valid),
  .rd_data(data_out),
  .rd_en(rd_ready),
  .full(fifo_full),
  .empty(fifo_empty),
  .almost_full(fifo_af),
  .almost_empty(fifo_ae)
);
```

Always use named parameter connections for clarity and resilience to parameter reordering.

### defparam (Deprecated)

```systemverilog
// AVOID: defparam is deprecated and may not be supported in all tools
defparam u_fifo.DEPTH = 64;
defparam u_fifo.WIDTH = 128;
```

Never use `defparam`. It is deprecated in SystemVerilog and creates non-local modification that is difficult to track.

## Parameter Validation

### Compile-Time Assertions

```systemverilog
// Check parameters at elaboration time
initial begin
  assert (DEPTH > 0) else $fatal(1, "DEPTH must be positive, got %0d", DEPTH);
  assert ((DEPTH & (DEPTH-1)) == 0)
    else $fatal(1, "DEPTH must be power of 2 for gray-code pointers, got %0d", DEPTH);
  assert (WIDTH > 0) else $fatal(1, "WIDTH must be positive, got %0d", WIDTH);
  assert (ALMOST_FULL > 0 && ALMOST_FULL < DEPTH)
    else $fatal(1, "ALMOST_FULL out of range: %0d (valid: 1 to %0d)", ALMOST_FULL, DEPTH-1);
end
```

### Generate-Based Validation

```systemverilog
generate
  if (DEPTH < 2 || DEPTH > 65536) begin : gen_invalid_depth
    // This creates a compile error with a descriptive name
    INVALID_PARAMETER_DEPTH_OUT_OF_RANGE invalid_inst();
  end
endgenerate
```

This trick causes a compilation error with a meaningful name if the parameter is out of range.

## Generate Blocks

### generate for: Structural Replication

```systemverilog
module crossbar #(
  parameter int NUM_MASTERS = 4,
  parameter int NUM_SLAVES  = 4,
  parameter int DATA_W      = 64
)(
  input  logic [NUM_MASTERS-1:0][DATA_W-1:0] m_data,
  input  logic [NUM_MASTERS-1:0][$clog2(NUM_SLAVES)-1:0] m_sel,
  output logic [NUM_SLAVES-1:0][DATA_W-1:0] s_data
);

  genvar m, s;
  generate
    for (s = 0; s < NUM_SLAVES; s++) begin : gen_slave
      // For each slave, mux from all masters
      logic [NUM_MASTERS-1:0] master_sel;

      for (m = 0; m < NUM_MASTERS; m++) begin : gen_master_check
        assign master_sel[m] = (m_sel[m] == s);
      end

      // Priority mux (first master with matching select wins)
      always_comb begin
        s_data[s] = '0;
        for (int i = 0; i < NUM_MASTERS; i++) begin
          if (master_sel[i]) begin
            s_data[s] = m_data[i];
            break;
          end
        end
      end
    end
  endgenerate

endmodule
```

### generate if: Feature Selection

```systemverilog
module data_path #(
  parameter bit ENABLE_ECC      = 1'b0,
  parameter bit ENABLE_PARITY   = 1'b0,
  parameter int WIDTH           = 32
)(
  input  logic [WIDTH-1:0] data_in,
  output logic [WIDTH-1:0] data_out,
  output logic             error
);

  generate
    if (ENABLE_ECC) begin : gen_ecc
      localparam int ECC_BITS = calc_ecc_bits(WIDTH);
      logic [WIDTH+ECC_BITS-1:0] encoded;

      ecc_encoder #(.WIDTH(WIDTH)) u_enc (
        .data_in(data_in), .encoded(encoded)
      );
      ecc_decoder #(.WIDTH(WIDTH)) u_dec (
        .encoded(encoded), .data_out(data_out), .error(error)
      );
    end else if (ENABLE_PARITY) begin : gen_parity
      assign data_out = data_in;
      assign error    = ^data_in;  // simple parity
    end else begin : gen_passthru
      assign data_out = data_in;
      assign error    = 1'b0;
    end
  endgenerate

endmodule
```

### generate case

```systemverilog
generate
  case (IMPLEMENTATION)
    "FAST": begin : gen_fast
      fast_adder #(.WIDTH(WIDTH)) u_add (.*);
    end
    "SMALL": begin : gen_small
      small_adder #(.WIDTH(WIDTH)) u_add (.*);
    end
    "BALANCED": begin : gen_balanced
      balanced_adder #(.WIDTH(WIDTH)) u_add (.*);
    end
    default: begin : gen_default
      balanced_adder #(.WIDTH(WIDTH)) u_add (.*);
    end
  endcase
endgenerate
```

## Configurable Module Design Patterns

### Width-Parameterized Module

The most basic parameterization: make data widths configurable.

```systemverilog
module register_file #(
  parameter int NUM_REGS  = 32,
  parameter int REG_WIDTH = 64,
  parameter int RD_PORTS  = 2,
  parameter int WR_PORTS  = 1
)(
  input  logic                      clk,
  input  logic                      rst_n,
  // Read ports
  input  logic [RD_PORTS-1:0][$clog2(NUM_REGS)-1:0] rd_addr,
  output logic [RD_PORTS-1:0][REG_WIDTH-1:0]          rd_data,
  // Write ports
  input  logic [WR_PORTS-1:0]                          wr_en,
  input  logic [WR_PORTS-1:0][$clog2(NUM_REGS)-1:0]   wr_addr,
  input  logic [WR_PORTS-1:0][REG_WIDTH-1:0]           wr_data
);

  logic [REG_WIDTH-1:0] regs [0:NUM_REGS-1];

  // Multi-port read
  generate
    for (genvar r = 0; r < RD_PORTS; r++) begin : gen_rd
      assign rd_data[r] = regs[rd_addr[r]];
    end
  endgenerate

  // Multi-port write (priority to lower port index)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_REGS; i++)
        regs[i] <= '0;
    end else begin
      for (int w = 0; w < WR_PORTS; w++) begin
        if (wr_en[w])
          regs[wr_addr[w]] <= wr_data[w];
      end
    end
  end

endmodule
```

### Feature-Gated Module

Use boolean parameters to include or exclude features:

```systemverilog
module uart #(
  parameter int  BAUD_DIV    = 868,     // clock cycles per bit
  parameter int  DATA_BITS   = 8,       // 5, 6, 7, or 8
  parameter bit  PARITY_EN   = 1'b0,    // enable parity
  parameter bit  EVEN_PARITY = 1'b1,    // 1=even, 0=odd
  parameter int  STOP_BITS   = 1,       // 1 or 2
  parameter int  FIFO_DEPTH  = 16       // TX/RX FIFO depth (0 = no FIFO)
)(
  // ports
);
```

### Protocol-Configurable Module

```systemverilog
module bus_bridge #(
  parameter string SRC_PROTOCOL = "AXI4",   // "AXI4", "AHB", "APB"
  parameter string DST_PROTOCOL = "APB",
  parameter int    ADDR_WIDTH   = 32,
  parameter int    DATA_WIDTH   = 32
)(
  // Generalized port interface
);
```

## IP Parameterization Best Practices

### 1. Minimal Parameter Set

Expose only the parameters that users need to configure. Derive everything else internally.

```systemverilog
// USER-FACING: only depth and width
parameter int DEPTH = 16;
parameter int WIDTH = 32;

// INTERNAL: derived automatically
localparam int ADDR_W  = $clog2(DEPTH);
localparam int COUNT_W = ADDR_W + 1;
localparam int BYTE_W  = (WIDTH + 7) / 8;
```

### 2. Sensible Defaults

Every parameter should have a default value that produces a working, representative configuration.

### 3. Complete Validation

Check all parameter constraints at compile time. Provide clear error messages.

### 4. Test Multiple Configurations

Verify the design with multiple parameter combinations, not just the default:

```systemverilog
// Testbench instantiation sweep
fifo #(.DEPTH(4),  .WIDTH(8))   u_small  (...);
fifo #(.DEPTH(16), .WIDTH(32))  u_medium (...);
fifo #(.DEPTH(256),.WIDTH(128)) u_large  (...);
fifo #(.DEPTH(16), .WIDTH(32), .FWFT(1)) u_fwft (...);
```

### 5. Document Parameters

Each parameter needs documentation covering its purpose, valid range, default value, and interaction with other parameters.

### 6. Avoid String Parameters for Synthesis

String parameters (`parameter string`) are useful for configuration files and testbenches but may not be supported by all synthesis tools. Use integer or enum parameters for synthesizable code.

## Advanced: Package-Based Configuration

For complex IPs with many parameters, use a configuration package:

```systemverilog
package cpu_config;
  parameter int XLEN         = 64;
  parameter int NUM_HARTS    = 4;
  parameter bit ENABLE_FPU   = 1'b1;
  parameter bit ENABLE_MMU   = 1'b1;
  parameter int ICACHE_SIZE  = 32768;  // bytes
  parameter int DCACHE_SIZE  = 32768;
  parameter int TLB_ENTRIES  = 64;
endpackage

module cpu_core
  import cpu_config::*;
(
  input logic clk, rst_n,
  // ...
);
```

This centralizes configuration in one place, making it easy to create different product variants.

## Summary

Parameterized design is about writing hardware once and configuring it many times. Use parameters for user-facing configuration, localparams for derived values, generate blocks for structural variation, and thorough validation to catch invalid configurations early. Well-parameterized IP is the foundation of productive hardware design teams.
