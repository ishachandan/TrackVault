# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please email: deshmukhishac14@gmail.com

## Security Best Practices

### 1. Environment Variables

**Never commit sensitive data to the repository.** Use environment variables for:

- Secret keys
- Database passwords
- API tokens
- JWT secrets

### 2. Setup Instructions

1. Copy `.env.example` to `.env`:
   ```bash
   copy .env.example .env
   ```

2. Generate a secure secret key:
   ```python
   python -c "import secrets; print(secrets.token_hex(32))"
   ```

3. Update `.env` with your generated keys:
   ```
   SECRET_KEY=your-generated-secret-key-here
   POSTGRES_PASSWORD=your-secure-database-password
   JWT_SECRET=your-jwt-secret-key
   ```

### 3. Default Credentials

**Change these immediately in production:**

- Admin username: `admin`
- Admin password: `admin123`

### 4. File Monitoring Permissions

- Only monitor directories you have permission to access
- Avoid monitoring system directories without proper authorization
- Be cautious with sensitive file paths

### 5. Database Security

- Database files (`.db`) are excluded from git via `.gitignore`
- Never commit database files containing real data
- Use strong passwords for production databases

### 6. Production Deployment

Before deploying to production:

1. ✅ Change all default passwords
2. ✅ Set strong SECRET_KEY in environment
3. ✅ Use HTTPS for web interface
4. ✅ Restrict database access
5. ✅ Enable firewall rules
6. ✅ Regular security updates
7. ✅ Monitor access logs

## Security Features

- Risk-based activity assessment
- Real-time security alerts
- Process and user tracking
- Audit trail of all file operations
- Session-based authentication

## Known Security Considerations

1. **Windows-only**: Currently uses Windows-specific APIs (pywin32)
2. **Local deployment**: Designed for local/internal network use
3. **Basic authentication**: Uses session-based auth (consider adding 2FA for production)

## Updates

This project is actively maintained. Security updates will be released as needed.

Last updated: November 5, 2024
