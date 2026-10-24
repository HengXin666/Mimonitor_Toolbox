# Mimonitor Toolbox — Linux / Arch Linux 说明

> 本仓库是上游的 **Arch Linux 适配分支**，提供可直接下载运行的 AppImage。
> 上游：https://github.com/YiHoooong/Mimonitor_Toolbox

## 一、AppImage（推荐，免安装）

从 [Actions](../../actions/workflows/appimage.yml) 最新成功构建下载
`mimonitor-toolbox-appimage` 压缩包，解出后：

```bash
chmod +x mimonitor-toolbox-x86_64.AppImage
./mimonitor-toolbox-x86_64.AppImage
```

- 自带 Python 3.14 + Qt6 + 全部图形依赖，**不依赖系统 Python**
- 需要系统有 `adb`：`sudo pacman -S android-tools`
- 需要系统有 `ip`（网卡扫描用）：`sudo pacman -S iproute2`（Arch 默认已有）
- 配置与日志：`~/.gpro_controller/`
- 卸载：直接删掉这个文件即可

> FUSE 报错时：`sudo pacman -S fuse2`，或改用
> `./mimonitor-toolbox-x86_64.AppImage --appimage-extract-and-run`

## 二、源码 + venv

```bash
cd ~/Apps/Mimonitor_Toolbox
./run.sh
```

## 三、Linux 可用性

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| GUI 启动 / 全部 10 个页面 | ✅ | 原生 Wayland 下正常 |
| **内网自动扫描** | ✅ | **本分支新增**，通过 `ip -j addr` 枚举网卡 |
| 手动输入 IP 连接 | ✅ | 走 `adb connect` |
| 调参（背光/色温/色域/灯效） | ✅ | 依赖 adb + 随包 jar |
| Windows HDR / 全局快捷键 / 开机自启 | ❌ 不适用 | 有平台保护，不会崩 |
| 系统托盘 | ✅ | KDE 托盘正常 |
| 打开 ADB Shell 终端 | ✅ | 自动找 konsole 等 |

## 四、Linux 网卡枚举实现（本分支新增）

上游的 `enumerate_windows_adapter_addresses()` 只支持 Windows，Linux 上直接抛错，
导致"扫描内网"永远失败。本分支新增 `enumerate_linux_adapter_addresses()`：

- 通过 `ip -j addr`（iproute2 JSON 输出）枚举，复用既有 `RawAdapterAddress` 结构，
  上层筛选逻辑（`is_scan_adapter` / `_rejection_reason`）零改动
- **物理网卡判定**：`/sys/class/net/<name>` 指向 `/sys/devices/virtual/` 的一律视为虚拟，
  排除 lo / 网桥 / veth / docker / TUN(Tailscale、Mihomo 等)
- **无线网卡识别**：`/sys/class/net/<name>/wireless` 存在则为 IEEE80211
- **链路状态**：`flags` 含 `LOWER_UP` 且无 `NO-CARRIER` 才算已连接
- 新增 `enumerate_adapter_addresses()` 按平台分派，Windows 行为完全不变

实测（Arch + KDE Wayland，无线网卡）：

```
[扫描] 使用网卡 wlo1: 192.168.5.0/24
[扫描] 待探测地址 253 个
[扫描] 端口探测完成，1 个 IP 的 5555 端口开放
```

## 五、已知问题：XWayland(xcb) 下会段错误

`QT_QPA_PLATFORM=xcb` 启动会 SIGSEGV（崩溃栈在 `QXcbWindow::handleNativeEvent`）。
原生 Wayland 插件下无此问题。`run.sh` 与 AppImage 的 `AppRun` 均默认
`QT_QPA_PLATFORM=wayland`。纯 X11 会话下可能不稳定，属上游程序问题。

## 六、构建 AppImage

```bash
./packaging/appimage/build-appimage.sh
# 产物：dist-appimage/mimonitor-toolbox-x86_64.AppImage
```

CI 见 `.github/workflows/appimage.yml`，push 到 master 或打 tag 自动构建。

### 体积优化（约 300 MB → 44 MB）

1. **Qt 库依赖闭包裁剪**（`prune_qt.py`）：从实际 import 的 PyQt6 模块 + 平台插件
   出发递归求闭包，只保留必需库。手工白名单极易漏依赖（如 `libqwayland.so`
   间接依赖 WaylandClient），漏了就会回落到系统 Qt 6.12 而启动失败。
2. **删除未用 Qt 组件**：QML、Quick3D、QuickControls2、Designer、Pdf、WebEngine、
    Multimedia、翻译（~11 MB）、类型存根
3. **删除 ffmpeg 系列**（~20 MB，无 Qt 模块链接）
4. **标准库裁剪**：排除 test/idlelib/tkinter/ensurepip/pydoc_data/config-*
5. **strip 全部 .so** + 删 `__pycache__`/`*.pyc`/`*.prl`
6. **squashfs zstd level 22 + 1M block**（appimagetool 未编译 xz）

> 关键教训：不要"先删库再补回"——必须让闭包算法一次算全，
> 否则会漏掉插件间接依赖。

### 自包含性

构建脚本会 `ldd` 出 Qt 库与平台插件的全部外部依赖并复制进包内
（glibc 核心交给系统，避免与宿主机冲突）。
已在**无 libGL 的 archlinux 容器**中实测可正常启动。

## 七、应用数据

`~/.gpro_controller/`（`config.json`、`logs/`）
