# Versioning Strategy

Design and rationale for CBflow's directory-based versioning system.

## Overview

CBflow uses **directory-based versioning** for managing configuration and script versions. This is deliberately not Git-branch-based or Git-worktree-based. Versions are physical directories on disk, and the active version is indicated by a `current` filesystem symlink.

## Why Directory-Based (Not Git Worktrees)

| Concern | Directory-Based | Git Worktree-Based |
|---------|----------------|-------------------|
| Simplicity | Plain directories, no Git knowledge needed | Requires Git branch/worktree understanding |
| Transparency | `ls` shows all versions | Versions hidden in Git refs |
| Debuggability | Inspect any version with standard tools | Requires Git checkout to inspect |
| Rollback | Re-point symlink | Must manage branch refs |
| Multi-user | No conflicts (each user has own workspace) | Worktree locking issues |
| Disk cost | Higher (full copies) | Lower (Git dedup) |
| Audit trail | Directory timestamps + VCS history | Git log |

The disk cost tradeoff is acceptable because config/script directories are small (typically < 1 MB per version).

## Version Copy Workflow

```
1. Copy
   config/v1.0.0/  -->  config/v1.0.1/   (full directory copy)

2. Edit
   Modify files in config/v1.0.1/ directly

3. Promote
   config/current  -->  v1.0.1   (update symlink)
```

### Atomicity

Symlink updates are atomic on POSIX systems. The `set-current` operation:

1. Creates a temporary symlink to the new version
2. Atomically renames it to `current`
3. Result: no window where `current` is invalid

## Directory Layout

```
config/
    v1.0.0/                 # First version
        flow_config.tcl
        node_SYNTH.tcl
        node_PNR.tcl
        mmmc_config.tcl
    v1.0.1/                 # Second version (copy of v1.0.0, edited)
        flow_config.tcl     # Modified
        node_SYNTH.tcl
        node_PNR.tcl
        mmmc_config.tcl
    v1.0.2/                 # Third version
        ...
    current -> v1.0.1       # Symlink to active version
```

## Version Lifecycle

```
Created           Active             Superseded          Archived
   |                |                    |                   |
   v                v                    v                   v
v1.0.0/         current -> v1.0.0    current -> v1.0.1    (deleted or
exists on        flows use this       v1.0.0 still         moved to
disk             version              exists but            archive/)
                                      not active
```

## Rollback

Rolling back is a single symlink operation:

```bash
cbflow flow version set-current --dir config --version v1.0.0
# config/current now points to v1.0.0
```

No branch manipulation, no merge conflicts, no checkout required.

## Relationship to Source Control

The CBflow repository itself uses standard Git for source control (commits, branches, PRs). However, the **version management of config/script directories** within the repo is directory-based, not branch-based.

- Git tracks the directory structure normally (all version directories are committed)
- The `current` symlink is tracked by Git as well
- This means `git log` shows the full history of version changes
- But the versioning workflow itself (copy, edit, set-current) does not use Git branches or worktrees

## Best Practices

- Do not delete old version directories that have been used in completed runs. They serve as an audit trail.
- Use semantic version names (v1.0.0, v1.0.1) for standard iterations.
- Use descriptive suffixes (v1.0.0_eco_hotfix) for special-purpose versions.
- Always verify `current` symlink target before launching a flow.

---

**See also:**
- [Versioning Workflow](../02-user-guide/versioning-workflow.md) -- User-facing workflow
- [System Design](system-design.md) -- Overall architecture
- [Configuration Reference](../03-reference/configuration-reference.md) -- Config file details
