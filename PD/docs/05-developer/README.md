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

### Adding a Check
```bash
cbflow flow checklist add-check --milestone BTO \
  --name my_check --check-type mandatory \
  --grep-file "report.rpt" --grep-pattern "PASS" --grep-pass-if found
```

### Test Suite
```bash
bin/cbflow-test-suite --verbose    # 994 tests
bin/cbflow-test-suite --category 2 # Makefile/handler tests only
```

---

**Documentation Version**: 2.0.0
