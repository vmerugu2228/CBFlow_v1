#!/bin/bash
#===============================================================================
# Release Info Script for CBFlow
# Shows detailed information about a specific release
#===============================================================================

# Function to show usage
show_usage() {
    echo "Usage: ./release_info.sh RELEASE"
    echo ""
    echo "Examples:"
    echo "  ./release_info.sh v2.0.0"
    echo "  ./release_info.sh v1.5.3"
}

# Check required parameters
if [ -z "$1" ]; then
    echo "Error: RELEASE parameter required"
    show_usage

    # Show available releases
    echo "Available releases:"
    if [ -d "releases" ]; then
        ls -d releases/v* 2>/dev/null | xargs -n1 basename | tr '\n' ' ' || echo 'none'
    else
        echo 'none'
    fi
    exit 1
fi

RELEASE="$1"

python3 utils/version/current/flow_release_manager.py get_release_info "$RELEASE"