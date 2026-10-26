# Workspace Makefile Documentation

## Overview

The Workspace Makefile (`/workspace/Makefile`) is the central control point for CBFlow run management and environment setup. It provides commands for initializing environments, starting flows, monitoring progress, and managing runs.

**Location**: `/Users/vmerugu/projects/CBFlow/CBFlow/PD/workspace/Makefile`
**Purpose**: Run management, environment setup, and flow execution control

## Key Features

- **Environment Management**: Automatic CBFlow environment setup and validation
- **Run Lifecycle**: Complete run creation, execution, and monitoring
- **Status Monitoring**: Real-time progress tracking and dependency validation
- **Node Management**: Custom node creation and branch management

## Environment Detection

### CBFlow Environment Files
The Makefile automatically detects and loads CBFlow environment:

```makefile
# Check for CBFlow environment file
CBFLOW_ENV_FILE := $(wildcard .cbflow.env)

# Load environment variables if .cbflow.env exists
ifneq ($(CBFLOW_ENV_FILE),)
    CORE_UTILS_ROOT := ../core/utils/utilities/v1.0.0
    FLOW_SCRIPT := $(CORE_UTILS_ROOT)/start_run.tcl
    LIST_SCRIPT := $(CORE_UTILS_ROOT)/list_runs.tcl
    STATUS_SCRIPT := $(CORE_UTILS_ROOT)/run_status.tcl
    CBFLOW_ENV_LOADED := true
else
    CBFLOW_ENV_LOADED := false
endif
```

### Environment States
- **Loaded**: CBFlow environment detected and configured
- **Not Loaded**: Environment requires initialization

## Core Commands

### 1. Environment Management

#### `make init`
- **Purpose**: Initialize CBFlow environment in workspace
- **Functions**:
  - Creates `.cbflow.env` environment file
  - Sets up core script paths
  - Configures tool integration
- **Usage**: `make init`
- **Requirements**: Must be run before other commands

#### `make help`
- **Purpose**: Display available commands and system status
- **Behavior**:
  - Shows error if environment not initialized
  - Displays comprehensive command list if initialized
- **Usage**: `make help`

### 2. Run Management

#### `make start_run`
- **Purpose**: Create and initialize new CBFlow run
- **Parameters**: `CONFIG=<config_file>` - Configuration file path
- **Functions**:
  - Validates configuration
  - Creates run directory
  - Generates run-specific Makefile
  - Sets up environment files
- **Usage**: `make start_run CONFIG=my_config.tcl`

#### `make list_runs`
- **Purpose**: List all available runs in workspace
- **Implementation**: Uses `list_runs.tcl` script
- **Output**: Formatted list of run directories with status
- **Usage**: `make list_runs`

#### `make run_status`
- **Purpose**: Show detailed status of current or specified run
- **Parameters**: `RUN=<run_directory>` (optional)
- **Functions**:
  - Shows stage completion status
  - Displays dependency information
  - Reports errors and warnings
- **Usage**:
  - `make run_status` (current directory)
  - `make run_status RUN=P0_run_SYNTH_test_001`

### 3. Node Management

#### `make add_node`
- **Purpose**: Add custom node to current run
- **Parameters**:
  - `NODE=<node_name>` - Name of new node
  - `TYPE=<node_type>` - Type (must match flow stages)
  - `DEP=<dependencies>` - Comma-separated dependencies
- **Validation**: Enforces flat mode restrictions
- **Usage**: `make add_node NODE=synth1 TYPE=synthesis DEP=inputs`

#### `make delete_node`
- **Purpose**: Remove custom node from current run
- **Parameters**: `NODE=<node_name>` - Node to remove
- **Safety**: Validates dependencies before removal
- **Usage**: `make delete_node NODE=synth1`

#### `make create_branch`
- **Purpose**: Create execution branch from existing node
- **Parameters**:
  - `NODE=<start_node>` - Starting node for branch
  - `DEP=<dependency>` - Branch dependency (optional)
- **Restrictions**: Blocked in flat mode
- **Usage**: `make create_branch NODE=place1 DEP=inputs`

#### `make delete_branch`
- **Purpose**: Remove entire execution branch
- **Parameters**: `NODE=<start_node>` - Starting node of branch
- **Behavior**: Removes all downstream nodes in branch
- **Usage**: `make delete_branch NODE=place1`

#### `make list_nodes`
- **Purpose**: Display all nodes in current flow
- **Output**:
  - Base flow nodes with dependencies
  - Custom nodes with types and dependencies
  - Flat mode vs regular mode indication
- **Usage**: `make list_nodes`

### 4. Utility Commands

#### `make clean`
- **Purpose**: Clean workspace temporary files
- **Actions**: Removes temporary files and logs
- **Usage**: `make clean`

## Script Integration

### Core Scripts
The workspace Makefile integrates with versioned CBFlow scripts:

- **start_run.tcl**: Run creation and initialization
- **list_runs.tcl**: Run discovery and listing
- **run_status.tcl**: Status monitoring and reporting
- **generate_config.tcl**: Configuration generation
- **gen_run_makefile.tcl**: Run Makefile generation

### Script Path Resolution
```makefile
# Extract paths from environment file
CORE_UTILS_ROOT := ../core/utils/utilities/v1.0.0
GENERATE_CONFIG_SCRIPT := $(shell grep "^export SCRIPTS_ROOT=" .cbflow.env | cut -d'"' -f2)/generation/v1.0.0/generate_config.tcl
GEN_MAKEFILE_SCRIPT := $(shell grep "^export SCRIPTS_ROOT=" .cbflow.env | cut -d'"' -f2)/generation/v1.0.0/gen_run_makefile.tcl
```

## Color-Coded Output

The Makefile provides visual feedback through color coding:

```makefile
COLOR_GREEN := \033[32m    # Success messages
COLOR_CYAN := \033[36m     # Information
COLOR_YELLOW := \033[33m   # Warnings
COLOR_RED := \033[31m      # Errors
COLOR_RESET := \033[0m     # Reset formatting
```

### Status Indicators
- **✅ CBFlow Environment: Loaded** - Environment ready
- **❌ CBFlow Environment: Not initialized** - Requires `make init`
- **⚠️ Warning messages** - Non-fatal issues
- **❌ Error messages** - Fatal issues requiring attention

## Environment Initialization Process

### 1. Detection Phase
- Check for existing `.cbflow.env` file
- Validate core script availability
- Determine initialization status

### 2. Initialization Phase (make init)
- Create environment configuration
- Set up script paths and tool integration
- Validate core system availability
- Generate initial configuration templates

### 3. Validation Phase
- Verify script accessibility
- Check tool integration
- Validate configuration hierarchy
- Confirm workspace readiness

## Run Creation Workflow

### 1. Configuration Validation
```bash
make start_run CONFIG=my_config.tcl
```
- Validates TCL configuration syntax
- Checks required parameters
- Verifies flow type compatibility

### 2. Directory Creation
- Creates run directory with timestamp
- Sets up subdirectory structure
- Copies configuration files

### 3. Environment Setup
- Generates run-specific environment files
- Creates `.run.cbflow.tcl` or `.run.cbflow.env`
- Sets up tool-specific configurations

### 4. Makefile Generation
- Calls `gen_run_makefile.tcl`
- Creates stage-specific makefiles
- Sets up dependency tracking

## Integration with Run Makefiles

The workspace Makefile creates run-specific makefiles that:
- Source run-specific environments
- Define stage execution targets
- Implement dependency tracking
- Support both flat and regular execution modes

## Error Handling

### Common Error Scenarios
1. **Environment Not Initialized**
   - Error: Commands fail with initialization message
   - Solution: Run `make init`

2. **Configuration File Not Found**
   - Error: `start_run` fails with file not found
   - Solution: Verify CONFIG parameter and file path

3. **Invalid Node Type**
   - Error: `add_node` fails with type validation
   - Solution: Use `make list_nodes` to see valid types

4. **Flat Mode Violations**
   - Error: `create_branch` blocked in flat mode
   - Solution: Use regular mode or appropriate node management

### Debug Information
- Check `.cbflow.env` for environment configuration
- Verify script paths are accessible
- Use `make run_status` for detailed run information
- Check run directory logs for execution details

## Best Practices

### Workspace Management
- Always run `make init` in new workspaces
- Use descriptive configuration file names
- Maintain separate workspaces for different projects
- Regular cleanup of completed runs

### Run Management
- Use meaningful run names in configurations
- Monitor runs with `make run_status`
- Complete runs before starting new ones
- Archive completed runs for reference

### Node Management
- Understand flow stage dependencies before adding nodes
- Use flat mode for optimized execution
- Create branches only when necessary in regular mode
- Document custom node purposes

---

The workspace Makefile serves as the primary interface for CBFlow users, providing intuitive commands for environment setup, run management, and flow execution.