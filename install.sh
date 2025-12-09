#!/bin/bash

# ================= 配置区域 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
CONFIG_DIR="/etc/mihomo"
TEMPLATE_FILE="./config.template.yaml"

echo -e "${GREEN}=== Mihomo Linux 通用一键安装脚本 ===${NC}"

# --- 1. 检查 Root 权限 ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
   exit 1
fi

# ================================================================
# [智能检测] 检测是否已安装 -> 读取现有配置 -> 显示信息 -> 退出
# ================================================================
if [ -f "/etc/systemd/system/mihomo.service" ] && [ -f "${CONFIG_DIR}/config.yaml" ]; then
    echo -e "${YELLOW}检测到 Mihomo 服务已安装，停止运行安装脚本。${NC}"
    echo -e "正在读取配置信息..."
    
    # 1. 提取端口
    CURRENT_PORT=$(grep '^external-controller:' "${CONFIG_DIR}/config.yaml" | awk -F ':' '{print $NF}' | tr -d ' "')
    [ -z "$CURRENT_PORT" ] && CURRENT_PORT="9090"

    # 2. 提取密码
    CURRENT_SECRET=$(grep '^secret:' "${CONFIG_DIR}/config.yaml" | sed 's/^secret: *//;s/"//g;s/'"'"'//g' | tr -d ' ')
    [ -z "$CURRENT_SECRET" ] && CURRENT_SECRET="<未设置>"

    # 3. 获取 IP (尝试绕过代理获取真实IP)
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)
    if [ -n "$DEFAULT_IFACE" ]; then
        PUBLIC_IP=$(curl --interface "$DEFAULT_IFACE" -s --connect-timeout 3 ifconfig.me)
    else
        PUBLIC_IP=$(curl --noproxy "*" -s --connect-timeout 3 ifconfig.me)
    fi
    
    [ -z "$LOCAL_IP" ] && LOCAL_IP="<内网IP>"
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP="<公网IP/代理IP>"

    # 4. 输出信息
    echo -e "${GREEN}=== 当前服务运行信息 ===${NC}"
    echo -e "内网访问: http://${LOCAL_IP}:${CURRENT_PORT}/ui"
    echo -e "外网访问: http://${PUBLIC_IP}:${CURRENT_PORT}/ui"
    echo -e "访问密码: ${YELLOW}${CURRENT_SECRET}${NC}"
    echo -e "配置文件: ${CONFIG_DIR}/config.yaml"
    echo -e "常用命令: sudo systemctl status mihomo"
    echo -e ""
    echo -e "${YELLOW}提示: 如需强制重装/更新内核，请先卸载 (sudo bash uninstall.sh) 再运行此脚本。${NC}"
    
    exit 0
fi
# ================================================================


# --- 2. 检查 Systemd ---
echo -e "${YELLOW}Step 1/7: 检查 Systemd 环境...${NC}"
if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}严重错误: 未检测到 Systemd 初始化系统。${NC}"
    echo -e "本脚本不支持 OpenWrt/Alpine/Docker 等无 Systemd 环境。"
    exit 1
else
    echo -e "检测到 Systemd，继续安装..."
fi

# --- 3. 检查基础依赖 ---
echo -e "${YELLOW}Step 2/7: 检查系统依赖...${NC}"
DEPENDENCIES=("curl" "wget" "unzip" "gzip")
for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v $dep &> /dev/null; then
        echo -e "${YELLOW}正在安装 $dep...${NC}"
        if command -v apt &> /dev/null; then
            apt update && apt install -y $dep
        elif command -v yum &> /dev/null; then
            yum install -y $dep
        else
            echo -e "${RED}无法自动安装 $dep，请手动安装。${NC}"
            exit 1
        fi
    fi
done

# --- 4. 检查模板文件 ---
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${RED}错误: 未找到 config.template.yaml 文件！${NC}"
    echo -e "请确保您克隆了完整的仓库，且脚本与 yaml 文件在同一目录下。"
    exit 1
fi

# --- 5. 系统架构识别 ---
echo -e "${YELLOW}Step 3/7: 检测系统架构...${NC}"
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64)    Download_Arch="amd64" ;;
    aarch64)   Download_Arch="arm64" ;;
    armv7l)    Download_Arch="armv7" ;;
    *)         
        echo -e "${RED}不支持的架构: ${ARCH_RAW}${NC}"
        exit 1 
        ;;
esac
echo -e "架构: ${ARCH_RAW} -> ${Download_Arch}"

# --- 6. 安装核心 ---
echo -e "${YELLOW}Step 4/7: 安装 Mihomo 核心...${NC}"
mkdir -p "$CONFIG_DIR"
LATEST_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_VERSION" ]]; then
    echo -e "${RED}版本获取失败，请检查网络。${NC}"
    exit 1
fi

FILE_NAME="mihomo-linux-${Download_Arch}-${LATEST_VERSION}.gz"
DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VERSION}/${FILE_NAME}"

wget -O "/tmp/mihomo.gz" "$DOWNLOAD_URL"
if [[ $? -ne 0 ]]; then echo -e "${RED}核心下载失败${NC}"; exit 1; fi

gzip -d -c /tmp/mihomo.gz > /usr/local/bin/mihomo
chmod +x /usr/local/bin/mihomo
rm /tmp/mihomo.gz

# --- 7. 下载 Geo 数据库 ---
echo -e "${YELLOW}Step 5/7: 下载 GeoIP/GeoSite 数据库...${NC}"
wget -q --show-progress -O "${CONFIG_DIR}/GeoLite2-Country.mmdb" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
wget -q --show-progress -O "${CONFIG_DIR}/geosite.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
wget -q --show-progress -O "${CONFIG_DIR}/geoip.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"

# --- 8. 部署 UI 面板 ---
echo -e "${YELLOW}Step 6/7: 部署 Zashboard 面板...${NC}"
mkdir -p "${CONFIG_DIR}/ui"
wget -q --show-progress -O "/tmp/zashboard.zip" "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"

if [[ $? -eq 0 ]]; then
    unzip -q -o "/tmp/zashboard.zip" -d "/tmp/"
    rm -rf "${CONFIG_DIR}/ui/zashboard"
    mv "/tmp/zashboard-gh-pages" "${CONFIG_DIR}/ui/zashboard"
    rm "/tmp/zashboard.zip"
else
    echo -e "${RED}UI 面板下载失败，跳过。${NC}"
fi

# --- 9. 交互式配置 ---
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   核心组件安装完成，开始配置...       ${NC}"
echo -e "${GREEN}========================================${NC}"

# 8.1 订阅
echo -e "${YELLOW}1. 请输入您的机场订阅链接 (http/https开头):${NC}"
read -r SUB_URL
if [[ -z "$SUB_URL" ]]; then
    echo -e "${RED}警告: 未输入订阅链接，将保留默认占位符。${NC}"
fi
echo -e ""

# 8.2 密码
echo -e "${YELLOW}2. 请设置面板访问密码 (Secret) [默认: 123456]:${NC}"
read -r USER_SECRET
if [[ -z "$USER_SECRET" ]]; then
    USER_SECRET="123456"
    echo -e "${YELLOW}使用默认密码: 123456${NC}"
fi

# --- 10. 生成配置文件 ---
echo -e "${YELLOW}Step 7/7: 应用配置...${NC}"
cp "$TEMPLATE_FILE" "${CONFIG_DIR}/config.yaml"

if [[ -n "$SUB_URL" ]]; then
    sed -i "s|{{SUBSCRIPTION_URL}}|$SUB_URL|g" "${CONFIG_DIR}/config.yaml"
fi
sed -i "s|{{UI_SECRET}}|$USER_SECRET|g" "${CONFIG_DIR}/config.yaml"

# --- 11. Systemd 服务 ---
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# --- 12. 启动服务 ---
systemctl daemon-reload
systemctl enable mihomo
systemctl restart mihomo

# --- 13. [优化版] 获取 IP 信息 ---
# 1. 获取内网 IP
LOCAL_IP=$(hostname -I | awk '{print $1}')

# 2. 尝试获取默认物理网卡名称 (例如 eth0) 以绕过代理
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)

# 3. 尝试查询公网 IP
if [ -n "$DEFAULT_IFACE" ]; then
    # 尝试绑定物理网卡查询 (绕过 Tun)
    PUBLIC_IP=$(curl --interface "$DEFAULT_IFACE" -s --connect-timeout 3 ifconfig.me)
else
    # 找不到网卡名，尝试直接查询
    PUBLIC_IP=$(curl --noproxy "*" -s --connect-timeout 3 ifconfig.me)
fi

# 兜底
[ -z "$LOCAL_IP" ] && LOCAL_IP="<内网IP>"
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="<检测失败或为代理IP>"

echo -e "${GREEN}=== 安装全部完成 ===${NC}"
echo -e "内网访问: http://${LOCAL_IP}:9090/ui"
echo -e "外网访问: http://${PUBLIC_IP}:9090/ui"
echo -e "访问密码: ${YELLOW}${USER_SECRET}${NC}"
echo -e "配置文件: /etc/mihomo/config.yaml"
echo -e "常用命令: sudo systemctl status mihomo"
