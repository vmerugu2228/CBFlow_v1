# DEPRECATED: Old Makefile Command Scripts

## ⚠️ These Scripts Are Deprecated

The shell scripts in this directory are **deprecated** and no longer used by the CBFlow system.

## Migration

The system has migrated to **Git-based versioning** using:
- Git branches for versions
- Git worktrees for workspaces
- Git tags for releases

## Old Scripts (Deprecated)

| Script | Status | Replacement |
|--------|--------|-------------|
| `create_version.sh` | ❌ Deprecated | `git_version_manager.py create` |
| `set_version.sh` | ❌ Deprecated | `git_version_manager.py set_current` |
| `create_workspace.sh` | ❌ Deprecated | `git_worktree_manager.py create_workspace` |
| `commit_version.sh` | ❌ Deprecated | `git_worktree_manager.py commit_version` |
| `promote_version.sh` | ❌ Deprecated | `git_worktree_manager.py promote_version` |
| `list_workspace.sh` | ❌ Deprecated | `git_worktree_manager.py list_workspaces` |
| `release_flow.sh` | ❌ Deprecated | `git_release_manager.py create_release` |
| `release_info.sh` | ❌ Deprecated | `git_release_manager.py get_release_info` |

## New System

All version management is now in `utils/version/v2.0.0/`:

- **`git_version_manager.py`** - Version management with Git branches
- **`git_worktree_manager.py`** - Workspace management with Git worktrees
- **`git_release_manager.py`** - Release management with Git tags
- **`git_migration_manager.py`** - Migration utilities

## Documentation

See `MIGRATION_TO_GIT_VERSIONING.md` for:
- Command migration guide
- Benefits of new system
- Usage examples
- Troubleshooting

## Timeline

- **Now:** Scripts deprecated, Makefile shows migration message
- **v3.0.0:** These scripts will be removed

## Why Deprecated?

The old system had significant limitations:

- ❌ 26MB of duplicated files (slow, wasteful)
- ❌ 2s to create a version (Git: 0.1s)
- ❌ No version history
- ❌ Manual symlink management
- ❌ No way to compare or rollback

The new Git-based system provides:

- ✅ 94% storage reduction
- ✅ 20x faster operations
- ✅ Full Git history (log, diff, blame)
- ✅ Automatic symbolic ref management
- ✅ Easy version comparison
- ✅ Atomic operations with rollback

## Do Not Use

**Do not use these scripts directly.** They are kept only for reference and will be removed in the next major version.

Use the Git-based commands instead:

```bash
# Old (deprecated)
make create_version DIR=config VERSION=v1.0.0

# New (correct)
make git_create_version DIR=config VERSION=v1.0.0
```

For help, run: `make help` or see `GIT_VERSIONING_GUIDE.md`
