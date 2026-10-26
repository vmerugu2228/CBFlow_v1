# Liberty Timing Models: Cell Characterization and Delay Formats

## What Is Liberty?

Liberty (.lib) is the industry-standard format for describing the timing, power, and functionality of standard cells, IO pads, and memory macros. Every timing analysis in the VLSI flow -- from synthesis through signoff STA -- relies on Liberty models to compute cell delays, transition times, and constraint checks (setup, hold, minimum pulse width).

Liberty files are generated through cell characterization, where SPICE simulations are run across a matrix of input conditions to populate lookup tables. The accuracy of these tables directly determines the accuracy of STA.

## Liberty File Structure

A Liberty file contains:

```liberty
library (ss_0p72v_125c) {
  /* Library-level attributes */
  delay_model : table_lookup;
  time_unit : "1ns";
  voltage_unit : "1V";
  capacitive_load_unit (1, pf);

  operating_conditions (ss_0p72v_125c) {
    process : 1.0;
    voltage : 0.72;
    temperature : 125;
  }

  /* Cell definitions */
  cell (BUFX4_SVT) {
    area : 2.016;
    cell_leakage_power : 0.00123;

    pin (A) {
      direction : input;
      capacitance : 0.0015;
    }

    pin (Y) {
      direction : output;
      function : "A";
      max_capacitance : 0.12;

      timing () {
        related_pin : "A";
        timing_type : combinational;
        cell_rise (delay_template) { ... }
        cell_fall (delay_template) { ... }
        rise_transition (slew_template) { ... }
        fall_transition (slew_template) { ... }
      }
    }
  }
}
```

## Delay Models

### NLDM: Non-Linear Delay Model

NLDM is the traditional and most widely used delay model. Cell delay and output transition (slew) are stored as 2D lookup tables indexed by:
- **Input transition time** (input slew)
- **Output load capacitance**

```liberty
cell_rise (delay_7x7) {
  index_1 ("0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0");    /* input slew */
  index_2 ("0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5");   /* output load */
  values ( \
    "0.023, 0.028, 0.038, 0.068, 0.125, 0.240, 0.585", \
    "0.025, 0.030, 0.040, 0.070, 0.127, 0.242, 0.587", \
    ...
  );
}
```

**How NLDM computes delay:**
1. Look up the input slew from the driving cell's output transition table
2. Look up the output load from the downstream net capacitance
3. Interpolate the 2D table to get cell delay and output slew
4. The output slew becomes the input slew for the next cell

**NLDM limitations:**
- Models the output as a simple voltage source driving a lumped capacitance
- Does not account for the interaction between the cell's output impedance and the distributed RC of the output net
- At advanced nodes with high wire resistance, NLDM overestimates or underestimates delay depending on the net topology

### CCS: Composite Current Source

CCS (Synopsys) improves on NLDM by modeling the cell output as a time-varying current source rather than a voltage source. This enables accurate simulation of the cell driving a distributed RC network.

```liberty
output_current_rise (ccs_current_template) {
  index_1 ("input_slew_values");
  index_2 ("output_cap_values");
  index_3 ("time_points");
  values ("current_at_each_time_point");
}
```

**CCS advantages:**
- Accurately models the interaction between cell output characteristics and load network topology
- Handles complex load networks (RC trees with multiple branches) correctly
- Essential for accuracy at 16nm and below where wire RC is significant

**CCS components:**
- **CCS Timing:** Current waveform for delay and transition computation
- **CCS Power:** Current waveform for dynamic power computation
- **CCS Noise:** Current waveform for noise propagation analysis

### ECSM: Effective Current Source Model

ECSM (Cadence) is functionally similar to CCS but uses a different representation. Instead of current waveforms, ECSM stores voltage waveforms at the cell output.

```liberty
ecsm_waveform (ecsm_template) {
  index_1 ("input_slew_values");
  index_2 ("output_cap_values");
  index_3 ("voltage_points");
  values ("time_at_each_voltage_point");
}
```

ECSM and CCS achieve similar accuracy. The choice is typically determined by the tool ecosystem (Synopsys tools prefer CCS; Cadence tools prefer ECSM).

## Timing Arcs

### Combinational Timing Arcs

Define the delay from an input pin to an output pin:

```liberty
timing () {
  related_pin : "A";
  timing_type : combinational;
  timing_sense : positive_unate;  /* or negative_unate, non_unate */
  cell_rise (...) { ... }
  cell_fall (...) { ... }
  rise_transition (...) { ... }
  fall_transition (...) { ... }
}
```

**Timing sense:**
- `positive_unate`: Output rises when input rises (buffer, AND, OR)
- `negative_unate`: Output falls when input rises (inverter, NAND, NOR)
- `non_unate`: Output behavior depends on other inputs (XOR, MUX)

### Sequential Timing Arcs

Define clock-to-Q delay, setup time, and hold time for flip-flops:

```liberty
/* Clock-to-Q delay */
timing () {
  related_pin : "CK";
  timing_type : rising_edge;
  cell_rise (...) { ... }
  cell_fall (...) { ... }
}

/* Setup constraint */
timing () {
  related_pin : "CK";
  timing_type : setup_rising;
  rise_constraint (...) { ... }
  fall_constraint (...) { ... }
}

/* Hold constraint */
timing () {
  related_pin : "CK";
  timing_type : hold_rising;
  rise_constraint (...) { ... }
  fall_constraint (...) { ... }
}
```

Setup and hold tables are indexed by data transition time and clock transition time.

## Cell Characterization

### The Characterization Process

1. **Define the characterization matrix:** Input slew values, output load values, PVT conditions
2. **Run SPICE simulation** for each (input_slew, output_load) combination
3. **Measure delay:** Time from input threshold crossing to output threshold crossing
4. **Measure transition:** Time from 10% to 90% (or 20% to 80%) of output swing
5. **Measure power:** Integrate current waveform to get switching energy
6. **Populate Liberty tables** with measured values

### Threshold Points

Delay is measured between threshold voltage crossings:
- **50% VDD** is the standard threshold for delay measurement
- **10%/90% VDD** (or 20%/80%) for transition time measurement

Different libraries may use different thresholds, defined in the Liberty header:

```liberty
slew_lower_threshold_pct_rise : 20.0;
slew_upper_threshold_pct_rise : 80.0;
input_threshold_pct_rise : 50.0;
output_threshold_pct_rise : 50.0;
```

### PVT Tables

Each PVT corner requires a separate Liberty file characterized at that specific process, voltage, and temperature. A design with 8 signoff corners requires 8 Liberty files per library.

## Advanced Liberty Features

### Receiver Capacitance (CCS Receiver)

The input pin capacitance is not a single value -- it varies with the input waveform. CCS receiver models store the input pin capacitance as a function of input slew and voltage, improving accuracy for cell delay calculation in the driving stage.

### Electromigration (EM) Limits

Liberty can contain current density limits for cell pins, used during EM analysis:

```liberty
pin (Y) {
  max_transition : 0.5;
  max_capacitance : 0.2;
  /* EM constraints */
  signal_electromigration () { ... }
}
```

### AOCV/LVF Data

Variation data for advanced OCV analysis is embedded in Liberty:

```liberty
ocv_sigma_cell_rise (sigma_template) {
  index_1 ("input_slew_values");
  index_2 ("output_load_values");
  values ("sigma_values");
}
```

## Liberty for Different Cell Types

### Standard Cells

Full timing, power, and functional characterization. Includes combinational cells (BUF, INV, AND, OR, MUX) and sequential cells (DFF, DLATCH, ICG).

### IO Pads

IO pad Liberty includes:
- Drive strength and slew rate control tables
- Input buffer delay and capacitance
- Simultaneous Switching Noise (SSN) data

### Memory Macros (SRAMs, Register Files)

Memory Liberty includes:
- Read and write access time
- Setup and hold on address, data, and control pins
- Cycle time (minimum clock period)
- Typically NLDM-only (CCS characterization of large macros is expensive)

### Hard IP (PLL, ADC, SerDes)

Hard IP Liberty provides:
- Interface timing (pin-level constraints)
- Often simplified models with conservative timing

## Practical Recommendations

1. **Use CCS or ECSM for signoff at 16nm and below.** NLDM is insufficient for accurate timing at advanced nodes. Keep NLDM for early-stage estimation and synthesis.

2. **Verify library consistency.** All Liberty files for a given PVT must use the same characterization methodology, threshold points, and table templates. Mixing NLDM and CCS in the same corner is invalid.

3. **Check table index ranges.** If your design has input slews or output loads outside the characterized range, the tool extrapolates, which can be inaccurate. Verify that design conditions fall within the table index bounds.

4. **Validate against SPICE.** For critical paths, compare Liberty-based STA delay with SPICE simulation. Correlation within 3-5% is expected; larger discrepancies indicate characterization issues.

5. **Use the latest library version.** Foundries periodically update Liberty files to fix characterization errors or improve accuracy. Always use the version specified in the PDK release notes.

6. **Understand the delay model your tools use.** Synthesis typically uses NLDM for speed. Signoff STA should use CCS/ECSM for accuracy. Ensure the correct model is loaded at each stage.

Liberty files are the fundamental data source for all timing analysis. Understanding their structure, contents, and limitations is essential for interpreting STA results and debugging timing discrepancies.
