#!/usr/bin/env python3
"""
TRACKVAULT Backend - SQLite Version
Tests all DBMS concepts without Docker
"""

import sqlite3
import json
import hashlib
import uuid
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
import jwt
import uvicorn
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# FastAPI app
app = FastAPI(
    title="TRACKVAULT API",
    description="File Activity Monitoring with Advanced DBMS Concepts",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer()
JWT_SECRET = "trackvault-sqlite-secret-key"
JWT_ALGORITHM = "HS256"

# Database file
DB_FILE = "trackvault.db"

# Pydantic models
class UserLogin(BaseModel):
    username: str
    password: str
    organization_name: str = "TechCorp Inc"

class UserRegister(BaseModel):
    username: str
    password: str
    email: EmailStr
    full_name: str
    organization_name: str = "TechCorp Inc"

class FileEvent(BaseModel):
    hostname: str
    username: str
    action: str  # CREATE, READ, WRITE, DELETE, RENAME, MOVE
    file_path: str
    occurred_at: datetime
    success: bool = True
    file_size: Optional[int] = None
    details: Optional[Dict[str, Any]] = None

class EventBatch(BaseModel):
    events: List[FileEvent]

# Database initialization
def init_database():
    """Initialize SQLite database with normalized schema"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    # Create tables with normalization (3NF)
    cursor.executescript("""
    -- Organizations table
    CREATE TABLE IF NOT EXISTS organizations (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        name TEXT UNIQUE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    -- Roles table
    CREATE TABLE IF NOT EXISTS roles (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        name TEXT UNIQUE NOT NULL,
        description TEXT
    );
    
    -- Users table (normalized)
    CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        full_name TEXT NOT NULL,
        organization_id TEXT NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login TIMESTAMP,
        FOREIGN KEY (organization_id) REFERENCES organizations(id)
    );
    
    -- User roles junction table (many-to-many)
    CREATE TABLE IF NOT EXISTS user_roles (
        user_id TEXT NOT NULL,
        role_id TEXT NOT NULL,
        assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id, role_id),
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (role_id) REFERENCES roles(id)
    );
    
    -- Devices table
    CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        hostname TEXT UNIQUE NOT NULL,
        organization_id TEXT NOT NULL,
        device_type TEXT DEFAULT 'workstation',
        os_info TEXT,
        last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        is_active BOOLEAN DEFAULT TRUE,
        FOREIGN KEY (organization_id) REFERENCES organizations(id)
    );
    
    -- Files table (normalized)
    CREATE TABLE IF NOT EXISTS files (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_extension TEXT,
        file_hash TEXT,
        file_size INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(file_path, file_hash)
    );
    
    -- File events table (main activity log)
    CREATE TABLE IF NOT EXISTS file_events (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        file_id TEXT NOT NULL,
        action TEXT NOT NULL CHECK (action IN ('CREATE', 'READ', 'WRITE', 'DELETE', 'RENAME', 'MOVE')),
        occurred_at TIMESTAMP NOT NULL,
        success BOOLEAN DEFAULT TRUE,
        details TEXT, -- JSON
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (device_id) REFERENCES devices(id),
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (file_id) REFERENCES files(id)
    );
    
    -- Policies table
    CREATE TABLE IF NOT EXISTS policies (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        name TEXT NOT NULL,
        description TEXT,
        rule_definition TEXT NOT NULL, -- JSON
        is_active BOOLEAN DEFAULT TRUE,
        organization_id TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (organization_id) REFERENCES organizations(id)
    );
    
    -- Alerts table
    CREATE TABLE IF NOT EXISTS alerts (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        policy_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        severity TEXT DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
        status TEXT DEFAULT 'open' CHECK (status IN ('open', 'investigating', 'resolved', 'false_positive')),
        title TEXT NOT NULL,
        description TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        resolved_at TIMESTAMP,
        FOREIGN KEY (policy_id) REFERENCES policies(id),
        FOREIGN KEY (event_id) REFERENCES file_events(id)
    );
    
    -- Audit log table
    CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY DEFAULT (hex(randomblob(16))),
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        old_values TEXT, -- JSON
        new_values TEXT, -- JSON
        user_id TEXT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
    );
    """)
    
    # Create indexes for performance
    cursor.executescript("""
    -- Performance indexes
    CREATE INDEX IF NOT EXISTS idx_file_events_occurred_at ON file_events(occurred_at);
    CREATE INDEX IF NOT EXISTS idx_file_events_device_occurred ON file_events(device_id, occurred_at);
    CREATE INDEX IF NOT EXISTS idx_file_events_user_occurred ON file_events(user_id, occurred_at);
    CREATE INDEX IF NOT EXISTS idx_file_events_action ON file_events(action);
    CREATE INDEX IF NOT EXISTS idx_alerts_severity ON alerts(severity);
    CREATE INDEX IF NOT EXISTS idx_alerts_status ON alerts(status);
    CREATE INDEX IF NOT EXISTS idx_files_path ON files(file_path);
    CREATE INDEX IF NOT EXISTS idx_files_hash ON files(file_hash);
    CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
    CREATE INDEX IF NOT EXISTS idx_devices_hostname ON devices(hostname);
    """)
    
    # Create views for common queries
    cursor.executescript("""
    -- Recent events view
    CREATE VIEW IF NOT EXISTS recent_events_view AS
    SELECT 
        fe.id,
        d.hostname,
        u.username,
        f.file_path,
        fe.action,
        fe.occurred_at,
        fe.success
    FROM file_events fe
    JOIN devices d ON fe.device_id = d.id
    JOIN users u ON fe.user_id = u.id
    JOIN files f ON fe.file_id = f.id
    WHERE fe.occurred_at >= datetime('now', '-24 hours')
    ORDER BY fe.occurred_at DESC;
    
    -- User activity summary view
    CREATE VIEW IF NOT EXISTS user_activity_summary AS
    SELECT 
        u.username,
        u.full_name,
        COUNT(fe.id) as total_events,
        COUNT(CASE WHEN fe.occurred_at >= datetime('now', '-7 days') THEN 1 END) as events_last_7d,
        MAX(fe.occurred_at) as last_activity
    FROM users u
    LEFT JOIN file_events fe ON u.id = fe.user_id
    GROUP BY u.id, u.username, u.full_name;
    
    -- Alert summary view
    CREATE VIEW IF NOT EXISTS alert_summary_view AS
    SELECT 
        severity,
        status,
        COUNT(*) as count,
        MAX(created_at) as latest_alert
    FROM alerts
    GROUP BY severity, status;
    """)
    
    conn.commit()
    conn.close()
    logger.info("Database initialized successfully")

def seed_data():
    """Insert sample data for testing"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    try:
        # Insert organization
        org_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT OR IGNORE INTO organizations (id, name) 
            VALUES (?, ?)
        """, (org_id, "TechCorp Inc"))
        
        # Insert roles
        admin_role_id = str(uuid.uuid4())
        user_role_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT OR IGNORE INTO roles (id, name, description) 
            VALUES (?, ?, ?)
        """, (admin_role_id, "admin", "System Administrator"))
        cursor.execute("""
            INSERT OR IGNORE INTO roles (id, name, description) 
            VALUES (?, ?, ?)
        """, (user_role_id, "user", "Regular User"))
        
        # Insert admin user
        admin_id = str(uuid.uuid4())
        admin_password = hashlib.sha256("admin123".encode()).hexdigest()
        cursor.execute("""
            INSERT OR IGNORE INTO users (id, username, password_hash, email, full_name, organization_id) 
            VALUES (?, ?, ?, ?, ?, ?)
        """, (admin_id, "admin", admin_password, "admin@trackvault.com", "System Administrator", org_id))
        
        # Assign admin role
        cursor.execute("""
            INSERT OR IGNORE INTO user_roles (user_id, role_id) 
            VALUES (?, ?)
        """, (admin_id, admin_role_id))
        
        # Insert sample device
        device_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT OR IGNORE INTO devices (id, hostname, organization_id, device_type, os_info) 
            VALUES (?, ?, ?, ?, ?)
        """, (device_id, "DESKTOP-TEST", org_id, "workstation", "Windows 11"))
        
        # Insert sample files and events
        file_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT OR IGNORE INTO files (id, file_path, file_name, file_extension, file_size) 
            VALUES (?, ?, ?, ?, ?)
        """, (file_id, "/documents/report.pdf", "report.pdf", "pdf", 1024000))
        
        # Insert sample file events
        for i in range(10):
            event_id = str(uuid.uuid4())
            occurred_at = datetime.now() - timedelta(hours=i)
            action = ["CREATE", "READ", "WRITE"][i % 3]
            cursor.execute("""
                INSERT OR IGNORE INTO file_events (id, device_id, user_id, file_id, action, occurred_at, success) 
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (event_id, device_id, admin_id, file_id, action, occurred_at, True))
        
        # Insert sample policy
        policy_id = str(uuid.uuid4())
        rule_definition = json.dumps({
            "conditions": [
                {"field": "action", "operator": "equals", "value": "DELETE"},
                {"field": "file_extension", "operator": "in", "value": ["exe", "dll", "sys"]}
            ],
            "severity": "high"
        })
        cursor.execute("""
            INSERT OR IGNORE INTO policies (id, name, description, rule_definition, organization_id) 
            VALUES (?, ?, ?, ?, ?)
        """, (policy_id, "Critical File Deletion", "Alert on deletion of system files", rule_definition, org_id))
        
        conn.commit()
        logger.info("Sample data inserted successfully")
        
    except Exception as e:
        logger.error(f"Error seeding data: {e}")
        conn.rollback()
    finally:
        conn.close()

# Authentication functions
def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def verify_password(password: str, hashed: str) -> bool:
    return hash_password(password) == hashed

def create_jwt_token(user_id: str, username: str) -> str:
    payload = {
        "user_id": user_id,
        "username": username,
        "exp": datetime.utcnow() + timedelta(days=1)
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

def verify_jwt_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

# API Endpoints
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": "1.0.0",
        "database": "SQLite"
    }

@app.post("/auth/login")
async def login(user_login: UserLogin):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    try:
        cursor.execute("""
            SELECT u.id, u.username, u.password_hash, u.full_name 
            FROM users u 
            JOIN organizations o ON u.organization_id = o.id 
            WHERE u.username = ? AND o.name = ?
        """, (user_login.username, user_login.organization_name))
        
        user = cursor.fetchone()
        if not user or not verify_password(user_login.password, user[2]):
            raise HTTPException(status_code=401, detail="Invalid credentials")
        
        # Update last login
        cursor.execute("""
            UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?
        """, (user[0],))
        conn.commit()
        
        token = create_jwt_token(user[0], user[1])
        return {
            "access_token": token,
            "token_type": "bearer",
            "expires_in": 86400,
            "user_id": user[0],
            "username": user[1],
            "full_name": user[3]
        }
        
    finally:
        conn.close()

@app.post("/api/v1/events")
async def create_event(event: FileEvent, current_user: dict = Depends(verify_jwt_token)):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    try:
        # Get or create device
        cursor.execute("SELECT id FROM devices WHERE hostname = ?", (event.hostname,))
        device = cursor.fetchone()
        if not device:
            device_id = str(uuid.uuid4())
            cursor.execute("""
                INSERT INTO devices (id, hostname, organization_id) 
                SELECT ?, ?, organization_id FROM users WHERE id = ?
            """, (device_id, event.hostname, current_user["user_id"]))
        else:
            device_id = device[0]
        
        # Get or create user
        cursor.execute("SELECT id FROM users WHERE username = ?", (event.username,))
        user = cursor.fetchone()
        if not user:
            raise HTTPException(status_code=400, detail="User not found")
        user_id = user[0]
        
        # Get or create file
        cursor.execute("SELECT id FROM files WHERE file_path = ?", (event.file_path,))
        file = cursor.fetchone()
        if not file:
            file_id = str(uuid.uuid4())
            file_name = event.file_path.split('/')[-1]
            file_extension = file_name.split('.')[-1] if '.' in file_name else None
            cursor.execute("""
                INSERT INTO files (id, file_path, file_name, file_extension, file_size) 
                VALUES (?, ?, ?, ?, ?)
            """, (file_id, event.file_path, file_name, file_extension, event.file_size))
        else:
            file_id = file[0]
        
        # Create event
        event_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT INTO file_events (id, device_id, user_id, file_id, action, occurred_at, success, details) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (event_id, device_id, user_id, file_id, event.action, event.occurred_at, 
              event.success, json.dumps(event.details) if event.details else None))
        
        conn.commit()
        return {"status": "success", "event_id": event_id}
        
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.get("/api/v1/events")
async def get_events(
    limit: int = 100, 
    offset: int = 0,
    action: Optional[str] = None,
    current_user: dict = Depends(verify_jwt_token)
):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    try:
        query = """
            SELECT 
                fe.id, d.hostname, u.username, f.file_path, 
                fe.action, fe.occurred_at, fe.success
            FROM file_events fe
            JOIN devices d ON fe.device_id = d.id
            JOIN users u ON fe.user_id = u.id
            JOIN files f ON fe.file_id = f.id
        """
        params = []
        
        if action:
            query += " WHERE fe.action = ?"
            params.append(action)
        
        query += " ORDER BY fe.occurred_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        
        cursor.execute(query, params)
        events = cursor.fetchall()
        
        return {
            "events": [
                {
                    "id": row[0],
                    "hostname": row[1],
                    "username": row[2],
                    "file_path": row[3],
                    "action": row[4],
                    "occurred_at": row[5],
                    "success": row[6]
                }
                for row in events
            ],
            "total": len(events),
            "limit": limit,
            "offset": offset
        }
        
    finally:
        conn.close()

@app.get("/api/v1/analytics/summary")
async def get_analytics_summary(current_user: dict = Depends(verify_jwt_token)):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    try:
        # Get various statistics
        cursor.execute("SELECT COUNT(*) FROM file_events")
        total_events = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM file_events WHERE occurred_at >= datetime('now', '-24 hours')")
        events_24h = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM alerts WHERE status = 'open'")
        open_alerts = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(DISTINCT device_id) FROM file_events")
        active_devices = cursor.fetchone()[0]
        
        cursor.execute("""
            SELECT action, COUNT(*) 
            FROM file_events 
            WHERE occurred_at >= datetime('now', '-7 days')
            GROUP BY action
        """)
        action_stats = dict(cursor.fetchall())
        
        return {
            "total_events": total_events,
            "events_last_24h": events_24h,
            "open_alerts": open_alerts,
            "active_devices": active_devices,
            "action_distribution": action_stats,
            "timestamp": datetime.now().isoformat()
        }
        
    finally:
        conn.close()

@app.get("/api/v1/database/stats")
async def get_database_stats(current_user: dict = Depends(verify_jwt_token)):
    """Show database statistics to verify DBMS concepts"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    try:
        # Get table counts
        tables = {}
        for table in ['organizations', 'users', 'roles', 'user_roles', 'devices', 
                     'files', 'file_events', 'policies', 'alerts', 'audit_logs']:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            tables[table] = cursor.fetchone()[0]
        
        # Get index information
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'")
        indexes = [row[0] for row in cursor.fetchall()]
        
        # Get view information
        cursor.execute("SELECT name FROM sqlite_master WHERE type='view'")
        views = [row[0] for row in cursor.fetchall()]
        
        return {
            "database_type": "SQLite",
            "tables": tables,
            "total_tables": len(tables),
            "indexes": indexes,
            "total_indexes": len(indexes),
            "views": views,
            "total_views": len(views),
            "normalization": "3NF (Third Normal Form)",
            "features": [
                "Normalized schema with proper relationships",
                "Foreign key constraints",
                "Check constraints for data integrity", 
                "Indexes for query performance",
                "Views for query simplification",
                "Audit logging capability"
            ]
        }
        
    finally:
        conn.close()

# Initialize database on startup
@app.on_event("startup")
async def startup_event():
    init_database()
    seed_data()
    logger.info("TRACKVAULT SQLite Backend started successfully")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
