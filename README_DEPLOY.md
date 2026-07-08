# 部署说明

## 交付给老师的文件夹

交付时保留整个文件夹即可。老师只需要看到并使用根目录两个入口：

```text
1_解锁冰点并重启.bat
2_更新希沃管家并上锁重启.bat
_程序文件_请勿修改/
```

不要只复制两个 BAT。两个 BAT 只是入口，实际程序、配置、日志和更新脚本都在 `_程序文件_请勿修改` 目录中。

## 使用顺序

```text
1. 双击 1_解锁冰点并重启.bat
2. 等电脑重启回来
3. 双击 2_更新希沃管家并上锁重启.bat
```

第二个入口会先更新希沃管家。只有更新脚本返回成功时，才会继续执行上锁/冻结和重启。

## 配置位置

```text
_程序文件_请勿修改/config/app.ini
```

常用项：

```ini
[Freeze]
Password=
Drives=C
AutoRestart=1
```

如果要全自动运行，把冰点密码填到 `Password=` 后面。

## 日志位置

```text
_程序文件_请勿修改/logs/freeze/
_程序文件_请勿修改/logs/update/
```

排查失败时，优先取最新的 `lock_*.log`、`unlock_*.log` 或 `update_*.log`。

## 重新编译

开发电脑需要安装 AutoHotkey v1.1，然后运行：

```bat
_程序文件_请勿修改/build/compile.bat
```

编译产物会直接写入：

```text
_程序文件_请勿修改/bin/unlock.exe
_程序文件_请勿修改/bin/lock.exe
```

老师电脑不需要安装 AutoHotkey。
