#!/bin/bash
# NTFS助手 分发打包脚本
# 生成 Release 通用二进制（Apple Silicon + Intel）并压缩为 zip
set -e
cd "$(dirname "$0")"

APP_NAME="NTFS助手"
DERIVED="build/release"
DIST="dist"

echo "▶ 清理旧产物…"
rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

echo "▶ 构建 Release 通用二进制（arm64 + x86_64）…"
xcodebuild -project "$APP_NAME.xcodeproj" \
           -scheme "$APP_NAME" \
           -configuration Release \
           -derivedDataPath "$DERIVED" \
           -skipMacroValidation \
           ARCHS="arm64 x86_64" \
           ONLY_ACTIVE_ARCH=NO \
           build

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 构建产物不存在: $APP_PATH"
    exit 1
fi

STAGING="$DIST/$APP_NAME"
mkdir -p "$STAGING"

echo "▶ 复制到 dist…"
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"

echo "▶ 附带使用说明…"
if [ -f "使用说明.txt" ]; then
    cp "使用说明.txt" "$STAGING/"
fi

echo "▶ 压缩为 zip（保留符号链接与权限）…"
ditto -c -k --sequesterRsrc --keepParent "$STAGING" "$DIST/$APP_NAME.zip"

echo ""
echo "✅ 分发包已生成"
echo "   分发目录: $STAGING"
echo "   压缩包:   $DIST/$APP_NAME.zip"
echo ""
lipo -info "$STAGING/$APP_NAME.app/Contents/MacOS/$APP_NAME"
du -sh "$DIST/$APP_NAME.zip"
