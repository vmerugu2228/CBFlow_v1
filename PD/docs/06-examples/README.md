# Examples

Practical workflow examples for CBflow v2.0.0.

All examples run on the RACE (Run Automation & Control Engine) dispatcher. RACE builds the execution DAG from the
node configs at runtime and tracks status in a SQLite database. There is no Makefile and no `make` command.
Commercial examples use project `bumblebee` (gf_22nm); open-source examples use project `opensky`
(skywater_130nm, phases P0-P3, blocks gcd / mac_array / ctrl_subsys / ai_subsys / opensky_chip, library tag OSS2).

## Contents

### [Basic Workflows](basic-workflows.md)
1. SYNTH_PNR full run with FC
2. PNR with Cadence Innovus (tool override)
3. Open-source PNR of gcd (OpenROAD)
4. Per-scenario STA (dynamic subnodes, per-node scenarios)
5. PV (parallel DRC / LVS / PERC / XOR)
6. Release and handshake between flows
7. Checklist: add-check, run, sign-off
8. Email on completion
9. AutoPPT
10. Bypass / Force / Forcevalidate
11. Custom nodes, set-dep and branches
12. Retrace

### [Release Workflows](release-workflows.md)
- Publishing self-released runs, intermediate exits, MTO = BTO clones
- Signoff of an exit (`run_signoff.sh`), commercial `run release`, `release-check`
- Exit order per discipline
- Block releases into a library tag
- Framework releases (`cbflow flow release …`, `cbflow bundle`)

### [Advanced Scenarios](advanced-scenarios.md)
- Hierarchical DL3 -> DL2 -> DL1 build with library tags
- Several exits from one PNR run
- Per-node overrides and flow_proc hooks
- Per-node MMMC scenarios, parallelism
- Spec-to-GDS chain
- Debugging a run's configuration
- Framework version rollback

---

**Documentation Version**: 2.0.0
