#!/usr/bin/env bash
# 红米 G Pro 27U Toolbox 启动器 (Linux)
# 说明：本脚本不做任何系统级修改，仅启动 ~/Apps/Mimonitor_Toolbox 内的 venv 应用。
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_DIR"

# 优先使用系统 PATH 中的 adb（Arch: pacman -S android-tools）
if ! command -v adb >/dev/null 2>&1; then
  echo "错误：未找到 adb。请先安装：sudo pacman -S android-tools" >&2
  exit 1
fi

# Linux 下强制使用原生 Wayland 平台插件。
# 原因：在 XWayland(xcb) 下本程序会段错误退出（见 README-linux.md）。
# 若你在纯 X11 会话中，请改用下方注释掉的 XCB 方式并自行承担风险。
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
  unset QT_QPA_PLATFORM
fi

exec "$APP_DIR/.venv/bin/python" "$APP_DIR/monitor_controller.py" "$@"
