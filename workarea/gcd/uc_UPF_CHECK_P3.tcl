set project(name)              "opensky"
set flow(type)                 "UPF_CHECK"
set flow(design_name)          "gcd"
set flow(run_name)             "p3_upf"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"
set project(phase)             "P3"
set project(release,phase)     "P3"
set project(lib_config_tag)    "OSS2"
set upf_check(tool,name)        "rtlcheck"            ;# UPF_CHECK_rtlcheck_config.tcl (open-source)
set upf_check(input,release_tag) "SPEC_EXIT"    ;# RTL_SPEC release: rtl/<d>.f (+ sdc / upf / spec)
set upf_check(oss,waivers)      "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/P3/rtl/gcd_rtl_waivers.yaml"
