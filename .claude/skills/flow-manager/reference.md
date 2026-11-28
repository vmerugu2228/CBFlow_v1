# flow-manager reference

## Release model
```
global/releases/<vX.Y.Z>/
    MANIFEST.json          components: name -> {path (relative to CBFLOW_ROOT), version, link, hash}
    release_versions.tcl   CBFLOW_RELEASE_VERSION + <COMPONENT>_VERSION per component
    CHANGELOG.md
    components/<name>      symlinks to the component version dirs
global/releases/current -> <vX.Y.Z>   (cbflow flow release set-current)
```
**Components** (`cbflow flow release create` scans all trees):
| Component | Source |
|---|---|
| `cmds.<FLOW>.<vendor>.<tool>` | `<DISC>/cmds/<FLOW>/<vendor>/<tool>/<version>` (flows are unique, so no prefix) |
| `config.flow` / `config.tech.*` / `config.project.*` / `config.exit` / `config.setup.*` | the PD tree |
| `DFT.` / `DV.` / `RTL.` / `global.` prefixes | the same component name in another tree |
| `utils.*` | `global/utils/*` (the shared utilities runs use); the PD copies are `PD.utils.*` |

**Hash:** sha256 over the files of the version dir (relative path + content),
16 hex characters. Releases made before 2026-11-28 have no hash, so drift falls
back to git history.

**Locks:** `--lock` writes `.locked` and makes the version dirs read-only. It's
irreversible. Off by default, because the framework develops in place in its
version dirs.

## How a run picks its versions
1. `project(cbflow_release)` (project config) names the release.
2. Workspace create reads its `release_versions.tcl`:
   - config / utility versions become the run environment: `FLOW_CONFIG_VERSION`,
     `UTILITIES_VERSION`, `GENERATION_VERSION`, `TECH_CONFIG_VERSION`, … in
     `.run.cbflow.tcl`;
   - the command pin of the run's flow and tool
     (`CMDS_<FLOW>_<VENDOR>_<TOOL>_VERSION`) is appended to the run's
     `setup/user_config.tcl` as `<arr>(tool,version)`, unless the user config sets
     `tool,version` itself.
3. **How the command version is chosen:**
   - The engine's handler path is `<DISC>/cmds/<FLOW>/<vendor>/<tool>/<tool,version>/`.
   - Handlers take `$::env(<TOOL>_VERSION)` when set, else `<arr>(tool,version)`.
   - The node overlay's own `tool,version "v1.0.0"` is the default when no pin
     applies.

## Patch + retag recipe
| Step | Command | Gate |
|---|---|---|
| branch | `flowm.py patch --component <c> --to <v'> --apply` | user's yes |
| edit | cmd-manager / config-manager on `<path>/<v'>/` | lint, tests |
| test | `bin/cbflow test --e2e --flows <F>`; a sandbox run with `<arr>(tool,version) "<v'>"` | PASS |
| release | `cbflow flow release create --version <vR> --desc "…"` | user's yes |
| retag | `flowm.py pin --project <p> --release <vR> --reason "…" --apply` | config-manager owner gate |
| verify | a new run's `setup/user_config.tcl` ends with the pin line; the handler log shows `<v'>` | — |

Rollback is a pin back to the previous release (`flowm.py pin`). Released
versions are never edited in place.

## State (2026-11-28)
- v1.0.0 (2026-05-13): 39 components, PD only, no hashes. Every project pins it.
- 113 versioned components are on disk now (77 not in any release); v1.0.0 has
  drifted (3 components gone, 295 framework commits since).
- Recommendation: cut a release that captures the current tree, then pin the
  projects. Do it on the user's go-ahead (`release create --type minor`).

## Verified (2026-11-28)
- `release create --version v1.1.0` (test release, since removed): 113
  components, no lock, no git; the branched `cmds.STA.opensource.opensta`
  v1.0.1 was captured.
- Drift: 0 changes on the fresh release; a one-line edit in v1.0.1 was flagged
  EDITED by hash.
- The pin logic was unit-tested:
  - the release pin is appended to the run's user config;
  - an explicit `tool,version` is kept;
  - a release without a pin for the flow appends nothing.

  Pinning the live opensky config to the test release was not exercised (blocked
  as a live project change).
