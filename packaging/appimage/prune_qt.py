#!/usr/bin/env python3
"""计算 Qt 库依赖闭包并裁剪 PyQt6 的 Qt6 目录。

用法: prune_qt.py <Qt6目录> <PyQt6 site-packages 目录>

为什么用 Python 而不是 shell：
  - shell 里 `ldd | grep -q` 在 `set -o pipefail` 下，grep 提前退出会让
    管道返回 SIGPIPE，被 set -e 当成失败，导致构建中断。
  - 闭包需要迭代到不动点，用 Python 更清晰可靠。
"""
import os
import re
import subprocess
import sys

# 应用真正 import 的 PyQt6 模块（mimonitor_toolbox 只用这些）
APP_MODULES = ["QtCore", "QtGui", "QtWidgets", "QtNetwork", "QtSvg", "QtXml"]

# 需要保留的平台插件（Linux: wayland 为主，xcb/offscreen 备用）
KEEP_PLATFORMS = ("libqwayland", "libqxcb", "libqoffscreen")

QT_LIB_RE = re.compile(r"(libQt6[A-Za-z0-9_]+\.so(?:\.[0-9]+)*)")


def ldd_qt_libs(path):
    """返回某个 .so 直接依赖的 Qt 库文件名集合。"""
    try:
        out = subprocess.run(
            ["ldd", path], capture_output=True, text=True, timeout=30
        ).stdout
    except Exception:
        return set()
    return set(QT_LIB_RE.findall(out))


def main():
    if len(sys.argv) != 3:
        print("用法: prune_qt.py <Qt6目录> <PyQt6目录>", file=sys.stderr)
        return 2
    qt6_dir, pyqt6_dir = sys.argv[1], sys.argv[2]
    lib_dir = os.path.join(qt6_dir, "lib")
    plat_dir = os.path.join(qt6_dir, "plugins", "platforms")

    # 1) 起点：应用模块 + 平台插件
    needed = set()
    for mod in APP_MODULES:
        so = os.path.join(pyqt6_dir, mod + ".abi3.so")
        if os.path.exists(so):
            needed |= ldd_qt_libs(so)

    kept_plugins = []
    if os.path.isdir(plat_dir):
        for name in sorted(os.listdir(plat_dir)):
            if not name.endswith(".so"):
                continue
            if any(name.startswith(p) for p in KEEP_PLATFORMS):
                kept_plugins.append(name)
                needed |= ldd_qt_libs(os.path.join(plat_dir, name))
            else:
                os.remove(os.path.join(plat_dir, name))
                print("  删除平台插件: " + name)

    # 2) 迭代求传递闭包，直到不再增长
    changed = True
    while changed:
        changed = False
        for lib in list(needed):
            p = os.path.join(lib_dir, lib)
            if not os.path.exists(p):
                continue
            for dep in ldd_qt_libs(p):
                if dep not in needed:
                    needed.add(dep)
                    changed = True

    # 3) 先校验闭包自洽（必须在删除之前，否则查不到刚删的文件而误报）
    #    闭包外的库本来就该删，只有闭包内库的依赖缺失才是真问题。
    missing = []
    for lib in sorted(needed):
        p = os.path.join(lib_dir, lib)
        if not os.path.exists(p):
            missing.append(lib + " (文件不存在)")
            continue
        for dep in ldd_qt_libs(p):
            if dep not in needed:
                missing.append(lib + " -> " + dep)
    if missing:
        print("  [错误] 依赖闭包不完整，会导致回落到系统 Qt:", file=sys.stderr)
        for m in missing:
            print("    ! " + m, file=sys.stderr)
        return 1

    # 4) 删除闭包外的 Qt 库
    removed = []
    for name in sorted(os.listdir(lib_dir)):
        if not name.startswith("libQt6"):
            continue
        if name not in needed:
            os.remove(os.path.join(lib_dir, name))
            removed.append(name)

    # 5) 删除 ffmpeg 系列（无 Qt 模块链接它们，约省 20M）
    for name in sorted(os.listdir(lib_dir)):
        if re.match(r"lib(avcodec|avformat|avutil|swscale|swresample)", name):
            os.remove(os.path.join(lib_dir, name))
            removed.append(name)

    print("  保留 Qt 库 %d 个:" % len(needed))
    for n in sorted(needed):
        print("    + " + n)
    print("  删除 %d 个库/文件" % len(removed))
    print("  保留平台插件: " + ", ".join(kept_plugins))

    print("  依赖闭包校验通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
