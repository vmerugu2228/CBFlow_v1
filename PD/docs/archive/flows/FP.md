# FP Flow - Floorplanning

## Overview

The FP (Floorplanning) flow handles physical layout planning, including die size definition, macro placement, power planning, and initial placement preparation. It bridges the gap between synthesis and place & route by establishing the physical foundation of the design.

**Flow Type**: `FP`
**Primary Tool**: Cadence Innovus
**Configuration File**: `/core/config/flow/v1.0.0/node_configs/FP_config.tcl`

## Flow Stages

### Stage Sequence
```
inputs → import_design → floorplan → powerplan → post_floorplan → export_data → release_data
```

### 1. **inputs** - Data Preparation
- **Purpose**: Validate and prepare all input data for floorplanning
- **Duration**: 10-20 minutes
- **Key Outputs**: Validated netlist, constraints, libraries, floorplan data

#### Subnodes:
- **setup**: Initialize input processing environment
- **netlist**: Process gate-level netlist from synthesis
- **sdc**: Process timing constraints
- **def**: Process floorplan definition (if available)
- **upf**: Process power intent files
- **library**: Load technology and standard cell libraries
- **validate**: Comprehensive input validation
- **finish**: Complete input stage preparation

### 2. **import_design** - Design Import
- **Purpose**: Import netlist and constraints into physical design environment
- **Duration**: 15-30 minutes
- **Key Outputs**: Loaded design database with constraints

#### Subnodes:
- **setup**: Configure import environment
- **run**: Import netlist, apply constraints, load libraries
- **validate**: Verify successful import and constraint application
- **finish**: Complete design import

### 3. **floorplan** - Physical Floorplanning
- **Purpose**: Define die size, place macros, create initial floorplan
- **Duration**: 1-4 hours (complexity dependent)
- **Key Outputs**: Physical floorplan with macro placement

#### Subnodes:
- **setup**: Configure floorplanning environment
- **run**: Create floorplan, place macros, define placement regions
- **validate**: Verify floorplan quality and macro placement
- **finish**: Finalize floorplan configuration

### 4. **powerplan** - Power Planning
- **Purpose**: Create power distribution network and power stripes
- **Duration**: 30 minutes - 2 hours
- **Key Outputs**: Power grid, power stripes, power connections

#### Subnodes:
- **setup**: Configure power planning environment
- **run**: Create power rings, stripes, and power grid
- **validate**: Verify power network connectivity and IR drop
- **finish**: Complete power planning

### 5. **post_floorplan** - Post-Floorplan Optimization
- **Purpose**: Optimize floorplan for timing and congestion
- **Duration**: 30 minutes - 1 hour
- **Key Outputs**: Optimized floorplan ready for placement

#### Subnodes:
- **setup**: Configure optimization environment
- **run**: Perform floorplan optimization and congestion analysis
- **validate**: Verify optimization results
- **finish**: Complete floorplan optimization

### 6. **export_data** - Result Export
- **Purpose**: Package floorplan results for downstream flows
- **Duration**: 10-15 minutes
- **Key Outputs**: DEF, LEF, constraint files for P&R

#### Subnodes:
- **setup**: Prepare export environment
- **run**: Export physical database and constraints
- **validate**: Verify exported data integrity
- **finish**: Complete export process

### 7. **release_data** - Data Release
- **Purpose**: Finalize and archive floorplan results
- **Duration**: 5-10 minutes
- **Key Outputs**: Release package with documentation

#### Subnodes:
- **setup**: Prepare release environment
- **run**: Create release package
- **validate**: Verify release completeness
- **finish**: Complete floorplan flow

## Tool Configuration

### Primary Tool
```tcl
tool,vendor "cadence"
tool,name "innovus"
tool,version "v1.0.0"
tool_mode "floorplan"
```

### Execution Modes
- **Interactive Mode**: GUI-based interactive floorplanning
- **Batch Mode**: Script-based automated execution
- **Mixed Mode**: Batch with selective interactive steps

## Input Requirements

### Required Files
1. **Gate-Level Netlist**
   - Post-synthesis Verilog netlist
   - Hierarchical with proper module definitions
   - Technology-mapped standard cells

2. **Timing Constraints**
   - SDC file with complete timing specifications
   - Clock definitions and timing requirements
   - Input/output delay constraints

3. **Technology Files**
   - Technology LEF files
   - Standard cell LEF files
   - Memory/macro LEF files

4. **Library Files**
   - Liberty (.lib) files for timing
   - Technology library files
   - Macro characterization files

### Optional Files
1. **Floorplan Definition (DEF)**
   - Previous floorplan constraints
   - Macro placement guidance
   - Placement regions

2. **Power Intent (UPF)**
   - Power domain definitions
   - Power switching specifications
   - Voltage area definitions

3. **Physical Constraints**
   - Placement blockages
   - Routing blockages
   - Special routing requirements

## Floorplanning Process

### 1. Design Import Phase
```tcl
# Import netlist and constraints
read_netlist $netlist_file
read_sdc $constraint_file
read_lef $technology_lef
read_lef $standard_cell_lef
read_lef $macro_lef_files
```

### 2. Initial Floorplan Creation
```tcl
# Create initial floorplan
floorPlan -r $aspect_ratio $core_utilization $left_margin $bottom_margin $right_margin $top_margin
```

### 3. Macro Placement
```tcl
# Place hard macros
placeInstance $macro_name $x_coordinate $y_coordinate -fixed
createInstGroup $group_name -insts $instance_list
placeInstGroup $group_name -region $region_name
```

### 4. Power Planning
```tcl
# Create power rings
addRing -nets {VDD VSS} -width $ring_width -spacing $ring_spacing
# Create power stripes
addStripe -nets {VDD VSS} -direction vertical -width $stripe_width
```

### 5. Placement Region Definition
```tcl
# Define placement regions
createPlaceBlockage -area $blockage_area -type soft
createRouteBlockage -area $blockage_area -layer $metal_layer
```

## Flat Mode Implementation

### Merged Execution Model
In flat mode, FP flow merges execution stages:
```
inputs → floorplan_merged → export_data → release_data
```

### Consolidated Operations
The `floorplan_merged` stage combines:
- **import_design**: Design import and constraint application
- **floorplan**: Floorplan creation and macro placement
- **powerplan**: Power network creation
- **post_floorplan**: Optimization and finalization

### Flat Mode Benefits
- **Single Tool Session**: Eliminates tool startup/teardown overhead
- **Optimized Data Flow**: Direct data transfer between stages
- **Reduced File I/O**: Minimizes intermediate file operations
- **Faster Execution**: 20-30% execution time reduction

### Flat Mode Script Generation
```tcl
# Generated consolidated script structure
source $setup_environment
run_import_design_procs
run_floorplan_procs
run_powerplan_procs
run_post_floorplan_procs
generate_outputs
```

## Quality Metrics

### Floorplan Quality
- **Aspect Ratio**: Reasonable die proportions (0.5 - 2.0)
- **Core Utilization**: Appropriate density (60-85%)
- **Macro Placement**: Optimal macro positioning
- **Congestion**: Acceptable routing congestion levels

### Power Network Quality
- **IR Drop**: Within acceptable limits (<5% VDD)
- **Power Connectivity**: Complete power grid connectivity
- **Current Density**: Acceptable current density limits
- **Power Integrity**: Clean power delivery

### Timing Feasibility
- **Clock Domains**: Proper clock domain separation
- **Critical Paths**: Timing-aware macro placement
- **Clock Skew**: Manageable clock distribution

## Output Products

### Physical Database
1. **Design Database**
   - Complete physical design database
   - Placed macros and defined regions
   - Power network implementation

2. **DEF File**
   - Physical design exchange format
   - Macro placement coordinates
   - Power grid definition

3. **Constraint Files**
   - Updated physical constraints
   - Placement and routing constraints
   - Clock tree constraints

### Reports and Analysis
1. **Floorplan Reports**
   - Area utilization analysis
   - Macro placement summary
   - Congestion analysis

2. **Power Reports**
   - Power network analysis
   - IR drop analysis
   - Current density reports

3. **Timing Reports**
   - Preliminary timing analysis
   - Clock domain analysis
   - Critical path identification

## Integration with Other Flows

### Upstream Dependencies
- **SYNTH Flow**: Gate-level netlist and constraints
- **Library Development**: Technology and macro libraries
- **Floorplan Specification**: Initial floorplan guidelines

### Downstream Flows
- **PNR Flow**: Physical database for place and route
- **Power Analysis**: Floorplan for power estimation
- **Timing Analysis**: Physical constraints for STA

### Data Handoff
```tcl
# FP outputs for downstream flows
set export_data {
    design_db "results/floorplan.db"
    def_file "results/floorplan.def"
    physical_constraints "results/physical.sdc"
    power_network "results/power.def"
}
```

## Configuration Examples

### Basic FP Configuration
```tcl
# User configuration for floorplan run
array set flow {
    run_type "flat"
    design_name "my_soc"
    core_utilization "0.75"
    aspect_ratio "1.0"
}

array set project {
    die_size "2000 2000"
    margin "50"
    power_domains "2"
}

# Macro placement specifications
set macros {
    {memory_bank_0 {500 500}}
    {memory_bank_1 {1500 500}}
    {cpu_core {1000 1000}}
}
```

### Advanced FP Configuration
```tcl
# Complex floorplan with multiple voltage domains
array set fp {
    # Power planning
    power_rings "true"
    power_stripes "true"
    ring_width "10"
    stripe_width "5"
    stripe_spacing "100"

    # Placement constraints
    placement_blockages {
        {area {0 0 100 100} type soft}
        {area {1900 1900 2000 2000} type hard}
    }

    # Timing constraints
    clock_regions {
        {name cpu_region coords {800 800 1200 1200}}
        {name mem_region coords {400 400 800 800}}
    }
}
```

## Troubleshooting

### Common Issues
1. **Import Failures**
   - Verify netlist syntax and hierarchy
   - Check library compatibility
   - Validate constraint file format

2. **Macro Placement Issues**
   - Check macro LEF file availability
   - Verify macro size vs die size
   - Validate placement coordinates

3. **Power Planning Failures**
   - Check power net connectivity
   - Verify metal layer availability
   - Validate power ring/stripe specifications

4. **Congestion Issues**
   - Adjust core utilization
   - Redistribute macro placement
   - Add placement blockages

### Debug Techniques
- **Visual Inspection**: Use GUI for floorplan visualization
- **Report Analysis**: Review detailed congestion and timing reports
- **Incremental Changes**: Make small adjustments and re-evaluate
- **Constraint Validation**: Verify physical constraint consistency

## Best Practices

### Floorplan Strategy
- Start with conservative utilization (70-75%)
- Place critical macros first
- Consider timing-critical paths in placement
- Balance area utilization and routability

### Power Planning
- Plan power network early in floorplan
- Use appropriate metal layers for power distribution
- Consider power domain boundaries
- Validate IR drop requirements

### Macro Placement
- Group related macros together
- Consider data flow and connectivity
- Leave routing channels between macros
- Plan for clock distribution

### Quality Validation
- Check congestion maps regularly
- Validate timing feasibility
- Verify power network integrity
- Review area utilization balance

---

The FP flow establishes the physical foundation for successful place and route by creating an optimized floorplan with proper macro placement and power distribution.