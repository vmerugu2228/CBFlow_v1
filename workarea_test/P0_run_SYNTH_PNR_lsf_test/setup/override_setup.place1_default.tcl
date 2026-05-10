# Run-level Place1 Node Override (most specific — highest priority)
flow_proc_append create_placement {
    handle_info "NODE OVERRIDE: place1 instance-specific hook"
}

set synth_pnr(place,max_density) "0.75"
