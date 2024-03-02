#!/bin/bash

# Set non-interactive mode for package configuration
export DEBIAN_FRONTEND=noninteractive

# Function to display step messages
step_message() {
    echo "----------------------------------------------------------------------"
    echo "Step $1: $2"
    echo "----------------------------------------------------------------------"
}

# Step 1
step_message 1 "Updating and installing key packages"
sudo apt update && sudo apt upgrade -y && sudo apt install -y net-tools openvswitch-switch

# Step 2
step_message 2 "Loading tun module if not already loaded"
if ! lsmod | grep -q tun; then
    sudo sh -c 'echo tun >> /etc/modules'
    sudo modprobe tun
else
    echo "tun module is already loaded."
fi

# Step 3
step_message 3 "Installing Domotz Pro agent via Snap Store"
sudo snap install domotzpro-agent-publicstore

# Step 4
step_message 4 "Granting permissions to Domotz Pro agent"
sudo snap connect domotzpro-agent-publicstore:firewall-control
sudo snap connect domotzpro-agent-publicstore:network-observe
sudo snap connect domotzpro-agent-publicstore:raw-usb
sudo snap connect domotzpro-agent-publicstore:shutdown
sudo snap connect domotzpro-agent-publicstore:system-observe

# Step 5
step_message 5 "Allowing port 3000 in UFW"
sudo ufw allow 3000

# Step 6
step_message 6 "Configuring netplan for DHCP on attached NICs"
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
sudo unlink /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Step 8
step_message 8 "Removing openssh-server"
sudo apt purge -y openssh-server && sudo apt autoremove -y

# Step 9
step_message 9 "Cleaning command history"
history -c

echo "Setup completed successfully!"
