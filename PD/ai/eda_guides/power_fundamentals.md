# Power Fundamentals

## Overview

Power consumption is one of the three pillars of chip design alongside performance and area (the PPA tradeoff). In modern process nodes, power has become the primary constraint: it determines battery life in mobile devices, thermal limits in data centers, and reliability in automotive applications. PD engineers must understand the sources of power consumption and the techniques available to reduce it, because many power optimization decisions are made during physical implementation.

## Power Components

Total chip power consists of two main components: dynamic power (consumed when transistors switch) and static power (consumed even when the chip is idle).

```
P_total = P_dynamic + P_static
P_dynamic = P_switching + P_short_circuit
P_static = P_leakage
```

## Dynamic Power

### Switching Power

Switching power is consumed when a logic gate charges and discharges its output capacitance.

```
P_switching = alpha * C_load * V_dd^2 * f
```

Where:
- **alpha**: Activity factor (probability of a 0-to-1 or 1-to-0 transition per clock cycle). Typical values: 0.1-0.3 for random logic, 0.5 for clocks
- **C_load**: Total load capacitance (gate capacitance of driven inputs + wire capacitance)
- **V_dd**: Supply voltage. Power is proportional to V_dd squared, making voltage reduction the most effective power reduction technique
- **f**: Clock frequency

### Key Insights for PD Engineers

- **Wire capacitance matters**: In advanced nodes, wire capacitance can dominate gate capacitance for long interconnects. Placement that minimizes wire length reduces switching power
- **Coupling capacitance**: Crosstalk coupling adds effective capacitance. Dense routing increases coupling and thus switching power
- **Buffer insertion**: Adding buffers for timing improvement increases switching power (more gates toggling). There is always a power-timing tradeoff
- **Clock network**: The clock toggles every cycle (alpha = 1 for each edge, effectively alpha = 0.5 for power), driving high-capacitance global wires. Clock power is typically 30-50% of total dynamic power

### Short-Circuit Power

When both PMOS and NMOS transistors in a CMOS gate are simultaneously on during a switching transition, a direct path from VDD to GND conducts current momentarily.

```
P_short_circuit ~ beta * (V_dd - 2*V_th)^3 * t_rise * f
```

Short-circuit power is typically 5-15% of total dynamic power. It is managed by ensuring that input signal rise/fall times are not excessively slow (proper buffer sizing).

## Static Power (Leakage)

### Sources of Leakage

Even when a circuit is idle and no switching occurs, transistors leak current.

**Subthreshold leakage**: Current flowing through the channel when the transistor is nominally "off" (V_gs < V_th). This is the dominant leakage mechanism in modern nodes.

```
I_sub ~ exp(-V_th / (n * V_T))
```

Where V_T is the thermal voltage (kT/q). Leakage is exponentially sensitive to threshold voltage, which is why multi-Vt libraries exist.

**Gate leakage**: Current tunneling through the thin gate oxide. Addressed by high-k dielectrics in modern processes.

**Junction leakage**: Reverse-biased PN junction current. Relatively small in modern processes.

### Temperature Dependence

Leakage increases exponentially with temperature: a 10C temperature increase typically doubles leakage current. This creates a positive feedback loop: higher leakage increases temperature, which further increases leakage (thermal runaway risk).

**Physical implication**: Leakage analysis must be done at worst-case temperature. If the chip is in a thermally constrained environment (no heatsink, small package), leakage can dominate total power.

### Technology Scaling Impact

As transistors shrink, threshold voltage decreases (to maintain performance), and leakage increases. At 7nm and below, leakage can be 30-50% of total power in high-performance designs.

## Multi-Threshold Voltage (Multi-Vt) Optimization

### Concept

Modern standard cell libraries provide cells with different threshold voltages:

| Vt Type | Speed | Leakage | Usage |
|---------|-------|---------|-------|
| ULVT (Ultra-Low Vt) | Fastest | Highest leakage | Critical timing paths only |
| LVT (Low Vt) | Fast | High leakage | Timing-critical paths |
| SVT (Standard Vt) | Medium | Medium leakage | Default for most logic |
| HVT (High Vt) | Slowest | Lowest leakage | Non-critical paths |

### Optimization Strategy

1. Start with all cells at SVT or HVT (low leakage starting point)
2. Upsize or swap to LVT/ULVT only on timing-critical paths
3. After timing closure, swap non-critical cells to HVT to reduce leakage
4. Iterate: timing optimization may undo power-optimal Vt assignments

**Physical implication**: Multi-Vt optimization is performed by PnR tools during optimization and by PD engineers during ECO. The final Vt distribution (percentage of cells at each Vt) is a key power metric. A well-optimized design might have 60-70% HVT, 25-30% SVT, and < 10% LVT/ULVT.

## Clock Gating

### Mechanism

Clock gating disables the clock to registers that do not need to update, eliminating unnecessary switching.

```
Without clock gating:
Clock toggles every cycle -> Flip-flop CK input toggles -> Dynamic power consumed even if data doesn't change

With clock gating:
Enable signal gates the clock -> When enable=0, clock is blocked -> No CK toggling -> No dynamic power
```

### Implementation

Synthesis tools automatically infer integrated clock gating (ICG) cells from RTL patterns:

```verilog
always_ff @(posedge clk)
    if (enable)
        data_reg <= data_in;
// Synthesis infers: ICG cell generates gated_clk
// gated_clk only toggles when enable=1
```

### ICG Cell Characteristics

- ICG cells contain a latch (to prevent glitches on the gated clock) and an AND gate
- They add insertion delay to the clock path (30-80ps typically)
- They consume a small amount of area and leakage
- Break-even point: typically 3-8 flip-flops (below this, the ICG overhead exceeds the savings)

### Clock Gating Effectiveness

- **Measure**: Clock gating coverage = (gated flip-flops / total flip-flops) * 100%
- **Target**: > 90% for power-efficient designs
- **Impact**: 30-50% reduction in clock network power

**Physical implication**: ICG cells are part of the clock tree. CTS must handle ICG placement and balance the gated clock subtrees. Poorly placed ICG cells create skew imbalances.

## Power Gating (MTCMOS)

### Concept

Power gating completely shuts off the power supply to idle blocks using header (PMOS) or footer (NMOS) sleep transistors.

```
VDD -> Header Switch (PMOS) -> Virtual VDD -> Logic Block -> GND
         ^
         |
    Sleep Control (active low = off)
```

### Components

- **Sleep transistors (power switches)**: Large transistors that disconnect the block from the supply rail. Placed in a ring or grid around the power-gated domain
- **Isolation cells**: Clamp outputs of the power-gated domain to a known value (0 or 1) when the domain is off. Prevents floating outputs from corrupting always-on logic
- **Retention registers**: Special flip-flops that retain their state when power is removed, using a small always-on supply (balloon latch or shadow register)
- **Level shifters**: Translate voltage levels between domains operating at different voltages

### Physical Implementation

Power gating is one of the most physically complex power optimization techniques:

1. **Power switch placement**: Insert power switches in rows or columns around the domain boundary; size the switch network for acceptable IR drop during active mode
2. **Rush current control**: When power is restored, all cells simultaneously charge their capacitances, creating a large current spike (rush current). A staged wake-up sequence limits this
3. **Isolation cell placement**: Place isolation cells at the boundary between power-gated and always-on domains
4. **Retention flop routing**: Route the always-on supply to retention registers independently of the switchable supply
5. **Power grid design**: Two supply networks: switchable VDD (through power switches) and always-on VDD (bypass)

**Physical implication**: Power gating adds 5-10% area overhead and requires careful power grid design. PD engineers must handle the power switch network, isolation cells, and dual supply routing.

## Dynamic Voltage and Frequency Scaling (DVFS)

### Concept

DVFS adjusts the supply voltage and clock frequency at runtime based on the workload. During low-demand periods, both voltage and frequency are reduced, saving significant power.

```
P_dynamic ~ V_dd^2 * f
If V_dd and f are both halved: P_dynamic reduces by 8x (2^2 * 2 = 8)
```

### Implementation

- **Voltage regulators**: On-chip or off-chip regulators provide variable supply voltage
- **Frequency control**: PLL or clock divider adjusts the clock frequency
- **Voltage-frequency table**: Defines valid (voltage, frequency) operating points
- **Software control**: OS or firmware selects the operating point based on workload demand

### Physical Implications

- The design must be timing-clean at the lowest voltage (worst-case speed)
- Power grid must handle the highest voltage (maximum stress)
- Level shifters may be needed between domains at different voltages
- STA must analyze all voltage/frequency operating points

## Power Analysis Methodology

### Analysis Types

- **Average power**: Mean power over a representative time window. Determines battery life and thermal design
- **Peak power**: Maximum instantaneous power. Determines power delivery network requirements
- **Vectorless estimation**: Statistical estimate of switching activity without simulation vectors. Useful for early exploration
- **Vector-based analysis**: Uses switching activity from simulation (VCD/SAIF files) for accurate power calculation

### Tools

- **PrimeTime PX (PTPX)** (Synopsys): Signoff power analysis
- **Voltus** (Cadence): Power analysis integrated with Innovus
- **Joules** (Cadence): RTL power estimation

### Power Budgeting

A practical power budget allocates total power across blocks:

| Component | % of Total Power |
|-----------|-----------------|
| Clock network | 30-40% |
| Standard cell switching | 20-30% |
| Memory (SRAM) | 15-25% |
| Leakage | 10-30% (technology dependent) |
| I/O | 5-10% |

### Physical Power Optimization Checklist

1. Multi-Vt optimization (swap non-critical cells to HVT)
2. Clock gating coverage > 90%
3. Power gating for idle blocks (if architecture supports it)
4. Wire length minimization (placement optimization)
5. Optimal buffer sizing (do not over-buffer)
6. Decoupling capacitor insertion for dynamic IR drop
7. Power grid optimization for minimal static IR drop

Power optimization is not a one-time step but an ongoing concern throughout physical implementation. Every optimization decision (cell sizing, buffer insertion, routing) affects power, and PD engineers must balance power against timing and area at every stage.
