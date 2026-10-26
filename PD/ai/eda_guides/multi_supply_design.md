# Multi-Supply Design: UPF 2.0/3.0 Power Intent Specification

## Overview

The Unified Power Format (UPF), standardized as IEEE 1801, is the industry-standard language for specifying power intent in multi-supply digital designs. UPF separates the description of power architecture from the functional RTL, allowing power intent to be defined once and used consistently across synthesis, implementation, simulation, and verification tools. UPF 1.0 (IEEE 1801-2009) introduced the core concepts; UPF 2.0 (IEEE 1801-2013) added supply states, power state tables, and refined semantics; UPF 3.0 (IEEE 1801-2015) and subsequent revisions (UPF 3.1 in 2018, UPF 4.0 in 2022) added successive refinement, more precise corruption semantics, and improved repeatability.

This guide covers every UPF command and concept in production-level depth, with complete syntax, examples, and the semantic implications that affect simulation and implementation.

---

## UPF File Structure and Loading

A UPF file is a TCL-based script executed in the context of a power-intent-aware tool. UPF files are loaded at different stages:

```tcl
# In synthesis (Fusion Compiler / Design Compiler)
load_upf top_level.upf

# In implementation (Innovus)
read_power_intent top_level.upf
commit_power_intent

# In simulation (VCS / Xcelium)
# UPF is loaded via command-line or tool configuration
```

### UPF Scope and Hierarchy

UPF commands are scoped to the current design hierarchy. The `set_scope` command changes the hierarchical scope:

```tcl
# Top-level UPF
set_scope /top
create_power_domain PD_TOP ...

# Block-level UPF (separate file for CPU block)
set_scope /top/u_cpu
create_power_domain PD_CPU ...
```

For large designs, UPF is typically split into:
1. **Top-level UPF**: Defines top-level domains, supply network, cross-domain strategies
2. **Block-level UPF**: Defines internal power architecture of each major block
3. **Supply mapping UPF**: Maps supply nets from block level to top level

The `load_upf` command can include block-level UPF files:
```tcl
# In top-level UPF
load_upf cpu_block.upf -scope /top/u_cpu
load_upf gpu_block.upf -scope /top/u_gpu
```

---

## Power Domains

### create_power_domain

The `create_power_domain` command defines a region of the design that shares a common power/ground supply and can be independently controlled.

```tcl
create_power_domain domain_name
  [-elements {list_of_instances}]
  [-include_scope]
  [-supply {supply_set_handle}]
  [-atomic]
```

#### Parameters

- **-elements**: List of RTL instances that belong to this domain. If omitted, the domain includes all logic in the current scope not assigned to another domain.
- **-include_scope**: The domain includes the current scope instance itself (not just its children).
- **-supply**: Associates a supply set with the domain.
- **-atomic**: The domain cannot be further partitioned (used in bottom-up flows).

#### Examples

```tcl
# Default domain (catches everything not in another domain)
create_power_domain PD_TOP -include_scope

# CPU subsystem domain
create_power_domain PD_CPU \
  -elements {u_cpu_core u_l1_cache u_cpu_bus_if}

# GPU subsystem with two sub-domains
create_power_domain PD_GPU \
  -elements {u_gpu_core u_gpu_mem}

create_power_domain PD_GPU_SHADER \
  -elements {u_gpu_core/u_shader_array} \
  -scope /top/u_gpu_core
```

### Power Domain Hierarchy

Domains can be hierarchical. A child domain is enclosed within a parent domain. The parent domain provides the always-on infrastructure for the child:

```tcl
create_power_domain PD_TOP -include_scope
create_power_domain PD_CPU -elements {u_cpu}
create_power_domain PD_CPU_CORE -elements {u_cpu/u_core0 u_cpu/u_core1}
```

Here PD_CPU_CORE is a child of PD_CPU (because its elements are inside PD_CPU's elements). PD_CPU is a child of PD_TOP.

---

## Supply Network

### create_supply_net

Defines a power or ground net within a power domain:

```tcl
create_supply_net net_name
  [-domain domain_name]
  [-resolve {parallel | one_hot | user_defined}]
  [-reuse]
```

```tcl
create_supply_net VDD_CPU -domain PD_CPU
create_supply_net VDD_CPU_SW -domain PD_CPU  ;# switched supply (virtual VDD)
create_supply_net VDD_GPU -domain PD_GPU
create_supply_net VDD_AON -domain PD_TOP     ;# always-on supply
create_supply_net VSS                        ;# global ground (shared)
```

The `-resolve` parameter handles cases where a supply net has multiple drivers:
- **parallel**: Multiple drivers can drive simultaneously (typical for power grids)
- **one_hot**: Only one driver at a time (for supply multiplexing)

### create_supply_port

Defines a port that connects supply nets across hierarchical boundaries:

```tcl
create_supply_port port_name
  [-domain domain_name]
  [-direction {in | out | inout}]
```

```tcl
# At top level, create external supply ports
create_supply_port VDD_EXT -domain PD_TOP -direction in
create_supply_port VSS_EXT -domain PD_TOP -direction in

# At block level, create interface ports
create_supply_port VDD_CPU_PORT -domain PD_CPU -direction in
create_supply_port VSS_PORT -domain PD_CPU -direction in
```

### connect_supply_net

Connects supply ports to supply nets:

```tcl
connect_supply_net net_name -ports {list_of_ports}
```

```tcl
# Connect external ports to internal nets
connect_supply_net VDD -ports {VDD_EXT}
connect_supply_net VSS -ports {VSS_EXT}

# Connect block-level ports
connect_supply_net VDD_CPU -ports {u_cpu/VDD_CPU_PORT}
```

### create_supply_set

A supply set bundles a power/ground pair (and optionally other supplies) into a single handle for convenience:

```tcl
create_supply_set ss_name
  [-function {power net_name}]
  [-function {ground net_name}]
  [-function {nwell net_name}]
  [-function {pwell net_name}]
```

```tcl
create_supply_set SS_CPU \
  -function {power VDD_CPU} \
  -function {ground VSS}

create_supply_set SS_GPU \
  -function {power VDD_GPU} \
  -function {ground VSS}

# Associate supply set with domain
create_power_domain PD_CPU -supply {primary SS_CPU}
```

### set_domain_supply_net

Associates supply nets with a power domain:

```tcl
set_domain_supply_net domain_name
  -primary_power_net net_name
  -primary_ground_net net_name
```

```tcl
set_domain_supply_net PD_CPU \
  -primary_power_net VDD_CPU \
  -primary_ground_net VSS

set_domain_supply_net PD_GPU \
  -primary_power_net VDD_GPU \
  -primary_ground_net VSS
```

---

## Power States

### Supply States (UPF 2.0+)

Supply states define the voltage conditions of a supply net:

```tcl
add_port_state supply_port_name
  -state {state_name voltage}
  [-state {state_name voltage}] ...
```

```tcl
# Define voltage states for CPU supply
add_port_state VDD_CPU_PORT \
  -state {FULL_ON 0.90} \
  -state {SVS 0.72} \
  -state {RETENTION 0.50} \
  -state {OFF off}

# Define voltage states for GPU supply
add_port_state VDD_GPU_PORT \
  -state {FULL_ON 0.90} \
  -state {OFF off}

# Ground is always at 0V
add_port_state VSS_PORT \
  -state {ON 0.0}
```

### Power State Table (PST)

The power state table defines all legal combinations of supply states across all domains. This is the central definition of the chip's power architecture:

```tcl
create_pst pst_name -supplies {list_of_supply_ports}

add_pst_state state_name
  -pst pst_name
  -state {supply_states}
```

```tcl
create_pst CHIP_PST -supplies {VDD_CPU_PORT VDD_GPU_PORT VDD_AON_PORT VSS_PORT}

add_pst_state ALL_ON \
  -pst CHIP_PST \
  -state {FULL_ON FULL_ON FULL_ON ON}

add_pst_state GPU_OFF \
  -pst CHIP_PST \
  -state {FULL_ON OFF FULL_ON ON}

add_pst_state CPU_SVS_GPU_OFF \
  -pst CHIP_PST \
  -state {SVS OFF FULL_ON ON}

add_pst_state DEEP_SLEEP \
  -pst CHIP_PST \
  -state {RETENTION OFF FULL_ON ON}

add_pst_state SHUTDOWN \
  -pst CHIP_PST \
  -state {OFF OFF FULL_ON ON}
```

### add_power_state (UPF 2.1+)

The `add_power_state` command provides a more flexible way to define power states using logic expressions. It supersedes the PST approach for complex designs:

```tcl
add_power_state domain_or_supply
  -state {state_name [-supply_expr {expr}] [-logic_expr {expr}]}
  [-illegal]
```

```tcl
# Define states for a supply net
add_power_state VDD_CPU \
  -state {FULL_ON -supply_expr {power == {FULL_ON 0.90}}} \
  -state {SVS -supply_expr {power == {SVS 0.72}}} \
  -state {RET -supply_expr {power == {RETENTION 0.50}}} \
  -state {OFF -supply_expr {power == {OFF off}}}

# Define composite states for a domain
add_power_state PD_CPU \
  -state {ACTIVE -logic_expr {VDD_CPU == FULL_ON && clk_en == 1}} \
  -state {IDLE -logic_expr {VDD_CPU == FULL_ON && clk_en == 0}} \
  -state {SVS_ACTIVE -logic_expr {VDD_CPU == SVS}} \
  -state {RETENTION -logic_expr {VDD_CPU == RET}} \
  -state {OFF -logic_expr {VDD_CPU == OFF}}

# Define system-level states with legality constraints
add_power_state PD_TOP \
  -state {NORMAL -logic_expr {PD_CPU == ACTIVE && PD_GPU == ACTIVE}} \
  -state {GPU_GATED -logic_expr {PD_CPU == ACTIVE && PD_GPU == OFF}} \
  -state {ILLEGAL_GPU_WITHOUT_MEM \
    -logic_expr {PD_GPU == ACTIVE && PD_MEM == OFF}} -illegal
```

---

## Isolation Strategy

### set_isolation

Defines the isolation strategy for signals leaving a power domain:

```tcl
set_isolation strategy_name
  -domain domain_name
  [-applies_to {inputs | outputs | both}]
  [-clamp_value {0 | 1 | latch | Z}]
  [-elements {list_of_ports_or_nets}]
  [-exclude_elements {list}]
  [-source domain_name]
  [-sink domain_name]
  [-isolation_power_net net_name]
  [-isolation_ground_net net_name]
  [-diff_supply_only {true | false}]
  [-no_isolation]
  [-force_isolation]
```

#### Key Parameters

- **-applies_to**: Which signals get isolation. `outputs` is the most common (isolate signals going OUT of the gated domain).
- **-clamp_value**: The value to force during isolation. `0`, `1`, `latch` (hold last value), or `Z` (high-impedance).
- **-elements**: Specific ports/nets to isolate (for fine-grained control). Overrides the default of isolating all crossing signals.
- **-exclude_elements**: Ports/nets to exclude from isolation.
- **-diff_supply_only**: Only isolate signals that cross a supply boundary (not signals within the same supply).
- **-no_isolation**: Explicitly mark specific signals as not needing isolation (for signals that are safe to float).
- **-force_isolation**: Override automatic detection and force isolation insertion.

#### Examples

```tcl
# Isolate all CPU outputs to 0
set_isolation iso_cpu_out \
  -domain PD_CPU \
  -applies_to outputs \
  -clamp_value 0 \
  -isolation_power_net VDD_AON \
  -isolation_ground_net VSS

# Isolate specific signals to 1 (active-low reset)
set_isolation iso_cpu_rst \
  -domain PD_CPU \
  -applies_to outputs \
  -clamp_value 1 \
  -elements {rst_n_out ack_n_out} \
  -isolation_power_net VDD_AON \
  -isolation_ground_net VSS

# Latch isolation for configuration bus
set_isolation iso_cpu_cfg \
  -domain PD_CPU \
  -applies_to outputs \
  -clamp_value latch \
  -elements {cfg_bus[*]} \
  -isolation_power_net VDD_AON \
  -isolation_ground_net VSS

# No isolation needed for these signals (they go to powered-down domain)
set_isolation iso_cpu_to_gpu_none \
  -domain PD_CPU \
  -no_isolation \
  -elements {cpu_to_gpu_data[*]}
```

### set_isolation_control

Specifies the control signal for isolation:

```tcl
set_isolation_control strategy_name
  -domain domain_name
  -isolation_signal signal_name
  -isolation_sense {high | low}
  -location {self | parent | fanout | other}
```

```tcl
set_isolation_control iso_cpu_out \
  -domain PD_CPU \
  -isolation_signal pmc/iso_en_cpu \
  -isolation_sense high \
  -location parent

set_isolation_control iso_cpu_rst \
  -domain PD_CPU \
  -isolation_signal pmc/iso_en_cpu \
  -isolation_sense high \
  -location parent
```

- **-isolation_sense high**: Isolation is active when the control signal is high
- **-location parent**: Isolation cell is placed in the parent (receiving) domain

---

## Retention Strategy

### set_retention

Defines which registers in a power-gated domain should retain their state:

```tcl
set_retention strategy_name
  -domain domain_name
  [-elements {list_of_registers}]
  [-exclude_elements {list}]
  [-retention_power_net net_name]
  [-retention_ground_net net_name]
  [-save_signal {signal sense}]
  [-restore_signal {signal sense}]
  [-retention_condition {expr}]
```

```tcl
# Retain all registers in CPU domain
set_retention ret_cpu_all \
  -domain PD_CPU \
  -retention_power_net VDD_RET \
  -retention_ground_net VSS

# Retain only configuration registers (selective retention)
set_retention ret_cpu_cfg \
  -domain PD_CPU \
  -elements {u_cpu/config_regs/* u_cpu/csr/*} \
  -retention_power_net VDD_RET \
  -retention_ground_net VSS

# Exclude pipeline registers (not worth retaining)
set_retention ret_cpu_sel \
  -domain PD_CPU \
  -exclude_elements {u_cpu/pipe_stage*/* u_cpu/temp_buf/*} \
  -retention_power_net VDD_RET \
  -retention_ground_net VSS
```

### set_retention_control

Specifies the save and restore control signals:

```tcl
set_retention_control strategy_name
  -domain domain_name
  -save_signal {signal_name edge_or_level}
  -restore_signal {signal_name edge_or_level}
  [-assert_count count]
  [-assert_condition expr]
```

```tcl
set_retention_control ret_cpu_all \
  -domain PD_CPU \
  -save_signal {pmc/save_cpu posedge} \
  -restore_signal {pmc/restore_cpu posedge} \
  -assert_count 1
```

The `-assert_count` specifies how many clock edges the save/restore signal must be held. Typically 1 (edge-triggered) or 2 (level-sensitive requiring 2 active cycles).

---

## Level Shifter Strategy

### set_level_shifter

Defines the level shifting strategy for signals crossing voltage domains:

```tcl
set_level_shifter strategy_name
  -domain domain_name
  [-applies_to {inputs | outputs | both}]
  [-rule {low_to_high | high_to_low | both}]
  [-threshold voltage_diff]
  [-elements {list}]
  [-exclude_elements {list}]
  [-location {self | parent | fanout}]
  [-input_supply supply_set]
  [-output_supply supply_set]
  [-no_shift]
  [-force_shift]
```

```tcl
# Level shift all CPU outputs going to higher-voltage domains
set_level_shifter ls_cpu_out_lh \
  -domain PD_CPU \
  -applies_to outputs \
  -rule low_to_high \
  -threshold 0.05 \
  -location parent

# Level shift all CPU inputs coming from higher-voltage domains
set_level_shifter ls_cpu_in_hl \
  -domain PD_CPU \
  -applies_to inputs \
  -rule high_to_low \
  -threshold 0.05 \
  -location self

# No level shift needed for signals between same-voltage domains
set_level_shifter ls_cpu_to_cache_none \
  -domain PD_CPU \
  -no_shift \
  -elements {cache_addr[*] cache_data[*]} \
  -applies_to outputs
```

The `-threshold` parameter (in volts) specifies the minimum voltage difference that triggers level shifter insertion. A threshold of 0.0 means always insert; 0.05 means only when the voltage difference exceeds 50mV.

---

## Power Switches

### create_power_switch

Defines a power switch for a domain:

```tcl
create_power_switch switch_name
  -domain domain_name
  -input_supply_port {port_name supply_net}
  -output_supply_port {port_name supply_net}
  -control_port {port_name control_net}
  [-ack_port {port_name ack_net boolean_expr}]
  -on_state {state_name supply_port {boolean_expr}}
  [-off_state {state_name {boolean_expr}}]
```

```tcl
create_power_switch ps_cpu \
  -domain PD_CPU \
  -input_supply_port {vin VDD} \
  -output_supply_port {vout VDD_CPU_SW} \
  -control_port {sleep pmc/sleep_cpu} \
  -ack_port {ack pmc/ack_cpu {sleep}} \
  -on_state {on_state vin {!sleep}} \
  -off_state {off_state {sleep}}

create_power_switch ps_gpu \
  -domain PD_GPU \
  -input_supply_port {vin VDD} \
  -output_supply_port {vout VDD_GPU_SW} \
  -control_port {sleep pmc/sleep_gpu} \
  -control_port {ext_off pmc/force_gpu_off} \
  -on_state {on_state vin {!sleep && !ext_off}} \
  -off_state {off_state {sleep || ext_off}}
```

### map_power_switch

Maps the logical power switch to a physical cell:

```tcl
map_power_switch switch_name
  -domain domain_name
  -lib_cells {cell_list}
```

```tcl
map_power_switch ps_cpu \
  -domain PD_CPU \
  -lib_cells {HDRSW_HVT_X4 HDRSW_HVT_X8}
```

---

## Supply On/Off Semantics and Corruption

### Supply States

UPF defines several supply states:
- **FULL_ON**: Supply is at nominal voltage, logic operates normally
- **PARTIAL_ON**: Supply is at a reduced voltage (e.g., retention voltage) — limited functionality
- **OFF**: Supply is disconnected, no voltage

### Corruption Semantics

When a supply transitions from ON to OFF, all state elements in the domain are corrupted (set to X in simulation). This models the physical reality that all flip-flop, latch, and memory contents become undefined when power is removed.

UPF 2.0+ provides precise control over corruption:

```tcl
# Define corruption behavior
set_corruptor domain_name \
  -corruption_effect {on_to_off | off_to_on | both}
```

Corruption rules:
1. When VDD transitions OFF→ON: All registers in the domain are corrupted (X) unless they have retention
2. When VDD transitions ON→OFF: All registers and outputs become X; isolation cells take over for outputs
3. During OFF state: All logic outputs are X; only isolation cells produce defined values
4. Retention registers: Value is preserved during OFF if retention supply is maintained

### Simulation Behavior

In UPF-aware simulation (VCS, Xcelium, Questa):

```
Time 0:   VDD_CPU = ON    → CPU registers hold valid values
Time 100: ISO_EN = 1      → CPU outputs clamped to isolation values
Time 110: VDD_CPU = OFF   → CPU registers become X, isolation holds outputs
Time 200: VDD_CPU = ON    → CPU registers still X (corrupted)
Time 210: RESTORE = 1     → Retention registers restored to saved values
Time 220: RESET = 1       → Non-retained registers reset to known values
Time 230: ISO_EN = 0      → CPU outputs driven by active logic
```

---

## UPF 3.0/3.1/4.0 Enhancements

### Successive Refinement (UPF 3.0)

UPF 3.0 introduced the concept of successive refinement, where power intent is progressively detailed across the design flow:

- **Architecture UPF**: High-level domain definition, supply intent, operating modes
- **RTL UPF**: Detailed isolation, retention, level shifting strategies
- **Implementation UPF**: Cell mapping, placement constraints, physical information

Each stage adds detail without contradicting earlier specifications.

```tcl
# Architecture UPF (early)
create_power_domain PD_CPU -elements {u_cpu}
set_domain_supply_net PD_CPU -primary_power_net VDD_CPU -primary_ground_net VSS
add_power_state VDD_CPU -state {ON -supply_expr {power == 0.90}} \
                        -state {OFF -supply_expr {power == off}}

# Implementation UPF (later, adds detail)
# Uses -update to refine existing definitions
set_isolation iso_cpu -domain PD_CPU -update \
  -lib_cells {ISO_CLAMP0_X1 ISO_CLAMP0_X2}
```

### Supply Expressions (UPF 3.0)

More expressive supply state definitions using expressions:

```tcl
add_power_state PD_COMPLEX \
  -state {DVFS_HIGH \
    -supply_expr {power == {FULL_ON 0.90} && ground == {ON 0.0}}} \
  -state {DVFS_LOW \
    -supply_expr {power >= 0.60 && power <= 0.75}} \
  -state {RETENTION \
    -supply_expr {power == {PARTIAL_ON 0.50}}}
```

### Repeater Strategy (UPF 3.1)

UPF 3.1 added `set_repeater` for specifying repeater/buffer insertion strategies for long wires crossing power domains:

```tcl
set_repeater rep_cpu \
  -domain PD_CPU \
  -applies_to outputs \
  -lib_cells {BUF_AO_X2}
```

### Simstate Behavior (UPF 3.0)

The `set_simstate_behavior` command provides fine-grained control over simulation corruption:

```tcl
set_simstate_behavior \
  -domain PD_CPU \
  -corruption_model {on_to_off: corrupt_state_outputs, \
                     off_to_on: corrupt_state_only}
```

---

## UPF Verification and Debugging

### Static UPF Checks

```tcl
# Check UPF consistency (Synopsys)
check_mv_design -verbose

# Verify isolation completeness
check_mv_design -isolation
# Expected: 0 violations

# Verify level shifter completeness
check_mv_design -level_shifter
# Expected: 0 violations

# Verify retention strategy
check_mv_design -retention

# Check power switch connectivity
check_mv_design -power_switch

# Comprehensive report
report_mv_design -all
```

### Common UPF Errors

**"Supply net not defined"**: A domain references a supply net that hasn't been created. Ensure all `create_supply_net` commands precede domain definitions.

**"Missing isolation on signal X"**: A signal crosses from a power-gated domain without isolation. Either add isolation or use `-no_isolation` if the signal is safe.

**"Level shifter rule conflict"**: Multiple LS strategies apply to the same signal with conflicting rules. Use `-elements` to partition signals precisely.

**"Retention on non-sequential element"**: The `-elements` list includes combinational cells. Retention only applies to flip-flops and latches.

**"Illegal power state reached"**: Simulation entered a power state marked as `-illegal`. Fix the PMC sequencing logic.

**"Supply set function missing"**: A supply set is missing the `power` or `ground` function. Ensure both are specified.

### UPF Simulation Debugging

```tcl
# In VCS, enable UPF debug
-upf design.upf -power dbg

# Trace supply state changes
$display("CPU supply state: %s", $supply_state(VDD_CPU));

# Check isolation state
$display("ISO active: %b", iso_en_cpu);

# Monitor corruption events
// In SVA:
property no_corruption_during_active;
  @(posedge clk) (vdd_cpu_state == ON) |-> !$isunknown(cpu_data_out);
endproperty
assert property (no_corruption_during_active);
```

---

## Complete UPF Example

```tcl
#===================================================================
# Top-Level UPF for SoC with CPU, GPU, and Peripheral domains
#===================================================================

# Set scope to top level
set_scope /top

#--- Power Domains ---
create_power_domain PD_TOP -include_scope
create_power_domain PD_CPU -elements {u_cpu_subsys}
create_power_domain PD_GPU -elements {u_gpu_subsys}
create_power_domain PD_PERIPH -elements {u_periph_subsys}

#--- Supply Network ---
create_supply_net VDD -domain PD_TOP
create_supply_net VDD_CPU -domain PD_CPU
create_supply_net VDD_CPU_SW -domain PD_CPU    ;# switched (virtual)
create_supply_net VDD_GPU -domain PD_GPU
create_supply_net VDD_GPU_SW -domain PD_GPU
create_supply_net VDD_AON -domain PD_TOP       ;# always-on
create_supply_net VSS

#--- Supply Ports ---
create_supply_port VDD_EXT -direction in
create_supply_port VSS_EXT -direction in
connect_supply_net VDD -ports {VDD_EXT}
connect_supply_net VSS -ports {VSS_EXT}
connect_supply_net VDD_AON -ports {VDD_EXT}  ;# AON tied to main VDD

#--- Domain Supply Mapping ---
set_domain_supply_net PD_TOP -primary_power_net VDD -primary_ground_net VSS
set_domain_supply_net PD_CPU -primary_power_net VDD_CPU_SW -primary_ground_net VSS
set_domain_supply_net PD_GPU -primary_power_net VDD_GPU_SW -primary_ground_net VSS
set_domain_supply_net PD_PERIPH -primary_power_net VDD -primary_ground_net VSS

#--- Supply States ---
add_port_state VDD_EXT -state {ON 0.90} -state {OFF off}
add_port_state VSS_EXT -state {ON 0.0}

#--- Power Switches ---
create_power_switch ps_cpu \
  -domain PD_CPU \
  -input_supply_port {vin VDD_CPU} \
  -output_supply_port {vout VDD_CPU_SW} \
  -control_port {sleep pmc/sleep_cpu} \
  -on_state {on vin {!sleep}} \
  -off_state {off {sleep}}

create_power_switch ps_gpu \
  -domain PD_GPU \
  -input_supply_port {vin VDD_GPU} \
  -output_supply_port {vout VDD_GPU_SW} \
  -control_port {sleep pmc/sleep_gpu} \
  -on_state {on vin {!sleep}} \
  -off_state {off {sleep}}

#--- Isolation ---
set_isolation iso_cpu \
  -domain PD_CPU -applies_to outputs -clamp_value 0 \
  -isolation_power_net VDD_AON -isolation_ground_net VSS

set_isolation_control iso_cpu \
  -domain PD_CPU -isolation_signal pmc/iso_cpu \
  -isolation_sense high -location parent

set_isolation iso_gpu \
  -domain PD_GPU -applies_to outputs -clamp_value 0 \
  -isolation_power_net VDD_AON -isolation_ground_net VSS

set_isolation_control iso_gpu \
  -domain PD_GPU -isolation_signal pmc/iso_gpu \
  -isolation_sense high -location parent

#--- Level Shifters ---
set_level_shifter ls_cpu_out \
  -domain PD_CPU -applies_to outputs -rule both \
  -threshold 0.03 -location parent

set_level_shifter ls_gpu_out \
  -domain PD_GPU -applies_to outputs -rule both \
  -threshold 0.03 -location parent

#--- Retention ---
set_retention ret_cpu \
  -domain PD_CPU \
  -retention_power_net VDD_AON \
  -retention_ground_net VSS

set_retention_control ret_cpu \
  -domain PD_CPU \
  -save_signal {pmc/save_cpu posedge} \
  -restore_signal {pmc/restore_cpu posedge}

#--- Power State Table ---
add_power_state PD_TOP \
  -state {ALL_ON -logic_expr {PD_CPU==ACTIVE && PD_GPU==ACTIVE}} \
  -state {GPU_OFF -logic_expr {PD_CPU==ACTIVE && PD_GPU==OFF}} \
  -state {DEEP_SLEEP -logic_expr {PD_CPU==RETENTION && PD_GPU==OFF}} \
  -state {SHUTDOWN -logic_expr {PD_CPU==OFF && PD_GPU==OFF}}
```

---

## Expert Tips

- Always start with a clear power architecture document before writing UPF. The UPF is the formal specification of architectural decisions.
- Use `check_mv_design` after every UPF modification. Bugs compound quickly in multi-supply designs.
- Name UPF strategies consistently: `iso_<domain>_<direction>`, `ls_<domain>_<direction>`, `ret_<domain>`.
- Use `-elements` for fine-grained control rather than broad `-applies_to` when different signals in the same domain need different isolation values.
- Test UPF in simulation before implementation. A UPF bug found in P&R is 10x more expensive to fix than one found in RTL simulation.
- Use successive refinement (UPF 3.0) for large designs: define the architecture UPF first, add implementation details progressively.
- Be explicit about illegal power states. The tool and simulation should flag violations immediately.
- Document the power sequencing requirements in comments within the UPF file. Future engineers will need to understand the intent.
- Keep the PST manageable: for N domains each with M states, the full PST has M^N entries. Use illegal states and domain dependencies to prune aggressively.
- Validate the UPF against the power management controller RTL to ensure the PMC can actually produce all legal state transitions.
