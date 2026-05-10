#!/usr/bin/env tclsh
# ===============================================================================
# CBFlow - PV Inputs Command File
# Description: Input validation and preparation for Physical Verification
# Tool: Synopsys ICV
# ===============================================================================

set run_dir $::env(CBFLOW_RUN_DIR)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} { source -e $env_file } else { puts stderr "ERROR: .run.cbflow.tcl not found"; exit 1 }
if {[info exists ::env(FLOW_DIR)]} { set FLOW_DIR $::env(FLOW_DIR) } else { puts stderr "ERROR: FLOW_DIR not set"; exit 1 }
if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} { puts stderr "ERROR: UTILITIES_VERSION not set"; exit 1 }
set utils_path "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} { source -e $utils_path } else { puts stderr "ERROR: Utils not found"; exit 1 }
namespace import ::CBFlow::Utilities::print_header

set config_file "$run_dir/work/PV/inputs/run/config.tcl"
if {[file exists $config_file]} { source -e $config_file }

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }

global pv project tech flow
handle_info "Starting PV inputs with Synopsys ICV..."
if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

set WORK_DIR "$run_dir/work/PV/inputs"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

# Source release utilities for input resolution
set _release_utils "$FLOW_DIR/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"
if {[file exists $_release_utils]} { source $_release_utils }
set _release_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/release_config.tcl"
if {[file exists $_release_config]} { source $_release_config }

# --------------------------------------------------------------------------
# Procedure: resolve_inputs
#   Resolve input files from release tags or direct paths
# --------------------------------------------------------------------------
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global pv flow project flow_input_handshake

    set design_name [expr {[info exists pv(design_name)] ? $pv(design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── gds: pv(input,gds_release_tag) -> pv(input,gds) ────────────────────
    if {[info exists pv(input,gds_release_tag)] && $pv(input,gds_release_tag) ne ""} {
        set hs [get_input_handshake "PV" "gds"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pv "gds" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pv(input,gds) $_file
            handle_info "  GDS resolved: $_file"
        }
    }

    # ── netlist: pv(input,netlist_release_tag) -> pv(input,netlist) ─────────
    if {[info exists pv(input,netlist_release_tag)] && $pv(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "PV" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pv "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pv(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── def: pv(input,def_release_tag) -> pv(input,def) ────────────────────
    if {[info exists pv(input,def_release_tag)] && $pv(input,def_release_tag) ne ""} {
        set hs [get_input_handshake "PV" "def"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve pv "def" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set pv(input,def) $_file
            handle_info "  DEF resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# --------------------------------------------------------------------------
# Procedure: setup_dirs
#   Create directory structure for all PV stages
# --------------------------------------------------------------------------
flow_proc setup_dirs {
    handle_info "Setting up PV input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {
        "work/PV/inputs/netlist" "work/PV/inputs/def" "work/PV/inputs/gds"
        "work/PV/inputs/rules"  "work/PV/inputs/spice"
        "work/PV/drc/run"  "work/PV/lvs/run"  "work/PV/erc/run"  "work/PV/perc/run"
        "logs/pv"          "reports/pv/drc"    "reports/pv/lvs"
        "reports/pv/erc"   "reports/pv/perc"
        "results/pv"       "results/drc"       "results/lvs"
        "results/erc"      "results/perc"
    } {
        file mkdir "$run_dir/$dir"
    }
    handle_info "PV input directories created"
}

# --------------------------------------------------------------------------
# Procedure: read_gds
#   Locate and validate the input GDS file from pv(input,gds)
# --------------------------------------------------------------------------
flow_proc read_gds {
    global pv project
    handle_info "Reading GDS input for PV..."
    set run_dir $::env(CBFLOW_RUN_DIR)

    # Determine GDS source from pv config array
    if {[info exists pv(input,gds)]} {
        set gds_file $pv(input,gds)
    } elseif {[info exists project(gds_file)]} {
        set gds_file $project(gds_file)
    } else {
        # Search default input location
        set gds_candidates [glob -nocomplain "$run_dir/work/PV/inputs/gds/*.gds" "$run_dir/work/PV/inputs/gds/*.gds.gz"]
        if {[llength $gds_candidates] > 0} {
            set gds_file [lindex $gds_candidates 0]
        } else {
            handle_error "No GDS file specified in pv(input,gds) and none found in work/PV/inputs/gds/"
            return
        }
    }

    if {![file exists $gds_file]} {
        handle_error "GDS file not found: $gds_file"
        return
    }

    set ::pv_gds_file $gds_file
    handle_info "GDS file: $gds_file ([expr {[file size $gds_file] / 1048576}] MB)"
}

# --------------------------------------------------------------------------
# Procedure: read_rules
#   Load DRC/LVS rule decks from tech(rules,drc) and tech(rules,lvs)
# --------------------------------------------------------------------------
flow_proc read_rules {
    global tech
    handle_info "Reading rule decks for PV..."

    # DRC rules
    if {[info exists tech(rules,drc)]} {
        set drc_rules $tech(rules,drc)
        if {[file exists $drc_rules]} {
            set ::pv_drc_rules $drc_rules
            handle_info "DRC rule deck: $drc_rules"
        } else {
            handle_warning "DRC rule deck not found: $drc_rules"
        }
    } else {
        handle_warning "tech(rules,drc) not defined"
    }

    # LVS rules
    if {[info exists tech(rules,lvs)]} {
        set lvs_rules $tech(rules,lvs)
        if {[file exists $lvs_rules]} {
            set ::pv_lvs_rules $lvs_rules
            handle_info "LVS rule deck: $lvs_rules"
        } else {
            handle_warning "LVS rule deck not found: $lvs_rules"
        }
    } else {
        handle_warning "tech(rules,lvs) not defined"
    }

    # ERC rules (optional, often embedded in LVS deck)
    if {[info exists tech(rules,erc)]} {
        set ::pv_erc_rules $tech(rules,erc)
        handle_info "ERC rule deck: $tech(rules,erc)"
    }

    # PERC rules (optional)
    if {[info exists tech(rules,perc)]} {
        set ::pv_perc_rules $tech(rules,perc)
        handle_info "PERC rule deck: $tech(rules,perc)"
    }

    handle_info "Rule deck loading completed"
}

# --------------------------------------------------------------------------
# Procedure: validate_inputs
#   Validate all required inputs are present and consistent
# --------------------------------------------------------------------------
flow_proc validate_inputs {
    global pv project tech
    handle_info "Validating PV inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors {}

    # Check GDS
    if {![info exists ::pv_gds_file] || ![file exists $::pv_gds_file]} {
        lappend errors "GDS file not available"
    }

    # Check at least one rule deck
    set has_rules 0
    if {[info exists ::pv_drc_rules] && [file exists $::pv_drc_rules]} { incr has_rules }
    if {[info exists ::pv_lvs_rules] && [file exists $::pv_lvs_rules]} { incr has_rules }
    if {$has_rules == 0} {
        lappend errors "No valid rule decks found (need at least DRC or LVS)"
    }

    # Check top cell name
    if {![info exists project(top_module)] && ![info exists pv(top_cell)]} {
        lappend errors "Top cell not defined in project(top_module) or pv(top_cell)"
    }

    # Generate validation summary
    set vf "$::REPORTS_DIR/inputs_validation.rpt"
    set fp [open $vf w]
    puts $fp "==============================================================================="
    puts $fp "CBFlow PV - Input Validation Report"
    puts $fp "==============================================================================="
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp "Tool: Synopsys ICV"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists tech(node)]}          { puts $fp "Technology: $tech(node)" }
    puts $fp ""
    puts $fp "GDS File:   [expr {[info exists ::pv_gds_file] ? $::pv_gds_file : \"NOT SET\"}]"
    puts $fp "DRC Rules:  [expr {[info exists ::pv_drc_rules] ? $::pv_drc_rules : \"NOT SET\"}]"
    puts $fp "LVS Rules:  [expr {[info exists ::pv_lvs_rules] ? $::pv_lvs_rules : \"NOT SET\"}]"
    puts $fp ""

    if {[llength $errors] > 0} {
        puts $fp "VALIDATION STATUS: FAIL"
        puts $fp "Errors:"
        foreach e $errors { puts $fp "  - $e" }
        close $fp
        foreach e $errors { handle_error "Input validation: $e" }
        handle_error "PV input validation FAILED with [llength $errors] error(s)"
    } else {
        puts $fp "VALIDATION STATUS: PASS"
        puts $fp "All required inputs present"
        close $fp
        handle_info "PV input validation PASSED"
    }
}

# --------------------------------------------------------------------------
# Top-level flow execution
# --------------------------------------------------------------------------
flow_exec_all setup_dirs read_gds read_rules validate_inputs
exit
