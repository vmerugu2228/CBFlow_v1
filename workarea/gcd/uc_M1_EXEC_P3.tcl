# gcd P3 — M1 regression of the TB_SETUP testbench
set project(name)              "opensky"
set flow(design_name)          "gcd"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"
set project(phase)             "P3"
set project(release,phase)     "P3"
set project(lib_config_tag)    "OSS2"
set flow(type)                 "M1_EXEC"
set flow(run_name)             "p3_m1"
set m1_exec(tool,name)        "verilator"
set m1_exec(input,release_tag) "TB_SETUP_EXIT"      ;# tb/tb.f + vPlan
