#!/usr/bin/env tclsh
# CBFlow PNR INPUTS Subnode Handler - Synopsys FC
if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
if {[file exists "$run_dir/.run.cbflow.tcl"]} { source "$run_dir/.run.cbflow.tcl" } else { puts "ERROR: .run.cbflow.tcl not found"; exit 1 }
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/SYNTH_PNR_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }
set ::flow_type "SYNTH_PNR"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }
set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }
switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        file mkdir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir "$run_dir/work/$::flow_type/$node_name/setup"
        file mkdir "$run_dir/work/$::flow_type/$node_name/rtl"
        file mkdir "$run_dir/work/$::flow_type/$node_name/sdc"
        file mkdir "$run_dir/work/$::flow_type/$node_name/upf"
        # Generate setup.tcl and config.tcl
        if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
            set gen_script "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
            if {[file exists $gen_script]} {
                puts "INFO: Generating setup files via generate_setup.tcl..."
                if {[catch {exec tclsh $gen_script $::flow_type $node_name ${node_name}_default $run_dir} gen_result]} {
                    puts "WARNING: generate_setup.tcl: $gen_result"
                } else {
                    puts "INFO: Setup files generated: $gen_result"
                }
            }
        }
        puts "INFO: $stage_name setup completed"
    }
    "rtl" {
        puts "INFO: SYNTH_PNR $stage_name rtl..."
        set design_name [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]
        set rtl_dir "$run_dir/work/SYNTH_PNR/$node_name/rtl"
        file mkdir $rtl_dir
        set rtl_src $synth_pnr(input,rtl_filelist)
        file copy -force $rtl_src "$rtl_dir/[file tail $rtl_src]"
        catch { file link -symbolic "$rtl_dir/${design_name}.f" $rtl_src }
        puts "INFO: RTL linked: $rtl_src -> $rtl_dir/${design_name}.f"
        puts "INFO: SYNTH_PNR $stage_name rtl completed"
    }
    "sdc" {
        puts "INFO: SYNTH_PNR $stage_name sdc..."
        set design_name [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]
        set sdc_dir "$run_dir/work/SYNTH_PNR/$node_name/sdc"
        file mkdir $sdc_dir
        set sdc_src $synth_pnr(input,sdc_func_file)
        file copy -force $sdc_src "$sdc_dir/[file tail $sdc_src]"
        catch { file link -symbolic "$sdc_dir/${design_name}.sdc" $sdc_src }
        puts "INFO: SDC linked: $sdc_src -> $sdc_dir/${design_name}.sdc"
        puts "INFO: SYNTH_PNR $stage_name sdc completed"
    }
    "upf" {
        puts "INFO: SYNTH_PNR $stage_name upf..."
        set design_name [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]
        set upf_dir "$run_dir/work/SYNTH_PNR/$node_name/upf"
        file mkdir $upf_dir
        if {[info exists synth_pnr(input,upf_file)] && $synth_pnr(input,upf_file) ne ""} {
            set upf_src $synth_pnr(input,upf_file)
            if {[file exists $upf_src]} {
                file copy -force $upf_src "$upf_dir/[file tail $upf_src]"
                catch { file link -symbolic "$upf_dir/${design_name}.upf" $upf_src }
                puts "INFO: UPF linked: $upf_src -> $upf_dir/${design_name}.upf"
            } else {
                puts "WARNING: UPF file not found: $upf_src"
            }
        } else {
            puts "INFO: No UPF specified (synth_pnr(input,upf_file) not set) — skipping"
        }
        puts "INFO: SYNTH_PNR $stage_name upf completed"
    }
    "validate" {
        puts "INFO: SYNTH_PNR $stage_name validate..."
        set design_name [expr {[info exists flow(design_name)] ? $flow(design_name) : "design"}]
        set base_dir "$run_dir/work/SYNTH_PNR/$node_name"
        set errors {}
        foreach {label dir ext} [list RTL rtl .f SDC sdc .sdc UPF upf .upf] {
            if {[file exists "$base_dir/$dir/${design_name}${ext}"]} {
                puts "INFO: $label: OK ($base_dir/$dir/${design_name}${ext})"
            } else {
                lappend errors "$label"
                puts "WARNING: $label: MISSING ($base_dir/$dir/${design_name}${ext})"
            }
        }
        if {[llength $errors] > 0} {
            puts "WARNING: Missing inputs: [join $errors {, }]"
        } else {
            puts "INFO: All inputs validated"
        }
        puts "INFO: SYNTH_PNR $stage_name validate completed"
    }
    "finish" {
        puts "INFO: SYNTH_PNR $stage_name finish..."
        set ff "$run_dir/work/SYNTH_PNR/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $ff]
        set fh [open $ff "w"]; puts $fh "set finish_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""; close $fh
        puts "INFO: SYNTH_PNR $stage_name finish completed"
    }
    default { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
}
