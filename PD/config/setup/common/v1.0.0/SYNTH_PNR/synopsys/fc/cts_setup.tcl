# CBflow SYNTH_PNR CTS Stage Setup
# Priority: Level 3

flow_proc_prepend setup_cts {
    handle_info "CTS stage hook: Setting max transition for clock nets"
    # set_max_transition 0.100 -clock_path [all_clocks]
}
