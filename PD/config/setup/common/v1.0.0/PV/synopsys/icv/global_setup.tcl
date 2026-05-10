#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (PV/synopsys/icv)
handle_info "Loading Synopsys ICV tool global setup hooks"
flow_proc_prepend flow_init {
    handle_info "ICV flow init: Tool-specific initialization"
    foreach dir {"logs/icv" "work/icv" "reports/pv" "results/pv"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}
flow_proc_append flow_init { handle_info "ICV flow init: Tool validation complete" }
handle_info "Synopsys ICV tool global setup hooks loaded"
