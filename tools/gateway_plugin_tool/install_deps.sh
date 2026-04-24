#!/usr/bin/env bash
# 安装网关插件对应的 Python 依赖（单渠道或全部）
# 用法:
#   ./install_deps.sh
#   ./install_deps.sh dingtalk
#   ./install_deps.sh all

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHANNEL="${1:-all}"
exec python "$SCRIPT_DIR/install.py" deps "$CHANNEL"
