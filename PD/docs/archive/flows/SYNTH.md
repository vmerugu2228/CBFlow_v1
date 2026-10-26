# SYNTH Flow - Logic Synthesis

## Overview

The SYNTH flow converts RTL (Register Transfer Level) code into gate-level netlists using technology-specific standard cell libraries. It performs logic optimization for area, power, and timing while maintaining functional equivalence.

**Flow Type**: `SYNTH`
**Primary Tool**: Cadence Genus, Synopsys Design Compiler
**Configuration File**: `/core/config/flow/v1.0.0/node_configs/SYNTH_config.tcl`

## Flow Stages

### Stage Sequence
```
inputs → synthesis → export_data → release_data
```

### 1. **inputs** - Data Preparation
- **Purpose**: Validate and prepare all input data for synthesis
- **Duration**: 5-15 minutes
- **Key Outputs**: Validated RTL, constraints, libraries

#### Subnodes:
- **setup**: Initialize input processing environment
- **rtl**: Process and validate RTL files
- **sdc**: Process timing constraints (SDC files)
- **library**: Load and validate technology libraries
- **upf**: Process power intent (UPF files) - optional
- **validate**: Comprehensive input validation
- **finish**: Complete input stage preparation

### 2. **synthesis** - Logic Synthesis
- **Purpose**: RTL to gate-level conversion with optimization
- **Duration**: 30 minutes - 4 hours (design dependent)
- **Key Outputs**: Gate-level netlist, timing database

#### Subnodes:
- **setup**: Configure synthesis environment and constraints
- **run**: Execute synthesis and optimization
- **validate**: Verify synthesis results and timing
- **finish**: Generate reports and prepare outputs

### 3. **export_data** - Result Export
- **Purpose**: Package synthesis results for downstream flows
- **Duration**: 5-10 minutes
- **Key Outputs**: Netlist, constraints, timing database

#### Subnodes:
- **setup**: Prepare export environment
- **run**: Export netlist, constraints, and timing data
- **validate**: Verify exported data integrity
- **finish**: Complete export process

### 4. **release_data** - Data Release
- **Purpose**: Finalize and archive synthesis results
- **Duration**: 2-5 minutes
- **Key Outputs**: Release package, documentation

#### Subnodes:
- **setup**: Prepare release environment
- **run**: Create release package
- **validate**: Verify release completeness
- **finish**: Complete synthesis flow

## Tool Configuration

### Supported Tools
```tcl
supported_tools {genus dc fc}
default_tool "genus"
```

- **genus**: Cadence Genus Synthesis Solution (default)
- **dc**: Synopsys Design Compiler
- **fc**: Synopsys Fusion Compiler

### Tool Settings
```tcl
tool,vendor "cadence"
tool,name "genus"
tool,version "v1.0.0"
tool,args "-batch -no_gui"
```

### Runtime Configuration
```tcl
runtime,timeout,synthesis 120  # 2 hour timeout
```

## Input Requirements

### Required Files
1. **RTL Files**
   - Verilog (.v) or SystemVerilog (.sv) source files
   - Top-level module definition
   - All hierarchical modules

2. **Timing Constraints (SDC)**
   - Clock definitions and timing constraints
   - Input/output delay specifications
   - False path and multicycle path definitions

3. **Technology Libraries**
   - Standard cell libraries (.lib)
   - Memory compiler libraries
   - IO libraries (if applicable)

### Optional Files
1. **Power Intent (UPF)**
   - Power domain definitions
   - Power switching specifications
   - Retention and isolation strategies

2. **Physical Libraries**
   - LEF files for physical synthesis
   - Technology LEF files

### Input Validation Checks
- **RTL Syntax**: Verilog/SystemVerilog syntax validation
- **Elaboration**: Successful design elaboration
- **Constraint Consistency**: SDC constraint validation
- **Library Completeness**: Required library availability
- **UPF Compatibility**: Power intent consistency (if used)

## Synthesis Process

### 1. Setup Phase
```tcl
# Environment initialization
read_libs -technology_library $tech_lib
read_libs -standard_cell_library $std_cell_lib
read_hdl $rtl_files
elaborate $top_module
```

### 2. Constraint Application
```tcl
# Timing constraints
read_sdc $constraint_file
set_operating_conditions $op_cond
set_wire_load_model $wire_load
```

### 3. Synthesis Execution
```tcl
# Logic synthesis and optimization
synthesize -to_mapped
opt_design -area
opt_design -power
opt_design -timing
```

### 4. Quality Checks
- **Timing Analysis**: Setup/hold timing verification
- **Area Analysis**: Gate count and area reporting
- **Power Analysis**: Static power estimation
- **DRC Checking**: Design rule compliance

## Output Products

### Primary Outputs
1. **Gate-Level Netlist**
   - Mapped to technology libraries
   - Hierarchical or flattened as specified
   - Verilog format (.v)

2. **Timing Database**
   - Post-synthesis timing information
   - Setup/hold timing data
   - Clock tree information

3. **Constraint Files**
   - Physical constraints for P&R
   - Updated timing constraints
   - Clock specifications

### Reports and Analysis
1. **Timing Reports**
   - Setup/hold timing analysis
   - Critical path analysis
   - Clock domain analysis

2. **Area Reports**
   - Cell count by type
   - Area breakdown by hierarchy
   - Utilization analysis

3. **Power Reports**
   - Static power analysis
   - Power breakdown by hierarchy
   - Clock power analysis

4. **Quality Reports**
   - Design rule check results
   - Lint and synthesis warnings
   - Optimization summaries

## Flat Mode Support

### Merged Execution
In flat mode, SYNTH can be merged with preparation stages:
```
inputs → synthesis_merged → export_data → release_data
```

### Flat Mode Benefits
- **Reduced Overhead**: Single tool session for entire synthesis
- **Optimized Flow**: Streamlined data flow between stages
- **Faster Execution**: Reduced setup/teardown time

### Flat Mode Restrictions
- Cannot create individual execution branches
- Limited customization of intermediate stages
- Optimized for standard synthesis flows

## Configuration Examples

### Basic SYNTH Configuration
```tcl
# User configuration for synthesis run
array set flow {
    run_type "regular"
    design_name "my_processor"
    top_module "cpu_top"
}

array set project {
    target_library "tcbn28hpcplusbwp7t30p140"
    wire_load_model "ForQA"
    operating_conditions "ss0p72v125c"
}

# Input file specifications
set inputs(rtl_files) {
    "rtl/cpu_top.v"
    "rtl/alu.v"
    "rtl/register_file.v"
}

set inputs(sdc_file) "constraints/cpu_top.sdc"
set inputs(upf_file) "power/cpu_top.upf"
```

### Advanced SYNTH Configuration
```tcl
# High-performance synthesis setup
array set synth {
    # Optimization focus
    optimization_focus "timing"
    congestion_driven "true"

    # Advanced options
    multibit_banking "true"
    clock_gating "true"
    operand_isolation "true"

    # Runtime settings
    max_runtime "240"  # 4 hours
    num_cores "8"
}
```

## Integration with Other Flows

### Upstream Dependencies
- **RTL Development**: Source RTL and testbenches
- **Constraint Development**: Timing and physical constraints
- **Library Qualification**: Technology library validation

### Downstream Flows
- **FP (Floorplanning)**: Uses synthesis netlist for placement
- **PNR (Place & Route)**: Uses netlist and constraints for implementation
- **LEC (Logic Equivalence)**: Formal verification against RTL

### Data Handoff
```tcl
# Synthesis outputs used by downstream flows
set export_data {
    netlist "results/cpu_top_mapped.v"
    sdc "results/cpu_top_mapped.sdc"
    sdf "results/cpu_top_mapped.sdf"
    timing_db "results/cpu_top.db"
}
```

## Quality Metrics

### Timing Closure
- **Setup Timing**: Worst negative slack (WNS) > 0
- **Hold Timing**: Total negative slack (TNS) = 0
- **Clock Skew**: Balanced across clock domains

### Area Targets
- **Gate Count**: Within target specification
- **Utilization**: Reasonable for downstream P&R
- **Memory Usage**: Efficient memory implementation

### Power Goals
- **Leakage Power**: Within power budget
- **Dynamic Power**: Clock and logic power optimization
- **Power Gating**: Effective power domain implementation

## Troubleshooting

### Common Issues
1. **Elaboration Failures**
   - Check RTL syntax and module hierarchy
   - Verify include paths and define statements
   - Validate module port connections

2. **Library Issues**
   - Ensure library compatibility with tool version
   - Check library search paths
   - Verify operating condition definitions

3. **Timing Violations**
   - Review constraint definitions
   - Check clock specifications
   - Validate input/output delay constraints

4. **Optimization Failures**
   - Adjust optimization settings
   - Check design size and complexity
   - Review resource utilization

### Debug Techniques
- **Incremental Compilation**: Debug individual modules
- **Constraint Analysis**: Verify timing requirements
- **Quality Checks**: Use tool-specific lint checks
- **Report Analysis**: Review detailed synthesis reports

## Best Practices

### RTL Preparation
- Use consistent coding style
- Avoid inferred latches and combinational loops
- Implement proper reset strategies
- Use synchronous design practices

### Constraint Development
- Define realistic timing requirements
- Use appropriate clock specifications
- Set proper input/output delays
- Include uncertainty margins

### Synthesis Strategy
- Start with conservative optimization
- Iterate based on timing results
- Balance area, power, and timing
- Validate against design specifications

### Quality Assurance
- Run comprehensive lint checks
- Verify timing closure
- Validate power estimates
- Check design rule compliance

---

The SYNTH flow provides the foundation for physical design by converting RTL to optimized gate-level netlists while maintaining timing, area, and power requirements.