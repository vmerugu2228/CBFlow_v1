# Synopsys Fusion Compiler Command Reference

Comprehensive command reference for Synopsys Fusion Compiler (FC), the unified
synthesis-through-signoff platform. Covers FC shell (fcsh) commands for library
management, reading/writing design data, synthesis, floorplanning, placement,
CTS, routing, optimization, analysis, and app-option configuration.

FC version baseline: 2023.12-SP3 and later (T-2022.03+ syntax compatible).

---

## Table of Contents

1. [Library and Block Management](#1-library-and-block-management)
2. [Reading Design Data](#2-reading-design-data)
3. [Writing / Exporting Design Data](#3-writing--exporting-design-data)
4. [Synthesis Commands](#4-synthesis-commands)
5. [Floorplanning](#5-floorplanning)
6. [Placement](#6-placement)
7. [Clock Tree Synthesis (CTS)](#7-clock-tree-synthesis-cts)
8. [Routing](#8-routing)
9. [Optimization and ECO](#9-optimization-and-eco)
10. [Timing Analysis and Reporting](#10-timing-analysis-and-reporting)
11. [Power Analysis and Reporting](#11-power-analysis-and-reporting)
12. [Physical Verification In-Design](#12-physical-verification-in-design)
13. [App Options Reference](#13-app-options-reference)
14. [Useful Utility Commands](#14-useful-utility-commands)

---

## 1. Library and Block Management

FC uses the **NDM (New Data Model)** library framework. Designs live as
"blocks" inside "libraries." All persistent data is stored in the NDM database.

### create_lib

Create a new NDM library.

```
create_lib <library_name>
  -technology <tech_file | NDM_ref_lib>
  [-ref_libs <list_of_ref_libs>]
  [-use_technology_lib <NDM_lib>]
```

**Options**

| Option | Description |
|---|---|
| `-technology` | Path to the `.tf` technology file or a reference NDM lib that carries the tech |
| `-ref_libs` | Ordered list of NDM reference libraries (standard cells, macros, IOs, etc.) |
| `-use_technology_lib` | Use the technology definition from an existing NDM library instead of a `.tf` file |

**Examples**

```tcl
# Create lib using .tf file and multiple reference libraries
create_lib my_design_lib \
  -technology /pdk/tech/saed14nm.tf \
  -ref_libs [list \
    /libs/ndm/saed14_hvt.ndm \
    /libs/ndm/saed14_rvt.ndm \
    /libs/ndm/saed14_lvt.ndm \
    /libs/ndm/sram_macros.ndm \
    /libs/ndm/io_cells.ndm \
  ]

# Create lib borrowing technology from an existing reference lib
create_lib chip_lib \
  -use_technology_lib /libs/ndm/saed14_hvt.ndm \
  -ref_libs {/libs/ndm/saed14_hvt.ndm /libs/ndm/saed14_rvt.ndm}
```

### open_lib

Open an existing NDM library.

```
open_lib <library_path>
  [-read]
  [-write]
```

**Examples**

```tcl
open_lib my_design_lib
open_lib /project/work/chip_lib -write
```

### save_lib

Save the current library to disk.

```
save_lib
  [-as <new_library_path>]
  [-all]
```

**Examples**

```tcl
save_lib
save_lib -as /project/checkpoint/chip_lib_placed
```

### create_block

Create a new design block inside the current library.

```
create_block <block_name>
  [-lib <library>]
```

**Examples**

```tcl
create_block my_top
create_block cpu_core -lib chip_lib
```

### open_block

Open an existing block for editing.

```
open_block <library>:<block_name>[/<label>]
  [-read | -write]
```

**Examples**

```tcl
open_block chip_lib:my_top
open_block chip_lib:my_top/placed -read
```

### save_block

Save the current block (optionally with a label).

```
save_block
  [-as <library>:<block_name>[/<label>]]
  [-force]
  [-compress]
```

**Examples**

```tcl
save_block
save_block -as chip_lib:my_top/post_cts
save_block -as chip_lib:my_top/post_route -force
```

### copy_block

Copy a block within or between libraries.

```
copy_block
  -from_block <library>:<block_name>[/<label>]
  -to_block <library>:<block_name>[/<label>]
  [-force]
```

**Examples**

```tcl
copy_block -from_block chip_lib:my_top/post_place \
           -to_block   chip_lib:my_top/post_place_backup

copy_block -from_block old_lib:cpu_core \
           -to_block   new_lib:cpu_core -force
```

### remove_block / remove_lib

```tcl
remove_block <library>:<block_name>[/<label>]
remove_lib <library_path>
```

### link_block

Link the current block — resolves references to cells in the ref_libs.

```
link_block
  [-force]
```

This is the FC equivalent of `link_design`. It must be called after reading a
netlist into a block.

```tcl
link_block -force
```

---

## 2. Reading Design Data

### read_verilog

Read gate-level or RTL Verilog into the current block.

```
read_verilog <file_list>
  [-design <design_name>]
  [-top <top_module>]
  [-library <lib_name>]
  [-define <macro_list>]
  [-include <dir_list>]
  [-allow_black_box]
```

**Examples**

```tcl
read_verilog {./netlist/top.v ./netlist/sub_a.v ./netlist/sub_b.v}
read_verilog -top chip_top ./netlist/chip_top.v
read_verilog -allow_black_box ./netlist/incomplete_design.v
```

### read_vhdl

```
read_vhdl <file_list>
  [-design <design_name>]
  [-top <entity_name>]
  [-library <lib_name>]
  [-93 | -2008]
```

### read_ddc

Read a Synopsys DDC (compiled design) database.

```
read_ddc <file>
```

### read_def

Read a DEF file (floorplan, placement, routing).

```
read_def <file>
  [-add_def_only_objects {nets cells vias rows}]
  [-no_incremental]
```

**Examples**

```tcl
# Read floorplan DEF
read_def ./def/chip_top.floorplan.def

# Read incremental DEF for IO placement only
read_def ./def/io_placement.def -add_def_only_objects {cells}
```

### read_sdc

Read timing constraints.

```
read_sdc <file>
  [-echo]
  [-version <sdc_version>]
```

**Examples**

```tcl
read_sdc ./constraints/func_mode.sdc
read_sdc ./constraints/scan_mode.sdc -echo
```

### read_upf

Read Unified Power Format for multi-voltage / low-power design.

```
read_upf <file>
  [-scope <instance_path>]
  [-version {1.0 | 2.0 | 2.1 | 3.0}]
```

**Examples**

```tcl
read_upf ./upf/top.upf
read_upf ./upf/cpu_core.upf -scope cpu_core_inst
```

### read_parasitic

Read parasitic data (SPEF/SBPF).

```
read_parasitics <file>
  [-format {spef | sbpf}]
  [-path <instance_path>]
  [-corner <corner_name>]
```

**Examples**

```tcl
read_parasitics ./spef/top_ss_125c.spef -corner ss_125c
read_parasitics ./spef/cpu_core.spef -path cpu_core_inst
```

### read_saif

Read switching activity for power analysis.

```
read_saif <file>
  [-strip_path <path>]
  [-target_instance <instance>]
```

```tcl
read_saif ./saif/top.saif -strip_path testbench/dut
```

### read_fsdb

Read FSDB waveform for power analysis.

```
read_fsdb <file>
  [-strip_path <path>]
  [-scope <scope>]
```

### Additional Read Commands

```tcl
# Read Milkyway library (legacy)
read_mw_lib <mw_lib_path>

# Read LEF (rarely needed — NDM preferred)
read_lef <file>

# Read technology LEF
read_tech_lef <file>

# Read abstract (for reference cells)
read_abstract <file>

# Read scan chain definitions
read_scan_def <file>

# Read floorplan from a file
read_floorplan <file>
```

---

## 3. Writing / Exporting Design Data

### write_verilog

Write a gate-level Verilog netlist.

```
write_verilog <file>
  [-hierarchy {all | <instance_list>}]
  [-exclude {pg_objects | empty_modules | unconnected_ports | supply_nets}]
  [-no_unconnected_cells]
  [-force_output_references]
  [-split_bus]
  [-pg]
  [-supply_statement {none | file}]
```

**Examples**

```tcl
# Standard gate-level netlist for simulation
write_verilog ./output/top_post_route.v \
  -exclude {pg_objects empty_modules}

# PG-aware netlist for power verification
write_verilog ./output/top_pg.v -pg

# Netlist with split buses for LVS
write_verilog ./output/top_lvs.v -split_bus -force_output_references
```

### write_def

Write a DEF file.

```
write_def <file>
  [-include {cells nets special_nets vias rows tracks blockages pins regions}]
  [-exclude {filler_cells decaps endcaps tap_cells}]
  [-compress {gzip}]
  [-version <def_version>]
  [-floorplan]
```

**Examples**

```tcl
write_def ./output/top_post_route.def
write_def ./output/top_floorplan.def -floorplan
write_def ./output/top.def.gz -compress gzip
```

### write_gds

Write GDSII layout.

```
write_gds <file>
  [-lib_cell_view_name <cell_name>]
  [-design <design_name>]
  [-long_names]
  [-merge_gds_files <list>]
  [-fill_via_mapping_file <file>]
  [-output_pin_name_as_label]
  [-keep_data_type]
  [-no_stamp]
  [-compress]
  [-max_points_per_polygon <N>]
  [-unit <uu_per_dbu>]
  [-map_layer <map_file>]
```

**Examples**

```tcl
# Basic GDSII export
write_gds ./output/top.gds

# Merge with macro GDSII files
write_gds ./output/top_merged.gds \
  -merge_gds_files [list /libs/gds/sram.gds /libs/gds/pll.gds] \
  -long_names \
  -map_layer ./tech/gds_map.map

# Compressed output
write_gds ./output/top.gds.gz -compress
```

### write_sdc

Write SDC constraints.

```
write_sdc <file>
  [-nosplit]
  [-version <version>]
  [-scenario <scenario>]
```

```tcl
write_sdc ./output/top_post_route.sdc -nosplit
```

### write_parasitics

Write parasitic data (SPEF).

```
write_parasitics <file>
  [-format {spef | sbpf | dspf}]
  [-compress]
  [-output {lumped | detailed}]
  [-corner <corner_name>]
```

```tcl
write_parasitics ./output/top_ss.spef -format spef -corner ss_125c
write_parasitics ./output/top_ss.spef.gz -format spef -compress
```

### write_script

Write a reproducible TCL script of the current session.

```
write_script <file>
  [-format {tcl | dctcl}]
  [-no_split]
  [-include_app_options]
  [-compress]
```

```tcl
write_script ./output/reproduce_session.tcl -include_app_options
```

### write_floorplan

Write the current floorplan.

```
write_floorplan <file>
  [-include {all | placement_blockages routing_blockages bounds io_constraints}]
  [-force]
  [-row]
  [-net_pin_constraints]
```

```tcl
write_floorplan ./output/floorplan.tcl
write_floorplan ./output/floorplan.tcl -include all -net_pin_constraints
```

### Additional Write Commands

```tcl
# Write UPF
write_upf <file>

# Write scan DEF
write_scan_def <file>

# Write OASIS layout
write_oasis <file>

# Write abstract for a cell
write_abstract <file>

# Write LEF
write_lef <file>

# Write power intent
write_power_intent <file>
```

---

## 4. Synthesis Commands

### compile_fusion

The unified synthesis + physical optimization command in FC. This is the
flagship command that differentiates FC from DC.

```
compile_fusion
  [-from <stage>]
  [-to <stage>]
  [-auto_dp]
  [-effort {low | medium | high}]
  [-gate_clock]
  [-retime]
  [-spg]
  [-ungroup_effort {low | medium | high}]
  [-power]
  [-congestion]
  [-area]
  [-timing]
  [-no_datapath]
  [-no_seq_output_inversion]
  [-no_autoungroup]
  [-no_boundary_optimization]
  [-no_design_rule_fix]
  [-exact_map]
  [-scan]
  [-incremental]
```

**Key Options Explained**

| Option | Description |
|---|---|
| `-from` / `-to` | Run a sub-range of the compile stages: `generic`, `map`, `opt` |
| `-auto_dp` | Enable automatic datapath optimization |
| `-effort` | Optimization effort level |
| `-gate_clock` | Insert clock gating during synthesis |
| `-retime` | Enable register retiming for better timing |
| `-spg` | Enable SPG (Synopsys Physical Guidance) for layout-aware synthesis |
| `-power` | Enable power-driven optimization |
| `-congestion` | Enable congestion-driven optimization |
| `-area` | Prioritize area reduction |
| `-timing` | Prioritize timing closure |
| `-scan` | Compile for DFT scan insertion |
| `-incremental` | Incremental synthesis on an already-compiled design |

**Examples**

```tcl
# Full compile_fusion with typical options
compile_fusion \
  -gate_clock \
  -retime \
  -spg \
  -effort high \
  -congestion \
  -power

# Incremental compile after ECO changes
compile_fusion -incremental

# Stages-based compile
compile_fusion -from generic -to map
compile_fusion -from opt -to opt

# Area-focused compile with datapath optimization
compile_fusion -auto_dp -area -effort high -power
```

### compile_ultra

Legacy DC-compatible compile command available in FC.

```
compile_ultra
  [-incremental]
  [-gate_clock]
  [-retime]
  [-no_autoungroup]
  [-no_boundary_optimization]
  [-no_seq_output_inversion]
  [-area_high_effort_script]
  [-timing_high_effort_script]
  [-scan]
  [-exact_map]
  [-no_design_rule]
```

**Examples**

```tcl
compile_ultra -gate_clock -retime -scan
compile_ultra -incremental -no_autoungroup
```

### set_dont_touch

Prevent optimization of specific cells or nets.

```
set_dont_touch <object_list>
  [-true | -false]
```

**Examples**

```tcl
set_dont_touch [get_cells u_analog_wrapper/*]
set_dont_touch [get_nets clk_tree_root]
set_dont_touch [get_designs sub_block] true

# Remove dont_touch
set_dont_touch [get_cells u_fixed_block/*] -false
```

### set_size_only

Mark cells as size-only (can be resized but not restructured).

```
set_size_only <cell_list>
  [-all_instances]
```

```tcl
set_size_only [get_cells -hier -filter "ref_name =~ BUF*"]
set_size_only [get_lib_cells */CLKBUF*] -all_instances
```

### Other Synthesis Commands

```tcl
# Uniquify design hierarchy
uniquify

# Ungroup hierarchy
ungroup <cells> [-flatten]
ungroup -all -flatten

# Change hierarchy
group <object_list> -design_name <name> -cell_name <name>

# Set structure
set_structure true|false

# Set flatten
set_flatten true|false -effort {low|medium|high}

# Register retiming standalone
optimize_registers

# Set optimization directives
set_cost_priority {-delay | -area}
```

---

## 5. Floorplanning

### initialize_floorplan

Create the initial floorplan.

```
initialize_floorplan
  [-die_area {{llx lly} {urx ury}}]
  [-core_area {{llx lly} {urx ury}}]
  [-core_offset {left bottom right top}]
  [-core_utilization <float>]
  [-core_aspect_ratio <float>]
  [-flip_first_row]
  [-rows_per_stripe <N>]
  [-row_height <height>]
  [-side_length <value>]
  [-shape {R | L | T | U | cross | custom}]
  [-shape_coordinates {{x1 y1} {x2 y2} ...}]
```

**Examples**

```tcl
# Simple utilization-driven floorplan
initialize_floorplan \
  -core_utilization 0.70 \
  -core_aspect_ratio 1.0 \
  -core_offset {5 5 5 5} \
  -flip_first_row

# Explicit die/core coordinates
initialize_floorplan \
  -die_area  {{0 0} {1200 1000}} \
  -core_area {{10 10} {1190 990}}

# Rectilinear floorplan (L-shape)
initialize_floorplan \
  -shape L \
  -shape_coordinates {{0 0} {600 0} {600 500} {300 500} {300 1000} {0 1000}}
```

### create_placement_blockage

Define regions where standard cells cannot be placed.

```
create_placement_blockage
  -boundary {{llx lly} {urx ury}}
  [-type {hard | soft | partial}]
  [-blocked_percentage <float>]
  [-name <name>]
```

**Examples**

```tcl
# Hard blockage under an analog macro
create_placement_blockage \
  -boundary {{100 200} {300 400}} \
  -type hard \
  -name blk_under_pll

# Soft blockage for congestion avoidance (50% density)
create_placement_blockage \
  -boundary {{400 100} {600 300}} \
  -type partial \
  -blocked_percentage 50 \
  -name blk_congestion_area
```

### create_bound

Create a placement bound (guide, region, or fence).

```
create_bound <bound_name>
  -boundary {{llx lly} {urx ury}}
  -type {guide | region | fence}
  [-exclusive]
  -objects <cell_list>
```

**Examples**

```tcl
# Region bound — cells should be inside but it is not strict
create_bound cpu_bound \
  -boundary {{100 100} {500 500}} \
  -type region \
  -objects [get_cells cpu_inst/*]

# Fence — cells must be inside this area (hard constraint)
create_bound mem_fence \
  -boundary {{600 100} {900 400}} \
  -type fence \
  -exclusive \
  -objects [get_cells mem_ctrl_inst/*]
```

### Macro Placement

```tcl
# Set macro placement
set_cell_location -coordinates {100 200} -fixed [get_cells sram_inst]

# Create keepout margin around macros
create_keepout_margin \
  -outer {5 5 5 5} \
  [get_cells -filter "is_hard_macro==true"]

# Set macro orientation
set_attribute [get_cells sram_inst] orientation R0

# Create rectilinear placement blockage
create_placement_blockage \
  -type hard \
  -boundary {{100 100} {200 200} {200 300} {300 300} {300 100}}
```

### Pin Placement

```tcl
# Set IO pin constraints
set_block_pin_constraints \
  -sides {1 2 3 4} \
  -allowed_layers {M4 M5 M6}

# Constrain specific pins to a side
set_individual_pin_constraints \
  -pins [get_ports clk*] \
  -sides 1 \
  -allowed_layers M5

# Place pins
place_pins -self

# Set pin grid
set_block_pin_constraints -pin_spacing 1.0

# Write pin constraints
write_pin_constraints ./output/pin_constraints.tcl
```

### Power Planning / PG Grid

```tcl
# Create PG region
create_pg_region pg_top -polygon {{0 0} {1000 0} {1000 800} {0 800}}

# Create PG patterns
create_pg_std_cell_conn_pattern std_cell_rail \
  -layers {M1} \
  -rail_width 0.1

create_pg_mesh_pattern mesh_m3m4 \
  -layers {
    {M3 -direction vertical   -width 2.0 -spacing interleaving -pitch 40 -offset 10}
    {M4 -direction horizontal -width 2.0 -spacing interleaving -pitch 40 -offset 10}
  }

create_pg_ring_pattern ring_pattern \
  -horizontal_layer M5 \
  -vertical_layer M6 \
  -horizontal_width 4.0 \
  -vertical_width 4.0 \
  -horizontal_spacing 2.0 \
  -vertical_spacing 2.0

# Create PG strap pattern
create_pg_strap_pattern strap_m5m6 \
  -layers {
    {M5 -direction horizontal -width 3.0 -spacing minimum -pitch 80}
    {M6 -direction vertical   -width 3.0 -spacing minimum -pitch 80}
  }

# Set PG strategies
set_pg_strategy core_mesh \
  -pattern mesh_m3m4 \
  -core

set_pg_strategy core_ring \
  -pattern ring_pattern \
  -core \
  -extension {{stop:outermost_ring}}

set_pg_strategy std_conn \
  -pattern std_cell_rail \
  -core

# Compile PG
compile_pg

# Create PG vias
set_pg_via_master_rule via_rule \
  -contact_code {VIA34 VIA45 VIA56}

create_pg_vias \
  -within_bbox {{0 0} {1000 800}}
```

### Voltage Area

```tcl
# Create voltage area (for multi-voltage designs from UPF)
create_voltage_area \
  -power_domain PD_cpu \
  -coordinate {{100 100} {500 500}} \
  -guard_band_x 5 \
  -guard_band_y 5
```

### set_attribute (Floorplan-Related)

```tcl
# Set core utilization target
set_attribute [current_block] core_utilization 0.70

# Set row orientation
set_attribute [get_rows *] orientation FS

# Set cell fixed status
set_attribute [get_cells macro_inst] is_fixed true

# Set cell placement status
set_attribute [get_cells macro_inst] status fixed
```

---

## 6. Placement

### place_opt

The main placement and placement-optimization command.

```
place_opt
  [-from <stage>]
  [-to <stage>]
  [-effort {low | medium | high}]
  [-congestion]
  [-timing]
  [-power]
  [-cts]
  [-optimize_dft]
  [-incremental]
  [-no_pre_place_opt]
  [-no_final_place_opt]
```

**Stages** (can be targeted with `-from`/`-to`):
- `initial_place` — global placement
- `initial_drc` — legalization
- `initial_opto` — initial optimization
- `final_place` — detailed placement
- `final_opto` — final optimization

**Examples**

```tcl
# Full place_opt with typical settings
place_opt -effort high -congestion -timing

# Incremental placement optimization
place_opt -incremental

# Run only specific stages
place_opt -from initial_place -to initial_opto

# Placement with CTS-aware optimization
place_opt -cts

# Power-driven placement
place_opt -power -effort high
```

### create_placement

Global or detailed placement (lower-level than place_opt).

```
create_placement
  [-effort {low | medium | high}]
  [-congestion]
  [-timing_driven]
  [-floorplan]
  [-incremental]
  [-no_legalize]
```

```tcl
create_placement -effort high -timing_driven -congestion
create_placement -incremental
```

### legalize_placement

Legalize cell placement to valid row sites.

```
legalize_placement
  [-effort {low | medium | high}]
  [-incremental]
  [-cells <cell_list>]
```

```tcl
legalize_placement
legalize_placement -cells [get_cells -hier -filter "is_placed==false"]
legalize_placement -effort high -incremental
```

### Placement-Related App Options

```tcl
# Congestion-driven placement
set_app_options -name place.coarse.congestion_driven_max_util -value 0.85
set_app_options -name place.coarse.max_density -value 0.70

# Timing-driven placement
set_app_options -name place_opt.flow.do_spg -value true
set_app_options -name place_opt.initial_place.effort -value high

# Cell padding
set_app_options -name place.rules.min_cell_spacing -value 2

# Auto density control
set_app_options -name place.coarse.auto_density_control -value true

# Enable enhanced placement
set_app_options -name place_opt.flow.optimize_icgs -value true

# Placement of specific cell types
set_app_options -name place.coarse.tns_driven -value true
set_app_options -name place.coarse.channel_detect_mode -value true

# Control legalization effort
set_app_options -name place.legalize.effort -value high
set_app_options -name place.legalize.max_displacement -value 50
```

### Cell Padding and Spacing

```tcl
# Add padding to specific cells
set_cell_spacing -left_value 2 -right_value 2 \
  [get_lib_cells */ANTENNA*]

# Add keepout around specific cells
create_keepout_margin \
  -type hard \
  -outer {2 0 2 0} \
  [get_cells -hier -filter "ref_name =~ *SRAM*"]
```

---

## 7. Clock Tree Synthesis (CTS)

### synthesize_clock_trees

Build clock trees for all clock domains.

```
synthesize_clock_trees
  [-clocks <clock_list>]
  [-no_propagation]
  [-postroute]
```

```tcl
synthesize_clock_trees
synthesize_clock_trees -clocks [get_clocks sys_clk]
synthesize_clock_trees -postroute
```

### clock_opt

Perform CTS followed by post-CTS optimization.

```
clock_opt
  [-from <stage>]
  [-to <stage>]
  [-effort {low | medium | high}]
  [-no_clock_route]
  [-power]
  [-congestion]
```

**Stages**:
- `build_clock` — clock tree construction
- `route_clock` — clock net routing
- `final_opto` — post-CTS optimization and data timing fix

**Examples**

```tcl
# Full clock_opt
clock_opt -effort high -power

# Build clocks only (no optimization)
clock_opt -from build_clock -to route_clock

# Post-CTS optimization only
clock_opt -from final_opto -to final_opto

# Power-optimized CTS
clock_opt -power -effort high
```

### set_clock_tree_options

Configure CTS behavior globally.

```
set_clock_tree_options
  [-target_skew <value>]
  [-target_latency <value>]
  [-max_fanout <value>]
  [-max_transition <value>]
  [-use_default_routing_for_sinks <0|1>]
  [-clock <clock_name>]
```

```tcl
set_clock_tree_options -target_skew 0.050 -target_latency 0.3
set_clock_tree_options -max_fanout 32 -max_transition 0.100
```

### CTS Reference Cells

```tcl
# Set which cells CTS can use
set_lib_cell_purpose -include cts [get_lib_cells */CTS*]
set_lib_cell_purpose -include cts [get_lib_cells */CLKBUF*]
set_lib_cell_purpose -include cts [get_lib_cells */CLKINV*]

# Exclude certain cells from CTS
set_lib_cell_purpose -exclude cts [get_lib_cells */CLKBUF_X1]
```

### CTS NDR (Non-Default Rules) for Clock Routing

```tcl
# Create routing rule for clock nets
create_routing_rule cts_double_width \
  -widths {M3 0.08 M4 0.08 M5 0.08} \
  -spacings {M3 0.08 M4 0.08 M5 0.08}

create_routing_rule cts_triple_width \
  -widths {M3 0.12 M4 0.12 M5 0.12} \
  -spacings {M3 0.12 M4 0.12 M5 0.12}

# Apply the rule to clock nets
set_clock_routing_rules \
  -rules cts_double_width \
  -min_routing_layer M3 \
  -max_routing_layer M5

# Different rules for trunk and leaf
set_clock_routing_rules \
  -rules cts_triple_width \
  -net_type trunk \
  -min_routing_layer M4 \
  -max_routing_layer M6

set_clock_routing_rules \
  -rules cts_double_width \
  -net_type leaf \
  -min_routing_layer M3 \
  -max_routing_layer M5
```

### CTS App Options

```tcl
# CTS engine options
set_app_options -name cts.compile.enable_global_route -value true
set_app_options -name cts.common.max_fanout -value 64
set_app_options -name clock_opt.flow.enable_ccd -value true

# Useful CTS skew balancing
set_app_options -name cts.compile.enable_local_skew -value true

# CTS buffer removal control
set_app_options -name cts.compile.enable_buffer_removal -value true

# Post-CTS optimization
set_app_options -name clock_opt.flow.optimize_setup -value true
set_app_options -name clock_opt.flow.optimize_hold -value true

# Clock concurrent optimization
set_app_options -name clock_opt.hold.effort -value high
set_app_options -name clock_opt.flow.datapath_opt -value true
```

### Clock Group / Skew Targets

```tcl
# Set skew group
create_clock_skew_group -name func_group \
  -objects [get_clocks {clk_sys clk_cpu}] \
  -target_skew 0.030

# Balance inter-clock skew
set_inter_clock_delay_options \
  -balance_group func_group
```

---

## 8. Routing

### route_auto

Top-level automatic routing command (global + detailed).

```
route_auto
  [-max_detail_route_iterations <N>]
  [-incremental]
  [-no_antenna_fix]
```

**Examples**

```tcl
route_auto
route_auto -max_detail_route_iterations 40
route_auto -incremental
```

### route_opt

Post-route optimization (combined optimization + routing).

```
route_opt
  [-from <stage>]
  [-to <stage>]
  [-effort {low | medium | high}]
  [-incremental]
  [-power]
  [-xtalk_reduction]
  [-area_recovery]
  [-hold]
```

**Stages**:
- `initial_opto`
- `initial_route`
- `final_opto`

**Examples**

```tcl
# Full route_opt
route_opt -effort high

# Hold-focused optimization
route_opt -hold -effort high

# Incremental
route_opt -incremental

# Power + crosstalk reduction
route_opt -power -xtalk_reduction

# Area recovery after timing closure
route_opt -area_recovery
```

### route_detail

Detailed routing only (no optimization).

```
route_detail
  [-incremental]
  [-max_number_iterations <N>]
  [-initial_drc_from_input]
```

```tcl
route_detail
route_detail -incremental -max_number_iterations 20
```

### route_global

Global routing only (for congestion analysis before detail routing).

```
route_global
  [-congestion_map_only]
```

```tcl
route_global
route_global -congestion_map_only
```

### route_zrt_auto

ZRoute-based automatic routing (legacy interface).

```
route_zrt_auto
  [-max_detail_route_iterations <N>]
```

### set_routing_rule

Apply non-default routing rules to specific nets.

```
set_routing_rule <net_list>
  -rule <rule_name>
  [-min_routing_layer <layer>]
  [-max_routing_layer <layer>]
```

```tcl
set_routing_rule [get_nets clk*] \
  -rule cts_double_width \
  -min_routing_layer M3 \
  -max_routing_layer M5
```

### Routing App Options

```tcl
# Layer usage
set_app_options -name route.common.global_min_layer_mode -value hard
set_app_options -name route.common.global_max_layer_mode -value allow
set_app_options -name route.common.minimum_layer_name -value M2
set_app_options -name route.common.maximum_layer_name -value M7

# Via preferences
set_app_options -name route.common.via_preference -value double

# Antenna fixing
set_app_options -name route.detail.antenna -value true
set_app_options -name route.detail.antenna_fixing_preference -value use_diodes

# Timing-driven routing
set_app_options -name route.global.timing_driven -value true
set_app_options -name route.track.timing_driven -value true
set_app_options -name route.detail.timing_driven -value true

# Crosstalk-driven routing
set_app_options -name route.global.crosstalk_driven -value true

# DRC iterations
set_app_options -name route.detail.drc_convergence_effort_level -value high

# Redundant via insertion
set_app_options -name route.common.post_detail_route_redundant_via_insertion -value medium

# Number of routing threads
set_app_options -name route.common.number_of_threads -value 8

# Routing blockage handling
set_app_options -name route.common.rc_driven_setup_effort_level -value high

# Search and repair
set_app_options -name route.detail.search_repair_loops -value 50
```

### Antenna Fix

```tcl
# Set diode cells for antenna fixing
set_app_options -name route.detail.default_diode_cell -value "ANTENNA_HVT"

# Insert antenna diodes
route_detail -incremental
```

### Redundant Via Insertion

```tcl
# Configure redundant vias
add_redundant_vias \
  -via_mapping_file ./tech/redundant_via.map

# Or use automatic
set_app_options -name route.common.post_detail_route_redundant_via_insertion -value high
```

---

## 9. Optimization and ECO

### optimize_logic

Logic optimization (restructure, remap).

```
optimize_logic
  [-effort {low | medium | high}]
  [-area]
```

### size_cell

Resize a specific cell to a different drive strength.

```
size_cell <cell_instance> <lib_cell>
```

```tcl
size_cell U_buf_123 saed14_rvt/BUFX8
size_cell [get_cells u_reg_file/ff_q_reg] saed14_rvt/DFFX2
```

### insert_buffer

Insert a buffer or inverter pair on a net.

```
insert_buffer <pin_or_net> <lib_cell>
  [-new_cell_name <name>]
  [-new_net_name <name>]
```

```tcl
insert_buffer [get_pins u_cpu/clk] saed14_rvt/CLKBUFX4
insert_buffer [get_nets data_bus[0]] saed14_rvt/BUFX4 \
  -new_cell_name eco_buf_1
```

### remove_buffer

Remove a buffer from a path.

```
remove_buffer <cell_list>
```

```tcl
remove_buffer [get_cells eco_buf_1]
remove_buffer [get_cells -hier -filter "ref_name == BUFX2 && is_eco_cell == true"]
```

### swap_cell

Replace a cell with a different library cell.

```
swap_cell <cell_instance> <lib_cell>
```

```tcl
swap_cell [get_cells u_mux_1] saed14_lvt/MUX2X2
```

### ECO Operations

```tcl
# Create ECO cell
create_cell eco_and_1 saed14_rvt/AND2X1

# Connect ECO cell
connect_net [get_nets sig_a] [get_pins eco_and_1/A]
connect_net [get_nets sig_b] [get_pins eco_and_1/B]
create_net eco_out_1
connect_net [get_nets eco_out_1] [get_pins eco_and_1/Y]

# Disconnect a pin
disconnect_net [get_nets old_net] [get_pins u_gate/A]

# Remove a cell
remove_cell [get_cells unused_buf]

# Remove a net
remove_net [get_nets unused_net]

# Freeze silicon ECO (for metal-only ECO)
set_app_options -name opt.common.allow_physical_feedthrough -value true
set_freeze_port -all
set_dont_touch [get_cells -hier -filter "is_fixed==true"]

# Incremental place + route after ECO
place_eco_cells -eco_changed_cells -legalize_only
route_eco
```

### Useful Opt Commands

```tcl
# Fix hold violations
set_app_options -name opt.hold.effort -value high
set_fix_hold [all_clocks]

# Remove ideal network
remove_ideal_network [get_ports clk]

# Set max transition / max capacitance
set_max_transition 0.200 [current_design]
set_max_capacitance 0.100 [current_design]
set_max_fanout 32 [current_design]

# Useful cell usage controls
set_prefer -min [get_lib_cells */DFFX1]
set_dont_use [get_lib_cells */FILL*]
set_lib_cell_purpose -include {optimization} [get_lib_cells */BUFX*]
set_lib_cell_purpose -exclude {optimization} [get_lib_cells */DELCELL*]
```

---

## 10. Timing Analysis and Reporting

### report_timing

The workhorse timing report command.

```
report_timing
  [-delay_type {max | min | min_max}]
  [-path_type {full | full_clock | full_clock_expanded | summary | end}]
  [-max_paths <N>]
  [-nworst <N>]
  [-group <path_group_list>]
  [-from <startpoints>]
  [-through <through_points>]
  [-to <endpoints>]
  [-rise_from | -fall_from]
  [-rise_to | -fall_to]
  [-rise_through | -fall_through]
  [-slack_lesser_than <value>]
  [-slack_greater_than <value>]
  [-nets]
  [-capacitance]
  [-transition_time]
  [-input_pins]
  [-crosstalk_delta]
  [-derate]
  [-nosplit]
  [-significant_digits <N>]
  [-sort_by {slack | group}]
  [-include_hierarchical_pins]
  [-scenario <scenario>]
  [-corners <corner_list>]
  [-physical]
  [-voltage]
  > <output_file>
```

**Examples**

```tcl
# Basic worst-path timing
report_timing -delay_type max -max_paths 100

# Detailed timing with all annotations
report_timing \
  -delay_type max \
  -path_type full_clock_expanded \
  -max_paths 50 \
  -nworst 5 \
  -nets \
  -capacitance \
  -transition_time \
  -input_pins \
  -crosstalk_delta \
  -derate \
  -significant_digits 4 \
  > ./reports/timing_setup.rpt

# Hold timing
report_timing -delay_type min -max_paths 100 \
  > ./reports/timing_hold.rpt

# Path group specific
report_timing -group {clk_sys} -max_paths 20 -nworst 3

# Endpoint-specific
report_timing -to [get_pins u_fifo/wr_data_reg*/D] -max_paths 10

# Through a specific cell
report_timing -through [get_pins u_mux/Y] -max_paths 5

# Cross-scenario
report_timing -scenario func_ss_125c -max_paths 50
```

### report_qor

Quality-of-Results summary.

```
report_qor
  [-summary]
  [-scenarios <list>]
  [-significant_digits <N>]
  > <output_file>
```

```tcl
report_qor > ./reports/qor.rpt
report_qor -summary > ./reports/qor_summary.rpt
```

### report_design

Design statistics report.

```
report_design
  [-physical]
  [-netlist]
  [-all]
```

```tcl
report_design -physical > ./reports/design_physical.rpt
```

### report_clock_timing

Clock-specific timing analysis.

```
report_clock_timing
  [-type {skew | latency | transition | summary}]
  [-clock <clock_list>]
  [-nworst <N>]
  [-setup | -hold]
  [-to <endpoint_list>]
  [-verbose]
  > <output_file>
```

```tcl
report_clock_timing -type skew -nworst 20 > ./reports/clock_skew.rpt
report_clock_timing -type latency -clock clk_sys > ./reports/clock_latency.rpt
report_clock_timing -type summary > ./reports/clock_summary.rpt
```

### report_constraint

```
report_constraint
  [-all_violators]
  [-max_delay]
  [-min_delay]
  [-max_transition]
  [-max_capacitance]
  [-max_fanout]
  [-significant_digits <N>]
```

```tcl
report_constraint -all_violators > ./reports/constraints.rpt
report_constraint -max_transition -all_violators
```

### report_power

```
report_power
  [-hierarchy]
  [-levels <N>]
  [-verbose]
  [-scenarios <list>]
  [-corner <corner>]
  [-analysis_effort {low | medium | high}]
  > <output_file>
```

```tcl
report_power > ./reports/power.rpt
report_power -hierarchy -levels 2 > ./reports/power_hier.rpt
report_power -verbose > ./reports/power_verbose.rpt
```

### Additional Report Commands

```tcl
# Area report
report_area
  [-hierarchy]
  [-physical]
  [-nosplit]
  > <output_file>

# Utilization
report_utilization > ./reports/utilization.rpt

# Congestion
report_congestion
  [-grc_based]
  [-routing_stage {global | detail}]
  > ./reports/congestion.rpt

# DRC violations
report_design_rule_violations > ./reports/drc.rpt

# Cell usage
report_cell [get_cells -hier *]
report_reference_summary > ./reports/ref_summary.rpt

# Net fanout
report_net_fanout -threshold 50 > ./reports/high_fanout.rpt

# Clock gating
report_clock_gating > ./reports/clock_gating.rpt

# Timing exceptions
report_exceptions > ./reports/exceptions.rpt

# Cross-probing physical
report_timing -physical > ./reports/timing_physical.rpt

# Noise (SI)
report_noise > ./reports/noise.rpt

# QoR comparison
compare_qor -base ./reports/qor_old.rpt -current ./reports/qor_new.rpt
```

---

## 11. Power Analysis and Reporting

### Power Analysis Flow in FC

```tcl
# 1. Set power analysis mode
set_app_options -name power.default_toggle_rate -value 0.1
set_app_options -name power.default_static_probability -value 0.5

# 2. Read switching activity
read_saif ./saif/top.saif -strip_path tb/dut

# 3. Propagate activity
propagate_switching_activity

# 4. Report power
report_power -hierarchy -levels 3 > ./reports/power.rpt

# 5. Power optimization
set_max_dynamic_power 500
set_max_leakage_power 100
```

### Power-Related App Options

```tcl
set_app_options -name power.default_toggle_rate -value 0.1
set_app_options -name power.default_static_probability -value 0.5
set_app_options -name power.analysis.mode -value {averaged | time_based}
set_app_options -name power.analysis.auto_compute_target_library_toggle_rate -value true
```

---

## 12. Physical Verification In-Design

### In-Design ICV DRC

```tcl
# Set ICV path
set_app_options -name signoff.check_drc.runset -value ./tech/drc_rules.rs

# Run in-design DRC
signoff_check_drc
  [-auto_eco {true | false}]
  [-max_errors_per_rule <N>]

signoff_check_drc > ./reports/drc_signoff.rpt

# Fix DRC violations
signoff_fix_drc
  [-max_iterations <N>]
  [-auto_eco]
```

### In-Design ICV Metal Fill

```tcl
# Insert metal fill using ICV
signoff_metal_fill
  [-runset <fill_rules>]
  [-select_layers <layer_list>]
  [-timing_preserve_setup_slack_threshold <value>]
  [-timing_preserve_hold_slack_threshold <value>]

signoff_metal_fill \
  -runset ./tech/metal_fill.rs \
  -timing_preserve_setup_slack_threshold 0.050

# Remove fill
remove_metal_fill
```

---

## 13. App Options Reference

App options in FC replace `set_app_var` from older tools. They control tool
behavior across all stages.

### Querying and Setting App Options

```tcl
# Get current value
get_app_options -name place_opt.flow.do_spg

# List all app options matching a pattern
get_app_options place*

# Set value
set_app_options -name <option_name> -value <value>

# Reset to default
reset_app_options -name <option_name>

# Report all non-default app options
report_app_options -non_default > ./reports/app_options.rpt
```

### Major App Option Categories

#### Synthesis

```tcl
set_app_options -name compile.flow.effort -value high
set_app_options -name compile.flow.enable_register_retiming -value true
set_app_options -name compile.flow.clock_gating -value true
set_app_options -name compile.area.effort -value high
```

#### Placement

```tcl
set_app_options -name place.coarse.congestion_driven_max_util -value 0.85
set_app_options -name place.coarse.max_density -value 0.75
set_app_options -name place.coarse.tns_driven -value true
set_app_options -name place.coarse.auto_density_control -value true
set_app_options -name place_opt.flow.do_spg -value true
set_app_options -name place_opt.initial_place.effort -value high
set_app_options -name place_opt.flow.optimize_icgs -value true
set_app_options -name place_opt.congestion.effort -value high
set_app_options -name place.rules.min_cell_spacing -value 2
```

#### CTS

```tcl
set_app_options -name cts.compile.enable_global_route -value true
set_app_options -name cts.common.max_fanout -value 64
set_app_options -name cts.compile.enable_local_skew -value true
set_app_options -name cts.compile.enable_buffer_removal -value true
set_app_options -name clock_opt.flow.enable_ccd -value true
set_app_options -name clock_opt.flow.optimize_setup -value true
set_app_options -name clock_opt.flow.optimize_hold -value true
set_app_options -name clock_opt.hold.effort -value high
```

#### Routing

```tcl
set_app_options -name route.common.global_min_layer_mode -value hard
set_app_options -name route.common.minimum_layer_name -value M2
set_app_options -name route.common.maximum_layer_name -value M7
set_app_options -name route.global.timing_driven -value true
set_app_options -name route.global.crosstalk_driven -value true
set_app_options -name route.track.timing_driven -value true
set_app_options -name route.detail.timing_driven -value true
set_app_options -name route.detail.antenna -value true
set_app_options -name route.detail.antenna_fixing_preference -value use_diodes
set_app_options -name route.common.post_detail_route_redundant_via_insertion -value medium
set_app_options -name route.common.number_of_threads -value 8
set_app_options -name route.common.via_preference -value double
set_app_options -name route.detail.search_repair_loops -value 50
set_app_options -name route.detail.drc_convergence_effort_level -value high
```

#### Optimization

```tcl
set_app_options -name opt.common.max_fanout -value 32
set_app_options -name opt.timing.effort -value high
set_app_options -name opt.area.effort -value medium
set_app_options -name opt.power.effort -value high
set_app_options -name opt.hold.effort -value high
set_app_options -name opt.leakage_power.effort -value high
set_app_options -name opt.common.allow_physical_feedthrough -value false
set_app_options -name opt.dft.optimize_scan_chain -value true
```

#### Timing

```tcl
set_app_options -name time.si_enable_analysis -value true
set_app_options -name time.pocvm_enable_analysis -value true
set_app_options -name time.aocvm_enable_analysis -value true
set_app_options -name time.ocvm_enable_analysis -value true
set_app_options -name time.remove_clock_reconvergence_pessimism -value true
set_app_options -name time.disable_recovery_removal_checks -value false
set_app_options -name timer.delay_calculation_style -value {auto | elmore | arnoldi}
```

#### Power

```tcl
set_app_options -name power.default_toggle_rate -value 0.1
set_app_options -name power.default_static_probability -value 0.5
set_app_options -name power.analysis.mode -value averaged
set_app_options -name opt.power.effort -value high
```

#### Signoff

```tcl
set_app_options -name signoff.check_drc.runset -value ./tech/drc.rs
set_app_options -name signoff.create_metal_fill.runset -value ./tech/fill.rs
set_app_options -name extract.tech_file -value ./tech/star_rcxt.nxtgrd
```

---

## 14. Useful Utility Commands

### MMMC (Multi-Mode Multi-Corner)

```tcl
# Create scenarios
create_scenario -name func_ss_125c
create_scenario -name func_ff_m40c
create_scenario -name scan_ss_125c

# Set current scenario
set_scenario_status func_ss_125c -active true -setup true -hold false
set_scenario_status func_ff_m40c -active true -setup false -hold true
set_scenario_status scan_ss_125c -active true -setup true -hold false

# Within a scenario — apply corners and modes
current_scenario func_ss_125c
read_sdc ./constraints/func_mode.sdc
set_operating_conditions ss_125c
set_timing_derate -early 0.95 -late 1.05

current_scenario func_ff_m40c
read_sdc ./constraints/func_mode.sdc
set_operating_conditions ff_m40c
set_timing_derate -early 0.95 -late 1.05

# Report across scenarios
report_timing -scenarios {func_ss_125c func_ff_m40c} -max_paths 20
report_qor -scenarios all
```

### Object Access Commands

```tcl
# Get objects by type
get_cells [-hier] [-filter <expr>] [<pattern>]
get_nets [-hier] [-filter <expr>] [<pattern>]
get_pins [-hier] [-filter <expr>] [<pattern>]
get_ports [<pattern>]
get_clocks [<pattern>]
get_lib_cells [<pattern>]
get_lib_pins [<pattern>]

# Get/Set attributes
get_attribute [get_cells u_cpu] area
get_attribute [get_cells u_cpu] ref_name
set_attribute [get_cells u_macro] is_fixed true

# Filter examples
get_cells -hier -filter "ref_name =~ BUF* && is_hierarchical == false"
get_cells -hier -filter "area > 10.0"
get_pins -hier -filter "direction == in && is_clock_pin == true"
get_nets -hier -filter "net_type == clock"
```

### Collections

```tcl
# Size of collection
sizeof_collection [get_cells -hier *]

# Iterate over collection
foreach_in_collection cell [get_cells -hier -filter "is_sequential==true"] {
  set name [get_attribute $cell full_name]
  set ref  [get_attribute $cell ref_name]
  puts "$name -> $ref"
}

# Sort collection
sort_collection [get_cells -hier *] area -descending

# Add / remove from collection
set all_bufs [get_cells -hier -filter "ref_name =~ BUF*"]
set big_bufs [filter_collection $all_bufs "area > 5.0"]

# Index into collection
index_collection [get_cells -hier *] 0
```

### GUI Commands

```tcl
# Start GUI
start_gui

# Highlight objects
gui_highlight [get_cells u_cpu]
gui_change_highlight -color red [get_cells u_cpu]

# Zoom to object
gui_zoom -fit
gui_zoom -selection

# Create rulers
gui_create_ruler -from {100 200} -to {300 400}

# Screenshot
gui_write_window_image -file ./reports/layout.png
```

### Session Management

```tcl
# Save session
save_session ./sessions/post_route_session

# Restore session
restore_session ./sessions/post_route_session

# History
history
write_script -history ./scripts/session_history.tcl

# Execute TCL script
source ./scripts/setup.tcl

# Redirect output
redirect -file ./reports/timing.rpt {report_timing -max_paths 100}
redirect -append -file ./reports/log.txt {report_qor}

# Suppress messages
suppress_message {CMD-041 ATTR-012}
unsuppress_message {CMD-041}

# Set host options (multi-CPU)
set_host_options -max_cores 16

# Memory usage
report_resource_usage

# Check design
check_design
check_timing
check_mv_design
```

### Physical Utility Commands

```tcl
# Add filler cells
create_stdcell_fillers -lib_cells {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}

# Add endcap cells
set_app_options -name place.rules.endcap_cells -value "ENDCAP"
create_boundary_cells

# Add tap/well-tie cells
create_tap_cells \
  -lib_cell TAPCELL \
  -distance 30 \
  -pattern stagger

# Add tie cells
connect_pg_net -tie

# Remove filler cells (before ECO)
remove_stdcell_fillers

# Check legality
check_legality
```

---

*End of Fusion Compiler Command Reference*
