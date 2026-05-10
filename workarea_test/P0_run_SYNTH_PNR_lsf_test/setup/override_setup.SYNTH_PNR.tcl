# Run-level SYNTH_PNR Flow Override
flow_proc_append setup_technology {
    handle_info "FLOW OVERRIDE: SYNTH_PNR-specific timing optimization"
}

set synth_pnr(compile,qor_mode) "timing"
