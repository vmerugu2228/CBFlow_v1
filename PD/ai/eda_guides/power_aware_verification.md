# Power-Aware Verification

## Overview

Modern SoC designs implement sophisticated power management techniques — multiple voltage domains, power shutoff, voltage scaling, retention, and isolation — to minimize power consumption. Power-aware verification ensures that these power management features function correctly: that logic is properly isolated when domains are powered off, that state is retained when required, that level shifters handle voltage differences, and that power state transitions do not corrupt data or functionality. The Unified Power Format (UPF) is the IEEE 1801 standard that specifies power intent, and power-aware simulation tools use UPF to model and verify power behavior.

## Power Intent Specification (UPF)

### UPF Fundamentals

UPF (Unified Power Format) describes the power architecture of a design:

- **Power domains**: Groups of logic that share the same power supply.
- **Supply networks**: Power and ground rails, switches, and their connectivity.
- **Power states**: The set of valid on/off/voltage combinations for each domain.
- **Isolation strategy**: How outputs of a powered-off domain are held to known values.
- **Retention strategy**: How specific registers preserve state during power-off.
- **Level shifting**: Voltage translation between domains operating at different voltages.

### UPF Commands

```tcl
# Define power domains
create_power_domain PD_TOP -include_scope
create_power_domain PD_CPU -elements {u_cpu}
create_power_domain PD_GPU -elements {u_gpu}

# Define supply ports and nets
create_supply_port VDD -direction in
create_supply_net VDD_CPU
create_supply_net VDD_GPU
create_supply_net VSS

# Connect supplies to domains
connect_supply_net VDD_CPU -ports {PD_CPU/primary_power}
connect_supply_net VSS -ports {PD_CPU/primary_ground}

# Define power switches
create_power_switch SW_CPU \
  -domain PD_CPU \
  -input_supply_port {vin VDD} \
  -output_supply_port {vout VDD_CPU} \
  -control_port {cpu_pwr_en u_pmc/cpu_pwr_en} \
  -on_state {on_state vin {cpu_pwr_en}}

# Define isolation
set_isolation iso_cpu \
  -domain PD_CPU \
  -isolation_power_net VDD \
  -isolation_ground_net VSS \
  -clamp_value 0 \
  -applies_to outputs

# Define retention
set_retention ret_cpu \
  -domain PD_CPU \
  -retention_power_net VDD \
  -retention_ground_net VSS \
  -save_signal {save_cpu posedge} \
  -restore_signal {restore_cpu posedge}

# Define level shifters
set_level_shifter ls_cpu_to_top \
  -domain PD_CPU \
  -applies_to outputs \
  -location parent
```

## Power-Aware Simulation

### How PA Simulation Works

Power-aware simulators (VCS with MV, Xcelium with MV, Questa Power Aware) read the UPF specification alongside the RTL and model the effects of power management:

1. **Supply state tracking**: The simulator maintains the on/off/voltage state of every supply net.
2. **Corruption modeling**: When a power domain is turned off, all registers in that domain are corrupted (set to X).
3. **Isolation enforcement**: Output signals from powered-off domains are clamped to the specified isolation values.
4. **Retention modeling**: Retained registers preserve their values through power-off/on cycles when save/restore signals are properly sequenced.
5. **Level shift verification**: Signals crossing voltage domains are checked for proper level shifting.

### Corruption Behavior

When a power domain is turned off:
- All flip-flops in the domain become X (unless they are retention registers with active save/restore).
- All combinational logic outputs become X.
- Isolation cells clamp domain outputs to specified values (0, 1, or latch).

When the domain is turned back on:
- Flip-flops remain X until they are reset or initialized.
- Retained registers restore their saved values when the restore signal is asserted.

## Isolation Verification

### What Isolation Verifies

Isolation ensures that outputs from a powered-off domain do not propagate X values into active domains:

```
PD_CPU (OFF) ──→ isolation cell ──→ PD_TOP (ON)
   X values       clamp to 0       clean 0 value
```

### Isolation Verification Checks

1. **Isolation placement**: Every output signal from a switchable domain has an isolation cell.
2. **Isolation enable timing**: Isolation is enabled before the domain powers off and disabled after the domain powers on.
3. **Isolation value correctness**: Clamped values are correct for the downstream logic (e.g., bus signals clamped to avoid false transactions).
4. **Isolation power supply**: The isolation cell is powered by an always-on supply.

### Common Isolation Bugs

- **Missing isolation cell**: An output from a switchable domain reaches an always-on domain without isolation, propagating X.
- **Wrong isolation value**: The clamp value causes incorrect behavior in the receiving domain (e.g., a clamp value of 1 on an active-low reset causes an unintended reset).
- **Isolation timing**: Isolation enabled too late (after power-off) or disabled too early (before power-on), causing a window of X propagation.
- **Isolation enable signal corruption**: The isolation enable signal itself comes from the domain being powered off.

## Retention Verification

### Retention Register Behavior

Retention registers contain a shadow latch (balloon latch) that preserves the register value when the main power is removed:

1. **Save**: Before power-off, the save signal copies register values to shadow latches.
2. **Power off**: Main power is removed; shadow latches maintain state on retention supply.
3. **Power on**: Main power is restored.
4. **Restore**: The restore signal copies shadow latch values back to the registers.

### Retention Verification Checks

1. **Save timing**: Save signal asserted while the domain is still powered on.
2. **Restore timing**: Restore signal asserted after the domain is powered on and stable.
3. **Data preservation**: Register values after restore match values before save.
4. **Retention supply**: Shadow latches powered by always-on retention supply.
5. **Non-retained registers**: Registers not designated for retention must be X after power-on (verified by checking they are properly re-initialized).

### Retention Verification Test Pattern

```systemverilog
task test_retention();
  // Phase 1: Initialize and program
  write_register(CTRL_REG, 32'hDEAD_BEEF);
  write_register(CONFIG_REG, 32'hCAFE_0000);

  // Phase 2: Power down with retention
  assert_save_signal();
  power_off_domain("PD_CPU");

  // Phase 3: Verify isolation during power-off
  check_isolated_outputs();

  // Phase 4: Power up and restore
  power_on_domain("PD_CPU");
  assert_restore_signal();

  // Phase 5: Verify retained values
  read_and_check(CTRL_REG, 32'hDEAD_BEEF);
  read_and_check(CONFIG_REG, 32'hCAFE_0000);
endtask
```

## Supply On/Off Verification

### Power State Machine Verification

The power management controller (PMC) drives power state transitions. Verification must ensure:

1. **Legal transitions**: Only valid power state transitions occur (e.g., cannot go directly from full-off to full-on without intermediate states).
2. **Sequencing**: Power-up and power-down sequences follow the specified order (isolation before power-off, power-on before de-isolation).
3. **Timing**: Minimum power-on stabilization time is respected before de-isolation and restore.
4. **Completeness**: All defined power states are reachable and tested.

### Power State Table

```
Power State  | PD_TOP | PD_CPU | PD_GPU | Description
-------------|--------|--------|--------|------------
FULL_ON      | ON     | ON     | ON     | All domains active
CPU_ONLY     | ON     | ON     | OFF    | GPU powered off
GPU_ONLY     | ON     | OFF    | ON     | CPU powered off
STANDBY      | ON     | OFF    | OFF    | Both powered off
```

### Power State Transition Assertions

```systemverilog
// Assert legal power state transitions
property p_legal_transition;
  @(posedge clk)
  (state == FULL_ON) |-> ##1 (state inside {FULL_ON, CPU_ONLY, GPU_ONLY});
endproperty

// Assert isolation before power-off
property p_isolate_before_off;
  @(posedge clk)
  $fell(cpu_power_good) |-> $past(cpu_iso_enable, 1);
endproperty

// Assert save before power-off
property p_save_before_off;
  @(posedge clk)
  $fell(cpu_power_good) |-> $past(cpu_save, 2);
endproperty
```

## Level Shifter Verification

### Level Shifter Requirements

When signals cross between voltage domains, level shifters translate signal levels:

- **High-to-low**: Signal from a high-voltage domain to a low-voltage domain.
- **Low-to-high**: Signal from a low-voltage domain to a high-voltage domain.
- **Enable level shifter**: Includes an enable signal for power-off scenarios.

### Level Shifter Checks

1. **Presence**: Every signal crossing voltage domains has a level shifter.
2. **Direction**: The level shifter direction matches the voltage relationship.
3. **Enable**: Enable level shifters are properly controlled during power state transitions.
4. **Supply availability**: Both input and output supplies of the level shifter are on when the signal is active.

## PA Verification Methodology

### Test Strategy

**Smoke Tests**
- Basic power-on: Verify all domains start correctly.
- Single domain power-off/on: Verify isolation and retention for each domain individually.

**Functional Tests**
- Power-off during active operations: Verify graceful handling of in-flight transactions.
- Multiple domain transitions: Verify complex power state changes.
- Retention across multiple power cycles: Verify data integrity over repeated save/restore.

**Stress Tests**
- Rapid power cycling: Fast on/off transitions testing worst-case timing.
- Concurrent power transitions: Multiple domains changing state simultaneously.
- Power transition during interrupt handling: Verify interrupt preservation and delivery.

### PA-Specific Coverage

```systemverilog
covergroup cg_power_states;
  cp_state: coverpoint power_state {
    bins full_on   = {FULL_ON};
    bins cpu_only  = {CPU_ONLY};
    bins gpu_only  = {GPU_ONLY};
    bins standby   = {STANDBY};
  }

  cp_transitions: coverpoint power_state {
    bins on_to_cpu_only = (FULL_ON => CPU_ONLY);
    bins cpu_only_to_on = (CPU_ONLY => FULL_ON);
    bins on_to_standby  = (FULL_ON => GPU_ONLY => STANDBY);
    // ... all legal transitions
  }
endgroup
```

## Tool Flows

### Synopsys VCS-MV

```bash
vcs -sverilog -upf power.upf -power_top tb.dut design.sv testbench.sv
simv +UPF_VERBOSE
```

### Cadence Xcelium PA

```bash
xrun -sv -upf power.upf -uvmhome CDNS-1.2 design.sv testbench.sv
```

### Siemens Questa Power Aware

```bash
vlog design.sv testbench.sv
vsim -pa_upf power.upf -do "run -all" tb_top
```

## Best Practices

1. **Verify power intent early** — run PA simulation as soon as UPF is available, even before full testbench is ready.
2. **Check for X propagation** — every X after power-on must be intentional (non-retained register) or a bug.
3. **Test all power state transitions** with coverage to prove all paths have been exercised.
4. **Verify isolation values** against downstream logic requirements — wrong clamp values cause subtle functional bugs.
5. **Automate save/restore timing checks** with assertions to catch sequencing errors.
6. **Run PA simulation in regression** — not just as a one-time check.

## Summary

Power-aware verification is essential for modern low-power SoC designs. UPF specifies the power architecture; PA simulation models supply on/off, isolation, retention, and level shifting. Verification must confirm that isolation prevents X propagation, retention preserves critical state, power state transitions follow legal sequences, and level shifters handle all voltage crossings. A disciplined PA verification methodology with comprehensive coverage of power states and transitions is required for sign-off confidence.
