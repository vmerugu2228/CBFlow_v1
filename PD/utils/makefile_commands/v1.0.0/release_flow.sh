#!/bin/bash
#===============================================================================
# Release Flow Script for CBFlow
# Handles comprehensive flow releases with auto-increment and version overrides
#===============================================================================

# Function to show usage
show_usage() {
    echo "Usage: ./release_flow.sh [VERSION_TYPE|VERSION] [DESC] [MILESTONE] [VERSIONS]"
    echo "   OR: make release_flow VERSION_TYPE=<major|minor|patch> [DESC=\"Description\"] [MILESTONE=\"milestone\"]"
    echo "   OR: make release_flow VERSION=<version> [DESC=\"Description\"] [MILESTONE=\"milestone\"]"
    echo ""
    echo "Auto-Versioning Examples (Recommended):"
    echo "  ./release_flow.sh major \"Major release with breaking changes\""
    echo "  ./release_flow.sh minor \"New features added\""
    echo "  ./release_flow.sh patch \"Bug fixes and improvements\""
    echo ""
    echo "Manual Version Examples:"
    echo "  ./release_flow.sh v2.0.0 \"Major release\""
    echo ""
    echo "With Milestone:"
    echo "  ./release_flow.sh minor \"Q1 Release\" \"Q1_MILESTONE\""
    echo ""
    echo "With Version Overrides:"
    echo "  ./release_flow.sh v2.1.0 \"Stable release\" \"\" \"config:v1.0.0,scripts:v2.0.0\""
}

# Check if at least version type/version is provided
if [ -z "$1" ]; then
    echo "❌ ERROR: VERSION_TYPE or VERSION is required"
    show_usage
    exit 1
fi

VERSION_OR_TYPE="$1"
DESC="${2:-Automated release}"
MILESTONE="$3"
VERSIONS="$4"

# Determine version
if [[ "$VERSION_OR_TYPE" =~ ^(major|minor|patch)$ ]]; then
    # Auto-versioning
    VERSION_TYPE="$VERSION_OR_TYPE"
    AUTO_VERSION=$(python3 utils/version/current/auto_version_manager.py get_next_release_version "$VERSION_TYPE")
    echo "🔄 Auto-generated release version: $AUTO_VERSION ($VERSION_TYPE increment)"
    FINAL_VERSION="$AUTO_VERSION"
elif [[ "$VERSION_OR_TYPE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Manual version
    FINAL_VERSION="$VERSION_OR_TYPE"
    echo "📌 Using specified version: $FINAL_VERSION"
else
    echo "❌ ERROR: Invalid version type or version format"
    echo "Version type must be: major, minor, or patch"
    echo "Version format must be: vX.Y.Z (e.g., v1.2.3)"
    show_usage
    exit 1
fi

# Display release information
echo "🚀 Creating release flow $FINAL_VERSION..."
echo "📝 Description: $DESC"
if [ -n "$MILESTONE" ]; then
    echo "🎯 Milestone: $MILESTONE"
fi
if [ -n "$VERSIONS" ]; then
    echo "⚙️  Version overrides: $VERSIONS"
fi

# Auto-discover and validate version directories before creating release
echo ""
echo "🔍 Auto-discovering version directories..."
echo "==========================================="

# Run version directory discovery and validation
if [ -f "config/flow_release/v1.0.0/flow_release_config.tcl" ]; then
    # Use TCL-based discovery
    echo "📋 Running comprehensive version discovery..."

    # Get project root (parent of core)
    PROJECT_ROOT="$(cd .. && pwd)"

    # Run discovery validation
    /usr/bin/tclsh << EOF
source config/flow_release/v1.0.0/flow_release_config.tcl

# Run discovery and validation
set validation_issues [validate_discovered_versions $PROJECT_ROOT]

if {[llength \$validation_issues] > 0} {
    puts ""
    puts "⚠️  RELEASE VALIDATION ISSUES DETECTED:"
    puts "======================================"
    foreach issue \$validation_issues {
        puts "   - \$issue"
    }

    # Get suggestions for fixes
    set suggestions [suggest_missing_version_configs $PROJECT_ROOT]
    puts ""
    puts "💡 TO FIX: Add these entries to config/flow_release/v1.0.0/flow_release_config.tcl:"
    foreach suggestion \$suggestions {
        puts "   \$suggestion"
    }
    puts ""
    puts "❌ RELEASE BLOCKED: Please fix version configuration issues first"
    exit 1
} else {
    puts "✅ All discovered versions are properly configured"
    puts "   Release validation passed - proceeding with release creation"
}
EOF

    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ Release creation blocked due to version validation issues"
        echo "   Please fix the configuration issues shown above and retry"
        exit 1
    fi
else
    echo "⚠️  Release config not found, skipping auto-discovery validation"
fi

echo ""
echo "🔧 Creating hierarchical release..."
echo "=================================="

# Create hierarchical release
python3 utils/version/current/hierarchical_release_manager.py "$FINAL_VERSION" "$DESC" "$MILESTONE" "$VERSIONS"

if [ $? -eq 0 ]; then
    echo "✅ Release $FINAL_VERSION created successfully"
else
    echo "❌ Failed to create release $FINAL_VERSION"
    exit 1
fi