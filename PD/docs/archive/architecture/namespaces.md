# CBFlow Namespace Architecture

## Overview

CBFlow implements a sophisticated namespace system that organizes functionality into logical domains, prevents naming conflicts, and provides clean separation of concerns. The namespace architecture supports modular development, maintenance, and extensibility while maintaining backward compatibility.

## Namespace Philosophy

### Design Principles
1. **Functional Separation**: Each namespace handles a specific domain of functionality
2. **Collision Avoidance**: Prevents function and variable name conflicts
3. **Modular Organization**: Clean separation enables independent development
4. **Extensibility**: Easy to add new functionality domains
5. **Maintainability**: Clear organization simplifies debugging and updates

### Namespace Hierarchy
```
::CBFlow::
├── Directory          # Directory structure management
├── Logo              # Branding and identification
├── Utilities         # Common utility functions
├── NodeManagement    # Node and branch operations
├── Validation        # Quality assurance and validation
├── Configuration     # Configuration management
├── Generation        # Code and file generation
├── Release          # Release management
└── Tools            # Tool integration abstractions
```

## Core Namespaces

### `::CBFlow::Directory`
**Purpose**: Manages directory structures, paths, and file organization

#### Namespace Structure
```tcl
namespace eval ::CBFlow::Directory {
    # Namespace variables
    variable directory_config
    variable flow_directories
    variable workspace_paths

    # Export public procedures
    namespace export {
        create_flow_directories
        get_flow_directory_path
        validate_directory_structure
        setup_workspace_directories
        cleanup_temporary_directories
    }
}
```

#### Key Procedures
```tcl
# Directory creation and management
proc ::CBFlow::Directory::create_flow_directories {flow_type run_dir} {
    global directory

    # Get flow-specific directory configuration
    if {![info exists directory($flow_type)]} {
        error "No directory configuration for flow type: $flow_type"
    }

    set flow_dirs $directory($flow_type)

    foreach {dir_type dir_path} $flow_dirs {
        set full_path [file join $run_dir $dir_path]
        file mkdir $full_path
        puts "Created directory: $full_path"
    }
}

# Path resolution and validation
proc ::CBFlow::Directory::get_flow_directory_path {flow_type dir_type run_dir} {
    global directory

    if {![info exists directory($flow_type)]} {
        return ""
    }

    set flow_dirs $directory($flow_type)
    if {![dict exists $flow_dirs $dir_type]} {
        return ""
    }

    return [file join $run_dir [dict get $flow_dirs $dir_type]]
}
```

#### Directory Configuration Integration
```tcl
# Load directory configuration from global arrays
proc ::CBFlow::Directory::load_directory_config {} {
    global directory
    variable directory_config

    # Convert global directory array to namespace variable
    array set directory_config [array get directory]

    # Validate directory configuration
    validate_directory_config
}
```

### `::CBFlow::Logo`
**Purpose**: Handles branding, identification, and system information display

#### Namespace Structure
```tcl
namespace eval ::CBFlow::Logo {
    # Namespace variables
    variable logo_config
    variable team_data
    variable version_info

    # Export public procedures
    namespace export {
        display_cbflow_logo
        get_team_information
        show_system_banner
        generate_run_header
        create_flow_identification
    }
}
```

#### Key Procedures
```tcl
# Logo display and branding
proc ::CBFlow::Logo::display_cbflow_logo {} {
    variable logo_config

    puts "============================================"
    puts "         CBFlow Physical Design"
    puts "       Version: $logo_config(version)"
    puts "       Build: $logo_config(build_date)"
    puts "============================================"
}

# Team and project information
proc ::CBFlow::Logo::get_team_information {} {
    variable team_data

    return [list \
        team_name $team_data(team_name) \
        project_name $team_data(project_name) \
        contact $team_data(contact_email) \
        manager $team_data(team_manager)]
}

# Run identification header
proc ::CBFlow::Logo::generate_run_header {flow_type design_name run_dir} {
    set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]

    puts "\n╔══════════════════════════════════════════════════════════════╗"
    puts "║                   CBFlow $flow_type Flow                    ║"
    puts "║ Design: [format "%-48s" $design_name] ║"
    puts "║ Run Directory: [format "%-43s" [file tail $run_dir]] ║"
    puts "║ Started: [format "%-47s" $timestamp] ║"
    puts "╚══════════════════════════════════════════════════════════════╝\n"
}
```

### `::CBFlow::Utilities`
**Purpose**: Common utility functions used across all CBFlow components

#### Namespace Structure
```tcl
namespace eval ::CBFlow::Utilities {
    # Namespace variables
    variable error_handlers
    variable logging_config
    variable debug_flags

    # Export public procedures
    namespace export {
        cbflow_log
        cbflow_error
        cbflow_debug
        validate_file_exists
        create_timestamp
        parse_configuration
        execute_with_timeout
    }
}
```

#### Key Procedures
```tcl
# Centralized logging system
proc ::CBFlow::Utilities::cbflow_log {level message {context ""}} {
    variable logging_config

    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set log_entry "[$timestamp] [$level]"

    if {$context ne ""} {
        append log_entry " \[$context\]"
    }

    append log_entry " $message"

    # Output to console and log file
    puts $log_entry

    if {[info exists logging_config(log_file)]} {
        set fd [open $logging_config(log_file) a]
        puts $fd $log_entry
        close $fd
    }
}

# Enhanced error handling
proc ::CBFlow::Utilities::cbflow_error {message {error_code ""} {context ""}} {
    variable error_handlers

    # Log error
    cbflow_log "ERROR" $message $context

    # Execute error handlers if configured
    if {[info exists error_handlers] && [llength $error_handlers] > 0} {
        foreach handler $error_handlers {
            catch {$handler $message $error_code $context}
        }
    }

    # Throw error
    if {$error_code ne ""} {
        error $message $error_code
    } else {
        error $message
    }
}

# Configuration parsing utilities
proc ::CBFlow::Utilities::parse_configuration {config_file} {
    if {![file exists $config_file]} {
        cbflow_error "Configuration file not found: $config_file"
    }

    # Source configuration file safely
    set old_errorInfo $::errorInfo
    set old_errorCode $::errorCode

    if {[catch {source $config_file} result]} {
        cbflow_error "Failed to parse configuration file $config_file: $result"
    }

    return $result
}
```

### `::CBFlow::NodeManagement`
**Purpose**: Node creation, management, and branch operations

#### Namespace Structure
```tcl
namespace eval ::CBFlow::NodeManagement {
    # Namespace variables
    variable node_database
    variable branch_tracking
    variable execution_history

    # Export public procedures
    namespace export {
        create_execution_node
        create_node_branch
        delete_node
        list_available_nodes
        get_node_status
        validate_node_dependencies
    }
}
```

#### Key Procedures
```tcl
# Node creation with validation
proc ::CBFlow::NodeManagement::create_execution_node {flow_type node_type node_name run_dir} {
    # Validate flow type and node type
    validate_flow_node_combination $flow_type $node_type

    # Check flat mode restrictions
    validate_flat_mode_restrictions $node_type $flow_type

    # Generate node configuration
    generate_node_setup $flow_type $node_type $node_name $run_dir

    # Update node database
    register_node $flow_type $node_type $node_name $run_dir

    ::CBFlow::Utilities::cbflow_log "INFO" "Created node: $node_name ($node_type)" "NodeManagement"
}

# Branch management
proc ::CBFlow::NodeManagement::create_node_branch {base_node branch_name} {
    variable branch_tracking

    # Validate base node exists
    if {![node_exists $base_node]} {
        ::CBFlow::Utilities::cbflow_error "Base node does not exist: $base_node"
    }

    # Create branch configuration
    set branch_config [create_branch_config $base_node $branch_name]

    # Register branch
    dict set branch_tracking $branch_name $branch_config

    ::CBFlow::Utilities::cbflow_log "INFO" "Created branch: $branch_name from $base_node" "NodeManagement"
}
```

### `::CBFlow::Validation`
**Purpose**: Quality assurance, validation, and verification functions

#### Namespace Structure
```tcl
namespace eval ::CBFlow::Validation {
    # Namespace variables
    variable validation_rules
    variable quality_metrics
    variable validation_history

    # Export public procedures
    namespace export {
        validate_input_files
        validate_configuration
        validate_flow_outputs
        check_quality_metrics
        generate_validation_report
    }
}
```

#### Key Procedures
```tcl
# Comprehensive input validation
proc ::CBFlow::Validation::validate_input_files {flow_type input_spec} {
    variable validation_rules

    set validation_errors {}

    foreach {file_type file_path} $input_spec {
        # Check file existence
        if {![file exists $file_path]} {
            lappend validation_errors "Missing $file_type file: $file_path"
            continue
        }

        # Apply file-type specific validation
        if {[dict exists $validation_rules $file_type]} {
            set validator [dict get $validation_rules $file_type]
            if {[catch {$validator $file_path} validation_result]} {
                lappend validation_errors "Invalid $file_type file $file_path: $validation_result"
            }
        }
    }

    if {[llength $validation_errors] > 0} {
        ::CBFlow::Utilities::cbflow_error "Input validation failed:\n[join $validation_errors "\n"]"
    }

    ::CBFlow::Utilities::cbflow_log "INFO" "Input validation passed for $flow_type" "Validation"
    return true
}

# Configuration validation
proc ::CBFlow::Validation::validate_configuration {config_arrays} {
    set validation_errors {}

    # Validate required configuration keys
    foreach array_name $config_arrays {
        upvar #0 $array_name config_array

        if {![array exists config_array]} {
            lappend validation_errors "Missing configuration array: $array_name"
            continue
        }

        # Apply array-specific validation rules
        validate_array_contents $array_name config_array validation_errors
    }

    if {[llength $validation_errors] > 0} {
        ::CBFlow::Utilities::cbflow_error "Configuration validation failed:\n[join $validation_errors "\n"]"
    }

    return true
}
```

## Namespace Integration Patterns

### Inter-Namespace Communication
```tcl
# Example: Directory namespace calling Utilities namespace
proc ::CBFlow::Directory::create_directory_with_logging {dir_path} {
    # Use utilities namespace for logging
    ::CBFlow::Utilities::cbflow_log "INFO" "Creating directory: $dir_path" "Directory"

    if {[catch {file mkdir $dir_path} error]} {
        # Use utilities namespace for error handling
        ::CBFlow::Utilities::cbflow_error "Failed to create directory $dir_path: $error" "" "Directory"
    }

    return true
}
```

### Namespace Configuration Loading
```tcl
# Centralized namespace initialization
proc ::CBFlow::initialize_namespaces {} {
    # Load configuration into each namespace
    ::CBFlow::Directory::load_directory_config
    ::CBFlow::Logo::load_logo_config
    ::CBFlow::Utilities::load_utilities_config
    ::CBFlow::NodeManagement::load_node_config
    ::CBFlow::Validation::load_validation_config

    ::CBFlow::Utilities::cbflow_log "INFO" "All namespaces initialized" "System"
}
```

## Advanced Namespace Features

### Dynamic Namespace Loading
```tcl
# Load namespace modules on demand
proc ::CBFlow::load_namespace_module {module_name} {
    set module_file "$::FLOW_DIR/utils/utilities/current/${module_name}_namespace.tcl"

    if {[file exists $module_file]} {
        source $module_file
        ::CBFlow::Utilities::cbflow_log "INFO" "Loaded namespace module: $module_name" "System"
    } else {
        ::CBFlow::Utilities::cbflow_error "Namespace module not found: $module_name"
    }
}
```

### Namespace Versioning
```tcl
# Namespace version management
namespace eval ::CBFlow::Version {
    variable namespace_versions

    proc register_namespace_version {namespace_name version} {
        variable namespace_versions
        dict set namespace_versions $namespace_name $version
    }

    proc get_namespace_version {namespace_name} {
        variable namespace_versions
        return [dict get $namespace_versions $namespace_name]
    }
}
```

### Plugin Namespace Support
```tcl
# Plugin namespace registration
proc ::CBFlow::register_plugin_namespace {plugin_name namespace_name} {
    # Validate plugin namespace
    if {![namespace exists $namespace_name]} {
        ::CBFlow::Utilities::cbflow_error "Plugin namespace does not exist: $namespace_name"
    }

    # Register plugin
    variable plugin_namespaces
    dict set plugin_namespaces $plugin_name $namespace_name

    ::CBFlow::Utilities::cbflow_log "INFO" "Registered plugin namespace: $plugin_name -> $namespace_name" "System"
}
```

## Namespace Documentation Standards

### Procedure Documentation
```tcl
# Standard documentation format for namespace procedures
proc ::CBFlow::Directory::create_flow_directories {flow_type run_dir} {
    # @description: Creates directory structure for specified flow type
    # @param flow_type: Flow type (SYNTH, FP, PNR, etc.)
    # @param run_dir: Base run directory path
    # @return: Boolean success status
    # @throws: Error if flow_type not found or directory creation fails
    # @example: ::CBFlow::Directory::create_flow_directories "FP" "/path/to/run"

    # Implementation...
}
```

### Namespace Usage Examples
```tcl
# Example usage patterns
namespace import ::CBFlow::Utilities::cbflow_log
namespace import ::CBFlow::Directory::create_flow_directories
namespace import ::CBFlow::Validation::validate_input_files

# Use imported procedures directly
cbflow_log "INFO" "Starting flow execution"
create_flow_directories $flow_type $run_dir
validate_input_files $flow_type $input_spec
```

## Best Practices

### Namespace Design Guidelines
1. **Single Responsibility**: Each namespace should have one clear purpose
2. **Consistent Naming**: Use clear, descriptive namespace and procedure names
3. **Minimal Dependencies**: Reduce inter-namespace dependencies where possible
4. **Clear Interfaces**: Export only necessary procedures
5. **Documentation**: Document all public procedures thoroughly

### Usage Guidelines
1. **Explicit Calls**: Use full namespace paths for clarity
2. **Selective Import**: Import only frequently used procedures
3. **Error Handling**: Use namespace-aware error handling
4. **Testing**: Test namespace isolation and integration
5. **Version Compatibility**: Maintain namespace version compatibility

### Performance Considerations
1. **Lazy Loading**: Load namespaces only when needed
2. **Procedure Caching**: Cache frequently accessed namespace procedures
3. **Memory Management**: Clean up namespace variables when appropriate
4. **Efficient Imports**: Minimize namespace imports for performance

---

CBFlow's namespace architecture provides a robust foundation for modular, maintainable, and extensible physical design automation while ensuring clean separation of concerns and preventing naming conflicts across the system.