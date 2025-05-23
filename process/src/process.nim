## process.nim - Common process management utilities
## 
## This module provides platform-independent process management utilities
## extracted from niuv, nibuild, and nim-debug-adapter for reuse across projects.

import std/[os, osproc, strutils, tables, json, options, asyncdispatch]

export osproc, options

type
  ProcessManager* = ref object
    ## Process manager for handling multiple processes
    processes: Table[string, Process]
    
  ProcessOptions* = object
    ## Options for process execution
    command*: string
    args*: seq[string]
    workingDir*: string
    env*: StringTableRef
    timeout*: Option[float]
    captureOutput*: bool
    options*: set[ProcessOption]
    
  ProcessResult* = object
    ## Result of process execution
    exitCode*: int
    output*: string
    error*: string
    timedOut*: bool
    
  ProcessError* = object of CatchableError
    ## Error type for process-related issues
    
  TimeoutError* = object of ProcessError
    ## Error type for process timeout

# Platform utilities from niuv/src/utils/shell.nim
proc isWindows*(): bool =
  ## Check if running on Windows
  when defined(windows):
    return true
  else:
    return false

proc isMacOS*(): bool =
  ## Check if running on macOS
  when defined(macosx):
    return true
  else:
    return false

proc isLinux*(): bool =
  ## Check if running on Linux
  when defined(linux):
    return true
  else:
    return false

proc getPlatformShellCommand*(): tuple[shell: string, flag: string] =
  ## Get platform-specific shell command and flag
  when defined(windows):
    return (getEnv("COMSPEC", "cmd.exe"), "/c")
  else:
    return (getEnv("SHELL", "/bin/sh"), "-c")

proc shellEscape*(s: string): string =
  ## Escape string for safe shell usage
  when defined(windows):
    if s.contains(" ") or s.contains("\"") or s.contains("&") or s.contains("|") or s.contains("<") or s.contains(">"):
      return "\"" & s.replace("\"", "\"\"") & "\""
    return s
  else:
    if s.contains("'"):
      return "'" & s.replace("'", "'\\''") & "'"
    elif s.contains(" ") or s.contains("\"") or s.contains("$") or s.contains("`") or s.contains("\\"):
      return "'" & s & "'"
    return s

# Core process execution functions
proc runCommand*(cmd: string, workingDir = "", env: StringTableRef = nil): ProcessResult =
  ## Run a command and return the result
  ## This is a simplified version of niuv's runCommand and runCommandWithEnv
  var options: set[ProcessOption] = {poUsePath, poStdErrToStdOut}
  
  # Save and restore working directory if specified
  var oldDir = ""
  if workingDir.len > 0:
    oldDir = getCurrentDir()
    try:
      setCurrentDir(workingDir)
    except OSError as e:
      raise newException(ProcessError, "Failed to change directory to " & workingDir & ": " & e.msg)
  
  defer:
    if oldDir.len > 0:
      try:
        setCurrentDir(oldDir)
      except OSError:
        discard
  
  try:
    let (output, exitCode) = execCmdEx(cmd, options = options, env = env)
    return ProcessResult(
      exitCode: exitCode,
      output: output,
      error: if exitCode != 0: output else: "",
      timedOut: false
    )
  except OSError as e:
    raise newException(ProcessError, "Failed to execute command: " & e.msg)

proc startProcessShell*(cmd: string, workingDir = "", env: StringTableRef = nil,
                       options: set[ProcessOption] = {poUsePath}): Process =
  ## Start a process using the system shell
  ## Based on niuv's execProcessEnv
  let (shell, flag) = getPlatformShellCommand()
  let fullCmd = shell & " " & flag & " " & shellEscape(cmd)
  
  return startProcess(fullCmd, workingDir = workingDir, env = env, options = options)

proc runCommandAsync*(cmd: string, workingDir = "", env: StringTableRef = nil): Future[ProcessResult] {.async.} =
  ## Run a command asynchronously
  var process: Process
  var result: ProcessResult
  
  try:
    process = startProcessShell(cmd, workingDir, env, {poUsePath, poStdErrToStdOut})
    
    # Wait for process to complete
    while process.running():
      await sleepAsync(10)
    
    result.exitCode = process.waitForExit()
    
    # Read output if available
    if process.outputStream != nil:
      result.output = process.outputStream.readAll()
    
    result.timedOut = false
    
  except Exception as e:
    result.exitCode = -1
    result.error = e.msg
    result.timedOut = false
  finally:
    if process != nil:
      process.close()
  
  return result

proc runCommandWithTimeout*(cmd: string, timeout: float, workingDir = "", 
                          env: StringTableRef = nil): ProcessResult =
  ## Run a command with a timeout (in seconds)
  ## Based on niuv's parallel execution timeout handling
  var process: Process
  var result: ProcessResult
  
  try:
    process = startProcessShell(cmd, workingDir, env, {poUsePath, poStdErrToStdOut})
    
    let startTime = epochTime()
    
    # Monitor process with timeout
    while process.running():
      if epochTime() - startTime > timeout:
        process.terminate()
        result.timedOut = true
        result.exitCode = -1
        result.error = "Process timed out after " & $timeout & " seconds"
        break
      
      sleep(10)  # Sleep 10ms to avoid CPU spin
    
    if not result.timedOut:
      result.exitCode = process.waitForExit()
      
      # Read output if available
      if process.outputStream != nil:
        result.output = process.outputStream.readAll()
    
  except Exception as e:
    result.exitCode = -1
    result.error = e.msg
    result.timedOut = false
  finally:
    if process != nil:
      process.close()
  
  return result

# Process manager functions
proc newProcessManager*(): ProcessManager =
  ## Create a new process manager
  ProcessManager(processes: initTable[string, Process]())

proc startManagedProcess*(pm: ProcessManager, id: string, cmd: string, 
                        workingDir = "", env: StringTableRef = nil,
                        options: set[ProcessOption] = {poUsePath}): Process =
  ## Start a managed process with the given ID
  if id in pm.processes:
    raise newException(ProcessError, "Process with ID '" & id & "' already exists")
  
  let process = startProcessShell(cmd, workingDir, env, options)
  pm.processes[id] = process
  return process

proc getManagedProcess*(pm: ProcessManager, id: string): Process =
  ## Get a managed process by ID
  if id notin pm.processes:
    raise newException(ProcessError, "Process with ID '" & id & "' not found")
  return pm.processes[id]

proc terminateManagedProcess*(pm: ProcessManager, id: string): bool =
  ## Terminate a managed process
  if id notin pm.processes:
    return false
  
  let process = pm.processes[id]
  try:
    process.terminate()
    process.close()
    pm.processes.del(id)
    return true
  except:
    return false

proc terminateAllProcesses*(pm: ProcessManager) =
  ## Terminate all managed processes
  for id, process in pm.processes:
    try:
      process.terminate()
      process.close()
    except:
      discard
  pm.processes.clear()

# Utility functions
proc findExecutableInPath*(executable: string): string =
  ## Find an executable in the system PATH
  ## From niuv's shell utilities
  result = ""
  
  # Add platform-specific extension
  var exeName = executable
  when defined(windows):
    if not exeName.endsWith(".exe"):
      exeName &= ".exe"
  
  # Check if full path was given
  if fileExists(exeName):
    return absolutePath(exeName)
  
  # Search in PATH
  let path = getEnv("PATH")
  let pathSep = when defined(windows): ';' else: ':'
  
  for dir in path.split(pathSep):
    let fullPath = dir / exeName
    if fileExists(fullPath):
      return fullPath
  
  return result  # Empty string if not found

proc createEnvTable*(baseEnv: StringTableRef = nil, 
                    additions: openArray[(string, string)] = []): StringTableRef =
  ## Create an environment table with additional variables
  ## Useful for process execution with custom environment
  var env = if baseEnv != nil: baseEnv else: newStringTable()
  
  # Add new variables
  for (key, val) in additions:
    env[key] = val
  
  return env

# High-level convenience functions
proc execute*(opts: ProcessOptions): ProcessResult =
  ## Execute a process with the given options
  var cmdLine = opts.command
  if opts.args.len > 0:
    cmdLine &= " " & opts.args.join(" ")
  
  if opts.timeout.isSome:
    return runCommandWithTimeout(cmdLine, opts.timeout.get, opts.workingDir, opts.env)
  else:
    return runCommand(cmdLine, opts.workingDir, opts.env)

proc executeAsync*(opts: ProcessOptions): Future[ProcessResult] {.async.} =
  ## Execute a process asynchronously with the given options
  var cmdLine = opts.command
  if opts.args.len > 0:
    cmdLine &= " " & opts.args.join(" ")
  
  # TODO: Add timeout support for async execution
  return await runCommandAsync(cmdLine, opts.workingDir, opts.env)

# Process output streaming (inspired by nim-debug-adapter)
proc readProcessOutput*(process: Process, callback: proc(line: string)) =
  ## Read process output line by line and call callback
  if process.outputStream != nil:
    var line: string
    while process.outputStream.readLine(line):
      callback(line)

proc readProcessOutputAsync*(process: Process, callback: proc(line: string) {.async.}): Future[void] {.async.} =
  ## Read process output asynchronously
  if process.outputStream != nil:
    var line: string
    while not process.outputStream.atEnd:
      if process.outputStream.readLine(line):
        await callback(line)
      await sleepAsync(1)

# Export commonly used types and functions
export Process, ProcessOption, startProcess, waitForExit, running, terminate, close