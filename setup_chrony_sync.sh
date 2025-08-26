#!/bin/bash
#===============================
# NTP Time Synchronization Setup using Chrony
# Installs, configures, enables, and verifies chrony for time sync.
#===============================

# --- Configuration ---
CHRONY_CONF="/etc/chrony.conf"
# Default NTP pool - consider using vendor-specific pools if available
# e.g., 0.rhel.pool.ntp.org, 1.rhel.pool.ntp.org for RHEL
DEFAULT_NTP_POOL="pool.ntp.org"
AUDIT_LOG="/var/log/security_hardening.log"
# --- End Configuration ---

# Function to log messages
log_action() {
    echo "$(date): $1" | tee -a "$AUDIT_LOG"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  log_action "❌ Error: This script must be run as root."
  exit 1
fi

log_action "🔍 Checking and configuring NTP time synchronization using 'chrony'..."

# 1. Install chrony if not present
log_action "Checking if 'chrony' package is installed..."
if ! rpm -q chrony &>/dev/null && ! dpkg -s chrony &>/dev/null; then
    log_action "⚠️ Chrony is not installed. Attempting to install now..."
    local installed=0
    if command -v dnf &> /dev/null; then
        if dnf install -y chrony; then installed=1; fi
    elif command -v apt-get &> /dev/null; then
         if apt-get update && apt-get install -y chrony; then installed=1; fi
    else
        log_action "❌ Error: Unsupported package manager. Please install chrony manually."
        exit 1
    fi
    if [ $installed -eq 1 ]; then
         log_action "✅ Chrony installed successfully."
    else
         log_action "❌ Error: Failed to install chrony."
         exit 1
    fi
else
    log_action "✅ Chrony is already installed."
fi
 # Ensure chronyc command is available
 if ! command -v chronyc &> /dev/null; then
      log_action "❌ Error: 'chronyc' command not found even after installation check. Exiting."
      exit 1
 fi

# 2. Configure NTP servers in /etc/chrony.conf
log_action "Checking NTP server configuration in $CHRONY_CONF..."
if [ ! -f "$CHRONY_CONF" ]; then
     log_action "❌ Error: Chrony configuration file $CHRONY_CONF not found."
     exit 1
fi

# Check if any non-commented 'server' or 'pool' lines exist
if ! grep -qE '^\s*(server|pool)\s+' "$CHRONY_CONF"; then
    log_action "⚠️ No active NTP servers (server/pool lines) found in $CHRONY_CONF."
    log_action "Adding default pool configuration: $DEFAULT_NTP_POOL..."
    # Backup original config
    cp "$CHRONY_CONF" "${CHRONY_CONF}.bak.$(date +%F_%T)" || { log_action "❌ Error creating backup for $CHRONY_CONF"; exit 1; }
    # Add pool configuration
    echo "" >> "$CHRONY_CONF" # Ensure newline before adding
    echo "# Added by script: Default NTP server pool" >> "$CHRONY_CONF"
    echo "pool $DEFAULT_NTP_POOL iburst" >> "$CHRONY_CONF"
    log_action "✅ Default NTP pool added to $CHRONY_CONF."
    NEEDS_RESTART=1 # Flag that restart is needed due to config change
else
    log_action "✅ Active NTP servers appear to be configured in $CHRONY_CONF."
    # Optional: List configured servers
    # grep -E '^\s*(server|pool)\s+' "$CHRONY_CONF" | sed 's/^/# /' # Log them commented out
    NEEDS_RESTART=0
fi

# 3. Enable and start chronyd service
log_action "Ensuring chronyd service is enabled and running..."
SERVICE_NAME="chronyd" # Default for RHEL/Fedora
# Check for chrony service name on Debian/Ubuntu
if systemctl list-unit-files | grep -q '^chrony.service'; then
     SERVICE_NAME="chrony"
fi
log_action "Using service name: $SERVICE_NAME"

# Enable the service
if ! systemctl is-enabled --quiet "$SERVICE_NAME"; then
     if systemctl enable "$SERVICE_NAME"; then
          log_action "✅ Enabled $SERVICE_NAME service."
          NEEDS_RESTART=1 # Restart after enabling
     else
          log_action "⚠️ Failed to enable $SERVICE_NAME service."
          # Continue, maybe it can still be started
     fi
else
     log_action "✅ $SERVICE_NAME service is already enabled."
fi

# Start or restart the service
if ! systemctl is-active --quiet "$SERVICE_NAME" || [ "$NEEDS_RESTART" -eq 1 ]; then
     log_action "Starting/Restarting $SERVICE_NAME service..."
     if ! systemctl restart "$SERVICE_NAME"; then
          log_action "❌ Error: Failed to start or restart $SERVICE_NAME service. Check status and logs:"
          log_action "   systemctl status $SERVICE_NAME"
          log_action "   journalctl -xeu $SERVICE_NAME"
          exit 1
     fi
     log_action "✅ $SERVICE_NAME service started/restarted."
     log_action "Waiting a few seconds for chrony to stabilize..."
     sleep 5 # Give chrony time to start communication
else
     log_action "✅ $SERVICE_NAME service is already active."
fi


# 4. Check synchronization status
log_action "Checking time synchronization status using 'chronyc tracking'..."
if chronyc tracking; then
    # Check Reference ID - if it's 127.127.1.0 (LOCAL), it's not synced to an external source
    ref_id=$(chronyc tracking | grep 'Reference ID' | awk '{print $4}')
    leap_status=$(chronyc tracking | grep 'Leap status' | awk '{print $4}')
    if [[ "$ref_id" == "127.127.1.0" ]] || [[ "$leap_status" == "NotSynchronised" ]]; then
         log_action "⚠️ Warning: Chrony is running but may not be synchronized to a valid external NTP source yet."
         log_action "   Reference ID: $ref_id, Leap Status: $leap_status"
         log_action "   Check 'chronyc sources' for details on NTP servers."
    else
         log_action "✅ Chrony appears to be synchronized."
    fi
else
    log_action "⚠️ Failed to get tracking status from chronyc."
fi

log_action "Detailed source information ('chronyc sources'):"
chronyc sources

log_action "✅ Chrony setup and check completed."
