# Advanced Scenarios

Complex use cases and advanced workflows.

## Version Rollback

Rollback to previous stable version.

```bash
# Current state
make list_versions DIR=gui
# v1.0.6 (current) - has issues
# v1.0.5 - stable
# v1.0.4

# Rollback to v1.0.5
make git_promote_version DIR=gui VERSION=v1.0.5

# Verify
make git_get_current DIR=gui
# Output: v1.0.5

ls -la gui/
# current -> v1.0.5
```

---

## Migrating Flat Component to Versioning

Convert existing flat directory to versioned component.

```bash
# Before: setup/ is flat directory
ls setup/
# install.sh  config.yaml  README.md

# 1. Create workspace from existing files
make git_create_workspace DIR=setup

# 2. Files copied to workspace automatically
ls workarea/worktrees/setup/workspace/
# install.sh  config.yaml  README.md

# 3. Create initial version
make git_commit_version DIR=setup VERSION=v1.0.0 DESC="Initial setup version"

# 4. Promote to current
make git_promote_version DIR=setup VERSION=v1.0.0

# 5. Clean up original files
rm setup/install.sh setup/config.yaml setup/README.md

# After: setup/ is versioned
ls -la setup/
# CHANGELOG.md
# current -> v1.0.0
# v1.0.0/
#   install.sh
#   config.yaml
#   README.md
```

---

## Parallel Development

Work on multiple components simultaneously.

```bash
# Terminal 1: Work on GUI
make git_create_workspace DIR=gui
cd workarea/worktrees/gui/workspace/
vim simple_gui.py
# ... continue working ...

# Terminal 2: Work on config (parallel)
make git_create_workspace DIR=config/flow
cd workarea/worktrees/config-flow/workspace/
vim flow_config.tcl
# ... continue working ...

# Terminal 1: Commit GUI
cd /path/to/core
make git_commit_version DIR=gui TYPE=minor DESC="New GUI features"

# Terminal 2: Commit config
cd /path/to/core
make git_commit_version DIR=config/flow TYPE=patch DESC="Config fixes"

# Create release with both
make git_create_release TYPE=minor DESC="GUI and config updates"
```

---

## Release Comparison

Compare two releases to see what changed.

```bash
# List releases
make git_list_releases

# View release details
make git_release_info RELEASE=v1.0.0
make git_release_info RELEASE=v2.0.0

# Compare component versions
make git_diff_releases R1=v1.0.0 R2=v2.0.0

# View CHANGELOGs for changed components
cat gui/CHANGELOG.md | grep "v1.0.4" -A 30
cat gui/CHANGELOG.md | grep "v1.0.5" -A 30

# See release CHANGELOG comparison
cat RELEASE_CHANGELOG.md | grep -E "(v1.0.0|v2.0.0)" -A 50
```

---

## Archiving Old Versions

Clean up old versions to save space.

```bash
# Check disk usage
du -sh gui/
du -sh .git/

# List all versions
make list_versions DIR=gui
# v1.0.0, v1.0.1, v1.0.2, v1.0.3, v1.0.4, v1.0.5 (current)

# Archive old versions (keep last 3)
make git_archive DIR=gui KEEP=3

# Or manually delete
git branch -D gui/v1.0.0 gui/v1.0.1 gui/v1.0.2
git tag -d gui-v1.0.0 gui-v1.0.1 gui-v1.0.2
rm -rf gui/v1.0.0/ gui/v1.0.1/ gui/v1.0.2/

# Reclaim space
git gc --aggressive
git prune

# Verify
make list_versions DIR=gui
# v1.0.3, v1.0.4, v1.0.5 (current)
```

---

## Multi-Repository Releases

Coordinate releases across multiple repositories.

```bash
# Repo 1: Core
cd CBFlow/PD/core
make git_create_release TYPE=major CONFIG=core-v2.0.0.json DESC="Core v2.0.0"

# Repo 2: Extensions (depends on core v2.0.0)
cd CBFlow/PD/extensions
# Update dependency reference to core v2.0.0
vim config/dependencies.json
make git_create_release TYPE=major CONFIG=ext-v2.0.0.json DESC="Extensions v2.0.0 (requires Core v2.0.0)"

# Document compatibility
echo "Extensions v2.0.0 requires Core v2.0.0" >> COMPATIBILITY.md
```

---

## Emergency Workspace Recovery

Recover from corrupted or stuck workspace.

```bash
# Problem: Workspace stuck or corrupted
make git_list_workspaces
# Shows: gui workspace (corrupted)

# Attempt cleanup
make git_cleanup_workspace DIR=gui

# If that fails, manual cleanup
cd workarea/worktrees/gui/workspace/
git status  # Check state
cd ../../..

# Force remove worktree
git worktree remove workarea/worktrees/gui/workspace --force

# Delete workspace branch
git branch -D gui/workspace

# Prune stale worktrees
git worktree prune

# Verify cleanup
make git_list_workspaces
# Should show nothing

# Start fresh
make git_create_workspace DIR=gui
```

---

**See also:**
- [Basic Workflows](basic-workflows.md) - Simple workflows
- [Release Workflows](release-workflows.md) - Release examples
- [Troubleshooting](../02-user-guide/troubleshooting.md) - Common issues
