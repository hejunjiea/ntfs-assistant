#!/bin/bash
# 调试用：强制显示「首次使用：配置运行环境」向导页
# 用法：./preview_setup.sh
# 说明：以“全部未安装”的假状态打开向导，便于预览新手首次打开时的界面。
#       关闭窗口即可退出，不影响正常使用。
set -e
cd "$(dirname "$0")"

APP="./build/DerivedData/Build/Products/Debug/NTFS助手.app"

if [ ! -d "$APP" ]; then
    echo "未找到 Debug 构建产物，先执行一次 ./build_all.sh"
    exit 1
fi

echo "▶ 正在以调试模式启动向导预览…"
NTFS_FORCE_SETUP=1 "$APP/Contents/MacOS/NTFS助手"

echo "已退出预览。"
