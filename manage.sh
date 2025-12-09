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

# ========================================================
# [核心修复] 捕捉 Ctrl+C 信号
# ========================================================
trap 'echo -e "\n${YELLOW}[提示] 操作已取消，返回主菜单...${NC}"; sleep 1' SIGINT

# ================= 辅助函数：版本检测 (增强版) =================
# 定义全局变量
CURRENT_VER="检测中..."
LATEST_VER="检测中..."

function check_versions() {
    # 1. 获取本地版本
    if [ -f "/usr/local/bin/mihomo" ]; then
        CURRENT_VER=$(/usr/local/bin/mihomo -v 2>/dev/null | head -n 1 | awk '{print $3}')
    else
        CURRENT_VER="${RED}未安装${NC}"
    fi

    # 2. 获取远程版本 (只在脚本启动时或更新后获取)
    if [[ "$LATEST_VER" == "检测中..." ]] || [[ "$1" == "force" ]]; then
        # 步骤 A: 尝试直连 (延长到 5秒)
        local api_res=$(curl -s -m 5 https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":')
        
        # 步骤 B: 如果直连失败，且本地 7890 端口通畅，尝试走代理检测
        if [ -z "$api_res" ]; then
            # 简单检测端口占用，判断代理是否开启
            if netstat -tunlp 2>/dev/null | grep -q ":7890 "; then
                # echo "尝试通过代理获取..." # 调试用
                api_res=$(curl -s -m 10 -x http://127.0.0.1:7890 https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name":')
            fi
        fi

        if [ -n "$api_res" ]; then
            LATEST_VER=$(echo "$api_res" | sed -E 's/.*"([^"]+)".*/\1/')
        else
            LATEST_VER="${RED}获取失败(网络超时)${NC}"
        fi
    fi
}

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
    
    check_versions force
    
    if [[ "$LATEST_VER" == *"获取失败"* ]]; then
        echo -e "${RED}无法获取最新版本信息，请检查网络或确保服务已启动。${NC}"
        return
    fi

    if [[ "$CURRENT_VER" == "$LATEST_VER" ]]; then
        echo -e "${GREEN}当前已是最新版本 ($CURRENT_VER)，无需更新。${NC}"
        read -p "是否强制重新安装? (y/n): " force_install
        if [[ "$force_install" != "y" ]]; then return; fi
    fi

    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64)    Download_Arch="amd64" ;;
        aarch64)   Download_Arch="arm64" ;;
        armv7l)    Download_Arch="armv7" ;;
        *)         echo -e "${RED}不支持的架构${NC}"; return ;;
    esac

    echo -e "目标版本: ${LATEST_VER}"
    DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-${Download_Arch}-${LATEST_VER}.gz"
    
    echo -e "${YELLOW}正在下载...${NC}"
    # 尝试下载 (先直连，失败则尝试代理)
    wget -T 15 -O "/tmp/mihomo.gz" "$DOWNLOAD_URL" || \
    wget -e use_proxy=yes -e http_proxy=127.0.0.1:7890 -T 20 -O "/tmp/mihomo.gz" "$DOWNLOAD_URL"
    
    if [[ $? -eq 0 ]]; then
        systemctl stop mihomo
        gzip -d -c /tmp/mihomo.gz > /usr/local/bin/mihomo
        chmod +x /usr/local/bin/mihomo
        rm /tmp/mihomo.gz
        systemctl start mihomo
        echo -e "${GREEN}内核更新完成并已重启服务！${NC}"
        check_versions force
    else
        echo -e "${RED}下载失败，请检查网络。${NC}"
    fi
}

# 3. 更新 Geo 数据库
function update_geodb() {
    echo -e "${YELLOW}正在更新 Geo 数据库...${NC}"
    # 同样增加了代理重试机制
    local DL_success=0
    for url in \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"; do
        
        filename=$(basename "$url")
        wget -q --show-progress -O "${CONFIG_DIR}/$filename" "$url"
        if [ $? -ne 0 ]; then
             echo -e "${YELLOW}直连下载 $filename 失败，尝试走代理...${NC}"
             wget -q --show-progress -e use_proxy=yes -e http_proxy=127.0.0.1:7890 -O "${CONFIG_DIR}/$filename" "$url"
        fi
    done
    
    echo -e "${GREEN}数据库更新流程结束，正在重启服务...${NC}"
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

# 5. 同步 GitHub 脚本代码
function git_pull_script() {
    echo -e "${YELLOW}正在从 GitHub 同步最新脚本...${NC}"
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

# ================= 初始化 =================
echo -e "${BLUE}正在初始化并检查版本...${NC}"
check_versions

# ================= 菜单逻辑 =================

while true; do
    sleep 0.1
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${GREEN}    Mihomo 管理脚本 (Manage Menu)    ${NC}"
    echo -e "${BLUE}=====================================${NC}"
    
    # === 版本显示区域 ===
    echo -e "当前内核: ${YELLOW}${CURRENT_VER}${NC}"
    
    # 修复了显示逻辑：只有当获取成功且版本不一致时才提示更新
    if [[ "$LATEST_VER" != "检测中..." ]] && [[ "$LATEST_VER" != *"获取失败"* ]]; then
        if [[ "$LATEST_VER" != "$CURRENT_VER" ]] && [[ "$CURRENT_VER" != *"未安装"* ]]; then
             echo -e "最新内核: ${GREEN}${LATEST_VER} (可更新)${NC}"
        else
             echo -e "最新内核: ${LATEST_VER} (已最新)"
        fi
    else
         # 如果获取失败，直接显示红色错误信息
         echo -e "最新内核: ${LATEST_VER}"
    fi
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
    echo -e "9. 查看实时日志 (View Log) [按 Ctrl+C 退出]"
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
        9) 
           echo -e "${YELLOW}正在打开日志... (按 Ctrl+C 返回菜单)${NC}"
           journalctl -u mihomo -f 
           ;;
        0) git_pull_script ;;
        q) exit 0 ;;
        *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
done
