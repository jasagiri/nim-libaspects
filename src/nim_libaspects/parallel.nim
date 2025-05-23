## Parallel execution module for nim-libs
## Provides unified parallel task execution with dependency management

import std/[cpuinfo, deques, os, strformat, tables, threadpool, locks, algorithm, times, options, sets, sequtils, hashes, json]
import ./errors
import ./logging

export threadpool, sets, tables, options

# Module logger
# Module logger disabled until needed
# let parallelLogger = newLogger("parallel")

type
  TaskId* = distinct string
    ## Unique identifier for a task
  
  TaskPriority* = enum
    ## Priority levels for task scheduling
    tpLow = 0
    tpNormal = 10
    tpHigh = 20
    tpCritical = 30
  
  TaskStatus* = enum
    ## Status of a task during execution
    tsPending    # Task is waiting to be executed
    tsRunning    # Task is currently running
    tsCompleted  # Task completed successfully
    tsFailed     # Task failed with error
    tsCancelled  # Task was cancelled
    tsSkipped    # Task was skipped (e.g., failed dependency)
  
  TaskCategory* = enum
    ## Task categories for grouping and scheduling
    tcGeneral     # General purpose task
    tcCPU         # CPU-intensive task
    tcIO          # I/O-bound task
    tcNetwork     # Network-dependent task
    tcMemory      # Memory-intensive task
  
  DependencyError* = object of AppError
    ## Error for dependency-related issues
  
  CancellationError* = object of AppError
    ## Error for task cancellation
  
  ParallelError* = object of AppError
    ## General parallel execution error
  
  TaskResult* = object
    ## Result of a task execution
    taskId*: TaskId            # Task identifier
    status*: TaskStatus        # Final status
    startTime*: DateTime       # When the task started
    endTime*: DateTime         # When the task ended
    duration*: float           # Duration in seconds
    output*: string            # Task output (if any)
    error*: string             # Error message (if failed)
    retryCount*: int           # Number of retry attempts
  
  TaskProc* = proc(): Result[string, ref AppError] {.thread, gcsafe.}
    ## Function type for task execution
  
  TaskSpec* = object
    ## Task specification
    id*: TaskId                      # Unique identifier
    name*: string                    # Human-readable name
    priority*: TaskPriority          # Execution priority
    category*: TaskCategory          # Task category
    dependencies*: seq[TaskId]       # Task dependencies
    maxRetries*: int                 # Maximum retry attempts
    retryDelay*: float               # Delay between retries
    timeout*: float                  # Timeout in seconds (0 = no timeout)
    tags*: HashSet[string]           # Tags for filtering
    metadata*: Table[string, string] # Additional metadata
  
  TaskInfo* = object
    ## Runtime task information
    spec*: TaskSpec               # Task specification
    taskProc*: TaskProc           # Task procedure
    status*: TaskStatus           # Current status
    attempt*: int                 # Current attempt number
    createdAt*: DateTime          # When task was created
    startedAt*: Option[DateTime]  # When task started
    completedAt*: Option[DateTime] # When task completed
    result*: Option[TaskResult]   # Execution result
  
  ExecutorConfig* = object
    ## Configuration for the parallel executor
    workerCount*: int            # Number of worker threads
    queueSize*: int              # Maximum queue size
    maxLoadFactor*: float        # Maximum system load factor (0.0-1.0)
    schedulingInterval*: float   # Interval between scheduling runs
    enableRetries*: bool         # Enable automatic retries
    enableDependencies*: bool    # Enable dependency resolution
    enablePriorities*: bool      # Enable priority scheduling
  
  ExecutorStats* = object
    ## Statistics for the executor
    tasksSubmitted*: int         # Total tasks submitted
    tasksCompleted*: int         # Tasks completed successfully
    tasksFailed*: int            # Tasks that failed
    tasksCancelled*: int         # Tasks that were cancelled
    tasksSkipped*: int           # Tasks that were skipped
    totalDuration*: float        # Total execution time
    avgTaskDuration*: float      # Average task duration
    currentLoad*: float          # Current system load
  
  ParallelExecutor* = ref object
    ## Main parallel executor
    config*: ExecutorConfig
    tasks: Table[TaskId, TaskInfo]
    taskQueue: Deque[TaskId]
    runningTasks: HashSet[TaskId]
    completedTasks: HashSet[TaskId]
    failedTasks: HashSet[TaskId]
    cancelledTasks: HashSet[TaskId]
    taskLock: Lock
    queueLock: Lock
    statsLock: Lock
    stats: ExecutorStats
    isRunning: bool
    stopRequested: bool
    logger: Logger

# Task ID helpers
proc `==`*(a, b: TaskId): bool = string(a) == string(b)
proc `$`*(id: TaskId): string = string(id)
proc hash*(id: TaskId): Hash = hash(string(id))
proc newTaskId*(id: string): TaskId = TaskId(id)

# Error constructors
proc newDependencyError*(msg: string): ref DependencyError =
  result = newException(DependencyError, msg)
  result.context = newErrorContext(ecInvalidInput, msg)

proc newCancellationError*(msg: string): ref CancellationError =
  result = newException(CancellationError, msg)
  result.context = newErrorContext(ecCancelled, msg)

proc newParallelError*(msg: string): ref ParallelError =
  result = newException(ParallelError, msg)
  result.context = newErrorContext(ecInternalError, msg)

# Default configurations
proc defaultExecutorConfig*(): ExecutorConfig =
  ## Create default executor configuration
  ExecutorConfig(
    workerCount: countProcessors(),
    queueSize: 1000,
    maxLoadFactor: 0.9,
    schedulingInterval: 0.1,
    enableRetries: true,
    enableDependencies: true,
    enablePriorities: true
  )

# Task creation
proc newTaskSpec*(
  id: string,
  name = "",
  priority = tpNormal,
  category = tcGeneral,
  dependencies: seq[string] = @[],
  maxRetries = 0,
  retryDelay = 1.0,
  timeout = 0.0,
  tags: seq[string] = @[],
  metadata: Table[string, string] = initTable[string, string]()
): TaskSpec =
  ## Create a new task specification
  result = TaskSpec(
    id: TaskId(id),
    name: if name.len > 0: name else: id,
    priority: priority,
    category: category,
    dependencies: dependencies.mapIt(TaskId(it)),
    maxRetries: maxRetries,
    retryDelay: retryDelay,
    timeout: timeout,
    tags: tags.toHashSet(),
    metadata: metadata
  )

proc newTaskInfo*(spec: TaskSpec, taskProc: TaskProc): TaskInfo =
  ## Create new task info
  TaskInfo(
    spec: spec,
    taskProc: taskProc,
    status: tsPending,
    attempt: 0,
    createdAt: now(),
    startedAt: none(DateTime),
    completedAt: none(DateTime),
    result: none(TaskResult)
  )

# Executor creation
proc newParallelExecutor*(config: ExecutorConfig = defaultExecutorConfig()): ParallelExecutor =
  ## Create a new parallel executor
  result = ParallelExecutor(
    config: config,
    tasks: initTable[TaskId, TaskInfo](),
    taskQueue: initDeque[TaskId](),
    runningTasks: initHashSet[TaskId](),
    completedTasks: initHashSet[TaskId](),
    failedTasks: initHashSet[TaskId](),
    cancelledTasks: initHashSet[TaskId](),
    stats: ExecutorStats(),
    isRunning: false,
    stopRequested: false,
    logger: newLogger("ParallelExecutor")
  )
  initLock(result.taskLock)
  initLock(result.queueLock)
  initLock(result.statsLock)

# Task management
proc addTask*(executor: ParallelExecutor, spec: TaskSpec, taskProc: TaskProc): Result[void, ref ParallelError] =
  ## Add a task to the executor
  var addResult: Result[void, ref ParallelError]
  
  withLock(executor.taskLock):
    if spec.id in executor.tasks:
      addResult = Result[void, ref ParallelError].err(
        newParallelError(fmt"Task with ID {spec.id} already exists"))
    else:
      let taskInfo = newTaskInfo(spec, taskProc)
      executor.tasks[spec.id] = taskInfo
      
      # Update stats
      withLock(executor.statsLock):
        inc executor.stats.tasksSubmitted
      
      executor.logger.debug("Added task", %*{
        "id": $spec.id,
        "name": spec.name,
        "priority": $spec.priority,
        "dependencies": spec.dependencies.mapIt($it)
      })
      
      addResult = Result[void, ref ParallelError].ok()
  
  return addResult

proc cancelTask*(executor: ParallelExecutor, taskId: TaskId): Result[void, ref ParallelError] =
  ## Cancel a task
  var cancelResult: Result[void, ref ParallelError]
  
  withLock(executor.taskLock):
    if taskId notin executor.tasks:
      cancelResult = Result[void, ref ParallelError].err(
        newParallelError(fmt"Task {taskId} not found"))
    else:
      let task = executor.tasks[taskId]
      if task.status in {tsCompleted, tsFailed, tsCancelled}:
        cancelResult = Result[void, ref ParallelError].err(
          newParallelError(fmt"Task {taskId} is already {task.status}"))
      else:
        executor.tasks[taskId].status = tsCancelled
        executor.cancelledTasks.incl(taskId)
        
        # Update stats
        withLock(executor.statsLock):
          inc executor.stats.tasksCancelled
        
        executor.logger.info("Cancelled task", %*{"id": $taskId})
        cancelResult = Result[void, ref ParallelError].ok()
  
  return cancelResult

# Dependency resolution
proc resolveDependencies(executor: ParallelExecutor): seq[TaskId] =
  ## Resolve task dependencies and return ready tasks
  var readyTasks: seq[TaskId] = @[]
  
  withLock(executor.taskLock):
    for taskId, task in executor.tasks:
      if task.status != tsPending:
        continue
      
      # Check if all dependencies are satisfied
      var allDepsComplete = true
      for depId in task.spec.dependencies:
        if depId notin executor.completedTasks:
          allDepsComplete = false
          # Check if dependency failed
          if depId in executor.failedTasks or depId in executor.cancelledTasks:
            # Skip this task as dependency failed
            executor.tasks[taskId].status = tsSkipped
            withLock(executor.statsLock):
              inc executor.stats.tasksSkipped
            executor.logger.warn("Skipping task due to failed dependency", %*{
              "task": $taskId,
              "failed_dependency": $depId
            })
            break
      
      if allDepsComplete and task.status == tsPending:
        readyTasks.add(taskId)
  
  # Sort by priority (highest first)
  readyTasks.sort do (a, b: TaskId) -> int:
    let taskA = executor.tasks[a]
    let taskB = executor.tasks[b]
    cmp(ord(taskB.spec.priority), ord(taskA.spec.priority))
  
  readyTasks

# Task execution
proc executeTask(executor: ParallelExecutor, taskId: TaskId) {.thread.} =
  ## Execute a single task (runs in worker thread)
  # Note: This is a simplified version - in production you'd want more error handling
  var task: TaskInfo
  withLock(executor.taskLock):
    if taskId notin executor.tasks:
      return
    task = executor.tasks[taskId]
  
  let startTime = now()
  
  # Update task status
  withLock(executor.taskLock):
    executor.tasks[taskId].status = tsRunning
    executor.tasks[taskId].startedAt = some(startTime)
    executor.runningTasks.incl(taskId)
  
  # Execute the task
  var result: TaskResult
  result.taskId = taskId
  result.startTime = startTime
  
  try:
    let taskResult = task.taskProc()
    result.endTime = now()
    result.duration = (result.endTime - result.startTime).inSeconds.float
    
    if taskResult.isOk:
      result.status = tsCompleted
      result.output = taskResult.get()
    else:
      result.status = tsFailed
      result.error = taskResult.error.msg
  except CatchableError as e:
    result.endTime = now()
    result.duration = (result.endTime - result.startTime).inSeconds.float
    result.status = tsFailed
    result.error = e.msg
  
  # Update task info with result
  withLock(executor.taskLock):
    executor.tasks[taskId].status = result.status
    executor.tasks[taskId].completedAt = some(result.endTime)
    executor.tasks[taskId].result = some(result)
    executor.runningTasks.excl(taskId)
    
    case result.status
    of tsCompleted:
      executor.completedTasks.incl(taskId)
      withLock(executor.statsLock):
        inc executor.stats.tasksCompleted
    of tsFailed:
      executor.failedTasks.incl(taskId)
      withLock(executor.statsLock):
        inc executor.stats.tasksFailed
    else:
      discard

# Executor control
proc start*(executor: ParallelExecutor) =
  ## Start the executor
  if executor.isRunning:
    return
  
  executor.isRunning = true
  executor.stopRequested = false
  executor.logger.info("Executor started", %*{
    "workers": executor.config.workerCount,
    "queue_size": executor.config.queueSize
  })

proc stop*(executor: ParallelExecutor) =
  ## Stop the executor
  executor.stopRequested = true
  executor.isRunning = false
  executor.logger.info("Executor stopped")

proc isRunning*(executor: ParallelExecutor): bool =
  ## Check if executor is running
  executor.isRunning

# Main scheduler loop
proc schedule*(executor: ParallelExecutor) =
  ## Run one scheduling iteration
  if not executor.isRunning:
    return
  
  # Get ready tasks
  let readyTasks = executor.resolveDependencies()
  
  # Queue ready tasks
  withLock(executor.queueLock):
    for taskId in readyTasks:
      if executor.taskQueue.len < executor.config.queueSize:
        executor.taskQueue.addLast(taskId)
        withLock(executor.taskLock):
          executor.tasks[taskId].attempt += 1
  
  # Spawn worker threads for queued tasks
  while true:
    var taskId: TaskId
    var hasTask = false
    
    withLock(executor.queueLock):
      if executor.taskQueue.len > 0:
        taskId = executor.taskQueue.popFirst()
        hasTask = true
    
    if not hasTask:
      break
    
    # Check worker limit
    withLock(executor.taskLock):
      if executor.runningTasks.len >= executor.config.workerCount:
        # Put task back in queue
        withLock(executor.queueLock):
          executor.taskQueue.addFirst(taskId)
        break
    
    # Spawn worker thread
    spawn executeTask(executor, taskId)

proc runUntilComplete*(executor: ParallelExecutor): ExecutorStats =
  ## Run executor until all tasks are complete
  executor.start()
  let startTime = epochTime()
  
  while executor.isRunning and not executor.stopRequested:
    executor.schedule()
    
    # Check if all tasks are complete
    var allComplete = true
    withLock(executor.taskLock):
      for taskId, task in executor.tasks:
        if task.status in {tsPending, tsRunning}:
          allComplete = false
          break
    
    if allComplete:
      break
    
    # Sleep briefly to avoid busy waiting
    sleep(int(executor.config.schedulingInterval * 1000))
  
  executor.stop()
  
  # Calculate final stats
  withLock(executor.statsLock):
    executor.stats.totalDuration = epochTime() - startTime
    if executor.stats.tasksCompleted > 0:
      executor.stats.avgTaskDuration = executor.stats.totalDuration / executor.stats.tasksCompleted.float
  
  executor.stats

# Utility functions
proc getTaskStatus*(executor: ParallelExecutor, taskId: TaskId): Result[TaskStatus, ref ParallelError] =
  ## Get the status of a task
  var statusResult: Result[TaskStatus, ref ParallelError]
  
  withLock(executor.taskLock):
    if taskId notin executor.tasks:
      statusResult = Result[TaskStatus, ref ParallelError].err(
        newParallelError(fmt"Task {taskId} not found"))
    else:
      statusResult = Result[TaskStatus, ref ParallelError].ok(executor.tasks[taskId].status)
  
  return statusResult

proc getTaskResult*(executor: ParallelExecutor, taskId: TaskId): Result[TaskResult, ref ParallelError] =
  ## Get the result of a task
  var taskResult: Result[TaskResult, ref ParallelError]
  
  withLock(executor.taskLock):
    if taskId notin executor.tasks:
      taskResult = Result[TaskResult, ref ParallelError].err(
        newParallelError(fmt"Task {taskId} not found"))
    else:
      let task = executor.tasks[taskId]
      if task.result.isNone:
        taskResult = Result[TaskResult, ref ParallelError].err(
          newParallelError(fmt"Task {taskId} has no result yet"))
      else:
        taskResult = Result[TaskResult, ref ParallelError].ok(task.result.get())
  
  return taskResult

proc getStats*(executor: ParallelExecutor): ExecutorStats =
  ## Get current statistics
  withLock(executor.statsLock):
    result = executor.stats
    
    # Calculate current load
    withLock(executor.taskLock):
      result.currentLoad = executor.runningTasks.len.float / executor.config.workerCount.float

# Convenience functions for simple use cases
proc runParallel*(tasks: seq[tuple[id: string, taskProc: TaskProc]], config = defaultExecutorConfig()): seq[TaskResult] =
  ## Run tasks in parallel and return results
  let executor = newParallelExecutor(config)
  
  # Add all tasks
  for task in tasks:
    let spec = newTaskSpec(task.id)
    discard executor.addTask(spec, task.taskProc)
  
  # Run until complete
  discard executor.runUntilComplete()
  
  # Collect results
  result = @[]
  for task in tasks:
    let taskResult = executor.getTaskResult(TaskId(task.id))
    if taskResult.isOk:
      result.add(taskResult.get())