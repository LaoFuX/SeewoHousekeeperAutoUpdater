# Seewo Housekeeper Automation Package

## Entry

Run:

```bat
main.bat
```

`main.bat` is the only teacher-facing entry. It shows the menu and calls independent modules.

## Modules

- `main.bat`: menu, admin elevation, module dispatch.
- `download.bat`: official update path, with VPS fallback.
- `backup.bat`: VPS update path.
- `scripts/seewo-update.ps1`: original update logic moved into a PowerShell module.
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

## Freeze Configuration

Default target:

```ini
Drives=C
```

To also operate E drive:

```ini
Drives=C,E
```

If `Password` is empty, the exe asks for a temporary password at runtime.

## Automation Method

The Seewo UI exposes only a Chromium host window to UI Automation. Internal buttons and fields are not exposed as standard controls, so the automation uses:

```text
window detection + window-relative click ratios + pixel validation
```

This avoids fixed screen coordinates and remains stable when the window moves.
