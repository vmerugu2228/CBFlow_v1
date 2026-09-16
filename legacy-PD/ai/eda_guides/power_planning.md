# Power Intent: UPF, Power Domains, and Low-Power Design Strategy

## Overview

Power management is a first-class concern in modern SoC design. The Unified Power Format (UPF, IEEE 1801) is the industry-standard specification for expressing power intent -- the description of power domains, supply networks, power states, and the special cells (isolation, retention, level shifters) needed to implement multi-voltage and power-gating strategies.

Physical design engineers must understand UPF because it directly drives floorplanning decisions, cell placement, power grid design, and verification. Mistakes in power intent implementation cause silicon failures that are nearly impossible to fix post-fabrication.

## UPF Fundamentals

### What UPF Describes

UPF is a TCL-based format that specifies:
- Power domains and their scope (which logic belongs to which domain)
- Supply networks (VDD, VSS, and their connections)
- Power states (ON, OFF, RETENTION for each domain)
- Power state transitions (legal sequences between states)
- Isolation strategy (which signals need isolation when a domain powers down)
- Retention strategy (which registers retain state during power gating)
- Level shifting strategy (which signals cross voltage domains)

### UPF Scope Levels

UPF supports hierarchical power intent:
- **Top-level UPF**: Defines chip-level domains, supplies, and states
- **Block-level UPF**: Defines power intent within a macro/block
- **UPF refinement**: Lower-level UPF can refine (add detail to) higher-level intent

## Power Domains

### Definition

A power domain is a group of logic elements that share a common power supply and can be independently controlled (powered on/off):

```tcl
create_power_domain PD_CPU -include_scope
create_power_domain PD_GPU -elements {gpu_top}
create_power_domain PD_ALWAYS_ON -elements {aon_logic pmu}
```

### Domain Types

- **Always-on domain**: Never powered down. Contains power management unit (PMU), wakeup logic, retention control, and always-on interconnect
- **Switchable domain**: Can be powered down to save leakage. Contains logic that is not needed in all operating modes
- **Multi-voltage domain**: Operates at a different voltage than neighboring domains for power/performance optimization

### Supply Sets

Each power domain has an associated supply set defining its power and ground connections:

```tcl
create_supply_port VDD_CPU
create_supply_port VSS
create_supply_net VDD_CPU -domain PD_CPU
create_supply_net VSS -domain PD_CPU
create_supply_set SS_CPU -function {power VDD_CPU} -function {ground VSS}
```

## Power States

### State Definitions

Power states describe the operating condition of each domain:

```tcl
add_power_state PD_CPU \
  -state ON  {-supply_expr {power == FULL_ON}} \
  -state RET {-supply_expr {power == PARTIAL_ON}} \
  -state OFF {-supply_expr {power == OFF}}
```

Common states:
- **ON**: Domain fully powered, logic operational
- **OFF**: Domain power gated, all state lost
- **RETENTION**: Domain power reduced to minimum retention voltage, registers hold state
- **STANDBY**: Domain powered but clocks gated (not a UPF power state per se, but a common operating mode)

### Power State Table

The power state table defines legal combinations of domain states:

```tcl
create_pst chip_pst -supplies {VDD_CPU VDD_GPU VDD_AON VSS}
add_pst_state ACTIVE -pst chip_pst -state {ON ON ON ON}
add_pst_state GPU_OFF -pst chip_pst -state {ON OFF ON ON}
add_pst_state SLEEP -pst chip_pst -state {OFF OFF ON ON}
```

This table is critical for verification -- it defines which state combinations are legal.

## Isolation Strategy

### Why Isolation is Needed

When a power domain is shut down, its outputs become undefined (floating). These floating signals can cause:
- Short-circuit current in downstream always-on logic
- Incorrect logic values propagating through the design
- Latch-up in receiving cells

### Isolation Cells

Isolation cells clamp the output of a powered-down domain to a known value (0 or 1):

```tcl
set_isolation iso_cpu_to_aon \
  -domain PD_CPU \
  -isolation_power_net VDD_AON \
  -isolation_ground_net VSS \
  -clamp_value 0 \
  -applies_to outputs
```

Key parameters:
- **Clamp value**: 0 (clamp low) or 1 (clamp high). Choose based on downstream logic requirements
- **Isolation power**: Must come from an always-on supply
- **Location**: Isolation cells can be inside the powered-down domain (source-side) or in the receiving domain (sink-side)
- **Enable signal**: Controlled by the power management unit

### Isolation Cell Placement

- Source-side isolation: Cells are in the powered-down domain, powered by always-on supply feed-through
- Sink-side isolation: Cells are in the receiving (always-on) domain
- Most flows use source-side isolation for cleaner physical implementation
- Isolation cells must be placed at or near the domain boundary

## Retention Strategy

### Why Retention is Needed

When a power domain is gated for leakage reduction, all register state is lost. If the domain needs to resume operation quickly without re-initialization, retention registers preserve critical state at reduced voltage.

### Retention Registers

Retention flip-flops have a shadow latch (balloon latch) that stores the register value when the save signal is asserted:

```tcl
set_retention ret_cpu \
  -domain PD_CPU \
  -retention_power_net VDD_RET \
  -retention_ground_net VSS \
  -save_signal {save_cpu high} \
  -restore_signal {restore_cpu high}
```

### Retention Implementation

- **Save operation**: Before power-down, assert the save signal to capture register state in the balloon latch
- **Power down**: Main supply is gated; retention supply (VDD_RET, typically 0.4-0.6V) keeps balloon latches alive
- **Restore operation**: After power-up, assert the restore signal to transfer state back to the main register

### Retention Considerations

- Retention flip-flops are 20-50% larger than standard flip-flops
- Not all registers need retention -- only state that is expensive to reconstruct
- Retention supply routing must be always-on and reliable
- Save/restore timing must be carefully managed by the power sequencer

## Always-On Networks

### Always-On Logic

Certain logic must remain active when surrounding domains are powered down:
- Power management controller
- Wakeup interrupt logic
- Clock controllers
- Isolation and retention control signals

### Always-On Buffers

Signals that traverse a powered-down domain must use always-on buffers:
- These buffers are powered by the always-on supply
- They maintain signal integrity through powered-down regions
- UPF specifies always-on requirements; the tool inserts appropriate buffers

```tcl
set_isolation iso_feedthrough \
  -domain PD_CPU \
  -no_isolation \
  -elements {feedthrough_signals}
```

## Power Switches

### Header vs. Footer Switches

Power switches (also called MTCMOS switches) gate the supply to a domain:

- **Header switch**: PMOS switch between VDD and virtual VDD (VDDV). Placed at the top of the power rail
- **Footer switch**: NMOS switch between virtual VSS (VSSV) and VSS. Placed at the bottom of the power rail

Header switches are more common because they directly gate VDD.

### Switch Design Considerations

- **Switch cell size**: Large enough to supply peak current without excessive voltage drop
- **Daisy-chain control**: Switch cells are daisy-chained so they turn on sequentially, limiting inrush current
- **Rush current management**: Simultaneous turn-on of all switches causes a massive current spike. Sequential enable with controlled ramp-up mitigates this
- **Switch placement**: Distributed uniformly across the domain for even power delivery

## Physical Implementation

### Floorplanning for Power Domains

- Group all cells of the same domain in a contiguous region
- Plan domain boundaries as rectilinear regions (not arbitrary shapes)
- Place isolation cells at domain boundaries
- Route always-on supply rails through powered-down regions

### Power Grid for Multi-Domain

- Each switchable domain needs virtual VDD (VDDV) rails driven by power switches
- Always-on VDD and VSS must be routed to all domains for isolation cells and retention registers
- Separate power grid planning for each domain's supply

### Verification

1. **UPF consistency**: Verify UPF syntax and semantics with UPF checkers
2. **Isolation completeness**: Every signal crossing from a switchable domain to an always-on domain must have isolation
3. **Retention correctness**: Verify save/restore sequences in simulation
4. **Power state coverage**: Simulate all legal power state transitions
5. **Level shifter completeness**: Every signal crossing voltage domains must have a level shifter

## Practical Guidance

1. **Define power intent before RTL freeze**: Power domains, states, and strategies should be defined during architecture, not during implementation
2. **Minimize domain count**: Each additional domain adds complexity. Combine domains where possible
3. **Choose clamp values carefully**: Incorrect clamp values cause functional failures. Analyze downstream logic requirements
4. **Budget for retention area**: Retention flip-flops add 20-50% area overhead. Account for this in die size estimation
5. **Verify across all states**: Every legal power state transition must be verified. Missing coverage leads to silicon bugs
6. **Always-on routing**: Plan always-on supply routing early. These routes must be robust and verified for IR drop at minimum supply voltage
