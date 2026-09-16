# Contributing to CBFlow

## Overview

This guide explains how to contribute to CBFlow development, including coding standards, development workflows, testing requirements, and submission procedures. CBFlow welcomes contributions from the physical design automation community.

## Development Environment Setup

### Prerequisites
- **Tcl 8.6+**: Core scripting language
- **Git**: Version control system
- **Make**: Build system
- **EDA Tools**: For testing (Genus, Innovus, etc.)
- **Text Editor**: With Tcl syntax highlighting recommended

### Setting Up Development Environment
```bash
# 1. Clone CBFlow repository
git clone <cbflow-repository>
cd CBFlow/PD

# 2. Set up workspace development
cd core
make workspace_setup

# 3. Initialize development environment
make dev_init

# 4. Verify setup
make dev_validate
```

### Development Workspace Structure
```
core/
├── utils/
│   ├── [category]/
│   │   ├── workspace/          # Active development area
│   │   ├── v1.0.0/            # Current stable version
│   │   └── current/           # Symlink to active version
├── config/
├── cmds/
└── docs/
```

## Development Workflow

### Branch Strategy

#### Branch Types
- **`main`**: Stable production code
- **`develop`**: Integration branch for new features
- **`feature/`**: Feature development branches
- **`bugfix/`**: Bug fix branches
- **`release/`**: Release preparation branches

#### Workflow Process
```bash
# 1. Create feature branch from develop
git checkout develop
git pull origin develop
git checkout -b feature/new-flat-mode-optimization

# 2. Develop in workspace
cd utils/generation/workspace/
# Make your changes...

# 3. Test changes
make test_workspace

# 4. Create version when ready
make new_version VERSION=v1.1.0 CATEGORY=generation

# 5. Commit and push
git add .
git commit -m "Add flat mode optimization for generation scripts"
git push origin feature/new-flat-mode-optimization

# 6. Create pull request
# (Use your Git hosting platform's PR process)
```

### Workspace Development

#### Using Workspace Directories
```bash
# Activate workspace for category
make workspace_start CATEGORY=generation

# This sets up:
# - utils/generation/workspace/ as active development
# - Automatic backup of changes
# - Testing framework access
```

#### Workspace Commands
```bash
# Start workspace development
make workspace_start CATEGORY=generation

# Test workspace changes
make test_workspace CATEGORY=generation

# Backup workspace
make workspace_backup CATEGORY=generation

# Restore from backup
make workspace_restore BACKUP=20251007_143022 CATEGORY=generation

# Promote workspace to version
make promote_workspace CATEGORY=generation VERSION=v1.1.0
```

## Coding Standards

### Tcl Coding Standards

#### File Organization
```tcl
#!/usr/bin/env tclsh
# CBFlow [Category] - [Purpose]
# Version: [version]
# Author: [author]
# Created: [date]

# Namespace definition (if applicable)
namespace eval ::CBFlow::Category {
    variable category_data
    namespace export public_procedure
}

# Global variables (minimize use)
set global_config ""

# Procedure definitions
proc main_procedure {args} {
    # Procedure implementation
}

# Main execution (if standalone script)
if {[info script] eq $argv0} {
    main $argv
}
```

#### Naming Conventions
```tcl
# Variables: lowercase with underscores
set input_file_path "/path/to/file"
set max_retry_count 3

# Procedures: lowercase with underscores
proc process_input_files {file_list} {
    # Implementation
}

# Constants: uppercase with underscores
set MAX_TIMEOUT 3600
set DEFAULT_FLOW_TYPE "SYNTH"

# Arrays: descriptive names
array set flow_config {
    design_name "example"
    flow_type "SYNTH"
}

# Namespace procedures: CamelCase after namespace
proc ::CBFlow::Utilities::ProcessFileList {file_list} {
    # Implementation
}
```

#### Code Structure
```tcl
proc example_procedure {required_arg optional_arg {default_value ""}} {
    # 1. Input validation
    if {$required_arg eq ""} {
        error "Required argument cannot be empty"
    }

    # 2. Local variable initialization
    set result_list {}
    set error_count 0

    # 3. Main logic with error handling
    if {[catch {
        # Main processing logic
        foreach item $required_arg {
            # Process each item
            lappend result_list [process_item $item]
        }
    } error_msg]} {
        # Error handling
        puts "Error processing: $error_msg"
        return -code error $error_msg
    }

    # 4. Return result
    return $result_list
}
```

### Documentation Standards

#### Procedure Documentation
```tcl
proc ::CBFlow::Generation::GenerateRunMakefile {flow_type run_dir {options {}}} {
    # @brief Generates run-specific Makefile for given flow type
    # @param flow_type Flow type (SYNTH, FP, PNR, etc.)
    # @param run_dir Target run directory for Makefile generation
    # @param options Optional configuration options (dict)
    # @return Boolean success status
    # @throws Error if flow_type is invalid or run_dir doesn't exist
    # @example
    #   set success [GenerateRunMakefile "SYNTH" "/path/to/run"]
    #   set success [GenerateRunMakefile "FP" "/path/to/run" {flat_mode 1}]

    # Implementation...
}
```

#### File Header Documentation
```tcl
#!/usr/bin/env tclsh
#===============================================================================
# CBFlow Generation Scripts - Makefile Generation
#===============================================================================
# File: gen_run_makefile.tcl
# Purpose: Generate run-specific Makefiles for CBFlow execution
# Version: 1.0.0
# Author: CBFlow Development Team
# Created: 2025-01-15
# Modified: 2025-01-15
#
# Description:
#   This script generates customized Makefiles for specific CBFlow runs,
#   incorporating flow type, execution mode, and configuration requirements.
#   Supports both regular and flat execution modes.
#
# Dependencies:
#   - CBFlow utilities (v1.0.0+)
#   - Configuration hierarchy loaded
#   - Valid run directory structure
#
# Usage:
#   tclsh gen_run_makefile.tcl [flow_type] [run_dir] [options]
#
# Examples:
#   tclsh gen_run_makefile.tcl SYNTH /path/to/run
#   tclsh gen_run_makefile.tcl FP /path/to/run {flat_mode 1}
#===============================================================================
```

### Error Handling Standards

#### Error Handling Patterns
```tcl
# Pattern 1: Validation with early return
proc validate_input_file {file_path} {
    if {![file exists $file_path]} {
        return -code error "Input file not found: $file_path"
    }

    if {![file readable $file_path]} {
        return -code error "Input file not readable: $file_path"
    }

    return true
}

# Pattern 2: Try-catch with cleanup
proc process_with_cleanup {input_data} {
    set temp_file ""

    if {[catch {
        # Create temporary file
        set temp_file [create_temp_file $input_data]

        # Process data
        set result [process_temp_file $temp_file]

    } error_msg]} {
        # Cleanup on error
        if {$temp_file ne "" && [file exists $temp_file]} {
            file delete $temp_file
        }
        return -code error "Processing failed: $error_msg"
    }

    # Normal cleanup
    if {[file exists $temp_file]} {
        file delete $temp_file
    }

    return $result
}

# Pattern 3: Namespace-aware error handling
proc ::CBFlow::Utilities::SafeExecution {script_block} {
    if {[catch {
        uplevel 1 $script_block
    } result options]} {
        # Log error with namespace context
        ::CBFlow::Utilities::LogError "Execution failed in [namespace current]: $result"

        # Re-throw with context
        return -options $options $result
    }

    return $result
}
```

## Testing Framework

### Test Organization

#### Test Directory Structure
```
utils/[category]/
├── v1.0.0/
├── workspace/
└── tests/
    ├── unit/              # Unit tests
    ├── integration/       # Integration tests
    ├── regression/        # Regression tests
    ├── fixtures/          # Test data
    └── common/           # Common test utilities
```

#### Test Naming Conventions
```
Format: test_[function_name]_[scenario].tcl

Examples:
test_generate_makefile_basic.tcl
test_generate_makefile_flat_mode.tcl
test_validate_config_missing_params.tcl
test_create_node_invalid_type.tcl
```

### Writing Tests

#### Unit Test Template
```tcl
#!/usr/bin/env tclsh
# Unit Test: [function_name] - [scenario]

# Load testing framework
source "../common/test_framework.tcl"

# Load module under test
source "../workspace/gen_run_makefile.tcl"

# Test setup
proc setup_test {} {
    global test_env

    # Create test environment
    set test_env(temp_dir) [create_temp_directory]
    set test_env(config_file) [create_test_config]

    return true
}

# Test teardown
proc cleanup_test {} {
    global test_env

    # Clean up test environment
    if {[info exists test_env(temp_dir)]} {
        file delete -force $test_env(temp_dir)
    }
}

# Test cases
proc test_generate_makefile_basic {} {
    global test_env

    # Setup
    set flow_type "SYNTH"
    set run_dir $test_env(temp_dir)

    # Execute
    set result [generate_run_makefile $flow_type $run_dir]

    # Verify
    assert_true $result "Makefile generation should succeed"
    assert_file_exists "$run_dir/Makefile" "Makefile should be created"

    # Check Makefile content
    set makefile_content [read_file "$run_dir/Makefile"]
    assert_contains $makefile_content "synthesis:" "Should contain synthesis target"

    return true
}

proc test_generate_makefile_invalid_flow {} {
    global test_env

    # Setup
    set flow_type "INVALID"
    set run_dir $test_env(temp_dir)

    # Execute and verify error
    assert_error {
        generate_run_makefile $flow_type $run_dir
    } "Should throw error for invalid flow type"

    return true
}

# Run tests
if {[info script] eq $argv0} {
    run_test_suite {
        setup_test
        test_generate_makefile_basic
        test_generate_makefile_invalid_flow
        cleanup_test
    }
}
```

#### Integration Test Template
```tcl
#!/usr/bin/env tclsh
# Integration Test: Full workflow test

source "../common/test_framework.tcl"

proc test_complete_synthesis_workflow {} {
    # Setup complete test environment
    set test_dir [setup_integration_environment]

    # Test complete workflow
    cd $test_dir

    # 1. Create run
    assert_command_success {
        exec make create_run CONFIG=../test_config.tcl
    } "Run creation should succeed"

    # 2. Execute synthesis
    cd P0_run_SYNTH_syn
    assert_command_success {
        exec make synthesis
    } "Synthesis execution should succeed"

    # 3. Validate results
    assert_file_exists "results/SYNTH/synthesis.db" "Synthesis database should exist"
    assert_file_exists "results/SYNTH/netlist.v" "Netlist should be generated"

    # Cleanup
    cd ../..
    file delete -force $test_dir

    return true
}
```

### Test Execution

#### Running Tests
```bash
# Run unit tests for specific category
make test_unit CATEGORY=generation

# Run integration tests
make test_integration CATEGORY=generation

# Run all tests
make test_all CATEGORY=generation

# Run specific test
tclsh utils/generation/tests/unit/test_generate_makefile_basic.tcl

# Run tests with coverage
make test_coverage CATEGORY=generation
```

#### Continuous Integration
```bash
# Pre-commit testing
make pre_commit_test

# Full test suite (for CI)
make ci_test_suite

# Performance regression testing
make performance_test
```

## Code Review Process

### Review Checklist

#### Code Quality
- [ ] Follows CBFlow coding standards
- [ ] Proper error handling implemented
- [ ] Adequate documentation provided
- [ ] No hardcoded paths or values
- [ ] Appropriate use of namespaces

#### Functionality
- [ ] Code addresses stated requirements
- [ ] Edge cases handled appropriately
- [ ] Backward compatibility maintained
- [ ] Performance implications considered

#### Testing
- [ ] Unit tests provided
- [ ] Integration tests updated
- [ ] All tests pass
- [ ] Test coverage adequate

#### Documentation
- [ ] Code comments are clear and helpful
- [ ] API documentation updated
- [ ] User guide updates included (if needed)
- [ ] Changelog updated

### Review Process

#### Submitting for Review
```bash
# 1. Ensure all tests pass
make test_all CATEGORY=generation

# 2. Update documentation
# Update relevant .md files in docs/

# 3. Commit changes
git add .
git commit -m "feat: add flat mode optimization for generation

- Implement merged execution node optimization
- Add 30% performance improvement for large designs
- Update test suite for new functionality
- Update documentation with usage examples"

# 4. Push and create PR
git push origin feature/flat-mode-optimization
# Create pull request via web interface
```

#### Review Response
```bash
# Address review comments
git checkout feature/flat-mode-optimization

# Make requested changes
# ...

# Commit changes
git add .
git commit -m "fix: address review comments

- Fix error handling in edge cases
- Add missing documentation
- Update test coverage"

# Push updates
git push origin feature/flat-mode-optimization
```

## Release Process

### Version Management

#### Semantic Versioning
```
MAJOR.MINOR.PATCH

Examples:
v1.0.0 - Initial stable release
v1.0.1 - Bug fix release
v1.1.0 - New feature release
v2.0.0 - Breaking changes release
```

#### Creating Releases
```bash
# 1. Prepare release branch
git checkout develop
git checkout -b release/v1.1.0

# 2. Update version information
make update_version VERSION=v1.1.0

# 3. Run comprehensive tests
make release_test_suite

# 4. Update changelog
vim CHANGELOG.md

# 5. Create release candidate
make create_release_candidate VERSION=v1.1.0

# 6. Final testing and approval
make final_release_test

# 7. Merge to main and tag
git checkout main
git merge release/v1.1.0
git tag v1.1.0
git push origin main --tags
```

### Deployment

#### Workspace to Production
```bash
# 1. Promote workspace to version
make promote_workspace CATEGORY=generation VERSION=v1.1.0

# 2. Test new version
make test_version CATEGORY=generation VERSION=v1.1.0

# 3. Deploy to production
make deploy_version CATEGORY=generation VERSION=v1.1.0

# 4. Update current symlink
make update_current CATEGORY=generation VERSION=v1.1.0
```

## Best Practices

### Development Best Practices
1. **Start Small**: Begin with small, focused changes
2. **Test Early**: Write tests as you develop
3. **Document Continuously**: Update documentation with code changes
4. **Follow Standards**: Adhere to coding and naming conventions
5. **Seek Feedback**: Engage with the community early and often

### Performance Considerations
1. **Profile Before Optimizing**: Measure performance impact
2. **Consider Memory Usage**: Monitor memory consumption
3. **Optimize I/O**: Minimize file system operations
4. **Parallel Execution**: Design for parallel execution where possible

### Security Considerations
1. **Input Validation**: Validate all external inputs
2. **Path Sanitization**: Prevent path traversal attacks
3. **Privilege Minimization**: Run with minimal required privileges
4. **Secrets Management**: Never commit sensitive information

### Maintenance
1. **Regular Refactoring**: Keep code clean and maintainable
2. **Dependency Updates**: Keep dependencies current
3. **Performance Monitoring**: Monitor performance regressions
4. **Documentation Updates**: Keep documentation current

## Community Guidelines

### Communication
- Be respectful and constructive in all interactions
- Provide clear, detailed bug reports and feature requests
- Help others in the community when possible
- Share knowledge and best practices

### Contributing Guidelines
- Follow the established development workflow
- Test your changes thoroughly
- Document new features and changes
- Respond promptly to review feedback

### Getting Help
- Check existing documentation first
- Search existing issues before creating new ones
- Provide complete information when asking for help
- Consider contributing solutions back to the community

---

Thank you for contributing to CBFlow! Your contributions help make physical design automation more accessible and efficient for everyone.