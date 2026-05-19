# Crosstalk Mitigation: Shielding, Spacing, NDR, Driver Sizing, and SI Analysis

## Overview

Crosstalk is the unintended coupling of signals between adjacent wires due to capacitive and inductive coupling. As process technology scales and wire spacing decreases, crosstalk becomes an increasingly dominant factor in timing, noise, and signal integrity. Crosstalk can cause timing violations (delay change), functional failures (glitch-induced state changes), and increased power consumption. This guide covers crosstalk mechanisms, analysis methods, and practical mitigation techniques used in physical design.

## Crosstalk Mechanisms

### Capacitive Coupling

Adjacent wires in the same or neighboring metal layers share coupling capacitance:

```
     Aggressor wire
     ================
     |||||||||||||||| Coupling capacitance (Cc)
     ================
     Victim wire
```

When the aggressor switches, charge couples onto the victim wire through Cc, causing a voltage perturbation.

**Key factors affecting coupling:**
- **Parallel run length**: longer parallel segments = more coupling
- **Wire spacing**: coupling capacitance decreases roughly as 1/spacing
- **Wire width**: wider wires have more coupling area
- **Metal layer**: upper layers have taller wires with more sidewall coupling
- **Dielectric constant**: lower-k dielectrics reduce coupling but also reduce structural support

### Coupling Ratio

The coupling ratio determines the magnitude of crosstalk:

```
Coupling ratio = Cc / (Cc + Cg + Cd)
```

Where Cc = coupling capacitance, Cg = ground capacitance, Cd = driver output capacitance.

Higher coupling ratios mean stronger crosstalk effects. At advanced nodes, the coupling capacitance often exceeds the ground capacitance, making coupling ratios of 0.5 or higher common.

### Crosstalk Effects

**Functional noise (glitch):**
- Aggressor transition couples a voltage pulse onto a static victim
- If the pulse exceeds the noise margin of the receiving gate, it can cause a logic error
- Most dangerous for asynchronous signals, clock lines, and reset signals

**Timing noise (delta delay):**
- **Same-direction switching**: aggressor and victim switch in the same direction; coupling accelerates the victim transition (speed-up, negative delta delay)
- **Opposite-direction switching**: aggressor and victim switch in opposite directions; coupling slows the victim transition (slow-down, positive delta delay)
- Speed-up can cause hold violations; slow-down can cause setup violations

**Quantification:**
```
Delta delay (slow-down) = Cc * Vagr / (Idriver_victim)
```

Simplified: delta delay is proportional to coupling capacitance and inversely proportional to victim driver strength.

## Victim-Aggressor Analysis

### Identification

SI-aware STA identifies victim-aggressor pairs:

1. **Extract parasitics**: SPEF extraction includes coupling capacitances between nets
2. **Identify aggressors**: for each victim net, identify all nets with significant coupling capacitance
3. **Compute timing windows**: determine when aggressor and victim can switch (from STA timing windows)
4. **Evaluate impact**: compute delta delay and glitch height for each aggressor-victim pair

### Timing Windows

Crosstalk only matters when aggressor and victim can switch simultaneously:

- **Full overlap**: aggressor and victim timing windows overlap completely; worst-case crosstalk
- **Partial overlap**: partial overlap; reduced crosstalk effect
- **No overlap**: timing windows do not overlap; no crosstalk impact (aggressor does not contribute)

The timing window is derived from the earliest and latest arrival times at each point on the victim and aggressor nets.

### Glitch Analysis

For static victim nets (not switching during the aggressor event):

- **Glitch height**: peak voltage of the crosstalk-induced pulse on the victim
- **Glitch width**: duration of the pulse
- **Propagation**: how the glitch propagates through downstream logic gates (attenuated or amplified)
- **Failure criterion**: glitch propagates to a latch/flip-flop data input during its transparent/capture window

### SI-Aware STA Flow

```
1. Extract parasitics with coupling (SPEF with coupling caps)
2. Run initial STA to establish timing windows
3. Compute crosstalk delta delays based on timing windows and coupling
4. Update timing with delta delays
5. Iterate (timing window refinement with updated delays)
6. Report SI-aware slack for all paths
```

## Mitigation Techniques

### Wire Spacing

Increasing the spacing between victim and aggressor wires reduces coupling:

**Double-spacing:**
- 2x minimum spacing between critical nets
- Coupling capacitance reduced by approximately 50%
- Area cost: 2x track consumption for affected nets

**Non-Default Rules (NDR):**
```tcl
# Define NDR with double spacing
create_routing_rule NDR_2X_SPACE \
  -widths {M3 0.1 M4 0.1 M5 0.14} \
  -spacings {M3 0.2 M4 0.2 M5 0.28}

# Apply to clock nets
set_routing_rule [get_nets clk*] -rule NDR_2X_SPACE
```

### Shielding

Insert grounded (VSS) or power (VDD) wires between victim and aggressor:

```
     Aggressor  |  Shield (VSS)  |  Victim
     ========   |  ============  |  ========
```

**Shielding effectiveness:**
- Shield wire absorbs coupling from aggressor, preventing it from reaching victim
- Most effective when shield is grounded (low impedance to absorb coupled charge)
- Shields must be connected to ground at both ends and at regular intervals (to prevent the shield itself from acting as a floating aggressor)

**NDR with shielding:**
```tcl
# NDR with shield wires
create_routing_rule NDR_SHIELDED \
  -widths {M4 0.1} \
  -spacings {M4 0.2} \
  -shield_widths {M4 0.1} \
  -shield_spacings {M4 0.1}
```

**Typical application:**
- Clock nets: always routed with NDR (double spacing and/or shielding)
- Critical async signals: reset, enable signals crossing clock domains
- High-speed data buses: when SI margin is tight

### Driver Sizing

Strengthening the victim driver reduces its susceptibility to crosstalk:

- **Stronger driver**: lower output impedance; coupled charge causes less voltage perturbation
- **Trade-off**: larger driver consumes more area and dynamic power
- **Quantification**: doubling driver strength approximately halves the delta delay

```
Delta_delay ~ Cc * V / I_driver
```

Where I_driver is the victim driver current. Larger driver = larger I_driver = smaller delta delay.

### Victim Net Buffering

Insert buffers along long victim nets to reduce the effective coupling:

- **Buffer insertion**: breaks a long net into shorter segments; each segment has lower coupling
- **Inverter pairs**: restore signal integrity at intermediate points
- **Placement**: buffers should be placed at points where coupling is highest

### Aggressor Net Management

Reduce the aggressor's ability to cause crosstalk:

- **Slew rate control**: slower aggressor transitions couple less charge per unit time
- **Routing avoidance**: route aggressors away from sensitive victims
- **Timing adjustment**: shift aggressor timing to minimize overlap with victim timing window

## Non-Default Routing Rules (NDR)

### NDR Application Strategy

| Net Category | Width | Spacing | Shielding | Justification |
|---|---|---|---|---|
| Clock trunks | 2x | 2x | Yes | Critical timing, glitch prevention |
| Clock branches | 1x | 2x | Optional | Balance area vs. protection |
| Reset/async | 1x | 2x | Yes | Functional failure prevention |
| Critical data | 1x | 1.5x | No | Timing margin improvement |
| Default signals | 1x | 1x | No | Minimum area |

### NDR Impact on Routing

- **Congestion**: NDR wires consume more routing tracks; increases routing congestion
- **Trade-off**: balance SI improvement against routability degradation
- **Selective application**: apply NDR only to nets that need it; avoid blanket rules
- **Congestion analysis**: check post-route congestion with NDR applied; relax rules if routing fails

### Clock NDR Best Practices

- **CTS NDR**: apply double-spacing to all clock tree nets
- **Leaf nets**: may relax to 1.5x spacing for clock tree leaf segments (shorter, less coupling)
- **Clock root**: maximum protection (double-width, double-spacing, shielded) for clock root and trunk
- **Metal layer preference**: route clocks on lower-congestion upper metal layers with NDR

## Advanced Crosstalk Mitigation

### Wire Staggering

Offset wire positions on adjacent metal layers to reduce inter-layer coupling:

- Metal N wires aligned between Metal N+1 wires (not directly above/below)
- Reduces vertical coupling between layers
- Implemented through routing grid offsets in the technology file

### Metal Layer Assignment

- **Route critical nets on layers with favorable geometry**: thicker, wider spacing layers have lower coupling ratios
- **Separate aggressor classes by layer**: route clocks on specific layers away from high-toggle data nets
- **Use orthogonal routing**: perpendicular crossing minimizes coupling (short overlap length)

### Dummy Fill Impact

Metal dummy fill (inserted for CMP uniformity) can affect crosstalk:

- **Grounded fill**: acts as partial shield; can reduce crosstalk
- **Floating fill**: can act as coupling intermediary; may increase or decrease crosstalk depending on geometry
- **Fill-aware extraction**: modern extractors model fill effects on coupling
- **Best practice**: use grounded fill near sensitive nets where possible

## Crosstalk Analysis and Reporting

### Key Reports

```tcl
# Report SI-aware timing with crosstalk delta delays
report_timing -crosstalk_delta

# Report worst aggressors on a specific net
report_noise -net clk_core -above 0.1

# Report glitch analysis
report_noise -type glitch -above_noise_margin

# Report nets with largest delta delay impact
report_si_bottleneck -sort_by delta_delay
```

### Fix Strategies by Severity

**Minor delta delay (< 50 ps):**
- Accept if margin is sufficient
- Gate sizing (strengthen victim driver or weaken aggressor)

**Moderate delta delay (50-200 ps):**
- Increase spacing (NDR)
- Buffer insertion on victim net
- Re-route to reduce parallel run length

**Severe delta delay (> 200 ps) or glitch:**
- Shield the victim net
- Reroute aggressor to different layer or different path
- Add guard bands in timing (last resort; fix the root cause instead)

## Verification Signoff

- Run SI-aware STA on all signoff corners
- Verify no glitches exceed noise margin at any state-holding element
- Confirm clock network meets jitter budget with crosstalk included
- Review worst aggressor-victim pairs and confirm all fixes are applied
- Check that NDR rules are honored in final routing (DRC verification)

Crosstalk mitigation is a critical aspect of physical design at advanced nodes. A systematic approach combining analysis, targeted NDR application, driver sizing, and shielding ensures signal integrity while managing the area and routability costs of protection measures.
