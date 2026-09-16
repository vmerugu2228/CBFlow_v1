# CBFlow Makefile User Guides v1.0.0

This directory contains comprehensive user guides for the three CBFlow Makefiles.

## Available Guides

| Guide | Location | Description |
|-------|----------|-------------|
| [Core Makefile Guide](core-makefile-guide.md) | `core/Makefile` | Main CBFlow management commands |
| [Workspace Makefile Guide](workspace-makefile-guide.md) | `workspace/Makefile` | Workspace and run initialization |
| [Run Makefile Guide](run-makefile-guide.md) | `<run_directory>/Makefile` | Flow execution and stage management |

## Makefile Hierarchy

```
CBFlow/PD/
├── core/
│   └── Makefile              # Core Makefile - System management
│
└── workspace/
    ├── Makefile              # Workspace Makefile - Run creation
    │
    └── P0_run_<flow>_<name>/
        └── Makefile          # Run Makefile - Flow execution
```

## Quick Start

### 1. System Setup (Core Makefile)

```bash
cd core/
make help                    # Show all core commands
make manage_projects         # Manage projects
make init_workspace PROJECT=phoenix FLOW=PNR BLOCK=cpu
```

### 2. Workspace Initialization (Workspace Makefile)

```bash
cd workspace/
make init                    # Initialize workspace
make start_run CONFIG=user_config.tcl
```

### 3. Flow Execution (Run Makefile)

```bash
cd P0_run_PNR_cpu/
make help                    # Show flow commands
make all                     # Run complete flow
make release TAG=v1.0 TYPE=pnr_signoff
```

## Command Overview

### Core Makefile Commands

| Category | Commands |
|----------|----------|
| System | `help`, `status`, `validate`, `clean` |
| Configuration | `manage_flow`, `manage_node`, `manage_tech` |
| Workspace | `init_workspace`, `update_workspace` |
| Release | `release_flow`, `list_releases`, `release_info` |
| Project | `manage_projects` |
| Git | `git_create_workspace`, `git_commit_version`, `git_create_release` |

### Workspace Makefile Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize/reinitialize workspace |
| `start_run` | Create and start a new run |
| `list_runs` | List all existing runs |
| `run_status` | Check run status |
| `clean` | Remove all runs |

### Run Makefile Commands

| Command | Description |
|---------|-------------|
| `all` | Run complete flow |
| `<stage>` | Run specific stage |
| `mmmc_corners` | Show MMMC scenarios |
| `release` | Create release package |
| `add_node` | Add custom node |
| `list_nodes` | List all nodes |
| `clean` | Clean run directory |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v1.0.0 | December 2024 | Initial documentation |

---

*For additional documentation, see the [main documentation index](../README.md).*
