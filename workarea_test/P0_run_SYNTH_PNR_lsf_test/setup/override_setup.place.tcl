# Run-level Place Stage Override
flow_proc_append create_placement {
    handle_info "STAGE OVERRIDE: Extra congestion check for place"
}

set synth_pnr(place,congestion_effort) "ultra"
