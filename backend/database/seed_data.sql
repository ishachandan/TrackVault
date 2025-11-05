-- TRACKVAULT Seed Data
-- Sample data for development and testing

-- =====================================================
-- SEED BASIC REFERENCE DATA
-- =====================================================

-- Insert roles
INSERT INTO roles (name, description) VALUES
('Admin', 'Full system administrator with all permissions'),
('Manager', 'Department manager with user and policy management'),
('Analyst', 'Security analyst with read access to logs and alerts'),
('User', 'Standard user with basic file access'),
('Auditor', 'Read-only access for compliance and auditing');

-- Insert permissions
INSERT INTO permissions (name, resource, action, description) VALUES
('users.create', 'users', 'create', 'Create new users'),
('users.read', 'users', 'read', 'View user information'),
('users.update', 'users', 'update', 'Update user information'),
('users.delete', 'users', 'delete', 'Delete users'),
('devices.read', 'devices', 'read', 'View device information'),
('devices.update', 'devices', 'update', 'Update device information'),
('events.read', 'events', 'read', 'View file events'),
('alerts.read', 'alerts', 'read', 'View security alerts'),
('alerts.update', 'alerts', 'update', 'Acknowledge and resolve alerts'),
('policies.create', 'policies', 'create', 'Create security policies'),
('policies.read', 'policies', 'read', 'View security policies'),
('policies.update', 'policies', 'update', 'Update security policies'),
('policies.delete', 'policies', 'delete', 'Delete security policies'),
('reports.read', 'reports', 'read', 'View reports and analytics'),
('system.admin', 'system', 'admin', 'System administration functions');

-- Assign permissions to roles
INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.name = 'Admin'; -- Admin gets all permissions

INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.name = 'Manager' AND p.name IN (
    'users.create', 'users.read', 'users.update',
    'devices.read', 'events.read', 'alerts.read', 'alerts.update',
    'policies.create', 'policies.read', 'policies.update',
    'reports.read'
);

INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.name = 'Analyst' AND p.name IN (
    'users.read', 'devices.read', 'events.read', 
    'alerts.read', 'alerts.update', 'policies.read', 'reports.read'
);

INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.name = 'User' AND p.name IN (
    'events.read', 'alerts.read', 'reports.read'
);

INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.name = 'Auditor' AND p.name IN (
    'users.read', 'devices.read', 'events.read', 'alerts.read', 'reports.read'
);

-- Insert device types
INSERT INTO device_types (name, description, os_family) VALUES
('Desktop', 'Desktop workstation', 'Windows'),
('Laptop', 'Laptop computer', 'Windows'),
('Server', 'Server system', 'Linux'),
('Mobile', 'Mobile device', 'Android'),
('Mac Desktop', 'Apple desktop', 'macOS'),
('Mac Laptop', 'Apple laptop', 'macOS');

-- =====================================================
-- SEED ORGANIZATIONS AND USERS
-- =====================================================

-- Insert sample organizations
INSERT INTO organizations (id, name, domain) VALUES
('550e8400-e29b-41d4-a716-446655440001', 'TechCorp Inc', 'techcorp.com'),
('550e8400-e29b-41d4-a716-446655440002', 'SecureBank Ltd', 'securebank.com'),
('550e8400-e29b-41d4-a716-446655440003', 'HealthSystem', 'healthsys.org');

-- Insert sample users for TechCorp
INSERT INTO users (id, organization_id, username, email, password_hash, first_name, last_name, department) VALUES
('650e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 'admin', 'admin@techcorp.com', 'admin123', 'System', 'Administrator', 'IT'),
('650e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', 'john.doe', 'john.doe@techcorp.com', 'password123', 'John', 'Doe', 'Engineering'),
('650e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440001', 'jane.smith', 'jane.smith@techcorp.com', 'password123', 'Jane', 'Smith', 'Security'),
('650e8400-e29b-41d4-a716-446655440004', '550e8400-e29b-41d4-a716-446655440001', 'bob.wilson', 'bob.wilson@techcorp.com', 'password123', 'Bob', 'Wilson', 'Finance'),
('650e8400-e29b-41d4-a716-446655440005', '550e8400-e29b-41d4-a716-446655440001', 'alice.brown', 'alice.brown@techcorp.com', 'password123', 'Alice', 'Brown', 'HR'),
('650e8400-e29b-41d4-a716-446655440006', '550e8400-e29b-41d4-a716-446655440001', 'charlie.davis', 'charlie.davis@techcorp.com', 'password123', 'Charlie', 'Davis', 'Engineering'),
('650e8400-e29b-41d4-a716-446655440007', '550e8400-e29b-41d4-a716-446655440001', 'diana.miller', 'diana.miller@techcorp.com', 'password123', 'Diana', 'Miller', 'Marketing');

-- Assign roles to users
INSERT INTO user_roles (user_id, role_id) VALUES
('650e8400-e29b-41d4-a716-446655440001', (SELECT id FROM roles WHERE name = 'Admin')),
('650e8400-e29b-41d4-a716-446655440002', (SELECT id FROM roles WHERE name = 'Manager')),
('650e8400-e29b-41d4-a716-446655440003', (SELECT id FROM roles WHERE name = 'Analyst')),
('650e8400-e29b-41d4-a716-446655440004', (SELECT id FROM roles WHERE name = 'User')),
('650e8400-e29b-41d4-a716-446655440005', (SELECT id FROM roles WHERE name = 'User')),
('650e8400-e29b-41d4-a716-446655440006', (SELECT id FROM roles WHERE name = 'User')),
('650e8400-e29b-41d4-a716-446655440007', (SELECT id FROM roles WHERE name = 'User'));

-- =====================================================
-- SEED DEVICES
-- =====================================================

-- Insert sample devices
INSERT INTO devices (id, organization_id, device_type_id, hostname, ip_address, mac_address, os_name, os_version, agent_version, metadata) VALUES
('750e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 1, 'DESKTOP-001', '192.168.1.101', '00:1B:44:11:3A:B7', 'Windows 11 Pro', '22H2', '1.2.3', '{"cpu": "Intel i7", "ram": "16GB"}'),
('750e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', 2, 'LAPTOP-002', '192.168.1.102', '00:1B:44:11:3A:B8', 'Windows 11 Pro', '22H2', '1.2.3', '{"cpu": "Intel i5", "ram": "8GB"}'),
('750e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440001', 3, 'SERVER-001', '192.168.1.10', '00:1B:44:11:3A:B9', 'Ubuntu Server', '22.04 LTS', '1.2.3', '{"cpu": "Xeon", "ram": "64GB"}'),
('750e8400-e29b-41d4-a716-446655440004', '550e8400-e29b-41d4-a716-446655440001', 2, 'LAPTOP-003', '192.168.1.103', '00:1B:44:11:3A:BA', 'Windows 11 Pro', '22H2', '1.2.3', '{"cpu": "AMD Ryzen 7", "ram": "16GB"}'),
('750e8400-e29b-41d4-a716-446655440005', '550e8400-e29b-41d4-a716-446655440001', 5, 'IMAC-001', '192.168.1.104', '00:1B:44:11:3A:BB', 'macOS Ventura', '13.4', '1.2.3', '{"cpu": "M2", "ram": "24GB"}');

-- =====================================================
-- SEED SAMPLE PROCESSES
-- =====================================================

INSERT INTO processes (id, device_id, pid, ppid, name, command_line, executable_path, user_name, hash_md5, hash_sha256) VALUES
('850e8400-e29b-41d4-a716-446655440001', '750e8400-e29b-41d4-a716-446655440001', 1234, 1000, 'notepad.exe', 'notepad.exe C:\temp\document.txt', 'C:\Windows\System32\notepad.exe', 'john.doe', 'a1b2c3d4e5f6', 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2'),
('850e8400-e29b-41d4-a716-446655440002', '750e8400-e29b-41d4-a716-446655440002', 5678, 1000, 'chrome.exe', 'chrome.exe --new-window', 'C:\Program Files\Google\Chrome\Application\chrome.exe', 'jane.smith', 'b2c3d4e5f6a7', 'b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3'),
('850e8400-e29b-41d4-a716-446655440003', '750e8400-e29b-41d4-a716-446655440003', 9012, 1, 'apache2', '/usr/sbin/apache2 -D FOREGROUND', '/usr/sbin/apache2', 'www-data', 'c3d4e5f6a7b8', 'c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4');

-- =====================================================
-- SEED SAMPLE FILES
-- =====================================================

INSERT INTO files (id, device_id, current_path, filename, extension, size_bytes, hash_md5, hash_sha256, mime_type, permissions, owner_name, group_name) VALUES
('950e8400-e29b-41d4-a716-446655440001', '750e8400-e29b-41d4-a716-446655440001', 'C:\Users\john.doe\Documents\project_plan.docx', 'project_plan.docx', 'docx', 524288, 'd1e2f3a4b5c6', 'd1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'rw-r--r--', 'john.doe', 'users'),
('950e8400-e29b-41d4-a716-446655440002', '750e8400-e29b-41d4-a716-446655440002', 'C:\Users\jane.smith\Desktop\security_report.pdf', 'security_report.pdf', 'pdf', 1048576, 'e2f3a4b5c6d7', 'e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3', 'application/pdf', 'rw-r--r--', 'jane.smith', 'users'),
('950e8400-e29b-41d4-a716-446655440003', '750e8400-e29b-41d4-a716-446655440003', '/var/log/apache2/access.log', 'access.log', 'log', 2097152, 'f3a4b5c6d7e8', 'f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4', 'text/plain', 'rw-r--r--', 'www-data', 'adm'),
('950e8400-e29b-41d4-a716-446655440004', '750e8400-e29b-41d4-a716-446655440001', 'C:\Temp\sensitive_data.xlsx', 'sensitive_data.xlsx', 'xlsx', 786432, 'a4b5c6d7e8f9', 'a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'rw-r--r--', 'bob.wilson', 'users'),
('950e8400-e29b-41d4-a716-446655440005', '750e8400-e29b-41d4-a716-446655440004', 'C:\Users\charlie.davis\Code\app.py', 'app.py', 'py', 16384, 'b5c6d7e8f9a0', 'b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6', 'text/x-python', 'rw-r--r--', 'charlie.davis', 'users');

-- =====================================================
-- SEED SAMPLE POLICIES
-- =====================================================

INSERT INTO policies (id, organization_id, name, description, rule_definition, severity, created_by) VALUES
('a50e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 'Sensitive File Access', 'Alert on access to files containing sensitive data', 
'{"type": "file_extension", "conditions": ["xlsx", "pdf", "docx"], "alert_title": "Sensitive File Accessed", "alert_description": "A file with potentially sensitive content was accessed"}', 
'MEDIUM', '650e8400-e29b-41d4-a716-446655440001'),

('a50e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', 'File Deletion Monitor', 'Alert on file deletion activities', 
'{"type": "file_action", "conditions": ["DELETE"], "alert_title": "File Deleted", "alert_description": "A file has been permanently deleted"}', 
'HIGH', '650e8400-e29b-41d4-a716-446655440001'),

('a50e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440001', 'Large File Transfer', 'Alert on large file operations', 
'{"type": "file_size", "conditions": {"min_size": 10485760}, "alert_title": "Large File Operation", "alert_description": "Operation on file larger than 10MB detected"}', 
'LOW', '650e8400-e29b-41d4-a716-446655440001'),

('a50e8400-e29b-41d4-a716-446655440004', '550e8400-e29b-41d4-a716-446655440001', 'Failed Operations', 'Alert on failed file operations', 
'{"type": "failed_operation", "conditions": {}, "alert_title": "Failed File Operation", "alert_description": "A file operation has failed"}', 
'MEDIUM', '650e8400-e29b-41d4-a716-446655440001'),

('a50e8400-e29b-41d4-a716-446655440005', '550e8400-e29b-41d4-a716-446655440001', 'Off-Hours Activity', 'Alert on file activity outside business hours', 
'{"type": "suspicious_time", "conditions": {}, "alert_title": "Off-Hours File Activity", "alert_description": "File activity detected outside normal business hours"}', 
'MEDIUM', '650e8400-e29b-41d4-a716-446655440001');

-- =====================================================
-- SEED SAMPLE FILE EVENTS (Last 30 days)
-- =====================================================

-- Generate file events for the last 30 days
INSERT INTO file_events (id, organization_id, device_id, user_id, process_id, file_id, action, source_path, occurred_at, session_id, ip_address, success, details) 
SELECT 
    uuid_generate_v4(),
    '550e8400-e29b-41d4-a716-446655440001',
    (ARRAY['750e8400-e29b-41d4-a716-446655440001', '750e8400-e29b-41d4-a716-446655440002', '750e8400-e29b-41d4-a716-446655440003', '750e8400-e29b-41d4-a716-446655440004'])[floor(random() * 4 + 1)]::UUID,
    (ARRAY['650e8400-e29b-41d4-a716-446655440002', '650e8400-e29b-41d4-a716-446655440003', '650e8400-e29b-41d4-a716-446655440004', '650e8400-e29b-41d4-a716-446655440005', '650e8400-e29b-41d4-a716-446655440006'])[floor(random() * 5 + 1)]::UUID,
    (ARRAY['850e8400-e29b-41d4-a716-446655440001', '850e8400-e29b-41d4-a716-446655440002', '850e8400-e29b-41d4-a716-446655440003'])[floor(random() * 3 + 1)]::UUID,
    (ARRAY['950e8400-e29b-41d4-a716-446655440001', '950e8400-e29b-41d4-a716-446655440002', '950e8400-e29b-41d4-a716-446655440003', '950e8400-e29b-41d4-a716-446655440004', '950e8400-e29b-41d4-a716-446655440005'])[floor(random() * 5 + 1)]::UUID,
    (ARRAY['READ', 'WRITE', 'CREATE', 'DELETE'])[floor(random() * 4 + 1)]::file_action,
    '/path/to/file_' || generate_series || '.txt',
    CURRENT_TIMESTAMP - (random() * INTERVAL '30 days'),
    'session_' || generate_series,
    ('192.168.1.' || floor(random() * 254 + 1))::INET,
    CASE WHEN random() > 0.1 THEN TRUE ELSE FALSE END,
    '{"user_agent": "TRACKVAULT-Agent/1.2.3", "process_name": "explorer.exe"}'::JSONB
FROM generate_series(1, 1000);

-- Generate some specific events for testing alerts
INSERT INTO file_events (organization_id, device_id, user_id, file_id, action, source_path, occurred_at, success, details) VALUES
-- Sensitive file access
('550e8400-e29b-41d4-a716-446655440001', '750e8400-e29b-41d4-a716-446655440001', '650e8400-e29b-41d4-a716-446655440004', '950e8400-e29b-41d4-a716-446655440004', 'READ', 'C:\Temp\sensitive_data.xlsx', CURRENT_TIMESTAMP - INTERVAL '2 hours', TRUE, '{"alert_triggered": true}'),

-- File deletion
('550e8400-e29b-41d4-a716-446655440001', '750e8400-e29b-41d4-a716-446655440002', '650e8400-e29b-41d4-a716-446655440005', '950e8400-e29b-41d4-a716-446655440002', 'DELETE', 'C:\Users\jane.smith\Desktop\security_report.pdf', CURRENT_TIMESTAMP - INTERVAL '1 hour', TRUE, '{"alert_triggered": true}'),

-- Failed operation
('550e8400-e29b-41d4-a716-446655440001', '750e8400-e29b-41d4-a716-446655440001', '650e8400-e29b-41d4-a716-446655440006', '950e8400-e29b-41d4-a716-446655440001', 'WRITE', 'C:\Users\john.doe\Documents\project_plan.docx', CURRENT_TIMESTAMP - INTERVAL '30 minutes', FALSE, '{"error": "Access denied", "alert_triggered": true}'),

-- Off-hours activity (weekend)
('550e8400-e29b-41d4-a716-446655440001', '750e8400-e29b-41d4-a716-446655440004', '650e8400-e29b-41d4-a716-446655440006', '950e8400-e29b-41d4-a716-446655440005', 'READ', 'C:\Users\charlie.davis\Code\app.py', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '22 hours', TRUE, '{"alert_triggered": true}');

-- =====================================================
-- SEED API CLIENTS
-- =====================================================

INSERT INTO api_clients (id, organization_id, name, client_id, client_secret_hash, device_id, permissions, expires_at, created_by) VALUES
('b50e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 'Desktop Agent 001', 'agent_desktop_001', 'secret123', '750e8400-e29b-41d4-a716-446655440001', ARRAY['events.create', 'devices.update'], CURRENT_TIMESTAMP + INTERVAL '1 year', '650e8400-e29b-41d4-a716-446655440001'),
('b50e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', 'Laptop Agent 002', 'agent_laptop_002', 'secret123', '750e8400-e29b-41d4-a716-446655440002', ARRAY['events.create', 'devices.update'], CURRENT_TIMESTAMP + INTERVAL '1 year', '650e8400-e29b-41d4-a716-446655440001'),
('b50e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440001', 'Server Agent 001', 'agent_server_001', 'secret123', '750e8400-e29b-41d4-a716-446655440003', ARRAY['events.create', 'devices.update'], CURRENT_TIMESTAMP + INTERVAL '1 year', '650e8400-e29b-41d4-a716-446655440001');

-- =====================================================
-- UPDATE STATISTICS AND REFRESH VIEWS
-- =====================================================

-- Update table statistics
ANALYZE users;
ANALYZE devices;
ANALYZE files;
ANALYZE file_events;
ANALYZE alerts;
ANALYZE policies;

-- Refresh materialized views
SELECT refresh_all_materialized_views();

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Verify data insertion
DO $$
DECLARE
    user_count INTEGER;
    device_count INTEGER;
    event_count INTEGER;
    alert_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO user_count FROM users;
    SELECT COUNT(*) INTO device_count FROM devices;
    SELECT COUNT(*) INTO event_count FROM file_events;
    SELECT COUNT(*) INTO alert_count FROM alerts;
    
    RAISE NOTICE 'Seed data verification:';
    RAISE NOTICE '- Users: %', user_count;
    RAISE NOTICE '- Devices: %', device_count;
    RAISE NOTICE '- File Events: %', event_count;
    RAISE NOTICE '- Alerts: %', alert_count;
    
    IF user_count = 0 OR device_count = 0 OR event_count = 0 THEN
        RAISE EXCEPTION 'Seed data insertion failed - missing critical data';
    END IF;
END $$;
