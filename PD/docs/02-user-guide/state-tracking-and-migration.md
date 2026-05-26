# CBflow State Tracking & Bundle Migration Guide

Track changes, migrate customizations, and upgrade bundles — without git.

---

## 1. Overview

CBflow bundles ship without `.git`. The **State Tracking** system provides lightweight version control using SQLite, and the **Migration** system safely carries your customizations when upgrading to a new release.

| Tool | Purpose |
|------|---------|
| `cbflow state` | Track what you changed in your bundle (like `git status/commit/log`) |
| `cbflow migrate` | Carry customizations from old bundle to new bundle |

Both work completely offline — no git, no network.

---

## 2. State Tracking (`cbflow state`)

### 2.1 How It Works

A SQLite database (`.cbflow_state.db`) inside `PD/` stores MD5 checksums of every tracked file. When you modify a file, `cbflow state status` instantly detects it by comparing current MD5 against the stored checksum.

The database ships with the bundle — `cbflow bundle` auto-initializes it at creation time.

### 2.2 First Time Setup

If your bundle doesn't have `.cbflow_state.db` (older bundle), initialize it:

```bash
cbflow state init
```

Output:
```
  State Initialized
  ════════════════════════════════════════════════════════════
  Files tracked: 768
  Commit #1:     Initial release state
  DB:            .cbflow_state.db
```

### 2.3 Check What You Changed

```bash
cbflow state status
```

Output:
```
  CBflow State Status
  ════════════════════════════════════════════════════════════
  Last commit: #1 — Initial release state
  ────────────────────────────────────────────────────────────
  Added:    0
  Modified: 2
  Deleted:  0
  ────────────────────────────────────────────────────────────

  Modified:
    M  PD/config/project/ravendrive/v1.0.0/ravendrive_config.tcl
    M  PD/config/tech/gf_22nm/v1.0.0/tech_config.tcl
```

### 2.4 Record Your Changes

```bash
cbflow state commit -m "Configured for our 7T process and 10M metal stack"
```

Output:
```
  Commit #2: Configured for our 7T process and 10M metal stack
  ────────────────────────────────────────────────────────────
  Added:    0
  Modified: 2
  Deleted:  0
  Total:    768 files tracked
```

### 2.5 Create Named Snapshots

Before making risky changes, take a snapshot:

```bash
cbflow state snapshot --tag "pre_cts_fix" -m "Stable state before CTS NDR changes"
```

### 2.6 View History

```bash
cbflow state log
```

Output:
```
  CBflow State History (3 commits)
  ══════════════════════════════════════════════════════════════════════

  #3 [pre_cts_fix]  2026-05-26T15:30:00  by john
    Stable state before CTS NDR changes
    +0 ~0 -0 (768 files)

  #2                2026-05-26T14:00:00  by john
    Configured for our 7T process and 10M metal stack
    +0 ~2 -0 (768 files)

  #1 [release]      2026-05-26T10:00:00  by release_manager
    Initial release state
    +768 ~0 -0 (768 files)
```

### 2.7 Inspect a Specific Commit

```bash
cbflow state show 2
```

Output:
```
  Commit #2: Configured for our 7T process and 10M metal stack
  Date: 2026-05-26T14:00:00  User: john  Tag: -
  ────────────────────────────────────────────────────────────
  M  PD/config/project/ravendrive/v1.0.0/ravendrive_config.tcl
  M  PD/config/tech/gf_22nm/v1.0.0/tech_config.tcl

  Total: 2 changed files
```

### 2.8 View Modified File Details

```bash
cbflow state diff
```

Shows each modified file with old/new MD5 checksums and file size.

### 2.9 Compare Against Another Bundle

When a new release arrives, compare before migrating:

```bash
cbflow state compare --with /opt/cbflow_v2
```

Output:
```
  Bundle Comparison
  ══════════════════════════════════════════════════════════════════════
  Ours:   /opt/cbflow_v1 (768 files)
  Other:  /opt/cbflow_v2 (785 files)
  ──────────────────────────────────────────────────────────────────────
  Only in other (new):     17
  Different (modified):    23
  Only in ours (removed):  0
  Identical:               745
```

---

## 3. Bundle Migration (`cbflow migrate`)

### 3.1 When Do You Need Migration?

When you receive a new CBflow bundle and want your customizations (project configs, tech config edits, threshold overrides, waivers) to carry over to the new version.

**Important:** Existing runs are standalone — they are NOT touched. Migration only updates the CBflow installation so that **new runs** inherit your customizations.

### 3.2 Migration Workflow

```bash
# Step 1: Unpack new bundle
tar xzf CBflow_v2.0.1.tar.gz
cd CBflow_v2.0.1

# Step 2: See what changed in the new release
cbflow migrate --diff --from /opt/cbflow_v1 --to /opt/cbflow_v2

# Step 3: Preview migration (no changes made)
cbflow migrate --from /opt/cbflow_v1 --to /opt/cbflow_v2 --dry-run

# Step 4: Migrate
cbflow migrate --from /opt/cbflow_v1 --to /opt/cbflow_v2

# Step 5: Verify new bundle is healthy
cbflow migrate --check --to /opt/cbflow_v2

# Step 6: Point environment to new bundle
export CBFLOW_HOME=/opt/cbflow_v2/PD
export PATH=$CBFLOW_HOME/bin:$PATH

# Step 7: Create new runs
cbflow workspace create --config user_config.tcl
```

### 3.3 What Gets Migrated

The migration detects files you modified in the old bundle (using `.cbflow_state.db` or `MANIFEST.checksums`) and copies them to the new bundle.

**Auto-migrated (safe — no conflict):**
- Files you modified that the new release did NOT change

**Prompted (conflict):**
- Files you modified AND the new release also changed
- You choose: `[K]eep yours`, `[N]ew release version`, or `[S]kip`

**Never migrated (always use new version):**
- `PD/bin/*` — CLI scripts
- `PD/utils/commands/*.py` — Python commands
- `PD/utils/dashboard/*.py` — Dashboard code

**Never migrated (always user-owned, already in new bundle's template):**
- `setup/user_config.tcl` — Per-run configs (in workarea, not in bundle)
- `setup/override_config*.tcl` — Per-run overrides

### 3.4 Conflict Resolution

When both you and the release changed the same file:

```
  CONFLICT: PD/config/tech/gf_22nm/v1.0.0/tech_config.tcl
  Your version differs from original release.
  New release also updated this file.
  [K]eep your version  [N]ew release version  [S]kip
  >
```

| Choice | What Happens |
|--------|-------------|
| **K** (Keep) | Your version is copied to new bundle. New release version backed up as `.release_backup` |
| **N** (New) | New release version is kept. Your version is NOT copied. |
| **S** (Skip) | File is left as-is in new bundle. Decide later manually. |

### 3.5 Release Diff

See what's new in the release before migrating:

```bash
cbflow migrate --diff --from /opt/cbflow_v1 --to /opt/cbflow_v2
```

Output:
```
  Release Diff
  ══════════════════════════════════════════════════════════════════════
  Old: /opt/cbflow_v1
  New: /opt/cbflow_v2
  ──────────────────────────────────────────────────────────────────────
  Added:   17
  Changed: 23
  Removed: 0
  Your modifications: 5
  Potential conflicts: 2

  NEW FILES (17):
    + PD/config/exit/v1.0.0/checks/eco_flow_checks.tcl
    + PD/config/exit/v1.0.0/EMIR_SIGNOFF_config.tcl
    + PD/utils/commands/state_cmd.py
    ...

  CHANGED FILES (23):
    ~ PD/utils/commands/race_engine.py
    ~ PD/config/tech/gf_22nm/v1.0.0/tech_config.tcl ← CONFLICT (you also modified)
    ...
```

### 3.6 Compatibility Check

After migration, verify everything works:

```bash
cbflow migrate --check --to /opt/cbflow_v2
```

Runs 5 checks:
1. **Command file syntax** — All 315 TCL files parse clean
2. **Config file syntax** — All 131 config files parse clean
3. **Python compilation** — All 49 Python scripts compile
4. **Variable cross-reference** — Variables used in commands exist in configs
5. **Source file references** — All sourced files exist

### 3.7 Validate Installation

Quick health check of current installation:

```bash
cbflow migrate --validate
```

Checks: directories exist, critical files present, project config paths valid.

---

## 4. Typical Customer Scenarios

### Scenario 1: First Bundle (No Previous Install)

```bash
tar xzf CBflow_v2.0.0.tar.gz
cd CBflow_v2.0.0

# Set environment
export CBFLOW_HOME=$(pwd)/PD
export PATH=$CBFLOW_HOME/bin:$PATH

# Configure project (edit paths for your environment)
vi PD/config/project/myproject/v1.0.0/myproject_config.tcl

# Record your setup
cbflow state commit -m "Initial project configuration"

# Create runs
cbflow workspace create --config user_config.tcl
```

### Scenario 2: Upgrade to New Release

```bash
# Unpack new bundle
tar xzf CBflow_v2.0.1.tar.gz

# Check what's new
cbflow migrate --diff --from /opt/cbflow_v2.0.0 --to /opt/cbflow_v2.0.1

# Migrate your customizations
cbflow migrate --from /opt/cbflow_v2.0.0 --to /opt/cbflow_v2.0.1

# Verify
cbflow migrate --check --to /opt/cbflow_v2.0.1

# Switch
export CBFLOW_HOME=/opt/cbflow_v2.0.1/PD
```

### Scenario 3: Multiple Engineers Sharing a Bundle

Each engineer modifies their project config. State tracking shows who changed what:

```bash
# Engineer A
cbflow state commit -m "Configured ravendrive for 9T track"

# Engineer B
cbflow state commit -m "Added 5nm tech config for phoenix"

# View all changes
cbflow state log
#  #3  2026-05-26  by engineer_b  — Added 5nm tech config
#  #2  2026-05-26  by engineer_a  — Configured ravendrive for 9T
#  #1  release     by release_mgr — Initial release state
```

### Scenario 4: Before Risky Configuration Change

```bash
# Snapshot current state
cbflow state snapshot --tag "stable_v1" -m "Working config before NDR changes"

# Make changes
vi PD/config/tech/gf_22nm/v1.0.0/cts_ndr.tcl

# Check what changed
cbflow state status

# If it breaks, know exactly what to revert
cbflow state show 4   # See what changed since snapshot
```

---

## 5. What Gets Tracked

| Category | Tracked | Example |
|----------|---------|---------|
| Command files | Yes | `PD/cmds/SYNTH_PNR/synopsys/fc/v1.0.0/*.tcl` |
| Flow configs | Yes | `PD/config/flow/v1.0.0/*.tcl` |
| Node configs | Yes | `PD/config/flow/v1.0.0/node_configs/*.tcl` |
| Tech configs | Yes | `PD/config/tech/gf_22nm/v1.0.0/*.tcl` |
| Project configs | Yes | `PD/config/project/ravendrive/v1.0.0/*.tcl` |
| Exit configs | Yes | `PD/config/exit/v1.0.0/*.tcl` |
| Check libraries | Yes | `PD/config/exit/v1.0.0/checks/*.tcl` |
| Metal stack configs | Yes | `PD/config/tech/*/metal_stack/*.tcl` |
| Python commands | Yes | `PD/utils/commands/*.py` |
| Dashboard | Yes | `PD/utils/dashboard/*.py` |
| Validation scripts | Yes | `PD/utils/validation/**/*.tcl` |
| Check scripts | Yes | `PD/utils/validation/v1.0.0/checks/*.tcl` |
| Documentation | Yes | `PD/docs/**/*.md` |

**Not tracked:** `.cbflow_state.db` itself, `__pycache__/`, `.pyc`, AI agent files, `.git/`

---

## 6. Command Reference

| Command | Description |
|---------|-------------|
| `cbflow state init` | Initialize tracking (first commit = release state) |
| `cbflow state status` | Show changes since last commit |
| `cbflow state diff` | Show modified file details |
| `cbflow state commit -m "msg"` | Record current state |
| `cbflow state commit -m "msg" --tag "name"` | Record with named tag |
| `cbflow state snapshot --tag "name"` | Alias for commit with tag |
| `cbflow state log` | View commit history |
| `cbflow state show <id>` | Show files changed in commit |
| `cbflow state compare --with /path` | Compare against another bundle |
| `cbflow migrate --from /old --to /new` | Migrate customizations |
| `cbflow migrate --from /old --to /new --dry-run` | Preview migration |
| `cbflow migrate --diff --from /old --to /new` | Show release diff |
| `cbflow migrate --check --to /path` | Verify bundle compatibility |
| `cbflow migrate --validate` | Check installation health |

---

## 7. Files Created

| File | Location | Purpose |
|------|----------|---------|
| `.cbflow_state.db` | `PD/.cbflow_state.db` | SQLite state database (ships with bundle) |
| `MANIFEST.checksums` | `PD/MANIFEST.checksums` | MD5 checksums for migration (ships with bundle) |
| `.release_backup` | Next to migrated files | Backup of new release version during conflict resolution |
