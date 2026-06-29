# CBFlow Configuration Hierarchy

> ⚠️ **ARCHIVED — pre-v2.1 document.** This file describes the early 4-level
> cascade and references `cbflow_init_config.tcl`, which was retired in v2.1.x
> (duplicated `project(name/version)` with `<project>_config.tcl` causing
> silent overwrites).
>
> The current cascade is 13 levels (project → team → tech → flow → node →
> mmmc → tool → user → 5 overrides). See **`PD/docs/03-reference/configuration-reference.md`**
> for the authoritative reference and **`PD/docs/04-architecture/system-design.md`**
> for the runtime cascade diagram.
>
> Left in place for historical context only.

---

## Overview

CBFlow implements a sophisticated 4-level hierarchical configuration system that provides maximum flexibility while maintaining sensible defaults. This architecture allows for global defaults, technology-specific settings, project customizations, and user overrides with clear precedence rules.

## Hierarchy Structure

### Configuration Levels (Priority Order)
```
1. User Config      (Highest Priority - Runtime Overrides)
    ↓
2. Project Config   (Project-Specific Settings)
    ↓
3. Technology Config (Technology Node Settings)
    ↓
4. Flow Config      (Lowest Priority - System Defaults)
```

### Precedence Rules
- **Higher levels override lower levels** for identical keys
- **Array merging** occurs for non-conflicting keys
- **Complete override** for scalar values
- **Additive behavior** for list values (when specified)

## Configuration File Locations

### 1. Flow Configuration (System Defaults)
**Location**: `/core/config/flow/v1.0.0/`

```
flow/v1.0.0/
├── flow_config.tcl              # Master flow configuration
├── dir_config.tcl               # Directory structure definitions
├── logo_config.tcl              # Branding and identification
└── node_configs/                # Flow-specific configurations
    ├── SYNTH_config.tcl         # Synthesis flow settings
    ├── FP_config.tcl            # Floorplan flow settings
    ├── PNR_config.tcl           # Place & route settings
    └── [other_flows].tcl        # Additional flow configurations
```

### 2. Technology Configuration
**Location**: `/core/config/technology/[tech_node]/v1.0.0/`

```
technology/tsmc_7nm/v1.0.0/
├── technology_config.tcl        # Technology-specific settings
├── library_config.tcl           # Standard cell libraries
├── metal_stack_config.tcl       # Metal layer definitions
└── process_config.tcl           # Process parameters
```

### 3. Project Configuration
**Location**: `/core/config/project/[project_name]/v1.0.0/`

```
project/phoenix/v1.0.0/
├── phoenix_config.tcl           # Main project configuration
├── team_config.tcl              # Team-specific settings
├── design_config.tcl            # Design-specific parameters
└── cbflow_init_config.tcl       # CBFlow initialization
```

### 4. User Configuration (Run-Specific)
**Location**: `[run_directory]/setup/`

```
[run_directory]/setup/
├── user_config.tcl              # User overrides
├── consolidated_config.tcl      # Merged configuration
└── runtime_flow_config.tcl      # Runtime modifications
```

## Configuration Array Structure

### Flow Configuration Arrays
Each flow type defines its configuration in dedicated arrays:

```tcl
# Flow-specific array (e.g., synth, fp, pnr)
array set synth {
    # Stage definitions
    stages {inputs synthesis export_data release_data}

    # Subnode definitions
    subnodes,inputs {setup rtl sdc library validate finish}
    subnodes,synthesis {setup run validate finish}

    # Dependencies
    dependencies,inputs {}
    dependencies,synthesis {inputs}

    # Tool configuration
    tool,vendor "cadence"
    tool,name "genus"
    tool,version "v1.0.0"

    # Runtime settings
    runtime,timeout,synthesis 120
}
```

### Global Configuration Arrays

#### Directory Configuration
```tcl
array set directory {
    # Flow-specific directory structures
    SYNTH {
        work "work/SYNTH"
        logs "logs/SYNTH"
        reports "reports/SYNTH"
        results "results/SYNTH"
    }

    PNR {
        work "work/PNR"
        logs "logs/PNR"
        reports "reports/PNR"
        results "results/PNR"
    }
}
```

#### Technology Configuration
```tcl
array set tech {
    # Process parameters
    process "7nm"
    foundry "tsmc"
    metal_stack "10M"

    # Library definitions
    std_cell_lib "tcbn7ffcllvt"
    memory_lib "ts1n7ffcllvtb1024x64m8sw"
    io_lib "tpdn7v5"

    # LEF files
    lef,technology "/path/to/tech.lef"
    lef,std_cells "/path/to/std_cells.lef"
}
```

#### Project Configuration
```tcl
array set project {
    # Design parameters
    design_name "phoenix_cpu"
    top_module "cpu_top"
    technology "tsmc_7nm"

    # Constraints
    clock_period "2.0"
    target_frequency "500"
    power_budget "1000"

    # Tool settings
    tool_versions {
        genus "21.1"
        innovus "21.1"
        tempus "21.1"
    }
}
```

#### User Configuration
```tcl
array set flow {
    # User-specific overrides
    run_type "flat"
    debug_mode "true"
    design_name "custom_cpu"

    # Custom settings
    optimization_focus "timing"
    custom_constraints "tight_timing.sdc"
}
```

## Configuration Loading Process

### Hierarchical Loading Sequence
1. **Flow Configuration**: Load system defaults
2. **Technology Configuration**: Apply technology-specific settings
3. **Project Configuration**: Apply project customizations
4. **User Configuration**: Apply runtime overrides

### Loading Implementation
```tcl
proc load_hierarchical_configuration {flow_type run_dir} {
    global flow project tech

    # 1. Load flow configuration (lowest priority)
    source "$FLOW_DIR/config/flow/v1.0.0/flow_config.tcl"
    source "$FLOW_DIR/config/flow/v1.0.0/node_configs/${flow_type}_config.tcl"

    # 2. Load technology configuration
    if {[info exists project(technology)]} {
        set tech_config "$FLOW_DIR/config/technology/$project(technology)/v1.0.0/technology_config.tcl"
        if {[file exists $tech_config]} {
            source $tech_config
        }
    }

    # 3. Load project configuration
    if {[info exists project(name)]} {
        set project_config "$FLOW_DIR/config/project/$project(name)/v1.0.0/${project(name)}_config.tcl"
        if {[file exists $project_config]} {
            source $project_config
        }
    }

    # 4. Load user configuration (highest priority)
    set user_config "$run_dir/setup/user_config.tcl"
    if {[file exists $user_config]} {
        source $user_config
    }

    # 5. Generate consolidated configuration
    generate_consolidated_config $run_dir
}
```

### Configuration Consolidation
```tcl
proc generate_consolidated_config {run_dir} {
    global flow project tech synth fp pnr

    set consolidated_file "$run_dir/setup/consolidated_config.tcl"
    set fd [open $consolidated_file w]

    # Write consolidated configuration
    puts $fd "# Consolidated CBFlow Configuration"
    puts $fd "# Generated: [clock format [clock seconds]]"
    puts $fd ""

    # Export all configuration arrays
    foreach array_name {flow project tech} {
        if {[array exists $array_name]} {
            puts $fd "# $array_name configuration"
            puts $fd "array set $array_name {"
            foreach {key value} [array get $array_name] {
                puts $fd "    [list $key] [list $value]"
            }
            puts $fd "}"
            puts $fd ""
        }
    }

    close $fd
}
```

## Configuration Override Examples

### Technology Override Example
```tcl
# Flow default (SYNTH_config.tcl)
array set synth {
    tool,name "genus"
    optimization_effort "medium"
}

# Technology override (tsmc_7nm/technology_config.tcl)
array set synth {
    optimization_effort "high"    # Override: high effort for 7nm
    wireload_model "7nm_wlm"     # Add: technology-specific wireload
}

# Result: synth(tool,name) = "genus", synth(optimization_effort) = "high"
```

### Project Override Example
```tcl
# Technology setting (technology_config.tcl)
array set project {
    clock_period "2.0"
    power_budget "1000"
}

# Project override (phoenix_config.tcl)
array set project {
    clock_period "1.5"           # Override: faster clock for Phoenix
    design_name "phoenix_cpu"    # Add: project-specific design name
}

# Result: project(clock_period) = "1.5", project(power_budget) = "1000"
```

### User Override Example
```tcl
# Project setting (phoenix_config.tcl)
array set flow {
    run_type "regular"
    debug_mode "false"
}

# User override (user_config.tcl)
array set flow {
    run_type "flat"              # Override: use flat mode
    custom_setting "value"       # Add: user-specific setting
}

# Result: flow(run_type) = "flat", flow(debug_mode) = "false"
```

## Configuration Validation

### Validation Framework
```tcl
proc validate_configuration {} {
    global flow project tech

    set validation_errors {}

    # Validate required settings
    if {![info exists flow(design_name)]} {
        lappend validation_errors "Missing design_name in flow configuration"
    }

    if {![info exists project(technology)]} {
        lappend validation_errors "Missing technology specification"
    }

    # Validate value ranges
    if {[info exists project(clock_period)] && $project(clock_period) < 0.5} {
        lappend validation_errors "Clock period too aggressive: $project(clock_period)"
    }

    # Report validation results
    if {[llength $validation_errors] > 0} {
        puts "Configuration validation errors:"
        foreach error $validation_errors {
            puts "  - $error"
        }
        return false
    }

    return true
}
```

### Validation Checks
- **Required Parameters**: Ensure mandatory settings are present
- **Value Ranges**: Validate parameter values are within acceptable ranges
- **Compatibility**: Check technology/project/flow compatibility
- **File Existence**: Verify referenced files exist
- **Tool Availability**: Confirm required tools are available

## Configuration Access Patterns

### Reading Configuration Values
```tcl
# Access with default fallback
proc get_config_value {array_name key {default ""}} {
    upvar #0 $array_name config_array

    if {[info exists config_array($key)]} {
        return $config_array($key)
    } else {
        return $default
    }
}

# Usage examples
set design_name [get_config_value flow design_name "default_design"]
set clock_period [get_config_value project clock_period "2.0"]
```

### Conditional Configuration
```tcl
# Flow-specific configuration access
proc get_flow_config {flow_type key {default ""}} {
    set flow_var [string tolower $flow_type]
    return [get_config_value $flow_var $key $default]
}

# Usage
set synth_tool [get_flow_config SYNTH tool,name "genus"]
set place_effort [get_flow_config PNR optimization_effort "medium"]
```

## Best Practices

### Configuration Organization
1. **Minimize Flow Config Changes**: Keep system defaults stable
2. **Technology-Specific Settings**: Use technology config for process-dependent parameters
3. **Project Standards**: Define project-wide standards in project config
4. **User Experimentation**: Use user config for experimental settings

### Naming Conventions
```tcl
# Hierarchical naming for complex settings
array set synth {
    tool,vendor "cadence"           # tool category
    tool,name "genus"               # tool subcategory
    runtime,timeout,synthesis 120   # runtime category, subcategory, specific setting
}
```

### Configuration Management
1. **Version Control**: Track all configuration changes
2. **Documentation**: Document configuration parameter meanings
3. **Validation**: Implement comprehensive validation
4. **Templates**: Provide configuration templates for common scenarios

### Debugging Configuration Issues
```tcl
# Configuration debugging utilities
proc debug_configuration {array_name} {
    upvar #0 $array_name config_array

    puts "Configuration for $array_name:"
    foreach key [lsort [array names config_array]] {
        puts "  $key = $config_array($key)"
    }
}

# Usage
debug_configuration flow
debug_configuration project
```

## Migration and Upgrades

### Configuration Migration
When upgrading CBFlow versions:
1. **Backup Existing**: Save current configuration files
2. **Identify Changes**: Compare with new default configurations
3. **Update Overrides**: Modify user/project configs for new parameters
4. **Test Migration**: Validate updated configurations work correctly

### Backward Compatibility
CBFlow maintains backward compatibility by:
- **Default Fallbacks**: Providing defaults for new parameters
- **Deprecated Warnings**: Warning about obsolete parameters
- **Gradual Migration**: Supporting old and new parameter names temporarily

---

The hierarchical configuration system provides CBFlow with the flexibility to support diverse design requirements while maintaining systematic organization and clear override precedence.