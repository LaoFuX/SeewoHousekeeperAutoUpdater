# winpe-builder — WinPE 构建与 Phase 2/3 脚本

## 目录结构

```
winpe-builder/
  winpe_builder.ps1     ← 在开发机上运行，生成 boot.wim + boot.sdi
  startnet.cmd          ← WinPE 启动时自动执行（Phase 2）
  phase3_source.bat     ← Phase 3 模板，Phase 1 会复制到 D:\SeewoHelper\
```

---

## 使用流程

### 第一步：在开发机上构建 WinPE（一次性）

**前提：** 安装 Windows ADK + Windows PE 附加组件  
下载地址：https://docs.microsoft.com/zh-cn/windows-hardware/get-started/adk-install

以管理员身份运行 PowerShell：

```powershell
cd winpe-builder
.\winpe_builder.ps1
```

默认输出到 `D:\WinPE\`，包含：
- `boot.wim`（已注入 startnet.cmd）
- `boot.sdi`

### 第二步：将 D:\WinPE\ 复制到每台目标机的 D:\

```
D:\WinPE\
  boot.wim
  boot.sdi
```

这是一次性部署。D: 盘不受冰点保护，文件永久存在。

### 第三步：老师触发（每次需要更新时）

在目标机上，双击根目录的：

```
0_全自动化更新.bat
```

后续全程自动，无需人工干预：

```
老师双击 → Phase 1（解锁冰点 + 设置一次性WinPE启动）
  ↓ 重启
WinPE 自动启动 → Phase 2（离线注入 RunOnce）
  ↓ 重启（冰点解冻状态）
用户自动登录 → RunOnce 触发 Phase 3（更新希沃管家 + 上锁 + 重启）
  ↓ 重启
冰点恢复冻结，更新完成
```

---

## 各脚本说明

### winpe_builder.ps1

- 调用 ADK 的 `copype.cmd` 创建 WinPE 工作目录
- 用 DISM 挂载 `boot.wim`
- 将 `startnet.cmd` 注入到镜像的 `\Windows\System32\startnet.cmd`
- 提交并输出到目标目录

### startnet.cmd（Phase 2，WinPE 内运行）

1. `wpeinit` 初始化WinPE 网络/驱动
2. 枚举驱动器，找到 Windows 分区（含 `\Windows\System32\config\SOFTWARE`）
3. 枚举驱动器，找到 SeewoHelper 分区（含 `_seewo_marker.txt`）
4. `reg load` 挂载离线 SOFTWARE hive
5. 写入 RunOnce → `D:\SeewoHelper\phase3.bat`
6. `reg unload` 卸载 hive
7. 读取 `_winpe_guid.txt` 并 `bcdedit /delete` 清理临时启动项
8. `wpeutil reboot`

### phase3_source.bat（Phase 3，RunOnce 触发）

1. 防重入锁（`_phase3_running.lock`）
2. 自动请求管理员权限
3. 运行 `seewo-update.ps1 -Source Auto`
4. 成功后运行 `lock.exe`
5. `shutdown /r /t 10`

---

## 日志位置

| 阶段 | 日志 |
|------|------|
| Phase 2 (WinPE) | `X:\seewo_phase2.log`（WinPE 内存，重启后消失） |
| Phase 3 | `D:\SeewoHelper\logs\phase3_YYYYMMDD_*.log` |
| unlock/lock | `_程序文件_请勿修改\logs\freeze\` |
| 希沃更新 | `_程序文件_请勿修改\logs\update\` |
