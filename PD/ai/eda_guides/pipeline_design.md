# Pipeline Design

## Overview

Pipelining is the fundamental technique for increasing throughput in digital systems. By dividing a long combinational path into multiple stages separated by registers, pipelining allows multiple operations to execute concurrently at different stages, trading latency for throughput. Virtually every high-performance digital design, from processors to signal processing chains to network packet engines, relies on pipelining. This guide covers pipeline design principles, hazard management, and practical tradeoffs.

## Pipeline Fundamentals

### Basic Concept

Consider a combinational block with a delay of 40ns. Without pipelining, it can produce one result every 40ns (25 MHz throughput). By inserting registers that divide the path into four 10ns stages, the clock period drops to 10ns, achieving 100 MHz throughput. However, each individual result now takes 4 clock cycles (40ns latency) instead of 1 cycle.

```
Without pipeline:  [---- 40ns combinational path ----] -> result every 40ns

With 4 stages:     [10ns] | [10ns] | [10ns] | [10ns] -> result every 10ns
                    Stage1  Stage2   Stage3   Stage4     (4-cycle latency)
```

### Throughput vs Latency

- **Throughput**: Number of results per unit time. Increases with more pipeline stages (up to a point).
- **Latency**: Time from input to corresponding output. Increases with more pipeline stages.
- **Pipeline rate**: Determined by the slowest stage (bottleneck). All stages must complete within one clock period.

### Balanced Stages

For maximum throughput, all stages should have approximately equal delay. An unbalanced pipeline where one stage is much longer than others wastes the potential of the shorter stages.

```systemverilog
// Stage 1: decode and operand fetch
always_ff @(posedge clk) begin
  if (valid_in) begin
    op_s1     <= decode(instr);
    operand_a <= reg_file[rs1];
    operand_b <= reg_file[rs2];
    valid_s1  <= 1'b1;
  end else begin
    valid_s1  <= 1'b0;
  end
end

// Stage 2: execute
always_ff @(posedge clk) begin
  if (valid_s1) begin
    result_s2 <= alu(op_s1, operand_a, operand_b);
    valid_s2  <= 1'b1;
  end else begin
    valid_s2  <= 1'b0;
  end
end

// Stage 3: write back
always_ff @(posedge clk) begin
  if (valid_s2) begin
    reg_file[rd_s2] <= result_s2;
    valid_out       <= 1'b1;
  end else begin
    valid_out       <= 1'b0;
  end
end
```

## Pipeline Hazards

Hazards are situations where the pipeline cannot proceed normally because of dependencies between stages.

### Data Hazards

A data hazard occurs when an instruction depends on the result of a previous instruction that has not yet completed. There are three types:

**Read After Write (RAW)**: The most common. Instruction B reads a value that instruction A writes, but A has not yet written it.

```
Cycle 1: A enters Stage 1 (will produce result in Stage 3)
Cycle 2: B enters Stage 1 (needs A's result now)
```

**Write After Read (WAR)**: Instruction B writes a value that instruction A reads. In simple in-order pipelines, this cannot occur because reads happen before writes.

**Write After Write (WAW)**: Two instructions write to the same destination. In simple pipelines, this is handled naturally by execution order.

### Control Hazards

A control hazard occurs when the pipeline makes a wrong prediction about the next instruction to fetch, typically due to a branch.

### Structural Hazards

A structural hazard occurs when two pipeline stages need the same hardware resource simultaneously (e.g., a single-ported memory accessed by both fetch and memory stages).

## Hazard Resolution Techniques

### Stalling (Pipeline Bubble)

The simplest approach: stop the upstream stages until the hazard is resolved.

```systemverilog
// Stall logic: freeze stages 1 and 2 if stage 2 result is needed by stage 1
wire stall = valid_s1 && valid_s2 &&
             ((rs1_s1 == rd_s2) || (rs2_s1 == rd_s2));

always_ff @(posedge clk) begin
  if (!stall) begin
    // Stage 1 progresses normally
    operand_a_s1 <= reg_file[rs1];
    operand_b_s1 <= reg_file[rs2];
    valid_s1     <= valid_in;
  end
  // When stalled, stage 1 registers hold their values
end
```

Stalls reduce throughput. The pipeline processes zero useful work during bubble cycles.

### Forwarding (Bypassing)

Forward the result from a later stage directly to an earlier stage that needs it, bypassing the register file.

```systemverilog
// Forward from stage 2 output to stage 1 input
always_comb begin
  if (valid_s2 && (rs1_s1 == rd_s2))
    alu_a = result_s2;  // forward
  else
    alu_a = operand_a_s1;  // normal read

  if (valid_s2 && (rs2_s1 == rd_s2))
    alu_b = result_s2;  // forward
  else
    alu_b = operand_b_s1;  // normal read
end
```

Forwarding eliminates stalls for many RAW hazards but adds mux delay to the critical path. The forwarding network grows quadratically with pipeline depth.

### Speculative Execution

For control hazards, predict the branch outcome and continue executing speculatively. If the prediction is wrong, flush the pipeline (discard speculative results) and restart from the correct path.

```systemverilog
// Flush on branch misprediction
always_ff @(posedge clk) begin
  if (branch_mispredict) begin
    valid_s1 <= 1'b0;  // kill stage 1
    valid_s2 <= 1'b0;  // kill stage 2
    pc       <= branch_target;
  end
end
```

## Valid-Ready Pipeline Protocol

The valid-ready (or valid/stall) handshake is the standard protocol for pipelines with variable-latency stages and backpressure.

```systemverilog
// Pipeline stage with valid-ready handshake
module pipe_stage (
  input  logic       clk, rst_n,
  input  logic       valid_in,
  input  logic [W:0] data_in,
  output logic       ready_out,    // backpressure to upstream

  output logic       valid_out,
  output logic [W:0] data_out,
  input  logic       ready_in      // backpressure from downstream
);

  wire advance = valid_in && ready_out;

  // Ready when: empty, or downstream is consuming our data
  assign ready_out = !valid_out || ready_in;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
    end else if (ready_out) begin
      valid_out <= valid_in;
      data_out  <= data_in;
    end
  end

endmodule
```

### Protocol Rules

1. **Valid** asserts when the producer has data. It must not depend on `ready`.
2. **Ready** asserts when the consumer can accept data. It must not depend on `valid` (to avoid combinational loops).
3. Transfer occurs when both `valid` and `ready` are asserted on the same clock edge.
4. Once `valid` is asserted, it must remain asserted until the transfer completes (data must not change).

This is the same protocol used by AXI and many other bus standards.

## Pipeline Depth Tradeoffs

### Benefits of Deeper Pipelines

- Higher clock frequency (shorter combinational paths per stage).
- Higher throughput when the pipeline is full.

### Costs of Deeper Pipelines

- Higher latency per operation.
- More flip-flops (area and power).
- More complex hazard detection and forwarding.
- Pipeline flush on misprediction costs more cycles.
- Diminishing returns: register overhead (setup + hold + clock-to-q) becomes a larger fraction of the stage delay.

### Practical Guidelines

- Use pipeline depth sufficient to meet the target clock frequency.
- Balance stages to within 10-15% of each other.
- Place pipeline registers at natural functional boundaries (decode, execute, writeback).
- For data paths without dependencies (e.g., signal processing), pipelines can be arbitrarily deep with minimal cost.
- For control-heavy logic (processors, protocol engines), keep pipelines shallow to minimize hazard costs.

## Register Retiming

Synthesis tools can automatically move pipeline registers to balance stage delays. This is called register retiming.

```tcl
# Enable retiming in Synopsys DC
set_register_type -flip_flop
optimize_registers -delay_threshold <target>
```

For retiming to work, registers must not have asynchronous resets (which pin them to a specific location), and the pipeline must not have feedback paths that prevent register movement. Design the pipeline with retiming in mind: use synchronous resets or no resets on pipeline registers, and keep pipeline stages in a flat hierarchy.

## Common Pipeline Design Patterns

### Skid Buffer

A two-entry buffer that decouples the valid-ready handshake, preventing ready from being combinationally derived from downstream.

### Pipeline Flush

A global or per-stage flush signal that invalidates all pipeline contents (used on branch misprediction, exception, or mode change).

### Pipeline Drain

Graceful shutdown where new entries are blocked but existing entries complete. Used before clock gating or power-down.

## Summary

Pipeline design is about balancing throughput, latency, area, and design complexity. Use the valid-ready protocol for flexible, composable pipelines. Handle data hazards with forwarding where possible and stalling where necessary. Keep pipeline depth appropriate for the target frequency and workload characteristics. Design with retiming in mind for synthesis optimization flexibility.
