#!/usr/bin/env bash
# =============================================================================
# install_uvm.sh — the Accellera UVM library for the open-source DV flow
# (SystemVerilog UVM on Verilator). The tool image ships Verilator but no UVM.
#
#   install_uvm.sh [<tools_dir>]        default: $HOME/eda/tools/oss
#   → <tools_dir>/uvm/<tag>/src/uvm_pkg.sv  (+ <tools_dir>/uvm/current -> <tag>)
#
# Source: github.com/accellera-official/uvm-core, pinned to one tag
# (Apache-2.0). The DV flows read it from <tools_dir>/uvm/current.
# =============================================================================
set -euo pipefail

UVM_REPO="https://github.com/accellera-official/uvm-core"
UVM_TAG="2020.3.1"
UVM_COMMIT="78c06547a2a0a29b3dc9dcafae62b75b2ff61544"   # refs/tags/2020.3.1

TOOLS_DIR="${1:-${CBFLOW_OSS_TOOLS:-$HOME/eda/tools/oss}}"
mkdir -p "$TOOLS_DIR/uvm"
TOOLS_DIR="$(cd "$TOOLS_DIR" && pwd -P)"
DST="$TOOLS_DIR/uvm/$UVM_TAG"

if [ ! -d "$DST/.git" ]; then
    git clone --quiet "$UVM_REPO" "$DST"
fi
git -C "$DST" fetch --quiet --tags origin
git -C "$DST" checkout --quiet "$UVM_COMMIT"
[ -f "$DST/src/uvm_pkg.sv" ] || { echo "install_uvm.sh: $DST/src/uvm_pkg.sv missing" >&2; exit 1; }
ln -sfn "$UVM_TAG" "$TOOLS_DIR/uvm/current"

echo "UVM $UVM_TAG ($UVM_COMMIT) -> $DST (current -> $UVM_TAG)"
