# Setting up a NanoPi as a Domotz Collector

This guide takes you from a blank SD card to a running Domotz collector on a
FriendlyELEC NanoPi R5S, R5C or R3S. Budget about 45 minutes, most of it
waiting.

You will do three things:

1. Write the installer image to an SD card.
2. Let the board copy the operating system to its internal storage (eMMC).
3. Run a setup script that installs and configures the Domotz Collector.

---

## What you need

- NanoPi R5S, R5C or R3S with its power supply
- microSD card, 16 GB or larger, and a card reader
- Ethernet cable and a network connection with DHCP
- A computer running Windows, macOS or Linux
- Your Domotz account login

You do **not** need a monitor or keyboard for the board. Everything is done
over the network.

### Files provided

| File | Runs on | Purpose |
|---|---|---|
| `Flash-NanoPiDomotz.ps1` | Windows | Writes the SD card and prepares it |
| `flash-nanopi-domotz.sh` | macOS or Linux | The same thing, for Mac and Linux |

Use the one that matches your computer. You do not need the other. Step 2
downloads the right script for you, so there is nothing to copy across by hand.

The setup script is not something you need to copy anywhere. The board
downloads it itself in step 5.

### The image

Download the eFlasher image for **your board**, from the FriendlyELEC download
page linked off its wiki page. The two boards use different chips, so the
images are not interchangeable.

| Board | Wiki page | Image name |
|---|---|---|
| R5S, R5C | [NanoPi R5S](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R5S) | `rk3568-eflasher-ubuntu-noble-core-6.1-arm64-YYYYMMDD.img.gz` |
| R3S | [NanoPi R3S](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R3S) | `rk3566-eflasher-ubuntu-noble-core-6.1-arm64-YYYYMMDD.img.gz` |

Note the `rk3568` against `rk3566` at the start. Using the wrong one leaves you
with a board that does nothing when powered on. The date on the end changes
with each release. Any recent one is fine.

---

## Step 1: Check the SD card

Anything already on the card will be destroyed. Copy off anything you want to
keep before going further.

A 16 GB card is the practical minimum. A larger card works, and the unused
space is simply left alone.

---

## Step 2: Write the image to the SD card

Follow the section for your computer.

### Windows

Save the downloaded image in your Downloads folder. The script is downloaded
in step 2.

**1. Open PowerShell as Administrator.** Click Start, type `PowerShell`,
right-click **Windows PowerShell** and choose **Run as administrator**. Writing
to an SD card needs administrator rights, and the script will stop and tell you
so if this is missed.

**2. Download the script and allow it to run.** Windows blocks all PowerShell
scripts by default. These commands download the script and lift that block for
this window only. Nothing about your computer's security settings is changed
permanently.

```
cd $HOME\Downloads
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Invoke-WebRequest -Uri https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/Flash-NanoPiDomotz.ps1 -OutFile Flash-NanoPiDomotz.ps1
Unblock-File .\Flash-NanoPiDomotz.ps1
```

**3. List the disks and find your SD card.**

```
.\Flash-NanoPiDomotz.ps1 -List
```

Look for the row whose size matches your card and that says `card present`.
Note its Number. Rows marked `EMPTY SLOT` are unused slots in a multi-slot card
reader; ignore them.

**4. Write the card**, using your image filename and the Number from step 3:

```
.\Flash-NanoPiDomotz.ps1 -ImagePath .\rk3568-eflasher-ubuntu-noble-core-6.1-arm64-YYYYMMDD.img.gz -DiskNumber 3
```

The script shows what it found and asks you to type `yes` twice. Read the disk
details before confirming. This is the one step that cannot be undone.

Writing takes 5 to 15 minutes. When it asks about `autoStart`, press Enter to
accept the default shown in brackets.

**5. If Windows offers to format a drive, click Cancel.** This can pop up more
than once while the card is being written. Never click Format. The card is
fine; Windows simply cannot read the board's Linux partitions.

**6. Eject the card safely** from the taskbar before removing it.

### macOS

1. Save the downloaded image in your Downloads folder.
2. Open Terminal. Find it in Applications, Utilities, Terminal, or press
   Command and Space, type `Terminal` and press Enter.
3. Copy and paste these three lines, one at a time, pressing Enter after each.
   The first line moves you into your Downloads folder, which is where the
   image is. The second downloads the script, and the third makes it runnable.

   ```
   cd ~/Downloads
   curl -O https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/flash-nanopi-domotz.sh
   chmod +x flash-nanopi-domotz.sh
   ```

4. Insert the SD card, then list the available disks:

   ```
   ./flash-nanopi-domotz.sh -l
   ```

   Find your card in the list. It will show as external and physical, and the
   size will match your card. Note the identifier, something like `/dev/disk4`.

5. Write the card, substituting your image name and disk identifier:

   ```
   ./flash-nanopi-domotz.sh -i rk3568-eflasher-ubuntu-noble-core-6.1-arm64-YYYYMMDD.img.gz -d /dev/disk4
   ```

6. The script shows you what it found and asks you to type `yes` twice. Read
   the disk details it prints before confirming. This is the one step that
   cannot be undone.
7. Enter your Mac password when prompted. Nothing appears on screen as you
   type it; that is normal. Press Enter when done.
8. Writing takes 5 to 15 minutes. Press Ctrl-T at any time to see progress.

Keep this Terminal window open for the whole process. If you close it and come
back later, run `cd ~/Downloads` again before the other commands.

### Linux

Identical to macOS, except the disk identifier looks like `/dev/sdb` or
`/dev/mmcblk0`. Open a terminal and run these in order. The first line moves
you into your Downloads folder, where the image is:

```
cd ~/Downloads
wget https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/flash-nanopi-domotz.sh
chmod +x flash-nanopi-domotz.sh
./flash-nanopi-domotz.sh -l
./flash-nanopi-domotz.sh -i rk3568-eflasher-ubuntu-noble-core-6.1-arm64-YYYYMMDD.img.gz -d /dev/sdb
```

---

## Step 3: Install the operating system to the board

1. Eject the SD card from your computer and insert it into the microSD slot on
   the NanoPi.
2. Connect the Ethernet cable to the **WAN** port. The R5S has three ports and
   the R3S has two; in both cases WAN is the one nearest the power connector
   and is labelled on the case.
3. Connect power. The board starts on its own. There is no power switch.
4. Watch the SYS LED:

   | SYS LED | LAN and WAN LEDs | Meaning |
   |---|---|---|
   | Solid | Off | Powered on |
   | Slow flash | Off | Booting |
   | Fast flash | Off | Installing to eMMC |
   | Slow flash | Both solid | Installation finished |

   The install takes roughly 10 to 20 minutes. The full erase pass before
   writing accounts for most of that. Leave it alone until both the LAN and
   WAN LEDs are solid.

5. Once installation is finished, remove the SD card. The board reboots by
   itself and starts from its internal storage.

If nothing appears to happen and the SYS LED never starts flashing fast,
see Troubleshooting below.

---

## Step 4: Find the board on your network

The board requests an address by DHCP. Find it in your router's client list,
looking for a device named `nanopi-r5s`, `nanopi-r3s` or similar.

Confirm you can reach it:

```
ssh pi@<board-ip>
```

The default password is `pi`.

**Change the password immediately.** Once logged in:

```
passwd
```

---

## Step 5: Run the setup script

Log in to the board:

```
ssh pi@<board-ip>
```

Then run this single command:

```
wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-nanopi-domotz.sh | bash
```

That is the whole installation. Copy and paste it exactly.

The script explains what it will do and asks you to type `yes` twice. It then
asks one question:

> Automatically reboot after kernel/security updates if required? (yes/no) [yes]

Press Enter to accept `yes`, which is recommended. It keeps the collector
patched without anyone having to visit it, and the reboot only happens at 02:00
and only when an update actually requires one.

The script runs for 10 to 20 minutes depending on how many updates are
pending. It prints each step as it goes. Leave it running.

When it finishes it prints the web address for the collector.

---

## Step 6: Activate the collector

In a browser on the same network, go to:

```
http://<board-ip>:3000
```

Use `http`, not `https`. Sign in with your Domotz account and follow the
prompts to link this collector to your account.

If the script told you a reboot was needed, reboot now:

```
sudo reboot
```

The collector starts automatically on every boot from here on. Nothing else is
required.

---

## Troubleshooting

**The board never starts installing (SYS LED never flashes fast).**
The card was probably not written correctly. Reflash it. If it still fails,
try a different SD card. Cheap or worn cards are the most common cause.

**I cannot find the board on the network.**
Confirm the cable is in the WAN port and that the port's LED is lit. Confirm
your network hands out DHCP addresses. Give it two minutes after power-on
before looking.

**macOS says "failed to mount: Blocked".**
Harmless, and the script works around it. It happens because macOS is strict
about the partition layout on these cards. The card itself is fine.

**macOS says the disk is not readable, offering to Initialize.**
Click **Ignore**. Never click Initialize. macOS cannot read the board's
partitions, which is expected.

**Windows says "running scripts is disabled on this system".**
The commands in step 2 of the Windows section were not run, or were run in a
different window than the one you are using now. Run them again in the same
window, then retry.

**Windows says "Access is denied" or the script says it must run as
Administrator.**
The PowerShell window is not elevated. Close it, then right-click Windows
PowerShell and choose Run as administrator.

**Windows offers to format the drive.**
Always click Cancel. This is normal and does not mean anything went wrong.

**Step 5 prints a download error, or returns to the prompt without doing
anything.**
The board has no internet access. It needs the internet for both the script
download and the Domotz install. Check that the WAN port is connected to a
network with internet access, then try again. If the command returns instantly
with no output at all, that is the same problem.

**The setup script fails at the Domotz install step.**
Almost always a network or timing problem on the first boot. Wait a minute and
run the script again. It is safe to run twice.

**Something else went wrong.**
Note which numbered step failed and what it printed, and send that along. The
step numbers make it quick to pin down.

---

## What the setup script actually does

For reference, in the order it does them:

1. Updates the system and installs supporting packages
2. Enables automatic security updates
3. Optionally enables automatic reboot after kernel updates
4. Loads the `tun` kernel module, needed for remote connections
5. Installs and prepares snapd
6. Installs the Domotz Collector
7. Grants the collector the permissions it needs
8. Opens port 3000 in the firewall
9. Sets all network ports to DHCP
10. Adjusts DNS handling so VPN on Demand works correctly
11. Disables cloud-init's network configuration
12. Disables IPv6
13. Verifies the services it configured will start again after a reboot

Everything it changes is standard system configuration. Nothing is
proprietary, and the script is plain text you are welcome to read first.
