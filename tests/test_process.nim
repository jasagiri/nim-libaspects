import unittest
import ../src/nim_libaspects/[process, errors]
import std/[os, strformat, strutils]

suite "Process Module Tests":
  
  test "Platform detection":
    # At least one platform should be detected
    check isLinux or isMacOS or isWindows or isBSD
    check isPosix == (not isWindows)
  
  test "Shell detection":
    let shell = getShell()
    check shell.len > 0
    when isWindows:
      check shell.endsWith(".exe") or shell.endsWith("cmd")
    else:
      check shell.startsWith("/") or shell == "sh" or shell == "bash"
  
  test "Shell argument escaping":
    let arg1 = "simple"
    let arg2 = "with space"
    let arg3 = "with'quote"
    let arg4 = "with\"doublequote"
    
    let escaped1 = escapeShellArg(arg1)
    let escaped2 = escapeShellArg(arg2)
    let escaped3 = escapeShellArg(arg3)
    let escaped4 = escapeShellArg(arg4)
    
    when isWindows:
      check escaped1 == "simple"
      check escaped2 == "\"with space\""
      check escaped3 == "with'quote"
      check escaped4 == "\"with\\\"doublequote\""
    else:
      check escaped1 == "'simple'"
      check escaped2 == "'with space'"
      check escaped3 == "'with'\"'\"'quote'"
      check escaped4 == "'with\"doublequote'"
  
  test "Shell command escaping":
    let cmd = "echo"
    let args = @["hello", "world with spaces"]
    let escaped = escapeShellCommand(cmd, args)
    
    check escaped.contains("echo")
    check escaped.contains("hello")
    check escaped.contains("world with spaces")
  
  test "Find executable":
    # Test finding common executables
    when isWindows:
      let notepad = findExecutable("notepad")
      check notepad.isSome
    else:
      let ls = findExecutable("ls")
      check ls.isSome
      let nonExistent = findExecutable("definitely_not_a_real_command_xyz123")
      check nonExistent.isNone
  
  test "Simple process execution":
    let options = ProcessOptions(
      command: "echo",
      args: @["Hello, Process!"],
      captureOutput: true
    )
    
    let result = runProcess(options)
    check result.isOk
    
    let processResult = result.get()
    check processResult.exitCode == 0
    check processResult.status == psCompleted
    check processResult.output.strip() == "Hello, Process!"
  
  test "Process with error":
    let options = ProcessOptions(
      command: "false",  # Unix command that always fails
      captureOutput: true
    )
    
    when not isWindows:
      let result = runProcess(options)
      check result.isOk
      
      let processResult = result.get()
      check processResult.exitCode != 0
      check processResult.status == psFailed
  
  test "Process with timeout":
    when not isWindows:
      let options = ProcessOptions(
        command: "sleep",
        args: @["10"],  # Sleep for 10 seconds
        timeout: 100,   # But timeout after 100ms
        captureOutput: true
      )
      
      let result = runProcess(options)
      check result.isOk
      
      let processResult = result.get()
      check processResult.status == psTimeout
      check processResult.exitCode == -1
  
  test "Process builder pattern":
    var builder = newProcessBuilder("echo")
    discard builder.args("Using", "builder", "pattern")
      .captureOutput(true)
      .timeout(5000)
    
    let result = builder.run()
    
    check result.isOk
    let processResult = result.get()
    check processResult.exitCode == 0
    check processResult.output.strip() == "Using builder pattern"
  
  test "Shell command execution":
    let result = execShell("echo 'Shell execution works'")
    check result.isOk
    
    let processResult = result.get()
    check processResult.exitCode == 0
    check processResult.output.strip() == "Shell execution works"
  
  test "Which command":
    let echo = which("echo")
    check echo.isSome
    
    let nonExistent = which("definitely_not_a_command_xyz")
    check nonExistent.isNone
  
  test "Process manager creation":
    let manager = newProcessManager()
    check manager != nil
  
  test "Process manager start and get":
    let manager = newProcessManager()
    
    let options = ProcessOptions(
      command: "echo",
      args: @["Process manager test"],
      captureOutput: true
    )
    
    let idResult = manager.start(options)
    check idResult.isOk
    
    let processId = idResult.get()
    check processId.len > 0
    
    let handle = manager.get(processId)
    check handle.isSome
    check handle.get().command == "echo"
    check handle.get().args == @["Process manager test"]
  
  test "Process manager running check":
    let manager = newProcessManager()
    
    when not isWindows:
      let options = ProcessOptions(
        command: "sleep",
        args: @["0.1"]  # Sleep for 100ms
      )
      
      let idResult = manager.start(options, "test-process")
      check idResult.isOk
      
      # Should be running initially
      check manager.running("test-process")
      
      # Wait a bit and check again
      sleep(200)
      check not manager.running("test-process")
  
  test "Process manager terminate":
    let manager = newProcessManager()
    
    when not isWindows:
      let options = ProcessOptions(
        command: "sleep",
        args: @["10"]  # Long-running process
      )
      
      let idResult = manager.start(options, "terminate-test")
      check idResult.isOk
      
      # Should be running
      check manager.running("terminate-test")
      
      # Terminate it
      let terminateResult = manager.terminate("terminate-test")
      check terminateResult.isOk
      
      # Should no longer be running
      check not manager.running("terminate-test")
  
  test "Process manager terminate all":
    let manager = newProcessManager()
    
    # Start multiple processes
    for i in 1..3:
      let options = ProcessOptions(
        command: "echo",
        args: @[fmt"Process {i}"]
      )
      let idResult = manager.start(options)
      check idResult.isOk
    
    # Terminate all
    manager.terminateAll()
    
    # All should be gone
    for i in 1..3:
      check not manager.running(fmt"process-{i}")
  
  test "Working directory":
    let tempDir = getTempDir()
    let options = ProcessOptions(
      command: "pwd",
      workingDir: tempDir,
      captureOutput: true
    )
    
    when not isWindows:
      let result = runProcess(options)
      check result.isOk
      
      let processResult = result.get()
      check processResult.exitCode == 0
      # The output should be the temp directory path
      check processResult.output.strip().startsWith("/")
  
  test "Environment variables":
    var env = newStringTable()
    env["TEST_VAR"] = "test_value"
    
    when not isWindows:
      let options = ProcessOptions(
        command: "sh",
        args: @["-c", "echo $TEST_VAR"],
        env: env,
        captureOutput: true
      )
    else:
      let options = ProcessOptions(
        command: "cmd",
        args: @["/c", "echo %TEST_VAR%"],
        env: env,
        captureOutput: true
      )
    
    let result = runProcess(options)
    check result.isOk
    
    let processResult = result.get()
    check processResult.exitCode == 0
    check processResult.output.strip() == "test_value"
  
  test "Complex shell command":
    when not isWindows:
      let result = execShell("echo 'First' && echo 'Second'")
      check result.isOk
      
      let processResult = result.get()
      check processResult.exitCode == 0
      check "First" in processResult.output
      check "Second" in processResult.output
  
  test "Process IDs":
    let options = ProcessOptions(
      command: "echo",
      args: @["PID test"],
      captureOutput: true
    )
    
    let result = runProcess(options)
    check result.isOk
    
    let processResult = result.get()
    check processResult.pid > 0
  
  test "Invalid command":
    let options = ProcessOptions(
      command: "definitely_not_a_real_command_xyz123",
      captureOutput: true
    )
    
    let result = runProcess(options)
    check result.isErr  # Should fail to run non-existent command
  
  test "Builder with all options":
    var env = newStringTable()
    env["BUILDER_TEST"] = "value"
    
    var builder = newProcessBuilder("echo")
    discard builder.args("Complete", "builder", "test")
      .workingDir(getTempDir())
      .env(env)
      .timeout(5000)
      .captureOutput(true)
      .streamOutput(false)
      .shell(false)
    
    let result = builder.run()
    
    check result.isOk
    let processResult = result.get()
    check processResult.exitCode == 0
    check processResult.output.strip() == "Complete builder test"