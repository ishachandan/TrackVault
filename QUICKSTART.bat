@echo off
echo ========================================
echo   TrackVault - Quick Start
echo ========================================
echo.

echo Checking Python installation...
python --version
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8 or higher
    pause
    exit /b 1
)

echo.
echo Installing dependencies...
pip install -r requirements.txt
if errorlevel 1 (
    echo ERROR: Failed to install dependencies
    pause
    exit /b 1
)

echo.
echo ========================================
echo   Installation Complete!
echo ========================================
echo.
echo To start TrackVault:
echo   1. Run: start_monitor.bat
echo   2. Run: start_web.bat
echo   3. Open: http://localhost:8080
echo.
echo Default login:
echo   Username: admin
echo   Password: admin123
echo.
echo ========================================
pause
