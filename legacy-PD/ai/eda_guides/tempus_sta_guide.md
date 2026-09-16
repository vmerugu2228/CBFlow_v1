# Cadence Tempus STA Guide

## Overview

Tempus Timing Signoff Solution is Cadence's static timing analysis tool for signoff-quality timing verification. Tempus integrates tightly with the Cadence Innovus PnR flow and provides advanced capabilities including SOCV (Statistical OCV), signal integrity analysis, concurrent MMMC analysis, and ECO guidance. It serves as the signoff counterpart to Innovus, similar to how PrimeTime serves as signoff for the Synopsys flow.

## Tempus Architecture

Tempus shares the same timing engine as Innovus, which provides excellent correlation between implementation and signoff. This is a key advantage — timing numbers in Innovus closely match Tempus signoff, reducing late-stage surprises.

Key capabilities:

- **Concurrent MMMC:** Analyze all modes and corners simultaneously in a single session.
- **SOCV:** Statistical OCV for accurate variation modeling.
- **SI analysis:** Crosstalk-aware timing with coupling capacitance.
- **ECO guidance:** Recommend and validate timing fixes.
- **Hierarchical analysis:** Interface timing models for large SoCs.

## Basic Tempus Flow

### Design Setup and Read-In

```tcl
# Read MMMC configuration
read_mmmc mmmc_setup.tcl

# Read physical design
read_physical -lefs {tech.lef stdcell.lef macros.lef}
read_netlist top_routed.v
read_def top_routed.def

init_design

# Read parasitics for each corner
read_spef -rc_corner rc_worst top_worst.spef
read_spef -rc_corner rc_best  top_best.spef

# Set propagated clocks (use real CTS delays)
set_interactive_constraint_modes [all_constraint_modes]
set_propagated_clock [all_clocks]
```

### MMMC Setup

```tcl
# mmmc_setup.tcl
# Library sets
create_library_set -name libs_ss -timing {ss_0p72v_125c.lib mem_ss.lib}
create_library_set -name libs_ff -timing {ff_0p88v_m40c.lib mem_ff.lib}
create_library_set -name libs_tt -timing {tt_0p80v_25c.lib mem_tt.lib}

# RC corners
create_rc_corner -name rc_worst -qrc_tech worst.qrcTechFile
create_rc_corner -name rc_best  -qrc_tech best.qrcTechFile
create_rc_corner -name rc_typ   -qrc_tech typ.qrcTechFile

# Delay corners
create_delay_corner -name dc_ss -library_set libs_ss -rc_corner rc_worst \
    -opcond ss_0p72v_125c
create_delay_corner -name dc_ff -library_set libs_ff -rc_corner rc_best \
    -opcond ff_0p88v_m40c
create_delay_corner -name dc_tt -library_set libs_tt -rc_corner rc_typ \
    -opcond tt_0p80v_25c

# Constraint modes
create_constraint_mode -name cm_func -sdc_files {func.sdc}
create_constraint_mode -name cm_test -sdc_files {test.sdc}
create_constraint_mode -name cm_scan -sdc_files {scan.sdc}

# Analysis views
create_analysis_view -name func_ss -constraint_mode cm_func -delay_corner dc_ss
create_analysis_view -name func_ff -constraint_mode cm_func -delay_corner dc_ff
create_analysis_view -name test_ss -constraint_mode cm_test -delay_corner dc_ss
create_analysis_view -name scan_ss -constraint_mode cm_scan -delay_corner dc_ss

# Active views
set_analysis_view -setup {func_ss test_ss scan_ss} -hold {func_ff}
```

### Timing Analysis and Reporting

```tcl
# Update timing
update_timing -full

# Report setup timing
report_timing -max_paths 100 -nworst 3 -path_type full_clock \
    -net -cap -tran > rpt/setup.rpt

# Report hold timing
report_timing -early -max_paths 100 -nworst 3 > rpt/hold.rpt

# Report across all views
report_timing -max_paths 20 -view func_ss > rpt/timing_func_ss.rpt
report_timing -max_paths 20 -view test_ss > rpt/timing_test_ss.rpt

# QoR summary
report_analysis_summary > rpt/analysis_summary.rpt

# Constraint violations
report_constraint -all_violators > rpt/violations.rpt

# Clock timing
report_clock_timing -type summary > rpt/clock_summary.rpt
report_clock_timing -type skew > rpt/clock_skew.rpt
```

## SOCV (Statistical OCV)

SOCV is Cadence's implementation of statistical variation analysis, analogous to Synopsys POCV.

### SOCV Setup

```tcl
# Enable SOCV
set_db timing_analysis_socv true

# Read SOCV data (Liberty Variation Format)
# LVF data is typically embedded in the .lib files
# or provided as separate .socv files
read_lib ss_0p72v_125c_lvf.lib

# Set sigma multiplier
set_db timing_socv_sigma_multiplier 3.0

# Set random and systematic variation components
set_db timing_analysis_socv_statistical_mode true
```

### SOCV Reporting

```tcl
# Report with SOCV information
report_timing -socv -max_paths 20

# Report variation contribution per stage
report_timing -socv -path_type full_clock -fields {socv_mean socv_sigma}

# Compare GBA vs PBA with SOCV
report_timing -socv -path_type full_clock -pba_mode path
```

### SOCV vs. Flat OCV

| Metric | Flat OCV | SOCV |
|--------|----------|------|
| Setup pessimism | High (5-15%) | Low (RSS reduces uncertainty) |
| Hold pessimism | High | Low |
| Library requirement | Standard .lib | LVF .lib |
| Runtime overhead | None | 10-20% |
| Accuracy | Conservative | Realistic |

SOCV typically recovers 20-50 ps of slack compared to flat OCV at advanced nodes.

## Signal Integrity Analysis

### SI Setup in Tempus

```tcl
# Enable SI analysis
set_db si_analysis_type aae  ;# AAE = Advanced Aggressor Enumeration
set_db si_delay_separate_on_data true
set_db si_delay_enable_report true

# Read parasitics with coupling caps
read_spef -rc_corner rc_worst top_worst_coupled.spef

# Set SI thresholds
set_db si_glitch_input_voltage_high 0.6
set_db si_glitch_input_voltage_low 0.4

# Update timing with SI
update_timing -full
```

### SI Reporting

```tcl
# Report SI-induced delay
report_timing -si -max_paths 50 > rpt/si_timing.rpt

# Report noise/glitch violations
report_noise -above_high -below_low > rpt/noise.rpt

# Identify worst aggressors
report_noise -victim net_name -aggressors > rpt/aggressors.rpt
```

## Concurrent MMMC Analysis

Tempus's concurrent MMMC capability analyzes all scenarios simultaneously, which provides several advantages over running scenarios independently:

- Cross-scenario constraint checking
- Shared data model reduces memory
- ECO changes validated across all scenarios simultaneously

```tcl
# Report timing across all active views
foreach view [all_analysis_views] {
    report_timing -view $view -max_paths 20 > rpt/timing_${view}.rpt
}

# Summary across all views
report_analysis_summary > rpt/mmmc_summary.rpt
```

## ECO Guidance

Tempus can recommend timing ECO actions and validate their impact.

### Timing ECO Commands

```tcl
# Automatic ECO optimization
opt_design -post_route

# Manual ECO: cell sizing
ecoChangeCell -inst u_buf_weak -cell BUFX8

# Manual ECO: buffer insertion
ecoAddRepeater -net long_net -cell BUFX4 -name eco_buf_1

# Manual ECO: Vt swapping
ecoChangeCell -inst u_gate_hvt -cell AND2X2_SVT

# Validate ECO
update_timing -full
report_timing -max_paths 20
```

### ECO Export

```tcl
# Write ECO script for Innovus
write_eco_opt_db -dir eco_db

# Or write Innovus-compatible ECO commands
saveEcoChanges -file eco_changes.tcl
```

## Hierarchical Analysis

For large designs, Tempus supports hierarchical analysis using Extracted Timing Models (ETM).

### ETM Extraction

```tcl
# At block level
read_design block_a
update_timing -full

# Extract ETM
do_extract_model -name block_a_etm \
    -cell_type lib_cell \
    -output_dir etm_output
```

### Top-Level with ETMs

```tcl
# At top level
read_lib block_a_etm.lib
read_netlist top.v
init_design

# Analyze with block models
update_timing -full
report_timing -max_paths 50
```

## Advanced Features

### Graph-Based vs. Path-Based Analysis

```tcl
# Graph-based analysis (default, conservative)
report_timing -max_paths 20

# Path-based analysis (less pessimistic, more accurate)
report_timing -max_paths 20 -pba_mode path

# Exhaustive PBA (most accurate, slower)
report_timing -max_paths 20 -pba_mode exhaustive
```

PBA recomputes slews along the actual sensitized path rather than using globally worst-case slews. This typically recovers 10-30 ps of artificial pessimism.

### CPPR (Common Path Pessimism Removal)

```tcl
# Enable CPPR (should always be on)
set_db timing_cppr_enabled true

# Report CPPR credit
report_timing -cppr -max_paths 10
```

### Clock Reconvergence Pessimism

```tcl
# Report clock reconvergence
report_clock_timing -type reconvergence

# Identify problematic reconvergent paths
report_timing -clock_reconvergence_pessimism -max_paths 20
```

## Integration with Innovus

Tempus and Innovus share the same database format and timing engine, enabling seamless handoff:

```tcl
# In Innovus: save for Tempus analysis
saveDesign top_routed.enc

# In Tempus: restore design
restoreDesign top_routed.enc.dat top

# Or read Innovus output directly
read_design -physical_data top_routed.enc.dat
```

## Common Issues and Fixes

**Issue: Timing mismatch between Innovus and Tempus**
- Verify that library versions are identical.
- Check SPEF extraction settings — same extractor version and options.
- Ensure MMMC setup is identical between tools.
- Compare `report_clock_timing` between tools to check CTS correlation.
- Check SI settings — both must have SI enabled or disabled.

**Issue: SOCV analysis significantly different from flat OCV**
- Verify LVF library quality — check sigma values are reasonable.
- Compare sigma_multiplier settings.
- Run both SOCV and flat OCV and compare the top 50 paths — the delta should be consistent.

**Issue: SI violations causing timing failures not seen in Innovus**
- Check that coupling caps in SPEF are extracted at the same fidelity.
- Verify aggressor alignment windows.
- Ensure SI delay mode settings match between tools.

**Issue: ECO changes fixing one view but breaking another**
- Use concurrent MMMC ECO validation — always check all active views.
- Prioritize fixes that improve the worst view without degrading others.
- Use Vt swapping as the first ECO action — it rarely causes cross-view degradation.

**Issue: Long runtime for SOCV analysis**
- Reduce the number of paths analyzed: focus on top violators.
- Use PBA selectively (not on all paths).
- Increase machine memory — SOCV requires approximately 30% more memory than non-SOCV.

## Best Practices

1. **Use the same MMMC setup** in both Innovus and Tempus to ensure consistency.
2. **Enable SOCV for signoff** at advanced nodes — flat OCV leaves excessive margin on the table.
3. **Run PBA on the worst 100 paths** before committing to ECO — many apparent violations disappear under PBA.
4. **Always run SI analysis** for signoff — coupling effects are significant at 7nm and below.
5. **Correlate with Innovus first** — fix systematic mismatches before starting path-level ECO.
6. **Use ETMs for large SoC signoff** — full-flat analysis at 50M+ instances is impractical.
7. **Archive Tempus databases** at each signoff milestone for audit and debug.
8. **Report unconstrained paths** to catch missing SDC coverage.
9. **Validate clock domain crossings** — Tempus can identify CDC paths that may need false_path or synchronizer constraints.
10. **Use `report_analysis_summary`** as the primary signoff dashboard — it shows WNS/TNS across all views in one table.
