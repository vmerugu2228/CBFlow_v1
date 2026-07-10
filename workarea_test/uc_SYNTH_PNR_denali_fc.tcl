# Filename keeps the `_innovus` suffix only because fixtures.py uses the
# filename pattern uc_<FLOW>_<project>_<vendor-or-tool>.tcl to discover
# project-tagged fixtures. SYNTH_PNR itself only ships a Synopsys FC
# implementation (no Cadence Innovus), so the tool here is fc.
set project(name) "denali"
set project(phase) "LC1"
set flow(type) "SYNTH_PNR"
set flow(design_name) "tom"
set flow(run_name) "denali_fc_test1"
set flow(run_type) "flat"
set flow(test_mode) "true"
set synth_pnr(tool,name) "fc"
set synth_pnr(tool,vendor) "synopsys"
set synth_pnr(input,rtl_filelist) "/Users/vmerugu/projects/CBflow_clone/rtl_denali.list"
set synth_pnr(input,rtl_format) "sverilog"
set synth_pnr(input,sdc_func_file) "/Users/vmerugu/projects/CBflow_clone/denali_func.sdc"
set synth_pnr(input,upf_file) "/Users/vmerugu/projects/CBflow_clone/denali_power.upf"
