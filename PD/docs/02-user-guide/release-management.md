# Release Management

Complete guide to creating and managing system-wide releases in CBflow v2.0.0.

## Overview

CBflow supports two release modes:
1. **Auto Mode** -- Automatically uses latest versions of all components
2. **Config Mode** -- Uses user-specified versions from a configuration file

### Release Path Convention

All releases follow a structured path:

```
$project(release,path)/$phase/$block_name/$release_tag
```

For example:
```
/releases/bumblebee/P0/cpu_core/v1.0.2
```

## Auto Mode (Quick Releases)

### Basic Usage

```bash
# Create release with auto-increment
make git_create_release TYPE=patch|minor|major DESC="Release description"
```

### How It Works

1. **Version Discovery**: Automatically finds all components with versions
2. **Latest Selection**: Uses `current` version of each component
3. **Auto-Increment**: Increments release version based on TYPE
4. **Tag Creation**: Creates Git tag `release/vX.Y.Z`
5. **CHANGELOG Update**: Updates `RELEASE_CHANGELOG.md`

### Example

```bash
# Create patch release
make git_create_release TYPE=patch DESC="Bug fixes and PNR timing improvements"
```

**Output:**
```
Auto-incremented version: v1.0.1
Collecting component versions (auto mode - latest versions)...

Release Components (29):
  config/flow                    v1.0.0       (ee78586)
  config/project                 v1.0.1       (f3a8d2e)
  cmds/SYNTH/synopsys/fc         v1.0.0       (a1b2c3d)
  cmds/PNR/synopsys/fc           v1.0.0       (d4e5f6a)
  cmds/STA/synopsys/pt           v1.0.0       (b7c8d9e)
  cmds/PV/synopsys/icv           v1.0.0       (f0a1b2c)
  ...

Release v1.0.1 created successfully
  Tag: release/v1.0.1
  Components: 29
```

### When to Use Auto Mode

- Rapid development releases
- Internal testing releases
- Continuous integration builds
- When all latest versions are stable

## Config Mode (Controlled Releases)

### Workflow Overview

```
Generate Config --> Edit Versions --> Validate Config --> Create Release
```

### Step 1: Generate Config Template

```bash
make git_generate_config OUTPUT=release.json DESC="Production release"
```

**Creates `release.json`:**
```json
{
  "version": "auto",
  "description": "Production release",
  "components": {
    "config/flow": "v1.0.0",
    "config/project": "v1.0.1",
    "cmds/SYNTH/synopsys/fc": "v1.0.0",
    "cmds/PNR/synopsys/fc": "v1.0.0",
    "cmds/STA/synopsys/pt": "v1.0.0",
    "cmds/PV/synopsys/icv": "v1.0.0",
    "utils/version": "v2.0.0"
  }
}
```

### Step 2: Customize Versions

Edit `release.json` to specify exact versions:

```json
{
  "version": "v2.0.0",
  "description": "Production release with tested components",
  "components": {
    "config/flow": "v1.0.0",
    "config/project": "v1.0.0",
    "cmds/SYNTH/synopsys/fc": "v1.0.0",
    "cmds/PNR/synopsys/fc": "v1.0.1",
    "cmds/STA/synopsys/pt": "v1.0.0",
    "cmds/PV/synopsys/icv": "v1.0.0",
    "utils/version": "v2.0.0"
  }
}
```

**Common customizations:**
- Use older stable versions instead of latest
- Pin specific tested combinations
- Rollback problematic components
- Mix and match versions across flows

### Step 3: Create Release from Config

```bash
# Auto-increment with config
make git_create_release TYPE=major CONFIG=release.json DESC="Tested production release"

# Or specify exact version
make git_create_release VERSION=v2.0.0 CONFIG=release.json DESC="Tested production release"
```

**Validation Process:**
1. Reads `release.json`
2. Validates each version exists
3. Checks all Git branches/tags present
4. Creates release only if all valid

### When to Use Config Mode

- Production releases
- Customer deliveries
- Milestone releases (P0, P1, P2, P3)
- QA-tested combinations
- Tapeout deliverables

## Release Information

### List All Releases

```bash
make git_list_releases
```

**Output:**
```
System Releases:
Version         Date         Components    Description
------------------------------------------------------------------
v2.0.0          2026-05-09   29           Tested production release
v1.0.1          2026-05-08   29           Bug fixes
v1.0.0          2026-05-01   29           Initial release
```

### View Release Details

```bash
make git_release_info RELEASE=v2.0.0
```

### Compare Releases

```bash
make git_diff_releases R1=v1.0.0 R2=v2.0.0
```

Shows component version differences between releases.

## Phase-Based Releases

CBflow organizes releases around project phases and stage exit milestones:

### Phase Milestones

| Phase | Description | Typical Release Activities |
|:---:|---|---|
| P0 | Trial | Initial synthesis, first floorplan, early timing closure |
| P1 | Implementation | Timing closure iterations, power optimization, DRC/LVS |
| P2 | Pre-signoff | Sign-off timing, final verification, ECO implementation |
| P3 | Tapeout | Tapeout data generation, manufacturing release |

### Stage Exit Milestones

| Milestone | Description |
|-----------|-------------|
| FP_EXIT | Floorplan complete, area/utilization targets met |
| PLACE_EXIT | Placement complete, timing/congestion acceptable |
| CTS_EXIT | Clock tree synthesized, skew targets met |
| PRO_EXIT | Post-route optimization complete |
| BTO | Backend tapeout ready |
| MTO | Manufacturing tapeout ready |

## Validation

### Validate Release Config

```bash
# Config validation happens automatically during release creation
make git_create_release TYPE=major CONFIG=release.json DESC="..."
```

**Validation checks:**
1. All components exist
2. All versions exist as Git branches/tags
3. JSON syntax is valid
4. Required fields present

### Validation Errors

**Invalid version specified:**
```
Error: Version v1.0.99 does not exist for component 'cmds/PNR/synopsys/fc'
Available versions: v1.0.0, v1.0.1
```

**Missing component:**
```
Error: Component 'unknown/component' specified in config does not exist
```

**Malformed JSON:**
```
Error: Failed to parse release.json - Invalid JSON syntax
```

## Release CHANGELOG

Every release creates or updates `RELEASE_CHANGELOG.md`:

```markdown
## [v2.0.0] - 2026-05-09

### Description
Tested production release

### Release Configuration
**Mode**: CONFIG
**Components**: 29

### Component Versions
| Component | Version | Commit |
|-----------|---------|--------|
| config/flow | v1.0.0 | ee78586 |
| cmds/PNR/synopsys/fc | v1.0.1 | a3d2f1c |
...

### Changed Components (from v1.0.1)
**Updated:**
- cmds/PNR/synopsys/fc: v1.0.0 -> v1.0.1

**Unchanged:**
- config/flow: v1.0.0
...
```

## Checkout Release

### Extract Release Contents

```bash
make git_checkout_release RELEASE=v2.0.0
```

**Creates:** `workarea/releases/v2.0.0/`

**Use cases:**
- Package release for distribution
- Verify release contents
- Build from specific release
- Archive release snapshot

## Version Locking

Released versions are permanently read-only. When a version is released (via `cbflow flow version create`, `cbflow flow dev promote`, or the release system), CBflow:

1. Sets all files in the version directory to `chmod 444` (read-only)
2. Creates a `.locked` marker file in the version directory

**This is irreversible** -- there is no unlock command or way to revert a locked version.

```bash
# After release, a version directory looks like:
# cmds/SYNTH/synopsys/fc/v1.0.0/.locked   (marker file)
# All files in v1.0.0/ are chmod 444

# Attempting to edit a locked version results in:
# Permission denied
```

To make changes to a released component, use the dev workflow to create a new version.

## Dev Workflow

The dev workflow provides a structured way to develop, test, and promote changes to released versions. Dev versions use the `-dev` suffix convention.

### Starting Development

```bash
# Start a dev version from an existing released version
cbflow flow dev start --dir cmds/SYNTH --from v1.0.0
# Creates: cmds/SYNTH/synopsys/fc/v1.0.0-dev/ (writable copy)
```

### Working with Dev Versions

```bash
# Check status of all active dev versions
cbflow flow dev status

# View changes made in a dev version vs its base
cbflow flow dev diff --dir cmds/SYNTH

# Create an isolated sandbox for experimentation
cbflow flow dev sandbox-create --name experiment1

# Push sandbox changes back to the dev version
cbflow flow dev sandbox-push --name experiment1
```

### Promoting to Release

```bash
# Promote dev version to a new released version
cbflow flow dev promote --dir cmds/SYNTH --version v1.0.1
# v1.0.1 is created with version locking (chmod 444 + .locked)
# v1.0.0-dev is removed
```

### Dev Workflow Lifecycle

```
v1.0.0 (locked)  -->  cbflow flow dev start  -->  v1.0.0-dev (writable)
                                                       |
                                                  edit, test, iterate
                                                       |
                                              cbflow flow dev promote
                                                       |
                                                  v1.0.1 (locked)
```

## Best Practices

### Auto Mode
- Use for internal and development releases
- Test all components before releasing
- Review component CHANGELOGs first
- Document release purpose clearly

### Config Mode
- Use for production and customer releases
- Test version combinations thoroughly
- Document why specific versions were chosen
- Save config files for audit trail
- Use meaningful release descriptions

### Dev Workflow
- Always use `cbflow flow dev start` instead of manually copying versions
- Run `cbflow flow dev diff` before promoting to review all changes
- Use sandboxes for risky experiments to avoid polluting the dev version
- Promote promptly -- long-lived dev versions increase merge risk

### Version Selection
- Check component CHANGELOG before choosing a version
- Use stable, tested versions for production
- Consider dependencies between components
- Document any known issues

### Release Frequency
- Patch releases: As needed (bug fixes)
- Minor releases: Weekly or bi-weekly (features)
- Major releases: Monthly or quarterly (milestones)

## Common Workflows

### Quick Internal Release
```bash
# Review latest changes
cat config/flow/CHANGELOG.md
cat cmds/PNR/synopsys/fc/CHANGELOG.md

# Create release
make git_create_release TYPE=patch DESC="Bug fixes"

# Verify
make git_release_info RELEASE=v1.0.1
```

### Production Release
```bash
# Generate config from current state
make git_generate_config OUTPUT=prod-release.json DESC="Q2 Release"

# Customize versions based on testing
vim prod-release.json

# Create release
make git_create_release TYPE=minor CONFIG=prod-release.json DESC="Q2 Production Release"

# Archive config for records
cp prod-release.json releases/configs/v1.1.0-config.json

# Checkout for packaging
make git_checkout_release RELEASE=v1.1.0
```

### Hotfix Release
```bash
# Generate config based on last production release
make git_release_info RELEASE=v2.0.0 > current-prod.txt

# Create config with just the hotfixed component updated
# Edit release.json to change only the fixed component

# Create hotfix release
make git_create_release TYPE=patch CONFIG=release.json DESC="Hotfix for timing issue"
```

## Troubleshooting

### Config Validation Failed
```bash
# View detailed error
make git_create_release TYPE=patch CONFIG=release.json DESC="..." 2>&1 | less

# Check component versions
make list_versions DIR=cmds/PNR/synopsys/fc

# Verify JSON syntax
cat release.json | python3 -m json.tool
```

### Release Already Exists
```bash
# View existing releases
make git_list_releases

# Use different version
make git_create_release VERSION=v2.0.1 CONFIG=release.json DESC="..."
```

### Missing Components in Config
```bash
# Regenerate config to get all current components
make git_generate_config OUTPUT=new-release.json DESC="..."

# Merge with your customizations
```

See [Troubleshooting Guide](troubleshooting.md) for more issues.

## Quick Reference

```bash
# Auto Mode
make git_create_release TYPE=patch|minor|major DESC="..."

# Config Mode
make git_generate_config OUTPUT=<file> DESC="..."
# ... edit file ...
make git_create_release TYPE=<type> CONFIG=<file> DESC="..."

# Information
make git_list_releases
make git_release_info RELEASE=<version>
make git_diff_releases R1=<v1> R2=<v2>

# Checkout
make git_checkout_release RELEASE=<version>

# Dev Workflow
cbflow flow dev start --dir <dir> --from <version>   # Start dev version
cbflow flow dev status                                # List active dev versions
cbflow flow dev diff --dir <dir>                      # Show changes
cbflow flow dev promote --dir <dir> --version <new>   # Promote to release
cbflow flow dev sandbox-create --name <name>          # Create sandbox
cbflow flow dev sandbox-push --name <name>            # Push sandbox changes
```

---

**Next**: [CHANGELOG System](changelog-system.md)
