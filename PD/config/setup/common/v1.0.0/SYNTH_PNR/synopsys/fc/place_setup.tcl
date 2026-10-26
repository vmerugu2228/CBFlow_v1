# CBflow SYNTH_PNR Place Stage Setup
# Priority: Level 3

# Customize placement for this technology
flow_proc_append create_placement {
    handle_info "Place stage hook: Running post-placement legalization check"
    # check_legality -verbose
}
