#!/bin/bash

# ================= 配置区域 =================
# 定义颜色用于美化输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}========================================${NC}"
echo -e "${RED}      Mihomo 通用卸载脚本 (Linux)      ${NC}"
echo -e "${RED}========================================${NC}"

# 1. 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须以 root 权限运行此脚本。${NC}"
   echo -e "请使用: sudo bash uninstall.sh"
   exit 1
fi

# 2. 警告与确认
echo -e "${YELLOW}警告：此操作将执行以下清理：${NC}"
echo -e "  1. 停止并禁用 Mihomo 系统服务"
echo -e "  2. 删除系统服务文件 (/etc/systemd/system/mihomo.service)"
echo -e "  3. 删除核心程序 (/usr/local/bin/mihomo)"
echo -e "  4. 删除所有配置、日志、证书及 UI 面板 (/etc/mihomo)"
echo -e ""
read -p "您确定要继续吗？(输入 y 确认): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "操作已取消。"
    exit 0
fi

echo -e "${YELLOW}正在开始卸载...${NC}"

# 3. 停止并禁用服务
# 使用 2>/dev/null 屏蔽服务未运行时可能出现的报错信息
if systemctl is-active --quiet mihomo; then
    echo -e "正在停止服务..."
    systemctl stop mihomo
fi

if systemctl is-enabled --quiet mihomo 2>/dev/null; then
    echo -e "正在禁用开机自启..."
    systemctl disable mihomo
fi

# 4. 删除 Systemd 服务文件
if [ -f "/etc/systemd/system/mihomo.service" ]; then
    rm -f /etc/systemd/system/mihomo.service
    systemctl daemon-reload
    echo -e "服务文件已删除。"
fi

# 5. 删除二进制文件
if [ -f "/usr/local/bin/mihomo" ]; then
    rm -f /usr/local/bin/mihomo
    echo -e "核心程序已删除。"
fi

# 6. 删除配置目录 (递归强制删除)
# 这会同时删除 config.yaml, geo数据库, 以及 ui/UI 目录
if [ -d "/etc/mihomo" ]; then
    rm -rf /etc/mihomo
    echo -e "配置目录 (/etc/mihomo) 已彻底删除。"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}      Mihomo 已成功从系统中卸载      ${NC}"
echo -e "${GREEN}========================================${NC}"
