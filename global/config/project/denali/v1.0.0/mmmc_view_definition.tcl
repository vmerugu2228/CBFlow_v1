#!/usr/bin/env tclsh
# =============================================================================
# Cadence MMMC View Definition — Auto-Generated
# Generated: 2026-11-21 21:36 | Tech: gf_28nm | Project: denali
# Scenarios: 7 (mmmc_scenario_sets: setup + hold + signoff)
# Sourced via: read_mmmc -file <this_file>
# DO NOT EDIT — regenerate with: cbflow flow mmmc-manager generate-view-def --style flow
# =============================================================================

# Variables are referenced via the global namespace ($::) so the
# file works when sourced from inside read_mmmc (a Tcl proc).

# -----------------------------------------------------------------------------
# Library Sets
# -----------------------------------------------------------------------------

create_library_set -name ff_1p10v_125c_ls \
    -timing $::tech($::project(track_variant),lib,ff_1p10v_125c,timing)

create_library_set -name ff_1p10v_25c_ls \
    -timing $::tech($::project(track_variant),lib,ff_1p10v_25c,timing)

create_library_set -name ff_1p10v_m40c_ls \
    -timing $::tech($::project(track_variant),lib,ff_1p10v_m40c,timing)

create_library_set -name ss_0p80v_125c_ls \
    -timing $::tech($::project(track_variant),lib,ss_0p80v_125c,timing)

create_library_set -name ss_0p80v_m40c_ls \
    -timing $::tech($::project(track_variant),lib,ss_0p80v_m40c,timing)

create_library_set -name ss_0p90v_125c_ls \
    -timing $::tech($::project(track_variant),lib,ss_0p90v_125c,timing)

create_library_set -name ss_0p90v_m40c_ls \
    -timing $::tech($::project(track_variant),lib,ss_0p90v_m40c,timing)

# -----------------------------------------------------------------------------
# RC Corners (one per rc_corner x view temperature)
# -----------------------------------------------------------------------------

create_rc_corner -name rc_max_125c \
    -qrc_tech $::tech(rcx,rc_max,qrc) \
    -T 125

create_rc_corner -name rc_max_m40c \
    -qrc_tech $::tech(rcx,rc_max,qrc) \
    -T -40

create_rc_corner -name rc_min_125c \
    -qrc_tech $::tech(rcx,rc_min,qrc) \
    -T 125

create_rc_corner -name rc_min_25c \
    -qrc_tech $::tech(rcx,rc_min,qrc) \
    -T 25

create_rc_corner -name rc_min_m40c \
    -qrc_tech $::tech(rcx,rc_min,qrc) \
    -T -40

# -----------------------------------------------------------------------------
# Delay Corners
# -----------------------------------------------------------------------------

create_delay_corner -name ff_1p10v_rc_min_125c_dc \
    -library_set ff_1p10v_125c_ls \
    -rc_corner rc_min_125c

create_delay_corner -name ff_1p10v_rc_min_25c_dc \
    -library_set ff_1p10v_25c_ls \
    -rc_corner rc_min_25c

create_delay_corner -name ff_1p10v_rc_min_m40c_dc \
    -library_set ff_1p10v_m40c_ls \
    -rc_corner rc_min_m40c

create_delay_corner -name ss_0p80v_rc_max_125c_dc \
    -library_set ss_0p80v_125c_ls \
    -rc_corner rc_max_125c

create_delay_corner -name ss_0p80v_rc_max_m40c_dc \
    -library_set ss_0p80v_m40c_ls \
    -rc_corner rc_max_m40c

create_delay_corner -name ss_0p90v_rc_max_125c_dc \
    -library_set ss_0p90v_125c_ls \
    -rc_corner rc_max_125c

create_delay_corner -name ss_0p90v_rc_max_m40c_dc \
    -library_set ss_0p90v_m40c_ls \
    -rc_corner rc_max_m40c

# -----------------------------------------------------------------------------
# Constraint Modes
# -----------------------------------------------------------------------------

# SDC files resolved at runtime from operating_modes array
# create_constraint_mode REQUIRES -sdc_files — error loudly if missing.
if {![info exists ::operating_modes(func,constraint_file)] || $::operating_modes(func,constraint_file) eq ""} {
    error "MMMC: operating_modes(func,constraint_file) not set — create_constraint_mode requires -sdc_files (mode=func)"
}
create_constraint_mode -name func_cm -sdc_files [list [subst $::operating_modes(func,constraint_file)]]

# -----------------------------------------------------------------------------
# Analysis Views
# -----------------------------------------------------------------------------

create_analysis_view -name func_ff_1p10v_rc_min_125c \
    -constraint_mode func_cm \
    -delay_corner ff_1p10v_rc_min_125c_dc

create_analysis_view -name func_ff_1p10v_rc_min_25c \
    -constraint_mode func_cm \
    -delay_corner ff_1p10v_rc_min_25c_dc

create_analysis_view -name func_ff_1p10v_rc_min_m40c \
    -constraint_mode func_cm \
    -delay_corner ff_1p10v_rc_min_m40c_dc

create_analysis_view -name func_ss_0p80v_rc_max_125c \
    -constraint_mode func_cm \
    -delay_corner ss_0p80v_rc_max_125c_dc

create_analysis_view -name func_ss_0p80v_rc_max_m40c \
    -constraint_mode func_cm \
    -delay_corner ss_0p80v_rc_max_m40c_dc

create_analysis_view -name func_ss_0p90v_rc_max_125c \
    -constraint_mode func_cm \
    -delay_corner ss_0p90v_rc_max_125c_dc

create_analysis_view -name func_ss_0p90v_rc_max_m40c \
    -constraint_mode func_cm \
    -delay_corner ss_0p90v_rc_max_m40c_dc

# -----------------------------------------------------------------------------
# Activate Views (mmmc_scenario_sets setup / hold)
# Command files will: set_analysis_view -setup {} -hold {} (deactivate all)
# then activate only their node-specific scenarios
# -----------------------------------------------------------------------------

set_analysis_view -setup [list func_ss_0p80v_rc_max_125c func_ss_0p80v_rc_max_m40c func_ss_0p90v_rc_max_125c func_ss_0p90v_rc_max_m40c] -hold [list func_ff_1p10v_rc_min_125c func_ff_1p10v_rc_min_25c func_ff_1p10v_rc_min_m40c]

