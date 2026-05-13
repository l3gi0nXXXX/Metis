package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.io.PrintUtils

import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private var gatewayFeishuOapiToolCallRunnerForTest: Option<(String, JsonObject) -> JsonObject> =
    None<(String, JsonObject) -> JsonObject>

public func debugSetGatewayFeishuOapiToolCallRunnerForTest(runner: Option<(String, JsonObject) -> JsonObject>): Unit {
    gatewayFeishuOapiToolCallRunnerForTest = runner
}

private func feishuOapiStringArrayJson(values: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (value in values) {
        arr.add(JsonString(value))
    }
    arr
}

private func feishuOapiCategoryForTool(toolName: String): String {
    let name = toolName.trimAscii()
    if (name == "feishu_fetch_doc" || name == "feishu_create_doc" || name == "feishu_update_doc" || name.startsWith("feishu_doc_")) {
        return "docs"
    }
    if (name.startsWith("feishu_wiki_")) {
        return "wiki"
    }
    if (name.startsWith("feishu_drive_")) {
        return "drive"
    }
    if (name.startsWith("feishu_search_doc")) {
        return "search"
    }
    if (name.startsWith("feishu_bitable_")) {
        return "bitable"
    }
    if (name.startsWith("feishu_calendar_")) {
        return "calendar"
    }
    if (name.startsWith("feishu_task_")) {
        return "task"
    }
    if (name == "feishu_sheet") {
        return "sheets"
    }
    if (name.startsWith("feishu_chat")) {
        return "chat"
    }
    if (name == "feishu_get_user" || name == "feishu_search_user") {
        return "user"
    }
    if (name.startsWith("feishu_im_")) {
        return "im"
    }
    "oapi"
}

private func feishuOapiRequiredScopes(category: String): Array<String> {
    match (category.trimAscii()) {
        case "docs" => ["docx:document:readonly"]
        case "wiki" => ["wiki:wiki:readonly"]
        case "drive" => ["drive:drive:readonly"]
        case "search" => ["docx:document:readonly", "wiki:wiki:readonly"]
        case "bitable" => ["bitable:app:readonly"]
        case "calendar" => ["calendar:calendar:readonly"]
        case "task" => ["task:task:readonly"]
        case "sheets" => ["sheets:spreadsheet:readonly"]
        case "chat" => ["im:chat:readonly"]
        case "user" => ["contact:contact.base:readonly"]
        case "im" => ["im:message:readonly"]
        case _ => []
    }
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

private func feishuOapiBaseEnvelope(toolName: String, category: String, action: String, accountId: String): JsonObject {
    let out = JsonObject()
    out.put("tool", JsonString(toolName))
    out.put("category", JsonString(category))
    out.put("action", JsonString(action))
    out.put("account_id", JsonString(accountId))
    out.put("required_scopes", feishuOapiStringArrayJson(feishuOapiRequiredScopes(category)))
    out
}

private func feishuOapiPutIfMissing(obj: JsonObject, key: String, value: JsonValue): Unit {
    if (obj.get(key).isNone()) {
        obj.put(key, value)
    }
}

private func feishuOapiInvalidRequest(toolName: String, category: String, action: String, accountId: String, reason: String): String {
    let out = feishuOapiBaseEnvelope(toolName, category, action, accountId)
    out.put("ok", JsonBool(false))
    out.put("status", JsonString("invalid_request"))
    out.put("reason", JsonString(reason.trimAscii()))
    out.toJsonString()
}

private func feishuOapiAuthRequired(toolName: String, category: String, action: String, accountId: String): String {
    let out = feishuOapiBaseEnvelope(toolName, category, action, accountId)
    out.put("ok", JsonBool(false))
    out.put("status", JsonString("auth_required"))
    out.put("error", JsonString("Feishu OAPI user authorization is not configured in this runtime. Configure account auth before calling this tool against Feishu."))
    let auth = JsonObject()
    auth.put("required", JsonBool(true))
    auth.put("state", JsonString("absent"))
    auth.put("mode", JsonString("user_access_token"))
    out.put("auth", auth)
    out.toJsonString()
}

private func feishuOapiNormalizeRunnerResult(
    result: JsonObject,
    toolName: String,
    category: String,
    action: String,
    accountId: String
): JsonObject {
    feishuOapiPutIfMissing(result, "tool", JsonString(toolName))
    feishuOapiPutIfMissing(result, "category", JsonString(category))
    feishuOapiPutIfMissing(result, "action", JsonString(action))
    feishuOapiPutIfMissing(result, "account_id", JsonString(accountId))
    feishuOapiPutIfMissing(result, "required_scopes", feishuOapiStringArrayJson(feishuOapiRequiredScopes(category)))
    result
}

private func feishuOapiInvoke(
    toolName: String,
    category: String,
    action: String,
    accountIdOpt: Option<String>,
    paramsJson: Option<String>
): String {
    let cleanTool = toolName.trimAscii()
    let cleanCategory = if (category.trimAscii().isEmpty()) { feishuOapiCategoryForTool(cleanTool) } else { category.trimAscii() }
    let cleanAction = if (action.trimAscii().isEmpty()) { "default" } else { action.trimAscii() }
    let cleanAccount = match (accountIdOpt) {
        case Some(raw) =>
            let value = raw.trimAscii()
            if (value.isEmpty()) { "default" } else { value }
        case None => "default"
    }
    let (validParams, params, reason) = feishuOapiParseParamsJson(paramsJson)
    if (!validParams) {
        return feishuOapiInvalidRequest(cleanTool, cleanCategory, cleanAction, cleanAccount, "params_json must be a JSON object: ${reason}")
    }

    let request = feishuOapiBaseEnvelope(cleanTool, cleanCategory, cleanAction, cleanAccount)
    request.put("params", params)
    match (gatewayFeishuOapiToolCallRunnerForTest) {
        case Some(runner) =>
            let result = runner(cleanTool, request)
            feishuOapiNormalizeRunnerResult(result, cleanTool, cleanCategory, cleanAction, cleanAccount).toJsonString()
        case None =>
            feishuOapiAuthRequired(cleanTool, cleanCategory, cleanAction, cleanAccount)
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

    @tool[description: "Fetch a Feishu document through the Metis-native Feishu OAPI surface. Runtime auth is not performed by this placeholder; when auth is absent it returns structured auth_required JSON. Pass OpenClaw-compatible parameters as params_json."]
    public func feishu_fetch_doc(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_fetch_doc", shortMessage: action)
        feishuOapiInvokeByTool("feishu_fetch_doc", action, params_json, account_id)
    }

    @tool[description: "Create a Feishu document through the Metis-native Feishu OAPI surface. Returns structured auth_required or fake-client JSON; no real Feishu network is used by this toolset."]
    public func feishu_create_doc(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_create_doc", shortMessage: action)
        feishuOapiInvokeByTool("feishu_create_doc", action, params_json, account_id)
    }

    @tool[description: "Update a Feishu document through the Metis-native Feishu OAPI surface. Pass OpenClaw-compatible update parameters as params_json."]
    public func feishu_update_doc(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_update_doc", shortMessage: action)
        feishuOapiInvokeByTool("feishu_update_doc", action, params_json, account_id)
    }

    @tool[description: "Handle Feishu document comments through the OAPI placeholder surface. Returns structured auth/scope diagnostics until runtime auth is configured."]
    public func feishu_doc_comments(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_doc_comments", shortMessage: action)
        feishuOapiInvokeByTool("feishu_doc_comments", action, params_json, account_id)
    }

    @tool[description: "Handle Feishu document media through the OAPI placeholder surface. Use feishu_im_user_fetch_resource for current-turn IM resources already staged by the channel."]
    public func feishu_doc_media(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_doc_media", shortMessage: action)
        feishuOapiInvokeByTool("feishu_doc_media", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu wiki spaces. Placeholder returns structured auth_required/scope_missing JSON and supports fake-client tests only."]
    public func feishu_wiki_space(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_wiki_space", shortMessage: action)
        feishuOapiInvokeByTool("feishu_wiki_space", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu wiki space nodes. Placeholder returns structured auth_required/scope_missing JSON and supports fake-client tests only."]
    public func feishu_wiki_space_node(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_wiki_space_node", shortMessage: action)
        feishuOapiInvokeByTool("feishu_wiki_space_node", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Drive files. This OpenClaw-lark-compatible tool name currently returns structured auth placeholders unless a fake client is injected for tests."]
    public func feishu_drive_file(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_drive_file", shortMessage: action)
        feishuOapiInvokeByTool("feishu_drive_file", action, params_json, account_id)
    }

    @tool[description: "Search Feishu documents and wiki nodes. This OpenClaw-lark-compatible tool name returns structured auth placeholders unless a fake client is injected for tests."]
    public func feishu_search_doc_wiki(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_search_doc_wiki", shortMessage: action)
        feishuOapiInvokeByTool("feishu_search_doc_wiki", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable apps. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_bitable_app(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable tables. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_bitable_app_table(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app_table", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app_table", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable records. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_bitable_app_table_record(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app_table_record", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app_table_record", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable fields. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_bitable_app_table_field(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app_table_field", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app_table_field", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu Bitable views. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_bitable_app_table_view(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_bitable_app_table_view", shortMessage: action)
        feishuOapiInvokeByTool("feishu_bitable_app_table_view", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu calendars. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_calendar_calendar(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_calendar_calendar", shortMessage: action)
        feishuOapiInvokeByTool("feishu_calendar_calendar", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu calendar events. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_calendar_event(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_calendar_event", shortMessage: action)
        feishuOapiInvokeByTool("feishu_calendar_event", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu calendar event attendees. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_calendar_event_attendee(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_calendar_event_attendee", shortMessage: action)
        feishuOapiInvokeByTool("feishu_calendar_event_attendee", action, params_json, account_id)
    }

    @tool[description: "Query Feishu calendar free/busy information. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_calendar_freebusy(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_calendar_freebusy", shortMessage: action)
        feishuOapiInvokeByTool("feishu_calendar_freebusy", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu tasks. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_task_task(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_task", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_task", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task lists. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_task_tasklist(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_tasklist", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_tasklist", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task attachments. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_task_attachment(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_attachment", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_attachment", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task sections. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_task_section(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_section", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_section", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task comments. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_task_comment(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_comment", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_comment", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu subtasks. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_task_subtask(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_subtask", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_subtask", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu task agent assignments. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_task_agent(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_task_agent", shortMessage: action)
        feishuOapiInvokeByTool("feishu_task_agent", action, params_json, account_id)
    }

    @tool[description: "Manage Feishu sheets. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_sheet(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_sheet", shortMessage: action)
        feishuOapiInvokeByTool("feishu_sheet", action, params_json, account_id)
    }

    @tool[description: "Search or inspect Feishu chats. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_chat(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_chat", shortMessage: action)
        feishuOapiInvokeByTool("feishu_chat", action, params_json, account_id)
    }

    @tool[description: "List or inspect Feishu chat members. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_chat_members(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_chat_members", shortMessage: action)
        feishuOapiInvokeByTool("feishu_chat_members", action, params_json, account_id)
    }

    @tool[description: "Get Feishu user information. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_get_user(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_get_user", shortMessage: action)
        feishuOapiInvokeByTool("feishu_get_user", action, params_json, account_id)
    }

    @tool[description: "Search Feishu users. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_search_user(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_search_user", shortMessage: action)
        feishuOapiInvokeByTool("feishu_search_user", action, params_json, account_id)
    }

    @tool[description: "Send or reply to Feishu IM messages as a user. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_im_user_message(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_message", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_user_message", action, params_json, account_id)
    }

    @tool[description: "Get Feishu IM messages as a user. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_im_user_get_messages(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_get_messages", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_user_get_messages", action, params_json, account_id)
    }

    @tool[description: "Get Feishu thread messages as a user. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_im_user_get_thread_messages(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_get_thread_messages", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_user_get_thread_messages", action, params_json, account_id)
    }

    @tool[description: "Search Feishu IM messages as a user. Placeholder returns structured auth/scope diagnostics and is policy-filterable by the concrete tool name."]
    public func feishu_im_user_search_messages(action: String, params_json: Option<String>, account_id: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_search_messages", shortMessage: action)
        feishuOapiInvokeByTool("feishu_im_user_search_messages", action, params_json, account_id)
    }
}
