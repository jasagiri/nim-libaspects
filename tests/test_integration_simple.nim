## test_integration_simple.nim
## =========================
##
## Simple integration tests for nim-libs modules

import ../src/nim_libaspects
import std/[json, strutils, os]

# Test all modules compile together
block importTest:
  # Test that all imports work
  discard newLogger("test")
  discard newConfig()
  discard newStdioTransport()
  discard newParallelExecutor()
  discard newProcessBuilder("echo")
  doAssert true
  echo "✓ All modules compile together"

# Test modules work together
block moduleInteraction:
  # Create logger
  let logger = newLogger("Integration")
  logger.addHandler(newConsoleHandler())
  logger.setLevel(lvlInfo)
  
  # Log something
  logger.info("Integration test starting")
  
  # Create config
  let config = newConfig()
  config.setDefault("workers", 2)
  doAssert config.getInt("workers") == 2
  
  # Test error handling
  let result = Result[int, string].err("test error")
  doAssert result.isErr
  doAssert result.error == "test error"
  
  # Test parallel execution
  var taskCompleted = false
  proc testTask(): Result[string, ref AppError] {.thread, gcsafe.} =
    taskCompleted = true
    Result[string, ref AppError].ok("test completed")
  
  let executor = newParallelExecutor()
  let spec = newTaskSpec("integration-task", "Test task")
  discard executor.addTask(spec, testTask)
  
  executor.start()
  discard executor.runUntilComplete()
  executor.stop()
  
  doAssert taskCompleted
  
  # Transport test (simplified)
  let transport = newStdioTransport()
  doAssert transport.state == csDisconnected
  
  # Process test
  let processResult = exec("echo", @["Integration test"])
  doAssert processResult.isOk
  doAssert processResult.get().exitCode == 0
  doAssert processResult.get().output.strip() == "Integration test"
  
  logger.info("Integration test completed")
  echo "✓ Modules can work together"

# Test cross-module integration
block crossModule:
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
  var errorTaskRan = false
  proc errorTask(): Result[string, ref AppError] {.thread, gcsafe.} =
    errorTaskRan = true
    Result[string, ref AppError].err(newAppError(ecInternalError, "Intentional error"))
  
  let executor = newParallelExecutor()
  let spec = newTaskSpec("error-task", "Error test task")
  discard executor.addTask(spec, errorTask)
  
  executor.start()
  let stats = executor.runUntilComplete()
  executor.stop()
  
  doAssert errorTaskRan
  doAssert stats.tasksFailed == 1
  
  logger.info("Cross-module integration test completed")
  echo "✓ Cross-module integration works"

# Test testing module integration
block testingModule:
  # Use our own testing assertions
  check(true, "This should pass")
  expect(42, 42)
  
  var raised = false
  try:
    expectError(ValueError):
      raise newException(ValueError, "Expected error")
    raised = false
  except PowerAssertError:
    raised = true
  doAssert not raised
  
  echo "✓ Testing module integration works"

# Config with environment variables
block configEnv:
  let config = newConfig(envPrefix = "NIMLIBS_")
  
  # Set an environment variable
  putEnv("NIMLIBS_TEST_VAR", "test_value")
  
  discard config.loadEnv()
  doAssert config.getString("test_var") == "test_value"
  
  # Clean up
  putEnv("NIMLIBS_TEST_VAR", "")
  echo "✓ Config with environment works"

# Process builder with config
block processBuilder:
  let config = newConfig()
  config.setDefault("echo.message", "Hello from builder")
  
  var builder = newProcessBuilder("echo")
  discard builder.args(config.getString("echo.message"))
  let result = builder.run()
  
  doAssert result.isOk
  if result.isOk:
    doAssert config.getString("echo.message") in result.get().output
  echo "✓ Process builder with config works"

echo "\nAll integration tests passed!"