#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

TMP_HOME="$(mktemp -d /tmp/metis-cli.XXXXXX)"

cleanup() {
  local exit_code=$?
  rm -rf "${TMP_HOME}" >/dev/null 2>&1 || true
  return "${exit_code}"
}
trap cleanup EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! printf '%s\n' "$haystack" | rg -F -- "$needle" >/dev/null; then
    echo "missing expected text: $needle" >&2
    exit 1
  fi
}

assert_matches() {
  local haystack="$1"
  local pattern="$2"
  if ! printf '%s\n' "$haystack" | rg "$pattern" >/dev/null; then
    echo "missing expected pattern: $pattern" >&2
    exit 1
  fi
}

run_cli() {
  METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" \
    rtk cjpm run --skip-script --skip-build --name metis --run-args "$*"
}

mkdir -p "$TMP_HOME"
cat >"$TMP_HOME/metis.json" <<'EOF'
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "qwen/qwen3.5-plus"
      }
    }
  },
  "models": {
    "providers": {
      "qwen": {
        "apiKey": "qwen-demo-key",
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1"
      }
    }
  },
  "gateway": {
    "enabled": true,
    "channelsExtra": {
      "telegram": {
        "enabled": true,
        "configured": true,
        "token": "tg-token"
      },
      "slack": {
        "enabled": true,
        "configured": true,
        "botToken": "xoxb-demo"
      },
      "discord": {
        "enabled": true,
        "configured": true,
        "botToken": "discord-demo"
      }
    }
  }
}
EOF

echo "[cli-regression] build"
mkdir -p target build-script-cache/release/metis/bin build-script-cache/release/magic/bin
with_metis_cjpm_build_lock rtk cjpm build -i >/dev/null

echo "[cli-regression] root help"
root_help_out="$(run_cli)"
printf '%s\n' "$root_help_out"
assert_contains "$root_help_out" "Usage:"
assert_contains "$root_help_out" "metis <command> [subcommand] [options]"
assert_contains "$root_help_out" "Commands:"
assert_contains "$root_help_out" "setup"
assert_contains "$root_help_out" "onboard"
assert_contains "$root_help_out" "configure"
assert_contains "$root_help_out" "config ..."
assert_contains "$root_help_out" "backup ..."
assert_contains "$root_help_out" "reset ..."
assert_contains "$root_help_out" "uninstall ..."
assert_contains "$root_help_out" "message ..."
assert_contains "$root_help_out" "status"
assert_contains "$root_help_out" "health"
assert_contains "$root_help_out" "doctor"
assert_contains "$root_help_out" "dashboard"
assert_contains "$root_help_out" "agent"
assert_contains "$root_help_out" "agents ..."
assert_contains "$root_help_out" "mcp ..."
assert_contains "$root_help_out" "tasks ..."
assert_contains "$root_help_out" "models ..."
assert_contains "$root_help_out" "logs ..."
assert_contains "$root_help_out" "docs ..."
assert_contains "$root_help_out" "system ..."
assert_contains "$root_help_out" "approvals ..."
assert_contains "$root_help_out" "sandbox ..."
assert_contains "$root_help_out" "node ..."
assert_contains "$root_help_out" "qa ..."
assert_contains "$root_help_out" "hooks ..."
assert_contains "$root_help_out" "webhooks ..."
assert_contains "$root_help_out" "qr ..."
assert_contains "$root_help_out" "pairing ..."
assert_contains "$root_help_out" "daemon ..."
assert_contains "$root_help_out" "acp ..."
assert_contains "$root_help_out" "nodes ..."
assert_contains "$root_help_out" "devices ..."
assert_contains "$root_help_out" "interactive"
assert_contains "$root_help_out" "gateway ..."
assert_contains "$root_help_out" "Docs: https://docs.metis.ai/cli"

echo "[cli-regression] version"
version_out="$(run_cli --version)"
printf '%s\n' "$version_out"
assert_contains "$version_out" "0.1.5"

echo "[cli-regression] root prompt requires gateway"
root_prompt_fail_out="$(run_cli --prompt hello 2>&1 || true)"
printf '%s\n' "$root_prompt_fail_out"
assert_contains "$root_prompt_fail_out" "Gateway agent failed:"
assert_contains "$root_prompt_fail_out" "Start the gateway with \`metis gateway run\`"

echo "[cli-regression] command help"
setup_help_out="$(run_cli help setup)"
printf '%s\n' "$setup_help_out"
assert_contains "$setup_help_out" "Metis setup"

onboard_help_out="$(run_cli help onboard)"
printf '%s\n' "$onboard_help_out"
assert_contains "$onboard_help_out" "Metis onboard"

configure_help_out="$(run_cli help configure)"
printf '%s\n' "$configure_help_out"
assert_contains "$configure_help_out" "Metis configure"

config_help_out="$(run_cli help config)"
printf '%s\n' "$config_help_out"
assert_contains "$config_help_out" "Metis config"

backup_help_out="$(run_cli help backup)"
printf '%s\n' "$backup_help_out"
assert_contains "$backup_help_out" "Metis backup"

reset_help_out="$(run_cli help reset)"
printf '%s\n' "$reset_help_out"
assert_contains "$reset_help_out" "Metis reset"

uninstall_help_out="$(run_cli help uninstall)"
printf '%s\n' "$uninstall_help_out"
assert_contains "$uninstall_help_out" "Metis uninstall"

message_help_out="$(run_cli help message)"
printf '%s\n' "$message_help_out"
assert_contains "$message_help_out" "Metis message"

status_help_out="$(run_cli help status)"
printf '%s\n' "$status_help_out"
assert_contains "$status_help_out" "Metis status"

health_help_out="$(run_cli help health)"
printf '%s\n' "$health_help_out"
assert_contains "$health_help_out" "Metis health"

doctor_help_out="$(run_cli help doctor)"
printf '%s\n' "$doctor_help_out"
assert_contains "$doctor_help_out" "Metis doctor"

dashboard_help_out="$(run_cli help dashboard)"
printf '%s\n' "$dashboard_help_out"
assert_contains "$dashboard_help_out" "Metis dashboard"

agent_help_out="$(run_cli help agent)"
printf '%s\n' "$agent_help_out"
assert_contains "$agent_help_out" "Metis agent"

agents_help_out="$(run_cli help agents)"
printf '%s\n' "$agents_help_out"
assert_contains "$agents_help_out" "Metis agents"

mcp_help_out="$(run_cli help mcp)"
printf '%s\n' "$mcp_help_out"
assert_contains "$mcp_help_out" "Metis mcp"

tasks_help_out="$(run_cli help tasks)"
printf '%s\n' "$tasks_help_out"
assert_contains "$tasks_help_out" "Metis tasks"

models_help_out="$(run_cli help models)"
printf '%s\n' "$models_help_out"
assert_contains "$models_help_out" "Metis models"

logs_help_out="$(run_cli help logs)"
printf '%s\n' "$logs_help_out"
assert_contains "$logs_help_out" "Metis logs"

docs_help_out="$(run_cli help docs)"
printf '%s\n' "$docs_help_out"
assert_contains "$docs_help_out" "Metis docs"

system_help_out="$(run_cli help system)"
printf '%s\n' "$system_help_out"
assert_contains "$system_help_out" "Metis system"

approvals_help_out="$(run_cli help approvals)"
printf '%s\n' "$approvals_help_out"
assert_contains "$approvals_help_out" "Metis approvals"

sandbox_help_out="$(run_cli help sandbox)"
printf '%s\n' "$sandbox_help_out"
assert_contains "$sandbox_help_out" "Metis sandbox"

node_help_out="$(run_cli help node)"
printf '%s\n' "$node_help_out"
assert_contains "$node_help_out" "Metis node"

qa_help_out="$(run_cli help qa)"
printf '%s\n' "$qa_help_out"
assert_contains "$qa_help_out" "Metis qa"

hooks_help_out="$(run_cli help hooks)"
printf '%s\n' "$hooks_help_out"
assert_contains "$hooks_help_out" "Metis hooks"

webhooks_help_out="$(run_cli help webhooks)"
printf '%s\n' "$webhooks_help_out"
assert_contains "$webhooks_help_out" "Metis webhooks"

qr_help_out="$(run_cli help qr)"
printf '%s\n' "$qr_help_out"
assert_contains "$qr_help_out" "Metis qr"

pairing_help_out="$(run_cli help pairing)"
printf '%s\n' "$pairing_help_out"
assert_contains "$pairing_help_out" "Metis pairing"

daemon_help_out="$(run_cli help daemon)"
printf '%s\n' "$daemon_help_out"
assert_contains "$daemon_help_out" "Metis daemon"

acp_help_out="$(run_cli help acp)"
printf '%s\n' "$acp_help_out"
assert_contains "$acp_help_out" "Metis acp"

nodes_help_out="$(run_cli help nodes)"
printf '%s\n' "$nodes_help_out"
assert_contains "$nodes_help_out" "Metis nodes"

devices_help_out="$(run_cli help devices)"
printf '%s\n' "$devices_help_out"
assert_contains "$devices_help_out" "Metis devices"

interactive_help_out="$(run_cli help interactive)"
printf '%s\n' "$interactive_help_out"
assert_contains "$interactive_help_out" "Metis interactive"
assert_contains "$interactive_help_out" "Docs: https://docs.metis.ai/cli/tui"

gateway_help_out="$(run_cli help gateway)"
printf '%s\n' "$gateway_help_out"
assert_contains "$gateway_help_out" "Metis gateway"
assert_contains "$gateway_help_out" "gateway run"

channel_help_out="$(run_cli help channel)"
printf '%s\n' "$channel_help_out"
assert_contains "$channel_help_out" "Built-in channels"

plugin_help_out="$(run_cli help plugin)"
printf '%s\n' "$plugin_help_out"
assert_contains "$plugin_help_out" "Installed plugins"

sessions_help_out="$(run_cli help sessions)"
printf '%s\n' "$sessions_help_out"
assert_contains "$sessions_help_out" "gateway sessions"

cron_help_out="$(run_cli help cron)"
printf '%s\n' "$cron_help_out"
assert_contains "$cron_help_out" "gateway cron"

echo "[cli-regression] root dispatch"
config_out="$(run_cli config)"
printf '%s\n' "$config_out"
assert_contains "$config_out" "Metis config"
assert_contains "$config_out" "Inspect and manage local configuration"
assert_contains "$config_out" "Supported subcommands: path | show | workspace | defaults | validate | get <key> | set <field> <value...> | help"

config_help_sub_out="$(run_cli config help)"
printf '%s\n' "$config_help_sub_out"
assert_contains "$config_help_sub_out" "Usage:"

config_path_out="$(run_cli config path)"
printf '%s\n' "$config_path_out"
assert_contains "$config_path_out" "$TMP_HOME/metis.json"

config_defaults_out="$(run_cli config defaults)"
printf '%s\n' "$config_defaults_out"
assert_contains "$config_defaults_out" "\"kind\": \"config\""
assert_contains "$config_defaults_out" "\"modelConfig\":"
assert_contains "$config_defaults_out" "\"modelRuntime\":"
assert_contains "$config_defaults_out" "\"modelSelection\":"
assert_contains "$config_defaults_out" "\"candidateModels\":"
assert_contains "$config_defaults_out" "models.json"
assert_contains "$config_defaults_out" "\"provider\": \"qwen\""

config_validate_out="$(run_cli config validate)"
printf '%s\n' "$config_validate_out"
assert_contains "$config_validate_out" "\"gatewayEnabled\":"
assert_contains "$config_validate_out" "\"modelConfig\":"
assert_contains "$config_validate_out" "\"modelRuntime\":"
assert_contains "$config_validate_out" "\"modelSelection\":"

config_get_model_out="$(run_cli config get model)"
printf '%s\n' "$config_get_model_out"
assert_contains "$config_get_model_out" "\"key\": \"model\""

config_get_provider_out="$(run_cli config get provider)"
printf '%s\n' "$config_get_provider_out"
assert_contains "$config_get_provider_out" "\"key\": \"provider\""
assert_contains "$config_get_provider_out" "\"value\": \"qwen\""

config_get_missing_out="$(run_cli config get)"
printf '%s\n' "$config_get_missing_out"
assert_contains "$config_get_missing_out" "Missing required argument for config get: <key>"

config_set_provider_out="$(run_cli config set provider qwen)"
printf '%s\n' "$config_set_provider_out"
assert_contains "$config_set_provider_out" "\"field\": \"provider\""
assert_contains "$config_set_provider_out" "\"provider\": \"qwen\""
assert_contains "$config_set_provider_out" "\"value\": \"qwen:qwen3.5-plus\""

config_set_model_out="$(run_cli config set model qwen:qwen-plus)"
printf '%s\n' "$config_set_model_out"
assert_contains "$config_set_model_out" "\"field\": \"model\""
assert_contains "$config_set_model_out" "\"value\": \"qwen:qwen-plus\""

config_set_fallbacks_out="$(run_cli config set fallback-models openai:gpt-5.4 anthropic:claude-sonnet-4-5)"
printf '%s\n' "$config_set_fallbacks_out"
assert_contains "$config_set_fallbacks_out" "\"field\": \"fallback-models\""
assert_contains "$config_set_fallbacks_out" "openai:gpt-5.4"
assert_contains "$config_set_fallbacks_out" "anthropic:claude-sonnet-4-5"

backup_out="$(run_cli backup)"
printf '%s\n' "$backup_out"
assert_contains "$backup_out" "Metis backup"
assert_contains "$backup_out" "Inspect backup scope and backup state"

backup_state_out="$(run_cli backup state)"
printf '%s\n' "$backup_state_out"
assert_contains "$backup_state_out" "\"kind\": \"backup\""
assert_contains "$backup_state_out" "\"preview\": true"

backup_preview_out="$(run_cli backup preview)"
printf '%s\n' "$backup_preview_out"
assert_contains "$backup_preview_out" "\"mode\": \"preview\""

backup_unknown_out="$(run_cli backup bogus)"
printf '%s\n' "$backup_unknown_out"
assert_contains "$backup_unknown_out" "Unknown backup subcommand: bogus"

reset_out="$(run_cli reset)"
printf '%s\n' "$reset_out"
assert_contains "$reset_out" "Metis reset"
assert_contains "$reset_out" "Preview reset scope and reset targets"

reset_preview_out="$(run_cli reset preview)"
printf '%s\n' "$reset_preview_out"
assert_contains "$reset_preview_out" "\"kind\": \"reset\""
assert_contains "$reset_preview_out" "\"targets\""

reset_targets_out="$(run_cli reset targets)"
printf '%s\n' "$reset_targets_out"
assert_contains "$reset_targets_out" "\"targets\""

uninstall_out="$(run_cli uninstall)"
printf '%s\n' "$uninstall_out"
assert_contains "$uninstall_out" "Metis uninstall"
assert_contains "$uninstall_out" "Preview local uninstall scope"

uninstall_preview_out="$(run_cli uninstall preview)"
printf '%s\n' "$uninstall_preview_out"
assert_contains "$uninstall_preview_out" "\"kind\": \"uninstall\""
assert_contains "$uninstall_preview_out" "\"rootRemoval\": true"

uninstall_path_out="$(run_cli uninstall path)"
printf '%s\n' "$uninstall_path_out"
assert_contains "$uninstall_path_out" "$TMP_HOME"

message_out="$(run_cli message)"
printf '%s\n' "$message_out"
assert_contains "$message_out" "Metis message"
assert_contains "$message_out" "Preview and inspect explicit message payloads; use \`agent --message\` for formal agent turns"

message_payload_out="$(run_cli message hello world)"
printf '%s\n' "$message_payload_out"
assert_contains "$message_payload_out" "\"kind\": \"message\""
assert_contains "$message_payload_out" "\"text\": \"hello world\""

message_preview_out="$(run_cli message preview hello world)"
printf '%s\n' "$message_preview_out"
assert_contains "$message_preview_out" "\"dispatchMode\": \"local-preview\""

message_json_out="$(run_cli message json hello world)"
printf '%s\n' "$message_json_out"
assert_contains "$message_json_out" "\"model\":"

message_file_out="$(run_cli message file $TMP_HOME/metis.json)"
printf '%s\n' "$message_file_out"
assert_contains "$message_file_out" "\"source\": \"file\""

message_file_missing_out="$(run_cli message file)"
printf '%s\n' "$message_file_missing_out"
assert_contains "$message_file_missing_out" "Missing required argument for message file: <path>"

agent_out="$(run_cli agent)"
printf '%s\n' "$agent_out"
assert_contains "$agent_out" "Missing required argument for agent run: --message <text>"

agent_help_runtime_out="$(run_cli agent help)"
printf '%s\n' "$agent_help_runtime_out"
assert_contains "$agent_help_runtime_out" "Run the formal single-turn agent entrypoint via the unified Gateway main runtime"
assert_contains "$agent_help_runtime_out" "--to <target>"
assert_contains "$agent_help_runtime_out" "--agent <id>"
assert_contains "$agent_help_runtime_out" "--json"
assert_contains "$agent_help_runtime_out" "--extra-system-prompt <text>"

agents_out="$(run_cli agents)"
printf '%s\n' "$agents_out"
assert_contains "$agents_out" "Inspect managed agents via the unified Gateway main runtime"
assert_contains "$agents_out" "bindings [--agent <id>] [--json]"
assert_contains "$agents_out" "bind --agent <id> --bind <channel[:account]>"
assert_contains "$agents_out" "unbind --agent <id>"
assert_contains "$agents_out" "add --agent <id>"
assert_contains "$agents_out" "set-identity --agent <id>"
assert_contains "$agents_out" "delete --agent <id>"

mcp_out="$(run_cli mcp)"
printf '%s\n' "$mcp_out"
assert_contains "$mcp_out" "Manage MCP servers and expose the unified Gateway main runtime over MCP stdio"
assert_contains "$mcp_out" "serve [--url <url>]"
assert_contains "$mcp_out" "list | show [name] | set <name> <json> | unset <name>"

tasks_out="$(run_cli tasks)"
printf '%s\n' "$tasks_out"
assert_contains "$tasks_out" "Metis tasks"
assert_contains "$tasks_out" "Inspect and operate task workflows"

tasks_list_out="$(run_cli tasks list)"
printf '%s\n' "$tasks_list_out"
assert_contains "$tasks_list_out" "\"kind\": \"tasks\""
assert_contains "$tasks_list_out" "\"entries\""

tasks_show_out="$(run_cli tasks show)"
printf '%s\n' "$tasks_show_out"
assert_contains "$tasks_show_out" "\"defaultFlow\": \"agent --message\""

tasks_current_out="$(run_cli tasks current)"
printf '%s\n' "$tasks_current_out"
assert_contains "$tasks_current_out" "\"current\": \"agent --message\""

tasks_next_out="$(run_cli tasks next)"
printf '%s\n' "$tasks_next_out"
assert_contains "$tasks_next_out" "\"recommended\": \"gateway cron list\""

models_out="$(run_cli models)"
printf '%s\n' "$models_out"
assert_contains "$models_out" "Inspect models, providers, and model resolution"

models_providers_out="$(run_cli models providers)"
printf '%s\n' "$models_providers_out"
assert_contains "$models_providers_out" "\"providers\""
assert_contains "$models_providers_out" "\"authChoiceGroups\""
assert_contains "$models_providers_out" "\"apiKeyConfigPath\": \"models.providers.qwen.apiKey\""
assert_contains "$models_providers_out" "\"displayName\": \"Qwen Cloud\""
assert_contains "$models_providers_out" "\"defaultModelRef\": \"qwen:qwen3.5-plus\""
assert_contains "$models_providers_out" "\"provider\": \"volcengine\""
assert_contains "$models_providers_out" "\"provider\": \"byteplus\""
assert_contains "$models_providers_out" "\"provider\": \"custom\""
assert_contains "$models_providers_out" "\"provider\": \"zai\""
assert_contains "$models_providers_out" "\"authChoices\": ["

models_auth_out="$(run_cli models auth)"
printf '%s\n' "$models_auth_out"
assert_contains "$models_auth_out" "\"subcommand\": \"auth\""
assert_contains "$models_auth_out" "\"choiceId\": \"qwen-api-key\""

models_resolve_out="$(run_cli models resolve ark:kimi-k2-250905)"
printf '%s\n' "$models_resolve_out"
assert_contains "$models_resolve_out" "\"provider\": \"ark\""

models_status_out="$(run_cli models status)"
printf '%s\n' "$models_status_out"
assert_contains "$models_status_out" "\"subcommand\": \"status\""
assert_contains "$models_status_out" "\"modelConfig\":"
assert_contains "$models_status_out" "\"runtimeState\":"
assert_contains "$models_status_out" "\"modelSelection\":"
assert_contains "$models_status_out" "\"candidateModels\":"
assert_contains "$models_status_out" "\"runtimePrimaryModelRef\":"
assert_contains "$models_status_out" "\"runtimeProvider\": \"dashscope\""
assert_contains "$models_status_out" "\"authChoices\":"

models_set_out="$(run_cli models set qwen:qwen3.5-plus)"
printf '%s\n' "$models_set_out"
assert_contains "$models_set_out" "\"subcommand\": \"set\""
assert_contains "$models_set_out" "\"value\": \"qwen:qwen3.5-plus\""

config_set_fallbacks_clear_out="$(run_cli config set fallback-models clear)"
printf '%s\n' "$config_set_fallbacks_clear_out"
assert_contains "$config_set_fallbacks_clear_out" "\"field\": \"fallback-models\""
assert_contains "$config_set_fallbacks_clear_out" "\"applied\": []"

models_search_out="$(run_cli models search kimi)"
printf '%s\n' "$models_search_out"
assert_contains "$models_search_out" "\"matches\""

models_search_missing_out="$(run_cli models search)"
printf '%s\n' "$models_search_missing_out"
assert_contains "$models_search_missing_out" "Missing required argument for models search: <term>"

logs_out="$(run_cli logs path)"
printf '%s\n' "$logs_out"
assert_contains "$logs_out" "$TMP_HOME/logs"

logs_recent_out="$(run_cli logs recent)"
printf '%s\n' "$logs_recent_out"
assert_contains "$logs_recent_out" "\"mode\": \"recent\""

logs_tail_out="$(run_cli logs tail gateway.log)"
printf '%s\n' "$logs_tail_out"
assert_contains "$logs_tail_out" "\"target\": \"gateway.log\""

logs_show_out="$(run_cli logs show cli.log)"
printf '%s\n' "$logs_show_out"
assert_contains "$logs_show_out" "\"subcommand\": \"show\""

docs_out="$(run_cli docs open)"
printf '%s\n' "$docs_out"
assert_contains "$docs_out" "\"kind\": \"docs\""
assert_contains "$docs_out" "https://docs.metis.ai/cli"
assert_contains "$docs_out" "\"nextSteps\""

docs_topics_out="$(run_cli docs topics)"
printf '%s\n' "$docs_topics_out"
assert_contains "$docs_topics_out" "\"topics\""

docs_search_out="$(run_cli docs search cli)"
printf '%s\n' "$docs_search_out"
assert_contains "$docs_search_out" "\"query\": \"cli\""

docs_search_missing_out="$(run_cli docs search)"
printf '%s\n' "$docs_search_missing_out"
assert_contains "$docs_search_missing_out" "Missing required argument for docs search: <term>"

docs_index_out="$(run_cli docs index)"
printf '%s\n' "$docs_index_out"
assert_contains "$docs_index_out" "\"primaryPath\": \"/cli\""

docs_path_out="$(run_cli docs path)"
printf '%s\n' "$docs_path_out"
assert_contains "$docs_path_out" "\"subcommand\": \"path\""

system_out="$(run_cli system info)"
printf '%s\n' "$system_out"
assert_contains "$system_out" "\"kind\": \"system\""
assert_contains "$system_out" "\"nextSteps\""

system_paths_out="$(run_cli system paths)"
printf '%s\n' "$system_paths_out"
assert_contains "$system_paths_out" "\"logsDir\":"
assert_contains "$system_paths_out" "\"nextSteps\""

system_env_out="$(run_cli system env)"
printf '%s\n' "$system_env_out"
assert_contains "$system_env_out" "\"METIS_HOME\":"

system_status_out="$(run_cli system status)"
printf '%s\n' "$system_status_out"
assert_contains "$system_status_out" "\"subcommand\": \"status\""

system_doctor_out="$(run_cli system doctor)"
printf '%s\n' "$system_doctor_out"
assert_contains "$system_doctor_out" "\"subcommand\": \"doctor\""

approvals_out="$(run_cli approvals status)"
printf '%s\n' "$approvals_out"
assert_contains "$approvals_out" "\"kind\": \"approvals\""
assert_contains "$approvals_out" "\"nextSteps\""

approvals_current_out="$(run_cli approvals current)"
printf '%s\n' "$approvals_current_out"
assert_contains "$approvals_current_out" "\"mode\": \"current\""

approvals_policy_out="$(run_cli approvals policy)"
printf '%s\n' "$approvals_policy_out"
assert_contains "$approvals_policy_out" "\"subcommand\": \"policy\""

approvals_json_out="$(run_cli approvals json)"
printf '%s\n' "$approvals_json_out"
assert_contains "$approvals_json_out" "\"subcommand\": \"json\""

sandbox_out="$(run_cli sandbox status)"
printf '%s\n' "$sandbox_out"
assert_contains "$sandbox_out" "\"kind\": \"sandbox\""
assert_contains "$sandbox_out" "\"nextSteps\""

sandbox_rules_out="$(run_cli sandbox rules)"
printf '%s\n' "$sandbox_rules_out"
assert_contains "$sandbox_rules_out" "\"rules\""

sandbox_check_out="$(run_cli sandbox check)"
printf '%s\n' "$sandbox_check_out"
assert_contains "$sandbox_check_out" "\"profile\": \"workspace-write\""

sandbox_profile_out="$(run_cli sandbox profile)"
printf '%s\n' "$sandbox_profile_out"
assert_contains "$sandbox_profile_out" "\"subcommand\": \"profile\""

node_out="$(run_cli node show)"
printf '%s\n' "$node_out"
assert_contains "$node_out" "\"kind\": \"node\""
assert_contains "$node_out" "\"nextSteps\""

node_policy_out="$(run_cli node policy)"
printf '%s\n' "$node_policy_out"
assert_contains "$node_policy_out" "\"mode\": \"policy\""

node_status_out="$(run_cli node status)"
printf '%s\n' "$node_status_out"
assert_contains "$node_status_out" "\"subcommand\": \"status\""

node_history_out="$(run_cli node history)"
printf '%s\n' "$node_history_out"
assert_contains "$node_history_out" "\"subcommand\": \"history\""

qa_out="$(run_cli qa status)"
printf '%s\n' "$qa_out"
assert_contains "$qa_out" "\"kind\": \"qa\""
assert_contains "$qa_out" "\"nextSteps\""

qa_run_out="$(run_cli qa run)"
printf '%s\n' "$qa_run_out"
assert_contains "$qa_run_out" "\"scripts\""

qa_report_out="$(run_cli qa report)"
printf '%s\n' "$qa_report_out"
assert_contains "$qa_report_out" "\"subcommand\": \"report\""

qa_history_out="$(run_cli qa history)"
printf '%s\n' "$qa_history_out"
assert_contains "$qa_history_out" "\"subcommand\": \"history\""

hooks_out="$(run_cli hooks status)"
printf '%s\n' "$hooks_out"
assert_contains "$hooks_out" "\"kind\": \"hooks\""
assert_contains "$hooks_out" "\"nextSteps\""

hooks_current_out="$(run_cli hooks current)"
printf '%s\n' "$hooks_current_out"
assert_contains "$hooks_current_out" "\"mode\": \"current\""

hooks_validate_out="$(run_cli hooks validate)"
printf '%s\n' "$hooks_validate_out"
assert_contains "$hooks_validate_out" "\"subcommand\": \"validate\""

hooks_open_out="$(run_cli hooks open)"
printf '%s\n' "$hooks_open_out"
assert_contains "$hooks_open_out" "\"subcommand\": \"open\""

webhooks_out="$(run_cli webhooks status)"
printf '%s\n' "$webhooks_out"
assert_contains "$webhooks_out" "\"kind\": \"webhooks\""
assert_contains "$webhooks_out" "\"nextSteps\""

webhooks_deliveries_out="$(run_cli webhooks deliveries)"
printf '%s\n' "$webhooks_deliveries_out"
assert_contains "$webhooks_deliveries_out" "\"mode\": \"deliveries\""

webhooks_current_out="$(run_cli webhooks current)"
printf '%s\n' "$webhooks_current_out"
assert_contains "$webhooks_current_out" "\"subcommand\": \"current\""

webhooks_replay_out="$(run_cli webhooks replay)"
printf '%s\n' "$webhooks_replay_out"
assert_contains "$webhooks_replay_out" "\"subcommand\": \"replay\""

qr_out="$(run_cli qr show)"
printf '%s\n' "$qr_out"
assert_contains "$qr_out" "\"kind\": \"qr\""
assert_contains "$qr_out" "\"nextSteps\""

qr_payload_out="$(run_cli qr payload)"
printf '%s\n' "$qr_payload_out"
assert_contains "$qr_payload_out" "\"mode\": \"payload\""

qr_copy_out="$(run_cli qr copy)"
printf '%s\n' "$qr_copy_out"
assert_contains "$qr_copy_out" "\"subcommand\": \"copy\""

qr_link_out="$(run_cli qr link)"
printf '%s\n' "$qr_link_out"
assert_contains "$qr_link_out" "\"subcommand\": \"link\""

pairing_out="$(run_cli pairing status)"
printf '%s\n' "$pairing_out"
assert_contains "$pairing_out" "\"kind\": \"pairing\""
assert_contains "$pairing_out" "\"nextSteps\""

pairing_current_out="$(run_cli pairing current)"
printf '%s\n' "$pairing_current_out"
assert_contains "$pairing_current_out" "\"mode\": \"current\""

pairing_code_out="$(run_cli pairing code)"
printf '%s\n' "$pairing_code_out"
assert_contains "$pairing_code_out" "\"subcommand\": \"code\""

pairing_sessions_out="$(run_cli pairing sessions)"
printf '%s\n' "$pairing_sessions_out"
assert_contains "$pairing_sessions_out" "\"subcommand\": \"sessions\""

daemon_out="$(run_cli daemon status)"
printf '%s\n' "$daemon_out"
assert_contains "$daemon_out" "\"kind\": \"daemon\""
assert_contains "$daemon_out" "\"nextSteps\""

daemon_pid_out="$(run_cli daemon pid)"
printf '%s\n' "$daemon_pid_out"
assert_contains "$daemon_pid_out" "\"mode\": \"pid\""

daemon_socket_out="$(run_cli daemon socket)"
printf '%s\n' "$daemon_socket_out"
assert_contains "$daemon_socket_out" "\"subcommand\": \"socket\""

daemon_restart_out="$(run_cli daemon restart)"
printf '%s\n' "$daemon_restart_out"
assert_contains "$daemon_restart_out" "\"subcommand\": \"restart\""

acp_out="$(run_cli acp status)"
printf '%s\n' "$acp_out"
assert_contains "$acp_out" "\"kind\": \"acp\""
assert_contains "$acp_out" "\"nextSteps\""

acp_docs_out="$(run_cli acp docs)"
printf '%s\n' "$acp_docs_out"
assert_contains "$acp_docs_out" "\"mode\": \"docs\""

acp_mode_out="$(run_cli acp mode)"
printf '%s\n' "$acp_mode_out"
assert_contains "$acp_mode_out" "\"subcommand\": \"mode\""

acp_runtime_out="$(run_cli acp runtime)"
printf '%s\n' "$acp_runtime_out"
assert_contains "$acp_runtime_out" "\"subcommand\": \"runtime\""

nodes_out="$(run_cli nodes list)"
printf '%s\n' "$nodes_out"
assert_contains "$nodes_out" "\"kind\": \"nodes\""
assert_contains "$nodes_out" "\"nextSteps\""

nodes_policy_out="$(run_cli nodes policy)"
printf '%s\n' "$nodes_policy_out"
assert_contains "$nodes_policy_out" "\"mode\": \"policy\""

nodes_status_out="$(run_cli nodes status)"
printf '%s\n' "$nodes_status_out"
assert_contains "$nodes_status_out" "\"subcommand\": \"status\""

nodes_current_out="$(run_cli nodes current)"
printf '%s\n' "$nodes_current_out"
assert_contains "$nodes_current_out" "\"subcommand\": \"current\""

devices_out="$(run_cli devices list)"
printf '%s\n' "$devices_out"
assert_contains "$devices_out" "\"kind\": \"devices\""
assert_contains "$devices_out" "\"nextSteps\""

devices_audit_out="$(run_cli devices audit)"
printf '%s\n' "$devices_audit_out"
assert_contains "$devices_audit_out" "\"mode\": \"audit\""

devices_status_out="$(run_cli devices status)"
printf '%s\n' "$devices_status_out"
assert_contains "$devices_status_out" "\"subcommand\": \"status\""

devices_current_out="$(run_cli devices current)"
printf '%s\n' "$devices_current_out"
assert_contains "$devices_current_out" "\"subcommand\": \"current\""

channel_list_out="$(run_cli channel list)"
printf '%s\n' "$channel_list_out"
assert_contains "$channel_list_out" '"telegram"'
assert_contains "$channel_list_out" '"slack"'
assert_contains "$channel_list_out" '"discord"'

plugin_list_out="$(run_cli plugin list)"
printf '%s\n' "$plugin_list_out"
assert_contains "$plugin_list_out" "Installed plugins:"
assert_contains "$plugin_list_out" "(none)"

channels_help_out="$(run_cli help channels)"
printf '%s\n' "$channels_help_out"
assert_contains "$channels_help_out" "Built-in channels"

plugins_help_out="$(run_cli help plugins)"
printf '%s\n' "$plugins_help_out"
assert_contains "$plugins_help_out" "Installed plugins"

sessions_root_help_out="$(run_cli sessions help)"
printf '%s\n' "$sessions_root_help_out"
assert_contains "$sessions_root_help_out" "Metis gateway sessions"
assert_contains "$sessions_root_help_out" "Inspect persisted gateway sessions."

cron_root_help_out="$(run_cli cron help)"
printf '%s\n' "$cron_root_help_out"
assert_contains "$cron_root_help_out" "Metis gateway cron"
assert_contains "$cron_root_help_out" "Inspect and manage scheduled jobs."

echo "[cli-regression] non-interactive"
prompt_out="$(run_cli --prompt hello)"
printf '%s\n' "$prompt_out"
assert_contains "$prompt_out" "Gateway agent failed:"
assert_contains "$prompt_out" "Start the gateway with \`metis gateway run\`"

echo "[cli-regression] ok"
