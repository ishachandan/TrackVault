-- TRACKVAULT Database Schema
-- Comprehensive PostgreSQL schema with normalization, constraints, and DBMS concepts

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create custom enum types
CREATE TYPE file_action AS ENUM (
    'CREATE', 'READ', 'WRITE', 'DELETE', 'RENAME', 'MOVE', 'COPY', 'CHMOD', 'CHOWN'
);

CREATE TYPE alert_severity AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
CREATE TYPE alert_status AS ENUM ('NEW', 'ACKNOWLEDGED', 'INVESTIGATING', 'RESOLVED', 'DISMISSED');
CREATE TYPE device_status AS ENUM ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'OFFLINE');
CREATE TYPE user_status AS ENUM ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'LOCKED');

-- Domain constraints
CREATE DOMAIN email_address AS VARCHAR(255) 
    CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

CREATE DOMAIN ip_address AS INET;

-- =====================================================
-- NORMALIZED SCHEMA (3NF) - Core Tables
-- =====================================================

-- Organizations table (for multi-tenancy)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    domain VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- Roles table (normalized from users)
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Permissions table
CREATE TABLE permissions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    resource VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Role permissions junction table (many-to-many)
CREATE TABLE role_permissions (
    role_id INTEGER REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INTEGER REFERENCES permissions(id) ON DELETE CASCADE,
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    granted_by UUID,
    PRIMARY KEY (role_id, permission_id)
);

-- Users table (3NF normalized)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    username VARCHAR(50) NOT NULL,
    email email_address NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    department VARCHAR(100),
    status user_status DEFAULT 'ACTIVE',
    last_login_at TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id),
    
    CONSTRAINT unique_username_per_org UNIQUE (organization_id, username),
    CONSTRAINT unique_email_per_org UNIQUE (organization_id, email),
    CONSTRAINT valid_phone CHECK (phone IS NULL OR phone ~ '^\+?[1-9]\d{1,14}$')
);

-- User roles junction table
CREATE TABLE user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id INTEGER REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID REFERENCES users(id),
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,
    PRIMARY KEY (user_id, role_id)
);

-- Device types table (normalized)
CREATE TABLE device_types (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    os_family VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Devices table
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    device_type_id INTEGER REFERENCES device_types(id),
    hostname VARCHAR(255) NOT NULL,
    ip_address ip_address,
    mac_address MACADDR,
    os_name VARCHAR(100),
    os_version VARCHAR(50),
    agent_version VARCHAR(20),
    status device_status DEFAULT 'ACTIVE',
    last_seen TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT unique_hostname_per_org UNIQUE (organization_id, hostname)
);

-- Processes table (normalized from file events)
CREATE TABLE processes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    pid INTEGER NOT NULL,
    ppid INTEGER,
    name VARCHAR(255) NOT NULL,
    command_line TEXT,
    executable_path TEXT,
    user_name VARCHAR(100),
    start_time TIMESTAMP WITH TIME ZONE,
    hash_md5 VARCHAR(32),
    hash_sha256 VARCHAR(64),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT unique_pid_per_device UNIQUE (device_id, pid, start_time)
);

-- Files table (normalized)
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    current_path TEXT NOT NULL,
    original_path TEXT,
    filename VARCHAR(255) NOT NULL,
    extension VARCHAR(20),
    size_bytes BIGINT,
    hash_md5 VARCHAR(32),
    hash_sha256 VARCHAR(64),
    mime_type VARCHAR(100),
    permissions VARCHAR(10),
    owner_name VARCHAR(100),
    group_name VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT positive_file_size CHECK (size_bytes >= 0)
);

-- File events table (main activity log)
CREATE TABLE file_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    process_id UUID REFERENCES processes(id) ON DELETE SET NULL,
    file_id UUID REFERENCES files(id) ON DELETE CASCADE,
    action file_action NOT NULL,
    source_path TEXT,
    destination_path TEXT,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    session_id VARCHAR(100),
    ip_address ip_address,
    user_agent TEXT,
    success BOOLEAN DEFAULT TRUE,
    error_message TEXT,
    details JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT valid_paths CHECK (
        (action IN ('CREATE', 'READ', 'WRITE', 'DELETE', 'CHMOD', 'CHOWN') AND source_path IS NOT NULL) OR
        (action IN ('RENAME', 'MOVE', 'COPY') AND source_path IS NOT NULL AND destination_path IS NOT NULL)
    )
);

-- Policies table (for rules engine)
CREATE TABLE policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    rule_definition JSONB NOT NULL,
    severity alert_severity NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id),
    
    CONSTRAINT unique_policy_name_per_org UNIQUE (organization_id, name)
);

-- Alerts table
CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    policy_id UUID REFERENCES policies(id) ON DELETE SET NULL,
    file_event_id UUID REFERENCES file_events(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    severity alert_severity NOT NULL,
    status alert_status DEFAULT 'NEW',
    risk_score INTEGER CHECK (risk_score BETWEEN 0 AND 100),
    metadata JSONB DEFAULT '{}',
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    acknowledged_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- API clients table (for agent authentication)
CREATE TABLE api_clients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    client_id VARCHAR(100) NOT NULL UNIQUE,
    client_secret_hash VARCHAR(255) NOT NULL,
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    permissions TEXT[] DEFAULT '{}',
    last_used_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id)
);

-- Sessions table (for web authentication)
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    ip_address ip_address,
    user_agent TEXT,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT valid_expiry CHECK (expires_at > created_at)
);

-- Audit log table (for compliance)
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID,
    action VARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE
    old_values JSONB,
    new_values JSONB,
    ip_address ip_address,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- INDEXES FOR PERFORMANCE
-- =====================================================

-- Time-based indexes for file_events (most queried table)
CREATE INDEX idx_file_events_occurred_at ON file_events (occurred_at DESC);
CREATE INDEX idx_file_events_device_time ON file_events (device_id, occurred_at DESC);
CREATE INDEX idx_file_events_user_time ON file_events (user_id, occurred_at DESC);
CREATE INDEX idx_file_events_org_time ON file_events (organization_id, occurred_at DESC);

-- Composite indexes for common queries
CREATE INDEX idx_file_events_action_time ON file_events (action, occurred_at DESC);
CREATE INDEX idx_file_events_success_time ON file_events (success, occurred_at DESC) WHERE success = FALSE;

-- GIN index for JSONB fields
CREATE INDEX idx_file_events_details_gin ON file_events USING GIN (details);
CREATE INDEX idx_alerts_metadata_gin ON alerts USING GIN (metadata);
CREATE INDEX idx_devices_metadata_gin ON devices USING GIN (metadata);

-- Partial indexes for active records
CREATE INDEX idx_users_active ON users (organization_id, username) WHERE status = 'ACTIVE';
CREATE INDEX idx_devices_active ON devices (organization_id, hostname) WHERE status = 'ACTIVE';
CREATE INDEX idx_alerts_new ON alerts (organization_id, created_at DESC) WHERE status = 'NEW';

-- Hash indexes for exact lookups
CREATE INDEX idx_files_hash_md5 ON files USING HASH (hash_md5) WHERE hash_md5 IS NOT NULL;
CREATE INDEX idx_files_hash_sha256 ON files USING HASH (hash_sha256) WHERE hash_sha256 IS NOT NULL;

-- Text search indexes
CREATE INDEX idx_files_filename_trgm ON files USING GIN (filename gin_trgm_ops);
CREATE INDEX idx_processes_name_trgm ON processes USING GIN (name gin_trgm_ops);

-- =====================================================
-- CONSTRAINTS AND FOREIGN KEYS
-- =====================================================

-- Add foreign key for self-referencing tables
ALTER TABLE users ADD CONSTRAINT fk_users_created_by 
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE role_permissions ADD CONSTRAINT fk_role_permissions_granted_by 
    FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE user_roles ADD CONSTRAINT fk_user_roles_assigned_by 
    FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL;

-- Check constraints for data integrity
ALTER TABLE alerts ADD CONSTRAINT chk_alert_acknowledgment 
    CHECK ((acknowledged_at IS NULL) = (acknowledged_by IS NULL));

ALTER TABLE alerts ADD CONSTRAINT chk_alert_resolution 
    CHECK ((resolved_at IS NULL) = (resolved_by IS NULL));

ALTER TABLE alerts ADD CONSTRAINT chk_alert_timeline 
    CHECK (acknowledged_at IS NULL OR resolved_at IS NULL OR resolved_at >= acknowledged_at);

ALTER TABLE sessions ADD CONSTRAINT chk_session_activity 
    CHECK (last_activity >= created_at AND last_activity <= expires_at);

-- =====================================================
-- VIEWS FOR SIMPLIFIED QUERIES
-- =====================================================

-- Recent events view (last 24 hours)
CREATE VIEW recent_events_view AS
SELECT 
    fe.id,
    fe.occurred_at,
    fe.action,
    fe.source_path,
    fe.destination_path,
    u.username,
    u.first_name || ' ' || u.last_name AS full_name,
    d.hostname,
    f.filename,
    f.size_bytes,
    fe.success,
    fe.ip_address
FROM file_events fe
LEFT JOIN users u ON fe.user_id = u.id
LEFT JOIN devices d ON fe.device_id = d.id
LEFT JOIN files f ON fe.file_id = f.id
WHERE fe.occurred_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY fe.occurred_at DESC;

-- User activity summary (last 7 days)
CREATE VIEW user_activity_last_7d AS
SELECT 
    u.id,
    u.username,
    u.first_name || ' ' || u.last_name AS full_name,
    COUNT(fe.id) AS total_events,
    COUNT(CASE WHEN fe.action = 'CREATE' THEN 1 END) AS files_created,
    COUNT(CASE WHEN fe.action = 'DELETE' THEN 1 END) AS files_deleted,
    COUNT(CASE WHEN fe.success = FALSE THEN 1 END) AS failed_operations,
    MAX(fe.occurred_at) AS last_activity
FROM users u
LEFT JOIN file_events fe ON u.id = fe.user_id 
    AND fe.occurred_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
WHERE u.status = 'ACTIVE'
GROUP BY u.id, u.username, u.first_name, u.last_name
ORDER BY total_events DESC;

-- Alert summary view
CREATE VIEW alert_summary_view AS
SELECT 
    a.id,
    a.title,
    a.severity,
    a.status,
    a.risk_score,
    a.created_at,
    u.username AS acknowledged_by_user,
    p.name AS policy_name,
    fe.source_path,
    d.hostname
FROM alerts a
LEFT JOIN users u ON a.acknowledged_by = u.id
LEFT JOIN policies p ON a.policy_id = p.id
LEFT JOIN file_events fe ON a.file_event_id = fe.id
LEFT JOIN devices d ON fe.device_id = d.id
ORDER BY a.created_at DESC;

-- Device status view
CREATE VIEW device_status_view AS
SELECT 
    d.id,
    d.hostname,
    d.ip_address,
    d.status,
    d.last_seen,
    dt.name AS device_type,
    COUNT(fe.id) AS events_last_24h,
    COUNT(CASE WHEN fe.success = FALSE THEN 1 END) AS failed_events_last_24h
FROM devices d
LEFT JOIN device_types dt ON d.device_type_id = dt.id
LEFT JOIN file_events fe ON d.id = fe.device_id 
    AND fe.occurred_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY d.id, d.hostname, d.ip_address, d.status, d.last_seen, dt.name
ORDER BY d.last_seen DESC NULLS LAST;

-- =====================================================
-- MATERIALIZED VIEWS FOR HEAVY AGGREGATIONS
-- =====================================================

-- Hourly event statistics (for dashboard charts)
CREATE MATERIALIZED VIEW hourly_event_stats AS
SELECT 
    DATE_TRUNC('hour', occurred_at) AS hour,
    organization_id,
    action,
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(DISTINCT device_id) AS unique_devices,
    COUNT(CASE WHEN success = FALSE THEN 1 END) AS failed_count
FROM file_events
WHERE occurred_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY DATE_TRUNC('hour', occurred_at), organization_id, action
ORDER BY hour DESC;

-- Create unique index on materialized view
CREATE UNIQUE INDEX idx_hourly_stats_unique ON hourly_event_stats (hour, organization_id, action);

-- Daily user activity aggregation
CREATE MATERIALIZED VIEW daily_user_activity AS
SELECT 
    DATE_TRUNC('day', fe.occurred_at) AS day,
    fe.organization_id,
    u.id AS user_id,
    u.username,
    u.department,
    COUNT(fe.id) AS total_events,
    COUNT(DISTINCT fe.file_id) AS unique_files,
    COUNT(DISTINCT fe.device_id) AS unique_devices,
    SUM(CASE WHEN f.size_bytes IS NOT NULL THEN f.size_bytes ELSE 0 END) AS total_bytes_processed
FROM file_events fe
JOIN users u ON fe.user_id = u.id
LEFT JOIN files f ON fe.file_id = f.id
WHERE fe.occurred_at >= CURRENT_TIMESTAMP - INTERVAL '90 days'
GROUP BY DATE_TRUNC('day', fe.occurred_at), fe.organization_id, u.id, u.username, u.department
ORDER BY day DESC;

-- Create unique index on materialized view
CREATE UNIQUE INDEX idx_daily_user_activity_unique ON daily_user_activity (day, organization_id, user_id);

-- Top files by activity (for reports)
CREATE MATERIALIZED VIEW top_files_by_activity AS
SELECT 
    f.id,
    f.current_path,
    f.filename,
    f.extension,
    f.size_bytes,
    COUNT(fe.id) AS total_events,
    COUNT(DISTINCT fe.user_id) AS unique_users,
    COUNT(DISTINCT fe.device_id) AS unique_devices,
    MAX(fe.occurred_at) AS last_accessed,
    COUNT(CASE WHEN fe.action = 'READ' THEN 1 END) AS read_count,
    COUNT(CASE WHEN fe.action = 'WRITE' THEN 1 END) AS write_count,
    COUNT(CASE WHEN fe.action = 'DELETE' THEN 1 END) AS delete_count
FROM files f
JOIN file_events fe ON f.id = fe.file_id
WHERE fe.occurred_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY f.id, f.current_path, f.filename, f.extension, f.size_bytes
HAVING COUNT(fe.id) >= 10  -- Only files with significant activity
ORDER BY total_events DESC
LIMIT 1000;

-- Create unique index on materialized view
CREATE UNIQUE INDEX idx_top_files_unique ON top_files_by_activity (id);

-- =====================================================
-- REFRESH FUNCTIONS FOR MATERIALIZED VIEWS
-- =====================================================

-- Function to refresh all materialized views
CREATE OR REPLACE FUNCTION refresh_all_materialized_views()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY hourly_event_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_user_activity;
    REFRESH MATERIALIZED VIEW CONCURRENTLY top_files_by_activity;
END;
$$ LANGUAGE plpgsql;

-- Function to refresh views based on data age
CREATE OR REPLACE FUNCTION refresh_materialized_views_if_stale()
RETURNS VOID AS $$
DECLARE
    last_refresh TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Check if hourly stats need refresh (every 15 minutes)
    SELECT MAX(hour) INTO last_refresh FROM hourly_event_stats;
    IF last_refresh IS NULL OR last_refresh < CURRENT_TIMESTAMP - INTERVAL '15 minutes' THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY hourly_event_stats;
    END IF;
    
    -- Check if daily activity needs refresh (every hour)
    SELECT MAX(day) INTO last_refresh FROM daily_user_activity;
    IF last_refresh IS NULL OR last_refresh < CURRENT_DATE - INTERVAL '1 hour' THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY daily_user_activity;
    END IF;
    
    -- Check if top files need refresh (every 6 hours)
    SELECT MAX(last_accessed) INTO last_refresh FROM top_files_by_activity;
    IF last_refresh IS NULL OR last_refresh < CURRENT_TIMESTAMP - INTERVAL '6 hours' THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY top_files_by_activity;
    END IF;
END;
$$ LANGUAGE plpgsql;
