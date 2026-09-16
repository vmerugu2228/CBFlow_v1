# Analog/Mixed-Signal Verification

## Overview

Modern SoCs integrate significant analog and mixed-signal (AMS) content alongside digital logic: PLLs, ADCs, DACs, SerDes transceivers, voltage regulators, temperature sensors, and analog front-ends. Verifying the interaction between analog and digital domains is critical because bugs at the analog-digital interface are common and difficult to detect with digital-only simulation. AMS verification bridges the gap between analog circuit simulation (SPICE) and digital verification (SystemVerilog/UVM) using modeling techniques that balance accuracy against simulation speed.

## Real-Number Modeling (RNM)

### Concept

Real-number modeling represents analog signals as continuous real-valued variables in SystemVerilog, enabling analog behavior to be simulated within a digital simulator without requiring a SPICE engine.

```systemverilog
module pll_rnm (
  input  logic       ref_clk,
  input  logic       enable,
  input  logic [7:0] divider_ratio,
  output logic       pll_clk,
  output real        vctrl,
  output logic       lock
);
  real     frequency;
  real     target_frequency;
  real     phase_error;
  real     loop_filter_out;
  int      lock_counter;

  // Phase detector model
  always @(posedge ref_clk) begin
    if (enable) begin
      target_frequency = REF_FREQ * divider_ratio;
      phase_error = target_frequency - frequency;
      loop_filter_out = loop_filter_out + (KP * phase_error) + (KI * phase_error);
      vctrl = loop_filter_out;
    end
  end

  // VCO model
  always begin
    frequency = KVCO * vctrl + F_FREE;
    if (frequency > 0) begin
      #(0.5e9 / frequency);  // Half period
      pll_clk = ~pll_clk;
    end else begin
      #1ns;
    end
  end

  // Lock detector
  always @(posedge ref_clk) begin
    if (abs_real(phase_error) < LOCK_THRESHOLD)
      lock_counter <= (lock_counter < LOCK_COUNT) ? lock_counter + 1 : lock_counter;
    else
      lock_counter <= 0;
    lock <= (lock_counter >= LOCK_COUNT);
  end
endmodule
```

### RNM Advantages

- **Speed**: Runs at digital simulation speed (100-1000x faster than SPICE).
- **Integration**: Native SystemVerilog — works directly in UVM testbenches.
- **Coverage**: Can be included in functional coverage models.
- **Debug**: Standard waveform tools can display real-valued signals.

### RNM Limitations

- **Accuracy**: Behavioral approximation — does not capture transistor-level effects (noise, mismatch, parasitic loading).
- **Modeling effort**: Requires manual creation of behavioral models for each analog block.
- **Validation**: RNM models must be validated against SPICE or silicon measurements.
- **No circuit-level issues**: Cannot detect issues like signal integrity, supply noise coupling, or process variation effects.

### RNM Modeling Guidelines

1. **Capture the essential transfer function**: Model the input-output relationship accurately.
2. **Include key non-idealities**: Offset, gain error, nonlinearity, settling time, noise (if relevant).
3. **Model timing accurately**: Latency, sample-and-hold timing, clock-to-output delay.
4. **Parameterize**: Make models configurable for different operating conditions.
5. **Validate against SPICE**: Correlate RNM behavior with transistor-level simulation.

## Verilog-AMS

### Overview

Verilog-AMS (Analog and Mixed-Signal) is an IEEE standard language that extends Verilog with analog modeling capabilities. It supports both digital (discrete-event) and analog (continuous-time) modeling in a single language.

### Analog Modeling in Verilog-AMS

```verilog
module resistor (input electrical p, n);
  parameter real R = 1000.0;  // Resistance in ohms
  analog begin
    V(p, n) <+ R * I(p, n);
  end
endmodule

module capacitor (input electrical p, n);
  parameter real C = 1e-12;  // Capacitance in farads
  analog begin
    I(p, n) <+ C * ddt(V(p, n));
  end
endmodule
```

### Mixed-Signal Interface

Verilog-AMS handles the digital-analog boundary through connect modules that model the behavior of the interface:

```verilog
// Digital to analog converter interface
connectmodule d2a (input wire d, output electrical a);
  parameter real vhi = 1.8;
  parameter real vlo = 0.0;
  parameter real tr = 100p;  // Rise time
  parameter real tf = 100p;  // Fall time

  analog begin
    V(a) <+ transition(d ? vhi : vlo, 0, tr, tf);
  end
endconnectmodule
```

### Verilog-AMS Use Cases

- PLL verification with analog VCO and loop filter.
- ADC/DAC verification with analog signal processing.
- SerDes analog front-end with equalization.
- Power management IC verification.
- Sensor interface verification (temperature, pressure, light).

## SPICE Co-Simulation

### Concept

SPICE co-simulation couples a transistor-level SPICE simulator with a digital event-driven simulator. The SPICE engine simulates the analog circuits while the digital simulator handles the digital logic. The two simulators synchronize at defined boundaries.

### SPICE Co-Simulation Flows

**Cadence AMS Designer**
- Xcelium (digital) + Spectre (analog).
- Seamless integration with shared kernel technology.
- Supports Verilog-AMS connect modules for interface modeling.

**Synopsys VCS-AMS**
- VCS (digital) + CustomSim or HSPICE (analog).
- Socket-based co-simulation.
- Supports mixed analog/digital hierarchy.

**Siemens Questa AMS**
- Questa (digital) + Eldo (analog).
- Unified debug environment.

### When to Use SPICE Co-Simulation

- Validating RNM model accuracy against transistor-level behavior.
- Verifying analog circuits that cannot be accurately modeled behaviorally.
- Sign-off verification of critical analog-digital interfaces.
- Debugging analog issues that manifest only with full transistor-level simulation.

### SPICE Co-Simulation Performance

SPICE co-simulation is 100-10,000x slower than digital-only simulation. Use it sparingly:
- Target specific analog-digital interactions, not full-chip verification.
- Use RNM for the majority of verification; SPICE co-simulation for targeted checks.
- Run SPICE co-simulation on short, focused test scenarios.

## Mixed-Signal Coverage

### Analog Parameter Coverage

```systemverilog
covergroup cg_adc_performance;
  // ADC input voltage coverage
  cp_vin: coverpoint int'(adc_vin * 1000) {
    bins near_zero   = {[0:100]};
    bins low_range   = {[101:500]};
    bins mid_range   = {[501:1000]};
    bins high_range  = {[1001:1700]};
    bins near_max    = {[1701:1800]};
  }

  // ADC output code coverage
  cp_code: coverpoint adc_output {
    bins all_codes[] = {[0:255]};
  }

  // Sampling frequency coverage
  cp_fsample: coverpoint sample_rate_mhz {
    bins slow   = {[1:10]};
    bins medium = {[11:50]};
    bins fast   = {[51:100]};
  }
endgroup
```

### Analog Assertion Checking

```systemverilog
// PLL lock time assertion
AST_PLL_LOCK: assert property (@(posedge ref_clk)
  $rose(pll_enable) |-> ##[0:LOCK_TIME_CYCLES] pll_lock
) else $error("PLL failed to lock within %0d cycles", LOCK_TIME_CYCLES);

// ADC DNL assertion (check for missing codes)
always @(posedge sample_clk) begin
  if (adc_valid) begin
    code_hit[adc_output] = 1;
  end
end

// At end of test, check for missing codes
final begin
  foreach (code_hit[i]) begin
    if (!code_hit[i])
      $error("ADC missing code: %0d (DNL violation)", i);
  end
end
```

### Analog Performance Metrics

Key analog metrics to verify:

**ADC metrics:**
- INL (Integral Non-Linearity).
- DNL (Differential Non-Linearity).
- ENOB (Effective Number of Bits).
- SNR (Signal-to-Noise Ratio).
- SFDR (Spurious-Free Dynamic Range).
- Missing codes.

**PLL metrics:**
- Lock time.
- Jitter (cycle-to-cycle, period, accumulated).
- Phase noise.
- Frequency accuracy.
- Lock range.

**DAC metrics:**
- INL/DNL.
- Settling time.
- Glitch energy.
- Output accuracy.

**SerDes metrics:**
- Bit Error Rate (BER).
- Eye diagram metrics (eye width, eye height).
- Jitter (deterministic, random).

## AMS Verification Methodology

### Modeling Abstraction Levels

| Level | Description | Speed | Accuracy | Use Case |
|-------|-------------|-------|----------|----------|
| Ideal | Perfect behavior, no non-idealities | Fastest | Lowest | Early architecture exploration |
| Behavioral (RNM) | Key transfer functions, major non-idealities | Fast | Moderate | Digital-centric verification |
| Verilog-AMS | Detailed behavioral with analog domain | Moderate | Good | Mixed-signal verification |
| SPICE | Transistor-level | Slowest | Highest | Sign-off, analog debug |

### Recommended Flow

1. **Architecture phase**: Use ideal models for system-level exploration.
2. **RTL development phase**: Use RNM models for digital testbench integration.
3. **Integration phase**: Use Verilog-AMS for detailed mixed-signal interaction verification.
4. **Sign-off phase**: Use SPICE co-simulation for critical interface validation.

### Model Correlation

At each abstraction transition, validate the higher-level model against the lower-level model:
- RNM vs. SPICE: Run identical stimulus, compare output waveforms.
- Verilog-AMS vs. SPICE: Compare transfer functions, timing, and non-ideality modeling.
- Document correlation results and known model limitations.

## Debug Techniques

### Mixed-Signal Waveform Analysis

- Plot analog signals (voltage, current) alongside digital signals on the same timeline.
- Use cursors and measurements for timing analysis (settling time, propagation delay).
- FFT analysis for spectral content (ADC/DAC linearity, PLL phase noise).

### Common AMS Bugs

1. **Clock domain interaction**: Digital clock jitter affecting analog sampling.
2. **Supply noise coupling**: Digital switching noise coupling into analog circuits.
3. **Interface timing**: Setup/hold violations at analog-digital boundaries.
4. **Reset sequencing**: Analog blocks not properly initialized after reset.
5. **Configuration sequencing**: Analog calibration dependent on digital register programming order.

## Best Practices

1. **Start with RNM for functional verification** — SPICE is too slow for comprehensive testing.
2. **Validate RNM against SPICE** before trusting behavioral models.
3. **Include analog parameters in functional coverage** to ensure representative testing.
4. **Verify analog-digital interface timing** explicitly — this is the most common source of AMS bugs.
5. **Use SPICE co-simulation sparingly** for targeted sign-off checks, not broad coverage.
6. **Maintain model libraries** with version control and validation records.

## Summary

AMS verification addresses the critical challenge of verifying analog-digital interactions in modern SoCs. Real-number modeling provides digital-simulator-speed behavioral simulation. Verilog-AMS enables detailed mixed-signal modeling. SPICE co-simulation offers transistor-level accuracy for sign-off. A layered approach — using the appropriate abstraction level for each verification phase — balances thoroughness against simulation capacity. Mixed-signal coverage, analog performance assertions, and systematic model correlation ensure comprehensive AMS verification.
