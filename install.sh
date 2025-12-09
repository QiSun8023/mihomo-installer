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
# [智能检测] 检测是否已安装 -> 显示信息 -> 退出
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

    # 3. 获取 IP (尝试绕过代理)
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    # 使用 --noproxy "*" 尝试绕过可能存在的环境变量代理
    PUBLIC_IP=$(curl --noproxy "*" -s icanhazip.com)
    
    [ -z "$LOCAL_IP" ] && LOCAL_IP="<内网IP>"
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP="<公网IP>"

    # 4. 输出信息
    echo -e "${GREEN}=== 当前服务运行信息 ===${NC}"
    echo -e "内网访问: http://${LOCAL_IP}:${CURRENT_PORT}/ui"
    echo -e "外网访问: http://${PUBLIC_IP}:${CURRENT_PORT}/ui (自动检测)"
    echo -e "访问密码: ${YELLOW}${CURRENT_SECRET}${NC}"
    echo -e "配置文件: ${CONFIG_DIR}/config.yaml"
    echo -e "常用命令: sudo systemctl status mihomo"
    echo -e ""
    echo -e "${YELLOW}注意: 如果外网 IP 显示为代理节点 IP，请直接使用您的服务器真实 IP 访问。${NC}"
    echo -e "${YELLOW}提示: 如需强制重装，请先卸载 (sudo bash uninstall.sh)。${NC}"
    
    exit 0
fi
# ================================================================


# --- 2. 检查 Systemd ---
echo -e "${YELLOW}Step 1/7: 检查 Systemd 环境...${NC}"
if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}严重错误: 未检测到 Systemd 初始化系统。${NC}"
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
