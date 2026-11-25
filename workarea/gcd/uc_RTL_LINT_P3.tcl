set project(name)              "opensky"
set flow(type)                 "RTL_LINT"
set flow(design_name)          "gcd"
set flow(run_name)             "p3_lint"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "false"
set project(phase)             "P3"
set project(release,phase)     "P3"
set project(lib_config_tag)    "OSS2"
set rtl_lint(tool,name)        "verilator"            ;# RTL_LINT_verilator_config.tcl (open-source)
set rtl_lint(input,release_tag) "SPEC_EXIT"    ;# RTL_SPEC release: rtl/<d>.f (+ sdc / upf / spec)
set rtl_lint(oss,waivers)      "/Users/vmerugu/projects/CBflow_clone/inputs/opensky/gcd/P3/rtl/gcd_rtl_waivers.yaml"
