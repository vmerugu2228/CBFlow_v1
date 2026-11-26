# Your First Version

Step-by-step guide to CBflow's directory-based versioning system.

## Overview

CBflow uses **directory-based versioning** -- no Git worktrees. Each config, command set, or utility lives in a versioned directory (e.g., `v1.0.0/`). A `current` symlink points to the active version.

```
config/flow/
|-- v1.0.0/        <-- Original version
|-- v1.0.1/        <-- Your modified version
|-- v1.0.2/        <-- Another iteration
+-- current -> v1.0.1   <-- Active version (symlink)
```

## Step 1: Copy a Version

```bash
cbflow flow version copy --dir config/flow --from v1.0.0 --to v1.0.1
```

This creates `config/flow/v1.0.1/` as a full copy of `v1.0.0/`.

## Step 2: Edit Files

```bash
vi config/flow/v1.0.1/flow_config.tcl
vi config/flow/v1.0.1/node_configs/SYNTH_PNR_config.tcl
```

Note: In v2.0.0, the RACE engine reads the node configs (`<FLOW>_config.tcl` + `<FLOW>_<tool>_config.tcl`) directly at runtime to build the DAG. There is no Makefile to regenerate after editing configs. Simply edit the node_config and RACE will pick up the changes on the next run.

## Step 3: Set as Current

```bash
cbflow flow version set-current --dir config/flow --version v1.0.1
```

This updates the `current` symlink to point to `v1.0.1/`.

## Step 4: Verify

```bash
cbflow flow version list --dir config/flow
# Output:
#   v1.0.0
#   v1.0.1  <-- current
#   v1.0.2

cbflow flow version diff --dir config/flow --v1 v1.0.0 --v2 v1.0.1
```

## Step 5: Verify DAG (Optional)

After editing node configs, you can verify the RACE DAG is valid:

```bash
cbflow run gen-makefile      # from inside a run directory
```

This builds the run's dependency graph from the node configs and validates it without executing anything
(the subcommand name is historical — no Makefile is written).

## What Can Be Versioned

Paths are relative to a discipline root (`PD/`, `DFT/`, `DV/`, `RTL/`) or to `global/`:

| Directory | Contains |
|-----------|----------|
| `<disc>/config/flow/` | Discipline flow config, node configs, release / LSF / dir configs (PD) |
| `<disc>/config/project/<proj>/` | Discipline project overlay (`<proj>_pd_config.tcl`, …) |
| `global/config/flow/` | `flow_registry.tcl` (flow catalog, runtime + dashboard defaults) |
| `global/config/tech/<tech>/` | `tech_config.tcl`, metal stacks |
| `global/config/project/<proj>/` | Project identity, MMMC, schedule, team configs |
| `global/config/exit/` | Exit milestone + STA_SIGNOFF checklist configs, waiver config |
| `<disc>/cmds/<FLOW>/<vendor>/<tool>/` | Command files per flow/tool |
| `global/utils/utilities/` | Shared TCL utilities |

## Versioning Commands

```bash
cbflow flow version copy --dir <dir> --from <v1> --to <v2>
cbflow flow version set-current --dir <dir> --version <v>
cbflow flow version list --dir <dir>
cbflow flow version diff --dir <dir> --v1 <v1> --v2 <v2>
```

---

**Next**: [User Guide](../02-user-guide/README.md) for daily workflows.
