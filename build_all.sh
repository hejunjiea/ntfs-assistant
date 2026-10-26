#!/bin/bash
# NTFS助手 一键编译脚本
set -e
cd "$(dirname "$0")"

xcodebuild -project "NTFS助手.xcodeproj" \
           -scheme "NTFS助手" \
           -configuration Debug \
           -derivedDataPath "build/DerivedData" \
           -skipMacroValidation \
           build

echo ""
echo "✅ 编译完成，产物位于 build/DerivedData/Build/Products/Debug/NTFS助手.app"
