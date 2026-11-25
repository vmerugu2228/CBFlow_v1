#!/usr/bin/env bash
# =============================================================================
# install_atalanta.sh — build the Atalanta ATPG engine for the open-source DFT
# flow (Fault calls it with `fault atpg -g Atalanta`).
#
# Atalanta is not in the tool image, so it is built from source inside the
# image (same OS / arch / libc the tools run on) into a host directory that
# cbflow-oss mounts and puts on PATH (lsf(oss,tools_dir) → CBFLOW_OSS_TOOLS):
#
#   install_atalanta.sh [<tools_dir>]        default: $HOME/eda/tools/oss
#   → <tools_dir>/bin/atalanta
#
# The source is pinned to one commit of github.com/hsluoyz/Atalanta.
# =============================================================================
set -euo pipefail

ATALANTA_REPO="https://github.com/hsluoyz/Atalanta"
ATALANTA_COMMIT="a8e07fe4af80c55b0d4ca77e382731b03ad731dc"

TOOLS_DIR="${1:-${CBFLOW_OSS_TOOLS:-$HOME/eda/tools/oss}}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OSS="$HERE/../../bin/cbflow-oss"

mkdir -p "$TOOLS_DIR/bin" "$TOOLS_DIR/src"
TOOLS_DIR="$(cd "$TOOLS_DIR" && pwd -P)"
SRC="$TOOLS_DIR/src/atalanta"

if [ ! -d "$SRC/.git" ]; then
    git clone --quiet "$ATALANTA_REPO" "$SRC"
fi
git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet "$ATALANTA_COMMIT"

# Build inside the tool image; the host directory is mounted at the same path.
CBFLOW_OSS_MOUNTS="$TOOLS_DIR${CBFLOW_OSS_MOUNTS:+:$CBFLOW_OSS_MOUNTS}" \
    "$OSS" exec -- bash -c "cd '$SRC' && make clean >/dev/null 2>&1 || true; make -j4 && cp atalanta '$TOOLS_DIR/bin/atalanta'"

echo "atalanta ($ATALANTA_COMMIT) -> $TOOLS_DIR/bin/atalanta"
