#===============================
# SSH Hardening: Configure ClientAliveInterval and ClientAliveCountMax
# Helps prevent idle SSH sessions from staying open indefinitely.
# Corresponds to CIS Benchmark recommendations (e.g., 5.2.20).
#===============================

# --- Configuration ---
CONFIG_FILE="/etc/ssh/sshd_config"
DESIRED_INTERVAL=300 # CIS recommends 300 seconds (5 minutes) or less
DESIRED_COUNT=0    # CIS recommends 0 (server sends keepalive, disconnects on timeout)
AUDIT_LOG="/var/log/security_hardening.log"
# --- End Configuration ---

# Function to log messages
log_action() {
    echo "$(date): $1" | tee -a "$AUDIT_LOG"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  log_action "Error: This script must be run as root."
  exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_action "Error: SSH configuration file not found at $CONFIG_FILE."
    exit 1
fi

BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%F_%T)"

log_action "Configuring SSH ClientAlive settings in $CONFIG_FILE..."
log_action "Desired ClientAliveInterval: $DESIRED_INTERVAL"
log_action "Desired ClientAliveCountMax: $DESIRED_COUNT"

# Backup first
log_action "Creating backup of sshd_config at $BACKUP_FILE..."
cp "$CONFIG_FILE" "$BACKUP_FILE" || { log_action "Error: Failed to create backup. Exiting."; exit 1; }

# Use sshd -T to get current effective values
HOST_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$HOST_IP" ]]; then
    log_action "Warning: Could not determine host IP address. Using 127.0.0.1 for sshd -T check."
    HOST_IP="127.0.0.1"
fi
CURRENT_INTERVAL=$(sshd -T -C user=root -C host="$(hostname)" -C addr="$HOST_IP" | grep -i clientaliveinterval | awk '{print $2}')
CURRENT_COUNT=$(sshd -T -C user=root -C host="$(hostname)" -C addr="$HOST_IP" | grep -i clientalivecountmax | awk '{print $2}')

log_action "Current effective ClientAliveInterval: ${CURRENT_INTERVAL:-Not Set}"
log_action "Current effective ClientAliveCountMax: ${CURRENT_COUNT:-Not Set}"

# Check if current settings already match desired values
if [[ "$CURRENT_INTERVAL" == "$DESIRED_INTERVAL" && "$CURRENT_COUNT" == "$DESIRED_COUNT" ]]; then
    log_action "SSH ClientAlive settings are already configured as desired. No changes needed."
    # Optional: Ensure they are explicitly set in the config file anyway
    # Proceed with sed commands if explicit setting is required policy
fi

read -p "Do you want to ensure ClientAliveInterval is set to '$DESIRED_INTERVAL' and ClientAliveCountMax to '$DESIRED_COUNT' in $CONFIG_FILE? (y/N): " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    log_action "Applying changes to $CONFIG_FILE..."

    # Modify or append ClientAliveInterval
    # Use sed to uncomment/replace existing line or append if missing
    if grep -qE '^\s*#?\s*ClientAliveInterval' "$CONFIG_FILE"; then
        sed -i -E "s/^\s*#?\s*ClientAliveInterval.*/ClientAliveInterval $DESIRED_INTERVAL/" "$CONFIG_FILE"
    else
        echo "ClientAliveInterval $DESIRED_INTERVAL" >> "$CONFIG_FILE"
    fi

    # Modify or append ClientAliveCountMax
    if grep -qE '^\s*#?\s*ClientAliveCountMax' "$CONFIG_FILE"; then
        sed -i -E "s/^\s*#?\s*ClientAliveCountMax.*/ClientAliveCountMax $DESIRED_COUNT/" "$CONFIG_FILE"
    else
        echo "ClientAliveCountMax $DESIRED_COUNT" >> "$CONFIG_FILE"
    fi

    log_action "Changes written to $CONFIG_FILE."

    # Test SSH config before restart
    log_action "Testing SSH configuration syntax..."
    if sshd -t; then
        log_action "SSH config syntax is valid."
        log_action "Restarting sshd service..."
        # Use systemctl is-active to check status before restart, and verify after
        was_active=$(systemctl is-active sshd)
        if systemctl restart sshd && sleep 2 && systemctl is-active sshd | grep -q "active"; then
             log_action "sshd service restarted successfully."
             # Show updated effective values
             log_action "Verifying new effective settings..."
             UPDATED_INTERVAL=$(sshd -T -C user=root -C host="$(hostname)" -C addr="$HOST_IP" | grep -i clientaliveinterval | awk '{print $2}')
             UPDATED_COUNT=$(sshd -T -C user=root -C host="$(hostname)" -C addr="$HOST_IP" | grep -i clientalivecountmax | awk '{print $2}')
             log_action "New effective ClientAliveInterval: ${UPDATED_INTERVAL:-Not Set}"
             log_action "New effective ClientAliveCountMax: ${UPDATED_COUNT:-Not Set}"
        else
             log_action "Failed to restart sshd service or service did not become active."
             log_action "Restoring original config from backup: $BACKUP_FILE"
             cp "$BACKUP_FILE" "$CONFIG_FILE"
             # Attempt to restart with original config if it was active before
             if [[ "$was_active" == "active" ]]; then
                 systemctl restart sshd &>/dev/null
             fi
             exit 1
        fi
    else
        log_action "SSH config has syntax errors after modification. Not restarting."
        log_action "Restoring original config from backup: $BACKUP_FILE"
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        log_action "Original configuration restored. Please check $CONFIG_FILE manually."
        exit 1
    fi
else
    log_action "No changes made."
fi
log_action "SSH ClientAlive tuning script finished."
