#!/bin/bash
#===============================================================================
# Set Version Script for CBFlow
# Sets the current version for a directory component
#===============================================================================

# Function to show usage
show_usage() {
    echo "Usage: ./set_version.sh DIR VERSION"
    echo ""
    echo "Examples:"
    echo "  ./set_version.sh config v2.0.0"
    echo "  ./set_version.sh config/global v1.1.0"
    echo "  ./set_version.sh utils/version v1.5.0"
    echo "  ./set_version.sh cmds/SYNTH v1.2.0"
}

# Check required parameters
if [ -z "$1" ] || [ -z "$2" ]; then
    show_usage
    exit 1
fi

DIR="$1"
VERSION="$2"

echo "Setting current version for $DIR to $VERSION..."
echo "📌 Setting version $VERSION for $DIR - using Python backend"

# Call the backend to set the version
# python3 utils/version/current/flow_version_manager.py set_version "$DIR" "$VERSION"