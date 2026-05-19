# GDS Signoff: GDSII Format, Verification, and Tapeout Data Preparation

## Overview

GDSII (Graphic Data System II) is the industry-standard binary file format for transferring integrated circuit layout data to the semiconductor foundry for mask generation. GDS signoff is the final stage of physical design where the layout data is verified, merged, and prepared for delivery. Understanding the GDS format, verification operations, and delivery requirements is essential for successful tapeout.

## GDSII Format

### Structure

GDSII is a binary stream format organized hierarchically:

- **Library**: The top-level container. Contains one or more structures (cells). A GDS file is a single library.
- **Structure (Cell)**: A named collection of geometric elements. Cells can contain other cells via references (instantiation).
- **Structure Reference (SREF)**: A single instance of another cell, with optional translation, rotation, and magnification.
- **Array Reference (AREF)**: A rectangular array of instances of another cell.
- **Elements**: The actual geometric data within a cell:
  - **Boundary**: A filled polygon on a specific layer.
  - **Path**: A wire with a defined width on a specific layer.
  - **Text**: A text label on a specific layer (for net names, pin labels).
  - **Node**: Electrical node information (rarely used in modern flows).
  - **Box**: A rectangular element (rarely used).

### Layer Numbering

Each geometric element is assigned a layer number (0-65535) and a datatype (0-65535). The combination of layer and datatype identifies the physical or logical layer.

```
Example layer mapping:
Metal1 drawing: layer 31, datatype 0
Metal1 pin:     layer 31, datatype 252
Via1 drawing:   layer 51, datatype 0
NWELL drawing:  layer 3,  datatype 0
```

### Format Limitations

- **Coordinates**: GDSII uses 32-bit integer coordinates. With nanometer-resolution databases, this limits the maximum die size to approximately 2.1 million database units in each dimension.
- **Hierarchy depth**: No formal limit, but tools may have practical limits.
- **File size**: GDSII files for modern SoCs can be 10-100+ GB. OASIS (Open Artwork System Interchange Standard) is a compressed alternative that can be 5-10x smaller.
- **Polygon vertex limit**: Maximum 8191 vertices per polygon (GDSII spec). Complex shapes must be fractured into simpler polygons.

## Layer Mapping

Layer mapping translates between the internal layer names used by the P&R tool and the layer/datatype numbers required in the GDSII file.

### Map File

A layer map file specifies the correspondence:

```
# P&R tool layer name -> GDS layer/datatype
M1        31  0
M1_PIN    31  252
VIA1      51  0
M2        32  0
M2_PIN    32  252
NWELL     3   0
PWELL     46  0
```

### Common Issues

- **Missing layers**: If a P&R layer is not in the map file, its geometry is silently dropped from the GDS output. This can cause LVS failures.
- **Incorrect mapping**: Mapping a drawing layer to the wrong GDS number causes DRC and LVS failures.
- **Text layer mapping**: Pin text labels must be on the correct text layer/datatype for LVS pin recognition.
- **Blockage layers**: P&R blockage layers should NOT be mapped to GDS output (they are implementation-only constructs).

### Verification

After GDS export, verify the layer map by:
1. Opening the GDS in a viewer (Calibre DESIGNrev, K-Layout, Laker) and checking that expected layers are present.
2. Running a layer listing utility to confirm all expected layers exist in the GDS.
3. Cross-referencing with the foundry's layer table.

## XOR Comparison

XOR (exclusive OR) comparison is a geometric operation that identifies differences between two versions of a layout. It is used to verify that ECO changes are correct and limited to the intended area.

### How XOR Works

Two GDS files (or two cells) are compared layer by layer. For each layer, the XOR operation produces geometry that exists in one version but not the other:

```
XOR result = (Layout_A AND NOT Layout_B) OR (Layout_B AND NOT Layout_A)
```

If the two layouts are identical, the XOR result is empty (no differences). Any remaining geometry in the XOR result represents a difference.

### Use Cases

1. **ECO verification**: After an ECO fix, XOR the pre-ECO and post-ECO GDS to confirm only the intended area was modified.
2. **Version comparison**: Compare two design iterations to understand what changed.
3. **IP verification**: Confirm that an IP block's GDS matches the reference version.
4. **Fill verification**: Compare pre-fill and post-fill GDS to verify that fill was added correctly (fill-only differences expected).

### Tools

```
# Calibre XOR:
calibre -xor gds_old.gds gds_new.gds -xor_rules xor_runset

# K-Layout XOR (open source):
klayout -b -rd old=gds_old.gds -rd new=gds_new.gds -r xor.rb
```

## Merge Operations

GDS merge combines multiple GDS files into a single, unified GDS file for tapeout delivery.

### When Merge Is Needed

- **IP integration**: Standard cell GDS, SRAM GDS, analog IP GDS, I/O cell GDS, and the top-level routing GDS must be merged.
- **Fill addition**: Metal fill GDS (generated by a separate fill tool) is merged with the design GDS.
- **Seal ring and pad frame**: These are often separate GDS files that must be merged into the final layout.

### Merge Flow

```
# Calibre merge:
calibre -merge top_route.gds stdcell.gds sram.gds io.gds fill.gds \
    -output final_chip.gds

# ICC2/FC GDS export includes hierarchy:
write_gds -output final_chip.gds -merge_files {sram.gds analog_ip.gds}
```

### Merge Considerations

- **Cell name conflicts**: If two GDS files contain cells with the same name but different geometry, the merge tool must resolve the conflict (typically by taking one version and issuing a warning).
- **Layer conflicts**: Ensure consistent layer numbering across all input GDS files.
- **Hierarchy**: Merged GDS should maintain proper hierarchy. Flatten only when necessary (flattening increases file size).
- **Coordinate system**: All input GDS files must use the same database unit (e.g., 1nm or 0.5nm).

## Boolean Operations

Boolean operations (AND, OR, NOT, XOR) on geometric shapes are used for various verification and data preparation tasks.

### Common Boolean Operations

- **AND (intersection)**: Produces geometry where two layers overlap. Used to identify areas where two layers coexist (e.g., gate = poly AND active).
- **OR (union)**: Combines geometry from two layers. Used to merge related layers.
- **NOT (subtraction)**: Produces geometry from layer A that does not overlap with layer B. Used to identify areas of one layer outside another.
- **XOR**: Produces geometry that exists in exactly one of the two layers. Used for comparison (see above).
- **SIZING**: Grows or shrinks geometry by a specified amount. Used for generating derived layers (e.g., well boundary + 0.5um for guard ring check).

### Application in Signoff

Boolean operations are embedded in DRC/LVS rule decks to create derived layers. For example:

```
# Calibre rule deck snippet:
GATE = POLY AND ACTIVE          // Gate = poly where it crosses active
NMOS_GATE = GATE NOT NWELL      // NMOS gates = gates outside NWELL
PMOS_GATE = GATE AND NWELL      // PMOS gates = gates inside NWELL
```

PD engineers rarely write Boolean rules themselves but must understand them to debug DRC/LVS issues.

## Fill Verification

Metal fill (dummy metal) must be verified for compliance with density rules and absence of unintended connectivity.

### Fill Verification Checks

1. **Density compliance**: After fill insertion, re-run density checks to confirm that all windows meet minimum and maximum density requirements.
2. **No shorts**: Fill shapes must not create short circuits to signal or power nets. Run DRC spacing checks on filled layers.
3. **No antenna violations**: Fill shapes connected to signal nets (through accidental shorts) could create antenna violations. Fill should be electrically floating.
4. **Fill-to-signal spacing**: Fill shapes must maintain minimum spacing to active signal routes.
5. **Fill pattern quality**: Regular fill patterns are preferred for CMP uniformity. Random or irregular fill can create CMP variations.

## GDS Delivery to Foundry

### Tapeout Package Contents

A typical tapeout delivery includes:
- **Final GDS/OASIS**: The complete chip layout, merged and verified.
- **Layer map**: Documentation of layer/datatype assignments.
- **Cell list**: List of all cells in the hierarchy.
- **DRC/LVS/ERC reports**: Clean verification reports (or waiver documentation).
- **Density reports**: Metal and via density compliance reports.
- **Checksum**: MD5 or SHA checksum for data integrity verification.
- **Readme/cover sheet**: Design name, process node, metal stack option, die size, and contact information.

### Data Integrity

- Generate checksums for the final GDS file and verify after transfer.
- Use secure file transfer (SFTP, dedicated foundry portal).
- Verify file size matches expected (a truncated file is a common transfer error).
- Some foundries require specific GDS export settings (e.g., specific database unit, specific precision).

### Frame Generation

Some foundries require a die frame (also called die seal or scribe line) to be included in the GDS. The frame defines the die boundary and includes:
- Scribe line structures for die singulation.
- Alignment marks for lithography.
- Process control monitors (PCM) in the scribe line.
- Die identification (chip name, revision).

The frame GDS is typically provided by the foundry and merged with the design GDS.

## Best Practices

- Always regenerate GDS from the P&R database rather than editing GDS directly.
- Run a final DRC/LVS on the merged GDS (not just the individual components).
- Verify that the GDS hierarchy matches expectations using a cell listing tool.
- Keep all intermediate GDS files versioned for rollback capability.
- Document the exact tool versions and settings used for GDS generation.
- Allow adequate time for the final GDS merge, verification, and transfer (typically 2-5 days for a large SoC).

GDS signoff is the culmination of the physical design effort. Meticulous attention to format correctness, layer mapping, merge integrity, and verification completeness ensures a successful handoff to the foundry.
