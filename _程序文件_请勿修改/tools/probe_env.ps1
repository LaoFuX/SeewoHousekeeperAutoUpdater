param(
    [string]$OutputDir
)

$ErrorActionPreference = 'Continue'

function Join-RepoPath {
    param([string]$Child)
    $repoRoot = Split-Path -Parent $PSScriptRoot
    return Join-Path $repoRoot $Child
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-RepoPath 'logs\probe'
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$script:Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:ReportPath = Join-Path $OutputDir "probe_report_$script:Timestamp.txt"

function Write-ProbeLine {
    param([string]$Text = '')
    Add-Content -LiteralPath $script:ReportPath -Value $Text -Encoding UTF8
    Write-Host $Text
}

function Write-Section {
    param([string]$Title)
    Write-ProbeLine ''
    Write-ProbeLine "==== $Title ===="
}

function Write-ObjectText {
    param($Object)
    if ($null -eq $Object) {
        Write-ProbeLine '(none)'
        return
    }
    $text = $Object | Format-List * | Out-String -Width 240
    foreach ($line in ($text -split "`r?`n")) {
        if ($line.Trim().Length -gt 0) {
            Write-ProbeLine $line
        }
    }
}

function Get-CimOrWmi {
    param([string]$ClassName)
    try {
        return Get-CimInstance -ClassName $ClassName -ErrorAction Stop
    } catch {
        return Get-WmiObject -Class $ClassName -ErrorAction SilentlyContinue
    }
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-MatchingUninstallEntries {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $regex = 'Seewo|Easi|Freeze|Deep Freeze|Faronics|DFServ|DFFilter|FrzState'
    $items = foreach ($root in $roots) {
        Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object {
                "$($_.DisplayName) $($_.Publisher) $($_.InstallLocation) $($_.DisplayIcon) $($_.UninstallString)" -match $regex
            } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, DisplayIcon, UninstallString, PSPath
    }
    return $items
}

function Get-MatchingServices {
    $regex = 'Seewo|Easi|Freeze|Deep Freeze|Faronics|DFServ|DFFilter|FrzState'
    $wmiServices = @(Get-CimOrWmi 'Win32_Service' |
        Where-Object {
            "$($_.Name) $($_.DisplayName) $($_.PathName)" -match $regex
        } |
        Select-Object Name, DisplayName, State, StartMode, PathName)

    if ($wmiServices.Count -gt 0) {
        return $wmiServices
    }

    $services = foreach ($svc in (Get-Service -ErrorAction SilentlyContinue | Where-Object { "$($_.Name) $($_.DisplayName)" -match $regex })) {
        $imagePath = ''
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
            $imagePath = (Get-ItemProperty -LiteralPath $regPath -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
        } catch {}
        [pscustomobject]@{
            Name = $svc.Name
            DisplayName = $svc.DisplayName
            State = $svc.Status
            StartMode = ''
            PathName = $imagePath
        }
    }
    return $services
}

function Get-MatchingProcesses {
    $regex = 'Seewo|Easi|Freeze|Deep Freeze|Faronics|DFServ|DFFilter|FrzState'
    $wmiProcesses = @(Get-CimOrWmi 'Win32_Process' |
        Where-Object {
            "$($_.Name) $($_.ExecutablePath) $($_.CommandLine)" -match $regex
        } |
        Select-Object ProcessId, Name, ExecutablePath, CommandLine)

    if ($wmiProcesses.Count -gt 0) {
        return $wmiProcesses
    }

    $processes = foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        $path = ''
        try {
            $path = $proc.Path
        } catch {}
        $name = "$($proc.ProcessName).exe"
        if ("$name $path" -match $regex) {
            [pscustomobject]@{
                ProcessId = $proc.Id
                Name = $name
                ExecutablePath = $path
                CommandLine = ''
            }
        }
    }
    return $processes
}

function Get-CandidateFiles {
    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $dirRegex = 'Seewo|Easi|Freeze|Deep Freeze|Faronics|DFServ|DFFilter|FrzState'
    $fileRegex = 'Seewo|Easi|Freeze|Deep Freeze|Faronics|DFServ|DFFilter|FrzState'
    $hits = New-Object System.Collections.Generic.List[object]

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        try {
            $dirs = Get-ChildItem -LiteralPath $root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match $dirRegex } |
                Select-Object -First 40

            foreach ($dir in $dirs) {
                Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -match $fileRegex } |
                    Select-Object -First 80 |
                    ForEach-Object {
                        $hits.Add([pscustomobject]@{
                            Path = $_.FullName
                            SizeMB = [math]::Round($_.Length / 1MB, 2)
                            LastWriteTime = $_.LastWriteTime
                        })
                    }
            }
        } catch {
            $hits.Add([pscustomobject]@{
                Path = "ERROR scanning $root"
                SizeMB = ''
                LastWriteTime = $_.Exception.Message
            })
        }
    }

    return $hits | Sort-Object Path -Unique
}

function Get-ShortcutTargets {
    $paths = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('StartMenu'),
        [Environment]::GetFolderPath('CommonStartMenu')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $regex = 'Seewo|Easi|Freeze|Deep Freeze|Faronics|DFServ|DFFilter|FrzState'
    $shell = New-Object -ComObject WScript.Shell
    $items = foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        Get-ChildItem -LiteralPath $path -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    $shortcut = $shell.CreateShortcut($_.FullName)
                    $combined = "$($_.Name) $($shortcut.TargetPath) $($shortcut.Arguments)"
                    if ($combined -match $regex) {
                        [pscustomobject]@{
                            Shortcut = $_.FullName
                            Target = $shortcut.TargetPath
                            Arguments = $shortcut.Arguments
                            WorkingDirectory = $shortcut.WorkingDirectory
                        }
                    }
                } catch {}
            }
    }
    return $items
}

function Initialize-WindowApi {
    if ('Win32Probe' -as [type]) {
        return
    }
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Win32Probe
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
'@
}

function Get-TopLevelWindows {
    Initialize-WindowApi
    $windows = New-Object System.Collections.Generic.List[object]

    $callback = [Win32Probe+EnumWindowsProc]{
        param([IntPtr]$hwnd, [IntPtr]$lparam)

        if (-not [Win32Probe]::IsWindowVisible($hwnd)) {
            return $true
        }

        $classBuilder = New-Object System.Text.StringBuilder 256
        [void][Win32Probe]::GetClassName($hwnd, $classBuilder, $classBuilder.Capacity)

        [uint32]$windowProcessId = 0
        [void][Win32Probe]::GetWindowThreadProcessId($hwnd, [ref]$windowProcessId)

        $procName = ''
        $procPath = ''
        try {
            $proc = Get-Process -Id $windowProcessId -ErrorAction Stop
            $procName = $proc.ProcessName
            try {
                $procPath = $proc.Path
            } catch {}
        } catch {}

        $length = [Win32Probe]::GetWindowTextLength($hwnd)
        $titleBuilder = New-Object System.Text.StringBuilder ([Math]::Max($length + 1, 256))
        if ($length -gt 0) {
            [void][Win32Probe]::GetWindowText($hwnd, $titleBuilder, $titleBuilder.Capacity)
        }

        $title = $titleBuilder.ToString()
        $candidateRegex = 'Seewo|Easi|Freeze|Deep Freeze|Faronics|DFServ|DFFilter|FrzState'
        if ([string]::IsNullOrWhiteSpace($title) -and "$procName $procPath" -notmatch $candidateRegex) {
            return $true
        }

        $windows.Add([pscustomobject]@{
            Hwnd = ('0x{0:X}' -f $hwnd.ToInt64())
            Title = $title
            ClassName = $classBuilder.ToString()
            ProcessId = [int]$windowProcessId
            ProcessName = $procName
            ProcessPath = $procPath
        })

        return $true
    }

    [void][Win32Probe]::EnumWindows($callback, [IntPtr]::Zero)
    return $windows
}

function Write-UiElementTree {
    param(
        [IntPtr]$Hwnd,
        [int]$MaxDepth = 5,
        [int]$MaxChildrenPerNode = 80
    )

    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
    } catch {
        Write-ProbeLine "UI Automation assemblies could not be loaded: $($_.Exception.Message)"
        return
    }

    function Get-SafeCurrent {
        param($Element, [string]$Property)
        try {
            return $Element.Current.$Property
        } catch {
            return ''
        }
    }

    function Write-Element {
        param($Element, [int]$Depth)
        if ($Depth -gt $MaxDepth -or $null -eq $Element) {
            return
        }

        $indent = '  ' * $Depth
        $name = Get-SafeCurrent $Element 'Name'
        $automationId = Get-SafeCurrent $Element 'AutomationId'
        $className = Get-SafeCurrent $Element 'ClassName'
        $localType = Get-SafeCurrent $Element 'LocalizedControlType'
        $controlType = ''
        try {
            $controlType = $Element.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''
        } catch {}
        $enabled = Get-SafeCurrent $Element 'IsEnabled'
        $offscreen = Get-SafeCurrent $Element 'IsOffscreen'
        $rect = ''
        try {
            $r = $Element.Current.BoundingRectangle
            $rect = "x=$([int]$r.X),y=$([int]$r.Y),w=$([int]$r.Width),h=$([int]$r.Height)"
        } catch {}

        Write-ProbeLine "$indent- Type=$controlType LocalType=$localType Name=[$name] AutomationId=[$automationId] Class=[$className] Enabled=$enabled Offscreen=$offscreen Rect=[$rect]"

        if ($Depth -eq $MaxDepth) {
            return
        }

        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $child = $null
        try {
            $child = $walker.GetFirstChild($Element)
        } catch {
            return
        }

        $count = 0
        while ($null -ne $child -and $count -lt $MaxChildrenPerNode) {
            Write-Element $child ($Depth + 1)
            $count++
            try {
                $child = $walker.GetNextSibling($child)
            } catch {
                break
            }
        }

        if ($count -ge $MaxChildrenPerNode) {
            Write-ProbeLine "$indent  (child list truncated)"
        }
    }

    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
        if ($null -eq $root) {
            Write-ProbeLine 'UI Automation root was not found.'
            return
        }
        Write-Element $root 0
    } catch {
        Write-ProbeLine "UI Automation probe failed: $($_.Exception.Message)"
    }
}

try {
    Write-ProbeLine "Probe report: $script:ReportPath"
    Write-ProbeLine "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-ProbeLine "Computer: $env:COMPUTERNAME"
    Write-ProbeLine "User: $env:USERNAME"
    Write-ProbeLine "Admin: $(Test-IsAdmin)"

    Write-Section 'PowerShell'
    Write-ProbeLine "PSVersion: $($PSVersionTable.PSVersion)"
    Write-ProbeLine "Host: $($Host.Name)"
    try {
        Get-ExecutionPolicy -List | Out-String -Width 200 | ForEach-Object {
            foreach ($line in ($_ -split "`r?`n")) {
                if ($line.Trim().Length -gt 0) { Write-ProbeLine $line }
            }
        }
    } catch {
        Write-ProbeLine "ExecutionPolicy read failed: $($_.Exception.Message)"
    }

    Write-Section 'Operating System'
    $os = Get-CimOrWmi 'Win32_OperatingSystem' | Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime
    if ($null -eq $os) {
        try {
            $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $os = [pscustomobject]@{
                Caption = "$($cv.ProductName) $($cv.DisplayVersion)"
                Version = [Environment]::OSVersion.Version.ToString()
                BuildNumber = $cv.CurrentBuildNumber
                OSArchitecture = if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }
                InstallDate = ''
                LastBootUpTime = ''
            }
        } catch {
            $os = [pscustomobject]@{
                Caption = [Environment]::OSVersion.Platform
                Version = [Environment]::OSVersion.Version.ToString()
                BuildNumber = [Environment]::OSVersion.Version.Build
                OSArchitecture = if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }
                InstallDate = ''
                LastBootUpTime = ''
            }
        }
    }
    Write-ObjectText $os

    Write-Section 'Screens and DPI'
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
            Write-ProbeLine "Screen: Device=$($screen.DeviceName) Primary=$($screen.Primary) Bounds=$($screen.Bounds) WorkingArea=$($screen.WorkingArea)"
        }
        $form = New-Object System.Windows.Forms.Form
        $graphics = $form.CreateGraphics()
        Write-ProbeLine "DPI: X=$($graphics.DpiX) Y=$($graphics.DpiY)"
        $graphics.Dispose()
        $form.Dispose()
    } catch {
        Write-ProbeLine "Screen probe failed: $($_.Exception.Message)"
    }

    Write-Section 'AutoHotkey'
    $ahkCommand = Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue
    if ($ahkCommand) {
        Write-ProbeLine "AutoHotkey in PATH: $($ahkCommand.Source)"
    } else {
        Write-ProbeLine 'AutoHotkey in PATH: not found'
    }
    $ahkReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { "$($_.DisplayName) $($_.Publisher)" -match 'AutoHotkey' } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation
    Write-ObjectText $ahkReg

    Write-Section 'Matching Services'
    Write-ObjectText (Get-MatchingServices)

    Write-Section 'Matching Processes'
    Write-ObjectText (Get-MatchingProcesses)

    Write-Section 'Matching Uninstall Registry Entries'
    Write-ObjectText (Get-MatchingUninstallEntries)

    Write-Section 'Matching Shortcut Targets'
    Write-ObjectText (Get-ShortcutTargets)

    Write-Section 'Candidate Executable Files'
    Write-ObjectText (Get-CandidateFiles)

    Write-Section 'Visible Top-Level Windows'
    $windows = Get-TopLevelWindows | Sort-Object ProcessName, Title
    Write-ObjectText ($windows | Select-Object Hwnd, Title, ClassName, ProcessId, ProcessName, ProcessPath)

    Write-Section 'Candidate Window UI Automation Trees'
    $windowRegex = 'Seewo|Easi|Freeze|Deep Freeze|Faronics|DFServ|DFFilter|FrzState'
    $candidateWindows = $windows | Where-Object {
        "$($_.Title) $($_.ClassName) $($_.ProcessName) $($_.ProcessPath)" -match $windowRegex
    }

    if (-not $candidateWindows) {
        Write-ProbeLine 'No candidate windows were found.'
        Write-ProbeLine 'Tip: open the target app window and run probe.bat again.'
    } else {
        foreach ($window in $candidateWindows) {
            Write-ProbeLine ''
            Write-ProbeLine "Window: Hwnd=$($window.Hwnd) Process=$($window.ProcessName) Title=[$($window.Title)] Class=[$($window.ClassName)]"
            $handleValue = [Convert]::ToInt64(($window.Hwnd -replace '^0x',''), 16)
            Write-UiElementTree -Hwnd ([IntPtr]$handleValue)
        }
    }

    Write-Section 'Manual Info Needed If Missing'
    Write-ProbeLine '1. Exact target program path for lock/unlock.'
    Write-ProbeLine '2. Exact window title shown during lock/unlock.'
    Write-ProbeLine '3. Password policy: current password, can it be stored in config, and who can read it.'
    Write-ProbeLine '4. Screenshots of each step if UI Automation tree is empty or incomplete.'
    Write-ProbeLine '5. Expected success signal after lock/unlock, such as text, tray icon state, or dialog.'

    Write-ProbeLine ''
    Write-ProbeLine "DONE: $script:ReportPath"
    exit 0
} catch {
    Write-ProbeLine ''
    Write-ProbeLine "FATAL: $($_.Exception.Message)"
    Write-ProbeLine "STACK: $($_.ScriptStackTrace)"
    exit 1
}
