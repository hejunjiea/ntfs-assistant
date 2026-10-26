# NTFS助手

macOS 上让 NTFS 磁盘可读写的图形化工具。系统原生只支持 NTFS 只读，本工具通过 ntfs-3g 接管磁盘为读写模式，并提供文件浏览器、传输队列和环境配置向导。

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Architecture](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)
[![Build](https://github.com/hejunjiea/ntfs-assistant/actions/workflows/build.yml/badge.svg)](https://github.com/hejunjiea/ntfs-assistant/actions/workflows/build.yml)

## 功能特性

**磁盘接管**

- 自动检测外接磁盘，显示文件系统类型、容量与已用比例
- 一键接管全部磁盘为读写模式，或单独接管指定磁盘
- 右键可"卸载并恢复只读"，整盘弹出
- 环境未配置时自动显示安装向导

**文件管理**

- 文件夹优先排序，支持按名称 / 大小 / 修改日期 / 类型排序
- 实时搜索过滤、显示隐藏文件开关、面包屑路径跳转
- 多选批量删除、批量复制，右键菜单按选中数量变文案
- 拖入自动复制、拖出到访达，同名文件自动追加序号
- 文件夹大小递归计算并缓存，避免重复扫描

**传输队列**

- 多文件串行排队，面板显示"第 2/5 个"
- 基于 `copyfile` 状态回调的真实进度，显示速度与剩余时间
- 单个任务取消 / 全部取消，取消后自动清理半成品
- 复制前空间预检，预留 5% 余量防止写满

**系统集成**

- 菜单栏常驻，可直接挂载 / 弹出
- 登录时自动启动（`SMAppService`）
- 挂载完成、传输结束推送系统通知
- 操作日志与顶部错误提示条

## 快捷键

| 快捷键 | 功能 |
|---|---|
| `⌘ C` | 复制选中项 |
| `⌘ V` | 粘贴到当前目录 |
| `⌘ ⌫` | 删除选中项（二次确认） |
| `空格` | Quick Look 预览 |

> 焦点需在文件列表上，在搜索框中输入时快捷键不会生效。

## 系统要求

- macOS 14.0 或更高版本
- Intel 或 Apple 芯片（提供 arm64 + x86_64 通用二进制）
- 需要 [ntfs-3g](https://github.com/tuxera/ntfs-3g) 与 [macFUSE](https://macfuse.github.io/)

## 安装

### 1. 安装运行环境

```bash
brew install --cask macfuse
brew install ntfs-3g-mac
```

安装 macFUSE 时会弹出系统扩展授权窗口，允许后需**重启电脑**。重启后在「系统设置 → 通用 → 登录项与扩展」中确认已加载。

> 首次打开 App 若检测到环境缺失，会直接显示分步配置向导，每一步都提供可复制的命令。

### 2. 下载并放行

从 [Releases](https://github.com/hejunjiea/ntfs-assistant/releases) 下载 `NTFS-Assistant-v1.0.0.zip`，解压后拖入「应用程序」。

由于本项目使用 ad-hoc 签名（未购买 Apple 开发者证书），首次打开会提示"无法验证开发者"：

```bash
xattr -dr com.apple.quarantine "/Applications/NTFS助手.app"
```

或双击后前往「系统设置 → 隐私与安全性」，点击「仍要打开」。

### 3. 开始使用

插上 NTFS 磁盘，点击左侧「一键挂载」，输入管理员密码即可。挂载成功后磁盘显示绿色对勾，右侧出现文件列表。

## 从源码构建

需要 Xcode 16 或更高版本。

```bash
# Debug 构建
./build_all.sh

# Release 构建（通用二进制 + 自动打包为 zip，输出到 dist/）
./release.sh

# 预览首次使用配置向导（调试用）
./preview_setup.sh
```

构建产物：

- Debug：`build/DerivedData/Build/Products/Debug/NTFS助手.app`
- 本地分发包：`dist/NTFS助手.zip`（含 App 与使用说明）

## 发布新版本

推送 `v*` 格式的 tag 会自动触发 Actions 构建并发布：

```bash
git tag v1.0.1
git push origin v1.0.1
```

工作流会构建通用二进制、做 ad-hoc 签名、打包为 `NTFS-Assistant-<tag>.zip`，并创建对应的 GitHub Release。也可以在 Actions 页面手动运行 `Release` 工作流并填入已有 tag，用于重建或补传资产。

自动化流程：

| 工作流 | 触发条件 | 作用 |
|---|---|---|
| `Build` | push 到 `main`、提交 PR | 编译验证，不产出发布包 |
| `Release` | 推送 `v*` tag、手动触发 | 构建、签名、打包并发布 Release |

## 项目结构

```
NTFS助手/
├── Models/          FileItem、GenericDisk、TransferTask
├── Disk/            DiskObserver —— 磁盘扫描、挂载、卸载、弹出
├── Files/           FileBrowserModel —— 目录、搜索、排序、大小缓存
├── Transfer/        TransferManager —— 队列、进度、取消、空间预检
├── Services/        LogStore、EnvironmentChecker、NotificationService、QuickLookController
└── Views/           ContentView、DiskListView、FileBrowserView、
                     TransferPanel、SetupGuideView、SettingsView 等
```

## 技术说明

- **磁盘监听**：`DiskArbitration` 框架注册变更回调，配合 `getfsstat` 读取内核实际挂载类型，判断磁盘是否已被接管
- **挂载方式**：先结束系统 `fsck_ntfs` 检查，强制卸载只读挂载，再以 `ntfs-3g` 携带 `allow_other` 参数重新挂载，因此后续文件操作无需 root 权限
- **传输进度**：使用 `copyfile()` 并注册 `COPYFILE_STATE_STATUS_CB` 回调，逐文件统计已拷字节，拼接为整体进度
- **权限提升**：仅挂载 / 弹出使用 `osascript` 管理员授权，其余文件操作用 `FileManager` 直接完成
- **命令安全**：拼入 Shell 的卷标与路径统一经单引号转义，防止命令注入

## 已知限制

- 未签名公证，每次分发都需要接收方手动放行一次
- 依赖第三方 NTFS 驱动，异常断电或磁盘存在坏道时仍有数据损坏风险，**重要数据请先备份**
- 无法支持 macOS 原生已不支持的文件系统格式
- 首次进入包含大量子文件夹的目录时，大小统计会有短暂延迟

## 免责声明

本软件通过修改磁盘挂载方式实现 NTFS 写入，属于第三方驱动方案。任何第三方 NTFS 实现都无法保证与 Windows 完全一致。使用前请务必备份重要数据，因数据损坏造成的损失作者不承担责任。

## 许可证

本项目基于 [MIT License](LICENSE) 开源，可自由使用、修改与分发，保留版权声明即可。
