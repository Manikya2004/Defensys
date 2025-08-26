#!/usr/bin/env bash

# Function to check if Lynis is installed
check_lynis() {
    if ! command -v lynis &> /dev/null; then
        echo -e "\n🔍 Lynis not found! Installing now..."
        sudo dnf install -y epel-release && sudo dnf install -y lynis
    else
        echo -e "\n✅ Lynis is already installed!"
    fi
}

# Function to check and remove stale Lynis PID file
clean_lynis_pid() {
    if [[ -f /var/run/lynis.pid ]]; then
        echo -e "\n🛠️ Removing stale Lynis PID file..."
        sudo rm -f /var/run/lynis.pid
    fi
}

# Function to run Lynis audit (visible scan)
run_lynis_audit() {
    echo -e "\n🚀 Running Lynis system audit..."
    sudo lynis audit system | tee lynis.log  # Show output & log it
    echo -e "\n✅ Audit completed!"
}

# Function to extract warnings from the Lynis report
extract_warnings() {
    echo -e "\n⚠️  Warnings Found:\n"
    grep -i "UNSAFE" lynis.log | cut -d ":" -f2- || echo "✅ No warnings found!"
}

# Function to extract security hardening suggestions from the Lynis report
extract_suggestions() {
    echo -e "\n🔐 Security Hardening Suggestions:\n"
    grep -i "SUGGESTION" lynis.log | cut -d ":" -f2- || echo "✅ No security suggestions found!"
}

# Function to show Lynis report options
show_report_options() {
    while true; do
        echo -e "\n📊 What would you like to do?"
        echo "1️⃣ Show full Lynis report"
        echo "2️⃣ Show warnings from the scan"
        echo "3️⃣ Show security hardening suggestions"
        echo "4️⃣ Show both warnings and suggestions"
        echo "5️⃣ Exit"

        read -p "➡️ Choose an option (1-5): " choice

        case $choice in
            1) cat lynis.log;;
            2) extract_warnings ;;
            3) extract_suggestions ;;
            4) extract_warnings; extract_suggestions ;;
            5) echo -e "\n👋 Exiting... Stay secure!"; exit 0 ;;
            *) echo -e "\n❌ Invalid option. Please choose again." ;;
        esac
    done
}

# Main Execution
check_lynis
clean_lynis_pid

# Ask user if they want to run an audit
read -p "🔍 Do you want to run a Lynis system audit? (y/n): " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    run_lynis_audit
    show_report_options
else
    echo -e "\n👋 Exiting... Run 'lynis audit system' manually whenever needed!"
fi

