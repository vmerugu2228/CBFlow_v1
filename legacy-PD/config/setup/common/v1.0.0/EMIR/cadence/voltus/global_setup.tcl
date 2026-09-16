#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (EMIR/cadence/voltus)
handle_info "Loading voltus tool global setup hooks"

flow_proc_prepend flow_init {
    handle_info "voltus flow init prepend: Tool-specific initialization"
    foreach dir {"logs/voltus" "work/voltus" "reports/emir" "results/emir"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}

flow_proc_append flow_init {
    handle_info "voltus flow init append: Tool validation complete"
}

handle_info "voltus tool global setup hooks loaded"
