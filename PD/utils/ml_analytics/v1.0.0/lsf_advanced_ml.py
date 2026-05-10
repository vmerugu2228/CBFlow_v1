#!/usr/bin/env python3
"""
Advanced ML Features for LSF Resource Management
Provides sophisticated ML models, cost management, and predictive analytics
"""

import json
import sqlite3
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import pickle
import os
import sys
from typing import Dict, List, Any, Tuple, Optional
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

try:
    from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
    from sklearn.linear_model import LinearRegression, Ridge
    from sklearn.cluster import KMeans
    from sklearn.preprocessing import StandardScaler
    from sklearn.model_selection import train_test_split, cross_val_score
    from sklearn.metrics import mean_squared_error, r2_score, mean_absolute_error
    SKLEARN_AVAILABLE = True
except ImportError:
    logger.warning("scikit-learn not available, using basic heuristics")
    SKLEARN_AVAILABLE = False

class AdvancedLSFAnalytics:
    """Advanced ML Analytics for LSF Resource Management"""

    def __init__(self, db_path: str = "/tmp/cbflow_lsf_analytics.db"):
        self.db_path = db_path
        self.models = {}
        self.scalers = {}
        self.cost_tracker = CostTracker(db_path)
        self.anomaly_detector = AnomalyDetector()
        self.budget_manager = BudgetManager(db_path)
        self.performance_optimizer = PerformanceOptimizer()

        # Initialize database
        self._init_database()

        # Load existing models
        self._load_models()

    def _init_database(self):
        """Initialize advanced analytics database tables"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Enhanced job analytics table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS advanced_job_analytics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT,
                flow_type TEXT,
                stage_name TEXT,
                submit_time INTEGER,
                start_time INTEGER,
                end_time INTEGER,
                queue_type TEXT,
                requested_memory_gb REAL,
                requested_cpu INTEGER,
                actual_memory_gb REAL,
                actual_cpu_utilization REAL,
                peak_memory_gb REAL,
                runtime_seconds INTEGER,
                queue_wait_seconds INTEGER,
                cost_dollars REAL,
                efficiency_score REAL,
                exit_status INTEGER,
                design_characteristics TEXT,
                node_hostname TEXT,
                resource_waste_factor REAL,
                performance_score REAL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Cost tracking table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS cost_tracking (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date DATE,
                flow_type TEXT,
                stage_name TEXT,
                queue_type TEXT,
                total_jobs INTEGER,
                total_cost_dollars REAL,
                total_cpu_hours REAL,
                total_memory_gb_hours REAL,
                average_efficiency REAL,
                cost_per_job REAL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Budget management table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS budget_management (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                budget_period TEXT,
                flow_type TEXT,
                allocated_budget REAL,
                spent_budget REAL,
                projected_spend REAL,
                budget_utilization REAL,
                alert_threshold REAL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Performance baselines table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS performance_baselines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flow_type TEXT,
                stage_name TEXT,
                baseline_runtime_seconds INTEGER,
                baseline_memory_gb REAL,
                baseline_cpu_utilization REAL,
                baseline_cost REAL,
                confidence_score REAL,
                sample_size INTEGER,
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        conn.commit()
        conn.close()

    def train_advanced_models(self) -> Dict[str, Any]:
        """Train advanced ML models for resource prediction"""
        if not SKLEARN_AVAILABLE:
            return {"status": "error", "message": "scikit-learn not available"}

        logger.info("Training advanced ML models...")

        # Get training data
        training_data = self._get_training_data()

        if len(training_data) < 50:
            logger.warning("Insufficient training data, using basic models")
            return {"status": "warning", "message": "Insufficient data for advanced models"}

        results = {}

        # Train memory prediction model
        memory_result = self._train_memory_prediction_model(training_data)
        results['memory_prediction'] = memory_result

        # Train runtime prediction model
        runtime_result = self._train_runtime_prediction_model(training_data)
        results['runtime_prediction'] = runtime_result

        # Train cost optimization model
        cost_result = self._train_cost_optimization_model(training_data)
        results['cost_optimization'] = cost_result

        # Train queue recommendation model
        queue_result = self._train_queue_recommendation_model(training_data)
        results['queue_recommendation'] = queue_result

        # Save models
        self._save_models()

        logger.info("Advanced ML model training completed")
        return {"status": "success", "results": results}

    def _get_training_data(self) -> pd.DataFrame:
        """Get training data from database"""
        conn = sqlite3.connect(self.db_path)

        query = '''
            SELECT
                flow_type, stage_name, requested_memory_gb, requested_cpu,
                actual_memory_gb, actual_cpu_utilization, peak_memory_gb,
                runtime_seconds, queue_wait_seconds, cost_dollars,
                efficiency_score, design_characteristics, queue_type,
                resource_waste_factor, performance_score
            FROM advanced_job_analytics
            WHERE exit_status = 0 AND runtime_seconds > 0
            ORDER BY submit_time DESC
            LIMIT 10000
        '''

        df = pd.read_sql_query(query, conn)
        conn.close()

        # Parse design characteristics
        if not df.empty:
            df = self._parse_design_characteristics(df)

        return df

    def _parse_design_characteristics(self, df: pd.DataFrame) -> pd.DataFrame:
        """Parse JSON design characteristics into separate columns"""
        characteristics = []

        for _, row in df.iterrows():
            try:
                if pd.isna(row['design_characteristics']):
                    char_dict = {}
                else:
                    char_dict = json.loads(row['design_characteristics'])

                characteristics.append({
                    'gate_count': char_dict.get('gate_count', 100000),
                    'design_size': char_dict.get('design_size', 'medium'),
                    'hierarchy_depth': char_dict.get('hierarchy_depth', 5),
                    'net_count': char_dict.get('net_count', 50000),
                    'technology_node': char_dict.get('technology_node', '7nm')
                })
            except (json.JSONDecodeError, TypeError):
                characteristics.append({
                    'gate_count': 100000,
                    'design_size': 'medium',
                    'hierarchy_depth': 5,
                    'net_count': 50000,
                    'technology_node': '7nm'
                })

        char_df = pd.DataFrame(characteristics)
        return pd.concat([df, char_df], axis=1)

    def _train_memory_prediction_model(self, data: pd.DataFrame) -> Dict[str, Any]:
        """Train memory usage prediction model"""
        if data.empty:
            return {"status": "error", "message": "No training data"}

        # Prepare features
        feature_columns = ['requested_memory_gb', 'requested_cpu', 'gate_count',
                          'hierarchy_depth', 'net_count']
        target = 'peak_memory_gb'

        # Filter available columns
        available_features = [col for col in feature_columns if col in data.columns]

        if len(available_features) < 2:
            return {"status": "error", "message": "Insufficient features"}

        X = data[available_features].fillna(0)
        y = data[target].fillna(0)

        # Remove outliers
        Q1 = y.quantile(0.25)
        Q3 = y.quantile(0.75)
        IQR = Q3 - Q1
        lower_bound = Q1 - 1.5 * IQR
        upper_bound = Q3 + 1.5 * IQR

        mask = (y >= lower_bound) & (y <= upper_bound)
        X = X[mask]
        y = y[mask]

        if len(X) < 20:
            return {"status": "error", "message": "Insufficient clean data"}

        # Split data
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

        # Scale features
        scaler = StandardScaler()
        X_train_scaled = scaler.fit_transform(X_train)
        X_test_scaled = scaler.transform(X_test)

        # Train ensemble model
        models = {
            'random_forest': RandomForestRegressor(n_estimators=100, random_state=42),
            'gradient_boost': GradientBoostingRegressor(n_estimators=100, random_state=42),
            'linear': Ridge(alpha=1.0)
        }

        best_model = None
        best_score = -np.inf
        results = {}

        for name, model in models.items():
            # Train model
            model.fit(X_train_scaled, y_train)

            # Evaluate
            y_pred = model.predict(X_test_scaled)
            r2 = r2_score(y_test, y_pred)
            mse = mean_squared_error(y_test, y_pred)
            mae = mean_absolute_error(y_test, y_pred)

            results[name] = {
                'r2_score': r2,
                'mse': mse,
                'mae': mae
            }

            if r2 > best_score:
                best_score = r2
                best_model = model

        # Store best model
        self.models['memory_prediction'] = best_model
        self.scalers['memory_prediction'] = scaler

        return {
            "status": "success",
            "best_model": max(results.keys(), key=lambda k: results[k]['r2_score']),
            "best_r2_score": best_score,
            "results": results,
            "feature_columns": available_features
        }

    def _train_runtime_prediction_model(self, data: pd.DataFrame) -> Dict[str, Any]:
        """Train runtime prediction model"""
        # Similar structure to memory prediction but for runtime
        if data.empty:
            return {"status": "error", "message": "No training data"}

        feature_columns = ['requested_memory_gb', 'requested_cpu', 'gate_count',
                          'hierarchy_depth', 'net_count', 'peak_memory_gb']
        target = 'runtime_seconds'

        available_features = [col for col in feature_columns if col in data.columns]

        if len(available_features) < 2:
            return {"status": "error", "message": "Insufficient features"}

        X = data[available_features].fillna(0)
        y = data[target].fillna(0)

        # Remove outliers and invalid data
        mask = (y > 60) & (y < 86400)  # Between 1 minute and 24 hours
        X = X[mask]
        y = y[mask]

        if len(X) < 20:
            return {"status": "error", "message": "Insufficient clean data"}

        # Train similar to memory model
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

        scaler = StandardScaler()
        X_train_scaled = scaler.fit_transform(X_train)
        X_test_scaled = scaler.transform(X_test)

        # Use log transformation for runtime (tends to be log-normal)
        y_train_log = np.log1p(y_train)
        y_test_log = np.log1p(y_test)

        model = RandomForestRegressor(n_estimators=100, random_state=42)
        model.fit(X_train_scaled, y_train_log)

        y_pred_log = model.predict(X_test_scaled)
        y_pred = np.expm1(y_pred_log)

        r2 = r2_score(y_test, y_pred)
        mse = mean_squared_error(y_test, y_pred)

        self.models['runtime_prediction'] = model
        self.scalers['runtime_prediction'] = scaler

        return {
            "status": "success",
            "r2_score": r2,
            "mse": mse,
            "feature_columns": available_features
        }

    def _train_cost_optimization_model(self, data: pd.DataFrame) -> Dict[str, Any]:
        """Train cost optimization model"""
        if data.empty or 'cost_dollars' not in data.columns:
            return {"status": "error", "message": "No cost data available"}

        # Create cost efficiency metric
        data['cost_efficiency'] = data['performance_score'] / (data['cost_dollars'] + 0.01)

        feature_columns = ['requested_memory_gb', 'requested_cpu', 'gate_count',
                          'runtime_seconds', 'queue_wait_seconds']
        target = 'cost_efficiency'

        available_features = [col for col in feature_columns if col in data.columns]

        if len(available_features) < 2:
            return {"status": "error", "message": "Insufficient features"}

        X = data[available_features].fillna(0)
        y = data[target].fillna(0)

        # Remove outliers
        mask = (y > 0) & (y < np.percentile(y, 95))
        X = X[mask]
        y = y[mask]

        if len(X) < 20:
            return {"status": "error", "message": "Insufficient clean data"}

        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

        scaler = StandardScaler()
        X_train_scaled = scaler.fit_transform(X_train)
        X_test_scaled = scaler.transform(X_test)

        model = GradientBoostingRegressor(n_estimators=100, random_state=42)
        model.fit(X_train_scaled, y_train)

        y_pred = model.predict(X_test_scaled)
        r2 = r2_score(y_test, y_pred)

        self.models['cost_optimization'] = model
        self.scalers['cost_optimization'] = scaler

        return {
            "status": "success",
            "r2_score": r2,
            "feature_columns": available_features
        }

    def _train_queue_recommendation_model(self, data: pd.DataFrame) -> Dict[str, Any]:
        """Train queue recommendation model using clustering"""
        if data.empty:
            return {"status": "error", "message": "No training data"}

        # Create feature matrix for clustering
        feature_columns = ['gate_count', 'peak_memory_gb', 'runtime_seconds',
                          'actual_cpu_utilization']

        available_features = [col for col in feature_columns if col in data.columns]

        if len(available_features) < 2:
            return {"status": "error", "message": "Insufficient features"}

        X = data[available_features].fillna(0)

        # Remove outliers
        for col in X.columns:
            Q1 = X[col].quantile(0.25)
            Q3 = X[col].quantile(0.75)
            IQR = Q3 - Q1
            lower_bound = Q1 - 1.5 * IQR
            upper_bound = Q3 + 1.5 * IQR
            X = X[(X[col] >= lower_bound) & (X[col] <= upper_bound)]

        if len(X) < 20:
            return {"status": "error", "message": "Insufficient clean data"}

        # Scale features
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)

        # Perform clustering
        n_clusters = min(5, len(X) // 10)  # Dynamic cluster count
        kmeans = KMeans(n_clusters=n_clusters, random_state=42)
        clusters = kmeans.fit_predict(X_scaled)

        # Associate clusters with queue types
        cluster_queue_mapping = {}
        data_with_clusters = data.copy()
        data_with_clusters['cluster'] = clusters

        for cluster_id in range(n_clusters):
            cluster_data = data_with_clusters[data_with_clusters['cluster'] == cluster_id]
            if len(cluster_data) > 0:
                # Find most common queue type in this cluster
                queue_counts = cluster_data['queue_type'].value_counts()
                cluster_queue_mapping[cluster_id] = queue_counts.index[0]

        self.models['queue_recommendation'] = {
            'kmeans': kmeans,
            'cluster_mapping': cluster_queue_mapping
        }
        self.scalers['queue_recommendation'] = scaler

        return {
            "status": "success",
            "n_clusters": n_clusters,
            "cluster_mapping": cluster_queue_mapping,
            "feature_columns": available_features
        }

    def predict_optimal_resources(self, flow_type: str, stage_name: str,
                                design_characteristics: Dict[str, Any]) -> Dict[str, Any]:
        """Predict optimal resource allocation using advanced models"""

        prediction = {
            "memory_gb": 16,
            "cpu_count": 8,
            "runtime_estimate": 3600,
            "cost_estimate": 5.0,
            "queue_recommendation": "M",
            "confidence": 0.6,
            "source": "advanced_ml"
        }

        if not SKLEARN_AVAILABLE or 'memory_prediction' not in self.models:
            return self._fallback_prediction(flow_type, stage_name, design_characteristics)

        try:
            # Prepare feature vector
            features = self._prepare_feature_vector(design_characteristics)

            # Memory prediction
            if 'memory_prediction' in self.models:
                memory_pred = self._predict_memory(features)
                prediction["memory_gb"] = max(8, int(memory_pred))

            # Runtime prediction
            if 'runtime_prediction' in self.models:
                runtime_pred = self._predict_runtime(features)
                prediction["runtime_estimate"] = max(300, int(runtime_pred))

            # Cost prediction
            if 'cost_optimization' in self.models:
                cost_pred = self._predict_cost(features, prediction["memory_gb"], prediction["runtime_estimate"])
                prediction["cost_estimate"] = max(1.0, cost_pred)

            # Queue recommendation
            if 'queue_recommendation' in self.models:
                queue_pred = self._predict_queue(features)
                prediction["queue_recommendation"] = queue_pred

            prediction["confidence"] = 0.85

        except Exception as e:
            logger.error(f"Advanced prediction failed: {e}")
            return self._fallback_prediction(flow_type, stage_name, design_characteristics)

        return prediction

    def _prepare_feature_vector(self, design_characteristics: Dict[str, Any]) -> Dict[str, float]:
        """Prepare feature vector from design characteristics"""
        return {
            'gate_count': float(design_characteristics.get('gate_count', 100000)),
            'hierarchy_depth': float(design_characteristics.get('hierarchy_depth', 5)),
            'net_count': float(design_characteristics.get('net_count', 50000)),
            'requested_memory_gb': 16.0,  # Will be updated iteratively
            'requested_cpu': 8.0,
        }

    def _predict_memory(self, features: Dict[str, float]) -> float:
        """Predict memory usage"""
        model = self.models['memory_prediction']
        scaler = self.scalers['memory_prediction']

        # Create feature array (order matters - same as training)
        feature_array = np.array([[
            features.get('requested_memory_gb', 16),
            features.get('requested_cpu', 8),
            features.get('gate_count', 100000),
            features.get('hierarchy_depth', 5),
            features.get('net_count', 50000)
        ]])

        feature_array_scaled = scaler.transform(feature_array)
        prediction = model.predict(feature_array_scaled)[0]

        return prediction

    def _predict_runtime(self, features: Dict[str, float]) -> float:
        """Predict runtime"""
        model = self.models['runtime_prediction']
        scaler = self.scalers['runtime_prediction']

        feature_array = np.array([[
            features.get('requested_memory_gb', 16),
            features.get('requested_cpu', 8),
            features.get('gate_count', 100000),
            features.get('hierarchy_depth', 5),
            features.get('net_count', 50000),
            features.get('peak_memory_gb', 16)
        ]])

        feature_array_scaled = scaler.transform(feature_array)
        log_prediction = model.predict(feature_array_scaled)[0]
        prediction = np.expm1(log_prediction)  # Reverse log transformation

        return prediction

    def _predict_cost(self, features: Dict[str, float], memory_gb: float, runtime_seconds: float) -> float:
        """Predict cost based on resources and runtime"""
        # Simple cost model: cost = (memory * memory_rate + cpu * cpu_rate) * runtime_hours
        cpu_count = features.get('requested_cpu', 8)
        runtime_hours = runtime_seconds / 3600.0

        memory_cost_per_hour = 0.05  # $0.05 per GB per hour
        cpu_cost_per_hour = 0.10     # $0.10 per CPU per hour

        total_cost = (memory_gb * memory_cost_per_hour + cpu_count * cpu_cost_per_hour) * runtime_hours

        return total_cost

    def _predict_queue(self, features: Dict[str, float]) -> str:
        """Predict optimal queue using clustering model"""
        model_data = self.models['queue_recommendation']
        kmeans = model_data['kmeans']
        cluster_mapping = model_data['cluster_mapping']
        scaler = self.scalers['queue_recommendation']

        feature_array = np.array([[
            features.get('gate_count', 100000),
            features.get('peak_memory_gb', 16),
            features.get('runtime_seconds', 3600),
            features.get('actual_cpu_utilization', 0.7)
        ]])

        feature_array_scaled = scaler.transform(feature_array)
        cluster = kmeans.predict(feature_array_scaled)[0]

        return cluster_mapping.get(cluster, "M")

    def _fallback_prediction(self, flow_type: str, stage_name: str,
                           design_characteristics: Dict[str, Any]) -> Dict[str, Any]:
        """Fallback prediction when ML models are not available"""
        gate_count = design_characteristics.get('gate_count', 100000)

        if gate_count > 2000000:
            return {
                "memory_gb": 64, "cpu_count": 32, "runtime_estimate": 14400,
                "cost_estimate": 25.0, "queue_recommendation": "XL",
                "confidence": 0.6, "source": "heuristic"
            }
        elif gate_count > 1000000:
            return {
                "memory_gb": 32, "cpu_count": 16, "runtime_estimate": 7200,
                "cost_estimate": 12.0, "queue_recommendation": "L",
                "confidence": 0.6, "source": "heuristic"
            }
        elif gate_count > 500000:
            return {
                "memory_gb": 16, "cpu_count": 8, "runtime_estimate": 3600,
                "cost_estimate": 6.0, "queue_recommendation": "M",
                "confidence": 0.6, "source": "heuristic"
            }
        else:
            return {
                "memory_gb": 8, "cpu_count": 4, "runtime_estimate": 1800,
                "cost_estimate": 3.0, "queue_recommendation": "S",
                "confidence": 0.6, "source": "heuristic"
            }

    def _save_models(self):
        """Save trained models to disk"""
        model_dir = "/tmp/cbflow_ml_models"
        os.makedirs(model_dir, exist_ok=True)

        for model_name, model in self.models.items():
            model_file = os.path.join(model_dir, f"{model_name}.pkl")
            with open(model_file, 'wb') as f:
                pickle.dump(model, f)

        for scaler_name, scaler in self.scalers.items():
            scaler_file = os.path.join(model_dir, f"{scaler_name}_scaler.pkl")
            with open(scaler_file, 'wb') as f:
                pickle.dump(scaler, f)

    def _load_models(self):
        """Load existing models from disk"""
        model_dir = "/tmp/cbflow_ml_models"
        if not os.path.exists(model_dir):
            return

        for model_name in ['memory_prediction', 'runtime_prediction', 'cost_optimization', 'queue_recommendation']:
            model_file = os.path.join(model_dir, f"{model_name}.pkl")
            scaler_file = os.path.join(model_dir, f"{model_name}_scaler.pkl")

            if os.path.exists(model_file):
                try:
                    with open(model_file, 'rb') as f:
                        self.models[model_name] = pickle.load(f)
                except Exception as e:
                    logger.warning(f"Failed to load model {model_name}: {e}")

            if os.path.exists(scaler_file):
                try:
                    with open(scaler_file, 'rb') as f:
                        self.scalers[model_name] = pickle.load(f)
                except Exception as e:
                    logger.warning(f"Failed to load scaler {model_name}: {e}")


class CostTracker:
    """Advanced cost tracking and budget management"""

    def __init__(self, db_path: str):
        self.db_path = db_path

    def track_job_cost(self, job_data: Dict[str, Any]) -> float:
        """Calculate and track job cost"""
        # Cost calculation based on resource usage
        memory_gb = job_data.get('peak_memory_gb', job_data.get('requested_memory_gb', 8))
        cpu_count = job_data.get('requested_cpu', 4)
        runtime_hours = job_data.get('runtime_seconds', 3600) / 3600.0

        # Cost rates (configurable)
        memory_rate = 0.05  # $/GB/hour
        cpu_rate = 0.10     # $/CPU/hour

        total_cost = (memory_gb * memory_rate + cpu_count * cpu_rate) * runtime_hours

        # Store cost data
        self._store_cost_data(job_data, total_cost)

        return total_cost

    def _store_cost_data(self, job_data: Dict[str, Any], cost: float):
        """Store cost data in database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO cost_tracking (
                date, flow_type, stage_name, queue_type, total_jobs,
                total_cost_dollars, total_cpu_hours, total_memory_gb_hours,
                average_efficiency, cost_per_job
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            datetime.now().date(),
            job_data.get('flow_type', ''),
            job_data.get('stage_name', ''),
            job_data.get('queue_type', ''),
            1,
            cost,
            job_data.get('requested_cpu', 4) * job_data.get('runtime_seconds', 3600) / 3600.0,
            job_data.get('peak_memory_gb', 8) * job_data.get('runtime_seconds', 3600) / 3600.0,
            job_data.get('efficiency_score', 0.7),
            cost
        ))

        conn.commit()
        conn.close()

    def get_cost_report(self, days: int = 30) -> Dict[str, Any]:
        """Generate cost report for specified period"""
        conn = sqlite3.connect(self.db_path)

        query = '''
            SELECT
                flow_type, stage_name, queue_type,
                SUM(total_jobs) as total_jobs,
                SUM(total_cost_dollars) as total_cost,
                AVG(average_efficiency) as avg_efficiency,
                AVG(cost_per_job) as avg_cost_per_job
            FROM cost_tracking
            WHERE date >= date('now', '-{} days')
            GROUP BY flow_type, stage_name, queue_type
            ORDER BY total_cost DESC
        '''.format(days)

        df = pd.read_sql_query(query, conn)
        conn.close()

        if df.empty:
            return {"total_cost": 0, "breakdown": [], "summary": {}}

        total_cost = df['total_cost'].sum()

        return {
            "total_cost": total_cost,
            "breakdown": df.to_dict('records'),
            "summary": {
                "total_jobs": df['total_jobs'].sum(),
                "average_efficiency": df['avg_efficiency'].mean(),
                "cost_per_job": df['avg_cost_per_job'].mean()
            }
        }


class AnomalyDetector:
    """Detect anomalies in resource usage and performance"""

    def __init__(self):
        self.baseline_metrics = {}

    def detect_anomalies(self, job_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Detect anomalies in job execution"""
        anomalies = []

        # Memory usage anomaly
        if self._is_memory_anomaly(job_data):
            anomalies.append({
                "type": "memory_anomaly",
                "severity": "medium",
                "description": "Memory usage significantly higher than expected",
                "recommendation": "Consider increasing memory allocation or investigating memory leaks"
            })

        # Runtime anomaly
        if self._is_runtime_anomaly(job_data):
            anomalies.append({
                "type": "runtime_anomaly",
                "severity": "high",
                "description": "Runtime significantly longer than expected",
                "recommendation": "Investigate performance bottlenecks or increase CPU allocation"
            })

        # Cost anomaly
        if self._is_cost_anomaly(job_data):
            anomalies.append({
                "type": "cost_anomaly",
                "severity": "medium",
                "description": "Cost per job significantly higher than baseline",
                "recommendation": "Review resource allocation efficiency"
            })

        return anomalies

    def _is_memory_anomaly(self, job_data: Dict[str, Any]) -> bool:
        """Check for memory usage anomalies"""
        actual_memory = job_data.get('peak_memory_gb', 0)
        requested_memory = job_data.get('requested_memory_gb', 8)

        # Anomaly if actual usage is more than 50% higher than requested
        return actual_memory > requested_memory * 1.5

    def _is_runtime_anomaly(self, job_data: Dict[str, Any]) -> bool:
        """Check for runtime anomalies"""
        runtime = job_data.get('runtime_seconds', 0)

        # Anomaly if runtime is more than 4 hours (configurable)
        return runtime > 14400

    def _is_cost_anomaly(self, job_data: Dict[str, Any]) -> bool:
        """Check for cost anomalies"""
        cost = job_data.get('cost_dollars', 0)

        # Anomaly if cost is more than $50 per job (configurable)
        return cost > 50.0


class BudgetManager:
    """Budget management and alerting"""

    def __init__(self, db_path: str):
        self.db_path = db_path

    def set_budget(self, flow_type: str, budget_amount: float, period: str = "monthly"):
        """Set budget for flow type"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT OR REPLACE INTO budget_management (
                budget_period, flow_type, allocated_budget, spent_budget,
                projected_spend, budget_utilization, alert_threshold
            ) VALUES (?, ?, ?, 0, 0, 0, 0.8)
        ''', (period, flow_type, budget_amount))

        conn.commit()
        conn.close()

    def check_budget_status(self, flow_type: str) -> Dict[str, Any]:
        """Check budget status and generate alerts if needed"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Get current budget
        cursor.execute('''
            SELECT allocated_budget, spent_budget, alert_threshold
            FROM budget_management
            WHERE flow_type = ?
            ORDER BY created_at DESC
            LIMIT 1
        ''', (flow_type,))

        budget_data = cursor.fetchone()

        if not budget_data:
            return {"status": "no_budget_set"}

        allocated, spent, threshold = budget_data

        # Calculate current spend
        current_spend = self._calculate_current_spend(flow_type, conn)

        utilization = current_spend / allocated if allocated > 0 else 0

        status = {
            "allocated_budget": allocated,
            "current_spend": current_spend,
            "budget_utilization": utilization,
            "alert_threshold": threshold,
            "status": "ok"
        }

        if utilization >= 1.0:
            status["status"] = "over_budget"
            status["alert"] = "Budget exceeded!"
        elif utilization >= threshold:
            status["status"] = "warning"
            status["alert"] = f"Budget utilization at {utilization*100:.1f}%"

        conn.close()
        return status

    def _calculate_current_spend(self, flow_type: str, conn) -> float:
        """Calculate current spend for flow type"""
        cursor = conn.cursor()

        cursor.execute('''
            SELECT SUM(total_cost_dollars)
            FROM cost_tracking
            WHERE flow_type = ? AND date >= date('now', 'start of month')
        ''', (flow_type,))

        result = cursor.fetchone()
        return result[0] if result[0] else 0.0


class PerformanceOptimizer:
    """Performance optimization recommendations"""

    def __init__(self):
        self.optimization_rules = self._load_optimization_rules()

    def _load_optimization_rules(self) -> List[Dict[str, Any]]:
        """Load performance optimization rules"""
        return [
            {
                "name": "memory_overallocation",
                "condition": lambda data: data.get('peak_memory_gb', 0) < data.get('requested_memory_gb', 8) * 0.7,
                "recommendation": "Reduce memory allocation to improve cost efficiency",
                "impact": "cost_reduction"
            },
            {
                "name": "cpu_underutilization",
                "condition": lambda data: data.get('actual_cpu_utilization', 0) < 0.5,
                "recommendation": "Reduce CPU count or improve parallelization",
                "impact": "cost_reduction"
            },
            {
                "name": "long_queue_wait",
                "condition": lambda data: data.get('queue_wait_seconds', 0) > 1800,  # 30 minutes
                "recommendation": "Consider using a different queue or scheduling at off-peak hours",
                "impact": "time_reduction"
            }
        ]

    def get_optimization_recommendations(self, job_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Get performance optimization recommendations"""
        recommendations = []

        for rule in self.optimization_rules:
            try:
                if rule["condition"](job_data):
                    recommendations.append({
                        "name": rule["name"],
                        "recommendation": rule["recommendation"],
                        "impact": rule["impact"]
                    })
            except (KeyError, TypeError):
                continue

        return recommendations


def main():
    """Main entry point for CLI usage"""
    if len(sys.argv) < 2:
        print("Usage: python3 lsf_advanced_ml.py <command> [args]")
        print("Commands: train_models, predict_resources, cost_report, budget_status")
        sys.exit(1)

    command = sys.argv[1]
    analytics = AdvancedLSFAnalytics()

    if command == "train_models":
        result = analytics.train_advanced_models()
        print(json.dumps(result, indent=2))

    elif command == "predict_resources":
        if len(sys.argv) < 5:
            print("Usage: predict_resources <flow_type> <stage_name> <design_characteristics_json>")
            sys.exit(1)

        flow_type = sys.argv[2]
        stage_name = sys.argv[3]
        design_characteristics = json.loads(sys.argv[4])

        result = analytics.predict_optimal_resources(flow_type, stage_name, design_characteristics)
        print(json.dumps(result, indent=2))

    elif command == "cost_report":
        days = int(sys.argv[2]) if len(sys.argv) > 2 else 30
        result = analytics.cost_tracker.get_cost_report(days)
        print(json.dumps(result, indent=2))

    elif command == "budget_status":
        if len(sys.argv) < 3:
            print("Usage: budget_status <flow_type>")
            sys.exit(1)

        flow_type = sys.argv[2]
        result = analytics.budget_manager.check_budget_status(flow_type)
        print(json.dumps(result, indent=2))

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()