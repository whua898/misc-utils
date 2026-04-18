#!/bin/bash
# ============================================================================
# GitHub Codespaces VLESS 节点一键部署脚本
# 基于 sing-box v1.10.1 + VLESS + WebSocket + TLS
# 适用于 GitHub Codespaces (Linux 环境)
# ============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# 配置参数
SINGBOX_VERSION="${SINGBOX_VERSION:-1.10.1}"
LISTEN_PORT="${LISTEN_PORT:-8080}"
UUID="${UUID:-}"
INSTALL_DIR="./sing-box-deployment"

# ============================================================================
# 工具函数
# ============================================================================

print_separator() {
    echo -e "${GRAY}$(printf '=%.0s' {1..80})${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_info() {
    echo -e "${CYAN}[*] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

# ============================================================================
# 第一步：环境检查
# ============================================================================
print_separator
echo -e "${MAGENTA}GitHub Codespaces VLESS 节点部署工具${NC}"
echo -e "${MAGENTA}版本: sing-box v${SINGBOX_VERSION}${NC}"
print_separator

print_info "正在检查系统环境..."

# 检查必要命令
REQUIRED_COMMANDS=("wget" "tar" "cat")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        print_error "缺少必要命令: $cmd"
        exit 1
    fi
done
print_success "系统环境检查通过"

# 检查是否在 root 权限下
if [ "$(id -u)" -ne 0 ]; then
    print_warning "当前非 root 用户，某些操作可能需要 sudo 权限"
fi

# ============================================================================
# 第二步：生成或验证 UUID
# ============================================================================
if [ -z "$UUID" ]; then
    print_info "未提供 UUID，正在生成新的 UUID..."
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || openssl rand -hex 16 | sed 's/\(..\)/\1-/g; s/.$//')
    print_success "已生成 UUID: $UUID"
else
    print_success "使用提供的 UUID: $UUID"
fi

# ============================================================================
# 第三步：创建安装目录
# ============================================================================
print_info "创建安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
print_success "目录准备完成"

# ============================================================================
# 第四步：下载 sing-box
# ============================================================================
print_separator
print_info "开始下载 sing-box v${SINGBOX_VERSION}..."

SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz"
ARCHIVE_NAME="sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz"

if wget -q --show-progress "$SINGBOX_URL" -O "$ARCHIVE_NAME"; then
    print_success "sing-box 下载完成"
else
    print_error "wget 下载失败，尝试使用 curl..."
    if curl -L -o "$ARCHIVE_NAME" "$SINGBOX_URL"; then
        print_success "使用 curl 下载成功"
    else
        print_error "所有下载方式均失败，请检查网络连接"
        exit 1
    fi
fi

# ============================================================================
# 第五步：解压 sing-box
# ============================================================================
print_separator
print_info "正在解压 sing-box..."

tar -zxvf "$ARCHIVE_NAME" > /dev/null 2>&1

SINGBOX_DIR="sing-box-${SINGBOX_VERSION}-linux-amd64"
if [ ! -d "$SINGBOX_DIR" ]; then
    print_error "解压失败，目录不存在"
    exit 1
fi

cd "$SINGBOX_DIR"
print_success "sing-box 解压成功"

# ============================================================================
# 第六步：创建配置文件
# ============================================================================
print_separator
print_info "正在创建配置文件..."

cat <<EOF > ./config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${LISTEN_PORT},
      "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/vless"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

print_success "配置文件创建完成"
print_info "配置文件位置: $(pwd)/config.json"

# ============================================================================
# 第七步：启动 sing-box
# ============================================================================
print_separator
print_info "正在启动 sing-box 服务..."

# 检查是否已有进程在运行
if pgrep -f "sing-box run" > /dev/null; then
    print_warning "检测到 sing-box 已在运行，正在停止旧进程..."
    pkill -f "sing-box run" || true
    sleep 2
fi

# 后台启动 sing-box
nohup ./sing-box run -c ./config.json > sing-box.log 2>&1 &
SINGBOX_PID=$!

sleep 2

# 检查进程是否正常运行
if ps -p $SINGBOX_PID > /dev/null; then
    print_success "sing-box 启动成功 (PID: $SINGBOX_PID)"
else
    print_error "sing-box 启动失败，请查看日志: $(pwd)/sing-box.log"
    exit 1
fi

# ============================================================================
# 第八步：显示配置信息
# ============================================================================
print_separator
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}           VLESS 节点配置信息${NC}"
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
echo ""
print_info "请在 GitHub Codespaces 界面执行以下操作："
echo ""
echo -e "${YELLOW}1. 点击底部的 Ports 标签页${NC}"
echo -e "${YELLOW}2. 找到 ${LISTEN_PORT} 端口${NC}"
echo -e "${YELLOW}3. 右键点击 Visibility，将 Private 改为 Public${NC}"
echo -e "${YELLOW}4. 复制 Local Address（预览域名）${NC}"
echo ""
print_separator
echo -e "${CYAN}客户端配置参数 (以 v2rayN 为例):${NC}"
print_separator
echo -e "${GREEN}地址 (Address):${NC}     <你的 GitHub 预览域名> (不带 https://)"
echo -e "${GREEN}端口 (Port):${NC}         443 (重要！不是 ${LISTEN_PORT})"
echo -e "${GREEN}用户 ID (UUID):${NC}      ${UUID}"
echo -e "${GREEN}传输协议:${NC}            ws"
echo -e "${GREEN}路径 (Path):${NC}         /vless"
echo -e "${GREEN}TLS:${NC}                 tls"
echo -e "${GREEN}SNI:${NC}                 <你的 GitHub 预览域名>"
echo -e "${GREEN}伪装类型:${NC}            none"
echo ""
print_separator
echo -e "${CYAN}VLESS 分享链接格式:${NC}"
echo -e "${YELLOW}vless://${UUID}@<预览域名>:443?encryption=none&security=tls&type=ws&host=<预览域名>&path=%2Fvless#${NC}"
print_separator
echo ""

# ============================================================================
# 第九步：保存配置到文件
# ============================================================================
CONFIG_FILE="../vless-config.txt"
cat <<EOF > "$CONFIG_FILE"
========================================
VLESS 节点配置信息
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
========================================

UUID: ${UUID}
监听端口: ${LISTEN_PORT}
sing-box 版本: ${SINGBOX_VERSION}

客户端配置参数:
- 地址 (Address): <你的 GitHub 预览域名>
- 端口 (Port): 443
- 用户 ID (UUID): ${UUID}
- 传输协议: ws
- 路径 (Path): /vless
- TLS: tls
- SNI: <你的 GitHub 预览域名>
- 伪装类型: none

VLESS 分享链接:
vless://${UUID}@<预览域名>:443?encryption=none&security=tls&type=ws&host=<预览域名>&path=%2Fvless#

========================================
快速复活命令:
cd ${INSTALL_DIR}/${SINGBOX_DIR}
./sing-box run -c ./config.json

查看日志:
tail -f sing-box.log

停止服务:
pkill -f "sing-box run"
========================================
EOF

print_success "配置信息已保存到: $CONFIG_FILE"
print_info "可以使用 cat $CONFIG_FILE 查看完整配置"
echo ""

# ============================================================================
# 第十步：使用说明
# ============================================================================
print_separator
echo -e "${MAGENTA}重要提示:${NC}"
print_separator
echo -e "${YELLOW}⚠ 端口说明:${NC}"
echo "  - 内部监听端口: ${LISTEN_PORT}"
echo "  - 客户端连接端口: 443 (GitHub 强制 TLS)"
echo ""
echo -e "${YELLOW}⚠ 休眠机制:${NC}"
echo "  - Codespaces 无操作后会自动休眠"
echo "  - 发现连不上时，登录 GitHub 重新启动容器即可"
echo ""
echo -e "${YELLOW}⚠ 连接验证:${NC}"
echo "  - 客户端连接成功后，终端会显示 'connection accepted'"
echo "  - 可以使用 tail -f sing-box.log 实时查看日志"
echo ""
print_separator
print_success "部署完成！祝您使用愉快！"
print_separator
