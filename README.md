# Mihomo (Clash Meta) 一键安装脚本 - Linux 通用版

这是一个适用于 Linux 系统的 Mihomo (原 Clash Meta) 自动化安装与配置工具。
脚本支持自动检测系统架构，自动下载最新内核、Geo 数据库及 UI 面板，并配置 Systemd 开机自启。

## ✨ 主要功能

* **全架构支持**：自动识别并适配 `amd64 (x86_64)`, `arm64 (aarch64)`, `armv7` 架构（支持 VPS、树莓派、Armbian 盒子等）。
* **完整环境部署**：
    * 下载最新版 Mihomo 内核。
    * 下载最新的 `GeoIP` 和 `GeoSite` 数据库。
    * 下载并部署 `Zashboard` 控制面板。
* **分离式配置**：使用本地 `config.template.yaml` 作为模板，方便定制默认规则。
* **交互式配置**：安装流程结束后，自动询问并注入您的机场订阅链接。
* **Systemd 集成**：自动创建服务文件，支持开机自启和后台运行。

## 📋 目录结构

```text
.
├── config.yaml   # 配置文件模板 (可按需修改规则)
├── install.sh             # 一键安装脚本
├── uninstall.sh           # 一键卸载脚本
└── README.md              # 说明文档

# 请将下方链接替换为您实际的 GitHub 仓库地址
git clone [https://github.com/您的用户名/您的仓库名.git](https://github.com/您的用户名/您的仓库名.git)
cd 您的仓库名

组件	路径	备注
核心程序	/usr/local/bin/mihomo	可执行文件
配置文件	/etc/mihomo/config.yaml	最终生成的配置
UI 面板	/etc/mihomo/ui/zashboard	Web 控制台文件
Geo 数据库	/etc/mihomo/*.dat	路由规则数据库
Systemd服务	/etc/systemd/system/mihomo.service	服务守护文件
