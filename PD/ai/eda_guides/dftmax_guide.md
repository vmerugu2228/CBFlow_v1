# Synopsys DFTMAX: Compression and Advanced Scan

## DFTMAX Overview

DFTMAX is Synopsys's test compression technology, integrated into the DFT Compiler (part of Design Compiler and Fusion Compiler) and supported by TetraMAX ATPG. DFTMAX provides on-chip compression that reduces test data volume and test application time by factors of 50x to 200x or more. The technology has evolved through several generations, from basic DFTMAX to DFTMAX Ultra and Pipeline Scan.

DFTMAX is typically inserted during synthesis as part of the DFT Compiler flow, ensuring tight integration between DFT structures and logic optimization.

## DFTMAX Architecture

### Adaptive Scan

DFTMAX uses an "adaptive scan" architecture that differs from traditional scan in how chains are organized and compressed:

**Codec-based compression**: A decompressor (decoder) expands compressed test data from a small number of scan input channels into a large number of internal scan chains. A compressor (encoder) reduces scan chain outputs into fewer scan output channels.

**XOR network decompressor**: The decompressor uses XOR-based logic to expand input channel data into multiple internal chains. The network is designed so that each internal chain position can be independently controlled through the appropriate combination of input channel values.

**Space compactor**: The compressor combines internal chain outputs using an XOR tree (space compactor). The XOR tree is designed to minimize aliasing while handling X-values through masking.

### DFTMAX Internal Chain Organization

Internal chains in DFTMAX are balanced and organized to maximize compression efficiency:
- Chain count is typically 10-100x the number of external channels
- Chain length is inversely proportional to chain count (for the same total flip-flop count)
- Shorter chains mean fewer shift cycles per pattern

## DFTMAX Configuration in DFT Compiler

### Basic DFTMAX Setup

```tcl
# In Design Compiler / Fusion Compiler

# Enable DFTMAX
set_dft_configuration -max_compression enable

# Configure scan chains and compression
set_scan_configuration -chain_count 8        ;# external channels
set_scan_compression_configuration \
  -chain_count 800 \                         ;# internal chains
  -minimum_compression 50                    ;# minimum compression ratio

# Define scan signals
set_dft_signal -view existing_dft -type ScanClock -timing {45 55} -port CLK
set_dft_signal -view existing_dft -type ScanEnable -port SE
set_dft_signal -view spec -type ScanDataIn -port {SI[0]} -hookup_pin codec/si[0]
set_dft_signal -view spec -type ScanDataOut -port {SO[0]} -hookup_pin codec/so[0]

# Configure test mode
set_dft_signal -view spec -type TestMode -port TM -active_state 1

# Insert DFT
insert_dft

# Verify
dft_drc
```

### Advanced DFTMAX Options

```tcl
# Specify compression ratio target
set_scan_compression_configuration -minimum_compression 100

# Control masking for X-handling
set_scan_compression_configuration -mask_function enable

# Pipeline stages for higher shift frequency
set_scan_compression_configuration -pipeline enable

# Specify codec location
set_scan_compression_configuration -location top

# Minimum/maximum internal chain length
set_scan_compression_configuration \
  -min_chain_length 100 \
  -max_chain_length 500
```

## DFTMAX Ultra

DFTMAX Ultra is the advanced version that achieves higher compression ratios and better X-tolerance:

### Key Features

**Higher compression ratios**: DFTMAX Ultra can achieve 200-500x compression through more efficient encoding.

**Enhanced X-tolerance**: Better handling of unknown values through advanced masking and selective observation techniques.

**Multi-mode compression**: Support for different compression configurations in different test modes, allowing optimization for each test scenario.

**Integrated diagnosis support**: Compression-aware diagnosis that maps compressed fail data back to specific internal chain positions.

### DFTMAX Ultra Configuration

```tcl
# Enable DFTMAX Ultra
set_dft_configuration -max_compression ultra

# Ultra-specific settings
set_scan_compression_configuration \
  -chain_count 2000 \
  -minimum_compression 200 \
  -ultra_compression enable

# X-tolerance configuration
set_scan_compression_configuration \
  -mask_function enhanced \
  -x_tolerance high
```

## Pipeline Scan

Pipeline scan adds pipeline stages within scan chains to enable higher shift clock frequencies. Instead of data shifting through the entire chain length in one clock period, pipeline stages break long chains into segments:

### How Pipeline Scan Works

- Pipeline flip-flops are inserted at regular intervals along scan chains
- During shift, data moves one pipeline segment per clock cycle
- The effective shift frequency is limited by the segment length, not the full chain length
- Higher shift frequency = shorter shift time = lower test cost

### Pipeline Scan Configuration

```tcl
# Enable pipeline scan
set_scan_configuration -pipeline enable

# Specify pipeline depth
set_scan_configuration -pipeline_stages 2

# Specify pipeline segment length
set_scan_configuration -max_pipeline_length 200
```

### Trade-offs

- Area overhead: Pipeline flip-flops add ~2-5% area
- Additional shift cycles: Pipeline latency adds (stages - 1) extra shift cycles per pattern
- Timing benefit: Shift frequency can increase 2-4x, more than compensating for extra cycles

## TetraMAX ATPG Integration

TetraMAX is Synopsys's ATPG tool that generates patterns for DFTMAX-compressed designs:

### Basic ATPG Flow with DFTMAX

```tcl
# Read compressed design
read_netlist design_scan.v
read_netlist tech_lib.v -library

# Build model
run_build_model top_module

# Run DRC
run_drc

# Set fault model
set_faults -model stuck
add_faults -all

# Generate patterns
run_atpg

# Report coverage
report_summaries

# Write patterns
write_patterns patterns_sa.stil -format stil -compress gzip
```

### Transition Fault ATPG

```tcl
set_faults -model transition
add_faults -all

# Configure launch method
set_delay -launch_cycle system_clock  ;# LOC
# or
set_delay -launch_cycle last_shift    ;# LOS

# At-speed configuration
set_atpg -capture_clock_period 1.0ns

run_atpg
report_summaries
```

### Low-Power ATPG in TetraMAX

```tcl
# Shift power reduction
set_atpg -fill adjacent  ;# adjacent fill for low shift power

# Capture power control
set_atpg -power_budget 0.2  ;# 20% capture toggle budget

# Combined
set_atpg -fill adjacent -power_budget 0.15
run_atpg
```

### Coverage Analysis

```tcl
# Detailed fault report
report_summaries -by_module
report_summaries -by_fault_status

# Identify hard-to-detect faults
report_faults -class AU -limit 100  ;# ATPG-untestable faults

# Coverage by module
report_summaries -module cpu_core
report_summaries -module dma_controller
```

## DFTMAX Diagnosis with TetraMAX

TetraMAX supports compression-aware diagnosis:

```tcl
# Read fail data
read_failures fail_data.txt

# Run diagnosis
run_diagnosis

# Report
report_diagnosis -summary
report_diagnosis -detail -limit 20
```

Diagnosis output includes:
- Suspected net location
- Fault type (SA0, SA1, STR, STF)
- Confidence score
- Number of failing patterns explained

## DFT Compiler Advanced Features

### Test Point Insertion

```tcl
# Analyze testability
report_test_point_candidates -count 1000

# Insert test points
set_test_point_configuration -count 500 -type control_observe
insert_test_points
```

### OCC Insertion

```tcl
# Configure OCC
set_occ_configuration -type clock_mux
set_occ_configuration -launch_mode loe  ;# launch-on-edge (LOC)

# Insert OCC
insert_occ
```

### Wrapper Insertion (IEEE 1500)

```tcl
# For hierarchical DFT
set_wrapper_configuration -class core_wrapper
insert_wrapper

# Configure wrapper modes
set_wrapper_mode -intest enable
set_wrapper_mode -extest enable
```

## DFTMAX Design Flow Summary

### Synthesis-Integrated Flow (Recommended)

1. **RTL synthesis with DFT**: Synthesize with DFT-aware settings
   ```tcl
   compile_ultra -scan -gate_clock
   ```

2. **DFT insertion**: Insert DFTMAX compression, scan, OCC
   ```tcl
   set_dft_configuration -max_compression enable
   insert_dft
   dft_drc
   ```

3. **Export for P&R**: Write netlist with DFT structures
   ```tcl
   write_file -format verilog -output design_dft.v
   write_scan_def -output design.scandef
   ```

4. **P&R with scan reordering**: P&R tool reorders scan chains based on placement

5. **ATPG with final netlist**: TetraMAX generates patterns on the final placed-and-routed netlist
   ```tcl
   run_build_model
   run_drc
   run_atpg
   ```

### Post-Synthesis Flow

For designs where DFT is inserted after synthesis:
1. Synthesize without DFT
2. Read synthesized netlist into DFT Compiler
3. Insert DFT structures
4. Re-optimize incrementally
5. Proceed to P&R and ATPG

## Practical Tips for DFTMAX

- **Channel count selection**: Start with the number of available scan pins and work backward to determine internal chain count and compression ratio. More channels = higher compression bandwidth.

- **Compression ratio**: Target 100x as a starting point. Increase if test time or ATE memory is constrained. Decrease if X-density is too high for effective compression.

- **X-source management**: Identify and mitigate X-sources early. Every X that reaches the compressor reduces effective compression. Use `report_scan_compression` to analyze X-impact.

- **Timing closure**: DFTMAX codec paths are usually not timing-critical at typical shift frequencies (100 MHz). However, pipeline scan introduces additional timing paths that must be closed.

- **Area overhead**: DFTMAX typically adds 1-3% area for the codec, masking, and control logic. Pipeline scan adds an additional 2-5%.

- **Incremental ATPG**: For large designs, run stuck-at ATPG first, then transition, then cell-aware. Each run builds on the previous detection.

- **Pattern debugging**: Use TetraMAX's pattern simulation mode to trace specific pattern failures through the compressed logic for debug.
