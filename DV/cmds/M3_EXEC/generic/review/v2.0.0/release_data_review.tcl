#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV M3_EXEC — Release Data Command File
# Collects every review-stage signoff from work/<stage>/outputs/ and emits
# a MANIFEST.json summarizing the full review audit trail.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "M3_EXEC"
set STAGE_NAME "release_data"
set NODE_NAME "release_data1"

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME

flow_proc collect_signoffs {
    set run_dir $::env(CBFLOW_RUN_DIR)
    handle_info "Collecting review signoffs for $::FLOW_TYPE..."

    set signoff_dir "$::OUTPUTS_DIR"
    file mkdir "$signoff_dir/review_signoffs"

    # Build MANIFEST.json listing every stage's review_signoff.txt
    set manifest "$signoff_dir/MANIFEST.json"
    set fh [open $manifest "w"]
    puts $fh "{"
    puts $fh "  \"flow\":  \"$::FLOW_TYPE\","
    puts $fh "  \"generated\": \"[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]\","
    puts $fh "  \"signoffs\": \["

    set flow_lower [string tolower $::FLOW_TYPE]
    set stages_list {}
    if {[info exists ::${flow_lower}(stages)]} {
        set stages_list [set ::${flow_lower}(stages)]
    }

    set entries [list]
    foreach s $stages_list {
        if {$s eq "inputs" || $s eq "release_data1"} { continue }
        set src "$run_dir/work/$::FLOW_TYPE/$s/outputs/review_signoff.txt"
        set dst "$signoff_dir/review_signoffs/${s}.txt"
        if {[file exists $src]} {
            file copy -force $src $dst
            lappend entries "    {\"stage\": \"$s\", \"signoff\": \"review_signoffs/${s}.txt\", \"status\": \"REVIEWED\"}"
        } else {
            lappend entries "    {\"stage\": \"$s\", \"signoff\": null, \"status\": \"MISSING\"}"
        }
    }
    puts $fh [join $entries ",\n"]
    puts $fh "  \]"
    puts $fh "}"
    close $fh
    handle_info "Manifest written: $manifest ([llength $entries] stages)"
}

flow_proc validate_release {
    handle_info "Validating release manifest..."
    if {![file exists "$::OUTPUTS_DIR/MANIFEST.json"]} {
        error "Missing MANIFEST.json in $::OUTPUTS_DIR"
    }
    handle_info "Release validation passed"
}

flow_exec_all
