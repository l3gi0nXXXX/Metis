FROM python:3.13-slim

WORKDIR /app

ENV UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

# 安装uv
RUN pip install -i $UV_INDEX_URL uv

# 复制依赖文件
COPY pyproject.toml uv.lock ./

# 安装依赖
RUN uv sync --frozen --no-dev

# 复制代码与资源
COPY simple_server.py .
COPY templates ./templates
COPY static ./static

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
