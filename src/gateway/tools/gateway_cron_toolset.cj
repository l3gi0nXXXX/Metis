package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.cron.executeGatewayCronCommand
import metis.io.PrintUtils

import std.collection.ArrayList
import stdx.encoding.json.{JsonObject, JsonString}

@toolset
public class GatewayCronToolset {
    private func normalizeAction(action: String): String {
        let normalized = action.trimAscii().toAsciiLower()
        if (
            normalized == "help" ||
            normalized == "path" ||
            normalized == "status" ||
            normalized == "list" ||
            normalized == "add" ||
            normalized == "update" ||
            normalized == "remove" ||
            normalized == "enable" ||
            normalized == "disable" ||
            normalized == "run" ||
            normalized == "runs" ||
            normalized == "wake"
        ) {
            return normalized
        }
        ""
    }

    @tool[
        description: "Operate gateway cron jobs through the unified Gateway cron backend. Supported actions: help, path, status, list, add, update, remove, enable, disable, run, runs, wake.",
        parameters: {
            action: "Cron action.",
            id: "Optional cron job id.",
            name: "Optional cron job name for add/update.",
            message: "Optional message/prompt text for add/update/wake.",
            every: "Optional interval schedule for add, e.g. 10m.",
            at: "Optional absolute timestamp for add.",
            cronExpr: "Optional cron expression for add/update.",
            enabled: "Optional enabled flag for update.",
            dueOnly: "Optional due_only flag for run.",
            mode: "Optional wake mode.",
            text: "Optional wake text."
        }
    ]
    public func cron(
        action: String,
        id: Option<String>,
        name: Option<String>,
        message: Option<String>,
        every: Option<String>,
        at: Option<String>,
        cronExpr: Option<String>,
        enabled: Option<Bool>,
        dueOnly: Option<Bool>,
        mode: Option<String>,
        text: Option<String>
    ): String {
        let act = this.normalizeAction(action)
        PrintUtils.printTool("cron", shortMessage: if (act.isEmpty()) { "help" } else { act })

        let args = ArrayList<String>(["cron"])
        if (act.isEmpty() || act == "help") {
            args.add("help")
        } else if (act == "path" || act == "list" || act == "status") {
            args.add(act)
        } else if (act == "add") {
            let jobName = match (name) { case Some(v) => v.trimAscii() case None => "" }
            let msg = match (message) { case Some(v) => v.trimAscii() case None => "" }
            if (jobName.isEmpty() || msg.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("action", JsonString("add"))
                err.put("status", JsonString("error"))
                err.put("error", JsonString("add requires name and message"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            args.add("add")
            args.add("--name")
            args.add(jobName)
            args.add("--message")
            args.add(msg)
            match (every) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--every")
                        args.add(t)
                    }
                case None => ()
            }
            match (at) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--at")
                        args.add(t)
                    }
                case None => ()
            }
            match (cronExpr) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--cron")
                        args.add(t)
                    }
                case None => ()
            }
        } else if (act == "update") {
            let resolvedId = match (id) { case Some(v) => v.trimAscii() case None => "" }
            if (resolvedId.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("action", JsonString("update"))
                err.put("status", JsonString("error"))
                err.put("error", JsonString("update requires id"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            args.add("update")
            args.add("--job-id")
            args.add(resolvedId)
            match (name) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--name")
                        args.add(t)
                    }
                case None => ()
            }
            match (message) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--message")
                        args.add(t)
                    }
                case None => ()
            }
            match (every) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--every")
                        args.add(t)
                    }
                case None => ()
            }
            match (at) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--at")
                        args.add(t)
                    }
                case None => ()
            }
            match (cronExpr) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--cron")
                        args.add(t)
                    }
                case None => ()
            }
            match (enabled) {
                case Some(v) => args.add(if (v) { "--enable" } else { "--disable" })
                case None => ()
            }
        } else if (act == "remove" || act == "enable" || act == "disable" || act == "run" || act == "runs" || act == "wake") {
            let resolvedId = match (id) { case Some(v) => v.trimAscii() case None => "" }
            if ((act == "remove" || act == "enable" || act == "disable" || act == "run" || act == "runs" || act == "wake") && resolvedId.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("action", JsonString(act))
                err.put("status", JsonString("error"))
                err.put("error", JsonString("${act} requires id"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            args.add(act)
            args.add("--job-id")
            args.add(resolvedId)
            if (act == "run") {
                if (dueOnly ?? false) {
                    args.add("--due-only")
                }
            }
            if (act == "wake") {
                match (mode) {
                    case Some(v) =>
                        let t = v.trimAscii()
                        if (!t.isEmpty()) {
                            args.add("--mode")
                            args.add(t)
                        }
                    case None => ()
                }
                match (text) {
                    case Some(v) =>
                        let t = v.trimAscii()
                        if (!t.isEmpty()) {
                            args.add("--text")
                            args.add(t)
                        }
                    case None => ()
                }
            }
        }

        // The unified gateway runtime registers the cron run hook during service setup,
        // so the tool only needs the shared cron command entrypoint here.
        let (msg, code) = executeGatewayCronCommand(args.toArray())
        let result = JsonObject()
        result.put("ok", (code == 0).toJsonValue())
        result.put("action", JsonString(if (act.isEmpty()) { "help" } else { act }))
        result.put("status", JsonString(if (code == 0) { "ok" } else { "error" }))
        result.put("exitCode", code.toJsonValue())
        result.put("output", JsonString(msg))
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }
}
