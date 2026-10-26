#!/usr/bin/env tclsh
# CBFlow - Tool Global Setup Hooks (POPT/Synopsys/PT)
handle_info "Loading Synopsys PT tool global setup hooks for POPT"
flow_proc_prepend flow_init {
    handle_info "PT flow init: POPT tool-specific initialization"
    foreach dir {"logs/pt" "work/pt" "reports/popt" "results/popt"} { if {![file exists $dir]} { file mkdir $dir } }
}
flow_proc_append flow_init { handle_info "PT flow init: POPT tool validation complete" }
handle_info "Synopsys PT POPT tool global setup hooks loaded"
