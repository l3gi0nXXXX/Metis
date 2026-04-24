#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import importlib.util

module_path = Path("tools/gateway_plugin_tool/install.py").resolve()
spec = importlib.util.spec_from_file_location("gateway_plugin_install", module_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

state_root = Path("/tmp/metis-plugin-state")
expected = state_root / ".metis" / "gateway-plugins" / "demo"
actual = module.plugin_root(state_root, "demo")
assert actual == expected, f"plugin_root mismatch: {actual} != {expected}"

help_text = module.build_parser().format_help()
assert ".metis/gateway-plugins" in help_text, help_text
assert ".magic-cli/gateway-plugins" not in help_text, help_text

print("Gateway plugin tool path configuration OK.")
PY
