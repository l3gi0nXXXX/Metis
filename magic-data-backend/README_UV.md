# 使用UV管理CJ数据服务器

## 🚀 UV快速开始

### 1. 安装UV

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell)
powershell -c "irm https://astral.sh/uv/install.sh | iex"

# 或者使用pip
pip install uv
```

### 2. 创建项目环境

```bash
cd cj-data

# 创建虚拟环境并安装依赖
uv sync

# 或者安装开发依赖
uv sync --dev
```

### 3. 运行服务器

```bash
# 使用uv运行服务器
uv run simple_server.py

# 或者激活虚拟环境后运行
uv shell
python simple_server.py
```

## 📦 UV命令参考

### 环境管理

```bash
# 创建虚拟环境
uv venv

# 激活虚拟环境
uv shell

# 在虚拟环境中运行命令
uv run python simple_server.py

# 删除虚拟环境
uv venv --remove
```

### 依赖管理

```bash
# 安装所有依赖
uv sync

# 安装开发依赖
uv sync --dev

# 添加新依赖
uv add fastapi uvicorn requests pydantic

# 添加开发依赖
uv add --dev pytest black mypy

# 移除依赖
uv remove requests

# 更新依赖
uv update

# 锁定依赖版本
uv lock
```

### 项目管理

```bash
# 运行测试
uv run pytest

# 代码格式化
uv run black .

# 代码检查
uv run flake8 .

# 类型检查
uv run mypy .
```

## 🐳 Docker与UV

### 更新Dockerfile使用UV

```dockerfile
FROM python:3.13-slim

WORKDIR /app

# 安装uv
RUN pip install uv

# 复制依赖文件
COPY pyproject.toml uv.lock ./

# 安装依赖
RUN uv sync --frozen

# 复制代码
COPY simple_server.py .

# 创建数据目录
RUN mkdir -p /app/data

# 设置环境变量
ENV DB_PATH=/app/data/cj_data.db

# 暴露端口
EXPOSE 8000

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# 运行服务器
CMD ["uv", "run", "simple_server.py"]
```

## 🔧 开发工作流

### 1. 设置开发环境

```bash
# 克隆项目
git clone <your-repo>
cd cj-data

# 安装uv（如果还没有安装）
curl -LsSf https://astral.sh/uv/install.sh | sh

# 创建环境并安装依赖
uv sync --dev

# 激活虚拟环境
uv shell
```

### 2. 开发和测试

```bash
# 运行服务器
uv run python simple_server.py

# 运行测试
uv run pytest

# 代码格式化
uv run black simple_server.py

# 代码检查
uv run flake8 simple_server.py

# 类型检查
uv run mypy simple_server.py
```

### 3. 快速验证

```bash
# 启动服务器
uv run python simple_server.py

# 在新终端验证API
curl -s http://localhost:8000/health | jq
curl -s -X POST http://localhost:8000/api/fix-summary \
  -H 'Content-Type: application/json' \
  -d '{"content":"hello from uv"}' | jq
```

## 📊 性能优化

### UV的性能优势

- **快速依赖解析**: 比pip快10-100倍
- **智能缓存**: 避免重复下载
- **并发安装**: 同时安装多个包
- **磁盘空间优化**: 共享依赖包

### 开发体验提升

```bash
# 查看依赖树
uv tree

# 查看过时的依赖
uv outdated

# 清理缓存
uv cache clean

# 查看环境信息
uv pip list
```

## 🚀 部署建议

### 生产环境使用UV

```bash
# 创建生产环境
uv sync --no-dev

# 运行生产服务器
uv run uvicorn simple_server:app --host 0.0.0.0 --port 8000
```

### Docker最佳实践

```dockerfile
# 多阶段构建
FROM python:3.13-slim as builder
RUN pip install uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

FROM python:3.13-slim
RUN pip install uv
COPY --from=builder /app/.venv /app/.venv
COPY simple_server.py .
ENV PATH="/app/.venv/bin:$PATH"
CMD ["uv", "run", "simple_server.py"]
```

## 🤝 升级现有项目

如果您已经有一个现有的Python项目，可以很容易地迁移到UV：

```bash
# 1. 安装uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# 2. 从requirements.txt生成pyproject.toml
uv init

# 3. 添加依赖
uv add fastapi uvicorn requests pydantic

# 4. 移除旧的requirements.txt
rm requirements.txt

# 5. 安装依赖
uv sync
```

现在您可以使用UV来管理这个轻量化数据服务器项目了！UV会比传统的pip工作流更快、更高效。
