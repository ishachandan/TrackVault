from flask import Flask, render_template, request, redirect, url_for, session, jsonify
from datetime import datetime, timedelta
import json
import random
import threading
import sqlite3
from file_monitor import FileMonitorService

app = Flask(__name__)
app.secret_key = 'your-secret-key-change-this'

# Initialize file monitor service
file_monitor = FileMonitorService([
    "C:\\Users\\Chandan Deshmukh\\OneDrive\\Desktop",
    "C:\\Users\\Chandan Deshmukh\\Documents"
])

# Start monitoring in background thread
def start_file_monitoring():
    file_monitor.start_monitoring()

monitor_thread = threading.Thread(target=start_file_monitoring, daemon=True)
monitor_thread.start()

# Sample users data
SAMPLE_USERS = [
    {'id': 1, 'username': 'admin', 'password': 'admin123', 'role': 'Admin', 'name': 'Administrator', 'email': 'admin@company.com', 'institute': 'System'},
    {'id': 2, 'username': 'john.doe', 'password': 'password', 'role': 'Staff', 'name': 'John Doe', 'email': 'john.doe@company.com', 'institute': 'IT Department'},
    {'id': 3, 'username': 'jane.smith', 'password': 'password', 'role': 'Researcher', 'name': 'Jane Smith', 'email': 'jane.smith@company.com', 'institute': 'Research Lab'},
]

def get_real_activities():
    """Get real activities from database"""
    try:
        # Direct database query to get more activities
        import sqlite3
        conn = sqlite3.connect('file_activity.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM file_activities 
            ORDER BY timestamp DESC 
            LIMIT 100
        ''')
        
        activities = cursor.fetchall()
        conn.close()
        
        formatted_activities = []
        for activity in activities:
            formatted_activity = {
                'id': activity[0],
                'timestamp': activity[1],
                'username': activity[2] or 'Unknown',
                'action': activity[5],  # action is at index 5
                'file_path': activity[6],  # file_path is at index 6
                'file_size': activity[7] or 0,  # file_size is at index 7
                'ip_address': activity[8] or 'N/A',  # ip_address is at index 8
                'status': activity[9] or 'Detected',  # status is at index 9
                'risk_level': activity[10] or 'Low'  # risk_level is at index 10
            }
            formatted_activities.append(formatted_activity)
            
        return formatted_activities
    except Exception as e:
        print(f"Error getting real activities: {e}")
        return []

def get_real_alerts():
    """Get real alerts from database"""
    try:
        # Direct database query instead of using file_monitor
        import sqlite3
        conn = sqlite3.connect('file_activity.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM alerts 
            ORDER BY timestamp DESC 
            LIMIT 20
        ''')
        
        alerts = cursor.fetchall()
        conn.close()
        
        formatted_alerts = []
        for alert in alerts:
            formatted_alert = {
                'id': alert[0],
                'timestamp': alert[1],
                'username': alert[2] or 'Unknown',
                'title': f"Security Alert #{alert[0]}",
                'description': alert[3],
                'file_path': alert[4],
                'risk_level': alert[5] or 'Medium',
                'status': alert[6] or 'New'
            }
            formatted_alerts.append(formatted_alert)
            
        return formatted_alerts
    except Exception as e:
        print(f"Error getting real alerts: {e}")
        return []


@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        
        user = next((u for u in SAMPLE_USERS if u['username'] == username and u['password'] == password), None)
        if user:
            session['username'] = username
            session['role'] = user['role']
            session['name'] = user['name']
            session['email'] = user['email']
            return redirect(url_for('dashboard'))
        else:
            return render_template('login.html', error='Invalid credentials')
    
    return render_template('login.html')

@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if request.method == 'POST':
        name = request.form['name']
        institute = request.form['institute']
        email = request.form['email']
        username = request.form['username']
        password = request.form['password']
        confirm_password = request.form['confirm_password']
        
        if password != confirm_password:
            return render_template('signup.html', error='Passwords do not match')
        
        if any(u['username'] == username for u in SAMPLE_USERS):
            return render_template('signup.html', error='Username already exists')
        
        if any(u['email'] == email for u in SAMPLE_USERS):
            return render_template('signup.html', error='Email already exists')
        
        new_user = {
            'id': len(SAMPLE_USERS) + 1,
            'username': username,
            'password': password,
            'role': 'Student',  # Default role
            'name': name,
            'email': email,
            'institute': institute
        }
        
        SAMPLE_USERS.append(new_user)
        
        session['username'] = username
        session['role'] = new_user['role']
        session['name'] = new_user['name']
        session['email'] = new_user['email']
        
        return redirect(url_for('dashboard'))
    
    return render_template('signup.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/')
def dashboard():
    # Get real file activities and alerts
    real_activities = get_real_activities()
    real_alerts = get_real_alerts()
    
    total_activities = len(real_activities) if real_activities else 0
    authorized = len([a for a in real_activities if a.get('status') == 'Detected']) if real_activities else 0
    unauthorized = len([a for a in real_activities if a.get('risk_level') == 'High']) if real_activities else 0
    high_risk_alerts = len([a for a in real_alerts if a.get('risk_level') == 'High']) if real_alerts else 0
    
    recent_activities = real_activities[:50]
    recent_alerts = real_alerts[:20] if real_alerts else []
    
    return render_template('dashboard.html', 
                         total_activities=total_activities,
                         authorized=authorized,
                         unauthorized=unauthorized,
                         high_risk_alerts=high_risk_alerts,
                         recent_activities=recent_activities,
                         recent_alerts=recent_alerts)

@app.route('/logs')
def logs():
    activities = get_real_activities()
    return render_template('logs.html', activities=activities)

@app.route('/alerts')
def alerts():
    if 'username' not in session:
        return redirect(url_for('login'))
    
    alerts = get_real_alerts()
    return render_template('alerts.html', alerts=alerts)

@app.route('/users')
def users():
    if 'username' not in session:
        return redirect(url_for('login'))
    
    return render_template('users.html', users=SAMPLE_USERS)

@app.route('/settings')
def settings():
    if 'username' not in session:
        return redirect(url_for('login'))
    
    return render_template('settings.html')

@app.route('/reports')
def reports():
    if 'username' not in session:
        return redirect(url_for('login'))
    
    return render_template('reports.html')

@app.route('/api/activities')
def api_activities():
    """API endpoint to get recent activities as JSON"""
    activities = get_real_activities()
    return jsonify(activities)

@app.route('/api/alerts')
def api_alerts():
    """API endpoint to get recent alerts as JSON"""
    alerts = get_real_alerts()
    return jsonify(alerts)

@app.route('/api/stats')
def api_stats():
    """API endpoint to get dashboard statistics"""
    
    real_activities = get_real_activities()
    real_alerts = get_real_alerts()
    
    stats = {
        'total_activities': len(real_activities) if real_activities else 0,
        'authorized': len([a for a in real_activities if a.get('status') == 'Detected']) if real_activities else 0,
        'unauthorized': len([a for a in real_activities if a.get('risk_level') == 'High']) if real_activities else 0,
        'high_risk_alerts': len([a for a in real_alerts if a.get('risk_level') == 'High']) if real_alerts else 0,
        'new_alerts': len([a for a in real_alerts if a.get('status') == 'New']) if real_alerts else 0
    }
    
    return jsonify(stats)



@app.route('/api/alert/<int:alert_id>/investigate', methods=['GET'])
def investigate_alert(alert_id):
    """Get investigation details for an alert"""
    if 'username' not in session:
        return jsonify({'error': 'Unauthorized'}), 401
    
    try:
        conn = sqlite3.connect(file_monitor.event_handler.db_path)
        cursor = conn.cursor()
        
        # Get alert details
        cursor.execute('SELECT * FROM alerts WHERE id = ?', (alert_id,))
        alert = cursor.fetchone()
        
        if not alert:
            return jsonify({'error': 'Alert not found'}), 404
        
        # Get related file activities
        cursor.execute('''
            SELECT * FROM file_activities 
            WHERE file_path = ? 
            ORDER BY timestamp DESC 
            LIMIT 10
        ''', (alert[4],))  # alert[4] is file_path
        
        activities = cursor.fetchall()
        conn.close()
        
        investigation_data = {
            'alert': {
                'id': alert[0],
                'timestamp': alert[1],
                'username': alert[2],
                'description': alert[3],
                'file_path': alert[4],
                'risk_level': alert[5],
                'status': alert[6]
            },
            'related_activities': [
                {
                    'id': act[0],
                    'timestamp': act[1],
                    'username': act[2],
                    'process_name': act[3],
                    'action': act[5],
                    'file_path': act[6],
                    'risk_level': act[10]
                } for act in activities
            ]
        }
        
        return jsonify(investigation_data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Alert action endpoints
@app.route('/api/alert/<int:alert_id>/acknowledge', methods=['POST'])
def acknowledge_alert(alert_id):
    try:
        import sqlite3
        conn = sqlite3.connect('file_activity.db')
        cursor = conn.cursor()
        cursor.execute('UPDATE alerts SET status = ? WHERE id = ?', ('Acknowledged', alert_id))
        conn.commit()
        conn.close()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/alert/<int:alert_id>/resolve', methods=['POST'])
def resolve_alert(alert_id):
    try:
        import sqlite3
        conn = sqlite3.connect('file_activity.db')
        cursor = conn.cursor()
        cursor.execute('UPDATE alerts SET status = ? WHERE id = ?', ('Resolved', alert_id))
        conn.commit()
        conn.close()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/alert/<int:alert_id>/dismiss', methods=['POST'])
def dismiss_alert(alert_id):
    try:
        import sqlite3
        conn = sqlite3.connect('file_activity.db')
        cursor = conn.cursor()
        cursor.execute('DELETE FROM alerts WHERE id = ?', (alert_id,))
        conn.commit()
        conn.close()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=8080)
