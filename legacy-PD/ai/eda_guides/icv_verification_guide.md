# Synopsys IC Validator (ICV) Verification Guide

## Overview

IC Validator (ICV) is Synopsys's physical verification tool for DRC, LVS, metal fill, and density checking. ICV is tightly integrated with the Synopsys implementation flow (Fusion Compiler, IC Compiler II) and provides signoff-quality verification with native distributed processing capabilities. ICV uses a rule-based architecture with runsets written in ICV's own format or compiled from Synopsys SVRF-compatible syntax.

## ICV Architecture

### Key Features

- **Native distributed processing:** Scales across multiple CPUs/machines automatically.
- **Hierarchical verification:** Processes the design hierarchically, dramatically reducing runtime for large designs.
- **Integration with FC/ICC2:** Can run in-design verification within the PnR tool.
- **Foundry-certified rule decks:** Available from major foundries (TSMC, Samsung, Intel, GF).
- **GDSII and OASIS support:** Reads both layout formats natively.

### ICV vs. Calibre

| Feature | ICV | Calibre |
|---------|-----|---------|
| Vendor | Synopsys | Siemens |
| Rule format | ICV runset | SVRF/TVF |
| Distributed processing | Native | Requires Calibre MT |
| Integration | FC/ICC2 native | Universal |
| Market position | Growing | Established standard |

## DRC with ICV

### DRC Runset Structure

ICV DRC runsets define geometric checks using a rule-based language. Foundries provide certified runsets for each process node.

```
// Example ICV DRC rule structure (simplified)
rule_deck {
    layer_map {
        M1_drw = 30:0
        M1_pin = 30:2
        VIA1   = 31:0
        M2_drw = 32:0
    }

    // Minimum width check
    rule M1_MIN_WIDTH {
        internal(M1_drw, < 0.040, "M1 minimum width violation")
    }

    // Minimum spacing check
    rule M1_MIN_SPACE {
        external(M1_drw, M1_drw, < 0.040, "M1 minimum spacing violation")
    }

    // Enclosure check
    rule VIA1_ENC {
        enclosure(VIA1, M1_drw, < 0.010, "VIA1 enclosure by M1 violation")
    }
}
```

### Running ICV DRC

```bash
# Command-line invocation
icv -i top.gds \
    -c top_cell \
    -r drc_runset.rs \
    -f GDSII \
    -o drc_results \
    -dp 16 \              # Distributed processing on 16 CPUs
    -D "METAL_FILL=1" \   # Define variables
    -log drc_run.log
```

### ICV DRC in Fusion Compiler / ICC2

```tcl
# In-design DRC check
set_app_options -name signoff.check_drc.runset -value drc_runset.rs
set_app_options -name signoff.check_drc.max_errors_per_rule -value 1000

# Run DRC
signoff_check_drc

# Review results
report_drc_violations -summary
report_drc_violations -rule "M1_MIN_SPACE" -max_violations 50
```

### DRC Results Viewing

ICV generates results in its native database format. View results using:

- **IC Validator Workbench (ICVWB):** GUI-based violation browser with layout overlay.
- **Galaxy Custom Designer:** Layout editor with DRC results integration.
- **FC/ICC2 GUI:** View DRC markers directly in the PnR environment.

```tcl
# In FC/ICC2: load and view DRC results
open_drc_error_data -file drc_results/top.drc_errors
gui_show_drc_errors
```

## LVS with ICV

### LVS Flow

ICV LVS extracts a circuit from the layout and compares it against the source netlist.

```bash
# Command-line LVS invocation
icv -i top.gds \
    -c top_cell \
    -r lvs_runset.rs \
    -f GDSII \
    -s top_routed.v \       # Source netlist
    -sf VERILOG \            # Source format
    -o lvs_results \
    -dp 16 \
    -log lvs_run.log
```

### LVS Runset Components

An ICV LVS runset contains:

1. **Layer definitions:** Map GDS layer numbers to logical layer names.
2. **Device recognition rules:** Define how transistors, resistors, and other devices are formed from geometric layers.
3. **Connectivity extraction:** Rules for tracing metal connectivity through vias and contacts.
4. **Comparison directives:** How to match extracted circuit against source netlist.
5. **Property checking:** Verify device parameters (W/L, resistance values).

### ICV LVS in FC/ICC2

```tcl
# In-design LVS
set_app_options -name signoff.check_lvs.runset -value lvs_runset.rs
set_app_options -name signoff.check_lvs.reference_netlist -value top_routed.v

signoff_check_lvs

# Review results
report_lvs_violations -summary
```

### LVS Debug

```bash
# Open LVS results in ICVWB
icvwb -lvs lvs_results/top.lvs_results
```

In the ICVWB LVS debug environment:
- View matched/unmatched instances and nets
- Highlight unmatched components in the layout
- Trace connectivity to find opens and shorts
- Cross-probe between schematic and layout views

## Metal Fill with ICV

### Density Fill Insertion

ICV can insert metal fill to meet foundry density requirements.

```bash
# Metal fill generation
icv -i top.gds \
    -c top_cell \
    -r fill_runset.rs \
    -f GDSII \
    -o fill_results \
    -dp 16 \
    -log fill_run.log
```

### Fill Runset Configuration

```
// Fill rule example (simplified)
fill_rules {
    layer M1 {
        min_density: 0.20
        max_density: 0.80
        window_size: 50.0    // um
        step_size:   25.0    // um

        fill_shape: rectangle
        fill_width:  0.080
        fill_height: 0.080
        fill_space_x: 0.080
        fill_space_y: 0.080

        // Keep fill away from signal nets
        keepout_signal: 0.050
        keepout_power:  0.020
    }
}
```

### Fill in FC/ICC2

```tcl
# Insert metal fill using ICV-based fill
set_app_options -name signoff.create_metal_fill.runset -value fill_runset.rs

# Generate fill
signoff_create_metal_fill

# Verify density after fill
signoff_check_drc -type density
```

### Fill Considerations

- **Timing impact:** Floating fill increases coupling capacitance, affecting SI. Run extraction with fill for accurate timing.
- **Grounded fill:** Connecting fill to VDD/VSS reduces coupling but increases ground capacitance.
- **Fill exclusion zones:** Keep fill away from sensitive analog or RF regions.
- **Progressive fill:** Insert fill iteratively, checking density after each pass.

## Density Checking

```bash
# Density check
icv -i top_filled.gds \
    -c top_cell \
    -r density_runset.rs \
    -f GDSII \
    -o density_results \
    -dp 16
```

### Density Rules

Foundries specify density requirements per layer:

| Requirement | Typical Value |
|-------------|--------------|
| Minimum metal density | 20-30% |
| Maximum metal density | 75-85% |
| Density window size | 50-100 um |
| Density step size | 25-50 um |
| Density uniformity | < 15-20% variance |

## Distributed Processing

ICV's native distributed processing is one of its key advantages. It automatically partitions the design and distributes work across available CPUs.

### Configuration

```bash
# Local multi-threaded
icv -dp 32 ...    # Use 32 local threads

# Distributed across machines
icv -dp_config dp_config.txt ...

# dp_config.txt
machine host1 cpus=16
machine host2 cpus=16
machine host3 cpus=16
```

### Runtime Scaling

Typical scaling for ICV DRC with distributed processing:

| CPUs | Relative Runtime |
|------|-----------------|
| 1 | 1.0x (baseline) |
| 4 | 0.30x |
| 16 | 0.10x |
| 32 | 0.06x |
| 64 | 0.04x |

Scaling efficiency decreases beyond 32-64 CPUs due to communication overhead and partitioning granularity.

## Antenna Checking

```bash
# Antenna check (often part of DRC runset)
icv -i top.gds \
    -c top_cell \
    -r antenna_runset.rs \
    -f GDSII \
    -o antenna_results \
    -dp 16
```

### Antenna Fix Strategies

1. **Diode insertion:** Add antenna protection diodes near gates with high antenna ratios.
2. **Layer hopping:** Route through higher layers to break the antenna ratio accumulation.
3. **Bridge routing:** Insert a short bridge on a higher layer to break the lower-layer antenna.

## Common Issues and Fixes

**Issue: ICV DRC results differ from Calibre results**
- Verify both tools use the same foundry rule deck version.
- Check layer mapping — GDS layer number assignments must match.
- Some rule implementations differ between ICV and Calibre — review the specific rules that disagree.
- Run on a small test case to isolate the discrepancy.

**Issue: LVS fails with "unmatched instances"**
- Check for missing cells in the GDS (standard cells, macros).
- Verify that the source netlist includes all leaf cells.
- Ensure power/ground net names match between layout and netlist.

**Issue: Metal fill causing new DRC violations**
- Fill spacing to signal nets may be too small. Increase `keepout_signal` in fill rules.
- Fill shapes may violate minimum area or minimum spacing rules. Adjust fill dimensions.
- Run DRC after fill insertion to catch fill-induced violations.

**Issue: Very long DRC runtime (>24 hours)**
- Increase distributed processing resources (more CPUs/machines).
- Use hierarchical mode — flat DRC on large designs is impractical.
- Check for pathological rules that cause excessive computation (e.g., wide-range spacing rules).
- Reduce max_errors_per_rule to avoid spending time reporting thousands of violations for one rule.

**Issue: Density violations persist after fill insertion**
- Check fill coverage — some regions may have fill exclusion zones that prevent achieving minimum density.
- Verify fill window and step size match the density rule requirements.
- Run iterative fill: fill, check density, add more fill in sparse areas.

## Best Practices

1. **Run in-design DRC/LVS** in FC/ICC2 during the implementation flow — catch violations early.
2. **Use distributed processing** — ICV scales well and the runtime reduction is substantial.
3. **Hierarchical verification** for designs > 10M instances — flat mode is prohibitively slow.
4. **Synchronize rule deck versions** with the foundry — always use the latest certified version.
5. **Automate the verification flow** — script ICV runs as part of the tapeout checklist.
6. **Track DRC count trends** — violations should decrease monotonically as the flow progresses.
7. **Run fill before final DRC** — density is a DRC rule and must be met for tapeout.
8. **Cross-validate with a second tool** on a critical block — if both ICV and Calibre agree, confidence is high.
9. **Keep fill away from analog/RF blocks** — use fill exclusion regions.
10. **Document all waivers** with foundry approval — never ship a design with undocumented DRC waivers.
