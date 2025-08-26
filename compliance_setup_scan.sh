#!/bin/bash
#===============================
# System Compliance Hardening & OpenSCAP Scan Script
# Installs tools, applies basic hardening, and runs an OpenSCAP scan.
#===============================

# --- Configuration ---
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

log_action "Starting System Integrity & Compliance Hardening..."

# 1. Install essential security tools
log_action "Ensuring OpenSCAP tools are installed (scap-security-guide, openscap-scanner)..."
if ! rpm -q scap-security-guide &>/dev/null || ! rpm -q openscap-scanner &>/dev/null; then
    log_action "Installing OpenSCAP tools..."
    if ! dnf install -y scap-security-guide openscap-scanner; then
        log_action "Error: Failed to install required OpenSCAP packages. Exiting."
        exit 1
    fi
     log_action "OpenSCAP tools installed."
else
    log_action "OpenSCAP tools are already installed."
fi

# 2. Check Secure Boot Validation (Informational)
log_action "Checking Secure Boot status (mokutil)..."
if command -v mokutil &> /dev/null; then
    mokutil --sb-state
    # Enabling validation requires manual interaction at boot. Inform the user.
    log_action "Note: Enabling Secure Boot validation (mokutil --enable-validation) requires manual steps during reboot."
else
    log_action "mokutil not found, skipping Secure Boot check."
fi

# 3. Disable USB Storage (Use with extreme caution!)
USB_BLACKLIST_FILE="/etc/modprobe.d/usb-storage-blacklist.conf"
read -p "❓ Do you want to disable USB storage via modprobe (blocks most USB drives)? (y/N): " disable_usb
if [[ "$disable_usb" =~ ^[Yy]$ ]]; then
    log_action "Attempting to disable USB storage access via $USB_BLACKLIST_FILE..."
    if ! grep -q "install usb_storage /bin/false" "$USB_BLACKLIST_FILE" 2>/dev/null; then
         echo "# Disabled by compliance script $(date)" >> "$USB_BLACKLIST_FILE"
         echo "install usb_storage /bin/false" >> "$USB_BLACKLIST_FILE"
         log_action "USB storage module blacklisted. Reboot may be required."
    else
         log_action "USB storage already appears blacklisted in $USB_BLACKLIST_FILE."
    fi
else
    log_action "Skipping USB storage disable."
fi

# 4. Ensure SELinux is in Enforcing Mode
log_action "Ensuring SELinux is in Enforcing mode..."
if command -v sestatus &> /dev/null; then
    if sestatus | grep -q "disabled"; then
        log_action " Error: SELinux is disabled in the kernel. Manual configuration and reboot required to enable."
        # Provide guidance or link to docs if possible
    elif sestatus | grep "Current mode:" | grep -q "permissive"; then
        log_action "SELinux is permissive. Attempting to set to enforcing..."
        if setenforce 1; then
            # Persist the change in the config file
            if ! sed -i 's/^\s*SELINUX=\s*permissive/SELINUX=enforcing/' /etc/selinux/config; then
                 log_action "Error: Failed to update /etc/selinux/config to enforcing."
            else
                 log_action "SELinux set to enforcing mode temporarily and configuration updated."
            fi
        else
            log_action "Error: Failed to set SELinux to enforcing mode using setenforce 1."
        fi
    elif sestatus | grep "Current mode:" | grep -q "enforcing"; then
        log_action "SELinux is already in enforcing mode."
        # Ensure config file matches just in case
         if ! grep -q "^\s*SELINUX=\s*enforcing" /etc/selinux/config; then
              sed -i 's/^\s*SELINUX=.*$/SELINUX=enforcing/' /etc/selinux/config
              log_action "Updated /etc/selinux/config to ensure persistence."
         fi
    fi
else
     log_action "'sestatus' command not found. Cannot verify or set SELinux mode."
fi

log_action "Base System Integrity & Compliance Hardening Steps Applied!"

# 5. Prompt admin to perform compliance scan
read -p "❓ Would you like to perform an OpenSCAP system compliance scan now? (y/N): " choice

if [[ "$choice" =~ ^[Yy]$ ]]; then
    log_action "Starting OpenSCAP compliance scan..."
    # Find the main SSG XCCDF file (adjust path/pattern if needed)
    # Prefer datastream file if available, otherwise fallback to xccdf
    SSG_CONTENT_FILE=$(find /usr/share/xml/scap/ssg/content/ -name 'ssg-*-ds.xml' -o -name 'ssg-*-xccdf.xml' | head -n 1)

    if [[ -z "$SSG_CONTENT_FILE" ]]; then
        log_action "Error: Could not find SCAP Security Guide content file (ds.xml or xccdf.xml). Cannot scan."
        exit 1
    fi
    log_action "Using SCAP content file: $SSG_CONTENT_FILE"

    log_action "Listing available compliance profiles..."
    sleep 1 # Brief pause
    oscap info "$SSG_CONTENT_FILE" || { log_action "Error running 'oscap info'."; exit 1; }

    echo ""
    log_action "Common profiles (verify exact ID from list above):"
    log_action "  - Standard: xccdf_org.ssgproject.content_profile_standard"
    log_action "  - CIS Benchmark: xccdf_org.ssgproject.content_profile_cis"
    # Add others as needed

    read -p "➡️ Enter the exact profile ID to use for scanning (e.g., xccdf_org.ssgproject.content_profile_standard): " profile

    if [[ -z "$profile" ]]; then
         log_action "No profile selected. Aborting scan."
         exit 1
    fi

    # Define report paths
    timestamp=$(date +%F_%T)
    report_basename="system_compliance_report_${profile}_${timestamp}"
    html_report="/tmp/${report_basename}.html"
    results_xml="/tmp/${report_basename}_results.xml" # Save results XML too

    log_action "Starting scan with profile '$profile'. This may take time..."
    log_action "HTML Report will be generated at: $html_report"
    log_action "Results XML will be generated at: $results_xml"

    # Run the scan as root, generate HTML report and results XML
    if oscap xccdf eval --profile "$profile" --results "$results_xml" --report "$html_report" "$SSG_CONTENT_FILE"; then
        log_action "Compliance scan completed successfully!"

        # Determine target directory for report (user's home or root's home)
        target_dir="/root" # Default for root
        if [[ -n "$SUDO_USER" ]] && [[ -d "/home/$SUDO_USER" ]]; then
             target_dir="/home/$SUDO_USER"
        fi

        final_html_report="${target_dir}/${report_basename}.html"
        final_results_xml="${target_dir}/${report_basename}_results.xml"

        log_action "Copying reports to $target_dir..."
        cp "$html_report" "$final_html_report"
        cp "$results_xml" "$final_results_xml"

        # Set ownership if copied to user's home
        if [[ "$target_dir" != "/root" ]]; then
            chown "$SUDO_USER:$SUDO_USER" "$final_html_report" "$final_results_xml"
        fi

        log_action "Reports available at:"
        log_action "  HTML: $final_html_report"
        log_action "  XML Results: $final_results_xml"
        log_action "To open the HTML report (if graphical env available): xdg-open \"$final_html_report\""
    else
        log_action "Compliance scan failed. Check output above."
        log_action "Partial reports might be available in /tmp."
        exit 1
    fi
else
    log_action "Skipping compliance scan as per user choice."
fi

log_action "System Hardening & Compliance Script Completed!"
