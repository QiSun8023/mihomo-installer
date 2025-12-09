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

# ================= 辅助函数：版本检测 (文件名提取Hash版) =================
# 定义全局变量
CURRENT_VER="检测中..."
LATEST_STABLE_VER="检测中..."
LATEST_ALPHA_VER="检测中..."

# 获取远程版本的通用函数
# 参数 $1: API URL
# 参数 $2: 是否为 Alpha (1=是, 0=否)
function fetch_remote_version() {
    local url="$1"
    local is_alpha="$2"
    local version=""
    local commit_sha=""
    
    # 1. 尝试直连 (5秒超时)
    local api_res=$(curl -s -m 5 "$url")
    
    # 2. 如果失败且本地有代理，尝试走代理
    if [[ -z "$api_res" ]] || [[ "$api_res" == *"API rate limit"* ]]; then
        if netstat -tunlp 2>/dev/null | grep -q ":7890 "; then
            api_res=$(curl -s -m 10 -x http://127.0.0.1:7890 "$url")
        fi
    fi
    
    # 3. 解析 JSON
    if [[ -n "$api_res" ]] && [[ "$api_res" != *"Not Found"* ]]; then
        # 提取 tag_name
        version=$(echo "$api_res" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
        
        # [修改点] 如果是 Alpha 版本，从文件名中提取 Hash
        if [[ "$is_alpha" == "1" ]]; then
            # 逻辑：查找包含 mihomo-linux-amd64-alpha-xxxx.gz 的行，提取 xxxx
            # 即使当前机器是 arm，查 amd64 的文件名也能拿到 hash，因为同一版本的 hash 是一样的
            commit_sha=$(echo "$api_res" | grep "mihomo-linux-amd64-alpha-" | head -n 1 | sed -E 's/.*alpha-([a-z0-9]+)\.gz.*/\1/')
            
            # 兜底：如果上面的方法没提取到 (防止文件名格式变动)，再尝试用旧方法
            if [[ -z "$commit_sha" ]] || [[ ${#commit_sha} -gt 10 ]]; then
                 commit_sha=$(echo "$api_res" | grep '"target_commitish":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' | cut -c 1-7)
            fi
        fi
    fi
    
    if [[ -z "$version" ]]; then
        echo "${RED}获取失败${NC}"
    else
        if [[ -n "$commit_sha" ]] && [[ "$commit_sha" != "main" ]]; then
            # 显示格式: Prerelease-Alpha (a1b2c3d)
            echo "${version} (${commit_sha})"
        else
            echo "$version"
        fi
    fi
}

function check_versions() {
    # 1. 获取本地版本
    if [ -f "/usr/local/bin/mihomo" ]; then
        CURRENT_VER=$(/usr/local/bin/mihomo -v 2>/dev/null | head -n 1 | awk '{print $3}')
    else
        CURRENT_VER="${RED}未安装${NC}"
    fi

    # 2. 获取远程版本 (缓存机制)
    if [[ "$LATEST_STABLE_VER" == "检测中..." ]] || [[ "$1" == "force" ]]; then
        LATEST_STABLE_VER=$(fetch_remote_version "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" 0)
        LATEST_ALPHA_VER=$(fetch_remote_version "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha" 1)
    fi
}

# ================= 功能函数 =================

# 1. 服务管理功能
function service_control() {
    case "$1" in
        start) systemctl start mihomo; echo -e "${GREEN}服务已启动${NC}" ;;
        stop) systemctl stop mihomo; echo -e "${YELLOW}服务已停止${NC}" ;;
        restart) systemctl restart mihomo; echo -e "${GREEN}服务已重启${NC}" ;;
        status) systemctl status mihomo -l --no-pager ;;
    esac
}

# 2. 更新 Mihomo 内核 (支持选择版本)
function update_core() {
    echo -e "${BLUE}正在检测最新版本信息...${NC}"
    check_versions force

    echo -e "\n${BLUE}请选择要更新的版本:${NC}"
    echo -e "1. ${GREEN}稳定版 (Stable)${NC}   -> ${LATEST_STABLE_VER}"
    echo -e "2. ${YELLOW}开发版 (Alpha)${NC}    -> ${LATEST_ALPHA_VER}"
    echo -e "0. 取消更新"
    read -p "请输入选项 [1-2]: " ver_choice

    local API_URL=""
    local TARGET_DISPLAY=""
    
    case "$ver_choice" in
        1)
            if [[ "$LATEST_STABLE_VER" == *"获取失败"* ]]; then echo -e "${RED}无法获取稳定版信息${NC}"; return; fi
            API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
            TARGET_DISPLAY="$LATEST_STABLE_VER"
            ;;
        2)
            if [[ "$LATEST_ALPHA_VER" == *"获取失败"* ]]; then echo -e "${RED}无法获取 Alpha 版信息${NC}"; return; fi
            API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha"
            TARGET_DISPLAY="$LATEST_ALPHA_VER"
            ;;
        *) return ;;
    esac

    # 架构识别
    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64)    Download_Arch="amd64" ;;
        aarch64)   Download_Arch="arm64" ;;
        armv7l)    Download_Arch="armv7" ;;
        *)         echo -e "${RED}不支持的架构${NC}"; return ;;
    esac

    echo -e "${YELLOW}正在获取下载链接 [$TARGET_DISPLAY]...${NC}"
    
    # 动态获取下载链接
    local api_json=$(curl -s "$API_URL")
    if [[ -z "$api_json" ]] && netstat -tunlp 2>/dev/null | grep -q ":7890 "; then
         api_json=$(curl -s -x http://127.0.0.1:7890 "$API_URL")
    fi
    
    # 提取对应架构的 .gz 文件 URL
    local DOWNLOAD_URL=$(echo "$api_json" | grep "browser_download_url" | grep "linux-$Download_Arch" | grep ".gz\"" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$DOWNLOAD_URL" ]]; then
        echo -e "${RED}错误：未找到适配当前架构 ($Download_Arch) 的下载资源。${NC}"
        return
    fi

    echo -e "下载地址: $DOWNLOAD_URL"
    echo -e "${YELLOW}正在下载...${NC}"
    
    # 下载
    wget -T 20 -O "/tmp/mihomo.gz" "$DOWNLOAD_URL" || \
    wget -e use_proxy=yes -e http_proxy=127.0.0.1:7890 -T 30 -O "/tmp/mihomo.gz" "$DOWNLOAD_URL"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${YELLOW}停止服务并安装...${NC}"
        systemctl stop mihomo
        gzip -d -c /tmp/mihomo.gz > /usr/local/bin/mihomo
        chmod +x /usr/local/bin/mihomo
        rm /tmp/mihomo.gz
        systemctl start mihomo
        echo -e "${GREEN}内核更新成功！当前版本已变更为: $(/usr/local/bin/mihomo -v | head -n1 | awk '{print $3}')${NC}"
        check_versions force
    else
        echo -e "${RED}下载失败，请检查网络。${NC}"
    fi
}

# 3. 更新 Geo 数据库
function update_geodb() {
    echo -e "${YELLOW}正在更新 Geo 数据库...${NC}"
    for url in \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" \
        "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"; do
        
        filename=$(basename "$url")
        wget -q --show-progress -O "${CONFIG_DIR}/$filename" "$url" || \
        wget -q --show-progress -e use_proxy=yes -e http_proxy=127.0.0.1:7890 -O "${CONFIG_DIR}/$filename" "$url"
    done
    echo -e "${GREEN}数据库更新完成，重启服务...${NC}"
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

# 5. 同步脚本
function git_pull_script() {
    echo -e "${YELLOW}正在同步脚本...${NC}"
    if [ -d ".git" ]; then
        git fetch --all; git reset --hard origin/main; chmod +x *.sh
        echo -e "${GREEN}同步完成，请重新运行。${NC}"; exit 0
    else
        echo -e "${RED}非 Git 目录，无法同步。${NC}"
    fi
}

# ================= 初始化 =================
echo -e "${BLUE}正在初始化...${NC}"
check_versions

# ================= 菜单逻辑 =================
while true; do
    sleep 0.1
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${GREEN}    Mihomo 管理脚本 (Manage Menu)    ${NC}"
    echo -e "${BLUE}=====================================${NC}"
    
    echo -e "当前安装版本: ${YELLOW}${CURRENT_VER}${NC}"
    echo -e "最新稳定版本: ${LATEST_STABLE_VER}"
    echo -e "最新 Alpha版: ${LATEST_ALPHA_VER}"
    echo -e "${BLUE}=====================================${NC}"

    echo -e "1. 启动服务"
    echo -e "2. 停止服务"
    echo -e "3. 重启服务"
    echo -e "4. 查看状态"
    echo -e "-------------------------------------"
    echo -e "5. 更新/切换 Mihomo 内核 (支持 Alpha)"
    echo -e "6. 更新 Geo 数据库"
    echo -e "7. 更新 UI 面板"
    echo -e "-------------------------------------"
    echo -e "8. 查看配置"
    echo -e "9. 查看日志 [Ctrl+C 退出]"
    echo -e "0. 同步脚本"
    echo -e "q. 退出"
    echo -e "${BLUE}=====================================${NC}"
    read -p "请输入选项: " choice

    case "$choice" in
        1) service_control start ;;
        2) service_control stop ;;
        3) service_control restart ;;
        4) service_control status; read -p "按回车继续..." ;;
        5) update_core; read -p "按回车继续..." ;;
        6) update_geodb; read -p "按回车继续..." ;;
        7) update_ui; read -p "按回车继续..." ;;
        8) nano /etc/mihomo/config.yaml ;;
        9) echo -e "${YELLOW}查看日志...${NC}"; journalctl -u mihomo -f ;;
        0) git_pull_script ;;
        q) exit 0 ;;
        *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
done
