# Advanced Scenarios

Complex use cases and advanced workflows.

## Version Rollback

Rollback to previous stable version.

```bash
# Current state
cbflow flow version list --dir gui
# v1.0.6 (current) - has issues
# v1.0.5 - stable
# v1.0.4

# Rollback to v1.0.5
cbflow flow version set-current --dir gui --version v1.0.5

# Verify
cbflow flow version get-current --dir gui
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

# 1. Copy to create initial version
cbflow flow version copy --dir setup --from . --to v1.0.0

# 2. Set as current
cbflow flow version set-current --dir setup --version v1.0.0

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
cbflow flow version copy --dir gui --from v1.0.4 --to v1.0.5
# Edit files in gui/v1.0.5/
vim gui/v1.0.5/simple_gui.py
# ... continue working ...

# Terminal 2: Work on config (parallel)
cbflow flow version copy --dir config/flow --from v1.0.0 --to v1.0.1
# Edit files in config/flow/v1.0.1/
vim config/flow/v1.0.1/flow_config.tcl
# ... continue working ...

# Terminal 1: Set GUI current
cbflow flow version set-current --dir gui --version v1.0.5

# Terminal 2: Set config current
cbflow flow version set-current --dir config/flow --version v1.0.1

# Create release with both
cbflow flow release create --type minor --desc "GUI and config updates"
```

---

## Release Comparison

Compare two releases to see what changed.

```bash
# List releases
cbflow flow release list

# View release details
cbflow flow release info --version v1.0.0
cbflow flow release info --version v2.0.0

# Compare component versions
cbflow flow release diff --v1 v1.0.0 --v2 v2.0.0

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
cbflow flow version list --dir gui
# v1.0.0, v1.0.1, v1.0.2, v1.0.3, v1.0.4, v1.0.5 (current)

# Archive old versions (keep last 3)
cbflow flow version archive --dir gui --keep 3

# Or manually delete
git branch -D gui/v1.0.0 gui/v1.0.1 gui/v1.0.2
git tag -d gui-v1.0.0 gui-v1.0.1 gui-v1.0.2
rm -rf gui/v1.0.0/ gui/v1.0.1/ gui/v1.0.2/

# Reclaim space
git gc --aggressive
git prune

# Verify
cbflow flow version list --dir gui
# v1.0.3, v1.0.4, v1.0.5 (current)
```

---

## Multi-Repository Releases

Coordinate releases across multiple repositories.

```bash
# Repo 1: Core
cd CBFlow/PD/core
cbflow flow release create --type major --config core-v2.0.0.json --desc "Core v2.0.0"

# Repo 2: Extensions (depends on core v2.0.0)
cd CBFlow/PD/extensions
# Update dependency reference to core v2.0.0
vim config/dependencies.json
cbflow flow release create --type major --config ext-v2.0.0.json --desc "Extensions v2.0.0 (requires Core v2.0.0)"

# Document compatibility
echo "Extensions v2.0.0 requires Core v2.0.0" >> COMPATIBILITY.md
```

---

## Emergency Workspace Recovery

Recover from corrupted or stuck workspace.

```bash
# Problem: Workspace stuck or corrupted
cbflow flow version list-workspaces
# Shows: gui workspace (corrupted)

# Attempt cleanup
cbflow flow version cleanup-workspace --dir gui

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
cbflow flow version list-workspaces
# Should show nothing

# Start fresh
cbflow flow version copy --dir gui --from v1.0.4 --to v1.0.5
```

---

**See also:**
- [Basic Workflows](basic-workflows.md) - Simple workflows
- [Release Workflows](release-workflows.md) - Release examples
- [Troubleshooting](../02-user-guide/troubleshooting.md) - Common issues
