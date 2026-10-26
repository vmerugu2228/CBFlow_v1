# CBFlow Configuration Guide

## Overview

CBFlow's configuration system is designed around a 4-level hierarchical structure that provides maximum flexibility while maintaining sensible defaults. This guide explains how to effectively configure CBFlow for your specific design and project requirements.

## Configuration Hierarchy

### The Four Levels
```
User Config      (Highest Priority - Runtime Overrides)
    ↓
Project Config   (Project-Specific Settings)
    ↓
Technology Config (Technology Node Settings)
    ↓
Flow Config      (Lowest Priority - System Defaults)
```

### Precedence Rules
- **Higher levels override lower levels** for identical keys
- **Array merging** occurs for non-conflicting keys
- **Complete override** for scalar values
- **Additive behavior** for list values when specified

## Flow Configuration (System Defaults)

### Location
`/core/config/flow/v1.0.0/`

### Key Files
- **`flow_config.tcl`** - Master flow configuration
- **`dir_config.tcl`** - Directory structure definitions
- **`logo_config.tcl`** - Branding and identification
- **`node_configs/`** - Flow-specific configurations

### Example Flow Configuration
```tcl
# flow_config.tcl - System-wide defaults
array set global_config {
    # Default execution settings
    default_timeout "3600"
    max_parallel_jobs "4"
    cleanup_temp_files "true"

    # Logging configuration
    log_level "INFO"
    debug_mode "false"

    # Resource limits
    max_memory_usage "16GB"
    max_disk_usage "100GB"
}

# Available flow types
set supported_flows {SYNTH FP PNR PV FCT LEC EMIR ECO CLP POPT FCFP}
```

### Node-Specific Configuration
```tcl
# node_configs/SYNTH_config.tcl - Synthesis flow defaults
array set synth {
    # Stage definitions
    stages {inputs synthesis export_data release_data}

    # Subnode definitions for each stage
    subnodes,inputs {setup rtl sdc library validate finish}
    subnodes,synthesis {setup run validate finish}
    subnodes,export_data {setup run validate finish}
    subnodes,release_data {setup run validate finish}

    # Dependencies between stages
    dependencies,inputs {}
    dependencies,synthesis {inputs}
    dependencies,export_data {synthesis}
    dependencies,release_data {export_data}

    # Tool configuration
    tool,vendor "cadence"
    tool,name "genus"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"

    # Default optimization settings
    optimization_effort "medium"
    compile_strategy "balanced"

    # Runtime settings
    timeout,synthesis 1800
    memory_limit "8GB"
}
```

## Technology Configuration

### Location
`/core/config/technology/[tech_node]/v1.0.0/`

### Purpose
Technology-specific settings that override flow defaults for a particular process node.

### Example Technology Configuration
```tcl
# technology/tsmc_7nm/v1.0.0/technology_config.tcl
array set tech {
    # Process information
    process "7nm"
    foundry "tsmc"
    metal_stack "10M"
    node_name "tsmc_7nm"

    # Library specifications
    std_cell_lib "tcbn7ffcllvt"
    memory_lib "ts1n7ffcllvtb1024x64m8sw"
    io_lib "tpdn7v5"

    # Technology files
    lef,technology "/path/to/tech.lef"
    lef,std_cells "/path/to/std_cells.lef"
    lef,memory "/path/to/memory.lef"

    # Timing libraries
    lib,ss_max "/path/to/ss_max.lib"
    lib,ff_min "/path/to/ff_min.lib"
    lib,tt_nom "/path/to/tt_nom.lib"

    # Physical design rules
    min_routing_layer "M2"
    max_routing_layer "M9"
    power_layers "M8 M9"
    clock_layers "M7 M8"

    # Technology-specific tool settings
    place_density "0.70"
    route_congestion_limit "0.85"
    clock_skew_target "50ps"
}

# Override synthesis settings for 7nm
array set synth {
    # 7nm requires higher optimization effort
    optimization_effort "high"

    # Technology-specific compile options
    compile_args "-gate_clock -effort high"

    # Timing constraints
    clock_uncertainty "0.05"
    setup_margin "0.1"
    hold_margin "0.05"
}
```

## Project Configuration

### Location
`/core/config/project/[project_name]/v1.0.0/`

### Purpose
Project-specific standards and settings that apply to all runs within a project.

### Example Project Configuration
```tcl
# project/phoenix/v1.0.0/phoenix_config.tcl
array set project {
    # Project identification
    project_name "phoenix_cpu"
    design_family "microprocessor"
    technology "tsmc_7nm"

    # Design specifications
    target_frequency "2.5GHz"
    power_budget "2.0W"
    area_target "5.0mm2"

    # Design constraints
    clock_period "0.4"
    input_delay "0.1"
    output_delay "0.1"
    clock_uncertainty "0.02"

    # Project standards
    coding_style "industry_standard"
    naming_convention "lower_case_underscore"
    directory_structure "hierarchical"

    # Quality requirements
    timing_margin "5%"
    power_margin "10%"
    area_margin "15%"

    # Tool versions (project standards)
    genus_version "21.1"
    innovus_version "21.1"
    tempus_version "21.1"
}

# Project-specific synthesis settings
array set synth {
    # Project optimization focus
    optimization_focus "timing"

    # Project-specific constraints
    max_fanout "32"
    max_transition "0.2"
    max_capacitance "0.5"

    # Design for test requirements
    dft_enable "true"
    scan_chain_count "8"
    atpg_coverage "95%"
}
```

### Team Configuration
```tcl
# project/phoenix/v1.0.0/team_config.tcl
array set team {
    # Team information
    team_name "Phoenix Design Team"
    team_manager "Alice Johnson"
    contact_email "phoenix-team@company.com"

    # Team preferences
    preferred_tools {genus innovus tempus}
    reporting_style "detailed"
    review_requirements "mandatory"

    # Development practices
    version_control "git"
    backup_policy "daily"
    documentation_level "comprehensive"
}
```

## User Configuration (Runtime)

### Location
`[run_directory]/setup/user_config.tcl`

### Purpose
Run-specific overrides and customizations that have the highest priority.

### Example User Configuration
```tcl
# user_config.tcl - Run-specific settings
array set flow {
    # Basic run configuration
    design_name "phoenix_core_v2"
    flow_type "SYNTH"
    run_type "flat"

    # User preferences
    debug_mode "true"
    verbose_logging "true"

    # Custom run settings
    custom_experiment "low_power_mode"
    iteration_number "5"
}

# Override project clock period for this experiment
array set project {
    clock_period "0.5"  # Slower clock for power optimization
    optimization_focus "power"
}

# Custom synthesis settings for this run
array set synth {
    # Power optimization focus
    optimization_effort "high"
    power_optimization "true"

    # Custom constraints for low power
    clock_gating "aggressive"
    operand_isolation "true"
    multi_vt_optimization "true"

    # Custom tool arguments
    tool,args "-batch -no_gui -power_opt"
}

# Input file specifications
set inputs_spec {
    rtl "/home/user/designs/phoenix/rtl/phoenix_core.v"
    sdc "/home/user/designs/phoenix/constraints/phoenix.sdc"
    upf "/home/user/designs/phoenix/power/phoenix.upf"
    library "/tools/libraries/tsmc_7nm/typical.lib"
}

# Custom directories for this run
set custom_dirs {
    custom_scripts "/home/user/phoenix/scripts"
    reference_data "/home/user/phoenix/reference"
    verification "/home/user/phoenix/verification"
}
```

## Configuration Arrays in Detail

### Flow Array
The `flow` array contains run-level execution settings:

```tcl
array set flow {
    # Required settings
    design_name "my_design"        # Design name
    flow_type "SYNTH"             # Flow type

    # Execution mode
    run_type "flat"               # flat or node mode

    # Debug and logging
    debug_mode "false"            # Enable debug output
    log_level "INFO"              # ERROR, WARN, INFO, DEBUG
    verbose_logging "false"       # Detailed logging

    # Resource management
    max_jobs "4"                  # Parallel execution limit
    timeout "7200"                # Overall timeout (seconds)
    memory_limit "16GB"           # Memory usage limit

    # Custom settings
    experiment_name "baseline"    # Experiment identifier
    iteration "1"                 # Iteration number
    notes "Initial implementation" # Run notes
}
```

### Project Array
The `project` array contains design-specific settings:

```tcl
array set project {
    # Design identification
    project_name "my_project"
    design_name "my_chip"
    technology "tsmc_7nm"

    # Performance targets
    target_frequency "1000"       # MHz
    clock_period "1.0"           # ns
    power_budget "500"           # mW
    area_target "2.5"            # mm²

    # Design constraints
    input_delay "0.2"            # ns
    output_delay "0.2"           # ns
    clock_uncertainty "0.05"     # ns
    clock_latency "0.1"          # ns

    # Quality targets
    setup_margin "0.1"           # ns
    hold_margin "0.05"           # ns
    max_transition "0.5"         # ns
    max_capacitance "1.0"        # pF
}
```

### Technology Array
The `tech` array contains process-specific information:

```tcl
array set tech {
    # Process information
    process "7nm"
    foundry "tsmc"
    metal_stack "9M"

    # Library files
    std_cell_lib "library_name"
    memory_lib "memory_name"

    # Technology files
    lef_files "/path/to/tech.lef /path/to/cells.lef"
    lib_files "/path/to/lib1.lib /path/to/lib2.lib"

    # Design rules
    min_width "0.07"             # μm
    min_spacing "0.07"           # μm
    via_resistance "5.0"         # Ω
    wire_cap_per_unit "0.2"      # fF/μm
}
```

### Flow-Specific Arrays
Each flow type has its own configuration array:

```tcl
# Synthesis-specific settings
array set synth {
    # Optimization settings
    optimization_effort "medium"  # low, medium, high
    optimization_focus "timing"   # timing, area, power

    # Compile settings
    compile_strategy "timing"     # timing, area, mixed
    gate_sizing "true"           # Enable gate sizing
    threshold_voltage_opt "true" # Multi-Vt optimization

    # Tool settings
    tool,vendor "cadence"
    tool,name "genus"
    tool,args "-batch"

    # Runtime limits
    timeout,synthesis "1800"     # seconds
    memory_limit "8GB"
}

# Floorplan-specific settings
array set fp {
    # Floorplan dimensions
    core_utilization "0.75"      # 75% utilization
    aspect_ratio "1.0"           # Square floorplan

    # Margins
    left_margin "10"             # μm
    right_margin "10"            # μm
    top_margin "10"              # μm
    bottom_margin "10"           # μm

    # Power planning
    power_rings "true"           # Create power rings
    power_stripes "true"         # Create power stripes
    ring_width "5"               # μm
    stripe_width "2"             # μm

    # Macro placement
    macro_placement "auto"       # auto, manual, guided
    placement_blockages ""       # Custom blockages
}
```

## Configuration Loading Process

### Automatic Loading Sequence
CBFlow automatically loads configurations in this order:

1. **Flow Configuration** - System defaults
2. **Technology Configuration** - Technology-specific settings
3. **Project Configuration** - Project standards
4. **User Configuration** - Run-specific overrides

### Manual Configuration Loading
```tcl
# Load specific configuration file
source "/path/to/config.tcl"

# Load configuration with validation
load_and_validate_config "/path/to/config.tcl"

# Merge additional configuration
merge_configuration $additional_config
```

## Configuration Validation

### Built-in Validation
CBFlow automatically validates:
- Required configuration parameters
- Value ranges and types
- File path existence
- Tool compatibility
- Cross-parameter consistency

### Custom Validation
```tcl
# Add custom validation rules
proc validate_custom_config {} {
    global flow project

    # Validate clock period
    if {$project(clock_period) < 0.5} {
        error "Clock period too aggressive: $project(clock_period)"
    }

    # Validate design name
    if {![regexp {^[a-zA-Z][a-zA-Z0-9_]*$} $flow(design_name)]} {
        error "Invalid design name format: $flow(design_name)"
    }

    return true
}
```

## Configuration Templates

### Basic Synthesis Template
```tcl
# synthesis_template.tcl
array set flow {
    design_name "DESIGN_NAME"
    flow_type "SYNTH"
    run_type "flat"
}

array set project {
    technology "TECHNOLOGY"
    clock_period "CLOCK_PERIOD"
    target_frequency "FREQUENCY"
}

set inputs_spec {
    rtl "RTL_PATH"
    sdc "SDC_PATH"
    library "LIBRARY_PATH"
}
```

### Advanced Configuration Template
```tcl
# advanced_template.tcl
array set flow {
    design_name "DESIGN_NAME"
    flow_type "FLOW_TYPE"
    run_type "EXECUTION_MODE"
    debug_mode "DEBUG"
    experiment_name "EXPERIMENT"
}

array set project {
    technology "TECHNOLOGY"
    clock_period "CLOCK_PERIOD"
    power_budget "POWER_BUDGET"
    area_target "AREA_TARGET"
}

array set FLOW_ARRAY {
    optimization_effort "EFFORT_LEVEL"
    optimization_focus "FOCUS_AREA"
    custom_setting "CUSTOM_VALUE"
}

# Custom procedures
proc custom_setup {} {
    # Custom setup procedures
}

proc custom_validation {} {
    # Custom validation procedures
}
```

## Best Practices

### Configuration Organization
1. **Use Hierarchy Effectively**: Place settings at the appropriate level
2. **Minimize Overrides**: Only override what's necessary
3. **Document Changes**: Comment non-obvious configuration choices
4. **Version Control**: Track configuration changes

### Configuration Maintenance
1. **Regular Review**: Periodically review and clean up configurations
2. **Standardization**: Establish project-wide configuration standards
3. **Testing**: Test configuration changes thoroughly
4. **Backup**: Maintain backups of working configurations

### Common Patterns
```tcl
# Pattern 1: Conditional configuration
if {$flow(run_type) eq "flat"} {
    array set synth {
        optimization_mode "merged"
        checkpoint_frequency "never"
    }
} else {
    array set synth {
        optimization_mode "incremental"
        checkpoint_frequency "stage"
    }
}

# Pattern 2: Environment-dependent configuration
if {[info exists env(HIGH_PERFORMANCE_MODE)]} {
    array set project {
        clock_period "0.8"
        optimization_effort "maximum"
    }
}

# Pattern 3: Design-size dependent configuration
set design_size [estimate_design_size $flow(design_name)]
if {$design_size > 1000000} {
    array set flow {
        max_jobs "8"
        memory_limit "32GB"
        timeout "14400"
    }
}
```

## Troubleshooting Configuration Issues

### Common Problems
1. **Missing Required Settings**: Ensure all required parameters are set
2. **Type Mismatches**: Check that values match expected types
3. **Path Issues**: Verify all file paths are correct and accessible
4. **Override Conflicts**: Review configuration hierarchy for conflicts

### Debugging Techniques
```tcl
# Debug configuration loading
set debug_config 1
source config.tcl

# Print configuration arrays
proc debug_config_array {array_name} {
    upvar #0 $array_name config_array
    parray config_array
}

# Validate specific settings
proc check_config_setting {array_name key expected_type} {
    upvar #0 $array_name config_array

    if {![info exists config_array($key)]} {
        puts "Missing configuration: $array_name($key)"
        return false
    }

    # Add type checking logic here
    return true
}
```

---

This configuration guide provides the foundation for effectively customizing CBFlow for your specific design requirements while maintaining the benefits of the hierarchical configuration system.