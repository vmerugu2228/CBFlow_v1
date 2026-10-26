# CDC Verification Complete Guide

Comprehensive guide for Clock Domain Crossing (CDC) verification covering
structural analysis, protocol verification, reconvergence, Gray coding,
reset domain crossing, tool usage, waivers, and sign-off methodology.

---

## 1. CDC Fundamentals

### 1.1 What is CDC?

Clock Domain Crossing (CDC) occurs when a signal generated in one clock domain
is sampled by a register in a different clock domain. Without proper
synchronization, CDC can cause metastability, data corruption, and system
failures.

**Types of Clock Relationships:**

| Relationship | Description | CDC Risk |
|-------------|-------------|---------|
| Asynchronous | Unrelated clocks | Highest |
| Rationally related | Integer frequency ratio, common source | Medium |
| Same frequency, different phase | Same freq, phase offset | Medium |
| Same clock, different trees | Same source, different distribution | Low |
| Synchronous | Same clock tree | None |

### 1.2 Metastability

```
Metastability occurs when a flip-flop's setup or hold time is violated:

  Source Domain (clk_a)          Destination Domain (clk_b)
  +---------+                   +---------+   +---------+
  | FF_src  |----signal-------->| FF_sync1|-->| FF_sync2|--->
  +---------+                   +---------+   +---------+
        ^                            ^              ^
        |                            |              |
      clk_a                        clk_b          clk_b

If signal changes too close to clk_b edge:
  - FF_sync1 enters metastable state
  - May resolve to 0 or 1 (unpredictable)
  - FF_sync2 provides one more cycle for resolution
  - MTBF (Mean Time Between Failures) increases exponentially
    with each synchronizer stage
```

**MTBF Calculation:**

```
MTBF = 1 / (f_src * f_dst * T_resolve^N * k)

Where:
  f_src     = source clock frequency
  f_dst     = destination clock frequency
  T_resolve = metastability resolution time constant
  N         = number of synchronizer stages
  k         = technology-dependent constant

Target: MTBF > 100 years for production designs
```

### 1.3 CDC Failure Modes

| Failure Mode | Description | Impact |
|-------------|-------------|--------|
| Data loss | Single bit crossing without sync | Unpredictable data |
| Data incoherence | Multi-bit crossing without proper scheme | Partial update visible |
| Reconvergence | Same source reaches dest via different paths | Inconsistent state |
| Reset domain crossing | Reset from one domain used in another | Incorrect initialization |
| Glitch | Combinational logic on CDC path creates glitch | Spurious transitions |

---

## 2. Synchronization Schemes

### 2.1 Two-FF Synchronizer (Single Bit)

The simplest and most common synchronization scheme for single-bit signals.

```systemverilog
module sync_2ff #(
  parameter STAGES = 2,
  parameter RESET_VAL = 1'b0
)(
  input  logic clk_dst,
  input  logic rst_dst_n,
  input  logic signal_src,
  output logic signal_dst
);

  (* async_reg = "true" *)
  logic [STAGES-1:0] sync_reg;

  always_ff @(posedge clk_dst or negedge rst_dst_n) begin
    if (!rst_dst_n)
      sync_reg <= {STAGES{RESET_VAL}};
    else
      sync_reg <= {sync_reg[STAGES-2:0], signal_src};
  end

  assign signal_dst = sync_reg[STAGES-1];

endmodule
```

**When to Use:**
- Single-bit control signals (enable, interrupt, status)
- Level signals (not pulses narrower than destination clock period)
- Signals that are stable for sufficient time

**When NOT to Use:**
- Multi-bit data buses (use Gray code or handshake)
- Pulse signals (use pulse synchronizer)
- Data with coherency requirements (use FIFO)

### 2.2 Pulse Synchronizer

For signals that are asserted for exactly one source clock cycle.

```systemverilog
module pulse_sync(
  input  logic clk_src,
  input  logic rst_src_n,
  input  logic clk_dst,
  input  logic rst_dst_n,
  input  logic pulse_src,
  output logic pulse_dst
);

  // Toggle in source domain
  logic toggle_src;
  always_ff @(posedge clk_src or negedge rst_src_n) begin
    if (!rst_src_n)
      toggle_src <= 1'b0;
    else if (pulse_src)
      toggle_src <= ~toggle_src;
  end

  // Synchronize toggle to destination
  logic toggle_dst, toggle_dst_d;
  sync_2ff u_sync(
    .clk_dst(clk_dst),
    .rst_dst_n(rst_dst_n),
    .signal_src(toggle_src),
    .signal_dst(toggle_dst)
  );

  // Detect edge in destination domain
  always_ff @(posedge clk_dst or negedge rst_dst_n) begin
    if (!rst_dst_n)
      toggle_dst_d <= 1'b0;
    else
      toggle_dst_d <= toggle_dst;
  end

  assign pulse_dst = toggle_dst ^ toggle_dst_d;

endmodule
```

**Limitation:** Cannot handle back-to-back pulses faster than synchronization latency.

### 2.3 Handshake Synchronizer

For multi-bit data crossing between domains.

```systemverilog
module handshake_sync #(
  parameter DATA_W = 32
)(
  input  logic             clk_src,
  input  logic             rst_src_n,
  input  logic             clk_dst,
  input  logic             rst_dst_n,
  input  logic             req_src,
  input  logic [DATA_W-1:0] data_src,
  output logic             ack_src,
  output logic             valid_dst,
  output logic [DATA_W-1:0] data_dst
);

  // Source domain
  logic req_reg;
  logic [DATA_W-1:0] data_reg;
  logic ack_sync;

  always_ff @(posedge clk_src or negedge rst_src_n) begin
    if (!rst_src_n) begin
      req_reg  <= 1'b0;
      data_reg <= '0;
    end else if (req_src && !req_reg && !ack_sync) begin
      req_reg  <= 1'b1;
      data_reg <= data_src;
    end else if (ack_sync) begin
      req_reg  <= 1'b0;
    end
  end

  // Synchronize ACK back to source
  sync_2ff u_ack_sync(
    .clk_dst(clk_src),
    .rst_dst_n(rst_src_n),
    .signal_src(ack_dst_reg),
    .signal_dst(ack_sync)
  );
  assign ack_src = ack_sync;

  // Destination domain
  logic req_sync;
  logic ack_dst_reg;

  // Synchronize REQ to destination
  sync_2ff u_req_sync(
    .clk_dst(clk_dst),
    .rst_dst_n(rst_dst_n),
    .signal_src(req_reg),
    .signal_dst(req_sync)
  );

  always_ff @(posedge clk_dst or negedge rst_dst_n) begin
    if (!rst_dst_n) begin
      ack_dst_reg <= 1'b0;
      valid_dst   <= 1'b0;
      data_dst    <= '0;
    end else begin
      valid_dst <= 1'b0;
      if (req_sync && !ack_dst_reg) begin
        ack_dst_reg <= 1'b1;
        data_dst    <= data_reg;  // Data is stable, safe to sample
        valid_dst   <= 1'b1;
      end else if (!req_sync) begin
        ack_dst_reg <= 1'b0;
      end
    end
  end

endmodule
```

### 2.4 Asynchronous FIFO

For high-throughput, multi-bit data crossing.

```systemverilog
module async_fifo #(
  parameter DATA_W = 32,
  parameter DEPTH  = 16,
  parameter ADDR_W = $clog2(DEPTH)
)(
  // Write domain
  input  logic             wr_clk,
  input  logic             wr_rst_n,
  input  logic             wr_en,
  input  logic [DATA_W-1:0] wr_data,
  output logic             wr_full,

  // Read domain
  input  logic             rd_clk,
  input  logic             rd_rst_n,
  input  logic             rd_en,
  output logic [DATA_W-1:0] rd_data,
  output logic             rd_empty
);

  // Memory
  logic [DATA_W-1:0] mem [DEPTH-1:0];

  // Write and read pointers (binary)
  logic [ADDR_W:0] wr_ptr_bin, rd_ptr_bin;

  // Gray-coded pointers
  logic [ADDR_W:0] wr_ptr_gray, rd_ptr_gray;
  logic [ADDR_W:0] wr_ptr_gray_sync, rd_ptr_gray_sync;

  // Binary to Gray conversion
  function automatic logic [ADDR_W:0] bin2gray(logic [ADDR_W:0] bin);
    return bin ^ (bin >> 1);
  endfunction

  // Gray to Binary conversion
  function automatic logic [ADDR_W:0] gray2bin(logic [ADDR_W:0] gray);
    logic [ADDR_W:0] bin;
    bin[ADDR_W] = gray[ADDR_W];
    for (int i = ADDR_W-1; i >= 0; i--)
      bin[i] = bin[i+1] ^ gray[i];
    return bin;
  endfunction

  // Write domain logic
  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_ptr_bin  <= '0;
      wr_ptr_gray <= '0;
    end else if (wr_en && !wr_full) begin
      mem[wr_ptr_bin[ADDR_W-1:0]] <= wr_data;
      wr_ptr_bin  <= wr_ptr_bin + 1;
      wr_ptr_gray <= bin2gray(wr_ptr_bin + 1);
    end
  end

  // Read domain logic
  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_ptr_bin  <= '0;
      rd_ptr_gray <= '0;
    end else if (rd_en && !rd_empty) begin
      rd_ptr_bin  <= rd_ptr_bin + 1;
      rd_ptr_gray <= bin2gray(rd_ptr_bin + 1);
    end
  end

  assign rd_data = mem[rd_ptr_bin[ADDR_W-1:0]];

  // Synchronize write pointer to read domain (for empty)
  sync_2ff #(.STAGES(2)) u_wr_sync [ADDR_W:0] (
    .clk_dst(rd_clk),
    .rst_dst_n(rd_rst_n),
    .signal_src(wr_ptr_gray),
    .signal_dst(wr_ptr_gray_sync)
  );

  // Synchronize read pointer to write domain (for full)
  sync_2ff #(.STAGES(2)) u_rd_sync [ADDR_W:0] (
    .clk_dst(wr_clk),
    .rst_dst_n(wr_rst_n),
    .signal_src(rd_ptr_gray),
    .signal_dst(rd_ptr_gray_sync)
  );

  // Full and empty flags
  assign wr_full  = (wr_ptr_gray == {~rd_ptr_gray_sync[ADDR_W:ADDR_W-1],
                                      rd_ptr_gray_sync[ADDR_W-2:0]});
  assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync);

endmodule
```

### 2.5 MUX Synchronizer (Data Bus)

For multi-bit data with an enable/valid signal.

```systemverilog
module mux_sync #(
  parameter DATA_W = 32
)(
  input  logic             clk_src,
  input  logic             rst_src_n,
  input  logic             clk_dst,
  input  logic             rst_dst_n,
  input  logic             valid_src,
  input  logic [DATA_W-1:0] data_src,
  output logic             valid_dst,
  output logic [DATA_W-1:0] data_dst
);

  // Synchronize valid signal
  logic valid_sync;
  sync_2ff u_valid_sync(
    .clk_dst(clk_dst),
    .rst_dst_n(rst_dst_n),
    .signal_src(valid_src),
    .signal_dst(valid_sync)
  );

  // Sample data when valid is asserted in destination domain
  // Data must be stable when valid_sync is asserted
  always_ff @(posedge clk_dst or negedge rst_dst_n) begin
    if (!rst_dst_n) begin
      data_dst  <= '0;
      valid_dst <= 1'b0;
    end else begin
      valid_dst <= valid_sync;
      if (valid_sync)
        data_dst <= data_src;  // Direct connection, stable when sampled
    end
  end

endmodule
```

---

## 3. Structural CDC Analysis

### 3.1 Clock Identification

The first step in CDC analysis is identifying all clock domains in the design.

**Clock Domain Sources:**
- Primary clock inputs
- PLL/DLL outputs
- Generated clocks (dividers, gaters)
- External interface clocks (PHY, IO)

**Clock Domain Mapping:**

```
Clock Domain Analysis:
======================
Domain    | Source           | Frequency | Registers
----------|-----------------|-----------|----------
clk_core  | PLL output 0    | 500 MHz   | 45,000
clk_bus   | PLL output 1    | 250 MHz   | 12,000
clk_io    | External pad    | 100 MHz   | 3,000
clk_usb   | USB PHY         | 60 MHz    | 2,500
clk_rtc   | RTC oscillator  | 32 KHz    | 500
```

### 3.2 Crossing Identification

For each register pair where source and destination are in different domains:

| Crossing Type | Description | Analysis Required |
|-------------|-------------|------------------|
| Single-bit | One signal crosses | Check synchronizer |
| Multi-bit | Bus crosses | Check encoding/scheme |
| Control | Control signal crosses | Check protocol |
| Data + valid | Data bus with qualifier | Check MUX sync |
| FIFO pointer | FIFO read/write pointer | Check Gray coding |
| Reset | Reset signal crosses | Check reset sync |

### 3.3 Structural Checks

CDC structural analysis verifies that proper synchronization hardware exists
on every crossing path.

**Check Categories:**

| Check | Description | Severity |
|-------|-------------|----------|
| No sync | Signal crosses without synchronizer | Error |
| Combo on CDC | Combinational logic before synchronizer | Error |
| Multi-bit no scheme | Multi-bit signal without sync scheme | Error |
| Reconvergence | Same signal arrives via multiple paths | Warning |
| Glitch on CDC | Glitch-prone logic on crossing path | Error |
| Fan-out on CDC | One signal fans out to multiple sync | Warning |
| Sync depth | Synchronizer has fewer than 2 stages | Error |
| Reset sync | Async reset crosses domain | Warning |

---

## 4. Protocol CDC Verification

### 4.1 Handshake Verification

Verify that handshake synchronizers follow the correct protocol:

```systemverilog
// Handshake protocol assertions
module handshake_checker(
  input logic clk_src,
  input logic rst_src_n,
  input logic clk_dst,
  input logic rst_dst_n,
  input logic req,
  input logic ack,
  input logic [DATA_W-1:0] data
);

  // REQ must be stable until ACK
  property p_req_stable;
    @(posedge clk_src) disable iff (!rst_src_n)
    $rose(req) |-> req throughout (##[1:$] ack);
  endproperty
  a_req_stable: assert property (p_req_stable);

  // Data must be stable while REQ is asserted
  property p_data_stable;
    @(posedge clk_src) disable iff (!rst_src_n)
    req |-> $stable(data);
  endproperty
  a_data_stable: assert property (p_data_stable);

  // REQ must de-assert after ACK
  property p_req_deassert;
    @(posedge clk_src) disable iff (!rst_src_n)
    req && ack |=> !req;
  endproperty
  a_req_deassert: assert property (p_req_deassert);

  // ACK must de-assert after REQ de-asserts
  property p_ack_deassert;
    @(posedge clk_dst) disable iff (!rst_dst_n)
    ack && !req |=> !ack;
  endproperty
  // Note: this assertion is approximate due to CDC

  // No new REQ before ACK completes
  property p_no_new_req;
    @(posedge clk_src) disable iff (!rst_src_n)
    $fell(req) |-> !req throughout (##[1:$] !ack);
  endproperty

endmodule
```

### 4.2 FIFO Verification

```systemverilog
// Async FIFO CDC verification
module async_fifo_checker #(
  parameter DEPTH  = 16,
  parameter ADDR_W = $clog2(DEPTH)
)(
  input logic             wr_clk,
  input logic             wr_rst_n,
  input logic             rd_clk,
  input logic             rd_rst_n,
  input logic             wr_en,
  input logic             rd_en,
  input logic             wr_full,
  input logic             rd_empty,
  input logic [ADDR_W:0]  wr_ptr_gray,
  input logic [ADDR_W:0]  rd_ptr_gray,
  input logic [ADDR_W:0]  wr_ptr_gray_sync,
  input logic [ADDR_W:0]  rd_ptr_gray_sync
);

  // Gray code verification: only one bit changes at a time
  a_wr_gray: assert property (
    @(posedge wr_clk) disable iff (!wr_rst_n)
    $changed(wr_ptr_gray) |-> $onehot(wr_ptr_gray ^ $past(wr_ptr_gray))
  ) else $error("Write pointer gray code violation");

  a_rd_gray: assert property (
    @(posedge rd_clk) disable iff (!rd_rst_n)
    $changed(rd_ptr_gray) |-> $onehot(rd_ptr_gray ^ $past(rd_ptr_gray))
  ) else $error("Read pointer gray code violation");

  // No push when full
  a_no_push_full: assert property (
    @(posedge wr_clk) disable iff (!wr_rst_n)
    wr_full |-> !wr_en
  ) else $error("Push to full FIFO");

  // No pop when empty
  a_no_pop_empty: assert property (
    @(posedge rd_clk) disable iff (!rd_rst_n)
    rd_empty |-> !rd_en
  ) else $error("Pop from empty FIFO");

  // Data integrity (auxiliary checker)
  // Track write data and verify read data matches FIFO order

endmodule
```

### 4.3 MUX Synchronizer Verification

```systemverilog
// Verify MUX synchronizer protocol
module mux_sync_checker #(
  parameter DATA_W = 32
)(
  input logic             clk_src,
  input logic             rst_src_n,
  input logic             valid_src,
  input logic [DATA_W-1:0] data_src
);

  // Data must be stable for at least 2 destination clock cycles
  // when valid is asserted (source domain check)
  property p_data_stable_during_valid;
    @(posedge clk_src) disable iff (!rst_src_n)
    valid_src |-> $stable(data_src);
  endproperty
  a_data_stable: assert property (p_data_stable_during_valid);

  // Valid must be held long enough for destination to sample
  // (depends on clock ratio)
  property p_valid_duration;
    @(posedge clk_src) disable iff (!rst_src_n)
    $rose(valid_src) |-> valid_src [*3:$];  // At least 3 source cycles
  endproperty

endmodule
```

---

## 5. Reconvergence Analysis

### 5.1 What is Reconvergence?

Reconvergence occurs when a signal from one clock domain reaches the
destination domain through multiple paths, potentially arriving at different
times due to different synchronization latencies.

```
                     Domain A              Domain B
                   +--------+            +--------+
                   | Source  |--path1---->| Sync1  |--+
                   | Signal  |            +--------+  |
                   |         |--path2---->| Sync2  |--+--> Logic
                   +--------+            +--------+

Problem: Sync1 and Sync2 may resolve at different destination
clock edges, causing temporary inconsistency.
```

### 5.2 Reconvergence Types

| Type | Description | Risk |
|------|-------------|------|
| Simple reconvergence | Same signal via different synchronizers | Medium |
| Data/control | Data and its control cross separately | High |
| Fanout reconvergence | One signal fans out then reconverges | Medium |
| Indirect reconvergence | Different source signals from same logic | Low |

### 5.3 Reconvergence Fixes

```systemverilog
// Problem: Two bits from same source crossing separately
// source_domain:
//   signal_a, signal_b derived from same source
// dest_domain:
//   sync_a, sync_b may not be coherent

// Fix 1: Use single synchronizer for control, MUX for data
// Synchronize a single enable/valid signal
// Use MUX synchronizer for the data bits

// Fix 2: Use Gray coding for multi-bit values
// Ensures only one bit changes at a time

// Fix 3: Use handshake for coherent data
// Ensures all bits are sampled together

// Fix 4: Use FIFO
// Provides clean data transfer with flow control
```

---

## 6. Gray Code Verification

### 6.1 Gray Code Properties

Gray code ensures only one bit changes between consecutive values:

```
Binary | Gray
-------|------
 0000  | 0000
 0001  | 0001
 0010  | 0011
 0011  | 0010
 0100  | 0110
 0101  | 0111
 0110  | 0101
 0111  | 0100
 1000  | 1100
 1001  | 1101
 1010  | 1111
 1011  | 1110
 1100  | 1010
 1101  | 1011
 1110  | 1001
 1111  | 1000
```

### 6.2 Gray Code Conversion Verification

```systemverilog
// Verify binary-to-Gray conversion
function automatic logic [N-1:0] bin2gray_check(logic [N-1:0] bin);
  return bin ^ (bin >> 1);
endfunction

// Verify Gray-to-binary conversion
function automatic logic [N-1:0] gray2bin_check(logic [N-1:0] gray);
  logic [N-1:0] bin;
  bin[N-1] = gray[N-1];
  for (int i = N-2; i >= 0; i--)
    bin[i] = bin[i+1] ^ gray[i];
  return bin;
endfunction

// Assertion: Gray code changes by at most one bit
property p_gray_one_hot_change;
  @(posedge clk) disable iff (!rst_n)
  $changed(gray_value) |-> $onehot(gray_value ^ $past(gray_value));
endproperty
assert property (p_gray_one_hot_change);

// Assertion: Gray conversion is reversible
property p_gray_reversible;
  @(posedge clk)
  gray2bin_check(bin2gray_check(binary_value)) == binary_value;
endproperty
assert property (p_gray_reversible);
```

### 6.3 Gray Code for FIFO Pointers

```systemverilog
// FIFO pointer Gray code requirements:
// 1. Power-of-2 depth (required for standard Gray code)
// 2. Only one bit changes per pointer increment
// 3. Full condition: MSB different, rest same
// 4. Empty condition: all bits same

// Verify FIFO pointer Gray code properties
module fifo_gray_checker #(parameter ADDR_W = 4)(
  input logic             wr_clk,
  input logic             wr_rst_n,
  input logic             rd_clk,
  input logic             rd_rst_n,
  input logic [ADDR_W:0]  wr_ptr_gray,
  input logic [ADDR_W:0]  rd_ptr_gray
);

  // Only one bit change on write pointer
  a_wr_one_bit: assert property (
    @(posedge wr_clk) disable iff (!wr_rst_n)
    $changed(wr_ptr_gray) |-> $onehot(wr_ptr_gray ^ $past(wr_ptr_gray))
  );

  // Only one bit change on read pointer
  a_rd_one_bit: assert property (
    @(posedge rd_clk) disable iff (!rd_rst_n)
    $changed(rd_ptr_gray) |-> $onehot(rd_ptr_gray ^ $past(rd_ptr_gray))
  );

  // Pointer must only increment (never decrement or skip)
  // This is verified by checking Gray code progression matches
  // the expected sequence

endmodule
```

---

## 7. Reset Domain Crossing (RDC)

### 7.1 RDC Issues

Reset Domain Crossing (RDC) occurs when:
- A reset signal from one domain is used in another domain
- Components in different reset domains interact
- Asynchronous reset de-assertion is not synchronized

| RDC Issue | Description | Risk |
|-----------|-------------|------|
| Async reset glitch | Glitch on async reset line | High |
| Reset de-assertion race | Different blocks release at different times | High |
| Reset sequence | Incorrect order of reset assertion/release | Medium |
| Reset recovery | Signal changes during reset recovery time | Medium |

### 7.2 Reset Synchronizer

```systemverilog
module reset_sync #(
  parameter STAGES = 2
)(
  input  logic clk_dst,
  input  logic rst_src_n,    // Async reset from source domain
  output logic rst_dst_n     // Synchronized reset in destination domain
);

  (* async_reg = "true" *)
  logic [STAGES-1:0] sync_reg;

  // Assert asynchronously, de-assert synchronously
  always_ff @(posedge clk_dst or negedge rst_src_n) begin
    if (!rst_src_n)
      sync_reg <= '0;     // Async assert (immediate)
    else
      sync_reg <= {sync_reg[STAGES-2:0], 1'b1};  // Sync de-assert
  end

  assign rst_dst_n = sync_reg[STAGES-1];

endmodule
```

### 7.3 RDC Verification

```systemverilog
// Verify reset domain crossing
module rdc_checker(
  input logic clk_a,
  input logic clk_b,
  input logic rst_a_n,
  input logic rst_b_n,
  input logic rst_sync_b_n
);

  // Reset synchronizer output must follow input (eventually)
  property p_reset_propagation;
    @(posedge clk_b)
    !rst_a_n |-> ##[1:5] !rst_sync_b_n;
  endproperty
  a_rst_prop: assert property (p_reset_propagation);

  // De-assertion must be synchronous to destination clock
  property p_deassert_sync;
    @(posedge clk_b)
    $rose(rst_sync_b_n) |-> ##0 (rst_sync_b_n === 1'b1);
  endproperty

  // Reset must be asserted long enough for destination
  property p_reset_width;
    @(posedge clk_b)
    $fell(rst_a_n) |-> !rst_a_n [*3];  // At least 3 dest cycles
  endproperty

endmodule
```

### 7.4 Reset Sequencing

```
Reset Sequence Requirements:
1. Assert reset in correct order (peripherals before core)
2. Hold reset long enough for all domains
3. De-assert reset in correct order (core before peripherals)
4. Synchronize de-assertion to each domain's clock
5. Wait for design to stabilize after de-assertion

Reset Sequence Example:
  Time   | Core Reset | Bus Reset | Peripheral Reset
  -------|-----------|-----------|------------------
  T0     | Assert    | Assert    | Assert
  T1     | Hold      | Hold      | Hold
  T2     | Hold      | Hold      | Hold
  T3     | Release   | Hold      | Hold           (core first)
  T4     | Active    | Release   | Hold           (bus second)
  T5     | Active    | Active    | Release        (peripheral last)
  T6     | Active    | Active    | Active         (all running)
```

---

## 8. CDC Tools

### 8.1 SpyGlass CDC (Synopsys)

```tcl
# SpyGlass CDC setup
set_option enableSV yes
set_option language_mode mixed

# Read design
read_file -type verilog design.v
read_file -type verilog std_cell.v

# Set top module
set_option top my_design

# Clock definition
current_design my_design
create_clock -name clk_core -period 2.0 [get_ports clk_core]
create_clock -name clk_bus  -period 4.0 [get_ports clk_bus]
create_clock -name clk_io   -period 10.0 [get_ports clk_io]

# Define clock relationships
set_clock_groups -asynchronous \
  -group [get_clocks clk_core] \
  -group [get_clocks clk_bus] \
  -group [get_clocks clk_io]

# Define reset
set_input_reset -name rst_core_n -active_low [get_ports rst_core_n]
set_input_reset -name rst_bus_n  -active_low [get_ports rst_bus_n]

# Run CDC analysis
set_option policy cdc
current_goal lint/lint_rtl
run_goal

current_goal cdc/cdc_verify
run_goal

current_goal cdc/cdc_verify_struct
run_goal

# Generate reports
write_report -output cdc_report.rpt
write_report -output cdc_crossings.rpt -type crossings
write_report -output cdc_violations.rpt -type violations

# Waivers
set_option waiver_file cdc_waivers.swl
```

**SpyGlass CDC Rules:**

| Rule ID | Description | Severity |
|---------|-------------|----------|
| Ac_cdc01 | Missing synchronizer | Error |
| Ac_cdc02 | Combo logic before sync FF | Error |
| Ac_cdc03 | Multi-bit CDC without scheme | Error |
| Ac_cdc04 | Reconvergence | Warning |
| Ac_cdc05 | FIFO gray code issue | Error |
| Ac_cdc06 | Reset CDC | Warning |
| Ac_cdc07 | Glitch on CDC path | Error |
| Ac_unsync01 | Unsynchronized crossing | Error |
| Ac_conv01 | Convergence issue | Warning |

### 8.2 Jasper CDC (Cadence)

```tcl
# Jasper CDC setup
clear -all

# Read design
analyze -sv design.sv
analyze -sv std_cell.sv
elaborate -top my_design

# Clock definition
clock clk_core -period 2.0
clock clk_bus  -period 4.0
clock clk_io   -period 10.0

# Reset
reset -expression {!rst_n}

# Define clock relationships
set_cdc_clock_domain -asynchronous clk_core clk_bus
set_cdc_clock_domain -asynchronous clk_core clk_io
set_cdc_clock_domain -asynchronous clk_bus  clk_io

# Run CDC analysis
check_cdc -type structural
check_cdc -type protocol
check_cdc -type reconvergence

# Reports
report_cdc -all -output cdc_report.rpt
report_cdc -crossings -output crossings.rpt
report_cdc -violations -output violations.rpt

# Formal CDC verification
check_cdc -type formal -prove
```

**Jasper CDC Features:**
- Structural CDC: identifies crossings and checks synchronizers
- Protocol CDC: formally verifies handshake/FIFO protocols
- Reconvergence: analyzes data coherency
- Metastability injection: formal analysis with metastable scenarios
- Coverage: CDC-specific coverage metrics

### 8.3 Questa CDC (Siemens)

```tcl
# Questa CDC setup
cdc run -d my_design

# Clock definitions
netlist clock clk_core -period 2ns
netlist clock clk_bus  -period 4ns
netlist clock clk_io   -period 10ns

# Reset
netlist reset rst_n -active_low

# Clock relationships
cdc preference -async_clocks clk_core clk_bus
cdc preference -async_clocks clk_core clk_io

# Run analysis
cdc run -structural
cdc run -protocol
cdc run -reconvergence

# Report
cdc generate report -output cdc_report.rpt
cdc generate crossings -output crossings.rpt
```

### 8.4 Tool Comparison

| Feature | SpyGlass CDC | Jasper CDC | Questa CDC |
|---------|-------------|-----------|-----------|
| Structural analysis | Yes | Yes | Yes |
| Protocol verification | Limited | Formal | Formal |
| Reconvergence | Yes | Yes | Yes |
| Metastability injection | No | Yes | Yes |
| Formal proof | No | Yes | Yes |
| Reset domain crossing | Yes | Yes | Yes |
| Glitch detection | Yes | Yes | Yes |
| Gray code check | Yes | Yes | Yes |
| Report quality | Good | Good | Good |
| Integration | SpyGlass GUI | Jasper GUI | Questa GUI |

---

## 9. CDC Waivers and Exceptions

### 9.1 Valid Waiver Categories

| Category | Description | Example |
|----------|-------------|---------|
| Quasi-static | Signal changes only during config, stable during operation | Mode register |
| Tied constant | Signal is tied to constant value | Hard-wired config |
| Same-phase | Clocks are same phase, guaranteed by design | Divided clocks |
| Rationally related | Integer ratio, phase-locked | 2x, 4x clocks |
| Test-only | Signal used only in test mode | Scan signals |
| Functionally excluded | Path never active in normal mode | Debug signals |

### 9.2 Waiver Documentation

```
CDC Waiver Template:
====================
Waiver ID:       CDC-WAIVE-XXXX
Crossing:        clk_a -> clk_b
Signal:          cfg_mode[2:0]
Path:            u_ctrl.cfg_mode -> u_sync.data_in
Rule Violated:   Multi-bit CDC without synchronization scheme
Category:        Quasi-static
Justification:   cfg_mode is programmed during initialization only,
                 before any clock domain is active. Signal is stable
                 during all operational modes. Verified by:
                 1. Assertion: cfg_mode stable after init_done
                 2. Coverage: cfg_mode changes only during reset
Risk:            None
Approved By:     J. Smith, 2024-03-15
Review Date:     2024-06-15
```

### 9.3 Waiver File Format (SpyGlass)

```tcl
# SpyGlass CDC waiver file (.swl)

waiver -rule Ac_cdc03 \
       -signal cfg_mode \
       -from_clock clk_core \
       -to_clock clk_bus \
       -comment "Quasi-static: programmed during init only" \
       -waiver_id CDC-WAIVE-0001

waiver -rule Ac_unsync01 \
       -signal debug_en \
       -comment "Test-only signal, not active in functional mode" \
       -waiver_id CDC-WAIVE-0002
```

---

## 10. CDC Sign-Off Methodology

### 10.1 CDC Verification Flow

```
CDC Sign-Off Flow:
==================
1. STRUCTURAL CDC
   - Run structural CDC tool
   - Identify all crossings
   - Verify synchronizers present
   - Check for combo logic on CDC paths
   - Check for multi-bit without scheme

2. PROTOCOL CDC
   - Verify handshake protocols
   - Verify FIFO protocols
   - Check Gray coding
   - Verify MUX synchronizer timing

3. RECONVERGENCE
   - Identify all reconvergent paths
   - Verify data coherency
   - Check for multi-path timing issues

4. RESET DOMAIN CROSSING
   - Verify reset synchronizers
   - Check reset sequencing
   - Verify reset recovery timing

5. WAIVERS
   - Document all waivers
   - Review and approve
   - Verify waiver validity

6. SIMULATION
   - CDC-aware simulation (metastability injection)
   - Verify CDC assertions pass
   - Cover CDC scenarios

7. SIGN-OFF
   - All structural CDC clean (or waived)
   - All protocol CDC verified
   - All reconvergence analyzed
   - All RDC verified
   - Waivers reviewed and approved
   - CDC regression passing
```

### 10.2 CDC Sign-Off Checklist

```
[ ] All clock domains identified and documented
[ ] All crossings identified by structural analysis
[ ] Every crossing has proper synchronization
[ ] No combinational logic on CDC paths
[ ] Multi-bit crossings use proper scheme (Gray/handshake/FIFO)
[ ] Reconvergence analyzed and resolved
[ ] Gray code verified for FIFO pointers
[ ] Reset synchronizers present for all async resets
[ ] Reset sequencing verified
[ ] CDC assertions defined and passing
[ ] CDC protocol formal verification complete
[ ] All waivers documented and approved
[ ] CDC regression clean
[ ] CDC review meeting completed
[ ] Sign-off approved by CDC owner
```

### 10.3 CDC Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| Crossings identified | 100% | All crossings found |
| Crossings verified | 100% | All crossings have proper sync |
| Structural violations | 0 | After waivers |
| Protocol violations | 0 | All protocols verified |
| Reconvergence issues | 0 | All resolved or waived |
| Reset violations | 0 | All resets synchronized |
| Waivers | Minimized | Each justified and reviewed |
| CDC assertions | 100% pass | All CDC assertions green |
| CDC coverage | > 90% | CDC scenarios exercised |

---

## 11. CDC Best Practices

### 11.1 Design Best Practices

1. **Minimize crossings:** Keep related logic in the same domain.
2. **Use standard synchronizers:** Do not invent custom schemes.
3. **Use async FIFOs** for high-throughput data crossing.
4. **Use handshakes** for low-frequency, coherent data crossing.
5. **Gray code** FIFO pointers (requires power-of-2 depth).
6. **Avoid combinational logic** between source register and synchronizer.
7. **Synchronize resets** in each domain.
8. **Document all crossings** in architecture specification.

### 11.2 Verification Best Practices

1. **Run CDC analysis early** (at RTL completion).
2. **Re-run after every RTL change** that modifies clock/reset/CDC paths.
3. **Define CDC assertions** for every crossing.
4. **Use formal CDC tools** for protocol verification.
5. **Inject metastability** in simulation for robustness.
6. **Review waivers quarterly** and after design changes.
7. **Track CDC metrics** as part of verification dashboard.
8. **Include CDC in sign-off criteria** with explicit checklist.

### 11.3 Common CDC Bugs

| Bug Pattern | Description | Detection |
|------------|-------------|-----------|
| Missing sync | No synchronizer on crossing | Structural CDC tool |
| Combo before sync | MUX/AND before sync FF | Structural CDC tool |
| Multi-bit no Gray | Bus crossing without encoding | Structural CDC tool |
| Wrong sync type | Level sync for pulse signal | Protocol verification |
| FIFO pointer bug | Non-Gray or non-power-of-2 | Gray code assertion |
| Reset glitch | Unsynchronized reset | RDC analysis |
| Reconvergence | Incoherent data arrival | Reconvergence analysis |
| Data hold violation | Data changes during sync | Protocol assertion |

---
