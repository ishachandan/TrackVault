// Main JavaScript file for File Activity Logger Dashboard

// Global variables
let sidebarToggled = false;
let autoRefreshInterval = null;

// Initialize dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    initializeDashboard();
    setupEventListeners();
    startAutoRefresh();
    setCurrentDate();
});

function setCurrentDate() {
    const dateFilter = document.getElementById('dateFilter');
    if (dateFilter) {
        const today = new Date().toISOString().split('T')[0];
        dateFilter.value = today;
    }
}

function initializeDashboard() {
    // Initialize tooltips
    var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });

    // Initialize popovers
    var popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'));
    var popoverList = popoverTriggerList.map(function (popoverTriggerEl) {
        return new bootstrap.Popover(popoverTriggerEl);
    });

    // Add fade-in animation to cards
    const cards = document.querySelectorAll('.card, .summary-card');
    cards.forEach((card, index) => {
        card.style.animationDelay = `${index * 0.1}s`;
        card.classList.add('fade-in');
    });

    // Initialize live indicators
    animateLiveIndicators();
}

function setupEventListeners() {
    // Sidebar toggle for mobile
    const sidebarToggle = document.querySelector('.sidebar-toggle');
    if (sidebarToggle) {
        sidebarToggle.addEventListener('click', toggleSidebar);
    }

    // Close sidebar when clicking outside on mobile
    document.addEventListener('click', function(event) {
        const sidebar = document.querySelector('.sidebar');
        const sidebarToggle = document.querySelector('.sidebar-toggle');
        
        if (window.innerWidth <= 991.98 && 
            !sidebar.contains(event.target) && 
            !sidebarToggle.contains(event.target) &&
            sidebar.classList.contains('show')) {
            closeSidebar();
        }
    });

    // Handle window resize
    window.addEventListener('resize', handleResize);

    // Date filter change
    const dateFilter = document.getElementById('dateFilter');
    if (dateFilter) {
        dateFilter.addEventListener('change', handleDateFilterChange);
    }

    // Search functionality
    setupSearchHandlers();
    
    // Password strength indicator
    setupPasswordStrength();
}

function toggleSidebar() {
    const sidebar = document.querySelector('.sidebar');
    sidebar.classList.toggle('show');
    sidebarToggled = !sidebarToggled;
}

function closeSidebar() {
    const sidebar = document.querySelector('.sidebar');
    sidebar.classList.remove('show');
    sidebarToggled = false;
}

function handleResize() {
    if (window.innerWidth > 991.98) {
        closeSidebar();
    }
}

function handleDateFilterChange() {
    const selectedDate = document.getElementById('dateFilter').value;
    console.log('Date filter changed to:', selectedDate);
    
    // Show loading state
    showLoadingState();
    
    // Simulate API call to filter data
    setTimeout(() => {
        hideLoadingState();
        showNotification('Data filtered for ' + selectedDate, 'info');
    }, 1000);
}

function setupSearchHandlers() {
    const searchInputs = document.querySelectorAll('input[type="search"], .search-container input');
    
    searchInputs.forEach(input => {
        let searchTimeout;
        
        input.addEventListener('input', function() {
            clearTimeout(searchTimeout);
            searchTimeout = setTimeout(() => {
                performSearch(this.value, this);
            }, 300);
        });
    });
}

function performSearch(query, inputElement) {
    if (query.length < 2) return;
    
    console.log('Searching for:', query);
    
    // Add loading state to search input
    inputElement.classList.add('loading');
    
    // Simulate search
    setTimeout(() => {
        inputElement.classList.remove('loading');
        // Implement actual search logic here
    }, 500);
}

function setupPasswordStrength() {
    const passwordInput = document.getElementById('password');
    const strengthBar = document.getElementById('passwordStrength');
    const strengthText = document.getElementById('passwordStrengthText');
    
    if (passwordInput && strengthBar && strengthText) {
        passwordInput.addEventListener('input', function() {
            const password = this.value;
            const strength = calculatePasswordStrength(password);
            
            strengthBar.style.width = strength.percentage + '%';
            strengthBar.className = 'progress-bar ' + strength.class;
            strengthText.textContent = strength.text;
        });
    }
}

function calculatePasswordStrength(password) {
    let score = 0;
    let feedback = [];
    
    if (password.length >= 8) score += 25;
    else feedback.push('at least 8 characters');
    
    if (/[a-z]/.test(password)) score += 25;
    else feedback.push('lowercase letters');
    
    if (/[A-Z]/.test(password)) score += 25;
    else feedback.push('uppercase letters');
    
    if (/[0-9]/.test(password)) score += 25;
    else feedback.push('numbers');
    
    if (score <= 25) {
        return { percentage: 25, class: 'bg-danger', text: 'Weak password' };
    } else if (score <= 50) {
        return { percentage: 50, class: 'bg-warning', text: 'Fair password' };
    } else if (score <= 75) {
        return { percentage: 75, class: 'bg-info', text: 'Good password' };
    } else {
        return { percentage: 100, class: 'bg-success', text: 'Strong password' };
    }
}

function startAutoRefresh() {
    // Auto-refresh dashboard data every 30 seconds
    autoRefreshInterval = setInterval(() => {
        refreshDashboardData();
    }, 30000);
}

function refreshDashboardData() {
    console.log('Auto-refreshing dashboard data...');
    
    // Update live activity feed
    updateLiveActivityFeed();
    
    // Update summary cards
    updateSummaryCards();
    
    // Update alerts
    updateRecentAlerts();
}

function updateLiveActivityFeed() {
    const activityTable = document.querySelector('#liveActivityTable tbody');
    if (!activityTable) return;
    
    // Simulate new activity
    const newActivity = createActivityRow({
        timestamp: new Date().toLocaleString(),
        username: 'user' + Math.floor(Math.random() * 100),
        action: ['CREATE', 'READ', 'UPDATE', 'DELETE'][Math.floor(Math.random() * 4)],
        file_path: '/documents/file' + Math.floor(Math.random() * 1000) + '.pdf',
        status: Math.random() > 0.8 ? 'Unauthorized' : 'Authorized',
        risk_level: ['Low', 'Medium', 'High'][Math.floor(Math.random() * 3)]
    });
    
    // Add to top of table
    activityTable.insertBefore(newActivity, activityTable.firstChild);
    
    // Remove last row if more than 10 rows
    if (activityTable.children.length > 10) {
        activityTable.removeChild(activityTable.lastChild);
    }
    
    // Animate new row
    newActivity.classList.add('fade-in');
}

function createActivityRow(activity) {
    const row = document.createElement('tr');
    row.innerHTML = `
        <td><small class="text-muted">${activity.timestamp}</small></td>
        <td>
            <div class="d-flex align-items-center">
                <div class="user-avatar me-2">
                    <i class="bi bi-person-circle"></i>
                </div>
                ${activity.username}
            </div>
        </td>
        <td><span class="badge bg-secondary">${activity.action}</span></td>
        <td><code class="small">${activity.file_path}</code></td>
        <td>
            <span class="badge ${activity.status === 'Authorized' ? 'bg-success' : 'bg-danger'}">
                <i class="bi bi-${activity.status === 'Authorized' ? 'check' : 'x'}-circle me-1"></i>${activity.status}
            </span>
        </td>
        <td>
            <span class="badge ${getRiskBadgeClass(activity.risk_level)}">${activity.risk_level}</span>
        </td>
    `;
    return row;
}

function getRiskBadgeClass(riskLevel) {
    switch(riskLevel) {
        case 'High': return 'bg-danger';
        case 'Medium': return 'bg-warning';
        case 'Low': return 'bg-success';
        default: return 'bg-secondary';
    }
}

function updateSummaryCards() {
    const cards = document.querySelectorAll('.summary-card h3');
    cards.forEach(card => {
        const currentValue = parseInt(card.textContent);
        const change = Math.floor(Math.random() * 5) - 2; // Random change between -2 and +2
        const newValue = Math.max(0, currentValue + change);
        
        if (change !== 0) {
            animateNumberChange(card, currentValue, newValue);
        }
    });
}

function animateNumberChange(element, from, to) {
    const duration = 1000;
    const start = Date.now();
    
    function update() {
        const progress = Math.min((Date.now() - start) / duration, 1);
        const current = Math.floor(from + (to - from) * progress);
        element.textContent = current;
        
        if (progress < 1) {
            requestAnimationFrame(update);
        }
    }
    
    requestAnimationFrame(update);
}

function updateRecentAlerts() {
    // Simulate new alert occasionally
    if (Math.random() < 0.1) { // 10% chance
        const alertsContainer = document.querySelector('.recent-alerts');
        if (alertsContainer) {
            const newAlert = createAlertElement({
                username: 'user' + Math.floor(Math.random() * 100),
                description: 'Suspicious file access detected',
                file_path: '/sensitive/data' + Math.floor(Math.random() * 100) + '.xlsx',
                risk_level: ['High', 'Medium'][Math.floor(Math.random() * 2)],
                timestamp: new Date().toLocaleString()
            });
            
            alertsContainer.insertBefore(newAlert, alertsContainer.firstChild);
            
            // Remove oldest alert if more than 5
            if (alertsContainer.children.length > 5) {
                alertsContainer.removeChild(alertsContainer.lastChild);
            }
        }
    }
}

function createAlertElement(alert) {
    const alertDiv = document.createElement('div');
    alertDiv.className = 'alert-item mb-3 p-3 border rounded fade-in';
    alertDiv.innerHTML = `
        <div class="d-flex justify-content-between align-items-start mb-2">
            <div class="flex-grow-1">
                <h6 class="mb-1">${alert.username}</h6>
                <p class="mb-1 small text-muted">${alert.description}</p>
                <code class="small">${alert.file_path}</code>
            </div>
            <div class="ms-2">
                <span class="badge ${alert.risk_level === 'High' ? 'bg-danger' : 'bg-warning'}">${alert.risk_level}</span>
            </div>
        </div>
        <div class="d-flex justify-content-between align-items-center">
            <small class="text-muted">${alert.timestamp}</small>
            <div>
                <button class="btn btn-sm btn-outline-primary me-1" onclick="acknowledgeAlert(${alert.id})">Acknowledge</button>
                <button class="btn btn-sm btn-outline-secondary" onclick="investigateAlert(${alert.id})">Investigate</button>
                <button class="btn btn-sm btn-outline-danger" onclick="dismissAlert(${alert.id})">Dismiss</button>
            </div>
        </div>
    `;
    return alertDiv;
}

function animateLiveIndicators() {
    const indicators = document.querySelectorAll('.live-indicator');
    indicators.forEach(indicator => {
        indicator.classList.add('live-indicator');
    });
}

function showLoadingState() {
    const mainContent = document.querySelector('.page-content');
    if (mainContent) {
        mainContent.classList.add('loading');
    }
}

function hideLoadingState() {
    const mainContent = document.querySelector('.page-content');
    if (mainContent) {
        mainContent.classList.remove('loading');
    }
}

function showNotification(message, type = 'info', duration = 5000) {
    const notification = document.createElement('div');
    notification.className = `alert alert-${type} alert-dismissible fade show position-fixed`;
    notification.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;';
    notification.innerHTML = `
        <div class="d-flex align-items-center">
            <i class="bi bi-${getNotificationIcon(type)} me-2"></i>
            ${message}
        </div>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    
    document.body.appendChild(notification);
    
    // Auto-remove notification
    setTimeout(() => {
        if (notification.parentNode) {
            notification.remove();
        }
    }, duration);
    
    return notification;
}

function getNotificationIcon(type) {
    const icons = {
        'success': 'check-circle',
        'danger': 'exclamation-triangle',
        'warning': 'exclamation-circle',
        'info': 'info-circle'
    };
    return icons[type] || 'info-circle';
}

// Alert Management Functions
function acknowledgeAlert(alertId) {
    fetch(`/api/alert/${alertId}/acknowledge`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        }
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showNotification('Alert acknowledged successfully', 'success');
            setTimeout(() => location.reload(), 1000);
        } else {
            showNotification('Error acknowledging alert: ' + data.error, 'error');
        }
    })
    .catch(error => {
        showNotification('Network error: ' + error.message, 'error');
    });
}

function resolveAlert(alertId) {
    if (confirm('Are you sure you want to mark this alert as resolved?')) {
        fetch(`/api/alert/${alertId}/resolve`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            }
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                showNotification('Alert resolved successfully', 'success');
                setTimeout(() => location.reload(), 1000);
            } else {
                showNotification('Error resolving alert: ' + data.error, 'error');
            }
        })
        .catch(error => {
            showNotification('Network error: ' + error.message, 'error');
        });
    }
}

function dismissAlert(alertId) {
    if (confirm('Are you sure you want to dismiss this alert? This action cannot be undone.')) {
        fetch(`/api/alert/${alertId}/dismiss`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            }
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                showNotification('Alert dismissed successfully', 'success');
                setTimeout(() => location.reload(), 1000);
            } else {
                showNotification('Error dismissing alert: ' + data.error, 'error');
            }
        })
        .catch(error => {
            showNotification('Network error: ' + error.message, 'error');
        });
    }
}

function investigateAlert(alertId) {
    console.log('Investigating alert:', alertId);
    
    fetch(`/api/alert/${alertId}/investigate`)
    .then(response => {
        console.log('Response status:', response.status);
        return response.json();
    })
    .then(data => {
        console.log('Investigation data:', data);
        
        if (data.error) {
            showNotification('Error loading investigation data: ' + data.error, 'error');
            return;
        }
        
        showInvestigationModal(data);
    })
    .catch(error => {
        console.error('Investigation error:', error);
        showNotification('Network error: ' + error.message, 'error');
    });
}

function showAlertDetails(alertId) {
    // For now, just show investigation data
    investigateAlert(alertId);
}

function showInvestigationModal(data) {
    const modal = document.createElement('div');
    modal.className = 'modal fade';
    modal.innerHTML = `
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">Investigation: Alert #${data.alert.id}</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                </div>
                <div class="modal-body">
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <strong>Description:</strong><br>
                            ${data.alert.description}
                        </div>
                        <div class="col-md-6">
                            <strong>Risk Level:</strong><br>
                            <span class="badge bg-${data.alert.risk_level === 'High' ? 'danger' : data.alert.risk_level === 'Medium' ? 'warning' : 'success'}">${data.alert.risk_level}</span>
                        </div>
                    </div>
                    <div class="mb-3">
                        <strong>File Path:</strong><br>
                        <code>${data.alert.file_path}</code>
                    </div>
                    <div class="mb-3">
                        <strong>Timestamp:</strong> ${data.alert.timestamp}
                    </div>
                    
                    <h6>Related File Activities:</h6>
                    <div class="table-responsive">
                        <table class="table table-sm">
                            <thead>
                                <tr>
                                    <th>Time</th>
                                    <th>User</th>
                                    <th>Process</th>
                                    <th>Action</th>
                                    <th>Risk</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${data.related_activities.map(act => `
                                    <tr>
                                        <td>${act.timestamp}</td>
                                        <td>${act.username}</td>
                                        <td>${act.process_name}</td>
                                        <td><span class="badge bg-secondary">${act.action}</span></td>
                                        <td><span class="badge bg-${act.risk_level === 'High' ? 'danger' : act.risk_level === 'Medium' ? 'warning' : 'success'}">${act.risk_level}</span></td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                </div>
            </div>
        </div>
    `;
    
    document.body.appendChild(modal);
    const bsModal = new bootstrap.Modal(modal);
    bsModal.show();
    
    modal.addEventListener('hidden.bs.modal', () => {
        document.body.removeChild(modal);
    });
}

function showNotification(message, type) {
    const alertClass = type === 'success' ? 'alert-success' : 'alert-danger';
    const notification = document.createElement('div');
    notification.className = `alert ${alertClass} alert-dismissible fade show position-fixed`;
    notification.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;';
    notification.innerHTML = `
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        if (notification.parentNode) {
            notification.parentNode.removeChild(notification);
        }
    }, 5000);
}

// Utility functions
function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatTimeAgo(timestamp) {
    const now = new Date();
    const time = new Date(timestamp);
    const diffInSeconds = Math.floor((now - time) / 1000);
    
    if (diffInSeconds < 60) return 'Just now';
    if (diffInSeconds < 3600) return Math.floor(diffInSeconds / 60) + ' minutes ago';
    if (diffInSeconds < 86400) return Math.floor(diffInSeconds / 3600) + ' hours ago';
    return Math.floor(diffInSeconds / 86400) + ' days ago';
}

function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// Export functions for use in other scripts
window.DashboardUtils = {
    showNotification,
    showLoadingState,
    hideLoadingState,
    formatFileSize,
    formatTimeAgo,
    debounce
};

// Handle page visibility change to pause/resume auto-refresh
document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
        if (autoRefreshInterval) {
            clearInterval(autoRefreshInterval);
        }
    } else {
        startAutoRefresh();
    }
});

// Cleanup on page unload
window.addEventListener('beforeunload', function() {
    if (autoRefreshInterval) {
        clearInterval(autoRefreshInterval);
    }
});
