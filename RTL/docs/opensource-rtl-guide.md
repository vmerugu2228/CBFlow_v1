# Open-Source RTL Flows (vendor `opensource`, project `opensky`)

The front end of spec-to-GDS on open tools: **RTL_SPEC** (block spec → design
collateral), then the RTL checks **RTL_LINT** (slang + Verilator + Verible),
**RTL_CDC** (opencdc) and **UPF_CHECK** (CBflow checker) on the RTL_SPEC
release; SYNTH reads the lint-clean SystemVerilog through the yosys-slang front
end. RTL_RDC has no open-source tool (gap — RDC_SIGNOFF is not claimed).

Related guides: [spec-to-GDS chain](../../PD/docs/02-user-guide/spec-to-gds-guide.md),
[open-source DV](../../DV/docs/opensource-dv-guide.md),
[open-source DFT](../../DFT/docs/opensource-dft-guide.md),
[open-source PD](../../PD/docs/02-user-guide/opensource-flow-guide.md).

## 1. Spec formats

| Artefact | Source format | Standard |
|---|---|---|
| Block spec — ports, interfaces, clocks, resets, IO timing, power domains, memories, RTL sources, features | YAML `<block>.spec.yaml` (CBflow spec schema v1) | — (generates IP-XACT) |
| Registers | SystemRDL `<regs>.rdl`, or an XLS register sheet | Accellera SystemRDL 2.0 |
| Component exchange | generated IP-XACT component | IEEE 1685-2014 |
| Verification plan | generated XLS vPlan (owned / edited by DV afterwards) | spreadsheet vPlan |

IP-XACT is 1685-2014 because that is what the register tool chain (PeakRDL)
writes and Kactus2 reads; the component is validated against the Accellera
schema.

### Block spec (YAML)

Excerpt of the pilot spec (`inputs/opensky/gcd/P3/spec/gcd.spec.yaml`):

```yaml
spec_version: 1
block: gcd
version: "1.0"
vendor: smartsocs.com
library: opensky
description: ...
clocks:    [{name: core_clock, port: clk, period_ns: 20.0, uncertainty_ns: 0.25}]
resets:    [{name: reset, port: reset, active: high, synchronous: true}]
ports:     [{name: req_msg, dir: in, width: 32, interface: req}, ...]
interfaces:
  - {name: req,  protocol: valid_ready, mode: slave,  signals: {valid: req_val, ready: req_rdy, data: req_msg}}
  - {name: resp, protocol: valid_ready, mode: master, signals: {valid: resp_val, ready: resp_rdy, data: resp_msg}}
  - {name: csr,  protocol: apb4,        mode: slave,  prefix: s_apb_, registers: gcd_regs.rdl, base_address: 0x0}
io_timing: {input_delay_pct: 10, output_delay_pct: 10, output_load_pf: 0.033}
power:
  upf_version: "2.1"
  domains: [{name: PD_GCD, elements: [.], supply: {power: VPWR, ground: VGND}, switchable: true, states: {ON: 1.80, OFF: off}}]
memories:
  - inst: u_sram_job
    macro: sky130_sram_1kbyte_1rw1r_32x256_8
    depth: 256
    width: 32
    ports: [{name: p0, type: rw, clock: clk, use: job push}, {name: p1, type: r, clock: clk, use: engine fetch}]
    mbist: {enable: true, algorithm: march_c_minus, group: mbist_g0}   # march_c_minus | march_c | march_b | mats_plus
rtl:       {top: gcd, language: systemverilog, sources: [../rtl/gcd.sv]}
features:  [{id: F1, name: gcd compute, priority: P1, milestone: M1, tests: [...], coverage: [...]}]
```

- Interface protocols: `valid_ready` (signals `valid` / `ready` / `data`;
  a `slave` has `valid` as an input) and `apb4` (every APB4 signal must be a
  port with the `prefix`). One register interface per spec; `registers:`
  names a SystemRDL file or an `.xlsx` register sheet.
- Memories carry the MBIST intent (algorithm, controller group) DFT reads later.
  spec_check validates them: unique instance, macro, depth / width ≥ 1, at least
  one port, port types `rw` / `r` / `w`, and with `mbist.enable` (default true) a
  known `algorithm` and a `group`. A memory without an `mbist` section is a
  warning. gen_collateral checks every spec memory is instantiated in the RTL
  with its macro, every memory macro the RTL instantiates is declared, and the
  macros are in the library tag (`project(lib_config_tag)`).
- Features: `milestone` M1–M4; a feature without tests is a warning. The vPlan
  is written from them (`Feature ID, Feature, Description, Priority, Milestone,
  Tests, Coverage Items, Owner, Status, Waiver`).

YAML 1.2 booleans: only `true` / `false` are booleans (`ON` / `OFF` stay
strings — power states). Paths are relative to the spec file.

### Registers — endianness is mandatory

The register map must declare its bus byte order — the UVM register model
cannot access a multi-byte register through a map without one; gen_regs fails
with `addrmap <name> declares no endianness` otherwise:

```systemrdl
addrmap gcd_regs {
    name = "gcd accelerator registers";
    littleendian = true;                 // APB byte order (the UVM register map needs it)
    default regwidth = 32;
    ...
};
```

### Register sheet (XLS)

One row per field; columns `Register, Offset, Register Name, Register
Description, Field, MSB, LSB, SW, HW, Reset, OnWrite, Flags, Field
Description`, plus an `addrmap` sheet with the columns `name, desc, regwidth,
endian` (`endian` = `little` | `big` — required for the same reason as above).
`spec_tool.py xls2rdl` converts it to SystemRDL (the `registers:` entry may
name the `.xlsx` directly; spec_check converts it to `regs.rdl`, addrmap
`<block>_regs`); `rdl2xls` writes the sheet from SystemRDL.

## 2. Tools and install

All in the CBflow tool container (`cbflow-oss`, tool `rtlcheck` — a Tcl
driver): sv2v, yosys, python3 + lxml from the image; from
`lsf(oss,tools_dir)`:

```bash
global/utils/oss/install_pytools.sh        # systemrdl-compiler, PeakRDL (regblock / uvm / cheader / ipxact / html), openpyxl, z3
global/utils/oss/install_ipxact_schema.sh  # IEEE 1685-2014 XSD (Accellera)
```

The Python packages are exposed as `CBFLOW_OSS_PYTHON` and put on the path of
the helper process only — not `PYTHONPATH` (their antlr4 runtime breaks the
image's nl2bench). Helper: `RTL/utils/oss/spec_tool.py` (`check`, `xls2rdl`,
`rdl2xls`, `regs`, `ipxact`, `sdc`, `upf`, `filelist`, `ports`,
`vplan-init`). Shared Tcl helpers: `global/utils/utilities/v1.0.0/oss_flow_utils.tcl`.

## 3. RTL_SPEC (`RTL_SPEC_rtlcheck_config.tcl`)

`rtl_spec(tool,name) "rtlcheck"` (the flow's default tool). User config
(`workarea/gcd/uc_RTL_SPEC_P3.tcl`):

```tcl
set flow(type)                 "RTL_SPEC"
set flow(design_name)          "gcd"
set flow(run_name)             "p3_spec"
set rtl_spec(tool,name)        "rtlcheck"
set rtl_spec(input,spec)       "<CBFLOW_ROOT>/inputs/opensky/gcd/P3/spec/gcd.spec.yaml"
set project(lib_config_tag)    "OSS2"           ;# memory macros checked against this tag
```

| Stage | Does |
|---|---|
| spec1 | input: `rtl_spec(input,spec)` — the YAML spec |
| spec_check1 | schema + consistency: required fields, port names / directions / widths, clocks and resets on input ports, valid/ready signals declared with the right direction for the mode, all APB4 signals present for the prefix, register source found, power domains, memories (above), RTL sources found, features (milestone M1–M4); normalized `spec.json`; registers → `regs.rdl` (XLS converted) |
| gen_regs1 | PeakRDL: register block SV + package (CPU interface `rtl_spec(oss,regs,cpuif)`, only `apb4-flat`), UVM register model, C header, IP-XACT memory map, HTML; the register RTL through sv2v + yosys; `regs.status` (`GENERATED <n>` / `NONE`). Fails on a map without endianness |
| gen_ipxact1 | IP-XACT 1685-2014 component: ports, bus interfaces (APB4 → `amba.com:AMBA4:APB4:r0p0_0` with port maps; valid/ready → a CBflow bus definition), the memory map, the RTL file set, the model view; schema-validated (`lsf(oss,tools_dir)/rtl_spec(oss,ipxact,schema)`, default `ipxact/1685-2014/index.xsd`) |
| gen_collateral1 | SDC (clocks, IO delays as % of the period, load), UPF (power domains), the RTL filelist (register block + designer RTL), the initial vPlan (`rtl_spec(oss,vplan,generate)`, default `true`), and the RTL top vs the spec's ports and memories (sv2v + yosys; memories / child blocks from the library tag as blackboxes) |
| release_data1 | `SPEC_EXIT` (below) |

**SPEC_EXIT release** (`<project(release,path)>/<phase>/<block>/RTL_SPEC/SPEC_EXIT/`):

| Directory | Content | Read by |
|---|---|---|
| `rtl/` | every RTL source + `<d>.f` at the released paths | RTL_LINT / RTL_CDC / UPF_CHECK (`<FLOW>,rtl`) |
| `spec/` | `<d>.spec.yaml`, `<d>.xml` (IP-XACT), `<d>_regs.rdl`, `<d>_vplan.xlsx` | UPF_CHECK (`UPF_CHECK,spec`), TB_SETUP (`TB_SETUP,spec\|vplan`) |
| `ral/` | `<d>_ral.sv` — the PeakRDL UVM register model | TB_SETUP (`TB_SETUP,ral`) |
| `sdc/`, `upf/` | `<d>.sdc`, `<d>.upf` | RTL_CDC (`RTL_CDC,sdc`), UPF_CHECK (`UPF_CHECK,upf`), SYNTH |
| `data/regs/` | UVM register package, C header, HTML register documentation | software / DV |
| `reports/` | spec_check, regs, ipxact, collateral / ports reports | — |

Exit **SPEC_EXIT** (`global/config/exit/v1.0.0/SPEC_EXIT_config.tcl`): spec
errors 0, IP-XACT schema VALID, RTL port mismatches 0, register collateral
generated.

## 4. RTL checks (RTL_LINT / RTL_CDC / UPF_CHECK)

Overlays `RTL_LINT_verilator_config.tcl`, `RTL_CDC_opencdc_config.tcl`,
`UPF_CHECK_rtlcheck_config.tcl` (select with `<arr>(tool,name)` — the flows'
default tools are the Synopsys ones). Inputs come from the RTL_SPEC release by
tag — `<arr>(input,release_tag) "SPEC_EXIT"` (handshakes `RTL_LINT,rtl`,
`RTL_CDC,rtl|sdc`, `UPF_CHECK,rtl|upf|spec`). Every check writes
`violations_final.csv` (`rule,severity,file,line,message,tool,status`; status
open / waived / excluded) and a sign-off report; helper
`RTL/utils/oss/rtl_check.py`, Tcl helpers `RTL/utils/utilities/v1.0.0/oss_rtl_utils.tcl`.

```tcl
# workarea/gcd/uc_RTL_LINT_P3.tcl (RTL_CDC / UPF_CHECK: same shape)
set flow(type)                  "RTL_LINT"
set flow(run_name)              "p3_lint"
set rtl_lint(tool,name)         "verilator"       ;# rtl_cdc: opencdc, upf_check: rtlcheck
set rtl_lint(input,release_tag) "SPEC_EXIT"
set rtl_lint(oss,waivers)       "<CBFLOW_ROOT>/inputs/opensky/gcd/P3/rtl/gcd_rtl_waivers.yaml"
```

| Flow | Stages | Tools / checks |
|---|---|---|
| RTL_LINT | rtl1 → init1 (sources, memory / child blackbox stubs) → compile1 (slang elaboration) → lint1 (Verilator `--lint-only` SARIF + Verible) → waiver_apply1 → report1 → release_data1 | findings in `oss,generated_globs` (default `*_regs.sv *_regs_pkg.sv` — the PeakRDL block) are `excluded` |
| RTL_CDC | rtl1, sdc1 → init1 → compile1 (yosys-slang) → cdc_setup1 (clocks from the SDC; RTL through sv2v — opencdc reads no SV structs) → cdc_analyze1 (opencdc) → cdc_report1 → waiver_apply1 → signoff1 → release_data1 | blocks opencdc cannot analyse (combinational `always @(*)`) are listed as info (`CDC-SKIPPED-BLOCK`) |
| UPF_CHECK | rtl1, upf1, spec1 → init1 → compile1 (yosys-slang → design.json) → upf_parse1 → upf_check1 → upf_report1 → waiver_apply1 → signoff1 → release_data1 | domains / elements vs the RTL, supplies, connections, primary supplies, port / PST states, isolation on crossings out of switchable domains, domains / supplies vs the spec's power section |

Keys (defaults):

| Key | Default |
|---|---|
| `<arr>(oss,top)` | `""` (= the design name) |
| `rtl_lint(oss,verilator,flags)` | `{-Wall}` |
| `rtl_lint(oss,verible,rules)` / `oss,verible,severity` | `""` / `warning` |
| `rtl_lint(oss,generated_globs)` | `{*_regs.sv *_regs_pkg.sv}` |
| `rtl_cdc(oss,cdc,profile)` | `asic_signoff` |
| `<arr>(oss,waivers)` | `""` (no waivers) |
| `<arr>(oss,signoff,fail_on_warning)` | `true` |

**Waivers** — `<arr>(oss,waivers)`, a YAML file: `rule` / `file` (globs),
optional `line` / `message` (regex), mandatory `reason`, `owner`, `expires`
(YYYY-MM-DD; an expired waiver does not apply and is counted). The pilot file
(`inputs/opensky/gcd/P3/rtl/gcd_rtl_waivers.yaml`):

```yaml
waivers:
  - rule: PINCONNECTEMPTY
    file: gcd.sv
    message: "'dout0'"
    reason: "SRAM port 0 is write-only by design (job push / result write); its read data is unused"
    owner: vmerugu
    expires: 2027-03-31
```

Sign-off: 0 open errors, and 0 open warnings while `oss,signoff,fail_on_warning`
is `true` (the default).

**Exits** (`global/config/exit/v1.0.0/`): `LINT_SIGNOFF` (open errors /
warnings = 0, no expired waivers), `CDC_SIGNOFF`, `UPF_SIGNOFF` (open errors /
warnings = 0).
**Releases**: LINT_SIGNOFF carries `rtl/` (the lint-clean sources + `<d>.f`
at the released paths — SYNTH's `synth(input,rtl_filelist)`); UPF_SIGNOFF
carries `upf/<d>.upf` (handshake `PNR,upf_from_check`); RTL_CDC adds
`reports/cdc_findings.json`; all carry the reports, `violations_final.csv` and
the waiver file under `reports/`.

## 5. SYNTH from the lint-clean RTL (yosys-slang)

`synth(input,rtl_format)` (default `sverilog`) selects the Yosys front end:
`sverilog` → the yosys-slang plugin (`read_slang --top <design>` over the whole
filelist — packages, structs, the PeakRDL register block); `verilog` →
`read_verilog`. Child blocks / memory macros are read as blackboxes first.
`workarea/gcd/uc_SYNTH_yosys_P3.tcl`:

```tcl
set synth(tool,name)           "yosys"
set synth(input,rtl_filelist)  "<release>/P3/gcd/RTL_LINT/LINT_SIGNOFF/rtl/gcd.f"
set synth(input,rtl_format)    "sverilog"
set synth(input,sdc_func_file) "<release>/P3/gcd/RTL_SPEC/SPEC_EXIT/sdc/gcd.sdc"
set synth(input,upf_file)      "<release>/P3/gcd/RTL_SPEC/SPEC_EXIT/upf/gcd.upf"
set project(release,tag)       "P3_SYNTH_v1"
```

## 6. Pilot — gcd P3 (`inputs/opensky/gcd/P3/`)

gcd P3 is a GCD **accelerator IP**: stream mode (valid/ready, as P0–P2) plus a
job queue — software pushes `{a,b}` jobs through `JOB_DATA` into the job SRAM,
`CTRL.start` runs them, the engine fetches each job (job SRAM read port),
computes and writes the result into the result SRAM; `STATUS.irq` on
completion; results read back through `RES_ADDR` / `RES_DATA`. Both
`sky130_sram_1kbyte_1rw1r_32x256_8` macros have real write and read paths
(MBIST-ready, `mbist` intent in the spec).

- `spec/gcd.spec.yaml` — 19 ports, 3 interfaces, 2 memories, features F1–F9
- `spec/gcd_regs.rdl` — CTRL, STATUS, RESULT, OPCOUNT, JOB_DATA, JOB_COUNT, RES_ADDR, RES_DATA, RES_COUNT (`littleendian`)
- `rtl/gcd.sv`, `rtl/gcd_rtl_waivers.yaml`
- `tb/gcd_smoke_tb.sv` — directed smoke test (Verilator `--binary --timing` + the SRAM model): 20 queued jobs + read-back, irq W1C, 10 stream ops, counters
- `tb/uvm/` (DV), `tb/gcd_gls_tb.v` (gate-level, DFT guide)

Runs: `workarea/gcd/uc_RTL_SPEC_P3.tcl`, `uc_RTL_LINT_P3.tcl`, `uc_RTL_CDC_P3.tcl`,
`uc_UPF_CHECK_P3.tcl`, `uc_SYNTH_yosys_P3.tcl` (release `P3_SYNTH_v1`) — stages
1–3 of the [spec-to-GDS chain](../../PD/docs/02-user-guide/spec-to-gds-guide.md)
(`DRY=1 workarea/run_spec2gds.sh gcd P3` lists them).

| Check | Result |
|---|---|
| spec | 19 ports, 3 interfaces, 2 memories, 9 features — 0 errors, 0 warnings |
| registers | 9 registers, regblock + package through sv2v / yosys |
| IP-XACT | 3 bus interfaces + memory map — schema VALID |
| SDC / UPF | identical commands to the hand-written P0–P2 `gcd.func.sdc` / `gcd.upf` |
| RTL ports | 19 / 19 match, 2 / 2 spec memories instantiated |
| XLS round trip | RDL → XLS → RDL regenerates identical register RTL |
| SPEC_EXIT checklist | PASS |
| negative | a missing APB signal / a port width differing from the RTL fail the stage |
| smoke test | PASS; a result-address mutation fails it |
| LINT_SIGNOFF | 24 findings: 21 excluded (generated register block), 3 waived (SRAM port-0 `dout0` unused, result word [31:16]) — 0 open, checklist PASS; without the waivers: FAIL (3 open warnings) |
| CDC_SIGNOFF | single clock — 0 crossings; 9 combinational blocks listed (info) — PASS; an unsynchronized two-clock crossing gives CDC001 error → FAIL |
| UPF_SIGNOFF | 1 domain, 2 supplies, 1 PST — 0 open (2 info: supply ports inserted by PD) — PASS; a domain element not in the RTL → UPF-ELEMENT error |
| SYNTH (slang) | from LINT_SIGNOFF: 1514 cells, 2 SRAM macros kept, 183 scan flops in 2 chains, scandef written |
