# CBFlow Core Makefile User Guide

**Version:** 1.0.0
**Location:** `core/Makefile`

This guide documents all available commands in the CBFlow Core Makefile, which is the primary interface for managing the CBFlow Physical Design system.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Core Commands](#core-commands)
3. [Interactive Configuration Management](#interactive-configuration-management)
4. [Version Control Commands](#version-control-commands)
5. [Workspace Management](#workspace-management)
6. [Release Management](#release-management)
7. [Project Management](#project-management)
8. [Git-Based Versioning](#git-based-versioning)
9. [Email Notifications](#email-notifications)
10. [Utility Commands](#utility-commands)
11. [Legacy Commands](#legacy-commands)

---

## Getting Started

### Prerequisites

- Git repository properly cloned
- TCL shell (`tclsh`) available
- Python 3 available
- Bash shell

### Basic Usage

Navigate to the `core/` directory and run:

```bash
cd CBFlow/PD/core
make help
```

---

## Core Commands

### `make help`

Display all available commands and their descriptions.

```bash
make help
```

### `make status`

Show the current status of the CBFlow system including version information and validation state.

```bash
make status
```

### `make validate`

Validate the entire Flow Management System including version control and releases.

```bash
make validate
```

**Output:**
- Validates version control configuration
- Checks release validity
- Reports any issues found

### `make clean`

Clean temporary files and operation logs.

```bash
make clean
```

---

## Interactive Configuration Management

These commands launch interactive TCL-based configuration managers.

### `make manage_flow`

Interactively manage flow types (SYNTH, PNR, FP, etc.).

```bash
make manage_flow
```

**Capabilities:**
- Add new flows
- Delete existing flows
- Rename flows
- View flow details

### `make manage_node`

Interactively manage nodes and subnodes within flows.

```bash
make manage_node
```

**Capabilities:**
- Add new nodes (Options 1-3)
- Delete nodes
- Rename nodes
- Add subnodes (Options 4-6)
- Delete subnodes
- Rename subnodes
- Command file validation for execution nodes

### `make manage_subnode`

Redirects to `manage_node` (subnode operations are options 4-6).

```bash
make manage_subnode
```

### `make manage_tech`

Interactively manage technology configurations (e.g., TSMC 7nm).

```bash
make manage_tech
```

**Capabilities:**
- Add technology nodes
- Modify technology parameters
- View technology settings

### `make validate_flow`

Validate the current CBFlow configuration for errors.

```bash
make validate_flow
```

---

## Version Control Commands

### `make list_versions`

List all available versions for a specific directory/component.

```bash
make list_versions DIR=<directory>
```

**Examples:**
```bash
make list_versions DIR=config
make list_versions DIR=utils/utilities
```

### `make add_directory`

Add a new directory to version control.

```bash
make add_directory DIR=<directory> DESC="<description>" [VERSION=<version>] [GIT=true|false]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| DIR | Yes | Directory path to add |
| DESC | Yes | Description of the directory |
| VERSION | No | Initial version (default: v1.0.0) |
| GIT | No | Enable Git tracking (default: true) |

### `make list_directories`

List all directories under version control.

```bash
make list_directories
```

### `make show_versions`

Display available component versions across the system.

```bash
make show_versions
```

---

## Workspace Management

### `make init_workspace`

Initialize a new block workspace for a specific project and flow.

```bash
make init_workspace PROJECT=<name> FLOW=<type> BLOCK=<block_name> [RELEASE_VERSION=vX.Y.Z]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| PROJECT | Yes | Project name (e.g., phoenix) |
| FLOW | Yes | Flow type (SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP, SYNTH_PNR) |
| BLOCK | Yes | Block from design hierarchy |
| RELEASE_VERSION | No | Override auto-detected release version |

**Examples:**
```bash
make init_workspace PROJECT=phoenix FLOW=SYNTH BLOCK=cpu_core
make init_workspace PROJECT=phoenix FLOW=PNR BLOCK=cpu_core
make init_workspace PROJECT=phoenix FLOW=FP BLOCK=chip_top RELEASE_VERSION=v1.0.0
```

**Generated Files:**
- `.cbflow.config` - Project, flow, block, release configuration
- `Makefile` - Workspace Makefile
- `user_config_template.tcl` - Template for design configs
- `README.md` - Block-specific usage instructions

### `make update_workspace`

Update an existing workspace to use the current release version.

```bash
make update_workspace TARGET=<workspace_directory>
```

**Examples:**
```bash
make update_workspace TARGET=/my/designs/phoenix_ws
make update_workspace TARGET=/tmp/test_workspace
```

**Features:**
- Detects current project and release
- Compares with current release association
- Offers to update if different
- Creates configuration backups

---

## Release Management

### `make release_flow`

Create a new CBFlow release with changelog.

```bash
make release_flow DESC="<description>" [VERSION_TYPE=major|minor|patch]
```

**Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| DESC | Yes | Release description |
| VERSION_TYPE | No | Version increment type (default: patch) |
| VERSION | No | Explicit version number |
| MILESTONE | No | Milestone tag |
| VERSIONS | No | Component versions |

**Examples:**
```bash
make release_flow DESC="New features" VERSION_TYPE=minor
make release_flow DESC="Bug fixes" VERSION_TYPE=patch
make release_flow DESC="Major update" VERSION_TYPE=major
make release_flow VERSION=v2.0.0 DESC="Explicit version release"
```

### `make list_releases`

List all available flow releases.

```bash
make list_releases
```

### `make release_info`

Show detailed information about a specific release.

```bash
make release_info RELEASE=<version>
```

**Example:**
```bash
make release_info RELEASE=v2.0.0
```

### `make release_help`

Display detailed help for release management commands.

```bash
make release_help
```

---

## Project Management

### `make manage_projects`

Interactive Python-based project management interface.

```bash
make manage_projects
```

**Capabilities:**
- Add new projects with detailed information
- Edit existing project details (flow owners only)
- Toggle project status: active/inactive (flow owners only)
- Update release associations (flow owners only)
- View project information

**Project Information Includes:**
- Chip lead
- Flow owners (frontend, backend, verification)
- Technology node
- Status (active/inactive) and tags
- Associated release version

**Access Control:**
- Only flow owners can edit projects or change status
- Only flow owners can update release associations
- Projects cannot be deleted, only marked inactive
- Only active projects can be associated with releases

---

## Git-Based Versioning

### Version Management

#### `make git_create_version`

Create a new version using Git branches.

```bash
make git_create_version DIR=<component> VERSION=<version> [DESC="<description>"]
```

**Examples:**
```bash
make git_create_version DIR=config VERSION=v2.0.0 DESC="New features"
make git_create_version DIR=cmds/SYNTH VERSION=v2.0.0
```

#### `make git_set_current`

Set the current version for a component.

```bash
make git_set_current DIR=<component> VERSION=<version>
```

#### `make git_get_current`

Get the current version of a component.

```bash
make git_get_current DIR=<component>
```

#### `make git_diff_versions`

Compare two versions of a component.

```bash
make git_diff_versions DIR=<component> V1=<version1> V2=<version2>
```

**Example:**
```bash
make git_diff_versions DIR=config V1=v1.0.0 V2=v2.0.0
```

### Workspace Management (Git-Based)

#### `make git_create_workspace`

Create a user-specific workspace using Git worktree.

```bash
make git_create_workspace DIR=<component> [FORCE=true]
```

**Features:**
- Creates workspace at: `workarea/worktrees/$(whoami)/<component>/workspace`
- Creates branch: `<component>/workspace-$(whoami)`
- Multiple users can work on same component simultaneously

**Examples:**
```bash
make git_create_workspace DIR=gui
make git_create_workspace DIR=config/flow
make git_create_workspace DIR=gui FORCE=true  # Recreate workspace
```

#### `make git_commit_version`

Commit workspace changes and create a new version.

```bash
make git_commit_version DIR=<component> TYPE=<type> [DESC="<description>"]
# or
make git_commit_version DIR=<component> VERSION=<version> [DESC="<description>"]
```

**TYPE Values:**
| Type | Description |
|------|-------------|
| patch | Increment patch version (x.y.Z+1) |
| minor | Increment minor version (x.Y+1.0) |
| major | Increment major version (X+1.0.0) |

**Examples:**
```bash
make git_commit_version DIR=gui TYPE=patch DESC="Bug fixes"
make git_commit_version DIR=gui TYPE=minor DESC="New features"
make git_commit_version DIR=config VERSION=v2.0.0 DESC="Explicit version"
```

#### `make git_promote_version`

Promote a version to be the current version.

```bash
make git_promote_version DIR=<component> VERSION=<version>
```

#### `make git_cleanup_workspace`

Remove your workspace for a component.

```bash
make git_cleanup_workspace DIR=<component>
```

**Examples:**
```bash
make git_cleanup_workspace DIR=gui
make git_cleanup_workspace DIR=config/flow
```

#### `make git_list_workspaces`

List all active workspaces (all users).

```bash
make git_list_workspaces
```

#### `make git_cleanup_all`

Cleanup all stale worktrees.

```bash
make git_cleanup_all
```

### Release Management (Git-Based)

#### `make git_create_release`

Create a Git tag-based release.

```bash
make git_create_release TYPE=<type> [CONFIG=<file>] [DESC="<description>"] [MILESTONE=<milestone>]
# or
make git_create_release VERSION=<version> [CONFIG=<file>] [DESC="<description>"] [MILESTONE=<milestone>]
```

**Release Modes:**
1. **Auto mode** (default) - Uses latest/current version of all components
2. **Config mode** - Use `CONFIG=<file>` to specify exact versions via JSON

**Examples:**
```bash
make git_create_release TYPE=patch DESC="Bug fixes"
make git_create_release TYPE=minor DESC="New features" MILESTONE="Q1_2025"
make git_create_release TYPE=patch CONFIG=release_v2.1.0.json DESC="Controlled release"
make git_create_release VERSION=v6.0.0 CONFIG=release_v6.0.0.json DESC="Production"
```

#### `make git_list_releases`

List all Git-based releases.

```bash
make git_list_releases
```

#### `make git_release_info`

Get detailed information about a release.

```bash
make git_release_info RELEASE=<version>
```

#### `make git_checkout_release`

Checkout a release to its exact state.

```bash
make git_checkout_release RELEASE=<version>
```

**Example:**
```bash
make git_checkout_release RELEASE=v5.0.3
```

#### `make git_validate_release`

Validate a release configuration.

```bash
make git_validate_release RELEASE=<version>
```

#### `make git_generate_config`

Generate a release configuration JSON file.

```bash
make git_generate_config OUTPUT=<file> [DESC="<description>"]
```

**Examples:**
```bash
make git_generate_config OUTPUT=config/release_v3.0.0.json
make git_generate_config OUTPUT=release.json DESC="Q1 2025 Production"
```

### Migration Commands

#### `make git_discover`

Discover components that can be migrated to Git-based versioning.

```bash
make git_discover
```

#### `make git_migrate`

Run full migration to Git-based system.

```bash
make git_migrate
```

**Note:** A backup will be created first.

#### `make git_archive`

Archive old directory structure after migration.

```bash
make git_archive
```

---

## Email Notifications

These commands are planned for future implementation.

### `make email_test`

Test the email notification system.

```bash
make email_test
```

### `make email_config`

Show email configuration status.

```bash
make email_config
```

### `make email_enable`

Enable email notifications.

```bash
make email_enable
```

### `make email_disable`

Disable email notifications.

```bash
make email_disable
```

---

## Utility Commands

### `make config_status`

Show configuration directory version status.

```bash
make config_status
```

### `make status_hierarchical`

Show complete hierarchical structure status including commands and configuration.

```bash
make status_hierarchical
```

### `make version_help`

Display detailed help for version management commands.

```bash
make version_help
```

### `make help_detail`

Display detailed help for a specific command type.

```bash
make help_detail TYPE=<type>
```

---

## Legacy Commands

These commands are deprecated and redirect to modern equivalents.

### `make add_flow`

**Deprecated** - Use `make manage_flow` instead.

### `make add_node`

**Deprecated** - Use `make manage_node` instead.

### `make add_subnode`

**Deprecated** - Use `make manage_subnode` instead.

### `make manage_project`

**Deprecated** - Use `make manage_projects` instead.

---

## Quick Reference

| Category | Command | Description |
|----------|---------|-------------|
| **Core** | `make help` | Show all commands |
| **Core** | `make status` | System status |
| **Core** | `make validate` | Validate system |
| **Config** | `make manage_flow` | Manage flows |
| **Config** | `make manage_node` | Manage nodes/subnodes |
| **Config** | `make manage_tech` | Manage technology |
| **Workspace** | `make init_workspace` | Create workspace |
| **Workspace** | `make update_workspace` | Update workspace |
| **Release** | `make release_flow` | Create release |
| **Release** | `make list_releases` | List releases |
| **Project** | `make manage_projects` | Manage projects |
| **Git** | `make git_create_workspace` | Create Git workspace |
| **Git** | `make git_commit_version` | Commit new version |
| **Git** | `make git_create_release` | Create Git release |

---

## Environment Variables

The Core Makefile exports these environment variables for child processes:

| Variable | Description |
|----------|-------------|
| `CBFLOW_REPO_ROOT` | Git repository root |
| `CBFLOW_CORE_DIR` | Core directory path |
| `CBFLOW_PROJECT_ROOT` | Project root path |
| `CBFLOW_CONFIG_ROOT` | Configuration root |
| `CBFLOW_SCRIPTS_ROOT` | Scripts root |
| `CBFLOW_RUN_DIR` | Current run directory |

---

## Troubleshooting

### Common Issues

1. **"Cannot find CBFlow core directory"**
   - Ensure you're in the correct Git repository
   - Verify the repository structure is intact

2. **"Release not found"**
   - Run `make git_checkout_release RELEASE=<version>` first
   - Verify the release exists with `make list_releases`

3. **"Workspace not initialized"**
   - Run `make init` in the workspace directory first

4. **"Permission denied for project operations"**
   - Only flow owners can modify projects
   - Check your username matches a flow owner

---

*Last Updated: December 2024*
