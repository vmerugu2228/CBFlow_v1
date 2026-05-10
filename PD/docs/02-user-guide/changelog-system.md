# CHANGELOG System

Understanding CBflow's automated change tracking system in v2.0.0.

## Overview

CBflow automatically maintains two types of CHANGELOGs:
1. **Component CHANGELOGs** -- Track changes for each versioned component
2. **Release CHANGELOG** -- Track system-wide releases

Both are **system-generated** and **read-only** -- users should never manually edit them.

## Component CHANGELOGs

### Location

Each versioned component has its own CHANGELOG:
```
config/flow/CHANGELOG.md
config/project/CHANGELOG.md
cmds/SYNTH/synopsys/fc/CHANGELOG.md
cmds/PNR/synopsys/fc/CHANGELOG.md
cmds/STA/synopsys/pt/CHANGELOG.md
cmds/PV/synopsys/icv/CHANGELOG.md
utils/utilities/CHANGELOG.md
utils/version/CHANGELOG.md
...
```

### Format

```markdown
<!--
THIS FILE IS AUTO-GENERATED - DO NOT EDIT MANUALLY

This CHANGELOG is automatically maintained by the CBflow versioning system.
Changes are recorded when versions are created using the versioning commands.

To create a new version: make git_commit_version DIR=<component> TYPE=patch|minor|major DESC="..."
To view version history: make list_versions DIR=<component>

Last Updated: 2026-05-09 14:30:15
-->

# CHANGELOG

## [v1.0.1] - 2026-05-09

### Description
Fixed timing constraints for STA corner setup

### Changes from v1.0.0

**Modified:**
- sta_pt.tcl

**Diff Statistics:**
 sta_pt.tcl | 5 +++--
 1 file changed, 3 insertions(+), 2 deletions(-)

**Detailed Changes:**
@@ -45,8 +45,9 @@
-        set corner_delay 0.1
+        set corner_delay 0.05

**Version Info:**
- Component: `cmds/STA/synopsys/pt`
- Version: `v1.0.1`
- Created: 2026-05-09 14:30:15
- Branch: `cmds_STA_synopsys_pt/v1.0.1`
- Tag: `cmds_STA_synopsys_pt-v1.0.1`
- Commit: `a3d2f1c`
- Previous: `v1.0.0`

---

## [v1.0.0] - 2026-04-15
...
```

### Content Sections

Each version entry includes:
- **Version number and date**: `## [v1.0.1] - 2026-05-09`
- **Description**: User-provided DESC from the commit command
- **File changes**: Added, modified, and deleted files
- **Diff statistics**: Line changes summary
- **Detailed diff**: Code-level changes (for small changes)
- **Version metadata**: Branch, tag, commit hash, timestamps

### When Updated

Component CHANGELOG is updated when:
```bash
make git_commit_version DIR=cmds/STA/synopsys/pt TYPE=patch DESC="..."
```

**Automatic actions:**
1. Creates version branch and tag
2. Generates diff from previous version
3. Appends new entry to CHANGELOG
4. Commits CHANGELOG to main branch

### Use Cases

#### Version Selection for Releases
```bash
# Review STA command changes before selecting a version for release
cat cmds/STA/synopsys/pt/CHANGELOG.md

# See what changed between versions
## [v1.0.1] - Fixed corner delay
## [v1.0.0] - Initial version

# Decision: Use v1.0.1 for release (has the corner fix)
```

#### Understanding Changes
```bash
# What changed in the latest PNR commands?
cat cmds/PNR/synopsys/fc/CHANGELOG.md | head -100

# What changed in flow config recently?
cat config/flow/CHANGELOG.md | head -50
```

#### Debugging Issues
```bash
# When did this file change?
cat cmds/PNR/synopsys/fc/CHANGELOG.md | grep place_fc.tcl

# What version introduced route optimization?
cat cmds/PNR/synopsys/fc/CHANGELOG.md | grep "route optimization"
```

## Release CHANGELOG

### Location

System-wide release tracking:
```
RELEASE_CHANGELOG.md  (at repository root)
```

### Format

```markdown
<!--
THIS FILE IS AUTO-GENERATED - DO NOT EDIT MANUALLY

This CHANGELOG tracks all system-wide releases created in CBflow.
Each release is a snapshot of component versions at a specific point in time.

To create a release: make git_create_release TYPE=patch|minor|major DESC="..."
To view releases: make git_list_releases

Last Updated: 2026-05-09 15:00:00
-->

# RELEASE CHANGELOG

## [v2.0.0] - 2026-05-09

### Description
Production release with tested component versions

### Release Configuration
**Mode**: CONFIG
**Components**: 29
**Config File**: release.json

### Component Versions
| Component | Version | Commit | Status |
|-----------|---------|--------|--------|
| config/flow | v1.0.0 | ee78586 | stable |
| cmds/SYNTH/synopsys/fc | v1.0.0 | a1b2c3d | stable |
| cmds/PNR/synopsys/fc | v1.0.1 | f3a8d2e | latest |
| cmds/STA/synopsys/pt | v1.0.0 | b7c8d9e | stable |
| cmds/PV/synopsys/icv | v1.0.0 | d4e5f6a | stable |
| utils/version | v2.0.0 | f1a2b3c | latest |
...

### Changed Components (from v1.0.1)

**Updated:**
- cmds/PNR/synopsys/fc: v1.0.0 -> v1.0.1

**New Versions:**
- utils/version: v1.0.0 -> v2.0.0 (major upgrade)

**Unchanged:**
- config/flow: v1.0.0 (stable, no changes needed)

### Release Info
- Release: `release/v2.0.0`
- Created: 2026-05-09 15:00:00
- Tag: `release/v2.0.0`
- Previous: `v1.0.1`
- Mode: CONFIG (user-specified versions)

---

## [v1.0.1] - 2026-05-08
...
```

### Content Sections

1. **Release Header** -- Version number, date, and description
2. **Release Configuration** -- Mode (AUTO or CONFIG), component count, config file reference
3. **Component Versions** -- Full list of all components with versions and commit hashes
4. **Changes from Previous** -- Updated, new, unchanged, and rolled-back components
5. **Release Metadata** -- Tag, timestamp, previous release reference, mode

### When Updated

Release CHANGELOG is updated when:
```bash
make git_create_release TYPE=patch CONFIG=release.json DESC="..."
```

**Automatic actions:**
1. Creates release tag
2. Compares with previous release
3. Identifies changed components
4. Appends new entry to RELEASE_CHANGELOG.md
5. Commits CHANGELOG to main branch

## CHANGELOG Workflow

### Component Version Workflow

```
Create Workspace --> Make Changes --> Commit Version --> Auto-Generate CHANGELOG Entry
```

```bash
make git_create_workspace DIR=cmds/PNR/synopsys/fc
# ... edit command files ...
make git_commit_version DIR=cmds/PNR/synopsys/fc TYPE=patch DESC="Improved route optimization"
# CHANGELOG.md updated automatically with new entry
```

### Release Workflow

```
Create Release --> Collect Versions --> Compare with Previous --> Generate Release Entry
```

```bash
make git_create_release TYPE=patch DESC="May release"
# RELEASE_CHANGELOG.md updated automatically with new entry
```

## Reading CHANGELOGs

### Find Specific Version

```bash
# Component version
grep "## \[v1.0.1\]" cmds/STA/synopsys/pt/CHANGELOG.md -A 50

# Release version
grep "## \[v2.0.0\]" RELEASE_CHANGELOG.md -A 100
```

### See Recent Changes

```bash
# Last entries of component CHANGELOG
head -200 cmds/PNR/synopsys/fc/CHANGELOG.md

# Last entries of release CHANGELOG
head -200 RELEASE_CHANGELOG.md
```

### Search for Specific Changes

```bash
# Find when a file was changed
grep "place_fc.tcl" cmds/PNR/synopsys/fc/CHANGELOG.md

# Find which release has a specific component version
grep "cmds/PNR.*v1.0.1" RELEASE_CHANGELOG.md
```

## Why CHANGELOGs are Read-Only

### Benefits

1. **Consistency**: All entries follow the same format
2. **Accuracy**: Generated directly from Git diffs, no human error
3. **Automation**: No manual maintenance required
4. **Completeness**: Changes are never forgotten
5. **Audit Trail**: Trusted source of truth

### What Happens if Manually Edited

- Next version creation will regenerate or overwrite changes
- Manual edits will be lost
- Formatting may break
- The system assumes it is the source of truth

**Instead:**
- Use the DESC parameter to provide descriptions
- Put detailed notes in Git commit messages
- Create separate documentation if needed

## Integration with Git

### CHANGELOG Commits

When CHANGELOG is updated, an automatic commit is created:
```bash
git commit -m "chore: Update CHANGELOG for cmds/STA/synopsys/pt v1.0.1"
```

### Version to CHANGELOG Mapping

```
Git Branch                           Git Tag                          CHANGELOG Entry
cmds_STA_synopsys_pt/v1.0.1   -->   cmds_STA_synopsys_pt-v1.0.1   --> [v1.0.1] - 2026-05-09
```

### Using Git with CHANGELOG

```bash
# View CHANGELOG for specific version
git show cmds_STA_synopsys_pt/v1.0.1:CHANGELOG.md

# See when CHANGELOG was updated
git log --follow cmds/STA/synopsys/pt/CHANGELOG.md

# Restore CHANGELOG if accidentally modified
git checkout cmds/STA/synopsys/pt/CHANGELOG.md
```

## Best Practices

### For Users

- Read CHANGELOGs before creating releases
- Use CHANGELOGs to understand version differences
- Reference CHANGELOG when reporting issues
- Include CHANGELOG excerpts in release notes
- Never manually edit CHANGELOG files
- Never delete CHANGELOG entries

### For Version Descriptions

When using DESC parameter, provide:
- Clear, concise summary of what changed
- Issues fixed (e.g., "Fixed timing corner setup delay")
- Features added (e.g., "Added per-corner STA reporting")
- Avoid generic descriptions like "Updates" or "Changes"

**Good examples:**
```bash
DESC="Fixed route optimization for congested regions"
DESC="Added PV fill stage for ICV metal fill insertion"
DESC="Updated STA extraction for TSMC 5nm tech node"
```

**Bad examples:**
```bash
DESC="Updates"
DESC="Changes"
DESC="Fixed stuff"
```

### For Release Descriptions

```bash
# Good -- describes purpose
DESC="P1 milestone release - timing closure complete"
DESC="Hotfix release - critical PV DRC rule update"
DESC="Q2 2026 production release - tested configuration"

# Bad -- too generic
DESC="Release"
DESC="New version"
```

## Troubleshooting

### CHANGELOG Not Updated

```bash
# Verify version was created successfully
make list_versions DIR=cmds/PNR/synopsys/fc

# Check CHANGELOG exists
ls -la cmds/PNR/synopsys/fc/CHANGELOG.md

# Check last update time
head -20 cmds/PNR/synopsys/fc/CHANGELOG.md | grep "Last Updated"
```

### CHANGELOG Shows Wrong Diff

```bash
# CHANGELOGs are generated from Git diffs
# If diff looks wrong, check:

# 1. Was workspace committed correctly?
git log --oneline | grep "cmds/PNR"

# 2. Does branch exist?
git branch | grep "cmds_PNR_synopsys_fc/v1.0.1"

# 3. Compare branches manually
git diff cmds_PNR_synopsys_fc/v1.0.0 cmds_PNR_synopsys_fc/v1.0.1
```

### CHANGELOG Accidentally Modified

```bash
# Restore from Git
git checkout cmds/PNR/synopsys/fc/CHANGELOG.md

# Or restore from specific version
git checkout cmds_PNR_synopsys_fc/v1.0.1 -- CHANGELOG.md
```

See [Troubleshooting Guide](troubleshooting.md) for more issues.

## Quick Reference

```bash
# View Component CHANGELOG
cat cmds/PNR/synopsys/fc/CHANGELOG.md
cat config/flow/CHANGELOG.md

# View Release CHANGELOG
cat RELEASE_CHANGELOG.md

# Find specific version
grep "## \[v1.0.1\]" cmds/STA/synopsys/pt/CHANGELOG.md -A 50

# See recent changes
head -200 cmds/PNR/synopsys/fc/CHANGELOG.md
tail -100 RELEASE_CHANGELOG.md

# Search for changes
grep "place_fc.tcl" cmds/PNR/synopsys/fc/CHANGELOG.md
grep -i "route optimization" cmds/PNR/synopsys/fc/CHANGELOG.md
```

**Remember:** CHANGELOGs are read-only, system-generated files. Use them to understand changes, select versions, and track history -- but never edit them manually.

---

**Next**: [Troubleshooting Guide](troubleshooting.md)
