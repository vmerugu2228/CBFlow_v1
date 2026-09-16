# Mixed-Signal DFT: Testing Analog and Mixed-Signal Circuits

## The Mixed-Signal Test Challenge

Modern SoCs are rarely purely digital. They integrate analog-to-digital converters (ADCs), digital-to-analog converters (DACs), phase-locked loops (PLLs), low-noise amplifiers (LNAs), power management units (PMUs), temperature sensors, voltage references, and various I/O transceivers. These analog and mixed-signal (AMS) blocks cannot be tested with standard digital scan techniques because their functionality depends on continuous-valued signals, precise timing, and analog performance metrics (gain, linearity, noise, bandwidth) that have no direct digital equivalent.

Mixed-signal DFT must bridge the gap between the digital test infrastructure (scan, compression, JTAG) and the analog world. The challenge is to provide sufficient test coverage for analog defects while minimizing the impact on analog performance, die area, and test time.

## ADC BIST

### ADC Test Parameters

ADC testing verifies several key parameters:
- **INL (Integral Non-Linearity)**: Maximum deviation of the transfer function from an ideal straight line
- **DNL (Differential Non-Linearity)**: Maximum deviation of any code width from the ideal 1 LSB
- **SNR (Signal-to-Noise Ratio)**: Ratio of signal power to noise power
- **SFDR (Spurious Free Dynamic Range)**: Ratio of signal to the largest spurious component
- **THD (Total Harmonic Distortion)**: Ratio of harmonic power to fundamental power
- **ENOB (Effective Number of Bits)**: Actual resolution considering noise and distortion
- **Offset and Gain Error**: DC errors in the transfer function

### ADC BIST Approaches

**On-Chip Stimulus Generation**: Generate a known analog test signal on-chip to stimulate the ADC without requiring an external precision source.

- **DAC-based stimulus**: Use an on-chip DAC to generate a ramp, sine wave, or known waveform. The DAC resolution must exceed the ADC resolution for meaningful testing. Challenge: the DAC itself may have errors.
- **Sigma-delta stimulus**: Use a low-resolution DAC with oversampling and filtering to generate a high-precision analog signal.
- **Ramp generator**: A capacitor charged by a constant current source creates a linear ramp. Simple and area-efficient.
- **Oscillator-based**: An on-chip oscillator generates a sinusoidal stimulus at a known frequency.

**On-Chip Response Analysis**: Analyze the ADC output digitally on-chip rather than sending raw data off-chip.

- **FFT-based analysis**: Compute FFT of the ADC output to extract SNR, THD, SFDR. Requires significant digital logic for the FFT computation.
- **Histogram analysis**: Collect a histogram of ADC codes from a known input stimulus. The histogram shape reveals INL, DNL, offset, and gain errors. A ramp input should produce a uniform histogram; deviations indicate non-linearity.
- **Signature-based analysis**: Compress ADC output into a signature (similar to MISR) and compare with a known-good signature. Simpler but less diagnostic than FFT or histogram.

### Practical ADC BIST Architecture

```
                +----------+     +---------+
Known Stimulus  | On-chip  |---->| ADC     |----> Digital
Generator       | DAC/Ramp |     | Under   |      Output
                +----------+     | Test    |        |
                                 +---------+        v
                                              +-----------+
                                              | Digital   |
                                              | Analysis  |
                                              | (Hist/FFT)|
                                              +-----------+
                                                    |
                                                    v
                                              Pass/Fail + Metrics
```

## DAC BIST

### DAC Test Parameters
- INL, DNL (similar to ADC but measured at analog output)
- Monotonicity: Output always increases/decreases with increasing/decreasing code
- Settling time: Time for output to reach final value after code change
- Glitch energy: Transient output excursions during code transitions
- Output voltage range and offset

### DAC BIST Approaches

**Loopback through ADC**: Drive DAC with known digital codes, capture DAC analog output with an on-chip ADC. The ADC digitizes the DAC output for digital comparison. Requires an ADC with sufficient accuracy (chicken-and-egg problem with ADC BIST).

**Comparator-based BIST**: Compare DAC output against a precision reference voltage using an on-chip comparator. Step through DAC codes and record at which code the output crosses each reference level. This is simpler than a full ADC loopback.

**Current measurement**: For current-output DACs, measure the output current using an on-chip current sense circuit.

## PLL BIST

### PLL Test Parameters
- Lock time: Time from enable to locked state
- Lock range: Frequency range over which the PLL can lock
- Jitter: Phase noise on the PLL output (period jitter, cycle-to-cycle jitter, long-term jitter)
- Spurious tones: Unwanted frequency components in the output
- Power supply rejection: Sensitivity to supply noise

### PLL BIST Approaches

**Frequency measurement**: Count PLL output clock cycles over a known time window using an on-chip counter. Compare with expected count based on reference frequency and multiplication factor.

```
Counter clocked by PLL output
Reference timer from known clock
PLL_frequency = Counter_value / Reference_time
```

**Lock detection**: Most PLLs include a lock detect circuit. BIST reads lock status after enabling the PLL and compares lock time against specification.

**Jitter measurement**: More challenging on-chip. Approaches include:
- **Time-to-digital converter (TDC)**: Measures the time interval between PLL output edges and reference edges. Multiple measurements give a jitter distribution.
- **Beat frequency method**: Compare PLL output with a slightly offset reference to create a beat frequency that encodes phase information.
- **Phase interpolator**: Use a phase interpolator to sample the PLL output at controlled phases and construct a phase noise profile.

**Loopback BIST**: The PLL output can be divided down and compared with the reference input. Any frequency error, lock failure, or large jitter is detectable.

## Analog Test Wrapper

Analog blocks need isolation during digital test (scan shifting creates noise that disrupts analog circuits) and test access during analog test.

### IEEE 1149.4 (Mixed-Signal Boundary Scan)

Extends IEEE 1149.1 with analog boundary scan capabilities:

**Analog Boundary Module (ABM)**: Placed on analog pins, can connect analog pins to an internal analog test bus for measurement.

**Internal Analog Test Bus**: A pair of differential analog lines (AT1, AT2) routed between the TAP controller and analog boundary modules. Used to source/measure analog signals.

**Test Bus Interface Circuit (TBIC)**: Connects the internal analog bus to external test access points.

**Limitations**: 1149.4 has seen limited adoption due to the complexity of routing precision analog buses on-chip and the performance impact of adding switches to sensitive analog paths.

### Practical Analog Wrapper

A more common approach than full 1149.4:

- **Digital isolation**: Clamp analog block outputs to known digital values during scan shift using isolation cells. Prevents analog noise from corrupting scan chains.
- **Analog bypass**: During digital test, bypass analog blocks with digital loopback paths to maintain scan chain continuity.
- **Test mux**: Add analog multiplexers that can route internal analog signals to external pads for measurement, controlled via JTAG or scan.

## Loopback Testing

Loopback testing is one of the most practical AMS test techniques. It routes the output of a transmitter back to the input of a receiver, creating a self-test loop:

### Digital Loopback
- Digital data is sent through the transmitter analog path and received back through the receiver analog path
- Received digital data is compared with transmitted data
- Tests the entire analog signal chain (TX + channel + RX) without external equipment
- Commonly used for SERDES, USB, PCIe, and other high-speed I/O

### Analog Loopback
- DAC output is routed to ADC input on-chip
- Tests DAC + ADC combined linearity, noise, and gain
- Cannot separate DAC errors from ADC errors, but catches gross defects efficiently

### Loopback Test Implementation

```
                 +---------+     +----------+     +---------+
Digital Data --> | TX      |---->| Loopback |---->| RX      |--> Received Data
(from scan)     | (DAC+   |     | Mux/Path |     | (ADC+   |    (to scan)
                | Driver) |     |          |     | Slicer) |
                +---------+     +----------+     +---------+
                                     ^
                                     |
                                 loopback_enable
                                 (from JTAG/scan)
```

## Mixed-Signal DFT Integration

### DFT Flow for AMS Blocks

1. **RTL/Schematic**: Identify all AMS blocks and their test requirements
2. **Test Plan**: Define BIST, loopback, and external test strategies for each block
3. **Analog Wrapper Design**: Add isolation, bypass, and test mux structures
4. **BIST Design**: Implement ADC BIST, DAC BIST, PLL BIST as needed
5. **Digital Integration**: Connect AMS BIST controllers to JTAG/IJTAG
6. **Verification**: Mixed-signal simulation of test modes
7. **Silicon Validation**: Correlate BIST results with bench measurements

### JTAG Control of Analog Test

AMS test modes are typically controlled via JTAG:
```
JTAG -> Instruction Register -> AMS Test Mode Select
                              -> Loopback Enable
                              -> BIST Start/Status
                              -> Test Mux Select
                              -> Analog Bus Connect
```

## Practical Considerations

### Area Overhead

AMS BIST structures add area:
- ADC BIST (stimulus + analysis): 5-20% of ADC area
- DAC BIST (loopback + comparator): 5-15% of DAC area
- PLL BIST (counter + logic): 2-10% of PLL area
- Loopback mux and routing: Minimal (1-5%)

### Performance Impact

AMS DFT structures must not degrade analog performance:
- Parasitic capacitance from test muxes on sensitive analog nodes
- Noise coupling from digital BIST logic to analog circuits
- Loading from observation circuits on high-impedance nodes

**Mitigation**: Use transmission gates with minimal parasitic capacitance. Place analog test circuits far from sensitive nodes. Use separate power supplies for BIST digital logic.

### Test Accuracy vs. Production Test

On-chip BIST typically achieves lower measurement accuracy than external ATE:
- ADC BIST may resolve INL/DNL to ~1-2 LSB accuracy (vs. 0.1 LSB with external equipment)
- PLL jitter measurement on-chip: ~10 ps resolution (vs. 1 ps with external instruments)

BIST is primarily used for go/no-go defect detection. Precision characterization still requires external instrumentation, typically done on a sample basis rather than 100% production.

### Test Strategy Hierarchy

1. **BIST** (on-chip): Go/no-go production screening. Fast, low cost, every die.
2. **Loopback** (on-chip): Functional path verification. Moderate complexity.
3. **ATE analog measurement**: Precision parameter characterization. Slower, higher cost, sample-based.
4. **Bench measurement**: Full datasheet characterization. Slowest, highest cost, engineering samples only.

## Emerging Trends

**ML-based analog test**: Machine learning models trained on a combination of digital test results, IDDQ measurements, and simple analog measurements to predict complex analog parameters. Reduces the need for expensive analog ATE time.

**Sensor-based monitoring**: On-chip sensors (temperature, voltage, process monitors) that provide indirect information about analog circuit health. Used for both test and in-field monitoring.

**Digital-centric AMS test**: Converting analog test problems to digital problems wherever possible -- using oversampled digital outputs, digital calibration, and digital self-test -- to leverage the efficiency of digital DFT infrastructure.
