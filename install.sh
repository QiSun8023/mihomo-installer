#!/bin/bash

# ================= 配置区域 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
CONFIG_DIR="/etc/mihomo"
TEMPLATE_FILE="./config.template.yaml"

echo -e "${GREEN}=== Mihomo Linux 通用一键安装脚本 ===${NC}"

# 1. 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
   exit 1
fi

# 2. 检查基础依赖
echo -e "${YELLOW}Step 1/6: 检查系统依赖...${NC}"
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

# 3. 检查模板文件
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${RED}错误: 未找到 config.template.yaml 文件！${NC}"
    exit 1
fi

# 4. 系统架构识别
echo -e "${YELLOW}Step 2/6: 检测系统架构...${NC}"
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

# 5. 安装核心
echo -e "${YELLOW}Step 3/6: 安装 Mihomo 核心...${NC}"
mkdir -p "$CONFIG_DIR"
LATEST_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_VERSION" ]]; then
    echo -e "${RED}版本获取失败，请检查网络。${NC}"
    exit 1
fi

FILE_NAME="mihomo-linux-${Download_Arch}-${LATEST_VERSION}.gz"
DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VERSION}/${FILE_NAME}"

wget -O "/tmp/mihomo.gz" "$DOWNLOAD_URL"
if [[ $? -ne 0 ]]; then echo -e "${RED}下载失败${NC}"; exit 1; fi

gzip -d -c /tmp/mihomo.gz > /usr/local/bin/mihomo
chmod +x /usr/local/bin/mihomo
rm /tmp/mihomo.gz

# 6. 下载 Geo 数据库
echo -e "${YELLOW}Step 4/6: 下载 GeoIP/GeoSite 数据库...${NC}"
wget -q --show-progress -O "${CONFIG_DIR}/GeoLite2-Country.mmdb" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
wget -q --show-progress -O "${CONFIG_DIR}/geosite.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
wget -q --show-progress -O "${CONFIG_DIR}/geoip.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"

# 7. 部署 UI (使用小写 ui 路径)
echo -e "${YELLOW}Step 5/6: 部署 Zashboard 面板...${NC}"
# 注意这里改为小写 ui
mkdir -p "${CONFIG_DIR}/ui"
wget -q --show-progress -O "/tmp/zashboard.zip" "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"

if [[ $? -eq 0 ]]; then
    unzip -q -o "/tmp/zashboard.zip" -d "/tmp/"
    # 清理旧目录
    rm -rf "${CONFIG_DIR}/ui/zashboard"
    # 移动到小写 ui 目录
    mv "/tmp/zashboard-gh-pages" "${CONFIG_DIR}/ui/zashboard"
    rm "/tmp/zashboard.zip"
else
    echo -e "${RED}UI 面板下载失败，跳过。${NC}"
fi

# 8. 交互式配置 (现在移动到了这里)
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   核心组件安装完成，开始配置订阅...   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}请输入您的机场订阅链接 (按 Ctrl+C 可跳过):${NC}"
read -r SUB_URL

if [[ -z "$SUB_URL" ]]; then
    echo -e "${RED}警告: 未输入订阅链接，将使用默认占位符。${NC}"
fi

# 9. 生成配置文件
echo -e "${YELLOW}Step 6/6: 应用配置...${NC}"
cp "$TEMPLATE_FILE" "${CONFIG_DIR}/config.yaml"
if [[ -n "$SUB_URL" ]]; then
    sed -i "s|{{SUBSCRIPTION_URL}}|$SUB_URL|g" "${CONFIG_DIR}/config.yaml"
fi

# 10. Systemd 服务
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

# 11. 启动
systemctl daemon-reload
systemctl enable mihomo
systemctl restart mihomo

echo -e "${GREEN}=== 安装全部完成 ===${NC}"
echo -e "控制面板: http://<IP>:9090/ui"
echo -e "配置文件: /etc/mihomo/config.yaml"
