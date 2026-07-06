param(
    [ValidateSet('Auto','Official','Vps')]
    [string]$Source = 'Auto'
)

$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Split-Path -Parent $ScriptRoot
$ConfigPath = Join-Path $RepoRoot 'config\app.ini'

$CFG = @{
    OfficialApiUrl = 'https://e.seewo.com/download/file?code=SeewoServiceSetup'
    VpsUrlB64      = 'aHR0cDovLzE2Ny4xNDguMjAzLjE3My9zZWV3by9TZWV3b1NlcnZpY2VTZXR1cF8xLjYuNi4zOTkzLmV4ZQ=='
    VpsDownloadUrl = $null
    DefaultPaths   = @(
        'C:\Program Files (x86)\Seewo\SeewoHousekeeper'
        'C:\Program Files\Seewo\SeewoHousekeeper'
        'C:\ProgramData\Seewo\SeewoHousekeeper'
        "$env:ProgramFiles\Seewo\SeewoHousekeeper"
    )
    TempDir        = 'C:\Temp\SeewoUpdate'
    LogDir         = (Join-Path $RepoRoot 'logs\update')
    Timeout        = 45
    Cleanup        = $true
}

function Read-IniFile {
    param([string]$Path)
    $result = @{}
    $section = ''
    foreach ($rawLine in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            if (-not $result.ContainsKey($section)) { $result[$section] = @{} }
            continue
        }
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $Matches[1].Trim()
            $val = $Matches[2].Trim()
            if (-not $result.ContainsKey($section)) { $result[$section] = @{} }
            $result[$section][$key] = $val
        }
    }
    return $result
}

function Get-IniValue {
    param($Ini, [string]$Section, [string]$Key, $Default)
    if ($Ini -and $Ini.ContainsKey($Section) -and $Ini[$Section].ContainsKey($Key)) {
        return $Ini[$Section][$Key]
    }
    return $Default
}

function Convert-ToBool {
    param($Value, [bool]$Default)
    if ($null -eq $Value) { return $Default }
    switch -Regex ($Value.ToString().Trim()) {
        '^(1|true|yes|on)$'  { return $true }
        '^(0|false|no|off)$' { return $false }
        default { return $Default }
    }
}

if (Test-Path -LiteralPath $ConfigPath) {
    $ini = Read-IniFile -Path $ConfigPath
    $CFG.OfficialApiUrl = Get-IniValue $ini 'Update' 'OfficialApiUrl' $CFG.OfficialApiUrl
    $CFG.VpsUrlB64      = Get-IniValue $ini 'Update' 'VpsUrlB64' $CFG.VpsUrlB64
    $CFG.VpsDownloadUrl = Get-IniValue $ini 'Update' 'VpsUrl' $CFG.VpsDownloadUrl
    $CFG.TempDir        = Get-IniValue $ini 'Update' 'TempDir' $CFG.TempDir
    $CFG.Timeout        = [int](Get-IniValue $ini 'Update' 'TimeoutSeconds' $CFG.Timeout)
    $CFG.Cleanup        = Convert-ToBool (Get-IniValue $ini 'Update' 'CleanupInstaller' $CFG.Cleanup) $CFG.Cleanup
    $CFG.LogDir         = Get-IniValue $ini 'Log' 'UpdateLogDir' $CFG.LogDir
}

if (-not $CFG.VpsDownloadUrl) {
    $CFG.VpsDownloadUrl = [System.Text.Encoding]::UTF8.GetString(
        [System.Convert]::FromBase64String($CFG.VpsUrlB64))
}

$_logBuf = [System.Collections.Generic.List[string]]::new()
$script:LogFile = $null

function Ensure-Dirs {
    foreach ($dir in @($CFG.TempDir, $CFG.LogDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    if (-not $script:LogFile) {
        $script:LogFile = Join-Path $CFG.LogDir "update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    }
}

function Write-Log {
    param(
        [string]$Msg,
        [ValidateSet('INFO','WARN','ERROR','OK','STEP')][string]$L = 'INFO'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = switch ($L) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'STEP'  { 'Cyan' }
        default { 'Gray' }
    }
    $line = "[$ts][$L] $Msg"
    Write-Host $line -ForegroundColor $color
    $_logBuf.Add($line)
}

function Save-Log {
    try {
        Ensure-Dirs
        $_logBuf | Out-File -LiteralPath $script:LogFile -Encoding UTF8 -Force
    } catch {}
}

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
    } catch {
        return ($Current -ne $Latest)
    }
}

function Get-InstalledVersion {
    param([string]$InstallPath)

    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='SeewoCoreService'" -ErrorAction SilentlyContinue
    if ($wmiSvc -and $wmiSvc.PathName -match 'SeewoService_(\d+\.\d+\.\d+(?:\.\d+)?)') {
        return $Matches[1]
    }

    $regRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rr in $regRoots) {
        $v = Get-ItemProperty $rr -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match 'SeewoHousekeeper|SeewoService' -or
                $_.Publisher -match 'seewo' -or
                $_.InstallLocation -match 'seewo'
            } |
            Select-Object -ExpandProperty DisplayVersion -First 1
        if ($v) { return $v.Trim() }
    }

    if ($InstallPath) {
        foreach ($e in @('SeewoService.exe','SeewoHousekeeper.exe','SeewoFreezeUpdateAssist.exe')) {
            $fp = Join-Path $InstallPath $e
            if (Test-Path -LiteralPath $fp) {
                $v = (Get-Item -LiteralPath $fp -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
                if ($v) { return $v.Trim() }
            }
        }
    }
    return $null
}

function Find-SeewoInstallPath {
    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='SeewoCoreService'" -ErrorAction SilentlyContinue
    if ($wmiSvc -and $wmiSvc.PathName) {
        $exePath = $wmiSvc.PathName.Trim('"') -replace '\s+.*$',''
        $dir = Split-Path $exePath -Parent
        for ($i = 0; $i -lt 5; $i++) {
            if ((Split-Path $dir -Leaf) -match '^SeewoService$') { return $dir }
            $parent = Split-Path $dir -Parent
            if (-not $parent -or $parent -eq $dir) { break }
            $dir = $parent
        }
        return Split-Path $exePath -Parent
    }

    $regRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rr in $regRoots) {
        $entry = Get-ItemProperty $rr -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.DisplayName -match 'SeewoHousekeeper|SeewoService' -or
                 $_.Publisher -match 'seewo') -and $_.InstallLocation
            } |
            Select-Object -First 1
        if ($entry -and (Test-Path -LiteralPath $entry.InstallLocation)) {
            return $entry.InstallLocation.TrimEnd('\')
        }
    }

    foreach ($p in $CFG.DefaultPaths) {
        if (Test-Path -LiteralPath $p) { return $p }
    }

    foreach ($root in @('C:\Program Files','C:\Program Files (x86)','C:\ProgramData')) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hit = Get-ChildItem $root -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('SeewoService.exe','SeewoCore.exe','SeewoHousekeeper.exe') } |
            Select-Object -First 1
        if ($hit) { return $hit.DirectoryName }
    }
    return $null
}

function Get-OfficialLatestInfo {
    try {
        $req = [System.Net.HttpWebRequest]::Create($CFG.OfficialApiUrl)
        $req.Method = 'HEAD'
        $req.Timeout = $CFG.Timeout * 1000
        $req.AllowAutoRedirect = $true
        $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        $resp = $req.GetResponse()
        $cd = $resp.Headers['Content-Disposition']
        $finalUrl = $resp.ResponseUri.AbsoluteUri
        $resp.Close()

        $filename = $null
        if ($cd -match "filename\*=utf-8''(.+)") { $filename = [System.Uri]::UnescapeDataString($Matches[1]) }
        elseif ($cd -match 'filename="([^"]+)"') { $filename = $Matches[1] }
        elseif ($cd -match 'filename=(\S+)') { $filename = $Matches[1] }
        if (-not $filename) {
            $filename = [System.IO.Path]::GetFileName(([uri]$finalUrl).LocalPath)
        }
        $filename = [System.Uri]::UnescapeDataString($filename)
        $version = Parse-VersionFromFilename -Name $filename
        if (-not $version) { throw "Cannot parse version from: $filename" }
        return @{ Version=$version; DownloadUrl=$finalUrl; Filename=$filename; Source='Official'; OK=$true }
    } catch {
        return @{ OK=$false; Error=$_.ToString() }
    }
}

function Get-VpsLatestInfo {
    try {
        $filename = [System.IO.Path]::GetFileName(([uri]$CFG.VpsDownloadUrl).LocalPath)
        $version = Parse-VersionFromFilename -Name $filename
        if (-not $version) { throw "Cannot parse version from VPS filename: $filename" }
        return @{ Version=$version; DownloadUrl=$CFG.VpsDownloadUrl; Filename=$filename; Source='VPS'; OK=$true }
    } catch {
        return @{ OK=$false; Error=$_.ToString() }
    }
}

function Resolve-LatestInfo {
    switch ($Source) {
        'Vps' {
            Write-Log 'Using VPS source.' STEP
            return Get-VpsLatestInfo
        }
        'Official' {
            Write-Log 'Using official source.' STEP
            return Get-OfficialLatestInfo
        }
        default {
            Write-Log 'Using official source first; VPS is fallback.' STEP
            $official = Get-OfficialLatestInfo
            if ($official.OK) { return $official }
            Write-Log "Official source failed: $($official.Error)" WARN
            return Get-VpsLatestInfo
        }
    }
}

function Get-Installer {
    param([string]$Url, [string]$Filename)
    Ensure-Dirs
    $dest = Join-Path $CFG.TempDir $Filename
    if (Test-Path -LiteralPath $dest) {
        Write-Log "Using cached installer: $dest" OK
        return $dest
    }

    Write-Log "Downloading: $Filename" STEP
    Write-Log "From: $Url" INFO
    try {
        $downloaded = $false
        Import-Module BitsTransfer -ErrorAction SilentlyContinue
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            try {
                Start-BitsTransfer -Source $Url -Destination $dest -DisplayName "Downloading $Filename" -ErrorAction Stop
                $downloaded = $true
            } catch {
                Write-Log "BITS failed; falling back to WebClient: $($_.Exception.Message)" WARN
                if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
            }
        }
        if (-not $downloaded) {
            Write-Log 'Using WebClient fallback.' INFO
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
        if (-not (Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -le 0) {
            throw "Downloaded file is missing or empty: $dest"
        }
        $mb = [math]::Round((Get-Item -LiteralPath $dest).Length / 1MB, 1)
        Write-Log "Download complete (${mb} MB)." OK
        return $dest
    } catch {
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
        throw "Download failed: $_"
    }
}

function Install-Seewo {
    param([string]$InstallerPath)
    Write-Log 'Running silent installer.' STEP
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList '/S' -Wait -PassThru -ErrorAction Stop
    switch ($proc.ExitCode) {
        0    { Write-Log 'Installation succeeded.' OK }
        3010 { Write-Log 'Installation succeeded; reboot is required.' WARN }
        default { throw "Installer exited with code $($proc.ExitCode)" }
    }
    return $proc.ExitCode
}

function Invoke-Update {
    param(
        [hashtable]$LatestInfo,
        [string]$InstallPath
    )
    $installerPath = Get-Installer -Url $LatestInfo.DownloadUrl -Filename $LatestInfo.Filename
    $exitCode = Install-Seewo -InstallerPath $installerPath

    Start-Sleep -Seconds 2
    try {
        $newVer = Get-InstalledVersion -InstallPath $InstallPath
        Write-Log "Version after install: $newVer" OK
    } catch {
        Write-Log 'Post-install version check skipped.' WARN
    }

    if ($CFG.Cleanup -and (Test-Path -LiteralPath $installerPath)) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        Write-Log 'Installer removed.' INFO
    }
    return $exitCode
}

Ensure-Dirs

try {
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ' Seewo Housekeeper Update Module' -ForegroundColor Cyan
    Write-Host " Source: $Source" -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''

    Write-Log 'Detecting installed version.' STEP
    $installPath = Find-SeewoInstallPath
    $currentVersion = if ($installPath) { Get-InstalledVersion -InstallPath $installPath } else { $null }
    if ($installPath) { Write-Log "Install path: $installPath" INFO }
    if ($currentVersion) { Write-Log "Current version: $currentVersion" INFO } else { Write-Log 'Current version was not detected.' WARN }

    $latestInfo = Resolve-LatestInfo
    if (-not $latestInfo.OK) {
        throw "Version info unavailable: $($latestInfo.Error)"
    }
    Write-Log "Latest version: $($latestInfo.Version) [$($latestInfo.Source)]" INFO

    if ($currentVersion) {
        if (Compare-Version -Current $currentVersion -Latest $latestInfo.Version) {
            Write-Log "Update required: $currentVersion -> $($latestInfo.Version)" STEP
        } else {
            Write-Log "Already latest or same version: $currentVersion. Reinstalling selected version." WARN
        }
    } else {
        Write-Log "Installed version not detected. Installing $($latestInfo.Version)." WARN
    }

    $code = Invoke-Update -LatestInfo $latestInfo -InstallPath $installPath
    Save-Log
    Write-Host ''
    Write-Host "Log file: $script:LogFile" -ForegroundColor Gray
    exit $code
} catch {
    Write-Log "Update failed: $_" ERROR
    if ($_.ScriptStackTrace) { Write-Log $_.ScriptStackTrace ERROR }
    Save-Log
    Write-Host ''
    Write-Host "Log file: $script:LogFile" -ForegroundColor Gray
    exit 1
}
