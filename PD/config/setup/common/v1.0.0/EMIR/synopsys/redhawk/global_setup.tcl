#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (EMIR/Synopsys/REDHAWK)
handle_info "Loading Synopsys REDHAWK tool global setup hooks"
flow_proc_prepend flow_init {
    handle_info "REDHAWK flow init: Tool-specific initialization"
    foreach dir {"logs/redhawk" "work/redhawk" "reports/emir" "results/emir"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}
flow_proc_append flow_init { handle_info "REDHAWK flow init: Tool validation complete" }
handle_info "Synopsys REDHAWK tool global setup hooks loaded"
