#!/bin/bash
#===============================================================================
# Promote Version Script for CBFlow
# Promotes a version to become the current stable version
#===============================================================================

# Function to show usage
show_usage() {
    echo "Usage: ./promote_version.sh DIR VERSION"
    echo ""
    echo "Promotes a version to become the current stable version"
    echo "⚠️  WARNING: All users pointing to 'current' will see this version"
    echo ""
    echo "Examples:"
    echo "  ./promote_version.sh cmds/SYNTH v1.1.1"
    echo "  ./promote_version.sh config/global v2.0.0"
    echo ""
    echo "Safety Check:"
    echo "  ./list_versions.sh cmds/SYNTH  # View available versions first"
}

# Check required parameters
if [ -z "$1" ] || [ -z "$2" ]; then
    show_usage
    exit 1
fi

DIR="$1"
VERSION="$2"

echo "🚀 Promoting $VERSION to stable for $DIR..."
python3 utils/version/current/workspace_manager.py promote_version "$DIR" "$VERSION"