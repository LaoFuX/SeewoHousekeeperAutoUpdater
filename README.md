# 希沃管家自动更新工具 - 两入口版

## 一、工具用途

本工具用于维护装有冰点/冻结保护的希沃管家电脑。

当前版本已经取消旧版 `1/2/3/4` 菜单，改为两个直接入口：

```text
unlock-and-restart.bat
  入口 1：解锁/解冻冰点，然后立即重启。

main.bat
  入口 2：更新希沃管家，更新成功后自动上锁/冻结冰点，然后立即重启。
```

推荐完整流程：

```text
第一步：双击 unlock-and-restart.bat
  电脑解冻并重启。

第二步：电脑重启回来后，双击 main.bat
  希沃管家更新完成后，上锁并重启。
```

`main.bat` 不会先执行解锁。它适用于电脑已经处于解冻/可写状态的场景。

## 二、交付包文件结构

正式交付给老师时，建议保留这些文件：

```text
unlock-and-restart.bat
main.bat
download.bat
backup.bat
unlock.exe
lock.exe
config/
scripts/
logs/
README.md
```

各文件作用：

```text
unlock-and-restart.bat
  老师入口 1。调用 unlock.exe 完成解锁/解冻和重启。

main.bat
  老师入口 2。调用 download.bat 更新希沃管家，成功后调用 lock.exe 上锁/冻结并重启。

download.bat
  更新入口。优先使用官方下载更新逻辑，保留 VPS 备用逻辑。

backup.bat
  VPS 备用更新入口，主要给维护人员排查时使用。

unlock.exe
  解锁/解冻 GUI 自动化程序，由 AutoHotkey 源码编译生成。

lock.exe
  上锁/冻结 GUI 自动化程序，由 AutoHotkey 源码编译生成。

config/app.ini
  配置文件。保存密码、目标磁盘、程序路径、等待时间、窗口修复和键盘处理策略。

scripts/seewo-update.ps1
  下载、版本检测、静默安装的 PowerShell 核心逻辑。

logs/
  日志目录。更新日志在 logs/update，GUI 自动化日志在 logs/freeze。
```

老师电脑不需要安装 AutoHotkey，也不需要携带 AutoHotkey.exe。

## 三、两个入口的调用关系

### 1. 解锁并重启

双击：

```bat
unlock-and-restart.bat
```

执行链路：

```text
unlock-and-restart.bat
  -> unlock.exe
  -> 解锁/解冻冰点
  -> 点击立即重启
```

### 2. 更新并上锁重启

双击：

```bat
main.bat
```

执行链路：

```text
main.bat
  -> download.bat
  -> scripts/seewo-update.ps1
  -> lock.exe
  -> 上锁/冻结冰点
  -> 点击立即重启
```

如果更新失败，`main.bat` 会停止，不会继续执行上锁。这样可以避免“软件没有更新成功，却又重新冻结电脑”的情况。

## 四、常用配置

配置文件位置：

```text
config/app.ini
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

## 五、GUI 自动化策略

希沃管家界面属于 Chromium/Electron 类窗口。外层窗口能被 Windows 识别，但内部按钮、输入框通常不能稳定暴露为标准控件。

所以本项目采用：

```text
窗口识别
+ 候选窗口筛选
+ 窗口内相对位置点击
+ 配置化等待时间
+ 日志记录
```

这比固定屏幕绝对坐标更稳。窗口移动或分辨率变化时，只要窗口比例结构没有大变，点击位置仍然能跟随窗口计算。

## 六、当前版本的稳定性处理

### 1. 小窗口/异常窗口修复

部分机器在更新后会残留希沃小窗口，例如 `540x246` 或类似尺寸。旧版本可能误选这个窗口，导致后续坐标全部失准。

当前版本会：

```text
枚举所有希沃候选窗口
选择面积最大的正常窗口
如果只有小窗口，则重新启动希沃主界面
必要时尝试把小窗口恢复到配置尺寸
```

相关配置：

```ini
[Freeze]
LaunchWhenWindowTooSmall=1

[Timing]
WindowPollMs=500
WindowRepairDelayMs=1500

[Validation]
MinWindowWidth=500
MinWindowHeight=350
RepairSmallWindow=1
RepairWindowX=100
RepairWindowY=60
RepairWindowWidth=984
RepairWindowHeight=683
MaximizeRepairedWindow=0
```

### 2. 触摸键盘抑制

触摸屏 Windows 设备在点击密码框时，可能会自动弹出触摸键盘并挡住界面。

当前版本会在自动化开始时临时关闭桌面触摸键盘自动唤起，并结束时恢复原状态：

```ini
[Keyboard]
SuppressTouchKeyboard=1
DisableDesktopAutoInvoke=1
RestoreDesktopAutoInvoke=1
KillTouchKeyboardProcesses=1
```

如果某台机器仍然频繁弹出触摸键盘，维护人员可以临时设置：

```ini
RestoreDesktopAutoInvoke=0
```

这样运行后会保持 Windows 触摸键盘桌面自动唤起为关闭状态。

### 3. 密码输入策略

当前默认使用 AutoHotkey 文本输入方式，而不是单纯依赖剪贴板粘贴：

```ini
[Keyboard]
PasswordInputMethod=Text
AfterPasswordInputClickDelayMs=500
RefocusPasswordInputAfterKeyboardClose=1
AfterPasswordInputRefocusDelayMs=150
AfterPasswordInputDelayMs=250
```

如果某台机器文本输入不稳定，可以把输入方式临时改成剪贴板：

```ini
PasswordInputMethod=Clipboard
```

## 七、日志位置

GUI 自动化日志：

```text
logs/freeze/
```

更新日志：

```text
logs/update/
```

排查问题时，优先看最新的：

```text
logs/freeze/lock_*.log
logs/freeze/unlock_*.log
logs/update/update_*.log
```

## 八、开发与编译

开发源码在：

```text
src/
```

重新编译需要在开发电脑安装 AutoHotkey v1.1，然后运行：

```bat
build\compile.bat
```

编译后会生成：

```text
unlock.exe
lock.exe
```

编译完成后，把新的 `unlock.exe`、`lock.exe` 和新版 `config/app.ini` 同步到交付目录。

## 九、维护建议

正式运行前确认：

- `config/app.ini` 中密码和目标磁盘正确。
- 不要在自动化过程中移动鼠标、敲键盘或遮挡希沃窗口。
- 冰点相关操作完成后可能立即重启，运行前保存好所有文件。
- 如果偶发出现密码错误，先保留 `logs/freeze` 中对应日志，再排查输入方式和页面状态。
