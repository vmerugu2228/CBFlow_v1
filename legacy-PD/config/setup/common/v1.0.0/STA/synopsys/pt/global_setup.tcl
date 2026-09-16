#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (STA/Synopsys/PT)
handle_info "Loading Synopsys PT tool global setup hooks"
flow_proc_prepend flow_init {
    handle_info "PT flow init: Tool-specific initialization"
    foreach dir {"logs/pt" "work/pt" "reports/sta" "results/sta"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}
flow_proc_append flow_init { handle_info "PT flow init: Tool validation complete" }
handle_info "Synopsys PT tool global setup hooks loaded"
