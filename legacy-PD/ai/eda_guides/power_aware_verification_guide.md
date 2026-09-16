# Power-Aware Verification Complete Guide

Comprehensive guide for power-aware verification covering UPF simulation,
isolation verification, retention verification, level shifters, always-on
logic, power state machine verification, power-aware assertions, PA-SIM
vs PA-GLS methodology, and power-aware coverage metrics.

---

## 1. Power-Aware Verification Overview

### 1.1 Why Power-Aware Verification?

Modern SoC designs implement complex power management strategies including
multiple voltage domains, power gating, retention, and dynamic voltage/frequency
scaling (DVFS). These features introduce failure modes invisible in standard
RTL simulation.

**Power-Related Failure Modes:**

| Failure Mode | Description | Impact |
|-------------|-------------|--------|
| Isolation failure | Output from powered-off domain not clamped | X/Z propagation |
| Retention failure | Register state lost during power down | Data corruption |
| Level shift error | Incorrect voltage translation | Logic error |
| Power sequence error | Wrong order of power-up/down steps | Design hang |
| Always-on corruption | Always-on logic affected by power event | System failure |
| Supply ramp issue | Logic operates during unstable supply | Metastability |
| Corruption semantics | Registers not properly corrupted on power off | Masked bugs |

### 1.2 Power Intent Specification

Power intent is specified using UPF (Unified Power Format, IEEE 1801) or
CPF (Common Power Format, Cadence legacy).

**UPF Key Concepts:**

```
UPF Hierarchy:
  Supply Network
    +-- Supply Set (VDD, VSS pairs)
    +-- Supply Port (connection point)
    +-- Supply Net (routing)
  Power Domain
    +-- Elements (instances assigned to domain)
    +-- Supply Set (power/ground)
    +-- Power State (ON, OFF, RETENTION)
  Power State Table
    +-- States per domain
    +-- Legal state combinations
  Isolation Strategy
    +-- Location (source/destination)
    +-- Clamp value
    +-- Enable signal
  Retention Strategy
    +-- Save/restore signals
    +-- Retention type
  Level Shifter Strategy
    +-- Direction (high-to-low, low-to-high)
    +-- Type (HL, LH, HL_LH)
```

### 1.3 Verification Strategy Overview

```
Power-Aware Verification Strategy:

Level 1: UPF Lint / Static Checks
  - UPF syntax and semantics
  - Supply network connectivity
  - Missing isolation/level shifters
  - Power state table consistency

Level 2: PA-SIM (Power-Aware RTL Simulation)
  - UPF-aware simulation with corruption
  - Isolation verification
  - Retention verification
  - Power state machine verification

Level 3: PA-GLS (Power-Aware Gate-Level Simulation)
  - Physical isolation cells verified
  - Physical retention cells verified
  - Level shifter cells verified
  - SDF timing with power cells

Level 4: Formal Power-Aware Verification
  - Formal proof of isolation completeness
  - Formal proof of retention correctness
  - Supply network formal analysis
```

---

## 2. UPF-Aware Simulation

### 2.1 UPF Fundamentals for Simulation

**Power Domain Definition:**

```tcl
# UPF file: my_design.upf

# Create supply ports and nets
create_supply_port VDD
create_supply_port VSS
create_supply_port VDD_CPU
create_supply_port VDD_IO

create_supply_net VDD     -domain TOP
create_supply_net VSS     -domain TOP
create_supply_net VDD_CPU -domain PD_CPU
create_supply_net VDD_IO  -domain PD_IO

# Connect supply ports to nets
connect_supply_net VDD     -ports VDD
connect_supply_net VSS     -ports VSS
connect_supply_net VDD_CPU -ports VDD_CPU
connect_supply_net VDD_IO  -ports VDD_IO

# Create power domains
create_power_domain PD_TOP \
  -supply {primary VDD VSS}

create_power_domain PD_CPU \
  -elements {u_cpu} \
  -supply {primary VDD_CPU VSS}

create_power_domain PD_IO \
  -elements {u_io_ctrl} \
  -supply {primary VDD_IO VSS}

# Set domain supply
set_domain_supply_net PD_TOP -primary_power_net VDD     -primary_ground_net VSS
set_domain_supply_net PD_CPU -primary_power_net VDD_CPU -primary_ground_net VSS
set_domain_supply_net PD_IO  -primary_power_net VDD_IO  -primary_ground_net VSS
```

**Power State Table:**

```tcl
# Define supply states
add_port_state VDD     -state {ON  0.90} -state {OFF 0.0}
add_port_state VDD_CPU -state {ON  0.90} -state {OFF 0.0} -state {RET 0.60}
add_port_state VDD_IO  -state {ON  1.80} -state {OFF 0.0}
add_port_state VSS     -state {ON  0.0}

# Power State Table
create_pst my_pst -supplies {VDD VDD_CPU VDD_IO VSS}

add_pst_state ALL_ON     -pst my_pst -state {ON  ON  ON  ON}
add_pst_state CPU_OFF    -pst my_pst -state {ON  OFF ON  ON}
add_pst_state CPU_RET    -pst my_pst -state {ON  RET ON  ON}
add_pst_state IO_OFF     -pst my_pst -state {ON  ON  OFF ON}
add_pst_state ALL_OFF    -pst my_pst -state {ON  OFF OFF ON}
add_pst_state CPU_RET_IO_OFF -pst my_pst -state {ON RET OFF ON}
```

**Isolation Strategy:**

```tcl
# Isolation for CPU domain outputs
set_isolation iso_cpu \
  -domain PD_CPU \
  -isolation_power_net VDD \
  -isolation_ground_net VSS \
  -clamp_value 0 \
  -applies_to outputs \
  -diff_supply_only TRUE

set_isolation_control iso_cpu \
  -domain PD_CPU \
  -isolation_signal pmu_cpu_iso_en \
  -isolation_sense high \
  -location parent

# Isolation for IO domain outputs
set_isolation iso_io \
  -domain PD_IO \
  -isolation_power_net VDD \
  -isolation_ground_net VSS \
  -clamp_value 0 \
  -applies_to outputs

set_isolation_control iso_io \
  -domain PD_IO \
  -isolation_signal pmu_io_iso_en \
  -isolation_sense high \
  -location parent
```

**Retention Strategy:**

```tcl
# Retention for CPU domain
set_retention ret_cpu \
  -domain PD_CPU \
  -retention_power_net VDD \
  -retention_ground_net VSS

set_retention_control ret_cpu \
  -domain PD_CPU \
  -save_signal    {pmu_cpu_save    high} \
  -restore_signal {pmu_cpu_restore high}
```

**Level Shifter Strategy:**

```tcl
# Level shifters between domains
set_level_shifter ls_cpu_to_io \
  -domain PD_CPU \
  -applies_to outputs \
  -rule high_to_low \
  -location parent

set_level_shifter ls_io_to_cpu \
  -domain PD_IO \
  -applies_to outputs \
  -rule low_to_high \
  -location self
```

### 2.2 Simulation Tool Setup

**VCS Power-Aware Simulation:**

```bash
# Compile with UPF
vcs -full64 -sverilog \
    -upf my_design.upf \
    -upf_scope tb_top.dut \
    -power=coverage \
    -power=dump \
    -power_top tb_top.dut \
    -f design.f \
    -f testbench.f \
    -top tb_top \
    -o simv_pa

# Runtime options
./simv_pa \
    +UVM_TESTNAME=power_test \
    -power=coverage \
    -power=dump+supply

# VCS power-aware options
# -upf <file>            : UPF file
# -upf_scope <scope>     : Scope for UPF application
# -power=coverage        : Power-aware coverage
# -power=dump            : Dump power events
# -power=dump+supply     : Dump supply state changes
# -power_top <scope>     : Top of power hierarchy
# -power=check           : Enable power-aware checks
# -power=corruption_off  : Disable corruption (debug only)
```

**Xcelium Power-Aware Simulation:**

```bash
# Compile with UPF
xrun -lowpower \
     -upf my_design.upf \
     -upf_scope tb_top.dut \
     -lps_verbose \
     -lps_iso_verbose \
     -lps_ret_verbose \
     -f design.f \
     -f testbench.f \
     -top tb_top

# Xcelium power options
# -lowpower              : Enable low-power simulation
# -upf <file>            : UPF file
# -lps_verbose           : Verbose power messages
# -lps_iso_verbose       : Verbose isolation messages
# -lps_ret_verbose       : Verbose retention messages
# -lps_corruption_off    : Disable corruption (debug)
# -lps_iso_off           : Disable isolation (debug)
# -lps_ret_off           : Disable retention (debug)
```

**Questa Power-Aware Simulation:**

```bash
# Compile with UPF
vlog -f design.f
vlog -f testbench.f

# Simulate with UPF
vsim -pa -upf my_design.upf \
     -pa_top /tb_top/dut \
     -pa_coverage \
     tb_top

# Questa power options
# -pa                    : Enable power-aware simulation
# -upf <file>            : UPF file
# -pa_top <scope>        : Top of power hierarchy
# -pa_coverage           : Power-aware coverage
# -pa_verbose            : Verbose power messages
# -pa_no_corruption      : Disable corruption (debug)
```

### 2.3 Supply State Control in Testbench

```systemverilog
// Control supply states from testbench
module tb_top;

  // Supply control
  supply_net_type VDD_CPU_net;

  initial begin
    // All ON initially
    supply_on("tb_top.dut.VDD",     0.90);
    supply_on("tb_top.dut.VDD_CPU", 0.90);
    supply_on("tb_top.dut.VDD_IO",  1.80);
    supply_on("tb_top.dut.VSS",     0.00);

    // Wait for reset
    @(posedge rst_n);
    repeat(100) @(posedge clk);

    // Power down CPU
    $display("[%0t] Powering down CPU domain", $time);
    supply_off("tb_top.dut.VDD_CPU");

    // Wait
    repeat(100) @(posedge clk);

    // Power up CPU
    $display("[%0t] Powering up CPU domain", $time);
    supply_on("tb_top.dut.VDD_CPU", 0.90);

    // Retention mode
    repeat(100) @(posedge clk);
    $display("[%0t] CPU entering retention", $time);
    supply_partial_on("tb_top.dut.VDD_CPU", 0.60);
  end

  // UPF-aware supply control tasks
  task supply_on(string path, real voltage);
    // Tool-specific API
    `ifdef VCS
      $supply_on(path, voltage);
    `elsif XCELIUM
      $lps_supply_on(path, voltage);
    `elsif QUESTA
      $pa_supply_on(path, voltage);
    `endif
  endtask

  task supply_off(string path);
    `ifdef VCS
      $supply_off(path);
    `elsif XCELIUM
      $lps_supply_off(path);
    `elsif QUESTA
      $pa_supply_off(path);
    `endif
  endtask

endmodule
```

### 2.4 UVM Power-Aware Sequences

```systemverilog
// Power management sequence
class power_down_cpu_sequence extends uvm_sequence;
  `uvm_object_utils(power_down_cpu_sequence)

  pmu_agent_sequencer pmu_sqr;

  task body();
    pmu_transaction tr;

    // Step 1: Save CPU state (retention)
    tr = pmu_transaction::type_id::create("tr");
    start_item(tr);
    tr.command = PMU_SAVE;
    tr.domain  = PD_CPU;
    finish_item(tr);

    // Step 2: Enable isolation
    tr = pmu_transaction::type_id::create("tr");
    start_item(tr);
    tr.command = PMU_ISO_ENABLE;
    tr.domain  = PD_CPU;
    finish_item(tr);

    // Step 3: Disable clocks
    tr = pmu_transaction::type_id::create("tr");
    start_item(tr);
    tr.command = PMU_CLK_DISABLE;
    tr.domain  = PD_CPU;
    finish_item(tr);

    // Step 4: Power off
    tr = pmu_transaction::type_id::create("tr");
    start_item(tr);
    tr.command = PMU_POWER_OFF;
    tr.domain  = PD_CPU;
    finish_item(tr);

    `uvm_info("PWR", "CPU domain powered off", UVM_LOW)
  endtask
endclass

class power_up_cpu_sequence extends uvm_sequence;
  `uvm_object_utils(power_up_cpu_sequence)

  task body();
    pmu_transaction tr;

    // Step 1: Power on
    tr = pmu_transaction::type_id::create("tr");
    start_item(tr);
    tr.command = PMU_POWER_ON;
    tr.domain  = PD_CPU;
    finish_item(tr);

    // Step 2: Enable clocks
    tr = pmu_transaction::type_id::create("tr");
    start_item(tr);
    tr.command = PMU_CLK_ENABLE;
    tr.domain  = PD_CPU;
    finish_item(tr);

    // Step 3: Restore state
    tr = pmu_transaction::type_id::create("tr");
    start_item(tr);
    tr.command = PMU_RESTORE;
    tr.domain  = PD_CPU;
    finish_item(tr);

    // Step 4: Disable isolation
    tr = pmu_transaction::type_id::create("tr");
    start_item(tr);
    tr.command = PMU_ISO_DISABLE;
    tr.domain  = PD_CPU;
    finish_item(tr);

    `uvm_info("PWR", "CPU domain powered up and restored", UVM_LOW)
  endtask
endclass
```

---

## 3. Isolation Verification

### 3.1 Isolation Requirements

Isolation cells clamp outputs from a powered-off domain to known values,
preventing X/Z propagation into active domains.

**Isolation Parameters:**

| Parameter | Description | Values |
|-----------|-------------|--------|
| Clamp value | Output value when isolated | 0, 1, latch, Z |
| Enable sense | Polarity of enable signal | high, low |
| Location | Where cell is placed | source, destination, parent |
| Applies to | Which signals are isolated | outputs, inputs, both |
| diff_supply_only | Only isolate if supply differs | TRUE, FALSE |

### 3.2 Isolation Verification Checks

```systemverilog
// Isolation verification assertions
module isolation_checker(
  input logic clk,
  input logic rst_n,
  input logic cpu_power_on,
  input logic iso_enable,
  input logic [31:0] cpu_data_out,
  input logic cpu_valid_out
);

  // 1. Isolation must be enabled before power off
  a_iso_before_off: assert property (
    @(posedge clk) disable iff (!rst_n)
    $fell(cpu_power_on) |-> $past(iso_enable, 2)
  ) else $error("Isolation not enabled before power off");

  // 2. Isolation must remain enabled while power is off
  a_iso_during_off: assert property (
    @(posedge clk) disable iff (!rst_n)
    !cpu_power_on |-> iso_enable
  ) else $error("Isolation disabled while power is off");

  // 3. When isolated, outputs must be clamped to expected value
  a_iso_clamp_data: assert property (
    @(posedge clk) disable iff (!rst_n)
    iso_enable && !cpu_power_on |-> cpu_data_out === 32'h0
  ) else $error("Isolated output not clamped to 0");

  a_iso_clamp_valid: assert property (
    @(posedge clk) disable iff (!rst_n)
    iso_enable && !cpu_power_on |-> cpu_valid_out === 1'b0
  ) else $error("Isolated valid not clamped to 0");

  // 4. Isolation must be disabled after power on (eventually)
  a_iso_after_on: assert property (
    @(posedge clk) disable iff (!rst_n)
    $rose(cpu_power_on) |-> ##[1:100] !iso_enable
  ) else $error("Isolation not disabled after power on");

  // 5. No glitch on isolation enable during power transition
  a_iso_no_glitch: assert property (
    @(posedge clk) disable iff (!rst_n)
    $changed(iso_enable) |=> $stable(iso_enable)
  ) else $warning("Glitch detected on isolation enable");

endmodule
```

### 3.3 Isolation Enable Timing

```
Correct Power-Down Sequence with Isolation:
===========================================

Step  | iso_enable | clk_gate | power
------|-----------|----------|------
  0   | 0 (off)   | 1 (on)   | ON     <- Normal operation
  1   | 1 (on)    | 1 (on)   | ON     <- Enable isolation first
  2   | 1 (on)    | 0 (off)  | ON     <- Gate clock
  3   | 1 (on)    | 0 (off)  | OFF    <- Power off
  ...
  4   | 1 (on)    | 0 (off)  | ON     <- Power on
  5   | 1 (on)    | 1 (on)   | ON     <- Enable clock
  6   | 1 (on)    | 1 (on)   | ON     <- Wait for stabilization
  7   | 0 (off)   | 1 (on)   | ON     <- Disable isolation last
```

### 3.4 Clamp Value Verification

```systemverilog
// Verify correct clamp values for different signal types
class isolation_clamp_checker extends uvm_component;
  `uvm_component_utils(isolation_clamp_checker)

  // Check each isolated signal for correct clamp value
  virtual task check_clamp_values();
    // Data bus: clamp to 0
    if (vif.cpu_data_out !== 32'h0)
      `uvm_error("ISO", "Data bus not clamped to 0")

    // Valid signal: clamp to 0
    if (vif.cpu_valid !== 1'b0)
      `uvm_error("ISO", "Valid not clamped to 0")

    // Ready signal: may need to be 1 (depends on protocol)
    if (vif.cpu_ready !== 1'b1)
      `uvm_error("ISO", "Ready not clamped to 1")

    // Interrupt: clamp to 0
    if (vif.cpu_intr !== 1'b0)
      `uvm_error("ISO", "Interrupt not clamped to 0")
  endtask
endclass
```

---

## 4. Retention Verification

### 4.1 Retention Requirements

Retention cells preserve register state during power-down or voltage reduction.

**Retention Types:**

| Type | Description | Use Case |
|------|-------------|----------|
| Always-on retention | Powered by always-on supply | Critical state |
| Balloon latch | Shadow latch for retention | Standard retention |
| Master-slave retention | Modified FF with retention slave | High performance |

### 4.2 Save/Restore Protocol

```
Retention Save/Restore Sequence:
================================

Power Down (with save):
  1. Complete ongoing transactions
  2. Assert save signal -> state captured in retention latch
  3. Enable isolation
  4. Gate clock
  5. Power down (main supply off, retention supply on)

Power Up (with restore):
  6. Power up (main supply on)
  7. Wait for supply stabilization
  8. Enable clock
  9. Assert restore signal -> state restored from retention latch
  10. De-assert restore
  11. Disable isolation
  12. Resume normal operation
```

### 4.3 Retention Verification Checks

```systemverilog
// Retention verification
module retention_checker #(
  parameter NUM_REGS = 10
)(
  input logic clk,
  input logic rst_n,
  input logic power_on,
  input logic save,
  input logic restore,
  input logic [31:0] reg_values [NUM_REGS]
);

  // Shadow storage for verification
  logic [31:0] saved_values [NUM_REGS];
  bit save_done = 0;

  // Capture values on save
  always @(posedge save) begin
    if (power_on) begin
      foreach (saved_values[i])
        saved_values[i] = reg_values[i];
      save_done = 1;
      `uvm_info("RET", "Register state saved for retention", UVM_MEDIUM)
    end
  end

  // Verify values on restore
  always @(posedge restore) begin
    if (power_on && save_done) begin
      foreach (reg_values[i]) begin
        if (reg_values[i] !== saved_values[i])
          `uvm_error("RET", $sformatf(
            "Retention mismatch: reg[%0d] expected=0x%08h got=0x%08h",
            i, saved_values[i], reg_values[i]))
      end
      `uvm_info("RET", "Retention restore verified", UVM_MEDIUM)
    end
  end

  // Save must happen before power off
  a_save_before_off: assert property (
    @(posedge clk) disable iff (!rst_n)
    $fell(power_on) |-> $past(save)
  ) else $error("Save not asserted before power off");

  // Restore must happen after power on
  a_restore_after_on: assert property (
    @(posedge clk) disable iff (!rst_n)
    $rose(power_on) |-> ##[1:50] restore
  ) else $error("Restore not asserted after power on");

  // Save and restore must not overlap
  a_no_overlap: assert property (
    @(posedge clk) disable iff (!rst_n)
    !(save && restore)
  ) else $error("Save and restore asserted simultaneously");

  // Registers must be corrupted when power is off (without retention)
  // This is handled by the UPF-aware simulator automatically

endmodule
```

### 4.4 Corruption Detection

The simulator should corrupt (set to X) all registers in a powered-off domain
that do not have retention. Verifying this is critical.

```systemverilog
// Verify corruption semantics
class corruption_checker extends uvm_component;
  `uvm_component_utils(corruption_checker)

  task check_corruption_after_power_off();
    // After power off, all non-retained registers should be X
    // The UPF-aware simulator handles this automatically

    // Verify that the design handles corruption correctly:
    // 1. After power-up without restore, registers should be re-initialized
    // 2. Software should not read corrupted values
    // 3. FSMs should recover from unknown state

    // Check FSM after power up
    if ($isunknown(vif.state))
      `uvm_info("CORR", "FSM state is X after power up (expected)", UVM_MEDIUM)

    // After reset or restore, state should be valid
    @(posedge vif.rst_n or posedge vif.restore);
    repeat(5) @(posedge vif.clk);

    if ($isunknown(vif.state))
      `uvm_error("CORR", "FSM state still X after reset/restore")
  endtask
endclass
```

---

## 5. Level Shifter Verification

### 5.1 Level Shifter Requirements

Level shifters translate signals between different voltage domains.

| Type | From | To | Description |
|------|------|-----|-------------|
| Low-to-High (LH) | Low voltage | High voltage | Amplify |
| High-to-Low (HL) | High voltage | Low voltage | Attenuate |
| Bi-directional | Either | Either | Both directions |

### 5.2 Level Shifter Verification Checks

```systemverilog
// Level shifter verification
module level_shifter_checker(
  input logic clk,
  input logic rst_n,
  input logic src_power_on,
  input logic dst_power_on,
  input logic [31:0] src_signal,
  input logic [31:0] dst_signal
);

  // When both domains powered, signal should pass through
  a_pass_through: assert property (
    @(posedge clk) disable iff (!rst_n)
    src_power_on && dst_power_on |->
    ##[1:2] (dst_signal === src_signal)
  ) else $error("Level shifter not passing signal correctly");

  // When source is off, output should be clamped
  // (level shifter may also act as isolation)
  a_src_off: assert property (
    @(posedge clk) disable iff (!rst_n)
    !src_power_on && dst_power_on |->
    !$isunknown(dst_signal)  // Should not be X
  ) else $error("Level shifter output is X with source off");

  // When destination is off, check is not meaningful
  // (output domain is dead anyway)

endmodule
```

### 5.3 Level Shifter Placement Verification

```tcl
# UPF: Verify level shifter strategy covers all crossings
set_level_shifter ls_cpu_to_top \
  -domain PD_CPU \
  -applies_to outputs \
  -rule low_to_high \
  -location parent

set_level_shifter ls_top_to_cpu \
  -domain PD_CPU \
  -applies_to inputs \
  -rule high_to_low \
  -location self

# Verification:
# - Every signal crossing voltage domains must have level shifter
# - Level shifter direction must match voltage relationship
# - Level shifter must be powered by the correct supply
```

---

## 6. Always-On Logic Verification

### 6.1 Always-On Requirements

Always-on logic remains powered during all power states. It includes:
- Power management unit (PMU)
- Interrupt controller (wake-up logic)
- Clock generation (for wake-up)
- Retention control signals
- Isolation control signals

### 6.2 Always-On Verification

```systemverilog
// Always-on logic verification
module always_on_checker(
  input logic clk_ao,     // Always-on clock
  input logic rst_ao_n,   // Always-on reset
  input logic vdd_ao,     // Always-on supply
  // PMU signals
  input logic cpu_power_req,
  input logic cpu_power_ack,
  input logic io_power_req,
  input logic io_power_ack,
  input logic cpu_iso_en,
  input logic io_iso_en,
  input logic cpu_save,
  input logic cpu_restore,
  // Wake-up
  input logic wake_irq,
  input logic wake_ack
);

  // Always-on supply must always be ON
  a_ao_supply: assert property (
    @(posedge clk_ao)
    vdd_ao === 1'b1
  ) else $fatal(1, "Always-on supply is OFF!");

  // PMU must respond to power requests
  a_cpu_power_ack: assert property (
    @(posedge clk_ao) disable iff (!rst_ao_n)
    $changed(cpu_power_req) |-> ##[1:100] cpu_power_ack
  ) else $error("PMU not acknowledging CPU power request");

  // Wake-up interrupt must trigger power-up sequence
  a_wake_response: assert property (
    @(posedge clk_ao) disable iff (!rst_ao_n)
    $rose(wake_irq) && !cpu_power_req |-> ##[1:50] cpu_power_req
  ) else $error("Wake-up interrupt not triggering power-up");

  // Isolation must be controlled correctly by always-on PMU
  a_iso_controlled: assert property (
    @(posedge clk_ao) disable iff (!rst_ao_n)
    !$isunknown(cpu_iso_en) && !$isunknown(io_iso_en)
  ) else $error("Isolation control signals are unknown");

endmodule
```

---

## 7. Power State Machine Verification

### 7.1 Power State Machine Model

```systemverilog
// Power state machine for verification
typedef enum logic [3:0] {
  PS_ALL_ON,         // All domains powered on
  PS_CPU_SAVING,     // CPU saving retention state
  PS_CPU_ISOLATING,  // CPU isolation being enabled
  PS_CPU_CLK_GATE,   // CPU clock being gated
  PS_CPU_OFF,        // CPU powered off
  PS_CPU_POWERING,   // CPU power ramping up
  PS_CPU_CLK_UNGATE, // CPU clock being ungated
  PS_CPU_RESTORING,  // CPU restoring retention state
  PS_CPU_DEISOLATING,// CPU isolation being disabled
  PS_ERROR           // Error state
} power_state_e;

module power_state_checker(
  input logic clk,
  input logic rst_n,
  input logic cpu_power_on,
  input logic cpu_iso_en,
  input logic cpu_clk_en,
  input logic cpu_save,
  input logic cpu_restore
);

  power_state_e current_state;

  // Track power state transitions
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= PS_ALL_ON;
    end else begin
      case (current_state)
        PS_ALL_ON: begin
          if (cpu_save) current_state <= PS_CPU_SAVING;
        end

        PS_CPU_SAVING: begin
          if (!cpu_save && cpu_iso_en) current_state <= PS_CPU_ISOLATING;
        end

        PS_CPU_ISOLATING: begin
          if (cpu_iso_en && !cpu_clk_en) current_state <= PS_CPU_CLK_GATE;
        end

        PS_CPU_CLK_GATE: begin
          if (!cpu_power_on) current_state <= PS_CPU_OFF;
        end

        PS_CPU_OFF: begin
          if (cpu_power_on) current_state <= PS_CPU_POWERING;
        end

        PS_CPU_POWERING: begin
          if (cpu_clk_en) current_state <= PS_CPU_CLK_UNGATE;
        end

        PS_CPU_CLK_UNGATE: begin
          if (cpu_restore) current_state <= PS_CPU_RESTORING;
        end

        PS_CPU_RESTORING: begin
          if (!cpu_restore && !cpu_iso_en) current_state <= PS_CPU_DEISOLATING;
        end

        PS_CPU_DEISOLATING: begin
          current_state <= PS_ALL_ON;
        end

        default: current_state <= PS_ERROR;
      endcase
    end
  end

  // Verify no illegal transitions
  a_no_skip: assert property (
    @(posedge clk) disable iff (!rst_n)
    current_state != PS_ERROR
  ) else $error("Power state machine entered error state");

  // Coverage
  covergroup cg_power_state @(posedge clk);
    cp_state: coverpoint current_state;
    cp_trans: coverpoint current_state {
      bins all_transitions[] = (
        PS_ALL_ON => PS_CPU_SAVING => PS_CPU_ISOLATING =>
        PS_CPU_CLK_GATE => PS_CPU_OFF => PS_CPU_POWERING =>
        PS_CPU_CLK_UNGATE => PS_CPU_RESTORING =>
        PS_CPU_DEISOLATING => PS_ALL_ON
      );
    }
  endgroup

endmodule
```

### 7.2 Power State Transition Verification

```systemverilog
// Verify power state transitions follow correct sequence
module power_sequence_checker(
  input logic clk,
  input logic rst_n,
  input logic power_on,
  input logic iso_en,
  input logic clk_en,
  input logic save,
  input logic restore
);

  // Power-down sequence: save -> isolate -> clock gate -> power off
  property p_power_down_sequence;
    @(posedge clk) disable iff (!rst_n)
    $fell(power_on) |->
      $past(save, 4) &&
      $past(iso_en, 3) &&
      $past(!clk_en, 2);
  endproperty
  a_pd_seq: assert property (p_power_down_sequence)
    else $error("Incorrect power-down sequence");

  // Power-up sequence: power on -> clock ungate -> restore -> de-isolate
  property p_power_up_sequence;
    @(posedge clk) disable iff (!rst_n)
    $rose(power_on) |-> ##[1:5] clk_en ##[1:5] restore ##[1:5] !iso_en;
  endproperty
  a_pu_seq: assert property (p_power_up_sequence)
    else $error("Incorrect power-up sequence");

endmodule
```

---

## 8. Power-Aware Assertions

### 8.1 Comprehensive Power Assertion Library

```systemverilog
// Power-aware assertion package
package pa_assertion_pkg;

  // Isolation assertion: output clamped when domain is off
  property p_isolation_clamp(clk, rst_n, power_on, iso_en, signal, clamp_val);
    @(posedge clk) disable iff (!rst_n)
    !power_on && iso_en |-> signal === clamp_val;
  endproperty

  // Isolation timing: enabled before power off
  property p_iso_timing(clk, rst_n, power_on, iso_en, int margin);
    @(posedge clk) disable iff (!rst_n)
    $fell(power_on) |-> $past(iso_en, margin);
  endproperty

  // Retention save timing: save before power off
  property p_save_timing(clk, rst_n, power_on, save, int margin);
    @(posedge clk) disable iff (!rst_n)
    $fell(power_on) |-> $past(save, margin);
  endproperty

  // Retention restore: after power on
  property p_restore_timing(clk, rst_n, power_on, restore, int max_delay);
    @(posedge clk) disable iff (!rst_n)
    $rose(power_on) |-> ##[1:max_delay] restore;
  endproperty

  // No X on always-on outputs
  property p_ao_no_x(clk, rst_n, signal);
    @(posedge clk) disable iff (!rst_n)
    !$isunknown(signal);
  endproperty

  // Clock gating before power off
  property p_clk_gate_before_off(clk, rst_n, power_on, clk_en);
    @(posedge clk) disable iff (!rst_n)
    $fell(power_on) |-> $past(!clk_en);
  endproperty

  // Power on before clock ungate
  property p_power_before_clk(clk, rst_n, power_on, clk_en);
    @(posedge clk) disable iff (!rst_n)
    $rose(clk_en) && $past(!clk_en) |-> power_on;
  endproperty

endpackage
```

### 8.2 Domain-Specific Assertions

```systemverilog
// Bind power assertions to DUT
module power_assertions(
  input logic clk,
  input logic rst_n,
  input logic cpu_power_on,
  input logic cpu_iso_en,
  input logic cpu_clk_en,
  input logic cpu_save,
  input logic cpu_restore,
  input logic [31:0] cpu_data_out,
  input logic cpu_valid_out
);

  import pa_assertion_pkg::*;

  // Isolation clamp checks
  a_data_clamp: assert property (
    p_isolation_clamp(clk, rst_n, cpu_power_on, cpu_iso_en, cpu_data_out, 32'h0)
  ) else $error("CPU data not clamped during isolation");

  a_valid_clamp: assert property (
    p_isolation_clamp(clk, rst_n, cpu_power_on, cpu_iso_en, cpu_valid_out, 1'b0)
  ) else $error("CPU valid not clamped during isolation");

  // Sequence timing
  a_iso_timing: assert property (
    p_iso_timing(clk, rst_n, cpu_power_on, cpu_iso_en, 2)
  );

  a_save_timing: assert property (
    p_save_timing(clk, rst_n, cpu_power_on, cpu_save, 3)
  );

  a_restore_timing: assert property (
    p_restore_timing(clk, rst_n, cpu_power_on, cpu_restore, 50)
  );

  a_clk_gate: assert property (
    p_clk_gate_before_off(clk, rst_n, cpu_power_on, cpu_clk_en)
  );

endmodule
```

---

## 9. PA-SIM vs PA-GLS Methodology

### 9.1 PA-SIM (Power-Aware RTL Simulation)

```
PA-SIM Characteristics:
  - Uses RTL netlist + UPF
  - Simulator applies UPF semantics:
    - Corruption on power off
    - Isolation clamping
    - Retention save/restore
    - Level shifter behavior
  - No physical power cells (behavioral)
  - Fast simulation speed
  - Good for:
    - Power state machine verification
    - Isolation/retention protocol verification
    - Software power management testing
    - Corruption propagation analysis
```

**PA-SIM Test Strategy:**

| Test Category | Purpose | Priority |
|--------------|---------|----------|
| Power on/off sequence | Verify basic power cycling | P0 |
| Retention save/restore | Verify state preservation | P0 |
| Isolation clamp values | Verify output clamping | P0 |
| Multiple domain interactions | Cross-domain power events | P1 |
| Rapid power cycling | Stress power transitions | P1 |
| Wake-up scenarios | Interrupt-driven power up | P1 |
| DVFS transitions | Voltage/frequency scaling | P2 |
| Error injection | Power sequence violations | P2 |

### 9.2 PA-GLS (Power-Aware Gate-Level Simulation)

```
PA-GLS Characteristics:
  - Uses gate-level netlist + UPF + SDF
  - Physical power cells instantiated:
    - Isolation cells (e.g., ISO_CLAMP_LO)
    - Retention cells (e.g., DFFR_RET)
    - Level shifter cells (e.g., LS_HL)
    - Power switch cells (e.g., HEADER_SW)
  - SDF timing includes power cell delays
  - Slowest simulation speed
  - Good for:
    - Physical cell functionality verification
    - Power cell timing verification
    - Final sign-off verification
```

**PA-GLS Setup:**

```bash
# VCS PA-GLS
vcs -full64 -sverilog \
    -upf my_design.upf \
    -sdf max:tb_top.dut:timing.sdf \
    -v std_cell_library.v \
    -v power_cell_library.v \
    -v retention_cell_library.v \
    -v level_shifter_library.v \
    -f netlist.f \
    -f testbench.f \
    -power=coverage \
    -top tb_top \
    -o simv_pa_gls

# Xcelium PA-GLS
xrun -lowpower \
     -upf my_design.upf \
     -sdf_cmd_file sdf_cmd.tcl \
     -v std_cell_library.v \
     -v power_cell_library.v \
     -f netlist.f \
     -f testbench.f \
     -top tb_top
```

### 9.3 PA-SIM vs PA-GLS Comparison

| Aspect | PA-SIM | PA-GLS |
|--------|--------|--------|
| Netlist | RTL | Gate-level |
| Power cells | Behavioral (UPF) | Physical (library) |
| SDF timing | No | Yes |
| Speed | Fast (10-50x RTL) | Very slow (100-500x RTL) |
| Accuracy | Functional | Physical |
| Debug | Easy (RTL signals) | Hard (gate names) |
| Coverage | Good | Limited |
| When to run | Throughout verification | Pre-tapeout |
| Test count | Full regression | Selected tests |

---

## 10. Power-Aware Coverage Metrics

### 10.1 Power State Coverage

```systemverilog
// Power state coverage
covergroup cg_power_states @(posedge clk);
  // Individual domain states
  cp_cpu_state: coverpoint {cpu_power_on, cpu_iso_en, cpu_clk_en, cpu_ret_mode} {
    bins all_on       = {4'b1010};  // Power on, no iso, clock on, no ret
    bins isolated     = {4'b0110};  // Power off, iso on, clock off, no ret
    bins retention    = {4'b0111};  // Power off, iso on, clock off, retention
    bins transitioning = default;
  }

  cp_io_state: coverpoint {io_power_on, io_iso_en} {
    bins on           = {2'b10};
    bins off_isolated = {2'b01};
  }

  // Power state combinations
  cx_domain_states: cross cp_cpu_state, cp_io_state {
    // Cover all legal state combinations
    ignore_bins illegal = binsof(cp_cpu_state) intersect {4'b1110}; // iso without power off
  }
endgroup
```

### 10.2 Power Transition Coverage

```systemverilog
// Power transition coverage
covergroup cg_power_transitions @(posedge clk);
  // State transitions
  cp_cpu_transitions: coverpoint cpu_power_state {
    bins power_down  = (PS_ALL_ON => PS_CPU_OFF);
    bins power_up    = (PS_CPU_OFF => PS_ALL_ON);
    bins to_retention = (PS_ALL_ON => PS_CPU_RET);
    bins from_retention = (PS_CPU_RET => PS_ALL_ON);
    bins rapid_cycle = (PS_ALL_ON => PS_CPU_OFF => PS_ALL_ON);
  }

  // Transition with context
  cp_activity_during_transition: coverpoint activity_level iff ($changed(cpu_power_state)) {
    bins idle   = {ACTIVITY_IDLE};
    bins low    = {ACTIVITY_LOW};
    bins medium = {ACTIVITY_MEDIUM};
    bins high   = {ACTIVITY_HIGH};
  }

  // Wake-up source
  cp_wakeup_source: coverpoint wakeup_source iff ($rose(cpu_power_on)) {
    bins timer_wake = {WAKE_TIMER};
    bins irq_wake   = {WAKE_IRQ};
    bins sw_wake    = {WAKE_SOFTWARE};
    bins debug_wake = {WAKE_DEBUG};
  }
endgroup
```

### 10.3 Isolation Coverage

```systemverilog
// Isolation coverage
covergroup cg_isolation @(posedge clk);
  // Isolation enable coverage per domain
  cp_cpu_iso: coverpoint cpu_iso_en {
    bins enabled  = {1};
    bins disabled = {0};
    bins enable_trans  = (0 => 1);
    bins disable_trans = (1 => 0);
  }

  // Isolation with power state
  cx_iso_power: cross cp_cpu_iso, cp_cpu_power {
    bins iso_while_off = binsof(cp_cpu_iso.enabled) && binsof(cp_cpu_power) intersect {0};
    bins iso_while_on  = binsof(cp_cpu_iso.enabled) && binsof(cp_cpu_power) intersect {1};
  }
endgroup
```

### 10.4 Retention Coverage

```systemverilog
// Retention coverage
covergroup cg_retention @(posedge clk);
  cp_save: coverpoint cpu_save {
    bins asserted   = {1};
    bins deasserted = {0};
    bins save_pulse = (0 => 1 => 0);
  }

  cp_restore: coverpoint cpu_restore {
    bins asserted   = {1};
    bins deasserted = {0};
    bins restore_pulse = (0 => 1 => 0);
  }

  // Save-restore pairs
  cx_save_restore: cross cp_save, cp_restore {
    illegal_bins simultaneous = binsof(cp_save.asserted) && binsof(cp_restore.asserted);
  }

  // Data pattern during retention
  cp_retained_data: coverpoint retained_reg_value {
    bins all_zeros = {32'h0};
    bins all_ones  = {32'hFFFF_FFFF};
    bins mixed     = default;
  }
endgroup
```

### 10.5 Power-Aware Coverage Report

```
Power-Aware Coverage Summary:
=============================

Category              | Target | Actual | Status
----------------------|--------|--------|-------
Power state coverage  | 100%   | 95%    | Open
  - All states visited|        | 100%   | Met
  - All transitions   |        | 90%    | Open

Isolation coverage    | 100%   | 100%   | Met
  - All domains       |        | 100%   | Met
  - Enable timing     |        | 100%   | Met
  - Clamp values      |        | 100%   | Met

Retention coverage    | 100%   | 92%    | Open
  - Save/restore      |        | 100%   | Met
  - Data patterns     |        | 85%    | Open
  - Rapid cycling     |        | 90%    | Open

Level shifter coverage| 100%   | 100%   | Met

Wake-up coverage      | 100%   | 88%    | Open
  - All sources       |        | 100%   | Met
  - Wake from all states|      | 75%    | Open
```

---

## 11. Power-Aware Verification Sign-Off

### 11.1 Sign-Off Checklist

```
Power-Aware Verification Sign-Off:
===================================

UPF Quality:
[ ] UPF lint clean (no errors, warnings reviewed)
[ ] All power domains defined
[ ] All supply networks connected
[ ] Power state table complete and consistent

Isolation:
[ ] All domain outputs isolated
[ ] Correct clamp values for all signals
[ ] Isolation timing verified (enable before power off)
[ ] Isolation disable timing verified (after power on)
[ ] No X propagation from powered-off domains

Retention:
[ ] Save signal timing verified
[ ] Restore signal timing verified
[ ] Data integrity across power cycles verified
[ ] Retention for all critical registers confirmed
[ ] Non-retained registers properly re-initialized

Level Shifters:
[ ] All cross-domain signals have level shifters
[ ] Correct direction (LH/HL) for each crossing
[ ] Level shifter powered by correct supply

Power Sequencing:
[ ] Power-down sequence correct for all domains
[ ] Power-up sequence correct for all domains
[ ] No race conditions in power transitions
[ ] Multiple domain interactions verified

Always-On Logic:
[ ] Always-on supply verified to never go off
[ ] PMU logic fully verified
[ ] Wake-up paths verified
[ ] Control signals (iso, save, restore) correct

Coverage:
[ ] Power state coverage meets target
[ ] Power transition coverage meets target
[ ] Isolation coverage 100%
[ ] Retention coverage meets target
[ ] Wake-up scenario coverage meets target

Simulation:
[ ] PA-SIM regression clean
[ ] PA-GLS regression clean (selected tests)
[ ] No open power-related bugs
[ ] Power-aware assertions all passing
```

### 11.2 Common Power-Aware Bugs

| Bug | Description | Detection Method |
|-----|-------------|-----------------|
| Missing isolation | Output not clamped when domain off | UPF lint, PA-SIM |
| Wrong clamp value | Signal clamped to wrong value | PA-SIM assertion |
| Isolation timing | Isolation enabled too late | PA-SIM assertion |
| Missing retention | Critical register not retained | PA-SIM, functional test |
| Save/restore order | Incorrect save/restore sequence | PA-SIM assertion |
| Level shifter missing | Signal crosses without LS | UPF lint |
| Power sequence error | Incorrect power-up/down order | PA-SIM, PMU test |
| Always-on violation | AO logic affected by power event | PA-SIM check |
| Supply network error | Wrong supply connection | UPF lint |
| Corruption handling | Software reads corrupted value | PA-SIM functional |

---
