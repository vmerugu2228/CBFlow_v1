# Open-Source DFT Flow (vendor `opensource`, project `opensky`)

Scan sign-off, stuck-at ATPG and gate-level simulation for sky130 with open
tools, run through the normal CBflow commands (`cbflow workspace create`,
`cbflow run all`, `cbflow run release`, `cbflow flow checklist`).

| Flow | `<arr>(tool,name)` | What it does | Tools |
|---|---|---|---|
| (SYNTH) | `yosys` | **Inserts** the scan chains (`project(dft,enable)`) | Yosys + OpenROAD DFT |
| SCAN_INSERT | `fault` | Signs the scan structure off: chain trace, DFT rules, chain flush | Python (`oss_dft.py`), Icarus |
| ATPG | `fault` | Stuck-at ATPG, fault simulation, chain-ordered patterns, pattern simulation | Fault (`cut`), nl2bench, Atalanta, Icarus |
| GLS_FUNC | `iverilog` | Zero-delay gate-level functional simulation + toggle coverage | Icarus |
| GLS_SCAN_MBIST | `iverilog` | The ATPG patterns simulated on the (post-route) netlist | Icarus |

Not covered yet: MBIST, boundary scan / TAP (DFT_INSERT_PASS1/2), EDT / OCC
(PASS3), transition-fault ATPG, and SDF-annotated (timing) pattern simulation.

## 1. Tools and install

Everything runs in the CBflow tool container (`global/bin/cbflow-oss`), which
ships Fault 0.9.4, nl2bench, Icarus Verilog 14, Verilator 5, Yosys and Python
(pyverilog). One tool is built for the image:

```bash
global/utils/oss/install_atalanta.sh        # -> $HOME/eda/tools/oss/bin/atalanta
global/bin/cbflow-oss check                 # lists fault, nl2bench, atalanta, iverilog, vvp, …
```

- `lsf(oss,tools_dir)` (`global/config/flow/v1.0.0/oss_launch_config.tcl`, default
  `$HOME/eda/tools/oss`) is mounted and its `bin/` put on the container PATH
  (`CBFLOW_OSS_TOOLS`).
- Atalanta (github.com/hsluoyz/Atalanta, pinned commit) is built with
  `-fsigned-char`: its circuit reader keeps characters in `char` and compares with
  EOF, which never matches on arm64 otherwise.
- **Licence:** Atalanta is released for teaching and research use only; any commercial
  use needs written permission from its authors (see its README).
- Fault's own ATPG simulation does not run in this image (no testbench is written and
  its compaction step aborts), so CBflow drives Atalanta directly and keeps Fault for
  `fault cut`.

Tool shells: `lsf(tool_shell,fault|iverilog)` = `cbflow-oss fault|iverilog`. Both run
the stage's Tcl command file under the container's tclsh, which execs the tools.
The netlist / pattern work is done by `DFT/utils/oss/oss_dft.py` (standard library;
`cells`, `census`, `trace`, `flush-tb`, `stubs`, `bench-clean`, `patterns`, `fsim`,
`coverage`, `toggle`, `model-fix`). Tcl helpers: `DFT/utils/utilities/v1.0.0/oss_dft_utils.tcl`.

## 2. Handoffs

```
SYNTH release (netlist with scan, sdc/<d>.scan.sdc)
   └─ SCAN_INSERT  ── SCAN_INSERT_EXIT: netlist/<d>.v, scan/<d>.scandef, scan/<d>.scan.json
         └─ ATPG pre-PD (release_tag SCAN_INSERT_EXIT)  ── ATPG_PREPD_EXIT: patterns/…
PNR release (BTO …)
   ├─ ATPG post-PD (netlist_release_tag BTO + scandef_release_tag SCAN_INSERT_EXIT) ── ATPG_POSTPD_EXIT
   ├─ GLS_FUNC       (netlist_release_tag BTO + testbench)             ── GLS_FUNC/BTO
   └─ GLS_SCAN_MBIST (netlist_release_tag BTO + patterns_release_tag ATPG_PREPD_EXIT) ── GLS_SCAN_MBIST/BTO
```

Handshake entries: `flow_input_handshake(SCAN_INSERT|ATPG|GLS_FUNC|GLS_SCAN_MBIST,*)` in
`PD/config/flow/v1.0.0/release_config.tcl`. The release config, the PD project
overlay (`workarea_path`, `release,path`, `lib_root`, lib tag) and the LSF settings live in the
PD tree and serve the DFT flows too. GLS flows are signoff-style (`<arr>(release,exit_from)`
= the netlist tag; the testbench / patterns input is exempt).

The liberty for a DFT stage comes from its MMMC view: `mmmc_node_scenarios.tcl` nodes
`init_scan`, `init_atpg`, `init_sim` (typical corner).

## 3. Project keys

Global (`opensky_config.tcl`): `project(dft,enable|max_chain_length|clock_mixing|scan_enable_pattern)`.
DFT overlay (`DFT/config/project/opensky/v1.0.0/opensky_dft_config.tcl`):

```tcl
set project(dft,scan_in_pattern)   scan_in_*
set project(dft,scan_out_pattern)  scan_out_*
set project(dft,atpg,test_coverage_min)   95.0
set project(dft,atpg,fault_coverage_min)  90.0
```

## 4. SCAN_INSERT (`SCAN_INSERT_fault_config.tcl`)

| Stage | Does |
|---|---|
| init_scan1 | scan cells from the liberty (`test_cell` signal types), netlist → Yosys JSON, cell census; no scan flops → error naming `project(dft,enable)` |
| scan_stitch1 | chains traced forward from each scan-in port (buffers / inverters, Q / QN) to the scan-out — a `scan_out_*` port or the functional output the inserter reused; clock port + edge (through ICGs), scan-enable port, inversions; `scan.scandef`, `scan.json`, `scan_chains.rpt` |
| scan_check1 | rule violations (broken / looped chains, enable not from a scan-enable port, clock mixing under `no_mix`, length > `max_chain_length`), unscanned flops (`scan_insert(oss,allow_unscanned)`), chain-flush simulation (0011… through every chain, macros stubbed) — any failure fails the stage |
| scan_export1 / release_data1 | `scan.v`, `scan.sdc`, `scan.scandef`, `scan.json` → `SCAN_INSERT_EXIT` |

## 5. ATPG (`ATPG_fault_config.tcl`)

| Stage | Does |
|---|---|
| init_atpg1 | decision node: `atpg(pd_phase)` pre / post; chains re-traced on this netlist and compared with the SCAN_INSERT scandef (different flops → error, reorder → warning, patterns follow this netlist); macro stubs |
| pattern_gen1 | macros replaced by stubs (outputs held 0) and flattened → `fault cut` → `nl2bench` → `bench-clean` (constants, held ports `atpg(oss,hold_ports)`, logic the cut leaves unobservable — counted, not tested) → Atalanta (`atpg(oss,atalanta,backtrack|phase2_backtrack|random_packets|compaction|seed|fill)`) |
| fault_sim1 | independent stuck-at fault simulation of the pattern set: cell-pin faults (every netlist net and cell input branch), all patterns bit-parallel; `atpg(oss,fault_sim,sample)` N > 0 samples N faults (± 95 % CI) |
| coverage_report1 | fault coverage, test coverage (= detected / (faults − proven redundant)), aborted, excluded logic, undetected faults, pin-fault coverage |
| export_patterns1 | patterns mapped onto the chain order (inversions undone): `patterns.json`, STIL-style `patterns.stil`, self-checking serial-scan testbench `scan_tb.v` (top ports only) |
| zd_sim1 | the testbench on the gate netlist (zero-delay); any mismatch fails |
| timing_sim1 | post-PD only; **not supported** — fails with that message; bypass it explicitly (`cbflow run bypass --stages timing_sim1`) and the ATPG_POSTPD_EXIT timing check stays open |
| signoff1 | coverage vs `project(dft,atpg,*_min)`, zd 0 mismatches; `signoff.rpt`, `delivery/MANIFEST.json` |
| release_data1 | `ATPG_PREPD_EXIT` / `ATPG_POSTPD_EXIT`: `patterns/<d>.atpg.stil`, `<d>.patterns.json`, `<d>_scan_tb.v`, `<d>_macro_stubs.v`, `scan/<d>.scandef` |

ATPG model assumptions: full scan, one scan clock, macro (memory / child block) outputs
held 0 (no memory bypass). Faults in logic only reachable through macros count as
excluded.

## 6. GLS_FUNC / GLS_SCAN_MBIST (`*_iverilog_config.tcl`)

Stages `init_sim1 compile1 run_sim1 coverage1 release_data1`. Keys:
`<arr>(oss,tb_top)`, `oss,defines`, `oss,plusargs`, `oss,macros models|stubs`,
`oss,pass_regex`, `oss,fail_regex`, `oss,toggle,enable`, `oss,dump_scope`
(toggle coverage over the nets of that scope, depth 1). GLS_FUNC uses the memory
models of the library tag (`oss_dft.py model-fix` moves the memory declaration ahead
of its use — iverilog rejects the OpenRAM model otherwise); GLS_SCAN_MBIST uses the macro
stubs, matching the ATPG model. `gls_scan_mbist(oss,verify)` must be `scan`.

## 7. Example (gcd, P2) — workarea/gcd/

```bash
cbflow workspace create --config uc_SCAN_INSERT_P2.tcl    && (cd P2_run_SCAN_INSERT_gcd_p2_scan && cbflow run all)
cbflow workspace create --config uc_ATPG_P2_pre.tcl       && (cd P2_run_ATPG_gcd_p2_atpg_pre && cbflow run all)
cbflow workspace create --config uc_ATPG_P2_post.tcl      # then: cbflow run bypass --stages timing_sim1; cbflow run all
cbflow workspace create --config uc_GLS_FUNC_P2_BTO.tcl   # testbench inputs/opensky/gcd/P2/tb/gcd_gls_tb.v
cbflow workspace create --config uc_GLS_SCAN_P2_BTO.tcl
cbflow flow checklist status --milestone SCAN_INSERT_EXIT --run-dir .
```

Results (gcd P2: 51 scan flops, 1 chain ending on `resp_msg[0]`, 2 SRAMs):

| Run | Result |
|---|---|
| SCAN_INSERT | 51/51 flops scanned, 0 violations, flush 59 checks / 0 mismatches; SCAN_INSERT_EXIT checklist PASS |
| ATPG pre-PD | 77 patterns, test coverage 99.91 %, fault coverage 96.95 %, pin-fault coverage 99.85 %, zd 5313 checks / 0 mismatches; ATPG_PREPD_EXIT PASS (fault coverage WARN vs the optional 99 %) |
| ATPG post-PD (BTO) | 73 patterns, test coverage 99.91 %, chains identical to the scandef, zd PASS; ATPG_POSTPD_EXIT blocked only by timing simulation |
| GLS_FUNC (BTO) | 32 tests / 0 errors incl. the SRAM result log, toggle coverage 75.8 % |
| GLS_SCAN_MBIST (BTO) | the 77 pre-PD patterns on the post-route netlist: 5313 checks / 0 mismatches |
