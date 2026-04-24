FROM --platform=linux/amd64 python:3.11-slim AS base

# 📌 1. 删除所有默认源（包括潜在的 /etc/apt/sources.list.d/debian.sources）
RUN rm -rf /etc/apt/sources.list /etc/apt/sources.list.d/*
# 📌 2. 写入清华源（完整覆盖）
RUN echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian bookworm main" > /etc/apt/sources.list \
    && echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main" >> /etc/apt/sources.list \
    && echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian bookworm-updates main" >> /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    bash && \
    rm -rf /var/lib/apt/lists/*

# Provide bundled SDK and CLI (replace with production binaries as needed).
COPY CangjieSDK /opt/CangjieSDK
COPY magic-cli /usr/local/bin/magic-cli
COPY entrypoint.sh /usr/local/bin/magic-entrypoint

RUN chmod +x /usr/local/bin/magic-cli /usr/local/bin/magic-entrypoint \
    && find /opt/CangjieSDK -type f -name "*.sh" -exec chmod +x {} \;

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/magic-entrypoint"]
CMD ["sleep", "infinity"]
