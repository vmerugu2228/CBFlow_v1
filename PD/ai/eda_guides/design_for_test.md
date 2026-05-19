# Design for Test (DFT)

## Overview

Design for Test (DFT) encompasses the techniques and structures inserted into a design to enable efficient manufacturing testing. Without DFT, testing a complex SoC would require exhaustive functional simulation — practically impossible for modern designs with billions of transistors. DFT transforms the testing problem from functional verification into structural verification, where standardized test patterns can detect manufacturing defects with high coverage. DFT decisions made early in the design flow save months of debug time and millions of dollars in test cost.

## Why DFT Matters

Manufacturing defects include:

- **Stuck-at faults:** A signal permanently at logic 0 or 1 (e.g., short to VDD/VSS)
- **Bridging faults:** Unintended connection between two signals
- **Open faults:** Broken connection in a wire or via
- **Transition faults:** Signal cannot transition fast enough (delay defect)
- **IDDQ faults:** Excessive quiescent current indicating a defect

Without DFT structures, these defects would escape to the customer, causing field failures. Achieving high test coverage (>95%) is essential for acceptable defect levels (DPPM < 10).

## Scan Testing

### Concept

Scan testing converts flip-flops into scan flip-flops that can be chained together, forming a shift register. This allows direct control and observation of internal state — the tester can shift in any pattern, apply it, capture the response, and shift it out for comparison.

### Scan Flip-Flop

A scan flip-flop adds a multiplexer at the D input:

```
Normal mode (SE=0): D input selected -> functional data
Test mode (SE=1):   SI input selected -> scan chain data

       SE
        |
    +---MUX---+
    |   0  1  |
    D   SI    |
    |         |
    +---DFF---+
        |
        Q ---> SO (to next scan FF)
```

### Scan Chain Architecture

```
Scan In -> FF1 -> FF2 -> FF3 -> ... -> FFn -> Scan Out
           (shift through chain in SE=1 mode)
```

**Chain length:** Total number of scan flip-flops divided by number of chains. Shorter chains = faster shift but more I/O pins.

```
Chain length = Total scan FFs / Number of chains
Shift cycles = Chain length
```

### Scan Insertion Flow

```tcl
# In Genus (Cadence)
set_db dft_scan_style muxed_scan
set_db dft_prefix DFT_

# Define scan chains
define_scan_chain -name chain_1 -sdi SI_1 -sdo SO_1 -non_shared_output
define_scan_chain -name chain_2 -sdi SI_2 -sdo SO_2 -non_shared_output

# Check scan rules
check_dft_rules

# Insert scan
connect_scan_chains

# Verify scan connectivity
report_scan_chains
```

```tcl
# In DC/FC (Synopsys)
set_scan_configuration -chain_count 8 -style multiplexed_flip_flop
set_dft_signal -view existing_dft -type ScanClock -timing {45 55} -port clk
set_dft_signal -view spec -type ScanEnable -port scan_en -active_state 1

# Insert DFT
insert_dft

# Verify
dft_drc
report_scan_chain
```

### Scan Chain Ordering

Scan chains should be ordered to minimize routing wirelength between consecutive scan flip-flops:

```tcl
# Physical-aware scan ordering in PnR
set_scan_reorder_mode -chain_count 8
reorder_scan_chains
```

Physical scan reordering in the PnR tool reduces scan routing congestion by 20-40% compared to synthesis-ordered chains.

## Automatic Test Pattern Generation (ATPG)

### Concept

ATPG tools automatically generate test patterns that detect specific fault types. The ATPG tool:

1. Targets a fault (e.g., net X stuck-at-0)
2. Generates an input pattern that activates the fault (makes the fault site switch to the opposite value)
3. Propagates the fault effect to an observable point (scan out or primary output)
4. If no pattern can detect the fault, it is classified as undetectable

### Fault Models

#### Stuck-At Fault

The most basic model. Each net can be stuck-at-0 (SA0) or stuck-at-1 (SA1).

- **Total possible stuck-at faults:** 2 * number of nets
- **Detectable faults:** Depends on design observability/controllability
- **Target coverage:** > 95% for production, > 98% for safety-critical

#### Transition Fault (At-Speed)

Tests whether a signal can switch fast enough. The pattern applies a launch value, then a capture value, and checks if the transition propagates within the clock period.

- **Launch-off-capture (LOC):** Uses functional clock to launch the transition
- **Launch-off-shift (LOS):** Uses the last shift cycle to launch the transition
- **Target coverage:** > 90%

#### Path Delay Fault

Tests specific timing paths rather than individual transitions. More thorough for delay testing but generates more patterns.

#### Bridging Fault

Tests for unintended connections between signals. Requires neighborhood analysis to identify likely bridge sites.

#### IDDQ Testing

Measures quiescent current (IDDQ) with the design in a stable state. Defective transistors cause elevated leakage current. Effective for detecting faults not caught by stuck-at/transition tests.

### ATPG Tools

**Synopsys TetraMAX:**

```tcl
# Read design
read_netlist top_scan.v
run_build_model top

# Read scan chain definition
run_drc top.spf

# Generate stuck-at patterns
set_faults -model stuck
add_faults -all
run_atpg -auto

# Generate transition patterns
set_faults -model transition
add_faults -all
run_atpg -auto

# Report coverage
report_faults -summary
write_patterns top_patterns.stil -format stil -replace
```

**Cadence Modus:**

```tcl
# Build test model
build_model -design top -library std.lib

# Stuck-at ATPG
create_pattern -type stuck_at
run_pattern_gen

# Transition ATPG
create_pattern -type transition -launch_cycle system_clock
run_pattern_gen

# Report
report_statistics
write_patterns -type stil -output top_patterns.stil
```

### Test Coverage

| Metric | Definition | Target |
|--------|-----------|--------|
| Fault coverage | Detected faults / Total faults | > 95% |
| Test coverage | Detected faults / (Total - Undetectable) | > 98% |
| ATPG effectiveness | (Detected + Undetectable) / Total | > 99% |
| Pattern count | Number of test vectors generated | < 10,000 typical |

## Test Compression

### Why Compression

Without compression:
- Pattern count * chain length = total shift cycles
- For 1M scan FFs and 1000 patterns: 1M * 1000 = 1 billion ATE cycles
- At 100 MHz ATE clock: 10 seconds per chip
- At $0.01/second test cost: $0.10/chip

With 100x compression:
- Test time reduced to 0.1 seconds
- Test cost: $0.001/chip

### Compression Architecture

```
              Decompressor          Compressor
ATE Channels -> (expander) -> Scan Chains -> (compactor) -> ATE Channels

Input:  8 ATE channels -> decompressor -> 800 internal scan chains
Output: 800 scan chains -> compressor -> 8 ATE channels
Compression ratio: 100x
```

### Compression Implementation

```tcl
# In TetraMAX (Synopsys DFTMAX)
set_dft_configuration -scan_compression enable
set_scan_compression_configuration -chain_count 800 -input_channel_count 8 -output_channel_count 8
insert_dft
```

```tcl
# In Genus (Cadence Modus EDT)
set_db dft_scan_compression true
set_db dft_scan_compression_chain_count 800
set_db dft_scan_compression_input_width 8
set_db dft_scan_compression_output_width 8
connect_scan_chains
```

## Built-In Self-Test (BIST)

### Memory BIST (MBIST)

Tests embedded memories (SRAM, ROM, register files) using on-chip test controllers.

**MBIST architecture:**

```
BIST Controller -> Address Generator -> Memory Under Test -> Comparator -> Pass/Fail
                -> Data Generator ----/                  /
                -> Expected Data ----/                  /
```

**Common MBIST algorithms:**

| Algorithm | Complexity | Coverage |
|-----------|-----------|----------|
| March C- | 10N | Stuck-at, transition, coupling |
| March SS | 22N | All above + linked faults |
| Checkerboard | 4N | Pattern-sensitive faults |

Where N = number of memory words.

```tcl
# MBIST insertion (tool-specific)
# Define memory instances for BIST
add_mbist_controller -memories {u_sram_0 u_sram_1 u_sram_2} \
    -algorithm march_c_minus \
    -controller_name mbist_ctrl_0
```

### Logic BIST (LBIST)

Uses on-chip pattern generators (LFSR) and response analyzers (MISR) to test combinational logic without external tester dependency.

**LBIST architecture:**

```
LFSR (Pattern Generator) -> Scan Chains -> MISR (Signature Analyzer)
```

Advantages: No external tester patterns required, enables in-field testing.
Disadvantages: Lower fault coverage than ATPG (typically 85-90% vs. 95%+), longer test time.

## DFT-Aware Synthesis

### Scan-Friendly Coding Guidelines

- **Avoid internally generated clocks:** They complicate scan chain timing.
- **Avoid combinational feedback loops:** They cause non-deterministic behavior during scan shift.
- **Avoid tri-state buses internally:** They are difficult to control during scan mode.
- **Use synchronous resets:** Asynchronous resets can interfere with scan shift.
- **Register all outputs of clock domain crossings:** Enables clean scan chain partitioning per clock domain.

### DFT Insertion Timing in the Flow

```
RTL Design
    |
DFT Planning (test architecture, chain count, compression ratio)
    |
Synthesis (with DFT-aware settings)
    |
Scan Insertion (insert scan chains, compression)
    |
ATPG (generate test patterns, verify coverage)
    |
Place and Route (physical scan chain reordering)
    |
Post-Route ATPG (re-verify coverage with actual delays)
    |
Silicon Testing
```

## Common Issues and Fixes

**Issue: Low stuck-at fault coverage (<95%)**
- Identify undetectable faults: `report_faults -undetectable`
- Common causes: uncontrollable signals, unobservable internal nodes
- Add test points (control/observe) at problematic locations
- Verify all scan flip-flops are in chains (check for unjustified exclusions)

**Issue: Scan chain fails to shift correctly**
- Check scan chain connectivity: `report_scan_chains -detailed`
- Verify scan enable (SE) timing — SE must be stable during shift clock edges
- Check for hold violations on scan chain connections
- Look for combinational logic between scan flip-flops (must be transparent during shift)

**Issue: Transition (at-speed) coverage is low (<90%)**
- Check for slow clock paths that prevent at-speed capture
- Verify launch/capture mechanism (LOC vs. LOS)
- Add more transition-specific test points
- Check for paths that are untestable at speed due to multiple clock domains

**Issue: Compression decompressor/compressor causes X-propagation**
- X-values (unknown states) in scan chains corrupt the compressor output
- Add X-masking logic or X-tolerance to the compressor
- Identify and fix sources of X in the design (uninitialized memories, multi-driven buses)

**Issue: MBIST fails on specific memory instances**
- Verify BIST controller clock and reset connectivity
- Check memory interface timing (setup/hold on BIST-to-memory paths)
- Verify address and data width configurations match the memory instance

## Best Practices

1. **Plan DFT architecture at the RTL stage** — retrofitting DFT is expensive and error-prone.
2. **Target > 95% stuck-at coverage** and > 90% transition coverage for production.
3. **Use test compression** — 100x compression reduces test time by 100x.
4. **Reorder scan chains in PnR** — physical ordering reduces scan routing congestion.
5. **Run ATPG after every major netlist change** — coverage can degrade after optimization or ECO.
6. **Include MBIST for all embedded memories** — ATPG cannot effectively test memories.
7. **Budget for DFT area overhead** — scan muxes, compression logic, and BIST controllers add 5-15% area.
8. **Test at speed** — stuck-at testing alone misses delay defects that dominate at advanced nodes.
9. **Validate scan chains in simulation** before tapeout — shift a known pattern, verify the output.
10. **Keep test mode isolated** from functional mode — set_false_path from test ports during functional timing analysis.
