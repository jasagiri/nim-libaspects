## Process management module for nim-libs
## Provides unified process spawning, monitoring, and communication

import std/[os, osproc, strutils, tables, strtabs, streams, options, asyncdispatch, times, json, oids, strformat, locks]
when not defined(windows):
  import posix
import ./errors
import ./logging

# Export commonly used types
export osproc, streams, options, strtabs

type
  ProcessError* = object of AppError
    ## Error type for process operations
  
  ProcessStatus* = enum
    ## Process status
    psRunning = "running"
    psCompleted = "completed"
    psFailed = "failed"
    psTerminated = "terminated"
    psTimeout = "timeout"
  
  ProcessResult* = object
    ## Result of process execution
    output*: string
    error*: string
    exitCode*: int
    status*: ProcessStatus
    pid*: int
  
  ProcessOptions* = object
    ## Options for process execution
    command*: string
    args*: seq[string]
    workingDir*: string
    env*: StringTableRef
    timeout*: int  # milliseconds, 0 = no timeout
    captureOutput*: bool
    streamOutput*: bool
    showWindow*: bool  # Windows only
    shell*: bool       # Execute through shell
  
  ProcessHandle* = object
    ## Handle to a running process
    process*: Process
    id*: string
    command*: string
    args*: seq[string]
    startTime*: DateTime
    options*: ProcessOptions
  
  ProcessManager* = ref object
    ## Manager for multiple processes
    processes: Table[string, ProcessHandle]
    logger: Logger
    processLock: Lock

# Platform detection
const
  isLinux* = defined(linux)
  isMacOS* = defined(macosx)
  isWindows* = defined(windows)
  isBSD* = defined(freebsd) or defined(openbsd) or defined(netbsd)
  isPosix* = not isWindows

# Error constructors
proc newProcessError*(msg: string): ref ProcessError =
  result = newException(ProcessError, msg)
  result.context = newErrorContext(ecInternalError, msg)

# Platform-specific utilities
proc getShell*(): string =
  ## Get the system shell
  when isWindows:
    getEnv("COMSPEC", "cmd.exe")
  else:
    getEnv("SHELL", "/bin/sh")

proc escapeShellArg*(s: string): string =
  ## Escape argument for shell execution
  when isWindows:
    if s.contains(' ') or s.contains('\t'):
      "\"" & s.replace("\"", "\\\"") & "\""
    else:
      s
  else:
    "'" & s.replace("'", "'\"'\"'") & "'"

proc escapeShellCommand*(cmd: string, args: seq[string]): string =
  ## Create escaped shell command
  result = escapeShellArg(cmd)
  for arg in args:
    result.add(" ")
    result.add(escapeShellArg(arg))

proc findExecutable*(name: string): Option[string] =
  ## Find executable in PATH
  let paths = getEnv("PATH").split(PathSep)
  for path in paths:
    let fullPath = path / name
    if fileExists(fullPath) and fpUserExec in getFilePermissions(fullPath):
      return some(fullPath)
    # Check with common extensions on Windows
    when isWindows:
      for ext in [".exe", ".bat", ".cmd"]:
        let withExt = fullPath & ext
        if fileExists(withExt):
          return some(withExt)
  none(string)

# Process creation
proc createProcess*(options: ProcessOptions): Process =
  ## Create a new process
  var processOptions = {poUsePath}
  
  if options.captureOutput:
    processOptions.incl(poStdErrToStdOut)
  
  if options.shell:
    when isWindows:
      processOptions.incl(poShellExecute)
    else:
      # On Unix, we need to manually invoke shell
      let shellCmd = escapeShellCommand(options.command, options.args)
      return startProcess(
        command = getShell(),
        args = @["-c", shellCmd],
        workingDir = options.workingDir,
        env = options.env,
        options = processOptions
      )
  
  startProcess(
    command = options.command,
    args = options.args,
    workingDir = options.workingDir,
    env = options.env,
    options = processOptions
  )

# Synchronous process execution
proc runProcess*(options: ProcessOptions): Result[ProcessResult, ref ProcessError] =
  ## Run a process synchronously
  var processResult = ProcessResult(
    pid: 0,
    status: psRunning
  )
  
  try:
    let process = createProcess(options)
    processResult.pid = process.processID()
    
    # Handle timeout
    if options.timeout > 0:
      var elapsed = 0
      let checkInterval = 100  # Check every 100ms
      
      while process.running() and elapsed < options.timeout:
        sleep(checkInterval)
        elapsed += checkInterval
      
      if process.running():
        process.terminate()
        processResult.status = psTimeout
        processResult.exitCode = -1
        return Result[ProcessResult, ref ProcessError].ok(processResult)
    
    # Capture output if requested
    if options.captureOutput:
      # Read output stream
      let outputStream = process.outputStream()
      processResult.output = outputStream.readAll()
      processResult.exitCode = process.waitForExit()
    else:
      processResult.exitCode = process.waitForExit()
    
    # Stream output if requested
    if options.streamOutput and not options.captureOutput:
      let outputStream = process.outputStream()
      while not outputStream.atEnd():
        let line = outputStream.readLine()
        echo line
        processResult.output.add(line & "\n")
    
    # Determine status
    processResult.status = if processResult.exitCode == 0: psCompleted else: psFailed
    
    Result[ProcessResult, ref ProcessError].ok(processResult)
  except OSError as e:
    Result[ProcessResult, ref ProcessError].err(
      newProcessError(fmt"Failed to run process: {e.msg}"))
  except Exception as e:
    Result[ProcessResult, ref ProcessError].err(
      newProcessError(fmt"Unexpected error: {e.msg}"))

# Asynchronous process execution
proc runProcessAsync*(options: ProcessOptions): Future[Result[ProcessResult, ref ProcessError]] {.async.} =
  ## Run a process asynchronously
  # For now, we'll use a simple implementation
  # In production, this would use proper async process handling
  return runProcess(options)

# Process builder pattern
type ProcessBuilder* = object
  options: ProcessOptions

proc newProcessBuilder*(command: string): ProcessBuilder =
  ## Create a new process builder
  ProcessBuilder(
    options: ProcessOptions(
      command: command,
      args: @[],
      workingDir: "",
      env: nil,
      timeout: 0,
      captureOutput: true,
      streamOutput: false,
      showWindow: true,
      shell: false
    )
  )

proc args*(builder: var ProcessBuilder, args: varargs[string]): var ProcessBuilder =
  ## Add arguments
  builder.options.args = @args
  builder

proc workingDir*(builder: var ProcessBuilder, dir: string): var ProcessBuilder =
  ## Set working directory
  builder.options.workingDir = dir
  builder

proc env*(builder: var ProcessBuilder, env: StringTableRef): var ProcessBuilder =
  ## Set environment variables
  builder.options.env = env
  builder

proc timeout*(builder: var ProcessBuilder, ms: int): var ProcessBuilder =
  ## Set timeout in milliseconds
  builder.options.timeout = ms
  builder

proc captureOutput*(builder: var ProcessBuilder, capture = true): var ProcessBuilder =
  ## Enable/disable output capture
  builder.options.captureOutput = capture
  builder

proc streamOutput*(builder: var ProcessBuilder, stream = true): var ProcessBuilder =
  ## Enable/disable output streaming
  builder.options.streamOutput = stream
  builder

proc shell*(builder: var ProcessBuilder, useShell = true): var ProcessBuilder =
  ## Execute through system shell
  builder.options.shell = useShell
  builder

proc run*(builder: ProcessBuilder): Result[ProcessResult, ref ProcessError] =
  ## Execute the process
  runProcess(builder.options)

proc runAsync*(builder: ProcessBuilder): Future[Result[ProcessResult, ref ProcessError]] =
  ## Execute the process asynchronously
  runProcessAsync(builder.options)

# Process manager
proc newProcessManager*(logger: Logger = nil): ProcessManager =
  ## Create a new process manager
  result = ProcessManager(
    processes: initTable[string, ProcessHandle](),
    logger: if logger != nil: logger else: newLogger("ProcessManager")
  )
  initLock(result.processLock)

proc generateProcessId(): string =
  ## Generate unique process ID
  $genOid()

proc start*(manager: ProcessManager, options: ProcessOptions, id = ""): Result[string, ref ProcessError] =
  ## Start a process and track it
  let processId = if id.len > 0: id else: generateProcessId()
  var startResult: Result[string, ref ProcessError]
  
  withLock(manager.processLock):
    if processId in manager.processes:
      startResult = Result[string, ref ProcessError].err(
        newProcessError(fmt"Process with ID {processId} already exists"))
    else:
      try:
        let process = createProcess(options)
        let handle = ProcessHandle(
          process: process,
          id: processId,
          command: options.command,
          args: options.args,
          startTime: now(),
          options: options
        )
        
        manager.processes[processId] = handle
        manager.logger.info("Started process", %*{
          "id": processId,
          "command": options.command,
          "pid": process.processID()
        })
        
        startResult = Result[string, ref ProcessError].ok(processId)
      except Exception as e:
        startResult = Result[string, ref ProcessError].err(
          newProcessError(fmt"Failed to start process: {e.msg}"))
  
  return startResult

proc get*(manager: ProcessManager, id: string): Option[ProcessHandle] =
  ## Get a process by ID
  var getResult: Option[ProcessHandle]
  
  withLock(manager.processLock):
    if id in manager.processes:
      getResult = some(manager.processes[id])
    else:
      getResult = none(ProcessHandle)
  
  return getResult

proc running*(manager: ProcessManager, id: string): bool =
  ## Check if process is running
  var isRunning: bool = false
  
  withLock(manager.processLock):
    if id in manager.processes:
      isRunning = manager.processes[id].process.running()
  
  return isRunning

proc terminate*(manager: ProcessManager, id: string): Result[void, ref ProcessError] =
  ## Terminate a process
  var terminateResult: Result[void, ref ProcessError]
  
  withLock(manager.processLock):
    if id notin manager.processes:
      terminateResult = Result[void, ref ProcessError].err(
        newProcessError(fmt"Process {id} not found"))
    else:
      try:
        let handle = manager.processes[id]
        handle.process.terminate()
        manager.processes.del(id)
        
        manager.logger.info("Terminated process", %*{
          "id": id,
          "command": handle.command
        })
        
        terminateResult = Result[void, ref ProcessError].ok()
      except Exception as e:
        terminateResult = Result[void, ref ProcessError].err(
          newProcessError(fmt"Failed to terminate process: {e.msg}"))
  
  return terminateResult

proc terminateAll*(manager: ProcessManager) =
  ## Terminate all processes
  withLock(manager.processLock):
    for id, handle in manager.processes:
      try:
        handle.process.terminate()
        manager.logger.info("Terminated process", %*{
          "id": id,
          "command": handle.command
        })
      except Exception as e:
        manager.logger.error("Failed to terminate process", %*{
          "id": id,
          "error": e.msg
        })
    manager.processes.clear()

# Convenience functions
proc exec*(command: string, args: seq[string] = @[]): Result[ProcessResult, ref ProcessError] =
  ## Execute a command and return result
  let options = ProcessOptions(
    command: command,
    args: args,
    captureOutput: true
  )
  runProcess(options)

proc execShell*(command: string): Result[ProcessResult, ref ProcessError] =
  ## Execute a shell command
  let options = ProcessOptions(
    command: getShell(),
    args: @["-c", command],
    shell: false,  # We're manually invoking the shell
    captureOutput: true
  )
  runProcess(options)

proc which*(command: string): Option[string] =
  ## Find command in PATH
  findExecutable(command)

# Process monitoring
proc monitorProcess*(handle: ProcessHandle, callback: proc(status: ProcessStatus) {.gcsafe.}) {.thread.} =
  ## Monitor a process and call callback on status change
  while handle.process.running():
    sleep(100)
  
  let exitCode = handle.process.waitForExit()
  let status = if exitCode == 0: psCompleted else: psFailed
  callback(status)

# Signal handling (Unix only)
when isPosix:
  proc sendSignal*(process: Process, signal: cint): bool =
    ## Send signal to process (Unix only)
    try:
      discard posix.kill(Pid(process.processID()), signal)
      true
    except:
      false
  
  proc sendSignal*(handle: ProcessHandle, signal: cint): bool =
    ## Send signal to process handle
    sendSignal(handle.process, signal)