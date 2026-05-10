# CBFlow Run Makefile User Guide

**Version:** 1.0.0
**Location:** `<run_directory>/Makefile` (auto-generated per run)

This guide documents all available commands in the CBFlow Run Makefile, which is auto-generated for each Physical Design flow run and provides commands for executing and managing the flow.

---

## Table of Contents

1. [Overview](#overview)
2. [Run Directory Structure](#run-directory-structure)
3. [Main Flow Targets](#main-flow-targets)
4. [Stage Targets](#stage-targets)
5. [MMMC Scenario Commands](#mmmc-scenario-commands)
6. [Release Management](#release-management)
7. [Node Management](#node-management)
8. [Makefile Regeneration](#makefile-regeneration)
9. [Flow-Specific Commands](#flow-specific-commands)
10. [Clean Commands](#clean-commands)
11. [Workflow Examples](#workflow-examples)
12. [Troubleshooting](#troubleshooting)

---

## Overview

The Run Makefile is auto-generated for each flow run and provides:

- Flow execution targets (stage-by-stage or complete flow)
- MMMC (Multi-Mode Multi-Corner) scenario management
- Release/deliverable creation
- Dynamic node management
- Quality of Results (QOR) reporting

### Supported Flow Types

| Flow Type | Description |
|-----------|-------------|
| SYNTH | Synthesis flow |
| FP | Floorplanning flow |
| PNR | Place and Route flow |
| STA | Static Timing Analysis |
| LEC | Logical Equivalence Checking |
| EMIR | Electromigration/IR drop analysis |
| PV | Physical Verification |
| ECO | Engineering Change Order |
| CLP | Clock Low Power |
| POPT | Power Optimization |
| FCFP | Full Chip Floorplan |
| SYNTH_PNR | Unified Synthesis + Place & Route |

---

## Run Directory Structure

Each run directory contains:

```
P0_run_<FLOW>_<run_name>/
├── Makefile                 # Run Makefile (this file)
├── .make/                   # Stage-specific make includes
│   ├── inputs.mk           # Inputs stage rules
│   ├── <stage>.mk          # Stage rules (varies by flow)
│   └── release_data.mk     # Release stage rules
├── .stamps/                 # Completion stamps
│   ├── inputs.stamp
│   └── <stage>.stamp
├── work/                    # Working directories
│   └── <stage>/            # Stage-specific work
├── logs/                    # Log files
├── .run.cbflow.tcl          # Run configuration
└── user_config_*.tcl        # User configuration
```

---

## Main Flow Targets

### `make help`

Display all available targets for the current flow.

```bash
make help
```

**Output Example (SYNTH):**
```
CBFlow SYNTHESIS Makefile
Available targets:
  all           - Run complete synthesis flow
  inputs        - Run inputs stage
  synthesis     - Run synthesis stage
  export_data   - Run export_data stage
  release_data  - Run release_data stage
  clean         - Clean all generated files
  help          - Show this help
```

### `make all`

Execute the complete flow from inputs to release.

```bash
make all
```

**What It Does:**
1. Executes all stages in dependency order
2. Creates stamp files for completed stages
3. Reports success/failure for each stage

**Stage Dependencies (Example - SYNTH):**
```
inputs → synthesis → export_data → release_data
```

**Stage Dependencies (Example - PNR):**
```
inputs → place → cts → cts_opt → route → pro → signoff → export_data → release_data
```

---

## Stage Targets

Each flow has specific stages. Run individual stages:

### Common Stages (All Flows)

```bash
make inputs         # Input validation and preparation
make export_data    # Export flow database
make release_data   # Release deliverables
```

### SYNTH Flow Stages

```bash
make inputs         # Input preparation
make synthesis      # Run synthesis
make export_data    # Export synthesis database
make release_data   # Release synthesis deliverables
```

### PNR Flow Stages

```bash
make inputs         # Input preparation (netlist, SDC, DEF, UPF, library)
make place          # Standard cell placement
make cts            # Clock tree synthesis
make cts_opt        # Clock tree optimization
make route          # Global and detailed routing
make pro            # Post-route optimization
make signoff        # Final design sign-off
make export_data    # Export PNR database
make release_data   # Release PNR deliverables
```

### FP Flow Stages

```bash
make inputs         # Input preparation
make floorplan      # Floorplanning
make export_data    # Export floorplan database
make release_data   # Release floorplan deliverables
```

### Stage Stamps

Each stage creates a stamp file when completed:

```bash
.stamps/inputs.stamp
.stamps/synthesis.stamp
.stamps/place.stamp
# etc.
```

To re-run a stage, delete its stamp file:

```bash
rm .stamps/place.stamp
make place
```

---

## MMMC Scenario Commands

Multi-Mode Multi-Corner scenario management.

### `make mmmc_corners`

Show available MMMC scenarios by type.

```bash
make mmmc_corners TYPE=<type>
```

**Parameters:**
| Type | Description |
|------|-------------|
| setup | Setup timing scenarios |
| hold | Hold timing scenarios |
| power | Power analysis scenarios |
| timing | All timing scenarios |
| all | All available scenarios |

**Examples:**
```bash
make mmmc_corners TYPE=setup    # Show setup scenarios
make mmmc_corners TYPE=hold     # Show hold scenarios
make mmmc_corners TYPE=power    # Show power scenarios
make mmmc_corners TYPE=timing   # Show timing scenarios
make mmmc_corners TYPE=all      # Show all scenarios
```

### `make mmmc_nodes`

Show MMMC node assignments for the flow.

```bash
make mmmc_nodes [NODE=<node_name>]
```

**Examples:**
```bash
# Show all node assignments
make mmmc_nodes

# Show specific node assignment
make mmmc_nodes NODE=place
make mmmc_nodes NODE=cts
```

---

## Release Management

### `make release`

Create a release package with deliverables.

```bash
make release TAG=<tag_name> TYPE=<release_type> [NOTES="<notes>"] [NODE=<node>] [DIR=<dir>] [MILESTONE=<milestone>]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| TAG | Yes | Release tag/version name |
| TYPE | Yes | Release type (see table below) |
| NOTES | No | Release notes |
| NODE | No | Source node name |
| DIR | No | Custom source directory |
| MILESTONE | No | Exit milestone |

**Available Release Types:**

| Type | Description |
|------|-------------|
| synthesis | Synthesis deliverables |
| pnr_floorplan | PNR floorplan deliverables |
| pnr_placed | PNR placed design deliverables |
| pnr_cts | PNR clock tree synthesis deliverables |
| pnr_postroute | PNR post-route deliverables |
| pnr_signoff | PNR signoff deliverables |
| signoff | Final signoff deliverables |

**Available Exit Milestones:**

| Milestone | Description |
|-----------|-------------|
| FP_EXIT | Floorplan exit milestone |
| PLACE_EXIT | Placement exit milestone |
| CTS_EXIT | CTS exit milestone |
| PRO_EXIT | Post-route optimization exit milestone |
| BTO | Backend tapeout milestone |
| MTO | Mask tapeout milestone |

**Examples:**
```bash
# Basic release
make release TAG=v1.0 TYPE=synthesis

# Release with notes
make release TAG=v2.0 TYPE=synthesis NOTES="Final synthesis"

# Release from specific node
make release TAG=v3.0 TYPE=synthesis NODE=synthesis1

# Release from custom directory
make release TAG=v4.0 TYPE=synthesis DIR=work/SYNTH/synthesis_custom

# Release with milestone
make release TAG=v5.0 TYPE=synthesis MILESTONE=SYNTH_EXIT

# PNR post-route release
make release TAG=v6.0 TYPE=pnr_postroute MILESTONE=PRO_EXIT

# Tapeout release
make release TAG=tapeout TYPE=signoff MILESTONE=BTO NOTES="Backend tapeout"
```

---

## Node Management

Dynamically manage nodes within a run.

### `make add_node`

Add a new custom node to the flow.

```bash
make add_node NODE=<node_name> TYPE=<node_type> [DEP=<dependency>]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| NODE | Yes | Name for the new node |
| TYPE | Yes | Node type (must match existing type) |
| DEP | No | Dependency node name |

**Examples:**
```bash
make add_node NODE=floorplan2 TYPE=floorplan DEP=inputs
make add_node NODE=synthesis2 TYPE=synthesis DEP=synthesis1
make add_node NODE=custom_cts TYPE=cts DEP=place
```

### `make delete_node`

Delete a custom node from the flow.

```bash
make delete_node NODE=<node_name>
```

**Example:**
```bash
make delete_node NODE=floorplan2
```

### `make list_nodes`

List all available nodes in the flow.

```bash
make list_nodes
```

**Output Example:**
```
Available Nodes:
  inputs       - Input validation and preparation
  place        - Standard cell placement
  cts          - Clock tree synthesis
  route        - Global and detailed routing
  signoff      - Final design sign-off
```

### `make show_graph`

Display the flow graph showing node dependencies.

```bash
make show_graph
```

**Output Example:**
```
Flow Graph:
  inputs
    └── place
          └── cts
                └── cts_opt
                      └── route
                            └── pro
                                  └── signoff
                                        └── export_data
                                              └── release_data
```

### `make validate_nodes`

Validate the node configuration for errors.

```bash
make validate_nodes
```

---

## Makefile Regeneration

### `make generate_makefile`

Regenerate the Makefile for the current run.

```bash
make generate_makefile
```

**Use Cases:**
- After adding/removing nodes
- After modifying flow configuration
- To pick up new release scripts

**Requirements:**
One of these files must exist:
- `.run.cbflow.tcl` - CBFlow environment file
- `.config.tcl` - Configuration file
- `user_config_*.tcl` - User configuration files

---

## Flow-Specific Commands

### SYNTH Flow Commands

#### `make check_rtl`

Check RTL syntax and elaborate.

```bash
make check_rtl
```

#### `make qor`

Generate Quality of Results report.

```bash
make qor
```

### PNR Flow Commands

#### `make place`

Run placement stage with all subnodes.

```bash
make place
```

Subnodes: setup → run → validate → finish

#### `make cts`

Run clock tree synthesis.

```bash
make cts
```

Subnodes: setup → run → validate → finish

#### `make route`

Run global and detailed routing.

```bash
make route
```

Subnodes: setup → run → validate → finish

---

## Clean Commands

### `make clean`

Clean all generated files for the run.

```bash
make clean
```

**What Gets Removed:**
- `work/` - All working directories
- `logs/` - All log files
- `.stamps/` - All completion stamps
- `.make/` - All make includes
- `Makefile` - The run Makefile itself

**Warning:** This is irreversible!

---

## Workflow Examples

### Example 1: Complete SYNTH Flow

```bash
cd P0_run_SYNTH_test

# Run complete flow
make all

# Check QOR
make qor

# Create release
make release TAG=v1.0 TYPE=synthesis NOTES="Initial synthesis"
```

### Example 2: Incremental PNR Flow

```bash
cd P0_run_PNR_chip_top

# Run through placement
make inputs
make place

# Check placement, then continue
make cts
make cts_opt
make route
make pro
make signoff

# Create releases at milestones
make release TAG=placed_v1 TYPE=pnr_placed MILESTONE=PLACE_EXIT
make release TAG=routed_v1 TYPE=pnr_postroute MILESTONE=PRO_EXIT
make release TAG=final_v1 TYPE=pnr_signoff MILESTONE=BTO
```

### Example 3: Re-running a Stage

```bash
cd P0_run_PNR_test

# Stage already completed but needs to be re-run
rm .stamps/cts.stamp

# Re-run CTS and all dependent stages
make all
```

### Example 4: Adding Custom Node

```bash
cd P0_run_PNR_test

# Add a custom optimization node
make add_node NODE=custom_opt TYPE=pro DEP=route

# Regenerate Makefile
make generate_makefile

# Run the new node
make custom_opt
```

### Example 5: MMMC Scenario Analysis

```bash
cd P0_run_PNR_test

# View setup scenarios
make mmmc_corners TYPE=setup

# View all scenarios
make mmmc_corners TYPE=all

# Check which scenarios are assigned to CTS
make mmmc_nodes NODE=cts
```

---

## Troubleshooting

### Common Issues

#### "No CBFlow configuration file found"

**Error:**
```
ERROR: No CBFlow configuration file found in current directory
Expected files: .run.cbflow.tcl, .config.tcl, or user config files
```

**Solution:**
- Ensure you're in a valid run directory
- Check that configuration files exist
- Re-create the run from workspace

#### "Stage dependency not met"

**Error:**
```
Error: Cannot run 'place' - dependency 'inputs' not completed
```

**Solution:**
```bash
make inputs
make place
```

#### "Stamp file missing"

If a stage reports as incomplete but you believe it ran:

```bash
# Check if stamp exists
ls .stamps/

# Manually create stamp (use with caution)
touch .stamps/<stage>.stamp
```

#### "Node not found"

**Error:**
```
Error: Node 'custom_node' not found in flow
```

**Solution:**
```bash
# List available nodes
make list_nodes

# Add the node if needed
make add_node NODE=custom_node TYPE=<type> DEP=<dependency>
```

#### "Release type invalid"

**Error:**
```
Error: Invalid release type 'invalid_type'
```

**Solution:**
Check available release types:
- synthesis
- pnr_floorplan
- pnr_placed
- pnr_cts
- pnr_postroute
- pnr_signoff
- signoff

### Log Files

Check log files for detailed error information:

```bash
# List log files
ls logs/

# View a specific log
cat logs/place.log

# Search for errors
grep -i error logs/*.log
```

### Environment Issues

Verify environment variables are set:

```bash
echo $FLOW_DIR
echo $GENERATION_VERSION
echo $UTILITIES_VERSION
echo $NODE_MANAGEMENT_VERSION
```

If not set, source the workspace environment:

```bash
cd ..  # Go to workspace
source .cbflow.env
cd <run_directory>
```

---

## Command Quick Reference

| Command | Description |
|---------|-------------|
| `make help` | Show available targets |
| `make all` | Run complete flow |
| `make <stage>` | Run specific stage |
| `make clean` | Clean all files |
| `make mmmc_corners TYPE=<type>` | Show MMMC scenarios |
| `make mmmc_nodes` | Show node assignments |
| `make release TAG=<tag> TYPE=<type>` | Create release |
| `make add_node NODE=<n> TYPE=<t>` | Add custom node |
| `make delete_node NODE=<n>` | Delete node |
| `make list_nodes` | List all nodes |
| `make show_graph` | Show flow graph |
| `make validate_nodes` | Validate configuration |
| `make generate_makefile` | Regenerate Makefile |
| `make qor` | Generate QOR report (SYNTH) |
| `make check_rtl` | Check RTL (SYNTH) |

---

## Flow-Specific Stage Reference

### SYNTH Stages

| Stage | Description |
|-------|-------------|
| inputs | Input validation |
| synthesis | Run synthesis |
| export_data | Export database |
| release_data | Release deliverables |

### PNR Stages

| Stage | Description |
|-------|-------------|
| inputs | Input validation (netlist, SDC, DEF, UPF, library) |
| place | Standard cell placement |
| cts | Clock tree synthesis |
| cts_opt | Clock tree optimization |
| route | Global and detailed routing |
| pro | Post-route optimization |
| signoff | Final design sign-off |
| export_data | Export PNR database |
| release_data | Release PNR deliverables |

### FP Stages

| Stage | Description |
|-------|-------------|
| inputs | Input validation |
| floorplan | Floorplanning |
| export_data | Export database |
| release_data | Release deliverables |

---

## Related Documentation

- [Core Makefile Guide](core-makefile-guide.md) - Core CBFlow commands
- [Workspace Makefile Guide](workspace-makefile-guide.md) - Workspace management

---

*Last Updated: December 2024*
