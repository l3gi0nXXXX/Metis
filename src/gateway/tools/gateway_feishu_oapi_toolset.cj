package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.io.PrintUtils

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private var gatewayFeishuOapiToolCallRunnerForTest: Option<(String, JsonObject) -> JsonObject> =
    None<(String, JsonObject) -> JsonObject>

private var gatewayFeishuOapiClientForTest: Option<FeishuOapiClient> = None<FeishuOapiClient>

public func debugSetGatewayFeishuOapiToolCallRunnerForTest(runner: Option<(String, JsonObject) -> JsonObject>): Unit {
    gatewayFeishuOapiToolCallRunnerForTest = runner
}

public func debugSetGatewayFeishuOapiClientForTest(client: Option<FeishuOapiClient>): Unit {
    gatewayFeishuOapiClientForTest = client
}

private func feishuOapiParseParamsJson(paramsJson: Option<String>): (Bool, JsonObject, String) {
    match (paramsJson) {
        case Some(raw) =>
            let trimmed = raw.trimAscii()
            if (trimmed.isEmpty()) {
                return (true, JsonObject(), "")
            }
            try {
                return (true, JsonValue.fromStr(trimmed).asObject(), "")
            } catch (e: Exception) {
                return (false, JsonObject(), e.message)
            }
        case None => (true, JsonObject(), "")
    }
}

private func feishuOapiPutIfMissing(obj: JsonObject, key: String, value: JsonValue): Unit {
    if (obj.get(key).isNone()) {
        obj.put(key, value)
    }
}

private func feishuOapiNormalizeRunnerResult(
    result: JsonObject,
    request: FeishuOapiRequest
): JsonObject {
    feishuOapiPutIfMissing(result, "tool", JsonString(request.toolName))
    feishuOapiPutIfMissing(result, "category", JsonString(request.category))
    feishuOapiPutIfMissing(result, "domain", JsonString(request.domain))
    feishuOapiPutIfMissing(result, "action", JsonString(request.action))
    feishuOapiPutIfMissing(result, "account_id", JsonString(request.accountId))
    feishuOapiPutIfMissing(result, "path", JsonString(request.path))
    feishuOapiPutIfMissing(result, "method", JsonString(request.method))
    feishuOapiPutIfMissing(result, "token_mode", JsonString(request.tokenMode))
    feishuOapiPutIfMissing(result, "required_scopes", feishuOapiJsonStringArray(request.requiredScopes))
    gatewayFeishuOapiAttachRepairActionForToolResult(result, request)
}

private func feishuOapiInvoke(
    toolName: String,
    _category: String,
    action: String,
    accountIdOpt: Option<String>,
    paramsJson: Option<String>
): String {
    let cleanTool = toolName.trimAscii()
    let cleanAction = if (action.trimAscii().isEmpty()) { "default" } else { action.trimAscii() }
    let cleanAccount = match (accountIdOpt) {
        case Some(raw) =>
            let value = raw.trimAscii()
            if (value.isEmpty()) { "default" } else { value }
        case None => "default"
    }
    let invalidRequestEnvelope = feishuOapiBuildRequest(cleanTool, cleanAction, cleanAccount, JsonObject())
    let (validParams, params, reason) = feishuOapiParseParamsJson(paramsJson)
    if (!validParams) {
        return FeishuOapiResult.invalidRequest(invalidRequestEnvelope, "params_json must be a JSON object: ${reason}").toJson().toJsonString()
    }

    let request = feishuOapiBuildRequest(cleanTool, cleanAction, cleanAccount, params)
    match (gatewayFeishuOapiToolCallRunnerForTest) {
        case Some(runner) =>
            let result = runner(cleanTool, request.toJson())
            feishuOapiNormalizeRunnerResult(result, request).toJsonString()
        case None =>
            match (gatewayFeishuOapiClientForTest) {
                case Some(client) => gatewayFeishuOapiAttachRepairActionForToolResult(client.invoke(request), request).toJsonString()
                case None => gatewayFeishuOapiAttachRepairActionForToolResult(MetisFeishuOapiClient(
                    tokenProvider: Some<FeishuOapiTokenProvider>(MetisFeishuOapiTokenProvider()),
                    httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient())
                ).invoke(request), request).toJsonString()
            }
    }
}

private func feishuOapiInvokeByTool(toolName: String, action: String, paramsJson: Option<String>, accountId: Option<String>): String {
    feishuOapiInvoke(toolName, feishuOapiCategoryForTool(toolName), action, accountId, paramsJson)
}

@toolset
public class GatewayFeishuOapiToolset {
    public init() {}

    public func debugFeishuOapiInvokeForTest(toolName: String, action: String, accountId: Option<String>, paramsJson: Option<String>): String {
        feishuOapiInvokeByTool(toolName, action, paramsJson, accountId)
    }

    public func debugFeishuOapiSmokeDryRunPlanForTest(casesJson: String, defaultAccountId: String, domain: String): String {
        feishuOapiSmokeDryRunPlanFromCases(casesJson, defaultAccountId: defaultAccountId, domain: domain).toJsonString()
    }

    @tool[description: "Build a redacted Feishu OAPI read/write smoke request plan without credentials, token lookup, or network. Pass cases_json as an array of {tool, action, accountId, params}; write cases remain external-resource-required until an operator enables live smoke."]
    public func feishu_oapi_smoke_plan(cases_json: String, default_account_id: Option<String>, domain: Option<String>): String {
        PrintUtils.printTool("feishu_oapi_smoke_plan", shortMessage: "dry-run")
        feishuOapiSmokeDryRunPlanFromCases(
            cases_json,
            defaultAccountId: match (default_account_id) {
                case Some(value) => value
                case None => "default"
            },
            domain: match (domain) {
                case Some(value) => value
                case None => "https://open.feishu.cn"
            }
        ).toJsonString()
    }

    @tool[description: "Fetch a Feishu document through the Metis-native Feishu OAPI client boundary. When auth is absent it returns structured auth_required JSON. Pass OpenClaw-compatible parameters as params_json."]
    public func feishu_fetch_doc(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_fetch_doc", shortMessage: action)
        feishuOapiInvokeByTool("feishu_fetch_doc", action, params_json, account_id)
    }

    @tool[description: "Create a Feishu document through the Metis-native Feishu OAPI client boundary. Returns structured success/auth/scope/API diagnostics."]
    public func feishu_create_doc(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_create_doc", shortMessage: action)
        feishuOapiInvokeByTool("feishu_create_doc", action, params_json, account_id)
    }

    @tool[description: "Update a Feishu document through the Metis-native Feishu OAPI client boundary. Pass OpenClaw-compatible update parameters as params_json."]
    public func feishu_update_doc(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_update_doc", shortMessage: action)
        feishuOapiInvokeByTool("feishu_update_doc", action, params_json, account_id)
    }

    @tool[description: "Handle Feishu document comments through the Metis-native Feishu OAPI client boundary."]
    public func feishu_doc_comments(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_doc_comments", shortMessage: action)
        feishuOapiInvokeByTool("feishu_doc_comments", action, params_json, account_id)
    }

    @tool[description: "Handle Feishu document media through the Metis-native Feishu OAPI client boundary. Use feishu_im_user_fetch_resource for current-turn IM resources already staged by the channel."]
    public func feishu_doc_media(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_doc_media", shortMessage: action)
        feishuOapiInvokeByTool("feishu_doc_media", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu wiki spaces through the Metis-native Feishu OAPI client boundary."]
    public func feishu_wiki_space(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_wiki_space", shortMessage: action)
        feishuOapiInvokeByTool("feishu_wiki_space", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu wiki space nodes through the Metis-native Feishu OAPI client boundary."]
    public func feishu_wiki_space_node(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_wiki_space_node", shortMessage: action)
        feishuOapiInvokeByTool("feishu_wiki_space_node", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Drive files through the Metis-native Feishu OAPI client boundary."]
    public func feishu_drive_file(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_drive_file", shortMessage: action)
        feishuOapiInvokeByTool("feishu_drive_file", action, params_json, account_id)
    }

    @tool[description: "Search Feishu documents and wiki nodes through the Metis-native Feishu OAPI client boundary."]
    public func feishu_search_doc_wiki(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_search_doc_wiki", shortMessage: action)
        feishuOapiInvokeByTool("feishu_search_doc_wiki", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable apps through the Metis-native Feishu OAPI client boundary."]
    public func feishu_bitable_app(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable tables through the Metis-native Feishu OAPI client boundary."]
    public func feishu_bitable_app_table(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app_table", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app_table", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable records through the Metis-native Feishu OAPI client boundary."]
    public func feishu_bitable_app_table_record(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app_table_record", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app_table_record", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable fields through the Metis-native Feishu OAPI client boundary."]
    public func feishu_bitable_app_table_field(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app_table_field", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app_table_field", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable views through the Metis-native Feishu OAPI client boundary."]
    public func feishu_bitable_app_table_view(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app_table_view", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app_table_view", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu calendars through the Metis-native Feishu OAPI client boundary."]
    public func feishu_calendar_calendar(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_calendar_calendar", shortMessage: action)
        feishuOapiInvokeByTool("feishu_calendar_calendar", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu calendar events through the Metis-native Feishu OAPI client boundary."]
    public func feishu_calendar_event(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_calendar_event", shortMessage: action)
        feishuOapiInvokeByTool("feishu_calendar_event", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu calendar event attendees through the Metis-native Feishu OAPI client boundary."]
    public func feishu_calendar_event_attendee(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_calendar_event_attendee", shortMessage: action)
        feishuOapiInvokeByTool("feishu_calendar_event_attendee", action, params_json, account_id)
    }

    @tool[description: "Query Feishu calendar free/busy information through the Metis-native Feishu OAPI client boundary."]
    public func feishu_calendar_freebusy(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_calendar_freebusy", shortMessage: action)
        feishuOapiInvokeByTool("feishu_calendar_freebusy", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu tasks through the Metis-native Feishu OAPI client boundary."]
    public func feishu_task_task(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_task", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_task", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task lists through the Metis-native Feishu OAPI client boundary."]
    public func feishu_task_tasklist(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_tasklist", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_tasklist", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task attachments through the Metis-native Feishu OAPI client boundary."]
    public func feishu_task_attachment(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_attachment", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_attachment", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task sections through the Metis-native Feishu OAPI client boundary."]
    public func feishu_task_section(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_section", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_section", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task comments through the Metis-native Feishu OAPI client boundary."]
    public func feishu_task_comment(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_comment", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_comment", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu subtasks through the Metis-native Feishu OAPI client boundary."]
    public func feishu_task_subtask(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_subtask", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_subtask", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task agent assignments through the Metis-native Feishu OAPI client boundary."]
    public func feishu_task_agent(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_agent", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_agent", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu sheets through the Metis-native Feishu OAPI client boundary."]
    public func feishu_sheet(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_sheet", shortMessage: action)
        feishuOapiInvokeByTool("feishu_sheet", action, params_json, account_id)
    }

    @tool[description: "Search or inspect Feishu chats through the Metis-native Feishu OAPI client boundary."]
    public func feishu_chat(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_chat", shortMessage: action)
        feishuOapiInvokeByTool("feishu_chat", action, params_json, account_id)
    }

    @tool[description: "List or inspect Feishu chat members through the Metis-native Feishu OAPI client boundary."]
    public func feishu_chat_members(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_chat_members", shortMessage: action)
        feishuOapiInvokeByTool("feishu_chat_members", action, params_json, account_id)
    }

    @tool[description: "Get Feishu user information through the Metis-native Feishu OAPI client boundary."]
    public func feishu_get_user(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_get_user", shortMessage: action)
        feishuOapiInvokeByTool("feishu_get_user", action, params_json, account_id)
    }

    @tool[description: "Search Feishu users through the Metis-native Feishu OAPI client boundary."]
    public func feishu_search_user(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_search_user", shortMessage: action)
        feishuOapiInvokeByTool("feishu_search_user", action, params_json, account_id)
    }

    @tool[description: "Send or reply to Feishu IM messages as a user through the Metis-native Feishu OAPI client boundary."]
    public func feishu_im_user_message(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_message", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_user_message", action, params_json, account_id)
    }

    @tool[description: "Get Feishu IM messages as a user through the Metis-native Feishu OAPI client boundary."]
    public func feishu_im_user_get_messages(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_get_messages", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_user_get_messages", action, params_json, account_id)
    }

    @tool[description: "Get Feishu thread messages as a user through the Metis-native Feishu OAPI client boundary."]
    public func feishu_im_user_get_thread_messages(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_get_thread_messages", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_user_get_thread_messages", action, params_json, account_id)
    }

    @tool[description: "Search Feishu IM messages as a user through the Metis-native Feishu OAPI client boundary."]
    public func feishu_im_user_search_messages(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_search_messages", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_user_search_messages", action, params_json, account_id)
    }

    @tool[description: "Inspect or revoke Metis Feishu user OAuth status through the A-stage Feishu OAuth boundary. Tokens and secrets are never returned."]
    public func feishu_oauth(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_oauth", shortMessage: action)
        feishuOapiInvokeByTool("feishu_oauth", action, params_json, account_id)
    }

    @tool[description: "Start A-stage batch user authorization diagnostics for Feishu. Full app-scope batch auth remains delegated to the native /feishu auth flow."]
    public func feishu_oauth_batch_auth(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_oauth_batch_auth", shortMessage: action)
        feishuOapiInvokeByTool("feishu_oauth_batch_auth", action, params_json, account_id)
    }

    @tool[description: "Fetch a Feishu IM resource through the OAPI request boundary using bot/resource-compatible envelope parameters. Media persistence is handled by the Feishu media toolset when available."]
    public func feishu_im_bot_image(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_bot_image", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_bot_image", action, params_json, account_id)
    }

    @tool[description: "Create a Feishu ask-user-question card through the A-stage OAPI boundary. Card action handling remains in the Feishu channel runtime."]
    public func feishu_ask_user_question(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_ask_user_question", shortMessage: action)
        feishuOapiInvokeByTool("feishu_ask_user_question", action, params_json, account_id)
    }
}
