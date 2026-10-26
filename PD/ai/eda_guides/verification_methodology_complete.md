# Complete Verification Methodology Guide

Comprehensive reference covering the end-to-end verification process: planning,
testbench architecture, stimulus strategies, checking, coverage, regression,
bug tracking, sign-off, and reuse.

---

## 1. Verification Planning

### 1.1 Feature Extraction

Feature extraction is the process of deriving verifiable features from
specifications, architecture documents, and design intent.

**Sources of Features:**
- Architecture specification
- Microarchitecture document
- Interface protocol specifications (AMBA, PCIe, USB, etc.)
- Timing diagrams and waveform specifications
- Power intent documents (UPF/CPF)
- Exception and error handling documentation
- Performance requirements
- Design review meeting notes

**Feature Categories:**

| Category | Description | Examples |
|----------|-------------|---------|
| Functional | Core design functionality | Data path operations, control logic, state machines |
| Protocol | Interface compliance | AXI handshake, read/write ordering, burst support |
| Error | Error detection/handling | ECC correction, parity errors, timeout recovery |
| Performance | Throughput/latency | Bandwidth targets, latency bounds, pipeline stalls |
| Power | Low-power behavior | Clock gating, power down, retention, isolation |
| Config | Register programming | CSR access, mode switching, reset values |
| Security | Security features | Access control, encryption, secure boot |
| Corner | Boundary/edge conditions | FIFO full/empty, counter rollover, max burst |
| Interrupt | Interrupt behavior | Assertion, clearing, masking, priority |
| Reset | Reset behavior | Sync/async reset, partial reset, warm reset |

**Feature Extraction Process:**
1. Read specification section by section.
2. Identify nouns (objects/entities) and verbs (operations/behaviors).
3. For each operation, identify:
   - Normal case
   - Boundary conditions
   - Error conditions
   - Concurrent/overlapping scenarios
4. Map features to design blocks and interfaces.
5. Assign priority (P0 = must test, P1 = should test, P2 = nice to test).
6. Review with design team for completeness.

### 1.2 Testplan Structure

A testplan documents what needs to be verified, how it will be verified, and
the expected coverage.

```
Testplan Hierarchy:
  Feature Area
    +-- Feature
        +-- Sub-feature
            +-- Test Scenario
                +-- Expected Result
                +-- Coverage Metric
                +-- Priority
```

**Testplan Template:**

```
Feature Area: DMA Controller
Feature:      Channel Configuration
Sub-feature:  Source Address Programming

Test Scenarios:
  1. Write source address register via APB
     - Expected: Register reflects written value
     - Coverage: All bit positions exercised
     - Priority: P0

  2. Read-back source address after programming
     - Expected: Read value matches written value
     - Coverage: Read-after-write for all channels
     - Priority: P0

  3. Source address alignment check
     - Expected: Unaligned address triggers error
     - Coverage: Aligned and unaligned addresses
     - Priority: P1

  4. Source address change during active transfer
     - Expected: Transfer uses address at start
     - Coverage: Address change timing
     - Priority: P1
```

**Testplan Coverage Model Mapping:**

Each feature should map to one or more coverage items:

| Feature | Verification Method | Coverage Metric |
|---------|-------------------|-----------------|
| Basic read/write | Directed test | Functional coverpoint |
| Random burst | CRT | Cross coverage |
| Error injection | Callback/error seq | Assertion coverage |
| Power down | Directed + UPF | Power state coverage |
| Performance | Performance monitor | Latency histogram |

### 1.3 Coverage Model Design

Coverage models translate testplan features into measurable metrics.

**Coverage Types to Plan:**

1. **Code Coverage** (automatic from tools):
   - Statement coverage
   - Branch coverage
   - Condition coverage
   - Toggle coverage
   - FSM coverage (state + transition)

2. **Functional Coverage** (manually defined):
   - Covergroups and coverpoints
   - Cross coverage
   - Transition coverage
   - Assertion coverage

3. **Protocol Coverage** (from VIPs or checkers):
   - Transaction type coverage
   - Error response coverage
   - Ordering coverage

**Coverage Model Example:**

```systemverilog
covergroup cg_dma_transfer @(posedge clk iff transfer_done);
  // Transfer type
  cp_direction: coverpoint cfg.direction {
    bins read  = {DMA_READ};
    bins write = {DMA_WRITE};
  }

  // Transfer size
  cp_size: coverpoint cfg.size {
    bins byte_xfer     = {SIZE_1B};
    bins halfword_xfer = {SIZE_2B};
    bins word_xfer     = {SIZE_4B};
    bins dword_xfer    = {SIZE_8B};
  }

  // Burst length
  cp_burst_len: coverpoint cfg.burst_len {
    bins single     = {1};
    bins short      = {[2:4]};
    bins medium     = {[5:16]};
    bins long       = {[17:64]};
    bins max        = {[65:256]};
  }

  // Address alignment
  cp_alignment: coverpoint cfg.src_addr[2:0] {
    bins aligned   = {3'b000};
    bins unaligned = {[3'b001:3'b111]};
  }

  // Channel
  cp_channel: coverpoint cfg.channel_id {
    bins ch[] = {[0:NUM_CHANNELS-1]};
  }

  // Cross coverage
  cx_dir_size: cross cp_direction, cp_size;
  cx_dir_burst: cross cp_direction, cp_burst_len;
  cx_chan_dir: cross cp_channel, cp_direction;
  cx_full: cross cp_direction, cp_size, cp_burst_len, cp_alignment;
endgroup
```

---

## 2. Testbench Architecture

### 2.1 Block-Level Testbench

Block-level testbenches verify individual design blocks in isolation.

```
                    +--------------------------------------------------+
                    |                   TEST                            |
                    +--------------------------------------------------+
                    |                   ENV                             |
                    |  +--------+   +-----------+   +--------+         |
                    |  | Agent  |   | Scoreboard|   |Coverage|         |
                    |  |+------+|   |           |   |        |         |
                    |  ||Sqr   ||   |  Expected |   |  Func  |         |
                    |  ||Driver||   |  vs       |   |  Cov   |         |
                    |  ||Monitor|   |  Actual   |   |        |         |
                    |  |+------+|   +-----------+   +--------+         |
                    |  +---||---+                                      |
                    +------||----------------------------------------------+
                           ||
                    +------||------+
                    |     DUT      |
                    |              |
                    +--------------+
```

**Components:**
- **Test**: Configures environment, selects sequences, defines overrides.
- **Environment**: Instantiates agents, scoreboards, coverage collectors.
- **Agent**: Contains sequencer, driver, monitor for one interface.
- **Scoreboard**: Compares expected vs actual behavior.
- **Coverage**: Functional coverage collection and reporting.
- **Reference Model**: Golden model for comparison (optional).

### 2.2 Subsystem-Level Testbench

Subsystem-level testbenches verify interconnected blocks.

```
                    +--------------------------------------------------+
                    |                   TEST                            |
                    +--------------------------------------------------+
                    |                SUBSYSTEM ENV                      |
                    |  +--------+   +--------+   +-----------+         |
                    |  |AXI Agt |   |APB Agt |   |Intr Agent |         |
                    |  +---||---+   +---||---+   +----||-----+         |
                    |      ||           ||             ||               |
                    |  +-Virtual Sequencer-+   +Subsystem Scoreboard+  |
                    |  +-------------------+   +--------------------+  |
                    +------||----------||----------||------------------+
                           ||          ||          ||
                    +------||----------||----------||--+
                    |          SUBSYSTEM DUT            |
                    |  +-------+  +-------+  +-------+ |
                    |  |Block A|  |Block B|  |Block C| |
                    |  +-------+  +-------+  +-------+ |
                    +----------------------------------+
```

**Key Differences from Block-Level:**
- Multiple agents for different interfaces.
- Virtual sequencer coordinates sequences across agents.
- Subsystem scoreboard understands inter-block interactions.
- May include passive agents for monitoring internal interfaces.
- Reference model complexity increases significantly.

### 2.3 Chip-Level Testbench

Chip-level testbenches verify the full SoC/ASIC.

```
                    +----------------------------------------------------------+
                    |                      CHIP-LEVEL TEST                      |
                    +----------------------------------------------------------+
                    |                      CHIP-LEVEL ENV                       |
                    |  +--------+ +--------+ +--------+ +--------+ +--------+  |
                    |  |AXI VIP | |DDR VIP | |PCIe VIP| |UART Agt| |GPIO Agt|  |
                    |  +---||---+ +---||---+ +---||---+ +---||---+ +---||---+  |
                    |      ||         ||         ||         ||         ||       |
                    |  +-----------Virtual Sequencer------------------+         |
                    |  +Chip Scoreboard+ +Reg Model+ +System Monitor+          |
                    +------||----||-----||---||---||------||------||------------+
                           ||    ||     ||   ||   ||      ||      ||
                    +------||----||-----||---||---||------||------||--+
                    |                    CHIP DUT                      |
                    |  CPU + Memory + Peripherals + Interconnect       |
                    +--------------------------------------------------+
```

**Chip-Level Considerations:**
- Real or behavioral CPU model.
- Multiple protocol VIPs (AXI, PCIe, DDR, USB, etc.).
- Register model for all chip registers.
- Power-aware simulation (UPF).
- Clock generation with real PLLs or behavioral models.
- System-level scenarios (boot, interrupt handling, DMA).
- Performance monitoring and analysis.

### 2.4 Testbench Infrastructure Components

**Clock and Reset Generator:**

```systemverilog
class clock_reset_gen extends uvm_component;
  virtual clk_rst_if vif;

  // Configurable parameters
  real clk_period  = 10.0;  // ns
  real clk_duty    = 0.5;
  int  reset_cycles = 10;
  bit  async_reset  = 0;

  task run_phase(uvm_phase phase);
    fork
      generate_clock();
      generate_reset();
    join_none
  endtask

  task generate_clock();
    vif.clk = 0;
    forever begin
      #(clk_period * clk_duty * 1ns) vif.clk = ~vif.clk;
      #(clk_period * (1.0 - clk_duty) * 1ns) vif.clk = ~vif.clk;
    end
  endtask

  task generate_reset();
    vif.rst_n = 0;
    if (async_reset) #(3.7ns);  // Async: not aligned to clock
    else repeat(reset_cycles) @(posedge vif.clk);
    vif.rst_n = 1;
  endtask
endclass
```

**Watchdog Timer:**

```systemverilog
class watchdog extends uvm_component;
  time timeout_val = 1ms;

  task run_phase(uvm_phase phase);
    fork
      begin
        #timeout_val;
        `uvm_fatal("WATCHDOG", $sformatf("Simulation timed out after %0t", timeout_val))
      end
    join_none
  endtask
endclass
```

---

## 3. Stimulus Generation

### 3.1 Directed Tests

Hand-written tests that target specific scenarios.

**When to Use:**
- Initial bring-up and sanity checks.
- Specific corner cases difficult to hit randomly.
- Deterministic scenarios for debug.
- Protocol compliance tests from spec.
- Performance benchmarks.

**Pattern:**

```systemverilog
class directed_write_read_test extends base_test;
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Directed write
    write_transaction(32'h0000_0100, 32'hDEAD_BEEF);

    // Directed read and check
    read_and_check(32'h0000_0100, 32'hDEAD_BEEF);

    // Specific corner case: write to last address
    write_transaction(32'hFFFF_FFFC, 32'h1234_5678);
    read_and_check(32'hFFFF_FFFC, 32'h1234_5678);

    phase.drop_objection(this);
  endtask
endclass
```

### 3.2 Constrained Random Tests (CRT)

Automated stimulus generation using SystemVerilog constraints.

**Constraint Strategies:**

```systemverilog
class smart_transaction extends base_transaction;
  // Basic constraints
  constraint c_addr_range {
    addr inside {[ADDR_MIN : ADDR_MAX]};
  }

  // Weighted distribution
  constraint c_size_dist {
    size dist {
      SIZE_1B  := 10,
      SIZE_2B  := 20,
      SIZE_4B  := 50,
      SIZE_8B  := 20
    };
  }

  // Conditional constraints
  constraint c_write_data {
    if (cmd == WRITE) {
      data != 0;
      data != '1;
    }
  }

  // Iterative constraints
  constraint c_unique_addr {
    foreach (addr_queue[i])
      addr != addr_queue[i];
  }

  // Solve order
  constraint c_order {
    solve cmd before data;
    solve size before addr;
  }

  // Soft constraints (can be overridden)
  constraint c_default_delay {
    soft delay inside {[1:5]};
  }
endclass

// Override soft constraints in test
class stress_test extends base_test;
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Override soft constraint
    smart_transaction tr;
    tr = smart_transaction::type_id::create("tr");
    assert(tr.randomize() with {
      delay == 0;  // Overrides soft constraint for back-to-back
    });

    phase.drop_objection(this);
  endtask
endclass
```

**Constraint Layering:**

```systemverilog
// Base constraint (always active)
class base_config extends uvm_object;
  rand int unsigned burst_len;
  constraint c_base { burst_len inside {[1:256]}; }
endclass

// Narrow constraint (for specific test)
class short_burst_config extends base_config;
  constraint c_short { burst_len inside {[1:4]}; }
endclass

// Corner constraint
class boundary_config extends base_config;
  constraint c_boundary { burst_len inside {1, 128, 255, 256}; }
endclass
```

### 3.3 Hybrid Approach

Combining directed and random for optimal coverage.

**Strategy:**

1. **Phase 1 - Directed bring-up:**
   - Basic read/write
   - Reset behavior
   - Register access
   - Sanity sequences

2. **Phase 2 - Constrained random:**
   - Random traffic with broad constraints
   - Multi-stream random sequences
   - Error injection with random timing

3. **Phase 3 - Targeted random:**
   - Constrained random targeting coverage holes
   - Scenario-specific random sequences
   - Corner-case random with tight constraints

4. **Phase 4 - Stress/corner:**
   - Back-to-back transactions
   - Maximum concurrency
   - Resource exhaustion
   - Long-running stability

### 3.4 Stimulus Patterns

**Traffic Patterns:**

| Pattern | Description | Use Case |
|---------|-------------|----------|
| Sequential | Address increment by fixed amount | Memory walk |
| Random | Random addresses and data | General coverage |
| Strided | Fixed stride through address space | Cache line testing |
| Ping-pong | Alternating between two addresses | RAW hazard |
| Burst | Consecutive addresses, variable length | DMA, cache fill |
| Scatter-gather | Random addresses, same data | Memory coherence |
| Walking ones | Single bit set, shifted each iteration | Connectivity |
| Checkerboard | Alternating 0/1 pattern | Signal integrity |
| All-ones/All-zeros | Extreme values | Corner cases |
| Back-to-back | Zero delay between transactions | Pipeline stress |

---

## 4. Checking Strategy

### 4.1 Scoreboard Approaches

**Approach 1: Reference Model Scoreboard**

```
Monitor(input) -> Reference Model -> Expected Queue
Monitor(output) -> Actual Queue
                 -> Comparator -> Pass/Fail
```

The reference model processes input transactions and predicts expected output.
The comparator matches expected vs actual.

**Approach 2: Transaction-by-Transaction Check**

Each output transaction is checked individually against expected behavior:
- Correct data values
- Correct timing (latency)
- Correct ordering
- Correct error responses

**Approach 3: End-to-End Check**

Compare final state (memory contents, register values) after a sequence of
operations, rather than checking each transaction.

**Scoreboard Design Guidelines:**
- Support out-of-order completion when protocol allows it.
- Handle dropped/lost transactions with timeout.
- Log all mismatches with full context (time, values, state).
- Report residual expected transactions at end of test.
- Provide statistics: match count, mismatch count, total count.

### 4.2 Self-Checking Assertions

Assertions embedded in or bound to the DUT provide continuous checking.

**Assertion Categories:**

| Category | Scope | Example |
|----------|-------|---------|
| Protocol | Interface | Valid/ready handshake rules |
| Structural | Internal | One-hot state encoding |
| Behavioral | Functional | Counter increment logic |
| Temporal | Timing | Maximum latency bounds |
| Data Integrity | Data path | Parity/ECC check |
| Safety | Critical | Mutex exclusion |
| Liveness | Progress | No deadlock/starvation |

### 4.3 Protocol Checkers

Protocol checkers verify interface protocol compliance:

```systemverilog
module axi_protocol_checker #(
  parameter ADDR_W = 32,
  parameter DATA_W = 64,
  parameter ID_W   = 4
)(
  input logic ACLK, ARESETn,
  // AW channel
  input logic AWVALID, AWREADY,
  // ... all AXI signals
);
  // Handshake rules (per channel)
  // Ordering rules (read/write interleaving)
  // Burst rules (length, size, type constraints)
  // Exclusive access rules
  // Response rules
  // Reset rules
endmodule
```

### 4.4 Data Integrity Checks

```
Methods:
1. Write-Read-Compare: Write data, read back, compare
2. Shadow Memory: Maintain software model of memory contents
3. Checksum/CRC: Verify data integrity through checksums
4. Sequence Number: Tag transactions and verify ordering
5. Signature: Compute and compare data signatures
```

### 4.5 End-of-Test Checks

```systemverilog
function void check_phase(uvm_phase phase);
  // 1. Scoreboard residual check
  if (scoreboard.has_pending())
    `uvm_error("EOT", "Scoreboard has pending transactions")

  // 2. FIFO empty check
  if (!dut_if.fifo_empty)
    `uvm_error("EOT", "DUT FIFO not empty at end of test")

  // 3. State machine idle check
  if (dut_if.state != IDLE)
    `uvm_error("EOT", $sformatf("DUT not in IDLE state: %s", dut_if.state.name()))

  // 4. Error counter check
  if (dut_if.error_count > 0)
    `uvm_error("EOT", $sformatf("DUT error count = %0d", dut_if.error_count))

  // 5. Memory consistency check
  verify_memory_contents();
endfunction
```

---

## 5. Coverage Strategy

### 5.1 Code Coverage

Code coverage is automatically collected by the simulator.

**Coverage Types:**

| Type | What it Measures | Goal |
|------|-----------------|------|
| Statement | Each executable line | 100% (after exclusions) |
| Branch | Each if/else, case branch | 100% |
| Condition | Each boolean sub-expression | 95%+ |
| Toggle | Each bit 0->1 and 1->0 | 95%+ |
| FSM State | Each state visited | 100% |
| FSM Transition | Each state-to-state transition | 95%+ |
| Expression | All truth table combinations | 90%+ |

**Code Coverage Analysis:**
- Unreachable code should be excluded with justification.
- Dead code indicates design or spec issues.
- Low toggle coverage on specific bits may indicate incomplete testing.

### 5.2 Functional Coverage

Functional coverage is defined by the verification engineer to track testplan
completion.

**Covergroup Best Practices:**

```systemverilog
// 1. Use meaningful bin names
coverpoint cmd {
  bins read_ops  = {CMD_READ, CMD_READ_BURST};
  bins write_ops = {CMD_WRITE, CMD_WRITE_BURST};
  bins config_op = {CMD_CONFIG};
  illegal_bins illegal = default;
}

// 2. Use auto_bin_max for large ranges
coverpoint addr {
  option.auto_bin_max = 16;  // 16 auto-bins across range
}

// 3. Transition coverage for state machines
coverpoint state {
  bins idle_to_active = (IDLE => ACTIVE);
  bins active_to_done = (ACTIVE => DONE);
  bins done_to_idle   = (DONE => IDLE);
  bins error_recovery = (ERROR => IDLE);
  illegal_bins bad    = (IDLE => DONE);  // Should not happen
}

// 4. Cross coverage for interactions
cross cp_cmd, cp_size, cp_channel {
  // Ignore impossible combinations
  ignore_bins impossible = binsof(cp_cmd) intersect {CMD_CONFIG}
                          && binsof(cp_size) intersect {SIZE_BURST};
}

// 5. Sample at meaningful events
covergroup cg_transfer @(transfer_complete);  // Sample when transfer completes
  // ...
endgroup

// 6. Conditional sampling
covergroup cg_error @(posedge clk iff error_valid);
  cp_err_type: coverpoint error_type;
  cp_err_addr: coverpoint error_addr { option.auto_bin_max = 8; }
endgroup
```

### 5.3 Assertion Coverage

Track assertion activity:

```systemverilog
// Cover properties
c_normal_flow: cover property (@(posedge clk) req |-> ##[1:3] ack);
c_max_latency: cover property (@(posedge clk) req |-> ##10 ack);  // Max latency hit
c_back_to_back: cover property (@(posedge clk) ack |=> req);      // Back-to-back

// Assertion pass/fail tracking
// Most tools report: attempts, passes, failures, vacuous passes
```

### 5.4 Coverage Closure Methodology

```
Coverage Closure Flow:
1. Run initial regression (random seeds)
2. Merge coverage across all tests
3. Analyze coverage holes:
   a. Code coverage: identify untested code paths
   b. Functional coverage: identify missed scenarios
   c. Assertion coverage: identify unexercised properties
4. For each hole, determine:
   a. Is it unreachable? -> Add exclusion with justification
   b. Is it a missing test? -> Write targeted test/constraint
   c. Is it a coverage model error? -> Fix coverage model
5. Run new/modified tests
6. Repeat until targets met
7. Final review of all exclusions
```

**Coverage Hole Analysis:**

| Hole Type | Root Cause | Action |
|-----------|-----------|--------|
| Unreachable code | Dead code in RTL | Exclude + file bug |
| Missed FSM state | State not reachable with current constraints | Add directed test |
| Uncovered cross bin | Rare combination | Add targeted constraint |
| Unexercised assertion | Scenario never triggered | Add scenario sequence |
| Low toggle coverage | Signal not fully exercised | Review data patterns |

---

## 6. Regression Management

### 6.1 Regression Infrastructure

**Test Suite Organization:**

```
regression/
  sanity/          # Quick smoke tests (< 5 min)
    test_list.f
  nightly/         # Full regression (4-8 hours)
    test_list.f
  weekly/          # Extended regression (24-48 hours)
    test_list.f
  targeted/        # Specific feature tests
    dma_tests.f
    interrupt_tests.f
    error_tests.f
  stress/          # Long-running stress tests
    test_list.f
```

**Test List Format:**

```
# test_name  seed  options  timeout
basic_read_write    random  +num_trans=100   1m
burst_transfer      random  +burst_mode=1    5m
error_injection     12345   +err_rate=10     10m
stress_test         random  +num_trans=10000 30m
corner_case_1       54321   +corner_mode=1   5m
```

### 6.2 Seed Management

```
Seed Strategy:
1. Each test runs with a random seed by default
2. Failing tests are re-run with the same seed for debug
3. Interesting seeds (coverage hits) are saved and replayed
4. Regression uses both random and saved seeds
5. Seed database tracks:
   - Seed value
   - Test name
   - Pass/fail status
   - Coverage contribution
   - Discovery date
```

**Seed Database Fields:**

| Field | Description |
|-------|-------------|
| seed_value | Random seed used |
| test_name | Test that ran |
| status | PASS / FAIL / TIMEOUT |
| coverage_delta | New coverage contribution |
| first_seen | Date first run |
| fail_signature | Hash of failure message (for grouping) |
| notes | Engineer notes |

### 6.3 Test Selection and Prioritization

**Selection Criteria:**

1. **Sanity first:** Run quick sanity tests before full regression.
2. **Coverage-driven:** Prioritize tests that historically add new coverage.
3. **Change-driven:** Run tests related to recent RTL changes.
4. **Bug-driven:** Re-run tests related to recently fixed bugs.
5. **Random exploration:** Include random seeds for new coverage discovery.

**Seed Coverage Ranking:**

```
1. Run N random seeds
2. Measure incremental coverage contribution of each seed
3. Rank seeds by contribution
4. Select top-K seeds for regression (covers most with fewest tests)
5. Add M new random seeds for exploration
6. Repeat periodically as design evolves
```

### 6.4 Regression Results Analysis

```
Daily Regression Dashboard:
---------------------------
Total tests:      500
Passed:           485 (97.0%)
Failed:           10  (2.0%)
Timeout:          3   (0.6%)
Infrastructure:   2   (0.4%)

New failures:     3
Known failures:   7
Regressions:      1

Coverage Summary:
  Code coverage:      92.3%  (+0.2% from yesterday)
  Functional coverage: 87.5%  (+0.5%)
  Assertion coverage:  95.1%  (+0.1%)

Failure Breakdown:
  Bug #1234 (known):   4 tests
  Bug #1256 (known):   3 tests
  NEW: Timeout in stress_test: 2 tests
  Infra: Disk full: 1 test
```

### 6.5 Failure Triage

**Triage Process:**

```
1. Categorize failure:
   a. Infrastructure (disk, license, compute)
   b. Testbench bug
   c. RTL bug (regression / new)
   d. Known issue

2. For RTL bugs:
   a. Reproduce with same seed
   b. Minimize test (reduce transactions)
   c. Identify root cause
   d. File bug with:
      - Failing test + seed
      - Waveform
      - Root cause analysis
      - Severity assessment

3. For testbench bugs:
   a. Fix testbench
   b. Verify fix doesn't mask real bugs
   c. Re-run affected tests

4. For known issues:
   a. Link to existing bug
   b. Verify failure signature matches
   c. Update bug with new info if needed
```

### 6.6 Regression Automation

```
Regression Flow:
1. Check out latest RTL and testbench
2. Compile design and testbench
3. Run sanity tests
4. If sanity passes, launch full regression
5. Monitor progress, detect hangs
6. Collect results and merge coverage
7. Generate reports
8. Notify team of results
9. Triage new failures
```

---

## 7. Bug Tracking

### 7.1 Bug Report Template

```
Bug ID:          BUG-XXXX
Title:           [Block] Brief description of issue
Reporter:        Name
Date Found:      YYYY-MM-DD
Severity:        P0/P1/P2/P3
Priority:        Critical/High/Medium/Low
Status:          New/Open/Fixed/Verified/Closed/Deferred
Assigned To:     Name

Environment:
  RTL Version:   commit hash or tag
  TB Version:    commit hash or tag
  Tool Version:  VCS/Xcelium version
  Platform:      Linux/OS version

Reproduction:
  Test Name:     test_xyz
  Seed:          12345
  Run Command:   make run TEST=test_xyz SEED=12345
  Failing Time:  12345ns

Description:
  What happened vs what was expected

Root Cause:
  Analysis of why the bug occurred

Fix:
  Description of fix applied

Verification:
  How the fix was verified
  Regression results after fix
```

### 7.2 Severity Classification

| Severity | Description | Example |
|----------|-------------|---------|
| P0 - Blocker | System crash, data corruption, security breach | Wrong data output, deadlock |
| P1 - Critical | Major feature broken, no workaround | DMA transfer fails for burst > 16 |
| P2 - Major | Feature broken with workaround | Performance 10% below target |
| P3 - Minor | Cosmetic, documentation, minor deviation | Unused register bit behavior |

### 7.3 Bug Trends and Metrics

**Key Metrics:**

| Metric | Description | Target |
|--------|-------------|--------|
| Bug find rate | New bugs per week | Decreasing over time |
| Bug fix rate | Bugs fixed per week | Should exceed find rate |
| Open bug count | Total open bugs | Decreasing to 0 at signoff |
| Bug age | Days from open to close | < 14 days for P0/P1 |
| Regression rate | Fixed bugs that reappear | 0% |
| Bug density | Bugs per KLOC | < 1 at signoff |

**Bug Rate Curve:**

```
Bugs/week
  ^
  |     __
  |    /  \
  |   /    \__
  |  /        \___
  | /              \____
  |/                    \________
  +---------------------------------> Time
  Start   Mid    Pre-Sign-off  Signoff
```

A healthy verification effort shows:
- Rising bug discovery rate early (ramping up testing).
- Peak bug rate during mid-verification.
- Declining bug rate as design stabilizes.
- Near-zero bug rate at signoff.

### 7.4 Root Cause Analysis

**Common Root Causes:**

| Root Cause | % Typical | Prevention |
|-----------|-----------|------------|
| Spec ambiguity | 15% | Spec review, early prototyping |
| Logic error | 25% | Code review, assertions |
| Corner case missed | 20% | Constrained random, coverage |
| Integration issue | 15% | Integration tests, protocol checks |
| Reset handling | 10% | Reset assertions, directed tests |
| Clock domain | 10% | CDC analysis, formal CDC |
| Power | 5% | PA simulation, UPF review |

### 7.5 Regression Prevention

For each fixed bug, add:
1. **Directed regression test** targeting the specific scenario.
2. **Assertion** catching the bug condition.
3. **Coverage point** ensuring the scenario is exercised.
4. **Code review checklist item** for similar patterns.

---

## 8. Sign-Off Criteria

### 8.1 Coverage Targets

| Coverage Type | Target | Minimum |
|--------------|--------|---------|
| Statement | 100% | 95% |
| Branch | 100% | 95% |
| Condition | 95% | 90% |
| Toggle (functional) | 95% | 90% |
| FSM State | 100% | 100% |
| FSM Transition | 95% | 90% |
| Functional | 100% | 95% |
| Assertion (attempted) | 100% | 95% |

### 8.2 Exclusion Requirements

All code coverage exclusions must be documented with:
1. Exclusion file checked into version control.
2. Justification for each exclusion (dead code, test limitation, etc.).
3. Review and approval by lead engineer.
4. Cross-reference to design documentation.

### 8.3 Bug Rate Trending

Sign-off requires:
- Bug discovery rate below threshold (e.g., < 1 new bug per week for 2 weeks).
- No open P0 or P1 bugs.
- All P2 bugs reviewed and disposition documented (fix or waive).
- Bug regression tests all passing.

### 8.4 Regression Stability

- All tests in regression passing for N consecutive runs (typically 3-5).
- No intermittent failures unresolved.
- Infrastructure failures < 1% of total runs.

### 8.5 Risk Assessment

| Risk Category | Assessment | Mitigation |
|--------------|------------|------------|
| Untested features | List features not covered | Add tests or document risk |
| Coverage holes | List uncovered bins | Justify or add tests |
| Known limitations | Document known issues | Impact analysis |
| Tool limitations | Document tool issues | Workarounds |
| Schedule pressure | Impact on coverage/testing | Prioritize P0/P1 features |

### 8.6 Sign-Off Checklist

```
[ ] All testplan features have at least one test
[ ] Code coverage meets targets (after justified exclusions)
[ ] Functional coverage meets targets
[ ] All assertion coverage attempted
[ ] No open P0/P1 bugs
[ ] Bug rate trending below threshold for N weeks
[ ] Regression stable for N consecutive runs
[ ] Coverage exclusions reviewed and approved
[ ] CDC analysis clean (or waivers justified)
[ ] Formal verification properties all proven
[ ] Gate-level simulation clean
[ ] Power-aware simulation clean
[ ] Performance targets met
[ ] Sign-off review meeting held
[ ] Sign-off document approved by project lead
```

---

## 9. Reuse Strategy

### 9.1 VIP Reuse

Verification IPs (VIPs) provide reusable protocol-specific agents:

**Reuse Hierarchy:**

```
Reuse Level:
  1. Transaction class (sequence item)
  2. Driver/Monitor (signal-level)
  3. Agent (full driver + monitor + sequencer)
  4. Sequences (reusable stimulus patterns)
  5. Environment (full testbench sub-environment)
  6. Test (base test class with common setup)
```

### 9.2 Agent Reuse Guidelines

```
Reusable Agent Checklist:
[ ] Parameterized for data width, address width
[ ] Configurable active/passive mode
[ ] Configuration object with all tunables
[ ] Virtual interface used (not direct hierarchy)
[ ] Factory registration for all classes
[ ] Coverage can be enabled/disabled via config
[ ] Protocol assertions can be enabled/disabled
[ ] No hardcoded constants (all parameterized)
[ ] UVM macros used consistently
[ ] Documentation: README with integration guide
[ ] Example testbench included
```

### 9.3 Sequence Reuse

```systemverilog
// Reusable base sequence with common functionality
class base_traffic_sequence extends uvm_sequence #(my_transaction);
  // Configurable parameters
  rand int unsigned num_transactions;
  rand int unsigned min_delay, max_delay;
  rand bit [31:0]   addr_min, addr_max;

  constraint c_defaults {
    soft num_transactions inside {[10:100]};
    soft min_delay inside {[0:5]};
    soft max_delay inside {[5:20]};
    soft addr_min == 0;
    soft addr_max == 32'hFFFF_FFFF;
  }

  // Override in derived sequences
  virtual task pre_transaction(my_transaction tr);
  endtask

  virtual task post_transaction(my_transaction tr);
  endtask

  task body();
    my_transaction tr;
    repeat(num_transactions) begin
      tr = my_transaction::type_id::create("tr");
      start_item(tr);
      assert(tr.randomize() with {
        addr inside {[addr_min:addr_max]};
        delay inside {[min_delay:max_delay]};
      });
      pre_transaction(tr);
      finish_item(tr);
      post_transaction(tr);
    end
  endtask
endclass

// Derived sequence for specific scenario
class write_only_sequence extends base_traffic_sequence;
  constraint c_write { /* all writes */ }
  // Inherits all base functionality
endclass
```

### 9.4 Environment Reuse

```systemverilog
// Block-level env reused in subsystem and chip-level
class block_env extends uvm_env;
  // Contains: agent, scoreboard, coverage
  // Fully configurable via config object
endclass

class subsystem_env extends uvm_env;
  block_env block_a;  // Reused
  block_env block_b;  // Reused
  // Additional subsystem-level components
endclass

class chip_env extends uvm_env;
  subsystem_env subsys;  // Reused
  // Additional chip-level components
endclass
```

### 9.5 Cross-Project Reuse

**Repository Organization:**

```
verification_library/
  vips/
    axi_vip/
    apb_vip/
    spi_vip/
  common/
    base_test.sv
    watchdog.sv
    clock_gen.sv
    coverage_utils.sv
  utilities/
    mem_model.sv
    scoreboard_utils.sv
    report_server.sv
  docs/
    integration_guide.md
    coding_standards.md
```

**Reuse Metrics:**

| Metric | Description |
|--------|-------------|
| Reuse ratio | % of testbench from reused components |
| Integration effort | Time to integrate reused component |
| Bug inheritance | Bugs from reused vs new components |
| Coverage from reuse | Coverage contributed by reused tests |

---

## 10. Advanced Topics

### 10.1 Emulation and FPGA Prototyping

**When to Use:**
- Software validation (running real firmware/OS).
- Performance validation (real-time speed requirements).
- System validation (end-to-end with real peripherals).
- Long-running tests infeasible in simulation.

**Emulation Testbench Architecture:**

```
Emulation:
  Speed: ~1 MHz (vs ~1 kHz simulation)
  Use: Hardware-assisted verification
  Tools: Palladium (Cadence), Zebu (Synopsys), Veloce (Siemens)

FPGA Prototyping:
  Speed: ~10-50 MHz
  Use: Software development, system validation
  Tools: HAPS (Synopsys), Protium (Cadence)
```

### 10.2 Formal Verification Integration

**Formal Methods in Verification Plan:**

| Method | Use Case | Typical Coverage |
|--------|----------|-----------------|
| Bounded model checking | Safety properties | Exhaustive (bounded) |
| Unbounded proof | Invariants | Complete |
| Coverage-driven formal | Increase formal coverage | Targeted |
| Equivalence checking | RTL vs RTL, RTL vs netlist | Complete |
| Connectivity checking | SoC-level routing | Complete |
| Register checking | CSR compliance | Complete |
| CDC formal | Clock domain crossing | Structural + protocol |
| Security checking | Information flow | Targeted |

### 10.3 Performance Verification

**Performance Metrics:**

```systemverilog
class performance_monitor extends uvm_component;
  // Latency tracking
  time start_times[int];  // Keyed by transaction ID
  real latencies[$];

  function void record_start(int id, time t);
    start_times[id] = t;
  endfunction

  function void record_end(int id, time t);
    if (start_times.exists(id)) begin
      real lat = real'(t - start_times[id]) / 1ns;
      latencies.push_back(lat);
      start_times.delete(id);
    end
  endfunction

  // Statistics
  function real get_avg_latency();
    real sum = 0;
    foreach (latencies[i]) sum += latencies[i];
    return sum / latencies.size();
  endfunction

  function real get_max_latency();
    real max_val = 0;
    foreach (latencies[i])
      if (latencies[i] > max_val) max_val = latencies[i];
    return max_val;
  endfunction

  function real get_min_latency();
    real min_val = latencies[0];
    foreach (latencies[i])
      if (latencies[i] < min_val) min_val = latencies[i];
    return min_val;
  endfunction

  // Bandwidth tracking
  int unsigned byte_count;
  time measurement_start;

  function real get_bandwidth_gbps();
    real elapsed = real'($time - measurement_start) / 1ns;
    return (real'(byte_count) * 8.0) / elapsed;  // Gbps
  endfunction
endclass
```

### 10.4 Debug Methodology

**Debug Flow:**

```
1. Reproduce failure
   - Same seed, same test, same options
   - Verify failure is consistent

2. Localize failure
   - Identify failing assertion or check
   - Determine time of first divergence
   - Narrow to specific interface or block

3. Analyze root cause
   - Open waveform viewer (Verdi, DVE, SimVision)
   - Trace backward from failure point
   - Check related signals and state machines
   - Use fsdb/vcd with selective dumping

4. Fix and verify
   - Apply RTL fix
   - Re-run failing test with same seed
   - Run related tests to verify no regression
   - Add regression test for the scenario
```

**Debug Techniques:**

| Technique | Tool | Use Case |
|-----------|------|----------|
| Waveform | Verdi, DVE | Signal-level debug |
| Transaction debug | Verdi Protocol Analyzer | Transaction-level debug |
| UVM debug | Verdi UVM Debug | Testbench component debug |
| Coverage debug | Verdi Coverage | Identify uncovered scenarios |
| Assertion debug | Assertion viewer | Failed assertion analysis |
| Memory dump | $readmemh/$writememh | Memory content comparison |
| Printf debug | `uvm_info with UVM_DEBUG | Quick trace |
| Force/release | simulator commands | Quick experiments |

---
