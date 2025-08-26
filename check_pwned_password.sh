#!/bin/bash
#===============================
# Pwned Password Check Script
# Checks if a given password appears in the Have I Been Pwned database.
# Usage: ./check_pwned_password.sh <password-to-check>
#===============================

# --- Colors ---
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color
# --- End Colors ---

# --- Functions ---
usage() {
    echo "Usage: $0 <password-to-check>"
    echo "Example: $0 'MySecretP@ssw0rd'"
    echo "Exit Codes:"
    echo "  0: Password not found in HIBP (appears safe)"
    echo "  1: Usage error or tool dependency missing"
    echo "  2: Password FOUND in HIBP (compromised)"
    echo "  3: API connection error"
}

# --- Main Script ---

# Check if a password argument is provided
if [ -z "$1" ]; then
    usage
    exit 1
fi
candidate_password="$1"

# Check for required tools
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: 'curl' command not found. Please install curl.${NC}"
    exit 1
fi
if ! command -v sha1sum &> /dev/null; then
    echo -e "${RED}Error: 'sha1sum' command not found. Please install coreutils.${NC}"
    exit 1
fi
if ! command -v awk &> /dev/null; then
    echo -e "${RED}Error: 'awk' command not found. Please install gawk or nawk.${NC}"
    exit 1
fi
 if ! command -v grep &> /dev/null; then
    echo -e "${RED}Error: 'grep' command not found. Please install grep.${NC}"
    exit 1
fi


# Generate SHA-1 hash (uppercase, no newline)
full_hash=$(printf "%s" "$candidate_password" | sha1sum | awk '{print toupper($1)}')
if [ -z "$full_hash" ]; then
     echo -e "${RED}Error: Failed to generate SHA-1 hash.${NC}"
     exit 1
fi

# Extract prefix (first 5 chars) and suffix (rest)
prefix=${full_hash:0:5}
suffix=${full_hash:5}

# Query the HIBP Pwned Passwords API (v3)
api_url="https://api.pwnedpasswords.com/range/$prefix"
echo "Checking password against Have I Been Pwned database..."
echo "(Querying API for hash prefix: $prefix)"

# Use curl: -s silent, -H User-Agent, --fail to exit non-zero on HTTP errors >= 400
response=$(curl --fail -s -H "User-Agent: PwnedPasswordCheckScript/1.0" "$api_url")
curl_exit_code=$?

# Check curl exit status
if [ $curl_exit_code -ne 0 ]; then
    # Specific check for 404 (prefix not found - which is good)
    # Note: curl --fail returns 22 for 4xx errors. We need to check the response content if possible,
    # but if the request truly failed (network error, etc.), response will be empty.
    # A simpler check is just the exit code. If it's non-zero, assume failure or not found.
    # If the API guarantees a 404 response body is empty, this check is okay.
    # Let's refine based on typical API behavior: 404 means prefix not found.
     # We need a way to differentiate 404 from other errors. Let's get HTTP status code.
     http_code=$(curl -o /dev/null -s -w "%{http_code}" -H "User-Agent: PwnedPasswordCheckScript/1.0" "$api_url")

     if [ "$http_code" == "404" ]; then
          echo -e "${GREEN}✅ Password hash prefix not found in the HIBP database.${NC}"
          echo "(Password appears safe according to HIBP)"
          exit 0
     else
          echo -e "${RED}Error: Failed to connect to the HIBP API ($api_url). HTTP status: $http_code${NC}"
          echo "Please check your internet connection or the API status."
          exit 3 # Specific exit code for API error
     fi
fi

# Check if the suffix appears in the response (case should match as hash is uppercase)
# Response format is SUFFIX:COUNT per line
match=$(echo "$response" | grep -E "^${suffix}:")

if [ -n "$match" ]; then
    pwn_count=$(echo "$match" | cut -d: -f2)
    echo "-----------------------------------------------------"
    echo -e "${RED}⚠️ WARNING: This password has been pwned!${NC}"
    echo "-----------------------------------------------------"
    echo "This password's hash was found in the Have I Been Pwned database."
    echo "It has appeared in data breaches at least ${YELLOW}$pwn_count${NC} times."
    echo -e "${RED}It is strongly recommended to choose a different, unique password.${NC}"
    exit 2 # Exit code 2 for pwned password
else
    echo "-----------------------------------------------------"
    echo -e "${GREEN}✅ Password hash prefix was found, but the specific suffix ($suffix) was NOT.${NC}"
    echo "-----------------------------------------------------"
    echo "(Password appears safe according to HIBP)"
    exit 0 # Exit code 0 for safe password
fi
