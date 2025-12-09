#!/bin/bash

# ================= 配置区域 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
CONFIG_DIR="/etc/mihomo"
TEMPLATE_FILE="./config.template.yaml"

echo -e "${GREEN}=== Mihomo Linux 智能一键安装脚本 ===${NC}"

# --- 1. 检查 Root 权限 ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
   exit 1
fi

# ================================================================
# [智能检测] 检测是否已安装 -> 读取现有配置 -> 显示信息 -> 退出
# ================================================================
if [ -f "/etc/systemd/system/mihomo.service" ] && [ -f "${CONFIG_DIR}/config.yaml" ]; then
    echo -e "${YELLOW}检测到 Mihomo 服务已安装，停止运行。${NC}"
    
    # 提取端口和密码用于显示
    CURRENT_PORT=$(grep '^external-controller:' "${CONFIG_DIR}/config.yaml" | awk -F ':' '{print $NF}' | tr -d ' "')
    [ -z "$CURRENT_PORT" ] && CURRENT_PORT="9090"
    
    CURRENT_SECRET=$(grep '^secret:' "${CONFIG_DIR}/config.yaml" | sed 's/^secret: *//;s/"//g;s/'"'"'//g' | tr -d ' ')
    [ -z "$CURRENT_SECRET" ] && CURRENT_SECRET="<未设置>"

    # 获取 IP (依赖 YAML 中的 DIRECT 规则显示真实 IP)
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me)
    [ -z "$LOCAL_IP" ] && LOCAL_IP="<内网IP>"
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP="<公网IP>"

    echo -e "${GREEN}=== 当前服务运行信息 ===${NC}"
    echo -e "内网访问: http://${LOCAL_IP}:${CURRENT_PORT}/ui"
    echo -e "外网访问: http://${PUBLIC_IP}:${CURRENT_PORT}/ui"
    echo -e "访问密码: ${YELLOW}${CURRENT_SECRET}${NC}"
    echo -e "配置文件: ${CONFIG_DIR}/config.yaml"
    echo -e ""
    echo -e "${YELLOW}提示: 如需强制重装，请先运行 sudo bash uninstall.sh${NC}"
    exit 0
fi

# --- 2. 检查 Systemd ---
if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}错误: 未检测到 Systemd，本脚本不支持此类系统。${NC}"
    exit 1
fi

# --- 3. 检查依赖 ---
echo -e "${YELLOW}Step 1/6: 检查环境依赖...${NC}"
DEPENDENCIES=("curl" "wget" "unzip" "gzip")
for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v $dep &> /dev/null; then
        echo -e "正在安装 $dep..."
        if command -v apt &> /dev/null; then apt update && apt install -y $dep
        elif command -v yum &> /dev/null; then yum install -y $dep
        else echo -e "${RED}无法自动安装 $dep，请手动安装。${NC}"; exit 1; fi
    fi
done

# --- 4. 检查模板 ---
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${RED}错误: 未找到 config.template.yaml 文件！${NC}"; exit 1
fi

# --- 5. 架构识别与核心安装 ---
echo -e "${YELLOW}Step 2/6: 安装 Mihomo 核心...${NC}"
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64)    Download_Arch="amd64" ;;
    aarch64)   Download_Arch="arm64" ;;
    armv7l)    Download_Arch="armv7" ;;
    *)         echo -e "${RED}不支持的架构: ${ARCH_RAW}${NC}"; exit 1 ;;
esac

mkdir -p "$CONFIG_DIR"
LATEST_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
[ -z "$LATEST_VERSION" ] && { echo -e "${RED}获取版本失败${NC}"; exit 1; }

DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VERSION}/mihomo-linux-${Download_Arch}-${LATEST_VERSION}.gz"
wget -O "/tmp/mihomo.gz" "$DOWNLOAD_URL"
[ $? -ne 0 ] && { echo -e "${RED}下载失败${NC}"; exit 1; }

gzip -d -c /tmp/mihomo.gz > /usr/local/bin/mihomo
chmod +x /usr/local/bin/mihomo
rm /tmp/mihomo.gz

# --- 6. 下载数据库 ---
echo -e "${YELLOW}Step 3/6: 下载 Geo 数据库...${NC}"
wget -q -O "${CONFIG_DIR}/GeoLite2-Country.mmdb" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
wget -q -O "${CONFIG_DIR}/geosite.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
wget -q -O "${CONFIG_DIR}/geoip.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"

# --- 7. 部署 UI ---
echo -e "${YELLOW}Step 4/6: 部署 UI 面板...${NC}"
mkdir -p "${CONFIG_DIR}/ui"
wget -q -O "/tmp/zashboard.zip" "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
if [[ $? -eq 0 ]]; then
    unzip -q -o "/tmp/zashboard.zip" -d "/tmp/"
    rm -rf "${CONFIG_DIR}/ui/zashboard"
    mv "/tmp/zashboard-gh-pages" "${CONFIG_DIR}/ui/zashboard"
    rm "/tmp/zashboard.zip"
fi

# --- 8. 应用配置 (智能询问) ---
echo -e "${YELLOW}Step 5/6: 应用配置...${NC}"
cp "$TEMPLATE_FILE" "${CONFIG_DIR}/config.yaml"

# 检测是否需要输入订阅
if grep -q "{{SUBSCRIPTION_URL}}" "${CONFIG_DIR}/config.yaml"; then
    echo -e "${YELLOW}请输入您的机场订阅链接:${NC}"
    read -r SUB_URL
    [ -n "$SUB_URL" ] && sed -i "s|{{SUBSCRIPTION_URL}}|$SUB_URL|g" "${CONFIG_DIR}/config.yaml"
fi

# 检测是否需要输入密码
if grep -q "{{UI_SECRET}}" "${CONFIG_DIR}/config.yaml"; then
    echo -e "${YELLOW}请设置面板密码 [默认: 123456]:${NC}"
    read -r USER_SECRET
    [ -z "$USER_SECRET" ] && USER_SECRET="123456"
    sed -i "s|{{UI_SECRET}}|$USER_SECRET|g" "${CONFIG_DIR}/config.yaml"
fi

# --- 9. 启动服务 ---
echo -e "${YELLOW}Step 6/6: 启动服务...${NC}"
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

systemctl daemon-reload
systemctl enable mihomo
systemctl restart mihomo

# --- 10. 完成显示 ---
LOCAL_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me) # 依赖 YAML 规则直连
USER_SECRET=$(grep '^secret:' "${CONFIG_DIR}/config.yaml" | sed 's/^secret: *//;s/"//g;s/'"'"'//g' | tr -d ' ')

echo -e "${GREEN}=== 安装全部完成 ===${NC}"
echo -e "内网访问: http://${LOCAL_IP}:9090/ui"
echo -e "外网访问: http://${PUBLIC_IP}:9090/ui"
echo -e "访问密码: ${YELLOW}${USER_SECRET}${NC}"
echo -e "配置文件: /etc/mihomo/config.yaml"
