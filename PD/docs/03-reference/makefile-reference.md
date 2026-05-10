# Makefile Command Reference

Complete reference for all Make commands in CBFlow versioning system.

## Component Versioning Commands

### git_create_workspace

Creates an isolated, user-specific Git worktree for developing a new version.

**Multi-User Support**: Workspaces are user-specific. Multiple users can work on the same component simultaneously without conflicts.

**Syntax:**
```bash
make git_create_workspace DIR=<component> [FORCE=true]
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path (e.g., gui, config/flow) |
| `FORCE` | No | boolean | Force recreate your own workspace if it exists (default: false) |

**What it does:**
1. Creates Git worktree at `workarea/worktrees/<username>/<component>/workspace/`
2. Creates user-specific branch `<component>/workspace-<username>`
3. Copies current version files to workspace
4. Provides isolated development environment
5. Auto-migrates old workspace structure if detected

**Example:**
```bash
# Create workspace for gui (user: alice)
make git_create_workspace DIR=gui
# Creates: workarea/worktrees/alice/gui/workspace/
# Branch: gui/workspace-alice

# Force recreate your workspace
make git_create_workspace DIR=gui FORCE=true

# Create workspace for nested component
make git_create_workspace DIR=config/flow
# Creates: workarea/worktrees/alice/config/flow/workspace/
```

**Multi-User Example:**
```bash
# User alice creates workspace
$ whoami
alice
$ make git_create_workspace DIR=gui
✓ Workspace created: workarea/worktrees/alice/gui/workspace
  Branch: gui/workspace-alice

# User bob creates workspace (simultaneously)
$ whoami
bob
$ make git_create_workspace DIR=gui
✓ Workspace created: workarea/worktrees/bob/gui/workspace
  Branch: gui/workspace-bob

# Both can work without conflicts!
```

**Output:**
```
📂 Creating workspace from gui/v1.0.4...
📋 Copying current files to workspace...
✓ Workspace created: /path/to/workarea/worktrees/alice/gui/workspace
  Branch: gui/workspace-alice
  Source: gui/v1.0.4

💡 Edit files in: /path/to/workarea/worktrees/alice/gui/workspace
   Then commit with: make git_commit_version DIR=gui
```

**Migration:**
If an old workspace structure is detected (`workarea/worktrees/<component>/workspace/`), it will be automatically migrated to the new user-specific structure.

**Errors:**
- Your workspace already exists (use FORCE=true or cleanup first)
- Component has no current version
- Git worktree creation failed

**See also:** git_commit_version, git_cleanup_workspace, git_list_workspaces

---

### git_commit_version

Creates a new version from workspace changes.

**Syntax:**
```bash
# Option 1: Auto-increment (recommended)
make git_commit_version DIR=<component> TYPE=patch|minor|major DESC="description"

# Option 2: Explicit version
make git_commit_version DIR=<component> VERSION=vX.Y.Z DESC="description"
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path |
| `TYPE` | Yes* | enum | Version increment type: patch, minor, major |
| `VERSION` | Yes* | string | Explicit version number (vX.Y.Z format) |
| `DESC` | Yes | string | Description of changes |

\* Either TYPE or VERSION required (mutually exclusive)

**TYPE values:**
- `patch` - Bug fixes, small changes (increments Z: x.y.Z+1)
- `minor` - New features, enhancements (increments Y: x.Y+1.0)
- `major` - Breaking changes, redesigns (increments X: X+1.0.0)

**What it does:**
1. Commits workspace changes to new version branch
2. Creates Git branch: `<component>/vX.Y.Z`
3. Creates Git tag: `<component>-vX.Y.Z`
4. Updates component CHANGELOG
5. Updates version registry
6. Removes workspace

**Example:**
```bash
# Create patch version (bug fix)
make git_commit_version DIR=gui TYPE=patch DESC="Fixed button alignment"

# Create minor version (new feature)
make git_commit_version DIR=gui TYPE=minor DESC="Added dark mode support"

# Create major version (breaking change)
make git_commit_version DIR=gui TYPE=major DESC="Complete UI redesign"

# Explicit version number
make git_commit_version DIR=gui VERSION=v2.0.0 DESC="Major release"
```

**Output:**
```
📝 Committing changes in workspace...
🏷️  Creating version branch v1.0.5...
✓ Version v1.0.5 created successfully
  Branch: gui/v1.0.5
  Tag: gui-v1.0.5

📝 Updating CHANGELOG...
✓ Updated CHANGELOG: gui/CHANGELOG.md

💡 To set as current: make git_promote_version DIR=gui VERSION=v1.0.5
```

**Errors:**
- No workspace found (create one first with git_create_workspace)
- No changes in workspace
- Invalid TYPE value (must be patch, minor, or major)
- Invalid VERSION format (must be vX.Y.Z)
- Version already exists
- Neither TYPE nor VERSION provided
- Both TYPE and VERSION provided

**See also:** git_create_workspace, git_promote_version, list_versions

---

### git_promote_version

Promotes a version to be the current active version.

**Syntax:**
```bash
make git_promote_version DIR=<component> VERSION=<version>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path |
| `VERSION` | Yes | string | Version to promote (vX.Y.Z) |

**What it does:**
1. Sets symbolic ref: `<component>/current → <component>/vX.Y.Z`
2. Checks out version to physical directory: `<component>/vX.Y.Z/`
3. Creates/updates symlink: `<component>/current → vX.Y.Z`
4. Updates version registry: current_version = vX.Y.Z

**Example:**
```bash
# Promote gui to v1.0.5
make git_promote_version DIR=gui VERSION=v1.0.5

# Promote nested component
make git_promote_version DIR=config/flow VERSION=v1.1.0
```

**Output:**
```
✓ Set gui/current → v1.0.5
✓ Checked out gui/v1.0.5 to gui/v1.0.5/
✓ Created symlink gui/current → v1.0.5
```

**Errors:**
- Version does not exist
- Component not found
- Git symbolic ref creation failed

**See also:** git_commit_version, git_get_current, list_versions

---

### list_versions

Lists all available versions for a component.

**Syntax:**
```bash
make list_versions DIR=<component>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path |

**Example:**
```bash
# List gui versions
make list_versions DIR=gui

# List nested component versions
make list_versions DIR=config/flow
```

**Output:**
```
📋 Versions for gui:
Version         Commit     Date         Status
-------------------------------------------------------
v1.0.5          a3d2f1c    2025-12-19   ← current
v1.0.4          e4b7a9d    2025-12-18
v1.0.3          c2f8d3e    2025-12-17
v1.0.0          b1f3a2e    2025-12-15
```

**See also:** git_get_current, git_diff_versions

---

### git_get_current

Gets the current active version of a component.

**Syntax:**
```bash
make git_get_current DIR=<component>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path |

**Example:**
```bash
make git_get_current DIR=gui
# Output: v1.0.5

make git_get_current DIR=config/flow
# Output: v1.0.0
```

**See also:** list_versions, git_promote_version

---

### git_diff_versions

Shows differences between two versions of a component.

**Syntax:**
```bash
make git_diff_versions DIR=<component> V1=<version1> V2=<version2>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path |
| `V1` | Yes | string | First version (vX.Y.Z) |
| `V2` | Yes | string | Second version (vX.Y.Z) |

**Example:**
```bash
# Compare two versions
make git_diff_versions DIR=gui V1=v1.0.0 V2=v1.0.5

# Compare with current
make git_diff_versions DIR=gui V1=v1.0.4 V2=$(make git_get_current DIR=gui)
```

**Output:**
Shows Git diff between the two version branches.

**See also:** list_versions, git_diff_releases

---

## Release Management Commands

### git_create_release

Creates a system-wide release with component versions.

**Syntax:**
```bash
# Option 1: Auto mode with auto-increment
make git_create_release TYPE=patch|minor|major DESC="description"

# Option 2: Auto mode with explicit version
make git_create_release VERSION=vX.Y.Z DESC="description"

# Option 3: Config mode with auto-increment
make git_create_release TYPE=patch|minor|major CONFIG=<file> DESC="description"

# Option 4: Config mode with explicit version
make git_create_release VERSION=vX.Y.Z CONFIG=<file> DESC="description"
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `TYPE` | Yes* | enum | Release increment type: patch, minor, major |
| `VERSION` | Yes* | string | Explicit release version (vX.Y.Z) |
| `CONFIG` | No | path | Path to release config JSON file |
| `DESC` | Yes | string | Release description |

\* Either TYPE or VERSION required (mutually exclusive)

**Modes:**
- **Auto Mode** (no CONFIG): Automatically uses latest/current version of all components
- **Config Mode** (with CONFIG): Uses versions specified in JSON config file

**What it does:**
1. Collects component versions (auto or from config)
2. Validates all versions exist
3. Creates release tag: `release/vX.Y.Z`
4. Updates RELEASE_CHANGELOG.md
5. Records release in version registry

**Example:**
```bash
# Auto mode - uses latest versions
make git_create_release TYPE=patch DESC="December bug fixes"

# Auto mode - explicit version
make git_create_release VERSION=v2.0.0 DESC="Major release"

# Config mode - controlled versions
make git_generate_config OUTPUT=release.json DESC="Prod release"
# ... edit release.json ...
make git_create_release TYPE=major CONFIG=release.json DESC="Production release"
```

**Output:**
```
🔢 Auto-incremented version: v1.0.1
📋 Collecting component versions (auto mode - latest versions)...

📦 Release Components (29):
  gui                            v1.0.5       (a3d2f1c)
  config/flow                    v1.0.0       (ee78586)
  config/project                 v1.0.1       (f3a8d2e)
  ...

✓ Release v1.0.1 created successfully
  Tag: release/v1.0.1
  Components: 29

📝 Updating Release CHANGELOG...
✓ Updated release CHANGELOG: RELEASE_CHANGELOG.md
```

**Errors:**
- Invalid TYPE or VERSION
- CONFIG file not found or invalid JSON
- Component version doesn't exist (config mode)
- Release version already exists
- No components found

**See also:** git_generate_config, git_list_releases, git_release_info

---

### git_generate_config

Generates a release configuration file with current component versions.

**Syntax:**
```bash
make git_generate_config OUTPUT=<filename> DESC="description"
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `OUTPUT` | Yes | path | Output file path (JSON) |
| `DESC` | Yes | string | Release description |

**What it does:**
1. Discovers all versioned components
2. Gets current version of each component
3. Creates JSON config file with all versions
4. Ready for customization by user

**Example:**
```bash
# Generate config for production release
make git_generate_config OUTPUT=prod-release.json DESC="Q4 Production Release"

# Generate config for testing
make git_generate_config OUTPUT=test-release.json DESC="Testing configuration"
```

**Output:**
```
📋 Generating release configuration...
✓ Discovered 29 components
✓ Configuration written to: prod-release.json

💡 Edit prod-release.json to customize component versions
   Then create release with: make git_create_release TYPE=<type> CONFIG=prod-release.json DESC="..."
```

**Generated file (prod-release.json):**
```json
{
  "version": "auto",
  "description": "Q4 Production Release",
  "components": {
    "gui": "v1.0.5",
    "config/flow": "v1.0.0",
    "config/project": "v1.0.1",
    "utils/version": "v2.0.0"
  }
}
```

**See also:** git_create_release, git_list_releases

---

### git_list_releases

Lists all system releases.

**Syntax:**
```bash
make git_list_releases
```

**Example:**
```bash
make git_list_releases
```

**Output:**
```
📋 System Releases:
Version         Date         Components    Description
------------------------------------------------------------------
v2.0.0          2025-12-19   29           Production release
v1.0.1          2025-12-18   29           December bug fixes
v1.0.0          2025-12-15   29           Initial release
```

**See also:** git_release_info, git_create_release

---

### git_release_info

Shows detailed information about a specific release.

**Syntax:**
```bash
make git_release_info RELEASE=<version>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `RELEASE` | Yes | string | Release version (vX.Y.Z) |

**Example:**
```bash
make git_release_info RELEASE=v2.0.0
```

**Output:**
```
📦 Release Information: v2.0.0

📋 Details:
  Created: 2025-12-19 14:30:15
  Description: Production release with tested components
  Mode: CONFIG
  Components: 29

📦 Component Versions:
  gui                            v1.0.4
  config/flow                    v1.0.0
  config/project                 v1.0.0
  utils/version                  v2.0.0
  ...

📝 CHANGELOG:
  See: RELEASE_CHANGELOG.md#v2.0.0
```

**See also:** git_list_releases, git_checkout_release

---

### git_checkout_release

Checks out a release to a physical directory for packaging/distribution.

**Syntax:**
```bash
make git_checkout_release RELEASE=<version>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `RELEASE` | Yes | string | Release version (vX.Y.Z) |

**What it does:**
1. Creates directory: `workarea/releases/<version>/`
2. Checks out each component version to this directory
3. Creates complete snapshot of the release

**Example:**
```bash
# Checkout release for packaging
make git_checkout_release RELEASE=v2.0.0
```

**Output:**
```
📦 Checking out release v2.0.0...
✓ Created directory: workarea/releases/v2.0.0/
✓ Checked out 29 components

📂 Release location: workarea/releases/v2.0.0/
```

**See also:** git_release_info, git_list_releases

---

### git_validate_release

Validates a release configuration file.

**Syntax:**
```bash
make git_validate_release CONFIG=<file>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `CONFIG` | Yes | path | Release config JSON file |

**Example:**
```bash
make git_validate_release CONFIG=release.json
```

**Output:**
```
📋 Validating release configuration...
✓ JSON syntax valid
✓ All 29 components exist
✓ All versions validated

✓ Configuration is valid
```

**See also:** git_generate_config, git_create_release

---

## Workspace Management Commands

### git_list_workspaces

Lists all active Git worktrees/workspaces from all users.

**Multi-User**: Shows workspaces from all users, making it easy to see who is working on what.

**Syntax:**
```bash
make git_list_workspaces
```

**Example:**
```bash
make git_list_workspaces
```

**Output:**
```
📂 Active Workspaces (All Users):
User            Component                 Path
---------------------------------------------------------------------------------
alice           gui                       workarea/worktrees/alice/gui/workspace
bob             gui                       workarea/worktrees/bob/gui/workspace
alice           config/flow               ...worktrees/alice/config/flow/workspace
```

**Use Cases:**
- See who is currently working on components
- Check if you already have a workspace for a component
- Identify active development activity
- Coordinate work with other team members

**See also:** git_cleanup_workspace, git_cleanup_all

---

### git_cleanup_workspace

Removes your own workspace for a specific component.

**Ownership Protection**: You can only cleanup your own workspaces. Workspace paths are user-specific, so there's no risk of accidentally deleting another user's work.

**Syntax:**
```bash
make git_cleanup_workspace DIR=<component>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path |

**What it does:**
1. Removes your Git worktree
2. Deletes your workspace directory
3. Deletes your workspace branch
4. Cleans up Git references

**Example:**
```bash
# Clean up your gui workspace (user: alice)
make git_cleanup_workspace DIR=gui
# Removes: workarea/worktrees/alice/gui/workspace/
# Deletes branch: gui/workspace-alice

# Clean up nested component workspace
make git_cleanup_workspace DIR=config/flow
```

**Output:**
```
✓ Removed workspace: workarea/worktrees/alice/gui/workspace
```

**Multi-User Note:**
Other users' workspaces are NOT affected. Only your own workspace for the component is removed.

**See also:** git_list_workspaces, git_cleanup_all

---

### git_cleanup_all

Removes all stale workspaces.

**Syntax:**
```bash
make git_cleanup_all
```

**Example:**
```bash
make git_cleanup_all
```

**Output:**
```
🧹 Cleaning up all workspaces...
✓ Removed workspace for gui
✓ Removed workspace for config/flow
✓ Total workspaces cleaned: 2
```

**See also:** git_list_workspaces, git_cleanup_workspace

---

## Discovery and Migration Commands

### git_discover

Discovers all components with Git-based versioning.

**Syntax:**
```bash
make git_discover
```

**Example:**
```bash
make git_discover
```

**Output:**
```
📋 Discovering versioned components...
✓ Found 29 components:
  gui (current: v1.0.5)
  config/flow (current: v1.0.0)
  config/project (current: v1.0.1)
  ...
```

---

### git_migrate

Migrates a flat directory to Git-based versioning.

**Syntax:**
```bash
make git_migrate DIR=<component> VERSION=v1.0.0 DESC="description"
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path |
| `VERSION` | Yes | string | Initial version (typically v1.0.0) |
| `DESC` | Yes | string | Description of initial version |

**Example:**
```bash
# Migrate setup/ directory to versioning
make git_migrate DIR=setup VERSION=v1.0.0 DESC="Initial setup version"
```

**What it does:**
1. Creates workspace from current directory
2. Creates first version branch/tag
3. Promotes to current
4. Sets up CHANGELOG

**See also:** git_create_workspace, git_commit_version

---

### git_archive

Archives old versions to reduce disk usage.

**Syntax:**
```bash
make git_archive DIR=<component> KEEP=<count>
```

**Parameters:**
| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `DIR` | Yes | string | Component directory path |
| `KEEP` | Yes | number | Number of recent versions to keep |

**Example:**
```bash
# Keep only last 3 versions of gui
make git_archive DIR=gui KEEP=3
```

**Output:**
```
📦 Archiving old versions of gui...
✓ Keeping v1.0.5, v1.0.4, v1.0.3
✓ Archived v1.0.0, v1.0.1, v1.0.2
```

---

## Common Usage Patterns

### Complete Versioning Workflow
```bash
# 1. Create workspace
make git_create_workspace DIR=gui

# 2. Edit files
cd workarea/worktrees/gui/workspace/
vim simple_gui.py
cd /path/to/CBFlow/PD/core

# 3. Commit version
make git_commit_version DIR=gui TYPE=patch DESC="Fixed button bug"

# 4. Promote to current
make git_promote_version DIR=gui VERSION=v1.0.5

# 5. Verify
make list_versions DIR=gui
cat gui/CHANGELOG.md
```

### Release Creation Workflow
```bash
# Auto mode
make git_create_release TYPE=patch DESC="December release"

# Config mode
make git_generate_config OUTPUT=release.json DESC="Prod release"
vim release.json  # Customize versions
make git_create_release TYPE=major CONFIG=release.json DESC="Production release"
```

### Workspace Cleanup
```bash
# List active workspaces
make git_list_workspaces

# Clean specific workspace
make git_cleanup_workspace DIR=gui

# Clean all workspaces
make git_cleanup_all
```

---

**See also:**
- [Python Scripts Reference](python-scripts-reference.md) - Script details
- [Git Reference](git-reference.md) - Git conventions
- [Configuration Reference](configuration-reference.md) - Config formats
