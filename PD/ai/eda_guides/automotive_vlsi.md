# Automotive VLSI Design

## Overview

Automotive semiconductor design operates under constraints fundamentally different from consumer electronics. When a chip fails in a phone, the user is inconvenienced. When a chip fails in a car, people can be injured or killed. This reality drives the entire automotive design methodology, from architecture through manufacturing, and is formalized in the ISO 26262 functional safety standard. PD engineers working on automotive chips must understand ASIL levels, functional safety mechanisms, redundancy strategies, and the qualification requirements that govern every design decision.

## ISO 26262 Functional Safety Standard

### What is ISO 26262?

ISO 26262 is the international standard for functional safety of electrical and electronic systems in road vehicles. It covers the entire lifecycle from concept through decommissioning and applies to all automotive electronic components, including semiconductors.

### Key Concepts

**Functional safety**: The absence of unreasonable risk due to hazards caused by malfunctioning behavior of electrical/electronic systems.

**Hazard**: A potential source of harm (e.g., unintended acceleration, loss of braking, incorrect steering assist).

**Risk**: The combination of probability of a hazard occurring and the severity of its consequences.

**Safety goal**: A top-level requirement that defines the safe state for each identified hazard (e.g., "the system shall not apply unintended braking force").

### ISO 26262 Parts Relevant to Semiconductors

- **Part 5**: Product development at the hardware level (directly applicable to chip design)
- **Part 8**: Supporting processes (configuration management, change management, documentation)
- **Part 11**: Semiconductor-specific guidance (added in the 2018 second edition)

## ASIL Levels

### ASIL Classification

Automotive Safety Integrity Level (ASIL) rates the risk associated with a safety function on a scale from A (lowest) to D (highest).

| ASIL Level | Risk Level | Example Application |
|------------|-----------|-------------------|
| QM (Quality Management) | No safety requirement | Infotainment, seat heater |
| ASIL A | Low | Interior lighting control |
| ASIL B | Medium | Headlight control, wiper control |
| ASIL C | High | Cruise control, ABS |
| ASIL D | Highest | Steering assist, autonomous driving, airbag deployment |

### ASIL Determination

ASIL is determined by a hazard analysis and risk assessment (HARA) that evaluates three factors:

- **Severity (S)**: How bad the consequences are (S0-S3)
- **Exposure (E)**: How often the operating condition occurs (E0-E4)
- **Controllability (C)**: How well the driver can control the situation (C0-C3)

The combination of S, E, and C determines the ASIL level for each hazard.

### ASIL Decomposition

A high ASIL requirement can be decomposed into lower ASIL requirements across redundant elements:

```
ASIL D = ASIL B(D) + ASIL B(D)   [two independent ASIL B elements]
ASIL D = ASIL C(D) + ASIL A(D)   [one ASIL C + one ASIL A element]
```

The (D) notation indicates the element was derived from an ASIL D decomposition and must maintain independence from the other element. This decomposition is crucial for practical implementation: achieving ASIL D on a single processing element is extremely difficult, but decomposing across two independent elements is feasible.

## Functional Safety Mechanisms

### Fault Types

ISO 26262 classifies faults into three categories:

**Permanent faults**: Faults that persist once they occur (e.g., stuck-at fault from a manufacturing defect or wear-out). Detected by offline tests (BIST, scan) or continuous monitoring.

**Transient faults**: Faults that occur temporarily and disappear (e.g., soft errors from radiation, supply noise glitches). Detected by redundancy or error detection codes.

**Latent faults**: Faults that are present but have not yet caused an observable failure. Dangerous because they reduce the effectiveness of other safety mechanisms. Detected by periodic testing.

### Safety Metrics

ISO 26262 defines hardware architectural metrics:

**SPFM (Single Point Fault Metric)**: Percentage of safety-relevant faults that are covered by a safety mechanism. ASIL D requires SPFM >= 99%.

```
SPFM = 1 - (Sum of single-point fault rates) / (Sum of all safety-relevant fault rates)
```

**LFM (Latent Fault Metric)**: Percentage of latent faults (faults not detected by any safety mechanism) that are covered. ASIL D requires LFM >= 90%.

**PMHF (Probabilistic Metric for Hardware Failure)**: The maximum probability of a safety goal violation due to random hardware failures over the vehicle's lifetime. ASIL D requires PMHF < 10 FIT (failures in time, where 1 FIT = 1 failure per 10^9 hours).

### Common Safety Mechanisms

**Dual-core lockstep (DCLS)**: Two identical CPU cores execute the same instructions in parallel. A comparator checks that outputs match on every cycle. Any mismatch triggers a fault indication.

- **Coverage**: Very high (99%+) for permanent and transient faults in the processing logic
- **Overhead**: 100% area overhead for the duplicated core, plus comparator logic
- **Physical design impact**: Two cores must be placed and routed identically (or at least with matched timing). Physical separation is needed to prevent common-cause failures

**ECC (Error Correcting Code)**: Memories protected with SECDED (Single Error Correct, Double Error Detect) codes.

- **Coverage**: Corrects all single-bit errors; detects all double-bit errors
- **Overhead**: ~12.5% additional memory bits for 64-bit data words
- **Physical design impact**: ECC logic adds to the critical path for memory read; must be included in timing analysis

**Parity**: Simpler than ECC; detects single-bit errors but cannot correct them.

- **Coverage**: 50% for random multi-bit errors
- **Overhead**: 1 additional bit per protected word
- **Usage**: For registers and smaller storage elements where ECC overhead is too high

**CRC (Cyclic Redundancy Check)**: Protects data transfers (bus transactions, memory interfaces) against multi-bit errors.

**Watchdog timer**: A hardware timer that must be periodically reset by software. If software hangs (due to a fault), the timer expires and triggers a safe state transition.

**Voltage and temperature monitors**: On-chip sensors that detect out-of-range conditions and trigger fault responses.

## Redundancy Strategies

### Spatial Redundancy

Duplicate hardware executing the same function:

- **Lockstep cores**: Two cores running identical code, outputs compared every cycle
- **Triple Modular Redundancy (TMR)**: Three copies with majority voting. Tolerates one faulty copy. Used for extremely critical logic (e.g., airbag deployment logic)
- **Physical design concern**: Redundant copies must be physically separated to prevent common-mode failures (e.g., a single IR drop event affecting both copies)

### Temporal Redundancy

Execute the same computation multiple times on the same hardware:

- **Re-execution**: Run the computation twice and compare results
- **Advantage**: No area overhead (uses existing hardware)
- **Disadvantage**: Doubles execution time; only detects transient faults (permanent faults produce the same wrong result both times)

### Information Redundancy

Add error detection/correction codes to data:

- **ECC on memories**: Standard for all safety-relevant SRAMs
- **Parity on registers**: Protects register files and pipeline registers
- **CRC on buses**: Protects data in transit

### Diverse Redundancy

Use different implementations of the same function:

- **Different algorithms**: Two different implementations of the same math function (e.g., addition via two different adder architectures)
- **Different compilers**: Compile the same source code with two different compilers for lockstep cores
- **Physical design implication**: Diverse implementations require separate synthesis and placement to ensure they do not share common failure modes

## BIST for Safety

### Built-In Self-Test Requirements

ISO 26262 requires periodic testing to detect latent faults. BIST mechanisms enable this testing in the field without external test equipment.

### Memory BIST (MBIST)

- Run march algorithms to test SRAM arrays for stuck-at and coupling faults
- Must be able to run during system operation (background BIST) or at startup
- Results must be checked against expected patterns; mismatches trigger fault indication

### Logic BIST (LBIST)

- Apply pseudo-random test patterns through scan chains and check responses
- Must achieve sufficient fault coverage (> 90% typically required for ASIL C/D)
- Can be run at startup or during idle periods
- Must not corrupt functional state (requires state save/restore or dedicated test mode)

### CPU Self-Test Libraries (STL)

- Software test routines that exercise CPU functional units and check for correct operation
- Run periodically by the safety software
- Must cover all safety-relevant CPU resources (ALU, registers, branch predictor, cache controller)

### Physical Design Impact

- BIST controllers and test logic add area (3-5% overhead)
- MBIST must have access to all SRAM arrays (routing of BIST signals)
- LBIST requires scan chains (standard in most designs but must be verified for safety coverage)
- BIST clock frequency may differ from functional clock (additional timing constraints)

## Mission Profiles

### Definition

A mission profile defines the operating conditions a chip must endure over its lifetime in a specific vehicle application.

### Typical Automotive Mission Profile

| Parameter | Consumer Grade | Automotive Grade |
|-----------|---------------|-----------------|
| Temperature range | 0C to 70C | -40C to 150C (junction) |
| Operating life | 3-5 years | 15-20 years |
| Operating hours | 2,000-5,000 hrs | 10,000-30,000 hrs |
| Humidity | Indoor | Outdoor (rain, condensation) |
| Vibration | Minimal | Continuous road vibration |
| Voltage range | +/- 5% | +/- 10% or wider |
| Thermal cycling | Mild | Severe (engine bay: -40C to 150C) |

### Physical Design Impact

- **Wider timing margins**: Must meet timing across the full -40C to 150C temperature range with voltage variation
- **More PVT corners**: Automotive STA requires more MMMC scenarios than consumer designs
- **Reliability derating**: Aging effects (BTI, HCI, EM) are more severe due to longer operating life and higher temperatures
- **Electromigration**: EM current density limits are tighter for 15-year lifetime than for 5-year lifetime

## Qualification

### AEC-Q100

AEC-Q100 is the automotive qualification standard for integrated circuits. It defines the stress tests a chip must pass before being qualified for automotive use.

### Qualification Grades

| Grade | Temperature Range | Application |
|-------|------------------|-------------|
| Grade 0 | -40C to 150C | Under-hood, near engine |
| Grade 1 | -40C to 125C | Under-hood, away from engine |
| Grade 2 | -40C to 105C | Passenger compartment |
| Grade 3 | -40C to 85C | Passenger compartment (mild) |

### Qualification Tests

- **HTOL (High Temperature Operating Life)**: 1000 hours at max temperature and elevated voltage
- **TC (Temperature Cycling)**: 1000 cycles from -40C to max temperature
- **THB (Temperature Humidity Bias)**: 1000 hours at 85C/85% RH with bias applied
- **HAST (Highly Accelerated Stress Test)**: 96 hours at 130C/85% RH (accelerated version of THB)
- **ESD (Electrostatic Discharge)**: HBM (Human Body Model) and CDM (Charged Device Model) testing
- **Latch-up**: Verify no latch-up at elevated temperature and current injection

### Physical Design Relevance

- Design must pass all qualification tests before production release
- Qualification failures may require design changes (power grid strengthening, latch-up prevention, ESD improvement)
- PD engineers must design for the full qualification temperature and voltage range from the start

## Automotive PD Best Practices

1. **Design for the full temperature range**: Analyze all corners including -40C (worst hold) and 150C (worst setup and leakage)
2. **Apply safety mechanisms early**: Integrate lockstep, ECC, and BIST during architecture, not as an afterthought
3. **Physical separation**: Ensure redundant elements are physically separated (different regions of the die, different power domains if possible)
4. **Conservative margins**: Use larger timing margins (5-10% additional margin) than consumer designs
5. **Robust power grid**: Design for worst-case automotive voltage droop plus aging derating
6. **Full signoff at all corners**: Do not skip any corner or mode in automotive signoff
7. **FMEDA support**: Provide Failure Modes, Effects, and Diagnostic Analysis data from the physical design (fault coverage per block)
8. **Documentation**: Automotive requires extensive documentation of design decisions, safety analyses, and verification results

Automotive VLSI design demands engineering rigor at every level. PD engineers working on automotive chips carry the responsibility of ensuring that their physical implementation supports the safety requirements that ultimately protect human lives.
