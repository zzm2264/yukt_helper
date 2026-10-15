# 雨课堂云端同步与 AI 答题服务端 (Backend Server)

本项目为配套 Flutter 客户端的独立云端服务，提供：
1. **多租户账号云端同步**：基于 API Key / Group Key 实现各学生群组的数据隔离、凭证加密备份与秒级多设备分发。
2. **AI 随堂智能答题网关**：内置支持 OpenAI 兼容格式大模型（如 DeepSeek、OpenAI、Qwen），并具备优雅离线降级与规则兜底能力。
3. **高并发与数据高可用**：采用轻量级原子化落盘（`safe_json_store.py`），杜绝并发写入损坏文件；集成 `waitress` 生产级 WSGI 多线程服务器。

---

## 快速开始

### 1. 环境准备
- Python 3.10 或更高版本
- pip 包管理器

### 2. 安装依赖
```bash
cd server
pip install -r requirements.txt
```

### 3. 配置环境变量
复制配置模板为 `.env`（或直接通过系统环境变量导出）：
```bash
cp .env.example .env
```
主要配置项说明：
```env
# 管理员全局操作密钥（强烈建议修改）
YKT_ADMIN_KEY=your_secure_admin_key_here

# 监听端口
YKT_BIND_HOST=0.0.0.0
YKT_PORT=5000

# (可选) AI 答题模型配置，如使用 DeepSeek:
YKT_AI_API_KEY=sk-xxxxxx
YKT_AI_BASE_URL=https://api.deepseek.com/v1
YKT_AI_MODEL=deepseek-chat
```

### 4. 启动服务
```bash
python api_server.py
```
启动成功后将显示：
```text
[INFO] 雨课堂同步 API 2.6.1 启动：http://0.0.0.0:5000
```

---

## 生产环境部署建议 (Linux Systemd 托管)

在 Linux 服务器（如 Ubuntu / Debian / CentOS）上，建议使用 `systemd` 守护进程进行托管：

1. 创建服务文件 `/etc/systemd/system/ykt-server.service`：
```ini
[Unit]
Description=Rain Classroom Cloud Sync & AI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/course_helper/server
EnvironmentFile=/opt/course_helper/server/.env
ExecStart=/usr/bin/python3 api_server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

2. 启动并启用开机自启：
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ykt-server
sudo systemctl status ykt-server
```

---

## 核心 API 概览

| 路由 | 请求方法 | 认证要求 | 说明 |
| :--- | :--- | :--- | :--- |
| `/api/status` | GET | 无 | 服务运行状态探测及版本查询 |
| `/api/sync/profile` | GET | `Authorization: <Key>` | 校验用户密钥有效性与返回组备注 |
| `/api/sync/download`| GET | `Authorization: <Key>` | 拉取该密钥名下绑定的所有账号与 Cookie |
| `/api/sync/upload`  | POST | `Authorization: <Key>` | 批量上传/备份本地账号凭证至云端 |
| `/api/ai/solve`     | POST | `Authorization: <Key>` | 提交题目由大模型解析生成标准选项 |
| `/api/sync/keys`    | GET | `Authorization: <ADMIN>`| 管理员查询所有已分发的租户密钥 |
| `/api/sync/create_key`| POST| `Authorization: <ADMIN>`| 管理员生成新的分发密钥 |
