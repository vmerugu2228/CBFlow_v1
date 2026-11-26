# Architecture

Technical architecture of CBflow v2.0.0 — one engine, config cascade, CLI and
release model shared by four disciplines (PD, DFT, DV, RTL).

## Contents

### [System Design](system-design.md)
- Repository layout: umbrella root, `global/`, `PD/` `DFT/` `DV/` `RTL/`; flow catalogue (`flow_registry.tcl`)
- Launcher composition: `global/bin/cbflow`, `cbflow-flow`, `cbflow-pd/dft/dv/rtl`, `discipline_commands.tcl`
- Config cascade (project → discipline overlays → tech → flow → node + tool overlay → MMMC → user → overrides) and the flow_proc hook cascade
- RACE engine (`global/utils/commands/race_engine.py`): DAG, dynamic subnodes, handler lookup, per-job env, SQLite status DB
- Handlers (`handler_common.tcl`, `launch_utils.tcl`), launch modes and the silent-test-mode gates
- Open-source tool container (`cbflow-oss`, `oss_launch_config.tcl`)
- Command-file bootstrap, flow_proc hooks, node helpers (`cbflow_chain_node`, `cbflow_source_node`)
- Release system (`release_utils.tcl`: exit tag, source-stage exits, per-discipline `check_exit_order`) and handshakes
- Exit milestones, dashboards (run daemons per discipline, SmartGrid incl. the chain page), versioning

### [Data Flow](data-flow.md)
A run end to end: workspace create → RACE execution → input handshakes → release → publish → SmartGrid, and the cross-discipline spec-to-GDS chain.

### [Component Design](component-design.md)
Module map: launchers, Python commands, Tcl runtime, generation, handlers, dashboards, open-source helpers, AI.

### [Versioning Strategy](git-strategy.md)
Directory-based versions, `current` symlinks, and how runs select versions through `*_VERSION` variables.

---

**See also:**
- [Developer Guide](../05-developer/README.md) — extending the framework
- [Examples](../06-examples/README.md) — workflow examples
