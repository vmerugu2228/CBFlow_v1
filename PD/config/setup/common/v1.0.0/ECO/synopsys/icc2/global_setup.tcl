#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (ECO/synopsys/icc2)
handle_info "Loading icc2 tool global setup hooks"

flow_proc_prepend flow_init {
    handle_info "icc2 flow init prepend: Tool-specific initialization"
    foreach dir {"logs/icc2" "work/icc2" "reports/eco" "results/eco"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}

flow_proc_append flow_init {
    handle_info "icc2 flow init append: Tool validation complete"
}

handle_info "icc2 tool global setup hooks loaded"
