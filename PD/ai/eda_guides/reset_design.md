# Reset Design

## Overview

Reset is one of the most fundamental and most frequently mishandled aspects of digital design. A correct reset strategy ensures that the chip starts in a known state at power-up, recovers gracefully from error conditions, and transitions cleanly between operating modes. Reset errors cause non-deterministic behavior that is extraordinarily difficult to debug in silicon. This guide covers synchronous vs asynchronous reset, reset trees, reset synchronizers, and the critical concept of reset deassertion.

## Reset Types

### Synchronous Reset

A synchronous reset is sampled by the clock edge like any other data input. The flip-flop resets only when the reset is active at the clock edge.

```systemverilog
always_ff @(posedge clk) begin
  if (!rst_n)
    q <= '0;
  else
    q <= d;
end
```

**Advantages:**
- Reset is part of the data path, so standard STA covers it.
- No special flip-flop cell required (standard DFF with muxed reset).
- Filters glitches on the reset signal (glitches shorter than a clock period are ignored).
- Easier to meet timing (reset is just another data input).

**Disadvantages:**
- Requires a running clock to reset. If the clock is gated or not yet stable at power-up, the design will not reset.
- Adds a mux to the data path, potentially impacting timing.
- Reset removal timing must still be met relative to the clock edge.

### Asynchronous Reset

An asynchronous reset acts immediately when asserted, regardless of the clock. It appears in the sensitivity list of the always block.

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    q <= '0;
  else
    q <= d;
end
```

**Advantages:**
- Resets immediately, even without a clock. Essential for power-on reset.
- Does not add mux delay to the data path (reset uses the flip-flop's built-in async reset pin).
- Guarantees a known state even if the clock is not running.

**Disadvantages:**
- Susceptible to glitches: a noise pulse on the reset line can inadvertently reset the design.
- Reset deassertion must be synchronous to the clock; otherwise, metastability and recovery timing violations occur.
- More complex timing analysis (recovery and removal checks).

### Industry Practice: Asynchronous Assert, Synchronous Deassert

The dominant approach in ASIC design combines the benefits of both:

1. **Assert asynchronously**: The reset takes effect immediately, ensuring a known state even without a clock.
2. **Deassert synchronously**: The reset is released in alignment with the clock edge, preventing metastability.

This requires a reset synchronizer at each clock domain.

## Reset Synchronizer

The reset synchronizer is a critical cell that converts an asynchronous reset deassertion into a synchronous event.

```systemverilog
module reset_sync (
  input  logic clk,
  input  logic rst_async_n,
  output logic rst_sync_n
);

  logic ff1, ff2;

  always_ff @(posedge clk or negedge rst_async_n) begin
    if (!rst_async_n) begin
      ff1 <= 1'b0;
      ff2 <= 1'b0;
    end else begin
      ff1 <= 1'b1;
      ff2 <= ff1;
    end
  end

  assign rst_sync_n = ff2;

endmodule
```

### How It Works

**Assertion (rst_async_n goes low):**
- Both flip-flops reset immediately to 0 (asynchronous reset pin).
- `rst_sync_n` goes low immediately.
- The design is reset without waiting for a clock edge.

**Deassertion (rst_async_n goes high):**
- On the next clock edge, `ff1` samples the high input (1'b1).
- On the following clock edge, `ff2` samples `ff1`, driving `rst_sync_n` high.
- The deassertion is aligned to the clock edge, preventing metastability.

### Design Rules

1. Place one reset synchronizer per clock domain.
2. The synchronizer output (`rst_sync_n`) drives all flip-flops in that clock domain.
3. Add `dont_touch` to the synchronizer flip-flops to prevent optimization.
4. Constrain the synchronizer with appropriate `set_max_delay` or use a dedicated reset synchronizer library cell.

## Reset Tree

The reset synchronizer output must reach every flip-flop in the clock domain with acceptable skew. The reset tree is the distribution network for the synchronized reset signal.

### Reset Tree Structure

```
rst_async_n -> [Reset Sync] -> rst_sync_n -> [Buffer Tree] -> to all flip-flops
                                                |
                                           (balanced buffer chain
                                            like a clock tree but
                                            for reset)
```

### Skew Requirements

Reset skew must be controlled to ensure that all flip-flops in a domain release from reset at the same clock edge. If some flip-flops see reset deassert one cycle earlier than others, the early-released flip-flops will begin computing with incorrect inputs from still-reset flip-flops.

```
Max reset skew < Clock period - Setup time - Recovery time
```

In practice, synthesis and physical design tools build reset trees automatically when the reset net has high fanout. Use `set_ideal_network` or `set_dont_touch_network` during synthesis to prevent reset buffer insertion, then let the clock tree synthesis (CTS) tool or a dedicated reset tree step handle distribution.

## Reset Polarity

### Active-Low Reset (rst_n)

The dominant convention in ASIC design. Active-low resets match the native behavior of library flip-flop cells (which typically have active-low async preset/clear pins). Using active-low avoids inverter insertion.

### Active-High Reset (rst)

Sometimes used in FPGA design or specific IP blocks. Requires an inverter before library cells with active-low reset pins.

### Consistency

Use one polarity consistently throughout the design. Mixing polarities causes confusion and connection errors.

## Reset Domain Crossing

When a reset originates in one clock domain and must reset logic in another domain, the reset signal must be synchronized to the destination clock domain. This is exactly what the reset synchronizer handles.

### Multiple Clock Domains

```
                          +-> [Reset Sync (clk_a)] -> rst_a_n -> Domain A
rst_por_n (power-on) ----+-> [Reset Sync (clk_b)] -> rst_b_n -> Domain B
                          +-> [Reset Sync (clk_c)] -> rst_c_n -> Domain C
```

Each domain has its own reset synchronizer. The asynchronous assertion reaches all domains simultaneously, but the synchronous deassertion is aligned to each domain's clock independently.

### Reset Ordering

Some designs require that certain domains reset before others (e.g., the interconnect must reset before the processors). Reset ordering is achieved by chaining reset synchronizers:

```
rst_por_n -> [Reset Sync (clk_xbar)] -> rst_xbar_n
                                           |
                                    [Delay/Qualifier]
                                           |
                                    -> [Reset Sync (clk_cpu)] -> rst_cpu_n
```

## Reset Values

### What to Reset

Not every flip-flop needs an explicit reset. Reset adds area (mux for synchronous reset, or async reset pin usage) and routing (reset tree). The guidelines are:

**Must reset:**
- FSM state registers (to ensure starting state).
- Control registers (enables, valid signals, ready signals).
- Counters and pointers.
- Registers whose initial value affects functional correctness.

**May not need reset:**
- Data path registers (they will be overwritten before first use).
- Pipeline stage data (valid bits are reset, data does not need to be).
- Memory contents (BIST or software initializes).

### Reset Value Choice

Reset to zero (`'0`) whenever possible. Non-zero reset values require additional logic (inverter on the reset path or a set flip-flop instead of a clear flip-flop). Most library cells have only an async clear (reset to 0), not async preset (reset to 1).

```systemverilog
// Easy: reset to zero
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) state <= IDLE;  // IDLE should be encoded as 0
  else        state <= next_state;
end

// Harder: reset to non-zero requires set flip-flop or init logic
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) config_reg <= 32'hDEAD_BEEF;  // synthesis uses preset cells or mux
  else if (wr_en) config_reg <= wr_data;
end
```

## Power-On Reset (POR)

The POR circuit generates the initial reset pulse at power-up. It is typically an analog circuit that monitors the supply voltage and asserts reset until the voltage is stable.

### POR Requirements

1. Assert reset before the clock starts toggling.
2. Hold reset long enough for all PLLs to lock and clocks to stabilize.
3. Release reset cleanly (monotonic, no glitches).
4. Feed into reset synchronizers for each clock domain.

### Brown-Out Reset

A brown-out detector monitors the supply voltage during operation and asserts reset if the voltage drops below a safe threshold. This prevents operation with corrupted state.

## Warm Reset vs Cold Reset

- **Cold reset (POR)**: Full chip reset at power-up. All state is initialized.
- **Warm reset**: Partial reset during operation (e.g., software-triggered). May preserve certain configuration state while resetting the data path.

```systemverilog
always_ff @(posedge clk or negedge por_n) begin
  if (!por_n) begin
    config_reg <= DEFAULT_CONFIG;  // cold reset: full init
    status_reg <= '0;
  end else if (!warm_rst_n) begin
    status_reg <= '0;              // warm reset: clear status only
  end else begin
    // normal operation
  end
end
```

## Verification of Reset

1. **Reset assertion**: Verify all registers reach their reset values when reset is asserted.
2. **Reset deassertion**: Verify no metastability, no glitches, no race conditions on deassertion.
3. **Reset during operation**: Apply reset mid-operation and verify clean recovery.
4. **Reset ordering**: If domain ordering is required, verify the sequence.
5. **Formal verification**: Prove that all registers have defined values after reset using formal tools.

```systemverilog
property p_reset_state;
  @(posedge clk) !rst_n |=> (state == IDLE && count == '0 && valid == 1'b0);
endproperty
assert property (p_reset_state);
```

## Summary

Use asynchronous assert, synchronous deassert as the default reset strategy. Place a reset synchronizer in every clock domain. Control reset tree skew. Reset only the registers that need it (control logic, FSMs, counters). Reset to zero whenever possible. Verify reset behavior thoroughly, including mid-operation reset scenarios and multi-domain ordering.
