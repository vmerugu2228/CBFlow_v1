# Synopsys DFTMAX / DFT Compiler Command Reference

Comprehensive command reference for Synopsys DFTMAX and DFT Compiler used within Design Compiler (dc_shell) and Fusion Compiler (fc_shell) environments. Covers scan insertion, compression, on-chip clocking, wrapper cells, DFT DRC, and test protocol generation.

---

## Table of Contents

1. [Environment and Setup](#environment-and-setup)
2. [Scan Configuration Commands](#scan-configuration-commands)
3. [Scan Insertion Commands](#scan-insertion-commands)
4. [DFTMAX Compression](#dftmax-compression)
5. [Adaptive Scan](#adaptive-scan)
6. [Pipeline Scan](#pipeline-scan)
7. [Codec Architecture](#codec-architecture)
8. [On-Chip Clocking (OCC)](#on-chip-clocking-occ)
9. [Wrapper Configuration](#wrapper-configuration)
10. [DFT DRC and Reporting](#dft-drc-and-reporting)
11. [Test Protocol Generation](#test-protocol-generation)
12. [All set_dft Commands Reference](#all-set_dft-commands-reference)
13. [DFT Attributes and Variables](#dft-attributes-and-variables)
14. [Common Flows and Examples](#common-flows-and-examples)

---

## 1. Environment and Setup

### Loading DFT License

```tcl
# In dc_shell or fc_shell
# DFT Compiler is included with DC; DFTMAX requires separate license
set_app_var compile_seqmap_propagate_constants true
set_app_var compile_seqmap_propagate_high_effort true

# Enable DFTMAX
set_app_var test_default_scan_style multiplexed_flip_flop
```

### DFT-Relevant Application Variables

```tcl
# Core DFT variables
set_app_var test_default_scan_style multiplexed_flip_flop
# Options: multiplexed_flip_flop, clocked_scan, lssd, aux_clock_lssd,
#          combinational, none

set_app_var test_default_delay 0
# Default: 0; specifies default delay value in test protocol

set_app_var test_default_bidir_delay 0
# Default: 0; delay for bidirectional ports

set_app_var test_default_period 100
# Default: 100; clock period in test mode

set_app_var test_default_strobe 40
# Default: 40; strobe point for capturing output values

set_app_var test_stil_netlist_format verilog
# Options: verilog, vhdl

set_app_var test_simulation_library ""
# Path to simulation library for test pattern verification

set_app_var test_disable_enhanced_scan_connectivity false
# Default: false; when true disables enhanced scan chain connection

set_app_var test_scan_clock_a_clk_name ""
# Name for lssd clock A

set_app_var test_scan_clock_b_clk_name ""
# Name for lssd clock B
```

### Design Reading for DFT

```tcl
# Read the design
read_ddc design.ddc
# or
read_verilog design.v
current_design top_module

# Link the design
link

# Read constraints
source constraints.sdc
```

---

## 2. Scan Configuration Commands

### set_scan_configuration

Configures global scan insertion parameters.

**Syntax:**
```tcl
set_scan_configuration
    [-style multiplexed_flip_flop | clocked_scan | lssd | aux_clock_lssd]
    [-methodology full_scan | partial_scan]
    [-clock_mixing no_mix | clock_mix | mix_clocks | mix_clocks_not_edges]
    [-max_length <integer>]
    [-chain_count <integer>]
    [-add_lockup <true | false>]
    [-internal_clocks <multi | single>]
    [-power_domain_mixing <true | false>]
    [-voltage_mixing <true | false | limited_mixing>]
    [-create_dedicated_scan_out_ports <true | false>]
    [-replace <true | false>]
    [-preserve_multibit_segment <true | false>]
    [-insert_terminal_lockup <true | false>]
    [-tracking_lockup_cell <cell_name>]
    [-exact_length <integer>]
    [-route_estimate <true | false>]
    [-scan_enable <port_name>]
    [-test_mode <mode_name>]
    [-head_pin_order <list>]
    [-tail_pin_order <list>]
```

**Key Options Explained:**

| Option | Description | Default |
|--------|-------------|---------|
| `-style` | Scan cell style | `multiplexed_flip_flop` |
| `-methodology` | Full or partial scan | `full_scan` |
| `-clock_mixing` | How clocks are mixed in chains | `no_mix` |
| `-max_length` | Maximum flip-flops per chain | unlimited |
| `-chain_count` | Number of scan chains | auto |
| `-add_lockup` | Insert lockup latches at clock boundaries | `true` |
| `-internal_clocks` | Internal clock gating handling | `multi` |
| `-power_domain_mixing` | Allow mixing power domains in chains | `false` |
| `-create_dedicated_scan_out_ports` | Create separate scan out ports | `false` |
| `-replace` | Replace existing scan configuration | `false` |
| `-preserve_multibit_segment` | Keep multibit register segments together | `false` |
| `-insert_terminal_lockup` | Insert lockup at chain end | `false` |
| `-exact_length` | Force exact chain length | N/A |

**Examples:**

```tcl
# Basic scan configuration
set_scan_configuration -chain_count 8 \
    -style multiplexed_flip_flop \
    -clock_mixing mix_clocks

# Full scan with lockup latches
set_scan_configuration -chain_count 16 \
    -methodology full_scan \
    -add_lockup true \
    -clock_mixing mix_clocks_not_edges \
    -max_length 500

# Multi-voltage design
set_scan_configuration -chain_count 12 \
    -voltage_mixing limited_mixing \
    -power_domain_mixing true \
    -add_lockup true

# Partial scan configuration
set_scan_configuration -chain_count 4 \
    -methodology partial_scan \
    -style multiplexed_flip_flop

# Preserve multibit registers during scan stitching
set_scan_configuration -chain_count 8 \
    -preserve_multibit_segment true

# Exact chain length balancing
set_scan_configuration -chain_count 10 \
    -exact_length 256
```

### set_scan_element

Marks or unmarks cells as scan elements.

**Syntax:**
```tcl
set_scan_element <true | false> <object_list>
```

**Examples:**
```tcl
# Mark specific flip-flops as scan elements
set_scan_element true [get_cells U_reg_*]

# Exclude specific flip-flops from scan
set_scan_element false [get_cells {U_ram/mem_reg_*}]

# Exclude all cells in a hierarchy
set_scan_element false [get_cells -hierarchical -filter "ref_name =~ MEM*"]
```

### set_scan_path

Explicitly defines a scan chain.

**Syntax:**
```tcl
set_scan_path <chain_name>
    -scan_data_in <port>
    -scan_data_out <port>
    [-scan_enable <port>]
    [-scan_master_clock <clock>]
    [-test_mode <mode>]
    [-class <class_name>]
    [-ordered_elements <element_list>]
    [-complete <true | false>]
```

**Examples:**
```tcl
# Define a scan chain with specific input/output
set_scan_path chain1 \
    -scan_data_in SI_1 \
    -scan_data_out SO_1 \
    -scan_enable SE

# Define chain with ordered elements
set_scan_path chain2 \
    -scan_data_in SI_2 \
    -scan_data_out SO_2 \
    -ordered_elements {reg_a reg_b reg_c reg_d}

# Define chain for specific test mode
set_scan_path chain_func \
    -scan_data_in SI_FUNC \
    -scan_data_out SO_FUNC \
    -test_mode func_test
```

### set_scan_group

Groups scan cells for chain assignment.

**Syntax:**
```tcl
set_scan_group <group_name> <object_list>
    [-test_mode <mode_name>]
```

**Examples:**
```tcl
# Group all clock domain A registers
set_scan_group clk_a_group [get_cells -hier -filter "clk_pin == clkA"]

# Group by voltage domain
set_scan_group vdd_core_group [get_cells -hier -filter "power_domain == PD_CORE"]
```

### set_scan_register_type

Specifies the scan register type for DFT insertion.

**Syntax:**
```tcl
set_scan_register_type
    [-type <scan_cell_type>]
    [-exact_cell <cell_name>]
    [-objects <cell_list>]
```

**Examples:**
```tcl
# Set all registers to use specific scan cell
set_scan_register_type -type mux_scan

# Use exact library cell for scan replacement
set_scan_register_type -exact_cell SDFFHQX1 -objects [get_cells reg_*]
```

### set_scan_signal

Defines scan-related signals.

**Syntax:**
```tcl
set_scan_signal <signal_type> -port <port_name>
    [-test_mode <mode>]
    [-hookup_pin <pin_name>]
    [-active_state <0 | 1>]
```

**Signal Types:**
- `scan_enable` - Scan enable signal
- `scan_data_in` - Scan data input
- `scan_data_out` - Scan data output
- `test_mode` - Test mode control
- `scan_clock` - Scan clock
- `scan_master_clock` - LSSD master clock
- `scan_slave_clock` - LSSD slave clock

**Examples:**
```tcl
# Define scan enable
set_scan_signal scan_enable -port SE -active_state 1

# Define test mode signal
set_scan_signal test_mode -port TM -active_state 1

# Define scan data ports
set_scan_signal scan_data_in -port SI[0] -test_mode mode_a
set_scan_signal scan_data_out -port SO[0] -test_mode mode_a
```

---

## 3. Scan Insertion Commands

### preview_dft

Runs DFT checks and shows what will happen during insertion without modifying the design.

**Syntax:**
```tcl
preview_dft
    [-test_mode <mode_name>]
    [-show <detail_option>]
    [-no_scan]
```

**Show Options:**
- `all` - All DFT preview information
- `scan_chains` - Scan chain information only
- `scan_cells` - Scan cell information only
- `violations` - DFT rule violations
- `test_points` - Test point information

**Examples:**
```tcl
# Full DFT preview
preview_dft

# Preview for specific test mode
preview_dft -test_mode internal_scan

# Show only chain information
preview_dft -show scan_chains

# Preview without scan (DRC only)
preview_dft -no_scan
```

### insert_dft

Performs actual DFT insertion including scan chain stitching, compression logic, test points, and OCC.

**Syntax:**
```tcl
insert_dft
    [-test_mode <mode_name>]
    [-no_scan]
    [-verbose]
```

**Examples:**
```tcl
# Standard DFT insertion
insert_dft

# Insert DFT for specific test mode
insert_dft -test_mode scan_compressed

# Insert without scan (OCC, wrapper only)
insert_dft -no_scan

# Verbose output for debugging
insert_dft -verbose
```

### Complete Scan Insertion Flow

```tcl
# Step 1: Read and elaborate design
read_verilog rtl/top.v
current_design top
link

# Step 2: Apply constraints
source timing.sdc

# Step 3: Configure scan
set_scan_configuration -chain_count 8 \
    -clock_mixing mix_clocks \
    -add_lockup true

# Step 4: Define scan signals
set_dft_signal -view existing_dft -type ScanClock \
    -timing {45 55} -port clk
set_dft_signal -view existing_dft -type Reset \
    -active_state 0 -port rst_n
set_dft_signal -view spec -type ScanEnable \
    -active_state 1 -port scan_en
set_dft_signal -view spec -type ScanDataIn \
    -port [list SI_0 SI_1 SI_2 SI_3 SI_4 SI_5 SI_6 SI_7]
set_dft_signal -view spec -type ScanDataOut \
    -port [list SO_0 SO_1 SO_2 SO_3 SO_4 SO_5 SO_6 SO_7]

# Step 5: Create test protocol (pre-DFT)
create_test_protocol

# Step 6: Preview DFT
preview_dft

# Step 7: Insert DFT
insert_dft

# Step 8: Verify DFT
dft_drc

# Step 9: Write outputs
write_test_protocol -output test_protocol.spf -test_mode internal_scan
write -format ddc -hierarchy -output top_scan.ddc
write -format verilog -hierarchy -output top_scan.v
```

---

## 4. DFTMAX Compression

### set_dft_drc_configuration

Configures DFT design rule checks including compression-related checks.

**Syntax:**
```tcl
set_dft_drc_configuration
    [-clock_gating_init_cycles <integer>]
    [-allow_se_set_reset_fix <true | false>]
    [-mix_clock_edges_in_scan_chains <true | false>]
    [-internal_pins <true | false>]
    [-connect_clock_gating_enable <true | false>]
```

**Examples:**
```tcl
# Standard DRC configuration
set_dft_drc_configuration \
    -clock_gating_init_cycles 4 \
    -allow_se_set_reset_fix true

# Enable clock edge mixing in chains
set_dft_drc_configuration \
    -mix_clock_edges_in_scan_chains true

# Enable internal pin checking
set_dft_drc_configuration \
    -internal_pins true \
    -connect_clock_gating_enable true
```

### set_scan_compression_configuration

Primary command for DFTMAX compression setup.

**Syntax:**
```tcl
set_scan_compression_configuration
    [-chain_count <integer>]
    [-max_length <integer>]
    [-min_power <true | false>]
    [-xtolerance <percentage>]
    [-base_clocking <edge_sensitive | level_sensitive>]
    [-inputs <integer>]
    [-outputs <integer>]
    [-mode_encoding <auto | binary | one_hot>]
    [-test_mode <mode_name>]
    [-replace <true | false>]
    [-minimum_compression_ratio <float>]
    [-max_shift_length <integer>]
```

**Examples:**
```tcl
# Basic compression: 4 inputs, 4 outputs, many internal chains
set_scan_compression_configuration \
    -chain_count 100 \
    -inputs 4 \
    -outputs 4

# Compression with minimum power
set_scan_compression_configuration \
    -chain_count 200 \
    -inputs 8 \
    -outputs 8 \
    -min_power true

# Set X-tolerance for compression
set_scan_compression_configuration \
    -chain_count 150 \
    -inputs 6 \
    -outputs 6 \
    -xtolerance 10

# Compression with specific mode encoding
set_scan_compression_configuration \
    -chain_count 100 \
    -inputs 4 \
    -outputs 4 \
    -mode_encoding binary

# Specify minimum compression ratio
set_scan_compression_configuration \
    -chain_count 50 \
    -minimum_compression_ratio 20.0

# Set max shift length for power control
set_scan_compression_configuration \
    -chain_count 100 \
    -max_shift_length 128
```

### DFTMAX Compression Complete Flow

```tcl
# 1. Read design
read_ddc top_mapped.ddc
current_design top
link

# 2. Define clocks for test
set_dft_signal -view existing_dft -type ScanClock \
    -timing {45 55} -port clk
set_dft_signal -view existing_dft -type Reset \
    -active_state 0 -port rst_n

# 3. Define test mode
set_dft_signal -view spec -type TestMode \
    -active_state 1 -port test_mode

# 4. Define compressed scan enable
set_dft_signal -view spec -type ScanEnable \
    -active_state 1 -port scan_en \
    -test_mode all

# 5. Define compressed scan I/O (fewer pins than internal chains)
set_dft_signal -view spec -type ScanDataIn \
    -port {csi_0 csi_1 csi_2 csi_3}
set_dft_signal -view spec -type ScanDataOut \
    -port {cso_0 cso_1 cso_2 cso_3}

# 6. Configure compression
set_scan_compression_configuration \
    -chain_count 100 \
    -inputs 4 \
    -outputs 4 \
    -min_power true \
    -xtolerance 10

# 7. Configure scan
set_scan_configuration \
    -add_lockup true \
    -clock_mixing mix_clocks

# 8. Create test protocol and insert
create_test_protocol
preview_dft
insert_dft

# 9. Verify
dft_drc
report_scan_configuration
report_scan_compression_configuration

# 10. Write outputs
write_test_protocol -output compressed.spf \
    -test_mode internal_scan
write -format verilog -hierarchy -output top_compressed.v
write -format ddc -hierarchy -output top_compressed.ddc
```

---

## 5. Adaptive Scan

Adaptive scan is a DFTMAX Ultra feature that dynamically adapts scan patterns during testing to improve coverage with fewer patterns.

### set_dft_configuration (Adaptive Scan)

```tcl
set_dft_configuration
    [-scan_compression_enable <true | false>]
    [-ui_scan_enable <true | false>]
    [-adaptive_scan <true | false>]
    [-codec <shared | dedicated>]
    [-power_domain_aware <true | false>]
```

### Adaptive Scan Configuration

```tcl
# Enable adaptive scan
set_dft_configuration -adaptive_scan true

# Configure adaptive scan parameters
set_scan_compression_configuration \
    -chain_count 200 \
    -inputs 8 \
    -outputs 8 \
    -min_power true

set_adaptive_scan_configuration \
    -streaming_compression <true | false> \
    [-decompressor_feedback <true | false>] \
    [-max_dictionary_size <integer>] \
    [-bit_stuffing <true | false>]
```

### Adaptive Scan Flow

```tcl
# Enable adaptive scan mode
set_dft_configuration -adaptive_scan true

# Define signals
set_dft_signal -view existing_dft -type ScanClock \
    -timing {45 55} -port clk
set_dft_signal -view spec -type ScanEnable \
    -active_state 1 -port scan_en
set_dft_signal -view spec -type TestMode \
    -active_state 1 -port test_mode

# Configure adaptive compression
set_scan_compression_configuration \
    -chain_count 256 \
    -inputs 4 \
    -outputs 4

# Insert adaptive scan DFT
create_test_protocol
preview_dft
insert_dft
```

---

## 6. Pipeline Scan

Pipeline scan allows scan data to be shifted through pipeline stages, reducing test time and power.

### Pipeline Scan Configuration

```tcl
# Enable pipeline scan
set_pipeline_scan_configuration \
    [-enable <true | false>] \
    [-pipeline_stages <integer>] \
    [-global_pipeline <true | false>]

# Example
set_pipeline_scan_configuration \
    -enable true \
    -pipeline_stages 2

# Configure with compression
set_scan_compression_configuration \
    -chain_count 200 \
    -inputs 8 \
    -outputs 8

set_pipeline_scan_configuration \
    -enable true \
    -pipeline_stages 3
```

### Pipeline Scan with OCC

```tcl
# Pipeline scan typically used with OCC for at-speed test
set_pipeline_scan_configuration \
    -enable true \
    -pipeline_stages 2

set_dft_clock_controller \
    -type occ \
    -chain_count 1 \
    -clock_port clk

create_test_protocol
insert_dft
```

---

## 7. Codec Architecture

DFTMAX codec (compressor/decompressor) architecture controls how scan data is compressed and decompressed.

### Codec Configuration

```tcl
# Shared codec (default) - one codec shared across all chains
set_dft_configuration -codec shared

# Dedicated codec - separate codec per chain group
set_dft_configuration -codec dedicated

# Configure codec parameters
set_scan_compression_configuration \
    -chain_count 100 \
    -inputs 4 \
    -outputs 4 \
    -mode_encoding binary
```

### Codec Architecture Details

```tcl
# Decompressor configuration
# The decompressor fans out compressed data to internal chains
# XOR-based decompressor network

# Compactor configuration
# The compactor compresses chain outputs back to fewer outputs
# Uses XOR-tree compaction with X-masking capability

# X-tolerance controls masking of unknown values
set_scan_compression_configuration \
    -xtolerance 15

# Report codec details after insertion
report_scan_compression_configuration
report_dft_drc_violations
```

### Multi-Mode Codec

```tcl
# Configure different compression modes
# Mode 1: High compression
set_scan_compression_configuration \
    -chain_count 200 \
    -inputs 4 \
    -outputs 4 \
    -test_mode compressed_mode

# Mode 2: Bypass mode (no compression)
set_scan_configuration \
    -chain_count 4 \
    -test_mode bypass_mode

# The codec supports mode switching via test_mode signals
```

---

## 8. On-Chip Clocking (OCC)

### set_dft_clock_controller

Configures on-chip clock controllers for at-speed testing.

**Syntax:**
```tcl
set_dft_clock_controller
    -type <occ | pll_bypass | user_defined>
    [-chain_count <integer>]
    [-clock_port <port_name>]
    [-input <port_list>]
    [-output <port_list>]
    [-cell <cell_name>]
    [-cycles <integer>]
    [-max_cycles <integer>]
    [-test_mode <mode_name>]
    [-usage <shift | capture | both>]
    [-occ_input_port <port_name>]
    [-occ_output_port <port_name>]
    [-pll_bypass_port <port_name>]
```

**Examples:**
```tcl
# Basic OCC controller
set_dft_clock_controller \
    -type occ \
    -chain_count 1 \
    -clock_port clk

# OCC with specific cycle count
set_dft_clock_controller \
    -type occ \
    -chain_count 1 \
    -clock_port clk \
    -cycles 2 \
    -max_cycles 8

# OCC for multiple clock domains
set_dft_clock_controller \
    -type occ \
    -chain_count 1 \
    -clock_port clk_core

set_dft_clock_controller \
    -type occ \
    -chain_count 1 \
    -clock_port clk_bus

# PLL bypass controller
set_dft_clock_controller \
    -type pll_bypass \
    -clock_port clk \
    -pll_bypass_port pll_bypass

# OCC with dedicated test mode
set_dft_clock_controller \
    -type occ \
    -chain_count 1 \
    -clock_port clk \
    -test_mode at_speed_test
```

### OCC-Related Signals

```tcl
# OCC scan enable (for OCC chain)
set_dft_signal -view spec -type OccScanEnable \
    -active_state 1 -port occ_se

# OCC scan data in
set_dft_signal -view spec -type OccScanDataIn \
    -port occ_si

# OCC scan data out
set_dft_signal -view spec -type OccScanDataOut \
    -port occ_so

# OCC bypass
set_dft_signal -view spec -type OccBypass \
    -port occ_bypass -active_state 1
```

### Complete OCC Flow

```tcl
# 1. Define clock signals
set_dft_signal -view existing_dft -type ScanClock \
    -timing {45 55} -port clk

# 2. Define scan signals
set_dft_signal -view spec -type ScanEnable \
    -active_state 1 -port scan_en
set_dft_signal -view spec -type ScanDataIn \
    -port {si_0 si_1 si_2 si_3}
set_dft_signal -view spec -type ScanDataOut \
    -port {so_0 so_1 so_2 so_3}

# 3. Define OCC signals
set_dft_signal -view spec -type OccScanEnable \
    -active_state 1 -port occ_scan_en
set_dft_signal -view spec -type OccScanDataIn \
    -port occ_si
set_dft_signal -view spec -type OccScanDataOut \
    -port occ_so

# 4. Configure OCC controller
set_dft_clock_controller \
    -type occ \
    -chain_count 1 \
    -clock_port clk \
    -cycles 2

# 5. Configure scan
set_scan_configuration -chain_count 4 \
    -clock_mixing mix_clocks

# 6. Insert
create_test_protocol
preview_dft
insert_dft

# 7. Report
report_dft_clock_controller
report_scan_path
```

---

## 9. Wrapper Configuration

### set_wrapper_configuration

Configures wrapper cells for hierarchical DFT (IEEE 1500 compatible).

**Syntax:**
```tcl
set_wrapper_configuration
    [-class <wrapper_class>]
    [-reuse_threshold <float>]
    [-shared <true | false>]
    [-instance <instance_name>]
    [-do_not_wrap <port_list>]
    [-implementation <dedicated | shared>]
    [-bus_clock <clock_name>]
    [-core_clock <clock_name>]
    [-chain_count <integer>]
    [-test_mode <mode_name>]
```

**Examples:**
```tcl
# Basic wrapper configuration
set_wrapper_configuration \
    -class wrapper_class1 \
    -chain_count 4

# Shared wrapper cells
set_wrapper_configuration \
    -class wrapper_class1 \
    -shared true \
    -implementation shared

# Wrapper with specific ports excluded
set_wrapper_configuration \
    -class wrapper_class1 \
    -do_not_wrap {jtag_tdi jtag_tdo jtag_tck jtag_tms}

# Wrapper for hierarchical block
set_wrapper_configuration \
    -instance u_sub_block \
    -chain_count 2 \
    -bus_clock bus_clk \
    -core_clock core_clk
```

### Wrapper Signals

```tcl
# Wrapper serial input
set_dft_signal -view spec -type WrapperSerialIn \
    -port wsi

# Wrapper serial output
set_dft_signal -view spec -type WrapperSerialOut \
    -port wso

# Wrapper enable
set_dft_signal -view spec -type WrapperEnable \
    -port wrapper_en -active_state 1

# Wrapper mode
set_dft_signal -view spec -type WrapperMode \
    -port wrapper_mode
```

### Wrapper Insertion Flow

```tcl
# 1. Configure wrapper
set_wrapper_configuration \
    -class core_wrapper \
    -chain_count 4 \
    -implementation dedicated

# 2. Define wrapper signals
set_dft_signal -view spec -type WrapperSerialIn -port wsi_0
set_dft_signal -view spec -type WrapperSerialOut -port wso_0

# 3. Define which ports to wrap
# By default all input/output ports are wrapped
# Exclude specific ports
set_wrapper_configuration \
    -do_not_wrap {clk rst_n scan_en}

# 4. Insert DFT (includes wrapper)
create_test_protocol
preview_dft
insert_dft

# 5. Report
report_wrapper_configuration
```

---

## 10. DFT DRC and Reporting

### check_dft / dft_drc

Runs design rule checks for DFT.

**Syntax:**
```tcl
# Legacy command
check_dft
    [-verbose]
    [-max_violations <integer>]

# Preferred command
dft_drc
    [-verbose]
    [-test_mode <mode_name>]
    [-coverage_estimate]
```

**Examples:**
```tcl
# Run DFT DRC
dft_drc

# Verbose DRC with coverage estimate
dft_drc -verbose -coverage_estimate

# DRC for specific test mode
dft_drc -test_mode compressed_scan

# Legacy check
check_dft -verbose
```

### report_dft_violations / report_scan_path

```tcl
# Report all DFT violations
report_dft_violations

# Report violations by type
report_dft_violations -type <violation_type>
# Violation types: clock, reset, scan, test_mode, x_source,
#                  sequential, combinational

# Report specific severity
report_dft_violations -severity <error | warning | info>

# Report with limit
report_dft_violations -max_violations 100
```

### report_scan_path

```tcl
# Report all scan chains
report_scan_path

# Report specific chain
report_scan_path -chain chain1

# Report with cell details
report_scan_path -view existing_dft -chain all

# Detailed report with pin names
report_scan_path -cell all -view existing_dft
```

### report_scan_configuration

```tcl
# Report current scan configuration
report_scan_configuration

# Report compression configuration
report_scan_compression_configuration

# Report DFT configuration
report_dft_configuration
```

### Additional DFT Reports

```tcl
# Report DFT signal definitions
report_dft_signal

# Report DFT signal with views
report_dft_signal -view existing_dft
report_dft_signal -view spec

# Report test mode
report_test_mode

# Report DFT clock controller
report_dft_clock_controller

# Report DFT insertion summary
report_dft_insertion_configuration

# Report coverage estimate
report_dft_coverage

# Report scan cells
report_scan_register
report_scan_register -type replaced
report_scan_register -type not_replaced

# Report wrapper
report_wrapper_configuration
```

---

## 11. Test Protocol Generation

### create_test_protocol

Creates the test protocol used by ATPG tools.

**Syntax:**
```tcl
create_test_protocol
    [-infer_asynch]
    [-infer_clock]
```

**Examples:**
```tcl
# Standard test protocol creation
create_test_protocol

# Infer asynchronous set/reset
create_test_protocol -infer_asynch

# Infer both async and clock
create_test_protocol -infer_asynch -infer_clock
```

### write_test_protocol

Writes the test protocol to a file.

**Syntax:**
```tcl
write_test_protocol
    -output <filename>
    [-test_mode <mode_name>]
    [-format <stil | wgl | spf>]
    [-names <verilog | vhdl>]
```

**Examples:**
```tcl
# Write SPF format (default)
write_test_protocol -output top_scan.spf

# Write STIL format
write_test_protocol -output top_scan.stil -format stil

# Write for specific test mode
write_test_protocol -output compressed.spf \
    -test_mode compressed_scan

# Write with Verilog names
write_test_protocol -output top_scan.spf -names verilog
```

### write_test_model

Writes the test model for ATPG.

```tcl
# Write test model
write_test_model -output top.test_model -format ctl

# Write with hierarchy
write_test_model -output top.test_model -format ctl -hierarchy
```

### DFT Output Files Summary

```tcl
# Complete DFT output generation
# 1. Netlist
write -format verilog -hierarchy -output top_scan.v
write -format ddc -hierarchy -output top_scan.ddc

# 2. Test protocol
write_test_protocol -output top_scan.spf -test_mode internal_scan

# 3. STIL protocol
write_test_protocol -output top_scan.stil -format stil

# 4. SDF for simulation
write_sdf top_scan.sdf

# 5. SDC for PnR
write_sdc top_scan.sdc

# 6. Scan DEF for PnR (scan chain ordering info)
write_scan_def -output top_scan_def.scandef
```

---

## 12. All set_dft Commands Reference

### set_dft_signal

Defines DFT signals and their properties.

**Syntax:**
```tcl
set_dft_signal
    -view <existing_dft | spec>
    -type <signal_type>
    [-port <port_name>]
    [-pin <pin_name>]
    [-timing <rise_fall_list>]
    [-active_state <0 | 1>]
    [-test_mode <mode_name>]
    [-hookup_pin <pin_name>]
    [-usage <scan | wrp_in | wrp_out | clock>]
```

**Signal Types:**

| Type | Description |
|------|-------------|
| `ScanClock` | Test clock |
| `ScanEnable` | Scan enable |
| `ScanDataIn` | Scan chain input |
| `ScanDataOut` | Scan chain output |
| `TestMode` | Test mode control |
| `Reset` | Reset signal in test |
| `Constant` | Constant value in test |
| `OccScanEnable` | OCC scan enable |
| `OccScanDataIn` | OCC scan data in |
| `OccScanDataOut` | OCC scan data out |
| `OccBypass` | OCC bypass |
| `WrapperSerialIn` | Wrapper serial in |
| `WrapperSerialOut` | Wrapper serial out |
| `WrapperEnable` | Wrapper enable |
| `WrapperMode` | Wrapper mode |
| `MasterClock` | LSSD master clock |
| `SlaveClock` | LSSD slave clock |

**Examples:**
```tcl
# Existing clock signal
set_dft_signal -view existing_dft -type ScanClock \
    -timing {45 55} -port clk

# Specify scan enable
set_dft_signal -view spec -type ScanEnable \
    -active_state 1 -port scan_en

# Multiple scan data ports
foreach i {0 1 2 3} {
    set_dft_signal -view spec -type ScanDataIn -port SI_${i}
    set_dft_signal -view spec -type ScanDataOut -port SO_${i}
}

# Reset signal
set_dft_signal -view existing_dft -type Reset \
    -active_state 0 -port rst_n

# Constant signal in test mode
set_dft_signal -view spec -type Constant \
    -active_state 0 -port func_mode

# Test mode
set_dft_signal -view spec -type TestMode \
    -active_state 1 -port test_mode
```

### set_dft_configuration

Master DFT configuration command.

**Syntax:**
```tcl
set_dft_configuration
    [-scan <true | false>]
    [-scan_compression <true | false>]
    [-clock_controller <occ | none>]
    [-wrapper <true | false>]
    [-test_points <true | false>]
    [-bist <true | false>]
    [-codec <shared | dedicated>]
    [-adaptive_scan <true | false>]
    [-power_domain_aware <true | false>]
    [-ui_scan <true | false>]
```

**Examples:**
```tcl
# Enable scan and compression
set_dft_configuration \
    -scan true \
    -scan_compression true

# Full DFT configuration
set_dft_configuration \
    -scan true \
    -scan_compression true \
    -clock_controller occ \
    -wrapper true \
    -test_points true

# Power-domain aware DFT
set_dft_configuration \
    -scan true \
    -power_domain_aware true
```

### set_dft_clock_gating_configuration

Configures clock gating handling during DFT.

**Syntax:**
```tcl
set_dft_clock_gating_configuration
    [-connect_to <scan_enable | test_mode | constant>]
    [-king_pin_cell <cell_name>]
```

**Examples:**
```tcl
# Connect clock gating enable to scan enable
set_dft_clock_gating_configuration \
    -connect_to scan_enable

# Use specific king pin cell
set_dft_clock_gating_configuration \
    -king_pin_cell TLATNTSCAX2
```

### set_dft_insertion_configuration

Controls detailed insertion parameters.

**Syntax:**
```tcl
set_dft_insertion_configuration
    [-preserve_design_name <true | false>]
    [-synthesis_optimization <none | area | timing>]
```

**Examples:**
```tcl
# Preserve design names during insertion
set_dft_insertion_configuration \
    -preserve_design_name true

# Enable synthesis optimization after DFT
set_dft_insertion_configuration \
    -synthesis_optimization area
```

### set_dft_test_point_configuration

Configures automatic test point insertion.

**Syntax:**
```tcl
set_dft_test_point_configuration
    [-max_test_point_count <integer>]
    [-type <control | observe | both>]
    [-effort <low | medium | high>]
    [-test_mode <mode_name>]
```

**Examples:**
```tcl
# Auto test point insertion
set_dft_test_point_configuration \
    -max_test_point_count 50 \
    -type both \
    -effort high

# Control points only
set_dft_test_point_configuration \
    -max_test_point_count 30 \
    -type control \
    -effort medium
```

### set_dft_power_controller

Configures power controller for low-power test modes.

```tcl
set_dft_power_controller \
    [-power_switch <cell_name>] \
    [-isolation_cell <cell_name>] \
    [-retention_cell <cell_name>] \
    [-test_mode <mode_name>]
```

### set_dft_connect_configuration

Controls DFT signal connectivity.

```tcl
set_dft_connect_configuration \
    [-type <port | pin>] \
    [-hookup_style <mux | direct>]
```

---

## 13. DFT Attributes and Variables

### Key DFT Attributes

```tcl
# Check if cell is scannable
get_attribute [get_cells reg_0] is_scannable

# Check scan replacement status
get_attribute [get_cells reg_0] scan_replaced

# Get scan chain of a cell
get_attribute [get_cells reg_0] scan_chain

# Check if cell is a lockup latch
get_attribute [get_cells lockup_0] is_lockup_latch

# Get DFT signal type
get_attribute [get_ports scan_en] dft_signal_type

# Check compression status
get_attribute [get_cells codec_inst] is_dftmax_codec
```

### Key Application Variables

```tcl
# DFT synthesis variables
set_app_var test_default_scan_style multiplexed_flip_flop
set_app_var test_default_period 100
set_app_var test_default_delay 0
set_app_var test_default_bidir_delay 0
set_app_var test_default_strobe 40
set_app_var test_stil_netlist_format verilog

# DFT optimization variables
set_app_var test_point_insert true
set_app_var compile_seqmap_propagate_constants true

# DFT reporting variables
set_app_var test_max_dft_violations 1000

# DFTMAX variables
set_app_var test_scan_compression_auto_configuration true
set_app_var test_scan_compression_min_power true
```

---

## 14. Common Flows and Examples

### Basic Scan-Only Flow

```tcl
# Read and link
read_ddc mapped.ddc
current_design top
link
source timing.sdc

# Configure scan
set_scan_configuration -chain_count 8 -clock_mixing mix_clocks

# Define signals
set_dft_signal -view existing_dft -type ScanClock -timing {45 55} -port clk
set_dft_signal -view existing_dft -type Reset -active_state 0 -port rst_n
set_dft_signal -view spec -type ScanEnable -active_state 1 -port scan_en
for {set i 0} {$i < 8} {incr i} {
    set_dft_signal -view spec -type ScanDataIn -port SI_${i}
    set_dft_signal -view spec -type ScanDataOut -port SO_${i}
}

# Insert
create_test_protocol
preview_dft
insert_dft
dft_drc

# Output
write_test_protocol -output top.spf
write -format verilog -hierarchy -output top_scan.v
write_scan_def -output top.scandef
```

### DFTMAX Compressed Scan with OCC

```tcl
# Read and link
read_ddc mapped.ddc
current_design top
link
source timing.sdc

# Master DFT configuration
set_dft_configuration -scan true -scan_compression true -clock_controller occ

# Clock and reset
set_dft_signal -view existing_dft -type ScanClock -timing {45 55} -port clk
set_dft_signal -view existing_dft -type Reset -active_state 0 -port rst_n

# Test mode
set_dft_signal -view spec -type TestMode -active_state 1 -port test_mode
set_dft_signal -view spec -type ScanEnable -active_state 1 -port scan_en

# Compressed I/O
for {set i 0} {$i < 4} {incr i} {
    set_dft_signal -view spec -type ScanDataIn -port csi_${i}
    set_dft_signal -view spec -type ScanDataOut -port cso_${i}
}

# OCC signals
set_dft_signal -view spec -type OccScanEnable -active_state 1 -port occ_se
set_dft_signal -view spec -type OccScanDataIn -port occ_si
set_dft_signal -view spec -type OccScanDataOut -port occ_so

# Compression configuration
set_scan_compression_configuration \
    -chain_count 100 -inputs 4 -outputs 4 \
    -min_power true -xtolerance 10

# OCC configuration
set_dft_clock_controller -type occ -chain_count 1 -clock_port clk -cycles 2

# Scan configuration
set_scan_configuration -clock_mixing mix_clocks -add_lockup true

# Insert
create_test_protocol
preview_dft
insert_dft
dft_drc -verbose

# Output
write_test_protocol -output top_compressed.spf -test_mode internal_scan
write -format verilog -hierarchy -output top_dft.v
write -format ddc -hierarchy -output top_dft.ddc
write_scan_def -output top.scandef
write_sdc -output top_dft.sdc
```

### Hierarchical DFT with Wrappers

```tcl
# Bottom-up DFT insertion for sub-block
read_ddc sub_block.ddc
current_design sub_block
link

# Configure wrapper
set_dft_configuration -scan true -wrapper true

# Define wrapper signals
set_dft_signal -view spec -type WrapperSerialIn -port wsi
set_dft_signal -view spec -type WrapperSerialOut -port wso

# Configure wrapper
set_wrapper_configuration \
    -class sub_wrapper \
    -chain_count 2 \
    -implementation dedicated

# Configure internal scan
set_scan_configuration -chain_count 4 -clock_mixing mix_clocks

# Define DFT signals
set_dft_signal -view existing_dft -type ScanClock -timing {45 55} -port clk
set_dft_signal -view spec -type ScanEnable -active_state 1 -port scan_en
for {set i 0} {$i < 4} {incr i} {
    set_dft_signal -view spec -type ScanDataIn -port SI_${i}
    set_dft_signal -view spec -type ScanDataOut -port SO_${i}
}

# Insert
create_test_protocol
preview_dft
insert_dft

# Write sub-block outputs
write -format ddc -hierarchy -output sub_block_dft.ddc
write_test_protocol -output sub_block.spf

# Now at top level
read_ddc top_with_sub.ddc
current_design top
link

# Top-level DFT uses TAM to connect wrapper chains
# ... top-level DFT insertion follows
```

### Multi-Mode DFT

```tcl
# Mode 1: Compressed scan
set_dft_signal -view spec -type TestMode -active_state 1 \
    -port {tm_compressed} -test_mode compressed
set_scan_compression_configuration \
    -chain_count 100 -inputs 4 -outputs 4 \
    -test_mode compressed

# Mode 2: Uncompressed scan (for debug)
set_dft_signal -view spec -type TestMode -active_state 1 \
    -port {tm_uncompressed} -test_mode uncompressed
set_scan_configuration -chain_count 4 -test_mode uncompressed

# Mode 3: BIST mode
set_dft_signal -view spec -type TestMode -active_state 1 \
    -port {tm_bist} -test_mode bist

# Insert all modes
create_test_protocol
preview_dft
insert_dft

# Write protocols for each mode
write_test_protocol -output compressed.spf -test_mode compressed
write_test_protocol -output uncompressed.spf -test_mode uncompressed
```

---

## Quick Reference: Command Cheat Sheet

| Task | Command |
|------|---------|
| Configure scan chains | `set_scan_configuration` |
| Configure compression | `set_scan_compression_configuration` |
| Define DFT signals | `set_dft_signal` |
| Define scan paths | `set_scan_path` |
| Configure OCC | `set_dft_clock_controller` |
| Configure wrapper | `set_wrapper_configuration` |
| Preview DFT changes | `preview_dft` |
| Insert DFT logic | `insert_dft` |
| Run DFT DRC | `dft_drc` |
| Create test protocol | `create_test_protocol` |
| Write test protocol | `write_test_protocol` |
| Report scan chains | `report_scan_path` |
| Report violations | `report_dft_violations` |
| Report DFT config | `report_dft_configuration` |
| Report compression | `report_scan_compression_configuration` |
| Write scan DEF | `write_scan_def` |
