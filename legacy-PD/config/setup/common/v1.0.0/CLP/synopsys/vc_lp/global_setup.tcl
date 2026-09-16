#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (CLP/Synopsys/VC_LP)
handle_info "Loading Synopsys VC_LP tool global setup hooks"
flow_proc_prepend flow_init {
    handle_info "VC_LP flow init: Tool-specific initialization"
    foreach dir {"logs/vc_lp" "work/vc_lp" "reports/clp" "results/clp"} {
        if {![file exists $dir]} { file mkdir $dir }
    }
}
flow_proc_append flow_init { handle_info "VC_LP flow init: Tool validation complete" }
handle_info "Synopsys VC_LP tool global setup hooks loaded"
