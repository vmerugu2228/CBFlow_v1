# Examples

Practical workflow examples for CBflow v2.0.0.

All examples use the RACE (Run Automation & Control Engine) dispatcher. RACE builds the execution DAG from node_config.tcl at runtime and tracks status in a SQLite database. There is no Makefile, no `.make/` directory, and no `make` command.

## Contents

### [Basic Workflows](basic-workflows.md)
10 core examples:
1. SYNTH_PNR full run with FC
2. PNR with Cadence Innovus (tool override)
3. Per-corner STA with PrimeTime (dynamic subnodes)
4. PV with ICV (parallel DRC/LVS/ERC subnodes)
5. Release and handshake between flows
6. Checklist: add-check, run, sign-off
7. Email on completion
8. AutoPPT generation
9. Bypass / Force / Forcevalidate
10. Custom nodes and branches

### [Release Workflows](release-workflows.md)
- Phase-based release (P0 -> P1 -> P2 -> P3)
- Cross-flow handshaking (SYNTH -> PNR -> STA -> PV)
- Milestone sign-off (FP_EXIT -> PLACE_EXIT -> CTS_EXIT -> PRO_EXIT -> BTO -> MTO)
- Release validation and mandatory file checks

### [Advanced Scenarios](advanced-scenarios.md)
- Hierarchical FCFP design planning
- Multi-corner EMIR analysis
- ECO with LEC verification loop
- Custom flow_proc hooks and overrides
- Multi-project shared release infrastructure
- File change detection and automatic retrace
- Parallel subnode execution tuning

---

**Documentation Version**: 2.0.0
