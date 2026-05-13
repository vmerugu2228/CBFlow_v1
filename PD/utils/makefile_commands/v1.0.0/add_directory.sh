#!/bin/bash
#===============================================================================
# Add Directory Script for CBFlow
# Adds a directory to version control
#===============================================================================

# Function to show usage
show_usage() {
    echo "Usage: ./add_directory.sh DIR DESC [VERSION]"
    echo ""
    echo "Examples:"
    echo "  ./add_directory.sh mycomponent \"Component description\""
    echo "  ./add_directory.sh mycomponent \"Component description\" v1.0.0"
}

# Check required parameters
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: DIR and DESC parameters required"
    show_usage
    exit 1
fi

DIR="$1"
DESC="$2"
VERSION="${3:-v1.0.0}"

echo "Adding directory $DIR to version control..."
python3 utils/version/current/flow_version_manager.py add_directory "$DIR" "$DESC" "$VERSION"
