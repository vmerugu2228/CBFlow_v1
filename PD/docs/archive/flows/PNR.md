# PNR Flow - Place & Route

## Overview

The PNR (Place & Route) flow performs standard cell placement, clock tree synthesis, and detailed routing to create a complete physical implementation. It transforms the floorplanned design into a fully routed layout ready for signoff verification.

**Flow Type**: `PNR`
**Primary Tool**: Cadence Innovus
**Configuration File**: `/core/config/flow/v1.0.0/node_configs/PNR_config.tcl`

## Flow Stages

### Stage Sequence
```
inputs → place → cts → cts_opt → route → route_opt → pro → signoff → export_data → release_data
```

This is CBFlow's most comprehensive flow with 10 total stages including 8 execution stages.

### 1. **inputs** - Data Preparation
- **Purpose**: Validate and prepare all input data for place & route
- **Duration**: 15-25 minutes
- **Key Outputs**: Validated netlist, floorplan, constraints, libraries

#### Subnodes:
- **setup**: Initialize input processing environment
- **netlist**: Process gate-level netlist
- **sdc**: Process timing constraints
- **def**: Process floorplan DEF file
- **upf**: Process power intent files
- **library**: Load technology and standard cell libraries
- **validate**: Comprehensive input validation
- **finish**: Complete input stage preparation

### 2. **place** - Standard Cell Placement
- **Purpose**: Place standard cells while optimizing timing and congestion
- **Duration**: 1-6 hours (design complexity dependent)
- **Key Outputs**: Placed design with timing-driven cell placement

#### Subnodes:
- **setup**: Configure placement environment and objectives
- **run**: Execute global and detailed placement
- **validate**: Verify placement quality and timing
- **finish**: Complete placement phase

### 3. **cts** - Clock Tree Synthesis
- **Purpose**: Build clock distribution network with balanced skew
- **Duration**: 30 minutes - 3 hours
- **Key Outputs**: Clock tree implementation with balanced delays

#### Subnodes:
- **setup**: Configure clock tree specifications
- **run**: Synthesize clock tree and balance skew
- **validate**: Verify clock tree quality and timing
- **finish**: Complete clock tree synthesis

### 4. **cts_opt** - Post-CTS Optimization
- **Purpose**: Optimize design after clock tree insertion
- **Duration**: 30 minutes - 2 hours
- **Key Outputs**: Optimized design with improved timing

#### Subnodes:
- **setup**: Configure post-CTS optimization
- **run**: Perform timing and power optimization
- **validate**: Verify optimization results
- **finish**: Complete post-CTS optimization

### 5. **route** - Global and Detailed Routing
- **Purpose**: Route all nets with DRC-clean connectivity
- **Duration**: 2-12 hours (design size dependent)
- **Key Outputs**: Completely routed design

#### Subnodes:
- **setup**: Configure routing objectives and constraints
- **run**: Execute global routing and detailed routing
- **validate**: Verify routing completeness and DRC compliance
- **finish**: Complete routing phase

### 6. **route_opt** - Post-Route Optimization
- **Purpose**: Optimize routed design for timing closure
- **Duration**: 1-4 hours
- **Key Outputs**: Timing-optimized routed design

#### Subnodes:
- **setup**: Configure post-route optimization
- **run**: Perform timing-driven optimization
- **validate**: Verify timing closure and DRC compliance
- **finish**: Complete routing optimization

### 7. **pro** - Physical Optimization
- **Purpose**: Final physical optimization and DRC fixing
- **Duration**: 30 minutes - 2 hours
- **Key Outputs**: DRC-clean optimized design

#### Subnodes:
- **setup**: Configure physical optimization parameters
- **run**: Execute physical optimization and DRC fixing
- **validate**: Verify DRC cleanliness and timing
- **finish**: Complete physical optimization

### 8. **signoff** - Signoff Preparation
- **Purpose**: Prepare design for signoff verification flows
- **Duration**: 30 minutes - 1 hour
- **Key Outputs**: Signoff-ready database and files

#### Subnodes:
- **setup**: Configure signoff preparation
- **run**: Generate signoff databases and extract parasitics
- **validate**: Verify signoff database quality
- **finish**: Complete signoff preparation

### 9. **export_data** - Result Export
- **Purpose**: Package P&R results for verification flows
- **Duration**: 15-30 minutes
- **Key Outputs**: GDS, DEF, netlist, parasitics for signoff

#### Subnodes:
- **setup**: Prepare export environment
- **run**: Export physical database and signoff files
- **validate**: Verify exported data integrity
- **finish**: Complete export process

### 10. **release_data** - Data Release
- **Purpose**: Finalize and archive P&R results
- **Duration**: 10-15 minutes
- **Key Outputs**: Complete release package with documentation

#### Subnodes:
- **setup**: Prepare release environment
- **run**: Create comprehensive release package
- **validate**: Verify release completeness
- **finish**: Complete P&R flow

## Tool Configuration

### Primary Tool
```tcl
tool,vendor "cadence"
tool,name "innovus"
tool,version "v1.0.0"
tool_mode "place_route"
```

### Multi-Stage Execution
PNR flow supports sophisticated execution strategies:
- **Sequential Execution**: Each stage completes before next begins
- **Parallel Execution**: Independent stages run simultaneously
- **Checkpoint-Based**: Intermediate checkpoints for recovery
- **Optimization Loops**: Iterative optimization between stages

## Input Requirements

### Required Files
1. **Physical Database**
   - Floorplanned design from FP flow
   - Macro placement and power grid
   - Physical constraints and placement regions

2. **Netlist and Constraints**
   - Gate-level netlist (post-synthesis)
   - Comprehensive SDC timing constraints
   - Physical constraints (placement/routing blockages)

3. **Technology Files**
   - Complete technology LEF files
   - Standard cell LEF files
   - Routing technology files

4. **Libraries**
   - Timing libraries (.lib) for all corners
   - Power libraries for dynamic power analysis
   - Noise libraries (if applicable)

### Optional Files
1. **Parasitics**
   - Wire load models or detailed parasitics
   - Interconnect models for estimation

2. **Power Intent**
   - UPF files for power-aware implementation
   - Multi-voltage domain specifications

3. **Special Routing**
   - Custom routing specifications
   - Critical net routing requirements

## Place & Route Process

### 1. Placement Phase
```tcl
# Global placement
setPlaceMode -place_global_max_density $density
placeDesign -inPlaceOpt -noPrePlaceOpt

# Detailed placement optimization
setPlaceMode -place_detail_legalization_inst_gap $gap
placeDesign -inPlaceOpt -detail
```

### 2. Clock Tree Synthesis
```tcl
# Clock tree specification
createClockTreeSpec -bufferList $buffer_list -rootPin $clock_root
ccopt_design

# Clock tree optimization
optDesign -postCTS -incr
```

### 3. Routing Phase
```tcl
# Global routing
setNanoRouteMode -quiet -routeSelectedNetOnly false
routeDesign -globalDetail

# Detailed routing optimization
setNanoRouteMode -quiet -routeWithTimingDriven true
routeDesign -wireOpt
```

### 4. Optimization Loops
```tcl
# Iterative optimization
optDesign -postRoute -incr
optDesign -postRoute -hold
optDesign -postRoute -setup
```

## Flat Mode Implementation

### Complex Merging Strategy
PNR flat mode groups related stages:
```
inputs → placement_merged → routing_merged → signoff_merged → export_data → release_data
```

Where:
- **placement_merged**: place + cts + cts_opt
- **routing_merged**: route + route_opt + pro
- **signoff_merged**: signoff preparation and validation

### Execution Benefits
- **Reduced Tool Overhead**: Fewer tool sessions
- **Optimized Data Flow**: Direct memory transfers between stages
- **Improved Convergence**: Better optimization across merged stages
- **Resource Efficiency**: Reduced memory and disk I/O

## Quality Metrics

### Placement Quality
- **Timing**: Setup/hold timing margins
- **Congestion**: Acceptable routing congestion (<80%)
- **Density**: Appropriate placement density distribution
- **Power**: Efficient power distribution

### Clock Tree Quality
- **Skew**: Balanced clock skew across domains (<50ps)
- **Insertion Delay**: Reasonable clock insertion delay
- **Power**: Optimized clock power consumption
- **DRC**: Clean clock tree implementation

### Routing Quality
- **Completion**: 100% routing completion
- **DRC**: Zero design rule violations
- **Timing**: Positive timing slack
- **Coupling**: Acceptable crosstalk noise

### Overall Quality
- **Area**: Efficient area utilization
- **Power**: Meeting power budgets
- **Performance**: Achieving frequency targets
- **Manufacturability**: DRC and LVS clean

## Output Products

### Physical Implementation
1. **Routed Database**
   - Complete physical implementation
   - All nets routed with DRC compliance
   - Optimized for timing and power

2. **GDS File**
   - Stream format for mask generation
   - Complete physical layout
   - Manufacturing-ready database

3. **Layout Files**
   - DEF format for tool exchange
   - OASIS format (alternative to GDS)
   - Technology-specific formats

### Analysis Files
1. **Timing Database**
   - Post-route timing information
   - Parasitics-aware timing data
   - Multi-corner timing analysis

2. **Parasitic Files**
   - Detailed interconnect parasitics
   - SPEF format for signoff STA
   - Capacitance and resistance data

3. **Power Analysis**
   - Power grid analysis results
   - Dynamic power estimates
   - IR drop analysis

### Verification Files
1. **Netlist**
   - Post-route Verilog netlist
   - Physical implementation netlist
   - LVS verification netlist

2. **Constraint Files**
   - Updated timing constraints
   - Physical verification constraints
   - Signoff constraint files

## Integration with Other Flows

### Upstream Dependencies
- **FP Flow**: Floorplan and power grid
- **SYNTH Flow**: Gate-level netlist and constraints
- **Library Qualification**: Characterized libraries

### Downstream Flows
- **PV Flow**: Physical verification (DRC, LVS)
- **FCT Flow**: Signoff timing analysis
- **EMIR Flow**: Power integrity analysis

### Handoff Quality Gates
```tcl
# Quality requirements for signoff handoff
timing_check {
    setup_slack "> 0"
    hold_slack "> 0"
    max_transition "< limit"
    max_capacitance "< limit"
}

physical_check {
    drc_violations "== 0"
    routing_completion "== 100%"
    antenna_violations "== 0"
}
```

## Advanced Features

### Multi-Corner Optimization
```tcl
# Multiple timing corners
create_scenario -name ss_max -timing_file ss_max.sdc
create_scenario -name ff_min -timing_file ff_min.sdc
create_scenario -name tt_nom -timing_file tt_nom.sdc
```

### Power-Aware Implementation
```tcl
# Power domain implementation
read_power_intent $upf_file
implement_power_plan
place_power_switch_cells
```

### Advanced Optimization
```tcl
# CCD (Concurrent Clock and Data) optimization
setCCDMode -enable true
optDesign -postRoute -ccd

# Useful skew optimization
setUsefulSkewMode -enable true
optDesign -postCTS -useful_skew
```

## Troubleshooting

### Placement Issues
- **Congestion**: Adjust placement density, add blockages
- **Timing**: Review timing constraints, optimize critical paths
- **Utilization**: Balance density across design regions

### Clock Tree Issues
- **Skew**: Adjust buffer selection, review clock specifications
- **Power**: Optimize clock gating, buffer sizing
- **DRC**: Check clock routing constraints

### Routing Issues
- **Completion**: Add routing resources, adjust constraints
- **DRC**: Review technology rules, fix violations
- **Timing**: Optimize critical nets, adjust routing priorities

### Optimization Convergence
- **Setup Timing**: Iterative optimization, constraint review
- **Hold Timing**: Buffer insertion, useful skew
- **Power**: Clock gating, operand isolation

## Configuration Examples

### High-Performance Configuration
```tcl
# Timing-driven implementation
array set pnr {
    optimization_focus "timing"
    placement_density "0.65"
    route_timing_driven "true"

    # Advanced features
    concurrent_clock_data "true"
    useful_skew "true"
    gate_sizing "true"
}
```

### Low-Power Configuration
```tcl
# Power-optimized implementation
array set pnr {
    optimization_focus "power"
    clock_gating "true"
    power_gating "true"

    # Power optimization
    operand_isolation "true"
    multi_vt_optimization "true"
    dynamic_power_optimization "true"
}
```

---

The PNR flow represents the most complex and critical phase of physical implementation, transforming floorplanned designs into complete, routed layouts ready for manufacturing.