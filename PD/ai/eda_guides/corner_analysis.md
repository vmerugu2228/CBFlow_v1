# Corner Analysis: PVT Corners and Worst-Case Timing

## The Role of PVT Corners

Semiconductor manufacturing introduces variability in three fundamental dimensions: Process (P), Voltage (V), and Temperature (T). A fabricated chip will not behave identically to the simulation model at nominal conditions. Corner analysis ensures the design functions correctly across the full range of expected manufacturing and operating conditions.

Each PVT corner represents a specific combination of process skew, supply voltage, and junction temperature. Timing signoff requires that setup and hold constraints are met at every relevant corner simultaneously.

## Process Corners

Process variation arises from lithographic imprecision, doping fluctuations, oxide thickness variation, and other manufacturing tolerances. The foundry characterizes these variations into discrete process corners:

### Slow-Slow (SS)

Both NMOS and PMOS transistors are slow. Gate delays are longest, drive strengths are weakest. This is the worst case for setup timing because signals take the longest to propagate.

### Fast-Fast (FF)

Both NMOS and PMOS transistors are fast. Gate delays are shortest, drive strengths are strongest. This is the worst case for hold timing because signals arrive too quickly, potentially violating hold requirements at capturing flip-flops.

### Typical-Typical (TT)

Both NMOS and PMOS are at nominal process. Used for power estimation, functional simulation, and as a reference point. Not typically used for signoff timing.

### Slow-Fast (SF) and Fast-Slow (FS)

Skewed corners where NMOS and PMOS transistors have opposite process skews. These are critical for circuits sensitive to NMOS/PMOS balance, such as SRAM bit cells, sense amplifiers, level shifters, and analog circuits. In digital signoff, SF and FS are sometimes included for specific path types or IP blocks.

### Process Sigma and Yield

Foundries specify corners at a certain sigma level (e.g., 3-sigma). A 3-sigma SS corner means that only 0.13% of chips will be slower than this corner. The choice of sigma level is a yield-reliability tradeoff -- tighter margins (higher sigma) improve yield but increase area and power.

## Voltage Ranges

Supply voltage variation comes from several sources:

- **Regulator tolerance** -- The voltage regulator on the board or in the PMU has a specified accuracy range (e.g., +/-5%).
- **IR drop** -- Resistive voltage drop across the power delivery network reduces the voltage at the cell.
- **Ldi/dt droop** -- Inductive voltage droop from sudden current transients.
- **Voltage scaling** -- Designs operating at multiple voltage levels (e.g., DVFS) must be analyzed at each operating voltage.

### Typical Voltage Ranges

For a nominal 0.75V process:
- **Minimum operating voltage:** 0.675V (SS corner) -- worst-case for setup
- **Nominal voltage:** 0.75V (TT corner)
- **Maximum operating voltage:** 0.825V (FF corner) -- worst-case for hold

The minimum voltage at the SS corner creates the longest gate delays (worst setup). The maximum voltage at the FF corner creates the shortest gate delays (worst hold).

### IR Drop Derating

Rather than modeling IR drop explicitly at every cell, some methodologies apply a voltage derating to the signoff corner. For example, if worst-case IR drop is 30mV, the signoff library might be characterized at 0.675V instead of 0.72V. More advanced flows use instance-level voltage maps from IR drop analysis to apply per-cell derating.

## Temperature Ranges

Temperature affects both transistor behavior and interconnect resistance.

### Transistor Temperature Effects

- **At larger technology nodes (28nm and above):** Higher temperature means slower transistors (increased threshold voltage, reduced mobility). SS corners are paired with high temperature (125C) for worst-case setup.
- **At advanced nodes (16nm FinFET and below):** Temperature inversion can occur at low voltages. Below a certain voltage threshold, transistors actually become slower at lower temperatures due to threshold voltage increase dominating over mobility degradation. This means cold temperatures can be setup-critical at low voltages.

### Interconnect Temperature Effects

Metal resistance increases with temperature. At 7nm and below, where wire resistance is a significant component of total delay, high temperature increases wire delay substantially. This reinforces the traditional pairing of high temperature with setup-critical analysis for interconnect-dominated paths.

### Typical Temperature Ranges

- **Commercial:** 0C to 100C junction temperature
- **Industrial:** -40C to 125C junction temperature
- **Automotive:** -40C to 150C (or higher for under-hood applications)
- **Military/Aerospace:** -55C to 175C

## Standard Signoff Corner Matrix

A typical signoff corner matrix for an advanced FinFET design:

| Corner Name | Process | Voltage | Temp | RC | Primary Use |
|---|---|---|---|---|---|
| ss_0p675v_125c | SS | 0.675V | 125C | Cmax | Setup (worst) |
| ss_0p675v_m40c | SS | 0.675V | -40C | Cmax | Setup (temp inversion check) |
| ff_0p825v_m40c | FF | 0.825V | -40C | Cmin | Hold (worst) |
| ff_0p825v_125c | FF | 0.825V | 125C | Cmin | Hold (high temp) |
| tt_0p75v_25c | TT | 0.75V | 25C | Ctyp | Power estimation |
| ss_0p72v_125c | SS | 0.72V | 125C | Cmax | Setup (nominal IR drop) |
| ff_0p78v_m40c | FF | 0.78V | -40C | Cmin | Hold (nominal voltage) |

## Worst-Case Analysis Strategy

### Setup Timing

Setup violations occur when data arrives too late at the capturing flip-flop. Worst case for setup:
- **Slowest data path:** SS process, low voltage, high temperature (or low temperature with inversion), Cmax extraction
- **Fastest clock path:** Ideally analyzed with OCV derating rather than a separate corner for the clock

### Hold Timing

Hold violations occur when data changes too quickly after the clock edge. Worst case for hold:
- **Fastest data path:** FF process, high voltage, low temperature, Cmin extraction
- **Slowest clock path:** Again, OCV derating handles this rather than a separate corner

### The Role of OCV

On-Chip Variation (OCV) derating accounts for local variation within a single chip. While global PVT corners capture die-to-die and lot-to-lot variation, OCV captures the fact that two nearby cells on the same die may have slightly different delays. OCV is applied on top of the PVT corner as additional derating (see the OCV guide for details).

## Best-Case and Typical Analysis

### Best-Case Analysis

Best-case (FF) analysis is not just for hold fixing. It also serves to:
- Validate minimum pulse width requirements
- Check clock duty cycle distortion at fast corners
- Verify that fast paths do not cause functional issues (e.g., race conditions)

### Typical Analysis

TT corner analysis is used for:
- Power estimation and power budgeting
- Dynamic simulation correlation with RTL
- Performance benchmarking (typical speed grade)
- Initial timing exploration before signoff corners are finalized

## Practical Recommendations

1. **Start with the foundry-recommended signoff corners.** The PDK documentation specifies which PVT points are required. Do not invent your own corners.

2. **Check for temperature inversion.** At advanced nodes with low operating voltages, run setup analysis at both hot and cold temperatures. The cold corner may be worse.

3. **Separate RC corners from PVT corners.** Use Cmax for setup-critical analysis and Cmin for hold-critical analysis. Do not use the same RC condition for both.

4. **Account for aging.** Some signoff methodologies require analysis at beginning-of-life (BOL) and end-of-life (EOL) conditions. EOL libraries model transistor degradation (NBTI, HCI) that slows cells over time.

5. **Validate with SPICE correlation.** For critical paths, correlate STA results at each corner with SPICE simulation using the same PVT conditions. Discrepancies indicate modeling issues.

6. **Do not over-optimize for non-signoff corners.** Including too many intermediate corners in active optimization wastes runtime. Focus optimization on the dominant signoff corners and verify the rest passively.

7. **Document corner definitions clearly.** Every corner should have an unambiguous name that encodes its PVT and RC conditions. Ambiguous names like "worst" or "best" cause confusion when multiple voltage domains or operating conditions are involved.

Corner analysis is the foundation of reliable silicon. Getting the corner matrix right -- and understanding why each corner exists -- is essential for every physical design engineer.
