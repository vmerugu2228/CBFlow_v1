set project(name)              "opensky"
set flow(type)                 "RTL_CDC"
set flow(design_name)          "gcd"
set flow(run_name)             "p3_cdc"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "P3"
set project(release,phase)     "P3"
set project(lib_config_tag)    "OSS2"
set rtl_cdc(tool,name)        "opencdc"            ;# RTL_CDC_opencdc_config.tcl (open-source)
set rtl_cdc(input,release_tag) "SPEC_EXIT"    ;# RTL_SPEC release: rtl/<d>.f (+ sdc / upf / spec)
set rtl_cdc(oss,waivers)      "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/P3/rtl/gcd_rtl_waivers.yaml"
