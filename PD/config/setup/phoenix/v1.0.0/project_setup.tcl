#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Project Level Setup Hooks (Phoenix Project)
# Description: Project-specific flow_proc hooks that apply to ALL flows in this project
# Priority: Medium (overrides global, can be overridden by flow-specific setup)
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "Loading project-level setup hooks for Phoenix project"

# Project-wide initialization hooks
flow_proc_prepend flow_init {
    handle_info "Project flow init prepend: Phoenix project initialization"

    # Set project-specific environment
    if {![info exists ::env(PROJECT_NAME)]} {
        set ::env(PROJECT_NAME) "phoenix"
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
    handle_info "Project flow init append: Phoenix project validation complete"

    # Validate project-specific requirements
    if {[info exists project(name)] && $project(name) eq "phoenix"} {
        handle_info "Phoenix project configuration validated"
    }
}

# Project-wide library setup hooks
flow_proc_prepend setup_libraries {
    handle_info "Project setup libraries prepend: Phoenix library path setup"

    # Set project-specific library search paths
    if {[info exists tech(library_root)]} {
        set phoenix_lib_path "$tech(library_root)/phoenix_libs"
        if {[file exists $phoenix_lib_path]} {
            handle_info "Phoenix library path verified: $phoenix_lib_path"
        }
    }
}

flow_proc_append setup_libraries {
    handle_info "Project setup libraries append: Phoenix library validation"

    # Validate Phoenix-specific library requirements
    set required_libs {"stdcell" "memory" "io"}
    foreach lib $required_libs {
        if {[info exists tech(lib,$lib)]} {
            handle_info "Phoenix required library $lib: configured"
        } else {
            handle_warning "Phoenix required library $lib: not configured"
        }
    }
}

# Project-wide reporting hooks
flow_proc_append generate_reports {
    handle_info "Project generate reports append: Phoenix project reporting"

    # Generate project-specific reports
    set project_report_dir "reports/project"
    if {![file exists $project_report_dir]} {
        file mkdir $project_report_dir
    }

    # Create project summary report
    set summary_file "$project_report_dir/phoenix_summary.rpt"
    set fp [open $summary_file w]
    puts $fp "═══════════════════════════════════════════════════════════════════════════════"
    puts $fp "Phoenix Project Flow Summary"
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

    handle_info "Phoenix project summary generated: $summary_file"
}

handle_info "Project-level setup hooks loaded for Phoenix project"