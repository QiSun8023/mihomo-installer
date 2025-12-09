#!/bin/bash

# ================= 配置区域 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
CONFIG_DIR="/etc/mihomo"

# 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
   exit 1
fi

# ================= 功能函数 =================

# 1. 服务管理功能
function service_control() {
    case "$1" in
        start)
            systemctl start mihomo
            echo -e "${GREEN}服务已启动${NC}"
            ;;
        stop)
            systemctl stop mihomo
            echo -e "${YELLOW}服务已停止${NC}"
            ;;
        restart)
            systemctl restart mihomo
            echo -e "${GREEN}服务已重启${NC}"
            ;;
        status)
            systemctl status mihomo -l --no-pager
            ;;
    esac
}

# 2. 更新 Mihomo 内核
function update_core() {
    echo -e "${BLUE}正在检测最新版本...${NC}"
    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64)    Download_Arch="amd64" ;;
        aarch64)   Download_Arch="arm64" ;;
        armv7l)    Download_Arch="armv7" ;;
        *)         echo -e "${RED}不支持的架构${NC}"; return ;;
    esac

    LATEST_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$LATEST_VERSION" ]]; then echo -e "${RED}获取版本失败${NC}"; return; fi
    
    echo -e "最新版本: ${LATEST_VERSION}"
    DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VERSION}/mihomo-linux-${Download_Arch}-${LATEST_VERSION}.gz"
    
    echo -e "${YELLOW}正在下载...${NC}"
    wget -O "/tmp/mihomo.gz" "$DOWNLOAD_URL"
    
    if [[ $? -eq 0 ]]; then
        systemctl stop mihomo
        gzip -d -c /tmp/mihomo.gz > /usr/local/bin/mihomo
        chmod +x /usr/local/bin/mihomo
        rm /tmp/mihomo.gz
        systemctl start mihomo
        echo -e "${GREEN}内核更新完成并已重启服务！${NC}"
    else
        echo -e "${RED}下载失败${NC}"
    fi
}

# 3. 更新 Geo 数据库
function update_geodb() {
    echo -e "${YELLOW}正在更新 Geo 数据库...${NC}"
    wget -q --show-progress -O "${CONFIG_DIR}/GeoLite2-Country.mmdb" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
    wget -q --show-progress -O "${CONFIG_DIR}/geosite.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
    wget -q --show-progress -O "${CONFIG_DIR}/geoip.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
    echo -e "${GREEN}数据库更新完成，正在重启服务...${NC}"
    systemctl restart mihomo
}

# 4. 更新 UI 面板
function update_ui() {
    echo -e "${YELLOW}正在更新 Zashboard 面板...${NC}"
    wget -q -O "/tmp/zashboard.zip" "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
    if [[ $? -eq 0 ]]; then
        unzip -q -o "/tmp/zashboard.zip" -d "/tmp/"
        rm -rf "${CONFIG_DIR}/ui/zashboard"
        mv "/tmp/zashboard-gh-pages" "${CONFIG_DIR}/ui/zashboard"
        rm "/tmp/zashboard.zip"
        echo -e "${GREEN}UI 面板更新完成！${NC}"
    else
        echo -e "${RED}下载失败${NC}"
    fi
}

# 5. 同步 GitHub 脚本代码 (自身更新)
function git_pull_script() {
    echo -e "${YELLOW}正在从 GitHub 同步最新脚本...${NC}"
    # 确保当前目录是 git 仓库
    if [ -d ".git" ]; then
        git fetch --all
        git reset --hard origin/main
        chmod +x *.sh
        echo -e "${GREEN}脚本同步完成！请重新运行脚本。${NC}"
        exit 0
    else
        echo -e "${RED}错误：当前目录不是 Git 仓库，无法同步。${NC}"
    fi
}

# ================= 菜单逻辑 =================

while true; do
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${GREEN}    Mihomo 管理脚本 (Manage Menu)    ${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "1. 启动服务 (Start)"
    echo -e "2. 停止服务 (Stop)"
    echo -e "3. 重启服务 (Restart)"
    echo -e "4. 查看运行状态 (Status)"
    echo -e "-------------------------------------"
    echo -e "5. 更新 Mihomo 内核 (Update Core)"
    echo -e "6. 更新 Geo 数据库 (Update GeoDB)"
    echo -e "7. 更新 UI 面板 (Update UI)"
    echo -e "-------------------------------------"
    echo -e "8. 查看配置文件 (View Config)"
    echo -e "9. 查看实时日志 (View Log)"
    echo -e "0. 同步更新本脚本 (Git Pull)"
    echo -e "q. 退出 (Quit)"
    echo -e "${BLUE}=====================================${NC}"
    read -p "请输入选项: " choice

    case "$choice" in
        1) service_control start ;;
        2) service_control stop ;;
        3) service_control restart ;;
        4) service_control status; read -p "按回车键继续..." ;;
        5) update_core; read -p "按回车键继续..." ;;
        6) update_geodb; read -p "按回车键继续..." ;;
        7) update_ui; read -p "按回车键继续..." ;;
        8) nano /etc/mihomo/config.yaml ;;
        9) journalctl -u mihomo -f ;;
        0) git_pull_script ;;
        q) exit 0 ;;
        *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
done
