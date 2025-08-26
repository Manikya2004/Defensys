#!/bin/bash
#===============================
# SELinux Audit: Check for Unconfined Services
# Identifies processes running in the 'unconfined_service_t' domain,
# which may indicate missing or incorrect SELinux policies.
# Corresponds to CIS Benchmark recommendations (e.g., 1.6.1.6).
#===============================

# --- Configuration ---
AUDIT_LOG="/var/log/security_hardening.log"
UNCONFINED_LOG="/var/log/selinux_unconfined_audit_$(date +%F_%T).log"
# --- End Configuration ---

# Function to log messages
log_action() {
    # Log to central audit log if it exists, otherwise just echo
    if [ -n "$AUDIT_LOG" ]; then
         echo "$(date): $1" | tee -a "$AUDIT_LOG"
    else
         echo "$(date): $1"
    fi
}

 # Root check is optional for just checking, but good practice
# if [ "$EUID" -ne 0 ]; then
#   log_action "Error: This script should ideally be run as root for full system visibility."
#   # exit 1 # Or just continue with potential limitations
# fi

log_action "[Audit] Checking SELinux status and for unconfined services..."

# Step 1: Check if SELinux is enabled and enforcing
if ! command -v sestatus &> /dev/null; then
    log_action "Warning: 'sestatus' command not found. Cannot determine SELinux status."
else
    sestatus_output=$(sestatus)
    log_action "SELinux Status:\n$sestatus_output"
    if ! echo "$sestatus_output" | grep -q "SELinux status:\s*enabled"; then
        log_action "Warning: SELinux does not appear to be enabled. Unconfined check may not be relevant."
        # exit 0 # Or continue anyway
    elif ! echo "$sestatus_output" | grep -q "Current mode:\s*enforcing"; then
         log_action "Warning: SELinux is not in enforcing mode. Unconfined services might still exist but policy is not being enforced."
    fi
fi

# Step 2: Check for processes running in the unconfined_service_t context
# Ensure ps command supports -Z
if ! ps -p 1 -o pid,label &>/dev/null; then
    log_action "Error: 'ps' command does not seem to support the 'label' or '-Z' option. Cannot check SELinux contexts."
    exit 1
fi

# Use ps with label format, handle potential errors
unconfined_services=$(ps -e --format pid,label,comm | grep 'unconfined_service_t')

if [ -z "$unconfined_services" ]; then
    log_action "[Secure] No processes found running in the 'unconfined_service_t' domain."
    exit 0
else
    log_action "[Warning] Unconfined services found:"
    log_action "--------------------------------------------------"
    log_action "PID      LABEL                           COMMAND"
    log_action "$unconfined_services" | tee -a "$UNCONFINED_LOG" # Log details to specific file
    log_action "--------------------------------------------------"
    log_action "Services running as 'unconfined_service_t' might bypass fine-grained SELinux controls."
    log_action "It is strongly recommended to investigate these services and apply specific SELinux policies."
    chmod 600 "$UNCONFINED_LOG" # Secure the log file

    # Step 3: Ask administrator (optional logging already done)
    read -p "Details logged to $UNCONFINED_LOG. Do you want to be reminded about investigation steps? (y/N): " remind

    if [[ "$remind" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Investigation Steps:"
        echo "1. Identify the package providing the service (e.g., 'rpm -qf /path/to/executable')."
        echo "2. Check if an SELinux policy module exists for this service (e.g., 'semodule -l | grep <service_name>')."
        echo "3. Search for existing boolean settings ('getsebool -a | grep <service_name>')."
        echo "4. Use 'audit2allow' on relevant AVC denial messages in '/var/log/audit/audit.log' to generate custom policy rules if necessary."
        echo "5. Consult distribution documentation and SELinux resources (e.g., Red Hat SELinux guide)."
        echo ""
    fi
    log_action "Unconfined services require investigation. See $UNCONFINED_LOG."
    exit 1 # Exit with warning status
fi
