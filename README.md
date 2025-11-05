# TrackVault - File Activity Monitoring System

A real-time file activity monitoring and security dashboard that tracks file system changes, detects suspicious activities, and provides comprehensive security alerts.

## 🚀 Features

- **Real-Time File Monitoring**: Tracks file creation, modification, deletion, and movement operations
- **Risk Assessment**: Automatically categorizes activities based on risk levels (Low, Medium, High)
- **Security Alerts**: Generates alerts for high-risk file operations
- **User Authentication**: Secure login and signup system with role-based access
- **Interactive Dashboard**: Real-time statistics and activity visualization
- **Activity Logs**: Comprehensive logging of all file system activities
- **Alert Management**: Acknowledge, resolve, or dismiss security alerts
- **Process Tracking**: Identifies which processes and users performed file operations
- **Customizable Monitoring**: Configure watch paths and risk settings

## 🛠️ Tech Stack

### Backend
- **Python 3.x** - Core programming language
- **Flask 2.3.3** - Web framework
- **SQLite** - Database for storing activities and alerts
- **Watchdog 3.0.0** - File system monitoring
- **psutil 5.9.6** - Process and system information
- **pywin32 306** - Windows-specific functionality

### Frontend
- **HTML5/CSS3** - Structure and styling
- **JavaScript** - Interactive features and real-time updates
- **Bootstrap** - Responsive UI framework

## 📋 Prerequisites

- Python 3.8 or higher
- Windows OS (for pywin32 functionality)
- pip (Python package manager)

## 🔧 Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/trackvault.git
   cd trackvault/fresh-dashboard
   ```

2. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure monitoring paths** (Optional)
   
   Edit `monitor_config.json` to customize:
   - Watch paths
   - Excluded file extensions
   - Risk assessment settings
   - Sync intervals

## 🚀 Usage

### Option 1: Using Batch Files (Windows)

1. **Start the Monitor Service**
   ```bash
   start_monitor.bat
   ```

2. **Start the Web Interface** (in a new terminal)
   ```bash
   start_web.bat
   ```

### Option 2: Manual Start

1. **Start the Monitor Service**
   ```bash
   python monitor_service.py
   ```

2. **Start the Web Interface** (in a new terminal)
   ```bash
   python web_interface.py
   ```

3. **Access the Dashboard**
   
   Open your browser and navigate to: `http://localhost:8080`

### Default Login Credentials

- **Admin Account**
  - Username: `admin`
  - Password: `admin123`

- **Test User**
  - Username: `john.doe`
  - Password: `password`

## 📁 Project Structure

```
fresh-dashboard/
├── app.py                  # Main Flask application
├── file_monitor.py         # File monitoring core logic
├── monitor_service.py      # Background monitoring service
├── web_interface.py        # Web dashboard interface
├── monitor_config.json     # Configuration file
├── requirements.txt        # Python dependencies
├── start_monitor.bat       # Monitor service launcher
├── start_web.bat          # Web interface launcher
├── templates/             # HTML templates
│   ├── dashboard.html
│   ├── alerts.html
│   ├── logs.html
│   ├── login.html
│   └── ...
├── static/               # CSS and JavaScript files
│   ├── css/
│   └── js/
└── backend/             # Additional backend components
```

## 🔒 Security Features

- **Risk Level Assessment**: Automatic categorization of file operations
- **High-Risk Detection**: Monitors sensitive system paths and file types
- **Process Identification**: Tracks which applications perform file operations
- **Alert System**: Real-time notifications for suspicious activities
- **User Activity Tracking**: Logs username and timestamp for all operations

## 📊 Dashboard Features

- **Statistics Overview**: Total activities, authorized/unauthorized operations, alerts
- **Recent Activities**: Real-time feed of file system changes
- **Alert Management**: View, acknowledge, and resolve security alerts
- **Activity Logs**: Searchable and filterable activity history
- **User Management**: View and manage system users
- **Reports**: Generate activity and security reports

## ⚙️ Configuration

Edit `monitor_config.json` to customize:

```json
{
  "watch_paths": [
    "C:\\Users\\YourUsername\\Desktop",
    "C:\\Users\\YourUsername\\Documents"
  ],
  "excluded_extensions": [".tmp", ".log", ".pyc"],
  "risk_settings": {
    "high_risk_extensions": [".exe", ".dll", ".sys"],
    "high_risk_actions": ["DELETE", "MOVE"],
    "sensitive_paths": ["system32", "windows"]
  },
  "sync_interval": 3
}
```

## 🐛 Troubleshooting

**Issue**: Monitor service not detecting activities
- Ensure the watch paths exist and are accessible
- Check that the service is running in the background
- Verify database permissions

**Issue**: Web interface shows no data
- Confirm monitor service is running first
- Check that `monitor_data.db` exists
- Restart both services

**Issue**: Permission errors
- Run as administrator for system path monitoring
- Adjust watch paths to user-accessible directories

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 👥 Authors

- Isha Deshmukh

## 🙏 Acknowledgments

- Flask framework for the web interface
- Watchdog library for file system monitoring
- Bootstrap for UI components

## 📧 Contact

For questions or support, please open an issue on GitHub.

---

**Note**: This system is designed for monitoring authorized file systems. Always ensure you have proper permissions before monitoring any directories.
