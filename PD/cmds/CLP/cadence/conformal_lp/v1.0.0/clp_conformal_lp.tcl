#!/usr/bin/env tclsh
# CLP Verification - Cadence Conformal LP

# -- Bootstrap -----------------------------------------------------------------
set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "CLP"
set STAGE_NAME "clp"
set NODE_NAME "clp1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       SETUP LIBRARIES                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc setup_libraries {
    global clp project tech flow FLOW_DIR
    handle_info "Setting up libraries for low power verification..."

    # Read timing library files
    if {[info exists tech(lib,timing)]} {
        puts "Reading Liberty files:"
        set lib_files [expr {[string match "*{*}*" $tech(lib,timing)] ? $tech(lib,timing) : [list $tech(lib,timing)]}]
        foreach lib $lib_files {
            set project_root [file dirname $FLOW_DIR]
            set expanded_lib [subst $lib]
            set lib_path [file join $project_root $expanded_lib]
            if {[file exists $lib_path]} {
                puts "   $lib"
                read_library $lib_path
            } else {
                handle_warning "Liberty file not found: $lib_path"
            }
        }
    } else {
        handle_warning "tech(lib,timing) not defined"
    }

    puts " Libraries setup completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       READ DESIGN                                          │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_design {
    global clp project tech flow FLOW_DIR
    handle_info "Reading design for low power verification..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set netlist_dir "$run_dir/work/CLP/inputs/netlist"
    set netlist_files [glob -nocomplain "$netlist_dir/*.v" "$netlist_dir/*.sv" "$netlist_dir/*.vg"]

    if {[llength $netlist_files] > 0} {
        puts "Found [llength $netlist_files] netlist files"
        foreach netlist $netlist_files {
            puts "   Reading: [file tail $netlist]"
            read_design $netlist -golden
        }
    } else {
        handle_error "No netlist files found in $netlist_dir"
    }

    # Set top module
    if {[info exists project(top_module)]} {
        puts "Setting top module: $project(top_module)"
        set_top $project(top_module)
    }

    puts " Design loaded"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       READ POWER INTENT                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_power_intent {
    global clp project tech flow
    handle_info "Reading power intent (UPF/CPF)..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set upf_dir "$run_dir/work/CLP/inputs/upf"

    # Read UPF files
    set upf_files [glob -nocomplain "$upf_dir/*.upf"]
    if {[llength $upf_files] > 0} {
        puts "Found [llength $upf_files] UPF files"
        foreach upf $upf_files {
            puts "   Reading UPF: [file tail $upf]"
            read_power_intent $upf -format upf
        }
        puts " UPF power intent loaded"
        return
    }

    # Fallback to CPF files
    set cpf_files [glob -nocomplain "$upf_dir/*.cpf"]
    if {[llength $cpf_files] > 0} {
        puts "Found [llength $cpf_files] CPF files"
        foreach cpf $cpf_files {
            puts "   Reading CPF: [file tail $cpf]"
            read_power_intent $cpf -format cpf
        }
        puts " CPF power intent loaded"
        return
    }

    handle_warning "No UPF or CPF files found in $upf_dir"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       READ POWER SPECIFICATION                             │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc read_power_specification {
    global clp project tech flow
    handle_info "Reading power specification..."

    set run_dir $::env(CBFLOW_RUN_DIR)
    set power_dir "$run_dir/work/CLP/inputs/power_spec"
    set power_files [glob -nocomplain "$power_dir/*"]

    if {[llength $power_files] > 0} {
        puts "Found [llength $power_files] power specification files"
        foreach pf $power_files {
            puts "   Reading: [file tail $pf]"
            source $pf
        }
        puts " Power specification loaded"
    } else {
        puts " No power specification files (optional)"
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       RUN LOW POWER VERIFICATION                           │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc run_lp_verification {
    global clp project tech flow
    handle_info "Running low power verification..."

    file mkdir $::REPORTS_DIR
    file mkdir $::OUTPUTS_DIR

    # Check power domain connectivity
    puts "Checking power domain connectivity..."
    check_lp -connectivity > "$::REPORTS_DIR/connectivity_check.rpt"

    # Check isolation rules
    puts "Checking isolation rules..."
    check_lp -isolation > "$::REPORTS_DIR/isolation_check.rpt"

    # Check level shifter rules
    puts "Checking level shifter rules..."
    check_lp -level_shifter > "$::REPORTS_DIR/level_shifter_check.rpt"

    # Check retention rules
    puts "Checking retention rules..."
    check_lp -retention > "$::REPORTS_DIR/retention_check.rpt"

    # Check power switch rules
    puts "Checking power switch rules..."
    check_lp -power_switch > "$::REPORTS_DIR/power_switch_check.rpt"

    # Run comprehensive low power check
    puts "Running comprehensive low power verification..."
    check_lp -all > "$::REPORTS_DIR/comprehensive_check.rpt"

    puts " Low power verification completed"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       GENERATE REPORTS                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc generate_reports {
    global clp project tech flow
    handle_info "Generating CLP reports..."

    file mkdir $::REPORTS_DIR
    file mkdir $::OUTPUTS_DIR

    # Power domain report
    puts "Generating power domain report..."
    report_power_domain > "$::REPORTS_DIR/power_domains.rpt"

    # Isolation cell report
    puts "Generating isolation cell report..."
    report_isolation > "$::REPORTS_DIR/isolation_cells.rpt"

    # Level shifter report
    puts "Generating level shifter report..."
    report_level_shifter > "$::REPORTS_DIR/level_shifters.rpt"

    # Power verification summary
    set summary_file "$::OUTPUTS_DIR/power_verification.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "CBFlow CLP - Power Verification Report"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists project(top_module)]} { puts $fp "Design: $project(top_module)" }
    if {[info exists project(name)]} { puts $fp "Project: $project(name)" }
    if {[info exists tech(node)]} { puts $fp "Technology: $tech(node)" }
    puts $fp ""
    puts $fp "Tool: Cadence Conformal LP"
    puts $fp ""
    puts $fp "Verification Checks:"
    puts $fp "  Connectivity:   reports/clp/connectivity_check.rpt"
    puts $fp "  Isolation:      reports/clp/isolation_check.rpt"
    puts $fp "  Level Shifter:  reports/clp/level_shifter_check.rpt"
    puts $fp "  Retention:      reports/clp/retention_check.rpt"
    puts $fp "  Power Switch:   reports/clp/power_switch_check.rpt"
    puts $fp "  Comprehensive:  reports/clp/comprehensive_check.rpt"
    puts $fp ""
    puts $fp "Analysis Reports:"
    puts $fp "  Power Domains:  reports/clp/power_domains.rpt"
    puts $fp "  Isolation Cells: reports/clp/isolation_cells.rpt"
    puts $fp "  Level Shifters: reports/clp/level_shifters.rpt"
    close $fp

    puts " Reports generated successfully"
    puts " Check reports in: reports/clp/"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       VALIDATE CLP RESULTS                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

flow_proc validate_clp_results {
    global clp project tech flow FLOW_DIR
    handle_info "Running validation for CLP stage..."

    set current_dir $::env(CBFLOW_RUN_DIR)
    set validation_flow_dir ""

    if {[info exists FLOW_DIR]} {
        set validation_flow_dir $FLOW_DIR
    } elseif {[info exists ::env(FLOW_DIR)]} {
        set validation_flow_dir $::env(FLOW_DIR)
    }

    # Check mandatory outputs
    set power_rpt "$current_dir/results/clp/power_verification.rpt"
    if {[file exists $power_rpt]} {
        handle_info "Power verification report verified: $power_rpt"
    } else {
        handle_warning "Power verification report not found: $power_rpt"
    }

    # Try enhanced validation
    set enhanced_validation_script "$validation_flow_dir/utils/validation/v1.0.0/enhanced_validate_run.tcl"
    if {[file exists $enhanced_validation_script]} {
        if {[catch {exec tclsh $enhanced_validation_script CLP clp $current_dir $validation_flow_dir} validation_result]} {
            handle_warning "Validation completed with warnings: $validation_result"
        } else {
            handle_info "Validation completed successfully"
        }
    }
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           EXECUTION CONTROL                                │
# └─────────────────────────────────────────────────────────────────────────────┘

handle_info "═══════════════════════════════════════════════════════════════════════════════"
handle_info " CBFlow CLP Verification with Cadence Conformal LP"
handle_info "═══════════════════════════════════════════════════════════════════════════════"

flow_proc clp_flow {
    handle_info "Executing CLP verification flow..."

    flow_exec setup_libraries
    flow_exec read_design
    flow_exec read_power_intent
    flow_exec read_power_specification
    flow_exec run_lp_verification
    flow_exec generate_reports
    flow_exec validate_clp_results

    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    handle_info " CLP Verification Complete!"
    handle_info "═══════════════════════════════════════════════════════════════════════════════"
    puts "Power verification report: results/clp/power_verification.rpt"
    puts "Check reports in: reports/clp/"
    handle_info "CLP verification completed successfully"
}

if {[info exists argv0] && $argv0 eq [info script]} {
    puts "Direct execution mode - running CLP verification flow"
    flow_exec clp_flow
} else {
    puts " CBFlow CLP verification procedures loaded"
    puts "Available: setup_libraries, read_design, read_power_intent, read_power_specification, run_lp_verification, generate_reports, validate_clp_results, clp_flow"
}

# Exit tool after stage completion
exit
