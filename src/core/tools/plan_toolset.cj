package metis.core.tools

import magic.dsl.*
import magic.dsl.{jsonable, field}
import magic.prelude.*
import magic.log.LogUtils

import metis.core.plan.{ Plan, Task }
import metis.core.config.CliConfig
import metis.io.{InputUtils, PrintUtils, Confirmation, WithColor, AnsiColor, Theme}
import metis.utils.*

import std.collection.*
import std.fs.*

@jsonable
public class UpdatePlanStepParam {
    @field["Short plan step."]
    protected let step: String

    @field["One of \"pending\", \"in_progress\", or \"completed\"."]
    protected let status: String
}


@toolset
public class PlanToolset {
    private var plan = Plan.load()

    private func normalizeUpdatePlanStatus(status: String): String {
        let normalized = status.trimAscii().toAsciiLower()
        if (normalized == "pending" || normalized == "in_progress" || normalized == "completed") {
            return normalized
        }
        return ""
    }

    private func rebuildPlanFromUpdatePlan(steps: Array<UpdatePlanStepParam>): String {
        if (steps.isEmpty()) {
            return "plan required"
        }

        var inProgressCount = 0
        let nextPlan = Plan()
        for (entry in steps) {
            let stepText = entry.step.trimAscii()
            if (stepText.isEmpty()) {
                return "plan step must be non-empty"
            }
            let normalizedStatus = this.normalizeUpdatePlanStatus(entry.status)
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
            if (normalizedStatus == "completed") {
                let taskId = "Task ${nextPlan.topLevelTasks.size}"
                if (let Some(task) <- nextPlan.getTask(taskId)) {
                    task.markAsComplete()
                }
            }
        }

        this.plan = nextPlan
        this.plan.save()
        PrintUtils.printPlan(this.plan)
        PrintUtils.printLine("")
        return "Plan updated."
    }

    @tool[
        description: "Creates a new task plan or overwrites an existing plan with a new one. This is the first step to start complex tasks.",
        parameters: { tasks: "An array of strings, each item is a clear subtask description" }
    ]
    public func todoCreate(tasks: Array<String>): String {
        this.plan = Plan(tasks)
        if (InputUtils.confirm(this.plan) == Confirmation.Deny) {
            return "User denied the plan"
        }
        this.plan.save()
        return "Plan has been approved by user, ready to start execution. The following tasks are created:\n${plan.toString()}"
    }

    @tool[
        description: "Breaks down a parent task into clear and actionable subtasks.",
        parameters: {
            todoId: "Id of the parent task that needs to be broken down into subtasks",
            subtasks: "An array of strings, each item is a clear description of the subtask broken down from the parent task" 
        }
    ]
    public func taskBreakDown(taskId: String, subtasks: Array<String>): String {
        let parentTask: ?Task = this.plan.getTask(taskId)
        if (parentTask.isNone()) {
            return "Error: task with the task id ${taskId} is not found. Please check whether the todoId is correct."
        }
        for (subtask in subtasks) {
            this.plan.addSubtask(subtask, taskId)
        }
        if (InputUtils.confirm(parentTask.getOrThrow()) == Confirmation.Deny) {
            parentTask.getOrThrow().clearSubtasks()
            return "User denied the subtasks"
        }
        this.plan.save()
        return "Subtasks has been approved by user, ready to start execution. The current plan is in the following:\n${plan.toString()}"
    }

    @tool[
        description: "Review the current plan, the completion status (TODO/DONE), and the task id of each task."
    ]
    public func todoReview(): String {
        if (this.plan.isEmpty()) {
            return "No current plan."
        }
        return "Current Plan:\n${this.plan}"
    }

    @tool[
        description: "Marks the task with the specific task id as completed (DONE) and returns the current TODO List. If the task is the last subtask of the parent task, the parent task will also be marked as completed.",
        parameters: { taskId: "Id of the task to mark as complete" }
    ]
    public func taskMarkComplete(taskId: String): String {
        let tasks = plan.getPathFromRootToTask(taskId)
        if (tasks.isNone()) {
            return "Error: cannot find the task with task id ${taskId}. Please check whether this task id exists in the plan."
        }
        let currentTask = tasks.getOrThrow()[tasks.getOrThrow().size - 1]
        if (currentTask.completed) {
            return "Task ${taskId} is already completed."
        }
        for (i in 0..tasks.getOrThrow().size) {
            let task = tasks.getOrThrow()[tasks.getOrThrow().size - 1 - i]
            task.markAsComplete()
            var parentTaskComplete = true
            if (i != tasks.getOrThrow().size - 1) {
                let parentTask = tasks.getOrThrow()[tasks.getOrThrow().size - 2 - i]
                for (task in parentTask.subtasks) {
                    if (!task.completed) {
                        parentTaskComplete = false
                        break
                    }
                }
                if (!parentTaskComplete) {
                    break
                }
                parentTask.markAsComplete()
            }
        }
        plan.save()
        PrintUtils.printPlan(this.plan)
        PrintUtils.printLine("")
        return "Task ${taskId} has been completed. Current task list:\n${this.plan}"
    }

    @tool[
        description: "Track a short structured work plan. Replaces the current top-level plan with an ordered list of steps using statuses pending, in_progress, or completed. At most one step may be in_progress.",
        parameters: {
            explanation: "Optional short note explaining what changed in the plan.",
            plan: "Ordered array of JSON objects, each with step and status."
        }
    ]
    public func update_plan(explanation: Option<String>, plan: Array<UpdatePlanStepParam>): String {
        let result = this.rebuildPlanFromUpdatePlan(plan)
        if (result != "Plan updated.") {
            return result
        }
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
