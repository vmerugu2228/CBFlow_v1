# Synopsys PrimeTime STA Guide

## Overview

PrimeTime (PT) is Synopsys's golden signoff static timing analysis tool, the industry standard for timing closure and signoff. PrimeTime provides the most accurate timing analysis with support for advanced features including POCV/AOCV, signal integrity (SI) analysis, multi-mode multi-corner (MMMC) via DMSA, ECO guidance, and parametric analysis. No ASIC tapeout proceeds without PrimeTime signoff.

## PrimeTime Variants

- **PrimeTime (PT):** Core STA engine
- **PrimeTime SI (PT-SI):** Signal integrity (crosstalk) analysis
- **PrimeTime PX (PT-PX / PTPX):** Power analysis (switching, leakage, internal)
- **PrimeTime ADV:** Advanced analysis (POCV, variation-aware)
- **PrimeTime DMSA:** Distributed multi-scenario analysis

## Basic PrimeTime Flow

### Design Read-In

```tcl
# Set search paths
set search_path [list ./libs ./netlists ./parasitics]
set link_path [list * ss_0p72v_125c.db]

# Read netlist
read_verilog top_routed.v
link_design top

# Read SDC
read_sdc top.sdc

# Read parasitics
read_parasitics -format SPEF top_routed.spef
# Or
read_parasitics -format SBPF top_routed.sbpf
```

### Timing Update and Reporting

```tcl
# Update timing (performs full STA)
update_timing -full

# Report setup timing
report_timing -max_paths 100 -nworst 3 -path_type full_clock_expanded \
    -input_pins -nets -transition_time -capacitance \
    > rpt/setup_timing.rpt

# Report hold timing
report_timing -delay_type min -max_paths 100 -nworst 3 \
    > rpt/hold_timing.rpt

# Report all violators
report_constraint -all_violators -max_transition -max_capacitance \
    > rpt/violations.rpt

# QoR summary
report_qor > rpt/qor.rpt
```

### Key Report Options

```tcl
# Detailed path report with all attributes
report_timing \
    -path_type full_clock_expanded \  ;# Show full clock path details
    -input_pins \                     ;# Show cell input pin arrivals
    -nets \                           ;# Show net names
    -transition_time \                ;# Show slew at each pin
    -capacitance \                    ;# Show load cap at each pin
    -crosstalk_delta \                ;# Show SI-induced delta delay
    -derate \                         ;# Show OCV derate factors
    -max_paths 50 \
    -nworst 3 \
    -group clk_core \
    > rpt/detailed_timing.rpt
```

## POCV/AOCV Analysis

### AOCV (Advanced OCV)

AOCV applies depth-dependent and distance-dependent derates. The deeper the logic path, the smaller the effective derate per stage (variation averages out).

```tcl
# Read AOCV tables
read_aocv lib_aocv.aocv

# Enable AOCV
set_app_var timing_aocvm_enable_analysis true

# Report with AOCV info
report_timing -derate -max_paths 20
```

### POCV (Parametric OCV)

POCV models delay variation as a Gaussian distribution with mean and sigma for each cell and net. Path delay variation is computed as RSS of individual sigmas.

```tcl
# Enable POCV
set_app_var si_pocv_analysis_mode true

# Read POCV models
read_pocvm cell_pocv.pocvm

# Set sigma multiplier (e.g., 3-sigma for 99.87% coverage)
set_app_var si_pocv_sigma_multiplier 3.0

# Report POCV-aware timing
report_timing -pocv -max_paths 50

# Report per-stage variation contribution
report_timing -variation -max_paths 10
```

**POCV vs. AOCV comparison:**

| Aspect | AOCV | POCV |
|--------|------|------|
| Model | Lookup table (depth, distance) | Gaussian (mean + sigma) |
| Accuracy | Good | Better (considers correlation) |
| Pessimism | Moderate | Lower (RSS aggregation) |
| Library requirement | AOCV tables | LVF (Liberty Variation Format) |
| Runtime | Low overhead | Moderate overhead |

## Signal Integrity (SI) Analysis

Crosstalk from coupling capacitance between adjacent wires can cause timing violations (delta delay) and functional failures (glitches).

### SI Setup

```tcl
# Enable SI analysis
set_app_var si_enable_analysis true
set_app_var si_xtalk_delay_analysis_mode all_violating_paths

# Read coupling information from parasitics
# (SPEF must include coupling caps — use detailed extraction)
read_parasitics -format SPEF top_si.spef

# Set noise thresholds
set_noise_parameters -above_low 0.3 -below_high 0.3

# Update timing with SI
update_timing -full
```

### SI Reporting

```tcl
# Report timing with crosstalk deltas
report_timing -crosstalk_delta -max_paths 50

# Report noise violations (glitches)
report_noise -above_low -below_high > rpt/noise.rpt

# Identify worst aggressors
report_si_bottleneck -max_aggressors 20 > rpt/si_bottleneck.rpt

# Report SI-specific delay contribution
report_delay_calculation -crosstalk -from [get_pins u1/A] -to [get_pins u1/Y]
```

### SI Fixing Strategies

When PT-SI identifies crosstalk violations:

1. **Net spacing increase** — Increase spacing between victim and aggressor in PnR.
2. **Shielding** — Route grounded shield wires between critical nets.
3. **Buffer insertion** — Reduce transition times on victim nets (faster transitions are less susceptible).
4. **Layer change** — Move aggressor or victim to a different routing layer.
5. **Driver sizing** — Upsize the victim net driver to improve drive strength and reduce susceptibility.

## ECO Timing Optimization

PrimeTime can recommend and validate timing ECO changes.

### ECO Flow

```tcl
# Identify bottleneck cells
report_bottleneck -max_cells 30

# Size up a cell for timing
size_cell u_buf1 BUFX8

# Insert a buffer
insert_buffer net_name BUFX4 -new_cell_name eco_buf_1

# Remove a buffer
remove_buffer eco_buf_old

# Swap Vt
size_cell u_gate1 AND2X1_LVT  ;# swap to LVT for speed

# Report post-ECO timing
update_timing -full
report_timing -max_paths 20

# Write ECO changes for PnR tool
write_changes -format iccompiler2 -output eco_changes.tcl
# Or for Innovus
write_changes -format innovus -output eco_changes.tcl
```

### ECO Strategies

1. **Fix WNS first** — Address the worst violating path before working on TNS.
2. **Bottleneck-driven** — Fix cells that appear on the most failing paths.
3. **Vt swapping** — Swap HVT to SVT/LVT on critical paths (cheapest ECO, no placement change).
4. **Cell sizing** — Upsize drivers on critical paths, downsize on non-critical paths.
5. **Buffer insertion** — Add buffers to break long nets or boost drive.
6. **Hold fixing** — Insert delay cells on short paths after all setup ECOs are done.

## DMSA (Distributed Multi-Scenario Analysis)

DMSA runs multiple PrimeTime scenarios (corners, modes) simultaneously across multiple machines, sharing a single netlist.

### DMSA Setup

```tcl
# dmsa_setup.tcl — run on the master
set_host_options -max_cores 8

# Define scenarios
create_scenario -name func_ss_125c
create_scenario -name func_ff_m40c
create_scenario -name test_ss_125c

# Configure each scenario
current_scenario func_ss_125c
read_parasitics -format SPEF top_ss.spef
read_sdc func.sdc
set_operating_conditions ss_0p72v_125c

current_scenario func_ff_m40c
read_parasitics -format SPEF top_ff.spef
read_sdc func.sdc
set_operating_conditions ff_0p88v_m40c

# Run analysis across all scenarios
update_timing -full -scenarios {func_ss_125c func_ff_m40c test_ss_125c}

# Report across scenarios
report_timing -scenarios all -max_paths 20
report_qor -scenarios all
```

### DMSA Benefits

- Shared netlist reduces memory footprint vs. running separate PT sessions.
- Cross-scenario ECO validation — a fix in one scenario is checked against all scenarios.
- Unified reporting across all modes and corners.

## Advanced Features

### Parametric On-Chip Variation (POCV) with LVF

Liberty Variation Format (LVF) libraries contain per-cell, per-arc sigma values:

```tcl
# Read LVF-aware libraries
set_app_var si_pocv_use_lvf true
read_lib ss_0p72v_125c_lvf.lib
```

### Path-Based Analysis (PBA)

Standard graph-based analysis (GBA) is pessimistic because it computes worst-case slews globally. PBA recomputes slews along the actual path for more accurate results.

```tcl
# Enable PBA
report_timing -path_type full_clock_expanded -pba_mode exhaustive -max_paths 20
```

PBA typically recovers 10-30 ps of slack compared to GBA. Use it for signoff on critical paths.

### Hierarchical STA

For very large designs (>50M instances), run STA hierarchically:

```tcl
# Extract interface timing model
extract_model -output block_a.etm -test_design

# Use ETM at top level
read_verilog top.v
read_db block_a.etm
link_design top
```

## Common Issues and Fixes

**Issue: Timing mismatch between PnR tool and PrimeTime**
- Check parasitic extraction settings — same extractor version, same RC corners.
- Verify library versions match exactly (CCS vs. NLDM, same PVT).
- Enable SI in both tools or neither.
- Check CPPR settings — both tools must handle CPPR identically.
- Compare clock tree latencies: `report_clock_timing -type latency`.

**Issue: POCV analysis shows violations that AOCV did not**
- POCV is generally less pessimistic. If POCV shows more violations, check sigma values in LVF libraries.
- Verify `si_pocv_sigma_multiplier` — standard is 3.0 (3-sigma).
- Cross-check with AOCV depth tables — ensure AOCV tables are correctly formatted.

**Issue: SI analysis adding excessive pessimism**
- Check coupling cap extraction quality — over-extracted coupling causes false SI violations.
- Set `si_xtalk_delay_analysis_mode` to `all_violating_paths` (not `all_paths`) to focus on real issues.
- Verify aggressor switching windows are correctly computed.

**Issue: ECO changes cause new violations in other scenarios**
- Always validate ECO changes across all DMSA scenarios before committing.
- Use `check_eco -type timing` to verify no new violations are introduced.

## Best Practices

1. **Use POCV for signoff** at 7nm and below — it replaces flat OCV and AOCV with more accurate statistical modeling.
2. **Enable SI analysis** for all signoff runs — crosstalk is not optional at advanced nodes.
3. **Run PBA on the worst 100-200 paths** to recover pessimism before committing to ECO.
4. **Use DMSA** for multi-corner multi-mode signoff — it is more efficient and consistent than separate PT runs.
5. **Correlate PT with the PnR tool** before starting ECO iterations — fix systematic mismatches first.
6. **Archive PT sessions** (save_session) for each milestone — timing databases are essential for debug.
7. **Report both WNS and TNS** — WNS alone can hide widespread moderate violations.
8. **Set `timing_report_unconstrained_paths`** to identify paths missing constraints.
