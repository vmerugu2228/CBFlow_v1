#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (FCFP/cadence/innovus)
handle_info "Loading innovus tool global setup hooks"

flow_proc_prepend flow_init {
    handle_info "innovus flow init prepend: Tool-specific initialization"
    foreach dir {"logs/innovus" "work/innovus" "reports/fcfp" "results/fcfp"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}

flow_proc_append flow_init {
    handle_info "innovus flow init append: Tool validation complete"
}

handle_info "innovus tool global setup hooks loaded"
