#!/bin/bash
#===============================
# Defenys: Main System Hardening Toolkit
# This script provides a menu-driven interface to run various
# system hardening and auditing scripts.
#===============================

# --- Configuration ---
# Set the path to the individual scripts relative to this script
SCRIPT_DIR="/opt/defenys/scripts"
AUDIT_LOG="/var/log/security_hardening.log"
# --- End Configuration ---

# --- Colors for better output ---
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color
# --- End Colors ---

# Function to log messages to a central file
log_action() {
    echo "$(date): $1" | tee -a "$AUDIT_LOG"
}

# Check if the script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_action "${RED}Error: This script must be run as root. Exiting.${NC}"
        exit 1
    fi
}

# Display the main menu
show_menu() {
    clear
    echo "====================================================="
    echo " Defensys: Linux System Hardening & Auditing Toolkit"
    echo "====================================================="
    echo "Please choose a task to perform:"
    echo ""
    echo "  1) Enforce Password Policy"
    echo "  2) Harden Network Parameters (sysctl)"
    echo "  3) Secure GRUB Bootloader Password"
    echo "  4) Secure GRUB File Permissions"
    echo "  5) Configure Logrotate for Secure Logs"
    echo "  6) Perform AIDE File Integrity Check"
    echo "  7) Run a Lynis System Audit"
    echo "  8) Audit for Unconfined SELinux Services"
    echo "  9) Run a Process Audit (Interactive)"
    echo " 10) Check Pwned Password"
    echo ""
    echo "  0) Exit"
    echo ""
    echo "====================================================="
    read -rp "Enter your choice [0-10]: " choice
}

# Execute the selected script
run_script() {
    local script_name=""
    case "$1" in
        1) script_name="enforce_password_policy.sh" ;;
        2) script_name="network_hardening_sysctl.sh" ;;
        3) script_name="secure_grub_password.sh" ;;
        4) script_name="secure_grub_permissions.sh" ;;
        5) script_name="logrotate_secure.sh" ;;
        6) script_name="aide_check_install.sh" ;;
        7) script_name="lynis.sh" ;;
        8) script_name="selinux_unconfined_check.sh" ;;
        9) script_name="process_audit_interactive.sh" ;;
        10) script_name="check_pwned_password.sh" ;;
        0) echo "Exiting. Stay secure!"; exit 0 ;;
        *) echo "Invalid choice. Please try again." ; return 1 ;;
    esac

    # Check if the script file exists
    if [ -f "${SCRIPT_DIR}/${script_name}" ]; then
        log_action "Executing script: ${script_name}"
        # Execute the script directly
        "${SCRIPT_DIR}/${script_name}"
    else
        log_action "${RED}Error: Script '${script_name}' not found at '${SCRIPT_DIR}'.${NC}"
    fi

    echo ""
    read -n 1 -s -r -p "Press any key to return to the menu..."
}

# Main loop
main() {
    check_root
    while true; do
        show_menu
        if [ -n "$choice" ]; then
            run_script "$choice"
        fi
    done
}

# Call the main function
main
