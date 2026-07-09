#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Build a minimal WinPE image with Phase 2 automation baked in.

.DESCRIPTION
    Requires Windows ADK + Windows PE add-on to be installed.
    Default ADK path: C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit

    What this script does:
      1. Locates winpe.wim and boot.sdi directly from the ADK installation
         (does NOT call copype.cmd — avoids environment variable dependency)
      2. Copies winpe.wim to a temp working directory as boot.wim
      3. Mounts boot.wim with DISM
      4. Copies our custom startnet.cmd into the image
      5. Unmounts and commits
      6. Copies boot.wim and boot.sdi to the output directory (default D:\WinPE\)

.PARAMETER OutputDir
    Where to place boot.wim and boot.sdi. Default: <project_root>\winpe

.PARAMETER Arch
    Architecture: amd64 or arm64. Default: amd64

.PARAMETER AdkRoot
    Path to the ADK installation. Auto-detected if not specified.

.EXAMPLE
    .\winpe_builder.ps1
    .\winpe_builder.ps1 -OutputDir "D:\WinPE" -Arch amd64
#>
param(
    [string]$OutputDir = "",
    [ValidateSet("amd64","arm64")]
    [string]$Arch = "amd64",
    [string]$AdkRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Default OutputDir to project's winpe\ folder ─────────────────────────────
if ($OutputDir -eq "") {
    $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) "winpe"
    Write-Host "[Config] Output directory (default): $OutputDir"
}

# ── Locate ADK ────────────────────────────────────────────────────────────────
$adkCandidates = @(
    "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit",
    "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit"
)
if ($AdkRoot -ne "") { $adkCandidates = @($AdkRoot) + $adkCandidates }

$adkPath = $null
foreach ($candidate in $adkCandidates) {
    if (Test-Path (Join-Path $candidate "Windows Preinstallation Environment")) {
        $adkPath = $candidate
        break
    }
}
if (-not $adkPath) {
    Write-Error @"
Windows PE add-on for ADK not found.
Install from: https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install
Looked in: $($adkCandidates -join "`n")
"@
    exit 1
}
Write-Host "[ADK] Found at: $adkPath"

$winpePath = Join-Path $adkPath "Windows Preinstallation Environment\$Arch"

# ── Locate source files directly (no copype.cmd needed) ──────────────────────
$wimSrc = Join-Path $winpePath "en-us\winpe.wim"
$sdiSrc = Join-Path $winpePath "Media\Boot\boot.sdi"

if (-not (Test-Path $wimSrc)) {
    Write-Error "winpe.wim not found at: $wimSrc`nMake sure the Windows PE add-on for $Arch is installed."
    exit 1
}
if (-not (Test-Path $sdiSrc)) {
    Write-Error "boot.sdi not found at: $sdiSrc"
    exit 1
}
Write-Host "[ADK] winpe.wim : $wimSrc"
Write-Host "[ADK] boot.sdi  : $sdiSrc"

# ── Working directory ─────────────────────────────────────────────────────────
$workDir  = Join-Path $env:TEMP "WinPEWork_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$mountDir = Join-Path $workDir "mount"
$bootWim  = Join-Path $workDir "boot.wim"

Write-Host "[Build] Working directory: $workDir"
New-Item -ItemType Directory -Path $mountDir -Force | Out-Null

# ── Step 1: Copy winpe.wim → boot.wim ────────────────────────────────────────
Write-Host "[Build] Copying winpe.wim → boot.wim ..."
Copy-Item -Path $wimSrc -Destination $bootWim -Force

# ── Step 2: Mount boot.wim ────────────────────────────────────────────────────
Write-Host "[DISM] Mounting boot.wim ..."
& dism /Mount-Image /ImageFile:"$bootWim" /Index:1 /MountDir:"$mountDir"
if ($LASTEXITCODE -ne 0) {
    Write-Error "DISM mount failed (exit code $LASTEXITCODE)"
    exit 1
}

# ── Step 3: Inject startnet.cmd ───────────────────────────────────────────────
$startnetSrc = Join-Path $PSScriptRoot "startnet.cmd"
if (-not (Test-Path $startnetSrc)) {
    Write-Error "startnet.cmd not found next to this script: $startnetSrc"
    & dism /Unmount-Image /MountDir:"$mountDir" /Discard | Out-Null
    exit 1
}

$startnetDst = Join-Path $mountDir "Windows\System32\startnet.cmd"
Write-Host "[Inject] Copying startnet.cmd -> $startnetDst"
Copy-Item -Path $startnetSrc -Destination $startnetDst -Force

# ── Step 4: Unmount and commit ────────────────────────────────────────────────
Write-Host "[DISM] Committing and unmounting ..."
& dism /Unmount-Image /MountDir:"$mountDir" /Commit
if ($LASTEXITCODE -ne 0) {
    Write-Error "DISM unmount/commit failed (exit code $LASTEXITCODE)"
    exit 1
}

# ── Step 5: Copy output files ─────────────────────────────────────────────────
Write-Host "[Output] Copying to: $OutputDir"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Copy-Item -Path $bootWim -Destination (Join-Path $OutputDir "boot.wim") -Force
Write-Host "[Output] boot.wim copied."

Copy-Item -Path $sdiSrc -Destination (Join-Path $OutputDir "boot.sdi") -Force
Write-Host "[Output] boot.sdi copied."

# ── Cleanup working directory ─────────────────────────────────────────────────
Write-Host "[Cleanup] Removing working directory ..."
Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "============================================================"
Write-Host " WinPE build complete."
Write-Host " Output: $OutputDir"
Write-Host " Files:  boot.wim  boot.sdi"
Write-Host ""
Write-Host " Next step:"
Write-Host "   Copy $OutputDir to D:\WinPE on every target machine."
Write-Host "   Then run: 0_全自动化更新.bat on the target machine."
Write-Host "============================================================"
