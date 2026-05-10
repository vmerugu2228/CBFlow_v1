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
- Testing with `bin/cbflow-test-suite`
- Documentation standards

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
- **File change detection**: Edit input -> auto-retrace downstream (VOV-like)
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

### Test Suite
```bash
bin/cbflow-test-suite --verbose    # 994 tests
bin/cbflow-test-suite --category 2 # RACE DAG/handler tests only
```

---

**Documentation Version**: 2.0.0
