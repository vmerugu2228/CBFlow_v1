# Cadence Modus: DFT and ATPG Tool Guide

## Modus Overview

Cadence Modus is an integrated test solution that combines DFT synthesis, ATPG, fault simulation, compression, diagnosis, and BIST within a unified platform. Modus leverages Cadence's broader EDA ecosystem, integrating tightly with Genus (synthesis), Innovus (place and route), and Tempus (timing) for an end-to-end DFT flow. It supports both flat and hierarchical DFT methodologies and all major fault models.

## Modus Architecture

Modus is built around several key engines:

**Modus Test Synthesis**: DFT insertion engine for scan, compression, OCC, BIST, and wrapper structures. Can operate standalone or integrated with Genus synthesis.

**Modus ATPG**: Pattern generation engine supporting stuck-at, transition, path delay, cell-aware, bridging, and IDDQ fault models.

**Modus Fault Simulation**: High-performance fault simulator for evaluating coverage of any pattern set.

**Modus Diagnosis**: Scan and logic diagnosis for yield learning and failure analysis.

**Modus Compression**: Integrated test compression with decompressor/compressor insertion and compression-aware ATPG.

## DFT Synthesis with Modus

### Basic Scan Insertion Flow

```tcl
# Read design
read_hdl design.v
read_libs tech_lib.lib

# Elaborate and synthesize (or read pre-synthesized netlist)
elaborate top_module

# Configure scan
set_db dft_scan_style muxed_scan
set_db dft_prefix DFT_

# Define scan chains
define_scan_chain -name chain_1 -sdi SI1 -sdo SO1
define_scan_chain -name chain_2 -sdi SI2 -sdo SO2

# Define test mode
define_test_mode -name scan_mode \
  -test_mode_port TM \
  -scan_enable_port SE

# Configure scan replacement
set_db dft_scan_map_mode tdrc_guided

# Synthesize with scan
synthesize -to_scan

# Check DFT rules
check_dft_rules

# Write output
write_hdl > design_scan.v
write_scandef > design.scandef
```

### Compression Configuration

```tcl
# Enable compression
set_db dft_compression true
set_db dft_compression_channel_count 16
set_db dft_compression_internal_chain_count 1000

# Configure masking for X-handling
set_db dft_compression_mask_enable true

# Insert compression
define_compression -name comp1 \
  -input_channels 16 \
  -output_channels 16 \
  -internal_chains 1000

synthesize -to_scan
```

### OCC Configuration

```tcl
# Define on-chip clocking
define_occ -name occ1 \
  -clock CLK \
  -type pll_mux \
  -launch_mode loc

# Associate OCC with clock domain
set_db occ:occ1 .clock_domain main_clk_domain
```

## ATPG with Modus

### Stuck-At ATPG

```tcl
# Read design
read_design design_scan.v -format verilog
read_library tech_lib.v -format verilog

# Build test model
build_model -design top_module

# Run DRC
run_drc

# Configure stuck-at ATPG
set_fault_model stuck

# Set ATPG options
set_atpg_options -abort_limit 5000
set_atpg_options -compression on

# Run ATPG
run_atpg

# Report results
report_coverage
report_fault_summary

# Write patterns
write_patterns -format stil -output patterns_sa.stil
```

### Transition Fault ATPG

```tcl
set_fault_model transition

# Configure at-speed options
set_delay_test_options -launch_mode loc
set_delay_test_options -clock_period 1.0ns

# Low-power options
set_power_options -capture_toggle_limit 20

run_atpg
report_coverage
write_patterns -format stil -output patterns_tdf.stil
```

### Cell-Aware ATPG

```tcl
# Read cell-aware fault models
read_cell_aware_library cell_aware_models.lib

set_fault_model cell_aware

run_atpg
report_coverage -fault_model cell_aware
```

### Path Delay ATPG

```tcl
set_fault_model path_delay

# Specify critical paths
read_path_list critical_paths.txt

# Or auto-identify timing-critical paths
set_path_delay_options -auto_select -slack_threshold 0.5ns

run_atpg
report_coverage -fault_model path_delay
```

## Fault Simulation

Modus fault simulation evaluates coverage of any pattern set, including functional vectors:

```tcl
# Read design and build model
read_design design_scan.v
build_model -design top_module
run_drc

# Read existing patterns (e.g., from another tool or functional vectors)
read_patterns existing_patterns.stil

# Run fault simulation
set_fault_model stuck
run_fault_simulation

# Report coverage achieved by these patterns
report_coverage
report_fault_summary
```

Fault simulation is useful for:
- Evaluating coverage of functional patterns
- Validating ATPG patterns from other tools
- Incremental coverage analysis (what coverage do these patterns add on top of existing ones?)

## Modus Diagnosis

### Scan Chain Diagnosis

When scan chains fail on silicon (shift data is corrupted):

```tcl
set_diagnosis_type chain

# Read fail data
read_fail_data chain_fails.log

# Run chain diagnosis
run_chain_diagnosis

# Report
report_chain_diagnosis -detail
```

Output identifies the most likely failing flip-flop in each broken chain, including:
- Chain name and position
- Suspected fault type (stuck-at on SI, SO, or SE path)
- Confidence score

### Logic Diagnosis

For capture-cycle failures:

```tcl
set_diagnosis_type logic

# Read fail data (pattern-level fail/pass information)
read_fail_data pattern_fails.log

# Run diagnosis
run_logic_diagnosis

# Report top suspects
report_logic_diagnosis -top 20 -detail
```

Diagnosis provides:
- Net/gate location of suspected defect
- Fault model (SA0, SA1, bridging, transition)
- Score (number of failing patterns explained / total failing patterns)
- Physical coordinates (when DEF is available) for correlation with FA

### Yield-Oriented Diagnosis

For high-volume yield learning:

```tcl
# Process multiple die fail data
read_fail_data -batch die_fail_directory/

# Run statistical diagnosis
run_batch_diagnosis

# Report common failure sites
report_yield_diagnosis -common_sites -threshold 5
```

Common failure sites across many die indicate systematic defects -- candidates for process or design improvement.

## Modus BIST

### MBIST Generation

```tcl
# Define memories
define_memory -name sram_0 \
  -type single_port \
  -depth 4096 -width 64 \
  -instance u_sram_0

# Configure MBIST
set_mbist_options -algorithm march_c_minus
set_mbist_options -retention_test enable -retention_time 50ms
set_mbist_options -repair enable

# Generate MBIST
generate_mbist

# Verify
check_mbist_rules
write_hdl > design_mbist.v
```

### LBIST Configuration

```tcl
# Configure LBIST
set_lbist_options -prpg_size 32
set_lbist_options -misr_size 32
set_lbist_options -pattern_count 50000

# Analyze and insert test points
analyze_lbist_testability
insert_lbist_test_points -count 1000

# Generate LBIST
generate_lbist

# Estimate coverage
estimate_lbist_coverage
```

## Pattern Porting

Pattern porting translates patterns between different netlist versions or between tools:

```tcl
# Read original patterns
read_patterns original_patterns.stil -source_design design_v1.v

# Read target design
read_design design_v2.v
build_model

# Port patterns
port_patterns -output ported_patterns.stil

# Verify ported patterns
run_fault_simulation
report_coverage
```

Common porting scenarios:
- Pre-layout to post-layout netlist (after scan reordering)
- Between ECO versions of the design
- Between different ATE formats (STIL to WGL)
- Between ATPG tools (Tessent patterns to Modus format)

## Integration with Cadence Flow

### Genus Integration

Modus DFT synthesis can be run within Genus:
```tcl
# In Genus
set_db dft_scan_style muxed_scan
synthesize -to_scan
# Genus invokes Modus internally for DFT insertion
```

### Innovus Integration

Scan chain reordering during placement:
```tcl
# In Innovus
read_scandef design.scandef
place_design
reorder_scan_chains  ;# physical-aware scan reordering
write_scandef reordered.scandef
```

The reordered scandef is then used by Modus ATPG to generate patterns with the physical chain order.

### Tempus Integration

Test mode timing analysis:
```tcl
# In Tempus
read_sdc test_mode.sdc
update_timing -mode test
report_timing -mode test -max_paths 100
```

## Modus Key Commands Reference

### Design and Model
| Command | Purpose |
|---------|---------|
| `read_design` | Import netlist |
| `read_library` | Import technology library |
| `build_model` | Build internal test model |
| `run_drc` | Design rule checking |

### DFT Insertion
| Command | Purpose |
|---------|---------|
| `define_scan_chain` | Define scan chain endpoints |
| `define_compression` | Configure compression |
| `define_occ` | Configure on-chip clocking |
| `synthesize -to_scan` | Insert scan and DFT structures |
| `check_dft_rules` | Verify DFT structure |

### ATPG and Fault Simulation
| Command | Purpose |
|---------|---------|
| `set_fault_model` | Select fault model |
| `run_atpg` | Generate test patterns |
| `run_fault_simulation` | Simulate patterns for coverage |
| `report_coverage` | Report fault coverage |
| `write_patterns` | Export patterns |

### Diagnosis
| Command | Purpose |
|---------|---------|
| `read_fail_data` | Import ATE fail data |
| `run_chain_diagnosis` | Diagnose scan chain failures |
| `run_logic_diagnosis` | Diagnose logic failures |
| `report_logic_diagnosis` | Report diagnosis results |

## Practical Tips for Modus

- Use `build_model -effort high` for complex designs to ensure complete model construction
- Run DRC with `-verbose` flag to get detailed violation descriptions and suggested fixes
- For large designs, use hierarchical mode: run block-level ATPG separately, then top-level for interconnect
- Enable parallel processing (`set_atpg_options -threads 8`) for faster ATPG on multi-core machines
- Use incremental ATPG to build coverage gradually: stuck-at first, then transition, then cell-aware
- Save intermediate results frequently (`save_session`) for long-running ATPG jobs
- When porting patterns between netlist versions, always run fault simulation on the target design to verify coverage is maintained
- Use `report_coverage -by_instance` to identify specific blocks with low coverage for targeted improvement
