#!/usr/bin/env bash
# 完全卸载脚本：删除本目录即彻底还原（应用不写系统目录、不改系统配置）
set -euo pipefail
APP_DIR="${1:-$HOME/Apps/Mimonitor_Toolbox}"
echo "将删除："
echo "  1) $APP_DIR            (程序本体 + venv)"
echo "  2) ~/.gpro_controller  (应用配置与日志)"
echo "  3) ~/.local/share/applications/mimonitor-toolbox.desktop (若存在)"
read -r -p "确认卸载？输入 yes 继续: " ans
[ "$ans" = "yes" ] || { echo "已取消"; exit 1; }
rm -rf "$APP_DIR"
rm -rf "$HOME/.gpro_controller"
rm -f "$HOME/.local/share/applications/mimonitor-toolbox.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "已卸载完成。"
