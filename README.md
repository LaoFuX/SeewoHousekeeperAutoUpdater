# 希沃管家自动更新脚本

这是一个用于“解冻冰点/还原保护 → 更新希沃管家 → 重新冻结并重启”的一键自动化工具。当前交付形态很简单：

```text
一键更新希沃.bat
配置文件/
```

老师或现场维护人员只需要双击 `一键更新希沃.bat`。`配置文件` 是程序、配置、WinPE 镜像、日志和源码目录，必须和入口 BAT 放在同一级，不要只复制入口文件。

注意：`配置文件\winpe\boot.wim` 和 `boot.sdi` 体积较大，其中 `boot.wim` 超过 GitHub 普通仓库的单文件限制，所以这两个文件不会提交到 GitHub。clone 仓库后需要在本机重新构建，或从已构建好的交付包中手动放回 `配置文件\winpe\`。

## 使用方式

1. 把整个项目文件夹放到目标电脑上。
2. 确认 `一键更新希沃.bat` 旁边存在 `配置文件` 文件夹。
3. 双击 `一键更新希沃.bat`。
4. 按系统弹窗授权管理员权限。
5. 后续流程会自动重启多次，等待它完成。

如果 Windows 需要手动登录，WinPE 阶段重启回 Windows 后需要登录一次；登录后 `RunOnce` 才会触发最后的更新和上锁流程。

## 自动化流程

整个流程分为三个阶段：

```text
Phase 1：Windows 内运行
  一键更新希沃.bat
    -> 配置文件\workflow\orchestrate.bat
    -> 部署 D:\WinPE
    -> 部署 D:\SeewoHelper
    -> 运行 unlock.exe 解冻冰点
    -> 创建一次性 WinPE 启动项
    -> 重启

Phase 2：WinPE 内运行
  startnet.cmd
    -> 查找 Windows 分区
    -> 查找 D:\SeewoHelper 标记
    -> 离线加载 Windows SOFTWARE 注册表
    -> 写入 RunOnce
    -> 清理临时 BCD 启动项
    -> 重启回 Windows

Phase 3：Windows 登录后运行
  D:\SeewoHelper\post-thaw-update.bat
    -> 运行 seewo-update.ps1 更新希沃管家
    -> 更新成功后运行 lock.exe 重新冻结
    -> 删除临时部署的 config\app.ini
    -> 重启
```

`seewo-update.ps1` 默认使用官方源，官方源不可用时自动切换到 VPS 备用源。只有更新脚本返回成功时，才会继续执行重新冻结；如果更新失败，会跳过上锁并保留窗口提示。

## 目录结构

```text
AHKSCRIPT/
├─ 一键更新希沃.bat
├─ README.md
├─ README_DEPLOY.md
└─ 配置文件/
   ├─ bin/
   │  ├─ unlock.exe
   │  └─ lock.exe
   ├─ config/
   │  └─ app.ini
   ├─ workflow/
   │  ├─ orchestrate.bat
   │  ├─ setup-winpe-boot.ps1
   │  └─ post-thaw-update.bat
   ├─ winpe/
   │  ├─ boot.wim
   │  └─ boot.sdi
   ├─ winpe-builder/
   │  ├─ build-winpe.ps1
   │  └─ startnet.cmd
   ├─ update/
   │  ├─ download.bat
   │  ├─ backup.bat
   │  └─ scripts/
   │     └─ seewo-update.ps1
   ├─ src/
   ├─ build/
   ├─ tools/
   ├─ pics/
   ├─ logs/
   └─ docs/
```

关键文件说明：

```text
一键更新希沃.bat
  根目录入口。自动请求管理员权限，并寻找旁边的程序目录。

配置文件\workflow\orchestrate.bat
  Phase 1 主编排脚本。部署 WinPE 和 SeewoHelper，运行解冻，创建一次性启动项。

配置文件\workflow\setup-winpe-boot.ps1
  创建 WinPE ramdisk BCD 对象和一次性 bootsequence，并把 GUID 写入 D:\SeewoHelper。

配置文件\winpe-builder\startnet.cmd
  注入 boot.wim 的 WinPE 启动脚本，也就是 Phase 2。

配置文件\workflow\post-thaw-update.bat
  Phase 3 脚本。由 Windows RunOnce 触发，负责更新、上锁和最终重启。

配置文件\bin\unlock.exe
  AutoHotkey 编译产物，用于在希沃管家界面中解冻目标磁盘。

配置文件\bin\lock.exe
  AutoHotkey 编译产物，用于在希沃管家界面中重新冻结目标磁盘。

配置文件\update\scripts\seewo-update.ps1
  希沃管家更新逻辑，包含版本检测、下载、静默安装和日志。
```

## 常用配置

配置文件在：

```text
配置文件\config\app.ini
```

常用项：

```ini
[Freeze]
LauncherPath=C:\Program Files (x86)\Seewo\SeewoService\SeewoHugoLauncher\SeewoHugoLauncher.exe
LauncherArgs=/runmode=launcher
Password=
Drives=C
AutoRestart=0
```

`Password` 留空时，`unlock.exe` 或 `lock.exe` 会弹出密码输入框。需要全自动时，可以把冰点密码写到这里；注意它是明文保存，交付包不要发给无关人员。Phase 3 会删除临时复制到 `D:\SeewoHelper\config\app.ini` 的那一份，但源目录里的 `配置文件\config\app.ini` 仍会保留。

`Drives` 表示要解冻/冻结的盘符，例如：

```ini
Drives=C
Drives=C,E
```

`AutoRestart` 只控制 AHK 在希沃管家确认界面里是否点击“立即重启”。一键总流程后续的系统重启由 BAT、WinPE 和 Phase 3 脚本控制。

更新源相关配置：

```ini
[Update]
OfficialApiUrl=https://e.seewo.com/download/file?code=SeewoServiceSetup
VpsUrlB64=...
TempDir=C:\Temp\SeewoUpdate
TimeoutSeconds=45
CleanupInstaller=1
```

## 日志位置

```text
配置文件\logs\freeze\
  Phase 1 中 unlock.exe 的日志，以及手动运行 lock/unlock 时的日志。

D:\SeewoHelper\logs\phase3_*.log
  Phase 3 主流程日志。

D:\SeewoHelper\logs\freeze\lock_*.log
  Phase 3 中 lock.exe 重新冻结时的日志。

D:\SeewoHelper\logs\update\update_*.log
  Phase 3 中希沃管家更新日志。

配置文件\logs\update\
  在项目目录内手动运行 update\download.bat 或 backup.bat 时的更新日志。

X:\seewo_phase2.log
  WinPE 内 Phase 2 临时日志，重启后会消失。

配置文件\logs\probe\
  tools\probe.bat 生成的环境探测日志。
```

`配置文件\winpe\boot.wim` 和 `boot.sdi` 是本地构建产物，不随 GitHub 仓库提交；如果是从 GitHub clone 的源码目录，这两个文件需要重新构建或手动补齐。

## 重新构建

重新编译 `unlock.exe` 和 `lock.exe`：

```bat
配置文件\build\compile.bat
```

开发机需要安装 AutoHotkey v1.1。

重新构建 WinPE 镜像：

```powershell
配置文件\winpe-builder\build-winpe.ps1
```

开发机需要安装 Windows ADK 和 Windows PE 附加组件，并以管理员身份运行 PowerShell。默认输出到 `配置文件\winpe\boot.wim` 和 `配置文件\winpe\boot.sdi`。修改 `startnet.cmd` 后必须重新构建 `boot.wim` 才会生效。

如果只是从另一台已经构建好的机器迁移，也可以直接把那台机器上的 `配置文件\winpe\boot.wim` 和 `配置文件\winpe\boot.sdi` 复制到当前目录；它们被 `.gitignore` 忽略，不会再被提交到 GitHub。

## 排查建议

如果入口提示找不到程序目录，检查 `一键更新希沃.bat` 和 `配置文件` 是否仍在同一级。

如果提示缺少 `boot.wim` 或 `boot.sdi`，说明当前目录没有本地 WinPE 构建产物；重新运行 `配置文件\winpe-builder\build-winpe.ps1`，或从交付包中复制 `配置文件\winpe\boot.wim` 和 `boot.sdi` 回来。

如果解冻或上锁失败，查看 `配置文件\logs\freeze\unlock_*.log`、`配置文件\logs\freeze\lock_*.log` 或 `D:\SeewoHelper\logs\freeze\lock_*.log`，并检查 `app.ini` 里的密码、目标盘符、希沃启动路径、窗口尺寸和坐标配置。

如果更新失败，查看 `D:\SeewoHelper\logs\update\update_*.log`。更新失败时会跳过上锁，避免在未更新完成的状态下重新冻结。

如果重启后没有进入 WinPE，重点检查 BCD 创建阶段输出、`D:\WinPE`、`D:\SeewoHelper\_winpe_guid.txt` 和 `D:\SeewoHelper\_ramdisk_guid.txt`。

如果进入 WinPE 后没有触发 Phase 3，确认 Windows 是否已经登录；`RunOnce` 需要在登录后运行。

## 维护注意

运行时 `.bat`、`.cmd` 和 `.ps1` 文件需要保持 Windows CRLF 行尾。仓库里的 `.gitattributes` 已经锁定这些文件类型，避免 CMD 解析异常。

`配置文件\winpe\boot.wim`、`boot.sdi`、`bin\*.exe` 和 `pics\*.png` 是二进制文件，不要做文本转换。
