# Open-Source RTL Flows (vendor `opensource`, project `opensky`)

The front end of spec-to-GDS on open tools. Today: **RTL_SPEC** (block spec →
design collateral). RTL_LINT / RTL_CDC / UPF_CHECK on open tools follow
(spec-to-GDS phase 2); RTL_RDC has no open-source tool.

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
  - {name: csr,  protocol: apb4,        mode: slave,  prefix: s_apb_, registers: gcd_regs.rdl}
io_timing: {input_delay_pct: 10, output_delay_pct: 10, output_load_pf: 0.033}
power:     {upf_version: "2.1", domains: [{name: PD_GCD, elements: [.], supply: {power: VPWR, ground: VGND}, states: {ON: 1.80, OFF: off}}]}
memories:  [{inst: u_sram_req, macro: sky130_sram_1kbyte_1rw1r_32x256_8}]
rtl:       {top: gcd, language: systemverilog, sources: [../rtl/gcd.sv]}
features:  [{id: F1, name: gcd compute, milestone: M1, tests: [...], coverage: [...]}]
```

YAML 1.2 booleans: only `true` / `false` are booleans (`ON` / `OFF` stay
strings — power states). Paths are relative to the spec file.

### Register sheet (XLS)

One row per field; columns `Register, Offset, Register Name, Register
Description, Field, MSB, LSB, SW, HW, Reset, OnWrite, Flags, Field
Description` (+ an optional `addrmap` sheet: name, desc). `spec_tool.py
xls2rdl` converts it to SystemRDL (the `registers:` entry may name the
`.xlsx` directly); `rdl2xls` writes the sheet from SystemRDL.

## 2. Tools and install

All in the CBflow tool container (`cbflow-oss`, tool `rtlcheck` — a Tcl
driver): sv2v, yosys, python3 + lxml from the image; from
`lsf(oss,tools_dir)`:

```bash
global/utils/oss/install_pytools.sh        # systemrdl-compiler, PeakRDL (regblock / uvm / cheader / ipxact / html), openpyxl
global/utils/oss/install_ipxact_schema.sh  # IEEE 1685-2014 XSD (Accellera)
```

The Python packages are exposed as `CBFLOW_OSS_PYTHON` and put on the path of
the helper process only — not `PYTHONPATH` (their antlr4 runtime breaks the
image's nl2bench). Helper: `RTL/utils/oss/spec_tool.py` (`check`, `xls2rdl`,
`rdl2xls`, `regs`, `ipxact`, `sdc`, `upf`, `filelist`, `ports`,
`vplan-init`). Shared Tcl helpers: `global/utils/utilities/v1.0.0/oss_flow_utils.tcl`.

## 3. RTL_SPEC (`RTL_SPEC_rtlcheck_config.tcl`)

| Stage | Does |
|---|---|
| spec1 | input: `rtl_spec(input,spec)` — the YAML spec |
| spec_check1 | schema + consistency: required fields, port names / directions / widths, clocks and resets on input ports, valid/ready signals declared with the right direction for the mode, all APB4 signals present for the prefix, register source found, power domains, RTL sources found, features (milestone M1–M4); normalized `spec.json`; registers → `regs.rdl` (XLS converted) |
| gen_regs1 | PeakRDL: register block SV + package (CPU interface `rtl_spec(oss,regs,cpuif)`, apb4-flat), UVM register model, C header, IP-XACT memory map, HTML; the register RTL through sv2v + yosys; `regs.status` (`GENERATED <n>` / `NONE`) |
| gen_ipxact1 | IP-XACT 1685-2014 component: ports, bus interfaces (APB4 → `amba.com:AMBA4:APB4:r0p0_0` with port maps; valid/ready → a CBflow bus definition), the memory map, the RTL file set, the model view; schema-validated (`lsf(oss,tools_dir)/rtl_spec(oss,ipxact,schema)`) |
| gen_collateral1 | SDC (clocks, IO delays as % of the period, load), UPF (power domains), the RTL filelist (register block + designer RTL), the initial vPlan (`rtl_spec(oss,vplan,generate)`), and the RTL top vs the spec's ports (sv2v + yosys; memories / child blocks from the library tag as blackboxes) |
| release_data1 | `SPEC_EXIT`: `rtl/` (every source + `<d>.f` at the released paths — handshake `RTL_LINT,rtl`), `spec/` (YAML, IP-XACT, SystemRDL, vPlan), `sdc/`, `upf/`, `data/regs/` (UVM RAL, C header, HTML), reports |

Exit **SPEC_EXIT** (`global/config/exit/v1.0.0/SPEC_EXIT_config.tcl`): spec
errors 0, IP-XACT schema VALID, RTL port mismatches 0, register collateral
generated.

## 4. Pilot — gcd P3 (`inputs/opensky/gcd/P3/`)

`spec/gcd.spec.yaml`, `spec/gcd_regs.rdl` (CTRL irq_en / cnt_clr, STATUS
busy / done / irq W1C, RESULT, OPCOUNT), `rtl/gcd.sv` (P2 + APB register block
+ `irq`). Run: `workarea/gcd/uc_RTL_SPEC_P3.tcl`.

| Check | Result |
|---|---|
| spec | 19 ports, 3 interfaces, 6 features — 0 errors, 0 warnings |
| registers | 4 registers, regblock + package through sv2v / yosys |
| IP-XACT | 3 bus interfaces + memory map — schema VALID |
| SDC / UPF | identical commands to the hand-written P0–P2 `gcd.func.sdc` / `gcd.upf` |
| RTL ports | 19 / 19 match |
| XLS round trip | RDL → XLS → RDL regenerates identical register RTL |
| SPEC_EXIT checklist | PASS |
| negative | a missing APB signal / a port width differing from the RTL fail the stage |
