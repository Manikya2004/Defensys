#!/bin/bash
#===============================
# System Hardening Script: Kernel Parameter Tuning for Network Security
# Applies settings to mitigate SYN floods, ICMP attacks, and IP spoofing.
#===============================

# --- Configuration ---
CONFIG_FILE="/etc/sysctl.d/99-network-hardening.conf"
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

log_action "Applying network hardening via sysctl configuration..."
log_action "Target configuration file: $CONFIG_FILE"

# Create the sysctl hardening file content
# Using printf for potentially better handling of special characters if needed
printf "%s\n" \
"# Kernel parameters for network security hardening" \
"# Applied by network_hardening_sysctl.sh script" \
"" \
"# Protect against SYN flood attacks (SYN cookies)" \
"net.ipv4.tcp_syncookies=1" \
"" \
"# Increase SYN backlog queue to handle more half-open connections during SYN floods" \
"net.ipv4.tcp_max_syn_backlog=4096" \
"" \
"# Reduce SYN-ACK retries to mitigate SYN flood amplification effects" \
"net.ipv4.tcp_synack_retries=2" \
"" \
"# Ignore ICMP echo requests sent to broadcast/multicast addresses" \
"net.ipv4.icmp_echo_ignore_broadcasts=1" \
"" \
"# Ignore bogus ICMP error responses (potential reconnaisance/attack vector)" \
"net.ipv4.icmp_ignore_bogus_error_responses=1" \
"" \
"# Enable Reverse Path Filtering (RFC 3704) to prevent IP spoofing" \
"# Mode 1: Strict - blocks packets if source IP doesn't match route back" \
"net.ipv4.conf.all.rp_filter=1" \
"net.ipv4.conf.default.rp_filter=1" \
"" \
"# Log suspicious packets (martians, source-routed, redirects)" \
"# Helps in detecting network anomalies and potential attacks" \
"net.ipv4.conf.all.log_martians=1" \
"net.ipv4.conf.default.log_martians=1" \
"" \
"# Disable acceptance of source-routed packets (rarely used legitimately, potential security risk)" \
"net.ipv4.conf.all.accept_source_route=0" \
"net.ipv4.conf.default.accept_source_route=0" \
"" \
"# Disable acceptance of ICMP redirects (can be used for MITM attacks)" \
"net.ipv4.conf.all.accept_redirects=0" \
"net.ipv4.conf.default.accept_redirects=0" \
"" \
"# Disable sending of ICMP redirects (servers shouldn't act as routers)" \
"net.ipv4.conf.all.send_redirects=0" \
"net.ipv4.conf.default.send_redirects=0" \
> "$CONFIG_FILE"

# Check if file was created successfully
if [ $? -ne 0 ]; then
    log_action "Error: Failed to write configuration to $CONFIG_FILE."
    exit 1
fi
chmod 644 "$CONFIG_FILE" # Set standard permissions
log_action "Successfully created/updated $CONFIG_FILE."

# Apply the new settings system-wide
log_action "Applying sysctl settings from all configuration files..."
if sysctl --system; then
    log_action "Network hardening sysctl settings applied successfully."
else
    log_action "Error: Failed to apply sysctl settings. Check output above and system logs."
    # Attempt to load the specific file as a fallback, though --system is preferred
    # sysctl -p "$CONFIG_FILE"
    exit 1
fi

log_action "Network hardening script finished."
