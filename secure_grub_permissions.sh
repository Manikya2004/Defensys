#!/bin/bash
#===============================
# GRUB Security: Secure Bootloader File Permissions
# Checks and optionally fixes permissions/ownership of GRUB config files.
#===============================

# --- Configuration ---
# Define files and their expected *maximum* secure permissions (more restrictive is OK)
declare -A GRUB_FILES=(
    # BIOS Paths
    ["/boot/grub2/grub.cfg"]="600"
    ["/boot/grub2/grubenv"]="600"
    ["/boot/grub2/user.cfg"]="600" # Often used for password hash
    ["/boot/grub/grub.cfg"]="600"  # Older BIOS path

    # Common UEFI Paths (add others as needed)
    ["/boot/efi/EFI/redhat/grub.cfg"]="600"
    ["/boot/efi/EFI/centos/grub.cfg"]="600"
    ["/boot/efi/EFI/fedora/grub.cfg"]="600"
    ["/boot/efi/EFI/ubuntu/grub.cfg"]="600"
    ["/boot/efi/EFI/debian/grub.cfg"]="600"
    # Generic fallback UEFI path
    ["/boot/efi/EFI/grub/grub.cfg"]="600"
)
EXPECTED_OWNER="0" # root UID
EXPECTED_GROUP="0" # root GID
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

log_action "🔍 Checking and Securing GRUB Configuration File Permissions..."

# --- Functions ---

# Function to check file permission and ownership
# Returns 0 if secure, 1 if insecure, 2 if file not found, 3 on error
check_permissions() {
    local file="$1"
    local expected_perm_str="$2" # Expected permission string (e.g., "600")

    if [ ! -e "$file" ]; then # Use -e to check existence (handles files/symlinks)
        return 2 # Indicate file not found
    fi

    # Use stat; handle potential errors (e.g., permission denied to stat)
    stat_out=$(stat -Lc "%a %u %g" "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
         log_action "⚠️ Error stating file: $file. Check permissions."
         return 3 # Indicate error
    fi

    read -r perm uid gid <<< "$stat_out"

    # Convert expected permission string to octal number for comparison
    # Use printf for reliable octal conversion
    printf -v expected_perm_oct '%o' "$(( 8#$expected_perm_str ))"
    printf -v current_perm_oct '%o' "$(( 8#$perm ))"

    local is_secure=1 # Assume secure initially
    local reason=""

    # Check permissions: current must be <= expected (e.g., 600 is ok if expected 644, but 777 is not ok if expected 600)
    # We want permissions to be *at most* the expected value.
    if [[ "$(( 8#$perm ))" -gt "$(( 8#$expected_perm_str ))" ]]; then
         is_secure=0
         reason+="Permissions '$perm' are too permissive (expected '$expected_perm_str' or less); "
    fi
    # Check owner
    if [[ "$uid" -ne "$EXPECTED_OWNER" ]]; then
         is_secure=0
         reason+="Owner UID is '$uid' (expected '$EXPECTED_OWNER'/root); "
    fi
    # Check group
    if [[ "$gid" -ne "$EXPECTED_GROUP" ]]; then
         is_secure=0
         reason+="Group GID is '$gid' (expected '$EXPECTED_GROUP'/root); "
    fi

    if [[ $is_secure -eq 1 ]]; then
        log_action "✅ $file has secure permissions ($perm) and ownership (root:root)."
        return 0 # Indicate success
    else
        log_action "⚠️ $file has insecure configuration: ${reason%%; }" # Log reasons
        return 1 # Indicate failure (insecure)
    fi
}

# Function to remediate permissions
fix_permissions() {
    local file="$1"
    local expected_perm="$2" # e.g., 600

    log_action "🔧 Attempting to fix permissions for $file (setting owner root:root, perms $expected_perm)..."
    chown "${EXPECTED_OWNER}:${EXPECTED_GROUP}" "$file"
    local chown_status=$?
    chmod "$expected_perm" "$file"
    local chmod_status=$?

    if [[ $chown_status -eq 0 && $chmod_status -eq 0 ]]; then
         # Verify after fixing
         if check_permissions "$file" "$expected_perm" >/dev/null; then # Recheck silently
             log_action "   -> ✅ Remediation successful for $file."
             return 0
         else
             log_action "   -> ⚠️ Remediation applied but verification failed for $file. Check manually."
             return 1
         fi
    else
         log_action "   -> ❌ Remediation FAILED for $file (chown exit: $chown_status, chmod exit: $chmod_status). Check manually."
         return 1
    fi
}

# --- Main Logic ---
PERMISSION_ISSUES_FOUND=0
files_to_fix=() # Array to store files needing remediation

# Iterate through the defined files
log_action "Checking permissions for potential GRUB files..."
for file in "${!GRUB_FILES[@]}"; do
    expected_perm=${GRUB_FILES[$file]}
    check_permissions "$file" "$expected_perm" # Log output handled by function
    result_code=$?

    if [[ $result_code -eq 1 ]]; then # Insecure configuration found
        PERMISSION_ISSUES_FOUND=1
        files_to_fix+=("$file:$expected_perm") # Store file:perm for fixing
    elif [[ $result_code -eq 3 ]]; then # Error during check
         PERMISSION_ISSUES_FOUND=1 # Treat error as needing attention
         # Don't add to files_to_fix automatically, requires manual check
         log_action "   -> Manual investigation required for $file due to check error."
    fi
    # Ignore result_code 2 (file not found) - this is expected for some paths
done

# Ask for remediation if issues were found
if [[ $PERMISSION_ISSUES_FOUND -eq 1 ]]; then
    echo # Add a newline for clarity before prompt
    if [ ${#files_to_fix[@]} -gt 0 ]; then
         log_action "⚠️ Insecure GRUB file configurations detected."
         read -rp "❓ Would you like to automatically attempt to fix them? (y/N): " response
         case "$response" in
             [Yy]*)
                 log_action "Applying remediation..."
                 local all_fixed=1
                 for item in "${files_to_fix[@]}"; do
                      file_to_fix="${item%%:*}" # Extract file path
                      perm_to_set="${item##*:}" # Extract permission
                      if ! fix_permissions "$file_to_fix" "$perm_to_set"; then
                           all_fixed=0
                      fi
                 done
                 if [ $all_fixed -eq 1 ]; then
                      log_action "✅ Remediation attempt finished for all identified insecure files."
                 else
                      log_action "⚠️ Remediation attempt finished, but some fixes failed or require verification. Review output."
                 fi
                 ;;
             *)
                 log_action "❌ Remediation skipped by administrator. Please fix permissions manually."
                 exit 1
                 ;;
         esac
    else
         log_action "⚠️ Errors occurred during permission checks. No automatic remediation possible. Please review logs and investigate manually."
         exit 1
    fi
else
    log_action "✅ All checked GRUB bootloader files have secure permissions and ownership."
fi

log_action "GRUB permission check script finished."
exit 0
