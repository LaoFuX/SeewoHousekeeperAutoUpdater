@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

set "SELF=%~f0"

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Requesting administrator privileges...
    echo [*] Please click Yes in the UAC prompt.
    echo.
    powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)

cls
echo.
echo ========================================
echo   Seewo Housekeeper Auto-Update Tool
echo ========================================
echo.
echo [*] Initializing...
echo.

:: Extract PowerShell section to temp file
set "TMPPS=%TEMP%\seewo_updater_%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$src=$env:SELF; $tmp=$env:TMPPS; $lines=[System.IO.File]::ReadAllLines($src,[System.Text.Encoding]::UTF8); $idx=-1; for($i=0;$i-lt$lines.Count;$i++){if($lines[$i]-eq':: PS_CODE_START'){$idx=$i+1;break}}; if($idx-lt0){Write-Host 'ERROR: Cannot find PowerShell marker' -ForegroundColor Red; Read-Host 'Press Enter'; exit 1}; [System.IO.File]::WriteAllLines($tmp,$lines[$idx..($lines.Count-1)],[System.Text.Encoding]::UTF8)"

if not exist "%TMPPS%" (
    echo [!] Failed to extract script. Please contact administrator.
    pause
    exit /b 1
)

:: Run the extracted PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%"

:: Cleanup
del "%TMPPS%" >nul 2>&1

exit /b

:: PS_CODE_START
# ================================================================
# CONFIG
# ================================================================
$CFG = @{
    OfficialApiUrl   = 'https://e.seewo.com/download/file?code=SeewoServiceSetup'
    VpsUrlB64        = 'aHR0cDovLzE2Ny4xNDguMjAzLjE3My9zZWV3by9TZWV3b1NlcnZpY2VTZXR1cF8xLjYuNi4zOTkzLmV4ZQ=='
    DefaultPaths     = @(
        'C:\Program Files (x86)\Seewo\SeewoHousekeeper'
        'C:\Program Files\Seewo\SeewoHousekeeper'
        'C:\ProgramData\Seewo\SeewoHousekeeper'
        "$env:ProgramFiles\Seewo\SeewoHousekeeper"
    )
    TempDir  = 'C:\Temp\SeewoUpdate'
    Timeout  = 45
    Cleanup  = $true
}
$CFG.VpsDownloadUrl = [System.Text.Encoding]::UTF8.GetString(
    [System.Convert]::FromBase64String($CFG.VpsUrlB64))

# ================================================================
# LOGGING
# ================================================================
$_logBuf        = [System.Collections.Generic.List[string]]::new()
$script:LogFile = $null

function Write-Log {
    param([string]$Msg,
          [ValidateSet('INFO','WARN','ERROR','OK','STEP')][string]$L = 'INFO')
    $ts    = Get-Date -Format 'HH:mm:ss'
    $color = switch ($L) {
        'OK'    { 'Green'  } 'WARN'  { 'Yellow' }
        'ERROR' { 'Red'    } 'STEP'  { 'Cyan'   }
        default { 'Gray'   }
    }
    $line = "[$ts][$L] $Msg"
    Write-Host $line -ForegroundColor $color
    $_logBuf.Add($line)
}

function Ensure-TempDir {
    if (-not (Test-Path $CFG.TempDir)) {
        New-Item -ItemType Directory -Path $CFG.TempDir -Force | Out-Null
    }
    if (-not $script:LogFile) {
        $script:LogFile = Join-Path $CFG.TempDir "update_$(Get-Date -f 'yyyyMMdd_HHmmss').log"
    }
}

function Save-Log {
    try {
        Ensure-TempDir
        if ($script:LogFile) { $_logBuf | Out-File $script:LogFile -Encoding UTF8 -Force }
    } catch {}
}

# ================================================================
# VERSION UTILITIES
# ================================================================
function Parse-VersionFromFilename {
    param([string]$Name)
    if ($Name -match '_(\d+\.\d+\.\d+(?:\.\d+)?)\.exe') { return $Matches[1] }
    if ($Name -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    return $null
}

function Compare-Version {
    param([string]$Current, [string]$Latest)
    try {
        $pad = { param($v) ($v.Split('.') + @('0','0','0','0'))[0..3] -join '.' }
        return ([version](& $pad $Current)) -lt ([version](& $pad $Latest))
    } catch { return ($Current -ne $Latest) }
}

function Get-InstalledVersion {
    param([string]$InstallPath)
    # Method 1: Extract version from SeewoCoreService PathName
    # Path pattern: ...\SeewoService_1.5.5.3917\SeewoCore\SeewoCore.exe
    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='SeewoCoreService'" -EA SilentlyContinue
    if ($wmiSvc -and $wmiSvc.PathName -match 'SeewoService_(\d+\.\d+\.\d+(?:\.\d+)?)') {
        return $Matches[1]
    }
    # Method 2: Registry DisplayVersion
    $regRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rr in $regRoots) {
        $v = Get-ItemProperty $rr -EA SilentlyContinue |
             Where-Object { $_.DisplayName -match 'SeewoHousekeeper|SeewoService' -or
                            $_.Publisher    -match 'seewo' -or
                            $_.InstallLocation -match 'seewo' } |
             Select-Object -ExpandProperty DisplayVersion -First 1
        if ($v) { return $v.Trim() }
    }
    # Method 3: Exe file version from install path
    if ($InstallPath) {
        foreach ($e in @('SeewoService.exe','SeewoHousekeeper.exe','SeewoFreezeUpdateAssist.exe')) {
            $fp = Join-Path $InstallPath $e
            if (Test-Path $fp) {
                $v = (Get-Item $fp -EA SilentlyContinue).VersionInfo.ProductVersion
                if ($v) { return $v.Trim() }
            }
        }
    }
    return $null
}

function Find-SeewoInstallPath {
    # Method 1: Derive from SeewoCoreService PathName (most reliable)
    # Example path: "C:\...\SeewoService\SeewoService_1.5.5.3917\SeewoCore\SeewoCore.exe" /winService
    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='SeewoCoreService'" -EA SilentlyContinue
    if ($wmiSvc -and $wmiSvc.PathName) {
        $exePath = $wmiSvc.PathName.Trim('"') -replace '\s+.*$',''
        # Walk up to find the SeewoService root directory
        $dir = Split-Path $exePath -Parent
        for ($i = 0; $i -lt 5; $i++) {
            if ((Split-Path $dir -Leaf) -match '^SeewoService$') { return $dir }
            $parent = Split-Path $dir -Parent
            if (-not $parent -or $parent -eq $dir) { break }
            $dir = $parent
        }
        return Split-Path $exePath -Parent
    }
    # Method 2: Registry InstallLocation
    $regRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rr in $regRoots) {
        $entry = Get-ItemProperty $rr -EA SilentlyContinue |
                 Where-Object { ($_.DisplayName -match 'SeewoHousekeeper|SeewoService' -or
                                 $_.Publisher    -match 'seewo') -and $_.InstallLocation } |
                 Select-Object -First 1
        if ($entry -and (Test-Path $entry.InstallLocation)) {
            return $entry.InstallLocation.TrimEnd('\')
        }
    }
    # Method 3: Known default paths
    foreach ($p in $CFG.DefaultPaths) { if (Test-Path $p) { return $p } }
    # Method 4: Disk search
    foreach ($root in @('C:\Program Files','C:\Program Files (x86)','C:\ProgramData')) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Recurse -Depth 4 -EA SilentlyContinue |
               Where-Object { $_.Name -in @('SeewoService.exe','SeewoCore.exe','SeewoHousekeeper.exe') } |
               Select-Object -First 1
        if ($hit) { return $hit.DirectoryName }
    }
    return $null
}

# ================================================================
# LATEST VERSION: Official API (Plan A)
# ================================================================
function Get-OfficialLatestInfo {
    try {
        $req = [System.Net.HttpWebRequest]::Create($CFG.OfficialApiUrl)
        $req.Method            = 'HEAD'
        $req.Timeout           = $CFG.Timeout * 1000
        $req.AllowAutoRedirect = $true
        $req.UserAgent         = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        $resp     = $req.GetResponse()
        $cd       = $resp.Headers['Content-Disposition']
        $finalUrl = $resp.ResponseUri.AbsoluteUri
        $resp.Close()

        $filename = $null
        if ($cd -match "filename\*=utf-8''(.+)")  { $filename = [System.Uri]::UnescapeDataString($Matches[1]) }
        elseif ($cd -match 'filename="([^"]+)"')  { $filename = $Matches[1] }
        elseif ($cd -match 'filename=(\S+)')      { $filename = $Matches[1] }
        if (-not $filename) {
            $filename = [System.IO.Path]::GetFileName(([uri]$finalUrl).LocalPath)
        }
        $filename = [System.Uri]::UnescapeDataString($filename)
        $version  = Parse-VersionFromFilename -Name $filename
        if (-not $version) { throw "Cannot parse version from: $filename" }
        return @{ Version=$version; DownloadUrl=$finalUrl; Filename=$filename; Source='A'; OK=$true }
    } catch {
        return @{ OK=$false; Error=$_.ToString() }
    }
}

# ================================================================
# LATEST VERSION: VPS Backup (Plan B)
# ================================================================
function Get-VpsLatestInfo {
    $filename = [System.IO.Path]::GetFileName(([uri]$CFG.VpsDownloadUrl).LocalPath)
    $version  = Parse-VersionFromFilename -Name $filename
    if (-not $version) { return @{ OK=$false; Error="Cannot parse version from VPS filename: $filename" } }
    return @{ Version=$version; DownloadUrl=$CFG.VpsDownloadUrl; Filename=$filename; Source='B'; OK=$true }
}

# ================================================================
# DOWNLOAD
# ================================================================
function Get-Installer {
    param([string]$Url, [string]$Filename)
    Ensure-TempDir
    $dest = Join-Path $CFG.TempDir $Filename
    if (Test-Path $dest) { Write-Log "Using cached installer: $dest" OK; return $dest }

    Write-Log "Downloading: $Filename" STEP
    Write-Log "  From: $Url" INFO
    try {
        $downloaded = $false
        Import-Module BitsTransfer -EA SilentlyContinue
        if (Get-Command Start-BitsTransfer -EA SilentlyContinue) {
            try {
                Start-BitsTransfer -Source $Url -Destination $dest -DisplayName "Downloading $Filename" -EA Stop
                $downloaded = $true
            } catch {
                Write-Log "BITS download failed, falling back to WebClient: $($_.Exception.Message)" WARN
                if (Test-Path $dest) { Remove-Item $dest -Force -EA SilentlyContinue }
            }
        }
        if (-not $downloaded) {
            Write-Log "Using WebClient download fallback" INFO
            try {
                [System.Net.ServicePointManager]::SecurityProtocol =
                    [System.Net.ServicePointManager]::SecurityProtocol -bor
                    [System.Net.SecurityProtocolType]::Tls12
            } catch {}
            $wc = New-Object System.Net.WebClient
            try {
                $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
                $wc.DownloadFile($Url, $dest)
            } finally {
                if ($wc) { $wc.Dispose() }
            }
        }
        if (-not (Test-Path $dest) -or (Get-Item $dest).Length -le 0) {
            throw "Downloaded file is missing or empty: $dest"
        }
        $mb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Write-Log "Download complete (${mb} MB)" OK
        return $dest
    } catch {
        if (Test-Path $dest) { Remove-Item $dest -Force -EA SilentlyContinue }
        throw "Download failed: $_"
    }
}

# ================================================================
# INSTALL
# ================================================================
function Install-Seewo {
    param([string]$InstallerPath)
    Write-Log "Running silent install..." STEP
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList '/S' -Wait -PassThru -EA Stop
    switch ($proc.ExitCode) {
        0    { Write-Log 'Installation succeeded' OK }
        3010 { Write-Log 'Installation succeeded (reboot required to finish)' WARN }
        default { throw "Installer exited with code $($proc.ExitCode)" }
    }
    return $proc.ExitCode
}

# ================================================================
# DO UPDATE: shared install logic called from menu options 1 and 2
# ================================================================
function Invoke-Update {
    param(
        [hashtable]$LatestInfo,
        [string]$CurrentVersion,
        [string]$InstallPath
    )
    # 1. Download
    $installerPath = Get-Installer -Url $LatestInfo.DownloadUrl -Filename $LatestInfo.Filename

    # 2. Install
    $exitCode = Install-Seewo -InstallerPath $installerPath

    # 3. Verify
    Start-Sleep -Seconds 2
    try {
        $newVer = Get-InstalledVersion -InstallPath $InstallPath
        Write-Log "Version after install: $newVer" OK
    } catch {
        Write-Log 'Post-install version check skipped (may require reboot)' WARN
    }

    # 4. Cleanup installer
    if ($CFG.Cleanup -and (Test-Path $installerPath)) {
        Remove-Item $installerPath -Force -EA SilentlyContinue
        Write-Log 'Installer removed' INFO
    }

    return $exitCode
}

# ================================================================
# MAIN FLOW
# ================================================================
Ensure-TempDir

# Header
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   Seewo Housekeeper Auto-Update Tool v3.0" -ForegroundColor Cyan
Write-Host "   Host: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""

# Version check phase
Write-Host "  [*] Detecting installed version..." -ForegroundColor Gray -NoNewline
$installPath    = Find-SeewoInstallPath
$currentVersion = if ($installPath) { Get-InstalledVersion -InstallPath $installPath } else { $null }

if ($currentVersion) {
    Write-Host " $currentVersion" -ForegroundColor White
} else {
    Write-Host " not detected" -ForegroundColor Yellow
}

Write-Host "  [*] Checking latest version online..." -ForegroundColor Gray -NoNewline
$latestA = Get-OfficialLatestInfo
if ($latestA.OK) {
    $latestInfo = $latestA
    Write-Host " $($latestA.Version)  [official]" -ForegroundColor White
} else {
    $latestB = Get-VpsLatestInfo
    if ($latestB.OK) {
        $latestInfo = $latestB
        Write-Host " $($latestB.Version)  [VPS fallback]" -ForegroundColor Yellow
        Write-Log "Official API failed: $($latestA.Error)" WARN
    } else {
        Write-Host " FAILED" -ForegroundColor Red
        $latestInfo = $null
    }
}
Write-Host ""

# Determine update status
$updateAvailable = $false
if ($currentVersion -and $latestInfo) {
    $updateAvailable = Compare-Version -Current $currentVersion -Latest $latestInfo.Version
}

# Build option 1 label dynamically
if (-not $latestInfo) {
    $opt1Label = "[1]  (Cannot check - network error)"
    $opt1Color = 'DarkGray'
} elseif (-not $currentVersion) {
    $opt1Label = "[1]  Install Seewo Housekeeper $($latestInfo.Version)"
    $opt1Color = 'Yellow'
} elseif ($updateAvailable) {
    $opt1Label = "[1]  Update:  $currentVersion  ->  $($latestInfo.Version)"
    $opt1Color = 'Yellow'
} else {
    $opt1Label = "[1]  Already latest ($currentVersion) - reinstall?"
    $opt1Color = 'Green'
}

# Show menu
while ($true) {
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  $opt1Label" -ForegroundColor $opt1Color
    Write-Host "  [2]  Use VPS backup source" -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    $sel = Read-Host "  Select [1-2]"

    switch ($sel.Trim()) {
        '1' {
            if (-not $latestInfo) {
                Write-Host "  [!] Version info unavailable. Try option [2] (VPS backup)." -ForegroundColor Red
                Write-Host ""; continue
            }
            Write-Host ""
            Write-Log "--- Starting update (source: $($latestInfo.Source)) ---" STEP
            try {
                $code = Invoke-Update -LatestInfo $latestInfo -CurrentVersion $currentVersion -InstallPath $installPath
                Write-Host ""
                Write-Host "  ========================================" -ForegroundColor Green
                if ($updateAvailable) {
                    Write-Host "   UPDATE COMPLETE: $currentVersion -> $($latestInfo.Version)" -ForegroundColor Green
                } else {
                    Write-Host "   REINSTALL COMPLETE: $($latestInfo.Version)" -ForegroundColor Green
                }
                if ($code -eq 3010) {
                    Write-Host "   NOTE: Reboot required to finish." -ForegroundColor Yellow
                }
                Write-Host "  ========================================" -ForegroundColor Green
            } catch {
                Write-Log "Update failed: $_" ERROR
                Write-Log $_.ScriptStackTrace ERROR
                Save-Log
                Write-Host ""
                Write-Host "  [!] Update failed. See log: $script:LogFile" -ForegroundColor Red
            }
            Write-Host ""
            Read-Host "  Press Enter to exit"
            Save-Log
            exit 0
        }
        '2' {
            Write-Host ""
            $vpsInfo = Get-VpsLatestInfo
            if (-not $vpsInfo.OK) {
                Write-Host "  [!] VPS info error: $($vpsInfo.Error)" -ForegroundColor Red
                Write-Host ""; continue
            }
            Write-Log "--- Starting update (source: VPS) ---" STEP
            try {
                $code = Invoke-Update -LatestInfo $vpsInfo -CurrentVersion $currentVersion -InstallPath $installPath
                Write-Host ""
                Write-Host "  ========================================" -ForegroundColor Green
                Write-Host "   UPDATE COMPLETE via VPS: $($vpsInfo.Version)" -ForegroundColor Green
                if ($code -eq 3010) {
                    Write-Host "   NOTE: Reboot required to finish." -ForegroundColor Yellow
                }
                Write-Host "  ========================================" -ForegroundColor Green
            } catch {
                Write-Log "Update failed (VPS): $_" ERROR
                Write-Host "  [!] Update failed. See log: $script:LogFile" -ForegroundColor Red
            }
            Write-Host ""
            Read-Host "  Press Enter to exit"
            Save-Log
            exit 0
        }
        default {
            Write-Host "  [!] Invalid option. Please enter 1 or 2." -ForegroundColor Red
            Write-Host ""
        }
    }
}

Save-Log
