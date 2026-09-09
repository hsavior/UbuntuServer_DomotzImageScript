#!/bin/bash
#
# flash-nanopi-domotz.sh
#
# Writes a FriendlyELEC RK3568 eflasher image to an SD card, sets eflasher to
# install the bundled OS to eMMC unattended, and drops the Domotz provisioning
# script onto the card's FriendlyARM partition.
#
# Built for the single-OS eflasher card that already carries Noble:
#   rk3568-eflasher-ubuntu-noble-core-6.1-arm64-20260721.img
# A .img.gz of the same, or a multiple-os eflasher card, also works.
#
# Target hardware: FriendlyELEC NanoPi boards using eflasher.
#   NanoPi R5S / R5C (RK3568) use rk3568-eflasher-* images
#   NanoPi R3S       (RK3566) use rk3566-eflasher-* images
# Reference: https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R5S
#            https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R3S
#
# Runs on Linux or macOS.
#

set -euo pipefail

IMAGE=""
DEVICE=""
OS_IMAGE=""
SETUP_SCRIPT=""
AUTOSTART="ask"
LOCK_UI="yes"
WELCOME_MESSAGE="Domotz Collector Installer"

usage() {
    cat <<'EOF'
Usage:
  ./flash-nanopi-domotz.sh -i <eflasher-image.img.gz> -d <device> [options]

Required:
  -i FILE     eflasher image, .img.gz or .img
              R5S/R5C: rk3568-eflasher-ubuntu-noble-core-6.1-arm64-*.img.gz
              R3S:     rk3566-eflasher-ubuntu-noble-core-6.1-arm64-*.img.gz
  -d DEV      target SD card device
              Linux:  /dev/sdX or /dev/mmcblkX
              macOS:  /dev/diskX  (the script uses /dev/rdiskX for speed)

Options:
  -o FILE     extra OS image (.img or .img.gz) to copy onto the card's
              FriendlyARM partition for eMMC installation
  -s FILE     setup script to copy onto the FriendlyARM partition
              (default: ./setup-nanopi-domotz.sh if it exists)
  -a NAME     value for autoStart= in eflasher.conf, or "none" to disable
              autostart, or "skip" to leave eflasher.conf untouched
  -w TEXT     welcome banner shown on the eflasher screen
              (default: "Domotz Collector Installer")
  -U          do NOT lock the eflasher UI. Leaves autoExit, hideMenuButton,
              hideBackupAndRestoreButton and welcomeMessage at image defaults.
  -N          stage only. Skip the erase and write, and just mount an
              already-flashed card to copy files and set autoStart.
              Use this to add the setup script to a card you already wrote.
  -l          list candidate disks and exit
  -h          show this help

Examples:
  ./flash-nanopi-domotz.sh -l
  ./flash-nanopi-domotz.sh -i rk3568-eflasher-ubuntu-noble-core-6.1-arm64-20260721.img -d /dev/disk4
EOF
}

list_disks() {
    if [ "$(uname -s)" = "Darwin" ]; then
        diskutil list external physical
    else
        lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL,RM
        echo
        echo "Removable disks have RM=1."
    fi
}

STAGE_ONLY="no"

while getopts ":i:d:o:s:a:w:UNlh" opt; do
    case "$opt" in
        i) IMAGE="$OPTARG" ;;
        N) STAGE_ONLY="yes" ;;
        w) WELCOME_MESSAGE="$OPTARG" ;;
        U) LOCK_UI="no" ;;
        d) DEVICE="$OPTARG" ;;
        o) OS_IMAGE="$OPTARG" ;;
        s) SETUP_SCRIPT="$OPTARG" ;;
        a) AUTOSTART="$OPTARG" ;;
        l) list_disks; exit 0 ;;
        h) usage; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 1 ;;
        :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
    esac
done

OS_NAME="$(uname -s)"

step_message() {
    echo "------------------------------------------------------------"
    echo "Step $1: $2"
    echo "------------------------------------------------------------"
}

progress_message() {
    echo "   [+] $1"
}

die() {
    echo "   [!] $1" >&2
    exit 1
}

echo "------------------------------------------------------------"
if [ "$STAGE_ONLY" = "yes" ]; then
    echo "STAGE-ONLY MODE. This script will perform the following actions:"
    echo "1. Validate the target SD card device"
    echo "2. Mount the FriendlyARM partition of the already-flashed card"
    echo "3. (Optional) Copy an OS image to that partition"
    echo "4. (Optional) Set autoStart in eflasher.conf for unattended eMMC install"
    echo "5. Copy the Domotz setup script to that partition"
    echo "------------------------------------------------------------"
    echo "Nothing is erased and nothing is rewritten in this mode."
else
    echo "This script will perform the following actions:"
    echo "1. Validate the eflasher image and the target SD card device"
    echo "2. Unmount any mounted partitions on the target device"
    echo "3. Write the eflasher image to the SD card (this ERASES the card)"
    echo "4. (Optional) Copy an OS image to the card's FriendlyARM partition"
    echo "5. Configure eflasher.conf for an unattended, locked-down install"
    echo "6. Copy the Domotz setup script onto the FriendlyARM partition"
    echo "------------------------------------------------------------"
    echo "Disclaimer:"
    echo
    echo "1. Purpose: this script prepares an SD card for a FriendlyELEC RK3568"
    echo "   NanoPi board (R5S, R5C or R3S) using the eflasher installer image."
    echo "2. By proceeding, you confirm that:"
    echo "   - ALL DATA on the target device will be destroyed."
    echo "   - You have verified the device path yourself. Pointing this at the"
    echo "     wrong disk will wipe it and it cannot be undone."
    echo "3. Responsibility: You are responsible for any consequences resulting"
    echo "   from running this script."
fi
echo

if [ -z "$DEVICE" ] || { [ -z "$IMAGE" ] && [ "$STAGE_ONLY" != "yes" ]; }; then
    usage
    exit 1
fi

step_message 1 "Validating inputs"

if [ "$STAGE_ONLY" = "yes" ]; then
    progress_message "Stage-only mode. The card will NOT be erased or rewritten."
else
    [ -f "$IMAGE" ] || die "Image not found: $IMAGE"
    case "$IMAGE" in
        *.img|*.img.gz|*.gz) ;;
        *) die "Image must be a .img or .img.gz file: $IMAGE" ;;
    esac
    progress_message "Image: $IMAGE ($(du -h "$IMAGE" | cut -f1))"
fi

if [ "$OS_NAME" = "Darwin" ]; then
    [ -b "$DEVICE" ] || [ -c "$DEVICE" ] || die "Not a device: $DEVICE"
    case "$DEVICE" in
        /dev/disk*|/dev/rdisk*) ;;
        *) die "On macOS the device should look like /dev/diskX" ;;
    esac
    RAW_DEVICE="${DEVICE/\/dev\/disk//dev/rdisk}"
    if [ "$STAGE_ONLY" = "yes" ]; then
        progress_message "Target: $DEVICE"
    else
        progress_message "Target: $DEVICE (writing via $RAW_DEVICE)"
    fi
    diskutil info "$DEVICE" | grep -E "Device / Media Name|Disk Size|Removable Media|Protocol" || true
else
    [ -b "$DEVICE" ] || die "Not a block device: $DEVICE"
    RAW_DEVICE="$DEVICE"
    progress_message "Target: $DEVICE"
    lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,MOUNTPOINT "$DEVICE" || true
    if [ "$(lsblk -dn -o RM "$DEVICE" | tr -d ' ')" != "1" ]; then
        progress_message "WARNING: $DEVICE is not flagged as removable. Double check this is the SD card."
    fi
fi

for cmd in dd gzip; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done

if [ -n "$OS_IMAGE" ]; then
    [ -f "$OS_IMAGE" ] || die "OS image not found: $OS_IMAGE"
fi

if [ -z "$SETUP_SCRIPT" ] && [ -f "./setup-nanopi-domotz.sh" ]; then
    SETUP_SCRIPT="./setup-nanopi-domotz.sh"
fi
if [ -n "$SETUP_SCRIPT" ]; then
    [ -f "$SETUP_SCRIPT" ] || die "Setup script not found: $SETUP_SCRIPT"
    progress_message "Setup script to stage: $SETUP_SCRIPT"
fi

if [ "$STAGE_ONLY" = "yes" ]; then
    echo
    echo "Stage-only: files will be copied onto the existing card on $DEVICE."
    read -r -p "Type 'yes' to proceed: " confirmation1
    if [ "$confirmation1" != "yes" ]; then
        echo "Confirmation not received. Exiting script."
        exit 1
    fi
else
    echo
    echo "Everything on $DEVICE will be erased."
    read -r -p "Type 'yes' to proceed: " confirmation1
    if [ "$confirmation1" != "yes" ]; then
        echo "Confirmation not received. Exiting script."
        exit 1
    fi
    echo "------------------------------------------------------------"
    echo "Please confirm again to proceed."
    read -r -p "Type 'yes' to proceed: " confirmation2
    if [ "$confirmation2" != "yes" ]; then
        echo "Confirmation not received. Exiting script."
        exit 1
    fi
fi

if [ "$STAGE_ONLY" != "yes" ]; then

step_message 2 "Unmounting partitions on the target device"
if [ "$OS_NAME" = "Darwin" ]; then
    progress_message "Running diskutil unmountDisk..."
    sudo diskutil unmountDisk "$DEVICE"
else
    progress_message "Unmounting any mounted partitions..."
    while read -r part mnt; do
        [ -n "$mnt" ] || continue
        progress_message "umount $part ($mnt)"
        sudo umount "$part" || true
    done < <(lsblk -ln -o PATH,MOUNTPOINT "$DEVICE" | tail -n +2)
fi

step_message 3 "Writing the eflasher image to the SD card"
progress_message "This takes several minutes. Do not remove the card."
if [ "$OS_NAME" = "Darwin" ]; then
    # BSD dd has no status=progress. Press Ctrl-T during the write for a
    # progress line instead.
    DD_ARGS="bs=4m"
    progress_message "Press Ctrl-T at any time to see how far along the write is."
else
    DD_ARGS="bs=4M conv=fsync oflag=direct status=progress"
fi

case "$IMAGE" in
    *.gz)
        # shellcheck disable=SC2086
        gzip -dc "$IMAGE" | sudo dd of="$RAW_DEVICE" $DD_ARGS
        ;;
    *)
        # shellcheck disable=SC2086
        sudo dd if="$IMAGE" of="$RAW_DEVICE" $DD_ARGS
        ;;
esac

progress_message "Flushing write cache..."
sync
progress_message "Image written."

fi  # end of STAGE_ONLY guard

step_message 4 "Staging files on the FriendlyARM partition"

MOUNTPOINT=""
DIRECT_MOUNT="no"
cleanup_mount() {
    if [ -n "$MOUNTPOINT" ]; then
        sync
        if [ "$DIRECT_MOUNT" = "yes" ]; then
            sudo umount "$MOUNTPOINT" >/dev/null 2>&1 || true
            sudo rmdir "$MOUNTPOINT" >/dev/null 2>&1 || true
        elif [ "$OS_NAME" = "Darwin" ]; then
            diskutil unmount "$MOUNTPOINT" >/dev/null 2>&1 || true
        else
            sudo umount "$MOUNTPOINT" >/dev/null 2>&1 || true
            rmdir "$MOUNTPOINT" >/dev/null 2>&1 || true
        fi
    fi
}
trap cleanup_mount EXIT

if [ -z "$OS_IMAGE" ] && [ -z "$SETUP_SCRIPT" ] && [ "$AUTOSTART" = "skip" ]; then
    progress_message "Nothing to stage, skipping."
else
    progress_message "Waiting for the card to settle..."
    sleep 5

    if [ "$OS_NAME" = "Darwin" ]; then
        # Match on partition type rather than volume name. macOS often does not
        # remount a card automatically after dd, and the FAT volume is not
        # always labelled FriendlyARM.
        BASE_DISK="$(echo "$DEVICE" | sed 's|/dev/r\{0,1\}disk\([0-9]\{1,\}\).*|disk\1|')"

        # Prefer a volume Finder has already mounted. macOS grants the CLI far
        # less latitude than Finder for removable media, so a volume that is
        # already mounted is the easiest one to use, and force-unmounting it
        # only to remount it from here is how you end up with "Blocked".
        for vol in /Volumes/*; do
            [ -d "$vol" ] || continue
            if [ -f "$vol/eflasher.conf" ] || ls "$vol"/*.img "$vol"/*.img.gz >/dev/null 2>&1; then
                VOL_DISK="$(diskutil info "$vol" 2>/dev/null \
                    | awk -F: '/Part of Whole/ {gsub(/ /, "", $2); print $2}')"
                if [ "$VOL_DISK" = "$BASE_DISK" ]; then
                    progress_message "Using the already-mounted volume at $vol"
                    MOUNTPOINT="$vol"
                    break
                fi
            fi
        done

        if [ -z "$MOUNTPOINT" ] && [ "$STAGE_ONLY" != "yes" ]; then
            progress_message "Re-reading the partition table on $BASE_DISK..."
            sudo diskutil unmountDisk force "$BASE_DISK" >/dev/null 2>&1 || true
        fi

        # An eflasher card exposes a dozen small partitions (idbloader, uboot,
        # trust, misc, boot and so on) plus one large data partition that holds
        # eflasher.conf and the OS payloads. That data partition is not always
        # the first one listed, so identify it by name when possible and verify
        # by content otherwise, rather than taking whatever comes first.
        PART_LIST=""
        for attempt in 1 2 3 4 5 6; do
            [ -n "$MOUNTPOINT" ] && break
            PART_LIST="$(diskutil list "$BASE_DISK" 2>/dev/null \
                | awk '/^ +[0-9]+:/ {print $NF}' \
                | grep -E '^disk[0-9]+s[0-9]+$' || true)"
            [ -n "$PART_LIST" ] && break
            progress_message "Partition table not visible yet, retrying ($attempt of 6)..."
            sleep 3
        done

        if [ -n "$MOUNTPOINT" ]; then
            :
        elif [ -z "$PART_LIST" ]; then
            progress_message "No partitions visible. Here is what macOS sees:"
            diskutil list "$BASE_DISK" || true
        else
            # Put a partition actually named FriendlyARM at the front of the queue.
            NAMED_PART="$(diskutil list "$BASE_DISK" 2>/dev/null \
                | grep -i 'FriendlyARM' | head -n1 | awk '{print $NF}')"
            CANDIDATE_PARTS="$NAMED_PART $(echo "$PART_LIST" | tr '\n' ' ')"

            for part in $CANDIDATE_PARTS; do
                [ -n "$part" ] || continue
                MOUNT_ERR="$(sudo diskutil mount "$part" 2>&1)" || true
                if echo "$MOUNT_ERR" | grep -qi "Blocked"; then
                    MOUNT_BLOCKED="yes"
                    continue
                fi
                sleep 1
                TRY_MP="$(diskutil info "$part" 2>/dev/null \
                    | awk -F: '/Mount Point/ {sub(/^ +/, "", $2); print $2}')"
                if [ -d "$TRY_MP" ] && { [ -f "$TRY_MP/eflasher.conf" ] || ls "$TRY_MP"/*.img "$TRY_MP"/*.img.gz >/dev/null 2>&1; }; then
                    progress_message "Data partition is $part"
                    MOUNTPOINT="$TRY_MP"
                    break
                fi
                # Not the one. Leave it as we found it.
                [ -n "$TRY_MP" ] && diskutil unmount "$TRY_MP" >/dev/null 2>&1 || true
            done
        fi

        if [ -z "$MOUNTPOINT" ]; then
            progress_message "Falling back to mounting every volume on the disk..."
            sudo diskutil mountDisk "$BASE_DISK" >/dev/null 2>&1 || true
            sleep 3
            for vol in /Volumes/*; do
                [ -d "$vol" ] || continue
                if [ -f "$vol/eflasher.conf" ] || [ -f "$vol/info.conf" ]; then
                    MOUNTPOINT="$vol"
                    break
                fi
            done
        fi

        if [ -z "$MOUNTPOINT" ]; then
            # DiskArbitration answers "Blocked" on these cards, most likely
            # because the image's backup GPT header still points at the end of
            # the image rather than the end of the card. mount_exfat does not
            # go through DiskArbitration and works fine.
            progress_message "diskutil refused the mount, trying a direct exfat mount..."
            DIRECT_MP="/private/tmp/flash-nanopi-domotz.$$"
            sudo mkdir -p "$DIRECT_MP"
            RETRY_PARTS="$(diskutil list "$BASE_DISK" 2>/dev/null \
                | grep -i 'FriendlyARM' | head -n1 | awk '{print $NF}')"
            RETRY_PARTS="$RETRY_PARTS $(diskutil list "$BASE_DISK" 2>/dev/null \
                | awk '/^ +[0-9]+:/ {print $NF}' | grep -E '^disk[0-9]+s[0-9]+$' | tr '\n' ' ')"
            for part in $RETRY_PARTS; do
                [ -n "$part" ] || continue
                sudo mount -t exfat "/dev/$part" "$DIRECT_MP" 2>/dev/null || continue
                if [ -f "$DIRECT_MP/eflasher.conf" ] || ls "$DIRECT_MP"/*.img "$DIRECT_MP"/*.img.gz >/dev/null 2>&1; then
                    progress_message "Mounted $part directly at $DIRECT_MP"
                    MOUNTPOINT="$DIRECT_MP"
                    DIRECT_MOUNT="yes"
                    break
                fi
                sudo umount "$DIRECT_MP" 2>/dev/null || true
            done
            [ -n "$MOUNTPOINT" ] || sudo rmdir "$DIRECT_MP" 2>/dev/null || true
        fi
    else
        sudo partprobe "$DEVICE" >/dev/null 2>&1 || true
        sleep 2
        # Same reasoning as the macOS branch: the data partition is not
        # necessarily the first FAT partition on the card.
        NAMED_PART=""
        OTHER_PARTS=""
        while read -r path fstype label; do
            case "$fstype" in
                vfat|exfat)
                    if [ "$label" = "FRIENDLYARM" ] || [ "$label" = "FriendlyARM" ]; then
                        NAMED_PART="$path"
                    else
                        OTHER_PARTS="$OTHER_PARTS $path"
                    fi
                    ;;
            esac
        done < <(lsblk -ln -o PATH,FSTYPE,LABEL "$DEVICE" | tail -n +2)

        TMP_MP="$(mktemp -d)"
        for part in $NAMED_PART $OTHER_PARTS; do
            [ -n "$part" ] || continue
            sudo mount "$part" "$TMP_MP" 2>/dev/null || continue
            if [ -f "$TMP_MP/eflasher.conf" ] || ls "$TMP_MP"/*.img "$TMP_MP"/*.img.gz >/dev/null 2>&1; then
                progress_message "Data partition is $part"
                MOUNTPOINT="$TMP_MP"
                break
            fi
            sudo umount "$TMP_MP" 2>/dev/null || true
        done
        if [ -z "$MOUNTPOINT" ]; then
            rmdir "$TMP_MP" 2>/dev/null || true
        fi
    fi

    if [ -z "$MOUNTPOINT" ]; then
        progress_message "WARNING: could not mount the FriendlyARM data partition."
        progress_message "The card is still fully written and bootable. Only staging was skipped,"
        progress_message "and staging is a convenience, not something eflasher needs."
        if [ "$OS_NAME" = "Darwin" ] && [ "${MOUNT_BLOCKED:-no}" = "yes" ]; then
            echo
            progress_message "macOS answered 'Blocked'. The partition is exFAT and perfectly"
            progress_message "readable; macOS is refusing the mount request from this terminal."
            progress_message "Two ways around it:"
            progress_message "  1. Unplug and reinsert the card reader. Finder mounts it, then"
            progress_message "     rerun with -N and this script will use the mounted volume."
            progress_message "  2. Grant your terminal access to removable volumes under"
            progress_message "     System Settings > Privacy & Security > Files and Folders."
            echo
            progress_message "Or skip the card entirely. The board can fetch the script itself:"
            progress_message "    wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-nanopi-domotz.sh | bash"
        elif [ "$OS_NAME" = "Darwin" ]; then
            echo
            progress_message "Not a problem. The board can fetch the script itself:"
            progress_message "    wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-nanopi-domotz.sh | bash"
        else
            progress_message "To retry staging without rewriting the card:"
            progress_message "    $0 -N -d $DEVICE"
        fi
    else
        progress_message "FriendlyARM partition mounted at $MOUNTPOINT"

        if [ -n "$OS_IMAGE" ]; then
            progress_message "Copying $(basename "$OS_IMAGE") to the card..."
            sudo cp "$OS_IMAGE" "$MOUNTPOINT/"
        fi

        if [ -n "$SETUP_SCRIPT" ]; then
            progress_message "Copying $(basename "$SETUP_SCRIPT") to the card..."
            sudo cp "$SETUP_SCRIPT" "$MOUNTPOINT/"
            # FAT does not carry the execute bit, so leave instructions.
            sudo tee "$MOUNTPOINT/DOMOTZ-README.txt" > /dev/null <<EOL
Domotz provisioning

This card's FriendlyARM partition carries $(basename "$SETUP_SCRIPT").
It is NOT copied to eMMC by eflasher. To use it after the board has
installed the OS to eMMC and booted from it:

  1. Boot the board from eMMC with the SD card removed.
  2. Insert this SD card once the board is up.
  3. sudo mkdir -p /mnt/sd
     sudo mount /dev/mmcblk\${N}p1 /mnt/sd     (check lsblk for the right device)
     cp /mnt/sd/$(basename "$SETUP_SCRIPT") ~/
     chmod +x ~/$(basename "$SETUP_SCRIPT")
     ./$(basename "$SETUP_SCRIPT")

You do not need this file if the board has internet access. It can fetch
the script itself:

  wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-nanopi-domotz.sh | bash
EOL
        fi

        if [ "$AUTOSTART" != "skip" ] && [ -f "$MOUNTPOINT/eflasher.conf" ]; then
            if [ "$AUTOSTART" = "ask" ]; then
                # An eflasher card carries its OS payloads either as directories
                # holding an info.conf, which is how the FriendlyELEC images are
                # packaged, or as loose .img / .img.gz files.
                CANDIDATES=()
                for entry in "$MOUNTPOINT"/*; do
                    [ -e "$entry" ] || continue
                    name="$(basename "$entry")"
                    if [ -d "$entry" ] && { [ -f "$entry/info.conf" ] || ls "$entry"/*.img "$entry"/*.img.gz "$entry"/*.raw >/dev/null 2>&1; }; then
                        CANDIDATES+=("$name")
                    elif [ -f "$entry" ] && echo "$name" | grep -qEi '\.(img|img\.gz|gz)$'; then
                        CANDIDATES+=("$name")
                    fi
                done

                CURRENT="$(grep -E '^autoStart=' "$MOUNTPOINT/eflasher.conf" | head -n1 | cut -d= -f2- || true)"
                echo
                progress_message "eflasher.conf currently has autoStart=${CURRENT:-(empty)}"

                if [ "${#CANDIDATES[@]}" -eq 0 ]; then
                    progress_message "No OS payloads found on the card."
                    AUTOSTART="skip"
                else
                    progress_message "OS payloads found on the card:"
                    idx=1
                    for c in "${CANDIDATES[@]}"; do
                        echo "      $idx) $c"
                        idx=$((idx + 1))
                    done
                    echo
                    if [ "${#CANDIDATES[@]}" -eq 1 ]; then
                        DEFAULT_CHOICE="${CANDIDATES[0]}"
                        echo "Press Enter to install '${DEFAULT_CHOICE}' to eMMC automatically,"
                    else
                        DEFAULT_CHOICE=""
                        echo "Enter a number or a filename to install that payload automatically,"
                    fi
                    echo "or 'none' to require manual selection on an HDMI monitor,"
                    echo "or 'skip' to leave eflasher.conf untouched."
                    read -r -p "autoStart: " reply

                    if [ -z "$reply" ]; then
                        AUTOSTART="${DEFAULT_CHOICE:-skip}"
                    elif echo "$reply" | grep -qE '^[0-9]+$' \
                        && [ "$reply" -ge 1 ] && [ "$reply" -le "${#CANDIDATES[@]}" ]; then
                        AUTOSTART="${CANDIDATES[$((reply - 1))]}"
                    else
                        AUTOSTART="$reply"
                    fi
                fi
            fi

            if [ "$AUTOSTART" != "skip" ]; then
                VALUE="$AUTOSTART"
                [ "$AUTOSTART" = "none" ] && VALUE=""

                progress_message "Backing up eflasher.conf to eflasher.conf.bak"
                sudo cp "$MOUNTPOINT/eflasher.conf" "$MOUNTPOINT/eflasher.conf.bak"

                # Sets key=value in eflasher.conf, replacing the existing line
                # when there is one and appending it otherwise. Commented-out
                # lines starting with ';' are left alone; they are the file's
                # documentation.
                set_conf() {
                    local key="$1" val="$2" tmp
                    tmp="$(mktemp)"
                    if grep -qE "^${key}=" "$MOUNTPOINT/eflasher.conf"; then
                        sed "s|^${key}=.*|${key}=${val}|" "$MOUNTPOINT/eflasher.conf" > "$tmp"
                    else
                        cat "$MOUNTPOINT/eflasher.conf" > "$tmp"
                        printf '%s=%s\n' "$key" "$val" >> "$tmp"
                    fi
                    sudo cp "$tmp" "$MOUNTPOINT/eflasher.conf"
                    rm -f "$tmp"
                    progress_message "  ${key}=${val}"
                }

                progress_message "Applying eflasher settings:"
                set_conf autoStart "$VALUE"

                if [ "$LOCK_UI" = "yes" ]; then
                    # Install and close, with no route into backup or restore.
                    set_conf autoExit "true"
                    set_conf hideMenuButton "true"
                    set_conf hideBackupAndRestoreButton "true"
                    set_conf welcomeMessage "$WELCOME_MESSAGE"
                    # Left deliberately at false: the full erase pass before
                    # writing is what keeps a reused board free of leftovers.
                    set_conf disableLowFormatting "false"
                fi
            fi
        elif [ "$AUTOSTART" != "skip" ]; then
            progress_message "No eflasher.conf on this card, skipping autoStart configuration."
        fi
    fi
fi

cleanup_mount
trap - EXIT
MOUNTPOINT=""

step_message 5 "Done"
echo "   [+] SD card is ready."
echo
echo "   Next steps:"
echo "   1. Eject the card and insert it into the board's microSD slot."
echo "   2. Power the board on. eflasher boots from the card and writes the OS"
echo "      to eMMC. SYS LED: slow flash while booting, fast flash while"
echo "      installing, slow flash with both LAN LEDs solid when finished."
echo "   3. Power down, remove the SD card, power back up to boot from eMMC."
echo "   4. Log in to the board, fetch the setup script and run it:"
echo "        wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-nanopi-domotz.sh | bash"
echo "------------------------------------------------------------"
