"""
TRACKVAULT FastAPI Backend
Advanced file activity monitoring system with comprehensive DBMS features
"""

from fastapi import FastAPI, Depends, HTTPException, status, BackgroundTasks, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
import asyncpg
import asyncio
import redis.asyncio as redis
import bcrypt
import jwt
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, EmailStr, validator
import logging
import os
from contextlib import asynccontextmanager
import json

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('trackvault.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuration
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://trackvault:password@localhost:5432/trackvault")
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
JWT_SECRET = os.getenv("JWT_SECRET", "your-super-secret-jwt-key-change-this")
JWT_ALGORITHM = "HS256"
JWT_EXPIRATION_HOURS = 24

# Global variables
db_pool: Optional[asyncpg.Pool] = None
redis_client: Optional[redis.Redis] = None

# =====================================================
# PYDANTIC MODELS
# =====================================================

class UserCreate(BaseModel):
    username: str
    email: EmailStr
    password: str
    first_name: str
    last_name: str
    department: Optional[str] = None
    role_name: str = "User"

class UserLogin(BaseModel):
    username: str
    password: str
    organization_name: str

class UserResponse(BaseModel):
    id: str
    username: str
    email: str
    first_name: str
    last_name: str
    department: Optional[str]
    status: str
    created_at: datetime
    last_login_at: Optional[datetime]

class DeviceCreate(BaseModel):
    hostname: str
    ip_address: Optional[str] = None
    mac_address: Optional[str] = None
    os_name: Optional[str] = None
    os_version: Optional[str] = None
    agent_version: Optional[str] = None
    device_type_name: str = "Desktop"

class FileEventCreate(BaseModel):
    hostname: str
    username: Optional[str] = None
    action: str
    file_path: str
    source_path: Optional[str] = None
    destination_path: Optional[str] = None
    occurred_at: datetime
    success: bool = True
    error_message: Optional[str] = None
    file_size: Optional[int] = None
    file_hash_md5: Optional[str] = None
    file_hash_sha256: Optional[str] = None
    process_pid: Optional[int] = None
    process_name: Optional[str] = None
    session_id: Optional[str] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    details: Optional[Dict[str, Any]] = {}

class FileEventBatch(BaseModel):
    organization_name: str
    events: List[FileEventCreate]

class AlertResponse(BaseModel):
    id: str
    title: str
    description: Optional[str]
    severity: str
    status: str
    risk_score: Optional[int]
    created_at: datetime
    file_event_id: Optional[str]
    policy_name: Optional[str]

class PolicyCreate(BaseModel):
    name: str
    description: Optional[str]
    rule_definition: Dict[str, Any]
    severity: str
    is_active: bool = True

class MetricsResponse(BaseModel):
    total_events: int
    total_alerts: int
    active_devices: int
    active_users: int
    events_last_24h: int
    alerts_last_24h: int

# =====================================================
# DATABASE CONNECTION MANAGEMENT
# =====================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan - startup and shutdown"""
    # Startup
    global db_pool, redis_client
    
    try:
        # Initialize database pool
        db_pool = await asyncpg.create_pool(
            DATABASE_URL,
            min_size=5,
            max_size=20,
            command_timeout=60
        )
        logger.info("Database pool created successfully")
        
        # Initialize Redis client
        redis_client = redis.from_url(REDIS_URL, decode_responses=True)
        await redis_client.ping()
        logger.info("Redis connection established")
        
        # Run database migrations if needed
        await run_migrations()
        
    except Exception as e:
        logger.error(f"Failed to initialize connections: {e}")
        raise
    
    yield
    
    # Shutdown
    if db_pool:
        await db_pool.close()
        logger.info("Database pool closed")
    
    if redis_client:
        await redis_client.close()
        logger.info("Redis connection closed")

async def run_migrations():
    """Run database migrations and setup"""
    try:
        async with db_pool.acquire() as conn:
            # Check if tables exist
            result = await conn.fetchval(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'"
            )
            
            if result == 0:
                logger.info("Running initial database setup...")
                # In production, use proper migration tools like Alembic
                # For now, we'll assume the schema is already created
                pass
                
    except Exception as e:
        logger.error(f"Migration error: {e}")
        raise

async def get_db_connection():
    """Get database connection from pool"""
    if not db_pool:
        raise HTTPException(status_code=500, detail="Database not available")
    
    async with db_pool.acquire() as connection:
        yield connection

# =====================================================
# AUTHENTICATION AND SECURITY
# =====================================================

security = HTTPBearer()

async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Validate JWT token and return current user"""
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = payload.get("sub")
        organization_id = payload.get("org_id")
        
        if not user_id or not organization_id:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        # Verify user exists and is active
        async with db_pool.acquire() as conn:
            user = await conn.fetchrow(
                """
                SELECT u.*, o.name as organization_name 
                FROM users u 
                JOIN organizations o ON u.organization_id = o.id 
                WHERE u.id = $1 AND u.status = 'ACTIVE'
                """,
                uuid.UUID(user_id)
            )
            
            if not user:
                raise HTTPException(status_code=401, detail="User not found or inactive")
            
            return dict(user)
            
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

async def verify_api_client(client_id: str, client_secret: str) -> Optional[Dict]:
    """Verify API client credentials"""
    try:
        async with db_pool.acquire() as conn:
            client = await conn.fetchrow(
                """
                SELECT ac.*, o.name as organization_name 
                FROM api_clients ac 
                JOIN organizations o ON ac.organization_id = o.id 
                WHERE ac.client_id = $1 AND ac.is_active = TRUE 
                AND (ac.expires_at IS NULL OR ac.expires_at > CURRENT_TIMESTAMP)
                """,
                client_id
            )
            
            if not client:
                return None
            
            # Verify client secret
            if bcrypt.checkpw(client_secret.encode(), client['client_secret_hash'].encode()):
                # Update last used timestamp
                await conn.execute(
                    "UPDATE api_clients SET last_used_at = CURRENT_TIMESTAMP WHERE id = $1",
                    client['id']
                )
                return dict(client)
            
            return None
            
    except Exception as e:
        logger.error(f"API client verification error: {e}")
        return None

# =====================================================
# FASTAPI APPLICATION
# =====================================================

app = FastAPI(
    title="TRACKVAULT API",
    description="Advanced File Activity Monitoring System",
    version="1.0.0",
    lifespan=lifespan
)

# Add middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:8080"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["localhost", "127.0.0.1", "*.trackvault.com"]
)

# =====================================================
# AUTHENTICATION ENDPOINTS
# =====================================================

@app.post("/auth/login")
async def login(user_login: UserLogin, request: Request):
    """Authenticate user and return JWT token"""
    try:
        async with db_pool.acquire() as conn:
            # Set session variables for audit logging
            await conn.execute("SET app.current_ip = $1", str(request.client.host))
            await conn.execute("SET app.current_user_agent = $1", request.headers.get("user-agent", ""))
            
            # Use stored procedure for authentication
            result = await conn.fetchrow(
                """
                SELECT * FROM authenticate_user($1, $2, $3, $4, $5)
                """,
                user_login.username,
                user_login.password,
                user_login.organization_name,
                request.client.host,
                request.headers.get("user-agent")
            )
            
            if not result['success']:
                raise HTTPException(status_code=401, detail=result['message'])
            
            # Create JWT token
            token_payload = {
                "sub": str(result['user_id']),
                "org_id": user_login.organization_name,
                "exp": datetime.utcnow() + timedelta(hours=JWT_EXPIRATION_HOURS),
                "iat": datetime.utcnow()
            }
            
            token = jwt.encode(token_payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
            
            return {
                "access_token": token,
                "token_type": "bearer",
                "expires_in": JWT_EXPIRATION_HOURS * 3600,
                "user_id": str(result['user_id'])
            }
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Login error: {e}")
        raise HTTPException(status_code=500, detail="Authentication failed")

@app.post("/auth/register")
async def register(user_create: UserCreate, current_user: dict = Depends(get_current_user)):
    """Register a new user (admin only)"""
    try:
        async with db_pool.acquire() as conn:
            # Set session variables for audit logging
            await conn.execute("SET app.current_user_id = $1", str(current_user['id']))
            
            # Use stored procedure to create user with role
            result = await conn.fetchrow(
                """
                SELECT * FROM create_user_with_role($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                current_user['organization_id'],
                user_create.username,
                user_create.email,
                user_create.password,
                user_create.first_name,
                user_create.last_name,
                user_create.role_name,
                current_user['id']
            )
            
            if not result['success']:
                raise HTTPException(status_code=400, detail=result['message'])
            
            return {"user_id": str(result['user_id']), "message": result['message']}
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Registration error: {e}")
        raise HTTPException(status_code=500, detail="Registration failed")

# =====================================================
# EVENT INGESTION ENDPOINTS
# =====================================================

@app.post("/api/v1/events/batch")
async def ingest_events_batch(
    batch: FileEventBatch,
    background_tasks: BackgroundTasks,
    request: Request
):
    """Bulk ingest file events with authentication"""
    
    # Verify API client credentials from headers
    client_id = request.headers.get("X-Client-ID")
    client_secret = request.headers.get("X-Client-Secret")
    
    if not client_id or not client_secret:
        raise HTTPException(status_code=401, detail="Missing API credentials")
    
    client = await verify_api_client(client_id, client_secret)
    if not client:
        raise HTTPException(status_code=401, detail="Invalid API credentials")
    
    try:
        # Convert events to JSON for stored procedure
        events_json = [event.dict() for event in batch.events]
        
        async with db_pool.acquire() as conn:
            # Set session variables for audit logging
            await conn.execute("SET app.current_user_id = $1", str(client['id']))
            await conn.execute("SET app.current_ip = $1", str(request.client.host))
            
            # Use stored procedure for bulk ingestion
            result = await conn.fetchrow(
                "SELECT * FROM ingest_events_batch($1)",
                json.dumps(events_json)
            )
            
            # Queue background processing for analytics
            background_tasks.add_task(
                process_events_analytics,
                batch.organization_name,
                len(batch.events)
            )
            
            return {
                "processed": result['processed_count'],
                "success": result['success_count'],
                "errors": result['error_count'],
                "error_details": result['errors'] if result['errors'] else []
            }
            
    except Exception as e:
        logger.error(f"Batch ingestion error: {e}")
        raise HTTPException(status_code=500, detail="Ingestion failed")

@app.post("/api/v1/events")
async def create_event(
    event: FileEventCreate,
    request: Request
):
    """Create single file event"""
    
    # For single events, we'll use the batch endpoint with one event
    batch = FileEventBatch(
        organization_name="TechCorp Inc",  # Default for demo
        events=[event]
    )
    
    return await ingest_events_batch(batch, BackgroundTasks(), request)

# =====================================================
# QUERY ENDPOINTS
# =====================================================

@app.get("/api/v1/events")
async def get_events(
    limit: int = 100,
    offset: int = 0,
    user_id: Optional[str] = None,
    device_id: Optional[str] = None,
    action: Optional[str] = None,
    since: Optional[datetime] = None,
    current_user: dict = Depends(get_current_user)
):
    """Get file events with filtering and pagination"""
    
    try:
        async with db_pool.acquire() as conn:
            query = """
                SELECT 
                    fe.id,
                    fe.action,
                    fe.source_path,
                    fe.destination_path,
                    fe.occurred_at,
                    fe.success,
                    fe.error_message,
                    u.username,
                    d.hostname,
                    f.filename,
                    f.size_bytes
                FROM file_events fe
                LEFT JOIN users u ON fe.user_id = u.id
                LEFT JOIN devices d ON fe.device_id = d.id
                LEFT JOIN files f ON fe.file_id = f.id
                WHERE fe.organization_id = $1
            """
            
            params = [current_user['organization_id']]
            param_count = 1
            
            if user_id:
                param_count += 1
                query += f" AND fe.user_id = ${param_count}"
                params.append(uuid.UUID(user_id))
            
            if device_id:
                param_count += 1
                query += f" AND fe.device_id = ${param_count}"
                params.append(uuid.UUID(device_id))
            
            if action:
                param_count += 1
                query += f" AND fe.action = ${param_count}"
                params.append(action)
            
            if since:
                param_count += 1
                query += f" AND fe.occurred_at >= ${param_count}"
                params.append(since)
            
            query += f" ORDER BY fe.occurred_at DESC LIMIT ${param_count + 1} OFFSET ${param_count + 2}"
            params.extend([limit, offset])
            
            events = await conn.fetch(query, *params)
            
            # Get total count for pagination
            count_query = query.split("ORDER BY")[0].replace("SELECT fe.id,fe.action,fe.source_path,fe.destination_path,fe.occurred_at,fe.success,fe.error_message,u.username,d.hostname,f.filename,f.size_bytes", "SELECT COUNT(*)")
            total_count = await conn.fetchval(count_query, *params[:-2])
            
            return {
                "events": [dict(event) for event in events],
                "total": total_count,
                "limit": limit,
                "offset": offset
            }
            
    except Exception as e:
        logger.error(f"Get events error: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve events")

@app.get("/api/v1/alerts")
async def get_alerts(
    limit: int = 50,
    offset: int = 0,
    severity: Optional[str] = None,
    status: Optional[str] = None,
    current_user: dict = Depends(get_current_user)
):
    """Get security alerts with filtering"""
    
    try:
        async with db_pool.acquire() as conn:
            query = """
                SELECT * FROM alert_summary_view
                WHERE organization_id = $1
            """
            
            params = [current_user['organization_id']]
            param_count = 1
            
            if severity:
                param_count += 1
                query += f" AND severity = ${param_count}"
                params.append(severity)
            
            if status:
                param_count += 1
                query += f" AND status = ${param_count}"
                params.append(status)
            
            query += f" ORDER BY created_at DESC LIMIT ${param_count + 1} OFFSET ${param_count + 2}"
            params.extend([limit, offset])
            
            alerts = await conn.fetch(query, *params)
            
            return {
                "alerts": [dict(alert) for alert in alerts],
                "limit": limit,
                "offset": offset
            }
            
    except Exception as e:
        logger.error(f"Get alerts error: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve alerts")

@app.get("/api/v1/metrics")
async def get_metrics(current_user: dict = Depends(get_current_user)):
    """Get system metrics and statistics"""
    
    try:
        async with db_pool.acquire() as conn:
            # Get basic counts
            metrics = await conn.fetchrow("""
                SELECT 
                    (SELECT COUNT(*) FROM file_events WHERE organization_id = $1) as total_events,
                    (SELECT COUNT(*) FROM alerts WHERE organization_id = $1) as total_alerts,
                    (SELECT COUNT(*) FROM devices WHERE organization_id = $1 AND status = 'ACTIVE') as active_devices,
                    (SELECT COUNT(*) FROM users WHERE organization_id = $1 AND status = 'ACTIVE') as active_users,
                    (SELECT COUNT(*) FROM file_events WHERE organization_id = $1 AND occurred_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours') as events_last_24h,
                    (SELECT COUNT(*) FROM alerts WHERE organization_id = $1 AND created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours') as alerts_last_24h
            """, current_user['organization_id'])
            
            return dict(metrics)
            
    except Exception as e:
        logger.error(f"Get metrics error: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve metrics")

# =====================================================
# USER MANAGEMENT ENDPOINTS
# =====================================================

@app.get("/api/v1/users")
async def get_users(
    limit: int = 50,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """Get users in organization"""
    
    try:
        async with db_pool.acquire() as conn:
            users = await conn.fetch("""
                SELECT 
                    u.id,
                    u.username,
                    u.email,
                    u.first_name,
                    u.last_name,
                    u.department,
                    u.status,
                    u.created_at,
                    u.last_login_at,
                    array_agg(r.name) as roles
                FROM users u
                LEFT JOIN user_roles ur ON u.id = ur.user_id AND ur.is_active = TRUE
                LEFT JOIN roles r ON ur.role_id = r.id
                WHERE u.organization_id = $1
                GROUP BY u.id, u.username, u.email, u.first_name, u.last_name, u.department, u.status, u.created_at, u.last_login_at
                ORDER BY u.created_at DESC
                LIMIT $2 OFFSET $3
            """, current_user['organization_id'], limit, offset)
            
            return {"users": [dict(user) for user in users]}
            
    except Exception as e:
        logger.error(f"Get users error: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve users")

# =====================================================
# ANALYTICS ENDPOINTS
# =====================================================

@app.get("/api/v1/analytics/user-activity")
async def get_user_activity_summary(
    days: int = 30,
    current_user: dict = Depends(get_current_user)
):
    """Get user activity analytics"""
    
    try:
        async with db_pool.acquire() as conn:
            start_date = datetime.now(timezone.utc) - timedelta(days=days)
            
            activity = await conn.fetch("""
                SELECT * FROM get_user_activity_summary($1, $2, $3, $4)
            """, 
            current_user['organization_id'],
            start_date,
            datetime.now(timezone.utc),
            100
            )
            
            return {"user_activity": [dict(row) for row in activity]}
            
    except Exception as e:
        logger.error(f"Get user activity error: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve user activity")

@app.get("/api/v1/analytics/anomalies")
async def get_anomalies(
    hours: int = 24,
    current_user: dict = Depends(get_current_user)
):
    """Detect anomalous behavior"""
    
    try:
        async with db_pool.acquire() as conn:
            anomalies = await conn.fetch("""
                SELECT * FROM detect_anomalous_behavior($1, $2)
            """, current_user['organization_id'], hours)
            
            return {"anomalies": [dict(row) for row in anomalies]}
            
    except Exception as e:
        logger.error(f"Get anomalies error: {e}")
        raise HTTPException(status_code=500, detail="Failed to detect anomalies")

# =====================================================
# BACKGROUND TASKS
# =====================================================

async def process_events_analytics(organization_name: str, event_count: int):
    """Background task to process event analytics"""
    try:
        # Update Redis cache with recent activity
        if redis_client:
            await redis_client.incr(f"events:count:{organization_name}", event_count)
            await redis_client.expire(f"events:count:{organization_name}", 3600)
        
        # Refresh materialized views if significant activity
        if event_count > 100:
            async with db_pool.acquire() as conn:
                await conn.execute("SELECT refresh_materialized_views_if_stale()")
        
        logger.info(f"Processed analytics for {event_count} events from {organization_name}")
        
    except Exception as e:
        logger.error(f"Analytics processing error: {e}")

# =====================================================
# HEALTH AND MONITORING ENDPOINTS
# =====================================================

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Check database
        async with db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        
        # Check Redis
        if redis_client:
            await redis_client.ping()
        
        return {
            "status": "healthy",
            "timestamp": datetime.utcnow(),
            "version": "1.0.0"
        }
        
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": str(e),
                "timestamp": datetime.utcnow()
            }
        )

@app.get("/metrics/prometheus")
async def prometheus_metrics():
    """Prometheus metrics endpoint"""
    try:
        async with db_pool.acquire() as conn:
            stats = await conn.fetch("SELECT * FROM get_table_statistics()")
            
            metrics = []
            for stat in stats:
                metrics.append(f"trackvault_table_rows{{table=\"{stat['table_name']}\"}} {stat['row_count']}")
            
            return "\n".join(metrics)
            
    except Exception as e:
        logger.error(f"Metrics error: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve metrics")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
