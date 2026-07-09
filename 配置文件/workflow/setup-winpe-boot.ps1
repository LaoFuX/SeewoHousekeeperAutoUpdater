#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Phase 1 BCD setup — create a one-shot WinPE boot entry.

.DESCRIPTION
    Called by phase1-fullautomation.bat after unlock.exe succeeds.

    Steps:
      1. Verify D:\WinPE\boot.wim and boot.sdi exist
      2. Create a fresh /device BCD object for ramdisk options (avoids the
         unreliable well-known {ramdiskoptions} alias on machines where WinRE
         uses its own private ramdisk-options GUID)
      3. Create a new WinPE osloader BCD entry
      4. Set bootsequence so the entry fires exactly once on next boot
      5. Save both GUIDs to D:\SeewoHelper\ so Phase 2 (WinPE startnet.cmd)
         can delete them after use

.PARAMETER WinPEDir
    Directory containing boot.wim and boot.sdi. Default: D:\WinPE

.PARAMETER SeewoHelperDir
    Directory where the GUID marker file is written. Default: D:\SeewoHelper
#>
param(
    [string]$WinPEDir       = "D:\WinPE",
    [string]$SeewoHelperDir = "D:\SeewoHelper"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) { Write-Host "[BCD] $msg" }

# ── Verify prerequisite files ─────────────────────────────────────────────────
$bootWim = Join-Path $WinPEDir "boot.wim"
$bootSdi = Join-Path $WinPEDir "boot.sdi"

if (-not (Test-Path $bootWim)) {
    Write-Error "boot.wim not found: $bootWim`nRun winpe_builder.ps1 on your dev machine first, then copy D:\WinPE to this machine."
    exit 1
}
if (-not (Test-Path $bootSdi)) {
    Write-Error "boot.sdi not found: $bootSdi`nIt should be built alongside boot.wim."
    exit 1
}
Write-Step "boot.wim and boot.sdi found in $WinPEDir"

# ── Detect drive letter of WinPEDir (may not be D: in WinPE, stored in BCD by GUID internally) ──
$winpeDrive = Split-Path -Qualifier $WinPEDir   # e.g. "D:"
$winpePath  = (Split-Path -NoQualifier $WinPEDir).TrimStart('\')   # e.g. "WinPE"

# ── Create a fresh ramdisk options BCD object ─────────────────────────────────
# We do NOT use the well-known {ramdiskoptions} alias. On machines where WinRE
# manages its own private ramdisk-options GUID, that alias either does not exist
# or exists as a read-only placeholder that bcdedit refuses to modify.
# Creating a fresh /device object (same strategy WinRE uses) is always safe and
# does not touch any existing BCD entries.
Write-Step "Creating ramdisk options object ..."
$rdOut = & bcdedit /create /d "SeewoAutoUpdate Ramdisk Options" /device 2>&1 | Out-String
Write-Host $rdOut.Trim()
$rdMatch = [regex]::Match($rdOut, '\{[0-9a-fA-F\-]{36}\}')
if (-not $rdMatch.Success) {
    Write-Error "Could not parse GUID from bcdedit /device creation output:`n$rdOut"
    exit 1
}
$ramdiskGuid = $rdMatch.Value
Write-Step "Ramdisk options GUID: $ramdiskGuid"

$rdSets = @(
    @($ramdiskGuid, "ramdisksdidevice", "partition=$winpeDrive"),
    @($ramdiskGuid, "ramdisksdipath",   "\$winpePath\boot.sdi")
)
foreach ($s in $rdSets) {
    $rdSetOut = & bcdedit /set $s[0] $s[1] $s[2] 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Error "bcdedit /set $($s -join ' ') failed (exit $LASTEXITCODE):`n$($rdSetOut.Trim())"
        exit 1
    }
}
Write-Step "Ramdisk options configured."

# ── Create WinPE BCD entry ────────────────────────────────────────────────────
Write-Step "Creating WinPE BCD entry ..."
$createOut = & bcdedit /create /d "SeewoAutoUpdate-WinPE" /application osloader 2>&1 | Out-String
Write-Host $createOut.Trim()

# Parse the GUID from output: "The entry {xxxxxxxx-...} was successfully created."
$guidMatch = [regex]::Match($createOut, '\{[0-9a-fA-F\-]{36}\}')
if (-not $guidMatch.Success) {
    Write-Error "Could not parse GUID from bcdedit output:`n$createOut"
    exit 1
}
$guid = $guidMatch.Value
Write-Step "New entry GUID: $guid"

# ── Configure the WinPE entry ─────────────────────────────────────────────────
$wimRamdisk = "ramdisk=[$winpeDrive]\$winpePath\boot.wim,$ramdiskGuid"

$bcdSets = @(
    @("/set", $guid, "device",     $wimRamdisk),
    @("/set", $guid, "path",       "\Windows\System32\winload.efi"),
    @("/set", $guid, "osdevice",   $wimRamdisk),
    @("/set", $guid, "systemroot", "\Windows"),
    @("/set", $guid, "detecthal",  "Yes"),
    @("/set", $guid, "winpe",      "Yes"),
    @("/set", $guid, "ems",        "No")
)

foreach ($args in $bcdSets) {
    $out = & bcdedit @args 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "bcdedit $($args -join ' ') failed (exit $LASTEXITCODE): $($out.Trim())"
    }
}
Write-Step "WinPE entry configured."

# ── Set one-shot bootsequence ─────────────────────────────────────────────────
Write-Step "Setting bootsequence (one-shot) ..."
$out = & bcdedit /set "{bootmgr}" bootsequence $guid 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set bootsequence (exit $LASTEXITCODE):`n$($out.Trim())"
    exit 1
}
Write-Step "Bootsequence set. WinPE will boot exactly once on next restart."

# ── Save GUIDs for Phase 2 cleanup ────────────────────────────────────────────
# startnet.cmd reads these files to delete the temporary BCD entries after use.
$guidFile = Join-Path $SeewoHelperDir "_winpe_guid.txt"
Set-Content -Path $guidFile -Value $guid -Encoding ASCII
Write-Step "WinPE GUID saved to: $guidFile"

$rdGuidFile = Join-Path $SeewoHelperDir "_ramdisk_guid.txt"
Set-Content -Path $rdGuidFile -Value $ramdiskGuid -Encoding ASCII
Write-Step "Ramdisk GUID saved to: $rdGuidFile"

Write-Host ""
Write-Host "[BCD] Phase 1 BCD setup complete. Ready to reboot."
