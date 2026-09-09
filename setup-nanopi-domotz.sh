#!/bin/bash
#
# setup-nanopi-domotz.sh
#
# Provisions a FriendlyELEC Rockchip board running a FriendlyELEC Ubuntu or
# Debian arm64 image as a Domotz Collector.
#
# Verified against: NanoPi R5S / R5C (RK3568), NanoPi R3S (RK3566)
# Image family:     rk356x-XYZ-ubuntu-noble-core-6.1-arm64-YYYYMMDD.img
# Reference:        https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R5S
#                   https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R3S
#
# This is the arm64 / FriendlyELEC counterpart to the Ubuntu Server x86_64
# script. Differences from that script, because this platform is not a stock
# Ubuntu Server install:
#   - There is no GRUB. IPv6 is disabled with sysctl and, when present, by
#     patching the extlinux kernel command line.
#   - snapd, ufw and netplan are not always present, so they are installed
#     or worked around instead of assumed.
#   - Network config is written for netplan when netplan is in use, and for
#     /etc/network/interfaces.d otherwise.
#   - Interfaces are eth0 (1GbE) plus eth1 and eth2 (2.5GbE) on the R5S.
#

set -euo pipefail

# This script is designed to be run either directly or piped straight from
# wget into bash. When piped, the script itself occupies stdin, so a plain
# "read" would swallow script text instead of waiting for the operator.
# Reading from /dev/tty talks to the terminal regardless of how we were
# started. Same reason sudo can still prompt for a password in a pipeline.
if [ -r /dev/tty ]; then
    exec 3</dev/tty
else
    echo "This script needs an interactive terminal and does not have one."
    echo "Run it from a login shell, not from a cron job or a non-interactive"
    echo "session."
    exit 1
fi

ask() {
    local prompt="$1" reply=""
    # The prompt goes to stderr so it stays visible even though the caller
    # captures our stdout in a command substitution.
    printf '%s' "$prompt" >&2
    read -r reply <&3 || reply=""
    printf '%s' "$reply"
}

echo "------------------------------------------------------------"
echo "This script will perform the following actions:"
echo "1. Update System and install key packages"
echo "2. Enable automatic security updates"
echo "3. (Optional) Enable automatic reboot after kernel/security updates"
echo "4. Load the 'tun' module if not already loaded"
echo "5. Install and prepare snapd"
echo "6. Install the Domotz Collector via Snap Store"
echo "7. Grant permissions to the Domotz Collector"
echo "8. Allow port 3000 in UFW"
echo "9. Configure DHCP on all attached NICs"
echo "10. Resolve VPN on Demand issue with DNS"
echo "11. Disable cloud-init's network configuration (if cloud-init present)"
echo "12. Disable IPv6 at the kernel level"
echo "------------------------------------------------------------"
echo "Disclaimer:"
echo
echo "1. Purpose: This script is designed for a fresh FriendlyELEC Ubuntu"
echo "   Noble core arm64 image on a NanoPi R5S, R5C or R3S."
echo "2. By proceeding, you confirm that:"
echo "   - The script will modify system configurations and install necessary packages."
echo "   - It may update system files and settings as per its instructions."
echo "   - Using this script on an already configured system may lead to unexpected behavior."
echo "3. Responsibility: You are responsible for any consequences resulting from running this script."
echo
confirmation1="$(ask "Type 'yes' to proceed: ")"
echo
if [ "$confirmation1" != "yes" ]; then
    echo "Confirmation not received. Exiting script."
    exit 1
fi
echo "------------------------------------------------------------"

echo "Please confirm again to proceed."
confirmation2="$(ask "Type 'yes' to proceed: ")"
echo
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

ARCH="$(dpkg --print-architecture)"
if [ "$ARCH" != "arm64" ]; then
    progress_message "WARNING: expected arm64, found $ARCH. Continuing anyway."
fi

step_message 1 "Updating System and installing key packages"
progress_message "Updating package lists..."
sudo apt update
progress_message "Upgrading packages..."
sudo apt upgrade -y
progress_message "Installing necessary packages..."
sudo apt install -y net-tools ufw curl ca-certificates

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
echo "Recommended for an unattended site: the collector stays patched without"
echo "anyone having to visit it. The reboot happens at 02:00, and only when an"
echo "update actually requires one."
echo
auto_reboot="$(ask "Automatically reboot after kernel/security updates if required? (yes/no) [yes]: ")"
echo
auto_reboot="$(echo "${auto_reboot:-yes}" | tr '[:upper:]' '[:lower:]')"
case "$auto_reboot" in
    y|yes) auto_reboot="yes" ;;
    *)     auto_reboot="no" ;;
esac
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

step_message 5 "Installing and preparing snapd"
if ! command -v snap >/dev/null 2>&1; then
    progress_message "snapd not present on this image, installing..."
    sudo apt install -y snapd
else
    progress_message "snapd already installed."
fi
progress_message "Enabling snapd services..."
sudo systemctl enable --now snapd.socket
sudo systemctl enable --now snapd.seeded.service 2>/dev/null || true
if [ ! -e /snap ]; then
    sudo ln -s /var/lib/snapd/snap /snap
fi
progress_message "Waiting for snap seeding to finish (this can take a few minutes on first boot)..."
sudo snap wait system seed.loaded

step_message 6 "Installing the Domotz Collector via Snap Store"
progress_message "Installing the Domotz Collector..."
sudo snap install domotzpro-agent-publicstore

step_message 7 "Granting permissions to the Domotz Collector"
permissions=("firewall-control" "network-observe" "raw-usb" "shutdown" "system-observe")
for permission in "${permissions[@]}"; do
    progress_message "Connecting Domotz Collector: $permission..."
    sudo snap connect "domotzpro-agent-publicstore:$permission"
done

step_message 8 "Allowing port 3000 in UFW"
progress_message "Creating firewall rule"
sudo ufw allow 3000/tcp

step_message 9 "Configuring DHCP on attached NICs"
if command -v netplan >/dev/null 2>&1 && [ -d /etc/netplan ]; then
    progress_message "netplan detected, writing /etc/netplan/00-installer-config.yaml..."
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

    # netplan renders to systemd-networkd by default. On the FriendlyELEC
    # images networkd is often installed but not enabled, so netplan apply
    # warns that it is not running and hard-restarts it. That works for the
    # session but leaves nothing bringing the network up at the next boot,
    # which would strand a headless collector. Enable it explicitly.
    # Test the exact word, not the exit status. "systemctl is-enabled" exits 0
    # for "enabled-runtime" too, and that state lives in /run, which is wiped
    # at every boot. netplan apply leaves networkd exactly like that, so a
    # status check that trusts the exit code passes while the board is still
    # one reboot away from having no network at all.
    NETWORKD_STATE="$(systemctl is-enabled systemd-networkd 2>/dev/null || true)"
    if [ "$NETWORKD_STATE" != "enabled" ]; then
        progress_message "systemd-networkd is '$NETWORKD_STATE', enabling it persistently..."
        sudo systemctl enable systemd-networkd
    fi
    sudo systemctl enable systemd-networkd.socket 2>/dev/null || true

    sudo netplan apply

    progress_message "Verifying an address was obtained..."
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if ip -4 -br addr show scope global | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
            ip -4 -br addr show scope global | sed 's/^/       /'
            break
        fi
        [ "$attempt" = "10" ] && progress_message "WARNING: no IPv4 address yet. Check the cable and DHCP."
        sleep 2
    done
elif systemctl is-active --quiet NetworkManager; then
    progress_message "NetworkManager is managing the network, configuring wired connections..."
    for dev in $(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1}'); do
        con="$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v d="$dev" '$2==d{print $1; exit}')"
        if [ -z "$con" ]; then
            con="domotz-$dev"
            progress_message "Creating DHCP connection for $dev..."
            sudo nmcli connection add type ethernet ifname "$dev" con-name "$con" \
                ipv4.method auto ipv6.method disabled connection.autoconnect yes
        else
            progress_message "Setting $con ($dev) to DHCP with IPv6 disabled..."
            sudo nmcli connection modify "$con" ipv4.method auto ipv6.method disabled connection.autoconnect yes
        fi
        sudo nmcli connection up "$con" || true
    done
else
    progress_message "netplan not in use, writing systemd-networkd configuration instead..."
    sudo mkdir -p /etc/systemd/network
    sudo tee /etc/systemd/network/10-domotz-dhcp.network > /dev/null <<EOL
[Match]
Name=eth* en*

[Network]
DHCP=ipv4
IPv6AcceptRA=no
LinkLocalAddressing=no

[DHCPv4]
UseDomains=yes
EOL
    sudo tee /etc/systemd/network/10-domotz-dhcp.link > /dev/null <<EOL
[Match]
OriginalName=eth*

[Link]
NamePolicy=keep kernel
EOL
    sudo systemctl enable --now systemd-networkd
    # ifupdown, if present on the FriendlyELEC image, will fight networkd.
    if [ -d /etc/network/interfaces.d ]; then
        progress_message "Neutralizing ifupdown interface files..."
        for f in /etc/network/interfaces.d/*; do
            [ -e "$f" ] || continue
            sudo mv "$f" "$f.disabled-by-domotz"
        done
    fi
    sudo systemctl restart systemd-networkd
fi

step_message 10 "Resolving VPN on Demand issue with DNS"
if systemctl is-active --quiet systemd-resolved || systemctl list-unit-files | grep -q '^systemd-resolved'; then
    progress_message "Ensuring systemd-resolved is running..."
    sudo systemctl enable --now systemd-resolved
    progress_message "Swapping resolv.conf file link..."
    sudo rm -f /etc/resolv.conf
    sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
else
    progress_message "systemd-resolved not available on this image, leaving /etc/resolv.conf as it is."
fi

step_message 11 "Disabling cloud-init's network configuration"
if [ -d /etc/cloud ]; then
    progress_message "Creating /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
    sudo mkdir -p /etc/cloud/cloud.cfg.d
    echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null
else
    progress_message "cloud-init not present on this image, skipping."
fi

step_message 12 "Disabling IPv6 at the kernel level"
progress_message "Writing /etc/sysctl.d/99-disable-ipv6.conf..."
sudo tee /etc/sysctl.d/99-disable-ipv6.conf > /dev/null <<EOL
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOL
sudo sysctl --system > /dev/null

# RK3568 boards boot through U-Boot and extlinux, not GRUB, so the kernel
# command line lives in extlinux.conf when it is present.
EXTLINUX=""
for candidate in /boot/extlinux/extlinux.conf /boot/extlinux.conf; do
    [ -f "$candidate" ] && EXTLINUX="$candidate" && break
done

if [ -n "$EXTLINUX" ]; then
    if grep -q "ipv6.disable=1" "$EXTLINUX"; then
        progress_message "extlinux already carries ipv6.disable=1."
    else
        progress_message "Adding ipv6.disable=1 to the kernel command line in $EXTLINUX..."
        sudo cp "$EXTLINUX" "$EXTLINUX.bak"
        sudo sed -i 's|^\(\s*append\s\+.*\)$|\1 ipv6.disable=1|I' "$EXTLINUX"
        if grep -qi "append" "$EXTLINUX" && grep -q "ipv6.disable=1" "$EXTLINUX"; then
            progress_message "Kernel command line updated. Backup at $EXTLINUX.bak"
        else
            progress_message "WARNING: could not update $EXTLINUX. sysctl still disables IPv6."
        fi
    fi
elif [ -f /etc/default/grub ]; then
    progress_message "GRUB detected, adding ipv6.disable=1 to GRUB kernel parameters..."
    if ! grep -q "ipv6.disable=1" /etc/default/grub; then
        sudo sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub
    fi
    sudo update-grub
else
    progress_message "No extlinux or GRUB config found. IPv6 is disabled via sysctl only."
fi
progress_message "IPv6 disabled (kernel command line change takes effect after reboot)."

step_message 13 "Verifying the collector survives a reboot"
BOOT_OK="yes"
for unit in systemd-networkd systemd-resolved snapd; do
    if ! systemctl list-unit-files "$unit.service" >/dev/null 2>&1; then
        continue
    fi
    state="$(systemctl is-enabled "$unit" 2>/dev/null || echo "not-found")"
    case "$state" in
        enabled|static|indirect|generated)
            progress_message "$unit: $state" ;;
        not-found)
            progress_message "$unit: not installed, skipping" ;;
        *)
            progress_message "WARNING: $unit is '$state', which does not survive a reboot."
            progress_message "         Fixing with: systemctl enable $unit"
            sudo systemctl enable "$unit" || BOOT_OK="no" ;;
    esac
done
if [ "$BOOT_OK" = "yes" ]; then
    progress_message "Boot-time services look correct."
fi

echo "------------------------------------------------------------"
echo "   [+] Setup completed successfully!"
echo "   [+] Domotz Collector web interface: http://$(hostname -I 2>/dev/null | awk '{print $1}'):3000"
echo "   [!] Reboot once and confirm the board comes back on the network"
echo "       before leaving it unattended."
if [ "$auto_reboot" != "yes" ]; then
    echo "   [!] A reboot is required for the IPv6 kernel-level change to take effect."
fi
echo "------------------------------------------------------------"
