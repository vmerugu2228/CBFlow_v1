# Developer Guide

Guide for extending and contributing to CBflow v2.0.0.

## Contents

### [Extending CBflow](extending.md)
- Adding a new flow_proc to an existing stage
- Adding a new exit check (script/grep/file modes)
- Adding a new design flow (node_config, commands, handlers)
- Overriding tool selection in user_config
- Standard command file pattern (153 files follow this)
- Adding email templates and autoppt slides
- RACE engine integration (DAG, SQLite DB, dynamic subnodes)

### [Contributing](contributing.md)
- Directory-based versioning workflow
- Code conventions (TCL, Python)
- Testing with `cbflow test`
- Documentation standards

### [Test Suite Developer Guide](test-suite.md) *(new in v2.1.1)*
The full reference for `cbflow test`:
- Module layout, results collector, reporters (console / JSON / JUnit)
- Static categories 1-9 (Cat 9 is the new dead-code & cross-reference audit)
- E2E checks 1-18 with their bug-class targets
- How to add a new static or e2e check
- CI integration (Jenkins / GitHub Actions / GitLab CI)
- The pseudo-stage / dynamic-subnode allowlist

## Quick Reference

### Command File Pattern
Every command file follows this structure:
```tcl
#!/usr/bin/env tclsh
# Header: env sourcing, utils, tech_config, user_config
set WORK_DIR / REPORTS_DIR / OUTPUTS_DIR
# Source release_utils + release_config (for inputs stages)
flow_proc resolve_inputs { ... }  # First: resolve release tags
flow_proc stage_work { ... }      # Main: EDA tool commands
flow_proc generate_reports { ... } # Last: report redirects
# Source setup hooks (prepend/append/replace)
flow_exec_all
exit
```

### RACE Engine
CBflow v2.0.0 uses the RACE (Run Automation & Control Engine) as its dispatcher. RACE builds the DAG from node_config.tcl at runtime and tracks status in a SQLite database. Key concepts:

- **No Makefile**: RACE reads node_config.tcl directly -- no Makefile generation
- **SQLite DB**: Status tracked in `.race_<uid>.db` (not stamp files)
- **File change detection**: Edit input -> auto-retrace downstream
- **Parallel execution**: Independent subnodes run in parallel
- **Dynamic subnodes**: STA per-corner generated from user_config
- **Custom nodes**: `add-node` and `create-branch` at run level
- **verify-dag**: Validates DAG from node_config without executing

### Adding a Check
```bash
cbflow flow checklist add-check --milestone BTO \
  --name my_check --check-type mandatory \
  --grep-file "report.rpt" --grep-pattern "PASS" --grep-pass-if found
```

### Test Suite (v2.1.1)
```bash
cbflow test                            # static cats 1-9 + e2e all 12 flows
cbflow test --static                   # cats 1-9 only (~0.2s)
cbflow test --e2e --flow SYNTH_PNR     # one flow (~20s)
cbflow test --static --category 9      # the new dead-code audit
cbflow test --ci                       # junit + non-zero exit on fail
bin/cbflow-test-suite                  # back-compat shim → cbflow test --static
```

See [Test Suite Developer Guide](test-suite.md) for the full reference (10 static check categories, 18 e2e checks per flow).

---

**Documentation Version**: 2.1.1
