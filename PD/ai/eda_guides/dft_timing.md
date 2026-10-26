# DFT Timing: Constraints, Closure, and Analysis for Test Modes

## DFT Timing Overview

Test mode timing closure is a distinct challenge from functional timing closure. While the same physical design must meet timing in both modes, the clock structures, signal paths, and operating conditions differ significantly. DFT timing involves three main scenarios: scan shift timing (slow clock, all chains shifting), stuck-at capture timing (single capture at arbitrary speed), and at-speed capture timing (transition test at functional frequency). Each requires dedicated SDC constraints and careful analysis.

Failure to close DFT timing results in silicon test failures -- patterns that work in simulation but fail on silicon due to timing violations. These failures are among the most difficult to debug because they manifest as pattern-dependent, corner-dependent scan mismatches.

## Scan Shift Timing

### Shift Path Analysis

During scan shift, data moves through the scan chain: SI -> scan_mux -> D -> Q -> SI_next -> scan_mux_next -> D_next. The timing path is:

```
Launch: CLK rising edge at flip-flop N
        -> CK-to-Q delay of flip-flop N
        -> routing delay to SI of flip-flop N+1
        -> scan mux delay (SE=1 selects SI path)
        -> setup time at flip-flop N+1
Capture: CLK rising edge at flip-flop N+1
```

**Setup constraint**: The total CK-to-Q + routing + mux delay must be less than the shift clock period minus the setup time of the destination flip-flop plus any useful skew.

**Hold constraint**: The CK-to-Q + routing + mux delay must be greater than the hold time, accounting for clock skew between source and destination.

### Shift Timing Characteristics

- Shift frequency is typically 50-200 MHz (period 5-20 ns) -- much more relaxed than functional timing
- Setup violations during shift are rare but can occur on very long scan routes (physically distant cells in the same chain)
- Hold violations during shift are more common, especially at clock domain boundaries within chains where skew exists
- Lockup latches at domain boundaries prevent hold violations by adding a half-cycle delay

### Shift SDC Constraints

```tcl
# Define shift clock
create_clock -name SHIFT_CLK -period 10.0 [get_ports scan_clk]

# Set test mode conditions
set_case_analysis 1 [get_ports test_mode]
set_case_analysis 1 [get_ports scan_enable]

# Disable functional paths during shift
set_false_path -from [get_ports func_data_*]
set_false_path -to [get_ports func_data_*]

# Constrain scan enable arrival
set_input_delay -clock SHIFT_CLK 2.0 [get_ports scan_enable]
```

## At-Speed Capture Timing

### Capture Path Analysis (Transition Test)

During at-speed capture, the scan enable is deasserted (SE=0) and functional logic paths are active. The timing path is identical to the functional timing path:

```
Launch: CLK edge at source flip-flop (functional data path)
        -> CK-to-Q of source flip-flop
        -> combinational logic delay
        -> setup time at destination flip-flop
Capture: CLK edge at destination flip-flop (one period later)
```

The at-speed capture must meet the same timing as functional operation. In theory, if the design meets functional timing, it meets capture timing. In practice, differences arise:

- **Different switching activity**: ATPG patterns create different toggle patterns than functional operation, causing different IR drop profiles that affect timing
- **Test mode logic**: Clock gating test enables, scan mux loads, and OCC logic may add delays not present in functional mode
- **Power/ground effects**: Higher test power causes more IR drop, potentially causing timing failures

### At-Speed Capture SDC

```tcl
# Define capture clock at functional frequency
create_clock -name CAPTURE_CLK -period 1.0 [get_pins OCC/clk_out]

# Deassert scan enable
set_case_analysis 0 [get_ports scan_enable]
set_case_analysis 1 [get_ports test_mode]

# Functional timing applies to capture paths
# All register-to-register paths constrained by CAPTURE_CLK
```

## OCC Timing Constraints

The OCC has specific internal timing paths that must be constrained:

### Clock Mux Control Timing

The clock source select signal must be stable before the clock edge:
```tcl
# Mux select must arrive before the clock it controls
set_max_delay 0.5 -from [get_pins OCC/mode_reg/Q] -to [get_pins OCC/clk_mux/S]
```

### Pulse Generator Timing

The launch and capture pulse timing must be precisely controlled:
```tcl
# Ensure pulse width is correct
set_min_delay 0.3 -from [get_pins OCC/pulse_gen/launch] -to [get_pins OCC/pulse_gen/capture]
```

### OCC Output to Clock Tree

The OCC output feeds the clock tree root. Any delay here directly impacts all capture timing:
```tcl
# OCC to clock tree timing
set_max_delay 0.2 -from [get_pins OCC/clk_out] -to [get_pins CTS_root/clk_in]
```

## Scan Enable Timing

Scan enable timing is often the most critical DFT timing constraint:

### SE Setup for Capture

SE must transition from 1 (shift) to 0 (capture) and arrive at every scan flip-flop before the capture clock edge. With massive fanout (every scan cell in the design), SE routing is extensive and the latest arrival determines the constraint:

```tcl
# SE must meet setup at all scan flip-flops relative to capture clock
# This is typically modeled as:
set_input_delay -clock CAPTURE_CLK [expr {$capture_period - $se_setup_margin}] [get_ports scan_enable]
```

### SE Hold for Last Shift

SE must remain high long enough during the last shift cycle to ensure all flip-flops shift correctly:
```tcl
# SE must be stable high during the last shift clock edge
set_input_delay -clock SHIFT_CLK -min 0.5 [get_ports scan_enable]
```

### SE Timing Challenges

At high functional frequencies (>2 GHz), the capture period is <500 ps. SE must arrive at all cells within this window after transitioning from 1 to 0. This requires:
- Dedicated SE buffer tree (similar to a clock tree but for a non-clock signal)
- SE skew management across the entire design
- Potentially multi-stage SE distribution with local buffering

Techniques to relax SE timing:
- **OCC with SE synchronization**: The OCC delays the first capture pulse until SE is guaranteed settled
- **Late SE delivery**: Pre-position SE close to its final value before the last shift, then make only a small final transition
- **Registered SE**: Register SE locally at each scan cell group, giving a full cycle for propagation

## Multicycle Paths in Test Mode

Several paths in test mode require multicycle path exceptions:

### Shift-to-Capture Multicycle

The transition from shift mode to capture mode spans multiple cycles. Paths from shift-related signals to capture-related signals should be multicycled or false-pathed:

```tcl
# Shift clock to capture clock paths are not single-cycle
set_multicycle_path -setup 2 -from [get_clocks SHIFT_CLK] -to [get_clocks CAPTURE_CLK]
set_multicycle_path -hold 1 -from [get_clocks SHIFT_CLK] -to [get_clocks CAPTURE_CLK]
```

### OCC Control Paths

OCC configuration registers are loaded during shift and used during capture. These are inherently multicycle:

```tcl
# OCC config loaded during shift, used during capture
set_false_path -from [get_cells OCC/config_reg*] -to [get_clocks CAPTURE_CLK]
# Or multicycle if they must be timed
set_multicycle_path -setup 100 -from [get_cells OCC/config_reg*]
```

### Compression Control Paths

Compression mode and masking control signals are similarly multicycle:

```tcl
set_false_path -from [get_cells EDT/mask_reg*]
set_false_path -from [get_cells EDT/mode_reg*]
```

## DFT Timing Closure Flow

### Step 1: Create Test Mode Constraints

Develop SDC files for each test mode:
- `test_shift.sdc`: Shift mode constraints
- `test_capture_sa.sdc`: Stuck-at capture constraints
- `test_capture_tdf.sdc`: At-speed transition capture constraints
- `test_bist.sdc`: BIST mode constraints (if LBIST/MBIST present)

### Step 2: Multi-Mode STA

Run STA across all modes:
```tcl
# In PrimeTime or Tempus
set_analysis_mode -mode test_shift
update_timing
report_timing -max_paths 100 -mode test_shift

set_analysis_mode -mode test_capture_tdf
update_timing
report_timing -max_paths 100 -mode test_capture_tdf
```

### Step 3: Fix Violations

Common fixes:
- **Shift hold violations**: Add delay buffers on scan chain connections or reorder chains
- **SE setup violations**: Add SE buffers, restructure SE distribution, or use OCC-based SE synchronization
- **Capture setup violations**: Same fixes as functional timing -- sizing, buffering, routing optimization
- **OCC path violations**: Resize OCC internal logic, adjust placement

### Step 4: Incremental Optimization

Fix test mode violations without degrading functional timing:
```tcl
# In Innovus/ICC2
set_mode test_capture_tdf
optimize_design -incremental
# Verify functional timing is not degraded
set_mode functional
report_timing -max_paths 100
```

### Step 5: Sign-Off Verification

Multi-mode multi-corner STA across all functional and test modes at all corners:
- All test modes must be clean at all signoff corners
- Test modes typically have the same PVT corners as functional (same silicon, same conditions)
- Exception: Some shift-specific corners may use relaxed timing (shift is slow)

## Timing-Aware ATPG

Advanced ATPG tools can account for timing information when generating at-speed patterns:

- **SDF-annotated ATPG**: ATPG uses gate delays from SDF to avoid generating patterns that would fail due to timing rather than defects
- **Path-based ATPG**: Targets specific timing paths identified by STA, generating patterns that exercise near-critical paths
- **Timing-based ATPG**: Uses timing information to score fault detection -- faults on timing-critical paths are prioritized

## Common DFT Timing Issues and Solutions

| Issue | Symptom | Solution |
|-------|---------|----------|
| Scan chain hold violation | Chain data corruption during shift | Insert delay buffer or lockup latch |
| SE late arrival | Intermittent capture failures | Buffer SE tree, use OCC synchronization |
| Clock gating test enable timing | Some flip-flops miss capture | Ensure test_enable meets timing to all ICGs |
| OCC pulse width too narrow | At-speed capture unreliable | Adjust OCC pulse generation logic |
| Compression codec timing | Shift frequency limited | Pipeline decompressor, optimize codec placement |
| Cross-domain capture timing | Inter-domain transition test failures | Align OCC pulse timing across domains |
