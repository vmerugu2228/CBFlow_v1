# CBFlow Flow Types Overview

## Introduction

CBFlow supports 11 specialized flow types, each designed for specific stages of the physical design process. Each flow type defines its own stages, dependencies, subnodes, and tool integration while following consistent architectural patterns.

## Supported Flow Types

### 1. **[SYNTH](SYNTH.md)** - Logic Synthesis
- **Purpose**: RTL to gate-level netlist conversion
- **Stages**: inputs → synthesis → export_data → release_data
- **Tools**: Cadence Genus, Synopsys Design Compiler
- **Key Features**: Logic optimization, area/power/timing trade-offs

### 2. **[FP](FP.md)** - Floorplanning
- **Purpose**: Physical layout planning and macro placement
- **Stages**: inputs → import_design → floorplan → powerplan → post_floorplan → export_data → release_data
- **Tools**: Cadence Innovus
- **Key Features**: Die size definition, macro placement, power planning

### 3. **[PNR](PNR.md)** - Place & Route
- **Purpose**: Standard cell placement and routing
- **Stages**: inputs → place → cts → cts_opt → route → route_opt → pro → signoff → export_data → release_data
- **Tools**: Cadence Innovus
- **Key Features**: Placement optimization, clock tree synthesis, routing

### 4. **[PV](PV.md)** - Physical Verification
- **Purpose**: DRC, LVS, and parasitic verification
- **Stages**: inputs → drc → lvs → erc → perc → merge_data → release_data
- **Tools**: Mentor Calibre, Synopsys ICV
- **Key Features**: Rule checking, layout vs schematic verification

### 5. **[FCT](FCT.md)** - Full Chip Timing
- **Purpose**: Static timing analysis and optimization
- **Stages**: inputs → extraction → timing
- **Tools**: Synopsys PrimeTime, Cadence Tempus
- **Key Features**: Timing closure, optimization

### 6. **[LEC](LEC.md)** - Logic Equivalence Check
- **Purpose**: Formal verification between design versions
- **Stages**: inputs → setup → compare → analyze
- **Tools**: Cadence Conformal, Synopsys Formality
- **Key Features**: Formal verification, equivalence checking

### 7. **[EMIR](EMIR.md)** - Electromagnetic IR Analysis
- **Purpose**: Power delivery and electromagnetic analysis
- **Stages**: inputs → extraction → analysis → report
- **Tools**: Cadence Voltus, Apache Redhawk
- **Key Features**: IR drop analysis, EM analysis

### 8. **[ECO](ECO.md)** - Engineering Change Order
- **Purpose**: Incremental design changes and fixes
- **Stages**: inputs → analysis → implementation
- **Tools**: Cadence Innovus
- **Key Features**: Minimal impact changes, timing fixes

### 9. **[CLP](CLP.md)** - Clock Planning
- **Purpose**: Clock tree planning and specification
- **Stages**: inputs → planning → specification → validation
- **Tools**: Cadence Innovus
- **Key Features**: Clock tree topology, skew planning

### 10. **[POPT](POPT.md)** - Power Optimization
- **Purpose**: Power reduction and optimization
- **Stages**: inputs → analysis → optimization → validation → signoff
- **Tools**: Cadence Innovus, Synopsys Power Compiler
- **Key Features**: Dynamic/static power optimization

### 11. **[FCFP](FCFP.md)** - Full Chip Floorplan
- **Purpose**: Comprehensive full-chip floorplanning
- **Stages**: inputs → global_fp → partition → placement → powerplan → validation
- **Tools**: Cadence Innovus
- **Key Features**: Hierarchical floorplanning, partition management

## Common Architecture

### Stage Structure
All flows follow a consistent stage structure:
- **inputs**: Data preparation and validation
- **[execution_stages]**: Flow-specific processing stages
- **export_data**: Result packaging and export
- **release_data**: Final data release and cleanup

### Subnode Pattern
Each stage typically includes:
- **setup**: Stage initialization and configuration
- **run**: Main execution phase
- **validate**: Result validation and quality checks
- **finish**: Cleanup and preparation for next stage

### Configuration Structure
```tcl
# Flow configuration array
array set [flow_type] {
    # Stage definitions
    stages {inputs stage1 stage2 ... export_data release_data}

    # Subnode definitions
    subnodes,inputs {setup netlist sdc def upf library validate finish}
    subnodes,stage1 {setup run validate finish}

    # Dependencies
    dependencies,inputs {}
    dependencies,stage1 {inputs}

    # Tool configuration
    tool,stage1 {innovus}
    tool_mode,stage1 {floorplan}
}
```

## Execution Modes

### Regular Mode
- **Individual Stages**: Each execution stage runs separately
- **Full Flexibility**: Complete control over each stage
- **Custom Nodes**: Support for custom stage variations
- **Branch Creation**: Parallel execution branches

### Flat Mode
- **Merged Execution**: Multiple execution stages consolidated
- **Optimized Performance**: Reduced overhead and faster execution
- **Simplified Management**: Single merged execution node
- **Architecture Protection**: Prevents creation of individual execution nodes

## Flow Selection Guide

### By Design Phase
- **RTL Development**: SYNTH
- **Physical Planning**: FP, FCFP
- **Implementation**: PNR
- **Verification**: PV, LEC
- **Optimization**: POPT, ECO
- **Analysis**: FCT, EMIR, CLP

### By Design Complexity
- **Simple Blocks**: SYNTH, FP, PNR
- **Complex Blocks**: FCFP, CLP, POPT
- **Full Chip**: FCFP, PV, FCT, EMIR

### By Tool Ecosystem
- **Cadence-Centric**: FP, PNR, LEC, EMIR, ECO, CLP, POPT, FCFP
- **Synopsys-Centric**: SYNTH, FCT, POPT
- **Mentor-Centric**: PV

## Configuration Hierarchy

### Flow Level (Highest Priority)
```tcl
# Flow-specific settings
array set fp {
    stages {inputs import_design floorplan powerplan post_floorplan export_data release_data}
    tool,floorplan {innovus}
    tool_mode,floorplan {floorplan}
}
```

### Project Level
```tcl
# Project-specific overrides
array set project {
    design_name {my_chip}
    technology {tsmc_7nm}
    constraints {tight_timing}
}
```

### Technology Level
```tcl
# Technology node settings
array set tech {
    process {7nm}
    libraries {tcbn7ffcllvt}
    metal_stack {10M}
}
```

### User Level (Lowest Priority)
```tcl
# User-specific customizations
array set flow {
    run_type {flat}
    debug_mode {true}
    custom_settings {value}
}
```

## Tool Integration

### Supported Tools
- **Synthesis**: Cadence Genus, Synopsys Design Compiler
- **P&R**: Cadence Innovus
- **STA**: Synopsys PrimeTime, Cadence Tempus
- **Physical Verification**: Mentor Calibre, Synopsys ICV
- **Formal Verification**: Cadence Conformal, Synopsys Formality
- **Power Analysis**: Cadence Voltus, Apache Redhawk

### Tool Configuration
```tcl
# Tool definitions per flow
array set [flow_type] {
    tool,synthesis {genus}
    tool,place {innovus}
    tool,route {innovus}
    tool,sta {tempus}
    tool,drc {calibre}
}
```

## Best Practices

### Flow Selection
1. **Match Purpose**: Choose flow type based on design phase and goals
2. **Consider Dependencies**: Understand input requirements from previous flows
3. **Tool Availability**: Ensure required tools are licensed and available
4. **Resource Planning**: Consider computational and storage requirements

### Configuration Management
1. **Hierarchical Setup**: Use proper configuration hierarchy
2. **Version Control**: Track configuration changes
3. **Documentation**: Document flow-specific settings and rationales
4. **Validation**: Validate configurations before execution

### Execution Planning
1. **Mode Selection**: Choose between regular and flat mode based on needs
2. **Resource Allocation**: Plan computational resources
3. **Monitoring**: Set up status monitoring and logging
4. **Error Handling**: Plan for error scenarios and recovery

## Flow Dependencies

### Typical Flow Sequence
```
RTL → SYNTH → FP → PNR → PV → FCT
              ↓
            FCFP (for complex designs)
              ↓
        CLP/POPT/EMIR (optimization flows)
              ↓
            ECO (final fixes)
              ↓
            LEC (verification)
```

### Data Flow
- **SYNTH Output**: Gate-level netlist, constraints
- **FP Output**: Floorplan, power plan, placement constraints
- **PNR Output**: Placed and routed design, timing database
- **PV Output**: Clean layout, verification reports
- **FCT Output**: Timing analysis, optimization reports

---

This overview provides the foundation for understanding CBFlow's comprehensive flow ecosystem. Each flow type builds on these common patterns while providing specialized capabilities for specific design challenges.