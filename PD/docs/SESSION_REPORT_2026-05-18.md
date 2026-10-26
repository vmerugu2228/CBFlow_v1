# CBflow Session Report — 2026-05-18/19

## Summary

85 files changed, 705 insertions, 675 deletions across the entire CBflow framework. This session addressed critical bugs, architectural improvements, and new features for customer deployment readiness.

---

## 1. Bugs Fixed

### Bug 1: SYNTH flow created in SYNTH_PNR run
**Files:** `PD/config/flow/v1.0.0/flow_config.tcl`

- **Root cause:** `flow(type)` defaulted to `"SYNTH"` (line 40). Method 2 silently picked up this default. The argv regex excluded `SYNTH_PNR`. The fallback loaded all configs except `SYNTH_PNR_config.tcl`.
- **Fix:** Removed silent fallback entirely. Flow type MUST be explicitly detected or the system exits with error listing all available flow types. Validation now reads from `flow(types)` variable directly (no hardcoded regex).

### Bug 2: Custom node handler file not found
**Files:** `PD/utils/commands/race_engine.py`

- **Root cause:** `_build_command()` used `stage.rstrip('0123456789')` as fallback, which for `synthesis2_xyz` produced `synthesis2_xy` instead of `synthesis`.
- **Fix:** Added `_custom_node_types` dict populated from runtime config. Handler lookup now checks custom node type mapping first.

### Bug 3: Custom nodes rejected by run commands
**Files:** `PD/utils/commands/run_cmd.py`

- **Root cause:** `cmd_stage`, `cmd_retrace`, `cmd_bypass`, `cmd_forcevalidate`, `cmd_force` validated against base stages only.
- **Fix:** Added `get_all_stages()` that merges base stages + custom nodes from runtime config. All 5 commands now accept custom node names.

### Bug 4: Branch from custom node creates single node
**Files:** `PD/utils/commands/node_manager.py`

- **Root cause:** `create_branch()` used `re.sub(r'\d+$', '', from_stage)` to find base type, which for `synthesis2_xyz` returned `synthesis2_xyz` (no trailing digits). Failed to match base stages.
- **Fix:** Looks up stored `type` field from `self.custom_nodes` dict first.

### Bug 5: GUI branch label shows tag instead of name
**Files:** `PD/utils/dashboard/templates/dashboard.html`

- **Root cause:** Two JS lines had `branch_tag || branch_name` priority (lines 1169, 1213).
- **Fix:** Flipped to `branch_name || branch_tag`.

### Bug 6: GUI branch override creates per-type files
**Files:** `PD/utils/dashboard/race_dashboard.py`

- **Root cause:** `_action_save_node_full_config` wrote `override_config.<stage_base>.tcl` for branch scope, bleeding across all nodes of that type.
- **Fix:** Branch scope now writes single `override_config.<branch_name>.tcl`. Per-node scope writes `override_config.<node>.tcl`.

---

## 2. Architecture: Config Sourcing Consolidation

### Before
Each `*_fc.tcl` cmd file sourced 6-10 configs individually:
```
.run.cbflow.tcl → utils.tcl → flow_config → node_config → user_config → tech_config
→ mmmc_config → fc_config → user_config (AGAIN) → override_config
```

### After
`generate_setup.tcl` produces a single `config.tcl` per node with the full 14-level cascade:
```
project_init → project → team → tech → flow → node → mmmc → tool_config → user
→ override (global → flow → type → branch → node)
```

Each cmd file now sources only:
```tcl
source .run.cbflow.tcl    # env vars
source utils.tcl           # utilities
source config.tcl          # ALL configs consolidated
```

**Files changed:** 54 `*_fc.tcl` files across 6 flows (SYNTH_PNR, PNR, SYNTH, FP, FCFP, ECO) — removed redundant user_config, mmmc_config, fc_config, override_config sourcing.

### Dynamic paths via CBFLOW_NODE_NAME
**Files:** `PD/utils/commands/race_engine.py`

RACE engine now exports `CBFLOW_NODE_NAME` and `CBFLOW_SUBNODE` env vars per job. All 54 cmd files use `$::env(CBFLOW_NODE_NAME)` for config.tcl and setup.tcl paths instead of hardcoded `<stage>1`. This enables custom nodes and branch nodes to use their own generated configs.

---

## 3. New Feature: Branch-Level Override Cascade

### generate_setup.tcl
Added branch-level override to config cascade between stage-type and per-node:
```
override_config.<stage_base>.tcl    # e.g., override_config.cts.tcl
override_config.<branch_name>.tcl   # e.g., override_config.timing_fix.tcl  ← NEW
override_config.<node_name>.tcl     # e.g., override_config.cts2.tcl
```

The system reads the node's `branch_key` from `runtime_flow_config.tcl`, resolves the branch name, and sources `override_config.<branch_name>.tcl` if it exists.

### Dashboard
GUI config editor (Save to → Branch) now writes a single `override_config.<branch_name>.tcl` file that applies to all nodes in the branch.

---

## 4. New Feature: Dynamic RC Corner Extraction (STA)

### Before
`extraction1` had static subnodes: `setup → run → validate → finish` (serial, single extraction)

### After
`extraction1` is now dynamic: `setup → [rc_max, rc_typ, rc_min] (parallel) → validate → finish`

**Files changed:**
- `PD/config/flow/v1.0.0/node_configs/STA_config.tcl` — `subnodes,extraction1 {dynamic}`
- `PD/config/flow/v1.0.0/mmmc_config.tcl` — Added `rc_corner_list`, added `tluplus_file`/`qrc_techfile`/`nxtgrd_file` to each RC corner definition
- `PD/utils/commands/race_engine.py` — `_resolve_dynamic_subnodes()` now handles extraction stages via `_resolve_rc_corners()` (reads from `rc_corner_list` in mmmc_config or user override)
- `PD/cmds/STA/synopsys/pt/v1.0.0/extraction_subnode_handler.tcl` — Handles RC corner subnodes, resolves parasitic file from `rc_corners` array, creates per-corner work dirs, generates mock SPEF
- `PD/cmds/STA/synopsys/pt/v1.0.0/timing_subnode_handler.tcl` — Setup subnode reads SPEF manifest from extraction, copies to timing work dir

### SPEF manifest handoff
Extraction `validate` generates `spef_manifest.tcl` mapping RC corners to SPEF file paths. Timing `setup` sources it — makes `spef_map(rc_max)` etc. available to all timing scenarios.

Adding a new RC corner to `rc_corner_list` in mmmc_config.tcl automatically creates a new parallel extraction subnode in every new STA run.

---

## 5. New Feature: Flow-to-Flow Data Handoff System

### Output Manifest Generation
**Files:** `PD/cmds/SYNTH_PNR/.../export_data_subnode_handler.tcl`, `PD/cmds/PNR/.../export_data_subnode_handler.tcl`

The `validate` subnode of `export_data` now generates `output_manifest.tcl`:
```tcl
set manifest(netlist,logic)  ".../outputs/cpu_core.v"
set manifest(netlist,pt)     ".../outputs/cpu_core.pt.v"
set manifest(netlist,fm)     ".../outputs/cpu_core.fm.v"
set manifest(netlist,lvs)    ".../outputs/cpu_core.lvs.v"
set manifest(netlist,vc_lp)  ".../outputs/cpu_core.vc_lp.v"
set manifest(gds)            ".../outputs/cpu_core.gds"
set manifest(def)            ".../outputs/cpu_core.def"
set manifest(spef)           ".../outputs/cpu_core.spef"
set manifest(sdc)            ".../outputs/cpu_core.sdc"
set manifest(upf)            ".../outputs/cpu_core.upf"
```

### Input Auto-Resolution
**New file:** `PD/utils/utilities/v1.0.0/resolve_inputs.tcl`

Three input modes (backward compatible):
1. **`from_run`**: `set sta(input,from_run) "/path/to/SYNTH_PNR_run"` → reads manifest, auto-sets all input variables
2. **`release_tag`**: `set sta(input,release_tag) "v1.0.2"` → resolves from release dir via `flow_input_handshake`
3. **Explicit paths**: `set sta(input,netlist) "/path.v"` → direct (existing behavior, always wins over auto-resolve)

**Handshake map** maps downstream flow inputs to manifest keys:
```
STA,netlist     → manifest(netlist,pt)     [picks .pt.v for PrimeTime]
LEC,netlist_revised → manifest(netlist,fm) [picks .fm.v for Formality]
PV,netlist      → manifest(netlist,lvs)    [picks .lvs.v for LVS]
CLP,netlist     → manifest(netlist,vc_lp)  [picks .vc_lp.v for VC_LP]
```

Each tool gets the correct netlist variant automatically.

**Resolved paths persisted** to `setup/resolved_inputs.tcl` so all subnodes across process boundaries can source them.

**8 downstream flow input handlers updated:** STA, LEC, CLP (vc_lp + conformal_lp), PV (icv + calibre), EMIR (redhawk + voltus)

---

## 6. Complete Data Flow: SYNTH_PNR → PV

```
SYNTH_PNR:
  rtl1/sdc1/upf1 (parallel inputs)
    → init_design1 (open_lib, read_verilog, read_sdc, read_upf)
      → synthesis1 (compile_fusion, multi-corner)
        → place1 (place_opt)
          → cts1 (clock_opt)
            → cts_opt1 (clock_opt -fix_hold)
              → route1 (route_auto)
                → pro1 (route_opt)
                  → signoff1 (final timing/DRC)
                    → export_data1 → output_manifest.tcl
                      → release_data1 → release/{category}/
                           │
    ┌────────────────────────┤ (flow-to-flow via manifest)
    │                        │
    ├─→ STA:  netlist.pt + sdc + spef + def
    │    → extraction1 [rc_max|rc_typ|rc_min] (parallel)
    │         → spef_manifest.tcl
    │    → timing1 [per-MMMC-scenario] (parallel)
    │    → reporting1 → release_data1
    │
    ├─→ LEC:  netlist.fm (revised) + RTL (golden)
    │    → compare1 → release_data1
    │
    ├─→ CLP:  netlist.vc_lp + upf
    │    → verification1 → release_data1
    │
    ├─→ EMIR: def + netlist + spef + gds
    │    → power_analysis1 → ir_drop1 → thermal1
    │
    └─→ PV:   gds + netlist.lvs + def
         → fill1 → drc1/lvs1/erc1/perc1 (parallel)
           → merge_data1 → release_data1
```

---

## 7. Documentation Updated (8 files)

| File | Changes |
|------|---------|
| `system-design.md` | Config cascade rewritten (8→14 levels), generated config.tcl section, per-job env vars |
| `KICKSTART.md` | Override hierarchy updated with new levels |
| `configuration-reference.md` | Split static/generated config, full 14-level cascade table |
| `cbflow-flow-user-guide.md` | Branch creates full pipeline, custom nodes work with all commands, new env vars |
| `cbflow-gui-user-guide.md` | Branch label shows name, branch-scoped override docs |
| `troubleshooting.md` | Added "Flow Type Not Detected" error section |
| `extending.md` | Simplified cmd file pattern, custom node handler resolution |
| `CBflow_v2.0.0_Feature_Document.md` | Config hierarchy table rewritten (8→14 levels) |

---

## 8. Test Results

### All 6 flows tested end-to-end:

| Test | SYNTH | PNR | STA | LEC | CLP | SYNTH_PNR |
|------|-------|-----|-----|-----|-----|-----------|
| Base run | PASS | PASS | PASS | PASS | PASS | PASS |
| Add custom node | PASS | PASS | PASS | PASS | PASS | PASS |
| Branch from base | PASS | PASS | PASS | PASS | PASS | PASS |
| Branch from custom | PASS | PASS | PASS | PASS | PASS | PASS |
| Run with branches | PASS | PASS | PASS | PASS | PASS | PASS |
| Config sourcing cleanup | PASS | PASS | PASS | PASS | PASS | PASS |

### STA dynamic extraction:
- 3 RC corners (rc_max, rc_typ, rc_min) run in parallel ✓
- SPEF manifest generated and consumed by timing ✓
- Adding new RC corner to mmmc_config auto-creates subnode ✓

### Flow-to-flow handoff:
- SYNTH_PNR → STA with `from_run` auto-resolved 4 inputs (netlist.pt, sdc, spef, def) ✓
- Resolved paths persisted across subnode boundaries ✓
- Backward compatible with explicit paths ✓

---

## 9. Files Changed (85 total)

| Category | Count | Files |
|----------|-------|-------|
| Bug fixes (engine/config) | 5 | flow_config.tcl, race_engine.py, run_cmd.py, node_manager.py, dashboard.html |
| Config sourcing cleanup (*_fc.tcl) | 54 | All cmd files across 6 flows |
| New features (manifests/resolve) | 5 | resolve_inputs.tcl (NEW), export_data handlers (2), extraction/timing handlers (2) |
| GUI fixes | 2 | race_dashboard.py, dashboard.html |
| Config cascade (generate_setup) | 1 | generate_setup.tcl |
| Config files | 3 | flow_config.tcl, mmmc_config.tcl, STA_config.tcl |
| Documentation | 8 | 8 docs across kickstart, user guide, reference, architecture, developer |
| Input resolution handlers | 8 | STA, LEC, CLP(2), PV(2), EMIR(2) input handlers |
| Workspace/user config | 1 | workspace_cmd.py (STA template with from_run/release_tag) |
