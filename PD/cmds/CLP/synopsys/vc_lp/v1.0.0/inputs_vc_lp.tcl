#!/usr/bin/env tclsh
# CBFlow CLP inputs - Synopsys VC LP

# ── Bootstrap ────────────────────────────────────────────────────────────────
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "CLP"
set STAGE_NAME "inputs"
set NODE_NAME "${STAGE_NAME}1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ---------------------------------------------------------------------------
flow_proc resolve_inputs {
    handle_info "Resolving input files..."
    global clp flow project flow_input_handshake

    set design_name [expr {[info exists clp(common,design_name)] ? $clp(common,design_name) : $flow(design_name)}]

    if {![namespace exists ::CBFlow::InputResolve]} {
        handle_info "Release input resolution not available — using direct paths only"
        return
    }

    # ── netlist: clp(input,netlist_release_tag) -> clp(input,netlist) ────────
    if {[info exists clp(input,netlist_release_tag)] && $clp(input,netlist_release_tag) ne ""} {
        set hs [get_input_handshake "CLP" "netlist"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve clp "netlist" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set clp(input,netlist) $_file
            handle_info "  Netlist resolved: $_file"
        }
    }

    # ── upf: clp(input,upf_release_tag) -> clp(input,upf_file) ─────────────
    if {[info exists clp(input,upf_release_tag)] && $clp(input,upf_release_tag) ne ""} {
        set hs [get_input_handshake "CLP" "upf"]
        if {[llength $hs] == 3} {
            set _file [::CBFlow::InputResolve::resolve clp "upf" \
                [lindex $hs 0] [lindex $hs 1] \
                [regsub -all {\$\{design_name\}} [lindex $hs 2] $design_name]]
            set clp(input,upf_file) $_file
            handle_info "  UPF resolved: $_file"
        }
    }

    handle_info "Input resolution completed"
}

# ---------------------------------------------------------------------------
# flow_proc: setup_dirs
# Create directory structure for CLP/VC LP input stage
# ---------------------------------------------------------------------------
flow_proc setup_dirs {
    handle_info "Setting up CLP input directories..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    foreach dir {
        "work/CLP/inputs/netlist"
        "work/CLP/inputs/upf"
        "work/CLP/inputs/power_spec"
        "work/CLP/inputs/library"
        "logs/inputs"
        "reports/clp"
        "results/clp"
    } {
        file mkdir "$run_dir/$dir"
    }
    handle_info "CLP input directories created successfully"
}

# ---------------------------------------------------------------------------
# flow_proc: read_design
# Read Verilog netlist into VC LP for low-power verification
# ---------------------------------------------------------------------------
flow_proc read_design {
    handle_info "Reading design netlist for LP verification..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set netlist_dir "$run_dir/work/CLP/inputs/netlist"

    # Locate netlist files from config or default paths
    if {[info exists ::clp(NETLIST_FILES)]} {
        set netlist_files $::clp(NETLIST_FILES)
    } else {
        set netlist_files [glob -nocomplain "$netlist_dir/*.v" "$netlist_dir/*.sv"]
    }

    if {[llength $netlist_files] == 0} {
        handle_error "No netlist files found in $netlist_dir"
        return -code error "Missing netlist files"
    }

    foreach nf $netlist_files {
        handle_info "Reading netlist: $nf"
        read_design -format verilog $nf
    }

    # Set top module
    if {[info exists ::clp(TOP_MODULE)]} {
        set_top $::clp(TOP_MODULE)
        handle_info "Top module set to $::clp(TOP_MODULE)"
    } elseif {[info exists ::project(DESIGN_NAME)]} {
        set_top $::project(DESIGN_NAME)
        handle_info "Top module set to $::project(DESIGN_NAME)"
    }

    handle_info "Design netlist read completed"
}

# ---------------------------------------------------------------------------
# flow_proc: read_upf
# Read UPF power intent specification for LP verification
# ---------------------------------------------------------------------------
flow_proc read_upf {
    handle_info "Reading UPF power intent..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set upf_dir "$run_dir/work/CLP/inputs/upf"

    if {[info exists ::clp(UPF_FILES)]} {
        set upf_files $::clp(UPF_FILES)
    } else {
        set upf_files [glob -nocomplain "$upf_dir/*.upf"]
    }

    if {[llength $upf_files] == 0} {
        handle_error "No UPF files found in $upf_dir"
        return -code error "Missing UPF files"
    }

    foreach uf $upf_files {
        handle_info "Reading UPF: $uf"
        read_power_intent -upf $uf
    }

    # Apply supplemental UPF if specified
    if {[info exists ::clp(SUPPLEMENTAL_UPF)]} {
        foreach suf $::clp(SUPPLEMENTAL_UPF) {
            handle_info "Reading supplemental UPF: $suf"
            read_power_intent -upf $suf -scope /
        }
    }

    handle_info "UPF power intent loaded successfully"
}

# ---------------------------------------------------------------------------
# flow_proc: read_libraries
# Read technology and standard cell libraries for LP verification
# ---------------------------------------------------------------------------
flow_proc read_libraries {
    handle_info "Reading libraries for LP verification..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set lib_dir "$run_dir/work/CLP/inputs/library"

    # Read Liberty libraries
    if {[info exists ::clp(LIBERTY_FILES)]} {
        set lib_files $::clp(LIBERTY_FILES)
    } elseif {[info exists ::tech(LIBERTY_FILES)]} {
        set lib_files $::tech(LIBERTY_FILES)
    } else {
        set lib_files [glob -nocomplain "$lib_dir/*.lib" "$lib_dir/*.db"]
    }

    foreach lf $lib_files {
        handle_info "Reading library: $lf"
        read_lib $lf
    }

    # Read technology LEF if available
    if {[info exists ::tech(TECH_LEF)]} {
        handle_info "Reading tech LEF: $::tech(TECH_LEF)"
        read_lef $::tech(TECH_LEF)
    }

    handle_info "Libraries loaded successfully"
}

# ---------------------------------------------------------------------------
# flow_proc: validate_inputs
# Validate that all required inputs are loaded and consistent
# ---------------------------------------------------------------------------
flow_proc validate_inputs {
    handle_info "Validating CLP inputs..."
    set run_dir $::env(CBFLOW_RUN_DIR)
    set errors 0

    # Check design is loaded
    set design_check [get_designs -quiet *]
    if {$design_check eq ""} {
        handle_error "No design loaded - check netlist read"
        incr errors
    }

    # Check power intent is loaded
    set pd_check [get_power_domains -quiet *]
    if {$pd_check eq ""} {
        handle_warning "No power domains found - check UPF"
    }

    # Write validation summary
    file mkdir $::REPORTS_DIR
    set fp [open "$::REPORTS_DIR/input_validation.rpt" w]
    puts $fp "CLP Input Validation Report - [clock format [clock seconds]]"
    puts $fp "============================================================"
    puts $fp "Design loaded:     [expr {$design_check ne "" ? "PASS" : "FAIL"}]"
    puts $fp "Power domains:     $pd_check"
    puts $fp "Errors:            $errors"
    close $fp

    if {$errors > 0} {
        handle_error "Input validation failed with $errors errors"
        return -code error "Validation failed"
    }

    handle_info "CLP input validation passed"
}

# ---------------------------------------------------------------------------
# flow_exec_all: Execute all input flow_procs in sequence
# ---------------------------------------------------------------------------
flow_proc inputs_flow {
    handle_info "Executing CLP inputs flow..."
    flow_exec setup_dirs
    flow_exec read_design
    flow_exec read_upf
    flow_exec read_libraries
    flow_exec validate_inputs
    handle_info "CLP inputs completed successfully"
}
if {[info exists argv0] && $argv0 eq [info script]} { flow_exec inputs_flow } else { puts " CLP inputs procedures loaded" }
exit
