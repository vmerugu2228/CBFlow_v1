# CBflow — Future Development Scope

Status: proposed · Owner: CBflow core (vmerugu) · Created: 2026-11-21

Five workstreams that close the loop between CBflow runs and SmartGrid (the
project dashboard, `global/utils/project_dashboard/`) and make every project
phase a systematic, tag-chained execution. Each lists today's baseline, the
gaps, the work items, and the acceptance criteria that mark it done.

---

## 1. Phase-wise checklist generation + SmartGrid integration (full test)

**Goal.** Every project phase (`project(phases)`, e.g. bumblebee LC1–LC5,
opensky P0–P3) produces the right milestone checklists for every discipline,
their status flows into SmartGrid automatically, and the progression
P0 → P3 is tested end to end.

**Baseline today**
- 21 milestones across PD / DFT / DV in `global/config/exit/v1.0.0/`
  (RTL milestones planned), phase-aware check activation, 182 PD library
  checks, `cbflow flow checklist {generate,status,sign-off,waiver,…}`.
- `cbflow run release` publishes a payload that includes a checklist
  snapshot (`client.build_payload` → `_read_run_snapshot`).

**Gaps**
- No test walks a project through *all* of its phases and verifies which
  checks activate at each phase, per discipline.
- The checklist reaches SmartGrid only as a side effect of a release; there
  is no publish on `checklist generate/status/sign-off/waiver`.
- Waivers and sign-offs (who, when, reason) are not visible in SmartGrid.
- RTL discipline has no milestones (LINT/CDC/RDC/UPF sign-off pending).

**Work items**
1. Phase-matrix test: for each project × phase × milestone, generate the
   checklist and assert the active check set against a golden table
   (`test_suite/`, runs in `--integration`).
2. Publish checklist events to SmartGrid (generate / status change /
   sign-off / waiver) through the same best-effort client used by release.
3. SmartGrid views: per-block phase timeline, per-milestone check table with
   status, waiver reason and sign-off owner; phase gate = all mandatory
   checks PASS or WAIVED.
4. RTL milestones (LINT_SIGNOFF, CDC_SIGNOFF, RDC_SIGNOFF, UPF_SIGNOFF)
   once the owner team fixes the criteria.

**Acceptance**
- `bin/cbflow test --integration` includes the phase matrix for bumblebee,
  denali and opensky; green.
- A sign-off or waiver in a run appears in SmartGrid within one refresh,
  with owner, timestamp and reason.
- SmartGrid shows a phase gate (open / blocked / closed) per block.

---

## 2. Release mechanism + integration of released data into SmartGrid

**Goal.** A release is a first-class SmartGrid object: what was released,
from which run, against which checklist state, and what consumed it
downstream (STA / PV / parent block / library tag).

**Baseline today**
- `cbflow run release` / `release-check`; `release_utils.tcl` writes
  `<release,path>/<phase>/<block>/<tag>/` with `MANIFEST.json`,
  `RELEASE_COMPLETE` (STATUS=PASS) and release notes; `--publish` default-on.
- Flow-to-flow handoff by tag (`release_tag`, per-input tags, `from_run`).
- Hierarchical blocks (opensky DL3 → DL2 → DL1) enter the parent through
  `library-manager add --category block --path <release dir>`.

**Gaps**
- SmartGrid shows the latest payload, not a release history per block.
- Consumers are not recorded: which STA/PV runs, parent blocks or library
  tags used a given release.
- No release diff (files, QoR, checklist) between two tags of one block.
- No stale-release warning when a parent or a lib tag still points at an
  older child release.

**Work items**
1. Release registry in the SmartGrid tracker DB: block, tag, phase, run,
   MANIFEST hash, QoR snapshot (WNS/TNS/area/DRC), checklist verdict.
2. Lineage: record each consumer at resolve time (`resolve_flow_inputs`,
   `library-manager add --category block`) and publish it.
3. Release diff page (MANIFEST + QoR + checklist) for any two tags.
4. Staleness: flag parents / lib tags whose child release is not the
   latest PASS release; show in SmartGrid and in `release-check`.

**Acceptance**
- For opensky, SmartGrid shows gcd → ctrl_subsys → opensky_chip and
  mac_array → ai_subsys → opensky_chip lineage with tags and QoR.
- Re-releasing a DL3 block marks its DL2 and the DL1 as stale until they
  are re-run against the new release.
- Two-tag diff renders for any block.

---

## 3. Open DEF and reports from SmartGrid for analysis

**Goal.** From a block's SmartGrid page, open its released DEF in a layout
view and its reports (timing, power, DRC, congestion, QoR) without a
terminal.

**Baseline today**
- `floorplan.py` parses DEF + LEF (die area, components, placement) for a
  floorplan viewer.
- Releases carry `def/`, `reports/`, `spef/`, `sdc/`; open-source runs also
  carry abstract LEF and per-lib-set timing models.

**Gaps**
- No routed-layout view (nets, special nets / power grid, layers), no
  highlight of macros, power domains or DRC markers.
- Reports are files in the release; SmartGrid does not list or render them.
- No cross-link: timing path → cells on the layout; DRC entry → location.

**Work items**
1. Report browser: list `reports/` per release; render text reports with
   search; parse timing (`report_checks`), QoR (`*_qor.tcl`), DRC
   (`route_drc.rpt`) and congestion into tables.
2. Layout viewer: extend `floorplan.py` to special nets (power straps per
   net), routed nets by layer (on demand), macro outlines, voltage-domain
   regions; DRC markers from the DRC report.
3. Cross-probe: click a timing path → highlight its cells; click a DRC
   violation → zoom to it.
4. Large designs: tile / level-of-detail rendering so a 150k-instance DEF
   (opensky mac_array) opens interactively; read access only, behind the
   existing run-ownership rules.
5. Optional: "open in KLayout" link that launches the GDS / DEF locally via
   `cbflow-oss` for full-fidelity inspection.

**Acceptance**
- From SmartGrid, a user opens opensky_chip's DEF, toggles power nets
  (VPWR / VPWR_GCD / VPWR_MAC / VGND), and sees the DL2/DL3 macros.
- Every report in a release is listed and readable; timing and DRC reports
  render as tables with cross-probe to the layout.
- mac_array (>100k instances) opens in under 10 s.

---

## 4. Phase-wise release chain + exit checklists (RTL → SYNTH → PNR → PV/STA)

**Goal.** For every project phase (P1–P4), one systematic run of the whole
chain: an RTL release tag is consumed by SYNTH, SYNTH's release tag by PNR,
PNR's by PV and STA. Every release is captured by its tag in the release
area, and every exit checklist of the phase is run and recorded.

**Baseline today**
- Flow-to-flow handoff by tag: `<flow>(input,release_tag)`, per-input tags,
  `from_run`; handshake map in `PD/config/flow/v1.0.0/release_config.tcl`
  §6 (`PNR,netlist {SYNTH netlist …}`, `PV,gds/netlist {ANY …}`,
  `SYNTH,rtl_from_lint {RTL_LINT …}`).
- Releases land in `<release,path>/<phase>/<block>/<tag>/` with
  `MANIFEST.json` and `RELEASE_COMPLETE` (`release_utils.tcl`); the tag
  resolver reads that layout and the flat `<base>/<tag>/` one
  (`resolve_inputs.tcl::_release_tag_dir`).
- Phases are project-declared (`project(phases)`); exit milestones in
  `global/config/exit/v1.0.0/`, mapped to stages by
  `MILESTONE_STAGE_MAPPING`; `cbflow flow checklist generate/status/sign-off`
  run per milestone.
- Hierarchical blocks move up a level through
  `library-manager add --category block` (DL3 → DL2 → DL1).

**Gaps**
- No RTL release producer: `SYNTH,rtl` / `SYNTH_PNR,rtl` handshakes read
  source `INPUTS`, not a released RTL snapshot (filelist + SDC + UPF).
- Nothing sequences a phase end to end; each flow run and each checklist is
  started by hand.
- No record ties "phase Pn" to the tags it produced, their upstream tags,
  and the checklist verdict at each exit.
- RTL has no exit milestones (see 1.4).
- opensky declares phases P0–P3; the target scheme is P1–P4 (project config
  change, owner sign-off needed).

**Work items**
1. RTL release: `cbflow run release` from an RTL flow (RTL_LINT / UPF_CHECK,
   or a dedicated RTL_RELEASE step) publishing `rtl/<block>.f` with its
   sources, `sdc/` and `upf/` under a tag; point `SYNTH,rtl`,
   `SYNTH_PNR,rtl` (and sdc/upf) at that producer instead of `INPUTS`.
2. Tag convention per phase and flow, e.g. `<phase>_<FLOW>_v<n>`:
   `P1_RTL_v1 → P1_SYNTH_v1 → P1_PNR_v1 → P1_PV_v1 / P1_STA_v1`; each
   MANIFEST names its upstream tag(s) (`_collect_upstream_tags` exists).
3. Phase orchestrator, `cbflow flow phase run --project <p> --phase <Pn>
   [--blocks …]`: creates the runs in chain order, injects each upstream tag
   as `<flow>(input,release_tag)`, runs and releases each flow, then runs
   the exit checklists mapped to that flow's stages — bottom-up per
   hierarchy level, with `library-manager add --category block` between
   levels.
4. Phase ledger: per project / phase / block — tags produced, upstream tags,
   each exit's checklist verdict (PASS / WAIVED / FAIL), violations carried
   (DRC, LVS, timing) — published to SmartGrid (items 1–2).
5. Phase gate: a phase closes when every block's chain released and every
   exit checklist is PASS or WAIVED; the next phase starts from the closed
   phase's tags.
6. RTL exit milestones (LINT / CDC / RDC / UPF sign-off) — with item 1.4.

**Acceptance**
- opensky runs each of P1–P4 for gcd, mac_array → ctrl_subsys, ai_subsys →
  opensky_chip with one command per phase.
- The release area holds every tag (RTL, SYNTH/SYNTH_PNR, PV, STA) per phase
  per block; every MANIFEST names its upstream tag.
- Every exit checklist of the phase ran; its result is in the ledger and in
  SmartGrid.
- Re-running a phase from its recorded tags reproduces the same releases.

---

## 5. Open-source LEC and low-power (CLP) checking

**Goal.** Equivalence and low-power checks in the open-source flow, so the
release chain (item 4) carries LEC and CLP verdicts like the commercial
flows (Formality / Conformal LEC, Conformal LP / VC-LP).

**Baseline today**
- In the cbflow-oss container: **EQY** (YosysHQ equivalence framework,
  v0.70), **SBY** + yices, **yosys-abc** (`cec`), **kepler-formal**
  (gate-level netlist equivalence).
- Flows `LEC` and `CLP` exist with commercial tool overlays only.
- UPF: OpenROAD `read_upf` implements a subset (domains, isolation, interface
  cells, level shifters, switches) and does not verify anything; there is no
  open-source static low-power checker or UPF-aware simulator.

**Work items**
1. LEC flow, tool `opensource/eqy`: RTL ↔ SYNTH netlist and SYNTH ↔ PNR
   netlist (sky130 cell Verilog models as the cell library), consuming the
   RTL / SYNTH / PNR release tags; `abc cec` as the fast gate ↔ gate check
   (post-CTS/buffering netlists). Reports: proved / failed partitions,
   unmatched points.
2. CLP-lite, a CBflow-native checker (Tcl/Python) over the design UPF
   (parsed by `oss_upf_parse`) + the power-aware netlist:
   - every output of a switchable domain reaches the always-on domain
     through an isolation cell (`is_isolation_cell`), with the strategy's
     enable signal, sense and clamp value;
   - isolation cells sit in, and are powered by, the always-on domain
     (pg connections in the `.lvs.v` netlist);
   - domain supplies connect as `connect_supply_net` declares; every supply
     port of a child block is driven at the parent;
   - level-shifter need per crossing from `set_domain_voltage` /
     `add_port_state` (none for opensky: all domains 1.8 V);
   - verdict + violations into the CLP flow's report and the phase ledger.
3. Both flows publish to SmartGrid through the opt-in release form.

**Acceptance**
- opensky: LEC proves RTL ≡ SYNTH and SYNTH ≡ PNR for every block; a
  deliberately broken netlist edit is caught.
- CLP-lite passes on opensky and flags a removed isolation cell or a
  mis-wired `VPWR_GCD` connection.

---

## Sequencing

| Order | Workstream | Depends on |
|---|---|---|
| 1 | Checklist phase-matrix test + checklist events (1.1, 1.2) | — |
| 2 | Release registry + lineage (2.1, 2.2) | 1.2 publish path |
| 3 | Report browser (3.1) | 2.1 registry (which release to open) |
| 4 | Layout viewer + cross-probe (3.2–3.4) | 3.1 |
| 5 | Staleness, release diff, RTL milestones (2.3, 2.4, 1.4, 4.6) | 2.2 |
| 6 | RTL release + phase/flow tag convention (4.1, 4.2) | 2.2 lineage |
| 7 | Phase orchestrator, ledger, gate (4.3–4.5) | 1.2, 2.1, 4.1, 4.2 |
| 8 | Open-source LEC (EQY) + CLP-lite (5.1–5.3) | 4.1 (RTL release) for RTL ↔ SYNTH |

The opensky open-source hierarchy (gcd, mac_array → ctrl_subsys, ai_subsys
→ opensky_chip) is the reference dataset for every acceptance test above.
