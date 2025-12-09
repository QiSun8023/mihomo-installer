#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}      Mihomo 卸载脚本 (Armbian)        ${NC}"
echo -e "${RED}========================================${NC}"

# 1. 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
   exit 1
fi

# 2. 确认提示 (防止误删)
echo -e "${YELLOW}警告：此操作将彻底删除 Mihomo 程序、系统服务以及所有配置文件(含订阅信息)。${NC}"
read -p "您确定要继续吗？(y/n): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "操作已取消。"
    exit 0
fi

# 3. 停止并禁用服务
echo -e "${YELLOW}正在停止服务...${NC}"
if systemctl is-active --quiet mihomo; then
    systemctl stop mihomo
    systemctl disable mihomo
    echo -e "服务已停止并禁用。"
else
    echo -e "服务未运行，跳过停止步骤。"
fi

# 4. 删除系统服务文件
if [ -f "/etc/systemd/system/mihomo.service" ]; then
    rm /etc/systemd/system/mihomo.service
    systemctl daemon-reload
    echo -e "Systemd 服务文件已删除。"
fi

# 5. 删除二进制文件
if [ -f "/usr/local/bin/mihomo" ]; then
    rm /usr/local/bin/mihomo
    echo -e "核心程序已删除。"
fi

# 6. 删除配置目录
if [ -d "/etc/mihomo" ]; then
    rm -rf /etc/mihomo
    echo -e "配置文件目录 (/etc/mihomo) 已删除。"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}      Mihomo 已成功从系统中卸载      ${NC}"
echo -e "${GREEN}========================================${NC}"
