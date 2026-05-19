# UPF Deep-Dive: Supply Networks, Power States, Retention, Isolation, and Level Shifting

## Overview

Unified Power Format (UPF) is the IEEE 1801 standard for specifying power intent in VLSI designs. UPF describes the power architecture separately from the RTL, defining supply networks, power domains, power states, isolation strategies, retention strategies, and level shifting requirements. Mastering UPF is essential for designing multi-voltage, power-gated SoCs where aggressive power management is a primary design goal. This guide covers UPF constructs in depth with practical implementation guidance.

## Supply Networks

### Supply Ports and Nets

UPF defines the power infrastructure using supply ports, nets, and sets:

**Supply net:**
```tcl
create_supply_net VDD
create_supply_net VSS
create_supply_net VDD_MEM
create_supply_net VDD_IO
```

**Supply port (boundary connections):**
```tcl
create_supply_port VDD -direction in
create_supply_port VSS -direction in
connect_supply_net VDD -ports {VDD}
connect_supply_net VSS -ports {VSS}
```

**Supply set (bundles of related supply nets):**
```tcl
create_supply_set SS_core -function {power VDD} -function {ground VSS}
create_supply_set SS_mem -function {power VDD_MEM} -function {ground VSS}
```

Supply sets group related power and ground nets, simplifying association with power domains.

### Supply Network Hierarchy

Supply nets are hierarchical:

- Top-level supply nets represent package/board power rails
- Supply nets propagate down through the hierarchy via supply ports
- Each hierarchical block can define local supply nets connected to parent nets
- Power switches create switchable supply nets from always-on sources

### Power Switches

```tcl
create_power_switch SW_core \
  -domain PD_core \
  -input_supply_port {vin VDD_AON} \
  -output_supply_port {vout VDD_core} \
  -control_port {sleep_ctrl sleep_signal} \
  -on_state {on vin {!sleep_ctrl}} \
  -off_state {off {sleep_ctrl}}
```

This defines a header switch that connects VDD_AON to VDD_core when sleep_ctrl is deasserted. The switch creates the switchable supply net VDD_core.

**Switch types:**
- **Header switch**: PMOS between VDD_AON and VDD_switched (most common)
- **Footer switch**: NMOS between VSS_switched and VSS (less common; creates ground bounce)
- **Fine-grain**: one switch per standard cell (integrated in cell design)
- **Coarse-grain**: column or row of switch cells shared across many standard cells

## Power Domains

### Domain Definition

A power domain is a group of logic sharing the same primary supply:

```tcl
create_power_domain PD_top -include_scope
create_power_domain PD_core -elements {u_cpu u_cache}
create_power_domain PD_io -elements {u_io_subsystem}
create_power_domain PD_always_on -elements {u_pmu u_rtc u_wakeup}
```

**Domain properties:**
- Each domain has a primary supply set (power + ground)
- Domains can be switchable (power-gated) or always-on
- Domain boundaries define where isolation and level shifters are needed
- Domains can be nested (sub-domains within parent domains)

### Domain Supply Association

```tcl
associate_supply_set SS_core -handle PD_core.primary
associate_supply_set SS_aon -handle PD_always_on.primary
```

## Power States

### Power State Table

The power state table (PST) defines the valid combinations of supply states across all domains:

```tcl
add_power_state PD_top.primary -state {ACTIVE   -supply_expr {power == FULL_ON && ground == FULL_ON}}
add_power_state PD_top.primary -state {OFF      -supply_expr {power == OFF && ground == FULL_ON}}
add_power_state PD_top.primary -state {RETENTION -supply_expr {power == PARTIAL_ON && ground == FULL_ON}}

add_port_state VDD_core -state {FULL_ON 0.9} -state {PARTIAL_ON 0.5} -state {OFF off}
add_port_state VDD_AON -state {FULL_ON 0.9}
add_port_state VSS -state {FULL_ON 0.0}
```

### System-Level Power States

```tcl
create_pst system_pst -supplies {VDD_AON VDD_core VDD_io}

add_pst_state ACTIVE -pst system_pst \
  -state {FULL_ON FULL_ON FULL_ON}
add_pst_state STANDBY -pst system_pst \
  -state {FULL_ON PARTIAL_ON OFF}
add_pst_state DEEP_SLEEP -pst system_pst \
  -state {FULL_ON OFF OFF}
```

The PST ensures that all tools (simulation, synthesis, implementation) agree on which supply states are valid and which transitions are legal.

## Isolation Strategies

### Why Isolation

When a power domain is powered down, its outputs become undefined (floating). Isolation cells clamp these outputs to a known value to prevent:

- Uncontrolled current through always-on logic inputs
- Glitches propagating to active domains
- Latch-up in receiving circuits
- Corruption of state in always-on domains

### Isolation Rules

```tcl
set_isolation ISO_core_to_aon \
  -domain PD_core \
  -isolation_power_net VDD_AON \
  -isolation_ground_net VSS \
  -clamp_value 0 \
  -applies_to outputs \
  -elements {u_cpu/data_out u_cpu/valid}

set_isolation_control ISO_core_to_aon \
  -domain PD_core \
  -isolation_signal isolate_core \
  -isolation_sense high \
  -location parent
```

**Isolation parameters:**
- **clamp_value**: 0 (clamp to ground), 1 (clamp to VDD), or latch (hold last value)
- **applies_to**: outputs (signals leaving the domain), inputs (signals entering), or both
- **location**: self (in shutting-down domain; must be powered by always-on supply) or parent (in always-on domain)
- **isolation_signal**: enable signal from the power management controller

### Isolation Cell Types

- **AND/OR isolation**: simple gate that forces output to 0 (AND with enable) or 1 (OR with enable)
- **Latch isolation**: latches the last value before shutdown; useful for maintaining bus state
- **High-impedance isolation**: tri-state output for shared buses
- **Clamp cell**: specialized cell that clamps to specific voltage level

### Isolation Timing

The isolation signal must be asserted:
1. **Before power switch turns off**: outputs are clamped while domain is still powered
2. **After power switch turns on**: isolation released after domain is fully powered and stable
3. **Margin**: typically 2-5 clock cycles of margin in each direction

## Retention Strategies

### Why Retention

Power-gated domains lose all register state when powered down. Retention flip-flops preserve critical state so the domain can resume operation without full re-initialization.

### Retention Rules

```tcl
set_retention RET_core \
  -domain PD_core \
  -retention_power_net VDD_AON \
  -retention_ground_net VSS \
  -elements {u_cpu/reg_bank/* u_cpu/pc}

set_retention_control RET_core \
  -domain PD_core \
  -save_signal {save_core high} \
  -restore_signal {restore_core high}
```

### Retention Cell Types

**Balloon latch (shadow latch):**
- Main flip-flop powered by switchable supply
- Shadow latch powered by always-on supply
- Save: copy main to shadow (on save_signal assertion)
- Restore: copy shadow to main (on restore_signal assertion)
- Area overhead: ~30-50% per flip-flop
- Always-on power: shadow latch leakage during retention

**Master-slave retention:**
- One latch (master or slave) connected to always-on supply
- Simpler but less flexible than balloon latch

### Retention Sequencing

**Sleep entry:**
1. Software saves context that is not retained (memory contents, peripheral state)
2. PMU asserts save signal (copy main registers to shadow latches)
3. PMU asserts isolation (clamp domain outputs)
4. PMU turns off power switch (domain enters retention state)

**Wake-up:**
1. Wake event triggers PMU
2. PMU turns on power switch (domain powers up)
3. PMU waits for power-good (supply stable)
4. PMU asserts restore signal (copy shadow latches to main registers)
5. PMU de-asserts isolation (domain outputs become active)
6. PMU releases reset (if reset was asserted during sleep)
7. Software restores non-retained context

### Selective Retention

Not all flip-flops need retention:

- **Retain**: program counter, critical FSM states, configuration registers, interrupt status
- **Do not retain**: pipeline registers, temporary buffers, data caches (can be re-fetched)
- **Savings**: selective retention reduces always-on power and area overhead

## Level Shifting

### Why Level Shifting

When adjacent power domains operate at different voltages, signals crossing the boundary need voltage translation:

- **Low-to-high**: signal from 0.7V domain to 0.9V domain; the receiver may not properly detect the low-voltage signal
- **High-to-low**: signal from 0.9V domain to 0.7V domain; potential reliability issue (overvoltage on thin-oxide devices)

### Level Shifter Rules

```tcl
set_level_shifter LS_core_to_io \
  -domain PD_core \
  -applies_to outputs \
  -rule both \
  -location parent

set_level_shifter LS_io_to_core \
  -domain PD_io \
  -applies_to outputs \
  -rule both \
  -location self
```

**Rule options:**
- **low_to_high**: only insert when source voltage < destination voltage
- **high_to_low**: only insert when source voltage > destination voltage
- **both**: always insert (accounts for DVFS scenarios where relative voltages may change)

### Level Shifter Types

- **Simple level shifter**: cross-coupled inverter pair; converts low-swing to high-swing
- **Enable level shifter**: combined isolation + level shifting in one cell (saves area)
- **Dual-supply level shifter**: powered by both source and destination supplies
- **Retention level shifter**: combined retention + level shifting

## UPF Verification

### Simulation-Based Verification

**Supply-aware simulation (e.g., Synopsys VCS with UPF):**
- Simulator tracks supply net states (ON, OFF, PARTIAL_ON)
- Signals in powered-down domains propagate X (undefined)
- Isolation clamps verified to produce correct values
- Retention save/restore verified against sequence
- Corruption detection: any register not retained shows X after restore

### Formal Verification

- **Power-aware equivalence checking**: verify that UPF-modified netlist is functionally equivalent to original RTL under all valid power states
- **Isolation completeness**: formally verify that all signals crossing powered-down boundaries are isolated
- **Retention completeness**: verify all required state elements have retention

### Static Checks

- **UPF consistency**: verify UPF is self-consistent (no conflicting rules, all referenced elements exist)
- **Missing isolation**: identify signals crossing power domain boundaries without isolation
- **Missing level shifters**: identify signals crossing voltage domain boundaries without level shifters
- **Supply connectivity**: verify all power domains have connected supplies in all valid states

## Common Pitfalls

1. **Forgotten isolation on feedback paths**: bidirectional signals or feedback loops crossing domain boundaries
2. **Incorrect isolation timing**: isolation asserted too late (after power-off) or released too early (before power-on)
3. **Incomplete retention**: critical state not retained; system fails to resume correctly
4. **Level shifter in wrong domain**: level shifter powered by the shutting-down domain instead of the always-on domain
5. **Missing always-on buffers**: signals from power-gated domain routed through power-gated cells before reaching isolation
6. **PST conflicts**: power states defined in UPF do not match firmware's power management sequence

## Best Practices

- Define UPF concurrently with RTL architecture; do not defer power intent to late in the project
- Use supply sets rather than individual supply net references for maintainability
- Verify UPF in simulation before synthesis; catching errors early is much cheaper
- Keep the power state table simple; every additional state multiplies verification effort
- Use naming conventions that clearly associate UPF elements with their domains (e.g., ISO_core, RET_core)
- Review UPF with both the design team and implementation team to ensure feasibility

UPF is the bridge between power architecture and physical implementation. A complete, correct, and well-verified UPF specification is essential for delivering a power-efficient SoC that functions correctly across all operating modes.
