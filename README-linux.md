# Mimonitor Toolbox — Linux (Arch + KDE Wayland) 安装说明

> 安装日期：2026-10-24 · 提交：`56fa67e8d990a2dd8d7ebe1b6865d3b18928d08d`
> 安装方式：**完全隔离的 venv**，不改动系统 Python、不写系统目录。

## 1. 能用吗？—— 结论

| 功能 | Linux 状态 | 说明 |
| --- | --- | --- |
| GUI 启动 / 全部 10 个页面 | ✅ 正常 | 原生 Wayland 下渲染正常 |
| 手动输入 IP 连接显示器 | ✅ 正常 | 走 `adb connect`，纯子进程调用 |
| 读取/写入显示器参数（背光、色温等） | ✅ 应可用 | 依赖 adb + jar，jar 已随仓库自带 |
| 内网自动扫描 | ❌ 不可用 | 网卡枚举走 Windows IP Helper API，日志提示"网卡枚举仅支持 Windows" |
| Windows HDR / 全局快捷键 / 开机自启 | ❌ 不适用 | Windows 专属，代码已做平台保护，不会崩溃 |
| 系统托盘 | ✅ 正常 | KDE 托盘可用 |
| 打开 ADB CMD | ❌ 不适用 | 明确提示"仅支持 Windows" |
| 打开 ADB Shell 终端 | ✅ 正常 | 自动寻找 konsole/gnome-terminal 等 |

**一句话**：GUI 和核心调参功能在 Linux 上可用；**自动扫描不可用，请手动输入显示器 IP 连接**。

## 2. 已知问题：XWayland(xcb) 下会段错误

在 `QT_QPA_PLATFORM=xcb`（即 XWayland）下启动会 **SIGSEGV 崩溃**，崩溃栈位于
`QXcbWindow::handleNativeEvent`。原生 Wayland 平台插件下**没有此问题**。

因此 `run.sh` 默认强制 `QT_QPA_PLATFORM=wayland`。
如果你运行在**纯 X11 会话**（非 KDE Wayland），此程序可能无法稳定运行——这是上游程序的问题，
不是安装造成的。可用 `QT_QPA_PLATFORM=xcb ./run.sh` 自行试验。

## 3. 启动方式

```bash
cd ~/Apps/Mimonitor_Toolbox
./run.sh
```

或在应用菜单里搜索 **"红米 G Pro 27U Toolbox"**。

## 4. 连接显示器

1. 显示器需开启无线 ADB 调试（端口 5555）。
2. 在本程序首页 **"显示器 IP"** 输入框中手动填写，例如 `192.168.1.50`。
3. 点 **"开始连接"**。

> 本程序使用**私有 ADB server 端口 5038**，不会与你系统的 5037 端口冲突。

## 5. 依赖

- `adb`：已存在（`/usr/bin/adb`，android-tools 37.0.0）。若缺失：`sudo pacman -S android-tools`
- Python 3.14.8（venv 内，不影响系统）
- PyQt6 6.11.0 / PyQt6-Fluent-Widgets 1.11.2（仅装在 venv 内）

## 6. 完全卸载（回滚）

```bash
~/Apps/Mimonitor_Toolbox/uninstall.sh
```

该脚本删除：程序目录、`~/.gpro_controller`（配置/日志）、桌面入口。
本安装**没有**修改任何系统文件、系统 Python 包或 systemd 服务。

## 7. 测试记录

- `pytest tests/` → **413 passed, 31 subtests passed**
- 11 个模块在 Linux 上全部可导入
- GUI 无头启动（offscreen）稳定运行 25s+
- GUI 原生 Wayland 启动正常，10 个页面全部可切换

## 8. 应用数据位置

配置与日志：`~/.gpro_controller/`（`config.json`、`logs/`）
