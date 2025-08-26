#!/bin/bash
#===============================
# SSH Hardening: Configure LoginGraceTime
# Sets the time allowed for successful authentication after connection.
# Corresponds to CIS Benchmark recommendations (e.g., 5.2.19).
#===============================

# --- Configuration ---
CONFIG_FILE="/etc/ssh/sshd_config"
DESIRED_GRACE_TIME=60 # CIS recommends 60 seconds or less
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

log_action "[Audit] Checking SSH LoginGraceTime setting..."

# Step 1: Get current effective value using sshd -T
HOST_IP=$(hostname -I | awk '{print $1}') # Get primary IP
if [[ -z "$HOST_IP" ]]; then
    log_action "Warning: Could not determine host IP address. Using 127.0.0.1 for sshd -T check."
    HOST_IP="127.0.0.1"
fi
# Use grep -i for case-insensitivity, handle potential errors
effective_grace_time=$(sshd -T -C user=root -C host="$(hostname)" -C addr="$HOST_IP" 2>/dev/null | grep -i '^logingracetime' | awk '{print $2}')

if [ $? -ne 0 ] || [ -z "$effective_grace_time" ]; then
     log_action "Warning: Could not determine effective LoginGraceTime setting via 'sshd -T'. Checking config file directly."
     # Fallback: Check config file directly (less reliable)
     config_setting=$(grep -Ei '^\s*LoginGraceTime\s+' "$CONFIG_FILE" | tail -n 1 | awk '{print $2}')
     if [[ -n "$config_setting" ]]; then
         effective_grace_time="$config_setting" # Use value from config if found
     else
         effective_grace_time="120" # Assume default '120' if not found
         log_action "Assuming default '120' as it's not explicitly set in $CONFIG_FILE."
     fi
fi

log_action "Current effective LoginGraceTime: $effective_grace_time seconds"

# Step 2: Validate against desired value
# CIS recommends <= 60 seconds. 0 means infinite (insecure).
if [[ "$effective_grace_time" -gt 0 && "$effective_grace_time" -le "$DESIRED_GRACE_TIME" ]]; then
    log_action "[Secure] LoginGraceTime ($effective_grace_time seconds) is within the recommended range (1-$DESIRED_GRACE_TIME seconds)."
    # Optional sanity check for explicit bad value in config despite effective good value
    if grep -Eqi '^\s*LoginGraceTime\s+(0|[6-9][1-9]|[1-9][0-9]{2,})' "$CONFIG_FILE"; then
         log_action "Warning: Although the effective setting is secure, '$CONFIG_FILE' contains an explicit LoginGraceTime outside the recommended range."
    fi
    exit 0
else
    if [[ "$effective_grace_time" -eq 0 ]]; then
        log_action "[Warning] LoginGraceTime is set to 0 (infinite), which is insecure."
    else
        log_action "[Warning] LoginGraceTime ($effective_grace_time seconds) is outside the recommended range (1-$DESIRED_GRACE_TIME seconds)."
    fi
    read -p "Do you want to remediate this by setting LoginGraceTime to '$DESIRED_GRACE_TIME' seconds in $CONFIG_FILE? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_action "Applying remediation..."

        # Backup sshd_config first
        log_action "Creating backup at $BACKUP_FILE..."
        cp "$CONFIG_FILE" "$BACKUP_FILE" || { log_action "Error: Failed to create backup. Exiting."; exit 1; }

        # Replace or append the config line using sed
        if grep -qEi '^\s*#?\s*LoginGraceTime' "$CONFIG_FILE"; then
             # If line exists (commented or not), uncomment and set to desired value
            sed -i -E "s/^\s*#?\s*LoginGraceTime.*/LoginGraceTime $DESIRED_GRACE_TIME/" "$CONFIG_FILE"
        else
             # If line doesn't exist, append it
            echo "" >> "$CONFIG_FILE" # Add newline for safety
            echo "LoginGraceTime $DESIRED_GRACE_TIME" >> "$CONFIG_FILE"
        fi
        log_action "Set 'LoginGraceTime $DESIRED_GRACE_TIME' in $CONFIG_FILE."

        # Test and Restart SSH service
        log_action "Testing SSH configuration syntax..."
        if sshd -t; then
             log_action "SSH config syntax is valid."
             log_action "Restarting sshd service..."
             was_active=$(systemctl is-active sshd)
             if systemctl restart sshd && sleep 2 && systemctl is-active sshd | grep -q "active"; then
                log_action "Remediation complete. sshd restarted. LoginGraceTime should now be effectively $DESIRED_GRACE_TIME seconds."
             else
                log_action "Restart failed or service did not become active! Check 'systemctl status sshd' and 'journalctl -xeu sshd.service'."
                log_action "Restoring backup from $BACKUP_FILE..."
                cp "$BACKUP_FILE" "$CONFIG_FILE"
                if [[ "$was_active" == "active" ]]; then systemctl restart sshd &>/dev/null; fi
                exit 1
             fi
        else
             log_action "SSH config test failed after modification. Restoring backup..."
             cp "$BACKUP_FILE" "$CONFIG_FILE"
             log_action "Original configuration restored. Please check $CONFIG_FILE manually."
             exit 1
        fi
    else
        log_action "No changes were made."
        exit 1 # Exit with non-zero status as it's not compliant
    fi
fi
 log_action "SSH LoginGraceTime check script finished."
