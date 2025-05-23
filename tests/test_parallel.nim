import unittest
import ../src/nim_libaspects/[parallel, errors]
import std/[os, tables, sets, strformat, strutils]

suite "Parallel Module Tests":
  
  test "Task ID operations":
    let id1 = newTaskId("task1")
    let id2 = newTaskId("task1")
    let id3 = newTaskId("task2")
    
    check id1 == id2
    check id1 != id3
    check $id1 == "task1"
    check hash(id1) == hash(id2)
    check hash(id1) != hash(id3)
  
  test "Task spec creation":
    let spec = newTaskSpec(
      id = "test-task",
      name = "Test Task",
      priority = tpHigh,
      category = tcCPU,
      dependencies = @["dep1", "dep2"],
      maxRetries = 3,
      retryDelay = 2.0,
      timeout = 30.0,
      tags = @["tag1", "tag2"],
      metadata = {"key": "value"}.toTable
    )
    
    check spec.id == newTaskId("test-task")
    check spec.name == "Test Task"
    check spec.priority == tpHigh
    check spec.category == tcCPU
    check spec.dependencies.len == 2
    check spec.dependencies[0] == newTaskId("dep1")
    check spec.maxRetries == 3
    check spec.retryDelay == 2.0
    check spec.timeout == 30.0
    check "tag1" in spec.tags
    check "tag2" in spec.tags
    check spec.metadata["key"] == "value"
  
  test "Default task spec":
    let spec = newTaskSpec("simple-task")
    
    check spec.id == newTaskId("simple-task")
    check spec.name == "simple-task"
    check spec.priority == tpNormal
    check spec.category == tcGeneral
    check spec.dependencies.len == 0
    check spec.maxRetries == 0
    check spec.retryDelay == 1.0
    check spec.timeout == 0.0
    check spec.tags.len == 0
    check spec.metadata.len == 0
  
  test "Executor creation":
    let config = defaultExecutorConfig()
    let executor = newParallelExecutor(config)
    
    check executor.config.workerCount > 0
    check executor.config.queueSize == 1000
    check executor.config.maxLoadFactor == 0.9
    check executor.config.enableRetries == true
    check executor.config.enableDependencies == true
    check executor.config.enablePriorities == true
    check not executor.isRunning()
  
  test "Add task to executor":
    let executor = newParallelExecutor()
    let spec = newTaskSpec("task1", name = "First Task")
    
    proc testTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Success")
    
    let result = executor.addTask(spec, testTask)
    check result.isOk
    
    # Try to add duplicate
    let result2 = executor.addTask(spec, testTask)
    check result2.isErr
    check result2.error.msg.contains("already exists")
  
  test "Simple task execution":
    let executor = newParallelExecutor()
    var executed = false
    
    proc simpleTask(): Result[string, ref AppError] {.thread.} =
      executed = true
      Result[string, ref AppError].ok("Task completed")
    
    let spec = newTaskSpec("simple-task")
    check executor.addTask(spec, simpleTask).isOk
    
    let stats = executor.runUntilComplete()
    
    # Since we're using threads, we should check the result instead
    let taskResult = executor.getTaskResult(newTaskId("simple-task"))
    check taskResult.isOk
    check taskResult.get().status == tsCompleted
    check taskResult.get().output == "Task completed"
    check stats.tasksCompleted == 1
    check stats.tasksFailed == 0
  
  test "Task with failure":
    let executor = newParallelExecutor()
    
    proc failingTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].err(newAppError(ecInternalError, "Task failed"))
    
    let spec = newTaskSpec("failing-task")
    check executor.addTask(spec, failingTask).isOk
    
    let stats = executor.runUntilComplete()
    
    let taskResult = executor.getTaskResult(newTaskId("failing-task"))
    check taskResult.isOk
    check taskResult.get().status == tsFailed
    check taskResult.get().error == "Task failed"
    check stats.tasksFailed == 1
    check stats.tasksCompleted == 0
  
  test "Task with dependencies":
    let executor = newParallelExecutor()
    
    proc task1(): Result[string, ref AppError] {.thread.} =
      sleep(10)  # Small delay to ensure ordering
      Result[string, ref AppError].ok("Task 1 done")
    
    proc task2(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Task 2 done")
    
    # Task 2 depends on Task 1
    let spec1 = newTaskSpec("task1")
    let spec2 = newTaskSpec("task2", dependencies = @["task1"])
    
    check executor.addTask(spec1, task1).isOk
    check executor.addTask(spec2, task2).isOk
    
    let stats = executor.runUntilComplete()
    
    check stats.tasksCompleted == 2
    check stats.tasksFailed == 0
    
    # Check results
    let result1 = executor.getTaskResult(newTaskId("task1"))
    let result2 = executor.getTaskResult(newTaskId("task2"))
    
    check result1.isOk
    check result1.get().status == tsCompleted
    check result2.isOk
    check result2.get().status == tsCompleted
  
  test "Failed dependency skips dependent task":
    let executor = newParallelExecutor()
    
    proc failingTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].err(newAppError(ecInternalError, "Dependency failed"))
    
    proc dependentTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Should not run")
    
    let spec1 = newTaskSpec("failing-dep")
    let spec2 = newTaskSpec("dependent", dependencies = @["failing-dep"])
    
    check executor.addTask(spec1, failingTask).isOk
    check executor.addTask(spec2, dependentTask).isOk
    
    let stats = executor.runUntilComplete()
    
    check stats.tasksFailed == 1
    check stats.tasksSkipped == 1
    check stats.tasksCompleted == 0
    
    let status2 = executor.getTaskStatus(newTaskId("dependent"))
    check status2.isOk
    check status2.get() == tsSkipped
  
  test "Priority scheduling":
    let executor = newParallelExecutor()
    
    proc lowTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("low done")
    
    proc normalTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("normal done")
    
    proc highTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("high done")
    
    # Add tasks with different priorities
    let highSpec = newTaskSpec("high", priority = tpHigh)
    let normalSpec = newTaskSpec("normal", priority = tpNormal)
    let lowSpec = newTaskSpec("low", priority = tpLow)
    
    check executor.addTask(lowSpec, lowTask).isOk
    check executor.addTask(normalSpec, normalTask).isOk
    check executor.addTask(highSpec, highTask).isOk
    
    let stats = executor.runUntilComplete()
    
    check stats.tasksCompleted == 3
    # Due to threading, exact order isn't guaranteed but priorities should be respected
  
  test "Cancel task":
    let executor = newParallelExecutor()
    
    proc longTask(): Result[string, ref AppError] {.thread.} =
      sleep(1000)  # Long running task
      Result[string, ref AppError].ok("Should not complete")
    
    let spec = newTaskSpec("long-task")
    check executor.addTask(spec, longTask).isOk
    
    # Cancel before execution
    let cancelResult = executor.cancelTask(newTaskId("long-task"))
    check cancelResult.isOk
    
    let stats = executor.runUntilComplete()
    
    check stats.tasksCancelled == 1
    check stats.tasksCompleted == 0
  
  test "Task status queries":
    let executor = newParallelExecutor()
    
    proc task(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Done")
    
    let spec = newTaskSpec("query-task")
    check executor.addTask(spec, task).isOk
    
    # Check initial status
    let status1 = executor.getTaskStatus(newTaskId("query-task"))
    check status1.isOk
    check status1.get() == tsPending
    
    # Run and check final status
    discard executor.runUntilComplete()
    
    let status2 = executor.getTaskStatus(newTaskId("query-task"))
    check status2.isOk
    check status2.get() == tsCompleted
    
    # Check non-existent task
    let status3 = executor.getTaskStatus(newTaskId("non-existent"))
    check status3.isErr
    check status3.error.msg.contains("not found")
  
  test "Statistics collection":
    let executor = newParallelExecutor()
    
    proc quickTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Quick")
    
    proc failTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].err(newAppError(ecInternalError, "Failed"))
    
    # Add multiple tasks
    for i in 1..5:
      let spec = newTaskSpec(fmt"task-{i}")
      if i mod 2 == 0:
        check executor.addTask(spec, failTask).isOk
      else:
        check executor.addTask(spec, quickTask).isOk
    
    let stats = executor.runUntilComplete()
    
    check stats.tasksSubmitted == 5
    check stats.tasksCompleted == 3
    check stats.tasksFailed == 2
    check stats.totalDuration > 0
    check stats.avgTaskDuration >= 0
  
  test "Convenience function runParallel":
    # Create tasks
    proc task1(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Task 1 done")
    
    proc task2(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Task 2 done")
    
    proc task3(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Task 3 done")
    
    proc task4(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Task 4 done")
    
    proc task5(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Task 5 done")
    
    var tasks: seq[tuple[id: string, taskProc: TaskProc]] = @[
      ("task-1", task1),
      ("task-2", task2),
      ("task-3", task3),
      ("task-4", task4),
      ("task-5", task5)
    ]
    
    let taskResults = runParallel(tasks)
    
    check taskResults.len == 5
    for r in taskResults:
      check r.status == tsCompleted
      check r.output.contains("done")
  
  test "Exception handling in tasks":
    let executor = newParallelExecutor()
    
    proc exceptionTask(): Result[string, ref AppError] {.thread.} =
      raise newException(ValueError, "Test exception")
    
    let spec = newTaskSpec("exception-task")
    check executor.addTask(spec, exceptionTask).isOk
    
    let stats = executor.runUntilComplete()
    
    check stats.tasksFailed == 1
    
    let result = executor.getTaskResult(newTaskId("exception-task"))
    check result.isOk
    check result.get().status == tsFailed
    check result.get().error.contains("Test exception")
  
  test "Complex dependency graph":
    let executor = newParallelExecutor()
    
    proc taskA(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("A done")
    
    proc taskB(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("B done")
    
    proc taskC(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("C done")
    
    proc taskD(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("D done")
    
    # Create a diamond dependency graph:
    #     A
    #    / \
    #   B   C
    #    \ /
    #     D
    
    let specA = newTaskSpec("A")
    let specB = newTaskSpec("B", dependencies = @["A"])
    let specC = newTaskSpec("C", dependencies = @["A"])
    let specD = newTaskSpec("D", dependencies = @["B", "C"])
    
    check executor.addTask(specA, taskA).isOk
    check executor.addTask(specB, taskB).isOk
    check executor.addTask(specC, taskC).isOk
    check executor.addTask(specD, taskD).isOk
    
    let stats = executor.runUntilComplete()
    
    check stats.tasksCompleted == 4
    check stats.tasksFailed == 0
    
    # Verify all completed
    for taskId in ["A", "B", "C", "D"]:
      let result = executor.getTaskResult(newTaskId(taskId))
      check result.isOk
      check result.get().status == tsCompleted