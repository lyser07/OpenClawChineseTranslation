#!/bin/bash
# ============================================================
# OpenClaw 汉化发行版 - Docker 一键部署脚本
# 
# 自动完成：环境检测、初始化配置、远程访问设置、启动容器
#
# 官方网站: https://openclaw.ai/
# 汉化项目: https://openclaw.qt.cool/
#
# 武汉晴辰天下网络科技有限公司 | https://qingchencloud.com/
#
# 用法:
#   curl -fsSL https://xxx/docker-deploy.sh | bash
#   curl -fsSL https://xxx/docker-deploy.sh | bash -s -- --token mytoken
#   curl -fsSL https://xxx/docker-deploy.sh | bash -s -- --local-only
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认配置
CONTAINER_NAME="openclaw"
VOLUME_NAME="openclaw-data"
PORT="18789"
IMAGE="ghcr.io/qingchencloud/openclaw-zh:latest"
GATEWAY_TOKEN=""
LOCAL_ONLY=false
SKIP_INIT=false

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            GATEWAY_TOKEN="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --local-only)
            LOCAL_ONLY=true
            shift
            ;;
        --skip-init)
            SKIP_INIT=true
            shift
            ;;
        --help|-h)
            echo "OpenClaw Docker 一键部署脚本"
            echo ""
            echo "用法:"
            echo "  curl -fsSL https://xxx/docker-deploy.sh | bash"
            echo "  curl -fsSL https://xxx/docker-deploy.sh | bash -s -- [选项]"
            echo ""
            echo "选项:"
            echo "  --token <token>   设置访问令牌（推荐）"
            echo "  --port <port>     设置端口（默认: 18789）"
            echo "  --name <name>     设置容器名（默认: openclaw）"
            echo "  --local-only      仅本地访问（不配置远程访问）"
            echo "  --skip-init       跳过初始化（容器已存在时）"
            echo "  --help            显示帮助信息"
            echo ""
            echo "示例:"
            echo "  # 远程访问模式（自动配置 allowInsecureAuth）"
            echo "  curl -fsSL .../docker-deploy.sh | bash -s -- --token mytoken123"
            echo ""
            echo "  # 仅本地访问"
            echo "  curl -fsSL .../docker-deploy.sh | bash -s -- --local-only"
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            exit 1
            ;;
    esac
done

# Logo
print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║     🦞 OpenClaw 汉化发行版 - Docker 部署                  ║"
    echo "║        开源个人 AI 助手平台                              ║"
    echo "║                                                           ║"
    echo "║     武汉晴辰天下网络科技有限公司                          ║"
    echo "║     https://openclaw.qt.cool/                             ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# 检查 Docker
check_docker() {
    if ! check_command docker; then
        echo -e "${RED}❌ 未检测到 Docker${NC}"
        echo ""
        echo -e "${YELLOW}请先安装 Docker：${NC}"
        echo "  官网: https://docs.docker.com/get-docker/"
        echo ""
        exit 1
    fi
    
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        echo -e "${RED}❌ Docker 未运行${NC}"
        echo ""
        echo -e "${YELLOW}请启动 Docker 服务后重试${NC}"
        exit 1
    fi
    
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
    echo -e "${GREEN}✓${NC} Docker 版本: $DOCKER_VERSION"
}

# 获取本机 IP
get_local_ip() {
    # 尝试多种方式获取 IP
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || \
               ip route get 1 2>/dev/null | awk '{print $7}' || \
               ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1 || \
               echo "localhost")
    echo "$LOCAL_IP"
}

# 生成随机 Token
generate_token() {
    if check_command openssl; then
        openssl rand -hex 16
    elif check_command tr; then
        tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32
    else
        echo "openclaw-$(date +%s)"
    fi
}

# 停止并删除现有容器
cleanup_existing() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${YELLOW}⚠${NC} 检测到现有容器 ${CONTAINER_NAME}，正在停止并删除..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} 已清理旧容器"
    fi
}

# 拉取镜像
pull_image() {
    echo ""
    echo -e "${BLUE}📦 拉取 Docker 镜像...${NC}"
    docker pull "$IMAGE"
    echo -e "${GREEN}✓${NC} 镜像拉取完成"
}

# 创建数据卷
create_volume() {
    if ! docker volume ls --format '{{.Name}}' | grep -q "^${VOLUME_NAME}$"; then
        echo -e "${BLUE}📁 创建数据卷 ${VOLUME_NAME}...${NC}"
        docker volume create "$VOLUME_NAME"
        echo -e "${GREEN}✓${NC} 数据卷创建完成"
    else
        echo -e "${GREEN}✓${NC} 数据卷 ${VOLUME_NAME} 已存在"
    fi
}

# 初始化配置
init_config() {
    if [ "$SKIP_INIT" = true ]; then
        echo -e "${YELLOW}⚠${NC} 跳过初始化（--skip-init）"
        return
    fi
    
    echo ""
    echo -e "${BLUE}⚙️  初始化 OpenClaw 配置...${NC}"
    
    # 执行 setup
    docker run --rm -v "${VOLUME_NAME}:/root/.openclaw" "$IMAGE" openclaw setup
    echo -e "${GREEN}✓${NC} 基础配置完成"
    
    # 设置 gateway.mode
    docker run --rm -v "${VOLUME_NAME}:/root/.openclaw" "$IMAGE" openclaw config set gateway.mode local
    echo -e "${GREEN}✓${NC} 设置 gateway.mode = local"
    
    # 远程访问配置
    if [ "$LOCAL_ONLY" = false ]; then
        echo ""
        echo -e "${BLUE}🌐 配置远程访问...${NC}"
        
        # 设置 bind 模式
        docker run --rm -v "${VOLUME_NAME}:/root/.openclaw" "$IMAGE" openclaw config set gateway.bind lan
        echo -e "${GREEN}✓${NC} 设置 gateway.bind = lan"
        
        # 启用不安全认证（HTTP 访问需要）
        docker run --rm -v "${VOLUME_NAME}:/root/.openclaw" "$IMAGE" openclaw config set gateway.controlUi.allowInsecureAuth true
        echo -e "${GREEN}✓${NC} 设置 gateway.controlUi.allowInsecureAuth = true"
    fi
}

# 启动容器
start_container() {
    echo ""
    echo -e "${BLUE}🚀 启动 OpenClaw 容器...${NC}"
    
    # 构建 docker run 命令
    DOCKER_CMD="docker run -d"
    DOCKER_CMD+=" --name $CONTAINER_NAME"
    DOCKER_CMD+=" -p ${PORT}:18789"
    DOCKER_CMD+=" -v ${VOLUME_NAME}:/root/.openclaw"
    
    # 添加 Token 环境变量
    if [ -n "$GATEWAY_TOKEN" ]; then
        DOCKER_CMD+=" -e OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN"
    fi
    
    DOCKER_CMD+=" --restart unless-stopped"
    DOCKER_CMD+=" $IMAGE"
    
    # 远程访问需要显式运行 gateway
    if [ "$LOCAL_ONLY" = false ]; then
        DOCKER_CMD+=" openclaw gateway run"
    fi
    
    # 执行
    eval $DOCKER_CMD
    
    echo -e "${GREEN}✓${NC} 容器启动完成"
}

# 等待服务就绪
wait_for_ready() {
    echo ""
    echo -e "${BLUE}⏳ 等待服务启动...${NC}"
    
    for i in {1..30}; do
        if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "listening on"; then
            echo -e "${GREEN}✓${NC} 服务已就绪"
            return 0
        fi
        sleep 1
    done
    
    echo -e "${YELLOW}⚠${NC} 等待超时，请检查日志: docker logs $CONTAINER_NAME"
}

# 打印成功信息
print_success() {
    LOCAL_IP=$(get_local_ip)
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║     ✅ OpenClaw Docker 部署成功！                         ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}📊 部署信息：${NC}"
    echo ""
    echo "   容器名称: $CONTAINER_NAME"
    echo "   数据卷:   $VOLUME_NAME"
    echo "   端口:     $PORT"
    
    if [ -n "$GATEWAY_TOKEN" ]; then
        echo "   Token:    $GATEWAY_TOKEN"
    fi
    echo ""
    
    echo -e "${CYAN}🌐 访问地址：${NC}"
    echo ""
    
    if [ "$LOCAL_ONLY" = true ]; then
        echo "   本地访问: http://localhost:${PORT}"
    else
        echo "   本地访问: http://localhost:${PORT}"
        if [ -n "$GATEWAY_TOKEN" ]; then
            echo "   远程访问: http://${LOCAL_IP}:${PORT}?token=${GATEWAY_TOKEN}"
        else
            echo "   远程访问: http://${LOCAL_IP}:${PORT}"
        fi
    fi
    echo ""
    
    echo -e "${CYAN}📝 常用命令：${NC}"
    echo ""
    echo "   docker logs -f $CONTAINER_NAME    # 查看日志"
    echo "   docker restart $CONTAINER_NAME    # 重启服务"
    echo "   docker stop $CONTAINER_NAME       # 停止服务"
    echo ""
    
    if [ "$LOCAL_ONLY" = false ]; then
        echo -e "${YELLOW}⚠  远程访问提示：${NC}"
        echo ""
        echo "   当前配置允许通过 HTTP 远程访问（仅 Token 认证）。"
        echo "   生产环境建议使用 HTTPS（Tailscale Serve 或 Nginx 反向代理）。"
        echo ""
    fi
    
    echo -e "${CYAN}📚 更多信息：${NC}"
    echo ""
    echo "   汉化官网: https://openclaw.qt.cool/"
    echo "   文档:     https://docs.openclaw.ai/"
    echo "   GitHub:   https://github.com/1186258278/OpenClawChineseTranslation"
    echo ""
}

# 主流程
main() {
    print_banner
    
    echo -e "${BLUE}🔍 环境检查...${NC}"
    echo ""
    
    check_docker
    
    # 如果没有指定 Token，生成一个
    if [ -z "$GATEWAY_TOKEN" ] && [ "$LOCAL_ONLY" = false ]; then
        GATEWAY_TOKEN=$(generate_token)
        echo -e "${GREEN}✓${NC} 自动生成 Token: $GATEWAY_TOKEN"
    fi
    
    cleanup_existing
    pull_image
    create_volume
    init_config
    start_container
    wait_for_ready
    print_success
}

main "$@"
