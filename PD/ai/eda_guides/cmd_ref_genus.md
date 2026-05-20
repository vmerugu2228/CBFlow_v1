# Cadence Genus Synthesis -- Comprehensive Command Reference

## Table of Contents

1. [Design Read-In Commands](#design-read-in-commands)
2. [Library and Technology Setup](#library-and-technology-setup)
3. [Elaboration and Design Setup](#elaboration-and-design-setup)
4. [Synthesis Commands](#synthesis-commands)
5. [Attribute and Database Commands](#attribute-and-database-commands)
6. [Constraint Commands](#constraint-commands)
7. [Physical-Aware Synthesis](#physical-aware-synthesis)
8. [Incremental Synthesis](#incremental-synthesis)
9. [DFT Integration](#dft-integration)
10. [Reporting Commands](#reporting-commands)
11. [Output and Export Commands](#output-and-export-commands)
12. [GII (Genus-Innovus Integration)](#gii-genus-innovus-integration)
13. [Power Optimization Commands](#power-optimization-commands)
14. [Multi-Mode Multi-Corner (MMMC)](#multi-mode-multi-corner-mmmc)
15. [Datapath Optimization](#datapath-optimization)
16. [Debug and Utility Commands](#debug-and-utility-commands)

---

## Design Read-In Commands

### read_hdl

Reads RTL source files (Verilog, SystemVerilog, VHDL) into the Genus database.

```tcl
# Basic syntax
read_hdl [-verilog | -sv | -vhdl] [-define <macro_list>] [-library <lib_name>] \
         [-f <filelist>] [-incdir <dir_list>] <file_list>

# Read single Verilog file
read_hdl rtl/top.v

# Read SystemVerilog files
read_hdl -sv rtl/top.sv rtl/pkg.sv

# Read with include directories and defines
read_hdl -sv -define "SYNTHESIS FPGA_OFF" -incdir "rtl/include rtl/headers" rtl/top.sv

# Read from file list
read_hdl -sv -f scripts/rtl_filelist.f

# Read VHDL files
read_hdl -vhdl rtl/top.vhd

# Read into a named library (for multi-library designs)
read_hdl -vhdl -library work rtl/top.vhd
read_hdl -vhdl -library mylib rtl/sub_block.vhd

# Read mixed-language design
read_hdl -vhdl rtl/vhdl_block.vhd
read_hdl -sv rtl/sv_wrapper.sv
```

**Options reference:**
| Option | Description |
|--------|-------------|
| `-verilog` | Parse files as Verilog-2001 |
| `-sv` | Parse files as SystemVerilog (IEEE 1800) |
| `-vhdl` | Parse files as VHDL |
| `-define <macros>` | Define preprocessor macros (space-separated) |
| `-incdir <dirs>` | Include directories for `include directives |
| `-f <filelist>` | Read file paths from a file list |
| `-library <name>` | Assign to a named VHDL library |
| `-2008` | Enable VHDL-2008 features |
| `-y <dir>` | Specify Verilog library directory |
| `-v <file>` | Specify Verilog library file |

**Best practices:**
- Always read package files before modules that reference them.
- Use `-sv` explicitly for SystemVerilog; auto-detection can be unreliable.
- Use file lists (`-f`) for large designs to keep scripts maintainable.
- Define `SYNTHESIS` macro to exclude simulation-only code.

---

### read_lib

Reads technology library files (Liberty .lib) into the database.

```tcl
# Basic syntax
read_lib [-lef <lef_file>] [-min] [-max] <liberty_file_list>

# Read a single library
read_lib /libs/stdcells/tt_0p85v_25c.lib

# Read multiple corners
read_lib /libs/stdcells/ss_0p75v_125c.lib
read_lib /libs/stdcells/ff_0p95v_m40c.lib

# Read with associated LEF
read_lib -lef /libs/stdcells/stdcells.lef /libs/stdcells/tt_0p85v_25c.lib

# Read macro libraries
read_lib /libs/sram/sram_tt.lib
read_lib /libs/io/io_tt.lib

# Read QRC techfile for physical-aware synthesis
read_qrc /libs/tech/qrcTechFile

# Read multiple libraries in one command
read_lib [glob /libs/stdcells/*_tt_*.lib] [glob /libs/macros/*_tt_*.lib]
```

**Options reference:**
| Option | Description |
|--------|-------------|
| `-lef <file>` | Associate a LEF file with the library |
| `-min` | Mark library as min (best-case) timing corner |
| `-max` | Mark library as max (worst-case) timing corner |
| `-liberty` | Explicitly specify Liberty format (default) |

**Best practices:**
- For MMMC, read libraries per analysis view (see MMMC section).
- Read LEF files early if doing physical-aware synthesis.
- Ensure library and LEF cell names match exactly.
- Read all required libraries (stdcells, macros, IOs, memories) before elaboration.

---

### read_physical

Reads physical data (LEF, DEF) for physical-aware synthesis.

```tcl
# Read LEF files (technology + cell LEF)
read_physical -lef {/libs/tech/tech.lef /libs/stdcells/stdcells.lef /libs/macros/sram.lef}

# Read DEF file (floorplan)
read_physical -def /data/floorplan/top_fp.def

# Read LEF and DEF together
read_physical -lef /libs/tech/tech.lef -def /data/floorplan/top.def
```

---

## Library and Technology Setup

### set_db (Library/Technology Configuration)

```tcl
# Set library search path
set_db init_lib_search_path {/libs/stdcells /libs/macros /libs/io}

# Set HDL search path
set_db init_hdl_search_path {/rtl /rtl/include /rtl/subblocks}

# Library configuration
set_db library {ss_0p75v_125c.lib sram_ss.lib io_ss.lib}

# Set LEF files
set_db lef_library {tech.lef stdcells.lef sram.lef io.lef}

# Set operating conditions
set_db operating_conditions_max ss_0p75v_125c
set_db operating_conditions_min ff_0p95v_m40c

# Wire load model
set_db interconnect_mode ple
# Options: ple (physical-layout estimation), wireload (statistical)

# Set target library for mapping
set_db target_library {ss_0p75v_125c.lib}
```

---

## Elaboration and Design Setup

### elaborate

Elaborates the design, resolving hierarchy, parameters, and generates.

```tcl
# Basic elaboration
elaborate <design_name>

# Elaborate top-level design
elaborate top_chip

# Elaborate with parameters
elaborate top_chip -parameters {WIDTH 32 DEPTH 16}

# Elaborate with VHDL configuration
elaborate -vhdl_config <config_name> <entity_name>

# Check elaboration status
check_design -unresolved

# Post-elaboration uniquification
uniquify /designs/top_chip
```

**Options reference:**
| Option | Description |
|--------|-------------|
| `<design_name>` | Name of the top-level module/entity |
| `-parameters <list>` | Override parameter values |
| `-vhdl_config <name>` | Use specific VHDL configuration |
| `-no_autouniq` | Disable automatic uniquification |

**Best practices:**
- Always run `check_design` after elaboration to catch issues early.
- Uniquify before applying instance-specific constraints.
- Verify `report_summary` after elaboration for cell counts and hierarchy.

### check_design

Validates the elaborated design.

```tcl
# Full design checks
check_design -all

# Check for unresolved references
check_design -unresolved

# Check for multiple drivers
check_design -multiple_driver

# Check timing constraints
check_timing_intent
```

---

## Synthesis Commands

### syn_generic

Performs technology-independent generic optimization (GTECH mapping).

```tcl
# Basic generic synthesis
syn_generic

# With effort level
syn_generic -effort high

# Physical-aware generic synthesis
syn_generic -physical
```

**Options reference:**
| Option | Description |
|--------|-------------|
| `-effort <level>` | Optimization effort: `low`, `medium`, `high` |
| `-physical` | Enable physical-aware optimization |
| `-dft` | Include DFT structures during generic synthesis |

**What happens during syn_generic:**
1. RTL-level optimizations (constant propagation, dead code removal)
2. Datapath extraction and optimization
3. FSM extraction and optimization
4. Resource sharing
5. Operator merging
6. Generic technology mapping (GTECH)

---

### syn_map

Maps the generic netlist to target technology library cells.

```tcl
# Basic technology mapping
syn_map

# With effort
syn_map -effort high

# Physical-aware mapping
syn_map -physical
```

**Options reference:**
| Option | Description |
|--------|-------------|
| `-effort <level>` | Mapping effort: `low`, `medium`, `high` |
| `-physical` | Enable physical-aware mapping |
| `-area` | Prioritize area optimization |
| `-no_seq_opt` | Disable sequential optimization during mapping |

**What happens during syn_map:**
1. Boolean matching to library cells
2. Cell sizing
3. Buffer insertion
4. Sequential optimization (register merging/splitting)
5. Area recovery

---

### syn_opt

Performs post-mapping incremental optimization.

```tcl
# Basic optimization
syn_opt

# With effort
syn_opt -effort high

# Physical-aware optimization
syn_opt -physical

# Incremental optimization
syn_opt -incr
```

**Options reference:**
| Option | Description |
|--------|-------------|
| `-effort <level>` | Optimization effort: `low`, `medium`, `high` |
| `-physical` | Enable physical-aware optimization |
| `-incr` | Incremental mode -- lighter optimization |
| `-area_recovery` | Focus on area recovery |
| `-spatial` | Enable spatial optimization (physical-aware) |

**What happens during syn_opt:**
1. Timing-driven optimization
2. Area recovery
3. Design rule fixing (max capacitance, max transition, max fanout)
4. Leakage power optimization
5. Critical path restructuring

---

### Full Synthesis Flow (Typical Sequence)

```tcl
# 1. Setup
set_db init_lib_search_path /libs/stdcells
set_db init_hdl_search_path /rtl

# 2. Read libraries
read_lib ss_0p75v_125c.lib
read_physical -lef {tech.lef stdcells.lef}

# 3. Read RTL
read_hdl -sv -f rtl_filelist.f

# 4. Elaborate
elaborate top_chip
check_design -all

# 5. Read constraints
read_sdc /constraints/top.sdc

# 6. Synthesize
syn_generic -physical -effort high
syn_map -physical -effort high
syn_opt -physical -effort high

# 7. Reports
report_timing > reports/timing.rpt
report_area > reports/area.rpt
report_power > reports/power.rpt

# 8. Export
write_hdl > output/top_chip_synth.v
write_sdc > output/top_chip_synth.sdc
write_design -innovus -base_name output/top_chip
```

---

## Attribute and Database Commands

### set_db

The primary command for setting tool attributes and database values in Genus.

```tcl
# ============================================================
# Root-level attributes (global settings)
# ============================================================

# Optimization effort
set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high

# Leakage power optimization
set_db leakage_power_effort high ;# none|low|medium|high

# Dynamic power optimization
set_db dynamic_power_effort high ;# none|low|medium|high

# Area optimization
set_db max_area 0 ;# 0 = minimize area

# Clock gating
set_db lp_insert_clock_gating true
set_db lp_clock_gating_min_flops 4
set_db lp_clock_gating_max_flops 64
set_db lp_clock_gating_cell_aware true

# Datapath optimization
set_db dp_postmap_upsize true
set_db dp_area_mode true

# Sequential optimization
set_db optimize_merge_flops true
set_db optimize_merge_latches false

# Boundary optimization
set_db boundary_opto true

# Ungrouping
set_db auto_ungroup none      ;# none|small|medium|both
set_db ungroup_separator "/"

# Timing
set_db timing_analysis_type best_case_worst_case
set_db timing_cppr both       ;# none|setup|hold|both

# Design rule fixing
set_db max_fanout 20
set_db max_transition 0.3
set_db max_capacitance 0.5

# Naming conventions
set_db hdl_track_filename_row_col true
set_db information_level 7    ;# verbosity: 0-9

# ============================================================
# Design-level attributes
# ============================================================

# Set design attribute
set_db [current_design] .max_fanout 16

# ============================================================
# Instance-level attributes
# ============================================================

# Mark cells
set_db [get_cells u_sram] .preserve true
set_db [get_cells u_analog] .boundary_opto false

# ============================================================
# Module-level attributes
# ============================================================

# Ungroup a module
set_db [get_designs sub_block] .ungroup true

# Set module effort
set_db [get_designs critical_path_block] .syn_opt_effort high

# ============================================================
# Net/Pin attributes
# ============================================================

# Ideal net
set_db [get_nets clk] .ideal true

# Net weight
set_db [get_nets critical_bus*] .weight 5
```

### get_db

Queries database values.

```tcl
# Get root attributes
get_db syn_generic_effort
get_db library

# Get design attributes
get_db [current_design] .area
get_db [current_design] .num_instances
get_db [current_design] .num_nets

# Get cell attributes
get_db [get_cells u_core] .ref_name
get_db [get_cells u_core] .area
get_db [get_cells -hierarchical *] .is_sequential

# Get port attributes
get_db [get_ports clk] .direction
get_db [get_ports data_out*] .fanout

# Get net attributes
get_db [get_nets *clk*] .num_connections

# Get library cell info
get_db [get_lib_cells */BUFX4] .area
get_db [get_lib_cells */AND2X1] .pins
get_db [get_lib_cells -regexp */DFF.*] .name

# Get timing info
get_db [get_timing_paths -max_paths 1] .slack
```

### set_attribute (Legacy)

Older syntax for setting attributes, still supported.

```tcl
# Legacy syntax (still works)
set_attribute -quiet lp_insert_clock_gating true /
set_attribute -quiet max_fanout 16 /designs/top_chip

# Equivalent modern set_db syntax (preferred)
set_db lp_insert_clock_gating true
set_db [current_design] .max_fanout 16
```

### set_dont_touch

Prevents the optimizer from modifying specific cells or nets.

```tcl
# Dont-touch on cells
set_dont_touch [get_cells u_custom_block]
set_dont_touch [get_cells u_sram*]

# Dont-touch on nets
set_dont_touch [get_nets critical_net]

# Dont-touch on a design (preserves hierarchy)
set_dont_touch [get_designs ip_block]

# Remove dont-touch
set_dont_touch [get_cells u_custom_block] false

# Using set_db equivalent
set_db [get_cells u_custom_block] .dont_touch true
set_db [get_cells u_custom_block] .dont_touch false

# Dont-touch on library cells (prevent usage)
set_dont_use [get_lib_cells */TIEH]
set_dont_use [get_lib_cells */TIEL]
set_dont_use [get_lib_cells */FILL*]

# Remove dont-use
set_dont_use [get_lib_cells */TIEH] false
```

### set_dont_use

Prevents specific library cells from being used in synthesis.

```tcl
# Prevent usage of specific cells
set_dont_use {slow_lib/BUF_X32 slow_lib/INV_X32}

# Prevent all filler cells from being used
set_dont_use [get_lib_cells */FILL*]

# Prevent weak drive cells
set_dont_use [get_lib_cells */BUFX1]
set_dont_use [get_lib_cells */INVX1]

# Allow a previously blocked cell
set_dont_use [get_lib_cells */BUFX1] false

# Using set_db
set_db [get_lib_cells */FILL*] .dont_use true
```

---

## Constraint Commands

### read_sdc

Reads Synopsys Design Constraints (SDC) files.

```tcl
# Read primary SDC
read_sdc /constraints/top_chip.sdc

# Read SDC for a specific mode
read_sdc -mode func /constraints/func_mode.sdc
read_sdc -mode test /constraints/test_mode.sdc

# Read SDC with echo
read_sdc -echo /constraints/top_chip.sdc
```

### create_clock

```tcl
# Basic clock
create_clock -name sys_clk -period 2.0 [get_ports clk]

# Clock with duty cycle
create_clock -name sys_clk -period 2.0 -waveform {0 0.8} [get_ports clk]

# Virtual clock (no port)
create_clock -name vclk -period 5.0

# Generated clock (divider)
create_generated_clock -name div2_clk -source [get_ports clk] \
    -divide_by 2 [get_pins clk_div/Q]

# Generated clock (multiplier)
create_generated_clock -name pll_clk -source [get_ports clk] \
    -multiply_by 4 [get_pins pll/clk_out]

# Generated clock (edges)
create_generated_clock -name mux_clk -source [get_ports clk] \
    -edges {1 3 5} [get_pins clk_mux/Y]
```

### set_input_delay / set_output_delay

```tcl
# Input delay
set_input_delay -clock sys_clk -max 0.5 [get_ports data_in*]
set_input_delay -clock sys_clk -min 0.1 [get_ports data_in*]

# Output delay
set_output_delay -clock sys_clk -max 0.8 [get_ports data_out*]
set_output_delay -clock sys_clk -min 0.2 [get_ports data_out*]

# Both rise and fall
set_input_delay -clock sys_clk -max -rise 0.5 [get_ports data_in*]
set_input_delay -clock sys_clk -max -fall 0.6 [get_ports data_in*]

# Clock-to-clock (source latency)
set_input_delay -clock src_clk -max 1.0 -source_latency_included [get_ports async_in]
```

### set_false_path / set_multicycle_path

```tcl
# False path between clock domains
set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]

# False path on specific pins
set_false_path -from [get_pins reg_a/Q] -to [get_pins reg_b/D]

# False path on ports
set_false_path -from [get_ports test_mode]

# Multicycle path
set_multicycle_path 2 -setup -from [get_clocks slow_clk] -to [get_clocks fast_clk]
set_multicycle_path 1 -hold -from [get_clocks slow_clk] -to [get_clocks fast_clk]

# Multicycle on specific registers
set_multicycle_path 3 -setup -from [get_cells slow_reg*] -to [get_cells fast_reg*]
set_multicycle_path 2 -hold -from [get_cells slow_reg*] -to [get_cells fast_reg*]
```

### set_clock_uncertainty

```tcl
# Simple uncertainty
set_clock_uncertainty -setup 0.1 [get_clocks sys_clk]
set_clock_uncertainty -hold 0.05 [get_clocks sys_clk]

# Inter-clock uncertainty
set_clock_uncertainty -setup 0.15 -from [get_clocks clk_a] -to [get_clocks clk_b]
```

### set_clock_latency / set_clock_transition

```tcl
# Source latency
set_clock_latency -source -max 1.5 [get_clocks sys_clk]
set_clock_latency -source -min 1.0 [get_clocks sys_clk]

# Network latency (pre-CTS estimate)
set_clock_latency -max 0.3 [get_clocks sys_clk]
set_clock_latency -min 0.1 [get_clocks sys_clk]

# Clock transition
set_clock_transition 0.08 [get_clocks sys_clk]
```

### set_load / set_driving_cell

```tcl
# Output load
set_load 0.05 [get_ports data_out*]
set_load -pin_load 0.03 [get_ports clk_out]

# Input driving cell
set_driving_cell -lib_cell BUFX4 -library tt_lib [get_ports data_in*]
set_driving_cell -lib_cell CLKBUF16 -library tt_lib -pin Y [get_ports clk]
```

### set_max_transition / set_max_capacitance / set_max_fanout

```tcl
# Design-level DRC constraints
set_max_transition 0.25 [current_design]
set_max_capacitance 0.3 [current_design]
set_max_fanout 20 [current_design]

# Port-specific
set_max_transition 0.15 [get_ports clk]
set_max_capacitance 0.1 [get_ports clk]

# Clock-specific (usually tighter)
set_max_transition 0.1 -clock_path [get_clocks sys_clk]
```

### group_path

```tcl
# Critical path grouping
group_path -name reg2reg -from [all_registers -clock_pins] -to [all_registers -data_pins]
group_path -name in2reg -from [all_inputs] -to [all_registers -data_pins]
group_path -name reg2out -from [all_registers -clock_pins] -to [all_outputs]
group_path -name in2out -from [all_inputs] -to [all_outputs]

# Named critical group with weight
group_path -name critical_bus -from [get_cells bus_ctrl/*] -to [get_cells fifo/*] -weight 2
```

---

## Physical-Aware Synthesis

### Setup for Physical-Aware Synthesis

```tcl
# Read physical data
read_physical -lef {tech.lef stdcells.lef sram.lef io.lef}
read_physical -def floorplan.def

# OR set through database
set_db lef_library {tech.lef stdcells.lef sram.lef io.lef}
set_db def_file floorplan.def

# Physical-aware database attributes
set_db root:/.physical_aware true
set_db root:/.physical_def_file /data/floorplan/top.def
set_db root:/.physical_lef_library {tech.lef stdcells.lef}

# QRC extraction for wire estimation
read_qrc /libs/tech/qrcTechFile

# Enable physical optimization
set_db interconnect_mode ple   ;# physical layout estimation

# Physical-aware synthesis flow
syn_generic -physical -effort high
syn_map -physical -effort high
syn_opt -physical -effort high
```

### Physical Attributes

```tcl
# Floorplan utilization
set_db root:/.physical_max_density 0.70

# Placement blockages (usually from DEF)
set_db root:/.physical_blockage_aware true

# Enable congestion-driven synthesis
set_db root:/.physical_congestion_effort high

# Allow Genus to do coarse placement
set_db root:/.physical_legalize_placement true

# Timing-driven placement
set_db root:/.physical_timing_driven true
```

---

## Incremental Synthesis

### Incremental Synthesis Flow

Incremental synthesis re-optimizes an existing netlist with modified constraints or RTL.

```tcl
# Method 1: Read an existing netlist and re-optimize
read_hdl -netlist output/top_chip_synth.v
read_lib ss_0p75v_125c.lib
elaborate top_chip
read_sdc output/top_chip.sdc

# Incremental optimization
syn_opt -incr

# Method 2: ECO synthesis (modify a small part of the design)
# After initial synthesis...
read_hdl -sv rtl/modified_block.sv  ;# Read modified RTL
elaborate top_chip
syn_generic -incr
syn_map -incr
syn_opt -incr

# Method 3: Netlist-in optimization
# Start from a gate-level netlist
read_hdl -netlist /gates/top.v
read_lib ss_0p75v_125c.lib
read_physical -lef {tech.lef stdcells.lef}
elaborate top_chip
read_sdc top.sdc

# Only run incremental opt
syn_opt -incr -effort high
```

### Remap / Retime

```tcl
# Sequential optimization (retiming)
set_db retime true
syn_opt -retime

# Remap to different library cells (e.g., after library swap)
syn_map -remap
```

---

## DFT Integration

### DFT Insertion in Genus

```tcl
# Enable DFT
set_db dft_scan_style muxed_scan

# Define scan configuration
set_db dft_prefix DFT_
set_db dft_scan_map_mode tdrc_pass

# Define test clocks
define_dft test_clock -name clk_scan -domain func_clk \
    -period 10.0 [get_ports clk]

# Define scan enable
define_dft test_mode -name scan_en -active high [get_ports scan_enable]

# Specify scan chains
define_dft scan_chain -name chain1 -sdi [get_ports scan_in1] \
    -sdo [get_ports scan_out1] -shift_enable [get_ports scan_enable]
define_dft scan_chain -name chain2 -sdi [get_ports scan_in2] \
    -sdo [get_ports scan_out2] -shift_enable [get_ports scan_enable]

# Check DFT rules before synthesis
check_dft_rules

# Run synthesis with DFT
syn_generic -dft
syn_map -dft
syn_opt -dft

# Insert scan chains
connect_dft

# Verify DFT
check_dft_rules
report_dft_chains

# Write DFT-specific outputs
write_dft_abstract_model > output/top_dft_abstract.v
write_scandef > output/top.scandef
```

### DFT Configuration Attributes

```tcl
# Scan chain configuration
set_db dft_max_chain_length 200
set_db dft_min_chain_length 190

# Scan ordering
set_db dft_scan_order auto ;# auto|timing|physical

# Lockup element insertion
set_db dft_lockup_element_type latch

# Non-scannable cell handling
set_db dft_non_scan_cell_handling clamp

# Compression (EDT-like)
set_db dft_compress true
set_db dft_compress_ratio 10

# BIST
set_db dft_mbist true
```

---

## Reporting Commands

### report_timing

Comprehensive timing analysis reporting.

```tcl
# Basic timing report (worst path)
report_timing

# Top N worst paths
report_timing -max_paths 50

# Report with full path detail
report_timing -max_paths 10 -path_type full_clock -nets -capacitance -transition

# Report specific path groups
report_timing -group reg2reg
report_timing -group in2reg

# Report by endpoint
report_timing -to [get_pins reg_bank/D] -max_paths 5

# Report by startpoint
report_timing -from [get_pins input_reg/Q] -max_paths 5

# Through-point timing
report_timing -through [get_pins mux/Y] -max_paths 10

# Hold timing
report_timing -late  ;# setup (default)
report_timing -early ;# hold

# Report for specific clock
report_timing -path_type full_clock -max_paths 20

# Slack-based filtering
report_timing -max_slack 0.0   ;# only failing paths
report_timing -min_slack -0.5  ;# paths with slack > -0.5
report_timing -max_slack 0.1   ;# paths with small positive slack

# Nworst per endpoint
report_timing -max_paths 100 -nworst 3

# Output to file
report_timing -max_paths 100 > reports/timing_setup.rpt
report_timing -early -max_paths 100 > reports/timing_hold.rpt

# Verbose timing path
report_timing -max_paths 1 -path_type full_clock \
    -nets -capacitance -transition -input_pins \
    -significant_digits 4

# Cost group summary
report_timing -summary
```

**Key report_timing options:**
| Option | Description |
|--------|-------------|
| `-max_paths <N>` | Maximum number of paths to report |
| `-nworst <N>` | Max paths per endpoint |
| `-path_type <type>` | `endpoint`, `full_clock`, `full` |
| `-late` / `-early` | Setup / hold analysis |
| `-from <obj>` | Path startpoint filter |
| `-to <obj>` | Path endpoint filter |
| `-through <obj>` | Through-point filter |
| `-group <name>` | Report specific path group |
| `-nets` | Show net names in path |
| `-capacitance` | Show capacitance values |
| `-transition` | Show transition times |
| `-input_pins` | Show input pin arrivals |
| `-significant_digits <N>` | Decimal precision |
| `-max_slack <val>` | Max slack filter |
| `-min_slack <val>` | Min slack filter |
| `-unconstrained` | Show unconstrained paths |
| `-summary` | Summary view by path group |

---

### report_area

Reports area breakdown.

```tcl
# Total area
report_area

# Hierarchical area
report_area -hierarchy

# By cell type
report_area -cell_type

# Detailed area
report_area -detail

# Output to file
report_area -hierarchy > reports/area.rpt
```

---

### report_power

Reports power analysis.

```tcl
# Basic power report
report_power

# Hierarchical power
report_power -hierarchy

# Detailed power (by cell)
report_power -detail

# Leakage only
report_power -leakage

# By power domain
report_power -power_domain

# With switching activity
set_db power_default_toggle_rate 0.1
set_db power_default_static_probability 0.5
report_power

# Read activity from simulation
read_vcd -vcd_scope top_tb/dut simulation.vcd
report_power

# Read SAIF file
read_saif -input top.saif -instance top_chip
report_power

# Output to file
report_power -hierarchy > reports/power.rpt
```

---

### report_qor

Reports overall Quality of Results.

```tcl
# QoR summary
report_qor

# Detailed QoR
report_qor -detail

# QoR for specific path group
report_qor -group reg2reg

# Levels of logic
report_qor -levels_of_logic

# Output
report_qor > reports/qor.rpt
```

---

### Additional Reports

```tcl
# Clock gating report
report_clock_gating

# Design statistics
report_summary

# Constraint violations
report_constraint -all_violators

# DRC violations
report_constraint -max_transition -all_violators
report_constraint -max_capacitance -all_violators
report_constraint -max_fanout -all_violators

# Hierarchy report
report_hierarchy

# Library usage
report_gates

# Datapath report
report_dp

# Sequential cells
report_sequential

# Clock report
report_clocks

# Port report
report_ports

# Ungrouped modules
report_ungroup

# Message summary
report_messages
```

---

## Output and Export Commands

### write_hdl

Writes out the synthesized gate-level netlist.

```tcl
# Write Verilog netlist
write_hdl > output/top_chip.v

# Write specific design
write_hdl top_chip > output/top_chip.v

# Write with specific options
write_hdl -pg  ;# include power/ground pins

# Write mapped netlist (post-syn_map, pre-syn_opt)
write_hdl > output/top_chip_mapped.v

# Write with naming rules applied
set_db write_hdl_names_no_special_characters true
write_hdl > output/top_chip.v
```

### write_sdc

Writes Synopsys Design Constraints.

```tcl
# Write SDC
write_sdc > output/top_chip.sdc

# Write SDC for specific mode
write_sdc -mode func > output/func_mode.sdc

# Write with all constraints
write_sdc -nosplit > output/top_chip_full.sdc
```

### write_sdf

Writes Standard Delay Format for gate-level simulation.

```tcl
# Write SDF
write_sdf > output/top_chip.sdf

# Write for specific corner
write_sdf -max_view wc_view > output/top_chip_max.sdf
write_sdf -min_view bc_view > output/top_chip_min.sdf

# Write with recalculated delays
write_sdf -recalculate > output/top_chip.sdf

# Write with timescale
write_sdf -timescale ns > output/top_chip.sdf
```

### write_design

Writes a complete design database (preferred for Innovus handoff).

```tcl
# Write design for Innovus (GII flow)
write_design -innovus -base_name output/top_chip

# This generates:
#   output/top_chip.v          (netlist)
#   output/top_chip.sdc        (constraints)
#   output/top_chip.invs_setup.tcl (Innovus setup script)

# Write design database (Genus binary)
write_db output/top_chip_genus.db

# Write OA database
write_design -oa -lib_name top_lib -cell_name top_chip -view_name synth

# Write for specific tool
write_design -encounter -base_name output/top_chip ;# legacy Encounter format
```

### write_db / read_db

Save and restore Genus sessions.

```tcl
# Save database
write_db output/genus_db -all_root_attributes

# Restore database
read_db output/genus_db
```

### Additional Export Commands

```tcl
# Write DEF (physical-aware synthesis)
write_def > output/top_chip.def

# Write SPEF (wire parasitics from PLE)
write_spef > output/top_chip.spef

# Write script to reproduce the session
write_script > output/reproduce.tcl

# Write do file (Genus session log as replayable script)
write_do_lec > output/lec_dofile.tcl

# Write Conformal LEC setup
write_do_lec -revised_design output/top_chip.v \
    -logfile output/lec.log > output/run_lec.do

# Write snapshot for comparison
write_snapshot -outdir output/snapshot -tag post_synth
```

---

## GII (Genus-Innovus Integration)

GII enables tight integration between Genus synthesis and Innovus implementation.

### GII Setup

```tcl
# Enable GII mode
set_db design_process_node 7  ;# or 5, 3 for advanced nodes

# Setup for GII
set_db innovus_executable /tools/cadence/innovus/bin/innovus

# Physical-aware synthesis with GII
read_physical -lef {tech.lef stdcells.lef macro.lef}
read_physical -def floorplan.def
read_qrc qrcTechFile

# Run synthesis with physical awareness
syn_generic -physical
syn_map -physical
syn_opt -physical

# Write design for Innovus
write_design -innovus -base_name output/top_chip

# Write GII interface files
write_design -innovus -gii -base_name output/top_chip_gii
```

### GII Database Sharing

```tcl
# In Genus: write GII database
write_db -innovus output/genus_innovus.db

# In Innovus: read GII database
# (Run in Innovus)
# read_db output/genus_innovus.db
```

### GII Flow Commands

```tcl
# Genus side: trigger Innovus placement
genus_innovus_place

# Genus side: read back Innovus placement
genus_innovus_read_placement

# Genus side: iterate with Innovus
genus_innovus_iterate -max_iter 3

# Check correlation with Innovus
genus_innovus_check_correlation
```

---

## Power Optimization Commands

### Clock Gating

```tcl
# Enable clock gating insertion
set_db lp_insert_clock_gating true

# Clock gating parameters
set_db lp_clock_gating_min_flops 4    ;# min FFs to gate
set_db lp_clock_gating_max_flops 64   ;# max FFs per gating group
set_db lp_clock_gating_cell [get_lib_cells */CKLNQD1]  ;# specific gating cell

# Integrated clock gating (ICG) cells
set_db lp_clock_gating_cell_aware true

# Clock gating with test
set_db lp_clock_gating_test true
set_db lp_clock_gating_test_signal [get_ports scan_enable]

# Report clock gating
report_clock_gating
report_clock_gating -detail
report_clock_gating -summary
```

### Multi-Vt Optimization

```tcl
# Multi-Vt setup
set_db leakage_power_effort high

# Specify Vt swap rules
set_db use_multibit_cells true

# Target Vt mix
set_db lp_multi_vt_optimization true

# Vt group definitions (done via library naming convention)
# Libraries typically named: hvt_*, svt_*, lvt_*, ulvt_*

# Report Vt distribution
report_gates -by_threshold_voltage
```

### Power Domains (UPF/CPF)

```tcl
# Read power intent
read_power_intent -cpf power_spec.cpf
read_power_intent -1801 power_spec.upf

# Apply power intent
commit_power_intent

# Check power intent
check_power_intent

# Report power domains
report_power_domain
```

---

## Multi-Mode Multi-Corner (MMMC)

### MMMC Setup

```tcl
# Define library sets
create_library_set -name ls_wc -timing {ss_0p75v_125c.lib sram_ss.lib}
create_library_set -name ls_bc -timing {ff_0p95v_m40c.lib sram_ff.lib}
create_library_set -name ls_tc -timing {tt_0p85v_25c.lib sram_tt.lib}

# Define RC corners
create_rc_corner -name rc_wc -qrc_tech qrcTechFile -T 125
create_rc_corner -name rc_bc -qrc_tech qrcTechFile -T -40
create_rc_corner -name rc_tc -qrc_tech qrcTechFile -T 25

# Define delay corners
create_delay_corner -name dc_wc -library_set ls_wc -rc_corner rc_wc
create_delay_corner -name dc_bc -library_set ls_bc -rc_corner rc_bc
create_delay_corner -name dc_tc -library_set ls_tc -rc_corner rc_tc

# Define constraint modes
create_constraint_mode -name cm_func -sdc_files {func.sdc}
create_constraint_mode -name cm_test -sdc_files {test.sdc}

# Define analysis views
create_analysis_view -name av_wc_func -constraint_mode cm_func -delay_corner dc_wc
create_analysis_view -name av_bc_func -constraint_mode cm_func -delay_corner dc_bc
create_analysis_view -name av_wc_test -constraint_mode cm_test -delay_corner dc_wc

# Set active views
set_analysis_view -setup {av_wc_func av_wc_test} -hold {av_bc_func}

# Report views
report_analysis_view
```

---

## Datapath Optimization

```tcl
# Enable datapath optimization
set_db dp_area_mode true
set_db dp_postmap_upsize true

# Datapath architecture selection
set_db dp_max_fanout 8

# Carry-select / carry-lookahead selection
set_db dp_csa_adder auto ;# auto|ripple|cla|csa|bk|ks

# Report datapath
report_dp
report_dp -all
report_dp -instances

# Booth encoding for multipliers
set_db dp_booth true

# Retiming across datapath
set_db dp_retime true
```

---

## Debug and Utility Commands

### Session Management

```tcl
# Save session
write_db /path/to/genus_session

# Restore session
read_db /path/to/genus_session

# Set log file
set_db log_file genus_run.log

# Set script file (echo all commands)
set_db command_log_file genus_commands.tcl
```

### Object Queries

```tcl
# Get design objects
get_cells -hierarchical *
get_cells -hierarchical -filter "is_sequential==true"
get_cells -hierarchical -filter "ref_name=~DFF*"

get_nets -hierarchical *clk*
get_nets -hierarchical -filter "num_connections > 100"

get_ports *
get_ports -filter "direction==in"
get_ports -filter "direction==out"

get_pins -hierarchical */D
get_pins -hierarchical */Q

get_clocks *
get_clocks -filter "period < 5.0"

# Counting
llength [get_cells -hierarchical *]
llength [get_cells -hierarchical -filter "is_sequential==true"]

# Find high-fanout nets
get_nets -hierarchical -filter "fanout > 50"
```

### Timing Debug

```tcl
# Detailed path analysis
report_timing -path_type full_clock -nets -capacitance -transition \
    -input_pins -max_paths 1

# Check for unconstrained paths
report_timing -unconstrained

# Check for loops
check_timing_intent -verbose

# Path through specific cell
report_timing -through [get_cells problematic_mux]

# Analyze clock relationship
report_clocks -relationships

# Check for latches
report_sequential -latch
```

### Error and Warning Management

```tcl
# Suppress specific messages
suppress_message {SYNTH-1234 ELAB-5678}

# Unsuppress
unsuppress_message SYNTH-1234

# Set message severity
set_message -id SYNTH-9999 -severity warning

# Get message log
report_messages
report_messages -error
report_messages -warning
```

### TCL Utilities in Genus

```tcl
# Time a command
time {syn_opt -effort high}

# Get runtime stats
report_runtime

# Memory usage
report_memory

# Set number of CPUs
set_db max_cpus_per_server 8
set_db super_thread_servers {host1 host2 host3}

# Distributed synthesis
set_db super_thread_servers "localhost localhost localhost localhost"

# GUI
gui_show   ;# launch GUI
gui_hide   ;# hide GUI
```

---

## Quick Reference: Complete Synthesis Script Template

```tcl
#============================================================
# Genus Synthesis Script -- Production Template
#============================================================

# Setup
set_db information_level 7
set_db max_cpus_per_server 8

# Paths
set_db init_lib_search_path {/libs/stdcells /libs/macros /libs/io}
set_db init_hdl_search_path {/rtl /rtl/include}

# Libraries
read_lib {ss_0p75v_125c.lib sram_ss.lib io_ss.lib}
read_physical -lef {tech.lef stdcells.lef sram.lef io.lef}
read_qrc /libs/tech/qrcTechFile

# RTL
read_hdl -sv -f scripts/filelist.f

# Elaborate
elaborate top_chip
check_design -all

# Constraints
read_sdc constraints/top_chip.sdc

# Optimization settings
set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high
set_db leakage_power_effort high
set_db lp_insert_clock_gating true
set_db lp_clock_gating_min_flops 4
set_db max_fanout 20
set_db boundary_opto true
set_db retime true

# Dont-use
set_dont_use [get_lib_cells */FILL*]

# Synthesize (physical-aware)
syn_generic -physical
syn_map -physical
syn_opt -physical

# Reports
report_qor > reports/qor.rpt
report_timing -max_paths 100 > reports/timing_setup.rpt
report_timing -early -max_paths 100 > reports/timing_hold.rpt
report_area -hierarchy > reports/area.rpt
report_power -hierarchy > reports/power.rpt
report_clock_gating > reports/clock_gating.rpt
report_constraint -all_violators > reports/violations.rpt
report_gates > reports/gates.rpt
report_dp > reports/datapath.rpt

# Output
write_hdl > output/top_chip.v
write_sdc > output/top_chip.sdc
write_sdf > output/top_chip.sdf
write_design -innovus -base_name output/top_chip
write_db output/genus_final_db

# LEC dofile
write_do_lec -revised_design output/top_chip.v > output/lec.do

puts "Synthesis complete."
```

---

## Genus Command Index (Alphabetical)

| Command | Category | Description |
|---------|----------|-------------|
| `check_design` | Validation | Validate design integrity |
| `check_dft_rules` | DFT | Check DFT rule compliance |
| `check_timing_intent` | Constraints | Validate timing constraints |
| `connect_dft` | DFT | Insert scan chains |
| `create_analysis_view` | MMMC | Define analysis view |
| `create_clock` | Constraints | Define clock |
| `create_constraint_mode` | MMMC | Define constraint mode |
| `create_delay_corner` | MMMC | Define delay corner |
| `create_generated_clock` | Constraints | Define derived clock |
| `create_library_set` | MMMC | Define library set |
| `create_rc_corner` | MMMC | Define RC extraction corner |
| `define_dft` | DFT | Define DFT structures |
| `elaborate` | Setup | Elaborate RTL design |
| `get_cells` | Query | Query cell objects |
| `get_clocks` | Query | Query clock objects |
| `get_db` | Database | Query database attributes |
| `get_lib_cells` | Query | Query library cells |
| `get_nets` | Query | Query net objects |
| `get_pins` | Query | Query pin objects |
| `get_ports` | Query | Query port objects |
| `group_path` | Constraints | Create timing path group |
| `read_db` | I/O | Restore session database |
| `read_hdl` | I/O | Read RTL source files |
| `read_lib` | I/O | Read Liberty libraries |
| `read_physical` | I/O | Read LEF/DEF |
| `read_power_intent` | Power | Read UPF/CPF |
| `read_qrc` | I/O | Read QRC techfile |
| `read_sdc` | Constraints | Read SDC constraints |
| `report_area` | Report | Report area breakdown |
| `report_clock_gating` | Report | Report clock gating statistics |
| `report_clocks` | Report | Report clock definitions |
| `report_constraint` | Report | Report constraint violations |
| `report_dp` | Report | Report datapath structures |
| `report_gates` | Report | Report gate usage |
| `report_hierarchy` | Report | Report design hierarchy |
| `report_memory` | Utility | Report memory usage |
| `report_messages` | Utility | Report message summary |
| `report_ports` | Report | Report port info |
| `report_power` | Report | Report power estimates |
| `report_qor` | Report | Report quality of results |
| `report_runtime` | Utility | Report CPU/elapsed time |
| `report_sequential` | Report | Report sequential cells |
| `report_summary` | Report | Report design statistics |
| `report_timing` | Report | Report timing paths |
| `set_analysis_view` | MMMC | Set active analysis views |
| `set_clock_latency` | Constraints | Set clock latency |
| `set_clock_transition` | Constraints | Set clock transition |
| `set_clock_uncertainty` | Constraints | Set clock uncertainty |
| `set_db` | Database | Set database attributes |
| `set_dont_touch` | Optimization | Prevent optimization |
| `set_dont_use` | Optimization | Prevent cell usage |
| `set_driving_cell` | Constraints | Set input driver |
| `set_false_path` | Constraints | Define false path |
| `set_input_delay` | Constraints | Set input arrival time |
| `set_load` | Constraints | Set output load |
| `set_max_capacitance` | Constraints | Set max cap limit |
| `set_max_fanout` | Constraints | Set max fanout limit |
| `set_max_transition` | Constraints | Set max slew limit |
| `set_multicycle_path` | Constraints | Define multicycle path |
| `set_output_delay` | Constraints | Set output required time |
| `syn_generic` | Synthesis | Technology-independent synthesis |
| `syn_map` | Synthesis | Technology mapping |
| `syn_opt` | Synthesis | Post-map optimization |
| `uniquify` | Setup | Make instances unique |
| `write_db` | I/O | Save session database |
| `write_def` | I/O | Write DEF |
| `write_design` | I/O | Write full design bundle |
| `write_do_lec` | I/O | Write LEC dofile |
| `write_hdl` | I/O | Write gate-level netlist |
| `write_sdc` | I/O | Write SDC constraints |
| `write_sdf` | I/O | Write SDF delays |
| `write_snapshot` | I/O | Write QoR snapshot |
| `write_spef` | I/O | Write parasitics |
