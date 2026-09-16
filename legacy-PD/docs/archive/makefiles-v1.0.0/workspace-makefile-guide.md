# CBFlow Workspace Makefile User Guide

**Version:** 1.0.0
**Location:** `workspace/Makefile` (or any initialized workspace directory)

This guide documents all available commands in the CBFlow Workspace Makefile, which manages the workspace environment and run creation for Physical Design flows.

---

## Table of Contents

1. [Overview](#overview)
2. [Getting Started](#getting-started)
3. [Initialization Commands](#initialization-commands)
4. [Run Management Commands](#run-management-commands)
5. [Environment Configuration](#environment-configuration)
6. [Workflow Examples](#workflow-examples)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The Workspace Makefile is a release-based workspace management system that provides:

- Release version management
- Run creation and management
- Environment initialization
- Run status monitoring

### Workspace Hierarchy

```
workspace/
├── Makefile                 # Workspace Makefile
├── .cbflow.env              # Shell environment (generated)
├── .cbflow.tcl              # TCL environment (generated)
├── user_config.tcl          # User configuration file
└── P0_run_PNR_test_001/     # Generated run directory
    └── Makefile             # Run Makefile
```

---

## Getting Started

### Prerequisites

1. CBFlow core directory accessible
2. Release version available (e.g., v1.0.0)
3. User configuration file created

### Basic Workflow

```bash
# 1. Navigate to workspace
cd workspace/

# 2. Initialize workspace
make init

# 3. Create and start a run
make start_run CONFIG=user_config.tcl

# 4. Navigate to run and execute
cd P0_run_PNR_test_001
make all
```

---

## Initialization Commands

### `make init`

Initialize or reinitialize the workspace environment.

```bash
make init [RELEASE_VERSION=vX.Y.Z]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| RELEASE_VERSION | No | Release version (default: v1.0.0) |

**Examples:**
```bash
# Initialize with default release
make init

# Initialize with specific release
make init RELEASE_VERSION=v2.0.0
```

**What It Does:**
1. Validates the release exists
2. Creates backup if `.cbflow.env` already exists
3. Generates `.cbflow.env` (shell environment)
4. Generates `.cbflow.tcl` (TCL environment)

**Generated Files:**

| File | Description |
|------|-------------|
| `.cbflow.env` | Shell environment with all component versions |
| `.cbflow.tcl` | TCL environment with release configuration |

**Output Example:**
```
═══════════════════════════════════════════════════════════════
  CBFlow Workspace Initialization
═══════════════════════════════════════════════════════════════

Configuration:
  Release Version: v1.0.0
  Core Directory:  /path/to/core
  Release Versions: /path/to/release_versions.tcl

Generating workspace environment from release...

═══════════════════════════════════════════════════════════════
Workspace initialized successfully!
═══════════════════════════════════════════════════════════════

Generated Files:
  .cbflow.env - Shell environment with all component versions
  .cbflow.tcl - TCL environment with release configuration

Next Steps:
  1. Edit user_config.tcl with your design specifics
  2. make start_run CONFIG=user_config.tcl
```

### Switching Releases

To switch to a different release version:

```bash
make init RELEASE_VERSION=v2.0.0
```

The system will:
1. Detect existing configuration
2. Show current vs new release
3. Ask for confirmation
4. Create timestamped backup in `.backup/` directory
5. Generate new environment files

---

## Run Management Commands

### `make start_run`

Create and start a new Physical Design flow run.

```bash
make start_run CONFIG=<config_file> [FORCE=1]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| CONFIG | Yes | TCL configuration file path |
| FORCE | No | Force recreate existing run (set to 1) |

**Examples:**
```bash
# Start a new run
make start_run CONFIG=user_config.tcl

# Force recreate an existing run
make start_run CONFIG=user_config.tcl FORCE=1

# Use a specific config file
make start_run CONFIG=my_test_config.tcl
```

**Configuration File Requirements:**

Your config file must include:
```tcl
set flow(run_name) "your_run_name"
set flow(type) "PNR"  # or SYNTH, FP, etc.
set project(phase) "P0"  # Optional, defaults to P0
```

**Run Directory Naming:**

Runs are created with the pattern:
```
{project_phase}_run_{flow_type}_{run_name}
```

Example: `P0_run_PNR_test_001`

**What Gets Created:**

| Item | Description |
|------|-------------|
| Run directory | Named per pattern above |
| Run Makefile | Flow-specific Makefile |
| Configuration | Consolidated config from release |
| Work directories | Stage-specific work areas |

**Output Example:**
```
═══════════════════════════════════════════════════════════════
  Starting Physical Design Flow
═══════════════════════════════════════════════════════════════

  Config File: user_config.tcl
  Release:     v1.0.0

Generating consolidated configuration...
Target run directory: P0_run_PNR_test_001
Configuration generation completed

Physical Design Flow setup completed successfully!
Next steps:
  1. cd P0_run_PNR_test_001
  2. make help     - Show available flow targets
  3. make all      - Run complete PNR flow
  4. make status   - Check run status
```

### `make list_runs`

List all existing run directories in the workspace.

```bash
make list_runs
```

**Output Example:**
```
Available Runs:
  P0_run_PNR_test_001     Status: Completed
  P0_run_SYNTH_syn_002    Status: Running
  P0_run_FP_fp_test       Status: Pending
```

### `make run_status`

Check the detailed status of a specific run.

```bash
make run_status RUN=<run_directory> [DETAILS=1] [LOGS=1] [WATCH=1]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| RUN | Yes | Run directory name |
| DETAILS | No | Show detailed stage information |
| LOGS | No | Show recent log entries |
| WATCH | No | Continuously watch status |

**Examples:**
```bash
# Basic status
make run_status RUN=P0_run_PNR_test_001

# Detailed status with stage breakdown
make run_status RUN=P0_run_PNR_test_001 DETAILS=1

# Status with recent logs
make run_status RUN=P0_run_PNR_test_001 LOGS=1

# Watch mode (continuous updates)
make run_status RUN=P0_run_PNR_test_001 WATCH=1
```

### `make clean`

Remove all run directories from the workspace.

```bash
make clean
```

**Warning:** This permanently deletes ALL run directories!

**Safety Features:**
- Shows list of directories to be deleted
- Requires explicit confirmation (y/Y)
- No recovery after deletion

**Output Example:**
```
WARNING: This will permanently delete ALL run directories!

The following directories will be deleted:
  P0_run_PNR_test_001
  P0_run_SYNTH_syn_002

Are you sure you want to continue? [y/N]: y

Cleaning all run directories...
All run directories cleaned
```

---

## Environment Configuration

### Release Configuration

The workspace uses a release-based configuration system:

| Variable | Description |
|----------|-------------|
| `RELEASE_VERSION` | Release version (e.g., v1.0.0) |
| `RELEASE_DIR` | Path to release directory |
| `RELEASE_VERSIONS_TCL` | TCL version configuration file |
| `RELEASE_VERSIONS_ENV` | Shell version configuration file |

### Exported Environment Variables

These variables are exported for child processes:

| Variable | Description |
|----------|-------------|
| `CBFLOW_REPO_ROOT` | Git repository root |
| `CBFLOW_CORE_DIR` | Core directory path |
| `CBFLOW_PROJECT_ROOT` | Project root path |
| `CBFLOW_RUN_DIR` | Current working directory |
| `CBFLOW_RELEASE_VERSION` | Active release version |
| `CBFLOW_RELEASE_DIR` | Release directory path |
| `CBFLOW_RELEASE_VERSIONS_TCL` | TCL versions file path |
| `CBFLOW_RELEASE_VERSIONS_ENV` | Shell versions file path |

### Environment Files

#### `.cbflow.env` (Shell Environment)

Contains all component versions and paths for shell scripts:

```bash
# CBFlow Environment Configuration
# Generated for release: v1.0.0

export CBFLOW_RELEASE_VERSION="v1.0.0"
export CBFLOW_CORE_DIR="/path/to/core"
export CBFLOW_START_RUN_SCRIPT="/path/to/start_run.tcl"
export CBFLOW_LIST_RUNS_SCRIPT="/path/to/list_runs.tcl"
export CBFLOW_STATUS_SCRIPT="/path/to/run_status.tcl"
export CBFLOW_GEN_CONFIG_SCRIPT="/path/to/gen_config.tcl"
# ... additional component versions
```

#### `.cbflow.tcl` (TCL Environment)

Contains release configuration for TCL scripts:

```tcl
# CBFlow TCL Environment
# Generated for release: v1.0.0

set ::env(CBFLOW_RELEASE_VERSION) "v1.0.0"
set ::env(CBFLOW_CORE_DIR) "/path/to/core"
# ... additional configuration
```

---

## Workflow Examples

### Example 1: Basic PNR Flow

```bash
# 1. Initialize workspace
cd workspace
make init RELEASE_VERSION=v1.0.0

# 2. Create configuration file
cat > pnr_config.tcl << 'EOF'
set flow(run_name) "pnr_test"
set flow(type) "PNR"
set project(phase) "P0"
set project(name) "phoenix"
# ... additional configuration
EOF

# 3. Start the run
make start_run CONFIG=pnr_config.tcl

# 4. Execute the flow
cd P0_run_PNR_pnr_test
make all
```

### Example 2: Multiple Concurrent Runs

```bash
# Create multiple configurations
make start_run CONFIG=config_timing.tcl
make start_run CONFIG=config_power.tcl
make start_run CONFIG=config_area.tcl

# List all runs
make list_runs

# Check status of each
make run_status RUN=P0_run_PNR_timing
make run_status RUN=P0_run_PNR_power
make run_status RUN=P0_run_PNR_area
```

### Example 3: Upgrading Release Version

```bash
# Check current release
make help  # Shows current release version

# Upgrade to new release
make init RELEASE_VERSION=v2.0.0

# Verify upgrade
make help  # Should show v2.0.0

# Note: Existing runs continue with old release
# New runs will use v2.0.0
```

### Example 4: Recreating a Failed Run

```bash
# First attempt failed
make start_run CONFIG=test_config.tcl

# Fix configuration issues in test_config.tcl
# Then force recreate
make start_run CONFIG=test_config.tcl FORCE=1
```

---

## Troubleshooting

### Common Issues

#### "Workspace not initialized"

**Error:**
```
Workspace Environment: Not initialized
Run 'make init' first to initialize the workspace
```

**Solution:**
```bash
make init
```

#### "Config file not found"

**Error:**
```
Error: Config file 'my_config.tcl' not found
```

**Solution:**
- Verify the file exists in the current directory
- Check the file path is correct
- Ensure proper file permissions

#### "Release not found"

**Error:**
```
Release v2.0.0 not found at /path/to/release.
Run 'make git_checkout_release RELEASE=v2.0.0' from core directory first.
```

**Solution:**
```bash
cd ../core
make git_checkout_release RELEASE=v2.0.0
cd ../workspace
make init RELEASE_VERSION=v2.0.0
```

#### "Run directory not found"

**Error:**
```
Error: Run directory 'P0_run_PNR_test' not found
```

**Solution:**
- Verify run was created: `make list_runs`
- Check the exact directory name
- Create the run: `make start_run CONFIG=your_config.tcl`

#### "Could not extract flow(run_name) or flow(type)"

**Error:**
```
Error: Could not extract flow(run_name) or flow(type) from config.tcl
```

**Solution:**
Ensure your config file contains:
```tcl
set flow(run_name) "your_run_name"
set flow(type) "PNR"  # or SYNTH, FP, etc.
```

### Backup Recovery

If you need to restore a previous configuration:

```bash
# List available backups
ls -la .backup/

# Restore a backup
cp .backup/.cbflow.env.backup.20241218_143022 .cbflow.env
```

---

## Command Quick Reference

| Command | Description |
|---------|-------------|
| `make help` | Show help and current status |
| `make init` | Initialize workspace |
| `make init RELEASE_VERSION=vX.Y.Z` | Initialize with specific release |
| `make start_run CONFIG=file.tcl` | Start new run |
| `make start_run CONFIG=file.tcl FORCE=1` | Force recreate run |
| `make list_runs` | List all runs |
| `make run_status RUN=name` | Check run status |
| `make run_status RUN=name DETAILS=1` | Detailed status |
| `make clean` | Remove all runs |

---

## Related Documentation

- [Core Makefile Guide](core-makefile-guide.md) - Core CBFlow commands
- [Run Makefile Guide](run-makefile-guide.md) - Flow execution commands

---

*Last Updated: December 2024*
