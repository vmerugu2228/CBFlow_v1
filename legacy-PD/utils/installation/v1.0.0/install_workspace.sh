#!/bin/bash
# ==============================================================================
# CBFlow Workspace Installation Script
# ==============================================================================
# Creates a standalone workspace that can be used anywhere on the filesystem
#
# Usage:
#   install_workspace.sh <target_directory>
#
# Example:
#   install_workspace.sh /my/designs/project_a
# ==============================================================================

set -e

# Detect CBFlow installation (this script lives in utils/installation/v1.0.0/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBFLOW_CORE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Validate CBFlow installation
if [ ! -f "$CBFLOW_CORE_DIR/Makefile" ]; then
    echo "ERROR: Cannot find CBFlow core at: $CBFLOW_CORE_DIR"
    exit 1
fi

# Get target directory
TARGET_DIR="$1"

if [ -z "$TARGET_DIR" ]; then
    echo "Usage: $0 <target_directory>"
    echo ""
    echo "Example:"
    echo "  $0 /my/designs/project_a"
    exit 1
fi

# Create target directory
mkdir -p "$TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"  # Get absolute path

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CBFlow Workspace Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Installing to: $TARGET_DIR"
echo "  CBFlow Core:   $CBFLOW_CORE_DIR"
echo ""

# Generate Makefile
cat > "$TARGET_DIR/Makefile" << 'EOF'
# ==============================================================================
# CBFlow Standalone Workspace Makefile
# ==============================================================================
# This workspace can be located anywhere on the filesystem.
# Edit CORE_DIR below to point to your CBFlow installation.
# ==============================================================================

#===============================================================================
# CBFLOW INSTALLATION PATH
#===============================================================================
# Edit this to point to your CBFlow core directory
CORE_DIR ?= __CBFLOW_CORE_DIR__

# Verify CORE_DIR exists
ifeq ($(wildcard $(CORE_DIR)/Makefile),)
    $(error CBFlow core not found at: $(CORE_DIR). Please update CORE_DIR in this Makefile)
endif

#===============================================================================
# WORKSPACE CONFIGURATION
#===============================================================================
WORKSPACE_DIR := $(shell pwd)
export CBFLOW_CORE_DIR := $(CORE_DIR)
export CBFLOW_PROJECT_ROOT := $(shell dirname "$(CORE_DIR)")
export CBFLOW_RUN_DIR := $(WORKSPACE_DIR)

#===============================================================================
# RELEASE CONFIGURATION
#===============================================================================
RELEASE_VERSION ?= v1.0.0

RELEASE_DIR := $(CORE_DIR)/workarea/releases/$(RELEASE_VERSION)
RELEASE_VERSIONS_TCL := $(RELEASE_DIR)/release_versions.tcl
RELEASE_VERSIONS_ENV := $(RELEASE_DIR)/release_versions.env

# Verify release exists
ifeq ($(wildcard $(RELEASE_VERSIONS_TCL)),)
    $(error Release $(RELEASE_VERSION) not found at $(RELEASE_DIR). Run 'make git_checkout_release RELEASE=$(RELEASE_VERSION)' from CBFlow core first)
endif

export CBFLOW_RELEASE_VERSION := $(RELEASE_VERSION)
export CBFLOW_RELEASE_DIR := $(RELEASE_DIR)
export CBFLOW_RELEASE_VERSIONS_TCL := $(RELEASE_VERSIONS_TCL)
export CBFLOW_RELEASE_VERSIONS_ENV := $(RELEASE_VERSIONS_ENV)

#===============================================================================
# ENVIRONMENT DETECTION
#===============================================================================
CBFLOW_ENV_FILE := $(wildcard .cbflow.env)

ifneq ($(CBFLOW_ENV_FILE),)
    CBFLOW_ENV_LOADED := true
else
    CBFLOW_ENV_LOADED := false
endif

#===============================================================================
# COLORS
#===============================================================================






.DEFAULT_GOAL := help

.PHONY: help init start_run list_runs run_status clean

#===============================================================================
# HELP
#===============================================================================
help:
	@if [ "$(CBFLOW_ENV_LOADED)" = "false" ]; then \
		echo ""; \
		echo "$(
		echo "$(
		echo "$(
		echo ""; \
		echo "$(
		echo ""; \
		echo "$(
		echo "  $(
		echo "  $(
		echo ""; \
		echo "$(
		echo "  CBFlow Core:     $(CORE_DIR)"; \
		echo "  Workspace:       $(WORKSPACE_DIR)"; \
		echo "  Current Release: $(
		echo ""; \
		echo "$(
		echo ""; \
		exit 1; \
	fi
	@echo ""
	@echo "$(
	@echo "$(
	@echo "$(
	@echo ""
	@echo "$(
	@echo "$(
	@echo "   CBFlow Core:    $(CORE_DIR)"
	@echo ""
	@echo "$(
	@echo "  $(
	@echo "  $(
	@echo ""
	@echo "$(
	@echo "  $(
	@echo "  $(
	@echo "  $(
	@echo "  $(
	@echo "  $(
	@echo ""
	@echo "$(
	@echo "  make start_run CONFIG=user_config.tcl"
	@echo "  make start_run CONFIG=my_test.tcl FORCE=1"
	@echo "  make list_runs"
	@echo "  make run_status RUN=P0_run_PNR_test_001"
	@echo ""
	@echo "$(
	@echo ""

#===============================================================================
# INIT
#===============================================================================
init:
	@echo ""
	@echo "$(
	@echo "$(
	@echo "$(
	@echo ""
	@echo "$(
	@echo "  Release Version: $(
	@echo "  CBFlow Core:     $(CORE_DIR)"
	@echo "  Workspace:       $(WORKSPACE_DIR)"
	@echo "  Release File:    $(RELEASE_VERSIONS_TCL)"
	@echo ""
	@if [ -f .cbflow.env ]; then \
		echo "$(
		echo ""; \
		current_version=$$(grep "CBFLOW_RELEASE_VERSION" .cbflow.env 2>/dev/null | cut -d'=' -f2 | tr -d '"'); \
		if [ -n "$$current_version" ]; then \
			echo "  Current Release: $(
		fi; \
		echo "  New Release:     $(
		echo ""; \
		echo "$(
		echo ""; \
		read -p "Do you want to proceed? (y/N): " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo ""; \
			echo "$(
			echo ""; \
			exit 0; \
		fi; \
	fi
	@echo ""
	@echo "$(
	@tclsh $(CORE_DIR)/utils/utilities/v2.0.0/workspace_init.tcl \
		$(RELEASE_VERSIONS_TCL) \
		$(CBFLOW_CORE_DIR) \
		$(WORKSPACE_DIR)
	@echo ""
	@echo "$(
	@echo "$(
	@echo "$(
	@echo ""
	@echo "$(
	@echo "  .cbflow.env - Shell environment with all component versions"
	@echo "  .cbflow.tcl - TCL environment with release configuration"
	@echo ""
	@echo "$(
	@echo "  1. Copy user_config_template.tcl to your_design.tcl"
	@echo "  2. Edit your_design.tcl with your design specifics"
	@echo "  3. make start_run CONFIG=your_design.tcl"
	@echo ""

#===============================================================================
# START_RUN
#===============================================================================
start_run:
	@if [ "$(CBFLOW_ENV_LOADED)" = "false" ]; then \
		echo "$(
		exit 1; \
	fi
	@if [ -z "$(CONFIG)" ]; then \
		echo "$(
		echo "Usage: make start_run CONFIG=your_config.tcl"; \
		exit 1; \
	fi
	@if [ ! -f "$(CONFIG)" ]; then \
		echo "$(
		exit 1; \
	fi
	@echo ""
	@echo "$(
	@echo "$(
	@echo "$(
	@echo ""
	@echo "  Config File: $(
	@echo "  Release:     $(
	@echo ""
	@set -a && . ./.cbflow.env && set +a && \
		if [ "$(FORCE)" = "1" ]; then \
			tclsh $$CBFLOW_START_RUN_SCRIPT -f $(CONFIG); \
		else \
			tclsh $$CBFLOW_START_RUN_SCRIPT $(CONFIG); \
		fi
	@echo ""
	@echo "$(
	@run_name=$$(grep "set flow(run_name)" $(CONFIG) | head -1 | sed 's/.*set flow(run_name)[[:space:]]*"\([^"\]*\)".*/\1/'); \
	flow_type=$$(grep "set flow(type)" $(CONFIG) | head -1 | sed 's/.*set flow(type)[[:space:]]*"\([^"\]*\)".*/\1/'); \
	project_phase=$$(grep "set project(phase)" $(CONFIG) | head -1 | sed 's/.*set project(phase)[[:space:]]*"\([^"\]*\)".*/\1/'); \
	if [ -z "$$project_phase" ]; then project_phase="P0"; fi; \
	if [ -n "$$run_name" ] && [ -n "$$flow_type" ]; then \
		run_dir="$${project_phase}_run_$${flow_type}_$${run_name}"; \
		echo "$(
		if [ -d "$$run_dir" ]; then \
			echo "$(
			set -a && . ./.cbflow.env && set +a && \
				tclsh $$CBFLOW_GEN_CONFIG_SCRIPT generate "$$run_dir" "$(CONFIG)"; \
			if [ $$? -eq 0 ]; then \
				echo "$(
				echo ""; \
				echo "$(
				echo "$(
				echo "  1. $(
				echo "  2. $(
				echo "  3. $(
				echo "  4. $(
			else \
				echo "$(
			fi; \
		else \
			echo "$(
		fi; \
	else \
		echo "$(
		echo "$(
		echo "  set flow(run_name) \"your_run_name\""; \
		echo "  set flow(type) \"PNR|SYNTH|SIGNOFF\""; \
	fi
	@echo ""

#===============================================================================
# LIST_RUNS
#===============================================================================
list_runs:
	@if [ "$(CBFLOW_ENV_LOADED)" = "false" ]; then \
		echo "$(
		exit 1; \
	fi
	@set -a && . ./.cbflow.env && set +a && \
		if [ -f "$$CBFLOW_LIST_RUNS_SCRIPT" ]; then \
			tclsh $$CBFLOW_LIST_RUNS_SCRIPT; \
		else \
			echo "$(
			exit 1; \
		fi

#===============================================================================
# RUN_STATUS
#===============================================================================
run_status:
	@if [ "$(CBFLOW_ENV_LOADED)" = "false" ]; then \
		echo "$(
		exit 1; \
	fi
	@if [ -z "$(RUN)" ]; then \
		echo "$(
		echo "Usage: make run_status RUN=run_directory_name"; \
		echo "Available runs:"; \
		ls -d *_run_*_* 2>/dev/null | head -5 | sed 's/^/  /' || echo "  No runs found"; \
		exit 1; \
	fi
	@if [ ! -d "$(RUN)" ]; then \
		echo "$(
		exit 1; \
	fi
	@set -a && . ./.cbflow.env && set +a && \
		cmd="tclsh $$CBFLOW_STATUS_SCRIPT"; \
		if [ "$(DETAILS)" = "1" ]; then cmd="$$cmd -d"; fi; \
		if [ "$(LOGS)" = "1" ]; then cmd="$$cmd -l"; fi; \
		if [ "$(WATCH)" = "1" ]; then cmd="$$cmd -w"; fi; \
		$$cmd $(RUN)

#===============================================================================
# CLEAN
#===============================================================================
clean:
	@if [ "$(CBFLOW_ENV_LOADED)" = "false" ]; then \
		echo "$(
		exit 1; \
	fi
	@echo "$(
	@echo ""
	@echo "The following directories will be deleted:"
	@ls -d *_run_*_* 2>/dev/null | sed 's/^/  /' || echo "  $(
	@echo ""
	@echo -n "$(
	@read confirm && [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || (echo "$(
	@echo ""
	@echo "$(
	@rm -rf *_run_*_*
	@echo "$(
EOF

# Replace placeholder with actual CORE_DIR
sed -i.bak "s|__CBFLOW_CORE_DIR__|$CBFLOW_CORE_DIR|g" "$TARGET_DIR/Makefile"
rm -f "$TARGET_DIR/Makefile.bak"

echo "  ✓ Generated Makefile"

# Copy user config template
cp "$CBFLOW_CORE_DIR/../workspace/user_config_template.tcl" "$TARGET_DIR/"
echo "  ✓ Copied user_config_template.tcl"

# Generate README
cat > "$TARGET_DIR/README.md" << 'EOF'
# CBFlow Standalone Workspace

This is a standalone CBFlow workspace that can be located anywhere on your filesystem.

## Quick Start

### 1. Initialize Workspace

```bash
make init RELEASE_VERSION=v1.0.0
```

This will:
- Source the release version file from CBFlow installation
- Generate `.cbflow.env` and `.cbflow.tcl` with all component versions
- Set up the workspace environment

### 2. Create Your Design Configuration

```bash
cp user_config_template.tcl my_design.tcl
# Edit my_design.tcl with your design specifics
```

### 3. Start a Run

```bash
make start_run CONFIG=my_design.tcl
```

## Configuration

The CBFlow installation path is configured in the `Makefile`:

```makefile
CORE_DIR ?= /path/to/cbflow/core
```

To use a different CBFlow installation, edit this line in the Makefile.

## Available Commands

```bash
make help                                 # Show all available commands
make init                                 # Initialize workspace (default release)
make init RELEASE_VERSION=v2.0.0         # Initialize with specific release
make start_run CONFIG=my_design.tcl      # Start a new run
make start_run CONFIG=my_design.tcl FORCE=1  # Force recreate existing run
make list_runs                            # List all runs in this workspace
make run_status RUN=P0_run_PNR_test_001  # Check run status
make clean                                # Clean all run directories
```

## Workspace Structure

After initialization and running designs:

```
workspace/
├── Makefile                      # Workspace control
├── user_config_template.tcl      # Template for design configs
├── my_design.tcl                 # Your design config
├── .cbflow.env                   # Generated environment (shell)
├── .cbflow.tcl                   # Generated environment (TCL)
└── P0_run_PNR_test_001/          # Generated run directory
    ├── Makefile                  # Run-specific makefile
    ├── work/                     # Working files
    ├── logs/                     # Log files
    └── setup/                    # Setup files
```

## Switching Releases

To switch to a different CBFlow release:

```bash
make init RELEASE_VERSION=v2.0.0
```

This will update your workspace environment to use the new release versions.

## Notes

- This workspace is completely independent of the CBFlow git repository
- All component versions come from the release you initialize with
- The workspace can be moved to any location (just update CORE_DIR in Makefile)
- Multiple workspaces can share the same CBFlow installation
EOF

echo "  ✓ Generated README.md"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Workspace installed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Location: $TARGET_DIR"
echo ""
echo "  Next steps:"
echo "    1. cd $TARGET_DIR"
echo "    2. make init RELEASE_VERSION=v1.0.0"
echo "    3. cp user_config_template.tcl my_design.tcl"
echo "    4. Edit my_design.tcl with your design specifics"
echo "    5. make start_run CONFIG=my_design.tcl"
echo ""
echo "  For help: make help"
echo ""
