#!/bin/bash
#===============================
# Password Policy Hardening Script
# Enforces strong password complexity, history, and aging policies.
# Uses libpwquality and PAM configuration.
#===============================

# --- Configuration ---
PWQUALITY_CONF="/etc/security/pwquality.conf"
LOGIN_DEFS="/etc/login.defs"
PAM_SYSTEM_AUTH="/etc/pam.d/system-auth"
PAM_PASSWORD_AUTH="/etc/pam.d/password-auth"
AUDIT_LOG="/var/log/security_hardening.log"

# pwquality settings (CIS recommendations, adjust as needed)
MIN_LEN=14
D_CREDIT=-1 # At least 1 digit
U_CREDIT=-1 # At least 1 uppercase
L_CREDIT=-1 # At least 1 lowercase
O_CREDIT=-1 # At least 1 special char
MIN_CLASS=4 # Require chars from 4 classes (digit, upper, lower, other)
MAX_REPEAT=2
MAX_CLASS_REPEAT=4
DIF_OK=8 # At least 8 chars different from old password
GECOS_CHECK=1
REJECT_USERNAME=1
ENFORCE_FOR_ROOT=1

# Password history
REMEMBER_PASSWORDS=5

# Password aging (days)
PASS_MAX_DAYS=90
PASS_MIN_DAYS=7
PASS_WARN_AGE=14 # Warn 14 days before expiry

# User account locking after inactivity
INACTIVE_LOCK_DAYS=35
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

log_action "Applying strict password security policies..."

# 1. Install required packages
log_action "Ensuring libpwquality and pam_pwhistory are installed..."
REQUIRED_PACKAGES=("libpwquality")
# Check if pam_pwhistory package exists (name might vary slightly)
if rpm -q pam_pwhistory &>/dev/null || apt-cache show pam_pwhistory &>/dev/null; then
    REQUIRED_PACKAGES+=("pam_pwhistory")
fi

PACKAGES_TO_INSTALL=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null && ! dpkg -s "$pkg" &>/dev/null; then
        PACKAGES_TO_INSTALL+=("$pkg")
    fi
done

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    log_action "Installing missing packages: ${PACKAGES_TO_INSTALL[*]}..."
    if command -v dnf &> /dev/null; then
        dnf install -y "${PACKAGES_TO_INSTALL[@]}"
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y "${PACKAGES_TO_INSTALL[@]}"
    else
         log_action "❌ Error: Unsupported package manager. Please install manually: ${PACKAGES_TO_INSTALL[*]}"
         exit 1
    fi
    # Verify installation
    for pkg in "${PACKAGES_TO_INSTALL[@]}"; do
         if ! rpm -q "$pkg" &>/dev/null && ! dpkg -s "$pkg" &>/dev/null; then
              log_action "❌ Error: Failed to install package '$pkg'."
              exit 1
         fi
    done
     log_action "✅ Required packages installed."
else
    log_action "✅ Required packages are already installed."
fi
USE_PAM_PWHISTORY=$(rpm -q pam_pwhistory &>/dev/null || dpkg -s pam_pwhistory &>/dev/null; echo $?)


# 2. Configure password complexity rules in pwquality.conf
log_action "Configuring password complexity in $PWQUALITY_CONF..."
# Create content using printf for clarity
printf "%s\n" \
"# Password quality configuration applied by script" \
"minlen = $MIN_LEN" \
"dcredit = $D_CREDIT" \
"ucredit = $U_CREDIT" \
"lcredit = $L_CREDIT" \
"ocredit = $O_CREDIT" \
"minclass = $MIN_CLASS" \
"maxrepeat = $MAX_REPEAT" \
"maxclassrepeat = $MAX_CLASS_REPEAT" \
"difok = $DIF_OK" \
"gecoscheck = $GECOS_CHECK" \
"reject_username = $REJECT_USERNAME" \
"enforce_for_root = $ENFORCE_FOR_ROOT" \
> "$PWQUALITY_CONF"

if [ $? -ne 0 ]; then log_action "❌ Error writing to $PWQUALITY_CONF"; exit 1; fi
chmod 600 "$PWQUALITY_CONF"
log_action "✅ Configured $PWQUALITY_CONF."

# 3. Modify PAM configuration files
# Function to safely update a PAM stack file
update_pam_file() {
    local pam_file="$1"
    log_action "Updating PAM file: $pam_file"
    if [ ! -f "$pam_file" ]; then
        log_action "⚠️ PAM file $pam_file not found. Skipping."
        return 1
    fi
    # Backup PAM file
    cp "$pam_file" "${pam_file}.bak.$(date +%F_%T)" || { log_action "❌ Error creating backup for $pam_file"; return 1; }

    # --- Enforce pwquality ---
    # Remove existing pam_pwquality.so line(s)
    sed -i '/pam_pwquality.so/d' "$pam_file"
    # Add 'requisite pam_pwquality.so' after pam_cracklib or before pam_unix
    # This ensures quality checks happen before hashing/storing
    local pwquality_line="password    requisite     pam_pwquality.so retry=3 enforce_for_root"
    if grep -q "pam_cracklib.so" "$pam_file"; then
         sed -i "/pam_cracklib.so/a $pwquality_line" "$pam_file"
    elif grep -q "password.*pam_unix.so" "$pam_file"; then
         sed -i "/password.*pam_unix.so/i $pwquality_line" "$pam_file"
    else
         # Add near beginning of password stack as fallback
         sed -i "/^password/a $pwquality_line" "$pam_file"
    fi
    log_action "  -> Added pam_pwquality.so enforcement."

    # --- Enforce password history ---
    if [ "$USE_PAM_PWHISTORY" -eq 0 ]; then
        log_action "  -> Configuring password history using pam_pwhistory (remember=$REMEMBER_PASSWORDS)..."
        # Remove remember option from pam_unix if present
        sed -i -E 's/(password\s+(sufficient|required)\s+pam_unix.so.*) remember=[0-9]+/\1/' "$pam_file"
        # Remove existing pam_pwhistory line(s)
        sed -i '/pam_pwhistory.so/d' "$pam_file"
        # Add pam_pwhistory after pam_pwquality
        local pwhistory_line="password    required      pam_pwhistory.so remember=$REMEMBER_PASSWORDS retry=3 enforce_for_root use_authtok"
         sed -i "/pam_pwquality.so/a $pwhistory_line" "$pam_file"
    else
        log_action "  -> Configuring password history using pam_unix remember option (remember=$REMEMBER_PASSWORDS)..."
        # Ensure pam_unix line exists and add/update remember option
         if grep -q "password.*pam_unix.so" "$pam_file"; then
              # Remove existing remember= option first
              sed -i -E 's/(password\s+(sufficient|required)\s+pam_unix.so.*) remember=[0-9]+/\1/' "$pam_file"
              # Add remember= option. Also ensure use_authtok is present.
              sed -i -E '/password\s+(sufficient|required)\s+pam_unix.so/ s/(pam_unix.so[^\n]*)$/\1 use_authtok remember=$REMEMBER_PASSWORDS/' "$pam_file"
         else
              log_action "⚠️ Could not find pam_unix.so line in $pam_file to set remember=$REMEMBER_PASSWORDS."
         fi
    fi
    # Ensure use_authtok is present on the pam_unix line if pwquality is used
    if grep -q "pam_pwquality.so" "$pam_file" && grep -q "password.*pam_unix.so" "$pam_file"; then
         sed -i -E '/password\s+(sufficient|required)\s+pam_unix.so/ s/(pam_unix.so[^\n]*use_authtok[^\n]*)$/\1/; t; s/(pam_unix.so[^\n]*)$/\1 use_authtok/' "$pam_file"
    fi
    log_action "✅ Successfully updated PAM file: $pam_file"
    return 0
}

# Apply PAM updates
update_pam_file "$PAM_SYSTEM_AUTH" || exit 1
update_pam_file "$PAM_PASSWORD_AUTH" || exit 1


# 4. Configure password aging policies in /etc/login.defs
log_action "Configuring password aging policies in $LOGIN_DEFS..."
# Backup login.defs
cp "$LOGIN_DEFS" "${LOGIN_DEFS}.bak.$(date +%F_%T)" || { log_action "❌ Error creating backup for $LOGIN_DEFS"; exit 1; }

# Use sed to modify existing values or append if not found
update_logindefs() {
    local key="$1"
    local value="$2"
    # Remove existing line (commented or not)
    sed -i -E "/^\s*#?\s*$key\s+/d" "$LOGIN_DEFS"
    # Append the new setting
    echo "$key $value" >> "$LOGIN_DEFS"
    log_action "  -> Set $key = $value"
}

update_logindefs "PASS_MAX_DAYS" "$PASS_MAX_DAYS"
update_logindefs "PASS_MIN_DAYS" "$PASS_MIN_DAYS"
update_logindefs "PASS_WARN_AGE" "$PASS_WARN_AGE"
log_action "✅ Configured password aging in $LOGIN_DEFS."

# 5. Set default useradd inactivity lock period
log_action "Setting default useradd password inactivity lock to $INACTIVE_LOCK_DAYS days..."
if useradd -D -f "$INACTIVE_LOCK_DAYS"; then
    log_action "✅ Set default user inactivity lock period."
else
     log_action "⚠️ Failed to set useradd default inactivity lock period."
fi

log_action "✅ Strict password security policies applied successfully!"
log_action "Review configurations: $PWQUALITY_CONF, $PAM_SYSTEM_AUTH, $PAM_PASSWORD_AUTH, $LOGIN_DEFS."
