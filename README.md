# Mihomo Auto Installer for Armbian

这是一个适用于 Armbian (N1, 树莓派等) 的 Mihomo (Clash Meta) 一键安装配置脚本。

## 功能
- 自动检测系统架构 (arm64/armv7)
- 自动拉取 Mihomo 最新 Release 版本
- 自动下载最新的 GeoIP/GeoSite 数据库
- **分离式配置**：使用本地 `config.yaml` 模板
- 交互式输入订阅链接，自动替换并生成配置

## 使用方法

### 1. 克隆仓库
```bash
# 替换成你自己的 GitHub 仓库地址
git clone [https://github.com/您的用户名/您的仓库名.git](https://github.com/您的用户名/您的仓库名.git)
cd 您的仓库名
