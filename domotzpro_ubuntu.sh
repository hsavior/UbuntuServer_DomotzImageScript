#!/bin/bash

# Set non-interactive mode for package configuration and disables NEEDRESTART MESSAGES
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=y
# Function to display step messages
step_message() {
    echo "------------------------------------------------------------"
    echo "Step $1: $2"
    echo "------------------------------------------------------------"
}

# Function to display real-time feedback
progress_message() {
    echo "   [+] $1"
}

# Step 1
step_message 1 "Updating and installing key packages"
progress_message "Updating package lists..."
sudo apt update

progress_message "Upgrading packages..."
sudo apt upgrade -y

progress_message "Installing necessary packages..."
sudo apt install -y net-tools openvswitch-switch

# Step 2
step_message 2 "Loading tun module if not already loaded"
progress_message "Loading 'tun' module..."
sudo modprobe tun
sudo grep -qxF "tun" /etc/modules || sudo sh -c 'echo "tun" >> /etc/modules'

# Step 3
step_message 3 "Installing Domotz Pro agent via Snap Store"
progress_message "Installing Domotz Pro agent..."
sudo snap install domotzpro-agent-publicstore

# Step 4
step_message 4 "Granting permissions to Domotz Pro agent"
permissions=("firewall-control" "network-observe" "raw-usb" "shutdown" "system-observe")
for permission in "${permissions[@]}"; do
    progress_message "Connecting Domotz Pro agent: $permission..."
    sudo snap connect "domotzpro-agent-publicstore:$permission"
done

# Step 5
step_message 5 "Allowing port 3000 in UFW"
progress_message "Creating firewall rule"
sudo ufw allow 3000

# Step 6
step_message 6 "Configuring netplan for DHCP on attached NICs"
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
        all-eth:
            match:
                name: "eth*"
            dhcp4: true
            dhcp6: false
            accept-ra: false
EOL
sudo netplan apply

# Step 7
step_message 7 "Resolving VPN on Demand issue"
progress_message "Swaping resolv.conf file link..."
sudo unlink /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Step 8
step_message 8 "Removing openssh-server"
progress_message "Purging openssh-server from system..."
sudo apt purge -y openssh-server && sudo apt autoremove -y

echo "------------------------------------------------------------"
echo "   [+] Setup completed successfully!"
echo "------------------------------------------------------------"
