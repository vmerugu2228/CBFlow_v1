# Clock Gating Design

## Overview

Clock gating is the most effective technique for reducing dynamic power in synchronous digital designs. The clock network typically accounts for 30-50% of total dynamic power because it switches every cycle and has the highest fanout. By stopping the clock to idle registers, clock gating eliminates both the clock tree switching power and the register toggling power for those registers. This guide covers ICG cell design, latch-based gating, enable generation strategies, and metrics for measuring clock gating effectiveness.

## Clock Gating Fundamentals

### Why Clock Gating Works

Without clock gating, every register toggles on every clock edge, consuming power regardless of whether the register value changes. With clock gating, idle registers see a static clock, consuming only leakage power.

```
Power savings = (1 - duty_cycle) * (P_clock_tree + P_register_switching)
```

Where `duty_cycle` is the fraction of cycles the register is active.

### Clock Gating vs Data Gating

An alternative to clock gating is data gating: holding the data input constant when the register should not update.

```systemverilog
// Data gating (no clock gating)
always_ff @(posedge clk) begin
  data_reg <= enable ? new_data : data_reg;  // mux holds old value
end
```

Data gating still toggles the clock (power wasted on clock tree and register clocking). Clock gating stops the clock entirely. For large register banks, clock gating saves significantly more power than data gating.

## ICG Cells (Integrated Clock Gating)

### Cell Structure

An ICG (Integrated Clock Gating) cell is a standard library cell that combines a latch and an AND gate to produce a glitch-free gated clock.

```
          +-------+
  EN  --->| Latch |---> Latched_EN
  CLK --->| (neg) |
          +-------+
              |
          +-------+
  CLK --->|  AND  |---> Gated_CLK
          +-------+
              ^
              |
          Latched_EN
```

### How It Works

1. The enable signal (`EN`) is latched on the negative edge of the clock (when CLK is low).
2. The latched enable is ANDed with the clock to produce the gated clock.
3. Because the latch captures `EN` while the clock is low, the latched enable is stable during the entire high phase of the clock, guaranteeing a glitch-free gated clock.

### Why Latch-Based Gating

Without the latch, the enable signal could change while the clock is high, creating a glitch on the gated clock. A glitch can cause:
- Spurious clock edge, clocking incorrect data into registers.
- Short clock pulse that violates minimum pulse width.
- Timing violation due to unexpected clock arrival.

The latch ensures the enable is sampled and held stable throughout the clock high phase.

### ICG Cell Variants

| Cell Name | Features |
|-----------|----------|
| `CKLNQD1` | Basic ICG: latch + AND, no test enable |
| `CKLHQD1` | ICG with test enable (TE) for scan bypass |
| `CKLNQD4` | Higher drive strength ICG for large fanout |

The test enable (TE) input bypasses the gating during scan test, ensuring the scan clock reaches all gated registers.

```
Gated_CLK = CLK & (Latched_EN | TE)
```

### ICG Cell in RTL

```systemverilog
// Technology-specific instantiation
CKLHQD1 u_icg (
  .CK (clk),
  .E  (func_enable),
  .TE (scan_enable),
  .Q  (gated_clk)
);
```

In most flows, ICG cells are inserted automatically by the synthesis tool. Manual instantiation is reserved for special cases.

## RTL Patterns for Clock Gating Inference

### Standard Inferable Pattern

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    data_reg <= '0;
  else if (load_en)
    data_reg <= data_in;
  // implicit else: hold value -> synthesis infers clock gating
end
```

The synthesis tool recognizes the conditional load pattern and replaces it with an ICG cell gating the clock to `data_reg`.

### Multi-Register Gating

When multiple registers share the same enable, synthesis groups them under a single ICG cell.

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    addr_reg <= '0;
    data_reg <= '0;
    ctrl_reg <= '0;
  end else if (wr_en) begin
    addr_reg <= addr_in;
    data_reg <= data_in;
    ctrl_reg <= ctrl_in;
  end
end
// One ICG cell gates all three registers
```

### Patterns That Block Inference

```systemverilog
// BAD: mux instead of enable -> no gating opportunity
always_ff @(posedge clk) begin
  data_reg <= sel ? data_a : data_b;  // always loads
end

// BAD: mixed enables -> separate ICGs or no gating
always_ff @(posedge clk) begin
  if (en_a) reg_a <= data_a;
  if (en_b) reg_b <= data_b;
  if (en_c) reg_c <= data_c;
end
// Three separate ICG cells needed (or tool may not gate at all)

// BAD: always loads unconditionally
always_ff @(posedge clk) begin
  pipe_s1 <= data_in;  // no enable -> no gating
end
```

## Enable Generation Strategies

### Activity-Based Enable

Generate the enable based on whether the data is changing or the module is active.

```systemverilog
// Enable when new data arrives
wire fifo_wr_en = valid_in && ready_out;

// Enable for configuration registers (rare writes)
wire cfg_wr_en = apb_psel && apb_penable && apb_pwrite;
```

### Idle Detection

For complex modules, detect idle conditions and gate the entire module's clock.

```systemverilog
// Module-level clock gating based on idle state
wire module_active = (state != IDLE) || start_req;
wire module_clk;

CKLHQD1 u_module_icg (
  .CK(clk), .E(module_active), .TE(scan_en), .Q(module_clk)
);

// All logic within the module uses module_clk
```

### Hierarchical Clock Gating

Large designs use multiple levels of clock gating:

```
System Clock
  |
  +-> [ICG: subsystem enable] -> Subsystem Clock
       |
       +-> [ICG: module enable] -> Module Clock
            |
            +-> [ICG: register enable] -> Register Clock
```

Each level provides coarser-grained gating. The subsystem ICG gates the entire subsystem when idle. The module ICG gates individual modules. The register ICG gates individual register groups.

## Synthesis Configuration

### Synopsys Design Compiler

```tcl
# Enable clock gating insertion
set_clock_gating_style -sequential_cell latch \
  -positive_edge_logic {integrated} \
  -negative_edge_logic {integrated} \
  -minimum_bitwidth 4 \
  -max_fanout 64

# Insert clock gating
insert_clock_gating

# Report clock gating
report_clock_gating
```

Key parameters:
- **minimum_bitwidth**: Minimum number of registers to justify an ICG cell (typically 4-8). Gating a single flip-flop wastes area.
- **max_fanout**: Maximum registers per ICG cell. Large fanout requires higher-drive ICG cells.
- **sequential_cell latch**: Use latch-based ICG cells (standard practice).

### Cadence Genus

```tcl
set_db design:top .lp_insert_clock_gating true
set_db design:top .lp_clock_gating_min_flops 4
set_db design:top .lp_clock_gating_max_flops 64
```

## Clock Gating Efficiency Metrics

### Gating Percentage

```
Gating % = (Number of gated registers / Total registers) * 100
```

Target: 80-95% gating percentage. Ungated registers include always-active pipeline stages, clock dividers, and debug counters.

### Enable Duty Cycle

The fraction of cycles the enable is active:

```
Duty Cycle = (Cycles with enable active) / (Total cycles)
```

Low duty cycle means more power savings. A gated clock with 90% duty cycle saves only 10%.

### Reporting

```tcl
# DC report
report_clock_gating -summary
report_clock_gating -detail -gating_elements

# Expected output:
# Clock Gating Summary:
#   Total registers:        15000
#   Gated registers:        13500  (90.0%)
#   Ungated registers:       1500  (10.0%)
#   ICG cells inserted:       425
#   Avg fanout per ICG:       31.8
```

## Clock Gating Verification

### Functional Verification

Clock gating must not change functional behavior. The gated design must produce identical results to the ungated design.

```systemverilog
// Assertion: gated register holds value when enable is low
property p_hold_when_gated;
  @(posedge clk) disable iff (!rst_n)
  !load_en |=> $stable(data_reg);
endproperty
assert property (p_hold_when_gated);
```

### Formal Equivalence

Run formal equivalence checking between the pre-gating and post-gating netlists to prove functional equivalence.

### Power Verification

Verify clock gating effectiveness with power analysis:

```tcl
# PrimeTime PX
read_saif -input sim.saif   ;# switching activity from simulation
report_power -cell_power     ;# power per cell
report_clock_gating          ;# gating statistics
```

## Common Clock Gating Issues

1. **Over-gating**: Gating too aggressively causes functional failures (registers not updating when they should).
2. **Under-gating**: Not enough gating leaves power savings on the table.
3. **Glitches on enable**: If the enable signal glitches, the ICG latch may capture the wrong value. Keep enable logic clean and glitch-free.
4. **Hold violations after ICG**: The ICG cell adds delay to the clock path, which can cause hold violations on the gated registers. CTS must balance the gated clock path.
5. **Test mode bypass**: Forgetting to connect the test enable (TE) input blocks scan shifting through gated registers.
6. **Mixed clock edges**: Gating a negative-edge clock requires a different ICG cell variant (positive-edge latch).

## Summary

Clock gating is essential for power-efficient design. Write enable-based register patterns for automatic inference. Group registers by enable for efficient gating. Use hierarchical gating for coarse-grained idle shutdown. Configure synthesis tools with appropriate minimum bitwidth and maximum fanout. Target 80-95% gating percentage and verify that gating does not change functionality.
