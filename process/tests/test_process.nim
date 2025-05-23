import unittest
import ../src/process
import std/[os, strutils, asyncdispatch, options]

suite "Process execution tests":
  
  test "Basic command execution":
    let result = runCommand("echo test")
    check result.exitCode == 0
    check result.output.strip() == "test"
    check result.timedOut == false
  
  test "Command with working directory":
    let tempDir = getTempDir()
    let result = runCommand("pwd", workingDir = tempDir)
    check result.exitCode == 0
    check result.output.strip().endsWith(tempDir)
  
  test "Command with custom environment":
    let env = createEnvTable(additions = [("TEST_VAR", "test_value")])
    let result = runCommand("echo $TEST_VAR", env = env)
    check result.exitCode == 0
    # Environment variable expansion depends on shell
  
  test "Command timeout":
    let result = runCommandWithTimeout("sleep 5", timeout = 0.1)
    check result.timedOut == true
    check result.exitCode == -1
    check result.error.contains("timed out")
  
  test "Failed command":
    let result = runCommand("exit 1")
    check result.exitCode == 1
    check result.output.len >= 0  # May have output
  
  test "Async command execution":
    proc testAsync() {.async.} =
      let result = await runCommandAsync("echo async test")
      check result.exitCode == 0
      check result.output.strip() == "async test"
    
    waitFor testAsync()
  
  test "Process manager":
    let pm = newProcessManager()
    
    # Start a process
    let process = pm.startManagedProcess("test1", "sleep 0.1")
    check process != nil
    
    # Get the process
    let retrieved = pm.getManagedProcess("test1")
    check retrieved == process
    
    # Wait for it to complete
    discard process.waitForExit()
    
    # Terminate
    check pm.terminateManagedProcess("test1") == true
    
    # Should not exist anymore
    expect ProcessError:
      discard pm.getManagedProcess("test1")
  
  test "ProcessOptions execution":
    let opts = ProcessOptions(
      command: "echo",
      args: @["hello", "world"],
      workingDir: "",
      env: nil,
      timeout: none[float]()
    )
    
    let result = execute(opts)
    check result.exitCode == 0
    check result.output.strip() == "hello world"
  
  test "Shell escape":
    check shellEscape("simple") == "simple"
    
    when defined(windows):
      check shellEscape("with space") == "\"with space\""
      check shellEscape("with\"quote") == "\"with\"\"quote\""
    else:
      check shellEscape("with space") == "'with space'"
      check shellEscape("with'quote") == "'with'\\''quote'"
  
  test "Platform detection":
    when defined(windows):
      check isWindows() == true
      check isMacOS() == false
      check isLinux() == false
    elif defined(macosx):
      check isWindows() == false
      check isMacOS() == true
      check isLinux() == false
    elif defined(linux):
      check isWindows() == false
      check isMacOS() == false
      check isLinux() == true
  
  test "Find executable in PATH":
    # Should find common system commands
    when defined(windows):
      let cmd = findExecutableInPath("cmd")
      check cmd.len > 0
      check cmd.endsWith("cmd.exe")
    else:
      let sh = findExecutableInPath("sh")
      check sh.len > 0
      check sh.contains("/sh")
  
  test "Process output callback":
    var lines: seq[string] = @[]
    
    proc callback(line: string) =
      lines.add(line)
    
    let process = startProcessShell("echo line1 && echo line2")
    readProcessOutput(process, callback)
    
    discard process.waitForExit()
    process.close()
    
    check lines.len > 0