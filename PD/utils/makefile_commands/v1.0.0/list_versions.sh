#!/bin/bash
#===============================================================================
# List Workspace Script for CBFlow
# Shows workspace status and all available versions
#===============================================================================

# Function to show usage
show_usage() {
    echo "Usage: ./list_workspace.sh DIR"
    echo ""
    echo "Shows workspace status and all available versions"
    echo ""
    echo "Examples:"
    echo "  ./list_workspace.sh cmds/SYNTH"
    echo "  ./list_workspace.sh config/global"
}

# Check required parameters
if [ -z "$1" ]; then
    show_usage
    exit 1
fi

DIR="$1"

python3 utils/version/current/workspace_manager.py list_versions "$DIR"