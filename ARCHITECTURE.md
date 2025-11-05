# TrackVault Architecture

## System Overview

TrackVault is a file activity monitoring system built with a separation of concerns architecture, consisting of two independent but interconnected services.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        User Browser                          │
│                    (http://localhost:8080)                   │
└────────────────────────────┬────────────────────────────────┘
                             │
                             │ HTTP Requests
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    Web Interface Service                     │
│                    (web_interface.py)                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Flask Application                                    │  │
│  │  - Routes & Views                                     │  │
│  │  - User Authentication                                │  │
│  │  - Dashboard Rendering                                │  │
│  │  - API Endpoints                                      │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
                             │ Database Queries
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      SQLite Database                         │
│                    (monitor_data.db)                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Tables:                                              │  │
│  │  - service_status                                     │  │
│  │  - file_activities                                    │  │
│  │  - alerts                                             │  │
│  │  - live_signals                                       │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────▲────────────────────────────────┘
                             │
                             │ Database Writes
                             │
┌─────────────────────────────────────────────────────────────┐
│                   Monitor Service                            │
│                  (monitor_service.py)                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  File Monitor Core                                    │  │
│  │  - Watchdog Observer                                  │  │
│  │  - Event Handler                                      │  │
│  │  - Risk Assessment                                    │  │
│  │  - Alert Generation                                   │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
                             │ File System Events
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      File System                             │
│              (Monitored Directories)                         │
│  - Desktop                                                   │
│  - Documents                                                 │
│  - Custom Paths                                              │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Monitor Service (`monitor_service.py`)

**Purpose**: Background service that monitors file system changes

**Key Responsibilities**:
- Watch specified directories for file changes
- Capture file system events (create, modify, delete, move)
- Assess risk level of each operation
- Generate security alerts for high-risk activities
- Store all data in SQLite database
- Send real-time signals for immediate updates

**Key Classes**:
- `MonitorService`: Main service orchestrator
- `FileActivityMonitor`: Event handler for file system changes
- `FileMonitorService`: Watchdog integration

**Database Tables Used**:
- `file_activities`: Stores all file operations
- `alerts`: Stores security alerts
- `service_status`: Service health and statistics
- `live_signals`: Real-time event queue

### 2. Web Interface (`web_interface.py`)

**Purpose**: User-facing dashboard and API

**Key Responsibilities**:
- Serve web dashboard
- Handle user authentication
- Display real-time statistics
- Provide activity logs and alerts
- Offer alert management (acknowledge, resolve, dismiss)
- Expose REST API for data access

**Routes**:
- `/` - Dashboard home
- `/logs` - Activity logs
- `/alerts` - Security alerts
- `/users` - User management
- `/settings` - Configuration
- `/api/*` - REST API endpoints

### 3. File Monitor Core (`file_monitor.py`)

**Purpose**: Core monitoring logic and utilities

**Key Components**:
- `FileActivityMonitor`: Watchdog event handler
- `FileMonitorService`: Service wrapper
- Risk assessment algorithms
- Process information gathering
- File owner detection

### 4. Main Application (`app.py`)

**Purpose**: Alternative Flask application with integrated monitoring

**Features**:
- Combined web interface and monitoring
- User authentication system
- Real-time dashboard updates
- Alert management API

## Data Flow

### File Activity Detection Flow

```
1. File System Event Occurs
   ↓
2. Watchdog Detects Event
   ↓
3. FileActivityMonitor.on_[event]() Called
   ↓
4. Risk Assessment Performed
   ↓
5. Activity Logged to Database
   ↓
6. Alert Generated (if high-risk)
   ↓
7. Live Signal Sent
   ↓
8. Web Interface Queries Database
   ↓
9. Dashboard Updates
```

### User Interaction Flow

```
1. User Opens Browser
   ↓
2. Loads Dashboard (web_interface.py)
   ↓
3. JavaScript Polls API Endpoints
   ↓
4. Flask Queries Database
   ↓
5. Returns JSON Data
   ↓
6. Frontend Updates UI
   ↓
7. User Takes Action (e.g., acknowledge alert)
   ↓
8. API Request Sent
   ↓
9. Database Updated
   ↓
10. UI Refreshes
```

## Database Schema

### file_activities
```sql
CREATE TABLE file_activities (
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
```

### alerts
```sql
CREATE TABLE alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    username TEXT,
    description TEXT NOT NULL,
    file_path TEXT,
    risk_level TEXT DEFAULT 'Medium',
    status TEXT DEFAULT 'New',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
```

### service_status
```sql
CREATE TABLE service_status (
    id INTEGER PRIMARY KEY,
    status TEXT NOT NULL,
    last_update TIMESTAMP,
    monitored_paths TEXT,
    total_activities INTEGER DEFAULT 0,
    alerts_count INTEGER DEFAULT 0
)
```

### live_signals
```sql
CREATE TABLE live_signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signal_type TEXT NOT NULL,
    data TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed BOOLEAN DEFAULT FALSE
)
```

## Risk Assessment Algorithm

```python
def assess_risk_level(file_path, action):
    # High Risk Conditions
    if action in ['DELETE', 'MOVE']:
        return 'High'
    
    if file_extension in ['.exe', '.dll', '.sys', '.bat']:
        return 'High'
    
    if path_contains(['system32', 'windows', 'program files']):
        return 'High'
    
    # Medium Risk Conditions
    if path_contains(['documents', 'desktop']):
        return 'Medium'
    
    # Default
    return 'Low'
```

## Configuration

### monitor_config.json Structure

```json
{
  "watch_paths": ["directories to monitor"],
  "excluded_extensions": ["file types to ignore"],
  "excluded_paths": ["directories to skip"],
  "risk_settings": {
    "high_risk_extensions": ["dangerous file types"],
    "high_risk_actions": ["risky operations"],
    "sensitive_paths": ["protected directories"]
  },
  "sync_interval": 3,
  "max_buffer_size": 100
}
```

## Security Considerations

1. **Authentication**: Session-based user authentication
2. **Risk Assessment**: Multi-factor risk evaluation
3. **Alert System**: Immediate notification of suspicious activities
4. **Process Tracking**: Identifies which applications perform operations
5. **Audit Trail**: Complete history of all file operations

## Performance Optimization

1. **Database Indexing**: Timestamps and file paths indexed
2. **Excluded Patterns**: Skip unnecessary files/directories
3. **Buffering**: Batch database writes
4. **Lazy Loading**: Paginated activity logs
5. **Efficient Queries**: Optimized SQL with limits

## Scalability

- **Horizontal**: Multiple monitor services for different paths
- **Vertical**: Adjust sync intervals and buffer sizes
- **Database**: Can migrate to PostgreSQL/MySQL for larger deployments
- **Distributed**: Services can run on different machines

## Future Enhancements

- [ ] Machine learning for anomaly detection
- [ ] Email/SMS alert notifications
- [ ] Advanced reporting and analytics
- [ ] Multi-user role-based access control
- [ ] Cloud storage integration
- [ ] Cross-platform support (Linux, macOS)
- [ ] Real-time WebSocket updates
- [ ] Export functionality (CSV, PDF)

## Technology Stack Summary

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Backend | Python 3.x | Core logic |
| Web Framework | Flask 2.3.3 | HTTP server |
| File Monitoring | Watchdog 3.0.0 | FS events |
| Database | SQLite | Data storage |
| Process Info | psutil 5.9.6 | System data |
| Windows API | pywin32 306 | OS integration |
| Frontend | HTML/CSS/JS | User interface |
| UI Framework | Bootstrap | Responsive design |

## Deployment Options

1. **Local Development**: Run both services manually
2. **Windows Service**: Install as background service
3. **Docker**: Containerized deployment (docker-compose.yml included)
4. **Cloud**: Deploy to AWS/Azure/GCP with appropriate permissions

---

For questions about the architecture, please open an issue on GitHub.
