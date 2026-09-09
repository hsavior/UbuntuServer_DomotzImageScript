<#
.SYNOPSIS
    Writes a FriendlyELEC eflasher image to an SD card, configures eflasher for
    an unattended eMMC install, and stages the Domotz setup script on the card.

.DESCRIPTION
    The Windows counterpart to flash-nanopi-domotz.sh.

    Target hardware: FriendlyELEC NanoPi boards using eflasher.
      NanoPi R5S / R5C (RK3568) use rk3568-eflasher-* images
      NanoPi R3S       (RK3566) use rk3566-eflasher-* images

    Must be run from an elevated PowerShell window. Writing a raw image to a
    physical disk requires administrator rights.

.PARAMETER ImagePath
    The eflasher image, .img or .img.gz. Gzip is decompressed on the fly, so
    there is no need to extract it first.

.PARAMETER DiskNumber
    Target disk number as reported by -List or by Get-Disk.

.PARAMETER List
    Show removable disks and exit. Start here.

.PARAMETER StageOnly
    Skip the erase and write. Just stage files and settings onto a card that
    has already been written.

.PARAMETER AutoStart
    Value for autoStart in eflasher.conf. Defaults to the single OS payload
    found on the card. Use "none" to force manual selection on an HDMI
    monitor, or "skip" to leave eflasher.conf untouched.

.PARAMETER WelcomeMessage
    Banner shown on the eflasher screen.

.PARAMETER NoLockUI
    Leave autoExit, hideMenuButton, hideBackupAndRestoreButton and
    welcomeMessage at the image defaults instead of locking the UI down.

.PARAMETER SetupScript
    Setup script to copy onto the card. Defaults to setup-nanopi-domotz.sh in
    the current folder if present. Optional: the board can download it itself.

.EXAMPLE
    .\Flash-NanoPiDomotz.ps1 -List

.EXAMPLE
    .\Flash-NanoPiDomotz.ps1 -ImagePath .\rk3568-eflasher-ubuntu-noble-core-6.1-arm64-20260721.img.gz -DiskNumber 2

.EXAMPLE
    .\Flash-NanoPiDomotz.ps1 -StageOnly -DiskNumber 2
#>

[CmdletBinding()]
param(
    [string]$ImagePath,
    [int]$DiskNumber = -1,
    [switch]$List,
    [switch]$StageOnly,
    [string]$AutoStart = "ask",
    [string]$WelcomeMessage = "Domotz Collector Installer",
    [switch]$NoLockUI,
    [string]$SetupScript
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([int]$Number, [string]$Text)
    Write-Host "------------------------------------------------------------"
    Write-Host "Step $Number`: $Text"
    Write-Host "------------------------------------------------------------"
}

function Write-Progress2 {
    param([string]$Text)
    Write-Host "   [+] $Text"
}

function Stop-WithError {
    param([string]$Text)
    Write-Host "   [!] $Text" -ForegroundColor Red
    exit 1
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Disks {
    Write-Host ""
    Write-Host "Removable and USB disks on this computer:"
    Write-Host ""
    $disks = Get-Disk | Where-Object { $_.BusType -eq 'USB' -or $_.BusType -eq 'SD' }
    if (-not $disks) {
        Write-Host "  None found. Insert the card reader and try again."
        Write-Host ""
        Write-Host "All disks, for reference:"
        Get-Disk | Format-Table Number, FriendlyName, @{n='Size(GB)';e={[math]::Round($_.Size/1GB,1)}}, BusType, IsSystem, IsBoot -AutoSize
        return
    }
    # A multi-slot card reader shows one row per slot, including empty ones,
    # which appear at 0 GB. Label them so nobody targets an empty slot.
    $disks | Format-Table Number, FriendlyName,
        @{n='Size(GB)';e={[math]::Round($_.Size/1GB,1)}},
        BusType, PartitionStyle,
        @{n='Status';e={ if ($_.Size -eq 0) { 'EMPTY SLOT' } else { 'card present' } }} -AutoSize

    Write-Host "Use the Number column as -DiskNumber."
    if ($disks | Where-Object { $_.Size -eq 0 }) {
        Write-Host "Rows marked EMPTY SLOT are unused slots in your card reader. Ignore them."
    }
}

# ---------------------------------------------------------------------------

if ($List) { Show-Disks; exit 0 }

if (-not (Test-Admin)) {
    Write-Host ""
    Write-Host "This script must run as Administrator." -ForegroundColor Yellow
    Write-Host "Close this window, then right-click Windows PowerShell and choose"
    Write-Host "'Run as administrator', and run the command again."
    exit 1
}

Write-Host "------------------------------------------------------------"
if ($StageOnly) {
    Write-Host "STAGE-ONLY MODE. This script will perform the following actions:"
    Write-Host "1. Validate the target disk"
    Write-Host "2. Locate the FriendlyARM partition on the already-flashed card"
    Write-Host "3. Configure eflasher.conf for an unattended install"
    Write-Host "4. Copy the Domotz setup script onto the card"
    Write-Host "------------------------------------------------------------"
    Write-Host "Nothing is erased and nothing is rewritten in this mode."
} else {
    Write-Host "This script will perform the following actions:"
    Write-Host "1. Validate the eflasher image and the target disk"
    Write-Host "2. Remove all existing partitions on the target disk"
    Write-Host "3. Write the eflasher image to the card (this ERASES the card)"
    Write-Host "4. Configure eflasher.conf for an unattended, locked-down install"
    Write-Host "5. Copy the Domotz setup script onto the card"
    Write-Host "------------------------------------------------------------"
    Write-Host "Disclaimer:"
    Write-Host ""
    Write-Host "1. Purpose: this script prepares an SD card for a FriendlyELEC"
    Write-Host "   NanoPi board (R5S, R5C or R3S) using the eflasher installer image."
    Write-Host "2. By proceeding, you confirm that:"
    Write-Host "   - ALL DATA on the target disk will be destroyed."
    Write-Host "   - You have verified the disk number yourself. Pointing this at"
    Write-Host "     the wrong disk will wipe it and it cannot be undone."
    Write-Host "3. Responsibility: You are responsible for any consequences"
    Write-Host "   resulting from running this script."
}
Write-Host ""

if ($DiskNumber -lt 0 -or (-not $StageOnly -and -not $ImagePath)) {
    Write-Host "Usage:"
    Write-Host "  .\Flash-NanoPiDomotz.ps1 -List"
    Write-Host "  .\Flash-NanoPiDomotz.ps1 -ImagePath <image.img.gz> -DiskNumber <n>"
    Write-Host "  .\Flash-NanoPiDomotz.ps1 -StageOnly -DiskNumber <n>"
    Write-Host ""
    Show-Disks
    exit 1
}

Write-Step 1 "Validating inputs"

if ($StageOnly) {
    Write-Progress2 "Stage-only mode. The card will NOT be erased or rewritten."
} else {
    if (-not (Test-Path -LiteralPath $ImagePath)) {
        Stop-WithError "Image not found: $ImagePath"
    }
    $imageItem = Get-Item -LiteralPath $ImagePath
    if ($imageItem.Extension -notin @('.img', '.gz')) {
        Stop-WithError "Image must be a .img or .img.gz file: $ImagePath"
    }
    Write-Progress2 ("Image: {0} ({1:N0} MB)" -f $imageItem.Name, ($imageItem.Length / 1MB))
}

$disk = $null
try { $disk = Get-Disk -Number $DiskNumber } catch { }
if (-not $disk) { Stop-WithError "No disk with number $DiskNumber. Run with -List." }

if ($disk.IsSystem -or $disk.IsBoot) {
    Stop-WithError "Disk $DiskNumber is a system or boot disk. Refusing to touch it."
}
if ($disk.Size -eq 0) {
    Stop-WithError ("Disk $DiskNumber reports a size of 0. That is an empty slot in " +
                    "your card reader, not a card. Run with -List and pick the row " +
                    "showing a real size.")
}
if ($disk.BusType -notin @('USB', 'SD')) {
    Write-Host ""
    Write-Host "   [!] Disk $DiskNumber is on a $($disk.BusType) bus, not USB or SD." -ForegroundColor Yellow
    Write-Host "       That is unusual for a card reader. Check this is really the SD card." -ForegroundColor Yellow
}

Write-Progress2 "Target: Disk $DiskNumber"
Write-Progress2 ("  Model:    {0}" -f $disk.FriendlyName)
Write-Progress2 ("  Size:     {0:N1} GB" -f ($disk.Size / 1GB))
Write-Progress2 ("  Bus:      {0}" -f $disk.BusType)
$existingVolumes = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
    Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):" }
if ($existingVolumes) {
    Write-Progress2 ("  Drives:   {0}" -f ($existingVolumes -join ', '))
}

if (-not $SetupScript -and (Test-Path -LiteralPath ".\setup-nanopi-domotz.sh")) {
    $SetupScript = ".\setup-nanopi-domotz.sh"
}
if ($SetupScript) {
    if (-not (Test-Path -LiteralPath $SetupScript)) {
        Stop-WithError "Setup script not found: $SetupScript"
    }
    Write-Progress2 "Setup script to stage: $SetupScript"
}

Write-Host ""
if ($StageOnly) {
    Write-Host "Stage-only: files will be copied onto the existing card on disk $DiskNumber."
    $c1 = Read-Host "Type 'yes' to proceed"
    if ($c1 -ne 'yes') { Write-Host "Confirmation not received. Exiting script."; exit 1 }
} else {
    Write-Host "Everything on disk $DiskNumber will be erased."
    $c1 = Read-Host "Type 'yes' to proceed"
    if ($c1 -ne 'yes') { Write-Host "Confirmation not received. Exiting script."; exit 1 }
    Write-Host "------------------------------------------------------------"
    Write-Host "Please confirm again to proceed."
    $c2 = Read-Host "Type 'yes' to proceed"
    if ($c2 -ne 'yes') { Write-Host "Confirmation not received. Exiting script."; exit 1 }
}

if (-not $StageOnly) {

    Write-Step 2 "Clearing the target disk"
    Write-Progress2 "Removing existing partitions so nothing holds a lock on the disk..."
    try {
        Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
    } catch {
        Write-Progress2 "Clear-Disk reported: $($_.Exception.Message)"
        Write-Progress2 "Continuing; the raw write overwrites the partition table anyway."
    }
    Start-Sleep -Seconds 2

    # No offline step here. Windows refuses to take removable media offline,
    # and an SD card in a reader is always removable. Clear-Disk above has
    # already removed the volumes, which is what actually releases the locks.
    $remaining = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter } | ForEach-Object {
            $p = Get-Partition -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue
            if ($p -and $p.DiskNumber -eq $DiskNumber) { $_.DriveLetter }
        }
    if ($remaining) {
        Write-Progress2 "WARNING: drive letters still present on this disk: $($remaining -join ', ')"
        Write-Progress2 "         Close any Explorer window showing them before continuing."
    }

    Write-Step 3 "Writing the eflasher image to the card"
    Write-Progress2 "This takes 5 to 15 minutes. Do not remove the card."

    $devicePath = "\\.\PhysicalDrive$DiskNumber"
    $inFile = $null; $gzStream = $null; $source = $null; $diskStream = $null

    try {
        $inFile = [System.IO.File]::OpenRead($imageItem.FullName)
        if ($imageItem.Extension -eq '.gz') {
            $gzStream = New-Object System.IO.Compression.GZipStream(
                $inFile, [System.IO.Compression.CompressionMode]::Decompress)
            $source = $gzStream
        } else {
            $source = $inFile
        }

        $diskStream = New-Object System.IO.FileStream(
            $devicePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite)

        # Raw disk writes must land on sector boundaries, so the buffer size is
        # a multiple of 512 and any short final read is padded up to the next
        # boundary before being written.
        $bufferSize = 4MB
        $buffer = New-Object byte[] $bufferSize
        $written = 0L
        $lastReport = Get-Date

        while ($true) {
            # GZipStream can return a short read before the end of the stream,
            # so fill the buffer in a loop rather than trusting one Read call.
            $filled = 0
            while ($filled -lt $bufferSize) {
                $n = $source.Read($buffer, $filled, $bufferSize - $filled)
                if ($n -le 0) { break }
                $filled += $n
            }
            if ($filled -le 0) { break }

            $toWrite = $filled
            if (($toWrite % 512) -ne 0) {
                $pad = 512 - ($toWrite % 512)
                for ($i = 0; $i -lt $pad; $i++) { $buffer[$toWrite + $i] = 0 }
                $toWrite += $pad
            }

            $diskStream.Write($buffer, 0, $toWrite)
            $written += $toWrite

            if (((Get-Date) - $lastReport).TotalSeconds -ge 2) {
                $mb = [math]::Round($written / 1MB, 0)
                Write-Progress -Activity "Writing image to disk $DiskNumber" `
                    -Status "$mb MB written" -PercentComplete -1
                $lastReport = Get-Date
            }
            if ($filled -lt $bufferSize) { break }
        }

        $diskStream.Flush()
        Write-Progress -Activity "Writing image to disk $DiskNumber" -Completed
        Write-Progress2 ("Wrote {0:N0} MB." -f ($written / 1MB))
    }
    catch {
        Stop-WithError "Write failed: $($_.Exception.Message)"
    }
    finally {
        if ($diskStream) { $diskStream.Dispose() }
        if ($gzStream)   { $gzStream.Dispose() }
        if ($inFile)     { $inFile.Dispose() }
    }

    Write-Progress2 "Rescanning so Windows picks up the new partition table..."
    Start-Sleep -Seconds 3
    try { Update-HostStorageCache } catch { }
    Start-Sleep -Seconds 3
}

Write-Step 4 "Staging files on the FriendlyARM partition"

# The eflasher card carries several small boot partitions plus one large data
# partition holding eflasher.conf and the OS payloads. Identify it by content,
# not by position, and give Windows a few tries to notice it.
$dataPath = $null
$assignedLetter = $null

for ($attempt = 1; $attempt -le 6; $attempt++) {
    $parts = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue
    foreach ($p in $parts) {
        if ($p.DriveLetter) {
            $candidate = "$($p.DriveLetter):"
            if (Test-Path (Join-Path $candidate "eflasher.conf")) { $dataPath = $candidate; break }
        }
    }
    if ($dataPath) { break }

    # Nothing mounted yet. Try assigning a letter to the largest partition,
    # which is the data partition on these cards.
    if ($attempt -ge 2 -and $parts) {
        $largest = $parts | Sort-Object Size -Descending | Select-Object -First 1
        if ($largest -and -not $largest.DriveLetter) {
            try {
                $free = [char[]](70..90) | Where-Object {
                    -not (Test-Path ("{0}:" -f $_))
                } | Select-Object -First 1
                if ($free) {
                    Write-Progress2 "Assigning drive letter $free`: to the data partition..."
                    Set-Partition -DiskNumber $DiskNumber -PartitionNumber $largest.PartitionNumber `
                        -NewDriveLetter $free
                    $assignedLetter = $free
                    Start-Sleep -Seconds 2
                }
            } catch { }
        }
    }

    Write-Progress2 "Waiting for Windows to mount the card ($attempt of 6)..."
    Start-Sleep -Seconds 3
}

if (-not $dataPath) {
    Write-Progress2 "WARNING: could not find the FriendlyARM partition."
    Write-Progress2 "The card is still fully written and bootable. Only staging was skipped,"
    Write-Progress2 "and staging is a convenience, not something eflasher needs."
    Write-Progress2 ""
    Write-Progress2 "If Windows offered to format a drive, click Cancel. Do not format."
    Write-Progress2 "To retry staging without rewriting the card:"
    Write-Progress2 "    .\Flash-NanoPiDomotz.ps1 -StageOnly -DiskNumber $DiskNumber"
} else {
    Write-Progress2 "FriendlyARM partition is $dataPath"

    if ($SetupScript) {
        Write-Progress2 "Copying $(Split-Path $SetupScript -Leaf) to the card..."
        # Write with Unix line endings; the board will not care for a copy that
        # is only read, but a CRLF shell script fails in confusing ways if it
        # ever gets executed directly.
        $scriptText = (Get-Content -LiteralPath $SetupScript -Raw) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText(
            (Join-Path $dataPath (Split-Path $SetupScript -Leaf)),
            $scriptText,
            (New-Object System.Text.UTF8Encoding($false)))

        $readme = @"
Domotz provisioning

This card carries $(Split-Path $SetupScript -Leaf).
It is NOT copied to eMMC by eflasher.

You do not need this file if the board has internet access. It can fetch
the script itself:

  wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-nanopi-domotz.sh | bash
"@
        [System.IO.File]::WriteAllText(
            (Join-Path $dataPath "DOMOTZ-README.txt"),
            ($readme -replace "`r`n", "`n"),
            (New-Object System.Text.UTF8Encoding($false)))
    }

    $confPath = Join-Path $dataPath "eflasher.conf"
    if ($AutoStart -ne 'skip' -and (Test-Path $confPath)) {

        if ($AutoStart -eq 'ask') {
            $candidates = @()
            Get-ChildItem -LiteralPath $dataPath | ForEach-Object {
                if ($_.PSIsContainer) {
                    if ((Test-Path (Join-Path $_.FullName "info.conf")) -or
                        (Get-ChildItem -LiteralPath $_.FullName -Filter *.img -ErrorAction SilentlyContinue)) {
                        $candidates += $_.Name
                    }
                } elseif ($_.Extension -in @('.img', '.gz')) {
                    $candidates += $_.Name
                }
            }

            $currentLine = Select-String -Path $confPath -Pattern '^autoStart=' | Select-Object -First 1
            $current = if ($currentLine) { $currentLine.Line -replace '^autoStart=', '' } else { '' }
            Write-Host ""
            Write-Progress2 "eflasher.conf currently has autoStart=$(if ($current) { $current } else { '(empty)' })"

            if ($candidates.Count -eq 0) {
                Write-Progress2 "No OS payloads found on the card."
                $AutoStart = 'skip'
            } else {
                Write-Progress2 "OS payloads found on the card:"
                for ($i = 0; $i -lt $candidates.Count; $i++) {
                    Write-Host ("      {0}) {1}" -f ($i + 1), $candidates[$i])
                }
                Write-Host ""
                if ($candidates.Count -eq 1) {
                    Write-Host "Press Enter to accept the default shown in brackets,"
                    Write-Host "or 'none' to require manual selection on an HDMI monitor,"
                    Write-Host "or 'skip' to leave eflasher.conf untouched."
                    $reply = Read-Host "autoStart [$($candidates[0])]"
                } else {
                    Write-Host "Enter a number or a name to install that payload automatically,"
                    Write-Host "or 'none' to require manual selection on an HDMI monitor,"
                    Write-Host "or 'skip' to leave eflasher.conf untouched."
                    $reply = Read-Host "autoStart"
                }

                if ([string]::IsNullOrWhiteSpace($reply)) {
                    $AutoStart = if ($candidates.Count -eq 1) { $candidates[0] } else { 'skip' }
                } elseif ($reply -match '^\d+$' -and
                          [int]$reply -ge 1 -and [int]$reply -le $candidates.Count) {
                    $AutoStart = $candidates[[int]$reply - 1]
                } else {
                    $AutoStart = $reply
                }
            }
        }

        if ($AutoStart -ne 'skip') {
            $value = if ($AutoStart -eq 'none') { '' } else { $AutoStart }

            Write-Progress2 "Backing up eflasher.conf to eflasher.conf.bak"
            Copy-Item -LiteralPath $confPath -Destination "$confPath.bak" -Force

            # eflasher.conf uses LF endings and documents itself in ';' comment
            # lines. Match only real setting lines, and write LF back out.
            $lines = [System.IO.File]::ReadAllText($confPath) -replace "`r`n", "`n"
            $lineArray = $lines -split "`n"

            function Set-Conf {
                param([string[]]$Content, [string]$Key, [string]$Value)
                $found = $false
                $out = foreach ($line in $Content) {
                    if ($line -match "^$([regex]::Escape($Key))=") {
                        $found = $true
                        "$Key=$Value"
                    } else {
                        $line
                    }
                }
                if (-not $found) { $out = $out + "$Key=$Value" }
                Write-Progress2 "  $Key=$Value"
                return $out
            }

            Write-Progress2 "Applying eflasher settings:"
            $lineArray = Set-Conf -Content $lineArray -Key 'autoStart' -Value $value

            if (-not $NoLockUI) {
                $lineArray = Set-Conf -Content $lineArray -Key 'autoExit' -Value 'true'
                $lineArray = Set-Conf -Content $lineArray -Key 'hideMenuButton' -Value 'true'
                $lineArray = Set-Conf -Content $lineArray -Key 'hideBackupAndRestoreButton' -Value 'true'
                $lineArray = Set-Conf -Content $lineArray -Key 'welcomeMessage' -Value $WelcomeMessage
                # Left at false on purpose: the full erase pass before writing
                # is what keeps a reused board free of leftovers.
                $lineArray = Set-Conf -Content $lineArray -Key 'disableLowFormatting' -Value 'false'
            }

            [System.IO.File]::WriteAllText($confPath, ($lineArray -join "`n"),
                (New-Object System.Text.UTF8Encoding($false)))
        }
    } elseif ($AutoStart -ne 'skip') {
        Write-Progress2 "No eflasher.conf on this card, skipping configuration."
    }
}

Write-Step 5 "Done"
Write-Host "   [+] SD card is ready."
Write-Host ""
Write-Host "   Eject the card safely from the taskbar before removing it."
Write-Host ""
Write-Host "   Next steps:"
Write-Host "   1. Insert the card into the board's microSD slot."
Write-Host "   2. Power the board on. eflasher writes the OS to eMMC."
Write-Host "      SYS LED: slow flash while booting, fast flash while installing,"
Write-Host "      slow flash with both LAN LEDs solid when finished."
Write-Host "   3. Remove the SD card. The board reboots from eMMC by itself."
Write-Host "   4. Log in to the board and run:"
Write-Host "        wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-nanopi-domotz.sh | bash"
Write-Host "------------------------------------------------------------"
