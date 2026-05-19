# MMMC Methodology: Multi-Mode Multi-Corner Analysis

## Why MMMC Matters

Modern SoC designs operate across multiple functional modes (e.g., functional, test, sleep) and must meet timing across a wide range of process, voltage, and temperature (PVT) conditions. Multi-Mode Multi-Corner (MMMC) methodology provides a structured framework for analyzing and optimizing a design under all relevant operating scenarios simultaneously. Without MMMC, engineers would need to run separate analyses for each mode-corner combination, leading to fragmented optimization, missed violations, and excessive runtime.

The core principle is simple: a single optimization pass that is aware of all relevant scenarios will produce a better result than sequential per-scenario optimization, because fixing timing in one scenario while being blind to others frequently introduces new violations elsewhere.

## Fundamental Concepts

### Modes

A **mode** represents a distinct functional configuration of the design. Each mode has its own set of timing constraints (SDC), clock definitions, and active logic paths. Common modes include:

- **Functional mode** -- Normal chip operation with all clocks active at target frequency.
- **Scan/test mode** -- Shift and capture configurations with scan clocks, often at reduced frequency.
- **JTAG/debug mode** -- Boundary scan with TCK clock, typically slow.
- **Low-power modes** -- Sleep, retention, shutdown states with subsets of logic active and potentially different voltage levels.

Each mode is defined by a constraint file (SDC) and optionally a set of case analysis settings that model mux select values, clock gating states, or power domain enables.

### Corners

A **corner** represents a specific PVT (Process, Voltage, Temperature) operating point plus an RC extraction condition. Corners capture the range of silicon variation the design must tolerate. Key corners include:

- **SS (Slow-Slow)** -- Worst-case slow process, low voltage, high temperature. Setup-critical.
- **FF (Fast-Fast)** -- Best-case fast process, high voltage, low temperature. Hold-critical.
- **TT (Typical-Typical)** -- Nominal process, nominal voltage, nominal temperature. Used for power estimation and functional validation.
- **Signoff corners** -- Additional corners like SS_0p675v_125c or FF_0p825v_m40c that represent specific voltage/temperature extremes.

Each corner is defined by a library set (timing .db or .lib files at that PVT) and a parasitic (RC) extraction condition (e.g., Cmax, Cmin, RCmax).

### Analysis Views

An **analysis view** is the combination of one mode and one corner. It represents one specific scenario under which timing is analyzed. For example:

- `func_ss_0p72v_125c` = functional mode + SS corner at 0.72V/125C
- `scan_ff_0p825v_m40c` = scan mode + FF corner at 0.825V/-40C

Each analysis view produces its own timing report with setup and hold slack values.

### Scenario Sets

Not every mode-corner combination is meaningful or required for every optimization step. **Scenario sets** group analysis views for specific purposes:

- **Setup analysis set** -- Views used for setup timing optimization (typically slow corners across all modes).
- **Hold analysis set** -- Views used for hold timing optimization (typically fast corners).
- **Leakage optimization set** -- Views at high temperature for leakage-critical analysis.
- **Active set** -- The subset of all views that are currently enabled for optimization.

## Defining the MMMC Configuration

### In Innovus (Cadence)

```tcl
# Define library sets
create_library_set -name ss_0p72v_125c_libs \
  -timing [list ss_0p72v_125c.lib]

create_library_set -name ff_0p825v_m40c_libs \
  -timing [list ff_0p825v_m40c.lib]

# Define RC corners
create_rc_corner -name rc_cmax -T 125 \
  -qrc_tech /path/to/qrcTechFile -preRoute_res 1.0 -preRoute_cap 1.0

create_rc_corner -name rc_cmin -T -40 \
  -qrc_tech /path/to/qrcTechFile -preRoute_res 1.0 -preRoute_cap 1.0

# Define delay corners (library set + RC corner)
create_delay_corner -name ss_125c_dc \
  -library_set ss_0p72v_125c_libs -rc_corner rc_cmax

create_delay_corner -name ff_m40c_dc \
  -library_set ff_0p825v_m40c_libs -rc_corner rc_cmin

# Define constraint modes
create_constraint_mode -name func_mode \
  -sdc_files [list func_mode.sdc]

create_constraint_mode -name scan_mode \
  -sdc_files [list scan_mode.sdc]

# Define analysis views
create_analysis_view -name func_ss_setup \
  -constraint_mode func_mode -delay_corner ss_125c_dc

create_analysis_view -name func_ff_hold \
  -constraint_mode func_mode -delay_corner ff_m40c_dc

# Set active views
set_analysis_view -setup {func_ss_setup} -hold {func_ff_hold}
```

### In Fusion Compiler (Synopsys)

```tcl
# Scenarios in FC
create_scenario func_ss_setup
set_operating_conditions ss_0p72v_125c
read_sdc func_mode.sdc
set_scenario_status func_ss_setup -setup true -hold false -active true

create_scenario func_ff_hold
set_operating_conditions ff_0p825v_m40c
read_sdc func_mode.sdc
set_scenario_status func_ff_hold -setup false -hold true -active true
```

## Scenario Reduction

With N modes and M corners, the total number of analysis views is N x M, which can easily reach 50-100+ scenarios. Running all of them during every optimization step is prohibitively expensive. Scenario reduction techniques prune this space:

### Filtering Non-Critical Scenarios

After an initial full-scenario analysis, identify views that have large positive slack (not timing-critical). These can be deactivated during iterative optimization and re-enabled only for final signoff.

### Representative Scenario Selection

For modes that share similar clock structures and constraints, select one representative mode per corner rather than analyzing all modes at every corner.

### Corner Sensitivity Analysis

Run a sensitivity study to determine which corners dominate timing for each path group. Often, only 2-3 corners out of 10+ are actually constraining. The non-constraining corners can be dropped from active optimization.

### Incremental Scenario Activation

Start optimization with a minimal set of dominant scenarios. After convergence, activate additional scenarios and re-optimize. This iterative approach balances runtime with coverage.

## Practical Guidelines

1. **Always separate setup and hold view sets.** Never assign the same view as both setup-active and hold-active during optimization -- it confuses the optimizer.

2. **Match RC corners to PVT corners.** Pair Cmax extraction with slow-process corners (setup-critical) and Cmin extraction with fast-process corners (hold-critical). Mismatched pairings can hide real violations.

3. **Use consistent SDC across corners within a mode.** The constraint file should be identical for all corners of the same mode. PVT-dependent differences come from the library, not from the SDC.

4. **Limit active scenarios during placement.** 4-6 active views is typical for placement optimization. Use the full set only during final timing signoff.

5. **Validate scenario completeness before signoff.** After all optimizations, run timing with all scenarios active to confirm no violations in inactive views were introduced.

6. **Document your scenario matrix.** Maintain a clear table mapping each analysis view to its mode, corner, PVT, RC condition, and whether it is setup-active, hold-active, or signoff-only.

## Common Pitfalls

- **Over-constraining with too many active views** slows optimization without improving results. The tool spends effort fixing slack in non-critical views at the expense of the truly critical ones.
- **Forgetting to update the MMMC config when adding a new mode** (e.g., a new low-power state) leads to untested paths that fail in silicon.
- **Using the same extraction corner for all PVT corners** misses the interaction between process-dependent cell delay and temperature-dependent wire resistance.
- **Not accounting for voltage droop** -- the nominal voltage in the library may not reflect the worst-case IR-drop-adjusted voltage the logic actually sees.

MMMC methodology is the backbone of modern timing signoff. A well-constructed scenario matrix, combined with disciplined scenario reduction, enables both thorough coverage and practical runtimes.
