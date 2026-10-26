# Getting Started with CBFlow

## Introduction

CBFlow is a comprehensive physical design automation framework that streamlines the process from synthesis to signoff. This guide will help you get started with CBFlow quickly and efficiently.

## Prerequisites

### System Requirements
- **Operating System**: Linux (RHEL 7+, Ubuntu 18.04+) or macOS
- **Memory**: Minimum 8GB RAM, recommended 32GB+ for large designs
- **Disk Space**: Minimum 100GB available space
- **Tcl Version**: Tcl 8.6 or later
- **Make**: GNU Make 4.0 or later

### EDA Tool Requirements
CBFlow integrates with various EDA tools. Ensure you have licenses and installations for:

- **Synthesis**: Cadence Genus or Synopsys Design Compiler
- **Place & Route**: Cadence Innovus
- **Timing Analysis**: Synopsys PrimeTime or Cadence Tempus
- **Physical Verification**: Mentor Calibre or Synopsys ICV

## Installation and Setup

### 1. Environment Setup
```bash
# Navigate to your project directory
cd /path/to/your/project

# Clone or extract CBFlow
# (Assuming CBFlow is already available in your environment)

# Navigate to CBFlow workspace
cd CBFlow/PD/workspace
```

### 2. Environment Configuration
Create the CBFlow environment file:
```bash
# Create .cbflow.env file
cp ../core/config/templates/.cbflow.env.template .cbflow.env

# Edit environment variables
vim .cbflow.env
```

Example `.cbflow.env` configuration:
```bash
# CBFlow Environment Configuration
export FLOW_DIR="/path/to/CBFlow/PD/core"
export FLOW_ROOT="$FLOW_DIR"

# Tool Configurations
export GENUS_HOME="/path/to/genus"
export INNOVUS_HOME="/path/to/innovus"
export TEMPUS_HOME="/path/to/tempus"

# Library Paths
export LIBRARY_ROOT="/path/to/libraries"
export TECH_ROOT="/path/to/technology"

# License Configurations
export LM_LICENSE_FILE="port@license_server"
```

### 3. Validate Installation
```bash
# Test CBFlow installation
make validate_environment

# Check available flows
make list_flows

# Verify tool access
make check_tools
```

## Your First CBFlow Run

### 1. Create a New Run
```bash
# Create a synthesis run
make create_run CONFIG=../user_config_synth.tcl

# This creates a new run directory like: P0_run_SYNTH_syn
```

### 2. Navigate to Run Directory
```bash
# Enter the created run directory
cd P0_run_SYNTH_syn

# Examine the run structure
ls -la
```

### 3. Configure Your Design
Edit the user configuration file:
```tcl
# user_config.tcl - Example synthesis configuration
array set flow {
    design_name "my_cpu"
    flow_type "SYNTH"
    run_type "flat"
}

array set project {
    technology "tsmc_7nm"
    clock_period "2.0"
    target_frequency "500"
}

# Input file specifications
set inputs_spec {
    rtl "/path/to/design.v"
    sdc "/path/to/constraints.sdc"
    library "/path/to/library.lib"
}
```

### 4. Execute the Flow
```bash
# Run the complete synthesis flow
make synthesis

# Or run individual stages
make inputs
make synthesis_setup
make synthesis_run
```

### 5. Monitor Progress
```bash
# Check run status
make status

# View detailed logs
tail -f logs/SYNTH/synthesis.log

# Check results
ls results/SYNTH/
```

## Understanding CBFlow Structure

### Run Directory Structure
```
P0_run_SYNTH_syn/
├── Makefile                 # Auto-generated run Makefile
├── setup/                   # Configuration files
│   ├── user_config.tcl     # User-specific settings
│   └── .run.cbflow.tcl     # Runtime environment
├── work/                   # Working directories
│   └── SYNTH/
│       └── synthesis/
├── logs/                   # Execution logs
│   └── SYNTH/
├── reports/               # Analysis reports
│   └── SYNTH/
├── results/              # Output files
│   └── SYNTH/
└── status/               # Status tracking
    └── SYNTH/
```

### Available Flow Types
CBFlow supports 11 different flow types:

1. **SYNTH** - Logic Synthesis
2. **FP** - Floorplanning
3. **PNR** - Place & Route
4. **PV** - Physical Verification
5. **FCT** - Final Critical Timing
6. **LEC** - Logic Equivalence Check
7. **EMIR** - Electromagnetic Interference & Reliability
8. **ECO** - Engineering Change Order
9. **CLP** - Clock Power Optimization
10. **POPT** - Physical Optimization
11. **FCFP** - Final Clock Floorplan

## Execution Modes

### Regular Mode (Default)
Individual stages execute independently:
```bash
# Each stage runs separately
make inputs
make synthesis
make export_data
make release_data
```

### Flat Mode (Optimized)
Stages are merged for performance:
```tcl
# Enable flat mode in configuration
array set flow {
    run_type "flat"
    design_name "my_design"
}
```

```bash
# Merged execution
make synthesis  # Runs all synthesis stages in single tool session
```

## Common Workflows

### 1. Complete RTL-to-GDS Flow
```bash
# Step 1: Synthesis
make create_run CONFIG=../user_config_synth.tcl
cd P0_run_SYNTH_syn
make synthesis

# Step 2: Floorplanning
cd ../
make create_run CONFIG=../user_config_fp.tcl FLOW_TYPE=FP
cd P0_run_FP_fp
make flat_flow

# Step 3: Place & Route
cd ../
make create_run CONFIG=../user_config_pnr.tcl FLOW_TYPE=PNR
cd P0_run_PNR_pnr
make flat_flow

# Step 4: Physical Verification
cd ../
make create_run CONFIG=../user_config_pv.tcl FLOW_TYPE=PV
cd P0_run_PV_pv
make flat_flow
```

### 2. Design Exploration Workflow
```bash
# Create multiple synthesis experiments
make create_run CONFIG=../config_high_performance.tcl
make create_run CONFIG=../config_low_power.tcl
make create_run CONFIG=../config_balanced.tcl

# Run experiments in parallel
# (In separate terminals or using job control)
```

### 3. ECO (Engineering Change Order) Workflow
```bash
# Create ECO run from existing implementation
make create_run CONFIG=../user_config_eco.tcl FLOW_TYPE=ECO
cd P0_run_ECO_eco

# Run ECO flow
make eco_inputs
make eco_implementation
make eco_validation
```

## Monitoring and Debugging

### Status Monitoring
```bash
# Check overall run status
make status

# View specific stage status
make status_synthesis

# Monitor active processes
make ps
```

### Log Analysis
```bash
# View real-time logs
tail -f logs/SYNTH/synthesis.log

# Search for errors
grep -i error logs/SYNTH/*.log

# Check warnings
grep -i warning logs/SYNTH/*.log
```

### Result Validation
```bash
# Validate outputs
make validate_results

# Check quality metrics
make check_quality

# Generate reports
make reports
```

## Configuration Management

### Hierarchical Configuration
CBFlow uses a 4-level configuration hierarchy:

1. **Flow Config** (System defaults)
2. **Technology Config** (Process-specific)
3. **Project Config** (Project standards)
4. **User Config** (Run-specific overrides)

### Configuration Examples

#### Basic Synthesis Configuration
```tcl
# user_config_synth.tcl
array set flow {
    design_name "cpu_core"
    flow_type "SYNTH"
}

array set project {
    technology "tsmc_7nm"
    clock_period "1.5"
}

# Tool-specific settings
array set synth {
    optimization_effort "high"
    compile_strategy "timing"
}
```

#### Floorplan Configuration
```tcl
# user_config_fp.tcl
array set flow {
    design_name "soc_top"
    flow_type "FP"
    run_type "flat"
}

array set fp {
    core_utilization "0.75"
    aspect_ratio "1.0"
    power_planning "true"
}
```

## Best Practices

### 1. File Organization
- Keep source files organized in logical directories
- Use consistent naming conventions
- Maintain separate directories for different design versions

### 2. Configuration Management
- Use project-level configurations for team standards
- Keep user configurations minimal and focused
- Document configuration changes

### 3. Run Management
- Use descriptive run names
- Archive successful runs for reference
- Clean up failed or obsolete runs regularly

### 4. Resource Management
- Monitor disk space usage
- Use appropriate run locations (local vs. network storage)
- Consider parallel execution resource requirements

### 5. Version Control
- Track configuration files in version control
- Maintain change logs for significant modifications
- Tag stable configurations

## Troubleshooting

### Common Issues

#### Environment Issues
```bash
# Problem: CBFlow tools not found
# Solution: Check .cbflow.env configuration
source .cbflow.env
which genus innovus

# Problem: License issues
# Solution: Verify license server access
echo $LM_LICENSE_FILE
lmstat -a
```

#### Configuration Issues
```bash
# Problem: Missing input files
# Solution: Validate input file paths
make validate_inputs

# Problem: Configuration errors
# Solution: Check configuration syntax
make validate_config
```

#### Execution Issues
```bash
# Problem: Stage failures
# Solution: Check logs and status
make status
tail logs/SYNTH/synthesis.log

# Problem: Resource limitations
# Solution: Monitor system resources
make check_resources
```

### Getting Help
```bash
# View available make targets
make help

# Check CBFlow documentation
ls ../core/docs/

# View specific flow documentation
cat ../core/docs/flows/SYNTH.md
```

## Next Steps

After completing this getting started guide:

1. **Read Flow-Specific Guides**: Explore detailed documentation for specific flows
2. **Learn Configuration**: Study the configuration hierarchy documentation
3. **Explore Advanced Features**: Learn about node management and flat mode
4. **Join the Community**: Connect with other CBFlow users for tips and best practices

For more detailed information, refer to:
- [Configuration Guide](configuration.md)
- [Running Flows](running-flows.md)
- [Node Management](node-management.md)
- [Troubleshooting Guide](troubleshooting.md)

---

Welcome to CBFlow! With these basics, you're ready to start your physical design journey.