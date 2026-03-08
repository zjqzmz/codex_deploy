# ChatGPT 批量注册 + CLIProxyAPI — 从零部署指南

## 整体架构

```
新服务器 → setup.sh 一键部署
  ├── 1. 安装依赖 (Python, Node.js, PM2, curl_cffi)
  ├── 2. 配置注册工具 (config.json + 代理)
  ├── 3. 部署 CLIProxyAPI (API 代理服务)
  ├── 4. 首次批量注册 (50个账号 + OAuth Token)
  ├── 5. Token 自动导入 CLIProxyAPI
  └── 6. PM2 定时任务 (每天凌晨自动注册新账号)
```

**工作流**: 注册机批量注册 ChatGPT 账号 → 获取 OAuth Token → 导入 CLIProxyAPI → 对外提供 OpenAI 兼容 API

---

## 一、环境要求

- **系统**: Ubuntu 20.04+ / Debian 11+ (x86_64)
- **Python**: 3.8+
- **Node.js**: 16+（用于 PM2）
- **代理**: 海外住宅代理（**必须**，否则 IP 会被封）
- **端口**: 8317（CLIProxyAPI 默认端口，需开放）

---

## 二、一键部署（推荐）

### 准备工作

1. 将代码上传到服务器：
```bash
scp -r codex_token_get/ root@服务器IP:/root/
scp -r cliproxy/ root@服务器IP:/root/
```

2. 确保 `cliproxy/cli-proxy-api` 二进制文件和 `codex_token_get/chatgpt_register.py` 已在对应目录。

### 一条命令完整部署

```bash
cd /root/codex_token_get

bash setup.sh \
  --proxy 'http://用户名:密码@代理地址:端口' \
  --cliproxy-key 'sk-your-api-key' \
  --cliproxy-mgmt 'your-mgmt-password' \
  --count 50
```

**执行完毕后自动完成**：
- 安装所有依赖
- 配置注册工具 + 代理
- 部署 CLIProxyAPI 并启动
- 批量注册 50 个账号
- 将 Token 导入 CLIProxyAPI
- 设置每天凌晨 2 点自动注册

### 完整参数列表

```bash
bash setup.sh [选项]
```

**注册相关：**

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--proxy` | 住宅代理地址 | 空 |
| `--proxy-api` | 代理提取 API | 空 |
| `--count` | 每次注册数量 | 50 |
| `--cron` | 定时任务表达式 | `0 2 * * *` |
| `--dir` | 注册工具目录 | `/root/codex_token_get` |
| `--skip-register` | 跳过首次注册 | false |

**CLIProxy 相关：**

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--cliproxy-dir` | CLIProxy 安装目录 | `/root/cliproxy` |
| `--cliproxy-port` | 服务端口 | 8317 |
| `--cliproxy-key` | API Key | `sk-your-api-key` |
| `--cliproxy-mgmt` | 管理面板密码 | 空（禁用） |
| `--cliproxy-url` | 下载 URL | 空（用本地文件） |
| `--token-dest` | Token 目录 | `~/.cli-proxy-api` |
| `--skip-cliproxy` | 跳过 CLIProxy | false |

### 示例

```bash
# 完整部署（推荐）
bash setup.sh \
  --proxy 'http://customer-xxx-cc-US:密码@gate.ipfoxy.io:58688' \
  --cliproxy-key 'sk-mykey-123' \
  --count 50

# 仅部署注册工具，不装 CLIProxy
bash setup.sh --proxy 'http://...' --skip-cliproxy

# 仅部署，不立即注册（先检查配置）
bash setup.sh --proxy 'http://...' --skip-register

# 使用代理 API
bash setup.sh --proxy-api 'http://api.iproyal.com/v1/rotating?apiKey=xxx'
```

---

## 三、手动部署（逐步操作）

### Step 1: 安装系统依赖

```bash
apt-get update
apt-get install -y python3 python3-pip curl nodejs npm
npm install -g pm2
pip3 install curl_cffi
```

### Step 2: 配置注册工具

```bash
cd /root/codex_token_get
vim config.json
```

关键配置项：
```json
{
  "total_accounts": 50,
  "proxy": "http://用户名:密码@代理地址:端口",
  "enable_oauth": true,
  "oauth_required": true
}
```

### Step 3: 测试注册 1 个账号

```bash
# 先改 total_accounts 为 1
cd /root/codex_token_get
python3 chatgpt_register.py
```

确认输出 `[OK] xxx@duckmail.sbs 注册成功!` 后继续。

### Step 4: 部署 CLIProxyAPI

```bash
# 创建目录
mkdir -p /root/cliproxy

# 将 cli-proxy-api 二进制文件和 config.yaml 放到目录
# (从 GitHub Releases 下载或从其他服务器复制)

# 创建 Token 目录
mkdir -p ~/.cli-proxy-api

# 编辑 CLIProxy 配置
vim /root/cliproxy/config.yaml
```

关键配置项：
```yaml
port: 8317
auth-dir: "~/.cli-proxy-api"
api-keys:
  - "sk-your-api-key"
remote-management:
  allow-remote: true
  secret-key: "your-mgmt-password"
```

### Step 5: 启动 CLIProxy

```bash
pm2 start /root/cliproxy/cli-proxy-api --name "cliproxy" --cwd /root/cliproxy
```

### Step 6: 批量注册并导入 Token

```bash
# 批量注册
cd /root/codex_token_get
python3 chatgpt_register.py

# 将 Token 复制到 CLIProxy
cp -f codex_tokens/*.json ~/.cli-proxy-api/
# CLIProxy 会自动热加载，无需重启
```

### Step 7: 设置每日定时注册

```bash
pm2 start /root/codex_token_get/daily_register.sh \
  --name "codex-daily-register" \
  --interpreter bash \
  --cron-restart "0 2 * * *" \
  --no-autorestart \
  --output /root/codex_token_get/pm2_daily.out.log \
  --error /root/codex_token_get/pm2_daily.err.log

# 保存 + 开机自启
pm2 save
pm2 startup
```

---

## 四、代理配置

### 三种代理模式（优先级从高到低）

**模式一：旋转网关（最推荐）**
```json
"proxy": "http://customer-xxx-cc-US:密码@gate.ipfoxy.io:58688"
```
一个固定入口，代理商自动换 IP。

**模式二：代理 API**
```json
"proxy_api": "http://api.iproyal.com/v1/rotating?apiKey=KEY"
```
每次注册从 API 获取新 IP。

**模式三：静态代理池**
```json
"proxy_pool": [
  "socks5://user:pass@1.2.3.4:1080",
  "http://user:pass@5.6.7.8:8080"
]
```

### 代理购买建议

| 服务商 | 价格 | 特点 |
|--------|------|------|
| **IPFoxy** | ¥3-5/GB | 中文界面，旋转网关 |
| **IPRoyal** | ~$1.75/GB | 便宜，API 提取 |
| **Webshare** | 免费起 | 有免费额度可测试 |
| **SmartProxy** | ~$4/GB | 稳定 |

**要点**：选**住宅代理**（Residential）+ **美国/欧洲节点**

---

## 五、验证部署

```bash
# 1. 检查所有进程状态
pm2 list

# 2. 检查注册结果
grep -c 'oauth=ok' /root/codex_token_get/registered_accounts.txt

# 3. 检查 Token 数量
ls ~/.cli-proxy-api/*.json | wc -l

# 4. 测试 CLIProxy API
curl http://localhost:8317/v1/models \
  -H "Authorization: Bearer sk-your-api-key"

# 5. 查看注册日志
pm2 logs codex-daily-register --lines 30

# 6. 查看 CLIProxy 日志
pm2 logs cliproxy --lines 30
```

---

## 六、日常运维

### 常用命令速查

```bash
# === 注册相关 ===
pm2 restart codex-daily-register     # 手动触发一次注册
pm2 logs codex-daily-register        # 查看注册日志
vim /root/codex_token_get/config.json # 修改注册配置

# === CLIProxy 相关 ===
pm2 restart cliproxy                 # 重启 CLIProxy
pm2 logs cliproxy                    # 查看代理日志
vim /root/cliproxy/config.yaml       # 修改代理配置

# === 统计 ===
grep -c 'oauth=ok' /root/codex_token_get/registered_accounts.txt  # 成功数
ls ~/.cli-proxy-api/*.json | wc -l   # Token 数
wc -l /root/codex_token_get/ak.txt   # AK 数
```

### 输出文件说明

| 文件 | 说明 |
|------|------|
| `registered_accounts.txt` | 邮箱----密码----邮箱密码----oauth状态 |
| `ak.txt` | Access Token（每行一个） |
| `rk.txt` | Refresh Token（每行一个） |
| `codex_tokens/*.json` | 每个账号完整 Token |
| `~/.cli-proxy-api/*.json` | CLIProxy 使用的 Token 副本 |

### 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| 403 Forbidden | IP 被封 | 配置住宅代理 |
| SSL WRONG_VERSION_NUMBER | DuckMail 走了代理 | 代码已修复，DuckMail 直连 |
| DuckMail 500 | 邮箱服务偶发故障 | 自动重试，忽略 |
| OAuth 获取失败 | Session 过期 | 已内建重试 |
| CLIProxy 无 Token | Token 未复制 | `cp codex_tokens/*.json ~/.cli-proxy-api/` |
| CLIProxy 401 | API Key 错 | 检查 config.yaml 的 api-keys |
