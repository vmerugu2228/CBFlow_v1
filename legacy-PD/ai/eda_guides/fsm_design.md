# FSM Design

## Overview

Finite State Machines (FSMs) are the control backbone of nearly every digital design, from simple protocol handlers to complex processor control units. A well-designed FSM is readable, synthesizable, verifiable, and area/timing-efficient. Poor FSM design, by contrast, is a leading source of functional bugs, unreachable states, and timing failures. This guide covers the theory and practical coding of production-quality FSMs.

## FSM Classification

### Moore Machines

In a Moore machine, outputs depend only on the current state, not on inputs. Outputs change synchronously with state transitions (one clock cycle after the input changes).

```
Output = f(State)
```

Moore machines are preferred in most ASIC designs because their outputs are registered (or can be easily registered), producing glitch-free signals and simpler timing analysis.

### Mealy Machines

In a Mealy machine, outputs depend on both the current state and current inputs. Outputs can change asynchronously with input changes within a clock cycle.

```
Output = f(State, Inputs)
```

Mealy machines can respond one cycle faster than Moore machines (outputs react in the same cycle as the input), but their outputs may glitch if inputs change mid-cycle. When Mealy outputs drive other logic, they create longer combinational paths.

### Practical Choice

Use Moore machines as the default. Use Mealy machines only when the one-cycle latency savings is critical and the output is either registered before use or drives only local logic.

## FSM Coding Styles

### Two-Block Style (Recommended)

Separate the design into a sequential block (state register) and a combinational block (next-state and output logic).

```systemverilog
typedef enum logic [2:0] {
  IDLE  = 3'b000,
  START = 3'b001,
  DATA  = 3'b010,
  PARITY= 3'b011,
  STOP  = 3'b100
} uart_state_t;

uart_state_t curr_state, next_state;

// Sequential block: state register
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    curr_state <= IDLE;
  else
    curr_state <= next_state;
end

// Combinational block: next state + outputs
always_comb begin
  // Defaults (prevent latches)
  next_state = curr_state;
  tx_busy    = 1'b0;
  tx_out     = 1'b1;

  case (curr_state)
    IDLE: begin
      if (tx_start) begin
        next_state = START;
      end
    end

    START: begin
      tx_busy = 1'b1;
      tx_out  = 1'b0;   // start bit
      if (bit_tick)
        next_state = DATA;
    end

    DATA: begin
      tx_busy = 1'b1;
      tx_out  = tx_data[bit_idx];
      if (bit_tick && bit_idx == 3'd7)
        next_state = PARITY;
    end

    PARITY: begin
      tx_busy = 1'b1;
      tx_out  = parity_bit;
      if (bit_tick)
        next_state = STOP;
    end

    STOP: begin
      tx_busy = 1'b1;
      tx_out  = 1'b1;   // stop bit
      if (bit_tick)
        next_state = IDLE;
    end

    default: next_state = IDLE;
  endcase
end
```

### Three-Block Style

Adds a third sequential block to register outputs, eliminating glitches on Moore outputs.

```systemverilog
// Block 3: registered outputs
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    tx_busy_r <= 1'b0;
    tx_out_r  <= 1'b1;
  end else begin
    tx_busy_r <= tx_busy_next;
    tx_out_r  <= tx_out_next;
  end
end
```

The three-block style adds one cycle of output latency but guarantees glitch-free, timing-clean outputs. It is recommended for outputs that cross module boundaries or drive I/O pads.

### One-Block Style (Discouraged)

Combines everything into a single sequential block. While compact, it is harder to read, harder to lint, and harder to modify.

## State Encoding

### Binary Encoding

States are assigned sequential binary values. Uses `ceil(log2(N))` flip-flops for N states.

- **Pros**: Minimum flip-flop count, minimum state register area.
- **Cons**: More combinational logic for decoding, higher switching activity.
- **Use when**: Area is critical and the FSM has many states.

### Gray Code Encoding

Adjacent states differ by only one bit. Uses `ceil(log2(N))` flip-flops.

- **Pros**: Minimum transitions between sequential states, lower power.
- **Cons**: Only beneficial when states are traversed sequentially.
- **Use when**: The FSM traverses states in a linear sequence and power is a concern.

### One-Hot Encoding

Each state uses one flip-flop; only one flip-flop is active at a time. Uses N flip-flops for N states.

- **Pros**: Simple, fast next-state logic (single-gate decode), no decoding delay.
- **Cons**: More flip-flops, impractical for FSMs with many states.
- **Use when**: Speed is critical and the FSM has fewer than ~16 states (the most common choice for ASIC synthesis).

### One-Cold, Johnson, Custom Encoding

Less common but occasionally used for specific optimization goals. Custom encoding allows manual optimization for a particular state transition graph.

### Letting Synthesis Choose

Most synthesis tools default to an encoding based on the number of states and optimization goals. You can control this with:

```tcl
# Synopsys DC
set_fsm_encoding -encoding one_hot [get_designs uart_tx]
```

Using SystemVerilog `enum` with explicit encoding gives the designer full control:

```systemverilog
typedef enum logic [4:0] {
  IDLE    = 5'b00001,
  START   = 5'b00010,
  DATA    = 5'b00100,
  PARITY  = 5'b01000,
  STOP    = 5'b10000
} state_t;  // explicit one-hot
```

## Unreachable States

If the state register has more bit patterns than defined states, the FSM can enter an undefined (illegal) state due to SEU (single event upset), power-on, or bugs. The `default` branch of the case statement must handle this.

### Safe FSM Design

```systemverilog
default: next_state = IDLE;  // return to known state
```

For safety-critical designs, add explicit detection:

```systemverilog
always_comb begin
  fsm_error = 1'b0;
  case (curr_state)
    // ... normal states ...
    default: begin
      next_state = IDLE;
      fsm_error  = 1'b1;  // flag for error reporting
    end
  endcase
end
```

### One-Hot Safety

With one-hot encoding, N states use N flip-flops, but there are 2^N possible patterns. Adding a check for `$onehot(curr_state)` catches corruption:

```systemverilog
assert property (@(posedge clk) disable iff (!rst_n) $onehot(curr_state))
  else $error("FSM state is not one-hot: %b", curr_state);
```

## FSM Synthesis Optimization

### State Minimization

Synthesis tools can merge equivalent states. This is generally beneficial but can make debug harder (state names in simulation no longer match RTL). Control with `set_fsm_minimize`.

### Encoding Optimization

Tools re-encode states for area or speed. If you want to preserve your encoding, use `set_fsm_encoding -encoding none` or apply `dont_touch` to the state register.

### Retiming Through FSMs

Register retiming moves flip-flops across combinational logic to balance pipeline stages. Synthesis tools generally cannot retime through FSM state registers because it changes the FSM behavior. If retiming is needed, restructure the FSM to separate the timing-critical data path from the control FSM.

## Common FSM Bugs

1. **Missing default**: Leads to latches in combinational blocks or stuck states.
2. **Incomplete output assignment**: Some outputs not assigned in some states, causing latches.
3. **Deadlock**: States with no exit transition under any input condition.
4. **Livelock**: Cycle of states that never reaches a useful terminal condition.
5. **Race conditions**: Mealy outputs depending on inputs that arrive at different times.
6. **Reset state not reachable**: Other states cannot transition back to reset state.

## FSM Verification

### Assertion-Based

```systemverilog
// No two consecutive IDLE states (ensure progress)
property p_no_stuck_idle;
  @(posedge clk) disable iff (!rst_n)
  (curr_state == IDLE) |=> (curr_state != IDLE || !tx_start);
endproperty

// All states reachable (covered in simulation)
covergroup cg_fsm @(posedge clk);
  cp_state: coverpoint curr_state;
  cp_transition: cross curr_state, next_state;
endgroup
```

### Formal Verification

Formal tools can exhaustively prove that no illegal state is reachable, that the FSM always makes progress (liveness), and that every defined state is reachable from reset. Formal is especially valuable for complex FSMs where simulation cannot cover all paths.

## Summary

Design FSMs with a two-block or three-block style, use SystemVerilog enums with explicit encoding, always include a default case for illegal states, and verify with assertions and coverage. One-hot encoding is the default choice for ASICs with moderate state counts. Always verify that all states are reachable and that no deadlock conditions exist.
