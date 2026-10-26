# CBflow SYNTH_PNR Flow Setup — applies to ALL stages in SYNTH_PNR
# Priority: Level 2

# Set FC-specific global options for SYNTH_PNR
flow_proc_prepend setup_technology {
    handle_info "SYNTH_PNR flow setup: Enabling unified flow options"
    # set_app_options -name design.multibit.enable -value true
}
