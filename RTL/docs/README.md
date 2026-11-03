# CBflow RTL Discipline

Register-Transfer-Level design-side quality flows. Complementary to:
- **DV** (dynamic verification: SPEC_RAMP → DV_SIGNOFF)
- **PD** (implementation: SYNTH → MTO)
- **DFT** (test-structure insertion + ATPG)

RTL flows run static checks on the design RTL **before** synthesis to catch
issues at the cheapest point in the design cycle.

## Flows

| Flow         | Purpose                               | Default tool   | Alt tool          |
|--------------|---------------------------------------|----------------|-------------------|
| `RTL_LINT`   | Static lint rule checks               | Spyglass       | Jaspergold HAL    |
| `RTL_CDC`    | Clock-domain-crossing analysis        | Spyglass CDC   | Jaspergold CDC    |
| `RTL_RDC`    | Reset-domain-crossing analysis        | Spyglass RDC   | Jaspergold RDC    |
| `UPF_CHECK`  | Static UPF intent check (pre-synth)   | VC-LP          | Conformal LP      |

Each flow is independently releasable; sign-off deliverables land under
`results/release/<flow_lower>/` and are packaged into the project release
dir via `cbflow run release --tag <TAG>`.

## Stages (common pattern)

Every RTL flow follows the same high-level stage shape:

```
<inputs> → init1 → compile1 → <tool-specific stages> →
    waiver_apply1 → <report|signoff>1 → release_data1
```

Where `<tool-specific stages>` differs per flow:
- `RTL_LINT`:    `lint1`
- `RTL_CDC`:     `cdc_setup1` → `cdc_analyze1` → `cdc_report1`
- `RTL_RDC`:     `rdc_setup1` → `rdc_analyze1` → `rdc_report1`
- `UPF_CHECK`:   `upf_parse1` → `upf_check1` → `upf_report1`

Each execution stage follows the standard CBflow subnode shape:
`setup → run → validate → finish`.

## Required inputs

Set in `user_config.tcl` under the lowercase flow array:

```tcl
# RTL_LINT
set rtl_lint(input,rtl)         "path/to/filelist.f"
set rtl_lint(input,rule_deck)   "path/to/rules.sgdc"
set rtl_lint(input,top_module)  "cpu_core"
set rtl_lint(input,waiver_file) "path/to/waivers.awl"   ;# optional

# RTL_CDC — same keys plus:
set rtl_cdc(input,sdc)         "path/to/func.sdc"
set rtl_cdc(input,scheme_file) "path/to/cdc_scheme.tcl"

# RTL_RDC — same as CDC plus:
set rtl_rdc(input,reset_scheme_file) "path/to/reset_scheme.tcl"

# UPF_CHECK — RTL + UPF file:
set upf_check(input,upf) "path/to/intent.upf"
```

## Running

```bash
cd workarea/<design>
bin/cbflow workspace create --config uc_RTL_LINT.tcl
cd <PHASE>_run_RTL_LINT_test1
bin/cbflow run all
bin/cbflow run release --tag RTL_SIGNOFF
```

## Architecture

- Flow registry: `global/config/flow/v1.0.0/flow_registry.tcl`
  (adds `RTL_LINT / RTL_CDC / RTL_RDC / UPF_CHECK` to `flow(types)` and
  `flow(discipline,*) RTL`).
- Discipline map: `global/config/flow/v1.0.0/flow_registry.tcl` adds
  `set flow(discipline_dir,RTL) "RTL"`.
- Launcher: `RTL/bin/cbflow-rtl` — extension point for RTL-specific
  subcommands (currently empty; everything routes through the
  cross-domain `cbflow run …` path).
- Env var: `CBFLOW_RTL_DIR` auto-exported if `RTL/` exists in the
  install.

## Tool handler status

| Tool chain              | Status                              |
|-------------------------|-------------------------------------|
| Synopsys Spyglass       | Real TCL command emission (RTL_LINT)|
| Synopsys Spyglass CDC   | Scaffold (owner team fills in)     |
| Synopsys Spyglass RDC   | Scaffold (owner team fills in)     |
| Synopsys VC-LP          | Scaffold (owner team fills in)     |
| Cadence Jaspergold / HAL| Scaffold stub                       |
| Cadence Conformal LP    | Scaffold stub                       |

The Spyglass RTL_LINT handlers emit production-shaped TCL — the rest
ship as scaffolds mirroring the DFT_INSERT_PASS2/PASS3 pattern.
