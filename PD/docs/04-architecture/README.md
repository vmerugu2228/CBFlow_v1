# Architecture

Technical architecture of the CBflow v2.0.0 PD automation framework.

## Contents

### [System Design](system-design.md)

Core architecture covering:
- flow_proc engine and flow_exec_all execution model
- Configuration override hierarchy (flow_config through override_setup.<stage>)
- Config loading from `$CONFIG_ROOT/flow/$FLOW_CONFIG_VERSION/`
- Tool mapping: 11 flows across Synopsys, Cadence, and Mentor tools
- Directory layout: reports in `work/<flow>/<node>/reports/`, outputs in `outputs/`
- Release system: path structure, MANIFEST.json, RELEASE_COMPLETE, input handshaking
- Four launch modes: LSF+xterm, LSF batch, xterm local, local
- SYNTH_PNR stage pipeline: inputs through release_data
- Per-corner STA and ICV PV parallel pipeline
- Standard command file pattern

---

**See also:**
- [Developer Guide](../05-developer/README.md) -- Extending the framework
- [Examples](../06-examples/README.md) -- Workflow examples
