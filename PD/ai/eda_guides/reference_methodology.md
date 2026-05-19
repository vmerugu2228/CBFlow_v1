# Reference Methodology: RM Flows, Customization, and Best Practices

## Overview

A Reference Methodology (RM) is a pre-built, vendor-provided design flow that implements industry best practices for taking a design from RTL to GDSII. RMs are developed by EDA vendors (primarily Synopsys and Cadence) in collaboration with foundries to provide a validated, optimized starting point for physical design projects. Understanding RM structure, customization mechanisms, and best practices is essential for PD engineers who want to leverage these flows effectively.

## What is a Reference Methodology?

An RM is a collection of scripts, configuration files, and documentation that automates a specific portion of the design flow using a particular EDA tool. Key characteristics:

- **Vendor-provided**: Developed and maintained by the EDA vendor's methodology team.
- **Foundry-validated**: Tested against foundry design rules and process-specific requirements.
- **Best practices**: Embodies the vendor's recommended tool settings and flow sequencing.
- **Customizable**: Designed to be extended and modified for project-specific requirements.
- **Versioned**: Updated with each tool release to incorporate new features and fixes.

### Why Use an RM?

1. **Reduced setup time**: Starting from an RM eliminates weeks of script development.
2. **Known-good settings**: App options and flow sequences have been validated by the vendor and foundry.
3. **Vendor support**: When using an RM, the vendor's support team can more easily debug issues.
4. **Consistent methodology**: Ensures all team members follow the same flow.
5. **Incremental updates**: New tool versions come with updated RMs that capture new best practices.

### Limitations of RMs

- **Generic**: RMs are designed for general-purpose flows. Project-specific needs require customization.
- **Opinionated**: RMs make choices that may not be optimal for every design (e.g., optimization effort level, CTS strategy).
- **Vendor-locked**: RMs are specific to one tool. Switching vendors requires a different RM.
- **Learning curve**: Understanding the RM structure well enough to customize it effectively takes time.

## Fusion Compiler Reference Methodology (FC-RM)

The FC-RM is Synopsys' reference flow for Fusion Compiler. It covers the complete synthesis-to-signoff flow in FC's unified environment.

### FC-RM Directory Structure

A typical FC-RM installation contains:

```
fc_rm/
  rm_setup/
    fc_setup.tcl              # Top-level setup: design name, libraries, constraints
    fc_dp_setup.tcl           # Design planning (floorplan) setup
    header_fc.tcl             # Common header sourced by all scripts
  rm_fc_scripts/
    init_design.tcl           # Read design, apply constraints, create Milkyway
    compile.tcl               # Synthesis (compile_fusion)
    place_opt.tcl             # Placement and optimization
    clock_opt_cts.tcl         # Clock tree synthesis
    clock_opt_opto.tcl        # Post-CTS optimization
    route_auto.tcl            # Detail routing
    route_opt.tcl             # Post-route optimization
    chip_finish.tcl           # Metal fill, filler cells, final checks
    write_data.tcl            # Export GDS, netlist, SPEF, reports
  rm_icc2_scripts/            # ICC2-specific scripts (if FC-RM includes ICC2 mode)
  rm_pt_scripts/              # PrimeTime signoff scripts
  Makefile                    # Make-based flow execution
  README.fc_rm.txt            # Documentation
```

### Key FC-RM Scripts

**fc_setup.tcl**: The primary configuration file. All design-specific settings are defined here:

```tcl
# Design name and top module
set DESIGN_NAME "my_soc_top"
set DESIGN_REF_DATA "rtl/my_soc_top.v"

# Technology libraries
set TECH_FILE "/lib/tech/saed14_1p9m.tf"
set REFERENCE_LIBRARY "/lib/std_cells/saed14hvt /lib/std_cells/saed14rvt /lib/sram"

# Timing constraints
set CONSTRAINT_FILES "constraints/my_soc.sdc"

# Multi-mode multi-corner setup
set MMMC_FILE "constraints/mmmc_setup.tcl"

# UPF (for multi-voltage designs)
set UPF_FILE "upf/my_soc.upf"
```

**place_opt.tcl**: Placement and optimization. Uses FC app_options to control behavior:

```tcl
# Source common header
source rm_setup/header_fc.tcl

# Application options for placement
set_app_options -name place_opt.flow.optimize_icgs -value true
set_app_options -name place_opt.flow.enable_ccd -value true
set_app_options -name place.coarse.max_density -value 0.70

# Run placement
place_opt

# Report results
report_timing -max_paths 50
report_qor
```

## PrimeTime Reference Methodology (PT-RM)

The PT-RM provides signoff timing analysis scripts.

### PT-RM Structure

```
pt_rm/
  rm_setup/
    pt_setup.tcl              # Design, libraries, MMMC configuration
  rm_pt_scripts/
    pt.tcl                    # Main PrimeTime analysis script
    pt_dmsa.tcl               # Distributed multi-scenario analysis
  README.pt_rm.txt
```

### PT-RM Flow

```tcl
# pt.tcl outline:
source rm_setup/pt_setup.tcl

# Read design
read_verilog ${NETLIST}
link_design ${DESIGN_NAME}

# Read parasitics
read_parasitics ${SPEF_FILE}

# Read constraints
read_sdc ${SDC_FILE}

# Configure OCV
set_app_options -name time.pocvm_enable_analysis -value true

# Enable SI
set_app_options -name si.enable_analysis -value true

# Update timing and report
update_timing -full
report_timing -max_paths 100 -slack_lesser_than 0
report_constraint -all_violators
```

## How to Customize an RM

### Customization Principles

1. **Never modify RM scripts directly**: Create override files that source the RM scripts and add customizations before or after. This preserves the ability to update the RM without losing customizations.
2. **Use the hook mechanism**: Most RMs provide pre/post hooks at major flow steps.
3. **Override through variables**: RMs use TCL variables for configuration. Override these in your setup file.
4. **Document all customizations**: Track what was changed and why.

### Hook Mechanism

FC-RM and ICC2-RM provide hook points where custom TCL scripts can be inserted:

```tcl
# In fc_setup.tcl, define custom hooks:
set PRE_PLACE_OPT_SCRIPT  "custom/pre_place_opt.tcl"
set POST_PLACE_OPT_SCRIPT "custom/post_place_opt.tcl"
set PRE_CTS_SCRIPT        "custom/pre_cts.tcl"
set POST_CTS_SCRIPT       "custom/post_cts.tcl"
set PRE_ROUTE_SCRIPT      "custom/pre_route.tcl"
set POST_ROUTE_SCRIPT     "custom/post_route.tcl"
```

The RM scripts check for these variables and source the custom scripts at the appropriate point:

```tcl
# Inside place_opt.tcl (RM script):
if {[info exists PRE_PLACE_OPT_SCRIPT] && [file exists $PRE_PLACE_OPT_SCRIPT]} {
    puts "INFO: Sourcing pre-placement hook: $PRE_PLACE_OPT_SCRIPT"
    source $PRE_PLACE_OPT_SCRIPT
}

place_opt

if {[info exists POST_PLACE_OPT_SCRIPT] && [file exists $POST_PLACE_OPT_SCRIPT]} {
    puts "INFO: Sourcing post-placement hook: $POST_PLACE_OPT_SCRIPT"
    source $POST_PLACE_OPT_SCRIPT
}
```

### Common Customizations

1. **Additional timing constraints**: Add project-specific false paths, multicycle paths, or clock definitions in a hook script.
2. **Floorplan loading**: Source a pre-built floorplan DEF in the pre-placement hook.
3. **NDR rules**: Define non-default routing rules for clock or critical signal nets.
4. **Power grid**: Custom power grid creation scripts (the RM typically provides a basic grid; production designs need customized grids).
5. **Optimization directives**: Add specific `set_app_options` commands to tune optimization behavior.
6. **Reporting**: Add custom QoR reports and metric extraction.

## App_Options Methodology

Synopsys tools (FC, ICC2, PT) use app_options (application options) to control tool behavior. App_options replace the older `set_*` variable mechanism.

### App_Options Basics

```tcl
# Set an app_option
set_app_options -name place.coarse.max_density -value 0.65

# Query an app_option
get_app_options -name place.coarse.max_density

# List all app_options in a category
report_app_options place.*

# Reset to default
reset_app_options -name place.coarse.max_density
```

### Key App_Option Categories

| Category | Controls |
|---|---|
| `place.*` | Placement behavior (density, effort, congestion) |
| `clock_opt.*` | CTS and clock optimization |
| `route.*` | Routing (via rules, DRC, antenna, NDR) |
| `opt.*` | Optimization (effort, leakage, area) |
| `time.*` | Timing analysis (derate, OCV, SI) |
| `extract.*` | In-design extraction settings |
| `power.*` | Power optimization settings |

### App_Options Best Practices

- Document every non-default app_option with a comment explaining why it was changed.
- Group app_option settings by flow stage for readability.
- Track app_option changes across iterations to understand their impact on QoR.
- Use `report_app_options -non_default` to list all customized settings.

## Flow Variables

RMs use flow variables to control high-level flow decisions (e.g., enable/disable features, select strategies).

```tcl
# Common FC-RM flow variables:
set ENABLE_CLOCK_GATING    true    ;# Enable clock gating optimization
set ENABLE_POWER_OPT       true    ;# Enable multi-Vt power optimization
set ENABLE_CCD             true    ;# Enable concurrent clock and data optimization
set ENABLE_SI              true    ;# Enable signal integrity analysis
set ENABLE_DFT             false   ;# Enable DFT insertion (if not done upstream)
set FLOORPLAN_FILE         "fp/chip.def"  ;# Pre-built floorplan
set STREAM_OUT_FORMAT      "gds"   ;# Output format: gds or oasis
```

## Building on Top of the RM

Production flows typically wrap the RM with a project-specific framework:

```
project_flow/
  setup/
    project_setup.tcl         # Project-specific overrides
    mmmc_config.tcl           # MMMC corner definitions
    block_config.tcl          # Per-block configuration
  hooks/
    pre_place_opt.tcl         # Custom pre-placement actions
    post_route_opt.tcl        # Custom post-route optimization
    custom_pg.tcl             # Power grid creation
  rm/
    fc_rm/                    # Unmodified RM (symlink or copy)
  Makefile                    # Project Makefile wrapping RM Makefile
  run.sh                      # Top-level run script
```

This layered approach keeps the RM pristine, allows easy RM upgrades, and separates project-specific customization from vendor-provided methodology.

## RM Updates and Version Management

- RMs are released with each major tool version (e.g., FC-RM 2024.09).
- Read the RM release notes to understand changes between versions.
- Test new RM versions on a representative block before deploying project-wide.
- Maintain a diff between your customizations and the RM defaults to simplify migration to new RM versions.

Reference methodologies are the foundation of professional physical design workflows. PD engineers who master RM structure and customization can rapidly deploy optimized flows while maintaining the flexibility to address project-specific challenges.
