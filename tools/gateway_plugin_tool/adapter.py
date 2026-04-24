#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""开发时入口：转发到 runtime/adapter.py（安装工具会复制整个 runtime/ 到插件目录）。"""

from __future__ import annotations

import pathlib
import runpy
import sys

if __name__ == "__main__":
    rt = pathlib.Path(__file__).resolve().parent / "runtime" / "adapter.py"
    if not rt.is_file():
        sys.stderr.write(f"missing {rt}\n")
        raise SystemExit(1)
    runpy.run_path(str(rt), run_name="__main__")
