# Clock Domain Crossing: Synchronization and Verification

## The CDC Problem

Modern SoCs contain multiple clock domains -- regions of logic driven by independent or loosely-related clocks. When a signal transitions from one clock domain to another, the receiving flip-flop may sample the signal during a transition, violating setup or hold time requirements. This results in **metastability**, where the flip-flop output enters an indeterminate state for an unpredictable duration before resolving to either 0 or 1.

Metastability cannot be eliminated, only managed. Clock domain crossing (CDC) design ensures that metastable events do not propagate into the design logic and corrupt data.

## Metastability Fundamentals

### What Happens During Metastability

When a flip-flop samples data during its setup/hold window:
1. The flip-flop output enters a voltage between VDD and VSS
2. The output remains in this intermediate state for a **resolution time** (Tres)
3. Eventually, positive feedback in the latch resolves to a valid logic level
4. The resolved value may or may not match the intended data value

### Mean Time Between Failures (MTBF)

MTBF quantifies the reliability of a synchronizer circuit:

```
MTBF = e^(Tres / tau) / (T0 * f_clk * f_data)
```

Where:
- **Tres** = available resolution time (clock period minus setup time)
- **tau** = metastability time constant of the flip-flop (technology-dependent, ~20-40ps for advanced nodes)
- **T0** = metastability capture window (technology-dependent)
- **f_clk** = receiving clock frequency
- **f_data** = rate of data transitions

A well-designed synchronizer achieves MTBF > 100 years for the target application.

### Resolution Time and Synchronizer Depth

Each additional synchronizer stage adds one clock period of resolution time. A 2-flop synchronizer provides (Tperiod - Tsetup) of resolution time. A 3-flop synchronizer provides (2 * Tperiod - Tsetup).

For most applications at frequencies up to 2GHz, a 2-flop synchronizer provides sufficient MTBF. At very high frequencies (>3GHz) or safety-critical applications (automotive, aerospace), 3-flop synchronizers may be required.

## Synchronizer Circuits

### Two-Flip-Flop Synchronizer

The simplest and most common CDC solution for single-bit signals.

```
Source Domain (clk_a):
  data -> FF_launch (clk_a)

Destination Domain (clk_b):
  FF_launch.Q -> FF_sync1 (clk_b) -> FF_sync2 (clk_b) -> synchronized_data
```

**Requirements:**
- FF_sync1 and FF_sync2 must be placed physically close together (short wire between them)
- No combinational logic between FF_sync1 and FF_sync2
- The data signal must be stable for at least one full destination clock period to ensure capture
- Both sync flops should use low-metastability-resolution cells if available in the library

### Pulse Synchronizer

For single-cycle pulse signals that may be shorter than the destination clock period:

```
Source Domain:          Destination Domain:
  pulse -> toggle_ff -> 2FF_sync -> edge_detector -> synced_pulse
```

The toggle flip-flop converts the pulse into a level change, which the 2FF synchronizer can safely capture. An edge detector in the destination domain converts back to a pulse.

### Reset Synchronizer

Asynchronous reset de-assertion must be synchronized to the destination clock:

```
VDD -> FF_sync1 (clk, async_reset) -> FF_sync2 (clk, async_reset) -> synced_reset
```

Reset assertion is asynchronous (immediate), but de-assertion is synchronous (aligned to clock edge). This ensures all flip-flops in the domain see reset de-assertion on the same clock edge.

## Multi-Bit CDC Techniques

### FIFO-Based Crossing

For multi-bit data buses, individual bit synchronization is insufficient because different bits may resolve at different clock edges, creating transient invalid values (data incoherency). A FIFO solves this:

**Architecture:**
- Dual-port RAM or register file for data storage
- Write pointer in source domain, read pointer in destination domain
- Gray-coded pointers synchronized across domains

**Gray Code Requirement:**
Gray code ensures that only one bit changes per pointer increment, making pointer synchronization safe with a 2FF synchronizer. Binary pointers would require multi-bit synchronization and risk data incoherency.

```
Write Domain (clk_a):
  write_data -> FIFO_RAM[wr_ptr]
  wr_ptr (gray) -> 2FF_sync -> wr_ptr_synced (in read domain)

Read Domain (clk_b):
  FIFO_RAM[rd_ptr] -> read_data
  rd_ptr (gray) -> 2FF_sync -> rd_ptr_synced (in write domain)

Full/Empty:
  full  = (wr_ptr_synced == rd_ptr with MSBs inverted)
  empty = (rd_ptr_synced == wr_ptr)
```

**FIFO Depth Calculation:**
The FIFO must be deep enough to absorb the latency of pointer synchronization (2-3 destination clock cycles) plus any burst data that accumulates during this latency.

### Handshake Protocol

For infrequent multi-bit transfers where FIFO overhead is not justified:

```
Source Domain:                    Destination Domain:
1. Assert req, present data  ->  2FF_sync(req) -> capture data
2.                           <-  2FF_sync(ack) -> assert ack
3. Deassert req              ->  2FF_sync(req) -> deassert ack
4.                           <-  2FF_sync(ack) -> ready for next
```

**Throughput:** Limited by the round-trip synchronization latency (4-6 clock cycles per transfer). Suitable for configuration registers, control signals, and low-bandwidth data.

### MUX-Based Recirculation

For multi-bit data with an associated valid/enable signal:

```
Source Domain:
  data_bus -> (held stable)
  valid -> 2FF_sync -> synced_valid (in dest domain)

Destination Domain:
  synced_valid -> MUX: if valid, capture data_bus into dest register
```

The data bus must be stable for the entire synchronization latency of the valid signal. This requires the source to hold data stable for at least 2 destination clock cycles after asserting valid.

## CDC Verification

### Structural CDC Verification

Tools like Synopsys CDC Compiler, Cadence Conformal CDC, and Mentor Questa CDC perform structural analysis:

1. **Identify all CDC paths** by tracing signals across clock domain boundaries
2. **Check for proper synchronization structures** (2FF sync, FIFO, handshake)
3. **Flag unsynchronized crossings** as errors
4. **Flag reconvergent CDC paths** where multiple bits from the same source domain reconverge in the destination domain without proper multi-bit synchronization

### Common CDC Violations

- **No synchronizer:** Direct connection from source domain FF to destination domain logic
- **Combinational logic in synchronizer:** Logic gates between the first and second sync flops
- **Multi-bit CDC without FIFO/handshake:** Multiple bits synchronized independently (data incoherency risk)
- **Gray code violation:** Non-Gray-coded multi-bit signal crossing domains
- **Reconvergent fanout:** Signal fans out, crosses domain on separate paths, and reconverges

### Metastability Injection Simulation

Functional CDC verification complements structural checks:

1. Insert random delays on CDC signals to model metastability resolution
2. Run functional simulation with injected metastability
3. Verify that the design handles all possible resolution outcomes correctly

## CDC Timing Constraints

### False Paths

CDC paths through synchronizers are typically constrained as false paths for STA because the timing relationship between source and destination clocks is not deterministic:

```tcl
# False path across asynchronous clock domains
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
set_false_path -from [get_clocks clk_b] -to [get_clocks clk_a]
```

### Max Delay on CDC Data

For multi-bit CDC with MUX recirculation, constrain the data path to ensure it arrives within the stable window:

```tcl
set_max_delay 2.0 -datapath_only \
  -from [get_pins source_reg/Q] -to [get_pins dest_mux/D0]
```

### Synchronizer Placement Constraints

Ensure sync flops are placed close together to minimize wire delay between them:

```tcl
# In Innovus
createInstGroup sync_group -region {100 100 110 110}
addInstToInstGroup sync_group {sync_ff1 sync_ff2}
```

## Practical Recommendations

1. **Use library-provided synchronizer cells** when available. They are characterized for metastability resolution and may have optimized layouts.

2. **Never put logic between synchronizer flops.** The first sync flop must feed the second directly. Any combinational logic increases the chance of metastability propagation.

3. **Always use Gray coding for FIFO pointers.** Binary-to-Gray and Gray-to-binary converters are simple and eliminate multi-bit CDC hazards.

4. **Run CDC verification early and often.** CDC bugs found in silicon are extremely difficult to debug. Catch them at RTL.

5. **Constrain synchronizer placement.** Physical distance between sync flops adds wire delay that reduces the resolution time. Place them within 50um of each other.

6. **Document every CDC crossing.** Maintain a spreadsheet listing each crossing, its synchronization method, the expected data rate, and the calculated MTBF.

7. **Do not use set_false_path blindly.** Every false path on a CDC must have a corresponding synchronization structure. False-pathing an unsynchronized crossing hides a real bug.

8. **Test CDC in silicon validation.** CDC bugs are timing-dependent and may not appear in simulation. Use clock frequency sweeps and voltage margining during silicon validation to stress CDC paths.

CDC design is one of the most error-prone aspects of digital design. Rigorous structural verification combined with proper synchronization circuits and careful physical implementation is essential for reliable multi-clock-domain SoCs.
