#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      PHYSICAL VERIFICATION FLOW CONFIGURATION               ║
# ║                              Node-Specific Settings                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# This file contains all PV flow specific configurations organized
# under a single pv() array structure for clean configuration management.
#
# Usage: source config/flow/v1.0.0/node_configs/PV_config.tcl

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         PV CONFIGURATION ARRAY                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# +- Flow Stage Definitions ----------------------------------------------+
array set pv {
    stages {inputs1 drc1 lvs1 erc1 perc1 merge_data1 release_data1}

    subnodes,inputs1 {setup netlist def gds validate finish}
    subnodes,drc1 {setup run validate finish}
    subnodes,lvs1 {setup run validate finish}
    subnodes,erc1 {setup run validate finish}
    subnodes,perc1 {setup run validate finish}
    subnodes,merge_data1 {setup run validate finish}
    subnodes,release_data1 {setup run validate finish}
}

# +- Stage Dependencies --------------------------------------------------+
array set pv {
    dependencies,inputs1 {}
    dependencies,drc1 {inputs1}
    dependencies,lvs1 {inputs1}
    dependencies,erc1 {inputs1}
    dependencies,perc1 {inputs1}
    dependencies,merge_data1 {drc1 lvs1 erc1 perc1}
    dependencies,release_data1 {merge_data1}
}

# +- Subnode Dependencies ------------------------------------------------+
# inputs stage subnodes
# drc stage subnodes
# lvs stage subnodes
# erc stage subnodes
# perc stage subnodes
# merge_data stage subnodes
# release_data stage subnodes
array set pv {
    subnode_dependencies,inputs1,setup {}
    subnode_dependencies,inputs1,netlist {setup}
    subnode_dependencies,inputs1,def {setup}
    subnode_dependencies,inputs1,gds {setup}
    subnode_dependencies,inputs1,validate {netlist def gds}
    subnode_dependencies,inputs1,finish {validate}

    subnode_dependencies,drc1,setup {}
    subnode_dependencies,drc1,run {setup}
    subnode_dependencies,drc1,validate {run}
    subnode_dependencies,drc1,finish {validate}

    subnode_dependencies,lvs1,setup {}
    subnode_dependencies,lvs1,run {setup}
    subnode_dependencies,lvs1,validate {run}
    subnode_dependencies,lvs1,finish {validate}

    subnode_dependencies,erc1,setup {}
    subnode_dependencies,erc1,run {setup}
    subnode_dependencies,erc1,validate {run}
    subnode_dependencies,erc1,finish {validate}

    subnode_dependencies,perc1,setup {}
    subnode_dependencies,perc1,run {setup}
    subnode_dependencies,perc1,validate {run}
    subnode_dependencies,perc1,finish {validate}

    subnode_dependencies,merge_data1,setup {}
    subnode_dependencies,merge_data1,run {setup}
    subnode_dependencies,merge_data1,validate {run}
    subnode_dependencies,merge_data1,finish {validate}

    subnode_dependencies,release_data1,setup {}
    subnode_dependencies,release_data1,run {setup}
    subnode_dependencies,release_data1,validate {run}
    subnode_dependencies,release_data1,finish {validate}
}

# +- Tool Configuration --------------------------------------------------+
array set pv {
    tool,vendor "synopsys"
    tool,name "icv"
    tool,version "v1.0.0"
    tool,args "-batch -no_gui"
    supported_tools {calibre icv pvs}
    default_tool "icv"
}

# +- Runtime Settings ----------------------------------------------------+
array set pv {
    runtime,timeout,inputs1 20
    runtime,timeout,drc1 90
    runtime,timeout,lvs1 60
    runtime,timeout,erc1 45
    runtime,timeout,perc1 30
    runtime,timeout,merge_data1 15
    runtime,timeout,release_data1 10
}

# +- Subnode Input Type Mappings -----------------------------------------+
array set pv {
    subnode_input_types,inputs1,netlist "netlist_inputs"
    subnode_input_types,inputs1,def "def_inputs"
    subnode_input_types,inputs1,gds "gds_inputs"
}

# +- Subnode Working Directories -----------------------------------------+
array set pv {
    subnode_work_dirs,inputs1,setup "work/inputs/setup"
    subnode_work_dirs,inputs1,netlist "work/inputs/netlist"
    subnode_work_dirs,inputs1,def "work/inputs/def"
    subnode_work_dirs,inputs1,gds "work/inputs/gds"
    subnode_work_dirs,inputs1,validate "work/inputs/validate"
    subnode_work_dirs,inputs1,finish "work/inputs/finish"

    subnode_work_dirs,drc1,setup "work/drc/setup"
    subnode_work_dirs,drc1,run "work/drc/run"
    subnode_work_dirs,drc1,validate "work/drc/validate"
    subnode_work_dirs,drc1,finish "work/drc/finish"

    subnode_work_dirs,lvs1,setup "work/lvs/setup"
    subnode_work_dirs,lvs1,run "work/lvs/run"
    subnode_work_dirs,lvs1,validate "work/lvs/validate"
    subnode_work_dirs,lvs1,finish "work/lvs/finish"

    subnode_work_dirs,erc1,setup "work/erc/setup"
    subnode_work_dirs,erc1,run "work/erc/run"
    subnode_work_dirs,erc1,validate "work/erc/validate"
    subnode_work_dirs,erc1,finish "work/erc/finish"

    subnode_work_dirs,perc1,setup "work/perc/setup"
    subnode_work_dirs,perc1,run "work/perc/run"
    subnode_work_dirs,perc1,validate "work/perc/validate"
    subnode_work_dirs,perc1,finish "work/perc/finish"

    subnode_work_dirs,merge_data1,setup "work/merge_data/setup"
    subnode_work_dirs,merge_data1,run "work/merge_data/run"
    subnode_work_dirs,merge_data1,validate "work/merge_data/validate"
    subnode_work_dirs,merge_data1,finish "work/merge_data/finish"

    subnode_work_dirs,release_data1,setup "work/release_data/setup"
    subnode_work_dirs,release_data1,run "work/release_data/run"
    subnode_work_dirs,release_data1,validate "work/release_data/validate"
    subnode_work_dirs,release_data1,finish "work/release_data/finish"
}

# +- Stage Type Mappings and Descriptions --------------------------------+
array set pv {
    stage_types,inputs1 "inputs"
    stage_types,drc1 "execution"
    stage_types,lvs1 "execution"
    stage_types,erc1 "execution"
    stage_types,perc1 "execution"
    stage_types,merge_data1 "data"
    stage_types,release_data1 "release_data"

    node_types,inputs1 "inputs"
    node_types,drc1 "drc"
    node_types,lvs1 "lvs"
    node_types,erc1 "erc"
    node_types,perc1 "perc"
    node_types,merge_data1 "merge_data"
    node_types,release_data1 "release_data"

    node_descriptions,inputs1 "Input file validation and preparation (6 subnodes: setup, netlist, def, gds, validate, finish)"
    node_descriptions,drc1 "Design rule checking verification (4 subnodes: setup, run, validate, finish)"
    node_descriptions,lvs1 "Layout vs schematic verification (4 subnodes: setup, run, validate, finish)"
    node_descriptions,erc1 "Electrical rule checking verification (4 subnodes: setup, run, validate, finish)"
    node_descriptions,perc1 "Parasitic extraction rule checking (4 subnodes: setup, run, validate, finish)"
    node_descriptions,merge_data1 "Physical verification data merge (4 subnodes: setup, run, validate, finish)"
    node_descriptions,release_data1 "Physical verification deliverables (4 subnodes: setup, run, validate, finish)"
}

# +- File Requirements ---------------------------------------------------+
array set pv {
    critical_files,inputs1 {pv(input,netlist) pv(input,def) pv(input,gds)}
    critical_files,drc1 {pv(input,gds)}
    critical_files,lvs1 {pv(input,netlist) pv(input,gds)}
    critical_files,erc1 {pv(input,gds)}
    critical_files,perc1 {pv(input,gds)}

    mandatory_outputs,drc1 {results/drc/drc.rpt}
    mandatory_outputs,lvs1 {results/lvs/lvs.rpt}
    mandatory_outputs,erc1 {results/erc/erc.rpt}
    mandatory_outputs,perc1 {results/perc/perc.rpt}
    mandatory_outputs,merge_data1 {results/verification/verification_summary.rpt}

    optional_files,inputs1 {pv(input,calibre_rules)}
}

# +- Mandatory Input Groups ----------------------------------------------+
array set pv {
    mandatory_input_groups {
        netlist_inputs {pv(input,netlist)}
        def_inputs {pv(input,def)}
        gds_inputs {pv(input,gds)}
    }
}

# +- Release Configuration -----------------------------------------------+
array set pv {
    release_types,verification,description "Physical verification reports and sign-off data"
    release_types,verification,files {
        "results/drc/drc.rpt" "reports/drc_verification.rpt"
        "results/lvs/lvs.rpt" "reports/lvs_verification.rpt"
        "results/erc/erc.rpt" "reports/erc_verification.rpt"
        "results/perc/perc.rpt" "reports/perc_verification.rpt"
        "results/verification/verification_summary.rpt" "reports/verification_summary.rpt"
    }
}

# ┌─ Verification Control Variables ─────────────────────────────────────────┐
array set pv {
    input,rule_deck_drc        ""
    input,rule_deck_lvs        ""
    input,rule_deck_erc        ""
    input,rule_deck_perc       ""
    input,lvs_reference_netlist ""
    drc,abort_limit            0
    drc,max_results            1000
    lvs,property_mapping       ""
    lvs,abort_on_mismatch      false
    output,report_dir          "reports/pv"
    output,results_dir         "results/pv"
    output,work_dir            "work/PV"
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                              INITIALIZATION                                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Configuration loading marker
if {![info exists ::pv_config_loaded]} {
    puts "INFO: PV configuration loaded successfully - [llength $pv(stages)] stages, [expr {[llength $pv(subnodes,inputs1)] + [llength $pv(subnodes,drc1)] + [llength $pv(subnodes,lvs1)] + [llength $pv(subnodes,erc1)] + [llength $pv(subnodes,perc1)] + [llength $pv(subnodes,merge_data1)] + [llength $pv(subnodes,release_data1)]}] total subnodes"
    set ::pv_config_loaded true
}

# ═══════════════════════════════════════════════════════════════════════════════
# END OF PV CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════