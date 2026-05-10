# Run-level Global Override — HIGHEST PRIORITY (applies to all stages)
# This overrides EVERYTHING from levels 1-4

flow_proc_append start_stage {
    handle_info "RUN OVERRIDE: test_mode=$::flow(test_mode)"
}

# Config variables in override files go to config.tcl
set synth_pnr(compile,high_effort_timing) "true"
