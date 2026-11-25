#!/usr/bin/env bash
# =============================================================================
# install_pytools.sh — Python tools the open-source RTL / DV flows need and the
# tool image does not ship, installed for the image's python3 into
#   <tools_dir>/python            (default tools_dir: $HOME/eda/tools/oss)
# cbflow-oss exports CBFLOW_OSS_PYTHON=<tools_dir>/python (CBFLOW_OSS_TOOLS =
# lsf(oss,tools_dir)); the RTL / DV helpers put it on their own sys.path. It is
# deliberately not on PYTHONPATH: systemrdl-compiler brings antlr4-python3-runtime
# 4.13, the image's nl2bench (ATPG) needs 4.9.
#
#   SystemRDL register specs: systemrdl-compiler + PeakRDL (regblock SV,
#   UVM RAL, C header, IP-XACT, HTML).  XLS (vPlan, register sheets): openpyxl.
#   z3 (SMT solver Verilator calls for constrained randomize() — UVM
#   sequences): the z3-solver wheel's binary, copied to <tools_dir>/bin.
# Versions are pinned.
# =============================================================================
set -euo pipefail

PKGS=(
    "systemrdl-compiler==1.33.0"
    "peakrdl==1.5.0"
    "peakrdl-regblock==1.3.1"
    "peakrdl-uvm==2.4.0"
    "peakrdl-cheader==1.2.0"
    "peakrdl-ipxact==3.5.0"
    "peakrdl-html==2.12.2"
    "openpyxl==3.1.5"
    "z3-solver==4.13.4.0"
)

TOOLS_DIR="${1:-${CBFLOW_OSS_TOOLS:-$HOME/eda/tools/oss}}"
mkdir -p "$TOOLS_DIR/python"
TOOLS_DIR="$(cd "$TOOLS_DIR" && pwd -P)"
HERE="$(cd "$(dirname "$0")" && pwd)"
OSS="$HERE/../../bin/cbflow-oss"

# Built for the image's python (same interpreter the flows run).
CBFLOW_OSS_TOOLS="$TOOLS_DIR" \
    "$OSS" exec -- bash -c "pip3 install --quiet --upgrade --no-warn-script-location --target '$TOOLS_DIR/python' ${PKGS[*]} \
        && mkdir -p '$TOOLS_DIR/bin' && cp -f '$TOOLS_DIR/python/bin/z3' '$TOOLS_DIR/bin/z3' && '$TOOLS_DIR/bin/z3' --version \
        && PYTHONPATH='$TOOLS_DIR/python' python3 -c 'import systemrdl, peakrdl_regblock, peakrdl_uvm, peakrdl_cheader, peakrdl_ipxact, peakrdl_html, openpyxl; print(\"python tools OK\")'"

echo "python tools -> $TOOLS_DIR/python"
