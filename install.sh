#!/bin/bash

# ================= 配置区域 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
CONFIG_DIR="/etc/mihomo"
TEMPLATE_FILE="./config.template.yaml"

echo -e "${GREEN}=== Mihomo Armbian 安装助手 ===${NC}"

# 1. 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
   exit 1
fi

# 2. 检查配置文件模板是否存在
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${RED}错误: 未找到 config.template.yaml 文件！${NC}"
    echo -e "请确保您克隆了完整的仓库，并且脚本与 yaml 文件在同一目录下。"
    exit 1
fi

# 3. 询问订阅链接
echo -e "${YELLOW}请输入您的机场订阅链接:${NC}"
read -r SUB_URL

if [[ -z "$SUB_URL" ]]; then
    echo -e "${RED}错误: 订阅链接不能为空。${NC}"
    exit 1
fi

# 4. 系统架构检测
ARCH=$(uname -m)
echo -e "${YELLOW}系统架构: ${ARCH}${NC}"
if [[ "$ARCH" == "aarch64" ]]; then
    Download_Arch="arm64"
elif [[ "$ARCH" == "armv7l" ]]; then
    Download_Arch="armv7"
else
    echo -e "${RED}不支持的架构: ${ARCH}${NC}"
    exit 1
fi

# 5. 准备目录
mkdir -p "$CONFIG_DIR"

# 6. 下载并安装 Mihomo 核心
echo -e "${YELLOW}正在获取最新版本...${NC}"
LATEST_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_VERSION" ]]; then
    echo -e "${RED}获取版本失败，请检查网络。${NC}"
    exit 1
fi

echo -e "最新版本: ${LATEST_VERSION}"
FILE_NAME="mihomo-linux-${Download_Arch}-${LATEST_VERSION}.gz"
DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VERSION}/${FILE_NAME}"

echo -e "${YELLOW}正在下载并安装二进制文件...${NC}"
wget -O "/tmp/mihomo.gz" "$DOWNLOAD_URL"
if [[ $? -ne 0 ]]; then echo -e "${RED}下载失败${NC}"; exit 1; fi

gzip -d -c /tmp/mihomo.gz > /usr/local/bin/mihomo
chmod +x /usr/local/bin/mihomo
rm /tmp/mihomo.gz

# 7. 下载 Geo 数据库
echo -e "${YELLOW}更新 GeoIP/GeoSite 数据库...${NC}"
wget -O "${CONFIG_DIR}/GeoLite2-Country.mmdb" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
wget -O "${CONFIG_DIR}/geosite.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
wget -O "${CONFIG_DIR}/geoip.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"

# 8. 处理配置文件 (核心步骤)
echo -e "${YELLOW}正在应用配置...${NC}"
# 复制模板到系统目录
cp "$TEMPLATE_FILE" "${CONFIG_DIR}/config.yaml"
# 使用 sed 替换占位符 (处理 URL 中的特殊字符)
sed -i "s|{{SUBSCRIPTION_URL}}|$SUB_URL|g" "${CONFIG_DIR}/config.yaml"

# 9. 配置 Systemd
echo -e "${YELLOW}配置系统服务...${NC}"
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

# 10. 启动
systemctl daemon-reload
systemctl enable mihomo
systemctl restart mihomo

echo -e "${GREEN}=== 安装完成 ===${NC}"
echo -e "状态检查: sudo systemctl status mihomo"
echo -e "控制面板: http://<你的IP>:9090/ui"
