#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FP — Inputs Subnode Handler (Cadence Innovus)
# Subnodes: setup, netlist, sdc, def, upf, library, validate, finish
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "FP"

set ::flow_type "FP"
set stage_name "inputs"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set test_mode [handler_is_test_mode]

# Helper: create input info file
proc write_input_info {run_dir flow_type node_name input_type} {
    set info_dir "$run_dir/work/$flow_type/$node_name/$input_type"
    file mkdir $info_dir
    set info_file "$info_dir/${input_type}_info.tcl"
    set fh [open $info_file "w"]
    puts $fh "set ${input_type}_info(timestamp) \"[clock format [clock seconds]]\""
    puts $fh "set ${input_type}_info(status) \"loaded\""
    close $fh
    return $info_file
}

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        # Create subdirectories for each input type
        foreach _dir {netlist sdc def upf library} {
            file mkdir "$run_dir/work/$::flow_type/$node_name/$_dir"
        }
        puts "INFO: $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: FP $stage_name netlist..."
        set _net_dir "$run_dir/work/$::flow_type/$node_name/netlist"
        file mkdir $_net_dir
        set _design $::flow(design_name)
        if {[info exists ::fp(input,netlist)] && $::fp(input,netlist) ne ""} {
            set _src $::fp(input,netlist)
            set _dst "$_net_dir/${_design}.v"
            if {[file exists $_src] && ![file exists $_dst]} {
                file link -symbolic $_dst $_src
            }
            puts "INFO: Netlist linked: ${_design}.v -> [file tail $_src]"
        }
        write_input_info $run_dir $::flow_type $node_name "netlist"
        puts "INFO: FP $stage_name netlist completed"
    }
    "sdc" {
        puts "INFO: FP $stage_name sdc..."
        set _sdc_dir "$run_dir/work/$::flow_type/$node_name/sdc"
        file mkdir $_sdc_dir
        set _design $::flow(design_name)

        # Link all SDC modes as <design_name>.<mode>.sdc
        # Reads from fp(input,sdc_<mode>_file) or sta(input,sdc,<mode>)
        foreach _mode {func test scan} {
            set _src ""
            if {[info exists ::fp(input,sdc_${_mode}_file)] && $::fp(input,sdc_${_mode}_file) ne ""} {
                set _src $::fp(input,sdc_${_mode}_file)
            } elseif {[info exists ::fp(input,sdc,${_mode})] && $::fp(input,sdc,${_mode}) ne ""} {
                set _src $::fp(input,sdc,${_mode})
            }
            if {$_src ne ""} {
                set _dst "$_sdc_dir/${_design}.${_mode}.sdc"
                if {[file exists $_src] && ![file exists $_dst]} {
                    file link -symbolic $_dst $_src
                }
                puts "INFO: SDC linked: ${_design}.${_mode}.sdc -> [file tail $_src]"
            }
        }
        write_input_info $run_dir $::flow_type $node_name "sdc"
        puts "INFO: FP $stage_name sdc completed"
    }
    "def" {
        puts "INFO: FP $stage_name def..."
        set _def_dir "$run_dir/work/$::flow_type/$node_name/def"
        file mkdir $_def_dir
        set _design $::flow(design_name)
        if {[info exists ::fp(input,def_file)] && $::fp(input,def_file) ne ""} {
            set _src $::fp(input,def_file)
            set _dst "$_def_dir/${_design}.def"
            if {[file exists $_src] && ![file exists $_dst]} {
                file link -symbolic $_dst $_src
            }
            puts "INFO: DEF linked: ${_design}.def -> [file tail $_src]"
        }
        write_input_info $run_dir $::flow_type $node_name "def"
        puts "INFO: FP $stage_name def completed"
    }
    "upf" {
        puts "INFO: FP $stage_name upf..."
        set _upf_dir "$run_dir/work/$::flow_type/$node_name/upf"
        file mkdir $_upf_dir
        set _design $::flow(design_name)
        if {[info exists ::fp(input,upf_file)] && $::fp(input,upf_file) ne ""} {
            set _src $::fp(input,upf_file)
            set _dst "$_upf_dir/${_design}.upf"
            if {[file exists $_src] && ![file exists $_dst]} {
                file link -symbolic $_dst $_src
            }
            puts "INFO: UPF linked: ${_design}.upf -> [file tail $_src]"
        }
        write_input_info $run_dir $::flow_type $node_name "upf"
        puts "INFO: FP $stage_name upf completed"
    }
    "library" {
        puts "INFO: FP $stage_name library..."
        set _lib_dir "$run_dir/work/$::flow_type/$node_name/library"
        file mkdir $_lib_dir
        # Library info is resolved from tech_config via config.tcl — just write info
        write_input_info $run_dir $::flow_type $node_name "library"
        puts "INFO: FP $stage_name library completed"
    }
    "validate" {
        puts "INFO: $stage_name validate..."
        handler_validate $run_dir $::flow_type $node_name $stage_name $test_mode
        puts "INFO: $stage_name validate completed"
    }
    "finish" {
        puts "INFO: $stage_name finish..."
        handler_finish $run_dir $::flow_type $node_name $stage_name
        puts "INFO: $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown inputs subnode: $subnode_name"
        exit 1
    }
}
