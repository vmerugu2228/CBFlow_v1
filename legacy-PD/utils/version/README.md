# Git-Based Versioning and Release Management

## Overview

CBFlow uses Git branches and tags for component versioning and release management, eliminating the need for physical directory copies. This provides:

- **Space efficiency**: Versions stored as Git references, not directory copies
- **Full history**: Complete Git log, diff, and blame capability
- **Atomic operations**: Rollback capability via Git
- **Automated versioning**: Auto-increment support for both components and releases

## System Components

### 1. Component Versioning
Individual components (config, utils, cmds, etc.) can be versioned independently.

### 2. Release Management
System-wide releases that bundle specific versions of all components into a tested, stable snapshot.

---

## Component Versioning

### Quick Start

```bash
# Create workspace for development
make git_create_workspace DIR=gui

# Make changes in: workarea/worktrees/gui/workspace/

# Commit changes as new version (auto-increment)
make git_commit_version DIR=gui TYPE=patch DESC="Bug fixes"

# Or specify version explicitly
make git_commit_version DIR=gui VERSION=v1.2.0 DESC="New features"

# Promote to current
make git_promote_version DIR=gui VERSION=v1.2.0

# List all versions
make list_versions DIR=gui
```

### Commands

#### Create Development Workspace
```bash
make git_create_workspace DIR=<component>
```
Creates isolated Git worktree for development at `workarea/worktrees/<component>/workspace/`

#### Commit Version (Auto-increment)
```bash
make git_commit_version DIR=<component> TYPE=<type> DESC="<description>"
```
- **TYPE**: `patch` (x.y.Z+1), `minor` (x.Y+1.0), or `major` (X+1.0.0)
- Auto-increments from current version
- Creates Git branch: `<component>/vX.Y.Z`
- Creates Git tag: `<component>-vX.Y.Z`
- Removes workspace after successful commit

#### Commit Version (Explicit)
```bash
make git_commit_version DIR=<component> VERSION=vX.Y.Z DESC="<description>"
```
Specify exact version number.

#### Promote Version to Current
```bash
make git_promote_version DIR=<component> VERSION=vX.Y.Z
```
- Sets symbolic ref: `<component>/current → <component>/vX.Y.Z`
- Checks out version to physical directory: `<component>/vX.Y.Z/`
- Creates symlink: `<component>/current → vX.Y.Z`

#### List Versions
```bash
make list_versions DIR=<component>
```

#### Diff Versions
```bash
make git_diff_versions DIR=<component> V1=v1.0.0 V2=v1.1.0
```

#### Workspace Management
```bash
make git_list_workspaces           # List all active workspaces
make git_cleanup_workspace DIR=<component>  # Remove specific workspace
make git_cleanup_all                # Remove all stale workspaces
```

### Version Increments

| Type  | Example | Use Case |
|-------|---------|----------|
| `patch` | 1.0.0 → 1.0.1 | Bug fixes, small changes |
| `minor` | 1.0.1 → 1.1.0 | New features, enhancements |
| `major` | 1.1.0 → 2.0.0 | Breaking changes |

---

## Release Management

### Quick Start

```bash
# Create release (auto-increment)
make git_create_release TYPE=patch DESC="Bug fixes"
make git_create_release TYPE=minor DESC="New features" MILESTONE="Q1_2025"
make git_create_release TYPE=major DESC="Breaking changes"

# Or specify version explicitly
make git_create_release VERSION=v6.0.0 DESC="Production release" MILESTONE="Q4_TAPEOUT"

# List all releases
make git_list_releases

# Get release information
make git_release_info RELEASE=v1.0.0

# Checkout release to exact state
make git_checkout_release RELEASE=v1.0.0

# Validate release integrity
make git_validate_release RELEASE=v1.0.0
```

### Commands

#### Create Release (Auto-increment)
```bash
make git_create_release TYPE=<type> DESC="<description>" [MILESTONE="<milestone>"]
```
- **TYPE**: `patch`, `minor`, or `major`
- Auto-increments from latest release version
- Automatically discovers all components with Git branches
- Creates release tag: `release/vX.Y.Z`
- Stores component manifest with exact commit SHAs

#### Create Release (Explicit)
```bash
make git_create_release VERSION=vX.Y.Z DESC="<description>" [MILESTONE="<milestone>"]
```
Specify exact release version.

#### List Releases
```bash
make git_list_releases
```
Shows all releases with version, date, component count, and description.

#### Get Release Info
```bash
make git_release_info RELEASE=vX.Y.Z
```
Shows complete release manifest with all component versions and commit SHAs.

#### Checkout Release
```bash
make git_checkout_release RELEASE=vX.Y.Z
```
Restores entire codebase to exact state of the release.

**WARNING**: This modifies your working directory. Commit changes first.

#### Validate Release
```bash
make git_validate_release RELEASE=vX.Y.Z
```
Verifies all component commits exist in the repository.

### Release Manifest Example

```json
{
  "release_version": "v1.0.0",
  "created_date": "2025-12-19T10:30:00",
  "description": "Production Baseline",
  "milestone": "Q4_TAPEOUT",
  "components": {
    "gui": {
      "version": "v1.0.4",
      "commit_sha": "01e89bc2..."
    },
    "config/flow": {
      "version": "v1.0.0",
      "commit_sha": "ee78586d..."
    },
    ...
  }
}
```

---

## Auto-increment Logic

### Component Versioning
Increments based on the **current** version (symbolic ref `<component>/current`):
- If current is `v1.2.3` and TYPE=patch → `v1.2.4`
- If current is `v1.2.3` and TYPE=minor → `v1.3.0`
- If current is `v1.2.3` and TYPE=major → `v2.0.0`

### Release Versioning
Increments based on the **latest** release tag:
- If latest is `v1.0.1` and TYPE=patch → `v1.0.2`
- If latest is `v1.0.1` and TYPE=minor → `v1.1.0`
- If latest is `v1.0.1` and TYPE=major → `v2.0.0`

---

## Git Structure

### Branches
```
gui/current         → symbolic ref to gui/v1.0.4
gui/v1.0.0          → branch
gui/v1.0.1          → branch
gui/v1.0.4          → branch
config/flow/current → symbolic ref to config/flow/v1.0.0
config/flow/v1.0.0  → branch
```

### Tags
```
gui-v1.0.0              → annotated tag with metadata
gui-v1.0.4              → annotated tag with metadata
config-flow-v1.0.0      → annotated tag with metadata
release/v1.0.0          → annotated tag with manifest
release/v1.0.1          → annotated tag with manifest
```

### Directory Structure
```
gui/
├── current -> v1.0.4        # Symlink to active version
├── v1.0.0/                  # Git checkout from branch
├── v1.0.1/                  # Git checkout from branch
└── v1.0.4/                  # Git checkout from branch (current)
```

---

## Workflow Examples

### Example 1: Create New Component Version

```bash
# 1. Create workspace
make git_create_workspace DIR=utils/validation

# 2. Edit files in workarea/worktrees/utils/validation/workspace/
vim workarea/worktrees/utils/validation/workspace/validator.py

# 3. Commit as patch version (auto-increment)
make git_commit_version DIR=utils/validation TYPE=patch DESC="Fixed edge case in validator"

# 4. Promote to current
make git_promote_version DIR=utils/validation VERSION=v1.0.1

# 5. Verify
make list_versions DIR=utils/validation
```

### Example 2: Create Production Release

```bash
# 1. Ensure all components are at desired versions
make list_versions DIR=gui
make list_versions DIR=config/flow
# ... check other components ...

# 2. Create minor release (auto-increment)
make git_create_release TYPE=minor DESC="Q1 2025 Release" MILESTONE="Q1_PRODUCTION"

# 3. Verify release
make git_list_releases
make git_release_info RELEASE=v1.1.0

# 4. Validate integrity
make git_validate_release RELEASE=v1.1.0

# 5. Tag and push
git push origin --tags
```

### Example 3: Rollback to Previous Release

```bash
# 1. List available releases
make git_list_releases

# 2. Checkout previous release
make git_checkout_release RELEASE=v1.0.0

# 3. Verify state
make list_versions DIR=gui
make list_versions DIR=config/flow
```

---

## Migration from Directory-Based Versioning

Existing v1.0.0 directories have been migrated to Git-based versioning:

```bash
# All components now have:
# - Git branch: <component>/v1.0.0
# - Git tag: <component>-v1.0.0
# - Symbolic ref: <component>/current → <component>/v1.0.0
# - Current symlink: <component>/current → v1.0.0

# Verify migration
git branch | grep "/"
git tag | grep "-v"
```

---

## Implementation Details

### Python Scripts

- **git_version_manager.py**: Component versioning
  - `GitVersionManager` class
  - Branch/tag creation
  - Current version tracking
  - Version comparison

- **git_worktree_manager.py**: Workspace management
  - `GitWorktreeManager` class
  - Worktree creation/cleanup
  - File synchronization

- **git_release_manager.py**: Release management
  - `GitReleaseManager` class
  - Component discovery
  - Manifest generation
  - Release validation
  - Auto-increment versioning

### Makefile Integration

All commands are exposed via Makefile targets for easy use:
- Component versioning: `git_create_workspace`, `git_commit_version`, `git_promote_version`
- Release management: `git_create_release`, `git_list_releases`, `git_checkout_release`
- Workspace management: `git_list_workspaces`, `git_cleanup_workspace`, `git_cleanup_all`

---

## Best Practices

1. **Always use workspaces** for development - never edit current/ directly
2. **Commit often** - create versions for meaningful changes
3. **Use semantic versioning** - patch for fixes, minor for features, major for breaking changes
4. **Test before promoting** - verify changes in workspace before setting as current
5. **Create releases regularly** - bundle tested component versions for stability
6. **Document changes** - use DESC parameter to explain what changed
7. **Validate releases** - run `git_validate_release` before distribution
8. **Push tags** - `git push origin --tags` to share releases with team

---

## Troubleshooting

### Workspace already exists
```bash
make git_cleanup_workspace DIR=<component>
# Then try again
```

### Version already exists
Check existing versions and increment appropriately:
```bash
make list_versions DIR=<component>
```

### Release validation fails
Ensure all component branches exist and commits are pushed:
```bash
git branch | grep <component>
git log <component>/v1.0.0
```

### Current symlink not updating
Manually verify and fix:
```bash
cd <component>
ls -la current
rm current
ln -sf v1.0.0 current
```

---

## Version Registry

Component metadata is tracked in:
```
utils/version/flow_version_registry.json
```

Example entry:
```json
{
  "gui": {
    "available_versions": {
      "v1.0.0": {
        "description": "Initial version",
        "creation_date": "2025-12-19T10:00:00",
        "git_tag": "gui-v1.0.0"
      },
      "v1.0.4": {
        "description": "Bug fixes",
        "creation_date": "2025-12-19T11:30:00",
        "git_tag": "gui-v1.0.4"
      }
    },
    "current_version": "v1.0.4",
    "creation_date": "2025-12-19T10:00:00"
  }
}
```

---

## Future Enhancements

- [ ] Component dependency tracking
- [ ] Automated release notes generation
- [ ] Version compatibility matrix
- [ ] Release promotion workflow (dev → staging → production)
- [ ] Component version pinning in releases
- [ ] Release branch support for hotfixes
