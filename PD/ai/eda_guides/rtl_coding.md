# RTL Coding for Synthesis

## Overview

Register Transfer Level (RTL) coding is the process of describing hardware behavior in a hardware description language (HDL) such as Verilog or SystemVerilog. While PD engineers do not typically write RTL, they must understand synthesizable coding practices because the quality of RTL directly determines the quality of the gate-level netlist they implement. Poor RTL creates unnecessarily long timing paths, excessive area, unwanted latches, and synthesis warnings that propagate into physical design headaches. This guide covers synthesizable coding guidelines, common pitfalls, and their physical implications.

## Synthesizable vs. Non-Synthesizable Constructs

### Synthesizable Constructs

These HDL constructs map to hardware and are accepted by synthesis tools:

- **always_ff** (SystemVerilog) / **always @(posedge clk)**: Infers flip-flops
- **always_comb** (SystemVerilog) / **always @(*)**: Infers combinational logic
- **assign**: Continuous assignment for combinational logic
- **if-else, case, ternary operator**: Conditional logic (maps to muxes and gates)
- **Arithmetic operators (+, -, *, /, %)**: Map to adder, subtractor, multiplier circuits
- **Logical and bitwise operators**: Map directly to gates
- **generate**: Structural repetition for parameterized designs
- **Module instantiation**: Hierarchical composition

### Non-Synthesizable Constructs

These are simulation-only and will be ignored or cause errors during synthesis:

- **initial blocks**: Used only in testbenches
- **Delays (#10)**: Ignored by synthesis; timing is determined by the technology library
- **System tasks ($display, $monitor, $finish)**: Simulation utilities
- **force/release**: Simulation debug constructs
- **Real data types**: No floating-point hardware inferred

## Coding Guidelines for Timing

### Keep Combinational Depth Shallow

Long combinational paths are the primary cause of timing closure difficulty.

```verilog
// BAD: Deep combinational chain
assign result = ((a + b) * c) >> (d & e) + f;

// BETTER: Pipeline the computation
always_ff @(posedge clk) begin
    stage1 <= a + b;
    stage2 <= stage1 * c;
    stage3 <= stage2 >> (d_delayed & e_delayed) + f_delayed;
end
```

**Physical impact**: Each additional logic level adds 30-100ps of delay (technology dependent). A 20-level path at 1GHz (1000ps period) leaves only 500-600ps for useful logic after accounting for setup, CQ, skew, and margin.

### Avoid Unnecessary Priority Logic

If-else chains create priority encoders; case statements create parallel muxes.

```verilog
// Creates priority chain (each condition depends on previous)
always_comb begin
    if (sel == 3'b000)      out = a;
    else if (sel == 3'b001) out = b;
    else if (sel == 3'b010) out = c;
    else if (sel == 3'b011) out = d;
    // ... 8 levels of priority
end

// Parallel decode (all conditions evaluated simultaneously)
always_comb begin
    case (sel)
        3'b000: out = a;
        3'b001: out = b;
        3'b010: out = c;
        3'b011: out = d;
        default: out = '0;
    endcase
end
```

**When priority is needed**: Use if-else when conditions genuinely have priority (e.g., interrupt arbitration). Use case when conditions are mutually exclusive.

### Minimize Fan-Out in RTL

A signal driving many destinations creates high fan-out, requiring buffer insertion that adds delay and area.

```verilog
// High fan-out: 'enable' drives 256 registers
always_ff @(posedge clk)
    if (enable)
        data_reg[255:0] <= data_in[255:0];

// Better: Replicate enable locally (synthesis can do this, but explicit is clearer)
// Or use clock gating to reduce toggle count
```

**Physical impact**: A net with fan-out > 50-100 typically requires a buffer tree, adding 2-4 levels of delay.

### Register Outputs of Modules

Registering module outputs prevents combinational path accumulation across hierarchy.

```verilog
module my_block (
    input  logic        clk,
    input  logic [31:0] data_in,
    output logic [31:0] data_out  // Registered output
);
    logic [31:0] computed;
    assign computed = /* combinational logic */;

    always_ff @(posedge clk)
        data_out <= computed;
endmodule
```

**Physical impact**: Without registered outputs, combinational paths can span multiple modules, creating long timing paths that are difficult to optimize and constrain.

## Common Synthesis Pitfalls

### Latch Inference

The most common and dangerous RTL coding error. Latches are inferred when combinational logic does not assign a value to a signal in all possible paths.

```verilog
// BAD: Latch inferred (missing else or missing case)
always_comb begin
    if (sel)
        out = a;
    // No else! 'out' retains its value -> latch
end

// BAD: Incomplete case
always_comb begin
    case (sel)
        2'b00: out = a;
        2'b01: out = b;
        // Missing 2'b10, 2'b11 -> latch
    endcase
end

// GOOD: Complete assignment
always_comb begin
    out = '0;  // Default assignment
    if (sel)
        out = a;
end

// GOOD: Complete case with default
always_comb begin
    case (sel)
        2'b00: out = a;
        2'b01: out = b;
        default: out = '0;
    endcase
end
```

**Physical impact**: Unintended latches create timing paths that are difficult to constrain and analyze. They also create functional bugs that may not be caught until silicon.

**Detection**: Synthesis tools report latch inference in their logs. PD engineers should check for and flag these warnings during synthesis review.

### Combinational Loops

A combinational loop occurs when a signal feeds back to itself through purely combinational logic, with no register in the path.

```verilog
// BAD: Combinational loop
assign a = b & c;
assign b = a | d;  // 'a' depends on 'b', 'b' depends on 'a'
```

**Physical impact**: Combinational loops cause STA tools to fail or produce incorrect results. They represent oscillatory or undefined behavior.

### Multi-Driven Nets

A net driven by multiple sources causes contention.

```verilog
// BAD: Two drivers on 'out'
assign out = a;
assign out = b;  // Conflict!
```

**Physical impact**: Multi-driven nets cause shorts in the layout. Synthesis tools typically error on this, but it can occur subtly with tri-state logic or incorrect module connectivity.

### Blocking vs. Non-Blocking Assignments

```verilog
// RULE: Use non-blocking (<=) in sequential always blocks
always_ff @(posedge clk) begin
    a <= b;  // Non-blocking: correct for sequential
    c <= a;  // 'c' gets the OLD value of 'a'
end

// RULE: Use blocking (=) in combinational always blocks
always_comb begin
    temp = a + b;  // Blocking: correct for combinational
    out = temp * c;
end
```

Mixing blocking and non-blocking in sequential blocks causes simulation-synthesis mismatch: simulation may show correct behavior but synthesis produces incorrect hardware.

## Clock Gating

Clock gating is the most effective technique for reducing dynamic power. Instead of enabling/disabling a register with a data mux, the clock itself is gated.

```verilog
// Implicit clock gating (synthesis tool infers ICG cell)
always_ff @(posedge clk)
    if (enable)
        data_reg <= data_in;

// Synthesis recognizes this pattern and replaces it with:
// ICG (Integrated Clock Gate) cell -> gated_clk
// always_ff @(posedge gated_clk) data_reg <= data_in;
```

### Clock Gating Guidelines

- Enable clock gating inference in synthesis (tool-specific setting)
- Set minimum bit width for clock gating (e.g., only gate groups of 4+ bits to amortize ICG cell overhead)
- Verify clock gating effectiveness: measure percentage of flip-flops that are clock-gated
- Target > 90% clock gating coverage for power-efficient designs

**Physical impact**: Each ICG cell adds a small amount of area and insertion delay to the clock path. CTS must handle ICG cells as part of the clock tree.

## Reset Strategy

### Synchronous vs. Asynchronous Reset

```verilog
// Synchronous reset
always_ff @(posedge clk)
    if (rst)
        q <= '0;
    else
        q <= d;

// Asynchronous reset
always_ff @(posedge clk or posedge rst)
    if (rst)
        q <= '0;
    else
        q <= d;
```

**Synchronous reset**: Adds a mux in the data path; requires the clock to be running for reset; simpler STA
**Asynchronous reset**: Does not require clock; adds reset routing and recovery/removal timing constraints; more complex STA

**Physical impact**: Asynchronous reset requires routing the reset signal to every flip-flop, creating a high-fan-out net. The reset deassertion must be synchronized to the clock to avoid metastability (reset synchronizer circuit).

### Reset Minimization

Not every flip-flop needs a reset. Datapath registers that will be written before they are read do not need reset.

```verilog
// Pipeline data register: no reset needed
always_ff @(posedge clk)
    pipe_stage2 <= pipe_stage1;  // Will be written before read

// Control FSM: reset required
always_ff @(posedge clk or negedge rst_n)
    if (!rst_n)
        state <= IDLE;
    else
        state <= next_state;
```

**Physical impact**: Removing unnecessary resets reduces routing congestion (reset net fan-out) and saves area (simpler flip-flop cells).

## Parameterized and Reusable RTL

### Parameters and Generics

```verilog
module fifo #(
    parameter DEPTH = 16,
    parameter WIDTH = 32
) (
    input  logic             clk,
    input  logic [WIDTH-1:0] data_in,
    output logic [WIDTH-1:0] data_out,
    // ...
);
```

Parameterized modules enable reuse across different configurations. PD engineers should understand that changing parameters changes the resulting hardware (and timing/area characteristics).

### Generate Blocks

```verilog
generate
    for (genvar i = 0; i < NUM_LANES; i++) begin : lane
        processing_unit u_proc (
            .clk(clk),
            .data_in(data_in[i]),
            .data_out(data_out[i])
        );
    end
endgenerate
```

**Physical impact**: Generate blocks create regular, replicated structures that benefit from structured placement techniques (placement groups, regions).

## RTL-to-Physical Interface

### Synthesis Constraints (SDC)

The SDC file bridges RTL intent and physical implementation:

- **create_clock**: Defines clock frequency (the target the RTL was designed for)
- **set_input_delay / set_output_delay**: Defines timing requirements at I/O ports
- **set_false_path / set_multicycle_path**: Captures design intent that cannot be expressed in RTL alone
- **set_max_fanout**: Limits fan-out to control buffering

### Synthesis Reports to Review

PD engineers should review these synthesis reports before starting physical implementation:

1. **Timing report**: Are there paths with large negative slack? These will be hard to close in PnR
2. **Area report**: Does the cell area match expectations? Unexpected area growth indicates RTL issues
3. **Warning log**: Latch inference, undriven nets, constant-driven ports, width mismatches
4. **Power report**: Baseline power estimate
5. **QoR summary**: Cell count by type (combinational, sequential, buffer)

Understanding RTL coding practices helps PD engineers communicate effectively with RTL designers, diagnose synthesis issues, and propose RTL changes that improve physical implementation quality.
