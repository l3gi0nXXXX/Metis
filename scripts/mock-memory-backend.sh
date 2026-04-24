#!/usr/bin/env bash
set -euo pipefail

query=""
limit="6"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      query="${2:-}"
      shift 2
      ;;
    --limit)
      limit="${2:-6}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$query" ]]; then
  printf '{"results":[],"backend":"mock-external","status":"ok"}\n'
  exit 0
fi

cat <<EOF
{
  "status": "ok",
  "backend": "mock-external",
  "results": [
    {
      "path": "external-memory/mock.md",
      "startLine": 1,
      "endLine": 2,
      "text": "1: External memory hit for query: ${query}\n2: limit=${limit}"
    }
  ]
}
EOF
