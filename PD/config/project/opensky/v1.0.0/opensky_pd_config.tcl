#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — opensky (PD overlay)
# =============================================================================

if {[info exists ::env(PROJECT_ROOT)]} {
    set ROOT_DIR $::env(PROJECT_ROOT)
} elseif {[info exists cbflow(root)]} {
    set ROOT_DIR [file dirname $cbflow(root)]
} else {
    set ROOT_DIR [file dirname [file dirname [file dirname [file dirname [file normalize [info script]]]]]]
}
set project(root_dir)      $ROOT_DIR
set project(workarea_path) "/Users/vmerugu/projects/CBflow_clone/workarea"

;# Technology — SkyWater SKY130, sky130_fd_sc_hd, li1 + 5 metals
set project(track_variant)  "hd"
set project(metal_stack)    "5M"
;# sky130A PDK (copied from the CBflow tool container by cbflow-oss setup)
set project(lib_root)       "/Users/vmerugu/eda/pdks/sky130A"
;# Library tags (library-manager generate --tag OSS0) — outside CBFLOW_ROOT
set project(lib_tag_root)   "/Users/vmerugu/eda/lib_tags"
set project(lib_config_tag) "OSS0"

set project(race,db_path) "/Users/vmerugu/projects/CBflow_clone/.race_area/opensky"

;# Release paths
set project(release,path)        "/Users/vmerugu/projects/CBflow_clone/test_releases"
set project(release,phase)       "P0"
set project(release,block_name)  ""
set project(release,active_tag)  "BTO"
set project(release,expiry_date) "2027-12-31"

set project(lsf,enabled)       "false"
set project(lsf,default_queue) "M"

;# Open-source tool stack (vendor "opensource")
set project(default_tools) {
    SYNTH     "yosys"
    PNR       "openroad"
    STA       "opensta"
    PV        "magic"
}

set project(validation,global_waivers)   {}
set project(validation,critical_errors)  {
    ".*[Ee]rror.*segmentation.*fault.*"
    ".*[Ff]atal.*"
    ".*[Aa]bort.*"
    ".*[Cc]ore.*dumped.*"
}
set project(release,structure) {
    "netlist" "sdc" "def" "gds" "spef" "reports" "data" "db" "lef" "lib"
}
