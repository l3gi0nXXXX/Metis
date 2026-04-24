package metis.core.plan

import magic.log.LogUtils
import metis.core.config.CliConfig

import std.collection.ArrayList
import std.fs.{File, OpenMode, FSException, exists}
import std.convert.*

/**
* Task Id of each task is in the The `taskId` is in the following format: `Task l1.l2...ln`, where `l1` is the 1-based index of the
* top-level task in the overall task list, `l2` is the 1-based index of the second-level subtask within its parent task, and 
* so on. For example, `Task 2.3.1` refers to the first subtask of the third subtask of the second top-level task.
*/

const INDENT = 2

/**
 * A plan represents a list of tasks to be completed.
 */
protected class Plan <: ToString {
    protected let topLevelTasks: ArrayList<Task>

    protected init() {
        this.topLevelTasks = ArrayList<Task>()
    }

    protected init(tasks: Array<String>) {
        this.topLevelTasks = ArrayList<Task>()
        for (task in tasks) { 
            this.addTopLevelTask(task)
        }
    }

    protected init(tasks: ArrayList<String>) {
        this.topLevelTasks = ArrayList<Task>()
        for (task in tasks) { 
            this.addTopLevelTask(task)
        }
    }

    private init(tasks: ArrayList<Task>) {
        // Because taskId of each task has a specific format and we cannot assume each input format is correct,
        // we make this constructor private
        this.topLevelTasks = tasks
    }

    private init(tasks: Array<Task>) {
        // Because taskId of each task has a specific format and we cannot assume each input format is correct,
        // we make this constructor private
        this.topLevelTasks = ArrayList<Task>(tasks)
    }

    public func addTopLevelTask(task: String): Bool {
        let task_id = "Task " + (this.topLevelTasks.size + 1).toString()
        let newTask = Task(task, task_id, 0)
        this.topLevelTasks.add(newTask)
        return true
    }

    public func addSubtask(subtask: String, parentTaskId: String): Bool {
        if (let Some(task) <- getTask(parentTaskId)) {
            task.addSubtask(subtask)
            return true
        }
        return false
    }

    public func addTask(task: String, parentTaskId!: String = ""): Bool {
        if (parentTaskId.isEmpty()) {
            return this.addTopLevelTask(task)
        }
        return this.addSubtask(task, parentTaskId)
    }

    public func getTask(taskId: String): ?Task {
        if (!Task.checkTaskIdFormat(taskId)) {
            return None
        }
        let indices = taskId.split(" ")[1].split(".")
        var task: ?Task = None
        var tasks = this.topLevelTasks
        for (i in indices) { 
            let index = Int64.parse(i) - 1
            if (index < 0 || index >= tasks.size) {
                return None
            }
            task = tasks[index]
            tasks = task.getOrThrow().subtasks
        }
        
        return task
    }

    public func isEmpty(): Bool {
        return this.topLevelTasks.isEmpty()
    }

    override public func toString(): String {
        var rsts = ""
        for (task in this.topLevelTasks) {
            rsts += task.toString()
        }
        rsts = rsts.trimAscii()
        return rsts
    }

    public func getPathFromRootToTask(taskId: String): ?ArrayList<Task> {
        if (!Task.checkTaskIdFormat(taskId)) {
            return None
        }
        let indices = taskId.split(" ")[1].split(".")
        var tasks = this.topLevelTasks
        let path = ArrayList<Task>()
        for (i in indices) { 
            let index = Int64.parse(i) - 1
            if (index < 0 || index >= tasks.size) {
                return None
            }
            path.add(tasks[index])
            tasks = tasks[index].subtasks
        }
        return path
    }

    public func save(): Unit {
        let path = CliConfig.todoFile
        try {
            let file = File(path, OpenMode.Write)
            file.write(this.toString().toArray())
            file.close()
        } catch(e: Exception) {
            LogUtils.error("Error: Unable to save plan file to ${path}. Details: ${e}")
        }
    }

    public static func load(): Plan {
        if (!exists(CliConfig.todoFile)) {
            return Plan()
        }
        var content = try {
            String.fromUtf8(File.readFrom(CliConfig.todoFile))
        } catch (e: FSException) {
            LogUtils.debug("File or directory does not exist or is not accessible")
            return Plan()
        }
        content = content.trimAscii()
        let splitLines = content.split("\n")
        var topLevelTasks = ArrayList<Task>()
        for (line in splitLines) {
            if (line.trimAscii().isEmpty()) {
                continue
            }
            let task = try {
                Task.parseTask(line)
            } catch (e: Exception) {
                LogUtils.error("Error parsing task line: ${line}. Details: ${e}")
                continue
            }
            // tasks.add(task)
            let indices = task.taskId.split(" ")[1].split(".")
            var tasks = topLevelTasks
            var breakFlag = false
            for (i in indices[..indices.size - 1]) {
                let index = Int64.parse(i) - 1
                if (index < 0 || index >= tasks.size) {
                    LogUtils.error("Error adding subtask: parent task does not exist for line: ${line}")
                    breakFlag = true
                    break
                }
                let parentTask = tasks[index]
                tasks = parentTask.subtasks
            }
            if (breakFlag) {
                continue
            }
            tasks.add(task)
        }
        return Plan(topLevelTasks)
    }
}

protected class Task <: ToString {
    protected let description: String
    protected let taskId: String
    protected let subtasks: ArrayList<Task>
    protected var completed: Bool
    protected let level: Int64

    public init(description: String, taskId: String, level: Int64) {
        this.description = description
        this.taskId = taskId
        this.subtasks = ArrayList<Task>()
        this.completed = false
        this.level = level
    }

    public init(description: String, taskId: String, subtasks: ArrayList<Task>, level: Int64) {
        this.description = description
        this.taskId = taskId
        this.subtasks = subtasks
        this.completed = false
        this.level = level
    }

    public func addSubtask(description: String): Unit {
        let subtaskId = this.taskId + "." + "${this.subtasks.size + 1}"
        this.subtasks.add(Task(description, subtaskId, this.level + 1))
    }

    public func markAsComplete(): Unit {
        this.completed = true
    }

    public func clearSubtasks(): Unit {
        subtasks.clear()
    }

    override public func toString(): String {
        return toStringRecursively()
    }

    private func toStringRecursively(): String {
        let descriptionCombo = this.taskId + " :: " + this.description
        var plainStr = " " * this.level * INDENT
        if (this.completed) {
            plainStr += "- [x] ${descriptionCombo}\n"
        } else {
            plainStr += "- [ ] ${descriptionCombo}\n"
        }
        for (subtask in this.subtasks) {
            plainStr += subtask.toStringRecursively()
        }
        return plainStr
    }

    public static func checkTaskIdFormat(taskId: String): Bool {
        // Check taskId format, should be "Task X.Y.Z" and X.Y.Z are 1-indexed
        if (taskId.isEmpty()) {
            return false
        }
        
        if (!taskId.startsWith("Task ")) {
            return false
        }
        
        let parts = taskId.split(" ")
        if (parts.size != 2) {
            return false
        }
        
        let indices = parts[1].split(".")
        for (idx in indices) {
            // Check if the index is a valid integer
            if (Int64.tryParse(idx).isNone()) {
                return false
            }
            // Check if the index is greater than 0 (1-indexed)
            if (Int64.parse(idx) <= 0) {
                return false
            }
        }
        return true
    }

    public static func parseTask(line: String): Task {
        // Line after trimming must be in this format: "- [ ] <taskId> :: <description>"
        let trimmedLine = line.trimAscii()
        if (!trimmedLine.startsWith("- [ ]") && !trimmedLine.startsWith("- [x]")) {
            throw Exception("Invalid task line format. Not starts with - [ ] or - [x]")
        }
        if (!trimmedLine.contains(" :: ")) {
            throw Exception("Invalid task line format. No \" :: \" found")
        }
        let rawDescription = trimmedLine[5..].trimAscii().split(" :: ")
        let taskId = rawDescription[0]
        if (!Task.checkTaskIdFormat(taskId)) {
            throw Exception("Invalid task ID format: ${taskId}")
        }
        let level = taskId.split(" ")[1].split(".").size - 1
        let description = String.join(rawDescription[1..], delimiter: " :: ")
        let task = Task(description, taskId, level)
        if (trimmedLine.startsWith("- [x]")) {
            task.markAsComplete()
        }
        return task
    }
}
