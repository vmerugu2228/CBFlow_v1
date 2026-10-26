# CBFlow - Physical Design Automation System

![CBFlow](https://img.shields.io/badge/Version-2.0.0-blue.svg)
![License](https://img.shields.io/badge/License-Proprietary-red.svg)
![Technology](https://img.shields.io/badge/Technology-Multi--Node-green.svg)

**CBFlow** is a comprehensive physical design automation framework for semiconductor chip design, supporting multiple specialized flows with hierarchical configuration management, parallel execution capabilities, and advanced flat mode execution.

## 🚀 Quick Start

```bash
# Initialize CBFlow environment
cd /path/to/CBFlow/PD/workspace
make init

# Start a synthesis flow
make start_run CONFIG=my_synth_config.tcl

# Monitor flow progress
make run_status

# List available nodes
make list_nodes
```

## 📋 System Overview

CBFlow provides a modular, scalable framework for physical design automation with:

- **11 Specialized Flow Types**: Comprehensive coverage of design stages
- **Hierarchical Configuration**: 4-level configuration system with validation
- **Parallel Execution**: Makefile-based orchestration with dependency tracking
- **Flat Mode Execution**: Merged execution model for optimized workflows
- **Version Management**: Structured script versioning with v1.0.0 standard
- **Real-time Monitoring**: Status tracking and dependency validation

## 🔧 Core Components

### Flow Types Supported
- **[SYNTH](flows/SYNTH.md)** - Logic Synthesis
- **[FP](flows/FP.md)** - Floorplanning
- **[PNR](flows/PNR.md)** - Place & Route
- **[PV](flows/PV.md)** - Physical Verification
- **[FCT](flows/FCT.md)** - Full Chip Timing
- **[LEC](flows/LEC.md)** - Logic Equivalence Check
- **[EMIR](flows/EMIR.md)** - Electromagnetic IR Analysis
- **[ECO](flows/ECO.md)** - Engineering Change Order
- **[CLP](flows/CLP.md)** - Clock Planning
- **[POPT](flows/POPT.md)** - Power Optimization
- **[FCFP](flows/FCFP.md)** - Full Chip Floorplan

### Architecture Components
- **[System Architecture](architecture/system-overview.md)** - Overall system design
- **[Configuration Hierarchy](architecture/configuration-hierarchy.md)** - 4-level config system
- **[Version Management](architecture/version-management.md)** - Script versioning
- **[Flat Mode](architecture/flat-mode.md)** - Merged execution model
- **[Namespaces](architecture/namespaces.md)** - CBFlow organization

## 📖 Documentation Structure

### For Users
- **[Getting Started](user-guides/getting-started.md)** - Initial setup and first run
- **[Configuration Guide](user-guides/configuration.md)** - How to configure flows
- **[Running Flows](user-guides/running-flows.md)** - Executing and monitoring
- **[Node Management](user-guides/node-management.md)** - Custom nodes and branches
- **[Troubleshooting](user-guides/troubleshooting.md)** - Common issues and solutions

### For Developers
- **[Contributing](developer/contributing.md)** - Development guidelines
- **[Script Development](developer/script-development.md)** - Creating new scripts
- **[Testing](developer/testing.md)** - Testing procedures
- **[API Reference](developer/api-reference.md)** - Internal APIs

### Makefile Documentation
- **[Main Makefile](makefiles/main-makefile.md)** - Core Makefile system
- **[Workspace Makefile](makefiles/workspace-makefile.md)** - Workspace management
- **[Run Makefile](makefiles/run-makefile.md)** - Generated run execution

## 🏗️ Key Features

### Advanced Execution Models
- **Regular Mode**: Individual stage execution with full flexibility
- **Flat Mode**: Merged execution for optimized workflow performance
- **Parallel Execution**: Multi-stage parallel processing with dependency tracking

### Configuration Management
- **Flow Level**: Flow-specific settings and stage definitions
- **Project Level**: Project-specific parameters and constraints
- **Technology Level**: Technology node configurations
- **User Level**: User-specific overrides and customizations

### Monitoring and Validation
- **Real-time Status**: Live progress tracking with dependency validation
- **Enhanced Logging**: Comprehensive logging with color-coded output
- **Error Detection**: Automatic error detection and reporting
- **Validation Framework**: Multi-level validation with critical error detection

## 🛠️ Tool Integration

CBFlow integrates with industry-standard EDA tools:
- **Cadence Innovus** - Place & Route, Floorplanning
- **Cadence Genus** - Logic Synthesis
- **Synopsys Design Compiler** - Synthesis
- **Mentor Calibre** - Physical Verification
- **Custom Tools** - Extensible tool integration framework

## 📊 Configuration Hierarchy

```
Flow Config     ←  Flow-specific stages, dependencies, subnodes
    ↓
Project Config  ←  Project constraints, design parameters
    ↓
Technology Config ←  Technology node settings, libraries
    ↓
User Config     ←  User overrides, custom settings
```

## 🔄 Execution Flow

1. **Environment Setup**: Load hierarchical configuration
2. **Dependency Resolution**: Calculate stage dependencies
3. **Parallel Execution**: Execute stages with dependency tracking
4. **Validation**: Validate results at each stage
5. **Status Reporting**: Real-time progress and error reporting

## 📝 Version Information

- **Current Version**: 2.0.0
- **Script Version Standard**: v1.0.0
- **Configuration Format**: Hierarchical TCL arrays
- **Makefile Format**: Auto-generated with dependency tracking

## 🤝 Support

For questions, issues, or contributions:
- Review the [Troubleshooting Guide](user-guides/troubleshooting.md)
- Check the [API Reference](developer/api-reference.md)
- Follow the [Contributing Guidelines](developer/contributing.md)

---

**CBFlow** - Enabling efficient, scalable physical design automation.