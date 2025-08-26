#!/bin/bash
#===============================
# Security Setup: Configure Fail2Ban for SSH Brute-Force Protection
# Installs and configures Fail2Ban to ban IPs after failed SSH logins.
#===============================

# --- Configuration ---
MAX_RETRY=3          # Ban after 3 failed attempts
FIND_TIME="10m"      # Within a 10-minute window
BAN_TIME="1h"        # Ban for 1 hour (-1 for permanent, use with caution)
# Add IPs/networks to ignore (e.g., local network, monitoring server)
# Space-separated list. CIDR notation allowed.
IGNORE_IPS="127.0.0.1/8 ::1"
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

log_action "Setting up Fail2Ban for SSH protection..."

# 1. Install Fail2Ban if not present
log_action "Checking Fail2Ban installation..."
if ! command -v fail2ban-client &> /dev/null; then
    log_action "Fail2Ban not found. Attempting installation..."
    local install_packages="fail2ban"
    # Include systemd support package if using systemd
    if command -v systemctl &> /dev/null && systemctl --version >/dev/null 2>&1; then
         install_packages+=" fail2ban-systemd" # RHEL/CentOS/Fedora
         # Debian/Ubuntu usually includes systemd support by default
    fi

    if command -v dnf &> /dev/null; then
        dnf install -y $install_packages
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y $install_packages
    else
        log_action "❌ Error: Unsupported package manager. Please install Fail2Ban manually."
        exit 1
    fi

    if ! command -v fail2ban-client &> /dev/null; then
         log_action "❌ Error: Fail2Ban installation failed."
         exit 1
    fi
     log_action "✅ Fail2Ban installed successfully."
else
    log_action "✅ Fail2Ban is already installed."
fi

# 2. Enable and start Fail2Ban service
log_action "Ensuring Fail2Ban service is enabled and started..."
# Use --now to enable and start in one step
if ! systemctl enable --now fail2ban; then
    # If enable --now fails, try starting separately (might already be enabled)
    if ! systemctl start fail2ban; then
        log_action "❌ Error: Failed to enable or start Fail2Ban service. Check 'systemctl status fail2ban'."
        exit 1
    fi
fi
if ! systemctl is-active --quiet fail2ban; then
     log_action "❌ Error: Fail2Ban service started but is not active. Check status."
     exit 1
fi
 log_action "✅ Fail2Ban service is enabled and running."

# 3. Configure SSH jail in a local override file
JAIL_LOCAL_CONFIG="/etc/fail2ban/jail.local"
JAIL_D_CONFIG="/etc/fail2ban/jail.d/sshd.local" # Alternative using .d directory

# Prefer using jail.d for cleaner overrides
TARGET_CONFIG=$JAIL_D_CONFIG
mkdir -p /etc/fail2ban/jail.d # Ensure directory exists

# Detect SSH port from sshd_config
SSH_PORT=$(grep -Ei '^\s*Port\s+' /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
SSH_PORT=${SSH_PORT:-22} # Default to 22 if not found

log_action "Configuring Fail2Ban SSH jail in $TARGET_CONFIG..."
log_action "  SSH Port: $SSH_PORT"
log_action "  Max Retry: $MAX_RETRY"
log_action "  Find Time: $FIND_TIME"
log_action "  Ban Time: $BAN_TIME"
log_action "  Ignoring IPs: $IGNORE_IPS"

# Create the jail override file
# Using printf for controlled output
printf "%s\n" \
"[sshd]" \
"enabled = true" \
"port = $SSH_PORT" \
"# filter = sshd  # Default filter is usually fine" \
"# logpath = %(sshd_log)s # Use Fail2Ban's automatic detection" \
"# backend = %(sshd_backend)s # Use Fail2Ban's automatic detection" \
"maxretry = $MAX_RETRY" \
"findtime = $FIND_TIME" \
"bantime = $BAN_TIME" \
"ignoreip = $IGNORE_IPS" \
> "$TARGET_CONFIG"

if [ $? -ne 0 ]; then
    log_action "❌ Error: Failed to write Fail2Ban configuration to $TARGET_CONFIG."
    exit 1
fi
chmod 644 "$TARGET_CONFIG"
log_action "✅ SSH jail configured successfully."

# 4. Reload Fail2Ban configuration
log_action "Reloading Fail2Ban configuration..."
if fail2ban-client reload; then
    log_action "✅ Fail2Ban configuration reloaded successfully."
else
    log_action "❌ Error: Failed to reload Fail2Ban configuration."
    log_action "   Run 'fail2ban-client -d' or check '/var/log/fail2ban.log' for errors."
    # Consider removing the potentially bad config file?
    # rm -f "$TARGET_CONFIG"
    exit 1
fi

# 5. Verify status of the sshd jail
log_action "Checking status of the 'sshd' jail..."
sleep 2 # Give Fail2Ban a moment to process reload
if fail2ban-client status sshd; then
    log_action "✅ Fail2Ban 'sshd' jail is active."
else
    log_action "⚠️ Warning: Could not get status for 'sshd' jail. It might not be active or an error occurred."
fi

log_action "✅ Fail2Ban setup for SSH completed."
