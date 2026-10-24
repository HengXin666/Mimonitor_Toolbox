#!/usr/bin/env bash
# =============================================================================
# Mimonitor Toolbox — Arch Linux AppImage 构建脚本
# -----------------------------------------------------------------------------
# 目标：产出可直接双击运行的 .AppImage，并尽量压缩体积。
# 精简手段：剔除 QML/Quick3D/翻译/未用插件/测试/__pycache__，strip 二进制，xz 高压缩。
#
# 用法： ./packaging/appimage/build-appimage.sh [输出目录]
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/dist-appimage}"
APP_NAME="mimonitor-toolbox"
APPDIR="$OUT_DIR/$APP_NAME.AppDir"
BUILD_VENV="$OUT_DIR/.build-venv"

# 动态探测 Python 版本，避免硬编码（Arch 滚动更新，版本会变）
PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

log() { printf "\n==> %s\n" "$*"; }

log "[1/8] 准备构建环境 (Python $PYVER)"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
python3 -m venv "$BUILD_VENV"
PIP="$BUILD_VENV/bin/pip"
PY="$BUILD_VENV/bin/python"
"$PIP" install -q --upgrade pip
"$PIP" install -q \
  "PyQt6==6.11.0" \
  "PyQt6-Qt6==6.11.2" \
  "PyQt6-sip==13.11.1" \
  "PyQt6-Fluent-Widgets==1.11.2" \
  "PyQt6-Frameless-Window==0.8.1" \
  "darkdetect==0.8.0" \
  "ordered-set==4.1.0"

SITE="$("$PY" -c 'import site; print(site.getsitepackages()[0])')"

log "[2/8] 构建 AppDir 骨架"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"
APP_ROOT="$APPDIR/usr"

# ---- 应用源码（排除 venv/测试/CI/macos/构建脚本）----
mkdir -p "$APP_ROOT/lib/$APP_NAME"
rsync -a \
  --exclude=.git --exclude=.venv --exclude=tests --exclude=macos \
  --exclude=.github --exclude=dist-appimage --exclude=installer \
  --exclude="build*.bat" --exclude=requirements-build.txt --exclude=packaging \
  "$REPO_ROOT/mimonitor_toolbox" "$REPO_ROOT/monitor_controller.py" \
  "$REPO_ROOT/assets" \
  "$APP_ROOT/lib/$APP_NAME/"

# ---- Python 依赖 ----
SITE_DST="$APP_ROOT/lib/python$PYVER/site-packages"
mkdir -p "$SITE_DST"
# 注意：darkdetect / ordered_set 是包目录，不是单文件 .py
for pkg in PyQt6 qfluentwidgets qframelesswindow darkdetect ordered_set; do
  if [ -e "$SITE/$pkg" ]; then
    cp -a "$SITE/$pkg" "$SITE_DST/"
  else
    echo "警告：未找到依赖包 $pkg" >&2
  fi
done
cp -a "$SITE"/PyQt6-*.dist-info   "$SITE_DST/" 2>/dev/null || true
cp -a "$SITE"/PyQt6_Qt6-*.dist-info "$SITE_DST/" 2>/dev/null || true
cp -a "$SITE"/PyQt6_sip-*.dist-info "$SITE_DST/" 2>/dev/null || true
cp -a "$SITE"/PyQt6_Fluent_Widgets-*.dist-info "$SITE_DST/" 2>/dev/null || true

log "[3/8] 精简 Qt（剔除未使用的 QML / Quick3D / 翻译 / 多余插件）"
QT6_DST="$SITE_DST/PyQt6/Qt6"

# 注意：这里不再手工列举"要删哪些库"——那极易漏掉传递依赖。
# 库的裁剪完全交给下面的依赖闭包算法（prune_qt.py），它只会删除
# 闭包外的库，并自动校验闭包完整性。

rm -rf "$QT6_DST/qml" "$QT6_DST/translations" "$QT6_DST/qsci" 2>/dev/null || true
for d in sqldrivers qmlls sceneparsers assetimporters renderers multimedia \
         designer canbus position geoservices sensors texttospeech webview \
         generic iconengines networkinformation tls; do
  rm -rf "$QT6_DST/plugins/$d" 2>/dev/null || true
done

# 平台插件：只留 xcb / wayland / offscreen（应用在 Linux 必须走 wayland）
find "$QT6_DST/plugins/platforms" -type f \
  ! -name "libqxcb.so" ! -name "libqwayland*.so" ! -name "libqoffscreen.so" \
  -delete 2>/dev/null || true

# 图片格式：只留 png/jpeg/svg/gif/webp/ico
find "$QT6_DST/plugins/imageformats" -type f \
  ! -name "libqjpeg.so" ! -name "libqsvg.so" ! -name "libqgif.so" \
  ! -name "libqwebp.so" ! -name "libqico.so" \
  -delete 2>/dev/null || true

# 用"依赖闭包"而非手工白名单：手工列极易漏（例如 libqwayland.so 间接依赖
# WaylandClient），一旦漏掉就会回落到系统的更高版本 Qt（6.12），
# 报 "version Qt_6.12 not found" 而启动失败。
# 闭包计算放在 Python 里做，避免 shell 的 pipefail/SIGPIPE 陷阱。
"$PY" "$REPO_ROOT/packaging/appimage/prune_qt.py" "$QT6_DST" "$SITE_DST/PyQt6"

find "$QT6_DST" -name "*.debug" -delete 2>/dev/null || true
find "$QT6_DST" -name "*.prl" -delete 2>/dev/null || true
find "$QT6_DST" -name "*.pyi" -delete 2>/dev/null || true
find "$APP_ROOT" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP_ROOT" -name "*.pyc" -delete 2>/dev/null || true

log "[4/8] strip 二进制"
find "$APP_ROOT" -type f \( -name "*.so" -o -name "*.so.*" \) \
  -exec strip --strip-unneeded {} + 2>/dev/null || true

log "[5/8] 复制 Python 解释器与标准库"
STDLIB="$(python3 -c 'import sysconfig;print(sysconfig.get_paths()["stdlib"])')"
PYLIB_DST="$APP_ROOT/lib/python$PYVER"
mkdir -p "$PYLIB_DST"
# 全量复制标准库，但排除体积大且用不到的目录
rsync -a \
  --exclude=site-packages --exclude=test --exclude=idlelib --exclude=tkinter \
  --exclude=turtledemo --exclude=ensurepip --exclude=pydoc_data \
  --exclude=lib2to3 --exclude=config-* --exclude=__pycache__ \
  "$STDLIB/" "$PYLIB_DST/"

PYTHON_LIBDIR="$(python3 -c 'import sysconfig;print(sysconfig.get_config_var("LIBDIR"))')"
cp -a "$PYTHON_LIBDIR"/libpython$PYVER.so* "$APP_ROOT/lib/" 2>/dev/null || true
# 复制真实解释器二进制（不能用 command -v，那是符号链接会断链）
PY_REAL="$(readlink -f "$(command -v python3)")"
cp -a "$PY_REAL" "$APP_ROOT/bin/python$PYVER"
ln -sf "python$PYVER" "$APP_ROOT/bin/python3"

log "[6/8] 生成启动器与桌面入口"
cat > "$APPDIR/AppRun" <<APPRUN
#!/bin/bash
HERE="\$(dirname "\$(readlink -f "\${BASH_SOURCE[0]}")")"
export PATH="\$HERE/usr/bin:\$PATH"
export PYTHONHOME="\$HERE/usr"
export PYTHONPATH="\$HERE/usr/lib/python$PYVER:\$HERE/usr/lib/python$PYVER/site-packages"
export LD_LIBRARY_PATH="\$HERE/usr/lib:\$HERE/usr/lib/python$PYVER/site-packages/PyQt6/Qt6/lib:\${LD_LIBRARY_PATH:-}"
export QT_PLUGIN_PATH="\$HERE/usr/lib/python$PYVER/site-packages/PyQt6/Qt6/plugins"
export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-wayland}"
exec "\$HERE/usr/bin/python$PYVER" \
  "\$HERE/usr/lib/mimonitor-toolbox/monitor_controller.py" "\$@"
APPRUN
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/$APP_NAME.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=红米 G Pro 27U Toolbox
Comment=通过无线 ADB 控制红米 G Pro 27U 显示器 (Arch Linux)
Exec=AppRun
Icon=$APP_NAME
Categories=Utility;Settings;
Terminal=false
DESKTOP

if command -v magick >/dev/null 2>&1; then
  magick "$REPO_ROOT/assets/app/icon.ico[0]" -resize 256x256 \
    "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" 2>/dev/null || true
fi
cp -f "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" "$APPDIR/$APP_NAME.png" 2>/dev/null || true
cp -f "$APPDIR/$APP_NAME.desktop" "$APPDIR/usr/share/applications/$APP_NAME.desktop" 2>/dev/null || true

log "[7/8] 打包 AppImage"
TOOL="$OUT_DIR/appimagetool-x86_64.AppImage"
if [ ! -x "$TOOL" ]; then
  curl -fsSL -o "$TOOL" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi
export ARCH=x86_64
# appimagetool 内置的 mksquashfs 只编译了 zstd（没有 xz/lz4/gzip）。
# 用 zstd 最高等级 + 1M 大块，是当前环境能达到的最小体积。
"$TOOL" --comp zstd \
  --mksquashfs-opt -Xcompression-level --mksquashfs-opt 22 \
  --mksquashfs-opt -b --mksquashfs-opt 1048576 \
  --no-appstream "$APPDIR" "$OUT_DIR/${APP_NAME}-x86_64.AppImage"

log "[8/8] 完成"
ls -lh "$OUT_DIR"/*.AppImage
echo "产物: $OUT_DIR/${APP_NAME}-x86_64.AppImage"
