# 希沃管家更新工具 - 两入口版说明

## 一、工具用途

本工具用于希沃管家维护。新版取消 1、2、3、4 菜单选择，老师只需要按场景双击对应入口。

正式使用入口：

```text
unlock-and-restart.bat
  入口 1：解锁/解冻冰点，并立即重启。

main.bat
  入口 2：更新希沃管家，成功后自动上锁/冻结冰点，并立即重启。
```

## 二、重要提醒

两入口版的完整维护顺序是：

```text
第一步：双击 unlock-and-restart.bat
  解锁/解冻冰点，然后电脑重启。

第二步：重启回来后，双击 main.bat
  更新希沃管家，更新成功后上锁/冻结冰点，然后电脑重启。
```

`main.bat` 不会先解锁冰点。它适用于第一步已经完成、电脑已经处于解冻/可写状态的维护场景。

如果电脑当前仍处于冻结状态，直接运行 `main.bat`，更新可能会在重启后被冰点还原。

正确流程是先运行：

```bat
unlock-and-restart.bat
```

电脑重启后，再运行：

```bat
main.bat
```

冰点相关功能完成后可能立即重启。使用前请确认：

- 当前电脑没有正在编辑但未保存的文件
- 不要在自动化过程中移动鼠标或操作键盘
- 不要修改文件名和目录结构
- 不要删除 `config`、`scripts`、`logs` 文件夹
- 尽量不要让希沃窗口被挡住

## 三、正式版文件结构

正式交付包建议保留以下内容：

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

各文件作用如下：

```text
unlock-and-restart.bat
  老师入口 1。调用 unlock.exe 解锁/解冻冰点并重启。

main.bat
  老师入口 2。更新希沃管家，成功后调用 lock.exe 上锁/冻结冰点并重启。

download.bat
  更新模块。优先使用官方源，官方源不可用时走 VPS 备用源。

backup.bat
  VPS 备用源更新模块，保留给维护人员手动排查时使用。

unlock.exe
  解锁/解冻冰点模块。由 AutoHotkey 编译生成，老师电脑无需安装 AutoHotkey。

lock.exe
  上锁/冻结冰点模块。由 AutoHotkey 编译生成，老师电脑无需安装 AutoHotkey。

config/app.ini
  配置文件。保存密码、目标磁盘、程序路径、等待时间等配置。

scripts/seewo-update.ps1
  下载、版本检测、静默安装的 PowerShell 核心逻辑。

logs/
  日志目录。程序运行后会在里面生成日志。
```

## 四、两个入口的调用关系

### 1. 解锁并重启

双击：

```bat
unlock-and-restart.bat
```

执行流程：

```text
unlock-and-restart.bat
  -> unlock.exe
  -> 立即重启
```

这一步完成后，电脑会进入解冻/可写状态，方便下一步更新软件。

### 2. 更新并上锁重启

双击：

```bat
main.bat
```

执行流程：

```text
main.bat
  -> download.bat
  -> scripts/seewo-update.ps1
  -> lock.exe
  -> 立即重启
```

如果更新失败，程序会停止，不会继续上锁。这样设计是为了避免“更新没有成功，却把机器重新冻结”的情况。

## 五、配置文件

配置文件位置：

```text
config/app.ini
```

常用配置在 `[Freeze]` 段：

```ini
[Freeze]
Password=
Drives=C
AutoRestart=1
```

### 1. 密码配置

如果不想把密码写进配置文件，保持为空：

```ini
Password=
```

运行冰点功能时，会弹出英文密码输入框，临时输入密码。

如果希望全自动运行，可以填写密码：

```ini
Password=123456
```

注意：密码明文保存在配置文件中，请不要把正式包交给无关人员。

### 2. 目标磁盘

默认只操作 C 盘：

```ini
Drives=C
```

如果需要同时操作 C 盘和 E 盘：

```ini
Drives=C,E
```

### 3. 是否自动重启

正式使用默认立即重启：

```ini
AutoRestart=1
```

如果维护人员调试时不希望自动点击重启，可以临时改成：

```ini
AutoRestart=0
```

正式上课使用建议保持 `AutoRestart=1`。

## 六、自动化稳定性配置

希沃管家是 Chromium/Electron 类界面，Windows UI Automation 无法识别内部按钮和输入框。因此本工具采用：

```text
窗口定位 + 窗口内相对位置点击 + 配置化等待
```

相关配置：

```ini
WindowReadyDelayMs=2500
NavClickCount=3
NavClickIntervalMs=600
PageDelayMs=2000
CheckGreenButton=0
```

如果某台机器偶尔点错页面，可以优先增加：

```ini
WindowReadyDelayMs=3500
PageDelayMs=2500
```

## 七、日志位置

冰点自动化日志：

```text
logs/freeze/
```

下载更新日志：

```text
logs/update/
```

如果操作失败，请查看对应目录中最新的日志文件。

## 八、维护人员说明

正式包中不需要包含以下开发资料：

```text
src/
build/
tools/
pics/
probe.bat
README_DEPLOY.md
logs/probe/
.agents/
.git/
```

如果以后需要修改 AutoHotkey 源码或重新编译，请在开发备份中保留：

```text
src/
build/
```

重新编译需要在开发电脑安装 AutoHotkey v1.1，然后运行：

```bat
build\compile.bat
```

编译完成后会生成新的：

```text
unlock.exe
lock.exe
```

老师电脑不需要安装 AutoHotkey。
