# False Paths and Multicycle Paths: Timing Exceptions

## Why Timing Exceptions Exist

Static timing analysis (STA) by default checks every topological path from every launch flip-flop to every capture flip-flop in the design. Many of these paths, however, are either functionally impossible (never exercised) or intentionally designed to operate over multiple clock cycles. Without explicit timing exceptions, the tool over-constrains the design, wasting optimization effort on non-existent or incorrectly-timed paths and potentially degrading real critical paths.

Timing exceptions -- false paths, multicycle paths, and case analysis -- refine the STA model to match the actual design intent. Getting these right is critical: too few exceptions means over-constraining and wasted PPA; too many (or incorrect) exceptions means hiding real violations that appear as silicon failures.

## False Paths

A false path is a timing path that exists topologically in the netlist but cannot be functionally exercised. No data can ever propagate along this path during normal operation.

### Legitimate False Path Categories

**Asynchronous Clock Domain Crossings:**
Paths between truly asynchronous clock domains are false-pathed because there is no deterministic timing relationship. Synchronizer circuits handle the crossing.

```tcl
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
```

**Mutually Exclusive Modes:**
Paths through MUX structures where only one path is active at a time:

```tcl
# Test mux: func_path and test_path are mutually exclusive
set_false_path -from [get_pins func_ff/Q] -through [get_pins test_mux/B]
set_false_path -from [get_pins test_ff/Q] -through [get_pins test_mux/A]
```

**Static Configuration Registers:**
Registers written once at boot and never changed during operation:

```tcl
set_false_path -from [get_cells config_regs/*]
```

**Reset and Power-Up Paths:**
Paths exercised only during reset or power-up, not during functional operation:

```tcl
set_false_path -from [get_ports async_reset_n]
```

### False Path Syntax Variations

```tcl
# Between specific clock domains
set_false_path -from [get_clocks src_clk] -to [get_clocks dst_clk]

# From specific registers
set_false_path -from [get_cells {reg_a reg_b}]

# To specific registers
set_false_path -to [get_cells {reg_x reg_y}]

# Through specific pins (combinational path segments)
set_false_path -through [get_pins mux/sel]

# Combining -from, -through, -to
set_false_path -from [get_cells src_reg] \
               -through [get_pins mid_gate/A] \
               -to [get_cells dst_reg]
```

### set_clock_groups vs. set_false_path

For asynchronous clock domains, `set_clock_groups` is preferred over `set_false_path`:

```tcl
# Preferred: bidirectional, cleaner
set_clock_groups -asynchronous \
  -group [get_clocks clk_a] \
  -group [get_clocks clk_b]

# Equivalent but requires two commands
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
set_false_path -from [get_clocks clk_b] -to [get_clocks clk_a]
```

`set_clock_groups -asynchronous` also handles paths between clocks within the same group correctly (they remain constrained), which individual false paths might miss.

## Multicycle Paths

A multicycle path is a real timing path that is designed to take more than one clock cycle to propagate. The data is sampled by the destination flip-flop every N cycles, not every cycle.

### When Multicycle Paths Occur

- **Pipeline stages with enables:** A register is only updated every 2nd, 3rd, or Nth clock cycle based on an enable signal
- **Slow-to-fast clock crossings:** Data from a slow clock domain is captured by a faster clock that has multiple edges per source clock period
- **Intentional relaxed paths:** Logic deliberately given extra cycles to meet area/power targets

### Basic Multicycle Path Syntax

```tcl
# 2-cycle setup path (data needs 2 clock periods)
set_multicycle_path 2 -setup \
  -from [get_cells slow_reg/*] -to [get_cells fast_reg/*]

# Corresponding hold adjustment
set_multicycle_path 1 -hold \
  -from [get_cells slow_reg/*] -to [get_cells fast_reg/*]
```

### The Setup-Hold Relationship

For a multicycle path with multiplier N:
- **Setup check:** Moved N-1 clock edges forward (N * Tperiod instead of 1 * Tperiod)
- **Hold check:** By default, moves to N-1 edges forward as well, which is usually wrong

The hold MCP value should almost always be N-1 to bring the hold check back to the launch edge:

```
Default (without hold MCP):
  Setup check at edge: N (correct)
  Hold check at edge:  N-1 (wrong -- too late, creates artificial hold violations)

With hold MCP = N-1:
  Setup check at edge: N (correct)
  Hold check at edge:  0 (correct -- check at launch edge)
```

**Rule of thumb:** For every `set_multicycle_path N -setup`, add `set_multicycle_path (N-1) -hold` on the same path.

### Inter-Clock Multicycle Paths

When source and destination have different clock frequencies, multicycle paths require careful analysis of the actual edge relationships:

```tcl
# Source at 500MHz (2ns), destination at 1GHz (1ns)
# Data launches on source clock, captured 2 destination edges later
set_multicycle_path 2 -setup -from [get_clocks clk_500] -to [get_clocks clk_1000]
set_multicycle_path 1 -hold  -from [get_clocks clk_500] -to [get_clocks clk_1000]
```

### Half-Cycle Paths

When data is launched on the rising edge and captured on the falling edge (or vice versa), it naturally has a half-cycle path. This is not a multicycle path but is sometimes confused with one:

```tcl
# Half-cycle path: capture on falling edge
# No multicycle needed -- the tool handles this from waveform definitions
# Just ensure the clock waveform correctly specifies the falling edge
```

## Case Analysis

Case analysis sets constant values on specific pins, modeling the design state in a particular operating mode:

```tcl
# Functional mode: test muxes select functional path
set_case_analysis 0 [get_ports test_mode]
set_case_analysis 0 [get_ports scan_enable]

# Scan mode: test muxes select scan path
set_case_analysis 1 [get_ports test_mode]
set_case_analysis 1 [get_ports scan_enable]
```

Case analysis implicitly creates false paths by making certain paths logically unreachable. It is more precise than explicit false paths because the tool automatically identifies which paths are disabled by the constant values.

## Min/Max Delay Constraints

Explicit delay constraints override the default clock-period-based analysis:

```tcl
# Maximum delay (replaces setup check with absolute delay)
set_max_delay 5.0 -from [get_ports async_in] -to [get_cells sync_reg/D]

# Minimum delay (replaces hold check with absolute delay)
set_min_delay 0.5 -from [get_cells reg_a/Q] -to [get_cells reg_b/D]

# set_max_delay with -datapath_only
# Ignores clock network delay, useful for CDC paths
set_max_delay 3.0 -datapath_only \
  -from [get_clocks clk_a] -to [get_clocks clk_b]
```

### When to Use set_max_delay vs. set_false_path

- Use `set_false_path` when the path is truly non-functional
- Use `set_max_delay -datapath_only` when the path exists but has a specific timing budget (e.g., CDC with data stability requirement)

## Exception Priority

When multiple exceptions apply to the same path, the tool resolves conflicts using priority rules:

1. **set_false_path** has the highest priority (path is excluded)
2. **set_multicycle_path** overrides default single-cycle check
3. **set_max_delay / set_min_delay** overrides clock-based timing
4. More specific exceptions override less specific ones (pin-level > cell-level > clock-level)

```tcl
# This path is false (highest priority, overrides any MCP)
set_false_path -from [get_cells reg_a] -to [get_cells reg_b]
# This MCP is ignored because the false path has higher priority
set_multicycle_path 2 -setup -from [get_cells reg_a] -to [get_cells reg_b]
```

## Verification and Debugging

### Report Exceptions

```tcl
# List all exceptions
report_exceptions

# Show which exception applies to a specific path
report_timing -from reg_a/Q -to reg_b/D -path_type full_clock
```

### Common Mistakes

1. **Missing hold MCP:** Adding `set_multicycle_path N -setup` without the corresponding hold adjustment creates false hold violations.

2. **Over-broad false paths:** `set_false_path -from [get_clocks clk_a]` false-paths ALL paths from clk_a, including intra-domain paths. Be specific.

3. **False-pathing synchronizer outputs:** The path from the synchronizer output to downstream logic is a real path and must be constrained. Only the path into the synchronizer is false.

4. **Multicycle path on wrong edges:** For inter-clock MCPs, verify the edge relationships by examining the timing report, not by guessing.

5. **Conflicting exceptions:** Multiple exceptions on the same path with different intents. Use `report_exceptions -conflict` to identify.

## Practical Recommendations

1. **Document every exception.** Add comments explaining why each false path or multicycle path exists. Future engineers (including your future self) will need this context.

2. **Prefer set_clock_groups over set_false_path for CDC.** It is cleaner, bidirectional, and less error-prone.

3. **Always add hold MCP with setup MCP.** The pair should be considered mandatory.

4. **Validate with report_timing.** After adding exceptions, run timing on the affected paths to confirm the constraint is applied correctly.

5. **Review exceptions during signoff.** Stale or incorrect exceptions are a top-5 cause of silicon timing failures.

6. **Minimize the use of set_max_delay.** It disables CPPR and can hide real timing issues. Prefer clock-based constraints when possible.

Timing exceptions are powerful but dangerous. They are the most common source of SDC errors, and SDC errors are the most common cause of timing-related silicon failures. Treat every exception as a potential risk and verify thoroughly.
