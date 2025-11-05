@echo off
echo ========================================
echo   File Monitor Service Launcher
echo ========================================
echo.

echo Installing dependencies...
pip install -r requirements.txt

echo.
echo Starting Monitor Service...
echo Press Ctrl+C to stop monitoring
echo.

python monitor_service.py

pause
