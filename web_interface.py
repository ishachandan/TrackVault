"""
Clean Web Interface - Pure Dashboard
Reads data from monitor service via database
No monitoring logic - just displays data beautifully
"""

from flask import Flask, render_template, jsonify, request, session, redirect, url_for
import sqlite3
import json
from datetime import datetime, timedelta
import os

app = Flask(__name__)
app.secret_key = 'your-secret-key-change-this'

# Configuration
MONITOR_DB = "monitor_data.db"
WEB_PORT = 8080

class WebInterface:
    def __init__(self):
        self.monitor_db = MONITOR_DB
        
    def get_db_connection(self):
        """Get database connection to monitor service data"""
        if not os.path.exists(self.monitor_db):
            return None
        return sqlite3.connect(self.monitor_db)
    
    def get_service_status(self):
        """Get current monitor service status"""
        conn = self.get_db_connection()
        if not conn:
            return {"status": "Disconnected", "message": "Monitor service not running"}
            
        try:
            cursor = conn.cursor()
            cursor.execute('SELECT * FROM service_status WHERE id = 1')
            row = cursor.fetchone()
            
            if row:
                return {
                    "status": row[1],
                    "last_update": row[2],
                    "monitored_paths": json.loads(row[3]) if row[3] else [],
                    "total_activities": row[4],
                    "alerts_count": row[5]
                }
            else:
                return {"status": "Unknown", "message": "No status data available"}
        except Exception as e:
            return {"status": "Error", "message": str(e)}
        finally:
            conn.close()
    
    def get_recent_activities(self, limit=50):
        """Get recent file activities from monitor service"""
        conn = self.get_db_connection()
        if not conn:
            return []
            
        try:
            cursor = conn.cursor()
            cursor.execute('''
                SELECT * FROM file_activities 
                ORDER BY created_at DESC 
                LIMIT ?
            ''', (limit,))
            
            activities = []
            for row in cursor.fetchall():
                activities.append({
                    'id': row[0],
                    'timestamp': row[1],
                    'username': row[2],
                    'process_name': row[3],
                    'process_id': row[4],
                    'action': row[5],
                    'file_path': row[6],
                    'file_size': row[7],
                    'risk_level': row[8],
                    'status': row[9],
                    'created_at': row[10]
                })
            return activities
        except Exception as e:
            print(f"Error getting activities: {e}")
            return []
        finally:
            conn.close()
    
    def get_alerts(self, status_filter=None):
        """Get alerts from monitor service"""
        conn = self.get_db_connection()
        if not conn:
            return []
            
        try:
            cursor = conn.cursor()
            if status_filter:
                cursor.execute('''
                    SELECT * FROM alerts 
                    WHERE status = ?
                    ORDER BY created_at DESC
                ''', (status_filter,))
            else:
                cursor.execute('''
                    SELECT * FROM alerts 
                    ORDER BY created_at DESC
                ''')
            
            alerts = []
            for row in cursor.fetchall():
                alerts.append({
                    'id': row[0],
                    'timestamp': row[1],
                    'username': row[2],
                    'description': row[3],
                    'file_path': row[4],
                    'risk_level': row[5],
                    'status': row[6],
                    'created_at': row[7]
                })
            return alerts
        except Exception as e:
            print(f"Error getting alerts: {e}")
            return []
        finally:
            conn.close()
    
    def get_live_signals(self):
        """Get unprocessed live signals from monitor service"""
        conn = self.get_db_connection()
        if not conn:
            return []
            
        try:
            cursor = conn.cursor()
            cursor.execute('''
                SELECT * FROM live_signals 
                WHERE processed = FALSE 
                ORDER BY timestamp ASC
            ''')
            
            signals = []
            signal_ids = []
            
            for row in cursor.fetchall():
                signals.append({
                    'id': row[0],
                    'signal_type': row[1],
                    'data': json.loads(row[2]) if row[2] else None,
                    'timestamp': row[3]
                })
                signal_ids.append(row[0])
            
            # Mark signals as processed
            if signal_ids:
                placeholders = ','.join(['?' for _ in signal_ids])
                cursor.execute(f'''
                    UPDATE live_signals 
                    SET processed = TRUE 
                    WHERE id IN ({placeholders})
                ''', signal_ids)
                conn.commit()
            
            return signals
        except Exception as e:
            print(f"Error getting live signals: {e}")
            return []
        finally:
            conn.close()
    
    def get_statistics(self):
        """Get dashboard statistics"""
        conn = self.get_db_connection()
        if not conn:
            return {
                'total_activities': 0,
                'high_risk_activities': 0,
                'active_alerts': 0,
                'activities_today': 0
            }
            
        try:
            cursor = conn.cursor()
            
            # Total activities
            cursor.execute('SELECT COUNT(*) FROM file_activities')
            total_activities = cursor.fetchone()[0]
            
            # High risk activities
            cursor.execute('SELECT COUNT(*) FROM file_activities WHERE risk_level = "High"')
            high_risk_activities = cursor.fetchone()[0]
            
            # Active alerts
            cursor.execute('SELECT COUNT(*) FROM alerts WHERE status = "New"')
            active_alerts = cursor.fetchone()[0]
            
            # Activities today
            today = datetime.now().strftime('%Y-%m-%d')
            cursor.execute('SELECT COUNT(*) FROM file_activities WHERE DATE(created_at) = ?', (today,))
            activities_today = cursor.fetchone()[0]
            
            return {
                'total_activities': total_activities,
                'high_risk_activities': high_risk_activities,
                'active_alerts': active_alerts,
                'activities_today': activities_today
            }
        except Exception as e:
            print(f"Error getting statistics: {e}")
            return {
                'total_activities': 0,
                'high_risk_activities': 0,
                'active_alerts': 0,
                'activities_today': 0
            }
        finally:
            conn.close()

# Initialize web interface
web_interface = WebInterface()

# Routes
@app.route('/')
def index():
    return redirect(url_for('dashboard'))

@app.route('/dashboard')
def dashboard():
    service_status = web_interface.get_service_status()
    recent_activities = web_interface.get_recent_activities(10)
    statistics = web_interface.get_statistics()
    
    return render_template('dashboard.html', 
                         service_status=service_status,
                         recent_activities=recent_activities,
                         statistics=statistics)

@app.route('/logs')
def logs():
    activities = web_interface.get_recent_activities(100)
    return render_template('logs.html', activities=activities)

@app.route('/activities')
def activities():
    activities = web_interface.get_recent_activities(100)
    return render_template('logs.html', activities=activities)

@app.route('/alerts')
def alerts():
    alerts = web_interface.get_alerts()
    return render_template('alerts.html', alerts=alerts)

@app.route('/users')
def users():
    return render_template('users.html')

@app.route('/settings')
def settings():
    return render_template('settings.html')

@app.route('/reports')
def reports():
    return render_template('reports.html')

@app.route('/login')
def login():
    return render_template('login.html')

@app.route('/logout')
def logout():
    return redirect(url_for('login'))

@app.route('/signup')
def signup():
    return render_template('signup.html')

# API Routes for real-time updates
@app.route('/api/status')
def api_status():
    return jsonify(web_interface.get_service_status())

@app.route('/api/activities')
def api_activities():
    limit = request.args.get('limit', 50, type=int)
    return jsonify(web_interface.get_recent_activities(limit))

@app.route('/api/alerts')
def api_alerts():
    status_filter = request.args.get('status')
    return jsonify(web_interface.get_alerts(status_filter))

@app.route('/api/statistics')
def api_statistics():
    return jsonify(web_interface.get_statistics())

@app.route('/api/live-signals')
def api_live_signals():
    """Get real-time signals from monitor service"""
    return jsonify(web_interface.get_live_signals())

@app.route('/api/alert-action', methods=['POST'])
def api_alert_action():
    """Handle alert actions (acknowledge, resolve, etc.)"""
    data = request.get_json()
    alert_id = data.get('alert_id')
    action = data.get('action')
    
    conn = web_interface.get_db_connection()
    if not conn:
        return jsonify({'success': False, 'message': 'Monitor service not available'})
    
    try:
        cursor = conn.cursor()
        
        # Update alert status based on action
        status_map = {
            'acknowledge': 'Acknowledged',
            'resolve': 'Resolved',
            'dismiss': 'Dismissed',
            'investigate': 'Under Investigation'
        }
        
        new_status = status_map.get(action, 'New')
        
        cursor.execute('''
            UPDATE alerts 
            SET status = ? 
            WHERE id = ?
        ''', (new_status, alert_id))
        
        conn.commit()
        
        return jsonify({
            'success': True, 
            'message': f'Alert {action}d successfully',
            'new_status': new_status
        })
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)})
    finally:
        conn.close()

if __name__ == '__main__':
    print("File Monitor Web Interface")
    print("=" * 40)
    print(f"Dashboard: http://localhost:{WEB_PORT}")
    print("Pure interface - no monitoring logic")
    print("Reads data from monitor service")
    print("=" * 40)
    
    app.run(host='0.0.0.0', port=WEB_PORT, debug=True)
