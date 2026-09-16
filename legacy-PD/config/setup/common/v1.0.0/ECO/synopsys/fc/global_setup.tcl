#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (ECO/Synopsys/FC)
handle_info "Loading Synopsys FC tool global setup hooks for ECO"
flow_proc_prepend flow_init {
    handle_info "FC flow init: ECO tool-specific initialization"
    foreach dir {"logs/fc" "work/fc" "reports/eco" "results/eco"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}
flow_proc_append flow_init { handle_info "FC flow init: ECO tool validation complete" }
handle_info "Synopsys FC ECO tool global setup hooks loaded"
