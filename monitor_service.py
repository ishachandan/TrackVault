"""
Lightweight File Monitor Service
Runs independently in background and monitors file system changes
Sends signals/data to web interface via database
"""

import os
import time
import json
import sqlite3
import threading
import signal
import sys
from datetime import datetime
from file_monitor import FileActivityMonitor, FileMonitorService
import logging

class MonitorService:
    def __init__(self, db_path="monitor_data.db", config_file="monitor_config.json"):
        self.db_path = db_path
        self.config_file = config_file
        self.running = False
        self.file_monitor = None
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('monitor_service.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        # Load configuration
        self.config = self.load_config()
        
        # Initialize database
        self.init_database()
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
    def load_config(self):
        """Load monitoring configuration"""
        default_config = {
            "watch_paths": [
                "C:\\Users\\Chandan Deshmukh\\Desktop",
                "C:\\Users\\Chandan Deshmukh\\Documents"
            ],
            "excluded_extensions": [".tmp", ".log", ".pyc"],
            "excluded_paths": ["__pycache__", "node_modules", ".git"],
            "risk_settings": {
                "high_risk_extensions": [".exe", ".dll", ".sys", ".bat", ".cmd", ".ps1"],
                "high_risk_actions": ["DELETE", "MOVE"],
                "sensitive_paths": ["system32", "windows", "program files"]
            },
            "sync_interval": 5,  # seconds
            "max_buffer_size": 100
        }
        
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults
                    for key, value in default_config.items():
                        if key not in config:
                            config[key] = value
                    return config
            else:
                # Create default config file
                with open(self.config_file, 'w') as f:
                    json.dump(default_config, f, indent=2)
                return default_config
        except Exception as e:
            self.logger.error(f"Error loading config: {e}")
            return default_config
    
    def init_database(self):
        """Initialize database for communication with web interface"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Service status table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS service_status (
                id INTEGER PRIMARY KEY,
                status TEXT NOT NULL,
                last_update TIMESTAMP,
                monitored_paths TEXT,
                total_activities INTEGER DEFAULT 0,
                alerts_count INTEGER DEFAULT 0
            )
        ''')
        
        # File activities table (same as before but optimized)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS file_activities (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                username TEXT,
                process_name TEXT,
                process_id INTEGER,
                action TEXT NOT NULL,
                file_path TEXT NOT NULL,
                file_size INTEGER,
                risk_level TEXT DEFAULT 'Low',
                status TEXT DEFAULT 'New',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Alerts table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                username TEXT,
                description TEXT NOT NULL,
                file_path TEXT,
                risk_level TEXT DEFAULT 'Medium',
                status TEXT DEFAULT 'New',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Real-time signals table (for immediate web updates)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS live_signals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                signal_type TEXT NOT NULL,
                data TEXT,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                processed BOOLEAN DEFAULT FALSE
            )
        ''')
        
        conn.commit()
        conn.close()
        
        # Initialize service status
        self.update_service_status("Starting")
        
    def update_service_status(self, status):
        """Update service status for web interface"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT OR REPLACE INTO service_status 
            (id, status, last_update, monitored_paths, total_activities, alerts_count)
            VALUES (1, ?, ?, ?, 
                (SELECT COUNT(*) FROM file_activities),
                (SELECT COUNT(*) FROM alerts WHERE status = 'New'))
        ''', (status, datetime.now().isoformat(), json.dumps(self.config['watch_paths'])))
        
        conn.commit()
        conn.close()
        
    def send_signal(self, signal_type, data=None):
        """Send real-time signal to web interface"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO live_signals (signal_type, data)
            VALUES (?, ?)
        ''', (signal_type, json.dumps(data) if data else None))
        
        conn.commit()
        conn.close()
        
    def log_activity(self, action, file_path, file_size=0):
        """Enhanced activity logging with signals"""
        # Get process info
        try:
            import psutil
            current_process = psutil.Process()
            username = current_process.username()
            process_name = current_process.name()
            process_id = current_process.pid
        except:
            username = "Unknown"
            process_name = "Unknown"
            process_id = 0
            
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        # Assess risk level
        risk_level = self.assess_risk_level(file_path, action)
        
        # Store in database
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO file_activities 
            (timestamp, username, process_name, process_id, action, file_path, file_size, risk_level)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (timestamp, username, process_name, process_id, action, file_path, file_size, risk_level))
        
        activity_id = cursor.lastrowid
        
        # Create alert for high-risk activities
        if risk_level == 'High':
            description = f"High-risk {action.lower()} operation detected"
            cursor.execute('''
                INSERT INTO alerts (timestamp, username, description, file_path, risk_level)
                VALUES (?, ?, ?, ?, ?)
            ''', (timestamp, username, description, file_path, 'High'))
            
            # Send immediate alert signal
            self.send_signal('new_alert', {
                'description': description,
                'file_path': file_path,
                'risk_level': 'High',
                'timestamp': timestamp
            })
        
        conn.commit()
        conn.close()
        
        # Send activity signal for real-time updates
        self.send_signal('new_activity', {
            'id': activity_id,
            'action': action,
            'file_path': os.path.basename(file_path),
            'risk_level': risk_level,
            'timestamp': timestamp
        })
        
        self.logger.info(f"[{timestamp}] {username} ({process_name}) - {action}: {file_path}")
        
    def assess_risk_level(self, file_path, action):
        """Assess risk level based on configuration"""
        file_path_lower = file_path.lower()
        
        # High risk conditions
        if action in self.config['risk_settings']['high_risk_actions']:
            return 'High'
            
        if any(ext in file_path_lower for ext in self.config['risk_settings']['high_risk_extensions']):
            return 'High'
            
        if any(path in file_path_lower for path in self.config['risk_settings']['sensitive_paths']):
            return 'High'
            
        # Medium risk conditions
        if 'documents' in file_path_lower or 'desktop' in file_path_lower:
            return 'Medium'
            
        return 'Low'
        
    def should_ignore_file(self, file_path):
        """Check if file should be ignored"""
        file_path_lower = file_path.lower()
        
        # Check excluded extensions
        if any(ext in file_path_lower for ext in self.config['excluded_extensions']):
            return True
            
        # Check excluded paths
        if any(path in file_path_lower for path in self.config['excluded_paths']):
            return True
            
        # Always ignore our own database
        if self.db_path in file_path:
            return True
            
        return False
        
    def start_monitoring(self):
        """Start the file monitoring service"""
        self.logger.info("Starting File Monitor Service")
        self.logger.info(f"Monitoring paths: {self.config['watch_paths']}")
        
        self.running = True
        self.update_service_status("Running")
        
        # Create custom file monitor
        self.file_monitor = FileMonitorService(self.config['watch_paths'])
        
        # Override the log_activity method
        self.file_monitor.event_handler.log_activity = self.log_activity
        self.file_monitor.event_handler.should_ignore_file = self.should_ignore_file
        
        # Start monitoring in separate thread
        monitor_thread = threading.Thread(target=self.file_monitor.start_monitoring, daemon=True)
        monitor_thread.start()
        
        # Start status update loop
        self.status_update_loop()
        
    def status_update_loop(self):
        """Periodic status updates"""
        while self.running:
            try:
                self.update_service_status("Running")
                time.sleep(self.config['sync_interval'])
            except Exception as e:
                self.logger.error(f"Status update error: {e}")
                time.sleep(5)
                
    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum}, shutting down...")
        self.stop_monitoring()
        
    def stop_monitoring(self):
        """Stop the monitoring service"""
        self.logger.info("Stopping File Monitor Service")
        self.running = False
        
        if self.file_monitor:
            self.file_monitor.stop_monitoring()
            
        self.update_service_status("Stopped")
        sys.exit(0)

def main():
    """Main service entry point"""
    print("File Monitor Service v1.0")
    print("=" * 40)
    
    service = MonitorService()
    
    try:
        service.start_monitoring()
    except KeyboardInterrupt:
        service.stop_monitoring()
    except Exception as e:
        service.logger.error(f"Service error: {e}")
        service.stop_monitoring()

if __name__ == "__main__":
    main()
