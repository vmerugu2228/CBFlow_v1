#!/usr/bin/env tclsh
# =============================================================================
# Cadence MMMC View Definition — Auto-Generated
# Generated: 2026-06-15 09:40 | Tech: gf_28nm | Project: denali
# Scenarios: 7 (from signoff node)
# Sourced via: read_mmmc -file <this_file>
# DO NOT EDIT — regenerate with: cbflow flow mmmc-manager generate
# =============================================================================

# -----------------------------------------------------------------------------
# Library Sets
# -----------------------------------------------------------------------------

create_library_set -name ff_1p10v_125c_ls \
    -timing $tech($project(track_variant),lib,ff_1p10v_125c,timing)

create_library_set -name ff_1p10v_25c_ls \
    -timing $tech($project(track_variant),lib,ff_1p10v_25c,timing)

create_library_set -name ff_1p10v_m40c_ls \
    -timing $tech($project(track_variant),lib,ff_1p10v_m40c,timing)

create_library_set -name ss_0p80v_125c_ls \
    -timing $tech($project(track_variant),lib,ss_0p80v_125c,timing)

create_library_set -name ss_0p80v_m40c_ls \
    -timing $tech($project(track_variant),lib,ss_0p80v_m40c,timing)

create_library_set -name ss_0p90v_125c_ls \
    -timing $tech($project(track_variant),lib,ss_0p90v_125c,timing)

create_library_set -name ss_0p90v_m40c_ls \
    -timing $tech($project(track_variant),lib,ss_0p90v_m40c,timing)

# -----------------------------------------------------------------------------
# RC Corners
# -----------------------------------------------------------------------------

create_rc_corner -name rcmax \
    -qrc_tech $tech(rcx,rc_max,qrc) \
    -T 125

create_rc_corner -name rcmin \
    -qrc_tech $tech(rcx,rc_min,qrc) \
    -T -40

# -----------------------------------------------------------------------------
# Delay Corners
# -----------------------------------------------------------------------------

create_delay_corner -name ff_1p10v_rcmin_125c_dc \
    -library_set ff_1p10v_125c_ls \
    -rc_corner rcmin

create_delay_corner -name ff_1p10v_rcmin_25c_dc \
    -library_set ff_1p10v_25c_ls \
    -rc_corner rcmin

create_delay_corner -name ff_1p10v_rcmin_m40c_dc \
    -library_set ff_1p10v_m40c_ls \
    -rc_corner rcmin

create_delay_corner -name ss_0p80v_rcmax_125c_dc \
    -library_set ss_0p80v_125c_ls \
    -rc_corner rcmax

create_delay_corner -name ss_0p80v_rcmax_m40c_dc \
    -library_set ss_0p80v_m40c_ls \
    -rc_corner rcmax

create_delay_corner -name ss_0p90v_rcmax_125c_dc \
    -library_set ss_0p90v_125c_ls \
    -rc_corner rcmax

create_delay_corner -name ss_0p90v_rcmax_m40c_dc \
    -library_set ss_0p90v_m40c_ls \
    -rc_corner rcmax

# -----------------------------------------------------------------------------
# Constraint Modes
# -----------------------------------------------------------------------------

# SDC files resolved at runtime from operating_modes array
# create_constraint_mode REQUIRES -sdc_files — error loudly if missing.
if {![info exists operating_modes(func,constraint_file)] || $operating_modes(func,constraint_file) eq ""} {
    error "MMMC: operating_modes(func,constraint_file) not set — create_constraint_mode requires -sdc_files (mode=func)"
}
create_constraint_mode -name func_cm -sdc_files [list [subst $operating_modes(func,constraint_file)]]

# -----------------------------------------------------------------------------
# Analysis Views
# -----------------------------------------------------------------------------

create_analysis_view -name func_ff_1p10v_rcmin_125c \
    -constraint_mode func_cm \
    -delay_corner ff_1p10v_rcmin_125c_dc

create_analysis_view -name func_ff_1p10v_rcmin_25c \
    -constraint_mode func_cm \
    -delay_corner ff_1p10v_rcmin_25c_dc

create_analysis_view -name func_ff_1p10v_rcmin_m40c \
    -constraint_mode func_cm \
    -delay_corner ff_1p10v_rcmin_m40c_dc

create_analysis_view -name func_ss_0p80v_rcmax_125c \
    -constraint_mode func_cm \
    -delay_corner ss_0p80v_rcmax_125c_dc

create_analysis_view -name func_ss_0p80v_rcmax_m40c \
    -constraint_mode func_cm \
    -delay_corner ss_0p80v_rcmax_m40c_dc

create_analysis_view -name func_ss_0p90v_rcmax_125c \
    -constraint_mode func_cm \
    -delay_corner ss_0p90v_rcmax_125c_dc

create_analysis_view -name func_ss_0p90v_rcmax_m40c \
    -constraint_mode func_cm \
    -delay_corner ss_0p90v_rcmax_m40c_dc

# -----------------------------------------------------------------------------
# Activate All Signoff Views
# Command files will: set_analysis_view -setup {} -hold {} (deactivate all)
# then activate only their node-specific scenarios
# -----------------------------------------------------------------------------

set_analysis_view -setup [list func_ss_0p80v_rcmax_125c func_ss_0p80v_rcmax_m40c func_ss_0p90v_rcmax_125c func_ss_0p90v_rcmax_m40c] -hold [list func_ff_1p10v_rcmin_125c func_ff_1p10v_rcmin_25c func_ff_1p10v_rcmin_m40c]

