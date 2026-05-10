# Troubleshooting Guide

Solutions to common issues with CBFlow versioning system.

## Workspace Issues

### Workspace Already Exists

**Problem:**
```bash
make git_create_workspace DIR=gui
# Error: Workspace already exists for gui
```

**Cause:** Previous workspace wasn't cleaned up.

**Solution:**
```bash
# Option 1: Clean up first
make git_cleanup_workspace DIR=gui

# Then create again
make git_create_workspace DIR=gui

# Option 2: Force recreate (loses uncommitted changes!)
make git_create_workspace DIR=gui FORCE=true
```

**Prevention:**
- Always commit or cleanup workspaces after use
- Check active workspaces: `make git_list_workspaces`

---

### No Changes to Commit in Workspace

**Problem:**
```bash
make git_commit_version DIR=gui TYPE=patch DESC="Fixed bug"
# Error: No changes detected in workspace
```

**Cause:** Files weren't actually edited in workspace, or changes weren't saved.

**Solution:**
```bash
# 1. Verify workspace exists
make git_list_workspaces

# 2. Check workspace path
cd workarea/worktrees/gui/workspace/

# 3. Verify files exist
ls -la

# 4. Make sure you saved your edits
# Edit files again if needed

# 5. Check Git status in workspace
git status

# 6. Return to core and try again
cd /path/to/CBFlow/PD/core
make git_commit_version DIR=gui TYPE=patch DESC="Fixed bug"
```

**Prevention:**
- Always edit files in `workarea/worktrees/<component>/workspace/`
- Save files after editing
- Verify changes: `cd workarea/worktrees/gui/workspace && git status`

---

### Workspace Directory Not Found

**Problem:**
```bash
cd workarea/worktrees/gui/workspace/
# No such file or directory
```

**Cause:** Workspace wasn't created, or was already cleaned up.

**Solution:**
```bash
# Check if workspace exists
make git_list_workspaces

# If not listed, create it
make git_create_workspace DIR=gui

# Then navigate
cd workarea/worktrees/gui/workspace/
```

---

### Stale Workspaces

**Problem:** Multiple old workspaces taking up space.

**Solution:**
```bash
# List all workspaces
make git_list_workspaces

# Clean up specific workspace
make git_cleanup_workspace DIR=gui
make git_cleanup_workspace DIR=config/flow

# Or clean up all at once
make git_cleanup_all
```

---

## Version Creation Issues

### Version Already Exists

**Problem:**
```bash
make git_commit_version DIR=gui VERSION=v1.0.5 DESC="Fix"
# Error: Version v1.0.5 already exists
```

**Cause:** You're trying to create a version that's already been created.

**Solution:**

**Option 1: Use auto-increment**
```bash
# Let the system pick the next version
make git_commit_version DIR=gui TYPE=patch DESC="Fix"
```

**Option 2: Use different version**
```bash
# Specify a different version number
make git_commit_version DIR=gui VERSION=v1.0.6 DESC="Fix"
```

**Option 3: Delete existing version (CAREFUL!)**
```bash
# Check what's in the version first
make list_versions DIR=gui

# Delete branch and tag (THIS CANNOT BE UNDONE!)
git branch -D gui/v1.0.5
git tag -d gui-v1.0.5

# If pushed to remote, also delete remotely
git push origin --delete gui/v1.0.5
git push origin --delete gui-v1.0.5

# Then create new version
make git_commit_version DIR=gui VERSION=v1.0.5 DESC="Fix"
```

**Prevention:**
- Use auto-increment (TYPE=patch/minor/major) instead of explicit VERSION
- Check existing versions first: `make list_versions DIR=gui`

---

### Invalid TYPE Parameter

**Problem:**
```bash
make git_commit_version DIR=gui TYPE=pat DESC="Fix"
# Error: Invalid TYPE 'pat'. Must be: patch, minor, or major
```

**Cause:** Typo or wrong value for TYPE.

**Solution:**
```bash
# Use correct TYPE value
make git_commit_version DIR=gui TYPE=patch DESC="Fix"    # For bug fixes
make git_commit_version DIR=gui TYPE=minor DESC="Feature" # For new features
make git_commit_version DIR=gui TYPE=major DESC="Breaking" # For breaking changes
```

---

### Missing TYPE or VERSION

**Problem:**
```bash
make git_commit_version DIR=gui DESC="Fix"
# Error: Must specify either VERSION or TYPE
```

**Cause:** Neither VERSION nor TYPE was provided.

**Solution:**
```bash
# Option 1: Use TYPE for auto-increment (recommended)
make git_commit_version DIR=gui TYPE=patch DESC="Fix"

# Option 2: Specify exact VERSION
make git_commit_version DIR=gui VERSION=v1.0.5 DESC="Fix"
```

---

### Component Not Versioned Yet

**Problem:**
```bash
make git_create_workspace DIR=new_component
# Error: No current version found for new_component
```

**Cause:** Component doesn't have any versions yet.

**Solution:**
```bash
# For first version, create workspace from directory
make git_create_workspace DIR=new_component

# Make changes in workspace if needed
# Then commit with explicit version
make git_commit_version DIR=new_component VERSION=v1.0.0 DESC="Initial version"

# Promote to current
make git_promote_version DIR=new_component VERSION=v1.0.0
```

---

## Release Issues

### Release Already Exists

**Problem:**
```bash
make git_create_release VERSION=v2.0.0 DESC="Release"
# Error: Release v2.0.0 already exists
```

**Solution:**

**Option 1: Use auto-increment**
```bash
make git_create_release TYPE=major DESC="Release"
```

**Option 2: Use different version**
```bash
make git_create_release VERSION=v2.0.1 DESC="Release"
```

**Option 3: Delete existing (CAREFUL!)**
```bash
git tag -d release/v2.0.0
git push origin --delete release/v2.0.0
```

---

### Config File Not Found

**Problem:**
```bash
make git_create_release TYPE=patch CONFIG=release.json DESC="Release"
# Error: Config file 'release.json' not found
```

**Solution:**
```bash
# Generate config file first
make git_generate_config OUTPUT=release.json DESC="Release"

# Edit if needed
vim release.json

# Then create release
make git_create_release TYPE=patch CONFIG=release.json DESC="Release"
```

---

### Invalid Component Version in Config

**Problem:**
```bash
make git_create_release TYPE=patch CONFIG=release.json DESC="Release"
# Error: Version v1.0.99 does not exist for component 'gui'
```

**Cause:** Config file specifies version that doesn't exist.

**Solution:**
```bash
# Check available versions
make list_versions DIR=gui

# Edit config file with correct version
vim release.json

# Update to valid version (e.g., v1.0.5)
{
  "components": {
    "gui": "v1.0.5",  # Changed from v1.0.99
    ...
  }
}

# Try again
make git_create_release TYPE=patch CONFIG=release.json DESC="Release"
```

---

### Invalid JSON in Config

**Problem:**
```bash
make git_create_release TYPE=patch CONFIG=release.json DESC="Release"
# Error: Failed to parse release.json - Invalid JSON syntax
```

**Solution:**
```bash
# Validate JSON syntax
cat release.json | python3 -m json.tool

# Fix syntax errors (missing comma, bracket, etc.)
vim release.json

# Validate again
cat release.json | python3 -m json.tool

# Try again
make git_create_release TYPE=patch CONFIG=release.json DESC="Release"
```

---

## Git Issues

### Not in Git Repository

**Problem:**
```bash
make git_create_workspace DIR=gui
# Error: Not a git repository
```

**Solution:**
```bash
# Verify you're in correct directory
pwd
# Should be: .../CBFlow/PD/core

# Check git status
git status

# If not in repo, navigate to correct location
cd /path/to/CBFlow/PD/core
```

---

### Detached HEAD State

**Problem:**
```bash
git status
# HEAD detached at gui/v1.0.5
```

**Cause:** Accidentally checked out a version branch directly.

**Solution:**
```bash
# Return to main branch
git checkout main

# Or whatever your default branch is
git checkout master
```

**Prevention:**
- Don't manually checkout version branches
- Use `make git_promote_version` instead

---

### Uncommitted Changes Blocking Operation

**Problem:**
```bash
make git_create_workspace DIR=gui
# Error: You have uncommitted changes
```

**Solution:**
```bash
# Check what's uncommitted
git status

# Option 1: Commit changes
git add -A
git commit -m "Your commit message"

# Option 2: Stash changes
git stash

# Then try operation again
make git_create_workspace DIR=gui

# Restore stashed changes later
git stash pop
```

---

### Push Rejected

**Problem:**
```bash
git push origin main
# Error: Updates were rejected
```

**Solution:**
```bash
# Pull first
git pull origin main --rebase

# Resolve conflicts if any
# Then push
git push origin main
```

---

## Permission Issues

### Permission Denied

**Problem:**
```bash
make git_create_workspace DIR=gui
# Permission denied: workarea/worktrees/
```

**Solution:**
```bash
# Check directory permissions
ls -la workarea/

# Fix permissions if needed
chmod -R u+w workarea/

# Or create directory if missing
mkdir -p workarea/worktrees
```

---

### Script Not Executable

**Problem:**
```bash
make git_commit_version DIR=gui TYPE=patch DESC="Fix"
# Permission denied: utils/version/v2.0.0/git_worktree_manager.py
```

**Solution:**
```bash
# Make scripts executable
chmod +x utils/version/v2.0.0/*.py

# Or all at once
find utils/version/v2.0.0 -name "*.py" -exec chmod +x {} \;
```

---

## CHANGELOG Issues

### CHANGELOG Not Updated

**Problem:** Created version but CHANGELOG doesn't show it.

**Solution:**
```bash
# Check if CHANGELOG exists
ls -la gui/CHANGELOG.md

# View last update time
head -20 gui/CHANGELOG.md | grep "Last Updated"

# Check if version was created successfully
make list_versions DIR=gui

# View Git log for CHANGELOG
git log --oneline gui/CHANGELOG.md | head -10

# If still missing, contact maintainer
```

---

### CHANGELOG Accidentally Modified

**Problem:** Edited CHANGELOG manually, now it's broken.

**Solution:**
```bash
# Restore from Git
git checkout gui/CHANGELOG.md

# Or restore from specific commit
git log --oneline gui/CHANGELOG.md
git checkout <commit-hash> -- gui/CHANGELOG.md

# Or restore from specific version branch
git checkout gui/v1.0.5 -- CHANGELOG.md
```

**Prevention:**
- Never manually edit CHANGELOG files
- They are system-generated and read-only

---

## Directory Structure Issues

### Current Symlink Missing

**Problem:**
```bash
ls -la gui/current
# No such file or directory
```

**Solution:**
```bash
# Check available versions
make list_versions DIR=gui

# Promote a version to current
make git_promote_version DIR=gui VERSION=v1.0.5

# Verify
ls -la gui/current
# Should show: current -> v1.0.5
```

---

### Version Directory Missing

**Problem:**
```bash
ls gui/v1.0.5/
# No such file or directory
```

**Cause:** Version exists as Git branch but not checked out to directory.

**Solution:**
```bash
# Check version exists in Git
git branch | grep gui/v1.0.5

# If exists, promote it to checkout
make git_promote_version DIR=gui VERSION=v1.0.5

# Verify
ls -la gui/v1.0.5/
```

---

## Command Not Found Issues

### Make Target Not Found

**Problem:**
```bash
make git_create_workspace DIR=gui
# No rule to make target 'git_create_workspace'
```

**Solution:**
```bash
# Verify you're in correct directory
pwd
# Should be: .../CBFlow/PD/core

# Check RACE DB exists
ls -la .race_*.db

# List available make targets
make help
# Or
sqlite3 .race_*.db "SELECT * FROM run_info"
```

---

### Python Script Not Found

**Problem:**
```bash
make git_commit_version DIR=gui TYPE=patch DESC="Fix"
# Error: utils/version/v2.0.0/git_worktree_manager.py not found
```

**Solution:**
```bash
# Verify script exists
ls -la utils/version/v2.0.0/git_worktree_manager.py

# If missing, check Git status
git status

# Restore if needed
git checkout utils/version/
```

---

## Getting More Help

### Check Command Usage

```bash
# Most commands show usage when run without parameters
make git_commit_version

# Or with invalid parameters
make git_commit_version DIR=gui
```

### View Logs

```bash
# Git log for version
git log gui/v1.0.5

# Git log for releases
git log --grep="release/"

# System output logs
# (Commands show detailed output directly)
```

### Debug Mode

```bash
# Run Python scripts directly for detailed output
python3 utils/version/v2.0.0/git_worktree_manager.py --help

# Check Git worktrees
git worktree list

# Check Git branches
git branch --all | grep gui

# Check Git tags
git tag | grep gui
```

### Verify Installation

```bash
# Check Git
git --version

# Check Python
python3 --version

# Check Make
make --version

# Check current state
make list_versions DIR=gui
make git_list_workspaces
make git_list_releases
```

### Common Diagnostic Commands

```bash
# Overall system state
git status
git branch --all
git tag
git worktree list

# Component state
make list_versions DIR=gui
ls -la gui/
ls -la workarea/worktrees/

# Release state
make git_list_releases
cat RELEASE_CHANGELOG.md | head -50
```

## Prevention Best Practices

### Workspace Management
- ✅ Clean up workspaces after committing
- ✅ List active workspaces regularly
- ✅ Don't leave stale workspaces
- ✅ Use descriptive descriptions

### Version Creation
- ✅ Use TYPE=patch/minor/major for auto-increment
- ✅ Write clear DESC messages
- ✅ Verify versions before promoting
- ✅ Test changes in workspace first

### Release Creation
- ✅ Review component CHANGELOGs first
- ✅ Use config mode for production
- ✅ Validate config files
- ✅ Test release combinations

### Git Hygiene
- ✅ Stay on main branch
- ✅ Commit regularly
- ✅ Pull before pushing
- ✅ Don't manually checkout version branches

### CHANGELOG
- ✅ Read CHANGELOGs, never edit them
- ✅ Use Git to restore if corrupted
- ✅ Report issues if generation fails

## Still Having Issues?

If you're still stuck:

1. **Check documentation**:
   - [Quick Start](../01-quick-start/)
   - [User Guide](../02-user-guide/)
   - [Command Reference](../03-reference/)

2. **Verify prerequisites**:
   - [Installation Guide](../01-quick-start/installation.md)

3. **Check examples**:
   - [Examples](../06-examples/)

4. **Review architecture**:
   - [Architecture Guide](../04-architecture/)

5. **Contact maintainer**:
   - Include error messages
   - Include commands run
   - Include output of diagnostic commands

---

**Next**: [Reference Documentation](../03-reference/) →
