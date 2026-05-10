# CBFlow Runtime Flow Configuration
# Generated: 2026-05-10 22:04:13
# Custom nodes and branches for SYNTH_PNR flow

array set synth_pnr {
    stages,export_data2,type export_data
    stages,export_data2,dependencies signoff2
    stages,export_data2,branch_key signoff_20260510_220413_208
    stages,place2,type place
    stages,place2,dependencies place1
    stages,release_data2,type release_data
    stages,release_data2,dependencies export_data2
    stages,release_data2,branch_key signoff_20260510_220413_208
    stages,signoff2,type signoff
    stages,signoff2,dependencies pro1
    stages,signoff2,branch_key signoff_20260510_220413_208
    branch_keys,signoff_20260510_220413_208,name "eco_fix"
    branch_keys,signoff_20260510_220413_208,created_date "2026-05-10 22:04:13"
    branch_keys,signoff_20260510_220413_208,created_by "vmerugu"
}

