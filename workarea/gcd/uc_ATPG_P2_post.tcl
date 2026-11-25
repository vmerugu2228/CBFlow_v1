set project(name)              "opensky"
set flow(type)                 "ATPG"
set flow(design_name)          "gcd"
set flow(run_name)             "p2_atpg_post"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "P2"
set project(release,phase)     "P2"
set project(lib_config_tag)    "OSS2"
set atpg(tool,name)                 "fault"              ;# ATPG_fault_config.tcl (open-source)
set atpg(pd_phase)                  "post"               ;# post-route netlist
set atpg(input,netlist_release_tag) "BTO"                ;# PNR BTO netlist
set atpg(input,scandef_release_tag) "SCAN_INSERT_EXIT"   ;# chain reference
