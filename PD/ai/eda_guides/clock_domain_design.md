# Clock Domain Design

## Overview

Modern SoCs contain multiple clock domains operating at different frequencies, phases, or from independent sources. Signals crossing between clock domains face metastability, data loss, and data corruption if not handled correctly. Clock domain crossing (CDC) design is one of the most error-prone aspects of digital design, and CDC bugs are notoriously difficult to find in simulation because they depend on clock phase relationships that vary in silicon. This guide covers the fundamental techniques for safe CDC design.

## Metastability

When a flip-flop samples a signal that changes within its setup/hold window, the output can enter a metastable state, an indeterminate voltage between 0 and 1 that can persist for an unpredictable duration before resolving to either 0 or 1. The resolution time is probabilistic; the longer you wait, the more likely the signal has resolved.

The Mean Time Between Failures (MTBF) for a single flip-flop is:

```
MTBF = e^(tr / tau) / (T0 * f_clk * f_data)
```

Where `tr` is the resolution time (one clock period for a synchronizer stage), `tau` is a technology constant, `f_clk` is the sampling clock frequency, and `f_data` is the data transition frequency. Adding synchronizer stages exponentially increases MTBF.

## Two-Flip-Flop Synchronizer

The simplest and most common CDC solution for single-bit signals.

```systemverilog
module sync_2ff #(
  parameter RESET_VAL = 1'b0
)(
  input  logic clk_dest,
  input  logic rst_dest_n,
  input  logic data_in,    // from source domain
  output logic data_out    // synchronized to dest domain
);

  logic meta_ff, sync_ff;

  always_ff @(posedge clk_dest or negedge rst_dest_n) begin
    if (!rst_dest_n) begin
      meta_ff <= RESET_VAL;
      sync_ff <= RESET_VAL;
    end else begin
      meta_ff <= data_in;   // first stage: may go metastable
      sync_ff <= meta_ff;   // second stage: resolved with high probability
    end
  end

  assign data_out = sync_ff;

endmodule
```

### Design Rules for Two-FF Synchronizer

1. Both flip-flops must be in the destination clock domain.
2. The flip-flops should be placed physically close together (use `dont_touch` and placement constraints).
3. No combinational logic between the two stages.
4. The input signal must be stable for at least one full destination clock period (to guarantee capture).
5. Only valid for single-bit, level-type signals (not pulses shorter than the destination clock period).

### Three-FF Synchronizer

For very high clock frequencies or high-reliability designs, a third synchronizer stage further reduces MTBF. The area cost is minimal.

## Multi-Bit Signal Crossing

A two-FF synchronizer handles only single-bit signals. Multi-bit buses require different strategies because individual bits may be captured in different clock cycles, creating transient invalid values.

### Gray Code Encoding

For monotonically incrementing counters (like FIFO pointers), converting to Gray code ensures that only one bit changes per increment. A two-FF synchronizer on each Gray-coded bit is safe because the worst case is reading the old or new value, never a corrupted intermediate.

```systemverilog
function automatic logic [N-1:0] bin2gray(input logic [N-1:0] bin);
  return bin ^ (bin >> 1);
endfunction

function automatic logic [N-1:0] gray2bin(input logic [N-1:0] gray);
  logic [N-1:0] bin;
  bin[N-1] = gray[N-1];
  for (int i = N-2; i >= 0; i--)
    bin[i] = bin[i+1] ^ gray[i];
  return bin;
endfunction
```

### MUX Synchronizer (Qualifier-Based)

For multi-bit data buses, use a qualifying signal to indicate when the data is valid and stable.

```systemverilog
// Source domain: hold data stable, pulse valid
always_ff @(posedge clk_src) begin
  if (send) begin
    data_hold <= data;
    valid_src <= 1'b1;
  end else if (ack_synced) begin
    valid_src <= 1'b0;
  end
end

// Destination domain: synchronize valid, then sample data
sync_2ff u_sync_valid (.clk_dest(clk_dest), .data_in(valid_src), .data_out(valid_dest));

always_ff @(posedge clk_dest) begin
  if (valid_dest && !valid_dest_d1) begin  // rising edge of synced valid
    data_captured <= data_hold;             // data is stable, safe to sample
  end
end
```

The key principle is that the multi-bit data bus is held stable while the single-bit qualifier is synchronized. The data bus itself does not need synchronizers.

## Asynchronous FIFO

The asynchronous FIFO is the workhorse of high-throughput CDC. It uses dual-port RAM with independent write and read clocks, and Gray-coded pointers synchronized between domains.

### Architecture

1. Write pointer (binary) incremented in write clock domain.
2. Read pointer (binary) incremented in read clock domain.
3. Write pointer converted to Gray code and synchronized to read domain for full detection.
4. Read pointer converted to Gray code and synchronized to write domain for empty detection.
5. Full condition: Gray-coded write pointer (in read domain) matches read pointer with the two MSBs inverted.
6. Empty condition: Gray-coded read pointer (in write domain) matches write pointer exactly.

### FIFO Depth Calculation

The minimum FIFO depth depends on the clock frequency ratio and burst characteristics:

```
Depth >= (Burst_Length * f_write) / (f_write - f_read)  [when f_write > f_read]
```

For bursty traffic, add margin for worst-case back-to-back bursts. In practice, round up to the next power of two (required for Gray code pointers).

## Handshake Protocols

For infrequent, low-bandwidth transfers, a handshake protocol is simpler than a FIFO.

### Four-Phase Handshake

```
Source domain:              Destination domain:
1. Assert REQ, hold DATA  ->
                           2. Sync REQ, capture DATA, assert ACK
3. Sync ACK, deassert REQ <-
                           4. Sync ~REQ, deassert ACK
```

Each signal transition is synchronized by a two-FF synchronizer. The protocol requires four synchronization delays per transfer, limiting throughput. It is suitable for configuration registers, control signals, and low-rate data.

### Two-Phase Handshake (Toggle Protocol)

Uses signal transitions (toggles) instead of levels. Each toggle on REQ indicates a new transfer; each toggle on ACK indicates completion. More efficient than four-phase but slightly more complex.

## Reset Synchronization

Reset signals often cross clock domains (e.g., a global reset generated in one domain must reset logic in another). Asynchronous assert, synchronous deassert is the standard pattern.

```systemverilog
module reset_sync (
  input  logic clk,
  input  logic rst_async_n,   // asynchronous, may come from another domain
  output logic rst_sync_n     // synchronized to clk
);

  logic rst_meta, rst_sync;

  always_ff @(posedge clk or negedge rst_async_n) begin
    if (!rst_async_n) begin
      rst_meta <= 1'b0;
      rst_sync <= 1'b0;
    end else begin
      rst_meta <= 1'b1;
      rst_sync <= rst_meta;
    end
  end

  assign rst_sync_n = rst_sync;

endmodule
```

Reset assertion is asynchronous (immediate). Reset deassertion is synchronous (aligned to the clock edge), preventing metastability on the recovery edge.

## CDC Verification

### Static CDC Analysis

Tools like Synopsys SpyGlass CDC, Cadence Conformal CDC, and Mentor Questa CDC perform structural analysis to find:

- Unsynchronized crossings
- Multi-bit signals crossed without a synchronization scheme
- Reconvergence (same source signal crossed on multiple paths that recombine)
- Glitch-prone crossings

Static CDC analysis is essential and should be run early and often.

### CDC-Aware Simulation

Standard RTL simulation uses ideal clocks with fixed relationships, which cannot expose CDC bugs. CDC-aware simulation tools inject random clock jitter and phase shifts to expose timing-dependent failures. Combine with assertions on synchronizer outputs.

### Formal CDC Verification

Formal methods can prove that CDC protocols are correct under all possible clock relationships. This is especially valuable for custom handshake protocols and complex FIFO designs.

## Best Practices

1. Document every clock domain crossing in the design specification.
2. Use proven, parameterized synchronizer modules from a validated library.
3. Use async FIFOs for high-throughput data crossings.
4. Use handshake protocols for low-rate control crossings.
5. Never synchronize multi-bit buses without a qualifying signal or Gray encoding.
6. Run static CDC analysis before tape-out; treat CDC violations as must-fix.
7. Synchronize reset deassertion in every clock domain.
8. Constrain synchronizer flip-flops with `set_max_delay` or `set_false_path` appropriately.
9. Place synchronizer flip-flops close together physically.
10. Add assertions at every CDC boundary for simulation coverage.
