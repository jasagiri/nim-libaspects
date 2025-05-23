import unittest
import ../src/nim_libaspects
import std/[json, strutils]

suite "IntegrationTests":
  test "All modules compile together":
    # Test that all imports work
    discard newLogger("test")
    discard newConfig()
    discard newStdioTransport()
    discard newParallelExecutor()
    discard newProcessBuilder("echo")
    
    check true
    
  test "Modules can work together":
    # Create logger
    let logger = newLogger("Integration")
    logger.addHandler(newConsoleHandler())
    logger.setLevel(lvlInfo)
    
    # Log something
    logger.info("Integration test starting")
    
    # Create config
    let config = newConfig()
    config.setDefault("workers", 2)
    check config.getInt("workers") == 2
    
    # Test error handling
    let result = Result[int, string].err("test error")
    check result.isErr
    check result.error == "test error"
    
    # Test parallel execution
    proc testTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].ok("Integration test task")
    
    let executor = newParallelExecutor()
    let spec = newTaskSpec("integration-task")
    discard executor.addTask(spec, testTask)
    
    let stats = executor.runUntilComplete()
    check stats.tasksCompleted == 1
    
    # Transport test (simplified)
    let transport = newStdioTransport()
    check transport.state == csDisconnected
    
    # Process test
    let processResult = exec("echo", @["Integration test"])
    check processResult.isOk
    check processResult.get().exitCode == 0
    check processResult.get().output.strip() == "Integration test"
    
    logger.info("Integration test completed")
    
  test "Cross module integration":
    # Config + Logging
    let config = newConfig()
    config.setDefault("log_level", "info")
    
    let logger = newLogger("CrossModule")
    let handler = newConsoleHandler()
    
    # Configure logger from config  
    let levelStr = config.getString("log_level")
    case levelStr
    of "debug": logger.setLevel(lvlDebug)
    of "info": logger.setLevel(lvlInfo)
    of "warn": logger.setLevel(lvlWarn)
    of "error": logger.setLevel(lvlError)
    else: logger.setLevel(lvlInfo)
    
    logger.addHandler(handler)
    
    # Use logger in error handling
    let errorResult = capture proc(): string =
      raise newException(ValueError, "Test exception")
    
    if errorResult.isErr:
      logger.error("Captured error", %*{
        "error": $errorResult.error.msg,
        "type": $errorResult.error.name
      })
    
    # Parallel + Errors
    proc errorTask(): Result[string, ref AppError] {.thread.} =
      Result[string, ref AppError].err(newAppError(ecInternalError, "Intentional error"))
    
    let executor = newParallelExecutor()
    let spec = newTaskSpec("error-task")
    discard executor.addTask(spec, errorTask)
    
    let stats = executor.runUntilComplete()
    check stats.tasksFailed == 1
    
    logger.info("Cross-module integration test completed")