# Low Power Verification (UPF Verification)

## Overview

Low power designs implement multiple power domains, voltage islands, power gating, retention, isolation, and level shifting to minimize power consumption. The Unified Power Format (UPF, IEEE 1801) specifies this power architecture. Verifying that the power intent is correctly implemented is critical — a missing isolation cell, incorrect retention strategy, or broken power sequence can cause silicon failure. Low power verification tools check both the UPF specification itself and its implementation in the gate-level netlist and physical layout.

## Power Architecture Concepts

### Power Domains

A power domain is a collection of logic elements that share the same power supply. Each domain can be independently powered on or off.

```tcl
# UPF power domain definition
create_power_domain PD_TOP
create_power_domain PD_CORE -elements {u_core}
create_power_domain PD_GPU -elements {u_gpu}
create_power_domain PD_ALWAYS_ON -elements {u_pmu u_wakeup}
```

### Power States

Each power domain has defined power states (ON, OFF, or specific voltage levels):

```tcl
add_port_state VDD_CORE -state {FULL_ON 0.80} -state {LOW_V 0.60} -state {OFF off}
add_port_state VDD_GPU -state {ON 0.80} -state {OFF off}
add_port_state VDD_AON -state {ON 0.80}

create_pst power_state_table -supplies {VDD_CORE VDD_GPU VDD_AON}
add_pst_state ALL_ON    -pst power_state_table -state {FULL_ON ON ON}
add_pst_state GPU_OFF   -pst power_state_table -state {FULL_ON OFF ON}
add_pst_state CORE_LOW  -pst power_state_table -state {LOW_V ON ON}
add_pst_state SLEEP     -pst power_state_table -state {OFF OFF ON}
```

### Isolation Cells

Isolation cells clamp the outputs of a powered-off domain to a known value (0 or 1) to prevent floating signals from corrupting active domains.

```tcl
set_isolation iso_core_out -domain PD_CORE \
    -applies_to outputs \
    -clamp_value 0 \
    -isolation_signal core_iso_en \
    -isolation_sense high \
    -location parent

set_isolation iso_gpu_out -domain PD_GPU \
    -applies_to outputs \
    -clamp_value 1 \
    -isolation_signal gpu_iso_en \
    -isolation_sense high \
    -location self
```

**Isolation rules:**

- Every signal crossing from a switchable domain to an always-on or independently-powered domain must be isolated.
- Isolation cells must be powered by the receiving domain's supply (or an always-on supply).
- The isolation enable signal must be asserted before the domain powers off and deasserted after it powers on.

### Retention Registers

Retention flip-flops preserve their state when the domain is powered off, allowing quick resume without re-initialization.

```tcl
set_retention ret_core -domain PD_CORE \
    -retention_power_net VDD_AON \
    -retention_ground_net VSS \
    -save_signal {save_en posedge} \
    -restore_signal {restore_en posedge}

# Apply to specific registers
set_retention ret_core -elements {u_core/reg_bank*}
```

**Retention rules:**

- Save must be asserted before power-off.
- Restore must be asserted after power-on and before normal operation resumes.
- The retention supply (balloon supply) must remain on during the power-off state.

### Level Shifters

Level shifters translate signal voltage levels between domains operating at different voltages.

```tcl
set_level_shifter ls_core_to_io -domain PD_CORE \
    -applies_to outputs \
    -rule both \
    -location parent

set_level_shifter ls_io_to_core -domain PD_IO \
    -applies_to outputs \
    -rule both \
    -location self
```

**Level shifter rules:**

- Required when signals cross between domains with different supply voltages.
- Must handle both high-to-low and low-to-high transitions.
- Placement location determines which supply powers the level shifter.

### Always-On Logic

Logic that must remain powered during all power states. Includes:

- Power management unit (PMU)
- Wake-up controllers
- Isolation enable/disable logic
- Retention save/restore controllers
- Clock distribution to always-on domains

```tcl
# Mark cells as always-on
set_design_attributes -elements {u_pmu} -attribute always_on_logic true
```

## Verification Tools

### Synopsys VC-LP (Verification Compiler Low Power)

VC-LP verifies UPF intent and implementation through structural and formal checks.

#### VC-LP Flow

```tcl
# Read UPF
read_power_intent -upf top.upf

# Read design
read_verilog top_routed.v
elaborate top

# Run structural checks
check_lp -type structural

# Run power state checks
check_lp -type power_state

# Run isolation checks
check_lp -type isolation

# Run retention checks
check_lp -type retention

# Run level shifter checks
check_lp -type level_shifter

# Run all checks
check_lp -all

# Report
report_lp_violations
report_lp_summary
```

#### VC-LP Check Categories

| Check | What It Verifies |
|-------|-----------------|
| Structural | UPF syntax, domain definitions, supply connections |
| Isolation | Every crossing signal has proper isolation cell |
| Retention | Retention cells present, save/restore connections correct |
| Level shifter | Voltage crossings have proper level shifters |
| Power state | Power state table is consistent and complete |
| Always-on | Always-on paths are correctly identified |
| Sequence | Power-up/down sequence is safe |

### Cadence Conformal LP

Conformal Low Power provides UPF verification within the Conformal formal verification framework.

#### Conformal LP Flow

```tcl
# Read design
read_library -liberty std.lib
read_design -golden -verilog top_syn.v
read_design -revised -verilog top_routed.v

# Read UPF
read_power_intent -golden -upf top.upf
read_power_intent -revised -upf top.upf

# Set system mode
set_system_mode lec

# Run low power checks
check_lp

# Report
report_lp -type isolation
report_lp -type retention
report_lp -type level_shifter
report_lp -type always_on
report_lp -summary
```

#### Conformal LP Check Types

1. **Isolation completeness:** Every signal crossing a power domain boundary has an isolation cell.
2. **Isolation correctness:** Isolation cells are connected to the correct supply and enable signal.
3. **Retention completeness:** All specified registers have retention cells.
4. **Retention correctness:** Save/restore signals are properly connected.
5. **Level shifter completeness:** All voltage-crossing signals have level shifters.
6. **Supply correctness:** All cells are connected to their intended power supply.
7. **Always-on path verification:** Paths through always-on logic are not broken by power-gated cells.

## UPF Verification Methodology

### Stage 1: UPF Intent Verification

Verify the UPF specification itself, independent of implementation:

- Power domain hierarchy is correct and complete
- Supply network is properly defined
- Power state table covers all operating modes
- Isolation, retention, and level shifter strategies cover all boundary crossings
- No conflicting or redundant specifications

### Stage 2: Pre-Synthesis UPF Check

Verify UPF against RTL before synthesis:

```tcl
# Check UPF consistency with RTL
read_hdl -sv top.sv
read_power_intent -upf top.upf
check_power_intent -stage pre_synth
```

### Stage 3: Post-Synthesis Structural Check

Verify that synthesis correctly implemented the UPF:

- Isolation cells are inserted at all required locations
- Retention cells replace standard flip-flops in specified locations
- Level shifters are inserted for voltage crossings
- Always-on buffers are used in always-on paths

### Stage 4: Post-PnR Physical Check

Verify physical implementation:

- Isolation cells are powered by the correct supply rail
- Retention balloon supplies are connected
- Level shifters have access to both voltage supplies
- Power switches (header/footer cells) are properly placed and connected
- Always-on routing is on always-on power rails

### Stage 5: Signoff Verification

Final comprehensive check before tapeout:

- Re-run all structural checks on the final netlist
- Verify power domain connectivity in the physical layout (LVS)
- Verify supply voltage levels at all cells (IR drop analysis per domain)

## Common Issues and Fixes

**Issue: Missing isolation cells detected**
- Review the UPF `set_isolation` scope — ensure `-applies_to outputs` covers all signals crossing the boundary.
- Check for signals that bypass the domain hierarchy (e.g., feed-through nets).
- Verify that the synthesis tool's isolation insertion is enabled and configured correctly.
- Some signals (e.g., static configuration) may legitimately not need isolation — add exceptions in UPF.

**Issue: Retention cells not implemented**
- Verify that retention library cells are available in the technology library.
- Check that the `set_retention` UPF command specifies the correct domain and elements.
- Ensure the synthesis tool supports retention cell mapping for the target library.
- Check save/restore signal connectivity — missing connections cause the tool to skip retention.

**Issue: Level shifter violations**
- Verify that level shifter library cells support the required voltage combinations.
- Check the `set_level_shifter -rule` parameter — `low_to_high`, `high_to_low`, or `both`.
- Ensure level shifter cells have access to both supply voltages.

**Issue: Always-on path broken by power-gated cell**
- Trace the signal path from always-on source to always-on destination.
- Insert always-on buffers to replace any standard buffers on the path.
- Verify that the always-on cells are connected to the always-on power supply.

**Issue: Power sequencing violation**
- Verify that isolation is asserted before power-down and deasserted after power-up.
- Verify that save is asserted before power-down and restore after power-up.
- Check for race conditions between isolation enable and power switch control.

**Issue: UPF-netlist mismatch after ECO**
- After any ECO, re-run LP verification to catch new boundary crossings.
- ECOs that add or modify cells near domain boundaries are high-risk for LP violations.
- Update UPF if the ECO intentionally changes the power architecture.

## Best Practices

1. **Define UPF early** in the design phase — retro-fitting power domains is extremely expensive.
2. **Verify UPF at every stage** — pre-synthesis, post-synthesis, post-PnR, post-ECO.
3. **Start with structural checks** before running formal LP checks — fix syntax and completeness first.
4. **Use the same UPF file** across all tools (synthesis, PnR, verification) to avoid inconsistency.
5. **Test power sequences in simulation** — formal checks verify structure, but simulation verifies temporal behavior.
6. **Document every isolation exception** — if a signal intentionally lacks isolation, explain why in the UPF comments.
7. **Verify always-on paths carefully** — a single standard cell in an always-on path causes domain-wide failure.
8. **Check retention balloon supply** connectivity in the physical layout — this is a common miss.
9. **Run LP checks after every ECO** — ECOs frequently introduce new LP violations.
10. **Maintain a power domain crossing register** that lists every signal crossing a domain boundary with its isolation/level shifter strategy — this is the single most important LP debug artifact.
