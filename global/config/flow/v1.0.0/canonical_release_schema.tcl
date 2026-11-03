#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║      CBflow — Canonical Release Folder Schema                               ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Authoritative map of artifact-type → folder-name used by every discipline's
# release output. Enforced by the static_checks.py cat7 check so an RTL run
# can hand off to PD by TAG alone, without per-input path overrides.
#
# Sourced by release_config.tcl on load. Node_configs reference the maps via
# `$canonical_file_type($ext) → <folder>` when staging files.
#
# Rules:
#   1. If an artifact of a known type (netlist/sdc/upf/def/gds/spef/lib) is
#      staged, its destination folder MUST be the canonical name.
#   2. Discipline-specific artifact folders are allowed via
#      `discipline_folders(<DISC>)` — additive, never override canonical.
#   3. `reports/` and `data/` are always safe fallback folders.

# ── Canonical folders every discipline recognizes ─────────────────────────────
set canonical_folders {
    netlist sdc upf def gds spef lib
    rtl icl pdl tcd tsdb spec dict mbist bscan patterns tap sim
    reports manifests violations waivers
    data
}

# ── Extension → canonical folder ──────────────────────────────────────────────
# Case-insensitive; the check normalizes extensions to lowercase.
set canonical_file_type(v)    netlist
set canonical_file_type(sv)   netlist
set canonical_file_type(vg)   netlist
set canonical_file_type(sdc)  sdc
set canonical_file_type(upf)  upf
set canonical_file_type(def)  def
set canonical_file_type(gds)  gds
set canonical_file_type(oas)  gds
set canonical_file_type(spef) spef
set canonical_file_type(lib)  lib
set canonical_file_type(ndm)  lib
# `.db` intentionally omitted — ambiguous between Liberty compiled DB and
# tool-state database (CLP/ECO use `db/<name>.db` for Verdi/Innovus state).
# Reports + waivers are extension-agnostic — anything in reports/ is a report.
# Static check does not force report extensions into canonical folders.

# ── Discipline-specific folders (allowed, additive) ───────────────────────────
# Any discipline's release_types,*,files block may stage artifacts into these
# folders in addition to the canonical set. The static check accepts them
# as valid destinations.
set discipline_folders(PD)  {}
set discipline_folders(DFT) {dft_inserted_design icl pdl mbist bscan tsdb spec}
set discipline_folders(DV)  {}
set discipline_folders(RTL) {clean_rtl validated}
