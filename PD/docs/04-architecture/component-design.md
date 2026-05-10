# Component Design

Detailed design of individual software components in CBFlow.

## Component Overview

```
┌──────────────────────────────────────────────────────────┐
│                    Makefile (CLI)                         │
│  - Parameter validation                                   │
│  - User interface                                         │
└───────────┬────────────────────────┬─────────────────────┘
            │                        │
            ▼                        ▼
┌───────────────────────┐  ┌───────────────────────┐
│ GitWorktreeManager    │  │  GitReleaseManager    │
│ - Workspace mgmt      │  │  - Release creation   │
│ - Version creation    │  │  - Config validation  │
└──────┬────────────────┘  └──────┬────────────────┘
       │                          │
       │    ┌─────────────────────┴─────────┐
       │    │                               │
       ▼    ▼                               ▼
┌──────────────────────┐         ┌──────────────────────┐
│  ChangelogManager    │         │  Version Registry    │
│  - CHANGELOG gen     │         │  - JSON storage      │
│  - Diff parsing      │         │  - Metadata          │
└──────────────────────┘         └──────────────────────┘
```

---

## GitWorktreeManager

### Responsibility

Manages Git worktrees for isolated development and component version creation.

### Class Structure

```python
class GitWorktreeManager:
    def __init__(self, base_dir: str = "."):
        self.base_dir = Path(base_dir)
        self.workarea_dir = self.base_dir / "workarea"
        self.worktrees_dir = self.workarea_dir / "worktrees"
        self.version_registry = self.base_dir / "utils/version/flow_version_registry.json"

    # Public API
    def create_workspace(component_path: str, force: bool = False) -> bool
    def commit_version(component_path: str, version: str = None, 
                      version_type: str = None, description: str = "") -> bool
    def promote_version(component_path: str, version: str) -> bool
    def cleanup_workspace(component_path: str) -> bool
    def cleanup_all_workspaces() -> int
    def list_workspaces() -> List[Dict]
    def get_current_version(component_path: str) -> str
    def list_versions(component_path: str) -> List[str]

    # Private helpers
    def _normalize_component_path(component_path: str) -> str
    def _get_next_version(component_path: str, version_type: str) -> str
    def _workspace_exists(component_path: str) -> bool
    def _version_exists(component_path: str, version: str) -> bool
```

### Key Methods

#### create_workspace

**Purpose:** Create isolated Git worktree for development.

**Algorithm:**
```python
def create_workspace(component_path, force=False):
    # 1. Validate component exists
    if not (base_dir / component_path).exists():
        raise ComponentNotFoundError()
    
    # 2. Check workspace doesn't exist (unless force)
    if _workspace_exists(component_path) and not force:
        raise WorkspaceExistsError()
    
    # 3. Get current version
    current_version = get_current_version(component_path)
    if not current_version:
        raise NoCurrentVersionError()
    
    # 4. Normalize path for Git branch
    normalized = _normalize_component_path(component_path)  # "config/flow" → "config-flow"
    
    # 5. Create worktree directory
    workspace_path = worktrees_dir / normalized / "workspace"
    workspace_path.parent.mkdir(parents=True, exist_ok=True)
    
    # 6. Create Git worktree
    branch_name = f"{normalized}/workspace"
    git worktree add workspace_path -b branch_name
    
    # 7. Copy current files to workspace
    git checkout -b branch_name current_version
    
    return True
```

#### commit_version

**Purpose:** Create new version from workspace changes.

**Algorithm:**
```python
def commit_version(component_path, version=None, version_type=None, description=""):
    # 1. Validate workspace exists
    if not _workspace_exists(component_path):
        raise NoWorkspaceError()
    
    # 2. Check for changes
    changes = git diff --name-only (in workspace)
    if not changes:
        raise NoChangesError()
    
    # 3. Determine version number
    if version:
        next_version = version
    elif version_type:
        next_version = _get_next_version(component_path, version_type)
    else:
        raise ValueError("Must specify version or version_type")
    
    # 4. Check version doesn't exist
    if _version_exists(component_path, next_version):
        raise VersionExistsError()
    
    # 5. Commit workspace changes
    cd workspace
    git add -A
    git commit -m f"Version {next_version}: {description}"
    
    # 6. Create version branch
    branch_name = f"{normalized}/{next_version}"
    git checkout -b branch_name
    
    # 7. Create version tag
    tag_name = f"{normalized}-{next_version}"
    git tag -a tag_name -m description
    
    # 8. Update CHANGELOG
    changelog_mgr.update_component_changelog(
        component_path, next_version, description
    )
    
    # 9. Update registry
    _update_registry(component_path, next_version, description)
    
    # 10. Cleanup workspace
    cleanup_workspace(component_path)
    
    return True
```

---

## GitReleaseManager

### Responsibility

Manages system-wide releases with component version bundling.

### Class Structure

```python
class GitReleaseManager:
    def __init__(self, base_dir: str = "."):
        self.base_dir = Path(base_dir)
        self.version_registry = self.base_dir / "utils/version/flow_version_registry.json"

    # Public API
    def create_release(version: str = None, version_type: str = None,
                      description: str = "", config_file: str = None) -> bool
    def generate_release_config(output_file: str, description: str = "") -> bool
    def load_release_config(config_file: str) -> Dict[str, str]
    def list_releases() -> List[Dict]
    def get_release_info(release_version: str) -> Dict
    def validate_release_config(config_file: str) -> bool

    # Private helpers
    def _discover_components() -> List[str]
    def _get_component_versions(components: List[str]) -> Dict[str, str]
    def _get_next_release_version(version_type: str) -> str
    def _validate_component_version(component: str, version: str) -> bool
```

### Key Methods

#### create_release (Auto Mode)

**Algorithm:**
```python
def create_release(version=None, version_type=None, description="", config_file=None):
    # Auto mode (no config)
    if not config_file:
        # 1. Discover all components
        components = _discover_components()  # Scan for */current branches
        
        # 2. Get current version of each
        component_versions = {}
        for component in components:
            current = get_current_version(component)
            component_versions[component] = current
        
        mode = "auto"
    
    # 3. Determine release version
    if version:
        release_version = version
    else:
        release_version = _get_next_release_version(version_type)
    
    # 4. Create release tag
    git tag -a f"release/{release_version}" -m description
    
    # 5. Update CHANGELOG
    changelog_mgr.update_release_changelog(
        release_version, description, component_versions, mode
    )
    
    # 6. Update registry
    _update_registry_release(release_version, component_versions, mode, description)
    
    return True
```

#### create_release (Config Mode)

**Algorithm:**
```python
def create_release(..., config_file="release.json"):
    # Config mode
    # 1. Load configuration
    config = load_release_config(config_file)
    component_versions = config["components"]
    
    # 2. Validate all versions exist
    for component, version in component_versions.items():
        if not _validate_component_version(component, version):
            raise InvalidVersionError(f"{component}: {version}")
    
    # 3. Create release (same as auto mode but mode="config")
    mode = "config"
    # ... rest same as auto mode
```

---

## ChangelogManager

### Responsibility

Generate and maintain automated CHANGELOG files.

### Class Structure

```python
class ChangelogManager:
    def __init__(self, base_dir: str = "."):
        self.base_dir = Path(base_dir)

    # Public API
    def update_component_changelog(component_path: str, version: str,
                                  description: str, prev_version: str = None) -> bool
    def update_release_changelog(release_version: str, description: str,
                                components: Dict[str, str], mode: str = "auto") -> bool

    # Private helpers
    def _get_version_diff(component_path: str, v1: str, v2: str) -> Dict
    def _generate_component_entry(component_path: str, version: str,
                                 description: str, diff_info: Dict) -> str
    def _generate_release_entry(release_version: str, description: str,
                               components: Dict, mode: str) -> str
    def _prepend_to_changelog(changelog_path: Path, entry: str) -> None
```

### Key Methods

#### update_component_changelog

**Algorithm:**
```python
def update_component_changelog(component_path, version, description, prev_version=None):
    # 1. Get previous version if not provided
    if not prev_version:
        versions = list_versions(component_path)
        prev_version = versions[-2] if len(versions) > 1 else None
    
    # 2. Get diff
    if prev_version:
        diff_info = _get_version_diff(component_path, prev_version, version)
    else:
        diff_info = {"added": ["all files"], "modified": [], "deleted": []}
    
    # 3. Generate markdown entry
    entry = f"""
## [{version}] - {datetime.now().strftime('%Y-%m-%d')}

### Description
{description}

### Changes from {prev_version or 'initial'}

**Added:**
{chr(10).join(f'- {f}' for f in diff_info['added'])}

**Modified:**
{chr(10).join(f'- {f}' for f in diff_info['modified'])}

**Deleted:**
{chr(10).join(f'- {f}' for f in diff_info['deleted'])}

**Diff Statistics:**
```
{diff_info['diff_stats']}
```

**Version Info:**
- Component: `{component_path}`
- Version: `{version}`
- Created: {datetime.now().isoformat()}
- Previous: `{prev_version}`

---
"""
    
    # 4. Prepend to CHANGELOG
    changelog_path = base_dir / component_path / "CHANGELOG.md"
    _prepend_to_changelog(changelog_path, entry)
    
    return True
```

---

## Version Registry

### Responsibility

Persistent storage of version and release metadata.

### Structure

```python
# Conceptual structure (stored as JSON)
class VersionRegistry:
    components: Dict[str, ComponentInfo]
    releases: Dict[str, ReleaseInfo]

class ComponentInfo:
    available_versions: Dict[str, VersionInfo]
    current_version: Optional[str]
    creation_date: str

class VersionInfo:
    description: str
    creation_date: str
    git_tag: str
    git_branch: str

class ReleaseInfo:
    description: str
    creation_date: str
    components: Dict[str, str]  # component -> version
    mode: str  # "auto" or "config"
```

### Operations

```python
# Load registry
def load_registry() -> Dict:
    with open(registry_path) as f:
        return json.load(f)

# Save registry (atomic)
def save_registry(registry: Dict):
    temp_path = registry_path.with_suffix('.tmp')
    with open(temp_path, 'w') as f:
        json.dump(registry, f, indent=2)
    temp_path.replace(registry_path)  # Atomic rename

# Add version
def add_version(component: str, version: str, info: VersionInfo):
    registry = load_registry()
    if component not in registry:
        registry[component] = {
            "available_versions": {},
            "current_version": None,
            "creation_date": datetime.now().isoformat()
        }
    registry[component]["available_versions"][version] = info.__dict__
    save_registry(registry)

# Add release
def add_release(version: str, info: ReleaseInfo):
    registry = load_registry()
    if "releases" not in registry:
        registry["releases"] = {}
    registry["releases"][version] = info.__dict__
    save_registry(registry)
```

---

## Integration Patterns

### Makefile → Python Integration

```makefile
git_commit_version:
	@python3 utils/version/v2.0.0/git_worktree_manager.py \
		commit_version \
		--component $(DIR) \
		--type $(TYPE) \
		--description "$(DESC)"
```

### Python → Git Integration

```python
def _run_git_command(cmd: List[str]) -> str:
    result = subprocess.run(
        ["git"] + cmd,
        capture_output=True,
        text=True,
        check=True
    )
    return result.stdout
```

### Component → CHANGELOG Integration

```python
# In GitWorktreeManager.commit_version():
changelog_mgr = ChangelogManager(self.base_dir)
changelog_mgr.update_component_changelog(
    component_path,
    next_version,
    description,
    prev_version=current_version
)
```

---

**See also:**
- [System Design](system-design.md) - Overall architecture
- [Git Strategy](git-strategy.md) - Git implementation
- [Data Flow](data-flow.md) - Data flow diagrams
