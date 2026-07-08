# 希沃管家自动更新工具 - 简洁交付版

## 一、老师只需要点击这两个入口

把整个文件夹交给老师后，根目录只需要关注两个 BAT：

```text
1_解锁冰点并重启.bat
2_更新希沃管家并上锁重启.bat
```

推荐完整流程：

```text
第一步：双击 1_解锁冰点并重启.bat
  解锁/解冻冰点，然后电脑重启。

第二步：电脑重启回来后，双击 2_更新希沃管家并上锁重启.bat
  更新希沃管家，更新成功后上锁/冻结冰点，然后电脑重启。
```

`2_更新希沃管家并上锁重启.bat` 不会先解锁。它适用于电脑已经处于解冻/可写状态的维护场景。

## 二、目录结构

当前交付结构：

```text
希沃管家自动更新工具/
│
├─ 1_解锁冰点并重启.bat
├─ 2_更新希沃管家并上锁重启.bat
│
└─ _程序文件_请勿修改/
   ├─ bin/
   │  ├─ unlock.exe
   │  └─ lock.exe
   │
   ├─ config/
   │  └─ app.ini
   │
   ├─ workflow/
   │  ├─ unlock-and-restart.bat
   │  └─ update-lock-restart.bat
   │
   ├─ update/
   │  ├─ download.bat
   │  ├─ backup.bat
   │  └─ scripts/
   │     └─ seewo-update.ps1
   │
   ├─ logs/
   │  ├─ freeze/
   │  └─ update/
   │
   ├─ src/
   ├─ build/
   ├─ tools/
   ├─ pics/
   └─ docs/
```

根目录两个 BAT 是老师入口。`_程序文件_请勿修改` 是内部程序目录，平时不要改名、移动或删除。

## 三、内部模块说明

```text
bin/unlock.exe
  解锁/解冻 GUI 自动化程序，由 AutoHotkey 源码编译生成。

bin/lock.exe
  上锁/冻结 GUI 自动化程序，由 AutoHotkey 源码编译生成。

config/app.ini
  配置文件。保存密码、目标磁盘、希沃启动路径、等待时间、窗口修复和触摸键盘处理策略。

workflow/unlock-and-restart.bat
  内部解锁流程。根目录入口 1 会调用它。

workflow/update-lock-restart.bat
  内部更新并上锁流程。根目录入口 2 会调用它。

update/download.bat
  更新入口。优先使用官方源，官方源不可用时走 VPS 备用源。

update/backup.bat
  VPS 备用更新入口，主要给维护人员手动排查时使用。

update/scripts/seewo-update.ps1
  下载、版本检测、静默安装的 PowerShell 核心逻辑。

logs/freeze
  解锁/上锁 GUI 自动化日志。

logs/update
  希沃管家更新日志。
```

老师电脑不需要安装 AutoHotkey，也不需要携带 AutoHotkey.exe。

## 四、常用配置

配置文件位置：

```text
_程序文件_请勿修改/config/app.ini
```

### 1. 密码

```ini
[Freeze]
Password=
```

如果 `Password=` 留空，运行时会弹出密码输入框。

如果要全自动运行，可以填写冰点密码：

```ini
Password=123456
```

注意：密码会明文保存在配置文件里，交付包不要发给无关人员。

### 2. 目标磁盘

只处理 C 盘：

```ini
Drives=C
```

同时处理 C 盘和 E 盘：

```ini
Drives=C,E
```

### 3. 自动重启

正式使用建议保持：

```ini
AutoRestart=1
```

调试时如果不想让程序最后自动点击重启，可以临时改成：

```ini
AutoRestart=0
```

## 五、稳定性处理

### 1. 小窗口/异常窗口修复

部分机器在更新后会残留希沃小窗口。当前版本会枚举候选窗口，优先选择面积最大的正常窗口；如果只有小窗口，会重新启动希沃主界面，必要时尝试恢复窗口尺寸。

相关配置：

```ini
[Freeze]
LaunchWhenWindowTooSmall=1

[Validation]
RepairSmallWindow=1
RepairWindowWidth=984
RepairWindowHeight=683
```

### 2. 触摸键盘抑制

触摸屏 Windows 设备点击密码框时可能弹出触摸键盘。当前版本会临时关闭桌面触摸键盘自动唤起，并在结束前恢复。

相关配置：

```ini
[Keyboard]
SuppressTouchKeyboard=1
DisableDesktopAutoInvoke=1
RestoreDesktopAutoInvoke=1
KillTouchKeyboardProcesses=1
```

### 3. 密码输入策略

当前默认使用 AutoHotkey 文本输入方式：

```ini
[Keyboard]
PasswordInputMethod=Text
```

如果某台机器文本输入不稳定，可以临时改为剪贴板输入：

```ini
PasswordInputMethod=Clipboard
```

## 六、开发与编译

源码位于：

```text
_程序文件_请勿修改/src/
```

重新编译需要在开发电脑安装 AutoHotkey v1.1，然后运行：

```bat
_程序文件_请勿修改/build/compile.bat
```

编译完成后会直接生成：

```text
_程序文件_请勿修改/bin/unlock.exe
_程序文件_请勿修改/bin/lock.exe
```

## 七、排查问题

如果更新失败，看：

```text
_程序文件_请勿修改/logs/update/
```

如果解锁/上锁失败，看：

```text
_程序文件_请勿修改/logs/freeze/
```

如果偶发出现密码错误，先保留对应的 `lock_*.log` 或 `unlock_*.log`，再排查输入方式和页面状态。
