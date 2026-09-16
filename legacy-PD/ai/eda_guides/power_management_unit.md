# PMU Design: Voltage Regulators, Power Sequencing, DVFS, and Sleep/Wake

## Overview

The Power Management Unit (PMU) is the central authority for SoC power control, responsible for generating voltage rails, sequencing power domains, implementing dynamic voltage-frequency scaling (DVFS), managing sleep/wake transitions, and protecting against fault conditions like brown-out. As SoCs become more complex with dozens of power domains and aggressive power targets, PMU design has become a specialized discipline bridging analog circuit design, digital control, and system firmware.

## Voltage Regulator Architectures

### LDO (Low Dropout Regulator)

An LDO is a linear regulator that provides a regulated output voltage:

- **Architecture**: error amplifier + pass transistor (PMOS or NMOS)
- **Dropout voltage**: minimum VIN - VOUT for regulation; typically 100-300 mV
- **Efficiency**: VOUT/VIN (e.g., 0.9V/1.1V = 82%); poor for large VIN-VOUT difference
- **Noise**: very low output noise; excellent for analog/PLL supplies
- **Transient response**: fast load transient response (sub-nanosecond with on-chip LDO)
- **Area**: compact; suitable for on-chip integration
- **Use case**: clean supplies for PLLs, ADCs, SerDes; post-regulation after switching regulator

**On-chip LDO considerations:**
- Integrated decoupling capacitance is limited; external cap may be needed
- Pass transistor sizing determines max current and dropout
- Quiescent current (Iq) matters for always-on domains in sleep mode
- Digital LDOs (clocked comparator + binary-weighted FET array) offer simpler design at cost of ripple

### Buck Converter (Step-Down Switching Regulator)

Buck converters efficiently convert higher voltage to lower voltage:

- **Architecture**: high-side switch + low-side switch + inductor + capacitor
- **Efficiency**: 85-95% across load range; far superior to LDO for large step-down ratios
- **Switching frequency**: 1-10 MHz typical; higher frequency allows smaller inductors but increases switching loss
- **Output ripple**: inherent ripple from switching; filtered by output capacitor and optional post-LDO
- **Control modes**: voltage mode (VMC), current mode (CMC, peak or average)
- **Use case**: main SoC rails (core, I/O, memory), battery-powered systems

**Integrated vs. external:**
- Fully integrated buck: inductor and caps on-package or on-chip (Intel FIVR); compact but limited current
- External buck: discrete inductor and caps; higher current capability (10-100A for server CPUs)
- PMIC (Power Management IC): external chip with multiple buck/LDO channels

### Boost Converter (Step-Up Switching Regulator)

Boosts input voltage to higher output voltage:

- **Use case**: generating VDDH (I/O voltage) from low battery voltage; flash memory programming voltage
- **Architecture**: inductor + switch + diode + capacitor
- **Efficiency**: 80-90%; less efficient than buck converters

### Charge Pump

Switched-capacitor voltage converter:

- **Use case**: low-current applications, voltage doubling for flash write, negative voltage generation
- **Advantage**: no inductor required; fully integrable on-chip
- **Limitation**: limited output current; efficiency depends on conversion ratio

## Power Sequencing

### Why Sequencing Matters

SoCs require specific power-up and power-down ordering to prevent:

- **Latch-up**: CMOS latch-up triggered when I/O voltage is applied before core voltage
- **Current injection**: powered I/O driving unpowered core logic through ESD clamps
- **State corruption**: logic operating in undefined state during partial power-up
- **Rush current**: simultaneous rail energization draws excessive current from supply

### Sequencing Requirements

Typical SoC power-up sequence:

1. **Always-on domain**: PMU control logic, RTC, brown-out detector
2. **Core voltage (VDD)**: main logic supply; must be stable before I/O
3. **I/O voltage (VDDIO)**: I/O pad supply; must follow core
4. **PLL/analog supplies**: clean supplies after main rails are stable
5. **Memory voltage**: SRAM retention voltage during sleep; full voltage for active
6. **Clock enable**: start clocks after power rails are stable and reset is asserted
7. **Reset release**: release reset after clocks are stable; sequenced per domain

Power-down is typically the reverse order.

### Sequencing Implementation

- **Hardware sequencer**: FSM in the PMU that controls enable signals to regulators in a defined sequence
- **Timing delays**: configurable delays between steps (settled via resistor or register programming)
- **Power-good monitoring**: each regulator reports power-good; sequencer waits for power-good before advancing
- **Fault handling**: if a rail fails to reach power-good within timeout, sequencer aborts and reports error

## Dynamic Voltage-Frequency Scaling (DVFS)

### Principle

Power consumption scales with voltage and frequency:

```
P_dynamic = C * V^2 * f
```

DVFS reduces both voltage and frequency together to achieve cubic power reduction for a given performance level.

### DVFS Implementation

**Operating Performance Points (OPPs):**

| OPP | Voltage | Frequency | Use Case |
|---|---|---|---|
| Turbo | 1.05V | 2.0 GHz | Peak performance burst |
| Nominal | 0.90V | 1.5 GHz | Normal workload |
| Low | 0.75V | 1.0 GHz | Light workload |
| Retention | 0.50V | 0 Hz | Sleep with state retention |

**Voltage-Frequency Transition Protocol:**

When scaling up (increasing performance):
1. Increase voltage first (takes 5-50 us for regulator to settle)
2. Wait for voltage to reach target (monitor power-good or use timer)
3. Increase frequency (PLL relock or clock divider change)

When scaling down (reducing power):
1. Decrease frequency first (immediate with divider, or PLL relock)
2. Decrease voltage (regulator settles to lower target)

The order prevents operating at high frequency with insufficient voltage (timing violations) or at high voltage with low frequency (wasted power).

**Hardware Components:**
- **Voltage regulator with DVFS input**: VID (voltage ID) code or analog control sets target voltage
- **PLL with frequency control**: programmable dividers or multiple PLL frequencies
- **DVFS controller**: FSM that sequences voltage and frequency changes based on firmware request
- **Voltage monitor (optional)**: on-chip voltage sensor for closed-loop DVFS

### Adaptive Voltage Scaling (AVS)

AVS refines DVFS by adjusting voltage based on actual silicon speed:

- **Process monitors**: ring oscillators or critical-path replicas measure actual silicon speed
- **Closed-loop control**: firmware or hardware adjusts voltage to provide minimum margin for current frequency
- **Benefit**: fast silicon runs at lower voltage (saving power); slow silicon gets adequate voltage (maintaining frequency)
- **Implementation**: on-chip ring oscillator frequency measured by counter; lookup table maps frequency to voltage

## Sleep and Wake Management

### Sleep States

Modern SoCs define multiple sleep states with different power/latency trade-offs:

| State | Power | Wake Latency | Description |
|---|---|---|---|
| Active | Full | N/A | All domains powered and clocked |
| Idle | Moderate | < 1 us | CPU clock gated; logic powered |
| Light Sleep | Low | 10-100 us | Non-critical domains clock gated; retention |
| Deep Sleep | Very Low | 100 us - 10 ms | Most domains power gated; SRAM in retention |
| Shutdown | Minimal | 100 ms+ | All domains off except always-on; full reboot |

### Sleep Entry Sequence

1. Software saves context (register state, cache contents)
2. PMU receives sleep request via register write or WFI instruction
3. PMU sequences power-down: gate clocks, assert isolation, enable retention, power gate domains
4. PMU enters low-power state; only always-on domain remains active

### Wake-Up Sequence

1. Wake-up event detected (interrupt, timer, GPIO) by always-on logic
2. PMU sequences power-up: enable regulators, wait for power-good, release isolation, restore clocks
3. Reset is asserted then released for powered domains
4. CPU resumes from reset vector or saved context (depending on sleep depth)
5. Software restores context and resumes operation

### Retention Strategies

**SRAM retention:**
- Reduce SRAM supply to retention voltage (0.5-0.6V); sufficient to hold data but not operate
- Special retention SRAM cells with higher Vt devices for lower leakage
- Retention power: 1-10 uW per KB

**Register retention:**
- Retention flip-flops with shadow latch powered by always-on supply
- Save (copy main to shadow) on sleep entry; restore on wake-up
- Area overhead: 30-50% larger than standard flip-flops

## Brown-Out Detection and Protection

### Brown-Out Detector (BOD)

Monitors supply voltage and triggers protective action when voltage drops below threshold:

- **Threshold levels**: configurable; typically 90% of nominal voltage
- **Response**: generate interrupt (warning), assert reset (protection), or force shutdown
- **Hysteresis**: prevent oscillation when voltage hovers near threshold (typically 50-100 mV hysteresis)
- **Speed**: comparator-based BOD responds in microseconds

### Over-Current Protection

- **Current sense**: resistive or FET-based current sensing in regulator path
- **Current limit**: hardware limits maximum current to prevent damage
- **Thermal shutdown**: disable regulators if junction temperature exceeds limit

### Voltage Monitoring

- **On-chip ADC**: periodic sampling of voltage rails via multiplexed ADC
- **Comparator-based monitors**: fast detection of voltage excursions
- **Droop detection**: fast on-chip droop detector triggers frequency throttling before timing failure (Intel SpeedShift, ARM Adaptive Clocking)

## PMU Integration Considerations

### PMU Placement

- **Always-on domain**: PMU control logic must be in the always-on power domain
- **Analog blocks**: LDOs, BODs, bandgap reference placed near package power pins
- **Decoupling**: extensive local decoupling for regulator outputs
- **Noise isolation**: separate analog and digital grounds in PMU area

### PMU Firmware

- **Sequencing tables**: firmware-programmable tables define power-up/down sequences
- **OPP tables**: voltage-frequency pairs for each DVFS operating point
- **Wake-up configuration**: which interrupt sources can wake from each sleep state
- **Thermal management**: firmware reads temperature sensors and adjusts DVFS accordingly

### Verification

- **Power sequencing simulation**: verify correct order and timing of rail enables across all entry/exit paths
- **DVFS transition simulation**: verify no timing violations during voltage/frequency transitions
- **Brown-out simulation**: verify protective response when supply drops below threshold
- **Sleep/wake simulation**: verify context retention and correct restoration across all sleep states

PMU design is where power architecture meets circuit implementation. A robust PMU with well-verified sequencing, DVFS, and sleep/wake management is essential for both functional correctness and meeting aggressive SoC power targets.
