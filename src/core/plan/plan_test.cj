package metis.core.plan

import std.env.setVariable
import std.unittest.testmacro.*
import std.unittest.*
import std.collection.ArrayList

/**
 * TavilyTool test cases
 */
@Test
public class TaskTest {
    @TestCase
    public func testcase1(): Unit {
        let task = Task("This is a test task", "Task 1", 0)
        println(task.toString())
    }

    @TestCase
    public func testcase2(): Unit {
        let task = Task("This is a test task", "Task 1", 0)
        task.addSubtask("This is subtask 1")
        task.addSubtask("This is subtask 2")
        println(task.toString())
    }

    @TestCase
    public func testcase3(): Unit {
        let task = Task("This is a test task", "Task 1", 0)
        task.addSubtask("This is subtask 1")
        task.addSubtask("This is subtask 2")
        task.subtasks[1].addSubtask("This is subsubtask 1")
        task.subtasks[1].addSubtask("This is subsubtask 1")
        task.subtasks[1].subtasks[0].addSubtask("This is sub-subtask 1")
        println("===== Task Hierarchy =====")
        println(task.toString())
        println("===== Subtask2 Hierarchy =====")
        println(task.subtasks[1].toString())
    }

    @TestCase
    public func testcase4(): Unit {
        let markdown = """
- [ ] Task 1 :: This is a test task
    - [x] Task 1.1 :: This is subtask 1
    - [ ] Task 1.2 :: This is subtask 2
        - [x] Task 1.2.1 :: This is sub-subtask 1
        - [x] Task 1.2.2 :: This is sub-subtask 1
            - [x] Task 1.2.2.1 :: This is sub-subtask 1
        - [ ] Task 1.2.3 :: This is sub-subtask 1
            - [ ] Task 1.2.3.1 :: This is sub-subtask 1
            - [ ] Task 1.2.3.2 :: This is sub-subtask 1
    - [ ] Task 1.3 :: This is subtask 3
"""
        let lines = ArrayList<String>(markdown.split("\n"))
        for (line0 in lines) {
            let line = line0.trimAscii()
            if (line.isEmpty()) {
                continue
            }
            let task = Task.parseTask(line)
            println(task)
        }
    }

    @TestCase
    public func testcase5(): Unit {
        @Expect(Task.checkTaskIdFormat("Task 1"), true)
        @Expect(Task.checkTaskIdFormat(""), false)
        @Expect(Task.checkTaskIdFormat("task1"), false)
        @Expect(Task.checkTaskIdFormat("Task1"), false)
        @Expect(Task.checkTaskIdFormat("Task"), false)
        @Expect(Task.checkTaskIdFormat("1"), false)
        @Expect(Task.checkTaskIdFormat("Task 1.2.3"), true)
        @Expect(Task.checkTaskIdFormat("Task 1.2."), false)
        @Expect(Task.checkTaskIdFormat("Task 1.2.3.4"), true)
        @Expect(Task.checkTaskIdFormat("Task 1.2-3.4"), false)
    }
}


@Test
public class PlanTest {
    var plan = Plan(["test task 1", "test task 2"])

    @BeforeAll
    public func setup(): Unit {
        let task = plan.topLevelTasks[0]
        task.addSubtask("This is subtask 1")
        task.addSubtask("This is subtask 2")
        task.subtasks[0].markAsComplete()
        task.subtasks[1].markAsComplete()
        task.markAsComplete()


        let task2 = plan.topLevelTasks[1]
        task2.addSubtask("This is subtask 1")
        task2.addSubtask("This is subtask 2")
        task2.subtasks[1].addSubtask("This is subsubtask 1")
        task2.subtasks[1].addSubtask("This is subsubtask 2")
        task2.subtasks[1].subtasks[0].addSubtask("This is nested subtask")
    }

    @TestCase
    public func testcase1(): Unit {
        plan.addTask("This is a new task")
        plan.addTask("This is another new task", parentTaskId: "Task 2.1")
        println(plan)
    }


    @TestCase
    public func testcase2(): Unit {
        println("===== Plan saved =====")
        plan.save()
        let newPlan = Plan.load()
        println("===== Loaded Plan =====")
        println(newPlan)
    }
}
