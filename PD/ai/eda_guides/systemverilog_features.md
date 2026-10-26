# SystemVerilog Features for RTL Design

## Overview

SystemVerilog (IEEE 1800) extends Verilog with features that improve RTL coding, verification, and design intent expression. For RTL designers, the key additions include enhanced always blocks, interfaces, packages, enumerated types, and assertion capabilities. For verification engineers, SystemVerilog adds classes, constrained randomization, functional coverage, and a rich set of constructs for building sophisticated testbenches. This guide covers both sides with emphasis on practical usage.

## Enhanced Always Blocks

SystemVerilog introduces `always_comb`, `always_ff`, and `always_latch` to replace the generic `always` block. These encode design intent and enable compiler checks.

### always_comb

```systemverilog
always_comb begin
  result = '0;  // default
  case (opcode)
    ADD: result = a + b;
    SUB: result = a - b;
    AND: result = a & b;
    OR:  result = a | b;
  endcase
end
```

The compiler warns if the block infers latches, uses non-blocking assignments, or has signals in the sensitivity list that should not be there. It also triggers at time zero, unlike `always @(*)`.

### always_ff

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    count <= '0;
  else if (en)
    count <= count + 1'b1;
end
```

The compiler enforces that only non-blocking assignments are used and that the sensitivity list contains edge expressions.

## Interfaces

Interfaces bundle related signals into a single named entity, dramatically reducing port lists and connection errors in complex designs.

```systemverilog
interface axi_if #(parameter ADDR_W = 32, DATA_W = 64);
  logic [ADDR_W-1:0] awaddr;
  logic [2:0]        awprot;
  logic               awvalid;
  logic               awready;
  logic [DATA_W-1:0] wdata;
  logic [DATA_W/8-1:0] wstrb;
  logic               wvalid;
  logic               wready;
  // ... additional signals

  modport master (
    output awaddr, awprot, awvalid, wdata, wstrb, wvalid,
    input  awready, wready
  );

  modport slave (
    input  awaddr, awprot, awvalid, wdata, wstrb, wvalid,
    output awready, wready
  );
endinterface
```

### Using Interfaces

```systemverilog
module axi_master (
  input logic clk,
  input logic rst_n,
  axi_if.master axi
);
  // access signals as axi.awaddr, axi.awvalid, etc.
endmodule
```

Interfaces are fully synthesizable and supported by major synthesis tools. They are especially valuable for standard bus protocols where the same signal bundle is replicated across many modules.

## Packages

Packages provide a namespace for sharing type definitions, constants, and functions across modules without relying on `include` files.

```systemverilog
package cpu_pkg;
  typedef enum logic [3:0] {
    ADD  = 4'b0000,
    SUB  = 4'b0001,
    AND  = 4'b0010,
    OR   = 4'b0011,
    XOR  = 4'b0100,
    SLL  = 4'b0101,
    SRL  = 4'b0110,
    SRA  = 4'b0111
  } opcode_t;

  typedef struct packed {
    logic [31:0] pc;
    opcode_t     opcode;
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] imm;
  } decoded_instr_t;

  function automatic logic [31:0] sign_extend(input logic [15:0] val);
    return {{16{val[15]}}, val};
  endfunction
endpackage
```

Import with `import cpu_pkg::*;` or selectively with `import cpu_pkg::opcode_t;`.

## Data Types

### logic

`logic` replaces both `wire` and `reg`. It can be driven by continuous assignments, port connections, or procedural blocks (but not multiple drivers). Use `logic` as the default type for all signals.

### Enumerated Types

```systemverilog
typedef enum logic [2:0] {
  IDLE   = 3'b000,
  FETCH  = 3'b001,
  DECODE = 3'b010,
  EXEC   = 3'b011,
  WB     = 3'b100
} state_t;

state_t curr_state, next_state;
```

Enums provide named constants with type safety. Specifying the underlying `logic` type and explicit encoding ensures synthesizable, predictable behavior. The `.name()` method returns the symbolic name in simulation, aiding debug.

### Structs

```systemverilog
typedef struct packed {
  logic        valid;
  logic [31:0] addr;
  logic [63:0] data;
  logic [7:0]  byte_en;
} mem_req_t;
```

`packed` structs map to a contiguous bit vector, making them synthesizable and usable in ports and assignments. Unpacked structs are for simulation/testbench use only.

### Unions

```systemverilog
typedef union packed {
  logic [31:0] word;
  struct packed {
    logic [15:0] upper;
    logic [15:0] lower;
  } halves;
} word_u;
```

Tagged unions (`tagged union`) add type safety but have limited synthesis support.

## Assertions

SystemVerilog Assertions (SVA) enable formal and simulation-based property checking directly in RTL.

### Immediate Assertions

```systemverilog
always_comb begin
  assert (onehot_bus == '0 || $onehot(onehot_bus))
    else $error("onehot_bus has multiple bits set: %b", onehot_bus);
end
```

### Concurrent Assertions

```systemverilog
property p_req_ack;
  @(posedge clk) disable iff (!rst_n)
  req |-> ##[1:3] ack;
endproperty

assert property (p_req_ack)
  else $error("ACK not received within 3 cycles of REQ");
```

Concurrent assertions are evaluated every clock cycle and can express temporal properties. The `|->` operator is an overlapping implication; `|=>` is a non-overlapping (next-cycle) implication.

### Common SVA Sequences

```systemverilog
// Signal must be stable while valid is high
property p_stable_while_valid;
  @(posedge clk) disable iff (!rst_n)
  (valid && !ready) |=> $stable(data);
endproperty

// Handshake: valid must stay high until ready
property p_valid_until_ready;
  @(posedge clk) disable iff (!rst_n)
  (valid && !ready) |=> valid;
endproperty
```

Assertions serve dual purposes: they catch bugs in simulation and they are input to formal verification tools.

## Covergroups

Functional coverage measures whether the testbench has exercised all interesting scenarios.

```systemverilog
covergroup cg_opcode @(posedge clk);
  cp_opcode: coverpoint opcode {
    bins arithmetic[] = {ADD, SUB, MUL, DIV};
    bins logical[]    = {AND, OR, XOR};
    bins shift[]      = {SLL, SRL, SRA};
    illegal_bins reserved = {4'b1111};
  }
  cp_size: coverpoint transfer_size {
    bins small  = {[1:4]};
    bins medium = {[5:16]};
    bins large  = {[17:64]};
  }
  cross_op_size: cross cp_opcode, cp_size;
endgroup
```

Coverage data is collected during simulation and analyzed to identify untested scenarios.

## unique and priority

These keywords annotate `if` and `case` statements to communicate design intent to both simulation and synthesis.

### unique

```systemverilog
unique case (state)
  IDLE:  next_state = start ? ACTIVE : IDLE;
  ACTIVE: next_state = done ? IDLE : ACTIVE;
endcase
```

`unique` asserts that exactly one branch matches. In simulation, a violation (no match or multiple matches) generates a warning. In synthesis, the tool can optimize assuming mutual exclusivity (similar to `parallel_case`).

### priority

```systemverilog
priority if (emergency)
  action = STOP;
else if (warning)
  action = SLOW;
else
  action = GO;
```

`priority` asserts that at least one branch matches (no fall-through). The evaluation order is preserved as priority logic.

### Practical Guidelines

Use `unique` for one-hot decoded selects and FSM case statements where exactly one branch should match. Use `priority` for priority-encoded structures. These keywords replace the problematic `synopsys full_case parallel_case` pragmas with standardized, simulation-visible behavior.

## Classes (Verification)

Classes are the foundation of object-oriented testbenches in SystemVerilog. They are not synthesizable but are essential for UVM-based verification.

```systemverilog
class transaction;
  rand logic [31:0] addr;
  rand logic [63:0] data;
  rand logic [2:0]  burst_len;

  constraint c_aligned { addr[1:0] == 2'b00; }
  constraint c_burst   { burst_len inside {1, 2, 4, 8}; }

  function void display();
    $display("ADDR=%h DATA=%h BURST=%0d", addr, data, burst_len);
  endfunction
endclass
```

Constrained randomization (`rand` fields with `constraint` blocks) enables directed-random testing, which achieves far higher coverage than purely directed tests.

## Summary

SystemVerilog's RTL features (enhanced always blocks, interfaces, packages, enums, structs, `unique`/`priority`) make designs more readable, less error-prone, and more amenable to tool analysis. Its verification features (classes, assertions, covergroups, constrained randomization) enable industrial-strength verification. Adopting SystemVerilog over plain Verilog is strongly recommended for any new design project.
