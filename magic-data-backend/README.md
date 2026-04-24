# Magic CLI 数据后台（简化版）

为 Magic CLI 编程助手提供“修复摘要”和“Agent Chat Round”两类数据的轻量级后端服务。支持 JSON API 与人类可读的 HTML 页面。

## 🎯 特点

- 极简部署：单文件服务器，一键启动
- 零配置：SQLite 本地数据库
- 低资源：极少依赖，开发/测试友好
- 双入口：`/api/...` 提供 JSON，网页路由提供 HTML 视图

## 🚀 快速开始

### 方式 1：直接运行（推荐搭配 UV）

```bash
# 安装依赖（建议使用 UV，详见 README_UV.md）
uv sync

# 启动服务器
uv run python simple_server.py

# 健康检查
curl -s http://localhost:8000/health | jq
```

### 方式 2：Docker

```bash
# 构建镜像
docker build -t magic-data-backend .

# 运行容器
docker run --rm -p 8000:8000 -v $(pwd)/data:/app/data magic-data-backend

# 健康检查
curl -s http://localhost:8000/health | jq
```

## 📚 数据模型

- Fix Summary
  - 字段：`id`, `content`, `timestamp`
- Agent Chat Round
  - 字段：`id`, `query`, `answer`, `steps`(JSON 数组), `timestamp`

## 🔌 API（JSON）

- Fix Summary
  - POST `/api/fix-summary`
    - 请求：`{"content": "..."}`
    - 响应：`{"summary_id": "uuid", "status": "created"}`
  - GET `/api/fix-summary/{summary_id}`
    - 响应：`{"id": "uuid", "content": "...", "timestamp": "..."}`
  - GET `/api/fix-summary?limit=50&offset=0`
    - 响应：`{"summaries": [...], "limit": 50, "offset": 0}`

- Agent Chat Round
  - POST `/api/agent-chat-round`
    - 请求：`{"question": {Message}, "answer": {Message}, "steps": [Message, ...]}`
    - 响应：`{"chat_round_id": "uuid", "status": "logged"}`
  - GET `/api/agent-chat-round/{chat_round_id}`
    - 响应：`{"id", "query", "answer", "steps", "timestamp"}`
  - GET `/api/agent-chat-round?limit=50&offset=0`
    - 响应：`{"chat_rounds": [...], "limit": 50, "offset": 0}`

Message 对象示例：
```json
{
  "role": "user",
  "content": "How to optimize this function?",
  "image": null,
  "reason": null
}
```

快速验证（示例）：
```bash
# 创建 Fix Summary
curl -s -X POST http://localhost:8000/api/fix-summary \
  -H 'Content-Type: application/json' \
  -d '{"content":"fixed type mismatch"}' | jq

# 创建 Agent Chat Round（使用 steps）
curl -s -X POST http://localhost:8000/api/agent-chat-round \
  -H 'Content-Type: application/json' \
  -d '{
    "question": {"role":"user","content":"Hi"},
    "answer": {"role":"assistant","content":"Hello"},
    "steps": [
      {"role":"user","content":"Hi"},
      {"role":"assistant","content":"Hello"}
    ]
  }' | jq

# 列表
curl -s "http://localhost:8000/api/agent-chat-round?limit=10&offset=0" | jq
```

## 🖥️ 网页页面（HTML）

- 首页 Dashboard：`/`
- Fix Summaries 列表：`/fix-summaries`
- Fix Summary 详情：`/fix-summary/{id}`
- Agent Chat Rounds 列表：`/agent-chat-rounds`
- Agent Chat Round 详情：`/agent-chat-rounds/{id}`
- API 文档（HTML）：`/api`

## 🗂️ 数据库（SQLite）

数据库文件默认位于 `cj_data.db`（可通过环境变量 `DB_PATH` 修改）。

常用查询：
```sql
-- Fix Summaries
SELECT id, content, timestamp
FROM fix_summaries
ORDER BY timestamp DESC
LIMIT 20;

-- Agent Chat Rounds
SELECT id, query, answer, steps, timestamp
FROM agent_chat_rounds
ORDER BY timestamp DESC
LIMIT 20;
```

索引：
```sql
CREATE INDEX IF NOT EXISTS idx_fix_summaries_timestamp ON fix_summaries(timestamp);
CREATE INDEX IF NOT EXISTS idx_agent_chat_rounds_timestamp ON agent_chat_rounds(timestamp);
```

## 🔧 配置

- `DB_PATH`: SQLite 数据库路径（默认 `cj_data.db`）
- `HOST`: 监听地址（默认 `0.0.0.0`）
- `PORT`: 端口（默认 `8000`）

## 🔍 监控与调试

```bash
curl http://localhost:8000/health
```

访问 `http://localhost:8000` 查看 Dashboard 与文档。

## 🛡️ 提示

- 本项目为开发/测试用途的简化服务，如需生产使用请添加鉴权、限流与备份策略。

## 📄 许可证

MIT License
