-- TRACKVAULT Database Triggers and Functions
-- Advanced DBMS concepts: Triggers, Stored Procedures, Functions

-- =====================================================
-- UTILITY FUNCTIONS
-- =====================================================

-- Function to update timestamp columns
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to generate secure random tokens
CREATE OR REPLACE FUNCTION generate_secure_token(length INTEGER DEFAULT 32)
RETURNS TEXT AS $$
BEGIN
    RETURN encode(gen_random_bytes(length), 'hex');
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- AUDIT LOGGING TRIGGERS
-- =====================================================

-- Generic audit logging function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    audit_user_id UUID;
    audit_ip INET;
    audit_user_agent TEXT;
BEGIN
    -- Get current user context from session variables
    audit_user_id := NULLIF(current_setting('app.current_user_id', TRUE), '')::UUID;
    audit_ip := NULLIF(current_setting('app.current_ip', TRUE), '')::INET;
    audit_user_agent := NULLIF(current_setting('app.current_user_agent', TRUE), '');
    
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_logs (
            organization_id,
            user_id,
            table_name,
            record_id,
            action,
            old_values,
            ip_address,
            user_agent
        ) VALUES (
            COALESCE(OLD.organization_id, audit_user_id),
            audit_user_id,
            TG_TABLE_NAME,
            OLD.id,
            TG_OP,
            row_to_json(OLD),
            audit_ip,
            audit_user_agent
        );
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_logs (
            organization_id,
            user_id,
            table_name,
            record_id,
            action,
            old_values,
            new_values,
            ip_address,
            user_agent
        ) VALUES (
            COALESCE(NEW.organization_id, audit_user_id),
            audit_user_id,
            TG_TABLE_NAME,
            NEW.id,
            TG_OP,
            row_to_json(OLD),
            row_to_json(NEW),
            audit_ip,
            audit_user_agent
        );
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit_logs (
            organization_id,
            user_id,
            table_name,
            record_id,
            action,
            new_values,
            ip_address,
            user_agent
        ) VALUES (
            COALESCE(NEW.organization_id, audit_user_id),
            audit_user_id,
            TG_TABLE_NAME,
            NEW.id,
            TG_OP,
            row_to_json(NEW),
            audit_ip,
            audit_user_agent
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- BUSINESS LOGIC TRIGGERS
-- =====================================================

-- Trigger to update device last_seen on file_event insert
CREATE OR REPLACE FUNCTION update_device_last_seen()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE devices 
    SET last_seen = NEW.occurred_at,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = NEW.device_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to maintain files.current_path on rename/move events
CREATE OR REPLACE FUNCTION update_file_current_path()
RETURNS TRIGGER AS $$
BEGIN
    -- Update file path for rename/move operations
    IF NEW.action IN ('RENAME', 'MOVE') AND NEW.destination_path IS NOT NULL THEN
        UPDATE files 
        SET current_path = NEW.destination_path,
            filename = split_part(NEW.destination_path, '/', -1),
            extension = CASE 
                WHEN split_part(NEW.destination_path, '/', -1) LIKE '%.%' 
                THEN lower(split_part(split_part(NEW.destination_path, '/', -1), '.', -1))
                ELSE NULL
            END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.file_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-lock users after failed login attempts
CREATE OR REPLACE FUNCTION check_failed_login_attempts()
RETURNS TRIGGER AS $$
DECLARE
    max_attempts INTEGER := 5;
    lockout_duration INTERVAL := '30 minutes';
BEGIN
    -- Only process failed login attempts
    IF NEW.failed_login_attempts > OLD.failed_login_attempts THEN
        -- Lock account if max attempts reached
        IF NEW.failed_login_attempts >= max_attempts THEN
            NEW.status := 'LOCKED';
            NEW.locked_until := CURRENT_TIMESTAMP + lockout_duration;
            
            -- Log security event
            INSERT INTO audit_logs (
                organization_id,
                user_id,
                table_name,
                record_id,
                action,
                new_values
            ) VALUES (
                NEW.organization_id,
                NEW.id,
                'users',
                NEW.id,
                'ACCOUNT_LOCKED',
                json_build_object(
                    'reason', 'too_many_failed_attempts',
                    'attempts', NEW.failed_login_attempts,
                    'locked_until', NEW.locked_until
                )
            );
        END IF;
    END IF;
    
    -- Reset failed attempts on successful login
    IF NEW.last_login_at > COALESCE(OLD.last_login_at, '1970-01-01'::timestamp) THEN
        NEW.failed_login_attempts := 0;
        NEW.locked_until := NULL;
        IF OLD.status = 'LOCKED' THEN
            NEW.status := 'ACTIVE';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to validate session expiry
CREATE OR REPLACE FUNCTION validate_session_expiry()
RETURNS TRIGGER AS $$
BEGIN
    -- Ensure expires_at is in the future
    IF NEW.expires_at <= CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'Session expiry must be in the future';
    END IF;
    
    -- Update last_activity on session access
    IF TG_OP = 'UPDATE' AND OLD.last_activity < NEW.last_activity THEN
        -- Extend session if within renewal window (last 25% of session life)
        IF NEW.last_activity > NEW.expires_at - (NEW.expires_at - NEW.created_at) * 0.25 THEN
            NEW.expires_at := NEW.last_activity + (NEW.expires_at - NEW.created_at);
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-generate file metadata
CREATE OR REPLACE FUNCTION generate_file_metadata()
RETURNS TRIGGER AS $$
BEGIN
    -- Extract filename from path if not provided
    IF NEW.filename IS NULL AND NEW.current_path IS NOT NULL THEN
        NEW.filename := split_part(NEW.current_path, '/', -1);
    END IF;
    
    -- Extract extension from filename
    IF NEW.extension IS NULL AND NEW.filename LIKE '%.%' THEN
        NEW.extension := lower(split_part(NEW.filename, '.', -1));
    END IF;
    
    -- Set MIME type based on extension
    IF NEW.mime_type IS NULL AND NEW.extension IS NOT NULL THEN
        NEW.mime_type := CASE NEW.extension
            WHEN 'txt' THEN 'text/plain'
            WHEN 'pdf' THEN 'application/pdf'
            WHEN 'doc' THEN 'application/msword'
            WHEN 'docx' THEN 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            WHEN 'xls' THEN 'application/vnd.ms-excel'
            WHEN 'xlsx' THEN 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            WHEN 'jpg' THEN 'image/jpeg'
            WHEN 'jpeg' THEN 'image/jpeg'
            WHEN 'png' THEN 'image/png'
            WHEN 'gif' THEN 'image/gif'
            WHEN 'mp4' THEN 'video/mp4'
            WHEN 'avi' THEN 'video/x-msvideo'
            WHEN 'zip' THEN 'application/zip'
            WHEN 'exe' THEN 'application/x-msdownload'
            ELSE 'application/octet-stream'
        END;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- SECURITY AND COMPLIANCE TRIGGERS
-- =====================================================

-- Trigger to hash passwords before storing
CREATE OR REPLACE FUNCTION hash_user_password()
RETURNS TRIGGER AS $$
BEGIN
    -- Only hash if password has changed and is not already hashed
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.password_hash != OLD.password_hash) THEN
        -- Check if password looks like a hash (starts with $2b$ for bcrypt)
        IF NOT (NEW.password_hash LIKE '$2b$%' OR NEW.password_hash LIKE '$2a$%') THEN
            -- Hash the password using crypt with bcrypt
            NEW.password_hash := crypt(NEW.password_hash, gen_salt('bf', 12));
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to hash API client secrets
CREATE OR REPLACE FUNCTION hash_client_secret()
RETURNS TRIGGER AS $$
BEGIN
    -- Only hash if secret has changed and is not already hashed
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.client_secret_hash != OLD.client_secret_hash) THEN
        -- Check if secret looks like a hash
        IF NOT (NEW.client_secret_hash LIKE '$2b$%' OR NEW.client_secret_hash LIKE '$2a$%') THEN
            NEW.client_secret_hash := crypt(NEW.client_secret_hash, gen_salt('bf', 12));
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to hash session tokens
CREATE OR REPLACE FUNCTION hash_session_token()
RETURNS TRIGGER AS $$
BEGIN
    -- Hash the token for storage
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.token_hash != OLD.token_hash) THEN
        -- Check if token looks like a hash
        IF NOT (NEW.token_hash LIKE '$2b$%' OR NEW.token_hash LIKE '$2a$%') THEN
            NEW.token_hash := crypt(NEW.token_hash, gen_salt('bf', 10));
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- DATA VALIDATION TRIGGERS
-- =====================================================

-- Trigger to validate file event data consistency
CREATE OR REPLACE FUNCTION validate_file_event_data()
RETURNS TRIGGER AS $$
BEGIN
    -- Validate that user belongs to the same organization as device
    IF NEW.user_id IS NOT NULL AND NEW.device_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM users u 
            JOIN devices d ON u.organization_id = d.organization_id 
            WHERE u.id = NEW.user_id AND d.id = NEW.device_id
        ) THEN
            RAISE EXCEPTION 'User and device must belong to the same organization';
        END IF;
    END IF;
    
    -- Validate occurred_at is not in the future
    IF NEW.occurred_at > CURRENT_TIMESTAMP + INTERVAL '5 minutes' THEN
        RAISE EXCEPTION 'Event time cannot be more than 5 minutes in the future';
    END IF;
    
    -- Validate occurred_at is not too old (more than 1 year)
    IF NEW.occurred_at < CURRENT_TIMESTAMP - INTERVAL '1 year' THEN
        RAISE EXCEPTION 'Event time cannot be more than 1 year in the past';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- ALERT GENERATION TRIGGERS
-- =====================================================

-- Trigger to evaluate policies and generate alerts
CREATE OR REPLACE FUNCTION evaluate_policies_for_alerts()
RETURNS TRIGGER AS $$
DECLARE
    policy_record RECORD;
    alert_title TEXT;
    alert_description TEXT;
    risk_score INTEGER;
BEGIN
    -- Loop through active policies for the organization
    FOR policy_record IN 
        SELECT * FROM policies 
        WHERE organization_id = NEW.organization_id 
        AND is_active = TRUE
    LOOP
        -- Evaluate rule (simplified - in real implementation, use a proper rules engine)
        IF evaluate_policy_rule(policy_record.rule_definition, NEW) THEN
            -- Generate alert title and description based on rule
            alert_title := COALESCE(
                policy_record.rule_definition->>'alert_title',
                'Policy Violation: ' || policy_record.name
            );
            
            alert_description := COALESCE(
                policy_record.rule_definition->>'alert_description',
                'File event triggered policy: ' || policy_record.name
            );
            
            -- Calculate risk score based on severity and context
            risk_score := CASE policy_record.severity
                WHEN 'LOW' THEN 25
                WHEN 'MEDIUM' THEN 50
                WHEN 'HIGH' THEN 75
                WHEN 'CRITICAL' THEN 90
            END;
            
            -- Adjust risk score based on event context
            IF NEW.action IN ('DELETE', 'RENAME', 'MOVE') THEN
                risk_score := risk_score + 10;
            END IF;
            
            IF NEW.success = FALSE THEN
                risk_score := risk_score + 15;
            END IF;
            
            -- Cap risk score at 100
            risk_score := LEAST(risk_score, 100);
            
            -- Insert alert
            INSERT INTO alerts (
                organization_id,
                policy_id,
                file_event_id,
                title,
                description,
                severity,
                risk_score,
                metadata
            ) VALUES (
                NEW.organization_id,
                policy_record.id,
                NEW.id,
                alert_title,
                alert_description,
                policy_record.severity,
                risk_score,
                json_build_object(
                    'policy_name', policy_record.name,
                    'event_action', NEW.action,
                    'event_path', NEW.source_path,
                    'event_success', NEW.success,
                    'triggered_at', CURRENT_TIMESTAMP
                )
            );
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to evaluate policy rules (simplified implementation)
CREATE OR REPLACE FUNCTION evaluate_policy_rule(rule_definition JSONB, event_data file_events)
RETURNS BOOLEAN AS $$
DECLARE
    rule_type TEXT;
    conditions JSONB;
BEGIN
    rule_type := rule_definition->>'type';
    conditions := rule_definition->'conditions';
    
    -- Simple rule evaluation (expand this for complex rules)
    CASE rule_type
        WHEN 'file_action' THEN
            RETURN conditions ? event_data.action::TEXT;
        
        WHEN 'file_extension' THEN
            RETURN EXISTS (
                SELECT 1 FROM files f 
                WHERE f.id = event_data.file_id 
                AND conditions ? f.extension
            );
        
        WHEN 'file_size' THEN
            RETURN EXISTS (
                SELECT 1 FROM files f 
                WHERE f.id = event_data.file_id 
                AND f.size_bytes > (conditions->>'min_size')::BIGINT
            );
        
        WHEN 'failed_operation' THEN
            RETURN event_data.success = FALSE;
        
        WHEN 'suspicious_time' THEN
            -- Check if event occurred outside business hours
            RETURN EXTRACT(hour FROM event_data.occurred_at) NOT BETWEEN 9 AND 17
                OR EXTRACT(dow FROM event_data.occurred_at) IN (0, 6); -- Weekend
        
        ELSE
            RETURN FALSE;
    END CASE;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- CREATE TRIGGERS
-- =====================================================

-- Updated timestamp triggers
CREATE TRIGGER tr_users_updated_at 
    BEFORE UPDATE ON users 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_devices_updated_at 
    BEFORE UPDATE ON devices 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_files_updated_at 
    BEFORE UPDATE ON files 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_organizations_updated_at 
    BEFORE UPDATE ON organizations 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_policies_updated_at 
    BEFORE UPDATE ON policies 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_alerts_updated_at 
    BEFORE UPDATE ON alerts 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Audit logging triggers
CREATE TRIGGER tr_users_audit 
    AFTER INSERT OR UPDATE OR DELETE ON users 
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER tr_devices_audit 
    AFTER INSERT OR UPDATE OR DELETE ON devices 
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER tr_file_events_audit 
    AFTER INSERT OR UPDATE OR DELETE ON file_events 
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER tr_alerts_audit 
    AFTER INSERT OR UPDATE OR DELETE ON alerts 
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- Business logic triggers
CREATE TRIGGER tr_file_events_update_device_last_seen 
    AFTER INSERT ON file_events 
    FOR EACH ROW EXECUTE FUNCTION update_device_last_seen();

CREATE TRIGGER tr_file_events_update_file_path 
    AFTER INSERT ON file_events 
    FOR EACH ROW EXECUTE FUNCTION update_file_current_path();

CREATE TRIGGER tr_users_check_failed_logins 
    BEFORE UPDATE ON users 
    FOR EACH ROW EXECUTE FUNCTION check_failed_login_attempts();

CREATE TRIGGER tr_sessions_validate_expiry 
    BEFORE INSERT OR UPDATE ON sessions 
    FOR EACH ROW EXECUTE FUNCTION validate_session_expiry();

CREATE TRIGGER tr_files_generate_metadata 
    BEFORE INSERT OR UPDATE ON files 
    FOR EACH ROW EXECUTE FUNCTION generate_file_metadata();

-- Security triggers
CREATE TRIGGER tr_users_hash_password 
    BEFORE INSERT OR UPDATE ON users 
    FOR EACH ROW EXECUTE FUNCTION hash_user_password();

CREATE TRIGGER tr_api_clients_hash_secret 
    BEFORE INSERT OR UPDATE ON api_clients 
    FOR EACH ROW EXECUTE FUNCTION hash_client_secret();

CREATE TRIGGER tr_sessions_hash_token 
    BEFORE INSERT OR UPDATE ON sessions 
    FOR EACH ROW EXECUTE FUNCTION hash_session_token();

-- Validation triggers
CREATE TRIGGER tr_file_events_validate_data 
    BEFORE INSERT OR UPDATE ON file_events 
    FOR EACH ROW EXECUTE FUNCTION validate_file_event_data();

-- Alert generation triggers
CREATE TRIGGER tr_file_events_evaluate_policies 
    AFTER INSERT ON file_events 
    FOR EACH ROW EXECUTE FUNCTION evaluate_policies_for_alerts();

-- =====================================================
-- CLEANUP AND MAINTENANCE TRIGGERS
-- =====================================================

-- Function to cleanup expired sessions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM sessions WHERE expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    -- Log cleanup activity
    INSERT INTO audit_logs (
        table_name,
        action,
        new_values
    ) VALUES (
        'sessions',
        'CLEANUP',
        json_build_object(
            'deleted_count', deleted_count,
            'cleanup_time', CURRENT_TIMESTAMP
        )
    );
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to archive old file events
CREATE OR REPLACE FUNCTION archive_old_file_events(retention_days INTEGER DEFAULT 365)
RETURNS INTEGER AS $$
DECLARE
    archived_count INTEGER;
    cutoff_date TIMESTAMP WITH TIME ZONE;
BEGIN
    cutoff_date := CURRENT_TIMESTAMP - (retention_days || ' days')::INTERVAL;
    
    -- Move old events to archive table (create if not exists)
    CREATE TABLE IF NOT EXISTS file_events_archive (LIKE file_events INCLUDING ALL);
    
    WITH archived_events AS (
        DELETE FROM file_events 
        WHERE occurred_at < cutoff_date
        RETURNING *
    )
    INSERT INTO file_events_archive 
    SELECT * FROM archived_events;
    
    GET DIAGNOSTICS archived_count = ROW_COUNT;
    
    -- Log archival activity
    INSERT INTO audit_logs (
        table_name,
        action,
        new_values
    ) VALUES (
        'file_events',
        'ARCHIVE',
        json_build_object(
            'archived_count', archived_count,
            'cutoff_date', cutoff_date,
            'retention_days', retention_days
        )
    );
    
    RETURN archived_count;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- PERFORMANCE MONITORING FUNCTIONS
-- =====================================================

-- Function to analyze query performance
CREATE OR REPLACE FUNCTION analyze_query_performance()
RETURNS TABLE (
    query_text TEXT,
    calls BIGINT,
    total_time DOUBLE PRECISION,
    mean_time DOUBLE PRECISION,
    rows BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pg_stat_statements.query,
        pg_stat_statements.calls,
        pg_stat_statements.total_exec_time,
        pg_stat_statements.mean_exec_time,
        pg_stat_statements.rows
    FROM pg_stat_statements
    WHERE pg_stat_statements.query LIKE '%file_events%'
       OR pg_stat_statements.query LIKE '%alerts%'
       OR pg_stat_statements.query LIKE '%users%'
    ORDER BY pg_stat_statements.total_exec_time DESC
    LIMIT 20;
END;
$$ LANGUAGE plpgsql;

-- Function to get table statistics
CREATE OR REPLACE FUNCTION get_table_statistics()
RETURNS TABLE (
    table_name TEXT,
    row_count BIGINT,
    table_size TEXT,
    index_size TEXT,
    total_size TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.table_name::TEXT,
        t.n_tup_ins - t.n_tup_del AS row_count,
        pg_size_pretty(pg_total_relation_size(c.oid) - pg_indexes_size(c.oid)) AS table_size,
        pg_size_pretty(pg_indexes_size(c.oid)) AS index_size,
        pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
    FROM pg_stat_user_tables t
    JOIN pg_class c ON c.relname = t.relname
    WHERE t.schemaname = 'public'
    ORDER BY pg_total_relation_size(c.oid) DESC;
END;
$$ LANGUAGE plpgsql;
