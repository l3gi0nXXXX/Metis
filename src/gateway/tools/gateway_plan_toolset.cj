package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.dsl.{jsonable, field}
import magic.prelude.*

import metis.core.plan.Plan
import metis.io.PrintUtils

@jsonable
public class GatewayUpdatePlanStepParam {
    @field["Short plan step."]
    protected let step: String

    @field["One of \"pending\", \"in_progress\", or \"completed\"."]
    protected let status: String
}

@toolset
public class GatewayPlanToolset {
    private var plan = Plan.load()

    private func normalizeStatus(status: String): String {
        let normalized = status.trimAscii().toAsciiLower()
        if (normalized == "pending" || normalized == "in_progress" || normalized == "completed") {
            return normalized
        }
        ""
    }

    @tool[
        description: "Review the current plan, including task ids and completion state."
    ]
    public func todoReview(): String {
        if (this.plan.isEmpty()) {
            return "No current plan."
        }
        return "Current Plan:\n${this.plan}"
    }

    @tool[
        description: "Track a short structured work plan. Replaces the current top-level plan with an ordered list of steps using statuses pending, in_progress, or completed.",
        parameters: {
            explanation: "Optional short note explaining what changed in the plan.",
            plan: "Ordered array of JSON objects, each with step and status."
        }
    ]
    public func update_plan(explanation: Option<String>, plan: Array<GatewayUpdatePlanStepParam>): String {
        if (plan.isEmpty()) {
            return "plan required"
        }
        var inProgressCount = 0
        var addedSteps: Int64 = 0
        let nextPlan = Plan()
        for (entry in plan) {
            let stepText = entry.step.trimAscii()
            if (stepText.isEmpty()) {
                return "plan step must be non-empty"
            }
            let normalizedStatus = this.normalizeStatus(entry.status)
            if (normalizedStatus.isEmpty()) {
                return "plan status must be one of pending, in_progress, completed"
            }
            if (normalizedStatus == "in_progress") {
                inProgressCount += 1
                if (inProgressCount > 1) {
                    return "plan can contain at most one in_progress step"
                }
            }
            nextPlan.addTopLevelTask(stepText)
            addedSteps += 1
            if (normalizedStatus == "completed") {
                let taskId = "Task ${addedSteps}"
                if (let Some(task) <- nextPlan.getTask(taskId)) {
                    task.markAsComplete()
                }
            }
        }

        this.plan = nextPlan
        this.plan.save()
        PrintUtils.printPlan(this.plan)
        PrintUtils.printLine("")
        let note = match (explanation) {
            case Some(text) =>
                let trimmed = text.trimAscii()
                if (trimmed.isEmpty()) {
                    ""
                } else {
                    "\nExplanation: ${trimmed}"
                }
            case None => ""
        }
        return "Plan updated.${note}\nCurrent plan:\n${this.plan}"
    }
}
