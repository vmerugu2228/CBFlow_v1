# Data Flow

Data flow and process workflows in CBFlow versioning system.

## Version Creation Flow

### Complete Workflow

```
┌────────────────────────────────────────────────────────────┐
│                     User Initiates                          │
│    cbflow flow version commit --dir gui --type patch       │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│             1. RACE DAG Validation                │
│  - Check DIR exists                                         │
│  - Validate TYPE (patch/minor/major)                        │
│  - Check DESC provided                                      │
└──────────────────────┬─────────────────────────────────────┘
                       │ [Valid]
                       ▼
┌────────────────────────────────────────────────────────────┐
│           2. GitWorktreeManager.commit_version()            │
│  - Check workspace exists                                   │
│  - Detect changes in workspace                              │
│  - Calculate next version number                            │
└──────────────────────┬─────────────────────────────────────┘
                       │ [Has Changes]
                       ▼
┌────────────────────────────────────────────────────────────┐
│                  3. Git Operations                          │
│  a) Commit workspace changes                                │
│     cd workspace && git add -A && git commit                │
│  b) Create version branch                                   │
│     git checkout -b gui/v1.0.5                              │
│  c) Create version tag                                      │
│     git tag gui-v1.0.5                                      │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│             4. ChangelogManager.update_component()          │
│  - Get diff: git diff gui/v1.0.4 gui/v1.0.5                │
│  - Identify changed files                                   │
│  - Generate markdown entry                                  │
│  - Prepend to gui/CHANGELOG.md                             │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│              5. Update Version Registry                     │
│  {                                                          │
│    "gui": {                                                 │
│      "available_versions": {                                │
│        "v1.0.5": {                                          │
│          "description": "...",                              │
│          "creation_date": "2025-12-19T...",                 │
│          "git_tag": "gui-v1.0.5"                            │
│        }                                                    │
│      }                                                      │
│    }                                                        │
│  }                                                          │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│                 6. Cleanup Workspace                        │
│  - Remove worktree: git worktree remove                     │
│  - Delete workspace branch: git branch -D gui/workspace     │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│                    Success Output                           │
│  ✓ Version v1.0.5 created successfully                     │
│  💡 To set as current: make git_promote_version ...        │
└────────────────────────────────────────────────────────────┘
```

### Data Transformations

**Input:**
- Component path: `gui`
- Version type: `patch`
- Description: `"Fixed button alignment"`

**Processing:**
- Current version: `v1.0.4` (from registry)
- Next version: `v1.0.5` (auto-increment)
- Git diff: `gui/v1.0.4..workspace`
- Changed files: `["simple_gui.py"]`

**Output:**
- Git branch: `gui/v1.0.5`
- Git tag: `gui-v1.0.5`
- CHANGELOG entry appended
- Registry entry created
- Workspace removed

---

## Release Creation Flow

### Auto Mode Workflow

```
┌────────────────────────────────────────────────────────────┐
│         cbflow flow release create --type patch            │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│          1. GitReleaseManager.create_release()             │
│  - Calculate next release version                          │
│  - Set mode: "auto"                                         │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│              2. Discover Components                         │
│  - Scan Git branches: */current                            │
│  - Found: gui/current, config-flow/current, ...            │
│  - Total: 29 components                                     │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│            3. Collect Current Versions                      │
│  {                                                          │
│    "gui": "v1.0.5",           # gui/current → gui/v1.0.5   │
│    "config/flow": "v1.0.0",   # config-flow/current → ...  │
│    ...                                                      │
│  }                                                          │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│               4. Create Release Tag                         │
│  git tag -a release/v1.0.1 -m "Release v1.0.1..."         │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│         5. Update RELEASE_CHANGELOG.md                     │
│  - Compare with previous release                            │
│  - Identify changed components                              │
│  - Generate markdown entry                                  │
│  - Prepend to RELEASE_CHANGELOG.md                         │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│            6. Update Version Registry                       │
│  {                                                          │
│    "releases": {                                            │
│      "v1.0.1": {                                            │
│        "description": "...",                                │
│        "creation_date": "2025-12-19T...",                   │
│        "components": {...},                                 │
│        "mode": "auto"                                       │
│      }                                                      │
│    }                                                        │
│  }                                                          │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│                   Success Output                            │
│  ✓ Release v1.0.1 created successfully                     │
│  📦 Components: 29                                          │
└────────────────────────────────────────────────────────────┘
```

### Config Mode Workflow

```
┌────────────────────────────────────────────────────────────┐
│  cbflow flow release create --type major --config release.json │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│              1. Load Configuration File                     │
│  {                                                          │
│    "version": "v2.0.0",                                     │
│    "description": "Production release",                     │
│    "components": {                                          │
│      "gui": "v1.0.4",                                       │
│      "config/flow": "v1.0.0"                                │
│    }                                                        │
│  }                                                          │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│             2. Validate Configuration                       │
│  For each component version:                                │
│    - Check component exists                                 │
│    - Check version branch exists                            │
│    - Check version tag exists                               │
└──────────────────────┬─────────────────────────────────────┘
                       │ [All Valid]
                       ▼
┌────────────────────────────────────────────────────────────┐
│              3. Create Release Tag                          │
│  git tag -a release/v2.0.0 -m "Release v2.0.0..."         │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│         4. Update RELEASE_CHANGELOG.md                     │
│  - Include config mode indicator                            │
│  - Show specific versions used                              │
│  - Highlight rollbacks if any                               │
└──────────────────────┬─────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────┐
│           5. Update Version Registry                        │
│  {                                                          │
│    "releases": {                                            │
│      "v2.0.0": {                                            │
│        "mode": "config",                                    │
│        "components": {"gui": "v1.0.4", ...}                 │
│      }                                                      │
│    }                                                        │
│  }                                                          │
└────────────────────────────────────────────────────────────┘
```

---

## CHANGELOG Generation Flow

### Component CHANGELOG

```
Version Committed
       │
       ▼
┌─────────────────────────────────────┐
│  ChangelogManager.update_component  │
└────────┬────────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│    Get Version Diff                │
│  git diff gui/v1.0.4 gui/v1.0.5   │
└────────┬───────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│   Parse Diff Output                │
│  - Added files                     │
│  - Modified files                  │
│  - Deleted files                   │
│  - Diff statistics                 │
└────────┬───────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│   Generate Markdown Entry          │
│  ## [v1.0.5] - 2025-12-19         │
│  ### Description                   │
│  Fixed button alignment            │
│  ### Changes from v1.0.4           │
│  **Modified:**                     │
│  - simple_gui.py                   │
└────────┬───────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  Prepend to CHANGELOG.md           │
│  - Read existing CHANGELOG         │
│  - Insert new entry after header   │
│  - Update timestamp                │
│  - Write back to file              │
└────────┬───────────────────────────┘
         │
         ▼
    CHANGELOG Updated
```

### Release CHANGELOG

```
Release Created
       │
       ▼
┌─────────────────────────────────────┐
│  ChangelogManager.update_release    │
└────────┬────────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  Get Previous Release               │
│  - Query version registry           │
│  - Find: v1.0.0 (previous)          │
└────────┬───────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  Compare Component Versions         │
│  v1.0.0 → v1.0.1:                  │
│    gui: v1.0.4 → v1.0.5 (updated)  │
│    config/flow: v1.0.0 (unchanged) │
└────────┬───────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  Generate Markdown Entry            │
│  ## [v1.0.1] - 2025-12-19          │
│  ### Component Versions             │
│  | Component | Version |            │
│  | gui | v1.0.5 |                  │
│  ### Changed Components             │
│  **Updated:**                       │
│  - gui: v1.0.4 → v1.0.5            │
└────────┬───────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  Prepend to RELEASE_CHANGELOG.md   │
└─────────────────────────────────────┘
```

---

## Registry Update Flow

### Version Registry Structure

```json
{
  "gui": {
    "available_versions": {
      "v1.0.5": { /* version data */ }
    },
    "current_version": "v1.0.5",
    "creation_date": "2025-12-19T..."
  },
  "releases": {
    "v1.0.1": { /* release data */ }
  }
}
```

### Update Process

```
Operation Triggered
       │
       ▼
┌─────────────────────────────────────┐
│  1. Load Registry (JSON)            │
│  Read: flow_version_registry.json   │
└────────┬────────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  2. Modify In-Memory Data           │
│  registry["gui"]["available_..."]  │
│      ["v1.0.5"] = {...}            │
└────────┬───────────────────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  3. Validate Schema                 │
│  - Check required fields            │
│  - Validate formats                 │
└────────┬───────────────────────────┘
         │ [Valid]
         ▼
┌────────────────────────────────────┐
│  4. Write Registry (Atomic)         │
│  Write: flow_version_registry.json │
│  (Atomic write with temp file)      │
└────────────────────────────────────┘
```

---

**See also:**
- [System Design](system-design.md) - Overall architecture
- [Git Strategy](git-strategy.md) - Git implementation
- [Component Design](component-design.md) - Component details
