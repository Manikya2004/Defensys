#!/bin/bash
# ============================
# Linux Process Audit Script (User-Interactive)
# Provides options to list idle, sleeping, or zombie processes.
# ============================

# --- Configuration ---
LOGFILE="/var/log/process_audit_$(date +%F).log"
AUDIT_LOG="/var/log/security_hardening.log" # Optional central log
# --- End Configuration ---

# Function to log messages to console and optionally central log
log_action() {
    local message="$1"
    local log_level="${2:-INFO}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    echo "$message" # Always print to console

    # Log plain message to central audit log if defined
    if [ -n "$AUDIT_LOG" ]; then
         echo "$timestamp [$log_level] $(echo "$message" | sed 's/\x1b\[[0-9;]*m//g')" >> "$AUDIT_LOG"
    fi
     # Also log to the specific process audit log
     echo "$timestamp [$log_level] $(echo "$message" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOGFILE"
}


# Check if running as root (needed for killing parent processes)
if [ "$EUID" -ne 0 ]; then
  echo "⚠️ Warning: Running as non-root. Killing parent processes (option 3) will not be possible."
fi

# --- Main Menu ---
clear
echo "==============================="
echo " Linux Process Audit Menu"
echo "==============================="
echo "1. List Idle Processes (0.0% CPU)"
echo "2. List Sleeping Processes (Status 'S')"
echo "3. List Zombie Processes (Status 'Z')"
echo "4. Exit"
echo "==============================="

read -p "Enter your choice [1-4]: " choice

# Setup log file for this run
touch "$LOGFILE" && chmod 600 "$LOGFILE"

log_action "Process Audit Started (Choice: $choice)" "INFO"
log_action "--------------------------------------" "INFO"

case "$choice" in
    1)
        log_action "[1] Idle Processes (CPU% == 0.0):" "INFO"
        log_action "--------------------------------------" "INFO"
        printf "%-10s %-15s %-8s %-8s %s\n" "PID" "USER" "CPU%" "MEM%" "COMMAND" | tee -a "$LOGFILE"
        # Use ps efficiently, sort by PID after filtering
        ps -eo pid,user,%cpu,%mem,comm --no-headers | awk '$3 == 0.0 {printf "%-10s %-15s %-8s %-8s %s\n", $1, $2, $3, $4, $5}' | sort -k1n | tee -a "$LOGFILE"
        log_action "--------------------------------------" "INFO"
        ;;
    2)
        log_action "[2] Sleeping Processes (Status 'S'):" "INFO"
        log_action "--------------------------------------" "INFO"
        printf "%-10s %-5s %s\n" "PID" "STAT" "COMMAND" | tee -a "$LOGFILE"
        # Match only 'S' state at beginning of status field
        ps -eo pid,stat,cmd --no-headers | awk '$2 ~ /^S/ {printf "%-10s %-5s %s\n", $1, $2, substr($0, index($0,$3))}' | tee -a "$LOGFILE"
        log_action "--------------------------------------" "INFO"
        ;;
    3)
        log_action "[3] Zombie Processes (Status 'Z'):" "INFO"
        log_action "--------------------------------------" "INFO"
        # Get zombie processes including PPID (Parent PID)
        ZOMBIE_PROCESSES=$(ps -eo pid,ppid,stat,comm --no-headers | awk '$3 ~ /^Z/ {print}')

        if [ -z "$ZOMBIE_PROCESSES" ]; then
            log_action "✅ No zombie processes found." "INFO"
        else
            printf "%-10s %-10s %-5s %s\n" "PID" "PPID" "STAT" "COMMAND" | tee -a "$LOGFILE"
            echo "$ZOMBIE_PROCESSES" | awk '{printf "%-10s %-10s %-5s %s\n", $1, $2, $3, $4}' | tee -a "$LOGFILE"
            log_action "--------------------------------------" "INFO"
            log_action "ℹ️ Note: Zombie processes are already terminated but remain in the process table" "INFO"
            log_action "   until their parent process reads their exit status (via wait())." "INFO"
            log_action "   They consume minimal resources but indicate a potential issue in the parent." "INFO"
            log_action "   To clear zombies, the PARENT process (PPID) must be signaled or terminated." "INFO"

            # Ask if user wants to attempt killing the PARENT processes
            read -p "❓ Attempt to send SIGCHLD (signal child exited) to parent processes? (Less intrusive) (y/N): " signal_choice
            if [[ "$signal_choice" =~ ^[Yy]$ ]]; then
                 if [ "$EUID" -ne 0 ]; then
                     log_action "❌ Error: Cannot send signals as non-root user." "ERROR"
                 else
                     log_action "[Action] Attempting to send SIGCHLD to parent processes..." "INFO"
                     ZOMBIE_PPIDS=$(echo "$ZOMBIE_PROCESSES" | awk '{print $2}' | sort -u)
                     for ppid in $ZOMBIE_PPIDS; do
                         if ps -p "$ppid" > /dev/null && [ "$ppid" -ne 1 ]; then
                             log_action "  -> Sending SIGCHLD to parent PID: $ppid" "INFO"
                             if kill -s SIGCHLD "$ppid"; then log_action "     Signal sent." "DEBUG"; else log_action "     Failed to send signal." "WARN"; fi
                         fi
                     done
                     log_action "ℹ️ Check if zombies were cleared after signaling parents." "INFO"
                 fi
            else
                 read -p "❓ Attempt to KILL the PARENT processes? (Use with extreme caution!) (y/N): " kill_choice
                 if [[ "$kill_choice" =~ ^[Yy]$ ]]; then
                      if [ "$EUID" -ne 0 ]; then
                          log_action "❌ Error: Cannot kill processes as non-root user." "ERROR"
                      else
                          log_action "[Action] Attempting to KILL parent processes (SIGKILL)..." "WARN"
                          ZOMBIE_PPIDS=$(echo "$ZOMBIE_PROCESSES" | awk '{print $2}' | sort -u)
                          for ppid in $ZOMBIE_PPIDS; do
                              if ps -p "$ppid" > /dev/null && [ "$ppid" -ne 1 ]; then
                                  parent_cmd=$(ps -p $ppid -o comm=)
                                  log_action "  -> Killing parent PID: $ppid (Command: $parent_cmd)" "WARN"
                                  if kill -9 "$ppid"; then log_action "     SIGKILL sent." "INFO"; else log_action "     Failed to send SIGKILL." "ERROR"; fi
                              elif [ "$ppid" -eq 1 ]; then
                                  log_action "  -> Skipping kill for parent PID 1 (init/systemd)." "INFO"
                              else
                                  log_action "  -> Parent PID $ppid not found." "INFO"
                              fi
                          done
                      fi
                 else
                     log_action "Skipping signal/kill actions for parent processes." "INFO"
                 fi
            fi
        fi
        log_action "--------------------------------------" "INFO"
        ;;
    4)
        log_action "Exiting script." "INFO"; exit 0 ;;
    *)
        log_action "Invalid choice '$choice'. Please select option 1-4." "ERROR"
        ;;
esac

log_action "Process Audit Completed." "INFO"
echo -e "\nAudit log saved to: $LOGFILE"
