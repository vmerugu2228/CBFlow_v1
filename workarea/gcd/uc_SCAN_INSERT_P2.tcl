set project(name)              "opensky"
set flow(type)                 "SCAN_INSERT"
set flow(design_name)          "gcd"
set flow(run_name)             "p2_scan"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "P2"
set project(release,phase)     "P2"
set project(lib_config_tag)    "OSS2"
set scan_insert(tool,name)          "fault"           ;# SCAN_INSERT_fault_config.tcl (open-source)
set scan_insert(input,release_tag)  "P2_SYNTH_v2"     ;# scan netlist + scan SDC + scandef of the SYNTH release
