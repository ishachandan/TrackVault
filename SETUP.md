# TrackVault Setup Guide

## Quick Start Guide

### Step 1: Install Python
Ensure you have Python 3.8 or higher installed on your system.

Check your Python version:
```bash
python --version
```

### Step 2: Clone and Navigate
```bash
git clone https://github.com/yourusername/trackvault.git
cd trackvault/fresh-dashboard
```

### Step 3: Install Dependencies
```bash
pip install -r requirements.txt
```

### Step 4: Configure Monitoring Paths

Edit `monitor_config.json` and update the `watch_paths` with your desired directories:

```json
{
  "watch_paths": [
    "C:\\Users\\YourUsername\\Desktop",
    "C:\\Users\\YourUsername\\Documents"
  ]
}
```

Replace `YourUsername` with your actual Windows username.

### Step 5: Start the Application

**Option A: Using Batch Files (Recommended for Windows)**

1. Double-click `start_monitor.bat` to start the monitoring service
2. Double-click `start_web.bat` to start the web interface
3. Open browser to `http://localhost:8080`

**Option B: Manual Start**

Terminal 1 - Start Monitor Service:
```bash
python monitor_service.py
```

Terminal 2 - Start Web Interface:
```bash
python web_interface.py
```

Then open `http://localhost:8080` in your browser.

### Step 6: Login

Use the default credentials:
- Username: `admin`
- Password: `admin123`

## Architecture

The system consists of two main components:

1. **Monitor Service** (`monitor_service.py`)
   - Runs in the background
   - Monitors file system changes
   - Stores data in `monitor_data.db`
   - Lightweight and efficient

2. **Web Interface** (`web_interface.py`)
   - Provides the dashboard UI
   - Reads data from the monitor service database
   - Handles user authentication
   - Displays real-time updates

## Configuration Options

### monitor_config.json

```json
{
  "watch_paths": ["paths to monitor"],
  "excluded_extensions": ["file extensions to ignore"],
  "excluded_paths": ["directories to ignore"],
  "risk_settings": {
    "high_risk_extensions": ["dangerous file types"],
    "high_risk_actions": ["risky operations"],
    "sensitive_paths": ["protected directories"]
  },
  "sync_interval": 3,
  "max_buffer_size": 100
}
```

### Customization Tips

- **Watch Paths**: Add any directories you want to monitor
- **Excluded Extensions**: Add file types to ignore (e.g., `.tmp`, `.cache`)
- **Risk Settings**: Customize what's considered high-risk
- **Sync Interval**: How often to update status (in seconds)

## Troubleshooting

### Monitor Service Won't Start
- Check if Python is in your PATH
- Verify all dependencies are installed
- Run as administrator if monitoring system directories

### No Activities Showing
- Ensure monitor service is running first
- Check that watch paths exist and are accessible
- Try creating/modifying a file in a watched directory

### Database Errors
- Delete `monitor_data.db` and restart (will lose history)
- Check file permissions in the project directory

### Port Already in Use
- Change the port in `web_interface.py`:
  ```python
  app.run(host='0.0.0.0', port=8080, debug=True)
  ```

## Security Considerations

- Change default passwords immediately
- Don't monitor directories without proper authorization
- Be cautious when monitoring system directories
- Review alerts regularly
- Keep the application updated

## Performance Tips

- Limit watch paths to necessary directories
- Use excluded_paths to skip large directories (node_modules, etc.)
- Adjust sync_interval based on your needs
- Monitor the database size and clean old records periodically

## Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Check existing issues for solutions
- Submit pull requests for improvements

---

**Happy Monitoring! 🔒**
