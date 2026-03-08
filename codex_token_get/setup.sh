#!/bin/bash
###############################################################################
#  ChatGPT 批量注册 + CLIProxyAPI 一键部署脚本
#  适用系统: Ubuntu 20.04+ / Debian 11+ (x86_64)
#  用法: bash setup.sh --proxy 'http://user:pass@host:port'
###############################################################################
set -e

# ========== 颜色输出 ==========
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ========== 配置区域 (按需修改) ==========
INSTALL_DIR="/root/codex_token_get"
CLIPROXY_DIR="/root/cliproxy"
CLIPROXY_PORT=8317
CLIPROXY_API_KEY="sk-your-api-key"  # CLIProxy 的 API Key
CLIPROXY_MGMT_KEY=""                # CLIProxy 管理面板密码（留空则禁用管理API）
PROXY=""                            # 代理地址，格式: http://user:pass@host:port
PROXY_API=""                        # 代理API地址（可选，和PROXY二选一）
DUCKMAIL_API="https://api.duckmail.sbs"
TOTAL_ACCOUNTS=50                   # 每次注册数量
CRON_SCHEDULE="0 2 * * *"           # 定时任务: 每天凌晨2点
TOKEN_DEST="/root/.cli-proxy-api"   # Token 复制目标目录（CLIProxyAPI auth-dir）
SKIP_CLIPROXY=false                 # 跳过 CLIProxy 部署
SKIP_REGISTER=false                 # 跳过首次批量注册
CLIPROXY_DOWNLOAD_URL=""            # CLIProxy 下载地址（留空则从本地 tar.gz 安装）

# ========== 解析命令行参数 ==========
while [[ $# -gt 0 ]]; do
    case $1 in
        --proxy)            PROXY="$2";              shift 2 ;;
        --proxy-api)        PROXY_API="$2";          shift 2 ;;
        --count)            TOTAL_ACCOUNTS="$2";     shift 2 ;;
        --cron)             CRON_SCHEDULE="$2";      shift 2 ;;
        --dir)              INSTALL_DIR="$2";        shift 2 ;;
        --token-dest)       TOKEN_DEST="$2";         shift 2 ;;
        --cliproxy-dir)     CLIPROXY_DIR="$2";       shift 2 ;;
        --cliproxy-port)    CLIPROXY_PORT="$2";      shift 2 ;;
        --cliproxy-key)     CLIPROXY_API_KEY="$2";   shift 2 ;;
        --cliproxy-mgmt)    CLIPROXY_MGMT_KEY="$2";  shift 2 ;;
        --cliproxy-url)     CLIPROXY_DOWNLOAD_URL="$2"; shift 2 ;;
        --skip-cliproxy)    SKIP_CLIPROXY=true;      shift ;;
        --skip-register)    SKIP_REGISTER=true;      shift ;;
        --help|-h)
            echo "用法: bash setup.sh [选项]"
            echo ""
            echo "注册相关:"
            echo "  --proxy         代理地址 (http://user:pass@host:port)"
            echo "  --proxy-api     代理API地址 (每次请求获取新IP)"
            echo "  --count         每次注册数量 (默认50)"
            echo "  --cron          定时任务表达式 (默认 '0 2 * * *')"
            echo "  --dir           注册工具安装目录 (默认 /root/codex_token_get)"
            echo "  --skip-register 跳过首次批量注册"
            echo ""
            echo "CLIProxy 相关:"
            echo "  --cliproxy-dir  CLIProxy 安装目录 (默认 /root/cliproxy)"
            echo "  --cliproxy-port CLIProxy 端口 (默认 8317)"
            echo "  --cliproxy-key  CLIProxy API Key (默认 sk-your-api-key)"
            echo "  --cliproxy-mgmt CLIProxy 管理面板密码"
            echo "  --cliproxy-url  CLIProxy 下载地址 (留空则从本地安装)"
            echo "  --token-dest    Token复制目标目录 (默认 ~/.cli-proxy-api)"
            echo "  --skip-cliproxy 跳过 CLIProxy 部署"
            echo ""
            echo "示例:"
            echo "  # 完整部署: 注册 + CLIProxy"
            echo "  bash setup.sh --proxy 'http://user:pass@gate.ipfoxy.io:58688' --cliproxy-key 'sk-mykey'"
            echo ""
            echo "  # 仅部署注册工具"
            echo "  bash setup.sh --proxy 'http://user:pass@host:port' --skip-cliproxy"
            exit 0 ;;
        *) error "未知参数: $1, 使用 --help 查看帮助" ;;
    esac
done

echo ""
echo "###############################################"
echo "#  ChatGPT 注册 + CLIProxyAPI 一键部署        #"
echo "###############################################"
echo ""

TOTAL_STEPS=10
[[ "$SKIP_CLIPROXY" == true ]] && TOTAL_STEPS=8
[[ "$SKIP_REGISTER" == true ]] && TOTAL_STEPS=$((TOTAL_STEPS - 1))

# ========== 1. 系统依赖 ==========
info "1/${TOTAL_STEPS} 安装系统依赖..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip curl git > /dev/null 2>&1

# 安装 Node.js (如果不存在)
if ! command -v node &> /dev/null; then
    apt-get install -y -qq nodejs npm > /dev/null 2>&1
fi
info "系统依赖安装完成"

# ========== 2. Python 依赖 ==========
info "2/${TOTAL_STEPS} 安装 Python 依赖..."
pip3 install --upgrade pip > /dev/null 2>&1
pip3 install curl_cffi > /dev/null 2>&1
info "curl_cffi 安装完成: $(pip3 show curl_cffi 2>/dev/null | grep Version)"

# ========== 3. 安装 PM2 ==========
info "3/${TOTAL_STEPS} 安装 PM2..."
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2 > /dev/null 2>&1
    info "PM2 安装完成"
else
    info "PM2 已存在: $(pm2 -v)"
fi

# ========== 4. 创建项目目录 ==========
info "4/${TOTAL_STEPS} 初始化项目目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/codex_tokens"
mkdir -p "$TOKEN_DEST"

# ========== 5. 生成 config.json ==========
info "5/${TOTAL_STEPS} 生成注册工具配置文件..."

if [[ -f "$INSTALL_DIR/config.json" ]]; then
    warn "config.json 已存在，备份为 config.json.bak"
    cp "$INSTALL_DIR/config.json" "$INSTALL_DIR/config.json.bak"
fi

cat > "$INSTALL_DIR/config.json" << JSONEOF
{
  "_comment": "ChatGPT 批量自动注册工具配置文件",

  "total_accounts": ${TOTAL_ACCOUNTS},

  "duckmail_api_base": "${DUCKMAIL_API}",
  "duckmail_bearer": "",

  "proxy": "${PROXY}",

  "_proxy_pool_comment": "静态代理池，格式: socks5://user:pass@ip:port",
  "proxy_pool": [],

  "_proxy_api_comment": "代理API地址，每次注册自动获取新IP",
  "proxy_api": "${PROXY_API}",

  "output_file": "registered_accounts.txt",
  "enable_oauth": true,
  "oauth_required": true,
  "oauth_issuer": "https://auth.openai.com",
  "oauth_client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
  "oauth_redirect_uri": "http://localhost:1455/auth/callback",
  "ak_file": "ak.txt",
  "rk_file": "rk.txt",
  "token_json_dir": "codex_tokens"
}
JSONEOF
info "config.json 已生成"

# ========== 6. 生成定时执行脚本 ==========
info "6/${TOTAL_STEPS} 生成定时执行脚本..."

cat > "$INSTALL_DIR/daily_register.sh" << SHEOF
#!/bin/bash
# 每天定时批量注册账号 + 自动导入 CLIProxyAPI

cd "\$(dirname "\$0")"
TOKEN_DEST="${TOKEN_DEST}"

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ========== 开始批量注册 =========="

# 1. 运行注册脚本
python3 chatgpt_register.py

# 2. 将新生成的 token 复制到 CLIProxyAPI auth-dir
if [[ -d "\$TOKEN_DEST" ]]; then
    cp -f codex_tokens/*.json "\$TOKEN_DEST/" 2>/dev/null
    TOKEN_COUNT=\$(ls "\$TOKEN_DEST"/*.json 2>/dev/null | wc -l)
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Token 已复制到 \$TOKEN_DEST (共 \$TOKEN_COUNT 个)"
else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 警告: Token 目标目录不存在: \$TOKEN_DEST"
fi

# 3. CLIProxyAPI 会自动热加载 token，无需重启
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ========== 注册完成 =========="
SHEOF

chmod +x "$INSTALL_DIR/daily_register.sh"
info "daily_register.sh 已生成"

# ========== 7. 注册 PM2 定时任务 ==========
info "7/${TOTAL_STEPS} 注册 PM2 定时任务..."

if pm2 describe codex-daily-register > /dev/null 2>&1; then
    warn "PM2 进程 codex-daily-register 已存在，先删除..."
    pm2 delete codex-daily-register > /dev/null 2>&1
fi

pm2 start "$INSTALL_DIR/daily_register.sh" \
    --name "codex-daily-register" \
    --interpreter bash \
    --cron-restart "$CRON_SCHEDULE" \
    --no-autorestart \
    --output "$INSTALL_DIR/pm2_daily.out.log" \
    --error "$INSTALL_DIR/pm2_daily.err.log"

info "PM2 定时任务已注册 (cron: $CRON_SCHEDULE)"

# ========== 8. 部署 CLIProxyAPI ==========
STEP_CLIPROXY=8
if [[ "$SKIP_CLIPROXY" != true ]]; then
    info "${STEP_CLIPROXY}/${TOTAL_STEPS} 部署 CLIProxyAPI..."

    mkdir -p "$CLIPROXY_DIR"

    # 获取 CLIProxy 二进制（优先下载，其次本地解压）
    if [[ -n "$CLIPROXY_DOWNLOAD_URL" ]]; then
        info "从 URL 下载 CLIProxy..."
        curl -fsSL "$CLIPROXY_DOWNLOAD_URL" -o /tmp/cliproxy.tar.gz
        tar xzf /tmp/cliproxy.tar.gz -C "$CLIPROXY_DIR"
        rm -f /tmp/cliproxy.tar.gz
    elif [[ -f "$CLIPROXY_DIR/cliproxy.tar.gz" ]]; then
        info "从本地 tar.gz 解压..."
        tar xzf "$CLIPROXY_DIR/cliproxy.tar.gz" -C "$CLIPROXY_DIR"
    elif [[ -f "$INSTALL_DIR/cliproxy.tar.gz" ]]; then
        info "从注册目录的 tar.gz 解压..."
        tar xzf "$INSTALL_DIR/cliproxy.tar.gz" -C "$CLIPROXY_DIR"
    fi

    # 检查二进制是否存在
    if [[ ! -f "$CLIPROXY_DIR/cli-proxy-api" ]]; then
        warn "cli-proxy-api 二进制文件不存在!"
        warn "请手动下载 CLIProxy 到 $CLIPROXY_DIR/"
        warn "下载地址: https://github.com/anthropics/cli-proxy-api/releases"
    else
        chmod +x "$CLIPROXY_DIR/cli-proxy-api"
        info "CLIProxy 二进制文件就绪"
    fi

    # 生成 CLIProxy 配置文件
    info "生成 CLIProxy config.yaml..."

    if [[ -f "$CLIPROXY_DIR/config.yaml" ]]; then
        warn "CLIProxy config.yaml 已存在，备份为 config.yaml.bak"
        cp "$CLIPROXY_DIR/config.yaml" "$CLIPROXY_DIR/config.yaml.bak"
    fi

    # 处理管理密钥
    MGMT_KEY_LINE='  secret-key: ""'
    if [[ -n "$CLIPROXY_MGMT_KEY" ]]; then
        MGMT_KEY_LINE="  secret-key: \"${CLIPROXY_MGMT_KEY}\""
    fi

    cat > "$CLIPROXY_DIR/config.yaml" << YAMLEOF
# CLIProxyAPI 配置文件
host: ""
port: ${CLIPROXY_PORT}

tls:
  enable: false
  cert: ""
  key: ""

remote-management:
  allow-remote: true
${MGMT_KEY_LINE}
  disable-control-panel: false
  panel-github-repository: "https://github.com/router-for-me/Cli-Proxy-API-Management-Center"

# Token 目录（注册工具会自动将 token 复制到此目录）
auth-dir: "${TOKEN_DEST}"

# API Keys（客户端使用此 key 调用 API）
api-keys:
  - "${CLIPROXY_API_KEY}"

debug: false
commercial-mode: false
logging-to-file: false
usage-statistics-enabled: true
proxy-url: ""
force-model-prefix: false
passthrough-headers: false
request-retry: 3
max-retry-credentials: 0
max-retry-interval: 30

quota-exceeded:
  switch-project: true
  switch-preview-model: true

routing:
  strategy: "round-robin"

ws-auth: false
nonstream-keepalive-interval: 0
YAMLEOF

    info "CLIProxy config.yaml 已生成"

    # 注册 CLIProxy PM2 进程
    info "注册 CLIProxy PM2 进程..."

    if pm2 describe cliproxy > /dev/null 2>&1; then
        warn "PM2 进程 cliproxy 已存在，先删除..."
        pm2 delete cliproxy > /dev/null 2>&1
    fi

    if [[ -f "$CLIPROXY_DIR/cli-proxy-api" ]]; then
        pm2 start "$CLIPROXY_DIR/cli-proxy-api" \
            --name "cliproxy" \
            --cwd "$CLIPROXY_DIR"

        info "CLIProxy 已启动 (端口: $CLIPROXY_PORT)"
    else
        warn "CLIProxy 二进制不存在，跳过启动"
    fi
fi

# ========== 9. 首次批量注册 ==========
STEP_REGISTER=$((STEP_CLIPROXY + 1))
[[ "$SKIP_CLIPROXY" == true ]] && STEP_REGISTER=8

if [[ "$SKIP_REGISTER" != true ]]; then
    info "${STEP_REGISTER}/${TOTAL_STEPS} 执行首次批量注册 (${TOTAL_ACCOUNTS} 个账号)..."

    if [[ -z "$PROXY" && -z "$PROXY_API" ]]; then
        warn "未配置代理，首次注册可能会被封 IP！"
        warn "建议先配置代理再运行: bash setup.sh --proxy 'http://...'"
        echo ""
        read -p "是否仍然继续注册? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            info "跳过首次注册，稍后可手动执行: cd $INSTALL_DIR && python3 chatgpt_register.py"
            SKIP_REGISTER=true
        fi
    fi

    if [[ "$SKIP_REGISTER" != true ]]; then
        cd "$INSTALL_DIR"
        info "开始注册，请等待..."
        python3 chatgpt_register.py

        # 注册完成后复制 token 到 CLIProxy
        if [[ -d "$TOKEN_DEST" ]]; then
            cp -f codex_tokens/*.json "$TOKEN_DEST/" 2>/dev/null
            TOKEN_COUNT=$(ls "$TOKEN_DEST"/*.json 2>/dev/null | wc -l)
            info "Token 已复制到 $TOKEN_DEST (共 $TOKEN_COUNT 个)"
        fi

        # 统计结果
        TOTAL=$(grep -c "oauth=" registered_accounts.txt 2>/dev/null || echo "0")
        OK=$(grep -c "oauth=ok" registered_accounts.txt 2>/dev/null || echo "0")
        FAIL=$(grep -c "oauth=fail" registered_accounts.txt 2>/dev/null || echo "0")
        info "注册完成! 总数: $TOTAL | 成功: $OK | 失败: $FAIL"
    fi
else
    info "${STEP_REGISTER}/${TOTAL_STEPS} 跳过首次注册"
fi

# ========== 保存 PM2 ==========
pm2 save > /dev/null 2>&1
pm2 startup > /dev/null 2>&1 || true

# ========== 完成 ==========
echo ""
echo "###############################################"
echo "#  部署完成!                                   #"
echo "###############################################"
echo ""
echo "========== 注册工具 =========="
echo "  项目目录:     $INSTALL_DIR"
echo "  配置文件:     $INSTALL_DIR/config.json"
echo "  注册脚本:     $INSTALL_DIR/chatgpt_register.py"
echo "  定时计划:     $CRON_SCHEDULE (每天自动注册)"
echo "  Token 目录:   $INSTALL_DIR/codex_tokens/"
echo "  注册结果:     $INSTALL_DIR/registered_accounts.txt"
echo ""

if [[ "$SKIP_CLIPROXY" != true ]]; then
echo "========== CLIProxyAPI =========="
echo "  安装目录:     $CLIPROXY_DIR"
echo "  配置文件:     $CLIPROXY_DIR/config.yaml"
echo "  服务端口:     $CLIPROXY_PORT"
echo "  API Key:      $CLIPROXY_API_KEY"
echo "  Token 目录:   $TOKEN_DEST"
echo "  API 地址:     http://服务器IP:$CLIPROXY_PORT"
echo ""
fi

echo "========== 常用命令 =========="
echo "  手动注册:       cd $INSTALL_DIR && python3 chatgpt_register.py"
echo "  注册日志:       pm2 logs codex-daily-register --lines 50"
echo "  注册统计:       grep -c 'oauth=ok' $INSTALL_DIR/registered_accounts.txt"
if [[ "$SKIP_CLIPROXY" != true ]]; then
echo "  CLIProxy日志:   pm2 logs cliproxy --lines 30"
echo "  CLIProxy重启:   pm2 restart cliproxy"
fi
echo "  查看所有进程:   pm2 list"
echo "  修改注册配置:   vim $INSTALL_DIR/config.json"
if [[ "$SKIP_CLIPROXY" != true ]]; then
echo "  修改代理配置:   vim $CLIPROXY_DIR/config.yaml"
fi
echo ""

if [[ -z "$PROXY" && -z "$PROXY_API" ]]; then
    warn "⚠️  未配置代理! 裸 IP 注册很快会被 OpenAI 封禁"
    warn "   请编辑 config.json 添加 proxy 或 proxy_api"
    warn "   推荐使用海外住宅代理 (Residential Proxy)"
    echo ""
fi
