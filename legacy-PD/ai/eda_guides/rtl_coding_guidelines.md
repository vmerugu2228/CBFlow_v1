# RTL Coding Guidelines

## Overview

Consistent coding guidelines are the foundation of a maintainable, verifiable, and integrable RTL codebase. In a team environment, guidelines ensure that code written by one engineer can be read, reviewed, and modified by another. They prevent bugs by encoding lessons learned and industry best practices into enforceable rules. This guide covers naming conventions, module hierarchy, parameterization, generate blocks, and file organization practices used in professional ASIC design teams.

## Naming Conventions

### Signal Naming

Consistent signal naming communicates intent and prevents connection errors.

| Suffix/Prefix | Meaning | Example |
|---------------|---------|---------|
| `clk_` | Clock signal | `clk_core`, `clk_ddr` |
| `rst_` / `_n` | Reset (active-low with `_n`) | `rst_core_n` |
| `_en` | Enable | `wr_en`, `clk_en` |
| `_vld` / `_valid` | Data valid | `data_vld`, `rsp_valid` |
| `_rdy` / `_ready` | Ready/backpressure | `rx_rdy`, `fifo_ready` |
| `_d` / `_q` | D-input / Q-output of register | `state_d`, `state_q` |
| `_nxt` | Next-state value | `count_nxt` |
| `_r` / `_reg` | Registered version | `data_r`, `addr_reg` |
| `_s1`, `_s2` | Pipeline stage | `data_s1`, `result_s2` |
| `_async` | Asynchronous signal | `req_async` |
| `_sync` | Synchronized signal | `req_sync` |
| `_i` / `_o` | Input / output (at module ports) | `data_i`, `result_o` |

### Module Naming

```
<block>_<function>[_<qualifier>]
```

Examples: `uart_tx`, `axi_arbiter`, `dma_channel_ctrl`, `cache_data_ram`

Use lowercase with underscores. Module names should be globally unique across the project to avoid elaboration conflicts.

### Instance Naming

Use the `u_` prefix for instances:

```systemverilog
uart_tx u_uart_tx (.clk(clk), .data(tx_data), ...);
sync_fifo #(.DEPTH(16)) u_tx_fifo (.clk(clk), ...);
```

For generated instances, use the generate block label:

```systemverilog
generate
  for (genvar i = 0; i < N; i++) begin : gen_channel
    channel_proc u_ch (.data(ch_data[i]), ...);
  end
endgenerate
```

### Parameter Naming

```systemverilog
parameter  DATA_WIDTH  = 32;    // UPPER_CASE for parameters
localparam ADDR_BITS   = $clog2(DEPTH);  // UPPER_CASE for localparams
```

Use `UPPER_CASE_WITH_UNDERSCORES` for all parameters and localparams. Prefix related parameters with a common identifier: `FIFO_DEPTH`, `FIFO_WIDTH`, `FIFO_ALMOST_FULL`.

### Type Naming

```systemverilog
typedef enum logic [2:0] { ... } state_t;     // _t suffix for types
typedef struct packed { ... } req_pkt_t;       // _t suffix
```

### File Naming

One module per file. File name matches module name:

```
uart_tx.sv         -> module uart_tx
axi_arbiter.sv     -> module axi_arbiter
cpu_pkg.sv         -> package cpu_pkg
axi_if.sv          -> interface axi_if
```

## Module Hierarchy

### Hierarchy Principles

1. **Single responsibility**: Each module should do one thing well.
2. **Manageable size**: Modules should be 100-500 lines. Modules exceeding 1000 lines should be split.
3. **Clean interfaces**: Ports should represent logical interfaces, not internal implementation details.
4. **Consistent depth**: Avoid excessively deep hierarchy (>6 levels) that makes navigation difficult.
5. **Balanced width**: Avoid single-child hierarchies (wrapper around wrapper) without functional justification.

### Top-Level Module

The top-level module should primarily be structural (instantiation and wiring), with minimal or no RTL logic. It connects the major subsystems and provides the chip-level I/O interface.

```systemverilog
module soc_top (
  input  logic        clk_pad,
  input  logic        rst_pad_n,
  // I/O pads
  inout  wire [31:0]  gpio_pad,
  input  logic        uart_rx_pad,
  output logic        uart_tx_pad,
  // DDR interface
  output logic [13:0] ddr_addr,
  // ...
);

  // Clock generation
  clk_gen u_clk_gen (...);

  // Reset synchronization
  reset_sync u_rst_sync (...);

  // CPU subsystem
  cpu_subsys u_cpu (...);

  // Peripheral subsystem
  periph_subsys u_periph (...);

  // Interconnect
  axi_crossbar u_xbar (...);

endmodule
```

### Leaf Modules

Leaf modules contain the actual RTL logic. They should be self-contained, parameterized, and reusable.

### Glue Logic

Avoid scattering glue logic (muxes, decoders, clock gating) at the top level. Either integrate it into a relevant submodule or create a dedicated glue module.

## Parameterization

### Design for Reuse

Parameters make modules configurable without modifying the source.

```systemverilog
module sync_fifo #(
  parameter int DEPTH      = 16,
  parameter int WIDTH      = 32,
  parameter bit FWFT       = 1'b0,   // first-word-fall-through mode
  parameter int ALMOST_FULL_THRESH = DEPTH - 2
)(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             full,
  output logic             empty,
  output logic             almost_full
);

  localparam int ADDR_W = $clog2(DEPTH);
  // ...
endmodule
```

### Parameter Guidelines

1. **Use `parameter` for user-configurable values**: Width, depth, enable/disable features.
2. **Use `localparam` for derived values**: Address widths, internal constants.
3. **Provide sensible defaults**: Every parameter should have a default that produces a functional module.
4. **Validate parameters**: Use `generate if` or assertions to check parameter validity.

```systemverilog
initial begin
  assert (DEPTH > 0 && (DEPTH & (DEPTH-1)) == 0)
    else $fatal("DEPTH must be a positive power of 2, got %0d", DEPTH);
  assert (WIDTH > 0)
    else $fatal("WIDTH must be positive, got %0d", WIDTH);
end
```

5. **Document parameters**: Each parameter should have a comment explaining its purpose and valid range.

## Generate Blocks

### generate for

Creates multiple instances based on a parameter.

```systemverilog
generate
  for (genvar i = 0; i < NUM_PORTS; i++) begin : gen_port
    port_handler #(
      .PORT_ID(i),
      .WIDTH(DATA_WIDTH)
    ) u_port (
      .clk(clk),
      .data_in(port_data[i]),
      .data_out(port_result[i])
    );
  end
endgenerate
```

### generate if

Conditionally includes or excludes hardware based on parameters.

```systemverilog
generate
  if (ENABLE_ECC) begin : gen_ecc
    ecc_encoder u_enc (.data_in(wdata), .encoded(wdata_ecc));
    ecc_decoder u_dec (.encoded(rdata_ecc), .data_out(rdata), .error(ecc_err));
  end else begin : gen_no_ecc
    assign wdata_ecc = wdata;
    assign rdata     = rdata_ecc;
    assign ecc_err   = 1'b0;
  end
endgenerate
```

### Generate Guidelines

1. **Always label generate blocks**: The label becomes part of the hierarchical path and is essential for debug and constraint application.
2. **Avoid complex logic in generate**: Use generate for instantiation and simple assignments. Put complex logic inside the instantiated modules.
3. **One generate per feature**: Do not bundle unrelated conditional features into a single generate block.

## File Organization

### Directory Structure

```
rtl/
  top/
    soc_top.sv
  cpu/
    cpu_core.sv
    alu.sv
    regfile.sv
    decode.sv
  mem/
    cache_ctrl.sv
    sram_wrapper.sv
  periph/
    uart_tx.sv
    uart_rx.sv
    gpio_ctrl.sv
  common/
    sync_fifo.sv
    async_fifo.sv
    arbiter_rr.sv
    sync_2ff.sv
  pkg/
    cpu_pkg.sv
    bus_pkg.sv
  intf/
    axi_if.sv
    apb_if.sv
```

### File Headers

Every RTL file should have a header with:

```systemverilog
// ============================================================================
// Module: uart_tx
// Description: UART transmitter with configurable baud rate and data width
// Author: <name>
// Created: <date>
// ============================================================================
```

### Include Files

Use `.svh` extension for include files (header files with defines, typedefs):

```systemverilog
`include "project_defines.svh"
```

Minimize include file usage. Prefer packages for type definitions and constants.

## Code Formatting

1. **Indentation**: 2 spaces (no tabs). Consistent across the entire project.
2. **Line length**: 100 characters maximum.
3. **Port alignment**: Align port directions, types, widths, and names in columns.
4. **One statement per line**: Never put multiple statements on one line.
5. **Block labels**: Label all `begin`/`end` blocks for readability.
6. **Comments**: Comment the "why," not the "what." The code shows what; comments explain intent.

```systemverilog
// Delay the valid signal by 2 cycles to match the SRAM read latency
always_ff @(posedge clk or negedge rst_n) begin : valid_delay
  if (!rst_n) begin
    valid_d1 <= 1'b0;
    valid_d2 <= 1'b0;
  end else begin
    valid_d1 <= valid_in;
    valid_d2 <= valid_d1;
  end
end
```

## Review Enforcement

Coding guidelines are only effective if enforced. Use:

1. **Lint tools**: Configure SpyGlass/HAL to check naming conventions and coding rules.
2. **Code review checklists**: Include guideline compliance as a review criterion.
3. **Pre-commit hooks**: Automated checks on formatting and basic rules.
4. **Documentation**: Maintain a living coding guidelines document that evolves with the project.

## Summary

Naming conventions, clean hierarchy, thorough parameterization, disciplined use of generate blocks, and consistent file organization collectively produce an RTL codebase that is readable, maintainable, and integrable. Invest in guidelines early; the return compounds over the life of the project.
