set project(name) "bumblebee"
set project(phase) "LC1"
set flow(type) "SYNTH"
set flow(design_name) "cpu_core"
set flow(run_name) "handoff_consumer"
set flow(test_mode) "true"
set synth(tool,name) "genus"
set synth(tool,vendor) "cadence"
# ── Cross-discipline tag-based input resolution ──────────────────────────────
# The handshake map entry `flow_input_handshake(SYNTH,rtl_from_lint)` points
# at `RTL_LINT netlist "${design_name}.v"`. Setting `rtl_from_lint_release_tag`
# below should cause resolve_single_from_tag to populate
# $synth(input,rtl_from_lint) with the staged file. Prove: compare the
# resolved value vs. $release_base/$tag/netlist/cpu_core.v.
set synth(input,rtl_release_tag)   "L0_RTL_SIGNOFF"
set synth(input,sdc_func_file)     "/Users/vmerugu/projects/CBflow_clone/inputs/cpu_core.func.sdc"
set synth(input,upf_file)          "/Users/vmerugu/projects/CBflow_clone/inputs/cpu_core.upf"
