#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — timing Subnode Handler (Synopsys PT)
# Subnodes emitted by _resolve_dynamic_subnodes(): setup, <per-MMMC-scenario>,
#                                                  validate, finish.
# The legacy `run` static-scenario subnode is retired (dynamic resolution
# takes its place). `dynamic` is kept for direct-invoke compatibility.
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "timing"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(PT_VERSION)] ? $::env(PT_VERSION) : "v1.0.0"}]

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        puts "INFO: $stage_name setup completed"
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
        # Resolve MMMC scenarios and dispatch each as a per-scenario invocation
        # of this same handler. The engine also expands `dynamic` into individual
        # per-scenario subnodes via _resolve_dynamic_subnodes(); this branch
        # covers direct CLI invocation ("cbflow run node --subnode dynamic").
        puts "INFO: $stage_name dynamic — resolving MMMC scenarios..."
        set mmmc_cfg "$::env(CONFIG_ROOT)/project/$::env(CBFLOW_PROJECT_NAME)/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $mmmc_cfg]} { uplevel #0 [list source $mmmc_cfg] }

        set setup_scenarios {}
        set hold_scenarios {}
        if {[info exists ::sta(mmmc,setup_scenarios)] && $::sta(mmmc,setup_scenarios) ne ""} {
            set setup_scenarios $::sta(mmmc,setup_scenarios)
        }
        if {[info exists ::sta(mmmc,hold_scenarios)] && $::sta(mmmc,hold_scenarios) ne ""} {
            set hold_scenarios $::sta(mmmc,hold_scenarios)
        }
        set all_scenarios [lsort -unique [concat $setup_scenarios $hold_scenarios]]
        if {[llength $all_scenarios] == 0} {
            puts "ERROR: No MMMC scenarios found — check sta(mmmc,setup_scenarios) and sta(mmmc,hold_scenarios)"
            exit 1
        }
        puts "INFO: MMMC scenarios: [llength $all_scenarios]"

        file mkdir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir "$run_dir/reports/sta"

        foreach scenario $all_scenarios {
            puts "INFO: -- Scenario: $scenario --"
            if {[catch {exec tclsh [info script] $scenario $run_dir $node_name >@ stdout 2>@ stderr} result]} {
                puts "ERROR: Scenario $scenario failed: $result"
                exit 1
            }
        }
        puts "INFO: $stage_name dynamic completed — [llength $all_scenarios] scenarios processed"
    }
    default {
        # Per-scenario MMMC subnode (e.g., func_ss_0p76v_rcmax_150c)
        set scenario $subnode_name
        puts "INFO: $stage_name scenario: $scenario"

        set mmmc_cfg "$::env(CONFIG_ROOT)/project/$::env(CBFLOW_PROJECT_NAME)/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $mmmc_cfg]} { uplevel #0 [list source $mmmc_cfg] }

        # analysis_views is auto-generated from PVT building blocks in
        # mmmc_config.tcl. Test fixtures sometimes name scenarios that fall
        # outside the auto-generated set — in test_mode we still produce a
        # stub report so downstream stages have artifacts to consume. Only
        # error in real runs where the scenario is genuinely unresolvable.
        set _have_view [info exists ::analysis_views($scenario)]
        if {!$_have_view && !$test_mode} {
            puts "ERROR: Scenario '$scenario' not found in analysis_views (mmmc_config.tcl)"
            exit 1
        }
        if {$_have_view} {
            array set _sv $::analysis_views($scenario)
        } else {
            # Test-mode fallback: fabricate minimal per-scenario metadata
            # so the rest of the flow can proceed and stub reports get written.
            array set _sv [list corner unknown mode unknown voltage "" \
                                temperature "" rc_corner unknown \
                                lib_set_ref "" constraint_file ""]
        }

        set _corner_dir "$run_dir/work/$::flow_type/$node_name/$scenario"
        set _run_dir_s  "$_corner_dir/run"
        set _reports_dir "$_corner_dir/reports"
        file mkdir $_run_dir_s
        file mkdir $_reports_dir
        file mkdir "$run_dir/reports/sta"

        # Resolve SPEF for this RC corner (from setup manifest if produced upstream)
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

        # ── Generate per-scenario PT command file ──
        set _cmd_file "$_run_dir_s/${scenario}.pt.tcl"
        set _fh [open $_cmd_file "w"]
        puts $_fh "#!/usr/bin/env tclsh"
        puts $_fh "# CBflow STA — PrimeTime scenario: $scenario"
        puts $_fh "# Sets per-scenario context, then delegates to timing_pt.tcl"
        puts $_fh ""
        puts $_fh "set ::SCENARIO      \"$scenario\""
        puts $_fh "set ::CORNER        \"$_sv(corner)\""
        puts $_fh "set ::MODE          \"$_sv(mode)\""
        puts $_fh "set ::VOLTAGE       \"$_sv(voltage)\""
        puts $_fh "set ::TEMPERATURE   \"$_sv(temperature)\""
        puts $_fh "set ::RC_CORNER     \"$_sv(rc_corner)\""
        puts $_fh "set ::LIB_SET       \"$_sv(lib_set_ref)\""
        puts $_fh "set ::SDC_FILE      \"$_sdc_file\""
        puts $_fh "set ::SPEF_FILE     \"$_spef_file\""
        puts $_fh "set ::REPORTS_DIR   \"$_reports_dir\""
        puts $_fh ""
        puts $_fh "source \"$::env(FLOW_DIR)/cmds/STA/synopsys/pt/$_tool_ver/timing_pt.tcl\""
        close $_fh
        puts "INFO: Generated command file: $_cmd_file"

        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Scenario $scenario"
            puts "INFO:   Corner=$_sv(corner) Mode=$_sv(mode) V=$_sv(voltage) T=$_sv(temperature)"
            set rpt [open "$_reports_dir/timing_${scenario}_summary.rpt" "w"]
            puts $rpt "# Test mode: $scenario — Setup WNS: 0.000ns  Hold WNS: 0.000ns"
            close $rpt
            # Also drop a run-level summary so downstream stages see per-scenario output
            set rpt2 [open "$run_dir/reports/sta/timing_${scenario}_summary.rpt" "w"]
            puts $rpt2 "# Test mode: $scenario — Setup WNS: 0.000ns  Hold WNS: 0.000ns"
            close $rpt2
        } else {
            set _tool [expr {[info exists ::sta(tool,name)] ? $::sta(tool,name) : "pt"}]
            handler_run $run_dir $::flow_type $node_name $scenario $_cmd_file false $_tool
        }
        puts "INFO: timing scenario $scenario done"
    }
}
