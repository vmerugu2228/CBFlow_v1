#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (SYNTH/synopsys/fc)
handle_info "Loading Synopsys FC tool global setup hooks"
flow_proc_prepend flow_init {
    handle_info "FC flow init: Tool-specific initialization"
    foreach dir {"logs/fc" "work/fc" "reports/synth" "results/synth"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}
flow_proc_append flow_init { handle_info "FC flow init: Tool validation complete" }
handle_info "Synopsys FC tool global setup hooks loaded"
