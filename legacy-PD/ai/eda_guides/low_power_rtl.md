# Low-Power RTL Design

## Overview

Power consumption is a first-order design constraint in modern SoCs. Mobile, IoT, and datacenter chips all face thermal and energy budgets that demand power-aware design from the earliest RTL stage. While physical implementation techniques (voltage scaling, power gating) deliver the largest power reductions, the RTL coding style fundamentally determines how much power the silicon will consume. This guide covers RTL techniques for minimizing dynamic and leakage power, and introduces the power intent specification frameworks that connect RTL decisions to physical implementation.

## Power Fundamentals

### Dynamic Power

```
P_dynamic = alpha * C_load * V_dd^2 * f_clk
```

Where `alpha` is the switching activity (probability of a signal toggling each cycle), `C_load` is the load capacitance, `V_dd` is the supply voltage, and `f_clk` is the clock frequency. RTL designers directly control `alpha` through coding style.

### Leakage Power

```
P_leakage = I_leak * V_dd
```

Leakage is a function of the technology and the number of transistors. RTL designers influence leakage through design choices that affect area (fewer gates = less leakage) and through power gating intent.

### Short-Circuit Power

Occurs during signal transitions when both PMOS and NMOS networks are briefly conducting. Reduced by minimizing glitches and controlling slew rates (a physical design concern, but RTL can reduce glitch sources).

## Clock Gating

Clock gating is the most effective RTL technique for dynamic power reduction. It stops the clock to idle registers, eliminating their switching activity.

### RTL Coding for Clock Gating Inference

```systemverilog
// This pattern enables clock gating inference
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    data_reg <= '0;
  else if (load_enable)
    data_reg <= data_in;
  // else: implicit hold (synthesis infers clock gating)
end
```

The synthesis tool replaces this with:

```
gated_clk = ICG(clk, load_enable);
data_reg: always_ff @(posedge gated_clk) data_reg <= data_in;
```

### Clock Gating Efficiency

Clock gating is beneficial only if the enable is deasserted frequently. An enable that is almost always active adds the ICG cell overhead without power savings. Target registers with enable duty cycles below 50%.

### Grouping for Gating

Registers that share the same enable should be grouped for efficient clock gating. One ICG cell can gate many registers. Split registers with different enables into separate always blocks.

```systemverilog
// Good: shared enable, one ICG cell gates all 128 bits
always_ff @(posedge clk) begin
  if (wr_en) begin
    data_reg_a <= data_a;
    data_reg_b <= data_b;
    data_reg_c <= data_c;
    data_reg_d <= data_d;
  end
end

// Bad: mixed enables prevent efficient gating
always_ff @(posedge clk) begin
  if (en_a) data_reg_a <= data_a;
  if (en_b) data_reg_b <= data_b;  // different enable -> separate ICG
end
```

### Manual Clock Gating

For cases where automatic inference is insufficient, instantiate ICG cells directly:

```systemverilog
// Technology-specific ICG instantiation
CKLNQD1 u_icg (
  .TE(scan_enable),  // test enable bypasses gating during scan
  .E(func_enable),
  .CP(clk),
  .Q(gated_clk)
);
```

## Operand Isolation

Operand isolation prevents unnecessary toggling in combinational logic when its output is not used.

```systemverilog
// Without operand isolation: multiplier toggles every cycle
assign product = a * b;
assign result  = use_product ? product : other_value;

// With operand isolation: multiplier inputs are frozen when not needed
wire [31:0] a_iso = use_product ? a : '0;
wire [31:0] b_iso = use_product ? b : '0;
assign product = a_iso * b_iso;
assign result  = use_product ? product : other_value;
```

When `use_product` is low, the multiplier inputs are constant zero, preventing input-driven toggling. The area cost is the isolation muxes, which is small compared to the multiplier.

### When to Use Operand Isolation

Apply operand isolation to:
- Large arithmetic units (multipliers, dividers, complex ALUs)
- Blocks that are idle most of the time
- Modules with high switching activity on inputs

Do not apply to:
- Small logic (gates, muxes) where the mux overhead exceeds the savings
- Always-active data paths

## Memory Power Management

### Memory Shutdown

SRAMs consume significant leakage power. When not in use, memories can be put into retention (data preserved, reduced leakage) or shutdown (data lost, minimal leakage) modes.

```systemverilog
// Power intent for memory shutdown (UPF)
// set_retention -elements {u_sram} -retention_power_net VDD_RET
// RTL must manage save/restore sequences
always_ff @(posedge clk) begin
  if (mem_shutdown_req) begin
    // Save critical state to always-on storage
    backup_reg <= critical_data;
  end
  if (mem_restore_req) begin
    // Restore from backup after power-up
    critical_data <= backup_reg;
  end
end
```

### Memory Banking

Divide large memories into banks that can be independently powered down. Only the bank being accessed is active.

```systemverilog
// Bank select based on address MSBs
wire [3:0] bank_en;
assign bank_en[0] = req && (addr[ADDR_W-1:ADDR_W-2] == 2'b00);
assign bank_en[1] = req && (addr[ADDR_W-1:ADDR_W-2] == 2'b01);
assign bank_en[2] = req && (addr[ADDR_W-1:ADDR_W-2] == 2'b10);
assign bank_en[3] = req && (addr[ADDR_W-1:ADDR_W-2] == 2'b11);
```

### Read-Gating

For memories that are read infrequently, gate the read enable to avoid unnecessary sensing activity.

## Multi-Vdd Coding

Multi-Vdd designs operate different blocks at different supply voltages. Lower voltage reduces dynamic power quadratically but requires level shifters at voltage domain boundaries.

### RTL Considerations

1. **Voltage domain awareness**: Know which modules are in which voltage domain. Cross-domain signals need level shifters.
2. **Level shifter insertion**: Typically handled by the power-aware synthesis tool based on UPF/CPF, but the RTL designer must ensure clean domain boundaries.
3. **Performance impact**: Lower-Vdd blocks are slower. Timing constraints must reflect the voltage.
4. **Isolation cells**: When a voltage domain is powered down, its outputs become undefined. Isolation cells clamp outputs to safe values (typically 0 or 1).

```systemverilog
// RTL does not explicitly code level shifters or isolation cells
// These are inserted by the tool based on power intent (UPF)
// But the designer must structure the hierarchy so that domain boundaries
// align with module boundaries
```

## Power Intent Specification

### UPF (Unified Power Format)

UPF (IEEE 1801) is the industry standard for specifying power intent separately from RTL.

```tcl
# Define power domains
create_power_domain PD_TOP -include_scope
create_power_domain PD_CPU -elements {u_cpu}
create_power_domain PD_GPU -elements {u_gpu}

# Define power states
add_power_state PD_CPU -state ON  {-supply_expr {power == FULL_ON}}
add_power_state PD_CPU -state OFF {-supply_expr {power == OFF}}
add_power_state PD_CPU -state RET {-supply_expr {power == PARTIAL_ON}}

# Isolation rules
set_isolation iso_cpu -domain PD_CPU -isolation_power_net VDD_AON \
  -clamp_value 0 -applies_to outputs

# Retention rules
set_retention ret_cpu -domain PD_CPU -retention_power_net VDD_RET \
  -save_signal {save_en posedge} -restore_signal {restore_en posedge}

# Level shifter rules
set_level_shifter ls_cpu_to_top -domain PD_CPU -applies_to outputs \
  -rule both -location parent
```

### CPF (Common Power Format)

CPF is Cadence's alternative to UPF. While functionally similar, UPF has broader industry adoption and is the IEEE standard.

## RTL Power Reduction Checklist

1. **Clock gating**: Write enable-based register patterns; group registers by enable.
2. **Operand isolation**: Gate inputs to large idle arithmetic blocks.
3. **Memory banking**: Partition memories for independent power control.
4. **Avoid unnecessary toggling**: Default assignments should minimize transitions (e.g., hold previous value rather than assigning zero then overwriting).
5. **Gray code**: Use Gray coding for counters and FIFO pointers to minimize bit transitions.
6. **One-hot vs binary**: One-hot encoding toggles fewer bits per transition but uses more flip-flops. Evaluate per design.
7. **Bus encoding**: For buses with high switching activity, consider bus encoding techniques.
8. **Glitch reduction**: Register outputs of combinational blocks that fan out widely.
9. **Data gating**: Gate data buses when data is not valid (using valid signals to hold buses constant).
10. **Early power analysis**: Run power estimation tools (Power Compiler, PrimeTime PX) on RTL with realistic switching activity to guide optimization.

## Power Verification

Verify power intent with:
- **UPF simulation**: Run simulation with power-aware semantics (power shutoff corrupts state, isolation clamps outputs).
- **Static power intent checks**: Tools verify that isolation, level shifters, and retention are correctly specified.
- **Power estimation**: RTL power analysis with annotated switching activity from simulation.
- **Post-layout power analysis**: Gate-level simulation with extracted parasitics for sign-off accuracy.

Power-aware verification catches bugs that functional simulation misses: missing isolation cells causing X propagation, incorrect retention save/restore sequences, and level shifter omissions.
