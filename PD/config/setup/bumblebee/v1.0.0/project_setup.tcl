#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Project Level Setup Hooks (Ravendrive Project)
# Description: Project-specific flow_proc hooks that apply to ALL flows in this project
# Priority: Medium (overrides global, can be overridden by flow-specific setup)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading project-level setup hooks for Ravendrive project"

# Project-wide initialization hooks
flow_proc_prepend flow_init {
    handle_info "Project flow init prepend: Ravendrive project initialization"

    # Set project-specific environment
    if {![info exists ::env(PROJECT_NAME)]} {
        set ::env(PROJECT_NAME) "bumblebee"
    }

    # Create project-specific directories
    set project_dirs {
        "logs/project"
        "reports/project"
        "work/project"
    }

    foreach dir $project_dirs {
        if {![file exists $dir]} {
            file mkdir $dir
            handle_info "Created project directory: $dir"
        }
    }
}

flow_proc_append flow_init {
    handle_info "Project flow init append: Ravendrive project validation complete"

    # Validate project-specific requirements
    if {[info exists project(name)] && $project(name) eq "bumblebee"} {
        handle_info "Ravendrive project configuration validated"
    }
}

# Project-wide library setup hooks
flow_proc_prepend setup_libraries {
    handle_info "Project setup libraries prepend: Ravendrive library path setup"

    # Set project-specific library search paths
    if {[info exists tech(library_root)]} {
        set bumblebee_lib_path "$tech(library_root)/bumblebee_libs"
        if {[file exists $bumblebee_lib_path]} {
            handle_info "Ravendrive library path verified: $bumblebee_lib_path"
        }
    }
}

flow_proc_append setup_libraries {
    handle_info "Project setup libraries append: Ravendrive library validation"

    # Validate Ravendrive-specific library requirements
    set required_libs {"stdcell" "memory" "io"}
    foreach lib $required_libs {
        if {[info exists tech(lib,$lib)]} {
            handle_info "Ravendrive required library $lib: configured"
        } else {
            handle_warning "Ravendrive required library $lib: not configured"
        }
    }
}

# Project-wide reporting hooks
flow_proc_append generate_reports {
    handle_info "Project generate reports append: Ravendrive project reporting"

    # Generate project-specific reports
    set project_report_dir "reports/project"
    if {![file exists $project_report_dir]} {
        file mkdir $project_report_dir
    }

    # Create project summary report
    set summary_file "$project_report_dir/bumblebee_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Ravendrive Project Flow Summary"
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Generated: [clock format [clock seconds]]"
    if {[info exists ::flow::current_stage]} {
        puts $fp "Current Stage: $::flow::current_stage"
    }
    if {[info exists project(name)]} {
        puts $fp "Project: $project(name)"
    }
    if {[info exists tech(node)]} {
        puts $fp "Technology: $tech(node)"
    }
    close $fp

    handle_info "Ravendrive project summary generated: $summary_file"
}

handle_info "Project-level setup hooks loaded for Ravendrive project"