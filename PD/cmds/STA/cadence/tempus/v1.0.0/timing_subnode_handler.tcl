#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — timing Subnode Handler (Cadence Tempus)
# Subnodes: setup, run, validate, finish, dynamic, <scenario> (MMMC)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "timing"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(TEMPUS_VERSION)] ? $::env(TEMPUS_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/cadence/tempus/$_tool_ver/timing_tempus.tcl"

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        puts "INFO: $stage_name setup completed"
    }
    "run" {
        puts "INFO: $stage_name run..."
        set _tool [expr {[info exists ::sta(tool,name)] ? $::sta(tool,name) : "tempus"}]
        handler_run $run_dir $::flow_type $node_name $stage_name $cmd_file $test_mode $_tool
    }
    "validate" {
        puts "INFO: $stage_name validate..."
        handler_validate $run_dir $::flow_type $node_name $stage_name $test_mode
        puts "INFO: $stage_name validate completed"
    }
    "finish" {
        puts "INFO: $stage_name finish..."
        handler_finish $run_dir $::flow_type $node_name $stage_name
        puts "INFO: $stage_name finish completed"
    }
    "dynamic" {
        # Resolve MMMC scenarios and run per-scenario timing
        puts "INFO: $stage_name dynamic — resolving MMMC scenarios..."

        set mmmc_config_file "$::env(CONFIG_ROOT)/project/$::env(CBFLOW_PROJECT_NAME)/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $mmmc_config_file]} { source $mmmc_config_file }

        set setup_scenarios {}
        set hold_scenarios {}

        if {[info exists ::sta(mmmc,setup_scenarios)] && $::sta(mmmc,setup_scenarios) ne ""} {
            set setup_scenarios $::sta(mmmc,setup_scenarios)
        } elseif {[info exists mmmc_scenario_sets] && [array exists mmmc_scenario_sets]} {
            set sset [expr {[info exists ::sta(mmmc,scenario_set)] ? $::sta(mmmc,scenario_set) : "sta_signoff"}]
            if {$sset ne "custom" && [info exists mmmc_scenario_sets($sset)]} {
                array set _ss $mmmc_scenario_sets($sset)
                if {[info exists _ss(scenarios)]} { set setup_scenarios $_ss(scenarios) }
            }
        }
        if {[info exists ::sta(mmmc,hold_scenarios)] && $::sta(mmmc,hold_scenarios) ne ""} {
            set hold_scenarios $::sta(mmmc,hold_scenarios)
        }

        set all_scenarios [lsort -unique [concat $setup_scenarios $hold_scenarios]]
        if {[llength $all_scenarios] == 0} {
            puts "ERROR: No MMMC scenarios found — check mmmc_config.tcl in project config"
            exit 1
        }

        puts "INFO: MMMC scenarios to run ([llength $all_scenarios]):"
        puts "INFO:   Setup: $setup_scenarios"
        puts "INFO:   Hold:  $hold_scenarios"

        set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir $_work_dir
        file mkdir "$run_dir/reports/sta"

        set _scenario_handler "$::env(FLOW_DIR)/cmds/STA/cadence/tempus/$_tool_ver/timing_scenario_handler.tcl"

        foreach scenario $all_scenarios {
            puts "INFO: -- Scenario: $scenario --"
            if {$test_mode} {
                if {[file exists $_scenario_handler]} {
                    catch {exec tclsh $_scenario_handler $scenario $run_dir} result
                    puts $result
                } else {
                    puts "INFO: \[TEST MODE\] Scenario $scenario — creating stubs"
                    set rpt [open "$run_dir/reports/sta/timing_${scenario}_summary.rpt" "w"]
                    puts $rpt "# Test mode: $scenario"
                    puts $rpt "Setup WNS: 0.000ns  Hold WNS: 0.000ns"
                    close $rpt
                }
            } else {
                if {[file exists $_scenario_handler]} {
                    if {[catch {exec tclsh $_scenario_handler $scenario $run_dir} result]} {
                        puts "ERROR: Scenario $scenario failed: $result"; exit 1
                    }
                    puts $result
                } else {
                    puts "ERROR: Scenario handler not found: $_scenario_handler"; exit 1
                }
            }
        }
        puts "INFO: $stage_name dynamic completed — [llength $all_scenarios] scenarios processed"
    }
    default {
        # Per-scenario MMMC subnode (e.g., func_ss_0p80v_rcmax_125c)
        set scenario $subnode_name
        puts "INFO: timing scenario: $scenario"

        set _mmmc_cfg "$::env(CONFIG_ROOT)/project/$::env(CBFLOW_PROJECT_NAME)/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $_mmmc_cfg]} { source $_mmmc_cfg }

        if {![info exists analysis_views($scenario)]} {
            puts "ERROR: Scenario '$scenario' not found in analysis_views"
            exit 1
        }
        array set _sv $analysis_views($scenario)

        set _corner_dir "$run_dir/work/$::flow_type/$node_name/$scenario"
        set _run_dir "$_corner_dir/run"
        set _reports_dir "$_corner_dir/reports"
        file mkdir $_run_dir
        file mkdir $_reports_dir

        # Resolve SPEF file for this RC corner
        set _spef_file ""
        set _spef_manifest "$run_dir/work/$::flow_type/$node_name/setup/spef_manifest.tcl"
        if {[file exists $_spef_manifest]} {
            source $_spef_manifest
            if {[info exists spef_map($_sv(rc_corner))]} {
                set _spef_file $spef_map($_sv(rc_corner))
            }
        }

        # Resolve SDC file
        set _sdc_dir "$run_dir/work/$::flow_type/sdc1/sdc"
        set _sdc_file "$_sdc_dir/$_sv(constraint_file)"

        # Resolve view definition file
        set _vd_file "$::env(FLOW_DIR)/config/project/$::env(CBFLOW_PROJECT_NAME)/$::env(FLOW_CONFIG_VERSION)/mmmc_view_definition.tcl"

        # ── Generate per-corner Tempus command file ──
        set _cmd_file "$_run_dir/${scenario}.tcl"
        set _fh [open $_cmd_file "w"]

        puts $_fh "#!/usr/bin/env tclsh"
        puts $_fh "# ================================================================"
        puts $_fh "# Tempus STA — Scenario: $scenario"
        puts $_fh "# Generated by CBflow timing subnode handler"
        puts $_fh "# Directly sourceable in Tempus"
        puts $_fh "# ================================================================"
        puts $_fh ""

        # Section 1: Bootstrap + config
        puts $_fh "# ── Config ──"
        puts $_fh "set run_dir \"$run_dir\""
        puts $_fh "source \"\$run_dir/.run.cbflow.tcl\""
        puts $_fh "source \"\$::env(FLOW_DIR)/utils/utilities/\$::env(UTILITIES_VERSION)/utils.tcl\""
        puts $_fh "source \"\$run_dir/work/STA/$node_name/run/config.tcl\""
        puts $_fh ""

        # Section 2: Corner-specific variables
        puts $_fh "# ── Scenario Variables ──"
        puts $_fh "set SCENARIO       \"$scenario\""
        puts $_fh "set CORNER         \"$_sv(corner)\""
        puts $_fh "set MODE           \"$_sv(mode)\""
        puts $_fh "set VOLTAGE        \"$_sv(voltage)\""
        puts $_fh "set TEMPERATURE    \"$_sv(temperature)\""
        puts $_fh "set RC_CORNER      \"$_sv(rc_corner)\""
        puts $_fh "set LIB_SET        \"$_sv(lib_set_ref)\""
        puts $_fh "set DESIGN_NAME    \"$::flow(design_name)\""
        puts $_fh "set SDC_FILE       \"$_sdc_file\""
        puts $_fh "set SPEF_FILE      \"$_spef_file\""
        puts $_fh "set REPORTS_DIR    \"$_reports_dir\""
        puts $_fh ""

        # Section 3: Threading
        puts $_fh "# ── Threading ──"
        puts $_fh "if {\[info exists sta(common,cpu_count)\] && \$sta(common,cpu_count) ne \"\"} {"
        puts $_fh "    set_multi_cpu_usage -localCpu \$sta(common,cpu_count)"
        puts $_fh "}"
        puts $_fh ""

        # Section 4: Read LEFs
        puts $_fh "# ── LEF ──"
        puts $_fh "read_lib -lef \$tech(lef_tech)"
        puts $_fh "foreach _lef \$tech(\$project(track_variant),lef) {"
        puts $_fh "    read_lib -lef \$_lef"
        puts $_fh "}"
        puts $_fh ""

        # Section 5: Read timing libs for this corner
        puts $_fh "# ── Timing Libraries (corner: \$LIB_SET) ──"
        puts $_fh "foreach _lib \$tech(\$project(track_variant),lib,\$LIB_SET,timing) {"
        puts $_fh "    read_lib \$_lib"
        puts $_fh "}"
        puts $_fh ""

        # Section 6: Read design
        puts $_fh "# ── Design ──"
        puts $_fh "read_verilog \$sta(input,netlist)"
        puts $_fh "set_top_module \$DESIGN_NAME -ignore_undefined_cell"
        puts $_fh ""

        # Section 7: Read DEF
        puts $_fh "# ── DEF ──"
        puts $_fh "if {\[info exists sta(input,def_file)\] && \$sta(input,def_file) ne \"\"} {"
        puts $_fh "    read_def \$sta(input,def_file)"
        puts $_fh "}"
        puts $_fh ""

        # Section 8: Read SDC
        puts $_fh "# ── Constraints ──"
        puts $_fh "read_sdc \$SDC_FILE"
        puts $_fh ""

        # Section 9: Read SPEF
        puts $_fh "# ── Parasitics ──"
        puts $_fh "if {\$SPEF_FILE ne \"\"} {"
        puts $_fh "    read_spef \$SPEF_FILE"
        puts $_fh "}"
        puts $_fh ""

        # Section 10: SI and delay cal mode
        puts $_fh "# ── SI & Analysis Mode ──"
        puts $_fh "if {\[info exists sta(common,si_aware)\] && \$sta(common,si_aware) eq \"true\"} {"
        puts $_fh "    set_delay_cal_mode -SIAware true"
        puts $_fh "    if {\[info exists sta(common,si_glitch_report)\]} {"
        puts $_fh "        set_si_mode -enable_glitch_report \$sta(common,si_glitch_report)"
        puts $_fh "    }"
        puts $_fh "    if {\[info exists sta(common,si_glitch_propagation)\]} {"
        puts $_fh "        set_si_mode -enable_glitch_propagation \$sta(common,si_glitch_propagation)"
        puts $_fh "    }"
        puts $_fh "}"
        puts $_fh ""

        # Section 10: Timing derates (OCV)
        puts $_fh "# ── Timing Derates ──"
        puts $_fh "if {\[info exists sta(timing,derate_early_data)\]} {"
        puts $_fh "    set_timing_derate -cell_delay -data  -early \$sta(timing,derate_early_data)"
        puts $_fh "    set_timing_derate -net_delay  -data  -early \$sta(timing,derate_early_data)"
        puts $_fh "}"
        puts $_fh "if {\[info exists sta(timing,derate_late_data)\]} {"
        puts $_fh "    set_timing_derate -cell_delay -data  -late  \$sta(timing,derate_late_data)"
        puts $_fh "    set_timing_derate -net_delay  -data  -late  \$sta(timing,derate_late_data)"
        puts $_fh "}"
        puts $_fh "if {\[info exists sta(timing,derate_early_clock)\]} {"
        puts $_fh "    set_timing_derate -cell_delay -clock -early \$sta(timing,derate_early_clock)"
        puts $_fh "    set_timing_derate -net_delay  -clock -early \$sta(timing,derate_early_clock)"
        puts $_fh "}"
        puts $_fh "if {\[info exists sta(timing,derate_late_clock)\]} {"
        puts $_fh "    set_timing_derate -cell_delay -clock -late  \$sta(timing,derate_late_clock)"
        puts $_fh "    set_timing_derate -net_delay  -clock -late  \$sta(timing,derate_late_clock)"
        puts $_fh "}"
        puts $_fh ""

        # Section 11: Run timing
        puts $_fh "# ── Update Timing ──"
        puts $_fh "update_timing -full"
        puts $_fh ""

        # Section 13: Reports
        puts $_fh "# ════════════════════════════════════════════════════════════"
        puts $_fh "# REPORTS"
        puts $_fh "# ════════════════════════════════════════════════════════════"
        puts $_fh "file mkdir \$REPORTS_DIR"
        puts $_fh ""

        # Full design timing
        puts $_fh "# ── Full Design Timing ──"
        puts $_fh "report_timing -late  -max_paths \$sta(timing,max_paths) -nworst \$sta(timing,nworst) -path_type full_clock -net \\"
        puts $_fh "    > \$REPORTS_DIR/setup.rpt"
        puts $_fh "report_timing -early -max_paths \$sta(timing,max_paths) -nworst \$sta(timing,nworst) -path_type full_clock -net \\"
        puts $_fh "    > \$REPORTS_DIR/hold.rpt"
        puts $_fh ""

        # Per clock group
        puts $_fh "# ── Per Clock Group ──"
        puts $_fh "foreach _clk \[all_clocks\] {"
        puts $_fh "    set _cn \[get_object_name \$_clk\]"
        puts $_fh "    catch {"
        puts $_fh "        report_timing -late  -max_paths \$sta(timing,max_paths) -nworst \$sta(timing,nworst) \\"
        puts $_fh "            -path_type full_clock -net -from \[all_registers -clock \$_cn\] \\"
        puts $_fh "            > \$REPORTS_DIR/setup_clk_\${_cn}.rpt"
        puts $_fh "        report_timing -early -max_paths \$sta(timing,max_paths) -nworst \$sta(timing,nworst) \\"
        puts $_fh "            -path_type full_clock -net -from \[all_registers -clock \$_cn\] \\"
        puts $_fh "            > \$REPORTS_DIR/hold_clk_\${_cn}.rpt"
        puts $_fh "    }"
        puts $_fh "}"
        puts $_fh ""

        # IO path groups
        puts $_fh "# ── IO Path Groups ──"
        puts $_fh "catch {"
        puts $_fh "    report_timing -late  -max_paths \$sta(timing,max_paths) -nworst \$sta(timing,nworst) \\"
        puts $_fh "        -path_type full_clock -net -from \[all_inputs\]  > \$REPORTS_DIR/setup_input.rpt"
        puts $_fh "    report_timing -late  -max_paths \$sta(timing,max_paths) -nworst \$sta(timing,nworst) \\"
        puts $_fh "        -path_type full_clock -net -to \[all_outputs\]   > \$REPORTS_DIR/setup_output.rpt"
        puts $_fh "    report_timing -early -max_paths \$sta(timing,max_paths) -nworst \$sta(timing,nworst) \\"
        puts $_fh "        -path_type full_clock -net -from \[all_inputs\]  > \$REPORTS_DIR/hold_input.rpt"
        puts $_fh "    report_timing -early -max_paths \$sta(timing,max_paths) -nworst \$sta(timing,nworst) \\"
        puts $_fh "        -path_type full_clock -net -to \[all_outputs\]   > \$REPORTS_DIR/hold_output.rpt"
        puts $_fh "}"
        puts $_fh ""

        # Violations
        puts $_fh "# ── Violations ──"
        puts $_fh "report_timing -path_type end_slack_only -max_slack \$sta(timing,max_slack) \\"
        puts $_fh "    > \$REPORTS_DIR/setup_viol.rpt"
        puts $_fh "report_timing -path_type end_slack_only -max_slack \$sta(timing,max_slack) -early \\"
        puts $_fh "    > \$REPORTS_DIR/hold_viol.rpt"
        puts $_fh ""

        # DRV — max_transition, max_capacitance, max_fanout
        puts $_fh "# ── DRV Violations (transition / capacitance / fanout) ──"
        puts $_fh "report_constraint -all_violators                          > \$REPORTS_DIR/all_violators.rpt"
        puts $_fh "report_constraint -all_violators -max_transition          > \$REPORTS_DIR/drv_max_tran.rpt"
        puts $_fh "report_constraint -all_violators -max_capacitance         > \$REPORTS_DIR/drv_max_cap.rpt"
        puts $_fh "report_constraint -all_violators -max_fanout              > \$REPORTS_DIR/drv_max_fanout.rpt"
        puts $_fh ""

        # QoR, bottleneck, histogram
        puts $_fh "# ── QoR & Analysis ──"
        puts $_fh "report_qor                                               > \$REPORTS_DIR/qor.rpt"
        puts $_fh "report_bottleneck -max_paths \$sta(timing,max_paths)      > \$REPORTS_DIR/bottleneck.rpt"
        puts $_fh "report_timing -path_type histogram                        > \$REPORTS_DIR/histogram.rpt"
        puts $_fh ""

        # Noise / SI
        puts $_fh "# ── Noise ──"
        puts $_fh "if {\[info exists sta(common,si_aware)\] && \$sta(common,si_aware) eq \"true\"} {"
        puts $_fh "    report_noise                                          > \$REPORTS_DIR/noise.rpt"
        puts $_fh "    report_si_bottleneck -max_paths \$sta(timing,max_paths) > \$REPORTS_DIR/si_bottleneck.rpt"
        puts $_fh "}"
        puts $_fh ""

        # Summary + coverage + check_design
        puts $_fh "# ── Summary ──"
        puts $_fh "report_timing -path_type summary_slack_only -late          > \$REPORTS_DIR/summary.rpt"
        puts $_fh "report_timing -path_type summary_slack_only -early        >> \$REPORTS_DIR/summary.rpt"
        puts $_fh "report_analysis_coverage                                  > \$REPORTS_DIR/coverage.rpt"
        puts $_fh "report_clocks                                             > \$REPORTS_DIR/clocks.rpt"
        puts $_fh "report_annotated_parasitics                               > \$REPORTS_DIR/annotated_parasitics.rpt"
        puts $_fh "check_design -noHtml -outfile \$REPORTS_DIR/check_design.rpt"
        puts $_fh ""

        # Outputs (SDF / ETM — optional)
        puts $_fh "# ── Outputs ──"
        puts $_fh "set _outputs_dir \[file dirname \$REPORTS_DIR\]/outputs"
        puts $_fh "file mkdir \$_outputs_dir"
        puts $_fh ""
        puts $_fh "# SDF generation (sta(sdf,enable) = true)"
        puts $_fh "if {\[info exists sta(sdf,enable)\] && \$sta(sdf,enable) eq \"true\"} {"
        puts $_fh "    set _sdf_file \"\$_outputs_dir/\${DESIGN_NAME}.\${SCENARIO}.sdf.gz\""
        puts $_fh "    write_sdf -version \$sta(sdf,version) \$_sdf_file"
        puts $_fh "    puts \"INFO: SDF written: \$_sdf_file\""
        puts $_fh "}"
        puts $_fh ""
        puts $_fh "# ETM generation (sta(etm,enable) = true)"
        puts $_fh "if {\[info exists sta(etm,enable)\] && \$sta(etm,enable) eq \"true\"} {"
        puts $_fh "    set _etm_file \"\$_outputs_dir/\${DESIGN_NAME}.\${SCENARIO}.lib\""
        puts $_fh "    write_timing_model -output_library \$_etm_file"
        puts $_fh "    puts \"INFO: ETM written: \$_etm_file\""
        puts $_fh "}"
        puts $_fh ""

        puts $_fh "puts \"INFO: Scenario \$SCENARIO completed\""
        puts $_fh ""

        close $_fh
        puts "INFO: Generated command file: $_cmd_file"

        # ── Execute or stub ──
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Scenario $scenario"
            puts "INFO:   Corner=$_sv(corner) Mode=$_sv(mode) V=$_sv(voltage) T=$_sv(temperature)"
            puts "INFO:   Command: $_cmd_file"
            set rpt [open "$_reports_dir/timing_${scenario}_summary.rpt" "w"]
            puts $rpt "# Test mode: $scenario"
            puts $rpt "Setup WNS: 0.000ns  Hold WNS: 0.000ns"
            close $rpt
        } else {
            set _tool [expr {[info exists ::sta(tool,name)] ? $::sta(tool,name) : "tempus"}]
            handler_run $run_dir $::flow_type $node_name $scenario $_cmd_file false $_tool
        }
        puts "INFO: timing scenario $scenario done"
    }
}
