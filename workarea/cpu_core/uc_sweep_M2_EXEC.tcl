set project(name) "bumblebee"
set project(phase) "LC1"
set flow(type) "M2_EXEC"
set flow(design_name) "cpu_core"
set flow(run_name) "sweep"
set flow(test_mode) "true"
set flow(use_lsf) "false"
set flow(use_xterm) "false"

# Attach the review artifact (regression report / review doc / coverage dump).
# In test_mode=true the artifact can be any file; production needs the real path.
set m2_exec(input,review_artifact) "/Users/vmerugu/projects/CBflow_clone/inputs/cpu_core.v"

# Per-review-stage artifact overrides — point individual stages at a specific
# document (e.g. the DRS pdf for drs_review, the regression HTML for
# log_scoreboard_check). All optional; falls back to the main artifact above.
# set m2_exec(review,drs_review,artifact)         "/path/to/drs.pdf"
# set m2_exec(review,waveform_check,artifact)     "/path/to/waves.rpt"

# Skip the optional lp_plan_signoff stage if your team does not do it:
# set m2_exec(skip_stages) {lp_plan_signoff}
