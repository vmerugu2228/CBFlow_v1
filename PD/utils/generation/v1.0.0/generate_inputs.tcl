#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Input Files Linking Script
# Description: Links/copies input files to proper work directory structure
# Usage: tclsh generate_inputs.tcl <FLOW_TYPE> <run_dir> <flow_dir>
# ═══════════════════════════════════════════════════════════════════════════════


# Parse command line arguments
if {$argc != 3} {
    puts "ERROR: Invalid number of arguments"
    puts "Usage: tclsh generate_inputs.tcl <FLOW_TYPE> <run_dir> <flow_dir>"
    puts "  FLOW_TYPE: SYNTH, PNR, SIGNOFF"
    puts "  run_dir: Run directory path"
    puts "  flow_dir: Flow directory path"
    puts ""
    puts "This script links/copies input files to work directory structure:"
    puts "  work/<FLOW_TYPE>/inputs/netlist/"
    puts "  work/<FLOW_TYPE>/inputs/constraints/"
    puts "  work/<FLOW_TYPE>/inputs/def/"
    puts "  work/<FLOW_TYPE>/inputs/utils/"
    exit 1
}

set flow_type [lindex $argv 0]
set run_dir [lindex $argv 1] 
set flow_dir [lindex $argv 2]

# Validate flow_type
if {$flow_type ni {SYNTH PNR SIGNOFF}} {
    puts "ERROR: Invalid flow_type '$flow_type'. Must be SYNTH, PNR, or SIGNOFF"
    exit 1
}

# Source utilities
source "$flow_dir/utils/utils.tcl"

# Change to run directory
cd $run_dir

# Load configuration
if {![file exists ".config.tcl"]} {
    handle_error "Configuration file not found: .config.tcl"
    exit 1
}

source ".config.tcl"

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

proc validate_mandatory_files {flow_type} {
    global flow synth pnr signoff
    
    handle_info "Validating mandatory input files for $flow_type flow..."
    
    set flow_type_lower [string tolower $flow_type]
    set mandatory_var_key "mandatory_vars,$flow_type_lower"
    
    if {![info exists flow($mandatory_var_key)]} {
        handle_warning "No mandatory files defined for $flow_type flow"
        return true
    }
    
    set critical_files $flow($mandatory_var_key)
    set missing_files {}
    
    foreach var_name $critical_files {
        # Extract variable value using hierarchical structure
        if {[regexp {^([^(]+)\(([^,]+),([^)]+)\)$} $var_name -> array_name category key]} {
            # Handle hierarchical variable like pnr(input,netlist)
            global $array_name
            if {[info exists ${array_name}($category,$key)]} {
                set file_path [set ${array_name}($category,$key)]
                
                # Skip empty paths (optional files)
                if {$file_path eq ""} {
                    handle_info "✓ Optional file not specified: $var_name"
                    continue
                }
                
                # Check if file exists
                if {![file exists $file_path]} {
                    lappend missing_files "$var_name = '$file_path'"
                } else {
                    handle_info "✓ Found: $var_name = $file_path"
                }
            } else {
                lappend missing_files "$var_name (variable not defined)"
            }
        } else {
            # Handle simple variable
            if {[info exists $var_name]} {
                set file_path [set $var_name]
                
                # Skip empty paths (optional files)
                if {$file_path eq ""} {
                    handle_info "✓ Optional file not specified: $var_name"
                    continue
                }
                
                # Check if file exists
                if {![file exists $file_path]} {
                    lappend missing_files "$var_name = '$file_path'"
                } else {
                    handle_info "✓ Found: $var_name = $file_path"
                }
            } else {
                lappend missing_files "$var_name (variable not defined)"
            }
        }
    }
    
    if {[llength $missing_files] > 0} {
        puts "\[ERROR\] ❌ MANDATORY FILES MISSING"
        puts "\[ERROR\] "
        puts "\[ERROR\] The following mandatory files are missing or undefined:"
        foreach missing $missing_files {
            puts "\[ERROR\]   • $missing"
        }
        puts "\[ERROR\] "
        puts "\[ERROR\] Please ensure all mandatory input files exist before running the inputs stage."
        puts "\[ERROR\] Check your user_config.tcl file and verify file paths are correct."
        puts "\[ERROR\] "
        puts "\[ERROR\] Available files that can be used:"
        puts "\[ERROR\]   • Netlist: releases/v1.0/netlist/phoenix.v"
        puts "\[ERROR\]   • SDC: releases/v1.0/sdc/phoenix.sdc" 
        puts "\[ERROR\]   • DEF: Check if releases/v1.0/def/ contains a DEF file"
        exit 1
    }
    
    handle_info "✓ All mandatory files validated successfully"
    return true
}

proc create_directory_structure {flow_type} {
    set inputs_work_dir "work/$flow_type/inputs"
    
    # Create flow-specific directories
    if {$flow_type eq "PNR"} {
        set dirs {
            "netlist"
            "constraints" 
            "def"
        }
    } elseif {$flow_type eq "SYNTH"} {
        set dirs {
            "rtl"
            "constraints"
        }
    } elseif {$flow_type eq "SIGNOFF"} {
        set dirs {
            "netlist"
            "def"
            "spef"
        }
    } else {
        handle_error "Unknown flow type: $flow_type"
    }
    
    foreach dir $dirs {
        ensure_directory "$inputs_work_dir/$dir"
    }
    
    handle_info "Created directory structure: $inputs_work_dir"
    return $inputs_work_dir
}

proc link_or_copy_file {source_file target_file use_symlinks} {
    if {![file exists $source_file]} {
        handle_error "Source file not found: $source_file"
        return false
    }
    
    # Ensure target directory exists
    ensure_directory [file dirname $target_file]
    
    # Remove existing target if it exists
    if {[file exists $target_file]} {
        file delete $target_file
    }
    
    if {$use_symlinks eq "true"} {
        file link -symbolic $target_file [file normalize $source_file]
        handle_info "Linked: $source_file → $target_file"
    } else {
        file copy $source_file $target_file
        handle_info "Copied: $source_file → $target_file"
    }
    
    return true
}

proc create_standard_links {inputs_work_dir file_type source_file project_name} {
    set source_basename [file tail $source_file]
    
    switch $file_type {
        "netlist" {
            # Create standard netlist.v link
            set standard_link "$inputs_work_dir/netlist/netlist.v"
            if {$source_basename ne "netlist.v"} {
                if {[file exists $standard_link]} {
                    file delete $standard_link
                }
                file link -symbolic $standard_link $source_basename
                handle_info "Created standard link: netlist.v → $source_basename"
            }
        }
        "sdc" {
            # Create block-named SDC link
            if {$project_name ne ""} {
                set block_link "$inputs_work_dir/constraints/${project_name}.sdc"
                if {$source_basename ne "${project_name}.sdc"} {
                    if {[file exists $block_link]} {
                        file delete $block_link
                    }
                    file link -symbolic $block_link $source_basename
                    handle_info "Created block-named link: ${project_name}.sdc → $source_basename"
                }
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SYNTH INPUTS LINKING
# ═══════════════════════════════════════════════════════════════════════════════

proc process_synth_inputs {inputs_work_dir} {
    global synth project
    
    handle_info "Processing SYNTH input files..."
    
    # Determine symlink preference
    set use_symlinks "false"
    if {[info exists synth(input,use_symlinks)]} {
        set use_symlinks $synth(input,use_symlinks)
    }
    
    set project_name ""
    if {[info exists project(name)]} {
        set project_name $project(name)
    }
    
    # Link RTL files
    if {[info exists synth(input,rtl_files)] && $synth(input,rtl_files) ne ""} {
        foreach rtl_file $synth(input,rtl_files) {
            set target_rtl "$inputs_work_dir/rtl/[file tail $rtl_file]"
            link_or_copy_file $rtl_file $target_rtl $use_symlinks
        }
    } else {
        handle_warning "No RTL files specified in synth(input,rtl_files)"
    }
    
    # Link SDC constraint file
    if {[info exists synth(input,sdc_file)] && $synth(input,sdc_file) ne ""} {
        set source_sdc $synth(input,sdc_file)
        set target_sdc "$inputs_work_dir/constraints/[file tail $source_sdc]"
        
        if {[link_or_copy_file $source_sdc $target_sdc $use_symlinks]} {
            create_standard_links $inputs_work_dir "sdc" $source_sdc $project_name
        }
    } else {
        handle_warning "No SDC file specified in synth(input,sdc_file)"
    }
    
    # Link UPF file (optional)
    if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
        set source_upf $synth(input,upf_file)
        set target_upf "$inputs_work_dir/utils/[file tail $source_upf]"
        link_or_copy_file $source_upf $target_upf $use_symlinks
    }
    
    # Link additional scripts (optional)
    if {[info exists synth(input,tcl_scripts)] && $synth(input,tcl_scripts) ne ""} {
        foreach script $synth(input,tcl_scripts) {
            set target_script "$inputs_work_dir/utils/[file tail $script]"
            link_or_copy_file $script $target_script $use_symlinks
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# PNR INPUTS LINKING  
# ═══════════════════════════════════════════════════════════════════════════════

proc process_pnr_inputs {inputs_work_dir} {
    global pnr project
    
    handle_info "Processing PNR input files..."
    
    # Determine symlink preference
    set use_symlinks "false"
    if {[info exists pnr(input,use_symlinks)]} {
        set use_symlinks $pnr(input,use_symlinks)
    }
    
    set project_name ""
    if {[info exists project(name)]} {
        set project_name $project(name)
    }
    
    # Link netlist file
    if {[info exists pnr(input,netlist)] && $pnr(input,netlist) ne ""} {
        set source_netlist $pnr(input,netlist)
        set target_netlist "$inputs_work_dir/netlist/[file tail $source_netlist]"
        
        if {[link_or_copy_file $source_netlist $target_netlist $use_symlinks]} {
            create_standard_links $inputs_work_dir "netlist" $source_netlist $project_name
        }
    } else {
        handle_warning "No netlist file specified in pnr(input,netlist)"
    }
    
    # Link SDC constraint file
    if {[info exists pnr(input,sdc)] && $pnr(input,sdc) ne ""} {
        set source_sdc $pnr(input,sdc)
        set target_sdc "$inputs_work_dir/constraints/[file tail $source_sdc]"
        
        if {[link_or_copy_file $source_sdc $target_sdc $use_symlinks]} {
            create_standard_links $inputs_work_dir "sdc" $source_sdc $project_name
        }
    } else {
        handle_warning "No SDC file specified in pnr(input,sdc)"
    }
    
    # Link DEF file (optional)
    if {[info exists pnr(input,def_file)] && $pnr(input,def_file) ne ""} {
        set source_def $pnr(input,def_file)
        set target_def "$inputs_work_dir/def/[file tail $source_def]"
        link_or_copy_file $source_def $target_def $use_symlinks
    }
    
    # Link UPF file (optional)
    if {[info exists pnr(input,upf_file)] && $pnr(input,upf_file) ne ""} {
        set source_upf $pnr(input,upf_file)
        set target_upf "$inputs_work_dir/utils/[file tail $source_upf]"
        link_or_copy_file $source_upf $target_upf $use_symlinks
    }
    
    # Link IO file (optional)
    if {[info exists pnr(input,io_file)] && $pnr(input,io_file) ne ""} {
        set source_io $pnr(input,io_file)
        set target_io "$inputs_work_dir/utils/[file tail $source_io]"
        link_or_copy_file $source_io $target_io $use_symlinks
    }
    
    # Link additional scripts (optional)
    if {[info exists pnr(input,tcl_scripts)] && $pnr(input,tcl_scripts) ne ""} {
        foreach script $pnr(input,tcl_scripts) {
            set target_script "$inputs_work_dir/utils/[file tail $script]"
            link_or_copy_file $script $target_script $use_symlinks
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SIGNOFF INPUTS LINKING
# ═══════════════════════════════════════════════════════════════════════════════

proc process_signoff_inputs {inputs_work_dir} {
    global signoff project
    
    handle_info "Processing SIGNOFF input files..."
    
    # Determine symlink preference  
    set use_symlinks "false"
    if {[info exists signoff(input,use_symlinks)]} {
        set use_symlinks $signoff(input,use_symlinks)
    }
    
    # Link netlist file
    if {[info exists signoff(input,netlist)] && $signoff(input,netlist) ne ""} {
        set source_netlist $signoff(input,netlist)
        set target_netlist "$inputs_work_dir/netlist/[file tail $source_netlist]"
        link_or_copy_file $source_netlist $target_netlist $use_symlinks
    }
    
    # Link SDC file
    if {[info exists signoff(input,sdc)] && $signoff(input,sdc) ne ""} {
        set source_sdc $signoff(input,sdc)
        set target_sdc "$inputs_work_dir/constraints/[file tail $source_sdc]"
        link_or_copy_file $source_sdc $target_sdc $use_symlinks
    }
    
    # Link SPEF file
    if {[info exists signoff(input,spef)] && $signoff(input,spef) ne ""} {
        set source_spef $signoff(input,spef)
        set target_spef "$inputs_work_dir/utils/[file tail $source_spef]"
        link_or_copy_file $source_spef $target_spef $use_symlinks
    }
    
    # Link DEF file
    if {[info exists signoff(input,def)] && $signoff(input,def) ne ""} {
        set source_def $signoff(input,def)
        set target_def "$inputs_work_dir/def/[file tail $source_def]"
        link_or_copy_file $source_def $target_def $use_symlinks
    }
    
    # Link GDS file (optional)
    if {[info exists signoff(input,gds)] && $signoff(input,gds) ne ""} {
        set source_gds $signoff(input,gds)
        set target_gds "$inputs_work_dir/def/[file tail $source_gds]"
        link_or_copy_file $source_gds $target_gds $use_symlinks
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# GENERATE SUMMARY REPORT
# ═══════════════════════════════════════════════════════════════════════════════

proc generate_summary_report {flow_type inputs_work_dir} {
    global synth pnr signoff project
    
    set summary_file "$inputs_work_dir/reports/inputs_summary.rpt"
    set fp [open $summary_file w]
    
    puts $fp "$flow_type Inputs Summary Report"
    puts $fp "[string repeat "=" [string length "$flow_type Inputs Summary Report"]]"
    puts $fp "Generated: [clock format [clock seconds]]"
    puts $fp "Flow Type: $flow_type"
    puts $fp "Stage: inputs"
    puts $fp ""
    
    if {[info exists project(name)]} {
        puts $fp "Project: $project(name)"
    }
    puts $fp ""
    
    puts $fp "Input Files Linked:"
    
    switch $flow_type {
        "SYNTH" {
            if {[info exists synth(input,rtl_files)]} {
                puts $fp "  RTL Files: $synth(input,rtl_files)"
            }
            if {[info exists synth(input,sdc_file)]} {
                puts $fp "  SDC: $synth(input,sdc_file)"
            }
            if {[info exists synth(input,upf_file)] && $synth(input,upf_file) ne ""} {
                puts $fp "  UPF: $synth(input,upf_file)"
            }
            if {[info exists synth(input,tcl_scripts)] && $synth(input,tcl_scripts) ne ""} {
                puts $fp "  Scripts: $synth(input,tcl_scripts)"
            }
        }
        "PNR" {
            if {[info exists pnr(input,netlist)]} {
                puts $fp "  Netlist: $pnr(input,netlist)"
            }
            if {[info exists pnr(input,sdc)]} {
                puts $fp "  SDC: $pnr(input,sdc)"
            }
            if {[info exists pnr(input,def_file)] && $pnr(input,def_file) ne ""} {
                puts $fp "  DEF: $pnr(input,def_file)"
            }
            if {[info exists pnr(input,upf_file)] && $pnr(input,upf_file) ne ""} {
                puts $fp "  UPF: $pnr(input,upf_file)"
            }
            if {[info exists pnr(input,io_file)] && $pnr(input,io_file) ne ""} {
                puts $fp "  IO: $pnr(input,io_file)"
            }
            if {[info exists pnr(input,tcl_scripts)] && $pnr(input,tcl_scripts) ne ""} {
                puts $fp "  Scripts: $pnr(input,tcl_scripts)"
            }
        }
        "SIGNOFF" {
            if {[info exists signoff(input,netlist)]} {
                puts $fp "  Netlist: $signoff(input,netlist)"
            }
            if {[info exists signoff(input,sdc)]} {
                puts $fp "  SDC: $signoff(input,sdc)"
            }
            if {[info exists signoff(input,spef)]} {
                puts $fp "  SPEF: $signoff(input,spef)"
            }
            if {[info exists signoff(input,def)]} {
                puts $fp "  DEF: $signoff(input,def)"
            }
            if {[info exists signoff(input,gds)] && $signoff(input,gds) ne ""} {
                puts $fp "  GDS: $signoff(input,gds)"
            }
        }
    }
    
    puts $fp ""
    puts $fp "Work Directory Structure:"
    puts $fp "  $inputs_work_dir/netlist/"
    puts $fp "  $inputs_work_dir/constraints/"
    puts $fp "  $inputs_work_dir/def/"
    puts $fp "  $inputs_work_dir/utils/"
    puts $fp "  $inputs_work_dir/rtl/"
    puts $fp "  $inputs_work_dir/reports/"
    
    close $fp
    
    handle_info "Summary report generated: $summary_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Starting $flow_type inputs linking..."
handle_info "Run directory: $run_dir"
handle_info "Flow directory: $flow_dir"

# Validate mandatory files first
if {![validate_mandatory_files $flow_type]} {
    exit 1
}

# Create directory structure
set inputs_work_dir [create_directory_structure $flow_type]

# Process inputs based on flow type
switch $flow_type {
    "SYNTH" {
        process_synth_inputs $inputs_work_dir
    }
    "PNR" {
        process_pnr_inputs $inputs_work_dir
    }
    "SIGNOFF" {
        process_signoff_inputs $inputs_work_dir
    }
    default {
        handle_error "Unsupported flow type: $flow_type"
        exit 1
    }
}

# No summary report generated - inputs directories only contain input files

handle_info "$flow_type inputs linking completed successfully!"

# Update run status after successful completion
if {[catch {
    source "$flow_dir/utils/utils.tcl"
    log_stage_status "inputs" "COMPLETE" "Input validation and linking completed successfully"
} result]} {
    handle_warning "Could not update run status: $result"
}

puts "✅ All input files linked to: $inputs_work_dir"