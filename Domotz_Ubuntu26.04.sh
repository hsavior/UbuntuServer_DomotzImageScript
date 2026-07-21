#!/bin/bash

set -euo pipefail

echo "------------------------------------------------------------"
echo "This script will perform the following actions:"
echo "1. Update System and install key packages"
echo "2. Enable automatic security updates"
echo "3. (Optional) Enable automatic reboot after kernel/security updates"
echo "4. Load the 'tun' module if not already loaded"
echo "5. Install Domotz Pro agent via Snap Store"
echo "6. Grant permissions to Domotz Pro agent"
echo "7. Allow port 3000 in UFW"
echo "8. Configure netplan for DHCP on attached NICs"
echo "9. Resolve VPN on Demand issue with DNS"
echo "10. Disable cloud-init's network configuration"
echo "11. Disable IPv6 at the kernel level"
echo "------------------------------------------------------------"
echo "Disclaimer:"
echo
echo "1. Purpose: This script is designed for a fresh installation of Ubuntu Server 24.04 LTS or 26.04 LTS."
echo "2. By proceeding, you confirm that:"
echo "   - The script will modify system configurations and install necessary packages."
echo "   - It may update system files and settings as per its instructions."
echo "   - Using this script on an already configured system may lead to unexpected behavior."
echo "3. Responsibility: You are responsible for any consequences resulting from running this script."
echo
read -p "Type 'yes' to proceed: " confirmation1
if [ "$confirmation1" != "yes" ]; then
    echo "Confirmation not received. Exiting script."
    exit 1
fi
echo "------------------------------------------------------------"

echo "Please confirm again to proceed."
read -p "Type 'yes' to proceed: " confirmation2
if [ "$confirmation2" != "yes" ]; then
    echo "Confirmation not received. Exiting script."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

step_message() {
    echo "------------------------------------------------------------"
    echo "Step $1: $2"
    echo "------------------------------------------------------------"
}

progress_message() {
    echo "   [+] $1"
}

step_message 1 "Updating System and installing key packages"
progress_message "Updating package lists..."
sudo apt update
progress_message "Upgrading packages..."
sudo apt upgrade -y
progress_message "Installing necessary packages..."
sudo apt install -y net-tools openvswitch-switch

step_message 2 "Enabling Unattended Security Updates"
progress_message "Installing unattended-upgrades package..."
sudo apt install -y unattended-upgrades

progress_message "Enabling unattended-upgrades system service..."
sudo dpkg-reconfigure -f noninteractive unattended-upgrades

progress_message "Ensuring security updates are enabled..."
sudo sed -i 's|//\s*"\${distro_id}:\${distro_codename}-security";|"\${distro_id}:\${distro_codename}-security";|' /etc/apt/apt.conf.d/50unattended-upgrades

progress_message "Configuring automatic update intervals..."
sudo tee /etc/apt/apt.conf.d/10periodic > /dev/null <<EOL
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOL

progress_message "Unattended security updates configured successfully."

step_message 3 "Prompting for Automatic Reboot After Kernel Updates"
echo
read -p "Do you want the system to automatically reboot after kernel/security updates if required? (yes/no): " auto_reboot
if [ "$auto_reboot" == "yes" ]; then
    progress_message "Enabling automatic reboot after updates..."
    sudo sed -i 's|^//\s*Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "true";|' /etc/apt/apt.conf.d/50unattended-upgrades
    sudo sed -i 's|^//\s*Unattended-Upgrade::Automatic-Reboot-Time "02:00";|Unattended-Upgrade::Automatic-Reboot-Time "02:00";|' /etc/apt/apt.conf.d/50unattended-upgrades

    if ! grep -qE '^\s*Unattended-Upgrade::Automatic-Reboot\s+"true";' /etc/apt/apt.conf.d/50unattended-upgrades; then
        sudo tee -a /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null <<EOL

Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOL
    fi

    if grep -qE '^\s*Unattended-Upgrade::Automatic-Reboot\s+"true";' /etc/apt/apt.conf.d/50unattended-upgrades; then
        progress_message "Automatic reboot after kernel updates is enabled."
    else
        progress_message "WARNING: Could not confirm automatic reboot setting; check /etc/apt/apt.conf.d/50unattended-upgrades manually."
    fi
else
    progress_message "Automatic reboot after updates was skipped per user input."
fi

step_message 4 "Loading tun module if not already loaded"
progress_message "Loading 'tun' module..."
sudo modprobe tun
sudo grep -qxF "tun" /etc/modules || sudo sh -c 'echo "tun" >> /etc/modules'

step_message 5 "Installing Domotz Pro agent via Snap Store"
progress_message "Installing Domotz Pro agent..."
sudo snap install domotzpro-agent-publicstore

step_message 6 "Granting permissions to Domotz Pro agent"
permissions=("firewall-control" "network-observe" "raw-usb" "shutdown" "system-observe")
for permission in "${permissions[@]}"; do
    progress_message "Connecting Domotz Pro agent: $permission..."
    sudo snap connect "domotzpro-agent-publicstore:$permission"
done

step_message 7 "Allowing port 3000 in UFW"
progress_message "Creating firewall rule"
sudo ufw allow 3000/tcp

step_message 8 "Configuring netplan for DHCP on attached NICs"
progress_message "Editing netplan configuration file..."
sudo tee /etc/netplan/00-installer-config.yaml > /dev/null <<EOL
network:
    version: 2
    ethernets:
        all-en:
            match:
                name: "en*"
            dhcp4: true
            dhcp6: false
            accept-ra: false
            optional: true
        all-eth:
            match:
                name: "eth*"
            dhcp4: true
            dhcp6: false
            accept-ra: false
            optional: true
EOL
sudo chmod 600 /etc/netplan/00-installer-config.yaml
sudo rm -f /etc/netplan/50-cloud-init.yaml
sudo netplan apply

step_message 9 "Resolving VPN on Demand issue with DNS"
progress_message "Swaping resolv.conf file link..."
sudo unlink /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

step_message 10 "Disabling cloud-init's network configuration"
progress_message "Creating /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

step_message 11 "Disabling IPv6 at the kernel level"
progress_message "Adding ipv6.disable=1 to GRUB kernel parameters..."
if ! grep -q "ipv6.disable=1" /etc/default/grub; then
    sudo sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub
fi
progress_message "Updating GRUB configuration..."
sudo update-grub
progress_message "IPv6 disabled at the kernel level (takes effect after reboot)."

echo "------------------------------------------------------------"
echo "   [+] Setup completed successfully!"
if [ "$auto_reboot" != "yes" ]; then
    echo "   [!] A reboot is required for the IPv6 kernel-level change to take effect."
fi
echo "------------------------------------------------------------"
