# Digital Logic Fundamentals

## Overview

Every physical design begins with digital logic. PD engineers do not typically write RTL, but they must understand the logic structures they are implementing: how combinational and sequential circuits work, how timing elements behave, how finite state machines are structured, and how datapath architectures and pipelining affect physical implementation. This understanding is essential for interpreting timing reports, diagnosing synthesis results, and making intelligent floorplanning decisions.

## Combinational Logic

Combinational circuits produce outputs that are purely a function of their current inputs, with no memory of past states.

### Basic Gates

The fundamental building blocks:

- **AND, OR, NOT**: Boolean primitives
- **NAND, NOR**: Universal gates (any Boolean function can be built from NAND or NOR alone); NAND is preferred in CMOS due to better drive strength per unit area
- **XOR, XNOR**: Parity and comparison functions
- **MUX (multiplexer)**: Selects one of N inputs based on select signals; the workhorse of datapath design
- **Decoder/encoder**: Converts between binary and one-hot representations

### Combinational Path Depth

The number of logic levels between a register output and the next register input determines the combinational path depth. This directly limits the maximum clock frequency:

```
T_clk >= T_cq + T_comb + T_setup + T_skew + T_margin
```

Where T_comb is the delay through the combinational logic. Deeper combinational paths mean longer T_comb and lower maximum frequency.

### Synthesis Mapping

Synthesis tools map Boolean expressions to standard cells from the technology library. Key concepts:

- **Technology mapping**: Selecting the best library cells to implement each logic function
- **Cell sizing**: Choosing between small (low power, slow) and large (high power, fast) variants of the same cell
- **Logic restructuring**: Reorganizing the Boolean network to reduce depth or area
- **Constant propagation**: Simplifying logic where inputs are tied to fixed values

### Physical Implications

- Wide multiplexers (32:1, 64:1) create deep logic and are difficult to close timing on
- Arithmetic operations (adders, multipliers) have well-known critical path structures that synthesis tools exploit
- Fan-out of a net affects delay: high fan-out nets require buffering
- Reconvergent paths can create glitches that increase dynamic power

## Sequential Logic

Sequential circuits have memory: their outputs depend on both current inputs and stored state.

### Flip-Flops

The fundamental storage element in synchronous digital design.

- **D flip-flop**: Captures the D input on the active clock edge and holds it until the next active edge
- **Setup time (T_setup)**: The input must be stable for this duration before the clock edge
- **Hold time (T_hold)**: The input must remain stable for this duration after the clock edge
- **Clock-to-Q delay (T_cq)**: Time from the clock edge to the output becoming valid
- **Reset**: Synchronous (reset captured on clock edge) or asynchronous (immediate reset)

### Latches

Latches are level-sensitive rather than edge-sensitive. When the enable signal is active, the output follows the input; when inactive, the output holds.

- **Usage**: Time borrowing (a technique to improve timing by allowing signals to pass through latches when enabled)
- **Caution**: Latches make STA more complex and can cause timing convergence issues; most digital methodologies avoid latches unless specifically needed
- **Unintentional latches**: A common RTL coding error; incomplete if-else or case statements can infer latches during synthesis

### Registers

Registers are groups of flip-flops sharing a common clock. In practice, "flip-flop" and "register" are often used interchangeably, but technically a register is a multi-bit storage element.

### Physical Implications

- Flip-flop area and power dominate in register-heavy designs (CPUs, GPUs)
- Scan flip-flops (used for DFT) are 15-30% larger than regular flip-flops
- Clock-gated registers reduce power by disabling the clock when the register value does not change
- Multi-bit flip-flops (banking 2-4 flip-flops into a single cell) reduce area and clock power

## Timing Elements and Clocking

### Synchronous Design

The vast majority of digital circuits use synchronous design, where all state transitions are synchronized to a clock signal.

- **Clock distribution**: The clock must arrive at every flip-flop with minimal skew
- **Clock period**: Determines the maximum combinational delay between any two registers
- **Clock gating**: Disables the clock to idle registers, saving 30-50% of clock power

### Clock Domain Crossing (CDC)

When signals cross between clock domains, special synchronization is required:

- **Two-flop synchronizer**: For single-bit signals crossing between asynchronous domains
- **Gray code counter + synchronizer**: For multi-bit counters
- **Async FIFO**: For multi-bit data streams with different source and destination clocks
- **Handshake protocol**: For control signals requiring acknowledgment

CDC errors cause metastability, data corruption, and intermittent failures that are extremely difficult to debug in silicon. CDC verification tools (Spyglass CDC) are essential.

### Physical Implications

- Clock tree synthesis must balance skew across the entire clock distribution
- CDC logic requires careful placement to minimize metastability window
- Multiple clock domains complicate floorplanning (each domain tends to cluster physically)

## Finite State Machines (FSMs)

FSMs are the backbone of control logic in digital systems.

### Moore Machine

Output depends only on the current state.

```
State Register -> Next State Logic -> State Register
                -> Output Logic -> Outputs
```

### Mealy Machine

Output depends on both current state and current inputs.

```
State Register -> Next State Logic (+ Inputs) -> State Register
                -> Output Logic (+ Inputs) -> Outputs
```

### FSM Encoding

- **Binary encoding**: Minimum number of flip-flops; deeper next-state logic
- **One-hot encoding**: One flip-flop per state; simpler next-state logic; preferred in FPGA and often in ASIC
- **Gray encoding**: Only one bit changes per state transition; useful for CDC

### Physical Implications

- FSMs are typically small in area but can have long combinational paths in the next-state logic
- One-hot encoding uses more flip-flops but has shorter critical paths
- Complex FSMs with many states can create wide multiplexers in the next-state logic

## Datapath Architecture

Datapaths perform arithmetic and data manipulation operations. They are characterized by regular, repetitive structures.

### Common Datapath Elements

- **Adder**: Ripple carry (simple, slow), carry look-ahead (fast, more area), Kogge-Stone/Brent-Kung (parallel prefix, fast)
- **Multiplier**: Array multiplier, Booth-encoded multiplier, Wallace tree
- **Shifter**: Barrel shifter (single-cycle arbitrary shift), funnel shifter
- **Comparator**: Magnitude comparator, equality comparator
- **ALU**: Combines multiple arithmetic/logic operations with a select input

### Datapath vs. Control

A typical digital block has two parts:

- **Datapath**: Wide (32-bit, 64-bit, 128-bit), regular, dominated by arithmetic and data movement. Timing is often determined by the bit width
- **Control path**: Narrow (single-bit or few-bit), irregular, dominated by FSMs and decode logic. Timing is often determined by logic depth

Physical implementation treats these differently: datapaths benefit from regular placement (bit-sliced), while control logic requires timing-driven placement.

### Physical Implications

- Datapath structures have natural bit-slice regularity that placement tools can exploit
- Carry chains create critical paths that span the full bit width
- Wide buses create congestion; floorplanning must provide adequate routing channels
- Datapath timing often determines the achievable clock frequency

## Pipelining

Pipelining divides a long combinational path into shorter segments separated by pipeline registers.

### Basic Concept

Without pipelining:
```
Input -> [Long Combinational Logic (20ns)] -> Output
Maximum frequency: 1/20ns = 50 MHz
```

With 4-stage pipeline:
```
Input -> [Stage 1 (5ns)] -> Reg -> [Stage 2 (5ns)] -> Reg -> [Stage 3 (5ns)] -> Reg -> [Stage 4 (5ns)] -> Output
Maximum frequency: 1/5ns = 200 MHz
```

### Pipelining Tradeoffs

- **Throughput**: Improves with more pipeline stages (higher clock frequency)
- **Latency**: Increases with more stages (more cycles from input to output)
- **Area**: Increases due to pipeline registers
- **Power**: Increases due to additional register toggling and clock distribution

### Pipeline Hazards

- **Data hazard**: A stage needs data that a previous stage has not yet produced (solved by forwarding or stalling)
- **Control hazard**: Branch decisions are not known until deep in the pipeline (solved by prediction or flushing)
- **Structural hazard**: Two stages need the same resource simultaneously (solved by duplication or arbitration)

### Retiming

Retiming is an optimization technique that moves registers across combinational logic to balance pipeline stage delays. Synthesis tools can perform retiming automatically, but PD engineers should understand its implications:

- Retiming changes register names, complicating debug and verification
- Retiming across module boundaries requires special handling in the tool flow
- Retiming can expose new timing paths that were previously hidden

### Physical Implications

- Deeply pipelined designs have more flip-flops, increasing area and clock power
- Pipeline stages should be physically adjacent for efficient data flow
- Retiming decisions made during synthesis affect the physical structure and placement
- Pipeline balance (equal delay in each stage) is critical; an unbalanced pipeline wastes frequency
- Wide pipelines (128-bit datapath with 20+ stages) create large regular structures that benefit from structured placement

## Design Patterns for PD Engineers

Understanding these logic fundamentals helps PD engineers:

1. **Interpret timing reports**: Knowing that a 64-bit adder has a carry chain helps explain why certain paths are critical
2. **Guide floorplanning**: Placing blocks with heavy data exchange close together reduces wire delay
3. **Predict congestion**: Wide buses and high fan-out control signals are congestion sources
4. **Evaluate RTL changes**: When RTL engineers propose architectural changes, PD engineers can assess the physical impact
5. **Debug synthesis results**: Understanding latch inference, clock gating, and FSM encoding helps diagnose unexpected synthesis outputs
