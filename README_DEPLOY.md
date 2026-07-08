# Seewo Housekeeper Automation Package

## Teacher-facing Entries

Use two direct entries instead of the old numbered menu:

```bat
unlock-and-restart.bat
```

Unlocks/unfreezes the disk, then reboots.

```bat
main.bat
```

Updates Seewo Housekeeper, then runs lock automation and reboots.

Run `unlock-and-restart.bat` first. After the reboot, run `main.bat`.

`main.bat` assumes the machine is already unfrozen/writable. If the disk is still frozen, the update may be reverted after reboot.

## Modules

- `unlock-and-restart.bat`: unlock + reboot workflow.
- `main.bat`: update + lock + reboot workflow.
- `download.bat`: official update path, with VPS fallback.
- `backup.bat`: VPS update path for maintenance troubleshooting.
- `scripts/seewo-update.ps1`: update logic.
- `src/unlock.ahk`: development source for unfreezing/unlocking the protected disk.
- `src/lock.ahk`: development source for freezing/locking the protected disk.
- `config/app.ini`: paths, password, drives, timings, click ratios, and log directories.
- `logs/update`: update logs.
- `logs/freeze`: GUI automation logs.

## Build

Install AutoHotkey v1.1 on the development computer, then run:

```bat
build\compile.bat
```

This creates:

```text
unlock.exe
lock.exe
```

The teacher computer does not need AutoHotkey installed after compilation.

## Automation Method

The Seewo UI exposes only a Chromium host window to UI Automation. Internal buttons and fields are not exposed as standard controls, so the automation uses:

```text
window detection + window-relative click ratios + pixel validation
```

This avoids fixed screen coordinates and remains stable when the window moves.

## Touch Keyboard Handling

Some touchscreen Windows machines automatically open the touch keyboard when the Seewo password field receives focus. The automation suppresses this before the GUI flow starts:

```ini
[Keyboard]
SuppressTouchKeyboard=1
DisableDesktopAutoInvoke=1
RestoreDesktopAutoInvoke=1
KillTouchKeyboardProcesses=1
```

By default, the script temporarily writes `EnableDesktopModeAutoInvoke=0` under the current user's `TabletTip` registry key, then restores the original value before the restart step or on script exit. If a classroom machine still opens the keyboard during maintenance and you want to keep Windows auto-invoke disabled after the run, set:

```ini
RestoreDesktopAutoInvoke=0
```
