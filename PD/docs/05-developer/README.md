# Developer Guide

Extending and contributing to CBflow v2.0.0 (PD, DFT, DV, RTL on one engine).

## Contents

### [Extending CBflow](extending.md)
- Hooking a flow_proc; overriding tool selection
- Adding a discipline-owned subcommand (`discipline_commands.tcl` + `cbflow-<disc>` array + dispatch case + Python handler)
- Adding a new flow (registry, discipline flow_config, dir_config, node config + tool overlay, tool shell, handlers, handshakes, project enablement)
- Adding an open-source tool overlay (`<FLOW>_<tool>_config.tcl`, `cmds/<FLOW>/opensource/<tool>/v1.0.0/` handlers + command files, container binaries)
- Adding a handshake (`flow_input_handshake`, PD `release_config.tcl` §6)
- Adding an exit milestone (`global/config/exit/v1.0.0/`, `milestone_info(discipline)`, tool checklist map, `project(phase_exits[,<DISC>])`)

### [Contributing](contributing.md)
Setup, branches, where code goes, versioned directories, conventions, testing, docs.

### [Test Suite Developer Guide](test-suite.md)
`cbflow test`: static categories 1-19, e2e checks 1-19, dispatch / CLI smoke, integration, hardcode audit, adding checks, CI.

### [Release 2026-07-10 Features](release-2026-07-10-features.md)
Historical feature notes for the 2026-07-10 bundle (pre `cbflow_global` layout; paths may be outdated).

## Quick Reference

### Command file bootstrap
```tcl
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "<FLOW>"
set STAGE_NAME "<stage>"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc <step> { … }       ;# executed in definition order
flow_exec_all                ;# oss_exec_all in the RTL / DFT / DV open-source drivers
exit
```

### Test suite
```bash
cbflow test --static                   # static categories (18 is opt-in)
cbflow test --e2e --flow SYNTH_PNR     # one flow end to end (test mode)
cbflow test --static --category 19     # open-source DFT / RTL / DV wiring
cbflow test --ci                       # junit + non-zero exit on fail
```

Architecture: [System Design](../04-architecture/system-design.md).
