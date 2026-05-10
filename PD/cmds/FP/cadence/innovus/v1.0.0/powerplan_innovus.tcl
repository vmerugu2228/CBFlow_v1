#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - FP Powerplan Stage for Innovus
# Description: Create power rings, straps, and global net connections
# Usage: Source this file in Innovus or run via CBFlow
# Output: Complete power distribution network with PG verification
# ═══════════════════════════════════════════════════════════════════════════════

# Validate required environment variables
if {![info exists ::env(FLOW_DIR)] || $::env(FLOW_DIR) eq ""} {
    puts "ERROR: FLOW_DIR not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

if {![info exists ::env(UTILITIES_VERSION)] || $::env(UTILITIES_VERSION) eq ""} {
    puts "ERROR: UTILITIES_VERSION not set. Ensure .run.cbflow.tcl is properly generated."
    exit 1
}

set flow_dir $::env(FLOW_DIR)

# Source flow utilities using release version
set utils_path "$flow_dir/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"
if {[file exists $utils_path]} {
    source $utils_path
} else {
    puts "ERROR: Cannot find flow utilities at: $utils_path"
    exit 1
}

set run_dir $::env(CBFLOW_RUN_DIR)

set WORK_DIR "$run_dir/work/FP/powerplan"
set REPORTS_DIR "$WORK_DIR/reports"
set OUTPUTS_DIR "$run_dir/outputs"
file mkdir $REPORTS_DIR
file mkdir $OUTPUTS_DIR

handle_info "Starting CBFlow FP powerplan stage for Innovus"

# Define common procedures used in config files
if {[info procs INFO] eq ""} {
    proc INFO {} {
        return "INFO"
    }
}
if {[info procs WARNING] eq ""} {
    proc WARNING {} {
        return "WARNING"
    }
}

# Define flow_proc if not already defined
if {[info procs flow_proc] eq ""} {
    proc flow_proc {name body} {
        proc $name {} $body
        handle_info "Flow procedure '$name' defined"
    }
}

# Source generated configuration file (from setup stage)
set flow_type "FP"
set config_files [list \
    "config.tcl" \
    "work/$flow_type/powerplan/run/config.tcl" \
    "../work/$flow_type/powerplan/run/config.tcl" \
]

set config_found 0
foreach config_file $config_files {
    if {[file exists $config_file]} {
        handle_info "Sourcing configuration: $config_file"
        if {[catch {source $config_file} error]} {

# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source -e $_tc }
}

# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source -e "$run_dir/setup/user_config.tcl" }
            handle_warning "Minor error in config file $config_file: $error"
            handle_info "Continuing with available configuration..."
        }
        set config_found 1
        break
    }
}

if {!$config_found} {
    handle_error "Cannot find generated config file. Run 'make powerplan_setup' first."
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# FLOW_PROC HOOKS - Powerplan Process
# ═══════════════════════════════════════════════════════════════════════════════

flow_proc create_power_rings {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Creating power rings..."

    # Get power net names from config
    set pwr_net  [expr {[info exists fp(power,vdd_net)]  ? $fp(power,vdd_net)  : "VDD"}]
    set gnd_net  [expr {[info exists fp(power,vss_net)]  ? $fp(power,vss_net)  : "VSS"}]

    # Ring parameters from config
    set ring_width   [expr {[info exists fp(power,ring_width)]   ? $fp(power,ring_width)   : 3.0}]
    set ring_spacing [expr {[info exists fp(power,ring_spacing)] ? $fp(power,ring_spacing) : 1.0}]
    set ring_offset  [expr {[info exists fp(power,ring_offset)}  ? $fp(power,ring_offset)  : 1.0}]
    set ring_layer_h [expr {[info exists fp(power,ring_layer_h)] ? $fp(power,ring_layer_h) : "M1"}]
    set ring_layer_v [expr {[info exists fp(power,ring_layer_v)] ? $fp(power,ring_layer_v) : "M2"}]

    handle_info "Power nets: $pwr_net / $gnd_net"
    handle_info "Ring width: ${ring_width}um, spacing: ${ring_spacing}um"
    handle_info "Ring layers: H=$ring_layer_h, V=$ring_layer_v"

    # Create core power rings
    addRing -nets [list $pwr_net $gnd_net] \
        -type core_rings \
        -width $ring_width \
        -spacing $ring_spacing \
        -offset $ring_offset \
        -layer [list $ring_layer_h $ring_layer_v] \
        -follow core

    # Create block-level rings around macros if configured
    if {[info exists fp(power,macro_rings)] && $fp(power,macro_rings) eq "true"} {
        set macro_ring_width   [expr {[info exists fp(power,macro_ring_width)]   ? $fp(power,macro_ring_width)   : 1.5}]
        set macro_ring_spacing [expr {[info exists fp(power,macro_ring_spacing)] ? $fp(power,macro_ring_spacing) : 0.5}]
        handle_info "Creating macro power rings (width=${macro_ring_width}um)..."

        addRing -nets [list $pwr_net $gnd_net] \
            -type block_rings \
            -width $macro_ring_width \
            -spacing $macro_ring_spacing \
            -offset $macro_ring_spacing \
            -layer [list $ring_layer_h $ring_layer_v] \
            -around each_block
    }

    handle_info "Power rings created successfully"
}

flow_proc create_power_straps {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Creating power straps..."

    # Get power net names
    set pwr_net [expr {[info exists fp(power,vdd_net)] ? $fp(power,vdd_net) : "VDD"}]
    set gnd_net [expr {[info exists fp(power,vss_net)] ? $fp(power,vss_net) : "VSS"}]

    # Strap configuration from config
    if {[info exists fp(power,straps)]} {
        foreach strap_spec $fp(power,straps) {
            array set strap_info $strap_spec
            set layer   $strap_info(layer)
            set width   $strap_info(width)
            set spacing $strap_info(spacing)
            set pitch   [expr {[info exists strap_info(pitch)]     ? $strap_info(pitch)     : [expr {$width * 10}]}]
            set dir     [expr {[info exists strap_info(direction)] ? $strap_info(direction) : "vertical"}]

            handle_info "Adding stripes on $layer: width=${width}um spacing=${spacing}um pitch=${pitch}um dir=$dir"

            addStripe -nets [list $pwr_net $gnd_net] \
                -layer $layer \
                -width $width \
                -spacing $spacing \
                -set_to_set_distance $pitch \
                -direction $dir \
                -start_from left

            array unset strap_info
        }
    } else {
        # Default strap configuration
        set strap_layer [expr {[info exists fp(power,strap_layer)} ? $fp(power,strap_layer) : "M4"}]
        set strap_width [expr {[info exists fp(power,strap_width)] ? $fp(power,strap_width) : 2.0}]
        set strap_pitch [expr {[info exists fp(power,strap_pitch)] ? $fp(power,strap_pitch) : 40.0}]

        handle_info "Using default strap config: layer=$strap_layer width=${strap_width}um pitch=${strap_pitch}um"

        addStripe -nets [list $pwr_net $gnd_net] \
            -layer $strap_layer \
            -width $strap_width \
            -spacing 1.0 \
            -set_to_set_distance $strap_pitch \
            -direction vertical \
            -start_from left
    }

    handle_info "Power straps created successfully"
}

flow_proc connect_power {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Connecting global power nets..."

    # Get power/ground net names
    set pwr_net [expr {[info exists fp(power,vdd_net)] ? $fp(power,vdd_net) : "VDD"}]
    set gnd_net [expr {[info exists fp(power,vss_net)] ? $fp(power,vss_net) : "VSS"}]

    # Get power/ground pin names
    set pwr_pin [expr {[info exists fp(power,vdd_pin)} ? $fp(power,vdd_pin) : "VDD"}]
    set gnd_pin [expr {[info exists fp(power,vss_pin)} ? $fp(power,vss_pin) : "VSS"}]

    # Connect VDD
    handle_info "Connecting $pwr_net to pin $pwr_pin on all instances..."
    globalNetConnect $pwr_net -type pgpin -pin $pwr_pin -inst * -override

    # Connect VSS
    handle_info "Connecting $gnd_net to pin $gnd_pin on all instances..."
    globalNetConnect $gnd_net -type pgpin -pin $gnd_pin -inst * -override

    # Connect tie-high/tie-low if specified
    if {[info exists fp(power,tie_high_pin)]} {
        handle_info "Connecting tie-high pin: $fp(power,tie_high_pin)"
        globalNetConnect $pwr_net -type tiehi -pin $fp(power,tie_high_pin) -inst * -override
    }

    if {[info exists fp(power,tie_low_pin)]} {
        handle_info "Connecting tie-low pin: $fp(power,tie_low_pin)"
        globalNetConnect $gnd_net -type tielo -pin $fp(power,tie_low_pin) -inst * -override
    }

    # Special rail connections for standard cells
    sroute -connect blockPin -layerChangeRange [list $fp(power,sroute_bottom_layer) $fp(power,sroute_top_layer)] \
        -nets [list $pwr_net $gnd_net] 2>/dev/null

    handle_info "Global power connections completed"
}

flow_proc verify_power {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Verifying power grid integrity..."

    # Get power/ground net names
    set pwr_net [expr {[info exists fp(power,vdd_net)] ? $fp(power,vdd_net) : "VDD"}]
    set gnd_net [expr {[info exists fp(power,vss_net)] ? $fp(power,vss_net) : "VSS"}]

    set verification_errors 0

    # Verify PG connectivity
    handle_info "Checking power/ground connectivity..."
    if {[catch {verifyConnectivity -type pgpin -net [list $pwr_net $gnd_net] \
            -report $::REPORTS_DIR/pg_connectivity.rpt} result]} {
        handle_warning "PG connectivity check reported issues: $result"
        incr verification_errors
    }

    # Verify power via DRC
    handle_info "Checking power grid geometry..."
    if {[catch {verify_pg_net -net [list $pwr_net $gnd_net] \
            -report $::REPORTS_DIR/pg_net_verify.rpt} result]} {
        handle_warning "PG net verification reported issues: $result"
        incr verification_errors
    }

    if {$verification_errors > 0} {
        handle_warning "Power verification completed with $verification_errors issue(s)"
    } else {
        handle_info "Power grid verification passed"
    }
}

flow_proc generate_reports {
    global fp project tech flow FLOW_DIR RUN_DIR ROOT_DIR
    handle_info "Generating powerplan reports..."

    # Create reports directory
    if {![file exists "reports"]} {
        file mkdir "reports"
    }

    # Power grid summary
    handle_info "Generating power grid summary..."
    if {[catch {report_power_domain > $::REPORTS_DIR/power_domain.rpt} result]} {
        handle_warning "Could not generate power domain report: $result"
    }

    # IR drop estimation if available
    if {[info exists fp(power,analyze_ir)] && $fp(power,analyze_ir) eq "true"} {
        handle_info "Running early IR drop analysis..."
        if {[catch {analyzeIR -net [expr {[info exists fp(power,vdd_net)] ? $fp(power,vdd_net) : "VDD"}] \
                -report $::REPORTS_DIR/ir_drop_estimate.rpt} result]} {
            handle_warning "IR drop analysis skipped: $result"
        }
    }

    # Power grid density report
    handle_info "Generating PG density report..."
    if {[catch {reportPGDensity > $::REPORTS_DIR/pg_density.rpt} result]} {
        handle_warning "Could not generate PG density report: $result"
    }

    handle_info "═══════════════════════════════════════════════════════════════"
    handle_info "CBFlow FP Powerplan Stage - COMPLETED SUCCESSFULLY"
    handle_info "Reports: reports/"
    handle_info "Next Stage: export_db (make export_db)"
    handle_info "═══════════════════════════════════════════════════════════════"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION FLOW
# ═══════════════════════════════════════════════════════════════════════════════

handle_info "═══════════════════════════════════════════════════════════════"
handle_info "CBFlow FP Powerplan Stage - Starting Execution"
handle_info "═══════════════════════════════════════════════════════════════"

# Execute flow procedures in sequence
set flow_steps {
    create_power_rings
    create_power_straps
    connect_power
    verify_power
    generate_reports
}

foreach step $flow_steps {
    handle_info "Executing flow step: $step"

    if {[catch {$step} error]} {
        handle_error "Flow step '$step' failed: $error"
        exit 1
    }

    handle_info "Flow step '$step' completed successfully"
}

handle_info "CBFlow FP powerplan stage completed successfully"

# Exit tool after stage completion
exit
