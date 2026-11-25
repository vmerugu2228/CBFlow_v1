set project(name)              "opensky"
set flow(type)                 "ATPG"
set flow(design_name)          "gcd"
set flow(run_name)             "p2_atpg_pre"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "P2"
set project(release,phase)     "P2"
set project(lib_config_tag)    "OSS2"
set atpg(tool,name)            "fault"              ;# ATPG_fault_config.tcl (open-source: Fault cut + Atalanta)
set atpg(pd_phase)             "pre"                ;# netlist + scandef of the SCAN_INSERT release
set atpg(input,release_tag)    "SCAN_INSERT_EXIT"
