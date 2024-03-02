#!/bin/bash

# Set non-interactive mode for package configuration
export DEBIAN_FRONTEND=noninteractive

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
if ! lsmod | grep -q tun; then
    progress_message "Adding 'tun' to /etc/modules..."
    sudo sh -c 'echo tun >> /etc/modules'
    
    progress_message "Loading 'tun' module..."
    sudo modprobe tun
else
    echo "   [!] 'tun' module is already loaded."
fi

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
progress_message "Allowing port 3000 in UFW..."
sudo ufw allow 3000

# Step 6
step_message 6 "Configuring netplan for DHCP on attached NICs"
progress_message "Configuring netplan for DHCP on attached NICs..."
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
progress_message "Resolving VPN on Demand issue..."
sudo unlink /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Step 8
step_message 8 "Removing openssh-server"
progress_message "Purging openssh-server..."
sudo apt purge -y openssh-server && sudo apt autoremove -y

# Step 9
step_message 9 "Cleaning command history"
progress_message "Cleaning command history..."
history -c

echo "------------------------------------------------------------"
echo "   [+] Setup completed successfully!"
echo "------------------------------------------------------------"
