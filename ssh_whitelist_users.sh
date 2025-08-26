#!/bin/bash
#===============================
# SSH Hardening: Configure User Whitelist (AllowUsers)
# Restricts SSH access to only specified users.
#===============================

# --- Configuration ---
# Define allowed users in this array. Add/remove usernames as needed.
ALLOWED_USERS=("alloweduser" "testuser" "admin") # Example users
SSH_CONFIG="/etc/ssh/sshd_config"
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

# Check if the allowed users array is empty
if [ ${#ALLOWED_USERS[@]} -eq 0 ]; then
    log_action "⚠️ Warning: ALLOWED_USERS array is empty. This would block all users. Exiting."
    exit 1
fi

log_action "Configuring SSH user whitelist in $SSH_CONFIG..."
log_action "Allowed users to be configured: ${ALLOWED_USERS[*]}"

# Check if sshd_config exists
if [ ! -f "$SSH_CONFIG" ]; then
    log_action "❌ Error: SSH configuration file not found at $SSH_CONFIG."
    exit 1
fi

BACKUP_FILE="${SSH_CONFIG}.bak.$(date +%F_%T)"

# Backup the original SSH config
log_action "Creating backup of existing SSH config at $BACKUP_FILE..."
cp "$SSH_CONFIG" "$BACKUP_FILE" || { log_action "❌ Error: Failed to create backup file. Exiting."; exit 1; }

# Remove any existing AllowUsers or DenyUsers lines to avoid conflicts
# Use semicolons as sed delimiter to handle potential slashes in paths if needed later
log_action "Removing existing AllowUsers/DenyUsers directives from $SSH_CONFIG..."
sed -i '\;^\s*AllowUsers\s\+.*;d' "$SSH_CONFIG"
sed -i '\;^\s*DenyUsers\s\+.*;d' "$SSH_CONFIG"
sed -i '\;^\s*AllowGroups\s\+.*;d' "$SSH_CONFIG" # Also remove AllowGroups for simplicity
sed -i '\;^\s*DenyGroups\s\+.*;d' "$SSH_CONFIG"  # Also remove DenyGroups

# Construct the AllowUsers line by joining array elements with space
allow_line="AllowUsers $(IFS=" "; echo "${ALLOWED_USERS[*]}")"

# Add the new AllowUsers line to the end of the file
log_action "Adding new AllowUsers directive..."
echo "" >> "$SSH_CONFIG" # Add a newline for separation
echo "$allow_line" >> "$SSH_CONFIG"
echo "" >> "$SSH_CONFIG" # Add a newline after

log_action "✅ Updated $SSH_CONFIG to whitelist: ${ALLOWED_USERS[*]}"

# Test SSH config before restart
log_action "Testing SSH configuration syntax..."
if sshd -t; then
    log_action "✅ SSH config syntax is valid."
    log_action "Restarting sshd service..."
    was_active=$(systemctl is-active sshd)
    if systemctl restart sshd && sleep 2 && systemctl is-active sshd | grep -q "active"; then
        log_action "✅ SSH service restarted successfully."
        log_action "Access should now be restricted to users: ${ALLOWED_USERS[*]}"
    else
        log_action "❌ Error: Failed to restart sshd service or it did not become active."
        log_action "Restoring configuration from backup: $BACKUP_FILE"
        cp "$BACKUP_FILE" "$SSH_CONFIG"
        if [[ "$was_active" == "active" ]]; then systemctl restart sshd &>/dev/null; fi
        exit 1
    fi
else
    log_action "❌ Error: SSH configuration test failed after modification!"
    log_action "Restoring configuration from backup: $BACKUP_FILE"
    cp "$BACKUP_FILE" "$SSH_CONFIG"
    log_action "Original configuration restored. Please check $SSH_CONFIG for errors."
    exit 1
fi
 log_action "SSH user whitelist script finished."
