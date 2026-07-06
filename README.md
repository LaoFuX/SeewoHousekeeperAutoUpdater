# 希沃管家更新工具 - 正式版说明

## 一、工具用途

本工具用于希沃管家相关维护，提供四个功能：

1. 解锁/解冻冰点，并立即重启
2. 官方下载更新
3. VPS 备用源下载更新
4. 上锁/冻结冰点，并立即重启

正式使用时只需要双击：

```bat
main.bat
```

## 二、重要提醒

选择冰点相关功能时，电脑会在操作完成后立即重启：

```text
1. Unlock / unfreeze - reboot immediately
4. Lock / freeze - reboot immediately
```

使用前请确认：

- 当前电脑没有正在编辑但未保存的文件
- 不要在自动化过程中移动鼠标或操作键盘
- 不要修改文件名和目录结构
- 不要删除 `config`、`scripts`、`logs` 文件夹
- 记得提前关闭火绒/360等杀毒软件
- 尽量不要让希沃窗口被挡住

菜单使用英文，是为了避免部分学校机器的 BAT 中文编码兼容问题。README 使用中文不会影响程序运行。

## 三、正式版文件结构

正式交付包建议只保留以下内容：

```text
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
main.bat
  唯一入口。显示菜单，读取选项，调用对应模块。

download.bat
  官方下载更新入口。优先使用官方源，官方源不可用时走备用源。

backup.bat
  VPS 备用源下载更新入口。

unlock.exe
  解锁/解冻冰点。由 AutoHotkey 编译生成，老师电脑无需安装 AutoHotkey。

lock.exe
  上锁/冻结冰点。由 AutoHotkey 编译生成，老师电脑无需安装 AutoHotkey。

config/app.ini
  配置文件。保存密码、目标磁盘、程序路径、等待时间等配置。

scripts/seewo-update.ps1
  下载、版本检测、静默安装的 PowerShell 核心逻辑。

logs/
  日志目录。程序运行后会在里面生成日志。
```

## 四、菜单说明

双击 `main.bat` 后，会看到类似菜单：

```text
==========================
  Seewo Housekeeper Tool
==========================

1. Unlock / unfreeze - reboot immediately
2. Official update
3. VPS update
4. Lock / freeze - reboot immediately
0. Exit
```

菜单含义：

```text
1 = 解锁/解冻冰点，完成后立即重启
2 = 官方下载更新
3 = VPS 备用源下载更新
4 = 上锁/冻结冰点，完成后立即重启
0 = 退出
```

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

含义：

```text
WindowReadyDelayMs
  找到希沃管家窗口后，等待页面完全响应。

NavClickCount
  连续点击底部“冰点还原”入口的次数。

NavClickIntervalMs
  多次点击之间的间隔。

PageDelayMs
  进入冰点页面后继续等待的时间。

CheckGreenButton
  是否启用绿色按钮取色校验。正式版建议保持 0。
```

如果某台机器仍然偶尔点错页面，可以优先增加：

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

如果操作失败，请查看对应目录中最新的日志文件。日志会记录：

- 是否找到希沃管家窗口
- 窗口大小
- 每一步点击位置
- 密码是否已输入
- 操作到哪一步失败

排查问题时，请把最新日志文件发给维护人员。

## 八、正式使用步骤

1. 打开 `config/app.ini`
2. 确认 `Password` 是否需要填写
3. 确认 `Drives` 是 `C` 还是 `C,E`
4. 双击 `main.bat`
5. 按菜单输入数字并回车

如果选择 `1` 或 `4`，电脑会在流程完成后立即重启。

## 九、维护人员说明

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
