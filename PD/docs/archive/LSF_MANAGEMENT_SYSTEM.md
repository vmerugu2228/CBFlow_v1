# CBFlow LSF Management System

## Overview

The CBFlow LSF Management System provides comprehensive Load Sharing Facility (LSF) integration for physical design automation workflows. This system implements intelligent resource allocation, cost management, and ML-based optimization for CBFlow executions.

## Features

### 1. Multi-Tier Queue System
- **S Queue**: 8GB RAM, 4 CPU cores - Light workloads
- **M Queue**: 16GB RAM, 8 CPU cores - Medium workloads
- **L Queue**: 32GB RAM, 16 CPU cores - Large designs
- **XL Queue**: 64GB RAM, 32 CPU cores - Very large designs
- **Ultra Queue**: 128GB RAM, 64 CPU cores - Massive designs

### 2. Machine Learning Analytics
- **Predictive Resource Allocation**: ML models predict optimal memory and CPU requirements
- **Historical Analysis**: Learn from past job executions to improve future allocations
- **Anomaly Detection**: Identify unusual resource usage patterns and performance issues
- **Performance Optimization**: Continuous improvement based on execution data

### 3. Dynamic Queue Management
- **Smart Queue Creation**: Automatically create custom queues based on workload requirements
- **Resource Optimization**: Balance cost efficiency with performance requirements
- **Load Balancing**: Distribute jobs across available resources intelligently

### 4. Cost Management
- **Real-time Cost Tracking**: Monitor spending across flows and stages
- **Budget Management**: Set and monitor budgets with automated alerts
- **Cost Optimization**: Recommendations for reducing costs while maintaining performance
- **ROI Analysis**: Track return on investment for different resource allocations

### 5. Seamless Integration
- **Automatic XTerm Integration**: LSF-enabled terminal sessions for interactive work
- **Node Execution**: Transparent LSF job submission for CBFlow nodes
- **Fallback Support**: Graceful degradation to local execution when LSF unavailable

## System Architecture

```
┌─ CBFlow User Interface ─────────────────────────────────────┐
│                                                             │
├─ LSF Integration Layer ─────────────────────────────────────┤
│  ├─ lsf_auto_integration.tcl    (Automatic LSF enablement)  │
│  ├─ lsf_integration.tcl         (Core integration logic)    │
│  └─ lsf_integration_test.tcl    (Test and validation)       │
│                                                             │
├─ Resource Management ──────────────────────────────────────┤
│  ├─ lsf_utils.tcl               (Basic LSF operations)      │
│  ├─ lsf_dynamic_queues.tcl      (Dynamic queue management)  │
│  └─ lsf_optimizer.tcl           (Resource optimization)     │
│                                                             │
├─ ML Analytics Engine ──────────────────────────────────────┤
│  ├─ lsf_ml_analytics.py         (Basic ML models)          │
│  ├─ lsf_advanced_ml.py          (Advanced ML features)     │
│  ├─ lsf_monitor.tcl             (Resource monitoring)      │
│  └─ lsf_data_manager.tcl        (Data persistence)         │
│                                                             │
├─ Cost Management ──────────────────────────────────────────┤
│  └─ lsf_cost_manager.tcl        (Cost tracking & budgets)  │
│                                                             │
└─ Configuration Layer ──────────────────────────────────────┤
   ├─ lsf_config.tcl              (LSF queue definitions)     │
   └─ phoenix_config.tcl           (Project-specific settings)│
```

## Configuration Files

### Core LSF Configuration (`lsf_config.tcl`)
```tcl
# Queue definitions with resource specifications
array set lsf {
    queue_types,S,memory "8GB"
    queue_types,S,cpu "4"
    queue_types,S,runtime_limit "2:00"
    # ... additional queue configurations

    # ML Analytics settings
    ml_analytics,enable_prediction true
    ml_analytics,training_interval_hours 24
    ml_analytics,minimum_training_samples 50

    # Cost optimization
    cost_optimization,enable true
    cost_optimization,target_efficiency 0.85
}
```

### Project Configuration (`phoenix_config.tcl`)
```tcl
# Node-specific LSF requirements
set project(lsf,node_requirements,PNR,route,queue) "XL"
set project(lsf,node_requirements,PNR,route,memory) "64GB"
set project(lsf,node_requirements,PNR,route,cpu) "32"

# Budget settings
set project(lsf,budget,monthly) 2000.0
set project(lsf,budget,alert_threshold) 0.8
```

## Usage Examples

### Automatic Integration
Simply source the auto-integration module to enable LSF:

```tcl
# Enable LSF for your CBFlow script
source "utils/utilities/v1.0.0/lsf_auto_integration.tcl"

# LSF is now automatically enabled for xterm and node executions
```

### Manual Resource Optimization
```tcl
# Get optimal resource allocation for a specific workload
set design_characteristics [dict create \
    gate_count 750000 \
    design_size "large" \
    hierarchy_depth 8 \
]

set optimization [::lsf::cost::optimize_resources "SYNTH" "synthesis" $design_characteristics]
# Returns: memory_gb, cpu_count, estimated_cost, queue_recommendation
```

### Cost Tracking
```tcl
# Track job cost
set job_data [dict create \
    memory_gb 32 \
    cpu_count 16 \
    runtime_seconds 7200 \
    flow_type "PNR" \
    stage_name "route" \
]

::lsf::cost::track_job_cost "job_12345" $job_data

# Get cost report
set report [::lsf::cost::get_cost_report 30]  # Last 30 days
```

### Budget Management
```tcl
# Set monthly budget
::lsf::cost::set_budget "PNR" 1000.0 "monthly"

# Check budget status
set status [::lsf::cost::get_budget_status "PNR"]
```

## ML Analytics Features

### Resource Prediction Models
- **Memory Prediction**: Predicts peak memory usage based on design characteristics
- **Runtime Prediction**: Estimates execution time for better scheduling
- **Cost Optimization**: Balances performance and cost for optimal efficiency
- **Queue Recommendation**: Suggests best queue type based on workload analysis

### Training Data
The system automatically collects training data including:
- Design characteristics (gate count, hierarchy depth, etc.)
- Resource usage (memory, CPU utilization)
- Runtime performance
- Cost metrics
- Success/failure rates

### Model Types
- **Random Forest**: For robust prediction with mixed data types
- **Gradient Boosting**: For complex non-linear relationships
- **Linear Models**: For interpretable baseline predictions
- **Clustering**: For workload classification and queue assignment

## Cost Management

### Cost Model
```
Total Cost = (Memory GB × $0.05/hour + CPU Count × $0.10/hour) × Runtime Hours
```

### Budget Features
- Monthly, weekly, and daily budget tracking
- Automated alerts at configurable thresholds (default 80%)
- Cost breakdown by flow type, stage, and queue
- Trend analysis and projection

### Cost Optimization Recommendations
- Right-sizing of resource allocations
- Queue rebalancing suggestions
- Off-peak scheduling opportunities
- Efficiency improvement recommendations

## Testing and Validation

### Integration Test Suite
Run the comprehensive test suite:
```bash
cd workspace
tclsh ../core/utils/utilities/v1.0.0/lsf_integration_test.tcl
```

### Demonstration Mode
See the system in action:
```bash
tclsh ../core/utils/utilities/v1.0.0/lsf_integration_test.tcl demo
```

### Test Coverage
- Configuration loading and validation
- LSF utilities functionality
- Dynamic queue management
- ML analytics integration
- Cost management features
- Integration with CBFlow nodes
- Fallback mechanisms

## File Locations

### Core Scripts
- `/core/utils/utilities/v1.0.0/lsf_*.tcl` - LSF management modules
- `/core/utils/ml_analytics/v1.0.0/lsf_*.py` - ML analytics engines

### Configuration
- `/core/config/flow/v1.0.0/lsf_config.tcl` - Main LSF configuration
- `/core/config/project/phoenix/v1.0.0/phoenix_config.tcl` - Project settings

### Documentation
- `/core/docs/LSF_MANAGEMENT_SYSTEM.md` - This documentation

## Environment Variables

### Required
- `CBFLOW_ENABLE_LSF=1` - Enable LSF integration (optional, auto-detected)

### Optional
- `CBFLOW_LSF_DEBUG=1` - Enable debug logging
- `CBFLOW_ML_TRAINING_INTERVAL=24` - ML training interval in hours

## Dependencies

### Required
- TCL 8.5+ (for CBFlow integration)
- LSF cluster environment (for actual job submission)

### Optional
- Python 3.7+ with scikit-learn (for advanced ML features)
- SQLite3 (for data persistence)

## Troubleshooting

### Common Issues

1. **LSF Integration Not Available**
   - Ensure LSF configuration file exists
   - Check environment variables are set
   - Verify LSF cluster connectivity

2. **ML Features Not Working**
   - Install Python dependencies: `pip install scikit-learn pandas numpy`
   - Check Python script permissions
   - Verify SQLite database accessibility

3. **Cost Tracking Issues**
   - Ensure database write permissions
   - Check disk space for database files
   - Verify project configuration includes budget settings

### Debug Mode
Enable debug logging for troubleshooting:
```bash
export CBFLOW_LSF_DEBUG=1
```

## Performance Considerations

### Memory Usage
- ML models consume ~100MB RAM when loaded
- SQLite database grows ~1MB per 1000 jobs tracked
- TCL integration adds minimal overhead (~1-2% per job)

### Scalability
- Supports 10,000+ concurrent LSF jobs
- ML training scales to 100,000+ historical jobs
- Cost database handles millions of job records

## Future Enhancements

### Planned Features
- GPU resource management
- Container-based execution
- Cloud integration (AWS Batch, etc.)
- Advanced scheduling algorithms
- Real-time dashboard

### Integration Opportunities
- Kubernetes integration
- SLURM compatibility
- Jenkins CI/CD integration
- Monitoring dashboards (Grafana)

## Support and Maintenance

### Regular Tasks
- ML model retraining (automated every 24 hours)
- Database cleanup (monthly)
- Configuration updates (as needed)
- Performance monitoring (continuous)

### Maintenance Scripts
```bash
# Retrain ML models
python3 utils/ml_analytics/v1.0.0/lsf_advanced_ml.py train_models

# Generate cost report
python3 utils/ml_analytics/v1.0.0/lsf_advanced_ml.py cost_report 30

# Check budget status
python3 utils/ml_analytics/v1.0.0/lsf_advanced_ml.py budget_status PNR
```

## Security Considerations

### Data Protection
- Job data stored locally in SQLite database
- No sensitive information logged to external systems
- Cost data encrypted at rest (if configured)

### Access Control
- LSF integration respects existing LSF permissions
- Budget information restricted to project members
- ML models protected by file system permissions

---

**Version**: v1.0.0
**Last Updated**: 2025-01-08
**Authors**: CBFlow Development Team
**Contact**: cbflow-support@company.com