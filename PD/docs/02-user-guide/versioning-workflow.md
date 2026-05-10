# Versioning Workflow

Complete guide to CBflow's directory-based versioning system.

## Overview

CBflow v2.0.0 uses **directory-based versioning** -- not Git worktrees or Git branches for version management. Each version is a physical directory. The `current` symlink points to the active version. This model is simple, transparent, and requires no special Git knowledge.

## Core Concepts

- **Version directory**: A named directory such as `v1.0.0/`, `v1.0.1/` containing the full set of files for that version.
- **current symlink**: A filesystem symlink (`current -> v1.0.1`) that points to the active version.
- **Copy-edit-promote**: The standard workflow is to copy an existing version, edit it, then update the symlink.

## Complete Workflow

```
Copy Version Directory --> Edit Files --> Set Current Symlink
```

### 1. Copy an Existing Version

```bash
cbflow flow version copy --dir config --from v1.0.0 --to v1.0.1
```

This creates `config/v1.0.1/` as a full copy of `config/v1.0.0/`.

### 2. Edit Files

```bash
# Edit files directly in the new version directory
vi config/v1.0.1/flow_config.tcl
vi config/v1.0.1/node_configs/SYNTH_config.tcl
```

No workspace isolation is needed. You edit the version directory in place.

### 3. Set Current (Promote)

```bash
cbflow flow version set-current --dir config --version v1.0.1
```

This updates the `current` symlink:
```
config/current -> v1.0.1
```

### 4. Verify

```bash
cbflow flow version list --dir config
ls -la config/current
```

## Version Naming

| Convention | Example | Use When |
|-----------|---------|----------|
| Semantic | v1.0.0, v1.0.1 | Standard releases |
| Date-based | v2026.05.09 | Snapshot versions |
| Descriptive | v1.0.0_eco_fix | ECO or hotfix branches |

## Common Commands

```bash
# List all versions for a directory
cbflow flow version list --dir config

# Copy version
cbflow flow version copy --dir config --from v1.0.0 --to v1.0.1

# Set current
cbflow flow version set-current --dir config --version v1.0.1

# Diff two versions
cbflow flow version diff --dir config --v1 v1.0.0 --v2 v1.0.1
```

## Directory Structure

```
config/
  v1.0.0/              # Older version (immutable after promotion)
    flow_config.tcl
    node_configs/
      SYNTH_config.tcl
      PNR_config.tcl
      STA_config.tcl
      ...              (12 flow configs)
  v1.0.1/              # Newer version
    flow_config.tcl
    node_configs/
      SYNTH_config.tcl
      PNR_config.tcl
      STA_config.tcl
      ...
  current -> v1.0.1    # Symlink to active version
```

## Versioned Components

CBflow applies directory-based versioning to these components:

| Component | Path | Description |
|-----------|------|-------------|
| Flow config | `config/flow/` | Master flow definitions and node configs |
| Project config | `config/project/{project}/` | Project-specific settings |
| Tech config | `config/tech/{node}/` | Technology node parameters |
| Setup hooks | `config/setup/common/` | Flow/tool setup hooks |
| Exit criteria | `config/exit/` | Exit milestone definitions |
| Commands | `cmds/{FLOW}/{vendor}/{tool}/` | EDA tool command files per flow |
| Utilities | `utils/utilities/` | TCL utility modules |
| Generation | `utils/generation/` | Makefile generation scripts |
| Validation | `utils/validation/` | Validation scripts |

## What This Is NOT

- **No Git worktrees**: Versions are not Git branches or worktrees.
- **No Git branches per version**: The repository uses standard Git for source control, but version management is purely directory-based.
- **No database**: Version metadata is derived from the directory structure and symlink state.

## Examples

### Create a New Config Version for ECO

```bash
cbflow flow version copy --dir config --from v1.0.0 --to v1.0.1
vi config/v1.0.1/node_configs/ECO_config.tcl    # Add ECO-specific settings
cbflow flow version set-current --dir config --version v1.0.1
```

### Create a New Command Version for PNR

```bash
cbflow flow version copy --dir cmds/PNR/synopsys/fc --from v1.0.0 --to v1.0.1
vi cmds/PNR/synopsys/fc/v1.0.1/place_fc.tcl    # Modify placement commands
cbflow flow version set-current --dir cmds/PNR/synopsys/fc --version v1.0.1
```

### Roll Back to a Previous Version

```bash
# Simply re-point the symlink
cbflow flow version set-current --dir config --version v1.0.0
```

### Compare Versions

```bash
cbflow flow version diff --dir config --v1 v1.0.0 --v2 v1.0.1
```

## Best Practices

- Keep version directories immutable after they have been promoted and used in a run.
- Use descriptive names when copying versions for ECO or hotfix work.
- Always verify the `current` symlink points to the intended version before executing a flow.
- Use `cbflow flow version list` to audit what versions exist and which is active.
- Test configuration changes in `flow(test_mode) true` before running with EDA tools.

## Troubleshooting

### Broken Symlink

If the `current` symlink points to a deleted directory:
```bash
cbflow flow version set-current --dir config --version v1.0.0
```

### Accidental Edit of Wrong Version

Because versions are plain directories, edits are immediate. If you accidentally edit the wrong version, copy the clean version again from a known-good source.

### Version Not Picked Up by Run

Runs lock their component versions at creation time. If you change the `current` symlink after a run was created, the existing run continues to use the version it was created with. Create a new run to use the updated version.

---

**See also:**
- [Configuration Reference](../03-reference/configuration-reference.md) -- Config file details
- [System Design](../04-architecture/system-design.md) -- Architecture overview
- [Versioning Strategy](../04-architecture/git-strategy.md) -- Design rationale
