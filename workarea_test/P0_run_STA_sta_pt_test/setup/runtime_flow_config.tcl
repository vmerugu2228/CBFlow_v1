# CBFlow Runtime Flow Configuration
# Generated: 2026-05-13 12:42:04
# Custom nodes and branches for STA flow

array set sta {
    stages,extraction2,type extraction
    stages,extraction2,dependencies library1
    stages,extraction2,branch_key extraction_20260513_124129_276
    stages,release_data2,type release_data
    stages,release_data2,dependencies reporting2
    stages,release_data2,branch_key extraction_20260513_124129_276
    stages,release_data3,type release_data
    stages,release_data3,dependencies reporting3
    stages,release_data3,branch_key timing_20260513_124134_843
    stages,release_data4,type release_data
    stages,release_data4,dependencies reporting4
    stages,release_data4,branch_key extraction_20260513_124204_887
    stages,reporting2,type reporting
    stages,reporting2,dependencies timing2
    stages,reporting2,branch_key extraction_20260513_124129_276
    stages,reporting3,type reporting
    stages,reporting3,dependencies timing2
    stages,reporting3,branch_key timing_20260513_124134_843
    stages,reporting4,type reporting
    stages,reporting4,dependencies timing3
    stages,reporting4,branch_key extraction_20260513_124204_887
    stages,timing2,type timing
    stages,timing2,dependencies extraction2
    stages,timing2,branch_key extraction_20260513_124129_276
    stages,timing3,type timing
    stages,timing3,dependencies extraction2
    stages,timing3,branch_key extraction_20260513_124204_887
    branch_keys,extraction_20260513_124129_276,name "extraction1_branch1"
    branch_keys,extraction_20260513_124129_276,created_date "2026-05-13 12:41:29"
    branch_keys,extraction_20260513_124129_276,created_by "vmerugu"
    branch_keys,extraction_20260513_124204_887,name "extraction2_branch2"
    branch_keys,extraction_20260513_124204_887,created_date "2026-05-13 12:42:04"
    branch_keys,extraction_20260513_124204_887,created_by "vmerugu"
    branch_keys,timing_20260513_124134_843,name "timing2_branch2"
    branch_keys,timing_20260513_124134_843,created_date "2026-05-13 12:41:34"
    branch_keys,timing_20260513_124134_843,created_by "vmerugu"
}

