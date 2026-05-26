# CBflow Checklist Guide -- STA, LEC, CLP, PV, EMIR, ECO Flows

## 1. Overview

CBflow v2.0.0 defines **11 milestones** across all design flows:

- **6 SYNTH_PNR milestones:** FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO
- **5 flow-specific signoff milestones:** STA_SIGNOFF, LEC_SIGNOFF, CLP_SIGNOFF, PV_SIGNOFF, EMIR_SIGNOFF

Together these milestones encompass **292 checks across 14 category libraries**, with each flow-specific signoff owning its own exit config (`*_SIGNOFF_config.tcl`) and check library (`*_flow_checks.tcl`).

**Check Libraries (14):**

| Category | Check File | Count | Applicable Flow |
|---|---|---|---|
| Timing | `timing_checks.tcl` | 30 | SYNTH_PNR, PNR, SYNTH, STA |
| Placement | `placement_checks.tcl` | 20 | SYNTH_PNR, PNR, FP |
| Clock | `clock_checks.tcl` | 25 | SYNTH_PNR, PNR |
| Power | `power_checks.tcl` | 20 | SYNTH_PNR, PNR, CLP |
| Routing | `routing_checks.tcl` | 25 | SYNTH_PNR, PNR, PV |
| Physical | `physical_checks.tcl` | 20 | SYNTH_PNR, PNR, FP, EMIR |
| Signal Integrity | `si_checks.tcl` | 15 | SYNTH_PNR, PNR, STA |
| Manufacturing | `manufacturing_checks.tcl` | 15 | SYNTH_PNR, PNR, PV |
| STA Flow | `sta_flow_checks.tcl` | 25 | STA |
| LEC Flow | `lec_flow_checks.tcl` | 15 | LEC |
| CLP Flow | `clp_flow_checks.tcl` | 20 | CLP |
| PV Flow | `pv_flow_checks.tcl` | 30 | PV |
| EMIR Flow | `emir_flow_checks.tcl` | 20 | EMIR |
| ECO Flow | `eco_flow_checks.tcl` | 12 | ECO |

**Design Phases (progressive):**

| Phase | Intent | Criteria |
|---|---|---|
| P0 | Trial / Exploration | Relaxed thresholds, partial deliverables |
| P1 | Implementation | Convergence, core deliverables |
| P2 | Pre-Signoff | Tight criteria, all deliverables |
| P3 | Signoff / Tapeout | Zero violations, full package |

Each check specifies a `min_phase` -- it only activates at that phase or later.

**CLI Commands (same for all milestones):**

```bash
cbflow flow checklist generate     --milestone <MILESTONE>
cbflow flow checklist status       --milestone <MILESTONE> --run-dir <dir> --phase <P0-P3>
cbflow flow checklist sign-off     --milestone <MILESTONE> --run-dir <dir> --approver <name> --phase <P0-P3>
cbflow flow checklist add-check    --milestone <MILESTONE> --name <check> --type mandatory|optional ...
cbflow flow checklist remove-check --milestone <MILESTONE> --name <check>
cbflow flow checklist waiver       --milestone <MILESTONE> --check <check> --reason <text> --approver <name>
```

---

## 2. STA Flow -- STA_SIGNOFF Milestone

**Tools:** PT (Synopsys), Tempus (Cadence)
**Stage:** `timing1` (STA flow)
**Stage Node:** `timing1`
**Report Directory:** `work/STA/timing1/reports`
**Description:** STA Signoff -- All timing scenarios pass across all MMMC views

### CLI Usage

```bash
# Check STA signoff status at P2
cbflow flow checklist status --milestone STA_SIGNOFF --run-dir <sta_run> --phase P2

# Sign off STA at P3
cbflow flow checklist sign-off --milestone STA_SIGNOFF --run-dir <sta_run> --approver timing_lead --phase P3

# Generate the STA_SIGNOFF checklist
cbflow flow checklist generate --milestone STA_SIGNOFF
```

### Check Packs

| Pack | Activates At |
|---|---|
| `sta_flow` | P0 |
| `timing` | P1 |
| `si` | P2 |

### Inline Checks (from STA_SIGNOFF_config.tcl)

**Mandatory Checks (5):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `sta_all_scenarios_pass` | All MMMC timing scenarios pass | grep mmmc_timing_summary.rpt for All.*PASS | P0 | `work/STA/timing1/reports/mmmc_timing_summary.rpt` |
| `sta_setup_clean` | Setup timing clean -- WNS >= 0 across all corners | setup_wns >= 0 | P0 | `work/STA/timing1/reports/report_timing.max.rpt` |
| `sta_hold_clean` | Hold timing clean -- WNS >= 0 across all corners | hold_wns >= 0 | P1 | `work/STA/timing1/reports/report_timing.min.rpt` |
| `sta_constraints_complete` | All timing constraints fully defined | check_timing.rpt shows no unconstrained paths | P1 | `work/STA/timing1/reports/check_timing.rpt` |
| `sta_qor_report` | STA QoR report generated | report exists and parseable | P0 | `work/STA/reporting1/reports/report_qor.rpt` |

**Optional Checks (3):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `sta_power_report` | STA power analysis report | file exists | P2 | `work/STA/timing1/reports/report_power.rpt` |
| `sta_si_report` | Signal integrity crosstalk report | file exists | P2 | `work/STA/timing1/reports/report_si.rpt` |
| `sta_sdf_generated` | SDF delay annotation file generated | file exists | P3 | `work/STA/timing1/outputs/timing.sdf` |

**Mandatory Files:**
- `work/STA/timing1/reports/mmmc_timing_summary.rpt`
- `work/STA/reporting1/reports/report_qor.rpt`

### Library Checks (25 from sta_flow_checks.tcl)

| ID | Check | Description | Severity | Phase | Threshold |
|---|---|---|---|---|---|
| STA-001 | `sta_scenario_complete` | All MMMC scenarios ran to completion without errors | critical | P0 | == 1 |
| STA-002 | `sta_setup_signoff` | Setup WNS across all scenarios must be non-negative | critical | P0 | >= 0.0 |
| STA-003 | `sta_hold_signoff` | Hold WNS across all scenarios must be non-negative | critical | P1 | >= 0.0 |
| STA-004 | `sta_cross_corner_setup` | Worst setup WNS across all corners must meet threshold | critical | P2 | >= 0.0 |
| STA-005 | `sta_cross_corner_hold` | Worst hold WNS across all corners must meet threshold | critical | P2 | >= 0.0 |
| STA-006 | `sta_pba_setup` | Path-based analysis setup timing must be clean | critical | P2 | >= 0.0 |
| STA-007 | `sta_pba_hold` | Path-based analysis hold timing must be clean | critical | P2 | >= 0.0 |
| STA-008 | `sta_epba_setup` | Exhaustive PBA setup analysis WNS must meet threshold | major | P3 | >= 0.0 |
| STA-009 | `sta_epba_hold` | Exhaustive PBA hold analysis WNS must meet threshold | major | P3 | >= 0.0 |
| STA-010 | `sta_si_delta` | SI-aware timing delta must be within acceptable limit | major | P2 | <= 0.050 |
| STA-011 | `sta_clock_reconvergence` | CRPR (clock reconvergence pessimism removal) applied correctly | major | P2 | == yes |
| STA-012 | `sta_constraint_coverage` | All SDC constraints must be exercised in timing analysis | major | P1 | >= 100.0 |
| STA-013 | `sta_unconstrained_paths` | Zero unconstrained timing paths must remain | critical | P1 | <= 0 |
| STA-014 | `sta_max_cap_clean` | Max capacitance violations must be zero across all scenarios | major | P1 | <= 0 |
| STA-015 | `sta_max_tran_clean` | Max transition violations must be zero across all scenarios | major | P1 | <= 0 |
| STA-016 | `sta_max_fanout_clean` | Max fanout violations must be zero across all scenarios | major | P1 | <= 0 |
| STA-017 | `sta_clock_uncertainty` | Clock uncertainty properly set for all clock domains | major | P1 | <= 0 |
| STA-018 | `sta_input_delay_coverage` | All input ports must have input delay constraints defined | minor | P2 | <= 0 |
| STA-019 | `sta_output_delay_coverage` | All output ports must have output delay constraints defined | minor | P2 | <= 0 |
| STA-020 | `sta_mmmc_summary` | Cross-scenario MMMC summary report must be generated | major | P0 | == yes |
| STA-021 | `sta_power_report` | Power analysis report must be generated during STA | minor | P2 | == yes |
| STA-022 | `sta_noise_analysis` | Noise and glitch analysis must be clean | major | P3 | <= 0 |
| STA-023 | `sta_sdf_generated` | SDF timing annotation file must be generated for gate-sim | minor | P3 | == yes |
| STA-024 | `sta_bottleneck_report` | Timing bottleneck analysis report must be complete | minor | P2 | == yes |
| STA-025 | `sta_eco_guidance` | ECO guidance report must be generated for timing closure | minor | P3 | == yes |

### Additional Library Checks Applied

- **timing_checks.tcl** (30 checks) -- loaded via `timing` check pack at P1. Covers generic setup/hold WNS/TNS, constraint violations, path group analysis, and cross-corner metrics applicable to any timing flow.
- **si_checks.tcl** (15 checks) -- loaded via `si` check pack at P2. Covers crosstalk delay/noise, glitch analysis, coupling capacitance, shielding, and SI-aware timing delta.

**STA_SIGNOFF total: 8 inline + 25 library (sta_flow) + 30 library (timing) + 15 library (si) = 78 checks maximum** (timing and si checks additive at P2+).

### Deliverables

| Name | Source | Target | Type |
|---|---|---|---|
| timing_summary | `work/STA/timing1/reports/mmmc_timing_summary.rpt` | `releases/STA_SIGNOFF/mmmc_timing_summary.rpt` | report |
| qor_report | `work/STA/reporting1/reports/report_qor.rpt` | `releases/STA_SIGNOFF/report_qor.rpt` | report |
| setup_timing | `work/STA/timing1/reports/report_timing.max.rpt` | `releases/STA_SIGNOFF/report_timing.max.rpt` | report |
| hold_timing | `work/STA/timing1/reports/report_timing.min.rpt` | `releases/STA_SIGNOFF/report_timing.min.rpt` | report |
| constraint_check | `work/STA/timing1/reports/check_timing.rpt` | `releases/STA_SIGNOFF/check_timing.rpt` | verification |

---

## 3. LEC Flow -- LEC_SIGNOFF Milestone

**Tools:** Formality (Synopsys), Conformal (Cadence)
**Stage:** `compare` (LEC flow)
**Stage Node:** `compare1`
**Report Directory:** `work/LEC/compare1/reports`
**Description:** LEC Signoff -- Formal equivalence verified between RTL and netlist

### CLI Usage

```bash
# Check LEC signoff status at P1
cbflow flow checklist status --milestone LEC_SIGNOFF --run-dir <lec_run> --phase P1

# Sign off LEC at P3
cbflow flow checklist sign-off --milestone LEC_SIGNOFF --run-dir <lec_run> --approver verification_lead --phase P3

# Generate the LEC_SIGNOFF checklist
cbflow flow checklist generate --milestone LEC_SIGNOFF
```

### Check Packs

| Pack | Activates At |
|---|---|
| `lec_flow` | P0 |

### Inline Checks (from LEC_SIGNOFF_config.tcl)

**Mandatory Checks (3):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `lec_equivalence_pass` | Formal equivalence check passed | grep comparison_summary.rpt for SUCCEEDED | P0 | `work/LEC/compare1/reports/comparison_summary.rpt` |
| `lec_zero_failures` | Zero non-equivalent points | failing_points == 0 | P0 | `work/LEC/compare1/reports/comparison_summary.rpt` |
| `lec_netlist_read_clean` | Netlist read without errors | read errors == 0 | P0 | `work/LEC/compare1/reports/read_design.rpt` |

**Optional Checks (2):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `lec_datapath_verify` | Datapath equivalence verification | file exists | P2 | `work/LEC/compare1/reports/datapath_verify.rpt` |
| `lec_svf_applied` | SVF guidance file applied successfully | file exists | P1 | `work/LEC/compare1/reports/svf_status.rpt` |

**Mandatory Files:**
- `work/LEC/compare1/reports/comparison_summary.rpt`

### Library Checks (15 from lec_flow_checks.tcl)

| ID | Check | Description | Severity | Phase | Threshold |
|---|---|---|---|---|---|
| LEC-001 | `lec_equivalence` | Overall logical equivalence verification must SUCCEED | critical | P0 | == SUCCEEDED |
| LEC-002 | `lec_non_equivalent` | Zero non-equivalent comparison points | critical | P0 | <= 0 |
| LEC-003 | `lec_unmapped_points` | Zero unmapped comparison points between golden and revised | critical | P1 | <= 0 |
| LEC-004 | `lec_abort_points` | Zero aborted comparison points during verification | critical | P1 | <= 0 |
| LEC-005 | `lec_black_box` | Zero unresolved black boxes in the design hierarchy | major | P1 | <= 0 |
| LEC-006 | `lec_setup_warnings` | Zero setup and configuration warnings during LEC run | major | P1 | <= 0 |
| LEC-007 | `lec_failing_points_report` | Failing points detailed report generated if any failures exist | major | P1 | == yes |
| LEC-008 | `lec_golden_netlist_read` | Golden (reference) netlist read without errors | critical | P0 | <= 0 |
| LEC-009 | `lec_revised_netlist_read` | Revised (implementation) netlist read without errors | critical | P0 | <= 0 |
| LEC-010 | `lec_datapath_verify` | Datapath equivalence verification completed successfully | major | P2 | == PASS |
| LEC-011 | `lec_multibit_matching` | Multi-bit register matching verified correctly | major | P2 | <= 0 |
| LEC-012 | `lec_scan_chain_verify` | Scan chain logic equivalence verified between golden and revised | major | P2 | <= 0 |
| LEC-013 | `lec_power_domain_verify` | Power domain logic equivalence verified across UPF domains | major | P2 | <= 0 |
| LEC-014 | `lec_svf_applied` | SVF guidance file applied correctly during comparison | major | P1 | == yes |
| LEC-015 | `lec_summary_report` | Complete comparison summary report generated successfully | major | P0 | == yes |

### Deliverables

| Name | Source | Target | Type |
|---|---|---|---|
| comparison_summary | `work/LEC/compare1/reports/comparison_summary.rpt` | `releases/LEC_SIGNOFF/comparison_summary.rpt` | verification |
| read_design_report | `work/LEC/compare1/reports/read_design.rpt` | `releases/LEC_SIGNOFF/read_design.rpt` | report |

**LEC_SIGNOFF total: 5 inline + 15 library (lec_flow) = 20 checks.**

---

## 4. CLP Flow -- CLP_SIGNOFF Milestone

**Tools:** VC-LP (Synopsys), Conformal LP (Cadence)
**Stage:** `clp` (CLP flow)
**Stage Node:** `clp1`
**Report Directory:** `work/CLP/clp1/reports`
**Description:** CLP Signoff -- Power intent verification pass (UPF/CPF clean)

### CLI Usage

```bash
# Check CLP signoff status at P1
cbflow flow checklist status --milestone CLP_SIGNOFF --run-dir <clp_run> --phase P1

# Sign off CLP at P3
cbflow flow checklist sign-off --milestone CLP_SIGNOFF --run-dir <clp_run> --approver power_lead --phase P3

# Generate the CLP_SIGNOFF checklist
cbflow flow checklist generate --milestone CLP_SIGNOFF
```

### Check Packs

| Pack | Activates At |
|---|---|
| `clp_flow` | P0 |
| `power` | P1 |

### Inline Checks (from CLP_SIGNOFF_config.tcl)

**Mandatory Checks (4):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `clp_all_checks_pass` | All power verification checks passed | grep power_verification_summary.rpt for All.*PASSED | P0 | `work/CLP/clp1/reports/power_verification_summary.rpt` |
| `clp_isolation_clean` | Isolation cell checks clean -- no missing isolation | isolation_violations == 0 | P0 | `work/CLP/clp1/reports/isolation_check.rpt` |
| `clp_level_shifter_clean` | Level shifter checks clean -- no missing level shifters | level_shifter_violations == 0 | P0 | `work/CLP/clp1/reports/level_shifter_check.rpt` |
| `clp_upf_clean` | UPF power intent read without errors | upf_errors == 0 | P0 | `work/CLP/clp1/reports/upf_check.rpt` |

**Optional Checks (2):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `clp_retention_verify` | Retention register verification | file exists | P2 | `work/CLP/clp1/reports/retention_verify.rpt` |
| `clp_power_state_complete` | All power states and transitions verified | file exists | P3 | `work/CLP/clp1/reports/power_state_table.rpt` |

**Mandatory Files:**
- `work/CLP/clp1/reports/power_verification_summary.rpt`

### Library Checks (20 from clp_flow_checks.tcl)

| ID | Check | Description | Severity | Phase | Threshold |
|---|---|---|---|---|---|
| CLP-001 | `clp_isolation_check` | All isolation cells present at power domain crossings | critical | P0 | <= 0 |
| CLP-002 | `clp_level_shifter_check` | All level shifters present at voltage domain crossings | critical | P0 | <= 0 |
| CLP-003 | `clp_retention_check` | Retention save and restore paths verified correctly | critical | P1 | <= 0 |
| CLP-004 | `clp_power_domain_check` | All power domains correctly defined and connected | critical | P0 | <= 0 |
| CLP-005 | `clp_always_on_check` | Always-on logic properly connected to always-on supply | critical | P1 | <= 0 |
| CLP-006 | `clp_voltage_area_check` | Voltage areas correctly bounded and non-overlapping | critical | P1 | <= 0 |
| CLP-007 | `clp_supply_check` | Supply net connections verified for all power domains | critical | P1 | <= 0 |
| CLP-008 | `clp_isolation_enable` | Isolation enable signal timing verified for all domains | major | P2 | <= 0 |
| CLP-009 | `clp_level_shifter_placement` | Level shifters placed in correct voltage area | major | P2 | <= 0 |
| CLP-010 | `clp_power_switch_check` | Power switch chain integrity and connectivity verified | major | P2 | <= 0 |
| CLP-011 | `clp_corruption_check` | State corruption during power transitions must be zero | major | P2 | <= 0 |
| CLP-012 | `clp_upf_syntax` | UPF file lint and syntax check must be clean | major | P0 | <= 0 |
| CLP-013 | `clp_upf_vs_impl` | UPF power intent must match physical implementation | critical | P1 | <= 0 |
| CLP-014 | `clp_multi_driver` | Multi-driver net checks at power domain boundaries | major | P1 | <= 0 |
| CLP-015 | `clp_hanging_crossover` | Hanging crossover signal detection at domain boundaries | major | P1 | <= 0 |
| CLP-016 | `clp_sleep_wakeup` | Sleep and wakeup sequence verification for all domains | major | P3 | <= 0 |
| CLP-017 | `clp_ao_buffer` | Always-on buffer chain verification for power-gated domains | major | P2 | <= 0 |
| CLP-018 | `clp_power_state_table` | Power state table completeness across all defined states | minor | P2 | >= 100.0 |
| CLP-019 | `clp_esd_domain` | ESD discharge path integrity through power domains | minor | P3 | <= 0 |
| CLP-020 | `clp_summary_report` | Complete CLP verification summary report generated | major | P0 | == yes |

### Additional Library Checks Applied

- **power_checks.tcl** (20 checks) -- loaded via `power` check pack at P1. Covers generic power domain, isolation, retention, UPF, and power switch checks shared with SYNTH_PNR milestones.

### Deliverables

| Name | Source | Target | Type |
|---|---|---|---|
| power_verification_summary | `work/CLP/clp1/reports/power_verification_summary.rpt` | `releases/CLP_SIGNOFF/power_verification_summary.rpt` | verification |
| isolation_report | `work/CLP/clp1/reports/isolation_check.rpt` | `releases/CLP_SIGNOFF/isolation_check.rpt` | verification |
| level_shifter_report | `work/CLP/clp1/reports/level_shifter_check.rpt` | `releases/CLP_SIGNOFF/level_shifter_check.rpt` | verification |
| upf_report | `work/CLP/clp1/reports/upf_check.rpt` | `releases/CLP_SIGNOFF/upf_check.rpt` | verification |

**CLP_SIGNOFF total: 6 inline + 20 library (clp_flow) + 20 library (power) = 46 checks maximum** (power checks additive at P1+).

---

## 5. PV Flow -- PV_SIGNOFF Milestone

**Tools:** ICV (Synopsys), Calibre (Cadence)
**Stage:** `merge_data` (PV flow)
**Stage Node:** `merge_data1`
**Report Directory:** `work/PV/merge_data1/reports`
**Description:** PV Signoff -- DRC/LVS/ERC clean for tapeout readiness

### CLI Usage

```bash
# Check PV signoff status at P2
cbflow flow checklist status --milestone PV_SIGNOFF --run-dir <pv_run> --phase P2

# Sign off PV at P3
cbflow flow checklist sign-off --milestone PV_SIGNOFF --run-dir <pv_run> --approver pv_lead --phase P3

# Generate the PV_SIGNOFF checklist
cbflow flow checklist generate --milestone PV_SIGNOFF
```

### Check Packs

| Pack | Activates At |
|---|---|
| `pv_flow` | P0 |
| `manufacturing` | P2 |

### Inline Checks (from PV_SIGNOFF_config.tcl)

**Mandatory Checks (4):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `pv_drc_clean` | DRC clean -- zero violations | grep drc_summary.rpt for Total.*0 | P0 | `work/PV/drc1/reports/drc_summary.rpt` |
| `pv_lvs_match` | LVS layout vs schematic match | grep lvs_summary.rpt for MATCH | P0 | `work/PV/lvs1/reports/lvs_summary.rpt` |
| `pv_erc_clean` | ERC electrical rule check clean | erc_violations == 0 | P1 | `work/PV/erc1/reports/erc_summary.rpt` |
| `pv_verification_complete` | All PV verification stages completed | all verification reports exist | P0 | `work/PV/merge_data1/reports/pv_status.rpt` |

**Optional Checks (3):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `pv_perc_clean` | PERC reliability check clean | file exists | P2 | `work/PV/perc1/reports/perc_summary.rpt` |
| `pv_fill_density` | Metal fill density within foundry limits | file exists | P2 | `work/PV/fill1/reports/fill_density.rpt` |
| `pv_xor_clean` | XOR check between revisions clean | file exists | P3 | `work/PV/xor1/reports/xor_summary.rpt` |

**Mandatory Files:**
- `work/PV/drc1/reports/drc_summary.rpt`
- `work/PV/lvs1/reports/lvs_summary.rpt`

### Library Checks (30 from pv_flow_checks.tcl)

| ID | Check | Description | Severity | Phase | Threshold |
|---|---|---|---|---|---|
| PV-001 | `pv_drc_total` | Total DRC violations must be zero | critical | P0 | == 0 |
| PV-002 | `pv_drc_spacing` | Metal spacing violations must be zero | critical | P1 | == 0 |
| PV-003 | `pv_drc_width` | Min width violations must be zero | critical | P1 | == 0 |
| PV-004 | `pv_drc_enclosure` | Via enclosure violations must be zero | critical | P1 | == 0 |
| PV-005 | `pv_drc_area` | Min area violations must be zero | major | P2 | == 0 |
| PV-006 | `pv_drc_density` | Density rule violations must be zero | major | P2 | == 0 |
| PV-007 | `pv_drc_antenna` | Antenna DRC violations must be zero | major | P2 | == 0 |
| PV-008 | `pv_drc_off_grid` | Off-grid violations must be zero | major | P1 | == 0 |
| PV-009 | `pv_drc_overlap` | Metal overlap violations must be zero | critical | P1 | == 0 |
| PV-010 | `pv_drc_notch` | Notch violations must be zero | major | P2 | == 0 |
| PV-011 | `pv_lvs_match` | LVS comparison result must be MATCH | critical | P0 | == MATCH |
| PV-012 | `pv_lvs_shorts` | LVS short circuits must be zero | critical | P0 | == 0 |
| PV-013 | `pv_lvs_opens` | LVS open circuits must be zero | critical | P0 | == 0 |
| PV-014 | `pv_lvs_device_mismatch` | Device count mismatch must be zero | critical | P1 | == 0 |
| PV-015 | `pv_lvs_net_mismatch` | Net count mismatch must be zero | critical | P1 | == 0 |
| PV-016 | `pv_lvs_property_mismatch` | Device property mismatch must be zero | major | P2 | == 0 |
| PV-017 | `pv_lvs_floating_nets` | Floating nets in layout must be zero | major | P1 | == 0 |
| PV-018 | `pv_lvs_missing_connections` | Missing connections must be zero | critical | P1 | == 0 |
| PV-019 | `pv_erc_total` | Total ERC violations must be zero | major | P1 | == 0 |
| PV-020 | `pv_erc_well_contact` | Well contact violations must be zero | major | P2 | == 0 |
| PV-021 | `pv_erc_floating_gate` | Floating gate violations must be zero | critical | P2 | == 0 |
| PV-022 | `pv_erc_latchup` | Latch-up violations must be zero | critical | P2 | == 0 |
| PV-023 | `pv_perc_esd` | ESD protection path violations must be zero | major | P2 | == 0 |
| PV-024 | `pv_perc_voltage` | Voltage-aware DRC violations must be zero | major | P2 | == 0 |
| PV-025 | `pv_perc_latchup` | PERC latch-up check violations must be zero | major | P2 | == 0 |
| PV-026 | `pv_fill_complete` | Metal fill generation completed successfully | major | P2 | == COMPLETED |
| PV-027 | `pv_fill_density` | Post-fill density within foundry limits | major | P2 | == 0 |
| PV-028 | `pv_xor_clean` | XOR comparison (pre/post fill) must be clean | major | P3 | == 0 |
| PV-029 | `pv_merge_complete` | Layout merge completed without errors | major | P3 | == COMPLETED |
| PV-030 | `pv_summary_report` | Complete PV summary report generated | major | P0 | == GENERATED |

### Additional Library Checks Applied

- **manufacturing_checks.tcl** (15 checks) -- loaded via `manufacturing` check pack at P2. Covers per-layer metal density, via density, double patterning, OPC-friendly checks, lithography hotspots, and CMP uniformity.

### Deliverables

| Name | Source | Target | Type |
|---|---|---|---|
| drc_summary | `work/PV/drc1/reports/drc_summary.rpt` | `releases/PV_SIGNOFF/drc_summary.rpt` | verification |
| lvs_summary | `work/PV/lvs1/reports/lvs_summary.rpt` | `releases/PV_SIGNOFF/lvs_summary.rpt` | verification |
| erc_summary | `work/PV/erc1/reports/erc_summary.rpt` | `releases/PV_SIGNOFF/erc_summary.rpt` | verification |
| pv_status | `work/PV/merge_data1/reports/pv_status.rpt` | `releases/PV_SIGNOFF/pv_status.rpt` | report |

**PV_SIGNOFF total: 7 inline + 30 library (pv_flow) + 15 library (manufacturing) = 52 checks maximum** (manufacturing checks additive at P2+).

---

## 6. EMIR Flow -- EMIR_SIGNOFF Milestone

**Tools:** RedHawk (Synopsys), Voltus (Cadence)
**Stage:** `ir_drop` (EMIR flow)
**Stage Node:** `ir_drop1`
**Report Directory:** `work/EMIR/ir_drop1/reports`
**Description:** EMIR Signoff -- IR drop and EM within limits for power grid signoff

### CLI Usage

```bash
# Check EMIR signoff status at P2
cbflow flow checklist status --milestone EMIR_SIGNOFF --run-dir <emir_run> --phase P2

# Sign off EMIR at P3
cbflow flow checklist sign-off --milestone EMIR_SIGNOFF --run-dir <emir_run> --approver power_integrity_lead --phase P3

# Generate the EMIR_SIGNOFF checklist
cbflow flow checklist generate --milestone EMIR_SIGNOFF
```

### Check Packs

| Pack | Activates At |
|---|---|
| `emir_flow` | P0 |

### Inline Checks (from EMIR_SIGNOFF_config.tcl)

**Mandatory Checks (3):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `emir_ir_drop_pass` | IR drop within specified limits | grep ir_drop_summary.rpt for PASS | P1 | `work/EMIR/ir_drop1/reports/ir_drop_summary.rpt` |
| `emir_em_clean` | Electromigration check -- zero violations | grep em_summary.rpt for violations.*0 | P2 | `work/EMIR/ir_drop1/reports/em_summary.rpt` |
| `emir_power_analysis` | Power analysis report generated | report exists and parseable | P0 | `work/EMIR/power_analysis1/reports/power_summary.rpt` |

**Optional Checks (2):**

| Check Name | Description | Criteria | Phase | Report File |
|---|---|---|---|---|
| `emir_thermal_check` | Thermal analysis within limits | file exists | P2 | `work/EMIR/ir_drop1/reports/thermal_analysis.rpt` |
| `emir_dynamic_ir` | Dynamic IR drop analysis | file exists | P3 | `work/EMIR/ir_drop1/reports/dynamic_ir_drop.rpt` |

**Mandatory Files:**
- `work/EMIR/ir_drop1/reports/ir_drop_summary.rpt`
- `work/EMIR/power_analysis1/reports/power_summary.rpt`

### Library Checks (20 from emir_flow_checks.tcl)

| ID | Check | Description | Severity | Phase | Threshold |
|---|---|---|---|---|---|
| EMIR-001 | `emir_power_total` | Total power must be within budget | major | P0 | <= 1000.0 mW |
| EMIR-002 | `emir_power_leakage` | Leakage power must be within limit | major | P1 | <= 100.0 mW |
| EMIR-003 | `emir_power_dynamic` | Dynamic power must be within limit | major | P1 | <= 900.0 mW |
| EMIR-004 | `emir_power_clock` | Clock power percentage must be acceptable | minor | P1 | <= 40.0 % |
| EMIR-005 | `emir_power_per_domain` | Per-power-domain power must be within budget | major | P2 | == 0 |
| EMIR-006 | `emir_static_ir_vdd` | Static VDD IR drop must be within threshold | critical | P1 | <= 20.0 mV |
| EMIR-007 | `emir_static_ir_vss` | Static VSS IR drop (ground bounce) must be within threshold | critical | P1 | <= 20.0 mV |
| EMIR-008 | `emir_dynamic_ir` | Dynamic IR drop must be within threshold | critical | P2 | <= 50.0 mV |
| EMIR-009 | `emir_ir_worst_instance` | Worst instance voltage drop must be within margin | critical | P2 | <= 30.0 mV |
| EMIR-010 | `emir_ir_coverage` | IR analysis coverage (percent of PG mesh analyzed) | major | P1 | >= 95.0 % |
| EMIR-011 | `emir_em_signal` | Signal EM violations must be zero | critical | P2 | == 0 |
| EMIR-012 | `emir_em_power` | Power net EM violations must be zero | critical | P2 | == 0 |
| EMIR-013 | `emir_em_via` | Via EM violations must be zero | major | P2 | == 0 |
| EMIR-014 | `emir_em_worst_ratio` | Worst EM current ratio must be within limit | major | P2 | <= 1.0 |
| EMIR-015 | `emir_thermal_max` | Max junction temperature must be within limit | major | P2 | <= 125.0 C |
| EMIR-016 | `emir_thermal_hotspot` | Number of thermal hotspots must be within limit | major | P2 | <= 0 |
| EMIR-017 | `emir_thermal_gradient` | Thermal gradient must be within limit | minor | P3 | <= 10.0 C/mm |
| EMIR-018 | `emir_pg_missing_via` | Missing PG vias must be zero | critical | P1 | == 0 |
| EMIR-019 | `emir_pg_strap_integrity` | PG strap connectivity must be verified | critical | P1 | == PASS |
| EMIR-020 | `emir_summary_report` | Complete EMIR summary report generated | major | P0 | == GENERATED |

### EMIR Library Check Categories

The 20 emir_flow checks span 5 sub-categories:

| Sub-Category | Checks | IDs |
|---|---|---|
| Power Analysis | `emir_power_total`, `emir_power_leakage`, `emir_power_dynamic`, `emir_power_clock`, `emir_power_per_domain` | EMIR-001 to EMIR-005 |
| IR Drop | `emir_static_ir_vdd`, `emir_static_ir_vss`, `emir_dynamic_ir`, `emir_ir_worst_instance`, `emir_ir_coverage` | EMIR-006 to EMIR-010 |
| Electromigration | `emir_em_signal`, `emir_em_power`, `emir_em_via`, `emir_em_worst_ratio` | EMIR-011 to EMIR-014 |
| Thermal | `emir_thermal_max`, `emir_thermal_hotspot`, `emir_thermal_gradient` | EMIR-015 to EMIR-017 |
| Power Mesh | `emir_pg_missing_via`, `emir_pg_strap_integrity`, `emir_summary_report` | EMIR-018 to EMIR-020 |

### Deliverables

| Name | Source | Target | Type |
|---|---|---|---|
| ir_drop_summary | `work/EMIR/ir_drop1/reports/ir_drop_summary.rpt` | `releases/EMIR_SIGNOFF/ir_drop_summary.rpt` | report |
| em_summary | `work/EMIR/ir_drop1/reports/em_summary.rpt` | `releases/EMIR_SIGNOFF/em_summary.rpt` | report |
| power_summary | `work/EMIR/power_analysis1/reports/power_summary.rpt` | `releases/EMIR_SIGNOFF/power_summary.rpt` | report |

**EMIR_SIGNOFF total: 5 inline + 20 library (emir_flow) = 25 checks.**

---

## 7. ECO Flow -- ECO_SIGNOFF (No Exit Config Yet)

**Tools:** FC (Synopsys), Innovus (Cadence)
**Stages:** `netlist1 -> def1 -> sdc1 -> library1 -> eco1 -> export_db1`
**Inputs:** Gate-level netlist, DEF, SDC, technology libraries, change file

The ECO flow does **not** yet have an `ECO_SIGNOFF_config.tcl` exit config, but it does have a complete check library (`eco_flow_checks.tcl`) with 12 checks ready for use. These checks can be applied via CLI to any milestone (e.g., BTO) or can become part of a future `ECO_SIGNOFF` milestone.

### Library Checks (12 from eco_flow_checks.tcl)

| ID | Check | Description | Severity | Phase | Threshold |
|---|---|---|---|---|---|
| ECO-001 | `eco_implementation` | ECO changes implemented successfully | critical | P0 | == PASS |
| ECO-002 | `eco_netlist_generated` | Post-ECO netlist generated successfully | critical | P0 | == GENERATED |
| ECO-003 | `eco_timing_impact` | ECO timing impact must be within acceptable range | critical | P1 | >= -0.050 |
| ECO-004 | `eco_hold_impact` | ECO hold timing impact must be within acceptable range | major | P1 | >= -0.020 |
| ECO-005 | `eco_drc_clean` | Post-ECO DRC must be clean | major | P2 | == 0 |
| ECO-006 | `eco_connectivity` | Post-ECO connectivity must be verified | critical | P1 | == PASS |
| ECO-007 | `eco_legality` | Post-ECO cell placement must be legal | critical | P1 | == 0 |
| ECO-008 | `eco_lec_verify` | Post-ECO LEC verification recommended | major | P2 | == PASS |
| ECO-009 | `eco_spare_cell_usage` | Spare cells used vs available within acceptable ratio | minor | P1 | <= 80.0 % |
| ECO-010 | `eco_routing_complete` | ECO routing must be completed | critical | P1 | == COMPLETED |
| ECO-011 | `eco_changes_report` | ECO changes report generated | major | P0 | == GENERATED |
| ECO-012 | `eco_summary_report` | Complete ECO summary report generated | major | P0 | == GENERATED |

### ECO Library Check Categories

| Sub-Category | Checks | IDs |
|---|---|---|
| ECO Core | `eco_implementation`, `eco_netlist_generated`, `eco_lec_verify`, `eco_spare_cell_usage`, `eco_changes_report`, `eco_summary_report` | ECO-001, ECO-002, ECO-008, ECO-009, ECO-011, ECO-012 |
| ECO Timing | `eco_timing_impact`, `eco_hold_impact` | ECO-003, ECO-004 |
| ECO Physical | `eco_drc_clean`, `eco_connectivity`, `eco_legality`, `eco_routing_complete` | ECO-005, ECO-006, ECO-007, ECO-010 |

### How to Add ECO Checks via CLI

Until an `ECO_SIGNOFF_config.tcl` is created, add ECO checks to the BTO milestone manually:

```bash
# ECO implementation passed
cbflow flow checklist add-check --milestone BTO --name eco_implementation --type mandatory \
  --description "ECO changes implemented successfully" \
  --grep-file "work/ECO/eco1/reports/eco_summary.rpt" \
  --grep-pattern "ECO Implementation Status.*PASS" --grep-pass-if found

# Post-ECO netlist generated
cbflow flow checklist add-check --milestone BTO --name eco_netlist_generated --type mandatory \
  --description "Post-ECO netlist generated" \
  --grep-file "work/ECO/eco1/reports/eco_summary.rpt" \
  --grep-pattern "Post-ECO Netlist.*GENERATED" --grep-pass-if found

# ECO timing impact within limits
cbflow flow checklist add-check --milestone BTO --name eco_timing_impact --type mandatory \
  --description "ECO setup timing impact within -50ps" \
  --grep-file "work/ECO/eco1/reports/eco_timing.rpt" \
  --grep-pattern "ECO Setup WNS Impact" --grep-pass-if found

# Post-ECO connectivity verified
cbflow flow checklist add-check --milestone BTO --name eco_connectivity --type mandatory \
  --description "Post-ECO connectivity verified" \
  --grep-file "work/ECO/eco1/reports/eco_summary.rpt" \
  --grep-pattern "Post-ECO Connectivity.*PASS" --grep-pass-if found

# Post-ECO placement legal
cbflow flow checklist add-check --milestone BTO --name eco_legality --type mandatory \
  --description "Post-ECO cell placement legal" \
  --grep-file "work/ECO/eco1/reports/eco_summary.rpt" \
  --grep-pattern "Post-ECO Legality Violations.*0" --grep-pass-if found

# Post-ECO LEC verification
cbflow flow checklist add-check --milestone BTO --name eco_lec_verify --type mandatory \
  --description "Post-ECO LEC equivalence verified" \
  --grep-file "work/ECO/eco1/reports/eco_summary.rpt" \
  --grep-pattern "Post-ECO LEC Status.*PASS" --grep-pass-if found

# ECO routing completed
cbflow flow checklist add-check --milestone BTO --name eco_routing_complete --type mandatory \
  --description "ECO routing completed" \
  --grep-file "work/ECO/eco1/reports/eco_summary.rpt" \
  --grep-pattern "ECO Routing Status.*COMPLETED" --grep-pass-if found

# Post-ECO DRC clean
cbflow flow checklist add-check --milestone BTO --name eco_drc_clean --type optional \
  --description "Post-ECO DRC clean" \
  --grep-file "work/ECO/eco1/reports/eco_summary.rpt" \
  --grep-pattern "Post-ECO DRC Violations.*0" --grep-pass-if found
```

---

## 8. Cross-Flow BTO Sign-Off Checklist

A complete BTO (Block Tapeout) requires ALL of the following signoff milestones to pass. This is the comprehensive cross-flow verification gate before tapeout.

### BTO Component Summary

| Flow | Milestone | Inline Checks | Library Checks | Total | Key Requirement |
|---|---|---|---|---|---|
| SYNTH_PNR | BTO | 9 | 170 | 182 | All 8 check categories pass at signoff1 |
| STA | STA_SIGNOFF | 8 | 25 | 33 | Timing clean across all MMMC scenarios |
| LEC | LEC_SIGNOFF | 5 | 15 | 20 | Formal equivalence verified |
| CLP | CLP_SIGNOFF | 6 | 20 | 26 | Power intent verified (UPF/CPF clean) |
| PV | PV_SIGNOFF | 7 | 30 | 37 | DRC/LVS/ERC clean |
| EMIR | EMIR_SIGNOFF | 5 | 20 | 25 | IR drop and EM within limits |
| **Total** | | **40** | **280** | **323** | **All cross-flow checks pass** |

### How to Verify Cross-Flow BTO

Run signoff status for each flow independently. All must show PASS before BTO can be signed off:

```bash
# 1. SYNTH_PNR BTO milestone
cbflow flow checklist status --milestone BTO --run-dir <synth_pnr_run> --phase P3

# 2. STA signoff
cbflow flow checklist status --milestone STA_SIGNOFF --run-dir <sta_run> --phase P3

# 3. LEC signoff
cbflow flow checklist status --milestone LEC_SIGNOFF --run-dir <lec_run> --phase P3

# 4. CLP signoff
cbflow flow checklist status --milestone CLP_SIGNOFF --run-dir <clp_run> --phase P3

# 5. PV signoff
cbflow flow checklist status --milestone PV_SIGNOFF --run-dir <pv_run> --phase P3

# 6. EMIR signoff
cbflow flow checklist status --milestone EMIR_SIGNOFF --run-dir <emir_run> --phase P3
```

### Cross-Flow Sign-Off Sequence

The recommended sign-off order ensures each dependent flow is verified before its consumers:

```
1. STA_SIGNOFF   (timing clean)
2. LEC_SIGNOFF   (equivalence verified)
3. CLP_SIGNOFF   (power intent verified)
4. PV_SIGNOFF    (DRC/LVS/ERC clean)
5. EMIR_SIGNOFF  (IR drop/EM clean)
6. BTO           (all above + SYNTH_PNR pass)
```

### Waiver Process for Cross-Flow BTO

If a check cannot pass and requires a waiver:

```bash
# Waiver example: PV DRC waiver for known foundry-accepted violation
cbflow flow checklist waiver --milestone PV_SIGNOFF \
  --check pv_drc_density \
  --reason "Foundry-accepted density waiver per TechNote TN-2024-042" \
  --approver pv_lead

# Waiver example: EMIR thermal check waiver
cbflow flow checklist waiver --milestone EMIR_SIGNOFF \
  --check emir_thermal_gradient \
  --reason "Thermal gradient acceptable per thermal simulation TSR-001" \
  --approver power_integrity_lead
```

---

## 9. Summary Table

### All 11 Milestones

| Milestone | Flow | Inline Checks | Library Checks | Total Checks | Stage |
|---|---|---|---|---|---|
| FP_EXIT | SYNTH_PNR | 6 | 170 | 176 | floorplan1 |
| PLACE_EXIT | SYNTH_PNR | 7 | 170 | 177 | place1 |
| CTS_EXIT | SYNTH_PNR | 8 | 170 | 178 | cts1 |
| PRO_EXIT | SYNTH_PNR | 8 | 170 | 178 | pro1 |
| BTO | SYNTH_PNR | 9 | 170 | 182 | signoff1 |
| MTO | SYNTH_PNR | 9 | 170 | 182 | signoff1 |
| STA_SIGNOFF | STA | 8 | 25 | 33 | timing1 |
| LEC_SIGNOFF | LEC | 5 | 15 | 20 | compare1 |
| CLP_SIGNOFF | CLP | 6 | 20 | 26 | clp1 |
| PV_SIGNOFF | PV | 7 | 30 | 37 | merge_data1 |
| EMIR_SIGNOFF | EMIR | 5 | 20 | 25 | ir_drop1 |

**Grand total: 292 unique checks across 14 category libraries.**

Note: Additional check packs (e.g., `timing` at P1, `si` at P2, `power` at P1, `manufacturing` at P2) load supplementary checks from shared libraries at their activation phase. The counts above reflect the flow-specific inline + primary library checks only.

### Config File Locations

```
Exit configs:           PD/config/exit/v1.0.0/{STA,LEC,CLP,PV,EMIR}_SIGNOFF_config.tcl
Flow check libraries:   PD/config/exit/v1.0.0/checks/{sta,lec,clp,pv,emir,eco}_flow_checks.tcl
Shared check libraries: PD/config/exit/v1.0.0/checks/{timing,placement,clock,power,routing,physical,si,manufacturing}_checks.tcl
SYNTH_PNR milestones:   PD/config/exit/v1.0.0/{FP_EXIT,PLACE_EXIT,CTS_EXIT,PRO_EXIT,BTO,MTO}_config.tcl
Release config:         PD/config/flow/v1.0.0/release_config.tcl
Threshold overrides:    PD/config/exit/v1.0.0/threshold_overrides.tcl
Waiver config:          PD/config/exit/v1.0.0/waiver_config.tcl
Remediation config:     PD/config/exit/v1.0.0/remediation_config.tcl
```
