-- TRACKVAULT Stored Procedures and Functions
-- Advanced DBMS concepts: Complex queries, transactions, bulk operations

-- =====================================================
-- BULK INGESTION PROCEDURES
-- =====================================================

-- Stored procedure for bulk event ingestion with upserts
CREATE OR REPLACE FUNCTION ingest_events_batch(events_json JSONB)
RETURNS TABLE (
    processed_count INTEGER,
    success_count INTEGER,
    error_count INTEGER,
    errors JSONB
) AS $$
DECLARE
    event_record JSONB;
    org_id UUID;
    device_id UUID;
    user_id UUID;
    process_id UUID;
    file_id UUID;
    processed INTEGER := 0;
    success INTEGER := 0;
    error INTEGER := 0;
    error_list JSONB := '[]'::JSONB;
    error_msg TEXT;
BEGIN
    -- Loop through each event in the JSON array
    FOR event_record IN SELECT * FROM jsonb_array_elements(events_json)
    LOOP
        BEGIN
            processed := processed + 1;
            
            -- Start a savepoint for this event
            SAVEPOINT event_processing;
            
            -- Get or create organization
            SELECT id INTO org_id FROM organizations 
            WHERE name = event_record->>'organization_name'
            LIMIT 1;
            
            IF org_id IS NULL THEN
                INSERT INTO organizations (name, domain)
                VALUES (
                    event_record->>'organization_name',
                    COALESCE(event_record->>'organization_domain', 'unknown.com')
                )
                RETURNING id INTO org_id;
            END IF;
            
            -- Upsert device
            INSERT INTO devices (
                organization_id,
                hostname,
                ip_address,
                mac_address,
                os_name,
                os_version,
                agent_version,
                metadata
            ) VALUES (
                org_id,
                event_record->>'hostname',
                NULLIF(event_record->>'ip_address', '')::INET,
                NULLIF(event_record->>'mac_address', '')::MACADDR,
                event_record->>'os_name',
                event_record->>'os_version',
                event_record->>'agent_version',
                COALESCE(event_record->'device_metadata', '{}'::JSONB)
            )
            ON CONFLICT (organization_id, hostname) 
            DO UPDATE SET
                ip_address = EXCLUDED.ip_address,
                os_name = EXCLUDED.os_name,
                os_version = EXCLUDED.os_version,
                agent_version = EXCLUDED.agent_version,
                metadata = EXCLUDED.metadata,
                updated_at = CURRENT_TIMESTAMP
            RETURNING id INTO device_id;
            
            -- Upsert user
            user_id := NULL;
            IF event_record ? 'username' AND event_record->>'username' != '' THEN
                INSERT INTO users (
                    organization_id,
                    username,
                    email,
                    password_hash,
                    first_name,
                    last_name,
                    department
                ) VALUES (
                    org_id,
                    event_record->>'username',
                    COALESCE(event_record->>'email', event_record->>'username' || '@unknown.com'),
                    'placeholder_hash',
                    COALESCE(event_record->>'first_name', split_part(event_record->>'username', '.', 1)),
                    COALESCE(event_record->>'last_name', split_part(event_record->>'username', '.', 2)),
                    event_record->>'department'
                )
                ON CONFLICT (organization_id, username) 
                DO UPDATE SET
                    email = EXCLUDED.email,
                    first_name = EXCLUDED.first_name,
                    last_name = EXCLUDED.last_name,
                    department = EXCLUDED.department,
                    updated_at = CURRENT_TIMESTAMP
                RETURNING id INTO user_id;
            END IF;
            
            -- Upsert process
            process_id := NULL;
            IF event_record ? 'process_pid' AND (event_record->>'process_pid')::INTEGER > 0 THEN
                INSERT INTO processes (
                    device_id,
                    pid,
                    ppid,
                    name,
                    command_line,
                    executable_path,
                    user_name,
                    hash_md5,
                    hash_sha256
                ) VALUES (
                    device_id,
                    (event_record->>'process_pid')::INTEGER,
                    NULLIF(event_record->>'process_ppid', '')::INTEGER,
                    event_record->>'process_name',
                    event_record->>'process_command_line',
                    event_record->>'process_executable_path',
                    event_record->>'process_user',
                    event_record->>'process_hash_md5',
                    event_record->>'process_hash_sha256'
                )
                ON CONFLICT (device_id, pid, start_time) 
                DO UPDATE SET
                    name = EXCLUDED.name,
                    command_line = EXCLUDED.command_line,
                    executable_path = EXCLUDED.executable_path,
                    user_name = EXCLUDED.user_name,
                    hash_md5 = EXCLUDED.hash_md5,
                    hash_sha256 = EXCLUDED.hash_sha256
                RETURNING id INTO process_id;
            END IF;
            
            -- Upsert file
            INSERT INTO files (
                device_id,
                current_path,
                original_path,
                size_bytes,
                hash_md5,
                hash_sha256,
                permissions,
                owner_name,
                group_name
            ) VALUES (
                device_id,
                event_record->>'file_path',
                event_record->>'file_original_path',
                NULLIF(event_record->>'file_size', '')::BIGINT,
                event_record->>'file_hash_md5',
                event_record->>'file_hash_sha256',
                event_record->>'file_permissions',
                event_record->>'file_owner',
                event_record->>'file_group'
            )
            ON CONFLICT (device_id, current_path) 
            DO UPDATE SET
                size_bytes = EXCLUDED.size_bytes,
                hash_md5 = EXCLUDED.hash_md5,
                hash_sha256 = EXCLUDED.hash_sha256,
                permissions = EXCLUDED.permissions,
                owner_name = EXCLUDED.owner_name,
                group_name = EXCLUDED.group_name,
                updated_at = CURRENT_TIMESTAMP
            RETURNING id INTO file_id;
            
            -- Insert file event
            INSERT INTO file_events (
                organization_id,
                device_id,
                user_id,
                process_id,
                file_id,
                action,
                source_path,
                destination_path,
                occurred_at,
                session_id,
                ip_address,
                user_agent,
                success,
                error_message,
                details
            ) VALUES (
                org_id,
                device_id,
                user_id,
                process_id,
                file_id,
                (event_record->>'action')::file_action,
                event_record->>'source_path',
                event_record->>'destination_path',
                (event_record->>'occurred_at')::TIMESTAMP WITH TIME ZONE,
                event_record->>'session_id',
                NULLIF(event_record->>'ip_address', '')::INET,
                event_record->>'user_agent',
                COALESCE((event_record->>'success')::BOOLEAN, TRUE),
                event_record->>'error_message',
                COALESCE(event_record->'details', '{}'::JSONB)
            );
            
            success := success + 1;
            
            -- Release the savepoint
            RELEASE SAVEPOINT event_processing;
            
        EXCEPTION WHEN OTHERS THEN
            -- Rollback to savepoint and log error
            ROLLBACK TO SAVEPOINT event_processing;
            error := error + 1;
            
            GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
            error_list := error_list || jsonb_build_object(
                'event_index', processed - 1,
                'error', error_msg,
                'event_data', event_record
            );
        END;
    END LOOP;
    
    -- Return results
    RETURN QUERY SELECT processed, success, error, error_list;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- USER MANAGEMENT PROCEDURES
-- =====================================================

-- Procedure to create user with role assignment
CREATE OR REPLACE FUNCTION create_user_with_role(
    p_organization_id UUID,
    p_username VARCHAR(50),
    p_email VARCHAR(255),
    p_password VARCHAR(255),
    p_first_name VARCHAR(100),
    p_last_name VARCHAR(100),
    p_role_name VARCHAR(50),
    p_created_by UUID DEFAULT NULL
)
RETURNS TABLE (
    user_id UUID,
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    new_user_id UUID;
    role_id INTEGER;
    error_msg TEXT;
BEGIN
    BEGIN
        -- Check if role exists
        SELECT id INTO role_id FROM roles WHERE name = p_role_name;
        IF role_id IS NULL THEN
            RETURN QUERY SELECT NULL::UUID, FALSE, 'Role not found: ' || p_role_name;
            RETURN;
        END IF;
        
        -- Create user
        INSERT INTO users (
            organization_id,
            username,
            email,
            password_hash,
            first_name,
            last_name,
            created_by
        ) VALUES (
            p_organization_id,
            p_username,
            p_email,
            p_password, -- Will be hashed by trigger
            p_first_name,
            p_last_name,
            p_created_by
        ) RETURNING id INTO new_user_id;
        
        -- Assign role
        INSERT INTO user_roles (user_id, role_id, assigned_by)
        VALUES (new_user_id, role_id, p_created_by);
        
        RETURN QUERY SELECT new_user_id, TRUE, 'User created successfully';
        
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
        RETURN QUERY SELECT NULL::UUID, FALSE, error_msg;
    END;
END;
$$ LANGUAGE plpgsql;

-- Procedure to authenticate user
CREATE OR REPLACE FUNCTION authenticate_user(
    p_username VARCHAR(50),
    p_password VARCHAR(255),
    p_organization_name VARCHAR(255),
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS TABLE (
    user_id UUID,
    session_token TEXT,
    expires_at TIMESTAMP WITH TIME ZONE,
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    user_record RECORD;
    org_id UUID;
    new_session_id UUID;
    token TEXT;
    expiry TIMESTAMP WITH TIME ZONE;
    error_msg TEXT;
BEGIN
    BEGIN
        -- Get organization
        SELECT id INTO org_id FROM organizations WHERE name = p_organization_name;
        IF org_id IS NULL THEN
            RETURN QUERY SELECT NULL::UUID, NULL::TEXT, NULL::TIMESTAMP WITH TIME ZONE, FALSE, 'Organization not found';
            RETURN;
        END IF;
        
        -- Get user and verify password
        SELECT * INTO user_record FROM users 
        WHERE organization_id = org_id 
        AND username = p_username 
        AND status = 'ACTIVE'
        AND (locked_until IS NULL OR locked_until < CURRENT_TIMESTAMP);
        
        IF user_record IS NULL THEN
            RETURN QUERY SELECT NULL::UUID, NULL::TEXT, NULL::TIMESTAMP WITH TIME ZONE, FALSE, 'Invalid credentials or account locked';
            RETURN;
        END IF;
        
        -- Verify password
        IF NOT (user_record.password_hash = crypt(p_password, user_record.password_hash)) THEN
            -- Increment failed login attempts
            UPDATE users 
            SET failed_login_attempts = failed_login_attempts + 1,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = user_record.id;
            
            RETURN QUERY SELECT NULL::UUID, NULL::TEXT, NULL::TIMESTAMP WITH TIME ZONE, FALSE, 'Invalid credentials';
            RETURN;
        END IF;
        
        -- Generate session token
        token := generate_secure_token(32);
        expiry := CURRENT_TIMESTAMP + INTERVAL '24 hours';
        
        -- Create session
        INSERT INTO sessions (user_id, token_hash, ip_address, user_agent, expires_at)
        VALUES (user_record.id, token, p_ip_address, p_user_agent, expiry)
        RETURNING id INTO new_session_id;
        
        -- Update user login info
        UPDATE users 
        SET last_login_at = CURRENT_TIMESTAMP,
            failed_login_attempts = 0,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = user_record.id;
        
        RETURN QUERY SELECT user_record.id, token, expiry, TRUE, 'Authentication successful';
        
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_msg = MESSAGE_TEXT;
        RETURN QUERY SELECT NULL::UUID, NULL::TEXT, NULL::TIMESTAMP WITH TIME ZONE, FALSE, error_msg;
    END;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- ANALYTICS AND REPORTING PROCEDURES
-- =====================================================

-- Function to get user activity summary
CREATE OR REPLACE FUNCTION get_user_activity_summary(
    p_organization_id UUID,
    p_start_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP - INTERVAL '30 days',
    p_end_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
    user_id UUID,
    username VARCHAR(50),
    full_name TEXT,
    department VARCHAR(100),
    total_events BIGINT,
    files_created BIGINT,
    files_modified BIGINT,
    files_deleted BIGINT,
    failed_operations BIGINT,
    unique_devices BIGINT,
    last_activity TIMESTAMP WITH TIME ZONE,
    risk_score NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.username,
        u.first_name || ' ' || u.last_name,
        u.department,
        COUNT(fe.id) AS total_events,
        COUNT(CASE WHEN fe.action = 'CREATE' THEN 1 END) AS files_created,
        COUNT(CASE WHEN fe.action = 'WRITE' THEN 1 END) AS files_modified,
        COUNT(CASE WHEN fe.action = 'DELETE' THEN 1 END) AS files_deleted,
        COUNT(CASE WHEN fe.success = FALSE THEN 1 END) AS failed_operations,
        COUNT(DISTINCT fe.device_id) AS unique_devices,
        MAX(fe.occurred_at) AS last_activity,
        -- Calculate risk score based on activity patterns
        ROUND(
            (COUNT(CASE WHEN fe.action = 'DELETE' THEN 1 END) * 3.0 +
             COUNT(CASE WHEN fe.success = FALSE THEN 1 END) * 2.0 +
             COUNT(CASE WHEN EXTRACT(hour FROM fe.occurred_at) NOT BETWEEN 9 AND 17 THEN 1 END) * 1.5) /
            GREATEST(COUNT(fe.id), 1) * 100, 2
        ) AS risk_score
    FROM users u
    LEFT JOIN file_events fe ON u.id = fe.user_id 
        AND fe.occurred_at BETWEEN p_start_date AND p_end_date
    WHERE u.organization_id = p_organization_id
        AND u.status = 'ACTIVE'
    GROUP BY u.id, u.username, u.first_name, u.last_name, u.department
    ORDER BY total_events DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to get file access patterns
CREATE OR REPLACE FUNCTION get_file_access_patterns(
    p_organization_id UUID,
    p_start_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP - INTERVAL '7 days',
    p_end_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    file_path TEXT,
    file_extension VARCHAR(20),
    access_count BIGINT,
    unique_users BIGINT,
    unique_devices BIGINT,
    read_count BIGINT,
    write_count BIGINT,
    delete_count BIGINT,
    first_access TIMESTAMP WITH TIME ZONE,
    last_access TIMESTAMP WITH TIME ZONE,
    avg_file_size NUMERIC,
    risk_level TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.current_path,
        f.extension,
        COUNT(fe.id) AS access_count,
        COUNT(DISTINCT fe.user_id) AS unique_users,
        COUNT(DISTINCT fe.device_id) AS unique_devices,
        COUNT(CASE WHEN fe.action = 'READ' THEN 1 END) AS read_count,
        COUNT(CASE WHEN fe.action = 'WRITE' THEN 1 END) AS write_count,
        COUNT(CASE WHEN fe.action = 'DELETE' THEN 1 END) AS delete_count,
        MIN(fe.occurred_at) AS first_access,
        MAX(fe.occurred_at) AS last_access,
        ROUND(AVG(f.size_bytes), 2) AS avg_file_size,
        CASE 
            WHEN COUNT(CASE WHEN fe.action = 'DELETE' THEN 1 END) > 0 THEN 'HIGH'
            WHEN COUNT(DISTINCT fe.user_id) > 5 THEN 'MEDIUM'
            WHEN COUNT(fe.id) > 100 THEN 'MEDIUM'
            ELSE 'LOW'
        END AS risk_level
    FROM files f
    JOIN file_events fe ON f.id = fe.file_id
    WHERE fe.organization_id = p_organization_id
        AND fe.occurred_at BETWEEN p_start_date AND p_end_date
    GROUP BY f.id, f.current_path, f.extension
    HAVING COUNT(fe.id) > 1  -- Only files with multiple accesses
    ORDER BY access_count DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to detect anomalous behavior
CREATE OR REPLACE FUNCTION detect_anomalous_behavior(
    p_organization_id UUID,
    p_lookback_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    anomaly_type TEXT,
    user_id UUID,
    username VARCHAR(50),
    device_id UUID,
    hostname VARCHAR(255),
    event_count BIGINT,
    anomaly_score NUMERIC,
    details JSONB
) AS $$
BEGIN
    -- Unusual file deletion activity
    RETURN QUERY
    SELECT 
        'EXCESSIVE_DELETIONS'::TEXT,
        u.id,
        u.username,
        d.id,
        d.hostname,
        COUNT(fe.id),
        ROUND((COUNT(fe.id)::NUMERIC / GREATEST(p_lookback_hours::NUMERIC / 24, 1)) * 10, 2),
        jsonb_build_object(
            'deleted_files', COUNT(fe.id),
            'time_period_hours', p_lookback_hours,
            'threshold_exceeded', COUNT(fe.id) > 50
        )
    FROM file_events fe
    JOIN users u ON fe.user_id = u.id
    JOIN devices d ON fe.device_id = d.id
    WHERE fe.organization_id = p_organization_id
        AND fe.occurred_at >= CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL
        AND fe.action = 'DELETE'
    GROUP BY u.id, u.username, d.id, d.hostname
    HAVING COUNT(fe.id) > 50  -- Threshold for excessive deletions
    
    UNION ALL
    
    -- Off-hours activity
    SELECT 
        'OFF_HOURS_ACTIVITY'::TEXT,
        u.id,
        u.username,
        d.id,
        d.hostname,
        COUNT(fe.id),
        ROUND((COUNT(fe.id)::NUMERIC / GREATEST(p_lookback_hours::NUMERIC / 24, 1)) * 5, 2),
        jsonb_build_object(
            'off_hours_events', COUNT(fe.id),
            'time_period_hours', p_lookback_hours,
            'weekend_activity', COUNT(CASE WHEN EXTRACT(dow FROM fe.occurred_at) IN (0, 6) THEN 1 END)
        )
    FROM file_events fe
    JOIN users u ON fe.user_id = u.id
    JOIN devices d ON fe.device_id = d.id
    WHERE fe.organization_id = p_organization_id
        AND fe.occurred_at >= CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL
        AND (EXTRACT(hour FROM fe.occurred_at) NOT BETWEEN 9 AND 17
             OR EXTRACT(dow FROM fe.occurred_at) IN (0, 6))
    GROUP BY u.id, u.username, d.id, d.hostname
    HAVING COUNT(fe.id) > 20  -- Threshold for off-hours activity
    
    UNION ALL
    
    -- Failed operation patterns
    SELECT 
        'EXCESSIVE_FAILURES'::TEXT,
        u.id,
        u.username,
        d.id,
        d.hostname,
        COUNT(fe.id),
        ROUND((COUNT(fe.id)::NUMERIC / GREATEST(p_lookback_hours::NUMERIC / 24, 1)) * 15, 2),
        jsonb_build_object(
            'failed_operations', COUNT(fe.id),
            'time_period_hours', p_lookback_hours,
            'failure_rate', ROUND(COUNT(fe.id)::NUMERIC / COUNT(*) * 100, 2)
        )
    FROM file_events fe
    JOIN users u ON fe.user_id = u.id
    JOIN devices d ON fe.device_id = d.id
    WHERE fe.organization_id = p_organization_id
        AND fe.occurred_at >= CURRENT_TIMESTAMP - (p_lookback_hours || ' hours')::INTERVAL
        AND fe.success = FALSE
    GROUP BY u.id, u.username, d.id, d.hostname
    HAVING COUNT(fe.id) > 10  -- Threshold for failed operations
    
    ORDER BY anomaly_score DESC;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- MAINTENANCE AND OPTIMIZATION PROCEDURES
-- =====================================================

-- Procedure to optimize database performance
CREATE OR REPLACE FUNCTION optimize_database_performance()
RETURNS TABLE (
    operation TEXT,
    status TEXT,
    details TEXT
) AS $$
DECLARE
    table_name TEXT;
    index_name TEXT;
BEGIN
    -- Update table statistics
    FOR table_name IN 
        SELECT t.table_name 
        FROM information_schema.tables t 
        WHERE t.table_schema = 'public' 
        AND t.table_type = 'BASE TABLE'
    LOOP
        BEGIN
            EXECUTE 'ANALYZE ' || quote_ident(table_name);
            RETURN QUERY SELECT 'ANALYZE', 'SUCCESS', 'Updated statistics for ' || table_name;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT 'ANALYZE', 'ERROR', 'Failed to analyze ' || table_name || ': ' || SQLERRM;
        END;
    END LOOP;
    
    -- Reindex heavily used indexes
    FOR index_name IN 
        SELECT indexname 
        FROM pg_indexes 
        WHERE schemaname = 'public' 
        AND indexname LIKE 'idx_file_events%'
    LOOP
        BEGIN
            EXECUTE 'REINDEX INDEX CONCURRENTLY ' || quote_ident(index_name);
            RETURN QUERY SELECT 'REINDEX', 'SUCCESS', 'Reindexed ' || index_name;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT 'REINDEX', 'ERROR', 'Failed to reindex ' || index_name || ': ' || SQLERRM;
        END;
    END LOOP;
    
    -- Refresh materialized views
    BEGIN
        PERFORM refresh_all_materialized_views();
        RETURN QUERY SELECT 'REFRESH_VIEWS', 'SUCCESS', 'All materialized views refreshed';
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'REFRESH_VIEWS', 'ERROR', 'Failed to refresh views: ' || SQLERRM;
    END;
    
    -- Cleanup expired sessions
    BEGIN
        PERFORM cleanup_expired_sessions();
        RETURN QUERY SELECT 'CLEANUP_SESSIONS', 'SUCCESS', 'Expired sessions cleaned up';
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT 'CLEANUP_SESSIONS', 'ERROR', 'Failed to cleanup sessions: ' || SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;

-- Function to get database health metrics
CREATE OR REPLACE FUNCTION get_database_health_metrics()
RETURNS TABLE (
    metric_name TEXT,
    metric_value TEXT,
    status TEXT,
    recommendation TEXT
) AS $$
DECLARE
    db_size BIGINT;
    connection_count INTEGER;
    slow_query_count INTEGER;
    index_usage NUMERIC;
BEGIN
    -- Database size
    SELECT pg_database_size(current_database()) INTO db_size;
    RETURN QUERY SELECT 
        'database_size'::TEXT,
        pg_size_pretty(db_size),
        CASE WHEN db_size > 10737418240 THEN 'WARNING' ELSE 'OK' END,
        CASE WHEN db_size > 10737418240 THEN 'Consider archiving old data' ELSE 'Database size is healthy' END;
    
    -- Active connections
    SELECT count(*) INTO connection_count FROM pg_stat_activity WHERE state = 'active';
    RETURN QUERY SELECT 
        'active_connections'::TEXT,
        connection_count::TEXT,
        CASE WHEN connection_count > 50 THEN 'WARNING' ELSE 'OK' END,
        CASE WHEN connection_count > 50 THEN 'Monitor connection pooling' ELSE 'Connection count is normal' END;
    
    -- Index usage efficiency
    SELECT ROUND(AVG(
        CASE WHEN idx_tup_read + seq_tup_read = 0 THEN 0
        ELSE idx_tup_read::NUMERIC / (idx_tup_read + seq_tup_read) * 100 END
    ), 2) INTO index_usage
    FROM pg_stat_user_tables;
    
    RETURN QUERY SELECT 
        'index_usage_ratio'::TEXT,
        index_usage::TEXT || '%',
        CASE WHEN index_usage < 80 THEN 'WARNING' ELSE 'OK' END,
        CASE WHEN index_usage < 80 THEN 'Review and add missing indexes' ELSE 'Index usage is efficient' END;
    
    -- Table bloat check (simplified)
    RETURN QUERY
    SELECT 
        'table_bloat'::TEXT,
        'Checking...'::TEXT,
        'INFO'::TEXT,
        'Run VACUUM ANALYZE regularly'::TEXT;
END;
$$ LANGUAGE plpgsql;
