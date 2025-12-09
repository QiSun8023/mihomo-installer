#!/bin/bash

# ================= 配置区域 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
CONFIG_DIR="/etc/mihomo"
TEMPLATE_FILE="./config.template.yaml"
# 定义硬编码的默认版本 (当API失败且用户不输入时使用)
DEFAULT_FALLBACK_VER="v1.19.17"

# 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
   exit 1
fi

trap 'echo -e "\n${YELLOW}[提示] 操作已取消...${NC}"; sleep 1' SIGINT

# ================= 辅助函数：版本检测 =================
CURRENT_VER="检测中..."
LATEST_STABLE_VER="检测中..."
LATEST_ALPHA_VER="检测中..."

function fetch_remote_version() {
    local url="$1"
    local is_alpha="$2"
    local api_res=$(curl -s -m 10 "$url")
    
    if [[ -n "$api_res" ]] && [[ "$api_res" != *"Not Found"* ]] && [[ "$api_res" != *"API rate limit"* ]]; then
        local version=$(echo "$api_res" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ "$is_alpha" == "1" ]]; then
            local raw_filename=$(echo "$api_res" | grep -oE "alpha-[a-f0-9]{6,}\.gz" | head -n 1)
            local commit_sha=""
            if [[ -n "$raw_filename" ]]; then
                commit_sha=$(echo "$raw_filename" | sed -E 's/alpha-([a-f0-9]+)\.gz/\1/')
            fi
            if [[ -n "$version" ]] && [[ -n "$commit_sha" ]]; then
                echo "${version} (${commit_sha})"
                return
            fi
        fi
        echo "$version"
    else
        echo "获取失败"
    fi
}

function check_versions() {
    if [ -f "/usr/local/bin/mihomo" ]; then
        CURRENT_VER=$(/usr/local/bin/mihomo -v 2>/dev/null | head -n 1 | awk '{print $3}')
        IS_INSTALLED=1
    else
        CURRENT_VER="${RED}未安装${NC}"
        IS_INSTALLED=0
    fi

    if [[ "$LATEST_STABLE_VER" == "检测中..." ]] || [[ "$1" == "force" ]]; then
        local stable_res=$(fetch_remote_version "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" 0)
        local alpha_res=$(fetch_remote_version "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha" 1)
        
        if [[ "$stable_res" == "获取失败" ]]; then
            LATEST_STABLE_VER="${RED}获取失败(API限制)${NC}"
            LATEST_ALPHA_VER="${RED}获取失败${NC}"
        else
            LATEST_STABLE_VER="$stable_res"
            LATEST_ALPHA_VER="$alpha_res"
        fi
    fi
}

# ================= 辅助函数：获取面板信息 =================
SHOW_PORT=""
SHOW_SECRET=""
SHOW_LOCAL_IP=""
SHOW_PUBLIC_IP=""
SHOW_CONFIG_PATH=""

function get_dashboard_info() {
    if [[ "$IS_INSTALLED" -eq 0 ]]; then return; fi

    if [ -f "${CONFIG_DIR}/config.yaml" ]; then
        SHOW_CONFIG_PATH="${CONFIG_DIR}/config.yaml"
        SHOW_PORT=$(grep '^external-controller:' "${CONFIG_DIR}/config.yaml" | awk -F ':' '{print $NF}' | tr -d ' "')
        [ -z "$SHOW_PORT" ] && SHOW_PORT="9090"
        SHOW_SECRET=$(grep '^secret:' "${CONFIG_DIR}/config.yaml" | sed 's/^secret: *//;s/"//g;s/'"'"'//g' | tr -d ' ')
        [ -z "$SHOW_SECRET" ] && SHOW_SECRET="<无密码>"
    else
        SHOW_CONFIG_PATH="${RED}${CONFIG_DIR}/config.yaml (未找到)${NC}"
        SHOW_SECRET="${RED}无配置${NC}"
        SHOW_PORT="9090"
    fi

    SHOW_LOCAL_IP=$(hostname -I | awk '{print $1}')
    [ -z "$SHOW_LOCAL_IP" ] && SHOW_LOCAL_IP="127.0.0.1"
    SHOW_PUBLIC_IP=$(curl -s --connect-timeout 2 ifconfig.me)
    [ -z "$SHOW_PUBLIC_IP" ] && SHOW_PUBLIC_IP="${RED}获取超时${NC}"
}

# ================= 核心功能模块 =================

# --- 功能 1: 安装/重装 Mihomo (含UI直装+智能默认值) ---
function install_mihomo() {
    echo -e "${GREEN}=== 开始安装 Mihomo (含UI) ===${NC}"

    if ! command -v systemctl &> /dev/null; then echo -e "${RED}错误: 无 Systemd${NC}"; return; fi
    if [[ ! -f "$TEMPLATE_FILE" ]]; then echo -e "${RED}错误: 缺少 config.template.yaml${NC}"; return; fi

    echo -e "${YELLOW}> 检查依赖...${NC}"
    for dep in curl wget unzip gzip; do
        if ! command -v $dep &> /dev/null; then
            if command -v apt &> /dev/null; then apt update && apt install -y $dep || return
            elif command -v yum &> /dev/null; then yum install -y $dep || return
            else echo -e "${RED}无法安装 $dep${NC}"; return; fi
        fi
    done

    echo -e "${YELLOW}> 获取最新版本...${NC}"
    check_versions force
    
    local auto_version=$(echo "$LATEST_STABLE_VER" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
    local install_version=""

    # === [优化] 版本选择逻辑 ===
    if [[ "$auto_version" != *"获取失败"* ]]; then
        echo -e "\n${BLUE}请选择要安装的版本:${NC}"
        echo -e "1. ${GREEN}稳定版 (Stable)${NC}   -> ${LATEST_STABLE_VER}"
        echo -e "2. ${YELLOW}Alpha版${NC}  -> ${LATEST_ALPHA_VER}"
        echo -e "3. 手动输入 (API受限时用)"
        read -p "选项 [默认1]: " v_choice
        case "$v_choice" in
            2) install_version="Prerelease-Alpha" ;;
            3) 
               # 手动输入带默认值
               read -p "请输入版本号 [默认: ${DEFAULT_FALLBACK_VER}]: " input_ver
               install_version="${input_ver:-$DEFAULT_FALLBACK_VER}"
               ;;
            *) install_version="$auto_version" ;;
        esac
    else
        # 自动获取失败时的强制输入逻辑
        echo -e "${RED}无法自动获取版本 (可能触发了 GitHub API 限制)${NC}"
        read -p "请手动输入版本号 [默认: ${DEFAULT_FALLBACK_VER}]: " input_ver
        install_version="${input_ver:-$DEFAULT_FALLBACK_VER}"
    fi

    # === 架构识别 ===
    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64) Download_Arch="amd64" ;;
        aarch64) Download_Arch="arm64" ;;
        armv7l) Download_Arch="armv7" ;;
        *) echo -e "${RED}不支持的架构${NC}"; return ;;
    esac

    # === 链接构建 ===
    local DOWNLOAD_URL=""
    if [[ "$install_version" == "Prerelease-Alpha" ]]; then
        echo -e "${YELLOW}正在解析 Alpha 下载地址...${NC}"
        local api_json=$(curl -s "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha")
        DOWNLOAD_URL=$(echo "$api_json" | grep "browser_download_url" | grep "linux-$Download_Arch" | grep ".gz\"" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ -z "$DOWNLOAD_URL" ]]; then echo -e "${RED}Alpha 解析失败，请选稳定版。${NC}"; return; fi
    else
        # 稳定版直接拼接，无论x86还是arm64都会自动适配
        DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${install_version}/mihomo-linux-${Download_Arch}-${install_version}.gz"
    fi

    echo -e "下载地址: $DOWNLOAD_URL"
    echo -e "${YELLOW}> 正在下载核心...${NC}"
    mkdir -p "$CONFIG_DIR"
    wget -q -O "/tmp/mihomo.gz" "$DOWNLOAD_URL"
    
    if [[ $? -ne 0 ]]; then echo -e "${RED}下载失败，请检查网络或版本号。${NC}"; return; fi

    systemctl stop mihomo 2>/dev/null
    gzip -d -c /tmp/mihomo.gz > /usr/local/bin/mihomo
    chmod +x /usr/local/bin/mihomo
    rm /tmp/mihomo.gz

    # 更新配套资源 & UI
    update_geodb || return
    update_ui || return  # 安装时自动下载 UI

    echo -e "${YELLOW}> 应用配置...${NC}"
    cp "$TEMPLATE_FILE" "${CONFIG_DIR}/config.yaml"
    
    if grep -q "{{SUBSCRIPTION_URL}}" "${CONFIG_DIR}/config.yaml"; then
        echo -e "${YELLOW}请输入机场订阅链接:${NC}"
        read -r SUB_URL
        [ -n "$SUB_URL" ] && sed -i "s|{{SUBSCRIPTION_URL}}|$SUB_URL|g" "${CONFIG_DIR}/config.yaml"
    fi
    if grep -q "{{UI_SECRET}}" "${CONFIG_DIR}/config.yaml"; then
        echo -e "${YELLOW}请设置面板密码 [默认: 123456]:${NC}"
        read -r USER_SECRET
        [ -z "$USER_SECRET" ] && USER_SECRET="123456"
        sed -i "s|{{UI_SECRET}}|$USER_SECRET|g" "${CONFIG_DIR}/config.yaml"
    fi

    echo -e "${YELLOW}> 配置服务...${NC}"
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

    echo -e "${GREEN}=== 安装完成 ===${NC}"
    check_versions force
    get_dashboard_info
}

# --- 功能: 更新 Geo ---
function update_geodb() {
    echo -e "${YELLOW}更新数据库...${NC}"
    for url in \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"; do
        wget -q --show-progress -O "${CONFIG_DIR}/$(basename $url)" "$url"
    done
    echo -e "${GREEN}数据库更新完成。${NC}"
    if [ -f "/etc/systemd/system/mihomo.service" ]; then systemctl restart mihomo; fi
}

# --- 功能: 更新 UI (根目录直装版) ---
function update_ui() {
    echo -e "${YELLOW}更新 UI (安装至 /ui 根目录)...${NC}"
    
    local TMP_UI_DIR="/tmp/mihomo_ui_extract"
    local TARGET_UI_DIR="${CONFIG_DIR}/ui"
    
    rm -rf "$TMP_UI_DIR"; mkdir -p "$TMP_UI_DIR"

    wget -q -O "/tmp/z.zip" "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
    
    if [[ $? -eq 0 ]]; then
        unzip -q -o "/tmp/z.zip" -d "$TMP_UI_DIR"
        local EXTRACTED_DIR=$(ls "$TMP_UI_DIR" | head -n 1)
        
        if [[ -n "$EXTRACTED_DIR" ]]; then
            # 1. 彻底清空 /etc/mihomo/ui 目录，确保无残留
            rm -rf "$TARGET_UI_DIR"
            mkdir -p "$TARGET_UI_DIR"
            
            # 2. 将内容直接平铺到 /etc/mihomo/ui/
            cp -rf "$TMP_UI_DIR/$EXTRACTED_DIR"/* "$TARGET_UI_DIR/"
            echo -e "${GREEN}UI 更新完成。文件位置: ${TARGET_UI_DIR}/index.html${NC}"
        else
            echo -e "${RED}解压失败，未找到文件。${NC}"
        fi
        
        rm -rf "$TMP_UI_DIR"; rm "/tmp/z.zip"
        if [ -f "/etc/systemd/system/mihomo.service" ]; then systemctl restart mihomo; fi
    else
        echo -e "${RED}UI下载失败${NC}"
    fi
}

# --- 功能: 服务管理 ---
function service_control() {
    case "$1" in
        start) systemctl start mihomo; echo -e "${GREEN}服务已启动${NC}" ;;
        stop) systemctl stop mihomo; echo -e "${YELLOW}服务已停止${NC}" ;;
        restart) systemctl restart mihomo; echo -e "${GREEN}服务已重启${NC}" ;;
        status) systemctl status mihomo -l --no-pager ;;
    esac
}

# --- 功能: 更新内核 (简版) ---
function update_core() {
    install_mihomo # 复用安装逻辑
}

# --- 功能: Git 同步 ---
function git_pull_script() {
    if [ -d ".git" ]; then
        echo -e "${YELLOW}同步脚本...${NC}"
        git fetch --all; git reset --hard origin/main; chmod +x *.sh
        echo -e "${GREEN}完成，请重新运行。${NC}"; exit 0
    else
        echo -e "${RED}非 Git 目录${NC}"
    fi
}

# --- 功能: 彻底卸载 ---
function uninstall_mihomo() {
    echo -e "${RED}=== Mihomo 彻底卸载 ===${NC}"
    echo -e "${YELLOW}即将删除服务、程序及所有配置。${NC}"
    read -p "确认卸载? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    systemctl stop mihomo 2>/dev/null
    systemctl disable mihomo 2>/dev/null
    
    if [ -f "/etc/systemd/system/mihomo.service" ]; then
        rm -f /etc/systemd/system/mihomo.service; systemctl daemon-reload
        echo -e "${GREEN}  [OK] 服务文件已删除${NC}"
    fi
    if [ -f "/usr/local/bin/mihomo" ]; then
        rm -f /usr/local/bin/mihomo
        echo -e "${GREEN}  [OK] 核心程序已删除${NC}"
    fi
    if [ -d "/etc/mihomo" ]; then
        rm -rf /etc/mihomo
        echo -e "${GREEN}  [OK] 配置目录已删除${NC}"
    fi
    
    check_versions force
}

# ================= CLI Mode =================
if [[ -n "$1" ]]; then
    case "$1" in
        install)   install_mihomo ;;
        uninstall) uninstall_mihomo ;;
        start)     service_control start ;;
        stop)      service_control stop ;;
        restart)   service_control restart ;;
        status)    service_control status ;;
        update)    update_core ;;
        log)       journalctl -u mihomo -f ;;
        *)         echo -e "${RED}用法: sudo bash mihomo.sh [install|...]${NC}" ;;
    esac
    exit 0
fi

# ================= Menu Mode =================
echo -e "${BLUE}初始化...${NC}"
check_versions
get_dashboard_info

while true; do
    get_dashboard_info 
    
    sleep 0.1
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${GREEN}      Mihomo 全能工具箱 (v3.5)       ${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "当前版本: ${YELLOW}${CURRENT_VER}${NC}"
    echo -e "最新稳定: ${LATEST_STABLE_VER}"
    echo -e "最新Alpha: ${LATEST_ALPHA_VER}"
    echo -e "${BLUE}-------------------------------------${NC}"
    
    if [[ "$IS_INSTALLED" -eq 1 ]]; then
        echo -e "内网访问: http://${SHOW_LOCAL_IP}:${SHOW_PORT}/ui"
        echo -e "外网访问: http://${SHOW_PUBLIC_IP}:${SHOW_PORT}/ui"
        echo -e "访问密码: ${YELLOW}${SHOW_SECRET}${NC}"
        echo -e "配置文件: ${SHOW_CONFIG_PATH}"
    else
        echo -e "${YELLOW}状态提示: 尚未安装 Mihomo，请选择选项 8 进行安装。${NC}"
    fi

    echo -e "${BLUE}=====================================${NC}"
    echo -e "1. 启动服务      2. 停止服务"
    echo -e "3. 重启服务      4. 查看状态"
    echo -e "${BLUE}-------------------------------------${NC}"
    echo -e "5. 更新内核      6. 更新数据库"
    echo -e "7. 更新 UI       ${GREEN}8. 安装/重装${NC}"
    echo -e "${BLUE}-------------------------------------${NC}"
    echo -e "9. 查看配置      L. 实时日志"
    echo -e "0. 同步脚本      ${RED}U. 彻底卸载${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${YELLOW}提示: 按回车键可刷新状态信息${NC}"
    read -p "请选择 [q退出]: " choice

    case "$choice" in
        1) service_control start ;;
        2) service_control stop ;;
        3) service_control restart ;;
        4) service_control status; read -p "按回车..." ;;
        5) update_core; read -p "按回车..." ;;
        6) update_geodb; read -p "按回车..." ;;
        7) update_ui; read -p "按回车..." ;;
        8) install_mihomo; read -p "按回车..." ;;
        9) nano /etc/mihomo/config.yaml ;;
        L|l) journalctl -u mihomo -f ;;
        0) git_pull_script ;;
        U|u) uninstall_mihomo; read -p "按回车..." ;;
        q) exit 0 ;;
        *) echo -e "刷新中...";;
    esac
done
