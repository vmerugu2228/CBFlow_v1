# NDM Libraries: Synopsys New Data Model

## What Is NDM?

NDM (New Data Model) is Synopsys's unified library format used by Fusion Compiler, IC Compiler II, and other Synopsys implementation tools. It replaces the older Milkyway library format and provides a single container for all views of a cell: timing, physical, power, signal integrity, and electromigration data. NDM is designed for modern SoC implementation at advanced nodes where the volume and complexity of library data have grown substantially.

Understanding NDM is essential for any physical design engineer working with Synopsys tools, as it is the mandatory library format for Fusion Compiler and IC Compiler II.

## NDM Architecture

### Frame and Cell Views

NDM organizes data in a hierarchical structure:

```
NDM Library (top-level container)
  |
  +-- Frame (technology/library-level data)
  |     +-- Technology data (layers, rules)
  |     +-- Reference libraries
  |
  +-- Cell View 1 (one cell, e.g., BUFX4_SVT)
  |     +-- Design view (physical layout)
  |     +-- Timing view (Liberty data, embedded)
  |     +-- Frame view (cell-level physical abstraction)
  |     +-- Power view
  |     +-- SI view
  |
  +-- Cell View 2 (another cell)
  |     +-- ...
  |
  +-- ...
```

### Frame Views

A **frame** is the physical abstraction of a cell, analogous to the cell LEF but richer in content. Frame views contain:

- **Pin definitions:** Pin names, directions, shapes, and layers
- **Obstructions:** Routing blockages within the cell
- **Boundary:** Cell outline and placement site
- **Metal fill:** Internal metal fill patterns (optional)
- **Via access points:** Preferred via locations for pin connections
- **Power rail geometry:** VDD/VSS rail shapes and widths

Frame views serve the same role as cell LEF but in the native NDM binary format, which is faster to read and can carry more detailed information.

### Design Views

The **design view** contains the full transistor-level layout of the cell, equivalent to the GDS/OASIS representation but stored in NDM format. This is used for:

- Cell-internal optimization
- Fill insertion within cells
- Detailed DRC checking
- LVS verification

Not all NDM libraries include design views. Some provide only frame views for PnR use.

### Timing Views

NDM can embed Liberty timing data directly within the library. This eliminates the need for separate .db or .lib files, though standalone Liberty files are still supported.

When timing views are embedded:
- Timing data is accessed directly from the NDM, avoiding library loading inconsistencies
- Multiple PVT corners can be stored in the same NDM or in separate NDM libraries
- CCS/ECSM waveform data is included

### Power Views

Power views contain:
- Cell-level switching power tables
- Internal power (short-circuit) tables
- Leakage power values (state-dependent)
- Dynamic power characterization data

### Signal Integrity Views

SI views contain noise immunity data (bump curves) used for crosstalk noise analysis.

## Creating and Managing NDM Libraries

### Creating NDM from LEF/Liberty

The most common workflow is converting existing LEF and Liberty files into NDM format:

```tcl
# In Library Manager or lc_shell
create_workspace -technology /path/to/tech.tf my_workspace

# Read technology LEF
read_lef /path/to/tech.lef

# Read cell LEF
read_lef /path/to/stdcell.lef

# Read Liberty timing
read_lib /path/to/ss_0p72v_125c.lib

# Write NDM
write_ndm -library my_lib.ndm
```

### In Fusion Compiler

```tcl
# Specify NDM reference libraries
set_app_options -name lib.configuration.ndm_search_path \
  -value {/path/to/ndm_libs}

create_lib my_design.nlib \
  -technology /path/to/tech.ndm \
  -ref_libs {stdcell.ndm sram.ndm io.ndm}
```

### NDM vs. Milkyway

| Aspect | Milkyway | NDM |
|---|---|---|
| Format | Directory-based, multiple files | Single binary file |
| Tool support | ICC (legacy) | ICC2, Fusion Compiler |
| Views | CEL, FRAM, timing via .db | Unified: design, frame, timing |
| Performance | Slower for large designs | Optimized for large SoCs |
| Scalability | Limited | Handles multi-billion gate designs |
| Incremental update | Difficult | Supported natively |
| Compression | No | Built-in compression |

## NDM in the Physical Design Flow

### Library Preparation

Before starting implementation, prepare the NDM reference libraries:

1. **Technology NDM:** Contains the technology definition (layer stack, design rules, via definitions). Created from the foundry's technology file (.tf) or technology LEF.

2. **Standard Cell NDM:** Contains frame views (and optionally timing/design views) for all standard cells. One NDM per VT flavor or one combined NDM.

3. **Macro NDM:** Contains frame views for hard macros (SRAMs, PLLs, IO pads). Typically provided by the IP vendor.

```tcl
# Library setup in FC
set ref_libs [list \
  /libs/ndm/stdcell_svt.ndm \
  /libs/ndm/stdcell_lvt.ndm \
  /libs/ndm/stdcell_hvt.ndm \
  /libs/ndm/sram_256x32.ndm \
  /libs/ndm/pll.ndm \
  /libs/ndm/iopads.ndm \
]

create_lib design.nlib \
  -technology /libs/ndm/tech.ndm \
  -ref_libs $ref_libs
```

### Design Library (NLIB)

The design library (.nlib) is an NDM container that holds the design data (netlist, placement, routing) along with references to the cell libraries:

```
design.nlib/
  +-- Design data (netlist, floorplan, placement, routes)
  +-- References to: stdcell.ndm, sram.ndm, io.ndm
  +-- Technology from: tech.ndm
```

The .nlib is the working database throughout the PnR flow.

### Block-Level and Chip-Level Libraries

For hierarchical designs, each block has its own .nlib. The top-level chip references block abstracts:

```tcl
# Block-level: create abstract for use at chip level
create_abstract -read_only
save_block

# Chip-level: reference block abstracts
create_lib chip.nlib \
  -technology tech.ndm \
  -ref_libs {stdcell.ndm block_a.nlib block_b.nlib iopads.ndm}
```

## Milkyway to NDM Migration

Many organizations are migrating from ICC/Milkyway to ICC2/Fusion Compiler. The migration involves converting libraries:

### Converting Milkyway to NDM

```tcl
# In ICC2 or Library Manager
create_workspace -technology /path/to/tech.tf migration_ws

# Import Milkyway library
read_milkyway -library /path/to/mw_lib -cell_name {cell1 cell2 ...}

# Write as NDM
write_ndm -library output.ndm
```

### Migration Considerations

- **Verify pin equivalence:** Ensure all pins from Milkyway are correctly represented in NDM
- **Check obstruction translation:** Verify that routing blockages are preserved
- **Validate timing view binding:** If embedding timing, verify it matches the standalone .db
- **Test with a representative design:** Run a small block through the full flow with NDM libraries and compare QoR with the Milkyway-based flow

## Advanced NDM Features

### Multi-Voltage NDM

NDM supports cells with multiple power domains:

```tcl
# Level shifter with two voltage domains
# NDM stores the power pin associations and voltage ranges
```

### On-Disk Compression

NDM uses built-in compression to reduce disk space. A large standard cell library NDM may be 50-70% smaller than the equivalent Milkyway + LEF + Liberty combination.

### Incremental Updates

NDM supports partial updates without regenerating the entire library:

```tcl
# Update only the timing view for a specific corner
update_ndm -library my_lib.ndm \
  -timing_lib /path/to/updated.lib
```

### Library Validation

```tcl
# Validate NDM library integrity
check_library -ref_libs {stdcell.ndm}

# Report library contents
report_lib -cells
report_lib -timing_views
report_lib -physical_views
```

## Practical Recommendations

1. **Use NDM for all new projects on Synopsys tools.** Milkyway is legacy and will not receive new features or optimizations.

2. **Keep one NDM per library type.** Separate NDM files for standard cells (per VT), SRAMs, IO pads, and hard IP. This simplifies library management and updates.

3. **Include all necessary views.** Ensure NDM libraries contain frame views at minimum. Timing views embedded in NDM can simplify the flow but require careful version management.

4. **Validate NDM after creation.** Run `check_library` and `report_lib` to verify contents. Missing pins, incorrect obstructions, or mismatched timing can cause subtle PnR issues.

5. **Version-control NDM libraries.** NDM files are binary and can be large, but version control is essential for reproducibility. Use a library management system or at minimum track the source LEF/Liberty versions used to generate each NDM.

6. **Align NDM with signoff.** The NDM frame views must be consistent with the GDS used for signoff DRC/LVS. Any discrepancy means the PnR tool's view of the cell differs from the manufactured cell.

7. **Plan for NDM storage.** A complete set of NDM libraries for a 5nm design with multiple VT flavors, memory compilers, and hard IP can consume tens of gigabytes. Ensure adequate disk space on the compute farm.

NDM is the modern foundation for Synopsys-based physical design. Proper library preparation and management in NDM format is a prerequisite for efficient and reliable implementation with Fusion Compiler and ICC2.
