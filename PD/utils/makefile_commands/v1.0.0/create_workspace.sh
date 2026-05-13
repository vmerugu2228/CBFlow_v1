#!/bin/bash
#===============================================================================
# Copy Version Script for CBFlow
# Creates a new version by copying an existing one
#===============================================================================

# Function to show usage
show_usage() {
    echo "Usage: ./create_workspace.sh DIR FROM_VERSION TO_VERSION"
    echo ""
    echo "Creates a new version by copying an existing version directory"
    echo ""
    echo "Examples:"
    echo "  ./create_workspace.sh config/flow v1.0.0 v1.0.2"
    echo "  ./create_workspace.sh cmds/SYNTH/synopsys/fc v1.0.0 v1.0.1"
    echo ""
    echo "Workflow:"
    echo "  1. Copy version:   ./create_workspace.sh config/flow v1.0.0 v1.0.2"
    echo "  2. Edit files in:  config/flow/v1.0.2/"
    echo "  3. Set as current: ./set_version.sh config/flow v1.0.2"
}

# Check required parameters
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    show_usage
    exit 1
fi

DIR="$1"
FROM_VERSION="$2"
TO_VERSION="$3"

python3 utils/version/current/workspace_manager.py copy_version "$DIR" "$FROM_VERSION" "$TO_VERSION"
