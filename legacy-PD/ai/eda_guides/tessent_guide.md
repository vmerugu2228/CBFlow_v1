# Siemens Tessent: DFT Tool Guide

## Tessent Overview

Tessent is Siemens EDA's comprehensive DFT platform, widely used across the semiconductor industry for scan insertion, ATPG, compression (EDT), BIST, diagnosis, and yield learning. The Tessent product family spans the entire DFT lifecycle from RTL analysis to silicon diagnosis. This guide covers the primary tools and their practical usage in a production DFT flow.

## Tessent Shell

Tessent Shell is the unified command-line interface for all Tessent DFT operations. It replaces the older tool-specific interfaces (DFTAdvisor, FastScan, etc.) with a single environment that can be configured for different DFT tasks.

### Contexts

Tessent Shell operates in different contexts depending on the task:

**DFT context**: For DFT insertion -- scan replacement, compression (EDT), OCC, BIST, wrapper insertion.
```
set_context dft -no_rtl
```

**Patterns context**: For ATPG pattern generation and fault simulation.
```
set_context patterns -scan
```

**Diagnosis context**: For fault diagnosis from fail data.
```
set_context diagnosis
```

### Basic Flow: DFT Insertion

```tcl
# Start Tessent Shell
set_context dft -no_rtl

# Read design
read_verilog design.v
read_cell_library tech_lib.v
set_current_design top_module

# Define clocks
add_clocks 0 CLK -period 2ns
add_clocks 0 TCK -period 20ns

# Configure scan
set_dft_specification_requirements -scan_chain_count 200
set_scan_configuration -style muxed_flip_flop

# Configure EDT compression
set_edt_configuration -channels 16 -ip_channels 16 -op_channels 16
set_edt_configuration -compression_ratio 100

# Configure OCC
set_occ_configuration -clock_intercept CLK

# Insert DFT
process_dft_specification
insert_test_logic

# Run DRC
run_testability_checks

# Write output
write_design -output_file design_scan.v -replace
write_atpg_setup -output_file atpg_setup.tcl
```

### Basic Flow: ATPG Pattern Generation

```tcl
# Start pattern context
set_context patterns -scan

# Read design
read_verilog design_scan.v
read_cell_library tech_lib.v
set_current_design top_module

# Read ATPG setup
dofile atpg_setup.tcl

# Run DRC
set_fault_type stuck
run_testability_checks

# Generate stuck-at patterns
create_patterns

# Report coverage
report_statistics

# Write patterns
write_patterns patterns_sa.stil -format stil -replace
```

### Transition Fault ATPG

```tcl
set_fault_type transition

# Configure launch method
set_pattern_type -sequential 2  ;# LOC (two capture cycles)

# Configure at-speed
set_at_speed_options -launch_cycle system_clock

# Generate patterns
create_patterns

report_statistics
write_patterns patterns_tdf.stil -format stil -replace
```

## EDT (Embedded Deterministic Test) Configuration

EDT is Tessent's compression technology. Key configuration parameters:

### Channel Configuration
```tcl
# Basic channel setup
set_edt_configuration -channels 16
# Or separate input/output channels
set_edt_configuration -ip_channels 16 -op_channels 16
```

### Compression Ratio
```tcl
# Target compression ratio
set_edt_configuration -compression_ratio 100
# Internal chain count (auto-calculated from ratio if not specified)
set_edt_configuration -internal_chain_count 1600
```

### X-Handling
```tcl
# Enable chain masking for X-tolerance
set_edt_configuration -masking on
# Configure X-press for enhanced X-handling
set_edt_configuration -xpress on
```

### Pipeline EDT
```tcl
# Enable pipelined decompressor for higher shift frequency
set_edt_configuration -pipeline_stages 1
```

## Tessent MemoryBIST

Tessent MemoryBIST generates MBIST controllers, interfaces, and repair logic for embedded memories.

### Memory Definition
```tcl
# Define memory instances
add_memory_instance -name mem_array_0 \
  -type single_port_ram \
  -depth 1024 -width 32 \
  -address_port ADDR -data_in_port DIN \
  -data_out_port DOUT -write_enable_port WEN \
  -clock_port CLK
```

### MBIST Configuration
```tcl
# Configure MBIST controller
set_memory_bist_configuration -controller_count 4
set_memory_bist_configuration -algorithm march_c_minus
set_memory_bist_configuration -retention_test on -retention_time 10ms

# Configure repair
set_memory_bist_configuration -repair on
set_memory_bist_configuration -redundancy_type row_column
```

### MBIST Insertion
```tcl
process_memory_bist_specification
insert_memory_bist

# Verify
run_memory_bist_checks
write_design -output_file design_mbist.v -replace
```

## Tessent LogicBIST

```tcl
# Configure LBIST
set_logic_bist_configuration -prpg_length 32
set_logic_bist_configuration -misr_length 32
set_logic_bist_configuration -pattern_count 10000

# Test point insertion for LBIST coverage
analyze_logic_bist_testability
insert_logic_bist_test_points -count 500

insert_logic_bist
```

## Tessent Diagnosis

Diagnosis identifies the most likely fault locations from production fail data. This is critical for yield learning and failure analysis.

### Scan Diagnosis Flow
```tcl
set_context diagnosis

# Read design and patterns
read_verilog design_scan.v
read_cell_library tech_lib.v
set_current_design top_module
dofile atpg_setup.tcl

# Read fail data
read_fail_data fail_log.txt -format ascii

# Run diagnosis
diagnose

# Report results
report_diagnosis -output_file diag_report.txt
```

### Chain Diagnosis

When scan chains fail (shift data is corrupted), chain diagnosis identifies the failing flip-flop:
```tcl
set_diagnosis_type chain
read_chain_fail_data chain_fail.txt
diagnose_chains
report_chain_diagnosis
```

### Logic Diagnosis

For patterns that fail in capture (not shift), logic diagnosis identifies the most likely failing gate:
```tcl
set_diagnosis_type logic
read_fail_data pattern_fails.txt
diagnose
report_diagnosis -sort_by score
```

Diagnosis results include:
- Suspected fault location (net/gate)
- Fault type (SA0, SA1, transition, bridge)
- Diagnosis score (confidence level)
- Number of patterns explained by the diagnosed fault

## Tessent IJTAG

Tessent supports IEEE 1687 (IJTAG) for flexible test access network design:

```tcl
# Define IJTAG network
add_ijtag_sib -name sib_scan -child_segments {edt_segment}
add_ijtag_sib -name sib_bist -child_segments {mbist_segment lbist_segment}

# Generate ICL/PDL
write_icl -output_file test_network.icl
write_pdl -output_file test_operations.pdl
```

## Key Tessent Commands Reference

### Design Setup
| Command | Purpose |
|---------|---------|
| `read_verilog` | Import Verilog netlist |
| `read_cell_library` | Import technology library |
| `set_current_design` | Set top-level module |
| `add_clocks` | Define clock signals |
| `add_input_constraints` | Set constant values on pins |

### DFT Insertion
| Command | Purpose |
|---------|---------|
| `set_dft_specification_requirements` | Configure scan parameters |
| `set_edt_configuration` | Configure EDT compression |
| `set_occ_configuration` | Configure on-chip clocking |
| `insert_test_logic` | Perform DFT insertion |
| `run_testability_checks` | Run DFT DRC |

### ATPG
| Command | Purpose |
|---------|---------|
| `set_fault_type` | Select fault model (stuck/transition) |
| `create_patterns` | Generate test patterns |
| `report_statistics` | Report coverage metrics |
| `write_patterns` | Export patterns (STIL/WGL/binary) |

### Diagnosis
| Command | Purpose |
|---------|---------|
| `read_fail_data` | Import ATE fail data |
| `diagnose` | Run fault diagnosis |
| `report_diagnosis` | Report diagnosed faults |

## Tessent Flow Integration

### With Synopsys Synthesis (DC/FC)
1. Synthesize with DFT-ready settings in DC/FC
2. Export netlist to Tessent for DFT insertion
3. Return scan-inserted netlist to DC/FC for optimization
4. Or: Use Tessent DFT insertion integrated with synthesis

### With Cadence P&R (Innovus)
1. Tessent inserts DFT pre-P&R
2. Innovus performs scan chain reordering during placement
3. Tessent ATPG uses the reordered chain definition from Innovus
4. Pattern generation accounts for physical chain order

### With STA (PrimeTime/Tempus)
1. Test mode SDC constraints generated by Tessent
2. STA runs with test mode constraints
3. Timing violations fed back to P&R for fixing
4. Tessent uses timing information for timing-aware ATPG

## Practical Tips

- Always run DRC before ATPG -- attempting ATPG with DRC violations wastes time and produces invalid patterns
- Use `report_clocks` and `report_scan_chains` after DFT insertion to verify the structure matches expectations
- For large designs, use incremental ATPG: low effort first (`set_pattern_limits -abort_limit 100`), then increase effort on remaining faults
- EDT channel count and internal chain count are the two most impactful compression parameters -- optimize these for your pin and test time budget
- Save and restore ATPG sessions (`write_session`/`read_session`) for iterative coverage improvement
- Use `-verbose` flags on reports for detailed analysis during debug
- Tessent supports TCL scripting -- automate repetitive flows with scripts
- For multi-million-gate designs, consider hierarchical DFT with block-level Tessent runs
