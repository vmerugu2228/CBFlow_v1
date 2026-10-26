# SystemVerilog Assertions (SVA) Complete Reference

Comprehensive reference for SystemVerilog Assertions covering immediate
assertions, concurrent assertions, sequences, properties, system functions,
multi-clock assertions, binding, and common protocol patterns.

---

## 1. Assertion Types Overview

SystemVerilog supports two fundamental assertion types:

| Type | Syntax | Execution | Use Case |
|------|--------|-----------|----------|
| Immediate | assert(expr) | Procedural, instant | Combinational checks, function arguments |
| Concurrent | assert property(prop) | Clock-based, temporal | Protocol checking, timing relationships |

---

## 2. Immediate Assertions

### 2.1 Basic Immediate Assertions

Immediate assertions are procedural statements evaluated at the point of
execution, like an if-statement with reporting.

```systemverilog
// Simple assert
assert (data !== 'x)
  else $error("Data is unknown");

// Assert with pass action
assert (grant inside {4'b0001, 4'b0010, 4'b0100, 4'b1000})
  $info("Valid one-hot grant: %b", grant);
else
  $error("Invalid grant encoding: %b", grant);

// Assert in always block
always @(posedge clk) begin
  assert (state != ILLEGAL_STATE)
  else $fatal(1, "Entered illegal state: %s", state.name());
end

// Assert in function
function automatic bit [31:0] divide(bit [31:0] a, bit [31:0] b);
  assert (b != 0) else $fatal(1, "Division by zero");
  return a / b;
endfunction
```

### 2.2 Deferred Immediate Assertions

Deferred assertions evaluate in the Observed region of the time step, avoiding
glitch sensitivity. Introduced in SystemVerilog 2012.

```systemverilog
// Deferred assertion (evaluated at end of time step)
always_comb begin
  assert #0 (onehot(grant))     // #0 = Observed region
    else $error("Grant not one-hot");
end

// Final deferred assertion (evaluated in Reactive-postponed region)
always_comb begin
  assert final (^parity === expected_parity)
    else $error("Parity mismatch");
end
```

### 2.3 Immediate Assume and Cover

```systemverilog
// Assume: tells formal tools to constrain input space
always @(posedge clk) begin
  assume (req inside {[0:MAX_REQ]})
    else $error("Request out of range");
end

// Cover: tracks whether condition was exercised
always @(posedge clk) begin
  cover (state == RARE_STATE)
    $info("Rare state reached");
end
```

---

## 3. Concurrent Assertions

### 3.1 Assert Property

Concurrent assertions specify temporal behavior checked across clock cycles.

```systemverilog
// Basic concurrent assertion
assert property (@(posedge clk) disable iff (!rst_n)
  req |-> ##[1:3] ack
) else $error("REQ not acknowledged within 3 cycles");

// Named assertion
req_ack_check: assert property (@(posedge clk) disable iff (!rst_n)
  req |-> ##[1:3] ack
) else $error("REQ-ACK protocol violation");

// With pass/fail actions
data_valid_check: assert property (@(posedge clk) disable iff (!rst_n)
  valid |-> !$isunknown(data)
)
  pass_count++;
else begin
  fail_count++;
  $error("Unknown data when valid asserted");
end
```

### 3.2 Assume Property

Used for constraining inputs in formal verification and simulation.

```systemverilog
// Formal constraint: input valid must not have X
assume property (@(posedge clk) !$isunknown(valid));

// Formal constraint: request must be one-hot-0
assume property (@(posedge clk) $onehot0(req));

// Simulation constraint with action
assume property (@(posedge clk) data_in < MAX_VALUE)
  else $warning("Input constraint violated");
```

### 3.3 Cover Property

Tracks whether a temporal property was exercised during simulation.

```systemverilog
// Cover a specific protocol sequence
cover property (@(posedge clk) disable iff (!rst_n)
  req ##1 ack ##1 !req ##1 !ack
);

// Named cover with action
back_to_back_cover: cover property (@(posedge clk) disable iff (!rst_n)
  req ##1 ack ##0 req  // Back-to-back request
) $info("Back-to-back request observed");

// Cover sequence (shorthand)
cover sequence (@(posedge clk) req ##[1:5] ack);
```

### 3.4 Restrict Property

Constrains formal tool only (not checked in simulation).

```systemverilog
// Formal-only constraint
restrict property (@(posedge clk) $rose(rst_n) |=> !rst_n throughout ##[0:100] 1);
```

---

## 4. Sequences

Sequences define temporal patterns of signal behavior.

### 4.1 Sequence Delay Operators

```systemverilog
// ## (cycle delay)
sequence s1;
  a ##1 b;        // a, then b next cycle
endsequence

sequence s2;
  a ##2 b;        // a, then b two cycles later
endsequence

sequence s3;
  a ##0 b;        // a and b in the same cycle
endsequence

// Range delay
sequence s4;
  a ##[1:3] b;    // a, then b 1 to 3 cycles later
endsequence

sequence s5;
  a ##[0:$] b;    // a, then b eventually (0 to infinite cycles)
endsequence

sequence s6;
  a ##[1:$] b;    // a, then b at least 1 cycle later
endsequence
```

### 4.2 Repetition Operators

```systemverilog
// Consecutive repetition [*n]
sequence s_consec;
  a ##1 b[*3];              // a, then b for 3 consecutive cycles
endsequence
// Matches: a, b, b, b

sequence s_consec_range;
  a ##1 b[*2:5];            // a, then b for 2 to 5 consecutive cycles
endsequence

sequence s_consec_zero;
  a[*0:3] ##1 b;            // 0 to 3 cycles of a, then b
endsequence

// Non-consecutive (goto) repetition [->n]
sequence s_goto;
  a ##1 b[->3];             // a, then eventually 3 non-consecutive b's
endsequence
// Matches: a, ..., b, ..., b, ..., b (ends at third b)

sequence s_goto_range;
  a ##1 b[->2:4] ##1 c;    // a, then 2-4 b's (non-consec), then c next cycle
endsequence

// Non-consecutive repetition [=n]
sequence s_nonconsec;
  a ##1 b[=3];              // a, then 3 non-consecutive b's, possibly more cycles after
endsequence
// Matches: a, ..., b, ..., b, ..., b, ... (does NOT need to end at last b)

sequence s_nonconsec_range;
  a ##1 b[=2:4] ##1 c;     // a, then 2-4 b's (non-consec), then c
endsequence
```

**Comparison of [->] vs [=]:**

| Operator | Name | End Point |
|----------|------|-----------|
| [->n] | Goto | Ends at the n-th match |
| [=n] | Non-consecutive | May have gaps after the n-th match |

```
b[->3] ##1 c: ..b..b..b, c  (c must follow immediately after 3rd b)
b[=3]  ##1 c: ..b..b..b..., c  (c can follow later)
```

### 4.3 Sequence Combinators

```systemverilog
// AND: both sequences must match, starting at same time
sequence s_and;
  (a ##[1:3] b) and (c ##[2:4] d);
endsequence
// Both sub-sequences start simultaneously and must both complete

// OR: either sequence must match
sequence s_or;
  (a ##1 b ##1 c) or (a ##2 d);
endsequence

// INTERSECT: both sequences match with same length
sequence s_intersect;
  (a ##[1:5] b) intersect (c ##3 d);
endsequence
// Both must match AND have the same overall length (3 cycles for the second)

// THROUGHOUT: expression must hold during entire sequence
sequence s_throughout;
  enable throughout (a ##[1:5] b ##1 c);
endsequence
// enable must be true from start to end of the inner sequence

// WITHIN: first sequence completes within the span of second
sequence s_within;
  (a ##1 b) within (c ##[2:5] d);
endsequence
// a ##1 b must occur entirely within the c...d window

// FIRST_MATCH: use only the first match of a multi-match sequence
sequence s_first_match;
  first_match(a ##[1:5] b);
endsequence
```

### 4.4 Sequence Methods

```systemverilog
// .ended - true when sequence completes
sequence s_req;
  req ##[1:3] ack;
endsequence

property p_check;
  @(posedge clk) s_req.ended |-> done;
endproperty

// .matched - true at the endpoint (for use in procedural code)
sequence s_trigger;
  @(posedge clk) req ##1 ack;
endsequence

always @(s_trigger.matched) begin
  $display("Trigger sequence matched at %0t", $time);
end

// .triggered - for multi-clock coordination (sampled value)
property p_cross_clock;
  @(posedge clk1) req ##1 @(posedge clk2) s_ack.triggered;
endproperty
```

### 4.5 Local Variables in Sequences

```systemverilog
sequence data_integrity;
  int unsigned captured_data;
  (valid, captured_data = data) ##[1:5] (done && (result == captured_data));
endsequence

sequence addr_range_check;
  bit [31:0] saved_addr;
  (req, saved_addr = addr) ##[1:10]
  (ack && addr == saved_addr);
endsequence

// Multiple local variables
sequence complex_handshake;
  int id_val;
  bit [7:0] cmd_val;
  (cmd_valid, id_val = trans_id, cmd_val = cmd) ##[1:20]
  (rsp_valid && rsp_id == id_val && rsp_cmd == cmd_val);
endsequence
```

### 4.6 Parameterized Sequences

```systemverilog
sequence handshake_seq(req_sig, ack_sig, int min_delay = 1, int max_delay = 10);
  req_sig ##[min_delay:max_delay] ack_sig;
endsequence

// Usage
assert property (@(posedge clk) handshake_seq(cpu_req, cpu_ack, 1, 5));
assert property (@(posedge clk) handshake_seq(dma_req, dma_ack, 2, 20));

// Parameterized with sequence arguments
sequence bus_transfer(req, ack, data, int width);
  req ##1 ack ##0 (!$isunknown(data));
endsequence
```

---

## 5. Properties

Properties add temporal logic and implication to sequences.

### 5.1 Implication Operators

```systemverilog
// Overlapping implication |->
// If antecedent matches, consequent starts in the SAME cycle as antecedent end
property p_overlap;
  @(posedge clk) req |-> ack;
endproperty
// If req is true, ack must be true in the same cycle

property p_overlap_delay;
  @(posedge clk) req |-> ##1 ack;
endproperty
// If req is true, ack must be true next cycle

// Non-overlapping implication |=>
// If antecedent matches, consequent starts ONE cycle after antecedent end
property p_nonoverlap;
  @(posedge clk) req |=> ack;
endproperty
// Equivalent to: req |-> ##1 ack

property p_nonoverlap_delay;
  @(posedge clk) req |=> ##2 ack;
endproperty
// If req, then ack 3 cycles later (1 implicit + 2 explicit)

// Antecedent is a sequence
property p_seq_ante;
  @(posedge clk) (req ##1 grant) |-> ##[1:5] done;
endproperty
// After req then grant, done must occur within 5 cycles

// Vacuous success
// If antecedent never matches, the property passes vacuously
// req |-> ack; // If req is never true, assertion PASSES (vacuously)
```

### 5.2 Property Operators

```systemverilog
// NOT: negate a property
property p_never_error;
  @(posedge clk) not (state == ERROR);
endproperty

// AND: both properties must hold
property p_both;
  @(posedge clk) p1 and p2;
endproperty

// OR: at least one property must hold
property p_either;
  @(posedge clk) p1 or p2;
endproperty

// IF-ELSE: conditional property
property p_conditional;
  @(posedge clk) if (mode == BURST)
    (req |-> ##[1:4] ack)
  else
    (req |-> ##1 ack);
endproperty

// CASE: multi-way conditional (SV2012)
property p_case;
  @(posedge clk) case (state)
    IDLE:   (!valid);
    ACTIVE: (valid |-> !$isunknown(data));
    DONE:   (done);
    default: (1);
  endcase
endproperty

// STRONG and WEAK
// strong: sequence MUST eventually complete (for formal tools)
property p_strong;
  @(posedge clk) req |-> strong(##[1:$] ack);
endproperty
// ack MUST eventually happen (in formal, blocks infinite waiting)

// weak: sequence MAY or may not complete (default in simulation)
property p_weak;
  @(posedge clk) req |-> weak(##[1:$] ack);
endproperty
```

### 5.3 Disable and Control

```systemverilog
// disable iff: disable assertion when condition is true
property p_with_disable;
  @(posedge clk) disable iff (!rst_n || scan_mode)
  req |-> ##[1:5] ack;
endproperty

// accept_on: property evaluates to true when condition is true (SV2012)
property p_accept;
  @(posedge clk) accept_on(abort_signal)
  req |-> ##[1:100] done;
endproperty
// If abort_signal goes high, property passes immediately

// reject_on: property evaluates to false when condition is true (SV2012)
property p_reject;
  @(posedge clk) reject_on(error_condition)
  req |-> ##[1:100] done;
endproperty
// If error_condition goes high, property fails immediately

// sync_accept_on / sync_reject_on: synchronous versions
property p_sync_accept;
  @(posedge clk) sync_accept_on(done_flag)
  req |-> ##[1:$] ack;
endproperty
```

### 5.4 Parameterized Properties

```systemverilog
property req_ack_protocol(req_sig, ack_sig, int max_latency = 10);
  @(posedge clk) disable iff (!rst_n)
  req_sig |-> ##[1:max_latency] ack_sig;
endproperty

assert property (req_ack_protocol(cpu_req, cpu_ack, 5));
assert property (req_ack_protocol(dma_req, dma_ack, 20));

// Property with sequence argument
property response_check(sequence trigger_seq, signal resp, int timeout);
  @(posedge clk) disable iff (!rst_n)
  trigger_seq |-> ##[1:timeout] resp;
endproperty
```

---

## 6. Clocking

### 6.1 Clock Specification

```systemverilog
// Explicit clock in property
property p1;
  @(posedge clk) req |-> ##1 ack;
endproperty

// Negedge clock
property p2;
  @(negedge clk) req |-> ##1 ack;
endproperty

// Both edges
property p3;
  @(clk) req |-> ##1 ack;  // Both posedge and negedge
endproperty

// Gated clock
property p4;
  @(posedge gated_clk) req |-> ##1 ack;
endproperty
```

### 6.2 Default Clocking

```systemverilog
// Define default clock for a module/interface
default clocking cb @(posedge clk);
endclocking

// Assertions without explicit clock use default
assert property (req |-> ##1 ack);
assert property (valid |-> !$isunknown(data));

// Override default for specific assertion
assert property (@(negedge clk) req |-> ##1 ack);
```

### 6.3 Default Disable

```systemverilog
// Default disable for all assertions in a module
default disable iff (!rst_n);

// Now assertions don't need explicit disable iff
assert property (@(posedge clk) req |-> ##1 ack);
// Automatically disabled when !rst_n

// Override default
assert property (@(posedge clk) disable iff (0) always_check |-> valid);
```

### 6.4 Multi-Clock Assertions

```systemverilog
// Multi-clock sequence
sequence cross_domain;
  @(posedge clk_a) req_a ##1 @(posedge clk_b) ack_b;
endsequence

// Multi-clock property
property cross_clock_handshake;
  @(posedge clk_fast) req
  |-> ##[1:5] @(posedge clk_slow) ack;
endproperty

// Using .triggered for clock domain crossing
sequence s_in_clk2;
  @(posedge clk2) ack;
endsequence

property p_cdc;
  @(posedge clk1) req |-> ##[1:10] s_in_clk2.triggered;
endproperty

// Multi-clock with different sampling
property p_multi_sample;
  @(posedge clk1) (start_pulse, save_data = data_out)
  |-> @(posedge clk2) ##[2:10] (result == transform(save_data));
endproperty
```

---

## 7. System Functions for Assertions

### 7.1 Sampled Value Functions

```systemverilog
// $rose - true if signal transitioned from 0 to 1
property p_rose;
  @(posedge clk) $rose(req) |-> ##[1:5] ack;
endproperty

// $fell - true if signal transitioned from 1 to 0
property p_fell;
  @(posedge clk) $fell(busy) |-> done;
endproperty

// $stable - true if signal did not change from previous cycle
property p_stable;
  @(posedge clk) hold |-> $stable(data);
endproperty

// $changed - true if signal changed from previous cycle
property p_changed;
  @(posedge clk) !$stable(counter) |-> $changed(counter);
endproperty

// $past - value of signal in a previous cycle
property p_past;
  @(posedge clk) ack |-> (data == $past(data, 1));  // 1 cycle ago
endproperty

property p_past_n;
  @(posedge clk) done |-> (result == $past(input_data, 5));  // 5 cycles ago
endproperty

// $past with gating clock
property p_past_gated;
  @(posedge clk) done |-> (result == $past(data, 1, enable));
endproperty

// $past with expression
property p_past_expr;
  @(posedge clk) $past(state, 2) == ACTIVE |-> valid;
endproperty
```

### 7.2 Detection Functions

```systemverilog
// $onehot - true if exactly one bit is set
property p_onehot;
  @(posedge clk) $onehot(grant);
endproperty

// $onehot0 - true if zero or one bit is set
property p_onehot0;
  @(posedge clk) $onehot0(req);
endproperty

// $countones - count number of set bits
property p_count;
  @(posedge clk) $countones(enable) <= 4;
endproperty

// $isunknown - true if any bit is X or Z
property p_no_x;
  @(posedge clk) valid |-> !$isunknown(data);
endproperty

// $countbits(expr, ctrl_bit) - count bits matching control
property p_countbits;
  @(posedge clk) $countbits(data, '1) == parity;
endproperty

// $bits - return bit width
// Used in generic assertions
property p_generic;
  @(posedge clk) $countones(bus) <= $bits(bus) / 2;
endproperty
```

### 7.3 Coverage System Functions

```systemverilog
// $assertoff - disable assertions
initial begin
  // Disable all assertions in module during reset
  $assertoff(0, tb.dut);
  #100ns;
  $asserton(0, tb.dut);
end

// $asserton - enable assertions
// $assertkill - kill and disable assertions

// Levels:
// 0 = all assertion types
// 1 = only immediate assertions
// 2 = only concurrent assertions

// Per-instance control
initial begin
  $assertoff(0, tb.dut.my_assertion_name);
end

// $assertcontrol (SV2012) - fine-grained control
// $assertcontrol(control_type, assertion_type, directive_type, levels, list)
initial begin
  $assertcontrol(3, 15, 7, 0, tb.dut);  // Kill all in dut hierarchy
end
```

---

## 8. Binding

Binding allows assertions to be attached to modules externally without
modifying the original RTL.

### 8.1 Bind Module

```systemverilog
// Assertion module
module fifo_assertions #(
  parameter DEPTH = 16,
  parameter WIDTH = 8
)(
  input logic             clk,
  input logic             rst_n,
  input logic             push,
  input logic             pop,
  input logic             full,
  input logic             empty,
  input logic [WIDTH-1:0] wdata,
  input logic [WIDTH-1:0] rdata,
  input logic [$clog2(DEPTH):0] count
);

  // No simultaneous push and pop when full
  a_no_push_when_full: assert property (
    @(posedge clk) disable iff (!rst_n)
    full |-> !push
  ) else $error("Push when full");

  // No pop when empty
  a_no_pop_when_empty: assert property (
    @(posedge clk) disable iff (!rst_n)
    empty |-> !pop
  ) else $error("Pop when empty");

  // Count consistency
  a_count_range: assert property (
    @(posedge clk) disable iff (!rst_n)
    count <= DEPTH
  ) else $error("Count exceeds depth");

  // Full/empty flags
  a_full_flag: assert property (
    @(posedge clk) disable iff (!rst_n)
    (count == DEPTH) == full
  ) else $error("Full flag inconsistent with count");

  a_empty_flag: assert property (
    @(posedge clk) disable iff (!rst_n)
    (count == 0) == empty
  ) else $error("Empty flag inconsistent with count");

  // Coverage
  c_push_pop_simultaneous: cover property (
    @(posedge clk) disable iff (!rst_n)
    push && pop && !full && !empty
  );

  c_full_to_not_full: cover property (
    @(posedge clk) disable iff (!rst_n)
    full ##1 !full
  );

endmodule

// Bind to DUT
bind fifo fifo_assertions #(
  .DEPTH(DEPTH),
  .WIDTH(WIDTH)
) fifo_assert_inst (
  .clk    (clk),
  .rst_n  (rst_n),
  .push   (push),
  .pop    (pop),
  .full   (full),
  .empty  (empty),
  .wdata  (wdata),
  .rdata  (rdata),
  .count  (count)
);

// Bind to specific instance
bind tb.dut.u_fifo fifo_assertions #(
  .DEPTH(16),
  .WIDTH(32)
) fifo_assert_inst (.*);

// Bind to all instances of a module type
bind fifo_module fifo_assertions fifo_chk(.*);
```

### 8.2 Bind Interface

```systemverilog
// Assertion interface checker
interface axi_protocol_checker(
  input logic        ACLK,
  input logic        ARESETn,
  input logic        AWVALID,
  input logic        AWREADY,
  input logic [31:0] AWADDR,
  input logic [7:0]  AWLEN,
  input logic        WVALID,
  input logic        WREADY,
  input logic        WLAST,
  input logic        BVALID,
  input logic        BREADY,
  input logic [1:0]  BRESP
);

  // AW handshake
  aw_handshake: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID && !AWREADY |=> AWVALID
  ) else $error("AWVALID de-asserted without AWREADY");

  aw_stable_addr: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID && !AWREADY |=> $stable(AWADDR)
  ) else $error("AWADDR changed while waiting for AWREADY");

  // W handshake
  w_handshake: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    WVALID && !WREADY |=> WVALID
  ) else $error("WVALID de-asserted without WREADY");

  // B handshake
  b_handshake: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    BVALID && !BREADY |=> BVALID
  ) else $error("BVALID de-asserted without BREADY");

endinterface

// Bind to AXI interface instance
bind axi_if axi_protocol_checker axi_chk(
  .ACLK     (ACLK),
  .ARESETn  (ARESETn),
  .AWVALID  (AWVALID),
  .AWREADY  (AWREADY),
  .AWADDR   (AWADDR),
  .AWLEN    (AWLEN),
  .WVALID   (WVALID),
  .WREADY   (WREADY),
  .WLAST    (WLAST),
  .BVALID   (BVALID),
  .BREADY   (BREADY),
  .BRESP    (BRESP)
);
```

### 8.3 Bind Best Practices

```systemverilog
// Use .* for port connection when names match
bind target_module checker_module checker_inst(.*);

// Use separate file for bind statements
// File: bind_assertions.sv
// Include in compile list after DUT and assertion modules

// Parameterized binding
bind target_module #(.PARAM(target_module.PARAM))
  checker_module checker_inst(.*);

// Hierarchical bind (bind inside specific sub-hierarchy)
bind tb.dut.subsystem.target_module checker_module checker_inst(.*);
```

---

## 9. Common Assertion Patterns

### 9.1 Handshake Protocol Patterns

```systemverilog
// Valid-Ready handshake (AXI-like)
// Once valid is asserted, it must stay until ready
property p_valid_until_ready;
  @(posedge clk) disable iff (!rst_n)
  valid && !ready |=> valid;
endproperty

// Data must be stable while valid and !ready
property p_data_stable;
  @(posedge clk) disable iff (!rst_n)
  valid && !ready |=> $stable(data);
endproperty

// Valid must eventually get ready (liveness)
property p_no_deadlock;
  @(posedge clk) disable iff (!rst_n)
  valid |-> strong(##[0:100] ready);
endproperty

// Request-Grant handshake
property p_req_grant;
  @(posedge clk) disable iff (!rst_n)
  $rose(req) |-> ##[1:MAX_LATENCY] grant;
endproperty

// Grant only when requested
property p_grant_needs_req;
  @(posedge clk) disable iff (!rst_n)
  $rose(grant) |-> req;
endproperty

// Request de-asserted after grant
property p_req_deassert;
  @(posedge clk) disable iff (!rst_n)
  req && grant |=> !req;
endproperty
```

### 9.2 FIFO Assertion Patterns

```systemverilog
// Never push to full FIFO
property p_no_overflow;
  @(posedge clk) disable iff (!rst_n)
  full |-> !push;
endproperty

// Never pop from empty FIFO
property p_no_underflow;
  @(posedge clk) disable iff (!rst_n)
  empty |-> !pop;
endproperty

// Count tracking
property p_count_incr;
  @(posedge clk) disable iff (!rst_n)
  push && !pop && !full |=> count == $past(count) + 1;
endproperty

property p_count_decr;
  @(posedge clk) disable iff (!rst_n)
  pop && !push && !empty |=> count == $past(count) - 1;
endproperty

property p_count_stable;
  @(posedge clk) disable iff (!rst_n)
  (push && pop) || (!push && !pop) |=> $stable(count);
endproperty

// Data integrity
sequence push_data;
  logic [WIDTH-1:0] saved;
  (push && !full, saved = wdata)
  ##[1:DEPTH] (pop && rdata == saved);
endsequence
```

### 9.3 Arbiter Patterns

```systemverilog
// Grant must be one-hot
property p_grant_onehot;
  @(posedge clk) disable iff (!rst_n)
  |grant |-> $onehot(grant);
endproperty

// No grant without request
property p_grant_needs_req;
  @(posedge clk) disable iff (!rst_n)
  grant[i] |-> req[i];
endproperty

// Fairness: if requested, must eventually be granted
property p_fairness(int i, int max_wait);
  @(posedge clk) disable iff (!rst_n)
  req[i] |-> strong(##[0:max_wait] grant[i]);
endproperty

// No starvation
generate
  for (genvar i = 0; i < N; i++) begin
    assert property (p_fairness(i, MAX_WAIT));
  end
endgenerate

// Priority: higher priority granted first
property p_priority;
  @(posedge clk) disable iff (!rst_n)
  req[0] && req[1] |-> grant[0] && !grant[1];
endproperty
```

### 9.4 State Machine Patterns

```systemverilog
// Valid transitions
property p_valid_transition;
  @(posedge clk) disable iff (!rst_n)
  case (state)
    IDLE:   1 |=> (state inside {IDLE, START});
    START:  1 |=> (state inside {ACTIVE, ERROR});
    ACTIVE: 1 |=> (state inside {ACTIVE, DONE, ERROR});
    DONE:   1 |=> (state inside {IDLE});
    ERROR:  1 |=> (state inside {IDLE, ERROR});
    default: 0;  // Illegal state
  endcase
endproperty

// No illegal states
property p_legal_state;
  @(posedge clk) disable iff (!rst_n)
  state inside {IDLE, START, ACTIVE, DONE, ERROR};
endproperty

// Liveness: must eventually leave active state
property p_no_stuck;
  @(posedge clk) disable iff (!rst_n)
  state == ACTIVE |-> strong(##[1:MAX_ACTIVE_CYCLES] state != ACTIVE);
endproperty

// Reset state
property p_reset_state;
  @(posedge clk)
  $rose(rst_n) |=> state == IDLE;
endproperty
```

### 9.5 Memory Interface Patterns

```systemverilog
// Read after write: data consistency
property p_raw_consistency;
  logic [31:0] saved_data;
  logic [31:0] saved_addr;
  @(posedge clk) disable iff (!rst_n)
  (wr_en, saved_data = wr_data, saved_addr = wr_addr)
  ##[1:$] (rd_en && rd_addr == saved_addr)
  |-> ##[RD_LATENCY] (rd_data == saved_data);
endproperty

// No simultaneous read and write to same address
property p_no_rw_conflict;
  @(posedge clk) disable iff (!rst_n)
  wr_en && rd_en |-> wr_addr != rd_addr;
endproperty

// Address alignment
property p_addr_aligned;
  @(posedge clk) disable iff (!rst_n)
  (wr_en || rd_en) |-> (addr[1:0] == 2'b00);  // 32-bit aligned
endproperty
```

### 9.6 Clock Domain Crossing Patterns

```systemverilog
// 2-FF synchronizer output must be stable for at least 1 cycle
property p_sync_stable;
  @(posedge clk_dest) disable iff (!rst_n)
  $changed(sync_out) |=> $stable(sync_out);
endproperty

// Gray code: only one bit changes at a time
property p_gray_code;
  @(posedge clk) disable iff (!rst_n)
  $countones(gray_ptr ^ $past(gray_ptr)) <= 1;
endproperty

// FIFO pointer gray code
property p_fifo_gray_ptr;
  @(posedge wr_clk) disable iff (!rst_n)
  $changed(wr_ptr_gray) |-> $onehot(wr_ptr_gray ^ $past(wr_ptr_gray));
endproperty
```

### 9.7 Bus Protocol Patterns (AXI)

```systemverilog
// AXI Write Channel assertions
module axi_write_assertions(
  input logic        ACLK,
  input logic        ARESETn,
  input logic        AWVALID, AWREADY,
  input logic [31:0] AWADDR,
  input logic [7:0]  AWLEN,
  input logic [2:0]  AWSIZE,
  input logic [1:0]  AWBURST,
  input logic        WVALID, WREADY,
  input logic [31:0] WDATA,
  input logic [3:0]  WSTRB,
  input logic        WLAST,
  input logic        BVALID, BREADY,
  input logic [1:0]  BRESP
);

  // AW channel: valid must stay until ready
  aw_valid_hold: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID && !AWREADY |=> AWVALID
  );

  // AW channel: all signals stable while valid and !ready
  aw_addr_stable: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID && !AWREADY |=> $stable(AWADDR)
  );

  aw_len_stable: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID && !AWREADY |=> $stable(AWLEN)
  );

  aw_size_stable: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID && !AWREADY |=> $stable(AWSIZE)
  );

  aw_burst_stable: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID && !AWREADY |=> $stable(AWBURST)
  );

  // W channel: valid must stay until ready
  w_valid_hold: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    WVALID && !WREADY |=> WVALID
  );

  // W channel: data stable while valid and !ready
  w_data_stable: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    WVALID && !WREADY |=> $stable(WDATA)
  );

  w_strb_stable: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    WVALID && !WREADY |=> $stable(WSTRB)
  );

  w_last_stable: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    WVALID && !WREADY |=> $stable(WLAST)
  );

  // B channel: valid must stay until ready
  b_valid_hold: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    BVALID && !BREADY |=> BVALID
  );

  b_resp_stable: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    BVALID && !BREADY |=> $stable(BRESP)
  );

  // WLAST must be asserted for the last beat
  // (This requires tracking burst length)

  // No X on control signals during valid
  aw_no_x: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID |-> !$isunknown({AWADDR, AWLEN, AWSIZE, AWBURST})
  );

  w_no_x: assert property (
    @(posedge ACLK) disable iff (!ARESETn)
    WVALID |-> !$isunknown(WSTRB) && !$isunknown(WLAST)
  );

  // After reset, valid signals must be low
  aw_reset: assert property (
    @(posedge ACLK)
    !ARESETn |=> !AWVALID
  );

  w_reset: assert property (
    @(posedge ACLK)
    !ARESETn |=> !WVALID
  );

  b_reset: assert property (
    @(posedge ACLK)
    !ARESETn |=> !BVALID
  );

endmodule
```

### 9.8 Interrupt Patterns

```systemverilog
// Interrupt must be acknowledged
property p_intr_ack;
  @(posedge clk) disable iff (!rst_n)
  $rose(intr) |-> strong(##[1:MAX_INTR_LATENCY] intr_ack);
endproperty

// Interrupt de-asserted after acknowledge
property p_intr_clear;
  @(posedge clk) disable iff (!rst_n)
  intr && intr_ack |=> !intr;
endproperty

// Level interrupt: stays asserted until cleared
property p_level_intr;
  @(posedge clk) disable iff (!rst_n)
  intr && !intr_clear |=> intr;
endproperty

// Edge interrupt: pulse for exactly 1 cycle
property p_edge_intr;
  @(posedge clk) disable iff (!rst_n)
  $rose(intr) |=> !intr;
endproperty
```

### 9.9 Data Integrity Patterns

```systemverilog
// Parity check
property p_parity;
  @(posedge clk) disable iff (!rst_n)
  valid |-> ^{data, parity} == 1'b0;  // Even parity
endproperty

// ECC check (single-bit error)
property p_ecc;
  @(posedge clk) disable iff (!rst_n)
  valid |-> (syndrome == 0 || $onehot(syndrome));
endproperty

// CRC check
property p_crc_valid;
  @(posedge clk) disable iff (!rst_n)
  frame_end |-> crc_result == 0;
endproperty

// Data preservation through pipeline
sequence pipeline_data;
  logic [31:0] saved;
  (stage1_valid, saved = stage1_data)
  ##1 (stage2_valid && stage2_data == saved);
endsequence
```

---

## 10. Assertion Coverage

### 10.1 Assertion-Based Coverage

```systemverilog
// Cover property - track temporal sequences
c_normal_flow: cover property (
  @(posedge clk) disable iff (!rst_n)
  req ##[1:3] grant ##[1:5] done
);

// Cover sequence
c_back_pressure: cover sequence (
  @(posedge clk) valid && !ready ##1 valid && !ready ##1 valid && ready
);

// Cover with cross-product
generate
  for (genvar i = 0; i < 4; i++) begin : gen_cover
    cover property (@(posedge clk) req[i] |-> ##[1:10] grant[i]);
  end
endgenerate

// Functional coverage from assertions
bit req_seen, grant_seen;
always @(posedge clk) begin
  if (req) req_seen = 1;
  if (grant) grant_seen = 1;
end

covergroup cg_protocol @(posedge clk);
  cp_req:   coverpoint req;
  cp_grant: coverpoint grant;
  cp_state: coverpoint state;
  cross cp_req, cp_grant, cp_state;
endgroup
```

### 10.2 Assertion Control in Simulation

```systemverilog
// Selective assertion control
module assertion_control;

  // Disable during known violation windows
  initial begin
    // Disable during initialization
    $assertoff(0, tb.dut);
    @(posedge tb.rst_n);
    repeat(5) @(posedge tb.clk);
    $asserton(0, tb.dut);
  end

  // Disable specific assertions during specific tests
  task disable_overflow_check();
    $assertoff(0, tb.dut.u_fifo.a_no_overflow);
  endtask

  task enable_overflow_check();
    $asserton(0, tb.dut.u_fifo.a_no_overflow);
  endtask

endmodule
```

---

## 11. Advanced SVA Techniques

### 11.1 Recursive Properties

```systemverilog
// Check that a counter increments correctly
property p_counter(int expected);
  @(posedge clk) disable iff (!rst_n)
  (count == expected) |=>
    if (enable)
      p_counter((expected + 1) % MAX_COUNT)
    else
      p_counter(expected);
endproperty

assert property (p_counter(0));
```

### 11.2 Auxiliary Code with SVA

```systemverilog
// Use auxiliary signals to track complex behavior
module protocol_checker(input clk, rst_n, req, ack, data);

  // Auxiliary counter
  int outstanding_reqs;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      outstanding_reqs <= 0;
    else if (req && !ack)
      outstanding_reqs <= outstanding_reqs + 1;
    else if (!req && ack)
      outstanding_reqs <= outstanding_reqs - 1;
  end

  // Assert using auxiliary signal
  a_no_overflow: assert property (
    @(posedge clk) disable iff (!rst_n)
    outstanding_reqs <= MAX_OUTSTANDING
  );

  a_no_underflow: assert property (
    @(posedge clk) disable iff (!rst_n)
    outstanding_reqs >= 0
  );

endmodule
```

### 11.3 Generate-Based Assertion Instantiation

```systemverilog
module bus_checker #(parameter N_MASTERS = 4, N_SLAVES = 8)(
  input logic        clk, rst_n,
  input logic [N_MASTERS-1:0] req,
  input logic [N_MASTERS-1:0] grant,
  input logic [N_SLAVES-1:0]  sel
);

  // Per-master assertions
  generate
    for (genvar m = 0; m < N_MASTERS; m++) begin : gen_master
      // Grant implies request
      a_grant_req: assert property (
        @(posedge clk) disable iff (!rst_n)
        grant[m] |-> req[m]
      );

      // Fairness
      a_fairness: assert property (
        @(posedge clk) disable iff (!rst_n)
        req[m] |-> strong(##[0:100] grant[m])
      );
    end
  endgenerate

  // Per-slave assertions
  generate
    for (genvar s = 0; s < N_SLAVES; s++) begin : gen_slave
      // At most one select at a time
      a_one_sel: assert property (
        @(posedge clk) disable iff (!rst_n)
        $onehot0(sel)
      );
    end
  endgenerate

endmodule
```

### 11.4 Let Declarations

```systemverilog
// Let declarations for reusable expressions (SV2012)
module assertions_with_let(input clk, rst_n, a, b, c);

  let valid_input = (a !== 'x) && (b !== 'x) && (c !== 'x);
  let output_match = (result == expected);
  let is_active = (state == ACTIVE) && enable;

  a_valid: assert property (
    @(posedge clk) disable iff (!rst_n)
    is_active |-> valid_input
  );

  a_output: assert property (
    @(posedge clk) disable iff (!rst_n)
    done |-> output_match
  );

endmodule
```

### 11.5 Checker Construct (SV2012)

```systemverilog
// Checker: reusable assertion package with internal state
checker fifo_checker(
  logic clk, rst_n, push, pop, full, empty,
  int unsigned count, int unsigned DEPTH
);

  default clocking @(posedge clk); endclocking
  default disable iff (!rst_n);

  // Internal state for tracking
  int unsigned model_count = 0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      model_count <= 0;
    else if (push && !pop && !full)
      model_count <= model_count + 1;
    else if (pop && !push && !empty)
      model_count <= model_count - 1;
  end

  // Assertions
  a1: assert property (full  |-> !push);
  a2: assert property (empty |-> !pop);
  a3: assert property (count == model_count);
  a4: assert property (count <= DEPTH);
  a5: assert property ((count == DEPTH) == full);
  a6: assert property ((count == 0)     == empty);

  // Coverage
  c1: cover property (push && pop && !full && !empty);
  c2: cover property ($rose(full));
  c3: cover property ($rose(empty));

endchecker

// Instantiate checker
fifo_checker fifo_chk(
  .clk(clk), .rst_n(rst_n),
  .push(push), .pop(pop),
  .full(full), .empty(empty),
  .count(count), .DEPTH(16)
);
```

---

## 12. SVA for Formal Verification

### 12.1 Formal-Specific Considerations

```systemverilog
// Assume: constrain formal tool's input space
// In formal: assume = truth
// In simulation: assume = assertion

// Environment constraints
assume property (@(posedge clk) $onehot0(req));
assume property (@(posedge clk) !$isunknown(data));
assume property (@(posedge clk) addr < MEM_SIZE);

// Reset constraint
assume property (@(posedge clk)
  $rose(rst_n) |-> $past(!rst_n, 5)
);

// Restrict: formal-only constraint (ignored in simulation)
restrict property (@(posedge clk)
  $fell(rst_n) |-> ##[5:20] $rose(rst_n)
);

// Cover: prove reachability
cover property (@(posedge clk) disable iff (!rst_n)
  state == IDLE ##[1:100] state == DONE
);
```

### 12.2 Formal-Friendly Assertion Patterns

```systemverilog
// Bounded liveness (preferred over unbounded for formal)
property p_bounded_liveness;
  @(posedge clk) disable iff (!rst_n)
  req |-> ##[1:MAX_CYCLES] ack;  // Bounded
endproperty

// vs unbounded (may cause formal tools to struggle)
property p_unbounded_liveness;
  @(posedge clk) disable iff (!rst_n)
  req |-> strong(##[1:$] ack);  // Unbounded
endproperty

// State space reduction: helper assumptions
assume property (@(posedge clk) disable iff (!rst_n)
  config_reg == EXPECTED_CONFIG  // Reduce state space for focused check
);

// Induction helpers
property p_invariant;
  @(posedge clk) disable iff (!rst_n)
  (ptr >= 0) && (ptr < DEPTH);  // Inductive invariant
endproperty
```

---

## 13. SVA Debug and Methodology

### 13.1 Assertion Naming Convention

```systemverilog
// Recommended naming:
// a_  prefix for assert property
// c_  prefix for cover property
// as_ prefix for assume property
// r_  prefix for restrict property

// Descriptive names
a_fifo_no_overflow:   assert property (...);
a_axi_aw_handshake:   assert property (...);
c_burst_max_length:   cover  property (...);
as_valid_input_range: assume property (...);
```

### 13.2 Assertion Severity and Actions

```systemverilog
// Severity levels in fail actions
a_critical: assert property (@(posedge clk) ...)
  else $fatal(1, "Critical protocol violation");

a_error: assert property (@(posedge clk) ...)
  else $error("Protocol error detected");

a_warning: assert property (@(posedge clk) ...)
  else $warning("Unexpected but non-fatal condition");

a_info: assert property (@(posedge clk) ...)
  else $info("Informational: unusual pattern seen");

// Custom fail action
a_with_debug: assert property (@(posedge clk) valid |-> !$isunknown(data))
  else begin
    $error("X detected on data bus");
    $display("  Time: %0t, State: %s, Addr: 0x%h", $time, state.name(), addr);
    // Optionally force simulation stop for debug
    // $stop;
  end
```

### 13.3 Debugging Failed Assertions

```
1. Check assertion waveform in viewer (Verdi, DVE, SimVision)
2. Look at antecedent activation time
3. Trace consequent evaluation
4. Check disable iff condition
5. Verify clock activity
6. Check for X/Z on sampled signals
7. Review vacuous pass vs genuine pass
8. Use $assertpasson / $assertpassoff to track passing assertions
```

---
