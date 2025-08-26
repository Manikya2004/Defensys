#!/bin/bash
#===============================
# Logrotate Configuration: Secure System Logs
# Configures rotation for /var/log/secure (common log for auth/sudo).
#===============================

# --- Configuration ---
AUDIT_LOG="/var/log/security_hardening.log" # Central log for hardening actions
LOGROTATE_TARGET_LOG="/var/log/secure"      # Log file to rotate
LOGROTATE_CONF_FILE="/etc/logrotate.d/secure-logs" # Config file name
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

log_action "Configuring log rotation for $LOGROTATE_TARGET_LOG..."

# Define the logrotate configuration content using printf for safety
LOGROTATE_CONF_CONTENT=$(printf "%s\n" \
"$LOGROTATE_TARGET_LOG {" \
"    # Rotated by secure_logrotate.sh script" \
"    weekly          # Rotate logs every week" \
"    rotate 4        # Keep the last 4 rotated logs" \
"    compress        # Compress older logs (e.g., secure.1.gz)" \
"    delaycompress   # Don't compress the most recent rotated log immediately" \
"    missingok       # Ignore errors if the log file is missing" \
"    notifempty      # Do not rotate if the log is empty" \
"    sharedscripts   # Run postrotate script once, not for every log matched" \
"    postrotate" \
"        # Signal relevant daemons to use the new log file" \
"        /usr/bin/systemctl kill -s HUP rsyslogd 2>/dev/null || true" \
"        /usr/bin/systemctl kill -s HUP auditd 2>/dev/null || true" \
"    endscript" \
"    create 0600 root root # Ensure proper permissions for new log files" \
"}" \
)

# Write the configuration to /etc/logrotate.d/
log_action "Writing configuration to $LOGROTATE_CONF_FILE..."
if echo "$LOGROTATE_CONF_CONTENT" > "$LOGROTATE_CONF_FILE"; then
    chmod 644 "$LOGROTATE_CONF_FILE" # Set standard permissions
    log_action "✅ Log rotation configured successfully in $LOGROTATE_CONF_FILE."

    # Test logrotate configuration syntax
    log_action "Testing logrotate configuration syntax..."
    if logrotate -d "$LOGROTATE_CONF_FILE"; then
         log_action "✅ Logrotate configuration test successful."
    else
         log_action "⚠️ Logrotate configuration test reported issues (see output above)."
         # Don't exit, but warn the user
    fi
else
    log_action "❌ Error: Failed to write logrotate configuration to $LOGROTATE_CONF_FILE."
    exit 1
fi
 log_action "Logrotate configuration script finished."
aide_check_install.sh (Improved: Refined functions, better logging, clearer output, fixed AIDE check logic)#!/bin/bash
#===============================
# AIDE Integrity Check Script
# Installs, initializes, and runs AIDE file integrity checks.
#===============================

# --- Configuration ---
LOG_DIR="/var/log/aide"
AUDIT_LOG="/var/log/security_hardening.log" # Optional central log
AIDE_DB="/var/lib/aide/aide.db.gz"
AIDE_NEW_DB="/var/lib/aide/aide.db.new.gz"
# --- End Configuration ---

# --- Colors ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[1;34m"
NC="\033[0m" # No Color
# --- End Colors ---

# Function to log messages to console and potentially central log
log_action() {
    local message="$1"
    local log_level="${2:-INFO}" # Default to INFO
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    echo -e "$message" # Always print colored message to console

    # Log plain message to central audit log if defined
    if [ -n "$AUDIT_LOG" ]; then
         echo "$timestamp [$log_level] $(echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g')" >> "$AUDIT_LOG"
    fi
}

# Function to log specifically to the AIDE check log
log_aide_check() {
    local message="$1"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    # Ensure log file is set up before trying to write
    if [ -n "$AIDE_CHECK_LOG" ]; then
         echo "$timestamp: $message" >> "$AIDE_CHECK_LOG"
    fi
}


# --- Functions ---
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_action "${RED}[✗] Error: This script must be run as root.${NC}" "ERROR"
        exit 1
    fi
}

setup_logging() {
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    if [ $? -ne 0 ]; then
        log_action "${RED}[✗] Error: Failed to create log directory $LOG_DIR.${NC}" "ERROR"
        exit 1
    fi
    chmod 700 "$LOG_DIR"

    # Define AIDE check log file path *after* ensuring directory exists
    AIDE_CHECK_LOG="$LOG_DIR/aide-check-$(date +%F_%T).log"
    touch "$AIDE_CHECK_LOG"
    chmod 600 "$AIDE_CHECK_LOG"
    log_action "${BLUE}[i] AIDE check results will be logged to: $AIDE_CHECK_LOG${NC}" "INFO"
}

install_aide() {
    if ! command -v aide &> /dev/null; then
        log_action "${RED}[✗] AIDE is not installed.${NC}" "WARN"
        log_action "${BLUE}[>] Attempting to install AIDE...${NC}" "INFO"
        local install_cmd=""
        if command -v dnf &> /dev/null; then install_cmd="dnf install -y aide";
        elif command -v apt-get &> /dev/null; then install_cmd="apt-get update && apt-get install -y aide";
        else
            log_action "${RED}[✗] Error: Unsupported package manager. Please install AIDE manually.${NC}" "ERROR"
            exit 1
        fi

        if ! $install_cmd; then
             log_action "${RED}[✗] Error: AIDE installation failed.${NC}" "ERROR"
             exit 1
        else
             log_action "${GREEN}[✓] AIDE installed successfully.${NC}" "INFO"
        fi
    else
        log_action "${GREEN}[✓] AIDE is already installed.${NC}" "INFO"
    fi
}

initialize_aide() {
    log_action "${BLUE}[?] Checking for existing AIDE database ($AIDE_DB)...${NC}" "INFO"
    if [ ! -f "$AIDE_DB" ]; then
        log_action "${BLUE}[>] AIDE database not found.${NC}" "INFO"
        log_action "${BLUE}[>] Running AIDE initialization (this may take a significant amount of time)...${NC}" "INFO"
        # Run init, redirect output to the specific AIDE log
        if aide --init >> "$AIDE_CHECK_LOG" 2>&1; then
            log_aide_check "AIDE initialization scan completed."
            log_action "${GREEN}[✓] AIDE initialization scan finished.${NC}" "INFO"
            if [ -f "$AIDE_NEW_DB" ]; then
                log_action "${BLUE}[>] Moving new database $AIDE_NEW_DB to $AIDE_DB...${NC}" "INFO"
                if mv "$AIDE_NEW_DB" "$AIDE_DB"; then
                    chmod 600 "$AIDE_DB" # Ensure proper permissions
                    log_action "${GREEN}[✓] AIDE database initialized successfully.${NC}" "INFO"
                    log_aide_check "Moved $AIDE_NEW_DB to $AIDE_DB."
                else
                     log_action "${RED}[✗] Error: Failed to move $AIDE_NEW_DB to $AIDE_DB.${NC}" "ERROR"
                     log_aide_check "Error moving new database."
                     exit 1
                fi
            else
                log_action "${RED}[✗] Error: AIDE init ran, but the new database ($AIDE_NEW_DB) was not found.${NC}" "ERROR"
                log_aide_check "New database $AIDE_NEW_DB not found after successful init."
                exit 1
            fi
        else
            log_action "${RED}[✗] Error: AIDE initialization failed. Check AIDE configuration (/etc/aide.conf) and review $AIDE_CHECK_LOG.${NC}" "ERROR"
            log_aide_check "AIDE initialization failed. Check /etc/aide.conf."
            exit 1
        fi
    else
         log_action "${GREEN}[✓] Existing AIDE database found at $AIDE_DB.${NC}" "INFO"
         log_aide_check "Existing database found: $AIDE_DB"
    fi
}

run_aide_check() {
    # Ensure DB exists before prompting for check
    if [ ! -f "$AIDE_DB" ]; then
         log_action "${RED}[✗] Cannot run check: AIDE database ($AIDE_DB) does not exist. Initialize first.${NC}" "ERROR"
         return 1
    fi

    read -p $'\n❓ Do you want to run an AIDE integrity check now? (y/N): ' answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        log_action "\n${BLUE}[>] Running AIDE integrity check (comparing filesystem to $AIDE_DB)...${NC}" "INFO"
        log_aide_check "Starting AIDE integrity check."

        # Run the check, capture exit code, redirect output to log
        aide --check >> "$AIDE_CHECK_LOG" 2>&1
        local exit_code=$?
        log_aide_check "AIDE check finished with exit code: $exit_code"

        # Interpret exit code (consult `man aide` for specifics, may vary slightly)
        # 0: No differences found
        # 1: Differences found
        # >1: Error (config error, file error, etc.)
        if [ $exit_code -eq 0 ]; then
             log_action "${GREEN}[✓] System integrity verified. No changes detected.${NC}" "INFO"
             log_aide_check "Result: No differences found."
        elif [ $exit_code -gt 0 ] && [ $exit_code -le 7 ]; then # Bits 0-2 indicate changes
             log_action "${RED}[!] ALERT: Changes detected in filesystem!${NC}" "WARN"
             log_aide_check "Result: Differences found between database and filesystem."
             log_action "${BLUE}[i] Review the full report for details: $AIDE_CHECK_LOG${NC}" "INFO"
        else # Assume error for other non-zero exit codes
             log_action "${RED}[!] ERROR: AIDE check encountered an error (exit code: $exit_code).${NC}" "ERROR"
             log_aide_check "Result: Error occurred during check."
             log_action "${BLUE}[i] Review the AIDE log for details: $AIDE_CHECK_LOG${NC}" "INFO"
             return 1 # Indicate error
        fi
    else
        log_action "${BLUE}[x] Skipping AIDE check as requested.${NC}" "INFO"
        log_aide_check "User skipped AIDE check."
    fi
    return 0 # Indicate success or skipped check
}

# --- Main Execution ---
clear
echo -e "${BLUE}🔐 AIDE Integrity Check Script — Linux Hardening${NC}"
echo "---------------------------------------------"

check_root
setup_logging # Sets up $AIDE_CHECK_LOG
install_aide
initialize_aide # Check or initialize DB
run_aide_check  # Ask and run check

echo "---------------------------------------------"
log_action "${BLUE}Script finished.${NC}" "INFO"
