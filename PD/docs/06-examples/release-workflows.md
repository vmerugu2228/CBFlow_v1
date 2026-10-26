# Release Workflows

Examples of creating releases for different scenarios.

## Quick Internal Release

Fast release for testing or internal use.

```bash
# Review latest changes
cat gui/CHANGELOG.md | head -50
cat config/flow/CHANGELOG.md | head -50

# Create release (auto mode)
make git_create_release TYPE=patch DESC="Internal testing release"

# View release
make git_list_releases
cat RELEASE_CHANGELOG.md | head -100
```

**Time:** 2-3 minutes

---

## QA Testing Release

Release for QA team with specific component versions.

```bash
# 1. Generate config
make git_generate_config OUTPUT=qa-release.json DESC="QA Sprint 23"

# 2. Review and adjust versions
cat qa-release.json
vim qa-release.json
# Keep stable versions, update components being tested

# Example qa-release.json:
{
  "version": "auto",
  "description": "QA Sprint 23",
  "components": {
    "gui": "v1.0.5",        # Testing new GUI features
    "config/flow": "v1.0.0", # Stable version
    "utils/version": "v2.0.0" # Testing new version features
  }
}

# 3. Create release
make git_create_release TYPE=minor CONFIG=qa-release.json DESC="QA Sprint 23"

# 4. Checkout for testing
make git_checkout_release RELEASE=v1.1.0

# 5. Share with QA
# Location: workarea/releases/v1.1.0/
```

**Time:** 10-15 minutes

---

## Production Release

Fully tested release for production deployment.

```bash
# 1. Review all component versions
for component in gui config/flow config/project utils/version; do
  echo "=== $component ==="
  make list_versions DIR=$component
  cat $component/CHANGELOG.md | head -30
done

# 2. Generate production config
make git_generate_config OUTPUT=prod-v2.0.0.json DESC="Q4 2025 Production Release"

# 3. Carefully select versions
vim prod-v2.0.0.json
# Use only QA-approved, tested versions
# Document why each version was chosen

# Example prod-v2.0.0.json:
{
  "version": "v2.0.0",
  "description": "Q4 2025 Production Release",
  "components": {
    "gui": "v1.0.4",          # Stable, no known issues
    "config/flow": "v1.0.0",  # Production tested
    "config/project": "v1.0.0", # Rollback from v1.0.1 (had bugs)
    "utils/version": "v2.0.0" # QA approved
  }
}

# 4. Validate config
cat prod-v2.0.0.json | python3 -m json.tool

# 5. Create release
make git_create_release TYPE=major CONFIG=prod-v2.0.0.json DESC="Q4 2025 Production Release"

# 6. Archive config for records
mkdir -p releases/configs/
cp prod-v2.0.0.json releases/configs/

# 7. Checkout for packaging
make git_checkout_release RELEASE=v2.0.0

# 8. Create distribution package
cd workarea/releases/v2.0.0/
tar -czf ../CBFlow-v2.0.0.tar.gz *
cd ../../..

# 9. Document release
cat RELEASE_CHANGELOG.md | head -150 > releases/v2.0.0-RELEASE-NOTES.md
```

**Time:** 30-60 minutes

---

## Hotfix Release

Emergency fix for production issue.

```bash
# 1. Check current production release
make git_release_info RELEASE=v2.0.0

# 2. Fix the urgent bug
make git_create_workspace DIR=gui
# ... fix bug ...
make git_commit_version DIR=gui TYPE=patch DESC="Hotfix: Critical security vulnerability (#789)"
make git_promote_version DIR=gui VERSION=v1.0.5

# 3. Generate config based on production
make git_generate_config OUTPUT=hotfix-v2.0.1.json DESC="Hotfix release"

# 4. Update only the fixed component
vim hotfix-v2.0.1.json
{
  "version": "v2.0.1",
  "description": "Hotfix: Security vulnerability",
  "components": {
    "gui": "v1.0.5",          # UPDATED - hotfix
    "config/flow": "v1.0.0",  # Same as v2.0.0
    "config/project": "v1.0.0", # Same as v2.0.0
    "utils/version": "v2.0.0" # Same as v2.0.0
  }
}

# 5. Create hotfix release
make git_create_release TYPE=patch CONFIG=hotfix-v2.0.1.json DESC="Hotfix: Security vulnerability"

# 6. Fast-track to production
make git_checkout_release RELEASE=v2.0.1
cd workarea/releases/v2.0.1/
# ... deploy immediately ...
```

**Time:** 15-30 minutes (urgent)

---

**See also:**
- [Basic Workflows](basic-workflows.md) - Component versioning
- [Advanced Scenarios](advanced-scenarios.md) - Complex cases
