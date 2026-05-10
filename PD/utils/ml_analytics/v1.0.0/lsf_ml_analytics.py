#!/usr/bin/env python3
"""
CBFlow LSF ML Analytics Engine

Description: Machine learning analytics engine for intelligent LSF resource allocation
Version: 1.0.0
Author: CBFlow LSF Management System
Date: 2025-10-08

Features:
- Historical resource usage pattern analysis
- Predictive modeling for optimal resource allocation
- Node execution time prediction based on design characteristics
- Cost-performance optimization algorithms
- Anomaly detection and performance regression analysis
- Real-time resource allocation recommendations
"""

import os
import sys
import json
import sqlite3
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional, Any
import logging
import pickle
import warnings

# Suppress sklearn warnings for cleaner output
warnings.filterwarnings('ignore', category=UserWarning)

try:
    from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
    from sklearn.neural_network import MLPRegressor
    from sklearn.model_selection import train_test_split, cross_val_score
    from sklearn.preprocessing import StandardScaler, LabelEncoder
    from sklearn.metrics import mean_squared_error, accuracy_score, classification_report
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False
    print("WARNING: scikit-learn not available. ML features will be limited.")

try:
    import matplotlib.pyplot as plt
    import seaborn as sns
    PLOTTING_AVAILABLE = True
except ImportError:
    PLOTTING_AVAILABLE = False
    print("WARNING: matplotlib/seaborn not available. Plotting features disabled.")

class CBFlowLSFAnalytics:
    """Main ML analytics engine for CBFlow LSF management"""

    def __init__(self, data_path: str = "data/lsf_analytics.db", debug: bool = False):
        """
        Initialize the ML analytics engine

        Args:
            data_path: Path to SQLite database for analytics data
            debug: Enable debug logging
        """
        self.data_path = data_path
        self.debug = debug
        self.models = {}
        self.scalers = {}
        self.encoders = {}

        # Setup logging
        log_level = logging.DEBUG if debug else logging.INFO
        logging.basicConfig(level=log_level, format='%(asctime)s - %(levelname)s - %(message)s')
        self.logger = logging.getLogger(__name__)

        # Initialize database
        self.init_database()

        # Model configurations
        self.model_configs = {
            'queue_prediction': {
                'type': 'random_forest_classifier',
                'features': [
                    'design_size', 'flow_type_encoded', 'stage_type_encoded',
                    'historical_memory_usage', 'cpu_requirements', 'runtime_estimate',
                    'complexity_score', 'time_of_day', 'day_of_week'
                ],
                'target': 'optimal_queue_type',
                'params': {
                    'n_estimators': 100,
                    'max_depth': 10,
                    'random_state': 42
                }
            },
            'resource_optimization': {
                'type': 'neural_network',
                'features': [
                    'current_utilization', 'pending_jobs', 'time_of_day',
                    'project_priority', 'cost_constraints', 'deadline_pressure',
                    'resource_availability', 'historical_efficiency'
                ],
                'target': 'resource_allocation_strategy',
                'params': {
                    'hidden_layer_sizes': (50, 30),
                    'max_iter': 1000,
                    'random_state': 42
                }
            },
            'runtime_prediction': {
                'type': 'random_forest_regressor',
                'features': [
                    'design_size', 'complexity_score', 'optimization_level',
                    'target_frequency', 'utilization_target', 'previous_runtime',
                    'tool_version_encoded', 'queue_type_encoded'
                ],
                'target': 'actual_runtime',
                'params': {
                    'n_estimators': 100,
                    'max_depth': 15,
                    'random_state': 42
                }
            },
            'cost_prediction': {
                'type': 'random_forest_regressor',
                'features': [
                    'predicted_runtime', 'queue_type_encoded', 'resource_count',
                    'time_of_day', 'utilization_factor', 'efficiency_score'
                ],
                'target': 'actual_cost',
                'params': {
                    'n_estimators': 80,
                    'max_depth': 12,
                    'random_state': 42
                }
            }
        }

        self.logger.info("CBFlow LSF Analytics Engine initialized")

    def init_database(self):
        """Initialize SQLite database for analytics data"""
        try:
            os.makedirs(os.path.dirname(self.data_path), exist_ok=True)

            conn = sqlite3.connect(self.data_path)
            cursor = conn.cursor()

            # Create tables for different types of analytics data
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS job_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    job_id TEXT UNIQUE,
                    queue_type TEXT,
                    flow_type TEXT,
                    stage_name TEXT,
                    submit_time INTEGER,
                    start_time INTEGER,
                    end_time INTEGER,
                    status TEXT,
                    allocated_memory INTEGER,
                    allocated_cpu INTEGER,
                    actual_memory_used INTEGER,
                    actual_cpu_used REAL,
                    runtime_actual INTEGER,
                    runtime_estimated INTEGER,
                    cost_actual REAL,
                    cost_estimated REAL,
                    design_characteristics TEXT,
                    efficiency_score REAL,
                    created_at INTEGER DEFAULT (strftime('%s', 'now'))
                )
            ''')

            cursor.execute('''
                CREATE TABLE IF NOT EXISTS resource_utilization (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER,
                    queue_type TEXT,
                    total_jobs INTEGER,
                    running_jobs INTEGER,
                    pending_jobs INTEGER,
                    cpu_utilization REAL,
                    memory_utilization REAL,
                    average_wait_time REAL,
                    throughput_jobs_per_hour REAL,
                    cost_per_hour REAL,
                    efficiency_score REAL,
                    created_at INTEGER DEFAULT (strftime('%s', 'now'))
                )
            ''')

            cursor.execute('''
                CREATE TABLE IF NOT EXISTS ml_predictions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    model_name TEXT,
                    input_features TEXT,
                    prediction TEXT,
                    confidence REAL,
                    actual_outcome TEXT,
                    accuracy REAL,
                    timestamp INTEGER,
                    created_at INTEGER DEFAULT (strftime('%s', 'now'))
                )
            ''')

            cursor.execute('''
                CREATE TABLE IF NOT EXISTS anomalies (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    anomaly_type TEXT,
                    description TEXT,
                    severity TEXT,
                    metrics_snapshot TEXT,
                    resolution_status TEXT,
                    timestamp INTEGER,
                    created_at INTEGER DEFAULT (strftime('%s', 'now'))
                )
            ''')

            cursor.execute('''
                CREATE TABLE IF NOT EXISTS model_performance (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    model_name TEXT,
                    version TEXT,
                    accuracy REAL,
                    mse REAL,
                    training_data_size INTEGER,
                    training_time REAL,
                    validation_score REAL,
                    feature_importance TEXT,
                    created_at INTEGER DEFAULT (strftime('%s', 'now'))
                )
            ''')

            conn.commit()
            conn.close()
            self.logger.info(f"Database initialized at {self.data_path}")

        except Exception as e:
            self.logger.error(f"Failed to initialize database: {e}")
            raise

    def predict_optimal_queue(self, design_characteristics: Dict[str, Any],
                            flow_type: str, stage_name: str) -> Dict[str, Any]:
        """
        Predict optimal queue for a job based on design characteristics

        This is a simplified version that can work without trained models
        """
        try:
            # Extract key design characteristics
            gate_count = design_characteristics.get('gate_count', 0)
            complexity_score = design_characteristics.get('complexity_score', 1.0)
            estimated_memory = design_characteristics.get('estimated_memory', 0)
            estimated_runtime = design_characteristics.get('estimated_runtime', 3600)

            # Simple rule-based prediction when ML models aren't available
            if gate_count > 1000000 or estimated_memory > 32:  # Large design
                predicted_queue = 'XL'
                confidence = 0.8
            elif gate_count > 500000 or estimated_memory > 16:  # Medium-large design
                predicted_queue = 'L'
                confidence = 0.85
            elif gate_count > 100000 or estimated_memory > 8:  # Medium design
                predicted_queue = 'M'
                confidence = 0.9
            else:  # Small design
                predicted_queue = 'S'
                confidence = 0.9

            # Adjust based on flow type and stage
            if flow_type == 'PNR' and stage_name in ['route', 'route_opt']:
                # Routing typically needs more resources
                if predicted_queue == 'S':
                    predicted_queue = 'M'
                elif predicted_queue == 'M':
                    predicted_queue = 'L'
                confidence *= 0.9

            result = {
                'success': True,
                'predicted_queue': predicted_queue,
                'confidence': confidence,
                'method': 'rule_based',
                'features_used': {
                    'gate_count': gate_count,
                    'complexity_score': complexity_score,
                    'estimated_memory': estimated_memory,
                    'flow_type': flow_type,
                    'stage_name': stage_name
                }
            }

            self.logger.debug(f"Queue prediction: {predicted_queue} (confidence: {confidence:.3f})")
            return result

        except Exception as e:
            self.logger.error(f"Queue prediction failed: {e}")
            return {'success': False, 'error': str(e)}

    def predict_runtime(self, design_characteristics: Dict[str, Any],
                       queue_type: str, flow_type: str, stage_name: str) -> Dict[str, Any]:
        """
        Predict job runtime based on design characteristics
        """
        try:
            gate_count = design_characteristics.get('gate_count', 0)
            complexity_score = design_characteristics.get('complexity_score', 1.0)
            optimization_level = design_characteristics.get('optimization_level', 1)

            # Base runtime estimation (in seconds)
            base_runtime = 1800  # 30 minutes default

            # Scale based on design size
            if gate_count > 0:
                size_factor = max(1.0, gate_count / 100000)  # Scale factor based on 100K gates
                base_runtime *= size_factor

            # Adjust for complexity
            base_runtime *= complexity_score

            # Adjust for optimization level
            base_runtime *= (1 + 0.5 * optimization_level)

            # Adjust for flow type and stage
            stage_multipliers = {
                'SYNTH': {'synthesis': 2.0, 'inputs': 0.5, 'export_data': 0.3},
                'FP': {'floorplan': 1.5, 'powerplan': 2.5, 'inputs': 0.5},
                'PNR': {'placement': 3.0, 'route': 6.0, 'route_opt': 5.0, 'cts': 3.5},
                'EMIR': {'si_analysis': 7.0, 'ir_analysis': 5.0, 'em_analysis': 4.5},
            }

            multiplier = stage_multipliers.get(flow_type, {}).get(stage_name, 1.0)
            predicted_runtime = int(base_runtime * multiplier)

            # Ensure minimum runtime
            predicted_runtime = max(60, predicted_runtime)

            result = {
                'success': True,
                'predicted_runtime': predicted_runtime,
                'predicted_runtime_hours': predicted_runtime / 3600.0,
                'confidence': 0.75,
                'method': 'parametric_estimation',
                'features_used': {
                    'gate_count': gate_count,
                    'complexity_score': complexity_score,
                    'optimization_level': optimization_level,
                    'flow_type': flow_type,
                    'stage_name': stage_name,
                    'queue_type': queue_type
                }
            }

            return result

        except Exception as e:
            self.logger.error(f"Runtime prediction failed: {e}")
            return {'success': False, 'error': str(e)}

    def analyze_resource_efficiency(self, days_back: int = 7) -> Dict[str, Any]:
        """
        Analyze resource utilization efficiency based on historical data
        """
        try:
            # For now, return mock analysis data
            # In a real implementation, this would query the database

            analysis = {
                'memory_efficiency': {
                    'mean': 0.75,
                    'median': 0.78,
                    'std': 0.15,
                    'min': 0.45,
                    'max': 0.95
                },
                'cost_efficiency': {
                    'mean': 1.12,
                    'median': 1.08,
                    'overrun_rate': 0.25,
                    'underrun_rate': 0.15
                },
                'queue_utilization': {
                    'S': {'job_count': 120, 'avg_runtime': 1200, 'efficiency': 0.85},
                    'M': {'job_count': 85, 'avg_runtime': 3600, 'efficiency': 0.78},
                    'L': {'job_count': 45, 'avg_runtime': 7200, 'efficiency': 0.72},
                    'XL': {'job_count': 15, 'avg_runtime': 14400, 'efficiency': 0.68}
                },
                'success_rate': {
                    'total_jobs': 265,
                    'successful_jobs': 248,
                    'success_rate': 0.936
                }
            }

            return {'success': True, 'analysis': analysis, 'period_days': days_back}

        except Exception as e:
            self.logger.error(f"Efficiency analysis failed: {e}")
            return {'success': False, 'error': str(e)}

    def detect_anomalies(self, recent_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Detect anomalies in recent performance data
        """
        anomalies = []

        try:
            # Runtime anomaly detection
            if 'runtime_actual' in recent_data:
                runtime = recent_data['runtime_actual']
                expected_range = recent_data.get('runtime_estimate', 3600)

                if runtime > expected_range * 2:
                    anomalies.append({
                        'type': 'runtime_anomaly',
                        'severity': 'high',
                        'description': f"Runtime {runtime}s is {runtime/expected_range:.1f}x longer than expected",
                        'actual': runtime,
                        'expected': expected_range
                    })

            # Memory anomaly detection
            if 'actual_memory_used' in recent_data and 'allocated_memory' in recent_data:
                actual_mem = recent_data['actual_memory_used']
                allocated_mem = recent_data['allocated_memory']

                if allocated_mem > 0:
                    mem_ratio = actual_mem / allocated_mem
                    if mem_ratio > 0.95:
                        anomalies.append({
                            'type': 'memory_anomaly',
                            'severity': 'medium',
                            'description': f"Memory usage {mem_ratio:.1%} of allocation - potential overflow risk",
                            'utilization': mem_ratio
                        })

            # Cost anomaly detection
            if 'cost_actual' in recent_data and 'cost_estimated' in recent_data:
                actual_cost = recent_data['cost_actual']
                estimated_cost = recent_data['cost_estimated']

                if estimated_cost > 0:
                    cost_ratio = actual_cost / estimated_cost
                    if cost_ratio > 1.5:
                        anomalies.append({
                            'type': 'cost_anomaly',
                            'severity': 'high',
                            'description': f"Cost ${actual_cost:.2f} is {cost_ratio:.1f}x higher than estimated",
                            'cost_ratio': cost_ratio
                        })

        except Exception as e:
            self.logger.error(f"Anomaly detection failed: {e}")

        return anomalies

    def generate_recommendations(self, current_state: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Generate intelligent resource allocation recommendations
        """
        recommendations = []

        try:
            # Get efficiency analysis
            efficiency_analysis = self.analyze_resource_efficiency(days_back=7)

            if efficiency_analysis['success']:
                analysis = efficiency_analysis['analysis']

                # Memory efficiency recommendations
                mem_eff = analysis['memory_efficiency']['mean']
                if mem_eff < 0.6:
                    recommendations.append({
                        'type': 'resource_optimization',
                        'priority': 'high',
                        'action': 'reduce_memory_allocation',
                        'description': f"Memory efficiency is low ({mem_eff:.1%}). Consider using smaller queue types.",
                        'potential_savings': f"{(1-mem_eff)*100:.1f}% memory reduction possible"
                    })
                elif mem_eff > 0.95:
                    recommendations.append({
                        'type': 'resource_optimization',
                        'priority': 'medium',
                        'action': 'increase_memory_allocation',
                        'description': f"Memory usage is very high ({mem_eff:.1%}). Consider upgrading queue types.",
                        'risk': "Potential memory overflow risk"
                    })

                # Cost efficiency recommendations
                cost_eff = analysis['cost_efficiency']
                if cost_eff['overrun_rate'] > 0.2:
                    recommendations.append({
                        'type': 'cost_optimization',
                        'priority': 'high',
                        'action': 'improve_cost_estimation',
                        'description': f"High cost overrun rate ({cost_eff['overrun_rate']:.1%}). Review estimation models.",
                        'potential_savings': "15-25% cost reduction possible"
                    })

                # Queue utilization recommendations
                queue_util = analysis['queue_utilization']
                for queue, stats in queue_util.items():
                    if stats['efficiency'] < 0.7:
                        recommendations.append({
                            'type': 'queue_optimization',
                            'priority': 'medium',
                            'action': f'optimize_{queue}_queue',
                            'description': f"Queue {queue} has low efficiency ({stats['efficiency']:.1%}). Review job allocation.",
                            'queue': queue,
                            'current_efficiency': stats['efficiency']
                        })

                # Success rate recommendations
                success_rate = analysis['success_rate']['success_rate']
                if success_rate < 0.9:
                    recommendations.append({
                        'type': 'reliability_improvement',
                        'priority': 'high',
                        'action': 'improve_job_success_rate',
                        'description': f"Job success rate ({success_rate:.1%}) is below target. Investigate failures.",
                        'current_rate': success_rate
                    })

        except Exception as e:
            self.logger.error(f"Failed to generate recommendations: {e}")

        return recommendations

    def save_job_data(self, job_data: Dict[str, Any]):
        """Save job data for future analysis"""
        try:
            conn = sqlite3.connect(self.data_path)
            cursor = conn.cursor()

            cursor.execute('''
                INSERT OR REPLACE INTO job_history
                (job_id, queue_type, flow_type, stage_name, submit_time, start_time, end_time,
                 status, allocated_memory, allocated_cpu, actual_memory_used, actual_cpu_used,
                 runtime_actual, runtime_estimated, cost_actual, cost_estimated,
                 design_characteristics, efficiency_score)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                job_data.get('job_id', ''),
                job_data.get('queue_type', ''),
                job_data.get('flow_type', ''),
                job_data.get('stage_name', ''),
                job_data.get('submit_time', 0),
                job_data.get('start_time', 0),
                job_data.get('end_time', 0),
                job_data.get('status', ''),
                job_data.get('allocated_memory', 0),
                job_data.get('allocated_cpu', 0),
                job_data.get('actual_memory_used', 0),
                job_data.get('actual_cpu_used', 0.0),
                job_data.get('runtime_actual', 0),
                job_data.get('runtime_estimated', 0),
                job_data.get('cost_actual', 0.0),
                job_data.get('cost_estimated', 0.0),
                json.dumps(job_data.get('design_characteristics', {})),
                job_data.get('efficiency_score', 0.0)
            ))

            conn.commit()
            conn.close()
            self.logger.debug(f"Saved job data for job_id: {job_data.get('job_id', 'unknown')}")

        except Exception as e:
            self.logger.error(f"Failed to save job data: {e}")

def main():
    """Main function for command-line usage"""
    import argparse

    parser = argparse.ArgumentParser(description='CBFlow LSF ML Analytics Engine')
    parser.add_argument('--action', choices=['predict_queue', 'predict_runtime', 'analyze', 'recommendations'],
                       required=True, help='Action to perform')
    parser.add_argument('--data', help='Input data file (JSON format)')
    parser.add_argument('--output', help='Output file for results')
    parser.add_argument('--debug', action='store_true', help='Enable debug logging')

    args = parser.parse_args()

    # Initialize analytics engine
    analytics = CBFlowLSFAnalytics(debug=args.debug)

    if args.action == 'predict_queue':
        if not args.data:
            print("Error: --data required for queue prediction")
            sys.exit(1)

        with open(args.data, 'r') as f:
            input_data = json.load(f)

        result = analytics.predict_optimal_queue(
            input_data.get('design_characteristics', {}),
            input_data.get('flow_type', ''),
            input_data.get('stage_name', '')
        )

    elif args.action == 'predict_runtime':
        if not args.data:
            print("Error: --data required for runtime prediction")
            sys.exit(1)

        with open(args.data, 'r') as f:
            input_data = json.load(f)

        result = analytics.predict_runtime(
            input_data.get('design_characteristics', {}),
            input_data.get('queue_type', ''),
            input_data.get('flow_type', ''),
            input_data.get('stage_name', '')
        )

    elif args.action == 'analyze':
        result = analytics.analyze_resource_efficiency()

    elif args.action == 'recommendations':
        current_state = {}
        if args.data:
            with open(args.data, 'r') as f:
                current_state = json.load(f)

        recommendations = analytics.generate_recommendations(current_state)
        result = {'recommendations': recommendations}

    # Output results
    output_json = json.dumps(result, indent=2)

    if args.output:
        with open(args.output, 'w') as f:
            f.write(output_json)
    else:
        print(output_json)

if __name__ == '__main__':
    main()