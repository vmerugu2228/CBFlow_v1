# Synopsys StarRC Command Reference

Comprehensive command reference for Synopsys StarRC, the signoff-quality
parasitic extraction tool. StarRC is command-file driven — you prepare a
`star_cmd` file with directives and then invoke the extraction engine.

StarRC version baseline: T-2022.03 and later.

---

## Table of Contents

1. [Overview and Invocation](#1-overview-and-invocation)
2. [Essential Directives](#2-essential-directives)
3. [Technology and Process](#3-technology-and-process)
4. [Design Input](#4-design-input)
5. [Extraction Configuration](#5-extraction-configuration)
6. [Coupling Capacitance](#6-coupling-capacitance)
7. [Net Selection](#7-net-selection)
8. [Output Control](#8-output-control)
9. [Advanced Extraction Modes](#9-advanced-extraction-modes)
10. [Distributed / Parallel Extraction](#10-distributed--parallel-extraction)
11. [Incremental Extraction](#11-incremental-extraction)
12. [Resistance Extraction](#12-resistance-extraction)
13. [Inductance Extraction](#13-inductance-extraction)
14. [Temperature and Process Variation](#14-temperature-and-process-variation)
15. [In-Design Extraction (FC/ICC2)](#15-in-design-extraction-fcicc2)
16. [Complete Command File Examples](#16-complete-command-file-examples)

---

## 1. Overview and Invocation

StarRC reads a command file (`star_cmd`) containing directives, then extracts
parasitics from the layout. The output is typically SPEF, SBPF, or DSPF.

### Invocation

```bash
# Basic invocation
StarXtract star_cmd

# With log file
StarXtract star_cmd 2>&1 | tee starrc.log

# Specifying command file explicitly
StarXtract -cmd star_cmd

# Using specific StarRC version
/tools/synopsys/starrc/T-2022.03-SP3/bin/StarXtract star_cmd
```

### Command File Basics

- One directive per line
- Comments start with `*` or `//`
- Directives are case-insensitive
- Spaces around `:` are optional
- File is typically named `star_cmd` or `starrc_cmd`

---

## 2. Essential Directives

Every StarRC run requires these minimum directives.

```
* Required directives
STAR_DIRECTORY        : ./star_work
BLOCK                 : chip_top
TCAD_GRD_FILE         : /pdk/starrc/saed14nm_1p9m.nxtgrd
MAPPING_FILE          : /pdk/starrc/saed14nm_1p9m.mapping
TOP_DEF_FILE          : ./def/chip_top_post_route.def
LEF_FILE              : /pdk/lef/saed14nm_tech.lef /pdk/lef/saed14nm_std.lef
```

### STAR_DIRECTORY

Working directory for StarRC intermediate files.

```
STAR_DIRECTORY : <path>
```

```
STAR_DIRECTORY : ./star_work
STAR_DIRECTORY : /scratch/starrc_run
```

### BLOCK

Top-level cell name.

```
BLOCK : <cell_name>
```

```
BLOCK : chip_top
BLOCK : cpu_core
```

### TOP_CELL (Alternative to BLOCK)

```
TOP_CELL : chip_top
```

### TCAD_GRD_FILE

The technology file from the foundry — contains RC models for the process.
This is the most critical file for extraction accuracy.

```
TCAD_GRD_FILE : <path_to_nxtgrd_file>
```

```
TCAD_GRD_FILE : /pdk/starrc/saed14nm_1p9m_Cmax.nxtgrd
TCAD_GRD_FILE : /pdk/starrc/saed14nm_1p9m_Cmin.nxtgrd
TCAD_GRD_FILE : /pdk/starrc/saed14nm_1p9m_RCmax.nxtgrd
```

### MAPPING_FILE

Maps GDS/LEF layer names to the nxtgrd file layer names.

```
MAPPING_FILE : <path_to_mapping_file>
```

```
MAPPING_FILE : /pdk/starrc/saed14nm_1p9m.mapping
```

---

## 3. Technology and Process

### LEF_FILE

LEF technology and cell LEF files.

```
LEF_FILE : <file1> [<file2> ...]
```

```
LEF_FILE : /pdk/lef/saed14nm_tech.lef \
           /pdk/lef/saed14nm_rvt.lef \
           /pdk/lef/saed14nm_hvt.lef \
           /pdk/lef/saed14nm_lvt.lef \
           /pdk/lef/sram_macros.lef
```

### GDS_FILE

Read layout from GDSII (instead of or in addition to DEF).

```
GDS_FILE : <file>
```

```
GDS_FILE : ./gds/chip_top_merged.gds
```

### MILKYWAY_DATABASE

Read from Milkyway database (legacy).

```
MILKYWAY_DATABASE : <mw_lib_path>
```

### NDM_DATABASE

Read from NDM database (FC/ICC2).

```
NDM_DATABASE : <ndm_lib_path>
```

```
NDM_DATABASE : ./ndm/chip_top.ndm
```

### TOP_DEF_FILE

DEF file with routing information.

```
TOP_DEF_FILE : <def_file>
```

```
TOP_DEF_FILE : ./def/chip_top_post_route.def
```

### ADDITIONAL_LEFS

```
ADDITIONAL_LEFS : /pdk/lef/io_cells.lef /pdk/lef/pll.lef
```

### MACRO_GDS_FILES

```
MACRO_GDS_FILES : /libs/gds/sram.gds /libs/gds/pll.gds
```

---

## 4. Design Input

### Netlist Source Options

```
* DEF-based extraction (most common for digital)
TOP_DEF_FILE : ./def/chip_top.def

* GDS-based extraction (for custom/analog)
GDS_FILE : ./gds/chip_top.gds

* NDM-based extraction (FC integration)
NDM_DATABASE : ./ndm/chip_top.ndm

* Milkyway-based (legacy)
MILKYWAY_DATABASE : ./mw/chip_top_mw
```

### Verilog Netlist for Connectivity

```
NETLIST_FILE : ./netlist/chip_top.v
NETLIST_FORMAT : VERILOG
```

### Power/Ground Net Identification

```
POWER_NETS       : VDD VDDH VDD_RET
GROUND_NETS      : VSS VSSQ
```

```
* Recognize PG nets from connectivity
POWER_NETS       : VDD*
GROUND_NETS      : VSS*
```

---

## 5. Extraction Configuration

### EXTRACTION

Master extraction mode control.

```
EXTRACTION : <mode>
```

| Mode | Description |
|---|---|
| `RC` | Extract both R and C (most common for digital signoff) |
| `C` | Capacitance only |
| `R` | Resistance only |
| `RLC` | R, L, and C (for high-speed) |
| `RCCC` | RC with coupling capacitance (standard for SI-aware signoff) |

```
EXTRACTION : RCCC
```

### COUPLE_TO_GROUND

Convert coupling capacitances to ground capacitances (disables SI but
simplifies SPEF).

```
COUPLE_TO_GROUND : YES | NO
```

```
COUPLE_TO_GROUND : NO   ;* Keep coupling for SI analysis
COUPLE_TO_GROUND : YES  ;* For non-SI runs
```

### REDUCTION

Parasitic network reduction method.

```
REDUCTION : <type>
```

| Type | Description |
|---|---|
| `NO_EXTRA_LOOPS` | Minimal reduction (largest SPEF, most accurate) |
| `NONE` | No reduction |
| `ARNOLDI` | Arnoldi reduction (balanced accuracy/size) |
| `TICER` | TICER reduction (good for large designs) |
| `STAR_MODEL` | Star model reduction |

```
REDUCTION : NO_EXTRA_LOOPS
REDUCTION : ARNOLDI
```

### MODE

Extraction accuracy mode.

```
MODE : <value>
```

| Mode | Description |
|---|---|
| `200` | Highest accuracy (3D field-solver quality) |
| `400` | High accuracy (signoff quality, most common) |
| `600` | Medium accuracy (faster, for exploration) |
| `800` | Lower accuracy (fastest) |

```
MODE : 400
```

### METAL_FILL_EXTRACTION

Account for metal fill in extraction.

```
METAL_FILL_GDS_FILE    : ./gds/metal_fill.gds
METAL_FILL_EXTRACTION  : FLOATING
```

| Option | Description |
|---|---|
| `FLOATING` | Treat fill as floating metal (most accurate) |
| `GROUNDED` | Treat fill as grounded |
| `NONE` | Ignore fill |

### CALIBRE_RUNSET (for Calibre-extracted layout)

```
CALIBRE_RUNSET : /pdk/calibre/drc_deck
```

---

## 6. Coupling Capacitance

### COUPLING_ABS_THRESHOLD

Minimum absolute coupling capacitance to report (in Farads).

```
COUPLING_ABS_THRESHOLD : <value>
```

```
COUPLING_ABS_THRESHOLD : 1e-17     ;* 10 aF
COUPLING_ABS_THRESHOLD : 3e-17     ;* 30 aF
```

### COUPLING_REL_THRESHOLD

Minimum coupling as fraction of total net capacitance.

```
COUPLING_REL_THRESHOLD : <value>
```

```
COUPLING_REL_THRESHOLD : 0.01      ;* 1% of total cap
COUPLING_REL_THRESHOLD : 0.03      ;* 3% of total cap
```

### COUPLING_REPORT

```
COUPLING_REPORT : YES | NO
```

### COUPLING Capacitance Directives (Complete)

```
COUPLING_ABS_THRESHOLD   : 1e-17
COUPLING_REL_THRESHOLD   : 0.01
COUPLE_TO_GROUND         : NO
COUPLING_REPORT          : YES
XREF                     : YES         ;* Cross-reference coupling to aggressor nets
```

---

## 7. Net Selection

### NETS / NETS_INCLUDE / NETS_EXCLUDE

Control which nets are extracted.

```
* Extract all nets (default)
NETS : *

* Extract specific nets
NETS : clk data_bus[0] data_bus[1] addr[*]

* Include file with net list
NETS_INCLUDE_FILE : ./net_list.txt

* Exclude specific nets
NETS_EXCLUDE : VDD VSS

* Exclude file
NETS_EXCLUDE_FILE : ./exclude_nets.txt
```

### Net Selection by Type

```
* Extract only signal nets
NETS : * -exclude_pg

* Extract only clock nets
NETS : -clock

* Extract only specified nets from a file
NET_FILE : ./critical_nets.txt
```

### SKIP_CELLS

Skip extraction inside certain cells (treat as black boxes).

```
SKIP_CELLS : sram_256x32 pll_top analog_block
```

### SELECTED_CELLS

Extract only within specified cells.

```
SELECTED_CELLS : cpu_core mem_ctrl
```

---

## 8. Output Control

### SPEF Output

```
NETLIST_FILE          : ./output/chip_top.spef
NETLIST_FORMAT        : SPEF
NETLIST_COMPRESS_TYPE : GZIP      ;* or NONE
```

### SBPF Output

```
NETLIST_FILE          : ./output/chip_top.sbpf
NETLIST_FORMAT        : SBPF
```

### DSPF Output

```
NETLIST_FILE          : ./output/chip_top.dspf
NETLIST_FORMAT        : DSPF
```

### Output Naming

```
* Control instance name delimiter
INSTANCE_NAME_SEPARATOR : /

* Bus naming style
BUS_BIT_INDEX_STYLE : [ ]

* Name mapping
NAME_MAP : YES
```

### Output Precision

```
COUPLE_NOMIAL_DIGITS    : 6
RESISTANCE_NOMIAL_DIGITS: 6
CAPACITANCE_UNIT        : FF     ;* fF (femtoFarads)
RESISTANCE_UNIT         : OHM
```

### Multiple Output Files

```
* Generate both SPEF and SBPF
NETLIST_FILE   : ./output/chip_top.spef
NETLIST_FORMAT : SPEF

SECOND_NETLIST_FILE   : ./output/chip_top.sbpf
SECOND_NETLIST_FORMAT : SBPF
```

### Hierarchical SPEF

```
* Write per-block SPEF files
HIERARCHICAL_SPEF   : YES
HIERARCHICAL_SEPARATOR : /
```

### SPEF Options

```
SPEF_VERSION         : IEEE1481-2009
XREF                 : YES          ;* Include cross-reference section
COMPRESS_SPEF        : YES
STAR_SPEF_VERSION    : 2
KEEP_VIA_NODES       : YES
PIN_ORDER_FILE       : ./pin_order.txt
```

---

## 9. Advanced Extraction Modes

### Corner-Based Extraction

```
* Best-case (minimum RC)
TCAD_GRD_FILE : /pdk/starrc/saed14nm_Cmin.nxtgrd
OPERATING_TEMPERATURE : -40

* Worst-case (maximum RC)
TCAD_GRD_FILE : /pdk/starrc/saed14nm_Cmax.nxtgrd
OPERATING_TEMPERATURE : 125

* RCmax corner
TCAD_GRD_FILE : /pdk/starrc/saed14nm_RCmax.nxtgrd
OPERATING_TEMPERATURE : 125

* Cmin-Rmin
TCAD_GRD_FILE : /pdk/starrc/saed14nm_Cmin_Rmin.nxtgrd
OPERATING_TEMPERATURE : -40
```

### Multi-Corner Extraction (Single Run)

```
MULTI_CORNER_EXTRACTION : YES
TCAD_GRD_FILE_1         : /pdk/starrc/saed14nm_Cmax.nxtgrd
OPERATING_TEMPERATURE_1 : 125
NETLIST_FILE_1          : ./output/chip_top_Cmax.spef

TCAD_GRD_FILE_2         : /pdk/starrc/saed14nm_Cmin.nxtgrd
OPERATING_TEMPERATURE_2 : -40
NETLIST_FILE_2          : ./output/chip_top_Cmin.spef
```

### Field Solver Mode

```
* Enable 3D field solver for critical nets
FIELD_SOLVER_MODE  : YES
FIELD_SOLVER_NETS  : clk_root clk_trunk* critical_bus[*]
```

### Frequency-Dependent Extraction

```
FREQUENCY : 1e9    ;* 1 GHz
SKIN_EFFECT : YES
```

### Via Resistance

```
VIA_RESISTANCE      : YES
VIA_RESISTANCE_TYPE : DISTRIBUTED
```

---

## 10. Distributed / Parallel Extraction

### Multi-CPU Extraction

```
NUM_CORES    : 8
NUM_THREADS  : 8
```

### Distributed Extraction (Multi-Machine)

```
DISTRIBUTED  : YES
NUM_PARTS    : 16
HOST_FILE    : ./host_list.txt

* Host file format (host_list.txt):
* hostname1 num_cores
* hostname2 num_cores
```

### Memory Management

```
MEMORY_LIMIT      : 64000    ;* in MB
SWAP_DIRECTORY     : /scratch/starrc_swap
DISK_SPACE_LIMIT   : 200000  ;* in MB
```

### Runtime Options

```
RUNTIME_SUMMARY_FILE : ./reports/starrc_runtime.rpt
VERBOSE              : YES
LOG_FILE             : ./logs/starrc.log
```

---

## 11. Incremental Extraction

Extract only changed regions of the design.

```
INCREMENTAL_EXTRACTION      : YES
REFERENCE_EXTRACTION_DIR    : ./star_work_golden
ECO_NET_FILE                : ./eco_nets.txt
```

### ECO-Based Incremental

```
* List of nets modified in ECO
ECO_NET_FILE : ./eco_nets.txt

* Reference SPEF from previous run
REFERENCE_SPEF : ./output/chip_top_pre_eco.spef

* Incremental output
NETLIST_FILE : ./output/chip_top_post_eco.spef
```

### Partial Extraction

```
* Extract only a region
EXTRACTION_REGION : {100 200 500 600}  ;* llx lly urx ury

* Extract only specific blocks
SELECTED_CELLS : cpu_core io_ring
```

---

## 12. Resistance Extraction

### Basic Resistance Controls

```
EXTRACTION          : RC
VIA_RESISTANCE      : YES
CONTACT_RESISTANCE  : YES
```

### Advanced Resistance

```
RESISTANCE_EXTRACTION    : DISTRIBUTED  ;* or LUMPED
MIN_RESISTANCE           : 0.001        ;* Minimum resistance to report (ohms)
SHEET_RESISTANCE_OVERRIDE: M1 0.08 M2 0.04 M3 0.04
```

### Resistance for Specific Layers

```
* Override sheet resistance for specific layers
LAYER_RESISTANCE : M1 0.08
LAYER_RESISTANCE : M2 0.04
LAYER_RESISTANCE : M3 0.04
LAYER_RESISTANCE : M4 0.02
```

---

## 13. Inductance Extraction

```
EXTRACTION : RLC

* Inductance controls
INDUCTANCE_EXTRACTION    : YES
INDUCTANCE_FREQUENCY     : 1e9
INDUCTANCE_NETS          : clk* vco* io_data*
INDUCTANCE_GROUND_NETS   : VSS

* Partial inductance
PARTIAL_INDUCTANCE       : YES
```

---

## 14. Temperature and Process Variation

### OPERATING_TEMPERATURE

```
OPERATING_TEMPERATURE : <value_in_celsius>
```

```
OPERATING_TEMPERATURE : 125    ;* Worst case hot
OPERATING_TEMPERATURE : -40    ;* Best case cold
OPERATING_TEMPERATURE : 25     ;* Nominal
OPERATING_TEMPERATURE : 105    ;* Typical hot
```

### Process Variation

```
* Process corner is encoded in the nxtgrd file
* Use different nxtgrd files for different process corners

* Typical
TCAD_GRD_FILE : /pdk/starrc/saed14nm_typ.nxtgrd

* Slow (max C, max R)
TCAD_GRD_FILE : /pdk/starrc/saed14nm_Cmax.nxtgrd

* Fast (min C, min R)
TCAD_GRD_FILE : /pdk/starrc/saed14nm_Cmin.nxtgrd

* RCworst (max R, max C — worst delay)
TCAD_GRD_FILE : /pdk/starrc/saed14nm_RCmax.nxtgrd

* RCbest (min R, min C — best delay)
TCAD_GRD_FILE : /pdk/starrc/saed14nm_RCmin.nxtgrd
```

### Voltage-Dependent Extraction

```
OPERATING_VOLTAGE : 0.72
```

---

## 15. In-Design Extraction (FC/ICC2)

When running StarRC from within Fusion Compiler or IC Compiler II.

### FC In-Design Extraction

```tcl
# In FC shell:
set_app_options -name extract.starrc_cmd_file -value ./star_cmd
set_app_options -name extract.tech_file -value /pdk/starrc/saed14nm_1p9m_Cmax.nxtgrd

# Run extraction
update_timing -full

# Or explicit extraction
extract_rc
```

### ICC2 In-Design Extraction

```tcl
# In ICC2 shell:
set_starrc_options \
  -star_directory ./star_work \
  -grd_file /pdk/starrc/saed14nm_Cmax.nxtgrd \
  -coupling_threshold 3e-17 \
  -max_threads 8

# Run extraction
extract_rc -coupling_cap
```

---

## 16. Complete Command File Examples

### Example 1: Standard Digital Signoff (RC with Coupling)

```
* ============================================
* StarRC Command File — Digital Signoff
* Corner: SS/Cmax/125C
* ============================================

STAR_DIRECTORY         : ./star_work_ss_125c
BLOCK                  : chip_top

* Technology
TCAD_GRD_FILE          : /pdk/starrc/saed14nm_1p9m_Cmax.nxtgrd
MAPPING_FILE           : /pdk/starrc/saed14nm_1p9m.mapping

* Design input
TOP_DEF_FILE           : ./def/chip_top_post_route.def
LEF_FILE               : /pdk/lef/saed14nm_tech.lef \
                         /pdk/lef/saed14nm_rvt.lef \
                         /pdk/lef/saed14nm_hvt.lef \
                         /pdk/lef/saed14nm_lvt.lef \
                         /pdk/lef/sram_macros.lef \
                         /pdk/lef/io_cells.lef

* Power/ground
POWER_NETS             : VDD VDDH
GROUND_NETS            : VSS

* Extraction settings
EXTRACTION             : RCCC
MODE                   : 400
OPERATING_TEMPERATURE  : 125
COUPLE_TO_GROUND       : NO
COUPLING_ABS_THRESHOLD : 1e-17
COUPLING_REL_THRESHOLD : 0.01
VIA_RESISTANCE         : YES
REDUCTION              : NO_EXTRA_LOOPS

* Metal fill
METAL_FILL_GDS_FILE    : ./gds/metal_fill.gds
METAL_FILL_EXTRACTION  : FLOATING

* Output
NETLIST_FILE           : ./output/chip_top_ss_Cmax_125c.spef
NETLIST_FORMAT         : SPEF
NETLIST_COMPRESS_TYPE  : GZIP
XREF                   : YES

* Performance
NUM_CORES              : 8
```

### Example 2: Fast Corner (Min C, Cold)

```
* ============================================
* StarRC Command File — Fast Corner
* Corner: FF/Cmin/-40C
* ============================================

STAR_DIRECTORY         : ./star_work_ff_m40c
BLOCK                  : chip_top

TCAD_GRD_FILE          : /pdk/starrc/saed14nm_1p9m_Cmin.nxtgrd
MAPPING_FILE           : /pdk/starrc/saed14nm_1p9m.mapping

TOP_DEF_FILE           : ./def/chip_top_post_route.def
LEF_FILE               : /pdk/lef/saed14nm_tech.lef \
                         /pdk/lef/saed14nm_rvt.lef \
                         /pdk/lef/saed14nm_hvt.lef \
                         /pdk/lef/saed14nm_lvt.lef

POWER_NETS             : VDD VDDH
GROUND_NETS            : VSS

EXTRACTION             : RCCC
MODE                   : 400
OPERATING_TEMPERATURE  : -40
COUPLE_TO_GROUND       : NO
COUPLING_ABS_THRESHOLD : 1e-17
VIA_RESISTANCE         : YES
REDUCTION              : NO_EXTRA_LOOPS

NETLIST_FILE           : ./output/chip_top_ff_Cmin_m40c.spef
NETLIST_FORMAT         : SPEF
NETLIST_COMPRESS_TYPE  : GZIP
XREF                   : YES

NUM_CORES              : 8
```

### Example 3: Hierarchical Extraction

```
* ============================================
* StarRC — Hierarchical Extraction
* ============================================

STAR_DIRECTORY         : ./star_work_hier
BLOCK                  : chip_top

TCAD_GRD_FILE          : /pdk/starrc/saed14nm_1p9m_Cmax.nxtgrd
MAPPING_FILE           : /pdk/starrc/saed14nm_1p9m.mapping

TOP_DEF_FILE           : ./def/chip_top_post_route.def
LEF_FILE               : /pdk/lef/saed14nm_tech.lef \
                         /pdk/lef/saed14nm_rvt.lef

POWER_NETS             : VDD
GROUND_NETS            : VSS

EXTRACTION             : RCCC
MODE                   : 400
OPERATING_TEMPERATURE  : 125

* Hierarchical SPEF output
HIERARCHICAL_SPEF      : YES
HIERARCHICAL_SEPARATOR : /
NETLIST_FORMAT         : SPEF
NETLIST_COMPRESS_TYPE  : GZIP

NUM_CORES              : 16
DISTRIBUTED            : YES
NUM_PARTS              : 8
```

### Example 4: PG Extraction for IR Drop

```
* ============================================
* StarRC — Power Grid Extraction for RedHawk
* ============================================

STAR_DIRECTORY         : ./star_work_pg
BLOCK                  : chip_top

TCAD_GRD_FILE          : /pdk/starrc/saed14nm_1p9m_Cmax.nxtgrd
MAPPING_FILE           : /pdk/starrc/saed14nm_1p9m.mapping

TOP_DEF_FILE           : ./def/chip_top_post_route.def
LEF_FILE               : /pdk/lef/saed14nm_tech.lef

POWER_NETS             : VDD VDDH VDD_RET
GROUND_NETS            : VSS

* Extract PG nets only
NETS                   : VDD* VSS*
EXTRACTION             : RC
MODE                   : 400
OPERATING_TEMPERATURE  : 125
VIA_RESISTANCE         : YES

NETLIST_FILE           : ./output/chip_top_pg.spef
NETLIST_FORMAT         : SPEF

NUM_CORES              : 8
```

---

### Directive Quick Reference Table

| Directive | Typical Value | Description |
|---|---|---|
| `STAR_DIRECTORY` | `./star_work` | Working directory |
| `BLOCK` | `chip_top` | Top cell name |
| `TCAD_GRD_FILE` | `*.nxtgrd` | Process RC model file |
| `MAPPING_FILE` | `*.mapping` | Layer name mapping |
| `TOP_DEF_FILE` | `*.def` | Routed DEF |
| `LEF_FILE` | `*.lef` | Tech + cell LEF files |
| `GDS_FILE` | `*.gds` | GDSII layout file |
| `EXTRACTION` | `RCCC` | Extraction mode |
| `MODE` | `400` | Accuracy mode (200-800) |
| `OPERATING_TEMPERATURE` | `125` | Temperature in Celsius |
| `COUPLE_TO_GROUND` | `NO` | Keep coupling caps |
| `COUPLING_ABS_THRESHOLD` | `1e-17` | Min coupling cap (F) |
| `COUPLING_REL_THRESHOLD` | `0.01` | Min coupling fraction |
| `VIA_RESISTANCE` | `YES` | Include via R |
| `REDUCTION` | `NO_EXTRA_LOOPS` | Parasitic reduction |
| `NETLIST_FILE` | `*.spef` | Output file |
| `NETLIST_FORMAT` | `SPEF` | Output format |
| `NETLIST_COMPRESS_TYPE` | `GZIP` | Compress output |
| `NUM_CORES` | `8` | Parallel threads |
| `POWER_NETS` | `VDD` | Power net names |
| `GROUND_NETS` | `VSS` | Ground net names |
| `METAL_FILL_EXTRACTION` | `FLOATING` | Fill handling |

---

*End of StarRC Command Reference*
