# Contributing Guide

How to change CBflow code, configs and docs. Paths are relative to `$CBFLOW_ROOT`.

## Setup

```bash
git clone <cbflow-repo> CBflow && cd CBflow
export CBFLOW_ROOT=$PWD            # the only variable you export
export PATH=$CBFLOW_ROOT/bin:$PATH
cbflow --version                   # shows the resolved path chain
cbflow flow types                  # flows per discipline
```

Prerequisites: Python 3, tclsh 8.6, git; docker for the open-source tools
(`cbflow-oss check`); commercial tools via `lsf(tool_shell,*)` / modules.

## Branches and commits

- Branch from the integration branch (`git checkout -b feature/<topic>`); never commit on `main`.
- One topic per commit; subject line says what changed and where
  (e.g. `library-manager check: --design + --netlist_tag`).
- Do not commit run data (workarea run dirs, logs, `test_releases/`, `.race_area/`).

## Where code goes

| Change | Location |
|---|---|
| Cross-discipline engine / CLI | `global/utils/commands/`, `global/utils/core/`, `global/bin/` |
| Tcl runtime used by handlers / command files | `global/utils/utilities/v1.0.0/` |
| Discipline-only Python | `<DISC>/utils/commands/` (+ launcher, see [Extending §3](extending.md#3-adding-a-discipline-owned-subcommand)) |
| Discipline Tcl helpers | `<DISC>/utils/utilities/v1.0.0/` |
| Flow / node / tool config | `<DISC>/config/flow/v1.0.0/` (data only) |
| Project, tech, exits, registry | `global/config/…` |
| Handlers + command files | `<DISC>/cmds/<FLOW>/<vendor>/<tool>/v1.0.0/` |

Config files are shared by every run of a project: get the owner's agreement
before editing project / tech / exit configs.

## Versioned directories

Released config / command / utility versions are not edited in place for
production changes: copy, edit, promote.

```bash
cbflow flow version copy --dir config/flow --from v1.0.0 --to v1.0.1
cbflow flow dev start --component config/flow --from v1.0.0   # writable v1.0.0-dev
cbflow flow dev diff --component config/flow
cbflow flow dev promote --component config/flow
```

Runs choose versions through `FLOW_CONFIG_VERSION`, `UTILITIES_VERSION`,
`TECH_CONFIG_VERSION`, `PROJECT_CONFIG_VERSION` and `<flow>(tool,version)`.
See [Versioning Strategy](../04-architecture/git-strategy.md).

## Code conventions

**Tcl**
- Command files use the standard bootstrap (`utils.tcl`, `config.tcl`,
  `setup.tcl`, `setup_dirs`) and `NODE_NAME [cbflow_node_name]` — never a
  hardcoded `place1`.
- Read config with `cbflow_require <arr> <key>` / `oss_get`; error on missing
  values, no silent defaults.
- No procs in config files; no `array set` blocks containing `#` comments
  (use per-key `set`).

**Python**
- Resolve paths through `core.paths` / `core.registry`; read resolved config
  through the resolver, not regex over config files.
- Raise clear errors naming the missing key and the file that should set it.

**Shell launchers**
- `set -euo pipefail`; source `_cbflow_paths.sh`; unknown commands fall
  through to `global/bin/cbflow`.

## Testing

```bash
cbflow test --static                     # always before committing
cbflow test --static --category 19       # open-source DFT / RTL / DV wiring
cbflow test --e2e --flow <FLOW>          # the PD flow you touched (test mode)
cbflow test --cli-smoke                  # CLI --help surface
cbflow test --hardcode                   # opt-in no-hardcode audit
```

A change to an open-source flow is also run for real on the opensky project
(see the [Open-Source Flow Guide](../02-user-guide/opensource-flow-guide.md)).

## Documentation

- User guides: `PD/docs/02-user-guide/`, discipline guides in
  `RTL/docs/`, `DV/docs/`, `DFT/docs/`; architecture `PD/docs/04-architecture/`;
  developer `PD/docs/05-developer/`. Index: `PD/docs/README.md`.
- Update `CLAUDE.md` (framework summary) and `RELEASE_NOTES.md` when behaviour changes.
- Keep commands runnable as written and paths relative to `$CBFLOW_ROOT`.

---

**See also:** [Extending CBflow](extending.md) · [Test Suite](test-suite.md)
