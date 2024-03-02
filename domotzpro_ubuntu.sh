#!/bin/bash

# Set non-interactive mode for package configuration
export DEBIAN_FRONTEND=noninteractive

# Update and install key packages
sudo apt update && sudo apt upgrade -y && sudo apt install -y net-tools openvswitch-switch

# Load tun module
sudo sh -c 'echo tun >> /etc/modules'
sudo modprobe tun

# Install Domotz Pro agent via Snap Store
sudo snap install domotzpro-agent-publicstore

# Grant permissions to Domotz Pro agent
sudo snap connect domotzpro-agent-publicstore:firewall-control
sudo snap connect domotzpro-agent-publicstore:network-observe
sudo snap connect domotzpro-agent-publicstore:raw-usb
sudo snap connect domotzpro-agent-publicstore:shutdown
sudo snap connect domotzpro-agent-publicstore:system-observe

# Allow port 3000 in UFW
sudo ufw allow 3000

# Configure netplan for DHCP on attached NICs
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

# Resolve VPN on Demand issue
sudo unlink /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
ls -l /etc/resolv.conf

# Remove openssh-server
sudo apt purge -y openssh-server && sudo apt autoremove -y

# Clean command history
history -c

echo "Setup completed successfully!"
