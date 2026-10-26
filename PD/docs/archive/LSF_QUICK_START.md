# CBFlow LSF Management - Quick Start Guide

## Overview

The CBFlow LSF Management System provides intelligent Load Sharing Facility (LSF) integration for your physical design workflows. This guide gets you up and running in minutes.

## Prerequisites

- CBFlow environment properly configured
- Access to LSF cluster (optional - system works locally without LSF)
- Python 3.7+ with scikit-learn (optional - for advanced ML features)

## Quick Setup

### 1. Enable LSF Integration

Simply source the auto-integration module in your CBFlow scripts:

```tcl
# Add this line to any CBFlow script to enable LSF
source "utils/utilities/v1.0.0/lsf_auto_integration.tcl"
```

That's it! LSF integration is now automatically enabled.

### 2. Verify Installation

Run the test suite to verify everything is working:

```bash
cd workspace
tclsh ../core/utils/utilities/v1.0.0/lsf_integration_test.tcl
```

### 3. See It in Action

Run the demonstration:

```bash
tclsh ../core/utils/utilities/v1.0.0/lsf_integration_test.tcl demo
```

## Basic Usage

### Automatic XTerm Integration

All your existing xterm calls now automatically use LSF when available:

```tcl
# This automatically uses LSF if configured
exec xterm -title "My Tool" -e "innovus -init script.tcl" &
```

### Cost Tracking

Track costs for any job:

```tcl
# Load cost management
source "utils/utilities/v1.0.0/lsf_cost_manager.tcl"

# Track a job
set job_data [dict create \
    memory_gb 32 \
    cpu_count 16 \
    runtime_seconds 7200 \
    flow_type "PNR" \
    stage_name "route" \
]

::lsf::cost::track_job_cost "my_job_001" $job_data
```

### Get Cost Report

```tcl
# Get cost report for last 30 days
set report [::lsf::cost::get_cost_report 30]

# Display total cost
set total_cost [dict get $report total_cost]
puts "Total cost: $[format "%.2f" $total_cost]"
```

### Set Budget

```tcl
# Set monthly budget for PNR flow
::lsf::cost::set_budget "PNR" 1000.0 "monthly"

# Check budget status
set status [::lsf::cost::get_budget_status "PNR"]
puts "Budget utilization: [format "%.1f" [expr {[dict get $status budget_utilization] * 100}]]%"
```

## Queue Types

The system provides 5 pre-configured queue types:

| Queue | Memory | CPU | Best For |
|-------|--------|-----|----------|
| **S** | 8GB | 4 cores | Small designs, quick tasks |
| **M** | 16GB | 8 cores | Medium designs, synthesis |
| **L** | 32GB | 16 cores | Large designs, floorplan |
| **XL** | 64GB | 32 cores | Very large designs, P&R |
| **ultra** | 128GB | 64 cores | Massive designs, timing closure |

## Configuration Files

### Main LSF Configuration
Located at: `core/config/flow/v1.0.0/lsf_config.tcl`

### Project-Specific Settings
Located at: `core/config/project/phoenix/v1.0.0/phoenix_config.tcl`

Example project configuration:
```tcl
# Set default queue for PNR route stage
set project(lsf,node_requirements,PNR,route,queue) "XL"
set project(lsf,node_requirements,PNR,route,memory) "64GB"

# Set monthly budget
set project(lsf,budget,monthly) 2000.0
```

## Environment Variables

### Optional Configuration
```bash
export CBFLOW_ENABLE_LSF=1        # Force enable LSF integration
export CBFLOW_LSF_DEBUG=1         # Enable debug logging
```

## Common Commands

### Check Integration Status
```tcl
source "utils/utilities/v1.0.0/lsf_integration.tcl"
set status [::lsf::integration::get_integration_status]
puts "LSF enabled: [dict get $status lsf_enabled]"
```

### Get Resource Recommendation
```tcl
source "utils/utilities/v1.0.0/lsf_cost_manager.tcl"

set design_chars [dict create gate_count 500000 design_size "large"]
set recommendation [::lsf::cost::optimize_resources "SYNTH" "synthesis" $design_chars]

puts "Recommended memory: [dict get $recommendation memory_gb]GB"
puts "Recommended CPUs: [dict get $recommendation cpu_count]"
puts "Estimated cost: $[dict get $recommendation estimated_cost]"
```

### Train ML Models
```bash
# Train the ML models with your data
python3 core/utils/ml_analytics/v1.0.0/lsf_advanced_ml.py train_models
```

## Troubleshooting

### LSF Not Available
If you see "LSF integration not available", this is normal. The system automatically falls back to local execution.

### Enable Debug Mode
```bash
export CBFLOW_LSF_DEBUG=1
# Re-run your script to see detailed logging
```

### Check Configuration
```tcl
# Verify LSF configuration exists
set config_file "core/config/flow/v1.0.0/lsf_config.tcl"
if {[file exists $config_file]} {
    puts "✓ LSF configuration found"
} else {
    puts "✗ LSF configuration missing"
}
```

## Next Steps

1. **Customize Configuration**: Edit `lsf_config.tcl` and `phoenix_config.tcl` for your specific needs
2. **Set Budgets**: Configure monthly budgets for each flow type
3. **Monitor Costs**: Use the cost reports to track spending
4. **Optimize Resources**: Let the ML system learn from your jobs and optimize allocations

## Getting Help

- **Full Documentation**: See `LSF_MANAGEMENT_SYSTEM.md` for complete details
- **API Reference**: See `LSF_API_REFERENCE.md` for all available functions
- **Configuration Guide**: See `LSF_CONFIGURATION.md` for advanced setup
- **Best Practices**: See `LSF_BEST_PRACTICES.md` for optimization tips

---

**Need more help?** Check the complete documentation in the `docs/` directory or run the test suite to verify your setup.