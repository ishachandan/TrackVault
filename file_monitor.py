import os
import time
import sqlite3
import psutil
import threading
from datetime import datetime
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import win32api
import win32con
import win32security

class FileActivityMonitor(FileSystemEventHandler):
    def __init__(self, db_path="file_activity.db"):
        self.db_path = db_path
        self.init_database()
        
    def init_database(self):
        """Initialize SQLite database for storing file activities"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
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
                ip_address TEXT,
                status TEXT DEFAULT 'Detected',
                risk_level TEXT DEFAULT 'Low'
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                username TEXT,
                description TEXT NOT NULL,
                file_path TEXT,
                risk_level TEXT DEFAULT 'Medium',
                status TEXT DEFAULT 'New'
            )
        ''')
        
        conn.commit()
        conn.close()
        
    def get_process_info(self):
        """Get current process information"""
        try:
            current_process = psutil.Process()
            username = current_process.username()
            process_name = current_process.name()
            process_id = current_process.pid
            return username, process_name, process_id
        except:
            return "Unknown", "Unknown", 0
            
    def get_file_owner(self, file_path):
        """Get file owner information on Windows"""
        try:
            sd = win32security.GetFileSecurity(file_path, win32security.OWNER_SECURITY_INFORMATION)
            owner_sid = sd.GetSecurityDescriptorOwner()
            name, domain, type = win32security.LookupAccountSid(None, owner_sid)
            return f"{domain}\\{name}" if domain else name
        except:
            return "Unknown"
            
    def assess_risk_level(self, file_path, action):
        """Assess risk level based on file path and action"""
        high_risk_paths = [
            'system32', 'windows', 'program files', 'programdata',
            'users\\all users', 'boot', 'config'
        ]
        
        sensitive_extensions = ['.exe', '.dll', '.sys', '.bat', '.cmd', '.ps1', '.reg']
        
        file_path_lower = file_path.lower()
        
        # High risk conditions
        if any(path in file_path_lower for path in high_risk_paths):
            return 'High'
        if any(ext in file_path_lower for ext in sensitive_extensions):
            return 'High'
        if action in ['DELETE', 'MOVE']:
            return 'High'
            
        # Medium risk conditions
        if 'documents' in file_path_lower or 'desktop' in file_path_lower:
            return 'Medium'
            
        return 'Low'
        
    def should_ignore_file(self, file_path):
        """Check if file should be ignored to prevent infinite loops"""
        ignore_patterns = [
            'file_activity.db',
            'file_activity.db-journal',
            'file_activity.db-wal',
            '.tmp',
            '.log',
            '__pycache__',
            '.pyc'
        ]
        
        file_path_lower = file_path.lower()
        return any(pattern in file_path_lower for pattern in ignore_patterns)
        
    def log_activity(self, action, file_path, file_size=0):
        """Log file activity to database"""
        # Skip logging for database files and temp files to prevent infinite loop
        if self.should_ignore_file(file_path):
            return
            
        username, process_name, process_id = self.get_process_info()
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        risk_level = self.assess_risk_level(file_path, action)
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO file_activities 
            (timestamp, username, process_name, process_id, action, file_path, file_size, risk_level)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (timestamp, username, process_name, process_id, action, file_path, file_size, risk_level))
        
        # Create alert for high-risk activities
        if risk_level == 'High':
            description = f"High-risk {action.lower()} operation detected on {os.path.basename(file_path)}"
            cursor.execute('''
                INSERT INTO alerts (timestamp, username, description, file_path, risk_level)
                VALUES (?, ?, ?, ?, ?)
            ''', (timestamp, username, description, file_path, 'High'))
            
        conn.commit()
        conn.close()
        
        print(f"[{timestamp}] {username} ({process_name}) - {action}: {file_path}")
        
    def on_created(self, event):
        if not event.is_directory and not self.should_ignore_file(event.src_path):
            file_size = 0
            try:
                file_size = os.path.getsize(event.src_path)
            except:
                pass
            self.log_activity('CREATE', event.src_path, file_size)
            
    def on_modified(self, event):
        if not event.is_directory and not self.should_ignore_file(event.src_path):
            file_size = 0
            try:
                file_size = os.path.getsize(event.src_path)
            except:
                pass
            self.log_activity('MODIFY', event.src_path, file_size)
            
    def on_deleted(self, event):
        if not event.is_directory and not self.should_ignore_file(event.src_path):
            self.log_activity('DELETE', event.src_path)
            
    def on_moved(self, event):
        if not event.is_directory and not self.should_ignore_file(event.src_path):
            self.log_activity('MOVE', f"{event.src_path} -> {event.dest_path}")

class FileMonitorService:
    def __init__(self, watch_paths=None):
        self.watch_paths = watch_paths or [
            "C:\\Users\\Chandan Deshmukh\\Desktop",
            "C:\\Users\\Chandan Deshmukh\\Documents"
        ]
        self.observer = Observer()
        self.event_handler = FileActivityMonitor()
        self.running = False
        
    def start_monitoring(self):
        """Start file system monitoring"""
        print("Starting File Activity Monitor...")
        print(f"Monitoring paths: {self.watch_paths}")
        
        for path in self.watch_paths:
            if os.path.exists(path):
                self.observer.schedule(self.event_handler, path, recursive=True)
                print(f"Watching: {path}")
            else:
                print(f"Path not found: {path}")
                
        self.observer.start()
        self.running = True
        
        try:
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            self.stop_monitoring()
            
    def stop_monitoring(self):
        """Stop file system monitoring"""
        print("Stopping File Activity Monitor...")
        self.observer.stop()
        self.observer.join()
        self.running = False
        
    def get_recent_activities(self, limit=50):
        """Get recent file activities from database"""
        conn = sqlite3.connect(self.event_handler.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM file_activities 
            ORDER BY timestamp DESC 
            LIMIT ?
        ''', (limit,))
        
        activities = cursor.fetchall()
        conn.close()
        
        return activities
        
    def get_recent_alerts(self, limit=20):
        """Get recent alerts from database"""
        conn = sqlite3.connect(self.event_handler.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM alerts 
            ORDER BY timestamp DESC 
            LIMIT ?
        ''', (limit,))
        
        alerts = cursor.fetchall()
        conn.close()
        
        return alerts

if __name__ == "__main__":
    # For testing - monitor current directory
    monitor = FileMonitorService(["C:\\Users\\Chandan Deshmukh\\OneDrive\\Desktop\\TRACKVAULT"])
    monitor.start_monitoring()
