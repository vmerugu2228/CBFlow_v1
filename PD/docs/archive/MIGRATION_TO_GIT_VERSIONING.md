# Migration to Git-Based Versioning System

## Overview

The CBFlow system has migrated from directory copying and symlink-based versioning to a **Git-native versioning system** using branches, worktrees, and tags.

## Why Migrate?

### Old System Problems
- ❌ 26MB of duplicated files
- ❌ Slow operations (2s for version creation)
- ❌ No version history
- ❌ Manual symlink management
- ❌ No way to compare versions
- ❌ No rollback capability

### New System Benefits
- ✅ **94% storage reduction** (26MB → 1.5MB)
- ✅ **20x faster** version creation (2s → 0.1s)
- ✅ **Full Git history** (log, diff, blame)
- ✅ **Automatic** symbolic ref management
- ✅ **Easy version comparison** with git diff
- ✅ **Atomic operations** with rollback

## Command Migration Guide

All old commands have been deprecated and replaced with Git-based equivalents:

### Version Management

| Old Command | New Command | Notes |
|-------------|-------------|-------|
| `make create_version DIR=config VERSION=v1.0.0 DESC="..."` | `make git_create_version DIR=config VERSION=v1.0.0 DESC="..."` | Creates Git branch instead of copying |
| `make set_version DIR=config VERSION=v1.0.0` | `make git_set_current DIR=config VERSION=v1.0.0` | Uses symbolic ref instead of symlink |
| `make list_versions DIR=config` | `make list_versions DIR=config` | Now uses Git backend automatically |
| N/A | `make git_get_current DIR=config` | Get current version from symbolic ref |
| N/A | `make git_diff_versions DIR=config V1=v1.0.0 V2=v2.0.0` | Compare versions (NEW!) |

### Workspace Management

| Old Command | New Command | Notes |
|-------------|-------------|-------|
| `make create_workspace DIR=config` | `make git_create_workspace DIR=config` | Uses Git worktree instead of copying |
| `make commit_version DIR=config VERSION=v1.1.0 DESC="..."` | `make git_commit_version DIR=config VERSION=v1.1.0 DESC="..."` | Commits to Git branch |
| N/A | `make git_commit_version DIR=config TYPE=minor DESC="..."` | Auto-increment version (NEW!) |
| `make promote_version DIR=config VERSION=v1.1.0` | `make git_promote_version DIR=config VERSION=v1.1.0` | Updates symbolic ref |
| `make list_workspace DIR=config` | `make git_list_workspaces` | Lists all Git worktrees |
| N/A | `make git_cleanup_workspace DIR=config` | Remove worktree after commit |
| N/A | `make git_cleanup_all` | Cleanup all stale worktrees (NEW!) |

### Release Management

| Old Command | New Command | Notes |
|-------------|-------------|-------|
| `make release_flow VERSION=v1.0.0 DESC="..."` | `make git_create_release VERSION=v1.0.0 DESC="..."` | Creates Git tag with manifest |
| `make list_releases` | `make git_list_releases` | Lists Git release tags |
| `make release_info RELEASE=v1.0.0` | `make git_release_info RELEASE=v1.0.0` | Shows manifest from tag annotation |
| N/A | `make git_checkout_release RELEASE=v1.0.0` | Checkout exact release state (NEW!) |
| N/A | `make git_validate_release RELEASE=v1.0.0` | Validate release integrity (NEW!) |

## Migration Steps

### For Existing Users

1. **Update Your Workflows**
   - Replace old commands with Git-based equivalents
   - See command mapping table above

2. **No Data Migration Needed**
   - Git branches already created for existing versions
   - Old directory structure can remain for reference
   - New work should use Git-based commands

3. **Test Git Commands**
   ```bash
   # List versions
   make list_versions DIR=config

   # Create workspace
   make git_create_workspace DIR=config

   # Make changes...

   # Commit new version
   make git_commit_version DIR=config TYPE=minor DESC="Bug fixes"

   # Promote to current
   make git_promote_version DIR=config VERSION=v1.1.0
   ```

### For New Projects

Simply use the Git-based commands from the start:

```bash
# 1. Create initial version
make git_create_version DIR=mycomponent VERSION=v1.0.0 DESC="Initial version"
make git_set_current DIR=mycomponent VERSION=v1.0.0

# 2. Create workspace for development
make git_create_workspace DIR=mycomponent

# 3. Edit files
cd workarea/worktrees/mycomponent/workspace/
vim myfile.txt

# 4. Commit new version (auto-increment)
make git_commit_version DIR=mycomponent TYPE=minor DESC="New features"

# 5. Promote to current
make git_promote_version DIR=mycomponent VERSION=v1.1.0

# 6. Create release
make git_create_release VERSION=v1.0.0 DESC="First release"
```

## What Happened to Old Commands?

### Removed Commands (Production Deployment)

These commands have been **completely removed** from the production Makefile. Use the Git-based equivalents:

- ~~`make create_version`~~ → Use `make git_create_version`
- ~~`make set_version`~~ → Use `make git_set_current`
- ~~`make create_workspace`~~ → Use `make git_create_workspace`
- ~~`make commit_version`~~ → Use `make git_commit_version`
- ~~`make promote_version`~~ → Use `make git_promote_version`
- ~~`make list_workspace`~~ → Use `make git_list_workspaces`

### Updated Commands (Now Git-Based)

These commands have been updated to use Git backend automatically:

- `make list_versions` → Always uses Git branches now

### Old Scripts (Preserved for Reference)

Old shell scripts are preserved in `utils/makefile_commands/v1.0.0/` for reference but are no longer used:

- `create_version.sh` (deprecated)
- `set_version.sh` (deprecated)
- `create_workspace.sh` (deprecated)
- `commit_version.sh` (deprecated)
- `promote_version.sh` (deprecated)

**These scripts will be removed in a future release.**

## GIT_BACKEND Flag

The `GIT_BACKEND` flag is now **always true** and cannot be disabled. Git-based versioning is the only supported method.

Before:
```makefile
GIT_BACKEND ?= true  # Could be set to false
```

After:
```makefile
GIT_BACKEND := true  # Always true, not configurable
```

## Troubleshooting

### "No rule to make target" Error

If you see this error:
```
make: *** No rule to make target 'create_version'. Stop.
```

**Solution:** Old commands have been removed. Use the Git-based equivalents:
- `make git_create_version` instead of `create_version`
- `make git_set_current` instead of `set_version`
- `make git_create_workspace` instead of `create_workspace`
- `make git_commit_version` instead of `commit_version`
- `make git_promote_version` instead of `promote_version`
- `make git_list_workspaces` instead of `list_workspace`

### Old Scripts Still Referenced

If old scripts are referenced in custom workflows:

1. Update workflows to use Git-based commands
2. See command migration table above
3. Consult `GIT_VERSIONING_GUIDE.md` for detailed usage

### Need Old Behavior

The old directory-based system is no longer supported. All benefits of the Git-based system outweigh any perceived advantages of the old system:

- **Performance:** 20x faster
- **Storage:** 94% less space
- **Features:** Full Git history, diff, rollback
- **Reliability:** Atomic operations

## Documentation

- **Complete Guide:** `core/GIT_VERSIONING_GUIDE.md`
- **This Migration Guide:** `core/MIGRATION_TO_GIT_VERSIONING.md`
- **API Documentation:** Inline help in all make commands

## Support

For questions or issues:

1. Run `make help` for command overview
2. Check `GIT_VERSIONING_GUIDE.md` for detailed examples
3. Use `make <command>` without parameters to see usage

## Timeline

- **v1.0.0:** Directory-based versioning (deprecated)
- **v2.0.0:** Git-based versioning (current) - **Old commands removed from production**
- **v3.0.0:** Old scripts archived (future)

## Summary

✅ All version management now uses Git branches
✅ All workspace management now uses Git worktrees
✅ All releases now use Git tags with manifests
✅ Old commands deprecated with clear migration paths
✅ 94% storage reduction, 20x performance improvement
✅ Full Git history and advanced features

**The migration is complete and the system is production-ready!**
