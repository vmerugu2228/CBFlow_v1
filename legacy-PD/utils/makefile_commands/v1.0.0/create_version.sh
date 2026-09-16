#!/bin/bash
#===============================================================================
# Create Version Script for CBFlow
# Handles version creation with auto-increment
#===============================================================================

# Function to show usage
show_usage() {
    echo "Usage: ./create_version.sh DIR DESC [VERSION_TYPE|VERSION]"
    echo "   OR: make create_version DIR=<directory> DESC=\"description\" VERSION_TYPE=<major|minor|patch>"
    echo "   OR: make create_version DIR=<directory> DESC=\"description\" VERSION=<version>"
    echo ""
    echo "Auto-Versioning Examples (Recommended):"
    echo "  ./create_version.sh config \"Updated config\" minor"
    echo "  ./create_version.sh config/global \"Global configs\" patch"
    echo "  ./create_version.sh utils/version \"Version scripts\" major"
    echo "  ./create_version.sh cmds/SYNTH \"Synthesis commands\" patch"
    echo ""
    echo "Manual Version Examples:"
    echo "  ./create_version.sh config \"Updated config\" v2.0.0"
}

# Check required parameters
if [ -z "$1" ] || [ -z "$2" ]; then
    show_usage
    exit 1
fi

DIR="$1"
DESC="$2"
VERSION_OR_TYPE="$3"

# Determine if it's a version type or explicit version
if [[ "$VERSION_OR_TYPE" =~ ^(major|minor|patch)$ ]]; then
    # Auto-versioning
    VERSION_TYPE="$VERSION_OR_TYPE"
    AUTO_VERSION=$(python3 utils/version/current/auto_version_manager.py get_next_version "$DIR" "$VERSION_TYPE")
    echo "Auto-generated version: $AUTO_VERSION ($VERSION_TYPE increment)"
    FINAL_VERSION="$AUTO_VERSION"
    VERSION_TYPE_FOR_CHANGELOG="$VERSION_TYPE"
elif [[ "$VERSION_OR_TYPE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Manual version
    FINAL_VERSION="$VERSION_OR_TYPE"
    echo "Using specified version: $FINAL_VERSION"
    VERSION_TYPE_FOR_CHANGELOG="manual"
else
    echo "ERROR: Invalid version type or version format"
    echo "Version type must be: major, minor, or patch"
    echo "Version format must be: vX.Y.Z (e.g., v1.2.3)"
    echo ""
    show_usage
    exit 1
fi

# Create version (directory-based, no Git)
echo "Creating version $FINAL_VERSION for $DIR..."
python3 utils/version/current/flow_version_manager.py create_version "$DIR" "$FINAL_VERSION" "$DESC"

# Update changelog
echo "Updating changelog for $DIR..."
python3 utils/version/current/changelog_manager.py "$DIR" "$FINAL_VERSION" "$DESC" "$VERSION_TYPE_FOR_CHANGELOG"

echo "Version $FINAL_VERSION created successfully for $DIR"
