#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  status)
    cat <<'EOF'
QMD status
Vectors: 42
Collections: 3
EOF
    ;;
  update)
    echo "updated"
    ;;
  embed)
    echo "embedded"
    ;;
  search|query|vsearch)
    query=""
    limit="6"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json)
          shift
          ;;
        --limit)
          limit="${2:-6}"
          shift 2
          ;;
        *)
          if [ -z "$query" ]; then
            query="$1"
          fi
          shift
          ;;
      esac
    done
    cat <<EOF
[
  {
    "path": "qmd/mock-memory.md",
    "start_line": 3,
    "end_line": 5,
    "snippet": "QMD mock hit for query: ${query} (limit=${limit})"
  }
]
EOF
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 1
    ;;
esac
