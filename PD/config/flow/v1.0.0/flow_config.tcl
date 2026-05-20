#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          PHYSICAL DESIGN FLOW CONFIGURATION                  ║
# ║                             Main Configuration File                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This is the main configuration file for the physical design flow.
# It loads specialized configuration files and defines core flow settings.
#
# Configuration Structure:
# - logo_config.tcl    → Logo, branding, and company information
# - dir_config.tcl     → Directory structures and file organization
# - flow_config.tcl    → Main flow logic and stage definitions (this file)
#
# Quick Navigation:
# - SECTION 1: PROJECT SETTINGS        → Basic project configuration
# - SECTION 2: FLOW DEFINITIONS        → Supported flows and stages
# - SECTION 3: TOOL CONFIGURATION      → EDA tool settings
# - SECTION 4: RUNTIME SETTINGS        → Performance and timeouts
# - SECTION 5: INPUT/OUTPUT FILES      → File definitions per stage
# - SECTION 6: VALIDATION RULES        → File and naming conventions
# - SECTION 7: RELEASE MANAGEMENT      → Release types and settings
# - SECTION 8: ADVANCED FEATURES       → MMMC, logging, etc.

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SECTION 1: PROJECT SETTINGS                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Basic project configuration that controls flow behavior and options.

# ┌─ Project and Technology Settings ──────────────────────────────────────────┐
set flow(project_name) ""                                    ; # Resolved from user_config/project_config at runtime
set flow(tech_node) ""                                   ; # Resolved from project(technology) at runtime

# Set hierarchical variables for configuration system
if {$flow(project_name) ne ""} { set project(name) $flow(project_name) }
if {$flow(tech_node) ne ""} { set tech(node) $flow(tech_node) }

# ┌─ Flow Types and Options ───────────────────────────────────────────────────┐
set flow(type) "SYNTH"                                                ; # Current flow type
set flow(types) {SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR}   ; # All supported flow types
set flow(default_type) "SYNTH"                                        ; # Default when not specified

# ┌─ Flow Runtime Variables (Default Values) ─────────────────────────────────┐
set flow(run_name) "default_run"                        ; # Default run name - usually overridden in user config
set flow(design_name) "default_design"                  ; # Default design name - must be overridden in user config

# ┌─ Track Height Configuration ──────────────────────────────────────────────┐
set flow(track_variant) ""                                   ; # Override tech default. Options: "9T", "7.5T", "6.75T"
# When set, this overrides tech(track,active_variant) before tech config resolution

# ┌─ Dispatcher Configuration ────────────────────────────────────────────────┐
set flow(dispatcher)         "race"       ;# Execution dispatcher: "race" (RACE) or "make" (GNU Make)
set flow(use_lsf)            true           ;# Enable LSF job submission
set flow(use_xterm)          true           ;# Enable xterm for interactive sessions

# ┌─ EDA Tool Module Versions ──────────────────────────────────────────────┐
# Module load commands for each tool. Edit version strings to upgrade tools.
set flow(tool_module,fc)       "synopsysFusionCompiler/2025.06-SP2"
set flow(tool_module,pt)       "synopsysPrimeTime/2025.06"
set flow(tool_module,fm)           "synopsysFormality/2025.06"
set flow(tool_module,formality)    "synopsysFormality/2025.06"
set flow(tool_module,icv)          "synopsysICV/2025.06"
set flow(tool_module,redhawk)      "synopsysRedHawk/2025.06"
set flow(tool_module,vc_lp)        "synopsysVC_LP/2025.06"
set flow(tool_module,conformal_lp) "cadenceConformalLP/23.1"
set flow(tool_module,genus)        "cadenceGenus/23.1"
set flow(tool_module,innovus)      "cadenceInnovus/23.1"
set flow(tool_module,tempus)       "cadenceTempus/23.1"
set flow(tool_module,voltus)       "cadenceVoltus/23.1"
set flow(tool_module,calibre)      "mentorCalibre/2024.1"

# ┌─ RACE Database Management ──────────────────────────────────────────────┐
set flow(race,db_max_sessions)   10        ;# Max RACE DB sessions per user. Warning issued when limit reached.
set flow(race,db_warn_threshold) 8         ;# Warn when this many DBs exist (before hitting max)

# ┌─ Flow Mode Configuration ─────────────────────────────────────────────────┐
set flow(mode) "default"                                 ; # default | merged
# default: SYNTH, FP, PNR are independent flows (traditional)
# merged:  SYNTH+PNR auto-merge into SYNTH_PNR, FP stays independent
#          PNR inputs depend on FP floorplan output
set flow(merged,flows) "SYNTH_PNR"                       ; # Merged flow combination
set flow(merged,fp_independent) true                     ; # FP stays as independent flow
set flow(merged,pnr_depends_fp) true                     ; # PNR reads DEF from FP output

# ┌─ Run Type Configuration ──────────────────────────────────────────────────┐
set flow(run_type) "node"                               ; # Run execution mode: "node" (default) or "flat"
set flow(test_mode) "false"                              ; # When true, bypass EDA tool calls and show command files instead
set flow(use_lsf)   "true"                               ; # Auto-submit stages to LSF (default: true for production)
set flow(use_xterm)  "true"                               ; # Launch tool in xterm window (default: true for interactive)
set flow(run_types) {node flat}                         ; # Supported run execution modes
set flow(default_run_type) "node"                       ; # Default run type when not specified

# Flow type descriptions (for help and documentation)
array set flow_descriptions {
    SYNTH "Logic synthesis and optimization"
    FP    "Floorplanning and power planning"
    PNR   "Place and route implementation"
    STA   "Final sign-off timing analysis"
    LEC   "Logic equivalence checking"
    EMIR  "Power and thermal analysis"
    PV  "Physical verification (DRC/LVS/ERC/PERC)"
    ECO   "Engineering change orders"
    CLP   "Conformal low power verification"
    POPT  "Power optimization and clock gating"
    FCFP      "Fullchip floorplanning"
    SYNTH_PNR "Unified synthesis to signoff (FC-RM aligned)"
}

# Run type descriptions (for help and documentation)
array set run_type_descriptions {
    node "Individual node execution - each stage runs as separate node (default)"
    flat "Merged execution - all execution nodes combined into single merged node for license efficiency"
}

# ┌─ Project Phases ───────────────────────────────────────────────────────────┐
set flow(phases) {P0 P1 P2 P3}                          ; # Available project phases
set flow(default_phase) "P0"                            ; # Default phase

# Phase descriptions
array set phase_descriptions {
    P0 "Initial implementation and prototyping"
    P1 "Design refinement and optimization"
    P2 "Final implementation and sign-off"
    P3 "Production and manufacturing release"
}

# ┌─ User Configuration Variables ─────────────────────────────────────────────┐
# These variables can be set in user configuration files
set project(phase) ""                                    ; # User-defined project phase

# ┌─ Exit Milestones ──────────────────────────────────────────────────────────┐
set flow(exit_milestones) {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
set flow(default_exit_milestone) ""

# Milestone definitions with descriptions
array set MILESTONE_STAGE_MAPPING {
    FP_EXIT    "floorplan"
    PLACE_EXIT "place"
    CTS_EXIT   "cts"
    PRO_EXIT   "post_route"
    BTO        "chip_finish"
    MTO        "signoff"
}

array set MILESTONE_DESCRIPTIONS {
    FP_EXIT    "Floorplan Exit - Design ready for placement"
    PLACE_EXIT "Placement Exit - Design ready for CTS"
    CTS_EXIT   "CTS Exit - Design ready for routing"
    PRO_EXIT   "Post Route Exit - Design ready for finishing"
    BTO        "Backend Tapeout - Design ready for manufacturing"
    MTO        "Manufacturing Tapeout - Final design release"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SECTION 2: FLOW DEFINITIONS                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This section sources node-specific configuration files that define:
# - Flow stages and execution order for each flow type
# - Stage dependencies and subnodes
# - Input/output file requirements
# - Tool configurations per flow
# - Validation rules
#
# Node configuration files are loaded dynamically based on flow type.

# ┌─ Universal Mandatory Variables ────────────────────────────────────────────┐
# These variables MUST be defined for ALL flows
set flow(mandatory_vars,all) {flow(run_name) flow(type) flow(design_name)}

# ┌─ Source Node-Specific Configuration Files ─────────────────────────────────┐
# Load configurations for all supported flow types from node_configs directory
# Each file contains flow-specific stages, dependencies, tools, and validation rules

# Get the directory where this config file is located
# Handle symlinks by resolving to the actual file location
set script_path [info script]
if {[file type $script_path] eq "link"} {
    set script_path [file readlink $script_path]
    # Handle relative symlink paths
    if {[file pathtype $script_path] ne "absolute"} {
        set script_path [file join [file dirname [info script]] $script_path]
    }
}
set config_dir [file dirname $script_path]

# Source individual node configuration files from node_configs subdirectory
# Conditionally load only the required flow configuration for performance optimization

# Determine current flow type from various sources
set current_flow_type ""
set _valid_flow_types $flow(types)

# Method 1: Check environment variable (from run directory)
if {[info exists ::env(CBFLOW_FLOW_TYPE)]} {
    set current_flow_type $::env(CBFLOW_FLOW_TYPE)
}

# Method 2: Check command line arguments for flow type
if {$current_flow_type eq ""} {
    global argc argv
    if {[info exists argc] && [info exists argv] && $argc > 0} {
        foreach arg $argv {
            set _arg_upper [string toupper $arg]
            if {$_arg_upper in $_valid_flow_types} {
                set current_flow_type $_arg_upper
                break
            }
        }
    }
}

# Flow type MUST be resolved — no silent fallback
if {$current_flow_type eq ""} {
    puts "ERROR: Could not determine flow type."
    puts "       Set CBFLOW_FLOW_TYPE environment variable or pass the flow type as an argument."
    puts "       Available flow types: $_valid_flow_types"
    exit 1
}

# Validate and load the flow configuration
set flow_config_file "$config_dir/node_configs/${current_flow_type}_config.tcl"
if {[file exists $flow_config_file]} {
    source $flow_config_file
} else {
    puts "ERROR: Flow configuration file not found: $flow_config_file"
    puts "       Available flow types: $_valid_flow_types"
    exit 1
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                       SECTION 3: TOOL CONFIGURATION                         ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# EDA tool settings and configurations are now defined in individual node config files.
# This section contains only global tool settings that apply across all flows.

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                       SECTION 4: RUNTIME SETTINGS                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Performance settings, timeouts, and runtime behavior configuration.

# ┌─ Resource Limits ──────────────────────────────────────────────────────────┐
set runtime(cpu_count)     8        ; # Number of CPU cores to use
set runtime(memory_limit)  "32GB"   ; # Maximum memory per job
set runtime(temp_dir)      "/tmp"    ; # Temporary directory for scratch files

# ┌─ Timeouts (in minutes) ────────────────────────────────────────────────────┐
# Flow-specific timeouts are now defined in individual node config files
# This section contains only global timeout settings

# ┌─ Execution Preferences ────────────────────────────────────────────────────┐
set runtime(terminal_type)     "terminal"  ; # Options: "xterm", "terminal", "background"
set runtime(parallel_jobs)     4           ; # Number of parallel make jobs

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      SECTION 5: INPUT/OUTPUT FILES                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Flow-specific file definitions are now in individual node config files.
# This section contains only global file settings and validation rules.

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      SECTION 6: VALIDATION RULES                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# File validation rules and naming conventions.

# ┌─ File Type Validation ─────────────────────────────────────────────────────┐
array set FILE_VALIDATION_RULES {
    NETLIST {".v" ".vg" ".sv"}
    SDC     {".sdc"}
    DEF     {".def"}
    SPEF    {".spef"}
    LIB     {".lib"}
    LEF     {".lef"}
    GDS     {".gds" ".gdsii"}
}

# ┌─ Status Tracking ──────────────────────────────────────────────────────────┐
set flow(valid_status) {NOTRUN RUNNING COMPLETE ERROR WARNING SKIPPED RETRACED}
set flow(status_file) ".run.status"

# ┌─ Input Validation Settings ────────────────────────────────────────────────┐
# These settings control input file validation behavior
set validation(check_file_exists) "true"                ; # Check if input files exist
set validation(check_file_readable) "true"              ; # Check if input files are readable
set validation(check_naming_convention) "true"          ; # Validate file naming conventions
set validation(strict_mode) "false"                     ; # Enable strict validation mode

# ┌─ Debug and Logging Settings ───────────────────────────────────────────────┐
# These settings control debug output and intermediate file saving
set debug(verbose) "false"                              ; # Enable verbose debug output
set debug(save_intermediate) "false"                    ; # Save intermediate files for debugging
set debug(log_level) "INFO"                             ; # Debug log level: DEBUG, INFO, WARNING, ERROR

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      SECTION 7: RELEASE MANAGEMENT                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Release directory structure and file packaging for deliverables.

# ┌─ Release Directory Settings ───────────────────────────────────────────────┐
set flow(release_base_dir)    "releases"
set flow(release_default_tag) "latest"
set flow(release_structure) {
    "netlist"
    "sdc"
    "def"
    "gds"
    "reports"
    "scripts"
}

# ┌─ Release Types and Required Files ─────────────────────────────────────────┐
# Flow-specific release types are now defined in individual node config files

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      SECTION 8: ADVANCED FEATURES                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Advanced configuration for MMMC, logging, notifications, and other features.

# ┌─ MMMC (Multi-Mode Multi-Corner) Settings ─────────────────────────────────┐
set flow(mmmc,enabled)      true
set flow(mmmc,config_file)  "mmmc_config.tcl"
# Flow-specific MMMC enabled stages are now defined in individual node config files

# ┌─ Logging Configuration ────────────────────────────────────────────────────┐
set flow(log,level)           "INFO"
set flow(log,rotation_size)   "100MB"
set flow(log,retention_days)  30
set flow(log,categories)      {INIT CONFIG STAGE TOOL ERROR WARNING DEBUG}

# ┌─ Makefile Generation ──────────────────────────────────────────────────────┐
set flow(makefile,include_colors)  true
set flow(makefile,parallel_jobs)   4
set flow(makefile,verbose_output)  false
set flow(makefile,default_targets) {all help status clean retrace}

# ┌─ XTerm Color Configuration ────────────────────────────────────────────────┐
set flow(xterm_colors) {
    "#f0f9ff"
    "#f8fafc"
    "#f1f5f9"
    "#f9fafb"
    "#fafafa"
    "#f5f5f5"
    "#ecfdf5"
    "#f0fdf4"
    "#fefce8"
    "#fffbeb"
    "#fef3c7"
    "#fde68a"
    "#fcf3ff"
    "#faf5ff"
    "#fdf2f8"
    "#fef7f0"
    "#fff7ed"
    "#f0fdfa"
}

# ┌─ Email / Notification Configuration ─────────────────────────────────────┐
set flow(email,enabled)       true              ;# Enable email notifications
set flow(email,smtp_server)   "localhost"        ;# SMTP server hostname
set flow(email,smtp_port)     25                 ;# SMTP port (25=plain, 587=TLS)
set flow(email,smtp_tls)      false              ;# Enable STARTTLS
set flow(email,smtp_auth)     false              ;# Require SMTP authentication
set flow(email,smtp_user)     ""                 ;# SMTP username (if auth enabled)
set flow(email,smtp_password) ""                 ;# SMTP password (if auth enabled)
set flow(email,from)          ""                 ;# From address (default: user@hostname)
set flow(email,cc)            ""                 ;# Default CC recipients
set flow(email,reply_to)      ""                 ;# Reply-To address
set flow(email,signature)     "CBflow Automation" ;# Email footer signature
set flow(email,recipients)    ""                 ;# Default recipients (comma-separated)
# Email triggers — set to true to auto-send on events
set flow(email,on_run_create) false              ;# Send on run creation
set flow(email,on_run_complete) false            ;# Send on run completion
set flow(email,on_stage_fail) false              ;# Send on stage failure
set flow(email,on_checklist)  false              ;# Send after checklist run

# ┌─ AutoPPT Configuration ─────────────────────────────────────────────────┐
set flow(autoppt,enabled)       true             ;# Enable auto PPT generation
set flow(autoppt,format)        "html"           ;# Default format: html or pptx
set flow(autoppt,auto_generate) false            ;# Auto-generate on run completion
set flow(autoppt,include_power) true             ;# Include power slides
set flow(autoppt,include_clock) true             ;# Include clock QoR slides
set flow(autoppt,include_drc)   true             ;# Include DRC summary slides

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                            HELPER FUNCTIONS                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Utility functions for configuration validation and file checking.

# ┌─ File Validation Function ─────────────────────────────────────────────────┐
proc validate_file_naming {file_path file_type} {
    # Validates file naming conventions
    # Returns: {success_boolean error_message}

    set filename [file tail $file_path]
    set extension [file extension $filename]
    set basename [file rootname $filename]

    global FILE_VALIDATION_RULES
    if {![info exists FILE_VALIDATION_RULES($file_type)]} {
        return [list false "Unknown file type: $file_type"]
    }

    set valid_extensions $FILE_VALIDATION_RULES($file_type)
    if {[lsearch -exact $valid_extensions $extension] == -1} {
        return [list false "Invalid extension '$extension' for $file_type. Expected: [join $valid_extensions {, }]"]
    }

    if {![regexp {^[a-zA-Z][a-zA-Z0-9_]*$} $basename]} {
        return [list false "Invalid block name '$basename'. Must start with letter and contain only letters, numbers, and underscores"]
    }

    return [list true "Valid filename format"]
}

# ┌─ MMMC Utility Functions ───────────────────────────────────────────────────┐
proc is_mmmc_stage {stage_name} {
    global flow
    return [expr {[lsearch $flow(mmmc,enabled_stages) $stage_name] != -1}]
}

proc load_mmmc_config {} {
    global flow FLOW_DIR

    if {!$flow(mmmc,enabled)} {
        return false
    }

    set mmmc_config_path "$FLOW_DIR/config/$flow(mmmc,config_file)"
    if {[file exists $mmmc_config_path]} {
        source $mmmc_config_path
        # puts "INFO: MMMC configuration loaded from $mmmc_config_path"
        return true
    } else {
        puts "WARNING: MMMC enabled but config file not found: $mmmc_config_path"
        return false
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        SECTION 9: FLAT MODE CONFIGURATION                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Node type classification and flat mode execution configuration for all flows.
# This section defines which nodes are data nodes (file management) vs execution nodes (tool execution).

# ┌─ Node Type Classification Arrays ──────────────────────────────────────────┐
# Node types: "data" (file management) or "execution" (tool execution)

# All Flow Node Classifications (combined array)
# Ensure these arrays are in global namespace regardless of sourcing context
global node_types flat_data_sequence flat_execution_nodes flat_merged_nodes

array set ::node_types {
    synth,inputs        "data"
    synth,synthesis     "execution"
    synth,export_data   "data"
    synth,release_data  "data"

    fp,inputs           "data"
    fp,import_design    "execution"
    fp,floorplan        "execution"
    fp,powerplan        "execution"
    fp,post_floorplan   "execution"
    fp,export_data      "data"
    fp,release_data     "data"

    pnr,inputs          "data"
    pnr,import_design   "execution"
    pnr,place           "execution"
    pnr,cts             "execution"
    pnr,route           "execution"
    pnr,post_route      "execution"
    pnr,chip_finish     "execution"
    pnr,export_data     "data"
    pnr,release_data    "data"

    sta,inputs          "data"
    sta,mmmc_setup      "execution"
    sta,extraction      "execution"
    sta,timing_setup    "execution"
    sta,timing_hold     "execution"
    sta,reporting       "execution"
    sta,export_data     "data"
    sta,release_data    "data"

    fct,inputs          "data"
    fct,sta_setup       "execution"
    fct,sta_hold        "execution"
    fct,export_data     "data"
    fct,release_data    "data"

    synth_pnr,inputs        "data"
    synth_pnr,synthesis       "execution"
    synth_pnr,place     "execution"
    synth_pnr,cts "execution"
    synth_pnr,cts_opt "execution"
    synth_pnr,route    "execution"
    synth_pnr,pro     "execution"
    synth_pnr,signoff   "execution"
    synth_pnr,export_data    "data"
    synth_pnr,release_data  "data"

    lec,inputs          "data"
    lec,conformal       "execution"
    lec,export_data     "data"
    lec,release_data    "data"
}

# ┌─ Flat Mode Merged Node Configuration ─────────────────────────────────────┐
# Defines target merged node names and which execution nodes to merge

# Merged execution node names for each flow
array set ::flat_merged_nodes {
    SYNTH   "synthesis_merged"
    FP      "floorplan_merged"
    PNR     "place_and_route_merged"
    STA     "timing_analysis_merged"
    LEC     "equivalence_check_merged"
    EMIR    "power_analysis_merged"
    PV    "physical_verification_merged"
    ECO     "engineering_change_merged"
    CLP     "low_power_verification_merged"
    POPT    "power_optimization_merged"
    FCFP    "fullchip_floorplan_merged"
    SYNTH_PNR "synthesis_place_and_route_merged"
}

# Execution nodes to merge for each flow (data nodes remain separate)
array set ::flat_execution_nodes {
    SYNTH   {synthesis}
    FP      {import_design floorplan powerplan post_floorplan}
    PNR     {import_design place cts route post_route chip_finish}
    STA     {mmmc_setup extraction timing_setup timing_hold reporting}
    LEC     {conformal}
    EMIR    {power_analysis thermal_analysis}
    PV    {drc lvs erc perc}
    ECO     {eco_analysis eco_implementation}
    CLP     {low_power_check}
    POPT    {power_opt clock_gating}
    FCFP    {fullchip_floorplan fullchip_powerplan}
    SYNTH_PNR {synthesis place cts cts_opt route pro signoff}
}

# Data node execution sequence (always individual, never merged)
array set ::flat_data_sequence {
    SYNTH   {inputs export_data release_data}
    FP      {inputs export_data release_data}
    PNR     {inputs export_data release_data}
    STA     {inputs export_data release_data}
    LEC     {inputs export_data release_data}
    EMIR    {inputs export_data release_data}
    PV    {inputs export_data release_data}
    ECO     {inputs export_data release_data}
    CLP     {inputs export_data release_data}
    POPT    {inputs export_data release_data}
    FCFP    {inputs export_data release_data}
    SYNTH_PNR {inputs export_data release_data}
}

# ┌─ Flat Mode Utility Functions ─────────────────────────────────────────────┐

# Get node type for a specific flow and stage
proc get_node_type {flow_type stage} {
    global node_types
    set key "[string tolower $flow_type],$stage"
    if {[info exists node_types($key)]} {
        return $node_types($key)
    }
    # Default to execution if not explicitly defined as data
    return "execution"
}

# Get list of data nodes for a flow
proc get_data_nodes {flow_type} {
    global flat_data_sequence
    # Convert flow_type to uppercase for consistency
    set flow_key [string toupper $flow_type]
    if {[info exists flat_data_sequence($flow_key)]} {
        return $flat_data_sequence($flow_key)
    }
    return {}
}

# Get list of execution nodes for a flow
proc get_execution_nodes {flow_type} {
    global flat_execution_nodes
    # Convert flow_type to uppercase for consistency
    set flow_key [string toupper $flow_type]
    if {[info exists flat_execution_nodes($flow_key)]} {
        return $flat_execution_nodes($flow_key)
    }
    return {}
}

# Get merged node name for a flow
proc get_merged_node_name {flow_type} {
    global flat_merged_nodes
    # Convert flow_type to uppercase for consistency
    set flow_key [string toupper $flow_type]
    if {[info exists flat_merged_nodes($flow_key)]} {
        return $flat_merged_nodes($flow_key)
    }
    return "${flow_key}_merged"
}

# Validate flat mode configuration for a flow
proc validate_flat_config {flow_type} {
    set data_nodes [get_data_nodes $flow_type]
    set execution_nodes [get_execution_nodes $flow_type]
    set merged_name [get_merged_node_name $flow_type]

    if {[llength $data_nodes] == 0 && [llength $execution_nodes] == 0} {
        return [list false "No nodes defined for flow $flow_type (checked: [string toupper $flow_type])"]
    }

    if {[llength $execution_nodes] == 0} {
        return [list false "No execution nodes defined for flat mode in flow $flow_type"]
    }

    return [list true "Flat mode configuration valid for $flow_type - Data nodes: [llength $data_nodes], Execution nodes: [llength $execution_nodes]"]
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              FINAL MESSAGE                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# puts "INFO: Flow configuration with MMMC support loaded successfully"
# puts "INFO: Configuration sections: Branding, Project, Flow, Team, Tools, Runtime, Directories, Files, Validation, Release, Advanced"

# ═══════════════════════════════════════════════════════════════════════════════
# END OF CONFIGURATION FILE
# ═══════════════════════════════════════════════════════════════════════════════