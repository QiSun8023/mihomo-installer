# Mihomo (Clash Meta) 一键安装脚本 - Linux 通用版

这是一个适用于 Linux 系统的 Mihomo (原 Clash Meta) 自动化安装与配置工具。
脚本旨在简化部署流程，支持从下载内核到配置面板的全自动化操作。

## ✨ 主要功能

* **全架构支持**：自动识别并适配 `amd64 (x86_64)`, `arm64 (aarch64)`, `armv7` 架构（支持 VPS、树莓派、Armbian 盒子等）。
* **完整环境部署**：
    * 自动获取 GitHub 最新版 Mihomo 内核。
    * 自动下载最新的 `GeoIP` 和 `GeoSite` 数据库。
    * 自动部署 `Zashboard` Web 控制面板。
* **分离式配置**：使用本地 `config.template.yaml` 作为模板，方便定制默认规则。
* **交互式配置**：安装流程结束后，脚本会自动询问并注入您的机场订阅链接。
* **Systemd 集成**：自动创建服务文件，支持开机自启和后台运行。

---

## 🚀 脚本使用说明

### 📥 一键安装 (Install)

| 步骤 | 操作 | 说明 |
| :--- | :--- | :--- |
| **1. 克隆仓库** | `git clone https://github.com/您的用户名/您的仓库名.git`<br>`cd 您的仓库名` | 下载脚本到本地 |
| **2. 修改配置** | (可选) 编辑 `config.template.yaml` | 如果需要修改端口或规则。<br>⚠️ **请勿修改** `url: "{{SUBSCRIPTION_URL}}"` |
| **3. 运行脚本** | `sudo bash install.sh` | 开始自动安装 |
| **4. 输入订阅** | 按屏幕提示操作 | 脚本跑完后会提示输入订阅链接，粘贴并回车即可。 |

### 🚀 极速安装 (Quick Start)

请根据您的网络环境选择一种安装方式：

**方式一：标准安装 (推荐)**
*适用于 VPS、海外服务器或网络环境良好的设备。*

`git clone --depth 1 [https://github.com/QiSun8023/mihomo-installer.git](https://github.com/QiSun8023/mihomo-installer.git) \
  && cd mihomo-installer \
  && sudo bash install.sh`

**方式二：国内加速安装**
*如果您的服务器位于国内，或无法连接 GitHub，请使用此镜像加速命令*
`git clone --depth 1 [https://gh-proxy.com/https://github.com/QiSun8023/mihomo-installer.git](https://gh-proxy.com/https://github.com/QiSun8023/mihomo-installer.git) \
  && cd mihomo-installer \
  && sudo bash install.sh`

### 🗑️ 一键卸载 (Uninstall)

如果您需要彻底清除 Mihomo 及其所有配置，请执行卸载脚本。

| 操作 | 命令 | 说明 |
| :--- | :--- | :--- |
| **执行卸载** | `sudo bash uninstall.sh` | **不可恢复！** 会删除程序、服务及所有配置文件。 |

> **卸载清理范围**：
> 1. 停止并禁用系统服务。
> 2. 删除 `/usr/local/bin/mihomo` 核心文件。
> 3. 删除 `/etc/mihomo` 目录下的所有文件（含配置、日志、数据库、UI）。

---

## 📂 路径与维护

### 📁 安装路径说明

脚本会将文件安装到标准的 Linux 系统目录中：

| 组件名称 | 路径位置 | 说明 |
| :--- | :--- | :--- |
| **核心程序** | `/usr/local/bin/mihomo` | Mihomo 二进制可执行文件 |
| **配置文件** | `/etc/mihomo/config.yaml` | 您的主要配置文件 |
| **UI 面板** | `/etc/mihomo/ui/zashboard` | Web 控制台静态文件 |
| **Geo 数据库** | `/etc/mihomo/*.dat` | `geoip.dat`, `geosite.dat` 等规则库 |
| **Systemd服务**| `/etc/systemd/system/mihomo.service` | 系统守护进程配置文件 |

### 🛠️ 常用维护命令

安装完成后，您可以使用标准的 systemd 命令来管理服务。

| 功能 | 命令 | 备注 |
| :--- | :--- | :--- |
| **启动服务** | `sudo systemctl start mihomo` | |
| **停止服务** | `sudo systemctl stop mihomo` | |
| **重启服务** | `sudo systemctl restart mihomo` | 修改配置文件后**必须**执行 |
| **查看状态** | `sudo systemctl status mihomo` | 检查运行状态和报错信息 |
| **查看日志** | `journalctl -u mihomo -f` | 实时查看日志 (按 `Ctrl+C` 退出) |
| **开机自启** | `sudo systemctl enable mihomo` | 设置开机自动运行 |

### 🌐 访问控制面板

确保服务运行正常后，在浏览器中输入：

```text
http://<您的服务器IP>:9090/ui
