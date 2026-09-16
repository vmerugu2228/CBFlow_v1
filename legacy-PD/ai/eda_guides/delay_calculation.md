# Delay Calculation: Cell Delay, Wire Delay, and Slew Propagation

## Overview of Delay in Digital Circuits

The total delay from one flip-flop output to the next flip-flop input consists of two fundamental components: **cell delay** (the time for a signal to propagate through a logic gate) and **wire delay** (the time for a signal to propagate through the interconnect). Understanding how each is computed and what factors influence them is essential for timing analysis, optimization, and debug.

```
Total Path Delay = Tcq + Sum(Cell_Delays) + Sum(Wire_Delays)
```

At older technology nodes (130nm-65nm), cell delay dominated total path delay. At advanced nodes (16nm and below), wire delay can constitute 40-60% or more of total delay, making interconnect optimization equally important as gate optimization.

## Cell Delay Computation

### The Basic Model

Cell delay is a function of two primary variables:
- **Input transition time (input slew):** How fast the input signal changes
- **Output load capacitance:** How much capacitance the cell must charge/discharge

```
Cell Delay = f(input_slew, output_load)
```

This function is stored as a 2D lookup table in the Liberty (.lib) file and interpolated during STA.

### Input Slew Effect

A faster input transition (smaller slew) means the cell switches more quickly, reducing delay. A slower input transition increases delay because the internal transistors spend more time in the linear region.

For a typical inverter:
- Input slew 20ps: cell delay ~15ps
- Input slew 100ps: cell delay ~25ps
- Input slew 500ps: cell delay ~50ps

The relationship is approximately linear for moderate slew values.

### Output Load Effect

Higher output load means the cell must supply more charge to swing the output, increasing delay. The relationship is approximately linear for moderate loads:

```
Cell Delay approximately = intrinsic_delay + (output_load * drive_resistance)
```

Where:
- **Intrinsic delay:** The minimum delay with zero load (parasitic capacitance of the cell itself)
- **Drive resistance:** Effective output impedance of the cell (lower for higher drive strengths)

### Drive Strength and Delay

A cell's drive strength determines its output resistance. Stronger cells (e.g., BUFX8 vs. BUFX2) have lower output resistance and can drive larger loads with less delay:

```
BUFX2:  Drive resistance ~ 2.0 kohm,  Intrinsic delay ~ 20ps
BUFX4:  Drive resistance ~ 1.0 kohm,  Intrinsic delay ~ 22ps
BUFX8:  Drive resistance ~ 0.5 kohm,  Intrinsic delay ~ 25ps
BUFX16: Drive resistance ~ 0.25 kohm, Intrinsic delay ~ 30ps
```

Note that intrinsic delay increases slightly with drive strength because larger transistors have larger parasitic capacitance. The optimal drive strength depends on the actual output load.

### Effective Capacitance

In NLDM, the output load is modeled as a single lumped capacitance. However, real nets have distributed RC. The **effective capacitance** (Ceff) model accounts for the fact that the cell initially sees only the near-end capacitance and gradually sees the far-end capacitance as the signal propagates down the wire.

```
Ceff < Ctotal  (because far-end capacitance is shielded by wire resistance)
```

CCS and ECSM models handle this naturally through current/voltage source modeling and do not need the Ceff approximation.

## Wire Delay Computation

### The RC Interconnect Problem

An on-chip wire is a distributed RC network. The signal at the far end of the wire is delayed relative to the near end due to the time required to charge the distributed capacitance through the distributed resistance.

### Elmore Delay Model

The Elmore delay is the simplest analytical model for wire delay:

```
T_elmore = Sum(Ri * Ci_downstream)
```

For each resistive segment Ri, multiply by the total capacitance downstream of that segment (including all branches). The sum gives the 50% delay approximation.

**Example: Simple RC ladder**
```
driver -> R1 -> node1 -> R2 -> node2 -> R3 -> sink
              |C1              |C2             |C3

T_elmore = R1*(C1+C2+C3) + R2*(C2+C3) + R3*C3
```

**Elmore delay properties:**
- Always gives an upper bound on the actual 50% delay
- Increasingly inaccurate for long, resistive networks
- Does not model waveform shape (assumes step input)
- Adequate for early estimation, not for signoff

### AWE: Asymptotic Waveform Evaluation

AWE improves on Elmore by computing multiple moments (poles) of the RC network transfer function, producing a more accurate delay and waveform shape.

```
Delay = weighted combination of dominant poles
Waveform = sum of decaying exponentials
```

AWE is more computationally expensive than Elmore but significantly more accurate for complex RC networks. Most modern STA engines use some form of moment-matching (2-pole or higher) for wire delay.

### Arnoldi Reduction

For large RC networks, Arnoldi-based model order reduction compresses the full RC network into a small equivalent circuit while preserving timing accuracy. This is the method used by signoff STA tools (PrimeTime, Tempus) for handling extracted parasitics.

## Interconnect Models

### Pi Model (Two-Segment)

The simplest wire model approximation: two capacitors and one resistor.

```
driver -> C1/2 -> R -> C2/2 -> receiver

Where C1 = near-end capacitance, C2 = far-end capacitance
```

Used during early-stage estimation when detailed parasitics are not available.

### Distributed RC (SPEF)

Post-extraction, the wire is represented as a distributed RC network in SPEF format. Each wire segment has a resistance and capacitance (both grounded and coupling).

```
*D_NET *net1 0.082
*CAP
1 *net1:1 0.005
2 *net1:2 0.008
3 *net1:3 0.004
4 *net1:2 *net2:5 0.003  ;# coupling cap
*RES
1 *net1:1 *net1:2 2.5
2 *net1:2 *net1:3 3.1
*END
```

The STA tool builds an RC tree from this data and computes delay to each sink using moment-matching.

### Wire Load Models (WLM)

Before placement, wire lengths are unknown. Wire load models estimate net capacitance and resistance based on fanout:

```liberty
wire_load (medium) {
  resistance : 0.001;    /* ohms per unit length */
  capacitance : 0.0002;  /* pF per unit length */
  slope : 5.0;           /* length scaling factor */
  fanout_length (1, 5.0);
  fanout_length (2, 10.0);
  fanout_length (4, 25.0);
}
```

Wire load models are crude and used only during pre-placement synthesis. Physical-aware synthesis and post-placement analysis use actual wire geometry.

## Slew Propagation

### What Is Slew?

Slew (transition time) is the time for a signal to transition between logic levels. It is measured between defined voltage thresholds (e.g., 20% to 80% of VDD for rise transition).

### Slew Through Cells

Each cell produces an output slew that depends on:
- Input slew (faster input -> faster output, to a point)
- Output load (higher load -> slower output transition)

The output slew is read from the Liberty transition table:

```liberty
rise_transition (slew_template) {
  index_1 ("input_slew_values");
  index_2 ("output_load_values");
  values ("output_slew_values");
}
```

### Slew Degradation on Wires

As a signal propagates through a resistive wire, the transition becomes slower (slew degrades). The slew at the far end of a wire is always worse than at the near end.

```
Slew at sink = sqrt(Slew_at_driver^2 + Slew_degradation^2)
```

Where slew degradation depends on the RC time constant of the wire. Long, resistive wires cause significant slew degradation, which increases the cell delay of the downstream gate.

### Slew Limits (Max Transition)

Excessive slew causes:
- Increased cell delay in downstream gates
- Short-circuit power (both NMOS and PMOS are on simultaneously during slow transitions)
- Noise susceptibility (slow transitions are more vulnerable to crosstalk)
- Potential functional failure if slew exceeds cell characterization limits

Design rules enforce maximum transition constraints:

```tcl
set_max_transition 0.200 [current_design]     ;# 200ps max on signal nets
set_max_transition 0.100 [get_clocks sys_clk]  ;# 100ps max on clock nets
```

## Delay Calculation in the STA Flow

### Pre-Placement (Synthesis)

- Cell delay: Liberty NLDM tables
- Wire delay: Wire load model estimates
- Accuracy: Low (30-50% correlation with final timing)

### Post-Placement, Pre-Route

- Cell delay: Liberty tables with estimated wire loads
- Wire delay: Steiner tree estimation based on cell placement
- Accuracy: Moderate (70-85% correlation)

### Post-Route

- Cell delay: Liberty CCS/ECSM tables with extracted Ceff
- Wire delay: Distributed RC from SPEF extraction
- SI effects: Crosstalk delta delay added
- Accuracy: High (95%+ correlation with silicon)

### Post-Route with SI

- All of the above, plus coupling-capacitance-induced delay adjustments
- This is the signoff-quality analysis

## Practical Delay Debug Techniques

### Path Delay Decomposition

When debugging a critical path, decompose it:

```tcl
report_timing -from launch_ff/CK -to capture_ff/D \
  -path_type full_clock_expanded -nets -capacitance -transition
```

This shows for each stage:
- Cell name and type
- Input slew
- Output load (capacitance)
- Cell delay
- Wire delay (net delay)
- Cumulative delay

### Identifying Delay Bottlenecks

Look for:
- **High cell delay:** Cell is undersized for its load -> upsize
- **High wire delay:** Long net with high RC -> insert buffer or shorten wire
- **High input slew:** Previous stage has poor slew -> improve upstream driver
- **High output capacitance:** Too many fanout sinks -> clone driver or split fanout

### SPICE Correlation

For critical paths, extract the path and run SPICE simulation with the same PVT conditions. Compare with STA:
- Cell delay mismatch > 5%: Check Liberty characterization and extraction
- Wire delay mismatch > 10%: Check extraction corner and RC accuracy
- Total path mismatch > 5%: Investigate each component individually

## Practical Recommendations

1. **Always check slew propagation.** A violation of max_transition on an internal net can cascade through multiple stages, degrading delay throughout the path.

2. **Insert buffers on long nets.** Any net longer than 200-300um at advanced nodes should have a repeater buffer to prevent excessive wire delay and slew degradation.

3. **Use CCS/ECSM for post-route timing.** NLDM inaccuracy at advanced nodes can be 10-20% on wire-delay-dominated paths.

4. **Understand the driver-load ratio.** As a rule of thumb, the optimal next-stage gate size is 3-4x the driving stage (FO4 fanout-of-4 rule). Significant deviations indicate sizing opportunities.

5. **Monitor net delay as a fraction of total delay.** If wire delay exceeds 50% of total path delay, focus on physical optimization (placement, routing, buffering) rather than gate-level optimization.

Delay calculation is the core engine of static timing analysis. Understanding how cell delays and wire delays are computed, what affects them, and how to debug discrepancies is fundamental to every physical design engineer's work.
