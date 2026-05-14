#!/usr/bin/env python3
"""Generate the Feishu OAPI action parity matrix for AgentTeam series13.

The report is intentionally source-backed: it reads OpenClaw-Lark's
ToolActionKey/TOOL_SCOPES and Metis' OAPI action registry instead of using a
hand-maintained list.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
from pathlib import Path


DEFAULT_OPENCLAW_ROOT = Path("/Users/l3gi0n/work/workspace_cangjie/openclaw-lark")
DEFAULT_OUTPUT = Path(
    "develop_steps/metis-agent-team-series-13-oapi-action-parity-report-2026-05-15.md"
)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def line_number(text: str, needle: str) -> int:
    index = text.find(needle)
    if index < 0:
        return 0
    return text.count("\n", 0, index) + 1


def extract_openclaw_actions(text: str) -> list[str]:
    match = re.search(r"^export\s+type\s+ToolActionKey\s*=\s*(.*?);", text, re.M | re.S)
    if not match:
        raise RuntimeError("Unable to locate OpenClaw ToolActionKey union")
    return re.findall(r"'([^']+)'", match.group(1))


def extract_openclaw_scopes(text: str) -> dict[str, list[str]]:
    scopes: dict[str, list[str]] = {}
    match = re.search(r"export\s+const\s+TOOL_SCOPES.*?=\s*\{(.*?)\}\s+as\s+const", text, re.S)
    if not match:
        raise RuntimeError("Unable to locate OpenClaw TOOL_SCOPES")
    block = match.group(1)
    for item in re.finditer(r"'([^']+)'\s*:\s*\[(.*?)\]", block, re.S):
        key = item.group(1)
        scopes[key] = re.findall(r"'([^']+)'", item.group(2))
    return scopes


def extract_metis_openclaw_keys(text: str) -> list[str]:
    match = re.search(r"public\s+func\s+feishuOapiOpenClawActionKeys\(\).*?\[(.*?)\]\s*\n\}", text, re.S)
    if not match:
        raise RuntimeError("Unable to locate Metis feishuOapiOpenClawActionKeys")
    return re.findall(r'"([^"]+)"', match.group(1))


def extract_cangjie_string_cases(text: str, function_name: str) -> dict[str, str]:
    block = extract_cangjie_function_body(text, function_name)
    return {m.group(1): m.group(2) for m in re.finditer(r'case\s+"([^"]+)"\s*=>\s*"([^"]*)"', block)}


def extract_cangjie_scope_cases(text: str, function_name: str) -> dict[str, list[str]]:
    block = extract_cangjie_function_body(text, function_name)
    scopes: dict[str, list[str]] = {}
    for item in re.finditer(r'case\s+"([^"]+)"\s*=>\s*\[(.*?)\]', block, re.S):
        scopes[item.group(1)] = re.findall(r'"([^"]+)"', item.group(2))
    return scopes


def extract_cangjie_function_body(text: str, function_name: str) -> str:
    match = re.search(rf"\bfunc\s+{re.escape(function_name)}\s*\(", text)
    if not match:
        raise RuntimeError(f"Unable to locate function {function_name}")
    start = match.start()
    brace = text.find("{", start)
    if brace < 0:
        raise RuntimeError(f"Unable to locate body for function {function_name}")
    depth = 0
    for pos in range(brace, len(text)):
        if text[pos] == "{":
            depth += 1
        elif text[pos] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1 : pos]
    raise RuntimeError(f"Unterminated function body for {function_name}")


def metis_method_for(action_key: str, explicit: dict[str, str]) -> str:
    if action_key in explicit:
        return explicit[action_key]
    action = action_key.split(".", 1)[1]
    if action in {
        "create",
        "batch_create",
        "register",
        "add_members",
        "append_steps",
        "copy",
        "reply",
        "upload",
        "export",
    }:
        return "POST"
    if action in {"patch", "update", "update_profile", "batch_update"}:
        return "PATCH"
    if action in {"delete", "batch_delete"}:
        return "DELETE"
    return "GET"


def metis_token_mode_for(action_key: str, explicit: dict[str, str]) -> str:
    return explicit.get(action_key, "user_access_token")


def metis_scopes_for(action_key: str, explicit: dict[str, list[str]]) -> list[str]:
    if action_key in explicit:
        return explicit[action_key]
    if action_key.startswith("feishu_bitable_app_table_field."):
        if action_key == "feishu_bitable_app_table_field.create":
            return ["base:field:create"]
        if action_key == "feishu_bitable_app_table_field.list":
            return ["base:field:read"]
        if action_key == "feishu_bitable_app_table_field.update":
            return ["base:field:read", "base:field:update"]
        if action_key == "feishu_bitable_app_table_field.delete":
            return ["base:field:delete"]
        return []
    if action_key.startswith("feishu_bitable_"):
        if ".list" in action_key:
            return ["space:document:retrieve"]
        if ".create" in action_key or ".batch_create" in action_key:
            return ["base:app:create"]
        if ".patch" in action_key or ".update" in action_key or ".batch_update" in action_key:
            return ["base:app:update"]
        if ".delete" in action_key or ".batch_delete" in action_key:
            return ["base:record:delete"]
        return ["base:app:read"]
    if action_key.startswith("feishu_calendar_event."):
        if action_key.endswith(".create"):
            return ["calendar:calendar.event:create", "calendar:calendar.event:update"]
        if action_key.endswith(".patch"):
            return ["calendar:calendar.event:update"]
        if action_key.endswith(".delete"):
            return ["calendar:calendar.event:delete"]
        if action_key.endswith(".reply"):
            return ["calendar:calendar.event:reply"]
        return ["calendar:calendar.event:read"]
    if action_key.startswith("feishu_calendar_"):
        if action_key == "feishu_calendar_freebusy.list":
            return ["calendar:calendar.free_busy:read"]
        return ["calendar:calendar:read"]
    if action_key.startswith("feishu_task_"):
        if any(
            part in action_key
            for part in [".create", ".patch", ".add_members", ".append_steps", ".register", ".update_profile"]
        ):
            return ["task:task:write"]
        return ["task:task:read", "task:task:write"]
    return []


def format_list(values: list[str]) -> str:
    if not values:
        return "[]"
    return "`" + "`, `".join(values) + "`"


def status_for(
    action: str,
    metis_keys: set[str],
    metis_paths: dict[str, str],
    openclaw_scopes: list[str],
    metis_scopes: list[str],
) -> str:
    if action not in metis_keys or not metis_paths.get(action, ""):
        return "missing"
    if openclaw_scopes == metis_scopes:
        return "aligned"
    return "partial"


def row_gap(status: str, openclaw_scopes: list[str], metis_scopes: list[str]) -> str:
    if status == "aligned":
        return "No action-level gap; Metis exposes path/method/scopes/tokenMode through the generic OAPI envelope."
    if status == "missing":
        return "Metis does not expose this OpenClaw-Lark action key."
    return f"Required scope matrix differs. OpenClaw: {format_list(openclaw_scopes)}; Metis: {format_list(metis_scopes)}."


def row_task(status: str) -> str:
    if status == "aligned":
        return "Keep fake HTTP coverage and report generation in CI/manual gate."
    if status == "missing":
        return "Add action key, path, method, required scopes, tokenMode row, and fake HTTP test."
    return "Decide whether Metis should match OpenClaw scopes exactly; if yes, update scope row and fake tests."


def row_acceptance(status: str) -> str:
    if status == "aligned":
        return "`cjpm test -i src/gateway/tools --filter GatewayFeishuOapiToolsetTest`; regenerate this report."
    if status == "missing":
        return "New action returns non-empty path/method/scopes, never hits real Feishu in tests, and appears as aligned/partial in regenerated report."
    return "Focused test asserts the exact required scope list and no token/secret appears in JSON output."


def generate(args: argparse.Namespace) -> str:
    openclaw_scope_path = args.openclaw_root / "src/core/tool-scopes.ts"
    metis_client_path = args.metis_root / "src/gateway/tools/gateway_feishu_oapi_client.cj"
    openclaw_text = read_text(openclaw_scope_path)
    metis_text = read_text(metis_client_path)

    openclaw_actions = extract_openclaw_actions(openclaw_text)
    openclaw_scopes = extract_openclaw_scopes(openclaw_text)
    metis_actions = extract_metis_openclaw_keys(metis_text)
    metis_action_set = set(metis_actions)
    metis_paths = extract_cangjie_string_cases(metis_text, "feishuOapiPathForActionKey")
    metis_methods = extract_cangjie_string_cases(metis_text, "feishuOapiMethodForActionKey")
    metis_token_modes = extract_cangjie_string_cases(metis_text, "feishuOapiTokenModeForActionKey")
    metis_scope_cases = extract_cangjie_scope_cases(metis_text, "feishuOapiRequiredScopesForActionKey")

    rows: list[dict[str, str]] = []
    counts = {"aligned": 0, "partial": 0, "missing": 0, "not-applicable": 0}
    for action in openclaw_actions:
        oc_scopes = openclaw_scopes.get(action, [])
        mt_scopes = metis_scopes_for(action, metis_scope_cases)
        status = status_for(action, metis_action_set, metis_paths, oc_scopes, mt_scopes)
        counts[status] += 1
        oc_line = line_number(openclaw_text, f"'{action}'")
        mt_action_line = line_number(metis_text, f'"{action}"')
        mt_path_line = line_number(metis_text, f'case "{action}" => "{metis_paths.get(action, "")}"')
        token_line = line_number(metis_text, f'case "{action}" => "{metis_token_modes.get(action, "")}"')
        if token_line == 0:
            token_line = line_number(metis_text, 'case _ => "user_access_token"')
        token_mode = metis_token_mode_for(action, metis_token_modes)
        rows.append(
            {
                "action": action,
                "status": status,
                "openclaw": f"`src/core/tool-scopes.ts:{oc_line}` scopes {format_list(oc_scopes)}",
                "metis": (
                    f"`src/gateway/tools/gateway_feishu_oapi_client.cj:{mt_action_line}` action; "
                    f"`:{mt_path_line}` path; `:{token_line}` tokenMode `{token_mode}`"
                ),
                "gap": row_gap(status, oc_scopes, mt_scopes),
                "task": row_task(status),
                "acceptance": row_acceptance(status),
            }
        )

    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines = [
        "# Metis AgentTeam Series13 Feishu OAPI Action Parity Report",
        "",
        f"Generated: {now}",
        "",
        "Source inputs:",
        f"- OpenClaw-Lark: `{openclaw_scope_path}`",
        f"- Metis: `{metis_client_path}`",
        "",
        "Notes:",
        f"- OpenClaw-Lark source currently enumerates {len(openclaw_actions)} `ToolActionKey` rows. "
        "The older source comment still says 96; this report follows the actual union, not the comment.",
        "- Status values are restricted to `aligned`, `partial`, `missing`, and `not-applicable`.",
        "- Metis OAPI tools use a generic `params_json` envelope, so aligned here means action-level path/method/scope/tokenMode parity, not a full per-action parameter transformer clone.",
        "",
        "Summary:",
        f"- aligned: {counts['aligned']}",
        f"- partial: {counts['partial']}",
        f"- missing: {counts['missing']}",
        f"- not-applicable: {counts['not-applicable']}",
        "",
        "| Action | Status | OpenClaw source evidence | Metis source evidence | Functional gap | Implementation task | Acceptance/tests |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            "| {action} | {status} | {openclaw} | {metis} | {gap} | {task} | {acceptance} |".format(
                **row
            )
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--openclaw-root", type=Path, default=DEFAULT_OPENCLAW_ROOT)
    parser.add_argument("--metis-root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    report = generate(args)
    output = args.output
    if not output.is_absolute():
        output = args.metis_root / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(report, encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
