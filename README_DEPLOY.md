# 部署说明

本文档说明当前交付版的部署、运行和排查方式。当前项目已经不是旧的“两步 BAT”形态，而是：

```text
一键更新希沃.bat
配置文件/
```

`一键更新希沃.bat` 是唯一入口。`配置文件` 里包含实际程序、配置、WinPE 镜像、更新脚本、源码和日志目录。交付时必须保留整个文件夹结构，不要只复制入口 BAT。

注意：`配置文件\winpe\boot.wim` 和 `boot.sdi` 是本地构建产物，不提交到 GitHub。`boot.wim` 体积超过 GitHub 普通仓库的单文件限制；从 GitHub clone 后，需要重新构建 WinPE，或从已构建好的交付包中手动复制这两个文件。

## 部署前检查

目标电脑需要满足：

```text
1. Windows 系统可正常启动并能使用管理员权限。
2. 希沃管家已经安装，且 config\app.ini 中的 LauncherPath 指向正确。
3. D: 盘可写；流程会创建或使用 D:\WinPE 和 D:\SeewoHelper。
4. 配置文件\winpe\boot.wim 和 boot.sdi 已存在；如果是从 GitHub clone 的源码，需要先构建或手动补齐。
5. 冰点/还原保护密码已知；如需全自动，应写入配置文件。
```

如果目标电脑没有自动登录，WinPE 重启回 Windows 后需要人工登录一次；登录后 Windows 的 `RunOnce` 才会触发最后的更新和上锁流程。

## 交付结构

交付给老师或现场维护人员时，根目录至少应保持：

```text
一键更新希沃.bat
配置文件/
```

核心目录如下：

```text
配置文件/
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
└─ update/
   ├─ download.bat
   ├─ backup.bat
   └─ scripts/
      └─ seewo-update.ps1
```

不要改名 `配置文件` 文件夹。入口 BAT 会在同级目录下寻找包含 `workflow\orchestrate.bat` 的程序目录。

## 配置

主要配置文件：

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

`Password` 留空时，解冻或上锁程序会弹出密码输入框。要全自动运行，可以填入冰点密码：

```ini
Password=123456
```

注意：密码会明文保存在 `配置文件\config\app.ini`。运行 Phase 3 时，脚本会删除临时复制到 `D:\SeewoHelper\config\app.ini` 的那一份，但源目录中的配置文件仍会保留。

`Drives` 是要解冻/冻结的盘符：

```ini
Drives=C
Drives=C,E
```

一键流程建议保持：

```ini
AutoRestart=0
```

这个值只控制 `unlock.exe` 和 `lock.exe` 是否在希沃管家界面点击“立即重启”。一键总流程中的系统重启由编排脚本、WinPE 和 Phase 3 统一控制。

## 部署流程

首次部署或交付前：

```text
1. 检查 配置文件\config\app.ini。
2. 确认 配置文件\winpe\boot.wim 和 boot.sdi 存在。
3. 把整个文件夹复制到目标电脑。
4. 双击 一键更新希沃.bat。
5. 授权管理员权限。
6. 等待自动重启和更新完成。
```

运行中会发生：

```text
Phase 1：Windows 中
  部署 D:\WinPE
  部署 D:\SeewoHelper
  运行 unlock.exe 解冻冰点
  创建一次性 WinPE 启动项
  重启

Phase 2：WinPE 中
  加载 Windows 离线注册表
  写入 RunOnce
  清理临时 BCD 项
  重启回 Windows

Phase 3：Windows 登录后
  运行 D:\SeewoHelper\post-thaw-update.bat
  更新希沃管家
  成功后运行 lock.exe 重新冻结
  删除 D:\SeewoHelper 中的临时配置
  重启
```

更新模块默认优先使用官方源，官方源不可用时自动切换到 VPS 备用源。只有更新脚本返回成功时才会继续上锁。

## 重新构建 WinPE

如果 `配置文件\winpe\boot.wim` 或 `boot.sdi` 缺失，或者修改过 `配置文件\winpe-builder\startnet.cmd`，需要重新构建 WinPE。

开发机前置条件：

```text
Windows ADK
Windows PE 附加组件
管理员 PowerShell
```

运行：

```powershell
配置文件\winpe-builder\build-winpe.ps1
```

默认输出：

```text
配置文件\winpe\boot.wim
配置文件\winpe\boot.sdi
```

如果已经有一份可用的交付包，也可以直接把其中的 `配置文件\winpe\boot.wim` 和 `配置文件\winpe\boot.sdi` 复制到当前项目；这两个文件会被 `.gitignore` 忽略，不会再进入 GitHub 提交。

## 重新编译 AHK 程序

如果修改了 `配置文件\src` 下的 AutoHotkey 源码，需要在开发机安装 AutoHotkey v1.1，然后运行：

```bat
配置文件\build\compile.bat
```

输出：

```text
配置文件\bin\unlock.exe
配置文件\bin\lock.exe
```

老师电脑不需要安装 AutoHotkey。

## 日志位置

```text
配置文件\logs\freeze\
  Phase 1 解冻日志，以及手动运行 lock/unlock 时的日志。

D:\SeewoHelper\logs\phase3_*.log
  Phase 3 主流程日志。

D:\SeewoHelper\logs\freeze\lock_*.log
  Phase 3 上锁日志。

D:\SeewoHelper\logs\update\update_*.log
  Phase 3 希沃管家更新日志。

配置文件\logs\update\
  手动运行 update\download.bat 或 backup.bat 时的更新日志。

X:\seewo_phase2.log
  WinPE 内临时日志，重启后消失。
```

## 常见问题

入口提示找不到程序目录：

```text
检查 一键更新希沃.bat 和 配置文件 是否在同一级。
检查 配置文件\workflow\orchestrate.bat 是否存在。
```

提示缺少 WinPE 文件：

```text
检查 配置文件\winpe\boot.wim
检查 配置文件\winpe\boot.sdi
必要时重新运行 配置文件\winpe-builder\build-winpe.ps1
```

解冻失败：

```text
查看 配置文件\logs\freeze\unlock_*.log
检查 app.ini 中的 Password、Drives、LauncherPath、窗口类名和坐标配置。
```

重启后没有进入 WinPE：

```text
检查 D:\WinPE\boot.wim 和 boot.sdi。
检查 D:\SeewoHelper\_winpe_guid.txt 和 _ramdisk_guid.txt。
检查 Phase 1 中 setup-winpe-boot.ps1 的 BCD 输出。
```

WinPE 后没有触发 Phase 3：

```text
确认是否已经登录 Windows。
RunOnce 需要登录后才会执行。
```

更新失败：

```text
查看 D:\SeewoHelper\logs\update\update_*.log。
更新失败时会跳过上锁，避免未完成更新就重新冻结。
```

上锁失败：

```text
查看 D:\SeewoHelper\logs\freeze\lock_*.log。
检查 D:\SeewoHelper\config\app.ini 是否在 Phase 3 运行前成功部署。
```

## 维护注意

`.bat`、`.cmd` 和 `.ps1` 文件应保持 Windows CRLF 行尾。仓库中的 `.gitattributes` 已锁定这些文件类型。

`boot.wim`、`boot.sdi`、`bin\*.exe` 和图片文件是二进制文件，不要做文本转换。
