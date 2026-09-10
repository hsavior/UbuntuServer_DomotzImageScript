#!/bin/bash
#
# setup-dynavlan-domotz.sh
#
# Optional add-on to setup-nanopi-domotz.sh.
#
# Installs DynaVLAN and points it at the Domotz Collector, so a collector on a
# trunk port brings up every tagged VLAN with DHCP and discovers devices on all
# of them instead of only the untagged network.
#
# DynaVLAN is a third-party open-source project:
#   https://github.com/pereljon/dynavlan
#
# Run this only when the collector is plugged into a trunk port. On a normal
# access port it has nothing to do.
#
# Usage, on the collector:
#   wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-dynavlan-domotz.sh | bash
#

set -euo pipefail

DYNAVLAN_INSTALLER="https://raw.githubusercontent.com/pereljon/dynavlan/main/get.sh"
COLLECTOR_SNAP="domotzpro-agent-publicstore"

# Same reasoning as the main setup script: this is designed to be piped from
# wget into bash, so prompts read the terminal directly rather than stdin.
if [ -r /dev/tty ]; then
    exec 3</dev/tty
else
    echo "This script needs an interactive terminal and does not have one."
    exit 1
fi

ask() {
    local prompt="$1" reply=""
    printf '%s' "$prompt" >&2
    read -r reply <&3 || reply=""
    printf '%s' "$reply"
}

step_message() {
    echo "------------------------------------------------------------"
    echo "Step $1: $2"
    echo "------------------------------------------------------------"
}

progress_message() {
    echo "   [+] $1"
}

echo "------------------------------------------------------------"
echo "DynaVLAN for the Domotz Collector"
echo "------------------------------------------------------------"
echo
echo "What this does:"
echo "  A collector on a trunk port sees only the untagged network, so devices"
echo "  on the tagged VLANs are never discovered. DynaVLAN detects the VLANs"
echo "  present on the port, brings each one up with DHCP, and restarts the"
echo "  Collector so it discovers devices on all of them."
echo
echo "This script will:"
echo "1. Check the prerequisites (netplan 0.106 or newer, systemd-networkd)"
echo "2. Install tcpdump and lldpd, which DynaVLAN uses to detect VLANs"
echo "3. Install DynaVLAN from $DYNAVLAN_INSTALLER"
echo "4. Configure it to restart the Domotz Collector after VLAN changes"
echo "5. Show you the resulting configuration"
echo
echo "Run this ONLY if the collector is on a trunk port. On a normal network"
echo "port it has nothing to do."
echo
echo "IMPORTANT: applying VLAN changes reconfigures the network and can drop an"
echo "SSH session. Nothing is applied by this script; DynaVLAN takes effect at"
echo "the next boot. Where possible, do that first reboot with physical access"
echo "to the board."
echo
echo "DynaVLAN is third-party open-source software, not maintained by Domotz:"
echo "  https://github.com/pereljon/dynavlan"
echo
confirmation="$(ask "Type 'yes' to proceed: ")"
echo
if [ "$confirmation" != "yes" ]; then
    echo "Confirmation not received. Exiting script."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

step_message 1 "Checking prerequisites"

if ! command -v netplan >/dev/null 2>&1; then
    echo "   [!] netplan is not installed on this system, and DynaVLAN requires it." >&2
    echo "   [!] DynaVLAN drives netplan with the systemd-networkd renderer." >&2
    exit 1
fi

# Getting the netplan version is fiddlier than it looks. Not every build has
# "netplan --version" (the FriendlyELEC Noble image does not; it just prints
# usage), so ask the package manager first, then fall back to "netplan info",
# then to --version for builds that do have it.
#
# The "|| true" on each matters: under "set -e" with pipefail, a bare
# assignment whose pipeline fails kills the script silently, with no message.
NETPLAN_VER=""
NETPLAN_SOURCE=""

NETPLAN_VER="$(dpkg-query -W -f='${Version}' netplan.io 2>/dev/null \
    | grep -oE '^[0-9]+\.[0-9]+' | head -n1 || true)"
[ -n "$NETPLAN_VER" ] && NETPLAN_SOURCE="dpkg"

if [ -z "$NETPLAN_VER" ]; then
    NETPLAN_VER="$(netplan info 2>/dev/null \
        | grep -iE '^[[:space:]]*version:' | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
    [ -n "$NETPLAN_VER" ] && NETPLAN_SOURCE="netplan info"
fi

if [ -z "$NETPLAN_VER" ]; then
    NETPLAN_VER="$(netplan --version 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
    [ -n "$NETPLAN_VER" ] && NETPLAN_SOURCE="netplan --version"
fi

if [ -n "$NETPLAN_VER" ]; then
    NP_MAJOR="${NETPLAN_VER%%.*}"
    NP_MINOR="${NETPLAN_VER##*.}"
    if [ "$NP_MAJOR" -eq 0 ] && [ "$NP_MINOR" -lt 106 ]; then
        echo "   [!] netplan $NETPLAN_VER is older than the required 0.106." >&2
        echo "   [!] DynaVLAN refuses to run below that version." >&2
        exit 1
    fi
    progress_message "netplan $NETPLAN_VER meets the 0.106 requirement (via $NETPLAN_SOURCE)."
else
    progress_message "Could not determine the netplan version, continuing anyway."
    progress_message "  DynaVLAN will refuse to run if it turns out to be older than 0.106."
fi

if systemctl is-active --quiet systemd-networkd; then
    progress_message "systemd-networkd is running."
else
    progress_message "WARNING: systemd-networkd is not running. DynaVLAN expects the"
    progress_message "         systemd-networkd renderer. Check your netplan configuration."
fi

if snap list "$COLLECTOR_SNAP" >/dev/null 2>&1; then
    progress_message "Domotz Collector snap is installed."
    COLLECTOR_PRESENT="yes"
else
    progress_message "WARNING: the $COLLECTOR_SNAP snap was not found."
    progress_message "         Continuing, but run setup-nanopi-domotz.sh first if this"
    progress_message "         board is not set up as a collector yet."
    COLLECTOR_PRESENT="no"
fi

step_message 2 "Installing detection tools"
progress_message "Installing tcpdump (VLAN sniffing) and lldpd (LLDP detection)..."
sudo apt update
sudo apt install -y tcpdump lldpd

step_message 3 "Installing DynaVLAN"
progress_message "Fetching and running the DynaVLAN installer..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$DYNAVLAN_INSTALLER" | sudo bash
else
    wget -qO- "$DYNAVLAN_INSTALLER" | sudo bash
fi

if ! command -v dynavlan >/dev/null 2>&1 && [ ! -f /etc/dynavlan.conf ]; then
    echo "   [!] DynaVLAN does not appear to have installed. Check the output above." >&2
    exit 1
fi
progress_message "DynaVLAN installed."

step_message 4 "Configuring DynaVLAN to restart the Domotz Collector"
if [ -f /etc/dynavlan.conf ]; then
    sudo cp /etc/dynavlan.conf /etc/dynavlan.conf.bak
    progress_message "Backed up /etc/dynavlan.conf to /etc/dynavlan.conf.bak"

    # Every key is present in the shipped file, usually commented at its
    # default, so match a commented or active line before appending.
    if grep -qE '^[[:space:]]*#?[[:space:]]*RESTART_SNAPS=' /etc/dynavlan.conf; then
        sudo sed -i "s|^[[:space:]]*#\?[[:space:]]*RESTART_SNAPS=.*|RESTART_SNAPS=$COLLECTOR_SNAP|" \
            /etc/dynavlan.conf
    else
        printf '\n# Added by setup-dynavlan-domotz.sh\nRESTART_SNAPS=%s\n' "$COLLECTOR_SNAP" \
            | sudo tee -a /etc/dynavlan.conf > /dev/null
    fi

    if grep -qE "^RESTART_SNAPS=$COLLECTOR_SNAP" /etc/dynavlan.conf; then
        progress_message "Set RESTART_SNAPS=$COLLECTOR_SNAP"
    else
        progress_message "WARNING: could not confirm RESTART_SNAPS. Check /etc/dynavlan.conf manually."
    fi
else
    progress_message "WARNING: /etc/dynavlan.conf was not created by the installer."
fi

step_message 5 "Current configuration"
if [ -f /etc/dynavlan.conf ]; then
    progress_message "Active settings in /etc/dynavlan.conf:"
    grep -E '^[A-Z_]+=' /etc/dynavlan.conf | sed 's/^/       /' || true
    echo
    progress_message "Everything else is commented at its default. Review VLAN_ROUTES"
    progress_message "and REMOVE_ON_CARRIER_LOSS if this site needs them."
fi

echo
progress_message "Service status:"
systemctl list-unit-files 2>/dev/null | grep -i dynavlan | sed 's/^/       /' || \
    progress_message "       (no dynavlan units listed)"

echo "------------------------------------------------------------"
echo "   [+] DynaVLAN setup complete."
echo
echo "   It runs at the next boot and on its rescan timer. Nothing about this"
echo "   system's network has been changed yet."
echo
echo "   To apply now instead of waiting for a reboot:"
echo "       sudo dynavlan --boot"
echo "   Be aware that this reconfigures the network and can drop your SSH"
echo "   session. Do it with physical access to the board if you can."
echo
if [ "$COLLECTOR_PRESENT" = "no" ]; then
    echo "   [!] The Domotz Collector snap was not found on this system. Run"
    echo "       setup-nanopi-domotz.sh to install it."
fi
echo "   After the VLANs come up, check the Collector sees devices on each one."
echo "------------------------------------------------------------"
